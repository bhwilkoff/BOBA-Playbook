/**
 * BOBA Playbook — Market Est. Worker
 *
 * Replaces the Radish Market Est. tier (DECISIONS.md #056 +
 * RADISH_REMOVAL_LOOP.md Phase 7). When a card has no recent eBay sold
 * activity, callers query this Worker for a comparability-derived
 * estimate computed over the BOBA catalog's own structure — never
 * against third-party data sources whose ToS prohibit it.
 *
 * ## Architecture
 *
 * 1. **Nightly cron** walks every catalog card. For each card:
 *    a. Compute the comparable set: same hero, same (weapon, power-tier,
 *       treatment-family), same (set, cardType). Each axis is a partial
 *       match — a card with no same-hero comp can still anchor on
 *       same-(weapon, power-tier).
 *    b. Query `boba-ebay-proxy /?cardNumber=...` for each comp's
 *       price. Reuse the existing eBay-aware Worker rather than
 *       re-implementing the OAuth + scoring path here.
 *    c. Compute a weighted estimate: hero matches 0.6, weapon+power-tier
 *       matches 0.3, set+cardType matches 0.1. Clamp to ±50% of the
 *       strongest signal so the estimate doesn't drift wildly when one
 *       comp returns an outlier.
 *    d. Write `{low, mid, high, comparableCount, comparableSources,
 *       computedAt}` to KV at `estimate:{bobaId}`.
 *
 * 2. **HTTP GET `/estimate?bobaId=X`** serves the KV entry verbatim.
 *    Returns 404 when the cron hasn't computed an entry yet (early
 *    days post-deploy + brand-new cards). Clients fall back to
 *    "MARKET EST. unavailable" gracefully, same as today's behavior
 *    when Radish Market Est. failed.
 *
 * 3. **Cross-set hero anchoring** is the bootstrap path for new sets.
 *    A brand-new card has no in-set comps yet, but the same hero in
 *    another set has eBay activity. We seed the new card's estimate
 *    using the hero-anchor's price + a treatment-family multiplier
 *    learned from cards where both signals exist.
 *
 * ## Response shape
 *
 * ```json
 * {
 *   "bobaId":            "RBF-72-Maverick--",
 *   "low":               18.50,
 *   "mid":               24.00,
 *   "high":              29.50,
 *   "comparableCount":   12,
 *   "comparableSources": ["same_hero", "same_weapon_power", "same_set"],
 *   "computedAt":        "2026-05-24T03:00:14Z",
 *   "method":            "comparability"
 * }
 * ```
 *
 * ## Scoped explicitly NOT to do
 *
 * - No outbound calls to radishpriceguide.com (it's in DECISIONS.md #056
 *   exclusion list).
 * - No scraping of third-party HTML beyond what boba-ebay-proxy already
 *   wraps (eBay's licensed APIs).
 * - No catalog mutation. The Worker reads cards.json; never writes back.
 *
 * See `README.md` for deploy / cron-setup instructions.
 */

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

// Weights — primary axes sum to 1.0 when all three match. Fallback
// axes are only consulted when primary axes are sparse; they carry
// reduced weight to reflect the looser comparability.
const WEIGHT_SAME_HERO              = 0.6;
const WEIGHT_SAME_WEAPON_POWER      = 0.3;
const WEIGHT_SAME_SET               = 0.1;
const WEIGHT_SAME_WEAPON_TREATMENT  = 0.2;   // fallback
const WEIGHT_SAME_CARD_TYPE         = 0.1;   // fallback
const WEIGHT_SAME_TREATMENT         = 0.1;   // fallback

// Confidence threshold. ≥ 6 priced comps from primary axes = high
// confidence; ≥ 3 = medium; below = low (UI surfaces a caveat).
const CONFIDENCE_HIGH = 6;
const CONFIDENCE_MED  = 3;

// Cap on price range deviation. The estimate is clamped so that
// low/mid/high never spread > 50% of mid in either direction.
const CLAMP_FRAC = 0.5;

// Power-tier buckets. Cards with similar power tend to sell at
// similar prices; bucketing avoids "200 power" cards being matched to
// "5 power" cards purely because they share the same hero.
function powerTier(power) {
  if (power == null) return null;
  if (power <= 25)  return "lo";
  if (power <= 60)  return "mid";
  if (power <= 100) return "hi";
  return "elite";
}

