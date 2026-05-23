package com.bobaplaybook.app.feature.scan

import android.graphics.Rect
import com.bobaplaybook.core.domain.model.Card

/**
 * Card-number regex — VERBATIM from iOS DECISIONS.md #012.
 *
 *   #?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)
 *
 * Matches the printed card-number on every BoBA card. The bare-suffix
 * branch (`-` or `/` then digits) covers serialized inserts like
 * `BL-IRT-25/50` (Inspired Ink).
 *
 * Kotlin's `Regex` uses identical PCRE semantics to Swift's
 * NSRegularExpression / Vision text matching, so this regex is a
 * drop-in port. Don't deviate without coordinating with iOS.
 */
private val CARD_NUMBER_REGEX =
    Regex("""#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)""")

/** Bare-digit suffix lookup for partial OCR reads (e.g. "20" → matches card_numbers ending in `-20`). */
private val BARE_DIGIT_REGEX = Regex("""\b(\d{1,4})\b""")

/**
 * Looser card-number regex used as a shiny-card fallback. Accepts
 * letters in the suffix slot where digits would normally be — OCR on
 * glow / holographic / foil prints frequently mis-reads digits as
 * their letter look-alikes ("779" → "T79" / "77Q"). Captured suffixes
 * run through [normalizeDigitConfusions] then must validate against
 * the strict [CARD_NUMBER_REGEX] before entering the candidate pool.
 */
private val LOOSE_CARD_NUMBER_REGEX =
    Regex("""#?([A-Z]{1,6}-[A-Z0-9]{1,4}(?:[/-][A-Z0-9]{1,4})?)""")

/**
 * Missing-dash recovery: ML Kit sometimes drops the hyphen between
 * prefix and suffix (font kerning, glow shimmer, etc.) — "GGL-779"
 * arrives as "GGL779" with no separator. Capture prefix + suffix
 * even when the dash is missing, then reconstruct the canonical
 * form. Only applied to JOINED token text so we don't fire on
 * unrelated words ("BIG10" tokens etc.).
 */
private val NO_DASH_CARD_NUMBER_REGEX =
    Regex("""([A-Z]{2,6})(\d{1,4})""")

/**
 * Standalone cardNumber-prefix tokens: shiny-card reads sometimes
 * give us "GGL" alone without the digit suffix. Letters only,
 * 2-6 chars, anchored as a full token (word boundary). The
 * downstream scoring requires the prefix to actually exist in the
 * catalog (via byCardNumberPrefix) so random letter sequences
 * don't pollute the candidate pool.
 */
private val PREFIX_TOKEN_REGEX = Regex("""\b([A-Z]{2,6})\b""")

/**
 * Map common OCR letter→digit confusions back to their probable digit.
 * Only applied to the SUFFIX part of a cardNumber (after the last dash)
 * because the prefix is genuinely letters. Conservative substitutions
 * (no `G→6` etc.) — G/L/M/R don't have a strong digit twin under glare.
 */
internal fun normalizeDigitConfusions(suffix: String): String =
    suffix.map { c ->
        when (c) {
            'O', 'Q', 'D' -> '0'
            'I', 'L', '|' -> '1'
            'S' -> '5'
            'B' -> '8'
            'T' -> '7'
            'Z' -> '2'
            else -> c
        }
    }.joinToString("")

/**
 * Apply [normalizeDigitConfusions] to the digit-suffix portion of a
 * full cardNumber (e.g. "GGL-T79" → "GGL-779"). Bails out unchanged
 * if there's no dash (shouldn't happen for our catalog shape).
 */
internal fun normalizeCardNumber(cn: String): String {
    val lastDash = cn.lastIndexOf('-')
    if (lastDash < 0) return cn
    val prefix = cn.substring(0, lastDash + 1)
    val suffix = cn.substring(lastDash + 1)
    return prefix + normalizeDigitConfusions(suffix)
}

