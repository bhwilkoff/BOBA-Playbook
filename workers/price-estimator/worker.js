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

// Rarity-first comparability (PRICING_PLAYBOOK.md §6.2). For BoBA, price
// tracks RARITY — not hero. The old hero=0.6 weighting was backwards.
// Comparables are now ranked tightest-rarity-class first (treatment-family +
// weapon + power-tier + type, then identical serialized print run, then
// looser treatment groupings); hero is the weakest, last-resort axis.
// computeEstimate uses the tightest class with enough priced comps and takes
// the MEDIAN (robust to the wild asking-price outliers eBay returns) — no
// weighted-sum of arbitrary axis weights (the "guess" §6.3 warns against;
// real per-feature weights get learned from comps once the dataset exists).

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
  // Axes ordered tightest (most price-comparable) → loosest. Rarity drives
  // price, so the rarity class leads and hero is the last resort.
  const result = {
    rarity_class:     [],   // treatment-family + weapon + power-tier + cardType
    serial:           [],   // identical serialized print run (hard scarcity peer)
    treatment_weapon: [],   // treatment-family + weapon (cross power-tier)
    treatment:        [],   // treatment-family (cross weapon/power)
    hero:             [],   // same hero — secondary signal only
  };
  const tHero  = (target.hero || "").toLowerCase();
  const tPower = powerTier(target.power);
  const tEl    = target.element;
  const tFam   = treatmentFamily(target.treatment);
  const tType  = target.cardType;
  const tPrint = target.printRun;

  for (const c of catalog) {
    if (!c.bobaId || c.bobaId === target.bobaId) continue;
    const cFam   = treatmentFamily(c.treatment);
    const cPower = powerTier(c.power);

    if (tEl && c.element === tEl && tFam && cFam === tFam &&
        tPower && cPower === tPower && tType && c.cardType === tType) {
      result.rarity_class.push(c.bobaId);
    }
    // Serialized cards of the SAME print run track each other strongly
    // regardless of hero (a /5 sells like other /5s). printRun is the
    // hardest scarcity signal we have (Feature 0, §6.4).
    if (tPrint && c.printRun === tPrint) {
      result.serial.push(c.bobaId);
    }
    if (tEl && c.element === tEl && tFam && cFam === tFam) {
      result.treatment_weapon.push(c.bobaId);
    }
    if (tFam && cFam === tFam) {
      result.treatment.push(c.bobaId);
    }
    if (tHero && (c.hero || "").toLowerCase() === tHero) {
      result.hero.push(c.bobaId);
    }
  }
  // Cap each axis to keep the /comps fan-out bounded.
  for (const k of Object.keys(result)) {
    if (result[k].length > 30) result[k] = result[k].slice(0, 30);
  }
  return result;
}

/**
 * For a list of bobaIds, fetch real inferred-sold comp prices from the Tier 1
 * tracker (boba-pricing-tracker `/comps`). Returns a map bobaId → median sold
 * price, skipping cards with no inferred-sold data yet. Replaces the dead
 * eBay-Marketplace-Insights sold path (PRICING_PLAYBOOK.md §0, §6.1) — the
 * estimator now stands on comps we generate ourselves.
 */
