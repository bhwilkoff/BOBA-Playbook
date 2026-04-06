/**
 * BOBA Playbook — eBay Pricing Proxy
 *
 * Auth: OAuth client credentials (EBAY_APP_ID + EBAY_CERT_ID).
 *
 * Two-API strategy:
 *   1. Marketplace Insights API — sold/completed item history (preferred)
 *      Requires buy.marketplace.insights scope; falls back if 403/empty.
 *   2. Browse API — current active fixed-price listings (fallback)
 *
 * Exact-match filtering:
 *   - Alphanumeric card numbers (e.g. CBF-656, RAD-352): listing title must
 *     contain the card number (normalized). This removes generic lots and
 *     "pick your card" listings that match on hero name alone.
 *   - Numeric-only card numbers (e.g. 199): exclude obvious lot/bundle
 *     patterns, require hero name in title.
 *
 * Search query: "bo jackson battle arena {hero} {cardNumber}"
 *   Card number encodes treatment (RAD-352 = Rad Battlefoil); using it
 *   directly is more reliable than full treatment names sellers rarely write.
 *
 * Response JSON:
 *   {
 *     "low": 1.99, "average": 4.50, "high": 12.00,
 *     "count": 3,
 *     "priceType": "sold",          // "sold" | "listed"
 *     "items": [
 *       { "title": "...", "price": 4.50, "date": "2026-03-15T12:00:00Z", "url": "..." },
 *       ...
 *     ]
 *   }
 */

const INSIGHTS_API = "https://api.ebay.com/buy/marketplace-insights/v1/item_sales/search";
const BROWSE_API   = "https://api.ebay.com/buy/browse/v1/item_summary/search";
const TOKEN_URL    = "https://api.ebay.com/identity/v1/oauth2/token";
const MARKETPLACE  = "EBAY_US";

// Base scope for Browse API. Marketplace Insights requires buy.marketplace.insights
// but requesting it as a combined scope causes a 400 if not approved. Instead we
// request just the base scope and let the Insights call return 403 (handled as
// a silent fallback to Browse).
const OAUTH_SCOPE = "https://api.ebay.com/oauth/api_scope";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

// ── Exact-match filtering ─────────────────────────────────────────────────────

// Normalize to lowercase alphanumeric only for fuzzy title comparison
const norm = s => s.toLowerCase().replace(/[^a-z0-9]/g, "");

// These patterns appear in bulk/lot listings and should be excluded when
// the specific card number is not confirmed to be in the title.
const LOT_PATTERNS = [
  "pick your", "you pick", "pick a card", "pick from", "singles pick",
  "lot of", "bundle", "choose your", "your card", "buy 3", "buy 2",
  "complete your set", "complete set", "your pick",
];

/**
 * Returns true if this listing is relevant to the specific card.
 *
 * Always excludes obvious lot/bundle listings (PICK YOUR CARD, etc.).
 *
 * For alphanumeric card numbers (e.g. CBF-656, RAD-352):
 *   - Match if the full normalized number is in the title ("cbf656"), OR
 *   - Match if the numeric portion alone ("656", "352") is in the title.
 *     Sellers often write "Brockness Rad Battlefoil #352" without the prefix.
 *     The hero is already baked into the search query so numeric part is specific enough.
 *
 * For numeric-only card numbers (e.g. "199"):
 *   - Exclude lots; require hero name in title.
 */
function isExactMatch(title, cardNumber, hero) {
  const titleNorm  = norm(title);
  const titleLower = title.toLowerCase();
  const isNumeric  = /^\d+$/.test(cardNumber);

  // Exclude obvious lot/bundle listings regardless of card number type
  if (LOT_PATTERNS.some(p => titleLower.includes(p))) return false;

  if (isNumeric) {
    // Pure numeric: require hero name (lots already excluded above)
    return titleNorm.includes(norm(hero));
  } else {
    // Alphanumeric (CBF-656, RAD-352):
    // 1. Full normalized match: "cbf656", "rad352", "cbf 656" etc.
    if (titleNorm.includes(norm(cardNumber))) return true;
    // 2. Numeric portion only: "656", "352" — catches "Bojax CBF #656" or "Rad #352"
    const numPart = cardNumber.replace(/\D/g, "");
    if (numPart && titleNorm.includes(numPart)) return true;
    return false;
  }
}

// ── OAuth token ───────────────────────────────────────────────────────────────