/**
 * Canonical hero-name form. Uppercase + strip whitespace + punctuation
 * commonly dropped or normalised by OCR (dots, hyphens, apostrophes).
 *
 * Without this: catalog heroes like "A.C.", "D-Harp", "D'Artagnan"
 * canonicalise to "A.C.", "D-HARP", "D'ARTAGNAN" (just whitespace
 * stripped). OCR drops the punctuation → tokens read "AC", "DHARP",
 * "DARTAGNAN". Levenshtein for short heroes is tolerance 0 — no match.
 *
 * Stripping punctuation in BOTH sides puts them in the same space:
 *   "A.C." → "AC"  vs  OCR "AC" → "AC"          → exact substring
 *   "D-Harp" → "DHARP"  vs  OCR "DHARP" → "DHARP" → exact substring
 *
 * Non-ASCII letters (e.g. "ç" in "Curaçao Kid") are PRESERVED so the
 * brand isn't quietly Anglicised.
 */
private val HERO_PUNCT_STRIP = Regex("""[\s.\-']+""")
internal fun canonicalizeHero(s: String): String =
    s.uppercase().replace(HERO_PUNCT_STRIP, "")

/**
 * Canonical form for treatment names — uses the same strip rules as
 * [canonicalizeHero]. Real catalog treatments include multi-word
 * forms ("Blue Battlefoil", "Inspired Ink Battlefoil") and
 * apostrophe forms ("Chillin' Battlefoil", "Grillin' Battlefoil").
 * OCR drops apostrophes, may compress whitespace, and may add
 * trailing punctuation — without normalising both sides the
 * `contains` check silently misses many treatment cards.
 */
internal fun canonicalizeTreatment(s: String): String =
    s.uppercase().replace(HERO_PUNCT_STRIP, "")

// ────────────────────────────────────────────────────────────────
// Domain — text token + observation shape
// ────────────────────────────────────────────────────────────────

/**
 * One recognized text fragment from ML Kit, with its bounding box in
 * frame coordinates. We keep the box because hero-name veto needs to
 * know whether a hero name was printed in the top-left of the card
 * (where iOS DECISIONS.md #035 says the hero name lives most reliably).
 */
data class ScanTextToken(
    val text: String,
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
    val frameWidth: Int,
    val frameHeight: Int,
) {
    /** True when this token sits in the upper-left quadrant of the frame. */
    val isTopLeft: Boolean
        get() = top < frameHeight * 0.5f && left < frameWidth * 0.5f

    companion object {
        /**
         * Construct from an Android [Rect]. Used by the live analyzer
         * path. The 4-int internal shape keeps the type pure-JVM-
         * testable (Android Rect's SDK stub returns 0 for every field
         * in unit tests, which broke the ScanGuideMath tests until we
         * refactored).
         */
        fun fromRect(text: String, rect: Rect, frameWidth: Int, frameHeight: Int) =
            ScanTextToken(
                text = text,
                left = rect.left,
                top = rect.top,
                right = rect.right,
                bottom = rect.bottom,
                frameWidth = frameWidth,
                frameHeight = frameHeight,
            )
    }
}

/**
 * Result of a single match attempt. Used by the live scan loop to
 * commit only when confidence + margin pass the gates, and by future
 * tests to assert the scoring math.
 */
data class ScanMatchResult(
    val card: Card,
    val score: Double,
    val margin: Double,
    val reasons: List<String>,
)

/**
 * Multi-signal card matcher — port of iOS DECISIONS.md #035 scoring
 * (minus the image-fingerprint signal; that's DECISIONS.md #043 v2 on
 * Android, gated on MediaPipe Image Embedder + a parallel
 * feature-prints-android.bin artifact).
 *
 * **Why not just first-hit-wins on cardNumber?**
 *   OCR fails partially in ways that look like success. A partial read
 *   of "BHBF-37" can arrive as "20"; the catalog has a real card at
 *   "20" (1-Tigre); the matcher commits 1-Tigre. The user sees the
 *   wrong card with high confidence. iOS DECISIONS.md #035 fixed this
 *   with multi-signal scoring + a hero-name veto: when "JacHammer" is
 *   clearly printed top-left, any candidate whose hero isn't JacHammer
 *   gets a −2.0 penalty.
 *
 * **Scoring weights** (iOS-matched):
 *   +1.0  OCR cardNumber exact match
 *   +0.4  OCR bare-digit suffix match
 *   +1.5  Hero name found in top-left quadrant
 *   +0.6  Hero name found elsewhere in frame
 *   −2.0  Hero veto — a hero name is clearly top-left but candidate
 *         doesn't belong to that hero (the catch for the partial-OCR
 *         silent-wrong case)
 *   +0.2  Element ("FIRE"/"ICE"/etc.) match
 *   +0.2  Treatment substring match
 *   +0.2  Power value match
 *
 * **Commit gates**:
 *   score >= 1.4    confidence floor
 *   score - second_best >= 0.3   margin floor
 *   nil otherwise → caller renders "scanning…" instead of a
 *   confident wrong answer.
 */
