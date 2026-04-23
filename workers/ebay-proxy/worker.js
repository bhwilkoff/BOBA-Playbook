/**
 * BOBA Playbook — eBay Pricing Proxy + Market Feed
 *
 * Auth: OAuth client credentials (EBAY_APP_ID + EBAY_CERT_ID).
 *
 * Per-card pricing — two-source strategy (Feature A):
 *   1. Radish Price Guide + eBay Browse API run in parallel → returns both
 *      a "sold" section (Radish or Marketplace Insights) and an "active"
 *      section (Browse API) in every response. Never early-returns on Radish
 *      data — users can always see Buy Now listings.
 *   2. Marketplace Insights API used for sold when no Radish URL available.
 *
 * Market Feed cron (Feature B):
 *   Runs every 30 minutes, searches for all recent BOBA sold items, matches
 *   them to the card catalog by extracting card number + hero from titles,
 *   and upserts them to the Supabase `recent_sales` table.
 *
 * Response JSON (per-card, v10):
 *   {
 *     "sold":   { "low", "average", "high", "count", "items" },  // may be absent
 *     "active": { "low", "average", "high", "count", "items" },  // may be absent
 *     // Legacy fields preserved for backward compat:
 *     "low", "average", "high", "count", "priceType", "items"
 *   }
 */

import HERO_ALIASES_FILE     from "./data/hero_aliases.json";
import TREATMENT_TOKENS_FILE from "./data/treatment_tokens.json";
import LOT_PATTERNS_FILE     from "./data/lot_patterns.json";
import TRUSTED_SELLERS_FILE  from "./data/trusted_sellers.json";
import PRICE_RANGES_FILE     from "./data/price_ranges.json";

const HERO_ALIASES    = HERO_ALIASES_FILE.aliases ?? {};
const TREATMENT_ALIAS = TREATMENT_TOKENS_FILE.aliases ?? {};
const TRUSTED_SELLERS = TRUSTED_SELLERS_FILE.sellers ?? [];
const PRICE_RANGES    = PRICE_RANGES_FILE.ranges ?? {};

const INSIGHTS_API = "https://api.ebay.com/buy/marketplace-insights/v1/item_sales/search";
const BROWSE_API   = "https://api.ebay.com/buy/browse/v1/item_summary/search";
const TOKEN_URL    = "https://api.ebay.com/identity/v1/oauth2/token";
const MARKETPLACE  = "EBAY_US";

// Score thresholds — see SOLD_COMP_MATCHER_HANDOFF.md §4. A listing
// scoring ≥ CONFIRMED contributes to low/avg/high. A listing in
// [PROBABLE, CONFIRMED) is shown with a "probable" badge but excluded
// from aggregates. Below PROBABLE, the listing is dropped entirely.
const SCORE_CONFIRMED = 0.70;
const SCORE_PROBABLE  = 0.45;

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

// Lot-listing substrings — pulled from ./data/lot_patterns.json so
// additions don't require code edits. When a title contains any of
// these, the sold-comp matcher applies a large negative score and the
// active-match path rejects outright.
const LOT_PATTERNS = LOT_PATTERNS_FILE.patterns ?? [];

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
 * Richer signal extraction used by the sold-comp scorer. Returns an object
 * capturing per-aspect hits without forcing a binary accept/reject — lets
 * scoreSoldListing() sum the signals additively.
 *
 * Per SOLD_COMP_MATCHER_HANDOFF.md §5.1.
 */
