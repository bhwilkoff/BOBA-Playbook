/**
 * BOBA Playbook — eBay Pricing Proxy
 *
 * Proxies eBay Finding API `findCompletedItems` for a given BOBA card,
 * calculates LOW / AVG / HIGH from sold listings, and caches results for 24 hours.
 *
 * Query parameters:
 *   cardNumber  — e.g. "BF-208" (used for cache key and as fallback)
 *   hero        — hero name, e.g. "Scary" (used in search query)
 *   set         — set name, e.g. "Griffey" (used to derive year)
 *   element     — element name, e.g. "Ice" (used in search query)
 *   days        — lookback window: 7, 30, or 90 (default 30)
 *
 * Search query formula (mirrors Radish's validated approach):
 *   "{year} bo jackson battle arena {hero} {treatment} {element}"
 *
 * Response JSON:
 *   {
 *     "low": 1.99, "average": 4.50, "high": 12.00, "saleCount": 14,
 *     "recentSales": [
 *       { "title": "...", "price": 4.50, "date": "2026-03-15T12:00:00Z", "url": "https://..." },
 *       ...
 *     ]
 *   }
 */

const EBAY_API = "https://svcs.ebay.com/services/search/FindingService/v1";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

// Maps card number prefix → full treatment name used by eBay sellers.
// "Paper" is the base (no prefix) — sellers include it explicitly.
const TREATMENT_MAP = {
  "GLBF": "Grandma's Linoleum Battlefoil",
  "BLBF": "Blizzard Battlefoil",
  "RAD":  "80's Rad Battlefoil",
  "LOGO": "Logo Battlefoil",
  "MIX":  "Mix Battlefoil",
  "BBF":  "Blizzard Battlefoil",
  "ABF":  "Alpha Battlefoil",
  "IBF":  "Ice Battlefoil",
  "SBF":  "Stained Glass Battlefoil",
};

// Maps set name → release year for the search query.
const SET_YEAR = {
  "Alpha":                   "2024",
  "Alpha Blast":             "2025",
  "Alpha Update":            "2025",
  "Griffey":                 "2026",
  "Battle Trainer Kit":      "2024",
  "National 24 Starter Set": "2024",
  "World Champions 2024":    "2024",
  "World Champions 2025":    "2025",
  "Promo Cards":             "2025",
  "Big League Chew":         "2025",
};

