/**
 * BOBA Playbook — Pricing Snapshot Worker
 *
 * Nightly cron that captures eBay + estimator pricing for every catalog
 * card and writes a timestamped row to the Supabase
 * `card_prices_history` table. Clients can read the latest row per
 * card on card-detail open (one PostgREST call, instant) instead of
 * always hitting the live ebay-proxy round-trip.
 *
 * Replaces the long-stale "Market Feed cron" docstring at the top of
 * boba-ebay-proxy/worker.js — that text described this exact
 * functionality but the cron itself was never implemented.
 *
 * ## What this Worker does
 *
 *  1. Reads the catalog from `CATALOG_URL`.
 *  2. Loads a rotating cursor from KV. Walks the catalog from that index.
 *  3. For each card, checks Supabase: is there a snapshot within the last
 *     `FRESH_THRESHOLD_HRS`? If yes, skip.
 *  4. Otherwise calls `boba-ebay-proxy` for fresh sold + active.
 *  5. If the response carries a sold or active section, inserts a row
 *     per non-empty section (source = 'ebay_sold' or 'ebay_active') into
 *     `card_prices_history`. If neither section had data, falls through
 *     to `boba-price-estimator` and inserts a 'estimator' row if it
 *     has a number.
 *  6. Every 100 cards processed, opportunistically deletes rows older
 *     than `RETENTION_DAYS` for the batch we just touched (so the
 *     table stays bounded without a separate purge job).
 *  7. Stops at `PER_CRON_BUDGET` or 25-minute soft wallclock cap.
 *  8. Saves cursor for next firing.
 *
 * No live HTTP endpoints beyond a manual `/refresh` trigger that
 * processes the next chunk and an `/explain` introspection endpoint
 * that returns the worker's config + last cron stats.
 *
 * ## Scoped explicitly NOT to do
 *
 *  - No outbound calls to radishpriceguide.com (DECISIONS.md #056).
 *  - No scraping of third-party HTML beyond what boba-ebay-proxy
 *    already wraps (eBay's licensed APIs).
 *  - No catalog mutation. Reads cards.json; never writes back.
 */

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const CURSOR_KEY = "cursor:snapshot:next_index";
const STATS_KEY  = "stats:snapshot:last_run";

async function supabaseInsert(env, rows) {
  if (rows.length === 0) return { written: 0 };
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/card_prices_history`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey":        env.SUPABASE_SERVICE_KEY,
      "Authorization": `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      "Prefer":        "return=minimal",
    },
    body: JSON.stringify(rows),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supabase insert failed ${res.status}: ${text}`);
  }
  return { written: rows.length };
}

async function supabaseLatestSnapshotAt(env, bobaId) {
  const url = new URL(`${env.SUPABASE_URL}/rest/v1/card_prices_history`);
  url.searchParams.set("boba_id", `eq.${bobaId}`);
  url.searchParams.set("select", "snapshot_at");
  url.searchParams.set("order", "snapshot_at.desc");
  url.searchParams.set("limit", "1");
  const res = await fetch(url, {
    headers: {
      "apikey":        env.SUPABASE_SERVICE_KEY,
      "Authorization": `Bearer ${env.SUPABASE_SERVICE_KEY}`,
    },
  });
  if (!res.ok) {
    await res.body?.cancel();
    return null;
  }
  const rows = await res.json();
  if (!Array.isArray(rows) || rows.length === 0) return null;
  return rows[0].snapshot_at;
}

async function supabasePruneOlderThan(env, daysAgo) {
  const cutoff = new Date(Date.now() - daysAgo * 24 * 3600 * 1000).toISOString();
  const url = new URL(`${env.SUPABASE_URL}/rest/v1/card_prices_history`);
  url.searchParams.set("snapshot_at", `lt.${cutoff}`);
  const res = await fetch(url, {
    method: "DELETE",
    headers: {
      "apikey":        env.SUPABASE_SERVICE_KEY,
      "Authorization": `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      "Prefer":        "return=minimal",
    },
  });
  if (!res.ok) {
    await res.body?.cancel();
    return { ok: false, status: res.status };
  }
  return { ok: true };
}

async function fetchEbayPricing(env, card) {
  const params = new URLSearchParams({
    cardNumber: card.cardNumber || "",
  });
  if (card.hero)      params.set("hero", card.hero);
  if (card.set)       params.set("set", card.set);
  if (card.element)   params.set("element", card.element);
  if (card.treatment) params.set("treatment", card.treatment);
  if (card.power != null) params.set("power", String(card.power));
  params.set("days", "90");
  try {
    const res = await fetch(`${env.EBAY_PROXY}?${params}`);
    if (!res.ok) {
      await res.body?.cancel();
      return null;
    }
    return await res.json();
  } catch {
    return null;
  }
}

async function fetchEstimator(env, bobaId) {
  try {
    const url = `${env.PRICE_ESTIMATOR}/estimate?bobaId=${encodeURIComponent(bobaId)}`;
    const res = await fetch(url);
    if (!res.ok) {
      await res.body?.cancel();
      return null;
    }
    return await res.json();
  } catch {
    return null;
  }
}

function buildRowsFromEbayResponse(bobaId, ebay) {
  const rows = [];
  if (ebay?.sold && (ebay.sold.average > 0 || ebay.sold.count > 0)) {
    rows.push({
      boba_id:     bobaId,
      source:      "ebay_sold",
      low_usd:     ebay.sold.low,
      avg_usd:     ebay.sold.average,
      high_usd:    ebay.sold.high,
      item_count:  ebay.sold.count || 0,
      raw:         { sold: ebay.sold },
    });
  }
  if (ebay?.active && (ebay.active.average > 0 || ebay.active.count > 0)) {
    rows.push({
      boba_id:     bobaId,
      source:      "ebay_active",
      low_usd:     ebay.active.low,
      avg_usd:     ebay.active.average,
      high_usd:    ebay.active.high,
      item_count:  ebay.active.count || 0,
      raw:         { active: ebay.active },
    });
  }
  return rows;
}

