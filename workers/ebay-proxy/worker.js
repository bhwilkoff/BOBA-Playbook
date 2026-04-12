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
 * Exact-match filtering (in order of reliability):
 *   1. localizedAspects "Card Number" — definitive match/reject when seller fills it in
 *   2. Title: alphanumeric card numbers (e.g. CBF-656, RAD-352) must appear with
 *      word-boundary context (not embedded in another number)
 *   3. Title: numeric-only card numbers require hero name; lot patterns excluded
 *
 * Search query: "bo jackson battle arena {hero} {cardNumber} {power}"
 *   Card number encodes treatment (RAD-352 = Rad Battlefoil). Power level helps
 *   eBay surface the right variant and lets us cross-check against aspect data.
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
 * Check eBay localizedAspects for structured card attributes.
 *
 * Returns:
 *   true  — Card Number aspect is an exact (normalised) match
 *   false — Card Number aspect has alphanumeric content that clearly
 *           identifies a DIFFERENT card (e.g. "CBF-100" when we want "CBF-656")
 *   null  — no decisive aspects; fall through to title matching
 *
 * Numeric-only aspects (e.g. "656" filled in for "CBF-656") are AMBIGUOUS:
 * any card numbered 656 in any set matches, so we return null and let
 * title matching decide. We never hard-accept on ambiguous data.
 */
function checkAspects(aspects, cardNumber, power) {
  if (!aspects || aspects.length === 0) return null;

  const map = {};
  for (const { name, value } of aspects) {
    if (name && value) map[name.toLowerCase()] = value;
  }

  const aspectCardNum =
    map["card number"] ?? map["card #"] ?? map["card no."] ?? map["number"];
  if (aspectCardNum !== undefined) {
    const normAspect = norm(aspectCardNum);
    const normCard   = norm(cardNumber);
    // Exact normalised match → definitive accept
    if (normAspect === normCard) return true;
    // Numeric-only aspect → too ambiguous; fall through to title matching
    if (/^\d+$/.test(normAspect)) return null;
    // Alphanumeric content that doesn't match → definitive reject
    return false;
  }

  // Power level check: reject only when aspect explicitly disagrees
  if (power != null) {
    const aspectPowerRaw = map["power"] ?? map["power level"];
    if (aspectPowerRaw !== undefined) {
      const aspectPower = parseInt(aspectPowerRaw, 10);
      if (!isNaN(aspectPower) && aspectPower !== power) return false;
    }
  }

  return null;
}

/**
 * Returns true if this listing is relevant to the specific card.
 *
 * Priority order:
 *   1. localizedAspects "Card Number" — definitive when present
 *   2. Title match (alphanumeric card numbers): full normalized number OR
 *      numeric portion with word-boundary context (not embedded in another number)
 *   3. Title match (numeric-only card numbers): hero name required, lots excluded
 */
function isExactMatch(title, aspects, cardNumber, hero, power) {
  // ── Step 1: structured aspect check ──────────────────────────────────────
  const aspectResult = checkAspects(aspects, cardNumber, power);
  if (aspectResult !== null) return aspectResult;

  // ── Step 2: title-based matching ──────────────────────────────────────────
  const titleNorm  = norm(title);
  const titleLower = title.toLowerCase();
  const isNumeric  = /^\d+$/.test(cardNumber);

  // Exclude obvious lot/bundle listings regardless of card number type
  if (LOT_PATTERNS.some(p => titleLower.includes(p))) return false;

  if (isNumeric) {
    // Pure numeric: require hero name (lots already excluded above)
    return titleNorm.includes(norm(hero));
  } else {
    // Alphanumeric (CBF-656, RAD-352, LOGO-203, etc.):
    // 1. Full normalized match: "cbf656", "rad352" — most reliable
    if (titleNorm.includes(norm(cardNumber))) return true;

    // 2. Numeric portion with word-boundary context.
    //    "Rad #352" → passes; "power203" or "12034" → fails.
    //    Use original title (not titleNorm) so we can check non-digit boundaries.
    const numPart = cardNumber.replace(/\D/g, "");
    if (numPart) {
      // Require the number to be preceded by a non-digit (or start) and followed
      // by a non-digit (or end). This prevents "203" matching "2034" or "1203".
      const re = new RegExp(`(?:^|\\D)0*${numPart}(?:\\D|$)`);
      if (re.test(titleLower)) return true;
    }
    return false;
  }
}