class ScanCardMatcher(private val catalog: () -> List<Card>) {

    // Lazy-built set of hero names from the catalog — populated on
    // first match() and re-built when the catalog count changes (which
    // is rare; a new set drop).
    @Volatile private var heroIndex: HeroIndex? = null

    fun match(tokens: List<ScanTextToken>): ScanMatchResult? {
        if (tokens.isEmpty()) return null
        val all = catalog()
        if (all.isEmpty()) return null

        val idx = heroIndex?.takeIf { it.catalogSize == all.size }
            ?: HeroIndex.build(all).also { heroIndex = it }

        // ── Pull observable signals out of the tokens ────────────
        // First pass: per-token regex hits. Catches the clean case
        // where ML Kit returns "BHBF-37" as one token.
        val perTokenHits = tokens
            .asSequence()
            .flatMap { tk -> CARD_NUMBER_REGEX.findAll(tk.text).map { it.groupValues[1].uppercase() } }
            .toSet()

        // Second pass: ML Kit OFTEN splits a printed cardNumber across
        // tokens — "BHBF" and "37" arrive as separate text lines, or
        // "BHBF-" + "37", or "BHBF" + "-37". The per-token regex misses
        // every variant. Joined-text search picks them up. False
        // positives are limited by the regex's letters-dash-digits
        // shape — random words don't accidentally form a valid card
        // number across boundaries.
        val joinedSpace = tokens.joinToString(" ") { it.text.uppercase() }
        val joinedNone = tokens.joinToString("") { it.text.uppercase() }
        val joinedHits = (CARD_NUMBER_REGEX.findAll(joinedSpace) + CARD_NUMBER_REGEX.findAll(joinedNone))
            .map { it.groupValues[1].uppercase() }
            .toSet()

        // Third pass: shiny-card digit-confusion recovery (iter 44).
        // Glow / holographic / foil prints often cause OCR to mis-read
        // digits as their letter look-alikes — "GGL-779" arrives as
        // "GGL-T79" / "GGL-77Q" / "GGL-77G". Strict regex requires
        // \d in the suffix slot so any letter kills the match. Run a
        // looser regex that accepts [A-Z0-9] in the suffix slot, then
        // normalise the suffix back to digits and revalidate against
        // the strict regex. False-positive guarded by:
        //   • Letters-dash-digits prefix shape still required
        //   • Result must validate as a real catalog cardNumber (the
        //     downstream `idx.byCardNumberUpper` lookup misses if not)
        val looseHits = (
            LOOSE_CARD_NUMBER_REGEX.findAll(joinedSpace) +
                LOOSE_CARD_NUMBER_REGEX.findAll(joinedNone) +
                tokens.asSequence().flatMap { LOOSE_CARD_NUMBER_REGEX.findAll(it.text.uppercase()) }
            )
            .map { normalizeCardNumber(it.groupValues[1].uppercase()) }
            .filter { CARD_NUMBER_REGEX.matches(it) }
            .toSet()

        // Fourth pass: missing-dash recovery (iter 45). ML Kit sometimes
        // returns "GGL779" instead of "GGL-779" (font kerning / shimmer).
        // Capture letter-prefix + digit-suffix even with no dash, then
        // reconstruct the canonical "PREFIX-SUFFIX" form. Run against
        // both joined-text forms. False positives are bounded by the
        // downstream `idx.byCardNumberUpper` lookup — non-existent
        // synthetic cardNumbers are silently dropped.
        val noDashHits = (
            NO_DASH_CARD_NUMBER_REGEX.findAll(joinedNone) +
                NO_DASH_CARD_NUMBER_REGEX.findAll(joinedSpace)
            )
            .map { "${it.groupValues[1]}-${it.groupValues[2]}" }
            .toSet()
        val cardNumberHits = perTokenHits + joinedHits + looseHits + noDashHits

        // Fifth pass: prefix-only recovery (iter 45). Shiny prints
        // sometimes give OCR the cardNumber PREFIX but not the digit
        // suffix — "GGL" alone on a DEKAP GGL-779 scan. Detect
        // standalone letter tokens 2-6 chars and look them up in the
        // prefix index. Only known catalog prefixes pass — random
        // letter sequences ("RED", "BIG") that don't map to a real
        // prefix get silently dropped.
        val cardPrefixHits = tokens.asSequence()
            .flatMap { PREFIX_TOKEN_REGEX.findAll(it.text.uppercase()) }
            .map { it.groupValues[1] }
            .filter { idx.byCardNumberPrefix.containsKey(it) }
            .toSet()

        val bareDigitHits = tokens
            .asSequence()
            .flatMap { tk -> BARE_DIGIT_REGEX.findAll(tk.text).map { it.groupValues[1] } }
            .toSet()

        // Hero names mentioned anywhere + the subset top-left. Fuzzy
        // match (Levenshtein ≤ 1 for short heroes, ≤ 2 for ≥6-char
        // heroes) recovers from OCR character flips like "MAVERIK" →
        // Maverick or "JACHAMMR" → JacHammer. iOS DECISIONS.md #035
        // uses exact substring; we improve on it.
        val heroesMentioned = mutableSetOf<String>()
        val heroesTopLeft = mutableSetOf<String>()
        // Strict subset of heroesTopLeft — only heroes with an EXACT
        // substring top-left match. The -2.0 hero veto is harsh; we
        // don't want a low-confidence fuzzy match (Levenshtein 2 on
        // OCR noise) to incorrectly suppress every other candidate.
        // Fuzzy matches still earn the +1.5 positive bonus; only
        // exact matches gate the veto.
        val heroesTopLeftStrict = mutableSetOf<String>()
        for (tk in tokens) {
            val upper = canonicalizeHero(tk.text)
            for (hero in idx.heroNames) {
                val canonical = idx.canonical[hero] ?: continue
                if (matchesHero(upper, canonical)) {
                    heroesMentioned += hero
                    if (tk.isTopLeft) {
                        heroesTopLeft += hero
                        if (upper.contains(canonical)) heroesTopLeftStrict += hero
                    }
                }
            }
        }
        // Second pass: adjacent-token concatenation. ML Kit splits
        // mid-word more often than its line-detection docs suggest —
        // "JacHammer" arrives as ["Jac", "Hammer"], "MAVERICK" can
        // arrive as ["MAV", "ERICK"] on a wide-spaced print. None of
        // those reach the per-token matcher above. Try every adjacent
        // pair's concatenation; if it matches a hero AND the FIRST
        // token sits top-left, treat the hero as top-left. Mirrors
        // iter 4's joined-text cardNumber fallback.
        for (i in 0 until tokens.size - 1) {
            val a = tokens[i]
            val b = tokens[i + 1]
            val joined = canonicalizeHero(a.text + b.text)
            for (hero in idx.heroNames) {
                val canonical = idx.canonical[hero] ?: continue
                // Skip heroes already detected in the per-token pass
                // — saves work + avoids double-counting top-left.
                if (hero in heroesMentioned) continue
                if (matchesHero(joined, canonical)) {
                    heroesMentioned += hero
                    if (a.isTopLeft) {
                        heroesTopLeft += hero
                        if (joined.contains(canonical)) heroesTopLeftStrict += hero
                    }
                }
            }
        }

        // Treatment text — if the user's card has a battlefoil/foil
        // treatment, the print often says so explicitly. Score +0.2
        // when an OCR token matches the candidate's treatment.
        // Treatment matching needs to handle multi-word treatments like
        // "Red Battlefoil" or "Inspired Ink". ML Kit puts each word in
        // its own token, so a per-token contains() check fails to find
        // "RED BATTLEFOIL" inside "RED" or "BATTLEFOIL" alone. Build a
        // joined-text uppercase blob to search against (same pattern as
        // iter 4's cardNumber joined-text fallback). Also keep the
        // per-token form so single-word treatments ("Battlefoil",
        // "Superfoil") still match on the cheap path.
        // Pre-canonicalised per-token + joined-text forms for treatment
        // matching. Both sides strip whitespace + punctuation per
        // `canonicalizeTreatment` so:
        //   • "Chillin' Battlefoil" (catalog) → "CHILLINBATTLEFOIL"
        //   • OCR "CHILLIN BATTLEFOIL" → "CHILLINBATTLEFOIL" → match
        //   • OCR "Chillin' Battlefoil" → "CHILLINBATTLEFOIL" → match
        // Joined-text uses no-space concat so multi-word treatments
        // catch even when ML Kit splits the phrase across tokens.
        val treatmentTokens = tokens.map { canonicalizeTreatment(it.text) }
        val joinedTreatmentText = tokens.joinToString("") { canonicalizeTreatment(it.text) }

        // Element / treatment / power scraps (low-confidence additives).
        // Split each token on non-letter chars before matching so:
        //   • "FIRE 135" (element + power on one line) → ["FIRE","135"]
        //     → "FIRE" hits idx.elements
        //   • "FIRE!" / "FIRE." (OCR-trailed punctuation) → ["FIRE",""]
        //     → "FIRE" hits
        //   • "FIREBRAND" (hero name containing "FIRE") → ["FIREBRAND"]
        //     → no false positive
        // Element names are all pure letters (FIRE, ICE, STEEL, BRAWL,
        // GLOW, HEX, GUM, SUPER, NONE) so splitting on non-letters is
        // safe.
        val elementHits = tokens
            .asSequence()
            .flatMap { it.text.uppercase().split(Regex("[^A-Z]+")).asSequence() }
            .filter { it.isNotBlank() && it in idx.elements }
            .toSet()
        val powerHits = tokens
            .asSequence()
            .flatMap { tk -> BARE_DIGIT_REGEX.findAll(tk.text).map { it.groupValues[1].toIntOrNull() ?: 0 } }
            // BoBA hero powers are 50–250 in increments of 5. Values
            // below 50 (5, 10, 15, ..., 45) are almost always print-run
            // serials, set-codes, or card-body digits — NOT power. Old
            // floor (> 0) was creating false +0.2 power bonuses on
            // candidates with low artificial "power" values that
            // happened to match a stray digit somewhere in the frame.
            .filter { it >= 50 && it % 5 == 0 }
            .toSet()

        // Restrict the candidate pool via the pre-built indexes (O(1)
        // per hit instead of O(N) catalog scans). Cuts 17k → typically
        // <60 in practice.
        val candidates = buildSet {
            cardNumberHits.forEach { num ->
                idx.byCardNumberUpper[num.uppercase()]?.let { addAll(it) }
            }
            bareDigitHits.forEach { digits ->
                idx.byBareDigitSuffix[digits.uppercase()]?.let { addAll(it) }
            }
            heroesMentioned.forEach { hero ->
                idx.byHeroLowercase[hero.lowercase()]?.let { addAll(it) }
            }
            // Prefix-only candidates: GGL → all 786 GGL-* cards. Only
            // populated when a heroesMentioned hit ALSO exists, so we
            // don't broadcast 786 cards into the pool every frame.
            // The intersection of "matches a known prefix" AND
            // "matches a hero" is the discriminating set.
            if (heroesMentioned.isNotEmpty()) {
                cardPrefixHits.forEach { prefix ->
                    idx.byCardNumberPrefix[prefix]?.let { addAll(it) }
                }
            }
        }
        if (candidates.isEmpty()) return null

        // Hoisted uppercased sets — the per-candidate loop below
        // checks `heroUpper in heroesTopLeftUpper` (and the strict
        // variant) for every candidate. Previously these were
        // recomputed inside the loop body via `.map { ... }`. With
        // ~30-60 candidates × ~3 hero strings = ~150 uppercase calls
        // per frame, per-frame OCR runs at 15-30 fps → ~3-5k
        // redundant uppercase ops/sec. Hoisting is free correctness.
        val heroesTopLeftUpper = heroesTopLeft.mapTo(HashSet()) { it.uppercase() }
        val heroesTopLeftStrictUpper = heroesTopLeftStrict.mapTo(HashSet()) { it.uppercase() }
        val heroesMentionedUpper = heroesMentioned.mapTo(HashSet()) { it.uppercase() }

        // ── Score every candidate ────────────────────────────────
        val scored = candidates.map { card ->
            val reasons = mutableListOf<String>()
            var score = 0.0

            val cardNumberUpper = card.cardNumber.uppercase()
            if (cardNumberUpper in cardNumberHits) {
                score += 1.0
                reasons += "cardNumber +1.0"
            }
            val bareSuffix = card.cardNumber.substringAfterLast('-').substringAfterLast('/')
            if (bareSuffix in bareDigitHits) {
                score += 0.4
                reasons += "bare-digit +0.4"
            }
            // Prefix-only signal (iter 45): GGL prefix on a DEKAP scan
            // narrows the candidate pool to GGL-* cards. Combined with
            // hero +1.5 and element/power matches, this is enough
            // signal to push GGL-779 above the +0.3 margin floor over
            // sibling GGL-124 / GGL-255 / etc. (which have different
            // elements + powers).
            val cardPrefix = if ('-' in card.cardNumber) {
                card.cardNumber.substringBefore('-').uppercase()
            } else ""
            if (cardPrefix.isNotEmpty() && cardPrefix in cardPrefixHits) {
                score += 0.4
                reasons += "prefix +0.4"
            }
            if (card.hero.isNotBlank()) {
                val heroUpper = card.hero.uppercase()
                if (card.hero in heroesTopLeft || heroUpper in heroesTopLeftUpper) {
                    score += 1.5
                    reasons += "hero top-left +1.5"
                } else if (card.hero in heroesMentioned || heroUpper in heroesMentionedUpper) {
                    score += 0.6
                    reasons += "hero +0.6"
                }
            }

            // ── HERO VETO ────────────────────────────────────────
            // The iOS catch from DECISIONS.md #035: when a hero is
            // clearly named top-left and this candidate isn't that hero,
            // hammer the score. This is what kills the "partial-OCR
            // landed on a real-but-wrong cardNumber" failure mode.
            //
            // Gate on `heroesTopLeftStrict` (exact substring match) so
            // a low-confidence fuzzy hero claim from OCR noise can't
            // wrongly suppress every legitimate candidate. Fuzzy
            // top-left matches still earn the +1.5 positive bonus
            // above; only exact matches drive the negative veto.
            if (heroesTopLeftStrictUpper.isNotEmpty() && card.hero.isNotBlank()) {
                val heroUpper = card.hero.uppercase()
                if (heroUpper !in heroesTopLeftStrictUpper) {
                    score -= 2.0
                    reasons += "hero veto −2.0"
                }
            }

            if (card.element.uppercase() in elementHits) {
                score += 0.2
                reasons += "element +0.2"
            }
            if ((card.power ?: -1) in powerHits) {
                score += 0.2
                reasons += "power +0.2"
            }
            // Treatment text — "Battlefoil", "Red Battlefoil", "Inspired
            // Ink", "Superfoil", etc. Check per-token first (fast path,
            // single-word treatments) then fall back to joined-text for
            // multi-word treatments that ML Kit splits across tokens.
            val treatment = card.treatment?.let { canonicalizeTreatment(it) } ?: ""
            if (treatment.isNotEmpty() &&
                (treatmentTokens.any { it.contains(treatment) } ||
                    joinedTreatmentText.contains(treatment))
            ) {
                score += 0.2
                reasons += "treatment +0.2"
            }

            ScanMatchResult(card = card, score = score, margin = 0.0, reasons = reasons)
        }.sortedByDescending { it.score }

        val best = scored.firstOrNull() ?: return null
        val second = scored.getOrNull(1)?.score ?: 0.0

        val margin = best.score - second
        val resolved = best.copy(margin = margin)

        // ── Commit gates ─────────────────────────────────────────
        // 1.4 confidence + 0.3 margin = iOS-matched thresholds.
        // Returning null is the right thing when neither is met:
        // the live UI keeps scanning instead of committing a guess.
        if (best.score < 1.4) return null
        if (margin < 0.3) return null
        return resolved
    }

