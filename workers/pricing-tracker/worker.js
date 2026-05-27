/**
 * boba-pricing-tracker — Tier 1 of the Pricing Playbook (PRICING_PLAYBOOK.md §3).
 *
 * Generates our OWN sold-history from public listings over time, since eBay
 * Marketplace Insights (sold comps) is permanently unavailable. When a
 * previously-seen active listing disappears from a fresh fetch, we infer
 * "sold @ last-seen price" with a confidence score (DECISIONS.md #058).
 *
 * PUSH MODEL (free-plan friendly): the eBay proxy fires `POST /ingest`
 * (ctx.waitUntil) on every pricing fetch — a card-detail open OR each card of
 * a Collection "refresh market values" — recording that card's CURRENT active
 * listings. Each ingest is its own tiny Worker invocation (well under
 * Cloudflare's 50-subrequest cap), so the system scales with real usage
 * instead of grinding the 17k catalog inside one cron invocation (which the
 * free-plan cap makes impossible). Vanish-detection runs per-card on ingest,
 * judged ONLY against a real new fetch of the same card — so a card nobody
 * views is never re-evaluated and never false-vanishes (no time-based sweep).
 *
 * `GET /comps?bobaId=X` serves the inferred-sold + community comps.
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
      if (url.pathname === "/ingest" && request.method === "POST")
        return await handleIngest(request, env);
      if (url.pathname === "/" || url.pathname === "")
        return json({
          service: "boba-pricing-tracker",
          doc: "PRICING_PLAYBOOK.md §3 + DECISIONS.md #058",
          endpoints: ["GET /comps?bobaId=X&days=90", "POST /ingest {bobaId,source,listings}"],
        });
      return json({ error: "not found" }, 404);
    } catch (e) {
      return json({ error: String(e && e.message || e) }, 500);
    }
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
            format, item_id AS itemId, image_url AS imageUrl, source
       FROM listings
      WHERE boba_id = ? AND inferred_sold = 1 AND sold_confidence >= ? AND vanished_at >= ?
      ORDER BY vanished_at DESC
      LIMIT 50`
  ).bind(bobaId, FLOOR, since).all();

  // Tag each inferred-sold comp by the marketplace it vanished from
  // ("ebay-inferred" / "whatnot-inferred") so clients can pill the source.
  const comps = (results || []).filter(c => c.price > 0)
    .map(c => ({
      price: c.price, soldAt: c.soldAt, confidence: c.confidence,
      format: c.format, itemId: c.itemId, imageUrl: c.imageUrl,
      source: `${c.source || "ebay"}-inferred`,
    }));

  // Merge approved community comps (Tier 3) — mod-approved, user-attested
  // sold prices from Supabase. Both are real "sold" signals, so they share
  // the summary; each row keeps its source so clients can pill it.
  for (const cc of await fetchCommunityComps(bobaId, since.slice(0, 10), env)) comps.push(cc);

  const prices = comps.map(c => Number(c.price)).filter(p => p > 0).sort((a, b) => a - b);
  const summary = prices.length
    ? { low: prices[0], median: prices[(prices.length - 1) >> 1], high: prices[prices.length - 1], count: prices.length }
    : { low: 0, median: 0, high: 0, count: 0 };
  return json({ bobaId, comps, summary, windowDays: days, source: "inferred_sold+community" });
}

/** Approved community comps for a card (Tier 3), via Supabase get_approved_comps. */
async function fetchCommunityComps(bobaId, sinceDate, env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return [];
  try {
    const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/get_approved_comps`, {
      method: "POST",
      headers: {
        apikey: env.SUPABASE_ANON_KEY,
        Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_boba_id: bobaId }),
    });
    if (!res.ok) return [];
    const rows = await res.json();
    return (rows || [])
      .filter(r => Number(r.price_usd) > 0 && (!r.sold_at || r.sold_at >= sinceDate))
      .map(r => ({
        price: Number(r.price_usd),
        soldAt: r.sold_at,
        confidence: 1.0,                          // mod-approved + user-attested
        format: null, itemId: null,
        imageUrl: r.photo_url || null,
        source: `community-${r.source_platform}`,
      }));
  } catch { return []; }
}

/**
 * POST /ingest — record one card's CURRENT active listings (push model).
 * Body: { bobaId, source: "ebay"|"whatnot", listings: [{itemId|url, price, …}] }.
 *
 * Upserts the fresh listings, then PER-CARD vanish-detection: any of this
 * card's previously-seen (un-vanished) listings absent from this fetch
 * disappeared → infer sold (confidence from listing duration). Correct
 * because we only judge "vanished" against a real new fetch of the SAME
 * card. Bounded to one card's listings, so it stays far under the
 * subrequest cap. Soft-validates; bad input is a no-op.
 */
async function handleIngest(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
  const bobaId = body && body.bobaId;
  const source = (body && body.source) === "whatnot" ? "whatnot" : "ebay";
  if (!bobaId) return json({ error: "bobaId required" }, 400);

  const incoming = (Array.isArray(body.listings) ? body.listings : [])
    .map(li => ({
      itemId:    li.itemId || itemIdFromUrl(li.url),
      price:     Number(li.price) || 0,
      title:     li.title || "",
      url:       li.url || "",
      image:     li.image || li.imageUrl || null,
      format:    li.format || li.buyingOption || null,
      endTime:   li.endTime || li.endDate || null,
      sellerId:  li.sellerId || li.seller || null,
      condition: li.condition || null,
    }))
    .filter(li => li.itemId && li.price > 0);
  const currentIds = new Set(incoming.map(li => li.itemId));

  // The card's un-vanished listings from the PREVIOUS fetch (same source).
  const { results: prior } = await env.DB.prepare(
    `SELECT item_id, price_usd, format, end_time, first_seen, last_seen
       FROM listings WHERE boba_id = ? AND source = ? AND vanished_at IS NULL`
  ).bind(bobaId, source).all();

  const stmts = incoming.map(li => upsertStmt(env, bobaId, li, source));

  const now = nowIso();
  let vanished = 0;
  for (const row of prior || []) {
    if (currentIds.has(row.item_id)) continue;      // still listed → not vanished
    const conf = soldConfidence(row);
    stmts.push(env.DB.prepare(
      `UPDATE listings SET vanished_at = ?, inferred_sold = ?, sold_confidence = ?, sold_price_usd = ?
         WHERE item_id = ?`
    ).bind(now, conf >= 0.55 ? 1 : 0, conf, row.price_usd, row.item_id));
    vanished++;
  }
  await flushBatch(env, stmts);
  return json({ bobaId, source, ingested: incoming.length, vanished });
}

// Build (not run) one upsert statement. Cloudflare caps subrequests per
// invocation, and a per-listing `.run()` is one subrequest each — at
// catalog scale that blows the cap. So we collect statements and flush via
// `DB.batch()` (one subrequest per batch).
function upsertStmt(env, bobaId, li, source = "ebay") {
  const now = nowIso();
  return env.DB.prepare(
    `INSERT INTO listings (item_id, boba_id, source, price_usd, condition, format, end_time,
                           seller_id, image_url, title, first_seen, last_seen)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
     ON CONFLICT(item_id) DO UPDATE SET
       price_usd = excluded.price_usd,
       last_seen = excluded.last_seen,
       condition = COALESCE(excluded.condition, listings.condition),
       format    = COALESCE(excluded.format, listings.format),
       end_time  = COALESCE(excluded.end_time, listings.end_time),
       seller_id = COALESCE(excluded.seller_id, listings.seller_id)`
  ).bind(li.itemId, bobaId, source, li.price, li.condition, li.format, li.endTime,
         li.sellerId, li.image, li.title, now, now);
}

/** Flush prepared statements in chunked `DB.batch()` calls (1 subrequest each). */
async function flushBatch(env, stmts) {
  for (let i = 0; i < stmts.length; i += 50) {
    await env.DB.batch(stmts.slice(i, i + 50));
  }
}

// Sold-inference confidence (additive, capped 0..1; DECISIONS.md #058).
// Uses listing duration (first_seen → last_seen) + auction end-time signals.
// On the push model, a long gap between fetches inflates duration, which is
// fine: a listing that was up a long time before disappearing is more likely
// a real sale than a quick edit/relist.
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
