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
async function fetchRadishHTML(url) {
  try {
    const res = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Accept":     "text/html,application/xhtml+xml",
      },
    });
    if (!res.ok) {
      // CRITICAL: drain the body even when we don't want it.
      // Cloudflare Workers warn ("stalled HTTP response was
      // canceled to prevent deadlock") and start cancelling other
      // in-flight requests when too many fetch() calls have
      // un-consumed bodies in flight at once. With the parallel
      // namespace sweep firing ~30 requests at a time and most
      // returning 404, leaking those bodies caused subsequent
      // legitimate calls (e.g. the Market Est. card_id lookup)
      // to be cancelled mid-flight — silently breaking pricing
      // for cards that should have produced an estimate.
      await res.body?.cancel();
      return null;
    }
    return await res.text();
  } catch {
    return null;
  }
}

function stripCardNumberFromRadishURL(url) {
  // Drop the last path segment so /boba/{year}/{slug}/{hero}/{num}
  // becomes /boba/{year}/{slug}/{hero}. Returns null when the URL
  // doesn't match that shape (e.g. /boba/sealed has no cardNumber).
  try {
    const u = new URL(url);
    const parts = u.pathname.split("/").filter(Boolean);
    if (parts.length < 5) return null;
    parts.pop();
    u.pathname = "/" + parts.join("/");
    return u.toString();
  } catch {
    return null;
  }
}

// Every year/slug pair Radish actually serves. Built from
// curl 'https://radishpriceguide.com/boba'. Cards in our catalog
// can live under a different (year, slug) than their `set`
// suggests — e.g. LeBoss-1 has set="Alpha Edition" in our data but
// Radish hosts him under /2025/Alpha_Update/. So when the catalog-
// hinted URL has no data, we sweep all known (year, slug) pairs.
const RADISH_NAMESPACES = [
  ["2026", "Griffey_Edition"],
  ["2025", "Alpha_Update"],
  ["2025", "Alpha_Blast"],
  ["2025", "World_Champions"],
  ["2025", "Big_League_Chew"],
  ["2025", "Promo_Cards"],
  ["2024", "Alpha_Edition"],
  ["2024", "World_Champions"],
  ["2024", "National_24_Starter_Set"],
  ["2024", "Battle_Trainer_Kit"],
  ["2024", "Promo_Cards"],
  ["2026", "Promo_Cards"],
];

async function fetchRadishSales(radishUrl, days) {
  // Walk a list of candidate URLs and pick whichever one has the
  // most useful data:
  //   - First preference: a URL with items inside the requested
  //     date window (these become the sold-comp data).
  //   - Second preference: a URL with sales aggregated but none in
  //     the window — surface the single most recent sale as a
  //     stale comp so the card still gets a price. We'd rather show
  //     a 90-day-old sale than nothing at all, since most users
  //     just want a market-value anchor.
  //   - Last resort: nothing carried any data; return null and the
  //     client falls back to its constructed URL.
  const parsed = parseRadishURL(radishUrl);
  let candidates;
  if (!parsed) {
    // Unrecognized shape (e.g. /boba/sealed). Just probe the
    // original URL once.
    candidates = [radishUrl];
  } else {
    const { hero, cardNumber, year: hintYear, slug: hintSlug } = parsed;
    // Catalog-hinted (year, slug) first, then every other namespace.
    const namespaceOrder = [
      [hintYear, hintSlug],
      ...RADISH_NAMESPACES.filter(([y, s]) => y !== hintYear || s !== hintSlug),
    ];
    // Hero-name variants. Our catalog stores hyphenated names
    // (Mean-Joe, Bell-Camp, Maxed-Out) but Radish is inconsistent —
    // some live at hyphen-form ("Mean-Joe"), some at space-form
    // ("Maxed Out"). Try both shapes. Capped at 2 variants total
    // because Cloudflare's 50-subrequest-per-invocation cap means
    // 11 namespaces × N variants × 1 cardNumber URL + 11 hero-only
    // URLs has to stay under ~45 to leave headroom for eBay calls.
    const heroVariants = Array.from(new Set([
      hero,
      hero.includes("-") ? hero.replaceAll("-", " ") : null,
      hero.includes(" ") ? hero.replaceAll(" ", "-") : null,
    ].filter(Boolean)));
    candidates = [];
    for (const [year, slug] of namespaceOrder) {
      for (const heroVariant of heroVariants) {
        const base = `https://radishpriceguide.com/boba/${year}/${slug}/${encodeURIComponent(heroVariant)}`;
        if (cardNumber) candidates.push(`${base}/${encodeURIComponent(cardNumber)}`);
      }
      // One hero-only fallback per namespace, using the canonical
      // (catalog) hero spelling. Hero pages exist whenever Radish
      // has any sales for that hero in that set, regardless of
      // which exact card_number we asked about.
      candidates.push(`https://radishpriceguide.com/boba/${year}/${slug}/${encodeURIComponent(hero)}`);
    }
  }

  // Fire every candidate probe in parallel. Sequential walk took
  // 4-5s on cold cache (11 namespaces × 2 URLs each × ~400ms),
  // which intermittently exceeded iOS's 7s URLSession timeout
  // (DeKap GGL-779, Crosbow FT-76). Stamping a 10-min negative
  // cache then meant the card stayed blank in the app even though
  // the worker would have eventually returned data. Promise.allSettled
  // collapses the wallclock cost to a single round-trip (~500ms)
  // and well under Cloudflare's 50-subrequest cap.
  const settled = await Promise.allSettled(
    candidates.map(url => tryRadishURL(url, days))
  );
  // Walk results in original priority order so the catalog-hinted
  // namespace wins ties.
  let staleBest = null;  // { item, url }
  for (let i = 0; i < candidates.length; i++) {
    const url = candidates[i];
    const s   = settled[i];
    const result = s.status === "fulfilled" ? s.value : null;
    if (!result) continue;  // 404, network error, or non-card page
    if (result.inWindow.length > 0) {
      return { items: result.inWindow, resolvedUrl: url, stale: false };
    }
    const newest = result.allItems[0];
    if (newest) {
      const newestMs = new Date(newest.date).getTime();
      if (!staleBest || newestMs > new Date(staleBest.item.date).getTime()) {
        staleBest = { item: newest, url };
      }
    }
  }
  if (staleBest) {
    return { items: [staleBest.item], resolvedUrl: staleBest.url, stale: true };
  }
  return { items: null, resolvedUrl: null, stale: false };
}

