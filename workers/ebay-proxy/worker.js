/**
 * BOBA Playbook — eBay Pricing Proxy
 *
 * Uses the eBay Browse API (v1) with OAuth client credentials.
 * The old Finding API (svcs.ebay.com/services/search/FindingService/v1)
 * was decommissioned February 5, 2025 — that's why all calls returned
 * "Service call has exceeded the number of times the operation is allowed to be called."
 *
 * Auth: Client Credentials Grant (app token, no user login required).
 *   Secrets required in Wrangler:
 *     EBAY_APP_ID  — your production Client ID  (e.g. "BenWilko-BOBAPlay-PRD-...")
 *     EBAY_CERT_ID — your production Client Secret / Cert ID
 *
 * Query parameters:
 *   cardNumber — e.g. "RAD-352"
 *   hero       — hero name, e.g. "Brockness"
 *   set        — set name (unused in query, kept for future)
 *   element    — element name (unused in query, kept for future)
 *   days       — lookback window hint 7/30/90 (kept for cache key; Browse API
 *                returns current active listings so "days" doesn't filter)
 *
 * Search strategy (two-stage):
 *   Stage 1: "bo jackson battle arena {hero} {cardNumber}"
 *     — card number encodes treatment; sellers almost always include it.
 *   Stage 2: "bo jackson battle arena {hero}"
 *     — broader fallback when stage 1 returns 0 results.
 *
 * Response JSON:
 *   {
 *     "low": 1.99, "average": 4.50, "high": 12.00, "listingCount": 14,
 *     "recentListings": [
 *       { "title": "...", "price": 4.50, "url": "https://..." },
 *       ...
 *     ]
 *   }
 *
 * Note: Browse API returns active (current) listings, not historical sold prices.
 * For sold price history, eBay's Marketplace Insights API is required (needs
 * special program approval from eBay developer support).
 */

const BROWSE_API  = "https://api.ebay.com/buy/browse/v1/item_summary/search";
const TOKEN_URL   = "https://api.ebay.com/identity/v1/oauth2/token";
const MARKETPLACE = "EBAY_US";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

// ── OAuth token management ────────────────────────────────────────────────────

/**
 * Returns a valid app-level OAuth Bearer token, fetching a fresh one when needed.
 * Tokens are cached in the Workers Cache for (expires_in - 5 min).
 */
async function getAppToken(env, cache) {
  const tokenCacheKey = new Request("https://boba-cache.internal/ebay-oauth/v1");
  const cachedToken   = await cache.match(tokenCacheKey);
  if (cachedToken) {
    const { access_token } = await cachedToken.json();
    return access_token;
  }

  // Client Credentials Grant: base64(clientId:clientSecret) in Authorization header
  const credentials = btoa(`${env.EBAY_APP_ID}:${env.EBAY_CERT_ID}`);
  const tokenRes = await fetch(TOKEN_URL, {
    method:  "POST",
    headers: {
      "Content-Type":  "application/x-www-form-urlencoded",
      "Authorization": `Basic ${credentials}`,
    },
    // scope must be URL-encoded in the body
    body: "grant_type=client_credentials&scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope",
  });

  if (!tokenRes.ok) {
    const txt = await tokenRes.text().catch(() => tokenRes.status);
    throw new Error(`OAuth token error ${tokenRes.status}: ${txt}`);
  }

  const { access_token, expires_in } = await tokenRes.json();

  // Cache for (expires_in - 5 minutes) so we never use an expired token
  const cacheTTL = Math.max(60, (expires_in ?? 7200) - 300);
  await cache.put(
    tokenCacheKey,
    new Response(JSON.stringify({ access_token }), {
      headers: {
        "Content-Type":  "application/json",
        "Cache-Control": `public, max-age=${cacheTTL}`,
      },
    })
  );

  return access_token;
}

// ── Browse API search ─────────────────────────────────────────────────────────

/**
 * Searches eBay Browse API for active fixed-price listings matching `keywords`.
 * Returns { items, error } where items is an array of itemSummary objects.
 */
async function searchListings(token, keywords) {
  const params = new URLSearchParams({
    q:      keywords,
    filter: "buyingOptions:{FIXED_PRICE}",
    limit:  "100",
    sort:   "price",
  });

  const res = await fetch(`${BROWSE_API}?${params}`, {
    headers: {
      "Authorization":           `Bearer ${token}`,
      "X-EBAY-C-MARKETPLACE-ID": MARKETPLACE,
      "Accept":                  "application/json",
    },
  });

  if (!res.ok) {
    let msg = `Browse API ${res.status}`;
    try {
      const err = await res.json();
      msg = err?.errors?.[0]?.message ?? msg;
    } catch { /* ignore parse error */ }
    return { items: [], error: msg };
  }

  const data  = await res.json();
  const items = data.itemSummaries ?? [];
  return { items, error: null };
}

// ── OCR handler (unchanged) ───────────────────────────────────────────────────

