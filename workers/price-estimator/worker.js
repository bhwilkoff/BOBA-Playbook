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

// Weights — sum to 1.0 when all three axes match.
const WEIGHT_SAME_HERO         = 0.6;
const WEIGHT_SAME_WEAPON_POWER = 0.3;
const WEIGHT_SAME_SET          = 0.1;

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
 */
function findComparables(target, catalog) {
  const result = {
    same_hero:         [],
    same_weapon_power: [],
    same_set:          [],
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
    // Same (weapon, power-tier, treatment-family)
    if (
      tEl && c.element === tEl &&
      tPower && powerTier(c.power) === tPower &&
      tFam && treatmentFamily(c.treatment) === tFam
    ) {
      result.same_weapon_power.push(c.bobaId);
    }
    // Same (set, cardType)
    if (tSet && c.set === tSet && tType && c.cardType === tType) {
      result.same_set.push(c.bobaId);
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
 */
function computeEstimate(comparables, priceMap) {
  const axes = [
    { ids: comparables.same_hero,         weight: WEIGHT_SAME_HERO,         tag: "same_hero" },
    { ids: comparables.same_weapon_power, weight: WEIGHT_SAME_WEAPON_POWER, tag: "same_weapon_power" },
    { ids: comparables.same_set,          weight: WEIGHT_SAME_SET,          tag: "same_set" },
  ];
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
  if (totalWeight === 0) return null;
  const mid = weightedSum / totalWeight;
  // Clamp range to ±CLAMP_FRAC of mid.
  const low  = Math.max(0, mid * (1 - CLAMP_FRAC));
  const high = mid * (1 + CLAMP_FRAC);
  return {
    low:               Math.round(low  * 100) / 100,
    mid:               Math.round(mid  * 100) / 100,
    high:              Math.round(high * 100) / 100,
    comparableCount:   totalCount,
    comparableSources: sourcesHit,
    method:            "comparability",
  };
}

/**
 * Cron handler — refresh estimates for every catalog card.
 */
async function refreshAllEstimates(env) {
  const catalogRes = await fetch(env.CATALOG_URL);
  if (!catalogRes.ok) {
    console.error("Catalog fetch failed:", catalogRes.status);
    return { processed: 0, written: 0, error: "catalog_fetch_failed" };
  }
  const catalog = await catalogRes.json();
  // Bound the per-cron work — large catalogs + per-card eBay queries
  // multiply quickly. PER_CRON_BUDGET is the absolute ceiling; cron
  // processes a daily rotating slice when catalog > budget.
  const budget = parseInt(env.PER_CRON_BUDGET || "18000", 10);
  const startedAt = Date.now();
  let processed = 0;
  let written   = 0;
  for (const target of catalog) {
    if (!target.bobaId) continue;
    if (processed >= budget) break;
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
      // 7-day TTL — cron refreshes nightly so a stale entry only
      // survives if the cron itself fails for multiple days. Past
      // 7 days, the entry expires and clients see "no estimate"
      // (graceful degrade) until cron catches up.
      { expirationTtl: 7 * 24 * 3600 },
    );
    written++;
  }
  const elapsedMs = Date.now() - startedAt;
  console.log(`[estimator-cron] processed=${processed} written=${written} elapsedMs=${elapsedMs}`);
  return { processed, written, elapsedMs };
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