/// Pull (year, slug, hero, treatment?, cardNumber?) out of a Radish
/// card URL. Handles both legacy 4-segment shape
///   /boba/{year}/{slug}/{hero}/{cardNumber}
/// AND the current canonical 5-segment shape
///   /boba/{year}/{slug}/{hero}/{treatment}/{cardNumber}
/// Returns null when the URL doesn't match either (e.g. /boba/sealed).
///
/// The catalog now bakes canonical 5-segment URLs sourced from
/// Radish's sitemap (scripts/build_radish_url_map.py). When the
/// client sends one of those, parts.length is 6 and the cardNumber
/// is in the LAST segment, not parts[4].
function parseRadishURL(url) {
  try {
    const u = new URL(url);
    const parts = u.pathname.split("/").filter(Boolean);
    if (parts.length < 4 || parts[0] !== "boba") return null;
    const year = parts[1];
    const slug = parts[2];
    if (!/^\d{4}$/.test(year)) return null;
    const heroEnc = parts[3];
    let treatment = null;
    let cardNumberEnc = null;
    if (parts.length === 5) {
      // Legacy 4-segment shape: hero + cardNumber
      cardNumberEnc = parts[4];
    } else if (parts.length >= 6) {
      // Current canonical shape: hero + treatment + cardNumber
      treatment    = decodeURIComponent(parts[4]);
      cardNumberEnc = parts[5];
    }
    return {
      year,
      slug,
      hero:       decodeURIComponent(heroEnc),
      treatment,
      cardNumber: cardNumberEnc ? decodeURIComponent(cardNumberEnc) : null,
    };
  } catch {
    return null;
  }
}

async function tryRadishURL(url, days) {
  // Returns { inWindow, allItems } where:
  //   inWindow  — sales within the requested days window
  //   allItems  — every aggregated sale (newest-first), used to
  //               surface a stale-but-real comp when the window
  //               has nothing.
  // Returns null only when the URL itself doesn't exist or doesn't
  // carry the Next.js allSales structure.
  try {
    const html = await fetchRadishHTML(url);
    if (!html) return null;

    const match = html.match(/<script id="__NEXT_DATA__" type="application\/json">([^<]+)<\/script>/);
    if (!match) return null;

    const nextData = JSON.parse(match[1]);
    const allSales = nextData?.props?.pageProps?.allSales;
    if (!Array.isArray(allSales) || allSales.length === 0) return null;

    const visible = allSales
      .filter(s => !s.hide && s.sold_date)
      .map(s => ({
        title: s.title ?? s.card_name ?? "",
        price: parseFloat(s.price ?? "0"),
        date:  s.sold_date ?? "",
        url:   s.link ?? "",
      }))
      .filter(i => i.price > 0 && i.title);
    if (visible.length === 0) return null;

    const cutoffMs = Date.now() - days * 86400 * 1000;
    const inWindow = visible.filter(i => new Date(i.date).getTime() >= cutoffMs);
    // allItems sorted newest-first so the caller can pick [0] for
    // "most recent sale of any age."
    const allItems = [...visible].sort((a, b) =>
      new Date(b.date).getTime() - new Date(a.date).getTime()
    );
    return { inWindow, allItems };
  } catch {
    return null;
  }
}

// ── Radish Market Est. fallback ───────────────────────────────────────────────
//
// When a card has no in-window sales AND no historical sales of its
// own, Radish's UI surfaces a "Market Est." range computed from
// comparable cards (same hero / same weapon / same power, across
// other parallels and treatments). The midpoint of that range is a
// reasonable market anchor for cards that have never sold.
//
// Implementation:
//   1. Hit the Next.js static-data endpoint for the card URL to
//      learn Radish's internal integer card_id (the public
//      catalog uses card_number + hero, but the estimated-value API
//      keys on card_id).
//   2. Hit /api/boba/estimated-value?card_id={id} which returns
//      {marketEstimatedValue, marketEstimatedValueLow,
//       marketEstimatedValueHigh, marketEstimatedValueSource}.
//   3. When marketEstimatedValueSource is "comps" or "own_sales" and
//      the value is positive, return it as the estimate.
//
// The Next.js buildId rotates on every Radish redeploy, so we scrape
// it on-demand from any rendered page and cache it for 24h.

let RADISH_BUILD_ID_CACHE = { value: null, fetchedAt: 0 };
const RADISH_BUILD_ID_TTL_MS = 86400 * 1000;

async function getRadishBuildId() {
  if (
    RADISH_BUILD_ID_CACHE.value &&
    Date.now() - RADISH_BUILD_ID_CACHE.fetchedAt < RADISH_BUILD_ID_TTL_MS
  ) {
    return RADISH_BUILD_ID_CACHE.value;
  }
  // Any page works — sealed index is the lightest.
  const html = await fetchRadishHTML("https://radishpriceguide.com/boba/sealed");
  if (!html) return RADISH_BUILD_ID_CACHE.value;  // serve stale on probe failure
  const m = html.match(/"buildId":"([^"]+)"/);
  if (!m) return RADISH_BUILD_ID_CACHE.value;
  RADISH_BUILD_ID_CACHE = { value: m[1], fetchedAt: Date.now() };
  return m[1];
}

async function fetchRadishCardId(year, slug, hero, cardNumber) {
  const buildId = await getRadishBuildId();
  if (!buildId) return null;
  const path = `${encodeURIComponent(hero)}/${encodeURIComponent(cardNumber)}.json`;
  const buildUrl = (id) =>
    `https://radishpriceguide.com/_next/data/${id}/boba/${year}/${slug}/${path}`;
  try {
    let res = await fetch(buildUrl(buildId), { headers: { "User-Agent": "Mozilla/5.0" } });
    if (res.status === 404) {
      // Stale buildId is the most likely cause of a 404 on this
      // endpoint (Radish redeploys rotate the value, our 24h
      // in-memory cache lags reality). Bust the cache and refetch
      // immediately so this request still produces a card_id —
      // otherwise Market Est. silently no-ops every time the
      // buildId rotates, even though the card exists.
      await res.body?.cancel();   // drain stale 404 before reassigning
      RADISH_BUILD_ID_CACHE = { value: null, fetchedAt: 0 };
      const fresh = await getRadishBuildId();
      if (fresh && fresh !== buildId) {
        res = await fetch(buildUrl(fresh), { headers: { "User-Agent": "Mozilla/5.0" } });
      } else {
        return null;  // couldn't get a fresh buildId — give up
      }
    }
    if (!res.ok) { await res.body?.cancel(); return null; }
    const data = await res.json();
    return data?.pageProps?.card?.id ?? null;
  } catch {
    return null;
  }
}

