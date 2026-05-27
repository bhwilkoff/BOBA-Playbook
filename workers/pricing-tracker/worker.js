/**
 * boba-pricing-tracker — Tier 1 of the Pricing Playbook (PRICING_PLAYBOOK.md §3).
 *
 * Generates our OWN sold-history from public eBay Browse listings over time,
 * since eBay Marketplace Insights (sold comps) is permanently unavailable to
 * us. Every cadence: snapshot active listings per card into D1; when a listing
 * vanishes from a later snapshot, infer "sold @ last-seen price" with a
 * confidence score. After ~60 days we own a sold-history dataset.
 *
 * STATUS: read endpoint (`GET /comps`) is live and complete. The snapshot
 * loop is implemented but GATED — it requires the eBay-proxy to expose the
 * FULL active-listing set + stable item ids (today the proxy returns only the
 * top ~10 of N, with {title,price,date,url}; inferring sold from a truncated
 * list yields false positives). See README §"two-part build". Cron stays off
 * (wrangler.toml) until that endpoint lands and a manual run is validated.
 */

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", "access-control-allow-origin": "*" },
  });

const nowIso = () => new Date().toISOString();

// Parse the eBay legacy item id from a listing URL (/itm/157840157677?...).
function itemIdFromUrl(url) {
  const m = /\/itm\/(\d{6,})/.exec(url || "");
  return m ? m[1] : null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/comps") return await handleComps(url, env);
      if (url.pathname === "/snapshot" && request.method === "POST")
        return await handleSnapshot(url, env);
      if (url.pathname === "/" || url.pathname === "")
        return json({
          service: "boba-pricing-tracker",
          doc: "PRICING_PLAYBOOK.md §3",
          endpoints: ["GET /comps?bobaId=X&days=90", "POST /snapshot?budget=N (gated)"],
        });
      return json({ error: "not found" }, 404);
    } catch (e) {
      return json({ error: String(e && e.message || e) }, 500);
    }
  },

  // Cron entry (disabled in wrangler.toml until validated).
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(runSnapshot(env, Number(env.PER_RUN_BUDGET || 600)));
  },
};

/**
 * GET /comps?bobaId=X&days=90 — inferred-sold "Recent Sales" for one card.
 * Only rows with sold_confidence >= FLOOR surface (§3.4). Returns the §3.5
 * shape. Works today; returns an empty comp set until the snapshot populates.
 */
async function handleComps(url, env) {
  const bobaId = url.searchParams.get("bobaId");
  if (!bobaId) return json({ error: "bobaId required" }, 400);
  const days = Math.min(365, Math.max(1, parseInt(url.searchParams.get("days") || "90", 10)));
  const since = new Date(Date.now() - days * 86400e3).toISOString();
  const FLOOR = 0.55; // sold-confidence threshold (§3.4)

  const { results } = await env.DB.prepare(
    `SELECT sold_price_usd AS price, vanished_at AS soldAt, sold_confidence AS confidence,
            format, item_id AS itemId, image_url AS imageUrl
       FROM listings
      WHERE boba_id = ? AND inferred_sold = 1 AND sold_confidence >= ? AND vanished_at >= ?
      ORDER BY vanished_at DESC
      LIMIT 50`
  ).bind(bobaId, FLOOR, since).all();

  const comps = (results || []).filter(c => c.price > 0);
  const prices = comps.map(c => c.price).sort((a, b) => a - b);
  const summary = prices.length
    ? { low: prices[0], median: prices[(prices.length - 1) >> 1], high: prices[prices.length - 1], count: prices.length }
    : { low: 0, median: 0, high: 0, count: 0 };
  return json({ bobaId, comps, summary, windowDays: days, source: "inferred_sold" });
}

/** POST /snapshot?budget=N — manual trigger (same path as cron). */
async function handleSnapshot(url, env) {
  const budget = Math.max(1, parseInt(url.searchParams.get("budget") || env.PER_RUN_BUDGET || "50", 10));
  const stats = await runSnapshot(env, budget);
  return json(stats);
}

