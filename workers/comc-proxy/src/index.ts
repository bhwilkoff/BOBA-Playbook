/**
 * boba-comc-proxy — COMC.com data source for BOBA Playbook.
 *
 * Why this exists:
 *   COMC.com has 931 BoBA listings (verified 2026-04-29) with cardNumbers
 *   matching cards.json exactly. Anonymous fetch returns 403, so we run
 *   here in a Worker with browser-shaped headers to proxy listing data
 *   for the iOS + web client's Buy Now panel.
 *
 * KNOWN ISSUE — Cloudflare Turnstile (2026-04-29):
 *   Hours after Cowork's recon, COMC turned on a Cloudflare-managed
 *   Turnstile JS challenge for ALL anonymous browsers (residential
 *   IPs too — verified). The browser-shaped headers below are no
 *   longer sufficient; every fetch comes back as a 403 carrying an
 *   HTML challenge page (`<title>Just a moment...</title>`).
 *
 *   This Worker is wired up end-to-end (KV cache, /listings, /image,
 *   cron sweep) and the iOS + web clients are integrated against it.
 *   While Turnstile is active, every lookup returns `count: 0` /
 *   `error: COMC 403` and the clients soft-fail (no COMC items
 *   render alongside eBay's active listings).
 *
 *   Bypass options when revisiting:
 *     1. Cloudflare Browser Rendering API (runs real Chromium)
 *     2. Migrate to a Playwright runner pattern (mirrors
 *        whatnot_direct_sourcer.py)
 *     3. Solve Turnstile out-of-band, persist cf_clearance cookie
 *
 *   Per the handoff: "If COMC tightens anti-bot (Cloudflare Turnstile,
 *   dynamic JS challenge), the fallback is to migrate this to a
 *   Playwright-based runner."
 *
 * Endpoints:
 *   GET /listings?cardNumber={cn}
 *     → { count, listings: [{ title, set, year, cardNumber, hero,
 *                             condition, grading, asking_price_usd,
 *                             comc_url, image_url, item_id, seller? }] }
 *
 *   GET /image?cardNumber={cn}&size=zoom
 *     → 302 to img.comc.com URL (Worker re-shapes headers to defeat
 *       anti-bot when the iOS/web client follows the redirect)
 *
 *   GET /sweep
 *     → cron-only bulk-harvest endpoint. Walks /Cards,i100,=bo+Jackson…
 *       through all pages, persists to KV. Gated by SWEEP_SECRET header.
 *
 *   GET /health
 *     → { ok: true, ts }
 *
 * Cache layers:
 *   - Edge cache: Cache-Control: public, max-age=1800 (30 min)
 *   - KV: comc:listings:{cn}     30-min TTL
 *   - KV: comc:negative:{cn}     2-hour TTL when no listings exist
 *   - KV: comc:sweep:{iso_hour}  6-hour TTL for sweep harvest
 *
 * Politeness:
 *   The Worker only fetches when KV cache is cold. Per-card lookups
 *   are throttled by KV's TTL (one fetch per cn per 30min window).
 *   Sweep cron runs every 6h.
 */

export interface Env {
  COMC_CACHE: KVNamespace;
  SWEEP_SECRET?: string;
}

const COMC_BASE = "https://www.comc.com";
const IMG_BASE  = "https://img.comc.com";
const CACHE_TTL_LISTINGS_S = 30 * 60;   // 30 min
const CACHE_TTL_NEGATIVE_S = 2 * 60 * 60; // 2 hours
const CACHE_TTL_SWEEP_S    = 6 * 60 * 60; // 6 hours

const HEADERS: Record<string, string> = {
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
  "Accept":
    "text/html,application/xhtml+xml,application/xml;q=0.9," +
    "image/avif,image/webp,image/apng,*/*;q=0.8",
  "Accept-Language": "en-US,en;q=0.9",
  "Cache-Control": "no-cache",
  "Sec-Fetch-Dest": "document",
  "Sec-Fetch-Mode": "navigate",
  "Sec-Fetch-Site": "none",
  "Sec-Fetch-User": "?1",
  "Upgrade-Insecure-Requests": "1",
};

const IMG_HEADERS: Record<string, string> = {
  ...HEADERS,
  "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
  "Sec-Fetch-Dest": "image",
  "Sec-Fetch-Mode": "no-cors",
  "Sec-Fetch-Site": "same-site",
  "Referer": COMC_BASE + "/",
};

// ─── Types ────────────────────────────────────────────────────────────────────

interface ComcListing {
  item_id: string;
  comc_url: string;
  year: string;
  set: string;          // human-readable, slug spaces → spaces
  cardNumber: string;
  hero: string;
  hero_slug: string;    // dash form for image URL
  set_slug: string;     // dash form for image URL
  grading: "Ungraded" | "Graded";
  condition: string;
  asking_price_usd: number | null;
  image_url: string | null;
}