async function fetchRadishMarketEst(radishUrl) {
  // Targeted lookup, not a sweep — Cloudflare Workers cap each
  // invocation at 50 subrequests, and `fetchRadishSales` already
  // burned a chunk walking every namespace. Just probe the single
  // (year, slug, hero, cardNumber) tuple the caller passes in. If
  // the caller needs to retry under a different namespace, they
  // should call us again with the corrected URL.
  const parsed = parseRadishURL(radishUrl);
  if (!parsed) return null;
  const { hero, cardNumber, year, slug } = parsed;
  if (!cardNumber) return null;  // hero-only URLs don't map to a card_id

  const cardId = await fetchRadishCardId(year, slug, hero, cardNumber);
  if (!cardId) return null;
  try {
    const apiUrl = `https://radishpriceguide.com/api/boba/estimated-value?card_id=${cardId}`;
    const res = await fetch(apiUrl, { headers: { "User-Agent": "Mozilla/5.0" } });
    if (!res.ok) { await res.body?.cancel(); return null; }
    const json = await res.json();
    const value  = parseFloat(json?.marketEstimatedValue ?? "0");
    const low    = parseFloat(json?.marketEstimatedValueLow ?? "0");
    const high   = parseFloat(json?.marketEstimatedValueHigh ?? "0");
    const source = json?.marketEstimatedValueSource ?? null;
    if (!source || !(value > 0 || (low > 0 && high > 0))) return null;
    // Prefer the explicit `marketEstimatedValue` (Radish's chosen
    // mid). Fall back to (low+high)/2 when the API returned a range
    // but no single mid value.
    const mid = value > 0 ? value : (low + high) / 2;
    return {
      mid:     round2(mid),
      low:     low > 0  ? round2(low)  : round2(mid),
      high:    high > 0 ? round2(high) : round2(mid),
      source,  // "comps" | "own_sales"
      resolvedUrl: `https://radishpriceguide.com/boba/${year}/${slug}/${encodeURIComponent(hero)}/${encodeURIComponent(cardNumber)}`,
    };
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

/** Stage A pipeline endpoint: search eBay by free-text query and
 *  return a small JSON array of {itemId, imageUrl, title, viewItemURL}
 *  per match. Used by pipeline/scripts/stage_a_scrape_ebay.py — eBay
 *  blocks GH Actions runner IPs from HTML scrape, so the pipeline
 *  routes through this Worker which already has Browse API
 *  credentials.
 *
 *  GET /scrape-ebay?q=<query>&limit=<N>   (default N=5, max 20)
 */
async function handleScrapeEbay(request, env) {
  if (!env.EBAY_APP_ID || !env.EBAY_CERT_ID) {
    return json({ error: "EBAY_APP_ID and EBAY_CERT_ID secrets required" }, 500);
  }
  const url = new URL(request.url);
  const q   = (url.searchParams.get("q") || "").trim();
  if (!q) return json({ error: "q parameter required" }, 400);
  const limit = Math.min(20, Math.max(1, parseInt(url.searchParams.get("limit") ?? "5", 10)));

  let token;
  try {
    token = await getAppToken(env, caches.default);
  } catch (e) {
    return json({ error: `oauth: ${e.message || e}` }, 500);
  }

  const params = new URLSearchParams({
    q,
    filter: "buyingOptions:{FIXED_PRICE|AUCTION},itemLocationCountry:US",
    limit:  String(limit),
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
    return json({ error: msg, items: [] }, 502);
  }

  const data = await res.json();
  const items = (data.itemSummaries ?? []).map(it => ({
    itemId:       it.itemId,
    title:        it.title,
    imageUrl:     it.image?.imageUrl ?? null,
    viewItemURL:  it.itemWebUrl,
  })).filter(x => x.imageUrl && x.itemId);

  return json({ items, query: q }, 200);
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
    // Two parallel AI calls: (1) structured JSON with bboxes for the
    // top-left scope + per-region matching the iOS Vision pipeline
    // does natively; (2) flat transcript as a backstop in case the
    // structured model returns malformed JSON. The flat-text path is
    // also what the client falls back to when regions parse fails.
    const [structuredResult, transcriptResult] = await Promise.all([
      env.AI.run(MODEL, {
        messages: [{ role: "user", content: [
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${image}` } },
          { type: "text", text: `Identify every text region visible on this trading card. For EACH region, return its text and its approximate location as a fraction of the image (0.0–1.0 for both axes, where (0,0) is top-left and (1,1) is bottom-right).

Return ONLY a JSON array, no prose, no markdown fences. Schema:
[
  {"text": "exact text as printed", "x": 0.12, "y": 0.05, "w": 0.4, "h": 0.05},
  ...
]

Include card name, hero name, card number, power value, ability text, set/treatment markings, and any other printed text. Use 6 decimal places of precision.` },
        ]}],
        max_tokens: 1024,
      }),
      env.AI.run(MODEL, {
        messages: [{ role: "user", content: [
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${image}` } },
          { type: "text", text: "Transcribe every piece of text you can see in this image. Include all letters, numbers, words, and codes exactly as printed. Return only the raw text, nothing else." },
        ]}],
        max_tokens: 256,
      }),
    ]);

    const rawText   = String(transcriptResult?.response ?? transcriptResult?.description ?? transcriptResult ?? "").trim();
    const structuredText = String(structuredResult?.response ?? structuredResult?.description ?? structuredResult ?? "").trim();

    // Best-effort parse of the structured response. Strip markdown
    // fences (the model wraps in ```json…``` despite the prompt) and
    // any leading prose; locate the outer [ … ] array.
    let regions = [];
    try {
      let s = structuredText;
      // Strip code fences
      s = s.replace(/```(?:json)?\s*/gi, "").replace(/```\s*$/g, "");
      // Find array bounds
      const start = s.indexOf("[");
      const end   = s.lastIndexOf("]");
      if (start >= 0 && end > start) {
        const arr = JSON.parse(s.slice(start, end + 1));
        if (Array.isArray(arr)) {
          regions = arr
            .filter(r => r && typeof r.text === "string" && r.text.trim().length > 0)
            .map(r => ({
              text: String(r.text).trim(),
              x: clampFrac(r.x), y: clampFrac(r.y),
              w: clampFrac(r.w, 0), h: clampFrac(r.h, 0),
            }));
        }
      }
    } catch { /* fall through to rawText-only path on client */ }

    const CARD_RE   = /[A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?/gi;
    const candidates = [...rawText.matchAll(CARD_RE)].map(m => m[0].toUpperCase());

    // Build top-left scope text from bbox-tagged regions. iOS uses
    // Vision rect filtering to pull text from the literal top-left
    // quadrant; the structured response makes the same thing
    // available to the web client.
    const topLeftRegions = regions.filter(r => r.x < 0.55 && r.y < 0.45);
    const topLeftText = topLeftRegions.map(r => r.text).join(" ").trim();

    return json({
      cardNumber: candidates[0] ?? null,
      candidates,
      rawText,
      regions,           // new — bbox-tagged text regions
      topLeftText,       // new — extracted for client convenience
    });
  } catch (err) {
    return json({ error: String(err), cardNumber: null, candidates: [] }, 500);
  }
}

function clampFrac(v, defaultVal = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return defaultVal;
  return Math.max(0, Math.min(1, n));
}

// ── Radish URL resolver (sitemap-driven, edge-cached) ────────────────────────
//
// Single source of truth for Radish URL construction. Clients NEVER
// hardcode Radish URL templates — they call /radish-url with the
// catalog tuple (set, hero, cardNumber) and get back the canonical
// URL. When Radish changes shape (4-segment → 5-segment, hero-casing
// drift, whatever's next), only this Worker needs an update; the
// edge cache evicts on the next miss and all clients get the new
// shape on next launch.
//
// Storage strategy: pure Cloudflare edge cache (caches.default).
// First call after expiry fetches Radish's sitemap.xml (~4 MB),
// parses every 5-segment URL into a {key → URL} map, and stuffs
// the JSON back into the cache with a 7-day TTL. Subsequent calls
// hit cache and do a single hashmap lookup.
//
// Lookup key: `{year}/{slug}/{lower(hero)}/{lower(cardnum)}`. The
// lowercase normalization means every drift dimension we've found
// (RAD vs Rad, ChetMate vs Chetmate, etc.) resolves to the SAME
// key — Radish's sitemap entry is the canonical answer regardless
// of input casing.

const RADISH_SITEMAP_URL = "https://radishpriceguide.com/sitemap.xml";
const RADISH_MAP_CACHE_TTL = 7 * 24 * 3600;  // 7 days

// Catalog set name → (year, slug). Mirrors SET_MAP on iOS / web /
// scripts/apply_radish_urls.py. The ONLY hardcoded thing in this
// pipeline that isn't auto-derived from Radish's sitemap.
const SET_TO_NAMESPACE = {
  "Alpha":                          ["2024", "Alpha_Edition"],
  "Alpha Edition":                  ["2024", "Alpha_Edition"],
  "Alpha Update":                   ["2025", "Alpha_Update"],
  "Alpha Blast":                    ["2025", "Alpha_Blast"],
  "Griffey":                        ["2026", "Griffey_Edition"],
  "Griffey Edition":                ["2026", "Griffey_Edition"],
  "National Starter Set":           ["2024", "National_24_Starter_Set"],
  "2024 National Show Starter Set": ["2024", "National_24_Starter_Set"],
  "National '24":                   ["2024", "National_24_Starter_Set"],
  "National 24 Starter Set":        ["2024", "National_24_Starter_Set"],
  "World Champions":                ["2024", "World_Champions"],
  "World Champions 2024":           ["2024", "World_Champions"],
  "World Champions 2025":           ["2025", "World_Champions"],
  "Battle Trainer Kit":             ["2024", "Battle_Trainer_Kit"],
  "Superfan Series":                ["2024", "Superfan_Series"],
  "Promo Cards":                    ["2025", "Promo_Cards"],
  "Big League Chew":                ["2025", "Big_League_Chew"],
  "Tecmo Bowl Edition":             ["2025", "Tecmo_Bowl"],
};

/// Fetch + parse Radish's sitemap. Returns a JSON-serializable
/// lookup object. Pure function — no side effects.
async function fetchRadishURLMap() {
  const res = await fetch(RADISH_SITEMAP_URL, {
    headers: { "User-Agent": "Mozilla/5.0 (BOBA Playbook Worker)" },
  });
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`Sitemap fetch failed: ${res.status}`);
  }
  const xml = await res.text();
  const locRegex = /<loc>([^<]+)<\/loc>/g;
  const map = {};
  const byHeroCardnum = {};   // (lower_hero, lower_cardnum) → first URL across any namespace
  const namespaces = new Set();
  let total = 0;
  let m;
  while ((m = locRegex.exec(xml)) !== null) {
    const u = m[1];
    const idx = u.indexOf("/boba/");
    if (idx < 0) continue;
    const parts = u.slice(idx + 6).split("/");
    if (parts.length !== 5) continue;  // only canonical 5-segment URLs
    let year, slug, heroEnc, _treatmentEnc, cardnumEnc;
    [year, slug, heroEnc, _treatmentEnc, cardnumEnc] = parts;
    try {
      year = decodeURIComponent(year);
      slug = decodeURIComponent(slug);
      const hero = decodeURIComponent(heroEnc);
      const cardnum = decodeURIComponent(cardnumEnc);
      const key = `${year}/${slug}/${hero.toLowerCase()}/${cardnum.toLowerCase()}`;
      if (!(key in map)) {
        map[key] = u;
        total++;
      }
      const hcKey = `${hero.toLowerCase()}/${cardnum.toLowerCase()}`;
      if (!(hcKey in byHeroCardnum)) byHeroCardnum[hcKey] = u;
      namespaces.add(`${year}/${slug}`);
    } catch { /* skip malformed URI */ }
  }
  return {
    builtAt: new Date().toISOString(),
    source: RADISH_SITEMAP_URL,
    totalUrls: total,
    namespaces: Array.from(namespaces).sort(),
    map,
    byHeroCardnum,
  };
}