    /**
     * Diagnostic-only: returns the top-scored candidate REGARDLESS of
     * the commit gates (confidence floor + margin floor). Used by the
     * ShinyScanDiag logging path to capture what almost-committed so
     * we can target the right gap. Not for production scoring — the
     * regular [match] is what drives the chip + queue.
     */
    fun debugTop(tokens: List<ScanTextToken>): ScanMatchResult? {
        val all = catalog()
        if (all.isEmpty()) return null
        val idx = heroIndex?.takeIf { it.catalogSize == all.size }
            ?: HeroIndex.build(all).also { heroIndex = it }

        // Re-run the candidate gathering + scoring pipeline but skip
        // the final gates. Reuses the public match() with a tiny
        // peek: if it commits, return it; otherwise reconstruct the
        // top by re-scoring. Cheap enough — diagnostic only fires
        // once per second.
        match(tokens)?.let { return it }

        // Falls through here when match returned null due to gates.
        // Quick re-score (duplicates a small amount of work but the
        // call site throttles to 1Hz so it's fine).
        val cardNumberHits = (CARD_NUMBER_REGEX.findAll(tokens.joinToString(" ") { it.text.uppercase() }) +
            CARD_NUMBER_REGEX.findAll(tokens.joinToString("") { it.text.uppercase() }) +
            tokens.asSequence().flatMap { CARD_NUMBER_REGEX.findAll(it.text.uppercase()) }
        ).map { it.groupValues[1].uppercase() }.toSet()
        val bareDigitHits = tokens.asSequence()
            .flatMap { BARE_DIGIT_REGEX.findAll(it.text).map { m -> m.groupValues[1] } }.toSet()
        val heroesMentioned = mutableSetOf<String>()
        for (tk in tokens) {
            val upper = canonicalizeHero(tk.text)
            for (hero in idx.heroNames) {
                val canonical = idx.canonical[hero] ?: continue
                if (matchesHero(upper, canonical)) heroesMentioned += hero
            }
        }
        val candidates = buildSet {
            cardNumberHits.forEach { idx.byCardNumberUpper[it.uppercase()]?.let(::addAll) }
            bareDigitHits.forEach { idx.byBareDigitSuffix[it.uppercase()]?.let(::addAll) }
            heroesMentioned.forEach { idx.byHeroLowercase[it.lowercase()]?.let(::addAll) }
        }
        if (candidates.isEmpty()) return null
        // Pick the candidate with the most matching signals as a
        // rough top-pick. Coarse — purely for logging.
        val best = candidates.maxByOrNull { card ->
            var s = 0.0
            if (card.cardNumber.uppercase() in cardNumberHits) s += 1.0
            val bs = card.cardNumber.substringAfterLast('-').substringAfterLast('/')
            if (bs in bareDigitHits) s += 0.4
            if (card.hero in heroesMentioned) s += 0.6
            s
        } ?: return null
        return ScanMatchResult(
            card = best, score = 0.0, margin = 0.0,
            reasons = listOf("DEBUG_TOP candidates=${candidates.size}"),
        )
    }
}