function extractAspectSignals(aspects, card) {
  const out = {
    decisiveAccept: false,
    decisiveReject: false,
    cardNumberSignal: 0,    // 0 | 0.5 | 1
    playerHit: false,
    manufacturerHit: false,
    yearHit: false,
    treatmentHit: false,
    powerHit: false,
  };
  if (!aspects || aspects.length === 0) return out;

  const map = {};
  for (const { name, value } of aspects) {
    if (name && value) map[name.toLowerCase()] = String(value);
  }

  // Card number aspect — same logic as the original checkAspects but
  // expressed as graded signal instead of tri-state.
  const aspectCardNum =
    map["card number"] ?? map["card #"] ?? map["card no."] ?? map["number"];
  if (aspectCardNum !== undefined) {
    const normAspect = norm(aspectCardNum);
    const normCard   = norm(card.cardNumber);
    if (normAspect === normCard) {
      out.cardNumberSignal = 1;
      out.decisiveAccept   = true;
    } else if (/^\d+$/.test(normAspect)) {
      // Numeric-only aspect — ambiguous; any card with that number in any
      // set matches. Give a partial signal; scorer needs more evidence
      // (hero, power, etc.) to tip into confirmed territory.
      const numPart = String(card.cardNumber).replace(/\D/g, "");
      if (numPart && normAspect === numPart) out.cardNumberSignal = 0.5;
    } else {
      // Alphanumeric content that doesn't match → hard reject.
      out.decisiveReject = true;
      return out;
    }
  }

  // Power — exact-match signal. Disagreement is a hard reject.
  if (card.power != null) {
    const powerRaw = map["power"] ?? map["power level"];
    if (powerRaw !== undefined) {
      const aspectPower = parseInt(powerRaw, 10);
      if (!isNaN(aspectPower)) {
        if (aspectPower === card.power) out.powerHit = true;
        else { out.decisiveReject = true; return out; }
      }
    }
  }

  // Player / Athlete — runs through hero alias expansion against the
  // canonical hero name.
  const playerRaw = map["player"] ?? map["athlete"] ?? map["subject"];
  if (playerRaw && heroMatches(playerRaw, card.hero)) {
    out.playerHit = true;
  }

  // Manufacturer / Brand — must explicitly mention BOBA.
  const mfgRaw = map["manufacturer"] ?? map["brand"] ?? map["publisher"];
  if (mfgRaw && /bo\s*jackson|BOBA|battle\s*arena/i.test(mfgRaw)) {
    out.manufacturerHit = true;
  }

  // Year — set-year match. We accept any of the canonical year hints
  // embedded in the catalog's `set` field (e.g. "Alpha Edition" → 2024,
  // "Griffey Edition" → 2025, "2026 Edition" → 2026).
  const yearRaw = map["year"] ?? map["season"] ?? map["release year"];
  if (yearRaw) {
    const aspectYear = parseInt(yearRaw, 10);
    const expected   = expectedYearForSet(card.set);
    if (!isNaN(aspectYear) && expected && aspectYear === expected) {
      out.yearHit = true;
    }
  }

  // Parallel / Treatment / Features — match against the catalog's
  // treatment tokens. Any one of the candidate aspects hitting is enough.
  const parallelRaw = map["parallel"] ?? map["treatment"] ?? map["variation"] ?? map["features"];
  if (parallelRaw && treatmentMatches(parallelRaw, card.treatment)) {
    out.treatmentHit = true;
  }

  return out;
}

// Map a set-name keyword to its canonical release year. Tolerant of
// future sets — unknown sets return null and the year signal contributes
// nothing.
function expectedYearForSet(set) {
  if (!set) return null;
  const s = set.toLowerCase();
  if (s.includes("2026")) return 2026;
  if (s.includes("griffey")) return 2025;
  if (s.includes("cyber")) return 2025;
  if (s.includes("alpha")) return 2024;
  // Fall back to any 4-digit year that looks like a release year.
  const m = s.match(/20(2[0-9]|3[0-9])/);
  return m ? parseInt(m[0], 10) : null;
}

/**
 * Case-/punctuation-insensitive substring match that additionally
 * accepts any known alias of the canonical hero name. Community spellings
 * like "Bojax" / "BJ" for BoJax get recovered here.
 *
 * Per SOLD_COMP_MATCHER_HANDOFF.md §5.2.
 */
function heroMatches(haystack, canonicalHero) {
  if (!haystack || !canonicalHero) return false;
  const hayNorm = norm(haystack);
  if (!hayNorm) return false;
  if (hayNorm.includes(norm(canonicalHero))) return true;
  const aliases = HERO_ALIASES[canonicalHero] ?? [];
  for (const alias of aliases) {
    const a = norm(alias);
    if (a && hayNorm.includes(a)) return true;
  }
  return false;
}

/**
 * Treatment / parallel match — checks if the title or a Parallel/Features
 * aspect mentions the canonical treatment or any of its community tokens.
 *
 * Per SOLD_COMP_MATCHER_HANDOFF.md §5.2.
 */