async function fetchCompPrices(bobaIds, env) {
  const prices = new Map();
  const CONCURRENCY = 6;
  let i = 0;
  async function worker() {
    while (i < bobaIds.length) {
      const id = bobaIds[i++];
      try {
        // Service-binding fetch — direct runtime route, no edge round-trip.
        const req = new Request(`https://internal/comps?bobaId=${encodeURIComponent(id)}&days=90`);
        const res = await env.PRICING_TRACKER_SVC.fetch(req);
        if (!res.ok) continue;
        const data = await res.json();
        const median = data?.summary?.median ?? 0;
        if (median > 0) prices.set(id, median);
      } catch {
        // Single-card failure must not break the cron — skip silently.
      }
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  return prices;
}

/**
 * Rarity-first estimate (PRICING_PLAYBOOK.md §6.2). Walk the comparability
 * axes tightest → loosest and use the FIRST axis that has enough priced comps;
 * the estimate is the MEDIAN of that axis's comps (robust to the wild outliers
 * eBay returns). Returns null when no axis has a single priced comp — honest:
 * a card with zero comparable sold data gets NO fabricated estimate (Tier 5
 * "Listed Range" covers that case). Real per-feature weighting is learned once
 * the comp dataset grows (§6.3).
 */
function computeEstimate(comparables, priceMap) {
  // Tightest → loosest. Hero is last (a weak signal, not a price driver).
  const order = ["rarity_class", "serial", "treatment_weapon", "treatment", "hero"];
  const priceFor = ids => ids.map(id => priceMap.get(id)).filter(p => p > 0).sort((a, b) => a - b);

  // Prefer the tightest axis with >= CONFIDENCE_MED priced comps; else the
  // tightest axis with any priced comp at all.
  let tag = null, priced = null;
  for (const t of order) {
    const p = priceFor(comparables[t] || []);
    if (p.length >= CONFIDENCE_MED) { tag = t; priced = p; break; }
  }
  if (!priced) {
    for (const t of order) {
      const p = priceFor(comparables[t] || []);
      if (p.length >= 1) { tag = t; priced = p; break; }
    }
  }
  if (!priced) return null;

  const median = priced[(priced.length - 1) >> 1];

  // Confidence: a tight rarity class with many comps is high; a single loose
  // comp is low; hero-only is always low (weakest axis).
  let confidence = "low";
  if (tag !== "hero" && priced.length >= CONFIDENCE_HIGH) confidence = "high";
  else if (priced.length >= CONFIDENCE_MED) confidence = "med";

  return {
    low:               Math.round(priced[0]                  * 100) / 100,
    mid:               Math.round(median                     * 100) / 100,
    high:              Math.round(priced[priced.length - 1]  * 100) / 100,
    comparableCount:   priced.length,
    comparableSources: [tag],
    confidence,
    method:            "rarity_comparability",
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
async function refreshAllEstimates(env, budgetOverride) {
  const catalogRes = await fetch(env.CATALOG_URL);
  if (!catalogRes.ok) {
    console.error("Catalog fetch failed:", catalogRes.status);
    return { processed: 0, written: 0, error: "catalog_fetch_failed" };
  }
  const catalog = await catalogRes.json();
  const cardsWithBobaId = catalog.filter(c => c.bobaId);
  const budget = budgetOverride ?? parseInt(env.PER_CRON_BUDGET || "600", 10);
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
    const existing = await env.ESTIMATES.get(`estimate:v2:${target.bobaId}`);
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
      ...comparables.rarity_class,
      ...comparables.serial,
      ...comparables.treatment_weapon,
      ...comparables.treatment,
      ...comparables.hero,
    ]));
    if (allCompIds.length === 0) continue;
    const prices = await fetchCompPrices(allCompIds, env);
    const estimate = computeEstimate(comparables, prices);
    if (!estimate) continue;
    const entry = {
      bobaId:    target.bobaId,
      ...estimate,
      computedAt: new Date().toISOString(),
    };
    await env.ESTIMATES.put(
      `estimate:v2:${target.bobaId}`,
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
  const raw = await env.ESTIMATES.get(`estimate:v2:${bobaId}`);
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
      // Manual `?budget=N` lets HTTP /refresh stay within the 30s CPU
      // cap. Without it, full PER_CRON_BUDGET runs hit "Exceeded CPU
      // Limit" on the HTTP path while still working fine via cron
      // (which has a 15-min budget).
      const budgetParam = url.searchParams.get("budget");
      const budgetOverride = budgetParam ? Math.max(1, parseInt(budgetParam, 10)) : undefined;
      const result = await refreshAllEstimates(env, budgetOverride);
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