/**
 * Fuzzy hero name match. Returns true if [token] contains [hero]
 * exactly OR a Levenshtein-distance-bounded variant of it. Distance
 * tolerance scales with name length so short heroes (TIGRE, BO) stay
 * strict and long heroes (JACHAMMER, BURRDOCIOUS) allow 1-2 OCR
 * character flips.
 */
private fun matchesHero(token: String, hero: String): Boolean {
    if (token.contains(hero)) return true
    // Slide a hero-length window across token; check Levenshtein on
    // each. Bounded distance keeps short heroes strict.
    val tolerance = when {
        hero.length <= 4 -> 0  // 4-char heroes need exact match
        hero.length <= 6 -> 1
        else -> 2
    }
    if (tolerance == 0) return false
    if (token.length < hero.length) {
        // Token shorter than hero — only worth checking if very close.
        return levenshtein(token, hero) <= tolerance
    }
    for (i in 0..(token.length - hero.length)) {
        val sub = token.substring(i, i + hero.length)
        if (levenshtein(sub, hero) <= tolerance) return true
    }
    return false
}

/** Standard iterative Levenshtein distance — O(n*m) with O(min(n,m)) space. */
private fun levenshtein(a: String, b: String): Int {
    if (a == b) return 0
    if (a.isEmpty()) return b.length
    if (b.isEmpty()) return a.length
    val prev = IntArray(b.length + 1) { it }
    val curr = IntArray(b.length + 1)
    for (i in 1..a.length) {
        curr[0] = i
        for (j in 1..b.length) {
            val cost = if (a[i - 1] == b[j - 1]) 0 else 1
            curr[j] = minOf(
                curr[j - 1] + 1,        // insert
                prev[j] + 1,            // delete
                prev[j - 1] + cost,     // substitute
            )
        }
        System.arraycopy(curr, 0, prev, 0, prev.size)
    }
    return prev[b.length]
}