async function getAppToken(env, cache) {
  const tokenCacheKey = new Request("https://boba-cache.internal/ebay-oauth/v2");
  const cachedToken   = await cache.match(tokenCacheKey);
  if (cachedToken) {
    const { access_token } = await cachedToken.json();
    return access_token;
  }

  const credentials = btoa(`${env.EBAY_APP_ID}:${env.EBAY_CERT_ID}`);
  const tokenRes = await fetch(TOKEN_URL, {
    method:  "POST",
    headers: {
      "Content-Type":  "application/x-www-form-urlencoded",
      "Authorization": `Basic ${credentials}`,
    },
    body: `grant_type=client_credentials&scope=${encodeURIComponent(OAUTH_SCOPE)}`,
  });

  if (!tokenRes.ok) {
    const txt = await tokenRes.text().catch(() => String(tokenRes.status));
    throw new Error(`OAuth ${tokenRes.status}: ${txt}`);
  }

  const { access_token, expires_in } = await tokenRes.json();
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

// ── API calls ─────────────────────────────────────────────────────────────────

/** Marketplace Insights — sold/completed items. Returns {items, error, noScope}. */
async function searchSold(token, keywords, cutoffISO) {
  const params = new URLSearchParams({
    q:      keywords,
    filter: `lastSoldDate:[${cutoffISO}..]`,
    limit:  "50",
    sort:   "-lastSoldDate",
  });

  const res = await fetch(`${INSIGHTS_API}?${params}`, {
    headers: {
      "Authorization":           `Bearer ${token}`,
      "X-EBAY-C-MARKETPLACE-ID": MARKETPLACE,
      "Accept":                  "application/json",
    },
  });

  // 403 = scope not approved; 404 = endpoint not available for this app.
  // Both mean "silent fallback to Browse API".
  if (res.status === 403 || res.status === 404) return { items: [], error: null, noScope: true };

  if (!res.ok) {
    let msg = `Insights API ${res.status}`;
    try { msg = (await res.json())?.errors?.[0]?.message ?? msg; } catch { /* ignore */ }
    return { items: [], error: msg, noScope: false };
  }

  const data  = await res.json();
  const items = data.itemSales ?? [];
  return { items, error: null, noScope: false };
}

/** Browse API — current active fixed-price listings. Returns {items, error}. */
async function searchActive(token, keywords) {
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
    try { msg = (await res.json())?.errors?.[0]?.message ?? msg; } catch { /* ignore */ }
    return { items: [], error: msg };
  }

  const data  = await res.json();
  const items = data.itemSummaries ?? [];
  return { items, error: null };
}

// ── Normalise raw API items into a common shape ───────────────────────────────

function normaliseSold(items, cardNumber, hero) {
  return items
    .filter(item => isExactMatch(item.title ?? "", cardNumber, hero))
    .map(item => ({
      title: item.title ?? "",
      price: parseFloat(item.lastSoldPrice?.value ?? "0"),
      date:  item.lastSoldDate ?? "",
      url:   item.itemWebUrl ?? "",
    }))
    .filter(i => i.price > 0);
}

function normaliseActive(items, cardNumber, hero) {
  return items
    .filter(item => isExactMatch(item.title ?? "", cardNumber, hero))
    .map(item => ({
      title: item.title ?? "",
      price: parseFloat(item.price?.value ?? "0"),
      date:  "",   // Browse API doesn't return a sale date
      url:   item.itemWebUrl ?? "",
    }))
    .filter(i => i.price > 0);
}

// ── OCR handler (unchanged) ───────────────────────────────────────────────────