async function handleOCR(request, env) {
  if (!env.AI) return json({ error: 'AI binding not configured', cardNumber: null }, 500);

  let body;
  try { body = await request.json(); }
  catch { return json({ error: 'Invalid JSON', cardNumber: null }, 400); }

  const { image } = body ?? {};
  if (!image || typeof image !== 'string') {
    return json({ error: 'image field required (base64 JPEG)', cardNumber: null }, 400);
  }

  const MODEL = '@cf/meta/llama-3.2-11b-vision-instruct';
  const runParams = {
    messages: [{
      role: 'user',
      content: [
        { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${image}` } },
        {
          type: 'text',
          text: 'This is a trading card. Find the card number printed on it. Card numbers look like: AL-123, GLBF-45, BF-208, RAD-12, BBF-3, or similar patterns of letters-hyphen-numbers. Return ONLY the card number, nothing else. If you cannot find one, return the word none.'
        }
      ]
    }],
    max_tokens: 32
  };

  try {
    let result;
    try {
      result = await env.AI.run(MODEL, runParams);
    } catch (err) {
      // Error 5016: Meta Llama license agreement required once per account.
      // Automatically agree and retry.
      if (String(err).includes('5016')) {
        await env.AI.run(MODEL, {
          messages: [{ role: 'user', content: 'agree' }],
          max_tokens: 1
        }).catch(() => {});
        result = await env.AI.run(MODEL, runParams);
      } else {
        throw err;
      }
    }

    const rawText = (result?.response ?? '').trim();
    const CARD_NUM_RE = /([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)/g;
    const candidates = [...rawText.matchAll(CARD_NUM_RE)].map(m => m[1]);

    return json({ cardNumber: candidates[0] ?? null, candidates, rawText });
  } catch (err) {
    return json({ error: String(err), cardNumber: null, candidates: [] }, 500);
  }
}

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
    const set        = searchParams.get("set")     || "";
    const element    = searchParams.get("element") || "";
    const days = Math.min(Math.max(parseInt(searchParams.get("days") ?? "30", 10), 1), 90);

    if (!cardNumber) {
      return json({ error: "cardNumber parameter required" }, 400);
    }
    if (!env.EBAY_APP_ID) {
      return json({ error: "EBAY_APP_ID secret not configured" }, 500);
    }

    // ── Build search query ────────────────────────────────────────────────────
    // Formula: "{year} bo jackson battle arena {hero} {treatment} {element}"
    // This mirrors how Radish and eBay sellers refer to cards — by game name,
    // hero, and parallel treatment. Card numbers are rarely in eBay listings.
    const prefix    = cardNumber.split("-")[0].toUpperCase();
    const treatment = TREATMENT_MAP[prefix] || "Paper";
    const year      = SET_YEAR[set]         || "2024";
    const keywords  = [year, "bo jackson battle arena", hero, treatment, element]
      .filter(Boolean).join(" ");

    // ── Cache ─────────────────────────────────────────────────────────────────
    // Key includes hero so that two cards sharing a number (e.g. RAD-352 Brockness
    // vs Spider) each get their own search results and cache entry.
    // v2 prefix invalidates any old v1 caches that used the wrong "BOBA {number}" query.
    const cache = caches.default;
    const cacheURL = `https://boba-cache.internal/v2/${encodeURIComponent(hero)}/${encodeURIComponent(cardNumber)}/${days}`;
    const cacheKey = new Request(cacheURL);

    const cached = await cache.match(cacheKey);
    if (cached) {
      const body = await cached.json();
      return json(body, 200, { "X-Cache": "HIT" });
    }

    // ── eBay Finding API ──────────────────────────────────────────────────────
    // Round cutoff to midnight UTC so results are stable within a day.
    const cutoff = new Date();
    cutoff.setUTCHours(0, 0, 0, 0);
    cutoff.setUTCDate(cutoff.getUTCDate() - days);
    const cutoffStr = cutoff.toISOString();

    // Build query string manually to keep parentheses unencoded.
    // URLSearchParams percent-encodes ( and ) which some eBay API versions reject.
    const qp = [
      ["OPERATION-NAME",                 "findCompletedItems"],
      ["SERVICE-VERSION",                "1.0.0"],
      ["SECURITY-APPNAME",               env.EBAY_APP_ID],
      ["RESPONSE-DATA-FORMAT",           "JSON"],
      ["REST-PAYLOAD",                   ""],
      ["keywords",                       keywords],
      ["itemFilter(0).name",             "SoldItemsOnly"],
      ["itemFilter(0).value",            "true"],
      ["itemFilter(1).name",             "EndTimeFrom"],
      ["itemFilter(1).value",            cutoffStr],
      ["sortOrder",                      "EndTimeSoonest"],
      ["paginationInput.entriesPerPage", "100"],
    ];

    const queryString = qp
      .map(([k, v]) => `${encodeURIComponent(k).replace(/%28/g, "(").replace(/%29/g, ")")}=${encodeURIComponent(v)}`)
      .join("&");

    const ebayURL = `${EBAY_API}?${queryString}`;

    const ebayRes  = await fetch(ebayURL);
    const ebayData = await ebayRes.json();

    // Surface eBay-level errors
    if (!ebayRes.ok) {
      const msg = ebayData?.errorMessage?.[0]?.error?.[0]?.message?.[0]
               ?? ebayData?.findCompletedItemsResponse?.[0]?.errorMessage?.[0]?.error?.[0]?.message?.[0]
               ?? `eBay HTTP ${ebayRes.status}`;
      return json({ error: msg, saleCount: 0, low: 0, average: 0, high: 0, recentSales: [] }, 502);
    }

    const ack = ebayData?.findCompletedItemsResponse?.[0]?.ack?.[0];
    if (ack === "Failure") {
      const msg = ebayData?.findCompletedItemsResponse?.[0]?.errorMessage?.[0]?.error?.[0]?.message?.[0]
               ?? "eBay API failure";
      return json({ error: msg, saleCount: 0, low: 0, average: 0, high: 0, recentSales: [] }, 502);
    }

    const items = ebayData?.findCompletedItemsResponse?.[0]?.searchResult?.[0]?.item ?? [];

    // Aggregate prices
    const prices = items
      .map(item => parseFloat(item?.sellingStatus?.[0]?.convertedCurrentPrice?.[0]?.__value__ ?? "0"))
      .filter(p => p > 0);

    if (prices.length === 0) {
      return json({ low: 0, average: 0, high: 0, saleCount: 0, recentSales: [] });
    }

    prices.sort((a, b) => a - b);
    const low     = round2(prices[0]);
    const high    = round2(prices[prices.length - 1]);
    const average = round2(prices.reduce((s, p) => s + p, 0) / prices.length);

    // Recent sales — sorted by end time descending (most recent first), up to 10
    const recentSales = items
      .filter(item => parseFloat(item?.sellingStatus?.[0]?.convertedCurrentPrice?.[0]?.__value__ ?? "0") > 0)
      .sort((a, b) => {
        const tA = new Date(a?.listingInfo?.[0]?.endTime?.[0] ?? 0).getTime();
        const tB = new Date(b?.listingInfo?.[0]?.endTime?.[0] ?? 0).getTime();
        return tB - tA;
      })
      .slice(0, 10)
      .map(item => ({
        title: item?.title?.[0] ?? "",
        price: round2(parseFloat(item?.sellingStatus?.[0]?.convertedCurrentPrice?.[0]?.__value__ ?? "0")),
        date:  item?.listingInfo?.[0]?.endTime?.[0] ?? "",
        url:   item?.viewItemURL?.[0] ?? "",
      }));

    const result = { low, average, high, saleCount: prices.length, recentSales };

    // Cache for 24 hours
    const responseToCache = new Response(JSON.stringify(result), {
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=86400",
      },
    });
    await cache.put(cacheKey, responseToCache);

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