// ── Radish Price Guide data source ────────────────────────────────────────────

/**
 * Fetches pre-validated sold data from Radish Price Guide.
 * Radish embeds all sales in __NEXT_DATA__ — no separate API call needed.
 * Their allSales array has already matched each eBay sale to the specific card,
 * so accuracy is far higher than our own eBay title/aspect filtering.
 *
 * Returns an array of normalised items, or null on failure.
 */
async function fetchRadishSales(radishUrl, days) {
  try {
    const res = await fetch(radishUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Accept":     "text/html,application/xhtml+xml",
      },
    });
    if (!res.ok) return null;

    const html  = await res.text();
    const match = html.match(/<script id="__NEXT_DATA__" type="application\/json">([^<]+)<\/script>/);
    if (!match) return null;

    const nextData = JSON.parse(match[1]);
    const allSales = nextData?.props?.pageProps?.allSales;
    if (!Array.isArray(allSales) || allSales.length === 0) return null;

    const cutoff = new Date();
    cutoff.setUTCDate(cutoff.getUTCDate() - days);

    return allSales
      .filter(s => !s.hide && s.sold_date && new Date(s.sold_date) >= cutoff)
      .map(s => ({
        title: s.title ?? s.card_name ?? "",
        price: parseFloat(s.price ?? "0"),
        date:  s.sold_date ?? "",
        url:   s.link ?? "",
      }))
      .filter(i => i.price > 0 && i.title);
  } catch {
    return null;
  }
}

// ── AI image verification ─────────────────────────────────────────────────────

/**
 * Uses the Cloudflare Workers AI vision model to read the card number from
 * an eBay listing image, then checks if it matches the expected card number.
 *
 * Returns:
 *   true  — image confirms this is the right card
 *   false — image shows a different card number (definitive mismatch)
 *   null  — image unreadable / AI uncertain / timeout (don't reject)
 */