interface ListingsResponse {
  count: number;
  cardNumber: string;
  fetched_at: string;
  source: "comc";
  listings: ComcListing[];
}

// ─── Parsing — DOM-regex (no JSON in HTML, verified 2026-04-29) ──────────────

const LISTING_HREF_RE =
  /<a[^>]*href="(\/Cards\/Gaming\/(\d{4})\/([^/]+)\/([^/]+)\/([^/]+)\/(\d+)\/(Ungraded|Graded)\/COMC_CCG\/([^"]+))"/gi;

const PRICE_NEAR_HREF_RE = /\$(\d{1,4}(?:,\d{3})*(?:\.\d{2}))/;

const DETAIL_IMG_RE =
  /https:\/\/img\.comc\.com\/i\/Gaming\/[^?\s"]+\?id=[a-f0-9-]+(?:&size=\w+)?/i;

function parseListings(html: string, expectedCardNumber: string): ComcListing[] {
  const out: ComcListing[] = [];
  const seen = new Set<string>();

  // Reset regex state — global flag means we share lastIndex across calls.
  LISTING_HREF_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = LISTING_HREF_RE.exec(html)) !== null) {
    const [, href, year, setSlug, cnInUrl, heroSlug, itemId, grading, condition] = m;
    if (cnInUrl !== expectedCardNumber) continue; // exact-match only
    if (seen.has(itemId)) continue;
    seen.add(itemId);

    // Look ahead in the HTML for the asking price near this anchor.
    const window = html.slice(m.index + m[0].length, m.index + m[0].length + 1500);
    const priceMatch = PRICE_NEAR_HREF_RE.exec(window);
    const asking = priceMatch ? parseFloat(priceMatch[1].replace(/,/g, "")) : null;

    out.push({
      item_id: itemId,
      comc_url: `${COMC_BASE}${href}`,
      year,
      set: decodeSlug(setSlug, "_"),
      cardNumber: cnInUrl,
      hero: decodeSlug(heroSlug, "_"),
      hero_slug: heroSlug,
      set_slug: setSlug,
      grading: grading as "Ungraded" | "Graded",
      condition,
      asking_price_usd: asking,
      image_url: null, // populated lazily below
    });
  }

  // Cheapest first — that's almost always what users want to surface.
  out.sort((a, b) => {
    const ax = a.asking_price_usd ?? Number.POSITIVE_INFINITY;
    const bx = b.asking_price_usd ?? Number.POSITIVE_INFINITY;
    return ax - bx;
  });
  return out;
}

function decodeSlug(slug: string, sep: "_" | "-"): string {
  return slug.split(sep).join(" ").replace(/\s+/g, " ").trim();
}

/**
 * Synthesize the canonical img.comc.com URL from a listing's slug parts.
 * Image URL uses dashes between slug words (set "Bo-Jackson-Battle-Arena…");
 * page URL uses underscores. The transform is mechanical.
 */
function synthesizeImageUrl(listing: ComcListing): string {
  const setDash = listing.set_slug.replace(/_/g, "-");
  const heroDash = listing.hero_slug.replace(/_/g, "-");
  // Without the ?id={uuid} query, the CDN may serve a 404 or generic
  // — the canonical URL is fetched from the detail page when we need
  // the cache-busting token. For the redirect endpoint, we rely on
  // ?size=zoom alone and let COMC's CDN resolve current-listing UUID.
  return `${IMG_BASE}/i/Gaming/${listing.year}/${setDash}/${listing.cardNumber}/${heroDash}.jpg?size=zoom`;
}

// ─── HTTP shells ──────────────────────────────────────────────────────────────

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      ...extra,
    },
  });
}

async function fetchHtml(url: string): Promise<{ ok: boolean; status: number; html?: string; challenged?: boolean }> {
  const resp = await fetch(url, { headers: HEADERS, redirect: "follow" });
  // ALWAYS read the body — even on non-OK status — so we can detect
  // Cloudflare's Turnstile challenge page (which is served as HTTP
  // 403 with a JS-challenge HTML body). Discarding the body without
  // reading would also leak the connection and trigger Cloudflare's
  // "stalled HTTP response was canceled to prevent deadlock" warning
  // under high concurrency.
  const html = await resp.text().catch(() => "");
  const challenged =
    html.includes("Just a moment...") ||
    html.includes("/cdn-cgi/challenge-platform");
  if (!resp.ok) {
    return { ok: false, status: resp.status, challenged };
  }
  // Some WAF configs also serve the challenge under HTTP 200.
  if (challenged) {
    return { ok: false, status: resp.status, challenged: true };
  }
  return { ok: true, status: resp.status, html };
}