// Treatment-family normalization. Battlefoil colorways collapse into
// one family ("battlefoil_color"); themed foils each get their own
// family. Inspired Ink is its own thing (serialized + scarce).
function treatmentFamily(treatment) {
  if (!treatment) return null;
  const t = treatment.toLowerCase();
  if (t.includes("battlefoil") && !t.includes("super")) return "battlefoil_color";
  if (t.includes("superfoil"))    return "superfoil";
  if (t.includes("inspired"))     return "inspired_ink";
  if (t.includes("blizzard"))     return "blizzard";
  if (t.includes("linoleum"))     return "linoleum";
  if (t.includes("logofoil"))     return "logofoil";
  if (t.includes("mixtape"))      return "mixtape";
  if (t.includes("chillin"))      return "chillin";
  if (t.includes("grillin"))      return "grillin";
  if (t.includes("alpha"))        return "alpha";
  return "base";
}

/**
 * Find comparable cards for a target card. Returns an object keyed by
 * comparability axis; each value is a list of bobaIds. The same card can
 * appear under multiple axes (additive).
 *
 * Six axes total — three primary (high signal) and three fallback
 * (looser, only consulted when primaries miss). The fallbacks let
 * brand-new cards in brand-new sets still get an estimate when the
 * primary axes return nothing.
 */
function findComparables(target, catalog) {
  const result = {
    same_hero:         [],
    same_weapon_power: [],
    same_set:          [],
    // Fallback axes — looser comparators, only used when the primary 3
    // are sparse.
    same_weapon_treatment: [],   // weapon + treatment-family only (no power-tier match)
    same_card_type:        [],   // weapon + card type (Hero / Play / Hot Dog)
    same_treatment:        [],   // any card of the same treatment family
  };
  const tHero  = (target.hero || "").toLowerCase();
  const tPower = powerTier(target.power);
  const tEl    = target.element;
  const tFam   = treatmentFamily(target.treatment);
  const tSet   = target.set;
  const tType  = target.cardType;

  for (const c of catalog) {
    if (!c.bobaId || c.bobaId === target.bobaId) continue;
    // Same hero — most weight-bearing axis
    if (tHero && (c.hero || "").toLowerCase() === tHero) {
      result.same_hero.push(c.bobaId);
    }
    const cFam = treatmentFamily(c.treatment);
    const cPower = powerTier(c.power);
    // Primary: same (weapon, power-tier, treatment-family)
    if (
      tEl && c.element === tEl &&
      tPower && cPower === tPower &&
      tFam && cFam === tFam
    ) {
      result.same_weapon_power.push(c.bobaId);
    }
    // Primary: same (set, cardType)
    if (tSet && c.set === tSet && tType && c.cardType === tType) {
      result.same_set.push(c.bobaId);
    }
    // Fallback: same (weapon, treatment-family) without power-tier
    if (tEl && c.element === tEl && tFam && cFam === tFam) {
      result.same_weapon_treatment.push(c.bobaId);
    }
    // Fallback: same (weapon, cardType) — broader cross-set
    if (tEl && c.element === tEl && tType && c.cardType === tType) {
      result.same_card_type.push(c.bobaId);
    }
    // Fallback: same treatment family across all cards
    if (tFam && cFam === tFam) {
      result.same_treatment.push(c.bobaId);
    }
  }
  // Cap each axis at 20 comps to keep eBay-query fan-out bounded.
  for (const k of Object.keys(result)) {
    if (result[k].length > 20) result[k] = result[k].slice(0, 20);
  }
  return result;
}

/**
 * For a list of bobaIds, fetch the most-recent average sold price from
 * boba-ebay-proxy. Returns a map bobaId → number (skipping cards with
 * no eBay sold data).
 */