function treatmentMatches(haystack, canonicalTreatment) {
  if (!haystack || !canonicalTreatment) return false;
  const hayNorm = norm(haystack);
  if (!hayNorm) return false;
  if (hayNorm.includes(norm(canonicalTreatment))) return true;
  const tokens = TREATMENT_ALIAS[canonicalTreatment] ?? [];
  for (const token of tokens) {
    const t = norm(token);
    if (t && hayNorm.includes(t)) return true;
  }
  return false;
}

/**
 * Detects when a listing title mentions a DIFFERENT set name than the
 * card's set. Strict mode (recommended): only fires when the title
 * explicitly names a conflicting set (e.g. card is Alpha but title
 * mentions "Griffey Edition").
 *
 * Per SOLD_COMP_MATCHER_HANDOFF.md §5.2 + §14 Q6.
 */
function wrongEditionInTitle(title, cardSet) {
  if (!title || !cardSet) return false;
  const hayNorm = norm(title);
  const myYear  = expectedYearForSet(cardSet);
  // Set-name → signature tokens. Add to this list when new sets launch.
  const editions = [
    { name: "alpha",     tokens: ["alphaedition", "alpha"],                     year: 2024 },
    { name: "griffey",   tokens: ["griffeyedition", "griffey"],                 year: 2025 },
    { name: "cyber",     tokens: ["cyberpromo", "cyber"],                       year: 2025 },
    { name: "2026",      tokens: ["2026edition"],                                year: 2026 },
  ];
  // Find which edition the *card* belongs to.
  const myEdition = editions.find(e => e.year === myYear || e.tokens.some(t => norm(cardSet).includes(t)));
  if (!myEdition) return false;
  // Does the title explicitly signal a different edition?
  for (const e of editions) {
    if (e.name === myEdition.name) continue;
    if (e.tokens.some(t => hayNorm.includes(t))) return true;
  }
  return false;
}

/**
 * Trusted-seller lookup. Worker-side list lives in
 * ./data/trusted_sellers.json and is populated by Ben. Rows with
 * ebay_username:null are ignored at runtime.
 */
function trustedSellerBonus(sellerUsername) {
  if (!sellerUsername) return 0;
  const u = String(sellerUsername).toLowerCase();
  for (const row of TRUSTED_SELLERS) {
    if (row.ebay_username && row.ebay_username.toLowerCase() === u) {
      return Math.max(0, Math.min(0.2, Number(row.confidence_bonus) || 0));
    }
  }
  return 0;
}

/**
 * Price-range sanity check. Returns a small positive contribution when
 * the listing's price falls inside a 3× IQR window around the historical
 * median. No penalty when no ranges are known for this (hero, treatment)
 * pair — we don't want an empty price_ranges.json file to silently reject
 * every listing.
 *
 * Per SOLD_COMP_MATCHER_HANDOFF.md §5.2 + §6.4.
 */
function priceInRange(price, card) {
  if (!price || price <= 0 || !card.hero) return 0;
  const key  = `${card.hero}|${card.treatment ?? "Base"}`;
  const band = PRICE_RANGES[key];
  if (!band || band.n == null || band.n < 5) return 0;
  const lo = band.p10 / 3;
  const hi = band.p90 * 3;
  return (price >= lo && price <= hi) ? 1 : -1;
}

/**
 * Composite score for a single sold listing. Signals are additive;
 * result clamped to [0, 1]. See SOLD_COMP_MATCHER_HANDOFF.md §4 for
 * the full formula + weights.
 */
