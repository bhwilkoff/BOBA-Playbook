/**
 * BOBA Playbook — eBay Pricing Proxy
 *
 * Proxies eBay Finding API `findCompletedItems` for a given BOBA card number,
 * calculates LOW / AVG / HIGH from sold listings, and caches the result for 24 hours.
 *
 * Query parameters:
 *   cardNumber  — e.g. "BF-208"
 *   days        — lookback window: 7, 30, or 90 (default 30)
 *
 * Response JSON:
 *   { "low": 1.99, "average": 4.50, "high": 12.00, "saleCount": 14 }
 *
 * Deploy with:
 *   wrangler secret put EBAY_APP_ID
 *   wrangler deploy
 */

const EBAY_FINDING_API =
  "https://svcs.ebay.com/services/search/FindingService/v1";

export default {
  async fetch(request, env) {
    // CORS headers — allow requests from the iOS app and any web origin
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    const { searchParams } = new URL(request.url);
    const cardNumber = searchParams.get("cardNumber");
    const days = parseInt(searchParams.get("days") ?? "30", 10);

    if (!cardNumber) {
      return new Response(
        JSON.stringify({ error: "cardNumber parameter required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Build eBay Finding API URL
    const params = new URLSearchParams({
      "OPERATION-NAME": "findCompletedItems",
      "SERVICE-VERSION": "1.0.0",
      "SECURITY-APPNAME": env.EBAY_APP_ID,
      "RESPONSE-DATA-FORMAT": "JSON",
      "REST-PAYLOAD": "",
      keywords: `BOBA ${cardNumber}`,
      "itemFilter(0).name": "SoldItemsOnly",
      "itemFilter(0).value": "true",
      "itemFilter(1).name": "ListingType",
      "itemFilter(1).value": "AuctionWithBIN",
      "itemFilter(2).name": "ListingType",
      "itemFilter(2).value[0]": "Auction",
      "itemFilter(2).value[1]": "FixedPrice",
      "sortOrder": "EndTimeSoonest",
      "paginationInput.entriesPerPage": "100",
    });

    // Days filter — eBay Finding API supports DaysNumberDays for completed items
    if (days <= 90) {
      params.set("itemFilter(3).name", "DaysNumberDays");
      params.set("itemFilter(3).value", String(days));
    }

    const ebayURL = `${EBAY_FINDING_API}?${params.toString()}`;

    // Use Cloudflare's cache for 24 hours
    const cacheKey = new Request(ebayURL);
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) {
      const body = await cached.json();
      return new Response(JSON.stringify(body), {
        headers: { ...corsHeaders, "Content-Type": "application/json", "X-Cache": "HIT" },
      });
    }

    // Fetch from eBay
    const ebayRes = await fetch(ebayURL);
    if (!ebayRes.ok) {
      return new Response(
        JSON.stringify({ error: "eBay API error", status: ebayRes.status }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const ebayData = await ebayRes.json();

    // Parse sold prices
    const items =
      ebayData?.findCompletedItemsResponse?.[0]?.searchResult?.[0]?.item ?? [];

    const prices = items
      .map((item) => {
        const price = parseFloat(
          item?.sellingStatus?.[0]?.convertedCurrentPrice?.[0]?.__value__ ?? "0"
        );
        return price;
      })
      .filter((p) => p > 0);

    if (prices.length === 0) {
      const empty = { low: 0, average: 0, high: 0, saleCount: 0 };
      return new Response(JSON.stringify(empty), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    prices.sort((a, b) => a - b);
    const low = round2(prices[0]);
    const high = round2(prices[prices.length - 1]);
    const average = round2(prices.reduce((sum, p) => sum + p, 0) / prices.length);

    const result = { low, average, high, saleCount: prices.length };

    // Cache for 24 hours
    const response = new Response(JSON.stringify(result), {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=86400",
        "X-Cache": "MISS",
      },
    });
    await cache.put(cacheKey, response.clone());

    return response;
  },
};

function round2(n) {
  return Math.round(n * 100) / 100;
}