async function handleOCR(request, env) {
  if (!env.AI) return json({ error: "AI binding not configured", cardNumber: null }, 500);

  let body;
  try { body = await request.json(); }
  catch { return json({ error: "Invalid JSON", cardNumber: null }, 400); }

  const { image } = body ?? {};
  if (!image || typeof image !== "string") {
    return json({ error: "image field required (base64 JPEG)", cardNumber: null }, 400);
  }

  const MODEL = "@cf/meta/llama-3.2-11b-vision-instruct";
  const runParams = {
    messages: [{
      role:    "user",
      content: [
        { type: "image_url", image_url: { url: `data:image/jpeg;base64,${image}` } },
        { type: "text",      text: "Transcribe every piece of text you can see in this image. Include all letters, numbers, words, and codes exactly as printed. Return only the raw text, nothing else." },
      ],
    }],
    max_tokens: 256,
  };

  try {
    const result  = await env.AI.run(MODEL, runParams);
    const rawText = String(result?.response ?? result?.description ?? result ?? "").trim();
    const CARD_NUM_RE = /[A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?/gi;
    const candidates  = [...rawText.matchAll(CARD_NUM_RE)].map(m => m[0].toUpperCase());
    return json({ cardNumber: candidates[0] ?? null, candidates, rawText });
  } catch (err) {
    return json({ error: String(err), cardNumber: null, candidates: [] }, 500);
  }
}

// ── Main handler ──────────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: CORS });
    }

    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname.endsWith("/ocr")) {
      return handleOCR(request, env);
    }

    const { searchParams } = url;
    const cardNumber = searchParams.get("cardNumber");
    const hero       = searchParams.get("hero")    || "";
    const days       = Math.min(Math.max(parseInt(searchParams.get("days") ?? "30", 10), 1), 90);

    if (!cardNumber) {
      return json({ error: "cardNumber parameter required" }, 400);
    }
    if (!env.EBAY_APP_ID || !env.EBAY_CERT_ID) {
      return json({ error: "EBAY_APP_ID and EBAY_CERT_ID secrets required" }, 500);
    }

    // ── Cache ─────────────────────────────────────────────────────────────────
    // v4 prefix invalidates old caches from the decommissioned Finding API.
    // Browse API returns current active listings, so cache for 6 hours
    // (shorter than 24h because active listings change more frequently).
    const cache    = caches.default;
    const cacheURL = `https://boba-cache.internal/v4/${encodeURIComponent(hero)}/${encodeURIComponent(cardNumber)}/${days}`;
    const cacheKey = new Request(cacheURL);

    const cached = await cache.match(cacheKey);
    if (cached) {
      const body = await cached.json();
      return json(body, 200, { "X-Cache": "HIT" });
    }

    // ── Fetch OAuth token ─────────────────────────────────────────────────────
    let token;
    try {
      token = await getAppToken(env, cache);
    } catch (err) {
      return json({ error: String(err), listingCount: 0, low: 0, average: 0, high: 0, recentListings: [] }, 502);
    }

    // ── Two-stage search ──────────────────────────────────────────────────────
    // Stage 1: specific (hero + card number — most precise)
    const keywordsSpecific = ["bo jackson battle arena", hero, cardNumber].filter(Boolean).join(" ");
    let { items, error } = await searchListings(token, keywordsSpecific);

    // Stage 2: broad fallback — if 0 results and no error, try hero only
    if (items.length === 0 && !error && hero) {
      const keywordsBroad = ["bo jackson battle arena", hero].filter(Boolean).join(" ");
      const fallback = await searchListings(token, keywordsBroad);
      if (!fallback.error) items = fallback.items;
    }

    if (error) {
      const errorBody = { error, listingCount: 0, low: 0, average: 0, high: 0, recentListings: [] };
      // Cache errors for 5 minutes so a broken token/quota doesn't cascade
      await cache.put(cacheKey, new Response(JSON.stringify(errorBody), {
        headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=300" },
      }));
      return json(errorBody, 502);
    }

    // ── Aggregate prices ──────────────────────────────────────────────────────
    const prices = items
      .map(item => parseFloat(item?.price?.value ?? "0"))
      .filter(p => p > 0);

    if (prices.length === 0) {
      return json({ low: 0, average: 0, high: 0, listingCount: 0, recentListings: [] });
    }

    prices.sort((a, b) => a - b);
    const low     = round2(prices[0]);
    const high    = round2(prices[prices.length - 1]);
    const average = round2(prices.reduce((s, p) => s + p, 0) / prices.length);

    const recentListings = items
      .filter(item => parseFloat(item?.price?.value ?? "0") > 0)
      .slice(0, 10)
      .map(item => ({
        title: item?.title ?? "",
        price: round2(parseFloat(item?.price?.value ?? "0")),
        url:   item?.itemWebUrl ?? "",
      }));

    const result = { low, average, high, listingCount: prices.length, recentListings };

    // Cache for 6 hours
    await cache.put(cacheKey, new Response(JSON.stringify(result), {
      headers: {
        "Content-Type":  "application/json",
        "Cache-Control": "public, max-age=21600",
      },
    }));

    return json(result, 200, { "X-Cache": "MISS" });
  },
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", ...extra },
  });
}

function round2(n) {
  return Math.round(n * 100) / 100;
}