async function verifyCardImage(imageUrl, cardNumber, env) {
  if (!env.AI || !imageUrl) return null;
  const numPart = cardNumber.replace(/\D/g, "");
  try {
    const imgRes = await fetch(imageUrl, { signal: AbortSignal.timeout(5000) });
    if (!imgRes.ok) return null;
    const buf    = await imgRes.arrayBuffer();
    const bytes  = new Uint8Array(buf);
    let binary   = "";
    for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
    const base64 = btoa(binary);

    const result = await env.AI.run("@cf/meta/llama-3.2-11b-vision-instruct", {
      messages: [{
        role:    "user",
        content: [
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${base64}` } },
          { type: "text", text: "Look at this trading card image. What card number is printed on it? Card numbers look like CBF-656 or RAD-203 or just a number like 203. Reply with ONLY the card number you can read clearly, or 'unknown' if you cannot see one." },
        ],
      }],
      max_tokens: 16,
    });

    const text = String(result?.response ?? "").trim().toUpperCase().replace(/[^A-Z0-9-]/g, "");
    if (!text || text === "UNKNOWN") return null;

    // Accept if AI saw the full card number or just its numeric portion
    return norm(text) === norm(cardNumber) || text === numPart;
  } catch {
    return null; // timeout or model error — don't reject
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

function normaliseSold(items, cardNumber, hero, power) {
  return items
    .filter(item => isExactMatch(
      item.title ?? "",
      item.localizedAspects ?? [],
      cardNumber, hero, power
    ))
    .map(item => ({
      title: item.title ?? "",
      price: parseFloat(item.lastSoldPrice?.value ?? "0"),
      date:  item.lastSoldDate ?? "",
      url:   item.itemWebUrl ?? "",
    }))
    .filter(i => i.price > 0);
}

/**
 * Normalise Browse API items with two-phase matching:
 *   Phase 1 — title + aspect filtering with confidence tracking
 *   Phase 2 — AI image verification for low-confidence matches (max 3, parallel)
 *
 * "Low confidence" = matched only on numeric portion of card number (no aspects,
 * no full card number in title). Image check can reject these but never force-reject
 * an unreadable image — null AI result = keep the listing.
 */
async function normaliseActive(items, cardNumber, hero, power, env) {
  // Phase 1: filter with confidence
  const candidates = [];
  for (const item of items) {
    const title    = item.title ?? "";
    const aspects  = item.localizedAspects ?? [];
    const imageUrl = item.image?.imageUrl ?? "";
    const price    = parseFloat(item.price?.value ?? "0");
    if (price <= 0) continue;

    const aspectResult = checkAspects(aspects, cardNumber, power);
    let match = false, confidence = "low";

    if (aspectResult !== null) {
      match      = aspectResult;
      confidence = "high";
    } else {
      const titleNorm  = norm(title);
      const titleLower = title.toLowerCase();
      const isNumeric  = /^\d+$/.test(cardNumber);

      if (LOT_PATTERNS.some(p => titleLower.includes(p))) {
        match = false;
      } else if (isNumeric) {
        match      = titleNorm.includes(norm(hero));
        confidence = "medium";
      } else {
        if (titleNorm.includes(norm(cardNumber))) {
          match = true; confidence = "high";
        } else {
          const numPart = cardNumber.replace(/\D/g, "");
          if (numPart) {
            const re = new RegExp(`(?:^|\\D)0*${numPart}(?:\\D|$)`);
            if (re.test(titleLower)) { match = true; confidence = "low"; }
          }
        }
      }
    }

    if (match) candidates.push({ item, confidence, imageUrl, price });
  }

  // Phase 2: image-verify low-confidence matches (parallel, max 3)
  const lowConf = candidates.filter(c => c.confidence === "low").slice(0, 3);
  let rejectedUrls = new Set();
  if (lowConf.length > 0 && env?.AI) {
    const checks = await Promise.all(
      lowConf.map(c => verifyCardImage(c.imageUrl, cardNumber, env))
    );
    rejectedUrls = new Set(
      lowConf
        .filter((_, i) => checks[i] === false)   // false = definitive mismatch
        .map(c => c.item.itemWebUrl ?? "")
    );
  }

  return candidates
    .filter(c => !rejectedUrls.has(c.item.itemWebUrl ?? ""))
    .map(c => ({
      title: c.item.title ?? "",
      price: c.price,
      date:  "",
      url:   c.item.itemWebUrl ?? "",
    }));
}

// ── Discord message proxy ─────────────────────────────────────────────────────

/**
 * GET /discord/messages?channel=...&limit=50&before=...&after=...
 * Proxies channel message reads using a Bot token so the client never needs
 * guild channel read permissions in its OAuth2 scope.
 * Requires DISCORD_BOT_TOKEN worker secret.
 */
async function handleDiscordMessages(request, env) {
  if (!env.DISCORD_BOT_TOKEN) {
    return json({ error: "DISCORD_BOT_TOKEN not configured" }, 500);
  }

  const url = new URL(request.url);
  const channelId = url.searchParams.get("channel") ?? "1306146115757936650";

  const params = new URLSearchParams();
  const limit  = url.searchParams.get("limit");
  const before = url.searchParams.get("before");
  const after  = url.searchParams.get("after");
  if (limit)  params.set("limit",  limit);
  if (before) params.set("before", before);
  if (after)  params.set("after",  after);

  const discordUrl = `https://discord.com/api/v10/channels/${channelId}/messages${params.toString() ? "?" + params : ""}`;

  const res = await fetch(discordUrl, {
    headers: { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}` },
  });

  if (!res.ok) {
    const err = await res.text().catch(() => String(res.status));
    return json({ error: `Discord ${res.status}: ${err}` }, res.status >= 500 ? 502 : res.status);
  }

  const messages = await res.json();
  return json(messages);
}

// ── Discord initial token exchange ────────────────────────────────────────────

/**
 * POST /discord/token
 * Body: { code, code_verifier, redirect_uri }
 * Returns: { access_token, refresh_token, expires_in, token_type, scope }
 *
 * Exchanges a Discord authorization code for tokens. Requires DISCORD_CLIENT_SECRET
 * because Discord's confidential client configuration requires the secret even for
 * PKCE flows. The client must never send the secret — this Worker holds it.
 */
async function handleDiscordToken(request, env) {
  if (!env.DISCORD_CLIENT_SECRET) {
    return json({ error: "DISCORD_CLIENT_SECRET not configured" }, 500);
  }
  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { code, code_verifier, redirect_uri } = body ?? {};
  if (!code || typeof code !== "string") return json({ error: "code required" }, 400);
  if (!code_verifier || typeof code_verifier !== "string") return json({ error: "code_verifier required" }, 400);
  if (!redirect_uri || typeof redirect_uri !== "string") return json({ error: "redirect_uri required" }, 400);

  const tokenRes = await fetch("https://discord.com/api/oauth2/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id:     "1491134218829304009",
      client_secret: env.DISCORD_CLIENT_SECRET,
      grant_type:    "authorization_code",
      code,
      redirect_uri,
      code_verifier,
    }),
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text().catch(() => String(tokenRes.status));
    return json({ error: `Discord ${tokenRes.status}: ${err}` }, tokenRes.status >= 500 ? 502 : 400);
  }

  const tokens = await tokenRes.json();
  return json({
    access_token:  tokens.access_token,
    refresh_token: tokens.refresh_token,
    expires_in:    tokens.expires_in,
    token_type:    tokens.token_type,
    scope:         tokens.scope,
  });
}

// ── Discord token refresh ─────────────────────────────────────────────────────

/**
 * POST /discord/refresh
 * Body: { refresh_token: "..." }
 * Returns: { access_token, refresh_token, expires_in }
 *
 * Exchanges a Discord refresh token for a new access + refresh token pair.
 * Requires DISCORD_CLIENT_SECRET worker secret. The client_id is public and
 * hardcoded; the secret must never appear in client code.
 */
async function handleDiscordRefresh(request, env) {
  if (!env.DISCORD_CLIENT_SECRET) {
    return json({ error: "DISCORD_CLIENT_SECRET not configured" }, 500);
  }
  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { refresh_token } = body ?? {};
  if (!refresh_token || typeof refresh_token !== "string") {
    return json({ error: "refresh_token required" }, 400);
  }

  const tokenRes = await fetch("https://discord.com/api/oauth2/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id:     "1491134218829304009",
      client_secret: env.DISCORD_CLIENT_SECRET,
      grant_type:    "refresh_token",
      refresh_token,
    }),
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text().catch(() => String(tokenRes.status));
    return json({ error: `Discord ${tokenRes.status}: ${err}` }, tokenRes.status >= 500 ? 502 : 400);
  }

  const tokens = await tokenRes.json();
  return json({
    access_token:  tokens.access_token,
    refresh_token: tokens.refresh_token,
    expires_in:    tokens.expires_in,
  });
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
    if (request.method === "POST" && url.pathname.endsWith("/discord/token"))   return handleDiscordToken(request, env);
    if (request.method === "POST" && url.pathname.endsWith("/discord/refresh")) return handleDiscordRefresh(request, env);
    if (request.method === "GET"  && url.pathname.endsWith("/discord/messages")) return handleDiscordMessages(request, env);

    const { searchParams } = url;
    const cardNumber = searchParams.get("cardNumber");
    const hero       = searchParams.get("hero") || "";
    const powerRaw   = searchParams.get("power");
    const power      = powerRaw != null ? parseInt(powerRaw, 10) : null;
    const days       = Math.min(Math.max(parseInt(searchParams.get("days") ?? "30", 10), 1), 90);
    const radishUrl  = searchParams.get("radishUrl") || "";

    if (!cardNumber) return json({ error: "cardNumber parameter required" }, 400);
    if (!env.EBAY_APP_ID || !env.EBAY_CERT_ID) return json({ error: "EBAY_APP_ID and EBAY_CERT_ID secrets required" }, 500);

    // ── Cache ─────────────────────────────────────────────────────────────────
    // v9: fix checkAspects false-accept on numeric-only values; remove Browse broad fallback.
    const cache    = caches.default;
    const cacheURL = `https://boba-cache.internal/v9/${encodeURIComponent(hero)}/${encodeURIComponent(cardNumber)}/${days}`;
    const cacheKey = new Request(cacheURL);
    const cached   = await cache.match(cacheKey);
    if (cached) {
      const body = await cached.json();
      return json(body, 200, { "X-Cache": "HIT" });
    }

    // ── Try Radish Price Guide first (highest accuracy) ───────────────────────
    // Radish has already matched each eBay sale to the specific card — no title
    // parsing needed. When available, this is far more reliable than eBay APIs.
    if (radishUrl) {
      const radishItems = await fetchRadishSales(radishUrl, days);
      if (radishItems && radishItems.length > 0) {
        const sorted  = [...radishItems].sort((a, b) => a.price - b.price);
        const prices  = sorted.map(i => i.price);
        const result  = {
          low:       round2(prices[0]),
          average:   round2(prices.reduce((s, p) => s + p, 0) / prices.length),
          high:      round2(prices[prices.length - 1]),
          count:     radishItems.length,
          priceType: "sold",
          // Return most recent 10 (already sorted newest-first by fetchRadishSales)
          items:     radishItems.slice(0, 10),
        };
        const cacheTTL = 21600; // 6h
        await cache.put(cacheKey, new Response(JSON.stringify(result), {
          headers: { "Content-Type": "application/json", "Cache-Control": `public, max-age=${cacheTTL}` },
        }));
        return json(result, 200, { "X-Cache": "MISS", "X-Source": "radish" });
      }
    }

    // ── OAuth token (needed for eBay APIs) ────────────────────────────────────
    let token;
    try { token = await getAppToken(env, cache); }
    catch (err) { return json({ error: String(err), count: 0, low: 0, average: 0, high: 0, priceType: "sold", items: [] }, 502); }

    // ── Cutoff date for sold search ───────────────────────────────────────────
    const cutoff = new Date();
    cutoff.setUTCHours(0, 0, 0, 0);
    cutoff.setUTCDate(cutoff.getUTCDate() - days);
    const cutoffISO = cutoff.toISOString();

    // ── Search query ──────────────────────────────────────────────────────────
    // Include power in the query: sellers often write "Maverick 135 RAD-203".
    // Stage 1 (specific): hero + card number + power
    // Stage 2 (broad): hero only — catches listings that omit the card number
    const powerStr         = power != null && !isNaN(power) ? String(power) : null;
    const keywordsSpecific = ["bo jackson battle arena", hero, cardNumber, powerStr].filter(Boolean).join(" ");
    const keywordsBroad    = ["bo jackson battle arena", hero].filter(Boolean).join(" ");

    // ── Try Marketplace Insights (sold items) ─────────────────────────────────
    let soldItems   = [];
    let useSold     = false;
    let browseError = null;

    {
      const { items, error, noScope } = await searchSold(token, keywordsSpecific, cutoffISO);
      if (!noScope && !error) {
        soldItems = normaliseSold(items, cardNumber, hero, power);
        // Broad fallback if specific query returned 0 exact matches
        if (soldItems.length === 0 && hero) {
          const fb = await searchSold(token, keywordsBroad, cutoffISO);
          if (!fb.error) soldItems = normaliseSold(fb.items, cardNumber, hero, power);
        }
        useSold = true;
      }
      // noScope or error → silent fallback to Browse (don't surface Insights errors)
    }

    // ── Fall back to Browse (active listings) if sold returned 0 ─────────────
    // Only use the specific query (hero + cardNumber + power) — no broad hero-only
    // fallback. The broad fallback returned hundreds of irrelevant cards for the
    // same hero, overwhelming the title/aspect filter with false positives.
    let activeItems = [];
    if (!useSold || soldItems.length === 0) {
      const { items, error } = await searchActive(token, keywordsSpecific);
      if (!error) {
        activeItems = await normaliseActive(items, cardNumber, hero, power, env);
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
    // Always sort by price for stats so LOW/HIGH are unambiguous.
    const sorted  = [...finalItems].sort((a, b) => a.price - b.price);
    const prices  = sorted.map(i => i.price);
    const low     = round2(prices[0]);
    const high    = round2(prices[prices.length - 1]);
    const average = round2(prices.reduce((s, p) => s + p, 0) / prices.length);

    // For active listings: sample evenly across the price-sorted array so the
    // visible list reflects the same distribution driving LOW/AVG/HIGH — not
    // just the cheapest 10. For sold items: keep chronological order (most recent).
    const items = priceType === "sold"
      ? finalItems.slice(0, 10)
      : sampleAcrossRange(sorted, 10);

    const result = { low, average, high, count: finalItems.length, priceType, items };

    // Cache sold 6h, active listings 2h (listings change faster)
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

/**
 * Pick up to maxCount items evenly spaced across a price-sorted array.
 * Ensures the returned list spans the full price range, so users can see
 * what's driving the LOW/AVG/HIGH stats — not just the cheapest items.
 */
function sampleAcrossRange(sortedByPrice, maxCount = 10) {
  if (sortedByPrice.length <= maxCount) return sortedByPrice;
  const step = (sortedByPrice.length - 1) / (maxCount - 1);
  return Array.from({ length: maxCount }, (_, i) =>
    sortedByPrice[Math.round(i * step)]
  );
}