/// Edge-cached wrapper. First call after TTL expiry refetches.
async function getRadishURLMap() {
  const cache = caches.default;
  const cacheKey = new Request("https://boba-cache.internal/radish-url-map/v1");
  const cached = await cache.match(cacheKey);
  if (cached) return cached.json();
  const data = await fetchRadishURLMap();
  await cache.put(cacheKey, new Response(JSON.stringify(data), {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": `public, max-age=${RADISH_MAP_CACHE_TTL}`,
    },
  }));
  return data;
}

/// GET /radish-url?set=&hero=&cardNumber= → {url, namespace, lookup}
async function handleRadishURL(request) {
  const { searchParams } = new URL(request.url);
  const setField   = (searchParams.get("set")        || "").trim();
  const hero       = (searchParams.get("hero")       || "").trim();
  const cardNumber = (searchParams.get("cardNumber") || "").trim();
  if (!hero || !cardNumber) {
    return json({ error: "hero + cardNumber required" }, 400);
  }
  let data;
  try {
    data = await getRadishURLMap();
  } catch (err) {
    return json({ error: `sitemap unavailable: ${err.message}` }, 502);
  }
  const lhero = hero.toLowerCase();
  const lcn   = cardNumber.toLowerCase();

  // Primary lookup: use the catalog set → namespace map.
  const ns = SET_TO_NAMESPACE[setField];
  if (ns) {
    const [year, slug] = ns;
    const url = data.map[`${year}/${slug}/${lhero}/${lcn}`];
    if (url) return json({ url, namespace: `${year}/${slug}`, lookup: "primary" });
  }

  // Cross-namespace fallback: same (hero, cardnum) lives at a different (year, slug).
  const crossUrl = data.byHeroCardnum[`${lhero}/${lcn}`];
  if (crossUrl) {
    return json({ url: crossUrl, namespace: null, lookup: "cross-namespace" });
  }

  // Hero-page fallback: at least direct to the hero index.
  if (ns) {
    return json({
      url: `https://radishpriceguide.com/boba/${ns[0]}/${ns[1]}/${encodeURIComponent(hero)}`,
      namespace: `${ns[0]}/${ns[1]}`,
      lookup: "hero-only",
    });
  }
  return json({ error: "no match", lookup: "none" }, 404);
}