async function handleOCR(request, env) {
  if (!env.AI) return json({ error: "AI binding not configured", cardNumber: null }, 500);
  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON", cardNumber: null }, 400); }
  const { image } = body ?? {};
  if (!image || typeof image !== "string") return json({ error: "image field required (base64 JPEG)", cardNumber: null }, 400);

  const MODEL = "@cf/meta/llama-3.2-11b-vision-instruct";
  try {
    const result  = await env.AI.run(MODEL, {
      messages: [{ role: "user", content: [
        { type: "image_url", image_url: { url: `data:image/jpeg;base64,${image}` } },
        { type: "text", text: "Transcribe every piece of text you can see in this image. Include all letters, numbers, words, and codes exactly as printed. Return only the raw text, nothing else." },
      ]}],
      max_tokens: 256,
    });
    const rawText   = String(result?.response ?? result?.description ?? result ?? "").trim();
    const CARD_RE   = /[A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?/gi;
    const candidates = [...rawText.matchAll(CARD_RE)].map(m => m[0].toUpperCase());
    return json({ cardNumber: candidates[0] ?? null, candidates, rawText });
  } catch (err) {
    return json({ error: String(err), cardNumber: null, candidates: [] }, 500);
  }
}

// ── Main handler ──────────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });

    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname.endsWith("/ocr")) return handleOCR(request, env);

    const { searchParams } = url;
    const cardNumber = searchParams.get("cardNumber");
    const hero       = searchParams.get("hero") || "";
    const days       = Math.min(Math.max(parseInt(searchParams.get("days") ?? "30", 10), 1), 90);

    if (!cardNumber) return json({ error: "cardNumber parameter required" }, 400);
    if (!env.EBAY_APP_ID || !env.EBAY_CERT_ID) return json({ error: "EBAY_APP_ID and EBAY_CERT_ID secrets required" }, 500);

    // ── Cache ─────────────────────────────────────────────────────────────────
    // v5 invalidates old caches. Sold results cached 6h, listed results 2h.
    const cache    = caches.default;
    const cacheURL = `https://boba-cache.internal/v5/${encodeURIComponent(hero)}/${encodeURIComponent(cardNumber)}/${days}`;
    const cacheKey = new Request(cacheURL);
    const cached   = await cache.match(cacheKey);
    if (cached) {
      const body = await cached.json();
      return json(body, 200, { "X-Cache": "HIT" });
    }

    // ── OAuth token ───────────────────────────────────────────────────────────
    let token;
    try { token = await getAppToken(env, cache); }
    catch (err) { return json({ error: String(err), count: 0, low: 0, average: 0, high: 0, priceType: "sold", items: [] }, 502); }

    // ── Cutoff date for sold search ───────────────────────────────────────────
    const cutoff = new Date();
    cutoff.setUTCHours(0, 0, 0, 0);
    cutoff.setUTCDate(cutoff.getUTCDate() - days);
    const cutoffISO = cutoff.toISOString();

    // ── Search query ──────────────────────────────────────────────────────────
    // Stage 1 (specific): hero + card number — card number gives precision
    // Stage 2 (broad): hero only — catches listings that omit the card number
    const keywordsSpecific = ["bo jackson battle arena", hero, cardNumber].filter(Boolean).join(" ");
    const keywordsBroad    = ["bo jackson battle arena", hero].filter(Boolean).join(" ");

    // ── Try Marketplace Insights (sold items) ─────────────────────────────────
    let soldItems   = [];
    let useSold     = false;
    let browseError = null;

    {
      const { items, error, noScope } = await searchSold(token, keywordsSpecific, cutoffISO);
      if (!noScope && !error) {
        soldItems = normaliseSold(items, cardNumber, hero);
        // Broad fallback if specific query returned 0 exact matches
        if (soldItems.length === 0 && hero) {
          const fb = await searchSold(token, keywordsBroad, cutoffISO);
          if (!fb.error) soldItems = normaliseSold(fb.items, cardNumber, hero);
        }
        useSold = true;
      }
      // noScope or error → silent fallback to Browse (don't surface Insights errors)
    }

    // ── Fall back to Browse (active listings) if sold returned 0 ─────────────
    let activeItems = [];
    if (!useSold || soldItems.length === 0) {
      const { items, error } = await searchActive(token, keywordsSpecific);
      if (!error) {
        activeItems = normaliseActive(items, cardNumber, hero);
        if (activeItems.length === 0 && hero) {
          const fb = await searchActive(token, keywordsBroad);
          if (!fb.error) activeItems = normaliseActive(fb.items, cardNumber, hero);
        }
      } else {
        browseError = error;
      }
    }

    const finalItems = useSold && soldItems.length > 0 ? soldItems : activeItems;
    const priceType  = useSold && soldItems.length > 0 ? "sold" : "listed";

    if (finalItems.length === 0) {
      // Only surface Browse errors — Insights errors are non-critical since Browse is the fallback
      if (browseError) return json({ error: browseError, count: 0, low: 0, average: 0, high: 0, priceType, items: [] }, 502);
      return json({ count: 0, low: 0, average: 0, high: 0, priceType, items: [] });
    }

    // ── Aggregate ─────────────────────────────────────────────────────────────
    const prices = finalItems.map(i => i.price).sort((a, b) => a - b);
    const low     = round2(prices[0]);
    const high    = round2(prices[prices.length - 1]);
    const average = round2(prices.reduce((s, p) => s + p, 0) / prices.length);
    const items   = finalItems.slice(0, 10);

    const result = { low, average, high, count: finalItems.length, priceType, items };

    // Cache sold results 6h, active listing results 2h (listings change faster)
    const cacheTTL = priceType === "sold" ? 21600 : 7200;
    await cache.put(cacheKey, new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json", "Cache-Control": `public, max-age=${cacheTTL}` },
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

function round2(n) { return Math.round(n * 100) / 100; }