/**
 * One snapshot run: poll a rotating slice of the catalog, upsert each active
 * listing into `listings`, then run vanish-detection over rows we haven't
 * seen recently. Cursor in KV so a run fits inside Cloudflare's wallclock.
 *
 * GATED: `activeListingsFor` needs the eBay-proxy's FULL active set + item
 * ids. Until that endpoint exists it returns [] and the run is a safe no-op
 * (records the run, infers nothing). See README §"two-part build".
 */
async function runSnapshot(env, budget) {
  const started = nowIso();
  let cardsPolled = 0, listingsSeen = 0;
  let err = null;

  // Safety: the tracker shares eBay's 5,000/day Browse quota with LIVE user
  // pricing. Never starve it — skip this run if Browse remaining is below the
  // floor (per-run budget + margin), so live pricing always wins.
  const SAFETY_FLOOR = Number(env.BROWSE_SAFETY_FLOOR || 1500);
  try {
    const rl = await env.EBAY_PROXY_SVC.fetch(new Request("https://internal/tracker/ratelimit"));
    const browse = ((await rl.json().catch(() => ({}))).summary || {})["Browse/buy.browse"];
    const remaining = browse ? Number(browse.remaining) : null;
    if (remaining != null && remaining < SAFETY_FLOOR) {
      await recordRun(env, started, 0, 0, 0, `skipped: Browse remaining ${remaining} < floor ${SAFETY_FLOOR}`);
      return { started, skipped: true, browseRemaining: remaining };
    }
  } catch { /* quota check failed — proceed; small budget + per-card try/catch bound the risk */ }

  try {
    const catalog = await (await fetch(env.CATALOG_URL, { cf: { cacheTtl: 3600 } })).json();
    const tracked = catalog.filter(c => c.imageFile && c.cardType !== "Sealed Product");
    const start = Number((await env.CURSOR.get("cursor:tracker:next_index")) || 0) % tracked.length;

    for (let n = 0; n < budget; n++) {
      const card = tracked[(start + n) % tracked.length];
      cardsPolled++;
      const listings = await activeListingsFor(card, env);
      for (const li of listings) {
        listingsSeen++;
        await upsertListing(env, card.bobaId, li);
      }
    }
    const next = (start + budget) % tracked.length;
    await env.CURSOR.put("cursor:tracker:next_index", String(next));

    const vanishCount = await detectVanished(env);
    await recordRun(env, started, cardsPolled, listingsSeen, vanishCount, null);
    return { started, cardsPolled, listingsSeen, vanishCount, nextIndex: next };
  } catch (e) {
    err = String(e && e.message || e);
    await recordRun(env, started, cardsPolled, listingsSeen, 0, err);
    return { started, error: err };
  }
}

/**
 * Full active-listing set for one card, with stable item ids.
 * TODO (two-part build): point at the eBay-proxy's tracker endpoint that
 * returns ALL active listings + buyingOption/endDate/seller/condition. The
 * current main endpoint returns only the top ~10 with {title,price,date,url},
 * which is insufficient for reliable vanish-inference — so this returns []
 * for now (snapshot is a safe no-op until the endpoint lands).
 */
async function activeListingsFor(card, env) {
  const params = new URLSearchParams({
    cardNumber: card.cardNumber || "", hero: card.hero || "",
    set: card.set || "", element: card.element || "", days: "90", full: "1",
  });
  if (card.treatment) params.set("treatment", card.treatment);
  const res = await env.EBAY_PROXY_SVC.fetch(new Request(`https://internal/tracker/active?${params}`));
  if (!res.ok) return [];
  const data = await res.json().catch(() => null);
  // GATE (step 1, README): only consume the dedicated enriched endpoint,
  // which marks its response `full:true` and returns ALL active listings with
  // stable item ids. The proxy's current fall-through to its main pricing
  // handler returns a TRUNCATED top-10 set WITHOUT that marker — never infer
  // sold from that. Returns [] until the enriched endpoint ships.
  if (!data || data.full !== true) return [];
  const items = data.items || [];
  return items
    .map(it => ({
      itemId: it.itemId || itemIdFromUrl(it.url),
      price: Number(it.price) || 0,
      title: it.title || "",
      url: it.url || "",
      image: it.image || it.imageUrl || null,
      format: it.buyingOption || it.format || null,
      endTime: it.endDate || it.itemEndDate || null,
      sellerId: it.seller || it.sellerId || null,
      condition: it.condition || null,
    }))
    .filter(li => li.itemId && li.price > 0);
}