/// GET /radish-url-map → the full lookup table (for offline catalog
/// bake / batch refresh). Cached at edge for 7 days; clients should
/// also cache locally.
async function handleRadishURLMapDump(_request) {
  try {
    const data = await getRadishURLMap();
    return json({
      builtAt: data.builtAt,
      source: data.source,
      totalUrls: data.totalUrls,
      namespaces: data.namespaces,
      map: data.map,
    }, 200, { "Cache-Control": `public, max-age=${RADISH_MAP_CACHE_TTL}` });
  } catch (err) {
    return json({ error: `sitemap unavailable: ${err.message}` }, 502);
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
    if (request.method === "GET"  && url.pathname.endsWith("/whatnot/upcoming")) return handleWhatnotUpcoming(request, env);
    if (request.method === "GET"  && url.pathname.endsWith("/scrape-ebay"))      return handleScrapeEbay(request, env);
    if (request.method === "GET"  && url.pathname.endsWith("/radish-url"))       return handleRadishURL(request);
    if (request.method === "GET"  && url.pathname.endsWith("/radish-url-map"))   return handleRadishURLMapDump(request);
    const { searchParams } = url;
    const cardNumber = searchParams.get("cardNumber");
    const hero       = searchParams.get("hero") || "";
    const powerRaw   = searchParams.get("power");
    const power      = powerRaw != null ? parseInt(powerRaw, 10) : null;
    const days       = Math.min(Math.max(parseInt(searchParams.get("days") ?? "30", 10), 1), 90);
    const radishUrl  = searchParams.get("radishUrl") || "";
    /// User-initiated refresh: when the client passes `fresh=1`, skip
    /// the cache lookup AND don't write a fresh cached entry — so the
    /// next click of the day-picker for the same card hits a clean
    /// fetch instead of the stale cache the refresh tried to bypass.
    const forceFresh = searchParams.get("fresh") === "1";

    if (!cardNumber) return json({ error: "cardNumber parameter required" }, 400);
    if (!env.EBAY_APP_ID || !env.EBAY_CERT_ID) return json({ error: "EBAY_APP_ID and EBAY_CERT_ID secrets required" }, 500);

    // ── Cache ─────────────────────────────────────────────────────────────────
    // v17: Cloudflare's stalled-HTTP-response auto-cancel was
    // killing the Radish card_id lookup mid-flight when ~33
    // parallel namespace probes leaked their 404 bodies. Now we
    // drain bodies on every non-200 (await res.body?.cancel()),
    // so Market Est. actually reaches the API. Plus a one-shot
    // buildId-rotation retry. v16 caches lock in the old broken
    // responses (NO_DATA where there should be data), so a
    // version bump is the only way to evict.
    const cache    = caches.default;
    const cacheURL = `https://boba-cache.internal/v17/${encodeURIComponent(hero)}/${encodeURIComponent(cardNumber)}/${days}`;
    const cacheKey = new Request(cacheURL);
    if (!forceFresh) {
      const cached = await cache.match(cacheKey);
      if (cached) {
        const body = await cached.json();
        return json(body, 200, { "X-Cache": "HIT" });
      }
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
    let radishResolvedUrl = null;
    const radishPayload = radishResult.status === "fulfilled" ? radishResult.value : null;
    const radishItems = radishPayload?.items ?? null;
    const radishStale = radishPayload?.stale ?? false;
    radishResolvedUrl = radishPayload?.resolvedUrl ?? null;
    if (radishItems && radishItems.length > 0) {
      const sorted = [...radishItems].sort((a, b) => a.price - b.price);
      const prices = sorted.map(i => i.price);
      soldSection = {
        low:     round2(prices[0]),
        average: round2(prices.reduce((s, p) => s + p, 0) / prices.length),
        high:    round2(prices[prices.length - 1]),
        count:   radishItems.length,
        items:   radishItems.slice(0, 10),   // already newest-first from fetchRadishSales
        // When stale=true the only "comp" is a single sale older than
        // `days`. UI surfaces it as "Last sold {date}" instead of the
        // window-based average copy, since one stale sale is not
        // really a 30-day average.
        ...(radishStale ? { stale: true } : {}),
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
      // Token fetch failed — soldSection might still come from Radish
      // sales or, below, Market Est. Don't bail yet; let the Market
      // Est. fallback have a shot at producing a number.
    }

    // ── Market Est. fallback (final tier) ─────────────────────────────────────
    // Reached when neither Radish sales (in-window or stale) nor
    // eBay sold history produced a soldSection. This is the third
    // tier of the price waterfall: Radish sales → eBay sold →
    // Radish Market Est. (range computed from comparable cards on
    // Radish's side). Better to ship a comp-based estimate than no
    // number at all, since most users just want a market anchor.
    if (!soldSection && radishUrl) {
      try {
        // Prefer the namespace fetchRadishSales already validated
        // (radishResolvedUrl) — that's where a real Radish card page
        // exists, so the card_id lookup lands on the first try. Falls
        // back to the catalog-hinted URL when the sweep didn't
        // validate any namespace. Targeted single-namespace lookup
        // keeps us under Cloudflare's 50-subrequest cap.
        const probeUrl = radishResolvedUrl || radishUrl;
        const est = await fetchRadishMarketEst(probeUrl);
        if (est && est.mid > 0) {
          soldSection = {
            low:     est.low,
            average: est.mid,
            high:    est.high,
            count:   0,
            items:   [],
            estimated: true,
            estimatedSource: est.source,
          };
          if (!radishResolvedUrl) radishResolvedUrl = est.resolvedUrl;
        }
      } catch {
        // Estimate is best-effort. Silent failure preserves the
        // active-only path below.
      }
    }

    if (!soldSection && !activeSection) {
      if (browseError) return json({ error: browseError, count: 0, low: 0, average: 0, high: 0, priceType: "sold", items: [] }, 502);
      // Token-fetch failure is only fatal if every other tier also
      // failed (Radish sales, eBay sold, Market Est., active listings).
      if (tokenResult.status !== "fulfilled") {
        return json({ error: String(tokenResult.reason), count: 0, low: 0, average: 0, high: 0, priceType: "sold", items: [] }, 502);
      }
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
      // The Radish URL that actually carried data — clients use this
      // for the "Radish Guide" button so it lands on a page with
      // listings rather than a 200-OK shell with no comps. Null
      // when neither the primary nor the hero-only fallback had any
      // sales (the client falls back to its own constructed URL).
      ...(radishResolvedUrl ? { radishResolvedUrl } : {}),
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

/* ════════════════════════════════════════════════════════════════════
 * WHATNOT UPCOMING SHOWS — three-layer extractor over the public
 * search HTML at https://www.whatnot.com/search?searchVertical=LIVESTREAM.
 * Spec + reference patterns: handoff-updates-2026-04-27/whatnot-shows-worker.
 *
 * Routes:
 *   GET /whatnot/upcoming?query=...&status=CREATED|LIVE
 *
 * Returns:
 *   { query, status, count, fetchedAtIso, shows: [WhatnotShow] }
 *
 * Extraction layers (one suffices most of the time, three combined is
 * resilient to Whatnot template tweaks):
 *   1. DOM regex on /live/{uuid} anchor pairs (always runs)
 *   2. Apollo SSR streaming pushes (rich data: viewer count, time)
 *   3. __NEXT_DATA__ script tag (currently absent; kept as fallback)
 * ════════════════════════════════════════════════════════════════════ */

const WHATNOT_BASE = "https://www.whatnot.com";
const WHATNOT_HEADERS = {
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

const WHATNOT_CACHE_TTL = 5 * 60; // 5 minutes — shows update slowly

async function handleWhatnotUpcoming(request, _env) {
  const url   = new URL(request.url);
  const query = url.searchParams.get("query")  || "bo Jackson battle arena";
  // Default includes BOTH live and upcoming so the Purchase view shows
  // streams that are happening right now alongside the upcoming feed.
  // Override with ?status=CREATED or ?status=PLAYING for one or the
  // other; comma-separated for an explicit list.
  const rawStatus = (url.searchParams.get("status") || "CREATED,PLAYING").toUpperCase();
  const statuses = rawStatus.split(",").map(s => s.trim()).filter(Boolean);

  const debug = url.searchParams.get("debug") === "1";

  // Edge cache (skipped when debug=1 so we can iterate)
  const cache = caches.default;
  const cacheKey = new Request(
    `https://boba-cache.internal/whatnot/v4/${encodeURIComponent(statuses.join(","))}/${encodeURIComponent(query.toLowerCase())}`,
    { method: "GET" }
  );
  if (!debug) {
    const hit = await cache.match(cacheKey);
    if (hit) {
      const body = await hit.json();
      return json(body, 200, { "X-Cache": "HIT" });
    }
  }

  // Whatnot's search results are paginated at ~24 shows per page. If
  // we ask for [CREATED, PLAYING] in one call and there are 25+ live
  // shows, the upcoming ones get pushed off the first page entirely.
  // Fetch each status sequentially and merge so we always see both
  // live + upcoming. (Parallel fetches of the same external host can
  // race on Whatnot's anti-bot heuristics; sequential is reliable.)
  const seen = new Map();
  const fetchErrors = [];
  // Live ("PLAYING") shows in Whatnot's search match by tag/category
  // not just title — so a "BoBA Singles" tag pulls in shows whose
  // titles never mention BoBA. Tighten the filter so live results
  // must include the BoBA name in the title; CREATED results are
  // already author-keyword specific and don't need the filter.
  const titleNeedles = ["bo jackson battle arena", "boba"];
  const matchesTitleFilter = (s) => {
    const t = (s.title || "").toLowerCase();
    return titleNeedles.some(n => t.includes(n));
  };
  for (const s of statuses) {
    const url = buildWhatnotSearchUrl(query, [s]);
    try {
      const resp = await fetch(url, { headers: WHATNOT_HEADERS, redirect: "follow" });
      if (!resp.ok) { fetchErrors.push({ status: s, code: resp.status }); continue; }
      const html = await resp.text();
      const extracted = whatnotExtractShows(html, query);
      const isLiveStatus = s === "PLAYING";
      for (const item of extracted) {
        if (seen.has(item.showId)) continue;
        if (isLiveStatus && !matchesTitleFilter(item)) continue;
        seen.set(item.showId, item);
      }
    } catch (err) {
      fetchErrors.push({ status: s, error: err.message });
    }
  }
  const shows = Array.from(seen.values());
  // Re-sort the merged list with the same rules
  // (live first, then by viewer count, then upcoming by start time).
  shows.sort((a, b) => {
    if (a.isLive && !b.isLive) return -1;
    if (!a.isLive && b.isLive) return 1;
    if (a.isLive && b.isLive) return (b.viewerCount || 0) - (a.viewerCount || 0);
    if (a.startTimeMs && b.startTimeMs) return a.startTimeMs - b.startTimeMs;
    if (a.startTimeMs) return -1;
    if (b.startTimeMs) return 1;
    return 0;
  });
  const payload = {
    query,
    status: statuses.join(","),
    count: shows.length,
    fetchedAtIso: new Date().toISOString(),
    shows,
    fetchErrors: fetchErrors.length ? fetchErrors : undefined,
  };

  const respBody = json(payload, 200, {
    "Cache-Control": `public, max-age=${WHATNOT_CACHE_TTL}`,
  });
  // Stash in edge cache for the next caller.
  try {
    await cache.put(cacheKey, respBody.clone());
  } catch (_) { /* edge cache write failures are non-fatal */ }
  return respBody;
}

function buildWhatnotSearchUrl(query, statuses) {
  // statuses is an array; Whatnot accepts multiple values per filter.
  const arr = Array.isArray(statuses) ? statuses : [statuses];
  const filter = encodeURIComponent(JSON.stringify([{ field: "status", values: arr }]));
  return `${WHATNOT_BASE}/search?query=${encodeURIComponent(query)}&searchVertical=LIVESTREAM&referringSource=typed&filter=${filter}`;
}

// ─── Extraction ──────────────────────────────────────────────────────

const WN_THUMB_RE =
  /<a[^>]*href="(\/live\/([a-f0-9-]{36}))"[^>]*>[\s\S]{0,1500}?<img[^>]*alt="Thumbnail for live show"[^>]*>/gi;
const WN_TITLE_RE =
  /<a[^>]*href="\/live\/([a-f0-9-]{36})"[^>]*>[\s\S]{0,400}?<(?:strong|span)[^>]*>([^<]{4,300})<\/(?:strong|span)>/gi;
const WN_HOST_NEAR_SHOW_RE =
  /<a[^>]*href="\/user\/([A-Za-z0-9_-]+)"[^>]*>[\s\S]{0,2500}?<a[^>]*href="\/live\/([a-f0-9-]{36})"/gi;
const WN_APOLLO_PUSH_RE =
  /ApolloSSRDataTransport[^;]{0,200}?\.push\(\s*(\{)/g;
const WN_NEXT_DATA_RE =
  /<script[^>]*id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/;

function whatnotExtractShows(html, query) {
  const byId = new Map();

  // Layer 1: anchor pairs
  for (const m of html.matchAll(WN_THUMB_RE)) {
    const showId = m[2];
    if (!byId.has(showId)) {
      byId.set(showId, { showId, showUrl: `${WHATNOT_BASE}/live/${showId}` });
    }
  }
  for (const m of html.matchAll(WN_TITLE_RE)) {
    const showId = m[1];
    const cur = byId.get(showId);
    if (cur && !cur.title) cur.title = wnDecodeHtml(m[2]).trim();
  }
  for (const m of html.matchAll(WN_HOST_NEAR_SHOW_RE)) {
    const host = m[1];
    const showId = m[2];
    const cur = byId.get(showId);
    if (cur && !cur.host) {
      cur.host = host;
      cur.hostUrl = `${WHATNOT_BASE}/user/${host}`;
    }
  }

  // Layer 2: Apollo SSR pushes
  whatnotEnrichFromApolloPushes(html, byId);

  // Layer 3: __NEXT_DATA__
  whatnotEnrichFromNextData(html, byId);

  // Per-card sweep around each anchor for time / viewer / category /
  // thumbnail.
  whatnotEnrichFromDomNeighborhood(html, byId);

  // Finalize
  const fetchedAtIso = new Date().toISOString();
  const shows = [];
  for (const partial of byId.values()) {
    if (!partial.showId || !partial.title) continue;
    // Derive the human-readable time string from startTimeMs when the
    // Apollo data gave it to us; fall back to whatever DOM scrape
    // produced (rare).
    let timeText = partial.scheduledTimeText || "";
    if (!timeText && partial.startTimeMs) {
      timeText = whatnotFormatRelativeTime(new Date(partial.startTimeMs));
    }
    shows.push({
      showId:            partial.showId,
      showUrl:           partial.showUrl || `${WHATNOT_BASE}/live/${partial.showId}`,
      title:             partial.title,
      host:              partial.host || "",
      hostUrl:           partial.hostUrl || "",
      status:            (partial.status || "").toUpperCase(), // CREATED | PLAYING
      isLive:            (partial.status || "").toUpperCase() === "PLAYING",
      scheduledTimeText: timeText,
      scheduledTimeIso:  partial.scheduledTimeIso || null,
      startTimeMs:       partial.startTimeMs || null,
      viewerCount:       partial.viewerCount ?? 0,
      categoryName:      partial.categoryName || "",
      categorySlug:      partial.categorySlug || "",
      tags:              partial.tags || [],
      thumbnailUrl:      partial.thumbnailUrl || "",
      source:            "whatnot-search",
      query,
      fetchedAtIso,
    });
  }
  // Sort: LIVE shows first (descending by viewers, popular ones up
  // top), then upcoming sorted soonest-first.
  shows.sort((a, b) => {
    if (a.isLive && !b.isLive) return -1;
    if (!a.isLive && b.isLive) return 1;
    if (a.isLive && b.isLive) return (b.viewerCount || 0) - (a.viewerCount || 0);
    if (a.startTimeMs && b.startTimeMs) return a.startTimeMs - b.startTimeMs;
    if (a.startTimeMs) return -1;
    if (b.startTimeMs) return 1;
    return (a.scheduledTimeText || "~").localeCompare(b.scheduledTimeText || "~");
  });
  return shows;
}

function whatnotEnrichFromApolloPushes(html, byId) {
  for (const m of html.matchAll(WN_APOLLO_PUSH_RE)) {
    const start = m.index + m[0].length - 1;
    const end = wnFindMatchingBrace(html, start);
    if (end <= start) continue;
    const raw = html.slice(start, end + 1);
    const obj = wnParseLooseJson(raw);
    if (!obj) continue;
    wnWalkShowNodes(obj, (node) => {
      const id = wnPickShowId(node);
      if (!id) return;
      const cur = byId.get(id);
      if (!cur) return;

      // Title from the LiveStream node.
      if (!cur.title) cur.title = wnPickString(node, ["title"]) || cur.title;

      // Status — LIVE shows render differently in the UI (red dot,
      // "LIVE NOW" pill, current viewer count instead of interested).
      if (!cur.status) cur.status = wnPickString(node, ["status"]) || "";

      // Host: nested under `user`. Fall back to `seller` if Whatnot
      // ever renames the field.
      if (!cur.host) {
        const user = node.user || node.seller || node.host;
        const handle = user && wnPickString(user, ["username", "handle", "slug"]);
        if (handle) {
          cur.host = handle;
          cur.hostUrl = `${WHATNOT_BASE}/user/${handle}`;
        }
      }

      // Thumbnail: nested under `thumbnail` with biggerImage / smallImage.
      if (!cur.thumbnailUrl) {
        const t = node.thumbnail;
        if (t && typeof t === "object") {
          cur.thumbnailUrl = t.biggerImage || t.smallImage || t.url || cur.thumbnailUrl;
        } else {
          cur.thumbnailUrl = wnPickImageUrl(node) || cur.thumbnailUrl;
        }
      }

      // Start time — Unix epoch milliseconds. Convert to ISO + a
      // human-readable label in user-local terms (we use UTC-anchored
      // ISO and let the client format).
      if (!cur.startTimeMs) {
        const startMs = wnPickInt(node, ["startTime", "startsAt", "scheduledStart"]);
        if (startMs && startMs > 1_000_000_000_000) {
          // milliseconds — store both for the client
          cur.startTimeMs = startMs;
          cur.scheduledTimeIso = new Date(startMs).toISOString();
        } else if (startMs && startMs > 1_000_000_000) {
          // seconds (defensive — older schema)
          cur.startTimeMs = startMs * 1000;
          cur.scheduledTimeIso = new Date(startMs * 1000).toISOString();
        }
      }

      // Viewer count — for upcoming shows this is the watchlist
      // (interested) count, for live shows it's the active viewers.
      if (!cur.viewerCount) {
        const isLive = (cur.status || "").toUpperCase() === "PLAYING";
        const watchlist = wnPickInt(node, ["totalWatchlistUsers"]);
        const active    = wnPickInt(node, ["activeViewers", "currentViewers"]);
        cur.viewerCount = isLive ? (active || watchlist || 0) : (watchlist || active || 0);
      }

      // Category — `categoryNodes[0].label` is the most consistent.
      if (!cur.categoryName) {
        const nodes = node.livestreamCategories || node.categoryNodes;
        if (Array.isArray(nodes) && nodes.length) {
          const first = nodes[0];
          cur.categoryName = wnPickString(first, ["label", "name"]) || "";
          cur.categorySlug = wnPickString(first, ["type", "slug"]) || "";
        }
      }

      // Tags — `tags[].label`.
      if (!cur.tags?.length) {
        const t = node.tags;
        if (Array.isArray(t)) {
          cur.tags = t.map(x => wnPickString(x, ["label", "name"])).filter(Boolean);
        }
      }
    });
  }
}

// Format a JS Date (UTC) into a Whatnot-style "Today / Tomorrow /
// Wed 6:30 PM" string in America/Los_Angeles local time. The Worker
// produces this so the client doesn't have to know Whatnot's
// rendering convention.
function whatnotFormatRelativeTime(date) {
  if (!(date instanceof Date) || isNaN(date.getTime())) return "";
  const tz = "America/Los_Angeles";
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: tz, weekday: "short", month: "short", day: "numeric",
    hour: "numeric", minute: "2-digit", year: "numeric",
  });
  const parts = {};
  for (const p of dtf.formatToParts(date)) parts[p.type] = p.value;
  // "Now" parts in same TZ for relative-day classification.
  const nowParts = {};
  const ndtf = new Intl.DateTimeFormat("en-US", {
    timeZone: tz, weekday: "short", month: "short", day: "numeric", year: "numeric",
  });
  for (const p of ndtf.formatToParts(new Date())) nowParts[p.type] = p.value;

  const dateKey = `${parts.year}-${parts.month}-${parts.day}`;
  const nowKey  = `${nowParts.year}-${nowParts.month}-${nowParts.day}`;
  const tmrw = new Date(Date.now() + 86400000);
  const tparts = {};
  for (const p of ndtf.formatToParts(tmrw)) tparts[p.type] = p.value;
  const tmrwKey = `${tparts.year}-${tparts.month}-${tparts.day}`;

  const time = `${parts.hour}:${parts.minute} ${parts.dayPeriod || ""}`.trim();
  if (dateKey === nowKey)  return `Today ${time}`;
  if (dateKey === tmrwKey) return `Tomorrow ${time}`;
  // Within 7 days → weekday; else month-day
  const diffDays = Math.floor((date.getTime() - Date.now()) / 86400000);
  if (diffDays >= 0 && diffDays < 7) return `${parts.weekday} ${time}`;
  return `${parts.month} ${parts.day} ${time}`;
}

function whatnotEnrichFromNextData(html, byId) {
  const m = WN_NEXT_DATA_RE.exec(html);
  if (!m) return;
  const data = wnParseLooseJson(m[1]);
  if (!data) return;
  wnWalkShowNodes(data, (node) => {
    const id = wnPickShowId(node);
    if (!id) return;
    const cur = byId.get(id) || {};
    if (!cur.showId) cur.showId = id;
    if (!cur.title)  cur.title  = wnPickString(node, ["title"]) || cur.title;
    byId.set(id, cur);
  });
}

function whatnotEnrichFromDomNeighborhood(html, byId) {
  for (const [showId, cur] of byId.entries()) {
    const idx = html.indexOf(`/live/${showId}`);
    if (idx < 0) continue;
    const win = html.slice(Math.max(0, idx - 500), idx + 3000);

    if (!cur.scheduledTimeText) {
      const t = /(?:Today|Tomorrow|Yesterday|Mon|Tue|Wed|Thu|Fri|Sat|Sun|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}(?::\d{2})?\s*(?:AM|PM)?/i.exec(win);
      if (t) cur.scheduledTimeText = t[0].trim();
    }
    if (!cur.viewerCount) {
      const v = /Bookmark this show[\s\S]{0,500}?<span[^>]*>(\d{1,5})<\/span>/i.exec(win);
      if (v) cur.viewerCount = parseInt(v[1], 10);
    }
    if (!cur.categoryName) {
      const c = /<a[^>]*href="\/tag\/([^"]+)"[^>]*>[\s\S]{0,200}?<(?:strong|span)[^>]*>([^<]+)<\/(?:strong|span)>/i.exec(win);
      if (c) {
        cur.categorySlug = c[1];
        cur.categoryName = wnDecodeHtml(c[2]).trim();
      }
    }
    if (!cur.thumbnailUrl) {
      const i = /<img[^>]*alt="Thumbnail for live show"[^>]*src(?:set)?="([^"]+)"/i.exec(win);
      if (i) cur.thumbnailUrl = wnPickHighestSrc(i[1]);
    }
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────

function wnFindMatchingBrace(s, start) {
  if (s[start] !== "{") return -1;
  let depth = 0, i = start, inStr = false, quote = "";
  while (i < s.length) {
    const ch = s[i];
    if (inStr) {
      if (ch === "\\") { i += 2; continue; }
      if (ch === quote) inStr = false;
    } else {
      if (ch === '"' || ch === "'") { inStr = true; quote = ch; }
      else if (ch === "{") depth++;
      else if (ch === "}") { depth--; if (depth === 0) return i; }
    }
    i++;
  }
  return -1;
}

function wnParseLooseJson(raw) {
  try { return JSON.parse(raw); } catch (_) {}
  const sanitized = raw.replace(
    /([:,\[]\s*)(undefined|NaN|-?Infinity)(\s*[,\]\}])/g,
    "$1null$3"
  );
  try { return JSON.parse(sanitized); } catch (_) { return null; }
}

function wnWalkShowNodes(obj, fn, depth = 0) {
  if (depth > 30 || !obj) return;
  if (Array.isArray(obj)) { for (const v of obj) wnWalkShowNodes(v, fn, depth + 1); return; }
  if (typeof obj !== "object") return;
  const t = obj.__typename || obj.type;
  if (t && /LiveStream|Livestream|Show/i.test(String(t))) fn(obj);
  else if (obj.id && (obj.title || obj.name) && (obj.url || obj.permalink || obj.slug)) fn(obj);
  for (const v of Object.values(obj)) wnWalkShowNodes(v, fn, depth + 1);
}

function wnPickShowId(node) {
  const url = wnPickString(node, ["url", "permalink", "shareUrl", "path", "href"]);
  if (url) {
    const m = /\/live\/([a-f0-9-]{36})/.exec(url);
    if (m) return m[1];
  }
  const id = wnPickString(node, ["id", "uuid", "globalId", "showId", "livestreamId"]);
  if (id && /^[a-f0-9-]{36}$/.test(id)) return id;
  return null;
}

function wnPickString(node, keys) {
  for (const k of keys) {
    const v = node?.[k];
    if (typeof v === "string" && v) return v;
  }
  return null;
}

function wnPickInt(node, keys) {
  for (const k of keys) {
    const v = node?.[k];
    if (typeof v === "number" && Number.isFinite(v)) return Math.floor(v);
  }
  return null;
}

function wnPickArray(node, keys) {
  for (const k of keys) {
    const v = node?.[k];
    if (Array.isArray(v)) {
      const out = v.map(x => typeof x === "string" ? x : (x?.name ?? x?.label)).filter(Boolean);
      if (out.length) return out;
    }
  }
  return null;
}

function wnPickImageUrl(node) {
  for (const k of ["thumbnailUrl", "imageUrl", "image", "thumbnail"]) {
    const v = node[k];
    if (typeof v === "string" && v.startsWith("http")) return v;
    if (v && typeof v === "object") {
      for (const kk of ["url", "src"]) {
        if (typeof v[kk] === "string" && v[kk].startsWith("http")) return v[kk];
      }
    }
  }
  return null;
}

function wnPickHighestSrc(srcsetOrSrc) {
  const parts = srcsetOrSrc.split(",").map(s => s.trim());
  let bestUrl = "", bestScore = 0;
  for (const part of parts) {
    const [url, descriptor] = part.split(/\s+/);
    const n = descriptor ? parseFloat(descriptor) : 0;
    if (n >= bestScore) { bestScore = n; bestUrl = url; }
  }
  return bestUrl || srcsetOrSrc;
}

function wnDecodeHtml(s) {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&#x27;/g, "'")
    .replace(/&nbsp;/g, " ");
}