function buildRowFromEstimator(bobaId, est) {
  if (!est || typeof est.mid !== "number" || est.mid <= 0) return null;
  return {
    boba_id:     bobaId,
    source:      "estimator",
    low_usd:     est.low,
    avg_usd:     est.mid,
    high_usd:    est.high,
    item_count:  est.comparableCount || 0,
    raw:         { estimator: est },
  };
}

async function processOneCard(env, card) {
  const bobaId = card.bobaId;
  if (!bobaId) return { processed: false, written: 0 };
  // Skip if a fresh snapshot already exists.
  const freshHours = parseInt(env.FRESH_THRESHOLD_HRS || "18", 10);
  const lastAt = await supabaseLatestSnapshotAt(env, bobaId);
  if (lastAt) {
    const ageMs = Date.now() - Date.parse(lastAt);
    if (ageMs < freshHours * 3600 * 1000) {
      return { processed: false, skipped: true, written: 0 };
    }
  }
  // Fetch live eBay; if no sold+active, try estimator.
  const ebay = await fetchEbayPricing(env, card);
  const rows = buildRowsFromEbayResponse(bobaId, ebay);
  if (rows.length === 0) {
    const est = await fetchEstimator(env, bobaId);
    const estRow = buildRowFromEstimator(bobaId, est);
    if (estRow) rows.push(estRow);
  }
  if (rows.length === 0) return { processed: true, written: 0 };
  const ins = await supabaseInsert(env, rows);
  return { processed: true, written: ins.written };
}

async function refreshAll(env) {
  const catalogRes = await fetch(env.CATALOG_URL);
  if (!catalogRes.ok) {
    console.error("Catalog fetch failed:", catalogRes.status);
    return { error: "catalog_fetch_failed" };
  }
  const catalog = await catalogRes.json();
  const cards = catalog.filter(c => c.bobaId);

  // Load rotating cursor.
  const cursorRaw = await env.SNAPSHOT_KV.get(CURSOR_KEY);
  let cursor = cursorRaw != null ? parseInt(cursorRaw, 10) : 0;
  if (!Number.isFinite(cursor) || cursor < 0 || cursor >= cards.length) cursor = 0;

  const budget = parseInt(env.PER_CRON_BUDGET || "600", 10);
  const SOFT_CAP_MS = 25 * 60 * 1000;
  const startedAt = Date.now();
  let processed = 0;
  let skipped   = 0;
  let written   = 0;
  let i = cursor;
  let wraps = 0;
  // Pre-prune old rows once per cron run (not per card; that would
  // burn too many DELETEs against Supabase).
  const retention = parseInt(env.RETENTION_DAYS || "90", 10);
  await supabasePruneOlderThan(env, retention);
  while (processed < budget && (Date.now() - startedAt) < SOFT_CAP_MS && wraps < 2) {
    if (i >= cards.length) { i = 0; wraps++; continue; }
    const target = cards[i++];
    let result;
    try {
      result = await processOneCard(env, target);
    } catch (e) {
      console.error("processOneCard failed", target.bobaId, e?.message);
      continue;
    }
    if (result.skipped) { skipped++; continue; }
    if (result.processed) processed++;
    written += result.written;
  }
  await env.SNAPSHOT_KV.put(CURSOR_KEY, String(i % cards.length));
  const elapsedMs = Date.now() - startedAt;
  const stats = {
    startedAt: new Date(startedAt).toISOString(),
    cursorStart: cursor,
    cursorEnd:   i % cards.length,
    processed, skipped, written, elapsedMs,
  };
  await env.SNAPSHOT_KV.put(STATS_KEY, JSON.stringify(stats));
  console.log("[snapshot-cron]", JSON.stringify(stats));
  return stats;
}

async function handleRefresh(env) {
  const stats = await refreshAll(env);
  return new Response(JSON.stringify(stats), {
    status: 200,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function handleExplain(env) {
  const stats = await env.SNAPSHOT_KV.get(STATS_KEY);
  const cursor = await env.SNAPSHOT_KV.get(CURSOR_KEY);
  return new Response(JSON.stringify({
    service: "boba-pricing-snapshot",
    config: {
      CATALOG_URL:         env.CATALOG_URL,
      EBAY_PROXY:          env.EBAY_PROXY,
      PRICE_ESTIMATOR:     env.PRICE_ESTIMATOR,
      PER_CRON_BUDGET:     env.PER_CRON_BUDGET,
      FRESH_THRESHOLD_HRS: env.FRESH_THRESHOLD_HRS,
      RETENTION_DAYS:      env.RETENTION_DAYS,
    },
    cursor:    cursor != null ? parseInt(cursor, 10) : 0,
    lastRun:   stats ? JSON.parse(stats) : null,
  }), {
    status: 200,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname.endsWith("/refresh")) {
      return handleRefresh(env);
    }
    if (request.method === "GET" && url.pathname.endsWith("/explain")) {
      return handleExplain(env);
    }
    return new Response(JSON.stringify({
      service:   "boba-pricing-snapshot",
      endpoints: ["POST /refresh", "GET /explain"],
    }), {
      status: 200,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  },

  async scheduled(_event, env) {
    await refreshAll(env);
  },
};