// ─── Endpoint handlers ───────────────────────────────────────────────────────

async function handleListings(req: Request, env: Env): Promise<Response> {
  const url = new URL(req.url);
  const cn = (url.searchParams.get("cardNumber") || "").trim();
  if (!cn) return json({ error: "cardNumber query param required" }, 400);

  // KV cache check
  const cacheKey = `comc:listings:${cn}`;
  const negKey   = `comc:negative:${cn}`;
  const cached = await env.COMC_CACHE.get(cacheKey, { type: "json" });
  if (cached) return json(cached, 200, {
    "Cache-Control": `public, max-age=${CACHE_TTL_LISTINGS_S}`,
  });
  const negative = await env.COMC_CACHE.get(negKey);
  if (negative === "1") {
    return json({
      count: 0,
      cardNumber: cn,
      fetched_at: new Date().toISOString(),
      source: "comc",
      listings: [],
      cached_negative: true,
    } satisfies ListingsResponse & { cached_negative: boolean });
  }

  // Fetch live
  const search = `${COMC_BASE}/Cards,i100,=${encodeURIComponent(cn)}`;
  const r = await fetchHtml(search);
  if (!r.ok || !r.html) {
    // Cloudflare Turnstile challenge — not a real failure, just an
    // anti-bot wall we can't currently bypass. Return the same
    // listings shape the client expects with count:0 and a
    // `challenged: true` hint, so soft-fail render paths don't
    // flag this as an error. Don't negative-cache (we want to
    // retry once the WAF rule lifts).
    if (r.challenged) {
      return json({
        count: 0,
        cardNumber: cn,
        fetched_at: new Date().toISOString(),
        source: "comc",
        listings: [],
        challenged: true,
      } satisfies ListingsResponse & { challenged: boolean });
    }
    return json({ error: `COMC ${r.status}`, cardNumber: cn }, 502);
  }

  const listings = parseListings(r.html, cn);
  const payload: ListingsResponse = {
    count: listings.length,
    cardNumber: cn,
    fetched_at: new Date().toISOString(),
    source: "comc",
    listings,
  };

  if (listings.length === 0) {
    // Negative-cache empty results so we don't pummel COMC for orphaned cardNumbers.
    await env.COMC_CACHE.put(negKey, "1", { expirationTtl: CACHE_TTL_NEGATIVE_S });
  } else {
    await env.COMC_CACHE.put(cacheKey, JSON.stringify(payload), {
      expirationTtl: CACHE_TTL_LISTINGS_S,
    });
  }

  return json(payload, 200, {
    "Cache-Control": `public, max-age=${CACHE_TTL_LISTINGS_S}`,
  });
}

/**
 * Lazy-resolve a card's image URL. Strategy:
 *   1. KV cache → return immediately
 *   2. If we have a cached listings response, pick the cheapest listing
 *      and use its detail-page URL → fetch detail page → parse img.comc.com URL
 *   3. Otherwise hit /Cards,i100,={cn} fresh, then step 2
 */
async function handleImage(req: Request, env: Env): Promise<Response> {
  const url = new URL(req.url);
  const cn = (url.searchParams.get("cardNumber") || "").trim();
  if (!cn) return json({ error: "cardNumber query param required" }, 400);

  const imgKey = `comc:image:${cn}`;
  const cached = await env.COMC_CACHE.get(imgKey);
  if (cached) return Response.redirect(cached, 302);

  // Locate the cheapest listing
  const listingsKey = `comc:listings:${cn}`;
  let listingPayload = await env.COMC_CACHE.get(listingsKey, { type: "json" }) as ListingsResponse | null;
  if (!listingPayload || listingPayload.listings.length === 0) {
    const search = `${COMC_BASE}/Cards,i100,=${encodeURIComponent(cn)}`;
    const r = await fetchHtml(search);
    if (!r.ok || !r.html) return json({ error: "no listings" }, 404);
    const fresh = parseListings(r.html, cn);
    if (fresh.length === 0) {
      await env.COMC_CACHE.put(`comc:negative:${cn}`, "1", {
        expirationTtl: CACHE_TTL_NEGATIVE_S,
      });
      return json({ error: "no listings" }, 404);
    }
    listingPayload = {
      count: fresh.length,
      cardNumber: cn,
      fetched_at: new Date().toISOString(),
      source: "comc",
      listings: fresh,
    };
    await env.COMC_CACHE.put(listingsKey, JSON.stringify(listingPayload), {
      expirationTtl: CACHE_TTL_LISTINGS_S,
    });
  }

  const top = listingPayload.listings[0];
  // Fetch the detail page to get the cache-busted CDN URL.
  const detail = await fetchHtml(top.comc_url);
  if (!detail.ok || !detail.html) {
    // Fall back to synthesized URL — works when COMC's CDN ignores the missing UUID.
    const synth = synthesizeImageUrl(top);
    await env.COMC_CACHE.put(imgKey, synth, { expirationTtl: CACHE_TTL_LISTINGS_S });
    return Response.redirect(synth, 302);
  }
  const m = DETAIL_IMG_RE.exec(detail.html);
  let imgUrl = m ? m[0] : synthesizeImageUrl(top);
  if (!imgUrl.includes("size=")) {
    imgUrl += (imgUrl.includes("?") ? "&" : "?") + "size=zoom";
  }
  await env.COMC_CACHE.put(imgKey, imgUrl, { expirationTtl: CACHE_TTL_LISTINGS_S });
  return Response.redirect(imgUrl, 302);
}