function scoreSoldListing(item, card) {
  const title        = item.title ?? "";
  const titleLower   = title.toLowerCase();
  const price        = parseFloat(item.lastSoldPrice?.value ?? item.price?.value ?? "0");
  const seller       = item.seller?.username ?? item.sellerUsername ?? null;
  const aspects      = item.localizedAspects ?? [];

  const asp = extractAspectSignals(aspects, card);
  if (asp.decisiveReject) {
    return { score: 0, reasons: ["aspect_mismatch"] };
  }

  const reasons = [];
  let score = 0;

  // Card-number signal — strongest when present.
  let cardNumSignal = asp.cardNumberSignal;
  if (cardNumSignal === 0) {
    // Fall back to title-based card-number matching (same logic as the
    // legacy isExactMatch for alphanumeric cards).
    const titleNorm  = norm(title);
    const isNumeric  = /^\d+$/.test(card.cardNumber);
    if (!isNumeric) {
      if (titleNorm.includes(norm(card.cardNumber))) {
        cardNumSignal = 1;
      } else {
        const numPart = String(card.cardNumber).replace(/\D/g, "");
        if (numPart) {
          const re = new RegExp(`(?:^|\\D)0*${numPart}(?:\\D|$)`);
          if (re.test(titleLower)) cardNumSignal = 0.5;
        }
      }
    }
  }
  if (cardNumSignal > 0) {
    score += 0.50 * cardNumSignal;
    reasons.push(cardNumSignal >= 1 ? "card_number_exact" : "card_number_partial");
  }

  // Hero signal — canonical hero or alias in title / player aspect.
  const heroHit = asp.playerHit || heroMatches(titleLower, card.hero);
  if (heroHit) {
    score += 0.20;
    reasons.push("hero");
  }

  // Power signal (aspect-level).
  if (asp.powerHit) {
    score += 0.10;
    reasons.push("power");
  } else if (card.power != null && new RegExp(`\\b${card.power}\\b`).test(titleLower)) {
    // Title mentions the power number — a weaker power signal.
    score += 0.05;
    reasons.push("power_in_title");
  }

  // Element signal.
  if (card.element && card.element !== "NONE" && titleLower.includes(card.element.toLowerCase())) {
    score += 0.05;
    reasons.push("element");
  }

  // Treatment — aspect or title.
  if (asp.treatmentHit || (card.treatment && treatmentMatches(titleLower, card.treatment))) {
    score += 0.05;
    reasons.push("treatment");
  }

  // Manufacturer aspect.
  if (asp.manufacturerHit) {
    score += 0.05;
    reasons.push("manufacturer");
  }

  // Year aspect.
  if (asp.yearHit) {
    score += 0.05;
    reasons.push("year");
  }

  // Trusted seller.
  const sellerBonus = trustedSellerBonus(seller);
  if (sellerBonus > 0) {
    score += sellerBonus;
    reasons.push("trusted_seller");
  }

  // Price-range sanity.
  const pr = priceInRange(price, card);
  if (pr > 0) { score += 0.05; reasons.push("price_in_range"); }
  else if (pr < 0) { score -= 0.05; reasons.push("price_outlier"); }

  // Lot penalty.
  if (LOT_PATTERNS.some(p => titleLower.includes(p))) {
    score -= 0.30;
    reasons.push("lot_penalty");
  }

  // Wrong-edition penalty.
  if (wrongEditionInTitle(title, card.set)) {
    score -= 0.15;
    reasons.push("wrong_edition_penalty");
  }

  // Clamp to [0, 1].
  score = Math.max(0, Math.min(1, score));
  return { score, reasons };
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

/**
 * Legacy sold-comp normaliser — used when MATCH_MODE=legacy (feature
 * flagged safety net during the enriched-matcher rollout, §10).
 */
function normaliseSoldLegacy(items, cardNumber, hero, power) {
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
 * Enriched sold-comp normaliser (MATCH_MODE=enriched, default). Each
 * item is scored via scoreSoldListing and placed into one of three
 * buckets:
 *
 *   score >= 0.70 → confirmed (counts toward low/avg/high)
 *   0.45 ≤ score < 0.70 → probable (shown with badge, excluded from aggregates)
 *   score < 0.45 → dropped
 *
 * Returns { confirmed, probable, counters } where counters is a small
 * diagnostic object logged to Cloudflare tail for §9 success metrics.
 *
 * Per SOLD_COMP_MATCHER_HANDOFF.md §4 + §5.3 + §9.
 */
function normaliseSoldEnriched(items, card) {
  const counters = {
    scanned:         items.length,
    confirmed:       0,
    probable:        0,
    rejected_lot:    0,
    rejected_score:  0,
  };
  const confirmed = [];
  const probable  = [];

  for (const item of items) {
    const price = parseFloat(item.lastSoldPrice?.value ?? "0");
    if (price <= 0) continue;

    const { score, reasons } = scoreSoldListing(item, card);
    const enriched = {
      title:            item.title ?? "",
      price,
      date:             item.lastSoldDate ?? "",
      url:              item.itemWebUrl ?? "",
      matchConfidence:  round2(score),
      matchReasons:     reasons,
    };

    if (score >= SCORE_CONFIRMED) {
      confirmed.push(enriched);
      counters.confirmed++;
    } else if (score >= SCORE_PROBABLE) {
      probable.push(enriched);
      counters.probable++;
    } else if (reasons.includes("lot_penalty")) {
      counters.rejected_lot++;
    } else {
      counters.rejected_score++;
    }
  }

  return { confirmed, probable, counters };
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
    // v11: enriched sold-comp matcher adds per-item matchConfidence /
    // matchReasons + count_probable on the sold section. v10 cached
    // responses don't have those fields, so bumping the key forces a
    // fresh fetch on first access under the new Worker.
    const cache    = caches.default;
    const cacheURL = `https://boba-cache.internal/v11/${encodeURIComponent(hero)}/${encodeURIComponent(cardNumber)}/${days}`;
    const cacheKey = new Request(cacheURL);
    const cached   = await cache.match(cacheKey);
    if (cached) {
      const body = await cached.json();
      return json(body, 200, { "X-Cache": "HIT" });
    }

    // ── Search query ──────────────────────────────────────────────────────────
    const powerStr         = power != null && !isNaN(power) ? String(power) : null;
    const keywordsSpecific = ["bo jackson battle arena", hero, cardNumber, powerStr].filter(Boolean).join(" ");
    const keywordsBroad    = ["bo jackson battle arena", hero].filter(Boolean).join(" ");

    // ── Cutoff date for sold search ───────────────────────────────────────────
    const cutoff = new Date();
    cutoff.setUTCHours(0, 0, 0, 0);
    cutoff.setUTCDate(cutoff.getUTCDate() - days);
    const cutoffISO = cutoff.toISOString();

    // ── Run Radish fetch + OAuth token in parallel ────────────────────────────
    // Radish has pre-matched each eBay sale to the specific card — far more
    // accurate than title/aspect filtering. The token is always needed for Browse.
    const [radishResult, tokenResult] = await Promise.allSettled([
      radishUrl ? fetchRadishSales(radishUrl, days) : Promise.resolve(null),
      getAppToken(env, cache),
    ]);

    // ── Build sold section from Radish ────────────────────────────────────────
    let soldSection  = null;
    const radishItems = radishResult.status === "fulfilled" ? radishResult.value : null;
    if (radishItems && radishItems.length > 0) {
      const sorted = [...radishItems].sort((a, b) => a.price - b.price);
      const prices = sorted.map(i => i.price);
      soldSection = {
        low:     round2(prices[0]),
        average: round2(prices.reduce((s, p) => s + p, 0) / prices.length),
        high:    round2(prices[prices.length - 1]),
        count:   radishItems.length,
        items:   radishItems.slice(0, 10),   // already newest-first from fetchRadishSales
      };
    }

    // ── eBay API calls (require OAuth token) ──────────────────────────────────
    let activeSection = null;
    let browseError   = null;

    if (tokenResult.status === "fulfilled") {
      const token = tokenResult.value;

      // If Radish had no data, try Marketplace Insights for sold history.
      // Per MATCH_MODE env flag: "enriched" (default) uses the new scorer;
      // "legacy" falls back to the binary isExactMatch filter.
      if (!soldSection) {
        const { items, error, noScope } = await searchSold(token, keywordsSpecific, cutoffISO);
        if (!noScope && !error) {
          const mode = (env.MATCH_MODE ?? "enriched").toLowerCase();

          if (mode === "legacy") {
            let soldItems = normaliseSoldLegacy(items, cardNumber, hero, power);
            if (soldItems.length === 0 && hero) {
              const fb = await searchSold(token, keywordsBroad, cutoffISO);
              if (!fb.error) soldItems = normaliseSoldLegacy(fb.items, cardNumber, hero, power);
            }
            if (soldItems.length > 0) {
              const sorted = [...soldItems].sort((a, b) => a.price - b.price);
              const prices = sorted.map(i => i.price);
              soldSection = {
                low:     round2(prices[0]),
                average: round2(prices.reduce((s, p) => s + p, 0) / prices.length),
                high:    round2(prices[prices.length - 1]),
                count:   soldItems.length,
                items:   soldItems.slice(0, 10),
              };
            }
          } else {
            // Enriched path — score every candidate listing, keep probable
            // + confirmed, aggregate on confirmed only.
            const cardCtx = {
              cardNumber, hero, power,
              set:       searchParams.get("set")       || "",
              element:   searchParams.get("element")   || "",
              treatment: searchParams.get("treatment") || "",
            };
            let batch = normaliseSoldEnriched(items, cardCtx);

            // Broad-hero fallback when the narrow query turned up nothing.
            if (batch.confirmed.length === 0 && batch.probable.length === 0 && hero) {
              const fb = await searchSold(token, keywordsBroad, cutoffISO);
              if (!fb.error) batch = normaliseSoldEnriched(fb.items, cardCtx);
            }

            // Cheap structured log — visible via `wrangler tail`. Success
            // metrics doc in the handoff §9.
            console.log("[sold_match]", JSON.stringify({ cardNumber, hero, ...batch.counters }));

            const mergedForList = [...batch.confirmed, ...batch.probable]
              .sort((a, b) => (b.matchConfidence ?? 0) - (a.matchConfidence ?? 0));

            if (batch.confirmed.length + batch.probable.length > 0) {
              // Aggregates come from confirmed only — badge-only probables
              // don't skew the headline numbers.
              const aggSource = batch.confirmed.length > 0 ? batch.confirmed : batch.probable;
              const sorted    = [...aggSource].sort((a, b) => a.price - b.price);
              const prices    = sorted.map(i => i.price);
              soldSection = {
                low:            round2(prices[0]),
                average:        round2(prices.reduce((s, p) => s + p, 0) / prices.length),
                high:           round2(prices[prices.length - 1]),
                count:          batch.confirmed.length,
                count_probable: batch.probable.length,
                items:          mergedForList.slice(0, 10),
              };
            }
          }
        }
      }

      // Always fetch active (Browse API) — regardless of whether Radish had sold data.
      // Users should always be able to see cards currently for sale.
      const { items: activeRaw, error: activeErr } = await searchActive(token, keywordsSpecific);
      if (!activeErr) {
        const activeItems = await normaliseActive(activeRaw, cardNumber, hero, power, env);
        if (activeItems.length > 0) {
          const sorted = [...activeItems].sort((a, b) => a.price - b.price);
          const prices = sorted.map(i => i.price);
          activeSection = {
            low:     round2(prices[0]),
            average: round2(prices.reduce((s, p) => s + p, 0) / prices.length),
            high:    round2(prices[prices.length - 1]),
            count:   activeItems.length,
            items:   sampleAcrossRange(sorted, 10),
          };
        }
      } else {
        browseError = activeErr;
      }
    } else {
      // Token fetch failed — surface as error only if Radish also failed
      if (!soldSection) {
        return json({ error: String(tokenResult.reason), count: 0, low: 0, average: 0, high: 0, priceType: "sold", items: [] }, 502);
      }
    }

    if (!soldSection && !activeSection) {
      if (browseError) return json({ error: browseError, count: 0, low: 0, average: 0, high: 0, priceType: "sold", items: [] }, 502);
      return json({ count: 0, low: 0, average: 0, high: 0, priceType: "sold", items: [] });
    }

    // ── Build response with dual sections + legacy fields ─────────────────────
    // Legacy fields use sold data when available, else active — so old app
    // versions continue working until they're updated to read sold/active keys.
    const primary    = soldSection ?? activeSection;
    const priceType  = soldSection ? "sold" : "listed";
    const legacyItems = soldSection
      ? soldSection.items
      : sampleAcrossRange([...((activeSection?.items) ?? [])].sort((a, b) => a.price - b.price), 10);

    const result = {
      ...(soldSection   ? { sold:   soldSection }   : {}),
      ...(activeSection ? { active: activeSection } : {}),
      // Legacy backward-compat fields
      low:       primary?.low       ?? 0,
      average:   primary?.average   ?? 0,
      high:      primary?.high      ?? 0,
      count:     primary?.count     ?? 0,
      priceType,
      items:     legacyItems,
    };

    // Cache 6h if we have sold data, 2h for active-only (listings change faster)
    const cacheTTL = soldSection ? 21600 : 7200;
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