async function upsertListing(env, bobaId, li) {
  const now = nowIso();
  await env.DB.prepare(
    `INSERT INTO listings (item_id, boba_id, price_usd, condition, format, end_time,
                           seller_id, image_url, title, first_seen, last_seen)
       VALUES (?,?,?,?,?,?,?,?,?,?,?)
     ON CONFLICT(item_id) DO UPDATE SET
       price_usd = excluded.price_usd,
       last_seen = excluded.last_seen,
       condition = COALESCE(excluded.condition, listings.condition),
       format    = COALESCE(excluded.format, listings.format),
       end_time  = COALESCE(excluded.end_time, listings.end_time),
       seller_id = COALESCE(excluded.seller_id, listings.seller_id)`
  ).bind(li.itemId, bobaId, li.price, li.condition, li.format, li.endTime,
         li.sellerId, li.image, li.title, now, now).run();
}

/**
 * Mark listings not seen in > 2x cadence as vanished, then score sold-inference.
 * v1 confidence uses only signals we currently have (listing duration before
 * vanish); §3.4's richer signals (format/end_time/seller behavior) activate
 * once the enriched proxy populates those columns.
 */
async function detectVanished(env) {
  const cadenceH = Number(env.CADENCE_HOURS || 6);
  const cutoff = new Date(Date.now() - 2 * cadenceH * 3600e3).toISOString();
  const { results } = await env.DB.prepare(
    `SELECT item_id, price_usd, format, end_time, first_seen, last_seen
       FROM listings WHERE vanished_at IS NULL AND last_seen < ?`
  ).bind(cutoff).all();

  let count = 0;
  for (const row of results || []) {
    const conf = soldConfidence(row);
    await env.DB.prepare(
      `UPDATE listings SET vanished_at = ?, inferred_sold = ?, sold_confidence = ?, sold_price_usd = ?
         WHERE item_id = ?`
    ).bind(nowIso(), conf >= 0.55 ? 1 : 0, conf, row.price_usd, row.item_id).run();
    count++;
  }
  return count;
}

// §3.4 sold-inference confidence (additive, capped 0..1). v1 uses listing
// duration; format/end_time/seller signals add weight once populated.
function soldConfidence(row) {
  let c = 0.5; // neutral prior for a vanished BIN-style listing
  const durDays = (Date.parse(row.last_seen) - Date.parse(row.first_seen)) / 86400e3;
  if (Number.isFinite(durDays)) {
    if (durDays > 14) c += 0.20;       // long-listed then moved = likely real sale
    else if (durDays < 1) c -= 0.30;   // <24h = likely edit/delist/typo
  }
  if (row.format === "AUCTION" && row.end_time && Date.parse(row.end_time) <= Date.now()) c += 0.20;
  if (row.format === "AUCTION" && row.end_time && Date.parse(row.end_time) - Date.now() > 86400e3) c -= 0.50;
  return Math.max(0, Math.min(1, c));
}

async function recordRun(env, started, polled, seen, vanish, error) {
  await env.DB.prepare(
    `INSERT INTO snapshot_runs (started_at, finished_at, cards_polled, listings_seen, vanish_count, error)
       VALUES (?,?,?,?,?,?)`
  ).bind(started, nowIso(), polled, seen, vanish, error).run();
}