async function handleSweep(req: Request, env: Env): Promise<Response> {
  const provided = req.headers.get("X-Sweep-Secret") || "";
  if (!env.SWEEP_SECRET || provided !== env.SWEEP_SECRET) {
    return json({ error: "unauthorized" }, 401);
  }

  // Walk /Cards,i100,=bo+jackson+battle+arena pages 1..N until empty.
  const baseQuery = "bo+Jackson+battle+arena";
  const allListings: ComcListing[] = [];
  for (let page = 1; page <= 12; page++) {
    const url = page === 1
      ? `${COMC_BASE}/Cards,i100,=${baseQuery}`
      : `${COMC_BASE}/Cards,i100,=${baseQuery},pg${page}`;
    const r = await fetchHtml(url);
    if (!r.ok || !r.html) break;
    // Extract every listing on this page (no cardNumber filter — we want all)
    const pageListings = parseListingsRaw(r.html);
    if (pageListings.length === 0) break;
    allListings.push(...pageListings);
  }

  const hourTag = new Date().toISOString().slice(0, 13).replace(":", "_");
  const sweepKey = `comc:sweep:${hourTag}`;
  const payload = {
    fetched_at: new Date().toISOString(),
    count: allListings.length,
    listings: allListings,
  };
  await env.COMC_CACHE.put(sweepKey, JSON.stringify(payload), {
    expirationTtl: CACHE_TTL_SWEEP_S,
  });
  await env.COMC_CACHE.put("comc:sweep:latest", sweepKey, {
    expirationTtl: CACHE_TTL_SWEEP_S,
  });
  return json({ ok: true, count: allListings.length, sweepKey });
}

/** parseListingsRaw — same as parseListings but does NOT filter by cardNumber. */
function parseListingsRaw(html: string): ComcListing[] {
  const out: ComcListing[] = [];
  const seen = new Set<string>();
  LISTING_HREF_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = LISTING_HREF_RE.exec(html)) !== null) {
    const [, href, year, setSlug, cnInUrl, heroSlug, itemId, grading, condition] = m;
    if (seen.has(itemId)) continue;
    seen.add(itemId);
    const window = html.slice(m.index + m[0].length, m.index + m[0].length + 1500);
    const priceMatch = PRICE_NEAR_HREF_RE.exec(window);
    const asking = priceMatch ? parseFloat(priceMatch[1].replace(/,/g, "")) : null;
    out.push({
      item_id: itemId,
      comc_url: `${COMC_BASE}${href}`,
      year,
      set: decodeSlug(setSlug, "_"),
      cardNumber: cnInUrl,
      hero: decodeSlug(heroSlug, "_"),
      hero_slug: heroSlug,
      set_slug: setSlug,
      grading: grading as "Ungraded" | "Graded",
      condition,
      asking_price_usd: asking,
      image_url: null,
    });
  }
  return out;
}

// ─── Entry point ─────────────────────────────────────────────────────────────

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);

    if (url.pathname === "/health") {
      return json({ ok: true, ts: new Date().toISOString() });
    }
    if (url.pathname === "/listings") {
      return handleListings(req, env);
    }
    if (url.pathname === "/image") {
      return handleImage(req, env);
    }
    if (url.pathname === "/sweep") {
      return handleSweep(req, env);
    }

    return json({
      error: "not found",
      endpoints: ["/health", "/listings?cardNumber=", "/image?cardNumber=", "/sweep (cron)"],
    }, 404);
  },

  // Cron-driven sweep — Cloudflare invokes this from the trigger config in wrangler.toml
  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    if (!env.SWEEP_SECRET) return; // skip silently if not configured
    const reqHeaders = new Headers({ "X-Sweep-Secret": env.SWEEP_SECRET });
    const fakeReq = new Request("http://internal/sweep", { headers: reqHeaders });
    await handleSweep(fakeReq, env);
  },
};