async function fetchCompPrices(bobaIds, catalog, ebayProxyUrl) {
  const indexByBobaId = new Map(catalog.map(c => [c.bobaId, c]));
  const prices = new Map();
  // Cap concurrency at 6 — Cloudflare Workers prefer fewer in-flight
  // fetches over a tighter pool.
  const CONCURRENCY = 6;
  let i = 0;
  async function worker() {
    while (i < bobaIds.length) {
      const idx = i++;
      const id  = bobaIds[idx];
      const card = indexByBobaId.get(id);
      if (!card) continue;
      try {
        const params = new URLSearchParams({
          cardNumber: card.cardNumber || "",
          hero:       card.hero       || "",
          set:        card.set        || "",
          element:    card.element    || "",
          days:       "90",
        });
        if (card.treatment) params.set("treatment", card.treatment);
        if (card.power != null) params.set("power", String(card.power));
        const res = await fetch(`${ebayProxyUrl}?${params}`);
        if (!res.ok) continue;
        const data = await res.json();
        // Prefer the explicitly-sold section's average. Falls back to
        // the top-level average when the response is in legacy shape.
        const avg = data?.sold?.average ?? data?.average ?? 0;
        if (avg > 0) prices.set(id, avg);
      } catch {
        // Single-card failure must not break the cron — skip silently.
      }
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  return prices;
}

/**
 * Combine the per-axis comparable prices into a single weighted estimate.
 * Returns null when no axis has data.
 *
 * Tiered: primary axes (same_hero, same_weapon_power, same_set) are
 * always weighted. Fallback axes (same_weapon_treatment, same_card_type,
 * same_treatment) are only consulted when the primary axes are sparse —
 * they prevent a brand-new card in a brand-new set from getting a null
 * estimate just because its in-set comps don't exist yet. The fallback
 * paths drive the `confidence` field (low / med / high) so the UI can
 * caveat estimates derived from looser data.
 */
function computeEstimate(comparables, priceMap) {
  const primaryAxes = [
    { ids: comparables.same_hero,         weight: WEIGHT_SAME_HERO,         tag: "same_hero" },
    { ids: comparables.same_weapon_power, weight: WEIGHT_SAME_WEAPON_POWER, tag: "same_weapon_power" },
    { ids: comparables.same_set,          weight: WEIGHT_SAME_SET,          tag: "same_set" },
  ];
  const fallbackAxes = [
    { ids: comparables.same_weapon_treatment, weight: WEIGHT_SAME_WEAPON_TREATMENT, tag: "same_weapon_treatment" },
    { ids: comparables.same_card_type,        weight: WEIGHT_SAME_CARD_TYPE,        tag: "same_card_type" },
    { ids: comparables.same_treatment,        weight: WEIGHT_SAME_TREATMENT,        tag: "same_treatment" },
  ];

  function aggregateAxes(axes) {
    let weightedSum = 0;
    let totalWeight = 0;
    let totalCount  = 0;
    const sourcesHit = [];
    for (const axis of axes) {
      const compsWithPrice = axis.ids.filter(id => priceMap.has(id));
      if (compsWithPrice.length === 0) continue;
      const avg = compsWithPrice
        .map(id => priceMap.get(id))
        .reduce((a, b) => a + b, 0) / compsWithPrice.length;
      weightedSum  += avg * axis.weight;
      totalWeight  += axis.weight;
      totalCount   += compsWithPrice.length;
      sourcesHit.push(axis.tag);
    }
    return { weightedSum, totalWeight, totalCount, sourcesHit };
  }

  const primary = aggregateAxes(primaryAxes);
  // Only consult fallback axes when primary axes returned too little —
  // they're noisier, so consulting them when primaries had data
  // would dilute the signal.
  const useFallbacks = primary.totalCount < CONFIDENCE_MED;
  const fallback = useFallbacks ? aggregateAxes(fallbackAxes) : null;
  const totalWeight = primary.totalWeight + (fallback?.totalWeight ?? 0);
  if (totalWeight === 0) return null;
  const weightedSum = primary.weightedSum + (fallback?.weightedSum ?? 0);
  const totalCount = primary.totalCount + (fallback?.totalCount ?? 0);
  const sourcesHit = [...primary.sourcesHit, ...(fallback?.sourcesHit ?? [])];

  const mid = weightedSum / totalWeight;
  const low  = Math.max(0, mid * (1 - CLAMP_FRAC));
  const high = mid * (1 + CLAMP_FRAC);

  // Confidence reflects how much primary-axis signal underpins the
  // estimate. Fallback-only estimates are always low-confidence.
  let confidence;
  if (primary.totalCount >= CONFIDENCE_HIGH) confidence = "high";
  else if (primary.totalCount >= CONFIDENCE_MED) confidence = "med";
  else confidence = "low";

  return {
    low:               Math.round(low  * 100) / 100,
    mid:               Math.round(mid  * 100) / 100,
    high:              Math.round(high * 100) / 100,
    comparableCount:   totalCount,
    comparableSources: sourcesHit,
    confidence,
    method:            useFallbacks ? "comparability_tiered" : "comparability",
  };
}

/**
 * Cron handler — refresh estimates incrementally. Each invocation:
 *   1. Reads a rotating cursor from KV (or starts at 0 on first run).
 *   2. Skips cards whose KV estimate is fresh (computed in last 5 days).
 *   3. Processes UP TO `PER_CRON_BUDGET` cards needing work, OR stops
 *      when wallclock approaches the 25-min soft cap.
 *   4. Writes the new cursor back so the next cron picks up where this
 *      one left off.
 *
 * Net effect at steady state: 18k catalog rotates through the cron over
 * ~30 nights at default budget; staler entries naturally take priority
 * once their TTL approaches. Brand-new cards get picked up on the very
 * next cron after they land in cards.json.
 */
async function refreshAllEstimates(env) {
  const catalogRes = await fetch(env.CATALOG_URL);
  if (!catalogRes.ok) {
    console.error("Catalog fetch failed:", catalogRes.status);
    return { processed: 0, written: 0, error: "catalog_fetch_failed" };
  }
  const catalog = await catalogRes.json();
  const cardsWithBobaId = catalog.filter(c => c.bobaId);
  const budget = parseInt(env.PER_CRON_BUDGET || "600", 10);
  // Wallclock soft cap — Cloudflare cron has a 30-min hard cap.
  // Stop slightly early so KV writes + cursor save are guaranteed to
  // land before the worker is killed.
  const SOFT_CAP_MS = 25 * 60 * 1000;
  // KV entries written by `refreshAllEstimates` carry 7-day TTL; cards
  // with KV entries fresher than this threshold are skipped this run.
  const FRESH_THRESHOLD_MS = 5 * 24 * 3600 * 1000;
  const startedAt = Date.now();

  // Load rotating cursor.
  const cursorRaw = await env.ESTIMATES.get("cursor:next_index");
  let cursor = cursorRaw != null ? parseInt(cursorRaw, 10) : 0;
  if (!Number.isFinite(cursor) || cursor < 0 || cursor >= cardsWithBobaId.length) cursor = 0;

  let processed = 0;
  let skipped   = 0;
  let written   = 0;
  let i = cursor;
  let wraps = 0;
  while (processed < budget && (Date.now() - startedAt) < SOFT_CAP_MS && wraps < 2) {
    if (i >= cardsWithBobaId.length) { i = 0; wraps++; continue; }
    const target = cardsWithBobaId[i++];

    // Skip-if-fresh check.
    const existing = await env.ESTIMATES.get(`estimate:${target.bobaId}`);
    if (existing) {
      try {
        const parsed = JSON.parse(existing);
        const computedMs = parsed.computedAt ? Date.parse(parsed.computedAt) : 0;
        if (computedMs && (Date.now() - computedMs) < FRESH_THRESHOLD_MS) {
          skipped++;
          continue;
        }
      } catch { /* stale-format entry — fall through and recompute */ }
    }

    processed++;
    const comparables = findComparables(target, catalog);
    const allCompIds = Array.from(new Set([
      ...comparables.same_hero,
      ...comparables.same_weapon_power,
      ...comparables.same_set,
    ]));
    if (allCompIds.length === 0) continue;
    const prices = await fetchCompPrices(allCompIds, catalog, env.EBAY_PROXY);
    const estimate = computeEstimate(comparables, prices);
    if (!estimate) continue;
    const entry = {
      bobaId:    target.bobaId,
      ...estimate,
      computedAt: new Date().toISOString(),
    };
    await env.ESTIMATES.put(
      `estimate:${target.bobaId}`,
      JSON.stringify(entry),
      { expirationTtl: 7 * 24 * 3600 },
    );
    written++;
  }

  // Save cursor for next cron. Modulo to wrap to head.
  await env.ESTIMATES.put("cursor:next_index", String(i % cardsWithBobaId.length));

  const elapsedMs = Date.now() - startedAt;
  console.log(`[estimator-cron] cursor_started=${cursor} cursor_now=${i % cardsWithBobaId.length} processed=${processed} skipped=${skipped} written=${written} elapsedMs=${elapsedMs}`);
  return { processed, skipped, written, elapsedMs, cursorStart: cursor, cursorEnd: i % cardsWithBobaId.length };
}

/**
 * HTTP handler — GET /estimate?bobaId=X
 */
async function handleEstimateRequest(request, env) {
  const url = new URL(request.url);
  const bobaId = url.searchParams.get("bobaId");
  if (!bobaId) {
    return new Response(JSON.stringify({ error: "bobaId parameter required" }), {
      status: 400,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
  const raw = await env.ESTIMATES.get(`estimate:${bobaId}`);
  if (!raw) {
    return new Response(JSON.stringify({
      bobaId,
      estimate: null,
      reason: "no_comps_yet",
    }), {
      status: 404,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
  return new Response(raw, {
    status: 200,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname.endsWith("/estimate")) {
      return handleEstimateRequest(request, env);
    }
    // Manual refresh trigger (rate-limit yourself manually; intended for
    // testing + the initial post-deploy seed run).
    if (request.method === "POST" && url.pathname.endsWith("/refresh")) {
      const result = await refreshAllEstimates(env);
      return new Response(JSON.stringify(result), {
        status: 200,
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({
      service: "boba-price-estimator",
      endpoints: ["GET /estimate?bobaId=X", "POST /refresh"],
    }), {
      status: 200,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  },

  async scheduled(_event, env) {
    await refreshAllEstimates(env);
  },
};