/**
 * Pre-built lookup from the catalog — heroes + elements indexed by
 * upper-cased canonical form so the per-token match is O(1) per
 * heroName lookup.
 */
private class HeroIndex(
    val catalogSize: Int,
    val heroNames: Set<String>,
    val canonical: Map<String, String>,
    val elements: Set<String>,
    // O(1) candidate-gathering lookups. Each filter call in the prior
    // candidate-building loop iterated 17k cards; at 15-30 fps with
    // multiple hits/frame that was ~150-300k iterations/sec just to
    // narrow the pool. Pre-indexing collapses each filter to a hash
    // lookup. Keys uppercase so case-insensitive matches don't need
    // per-element comparison.
    val byCardNumberUpper: Map<String, List<Card>>,
    val byBareDigitSuffix: Map<String, List<Card>>,
    val byHeroLowercase: Map<String, List<Card>>,
    // cardNumber-prefix → cards. The part of the cardNumber BEFORE
    // the first dash (e.g. "GGL" → 786 cards for Great Grandma's
    // Linoleum Battlefoil). Used as a shiny-card recovery signal when
    // OCR catches only the prefix without the digit suffix.
    val byCardNumberPrefix: Map<String, List<Card>>,
) {
    companion object {
        fun build(catalog: List<Card>): HeroIndex {
            val heroNames = catalog.asSequence()
                .map { it.hero }
                .filter { it.isNotBlank() }
                .toSet()
            // Canonical match-form: uppercase + strip whitespace +
            // punctuation (dots, hyphens, apostrophes) — see
            // `canonicalizeHero` doc. Aligns OCR-dropped-punctuation
            // tokens with catalog heroes containing the same chars.
            val canonical = heroNames.associateWith { canonicalizeHero(it) }
            val elements = catalog.asSequence().map { it.element.uppercase() }.toSet()
            val byCardNumberUpper = catalog.groupBy { it.cardNumber.uppercase() }
            // Bare-suffix derivation matches the per-card extraction at
            // scoring time: cardNumber.substringAfterLast('-')
            //   .substringAfterLast('/'). So "BHBF-37" → "37",
            //   "BL-IRT-25/50" → "50".
            val byBareDigitSuffix = catalog.groupBy {
                it.cardNumber.substringAfterLast('-').substringAfterLast('/').uppercase()
            }
            // Hero lookup is keyed lowercase to make `equals(..., ignoreCase = true)`
            // collapse to a normal hash hit. Sealed-product cards
            // (hero blank) get a "" key — irrelevant because heroesMentioned
            // never has the empty string.
            val byHeroLowercase = catalog.groupBy { it.hero.lowercase() }
            // Prefix: everything BEFORE the first dash. Cards without
            // a dash (base set "1", "20") land under "" → won't be
            // hit by the prefix-token regex (which requires ≥2 chars).
            val byCardNumberPrefix = catalog
                .filter { '-' in it.cardNumber }
                .groupBy { it.cardNumber.substringBefore('-').uppercase() }
            return HeroIndex(
                catalogSize = catalog.size,
                heroNames = heroNames,
                canonical = canonical,
                elements = elements,
                byCardNumberUpper = byCardNumberUpper,
                byBareDigitSuffix = byBareDigitSuffix,
                byHeroLowercase = byHeroLowercase,
                byCardNumberPrefix = byCardNumberPrefix,
            )
        }
    }
}
