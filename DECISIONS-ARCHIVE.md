# BOBA Playbook — Architecture Decisions ARCHIVE

> Superseded, foundational, or operational-detail decisions. These are kept for
> the historical record but are NOT loaded into context every session. The
> **load-bearing, actively-governing** decisions live in [DECISIONS.md](./DECISIONS.md).
>
> Why an entry is here: it's either (a) **superseded** by a newer decision, (b)
> **foundational** — baked into the codebase and no longer needing active recall,
> or (c) **operational tuning detail** that has its own dedicated playbook
> (pricing-estimator internals → PRICING_PLAYBOOK.md + PRICING_AUTOMATION.md).
>
> Same entry format as DECISIONS.md. The question every entry answers: *what
> would the next developer get wrong if they didn't know this?*

---

## 001 — Vanilla HTML/CSS/JS for Web
*2026-04-03*
No framework, no build step. GitHub Pages serves static files directly. Framework abstractions cost more than they save at this scale.

**Principle**: Reach for complexity only when simplicity has actually failed, not when it might someday fail.

## 002 — Xcode Project at Repository Root
*2026-04-03*
`.xcodeproj` lives at repo root, no subdirectory, no spaces in project name. Required for Xcode Cloud auto-discovery. Lesson from Bsky Dreams: a nested path caused a persistent "Project does not exist at root" error that cost hours to diagnose.

## 003 — Shared Version Config (xcconfig)
*2026-04-03*
`AppVersion.xcconfig` defines `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Editing via Xcode's identity panel creates per-target overrides that drift silently. Always edit the xcconfig file directly.

## 004 — SwiftUI + @Observable + SwiftData (iOS)
*2026-04-03*
SwiftUI for all UI. `@Observable` (iOS 17 macro) for state. SwiftData for local persistence. UIKit only where SwiftUI lacks a native equivalent. Requires iOS 17+ minimum deployment target.

## 006 — App Name and Brand Identity
*2026-04-03*
Display name: BOBA Playbook. Xcode product: BOBAPlaybook (no hyphens). Design language: Retro-futurism + cyberpunk + glassmorphism. Palette: battle orange / cyber cyan / deep violet on near-black (hexes in #010). Card art is always the focal point — UI chrome frames it, never competes.

## 009 — Static Card Catalog JSON
*2026-04-03*
`cards.json` (17,739 cards) committed to `assets/data/` and served from GitHub Pages. No database for catalog browsing. To update for new sets: re-run `reconcile_all.py`, copy outputs to `assets/data/`, commit.

## 013 — Pricing Comps Strategy
*2026-04-03*
Pricing fetched live at card-detail view time via Cloudflare Worker. Prices not stored in Supabase — live lookups only; Collection value caches last-fetched price in `user_cards.estimated_value`. Worker URL lives in `Config.swift` + `js/app.js`. **Superseded by #058** — the provenance-honest architecture (Radish removed #056; Marketplace Insights permanently unavailable; we generate our own sold-history). See #058 + PRICING_PLAYBOOK.md.

## 014 — iOS Card Catalog: Two-Phase Progressive Loading
*2026-04-03*
Phase 1: synchronous decode of `cards-head.json` (500 cards, ~192KB) in `CardStore.init()` — cards are available before SwiftUI frame 1 (<50ms). Phase 2: `Task.detached(priority: .background)` decodes `display-cards.json` (~12k cards, 4.7MB).

**Principle**: The user should never wait on data we already have. Phase 1 costs nothing and eliminates a blank screen.

## 015 — imageAvailable Flag Bypass
*2026-04-03*
`imageAvailable` boolean is NOT used to gate image loading. Any card with a non-empty `imageFile` always attempts CDN load. The flag had false negatives — some cards had `imageAvailable: false` but valid CDN images.

## 016 — Section Named "Play" Not "Rules"
*2026-04-03*
The rules/strategy/deck-builder section is named **Play** on both platforms. "Rules" implies constraint; "Play" conveys purpose.

**Principle**: Language shapes how users feel about a feature before they open it.

## 017 — Web Filter Panel: Mobile Collapsible, Desktop Persistent
*2026-04-03*
Mobile (<768px): filter panel hidden by default, toggled by a button with an active-count badge. Desktop (≥768px): always visible. Mirrors the iOS bottom sheet pattern.

## 018 — PWA GitHub Pages 404 Handling
*2026-04-03*
`404.html` redirects unresolvable URLs back to `/`, preserving query string. `manifest.json` has `"scope": "/"`. Without this, PWA homescreen launches hit GitHub's own 404 page.

## 019 — App Icon: XOXO Playbook Mark
*2026-04-03*
XOXO pattern (X, O, O, X in 2×2 grid) in BOBA orange on near-black. Legible at small sizes, evokes strategy/playbook thinking (X's and O's = play diagrams).

## 021 — Play Mode: Static Reference Content, Supabase for User Decks
*2026-04-05*
Rules, strategy guides, archetype templates, and the collecting guide are static/local — no auth required. User-created decks save to Supabase `decks` + `deck_cards` and require sign-in.

**Why**: Reference content belongs to everyone, immediately, without friction. Personal decks have identity — your choices, your strategy — and should persist across devices like the collection does.

## 022 — SwiftUI ScrollView Width: VStack Parent Must Have frame(maxWidth: .infinity)
*2026-04-06*
Any `VStack` that directly parents a `ScrollView` AND switches content conditionally must have `.frame(maxWidth: .infinity)`, or the ScrollView receives variable proposed widths per mode, causing horizontal rubber banding.

**Root cause**: SwiftUI's VStack sizes to the max of its children's natural widths. When that width varies by mode (e.g., Rookie = 228pt, Substitution = 361pt), every child ScrollView inherits that instability. Apply the frame constraint at the outermost VStack first.

## 024 — iOS Image Loading: Show Thumb Immediately While Full Loads
*2026-04-13*
When opening a card detail view, `CardImageView` shows the cached grid thumb immediately instead of a spinner (it's almost always cached — the user just saw it), then loads full-res in the background and swaps it in.

**Why**: A spinner for something the user just tapped creates a gap between intention and response. Showing the card immediately — even at grid resolution — confirms the right card is loading. Immediacy builds trust; spinners create anxiety.

## 032 — iOS home-screen display name: "Playbook" not "BOBA Playbook"
*2026-04-24*
`INFOPLIST_KEY_CFBundleDisplayName = Playbook`. The full "BOBA Playbook" still appears in `BOBAWordmark`, in `CFBundleName` (Settings → iPhone Storage), and on the App Store listing.

**Why**: "BOBA Playbook" truncates to "BOBA Pl…" under the icon on every iPhone tested. Truncation reads as broken; the shorter name is intentional. The XOXO icon already carries the brand — the under-icon label only needs to disambiguate from other installed apps.

## 033 — Open questions deferred to BoBA / real-world data
*2026-04-27*
Three items blocked on external signal — documented so they don't get lost.

**(a) `LA - 20 — Series MVP Award` anomaly.** A BoBA DBS PDF row references hero `MVFree` and release prefix `LA` not in our catalog. Skipped from `dbs_merge.py` (1/411 rows). **Ben TODO:** confirm with BoBA; rerun merge.

**(b) bobaleagues CSV roundtrip.** Phase C ships a v2 CSV alongside legacy v1. **Ben TODO:** export a real Playbook + adjust if the shape drifts. Both paths kept.

**(c) Elo tier-band tuning.** Phase D bands (200-pt: Brawl 0–999 … Super 2200+) are live-derived, never stored. Needs ~1k production matches to tune the bottom widths.

**Why defer**: all three are blocked on external confirmation / artifact / production data. Cost of waiting is zero; cost of guessing is silent drift.

## 038 — Profile redesign: generalized role-request (mod OR streamer)
*2026-05-04*
The mod-request flow generalized to a `request_role(role, reason)` RPC accepting `'moderator'` or `'streamer'`; the admin queue returns both kinds and promotes to whichever was requested. Old mod-only RPCs kept as delegating shims through the deploy window; migration is additive. **Why:** streamer always needed a request flow; one mechanism is cheaper than two.

## 040 — Profile pictures: Discord-default, R2-on-upload
*2026-05-05*
Three-tier resolver: **custom (R2) → Discord avatar → default silhouette.** Most users auth via Discord OAuth → recognizable avatar at zero storage cost. Avatars live in the existing R2 bucket; the `boba-avatar-upload` Worker verifies a Bearer JWT, caps at 2MB, writes R2.

**Security:** RPC `set_avatar_url` is own-row + **rejects URLs not matching the R2 avatars prefix** — without this, a malicious client could point `avatar_url` at tracking pixels or inappropriate images rendered on others' devices.

**Why R2+Worker, not Supabase Storage:** R2 (#008) = zero egress + edge cache + auth-free CDN; Supabase Storage avoided per #007.

## 046 — Android-specific app ID + signing strategy
*2026-05-19*
Package: **`com.bobaplaybook.app`**. Affects signing + Play Console + `assetlinks.json` + Firebase + every deep link. **Signing:** Play App Signing (mandatory since 2021) — Play resigns each release with its production key; upload-key creds in `gradle.properties` (git-excluded) + CI secrets.

**`assetlinks.json`** sits at the same `/.well-known/` path as `apple-app-site-association`; both coexist. Its fingerprint must include BOTH the upload-key AND the Play App Signing key SHA-256 — internal-testing builds (upload-key-signed) won't verify against the production key otherwise. ANDROID-DEV.md §8.5 + §14.

## 050 — Android: Sign in with Apple is NOT offered
*2026-05-19*
Sign in with Apple is iOS+Web branding. Android offers Sign in with Google (primary, Credential Manager one-tap), Discord OAuth (secondary; most-used in the BoBA community), email/password (fallback). Apple-ID accounts created on iOS map to email-based Supabase users; the same email signs in on Android.


**Why:** Sign in with Apple on Android is a foreign brand cue; Sign in with Google is the canonical one-tap; a third path adds complexity without proportional value.

## 052 — Firebase: stay on Spark (free) plan
*2026-05-19*
Android uses Firebase **only** for FCM push delivery. No Firestore, Realtime DB, Firebase Auth (Supabase + Credential Manager), Hosting, or Storage (R2 per #008). Spark covers unlimited FCM delivery. Single project, one Android app; `google-services.json` committed (public identifiers, safe). No Blaze upgrade needed for v1.

## 055 — Android scan: multi-pathway OCR recovery for shiny / holographic cards
*2026-05-23*
Real-world testing of **DEKAP GGL-779 (Great Grandma's Linoleum Battlefoil — Glow)** drove a rewrite of the Android matcher to accumulate **multiple independent OCR-recovery paths** rather than rely on one clean read (cross-token reassembly, digit-confusion + digit-to-letter prefix normalisation — `G6L`→`GGL`, most-impactful since OCR reads `G` as `6` on shimmer — missing-dash reconstruction, heroes-gated prefix-only candidates, cross-frame aggregation, fuzzy element matching). iOS #035's strict cardNumber regex + hero veto stays the core. The **killer feature: a parallel preprocessed-OCR pipeline** — a periodic `enhanceContrast` (percentile luma stretch) on a `PreviewView.bitmap` snapshot feeds a SECOND ML Kit pass into the same token buffer, restoring the cardNumber-strip contrast auto-exposure blows out on shimmer. Full path list + don't-touch diagram in memory `[[reference_android_scanner_recovery_paths]]` + SCANNER_LOOP.md.

**Why Android diverges from iOS:** iOS has a cleaner OCR baseline (Vision) + `feature-prints.bin` FP (#035); Android's ML Kit OCR is noisier on shimmer, FP deferred to v2 (#043). **Don't:** lower the stabilizer single-frame tier below 2.5, or relax the 0.3 margin / 1.4 confidence floors (tried iters 46-47, reverted within minutes — wrong-card/element commits). The floors are load-bearing; new paths get a SCANNER_LOOP.md row + `ScanCardMatcherTest` JVM test.

## 059 — Pricing UI parity: unified labels, slim-catalog carries radishUrl
*2026-05-28*

Closes the cross-platform pricing-UI drift surfaced by a real-card audit of #104 Superbaby Ice (iOS showed "EST. MID" tri-grid, web showed "AVG" tri-grid, Android showed no tri-grid AND no eBay Sales button AND Radish link fell back to the homepage). The four-signal resolver (#058) already lives in one shape on all three platforms (web `js/app.js`, iOS `PricingService.marketValue`, Android `:core:network` `marketValue()`), but the *rendering* of its output had drifted. This entry locks the rendering so the resolver and the UI agree across platforms.

**Principle — same data, same labels, same affordances; native-idiom rendering.** The Workers are the single source of truth; the resolver shapes are identical; the user-visible labels and affordances are identical; only the *chrome* (Liquid Glass tile / CSS grid / M3 Surface) differs per platform.

**The locked vocabulary.**
- Section headers: **RECENT SALES** · **LISTED RANGE** · **MARKET EST.** (drives the framing).
- Tri-grid cell labels: **LOW** · **AVG** · **HIGH** (everywhere — Recent Sales, Listed Range, MARKET EST. all three). iOS's prior "EST. MID" inside the MARKET EST. tile is gone; the section header carries the "estimated" framing. "AVG" is the user-facing word; the value is a *median* under the hood (robust to outliers) — implementation detail.
- Single-anchor cells (count == 1): **FROM $X** (asking) · **LAST SOLD $X** (transacted).
- Source pills: **eBay sale** · **Whatnot sale** · **BoBA Community · @user** (transacted) · **eBay listed** · **Whatnot ask** · **COMC asking · Ungraded NM** (asking).
- Footer affordances: **eBay Sales** (opens `bo jackson battle arena {hero} {cardNumber}` sold-search, `LH_Sold=1 LH_Complete=1`) · **View on Radish** (opens `card.radishUrl` or homepage). Same URL builder verbatim across iOS, web, Android — see `buildEbaySoldSearchUrl` in `android/.../CardDetailScreen.kt`, `ebayURL` in `BOBAPlaybook/Components/PricingSection.swift`, `buildEbayUrl` in `js/app.js`.

**The slim-catalog Radish-field gotcha (the load-bearing one).** Android's `cards.json` is produced by copying `assets/data/cards-slim.json` at preBuild time (`scripts/sync_shared_assets.sh`). Pre-2026-05-28, `pipeline/scripts/regen_bundles.py` explicitly DROPPED `radishUrl` from the slim bundle (≈1.4 MB savings). Result: every Android card landed with `radishUrl: null` and the "View on Radish" button always fell back to the homepage — silently broken since launch, visible only to users comparing to web/iOS. **Fix:** `radishUrl` is now ALWAYS in the slim + Android bundles (NEW FIELD treatment in `regen_bundles.py`, mirroring the printRun + searchAliases pattern). APK grows ~2 MB; the alternative (deriving the URL on-device from year + set + hero + cardNumber) is brittle because the encoding isn't a single deterministic function over those fields.

**The render-parity gap on Android.** `ResolvedPricing.listedLow/avg/high` and `recentLow/avg/high` were already computed by the Android `marketValue()` resolver but never displayed — `CardDetailScreen` only rendered the headline value + raw listing rows. The user saw a count ("11 active eBay + Whatnot listings") with no anchoring price range, while iOS and web showed the full LOW/AVG/HIGH band. Fixed by introducing `PriceTriGrid` + `PriceSingleAnchor` Material 3 composables (Surface(surfaceContainerLow) + Row of weighted Columns + VerticalDivider) — NOT a port of the iOS BOBAPriceTile chrome. M3-native, but the labels and behavior match across platforms.

**How to apply.** Any new pricing surface (deck-pricing aggregate, Collection value detail, sealed-product detail) uses the locked vocabulary above. Any new footer affordance on the pricing section gets its URL builder shared verbatim across the three platforms; "the same card opens the same external page no matter which client" is the test. Any catalog field a client renders to the user must be in the slim bundle (or the canonical bundle the slim is derived from) — verify with `python3 -c "import json; print(json.load(open('assets/data/cards-slim.json'))[0].keys())"` before shipping. The PARITY.md §8 row for "Pricing panels" stays ✅✅✅ only as long as this entry holds.

## 062 — Pricing parity is verified end-to-end, not "the function exists"
*2026-05-28*

Codifies the test discipline missed in v2.388 + v2.392. The pricing-system parity check that ratified v2.388 confirmed the **resolver shapes matched** (iOS / web / Android all had a `marketValue()` function ranking Recent Sales → Listed Range → Buy Now → Estimate) but never traced what each platform actually rendered for a card in each input state. Two platform-specific gaps shipped behind the same architectural facade:

- **iOS** had `fetchEstimatorBucket` and a Tier 3 `marketValue` branch, but the only caller was `CollectionStore` (refresh-values batch). `PricingSection.fetch()` — the card-detail UI flow — never called it. The resolver's estimate branch only fired on a legacy worker-embedded sold response that never happens for cards with no live eBay data; the branch was unreachable from production input.
- **Android** correctly fetched `MarketEstimate` in the VM and stashed it in `pricingState.marketEstimate`, but `marketValue()` didn't accept estimate as input AND `CardDetailScreen.PricingPanels` had no `hasEstimate` branch. The data reached the screen and the screen ignored it.

Both gaps were invisible to the "the function exists, the resolver shape matches" check; both were caught the moment a real estimator-only card (BLBF-203 Crews-Missle) was opened on each platform.

**Principle — parity is about the render the user sees, not the internal API surface.** A function existing on each platform is not parity. A `marketValue()` accepting the same inputs is not parity. **Parity is what shows in the pricing panel for a card in each input state.** Anything else is the same kind of trust-erosion the picker (#060) and the rarity overlay (#061) both shipped: a panel that looks unified at the architectural layer but renders inconsistently at the user layer.

**The seven-state pricing render matrix** — every pricing change is verified against this on all three platforms before shipping. Each state is reproducible against a real Worker response; pick a card whose `/comps`, eBay-proxy, Whatnot, and `/estimate` outputs match the row.

| State | Inputs | Expected render |
|---|---|---|
| **A** Estimator-only | sold=0, active=0, comps=0, whatnot=0, estimator=set | headline "~$X · estimated from comparable cards" + MARKET EST. tri-grid |
| **B** eBay active-only | sold=0, active>0, comps=0, whatnot=0 | headline "$X · N active eBay listings · no recent sales yet" + LISTED RANGE tri-grid + items |
| **C** Whatnot matched-only | sold=0, active=0, comps=0, whatnot=matched>0 | headline "$X · N active Whatnot listings · no recent sales yet" + LISTED RANGE + Whatnot strip |
| **D** eBay + Whatnot | sold=0, active>0, comps=0, whatnot=matched>0 | headline "$X · N active eBay + Whatnot listings · no recent sales yet" + LISTED RANGE + items + Whatnot strip |
| **E** Comps-only | sold=0, active=0, comps>0, whatnot=0 | headline "$X · based on N recent sales" + RECENT SALES tri-grid + comp rows (NO empty Buy Now placeholder) |
| **F** Comps + active | sold=0, active>0, comps>0, whatnot=any | headline "$X · based on N recent sales" + RECENT SALES + BUY NOW |
| **G** Truly empty | nothing anywhere | "No active listings or recent sales found." |

**Locked copy across platforms** (per state, per surface):

- Headline values: render in ALL three tiers (Recent Sales / Listed Range / Market Est.) when present. Web previously omitted the headline entirely; Android omitted it for Listed Range. Fixed.
- Section captions: `"N active X listing(s) · no recent sales yet"` (no "data") — drops the redundant word that drifted three section captions out of sync with three headlines that already said the same thing minus "data".
- Empty state: `"No active listings or recent sales found."` everywhere. iOS previously said "No eBay listings found." (misleading once comps + Whatnot + estimator joined the panel); Web previously said "No eBay sales or listings found." (same issue).
- Buy Now section header: rendered ONLY when active listings exist. Android previously rendered "Buy Now / No active listings" placeholder in comp-only state (state E); iOS + Web hid the section entirely. Aligned to hide.

**How to apply.** Any pricing-system change: pick a card in each of the seven states above, open it on iOS / web / Android, screenshot or describe the render, and check against the locked copy. If any platform's render doesn't match the expected row, the change isn't done. The static `boba-price-estimator` artifact + the live Workers are deterministic enough that the same card produces the same response for each platform, so this is a five-minute observation pass — the same five minutes that would have caught the v2.388 + v2.392 gaps before they shipped.

## 063 — Estimator tier-locks SUPER (1-of-1) cards to same-tier comps
*2026-05-29*

The closest-comp estimator (`scripts/build_price_estimates.py`) now (a) infers `printRun=1` for any catalog card with `element == "SUPER"` at build time, and (b) filters the priced-comp pool to Super-only peers when the target is Super. If the filtered pool is empty, the card honestly emits no estimate.

**Why.** Ben's 2026-05-29 audit found 444 of 454 SUPER cards estimated under $10 (median $3.07, minimum $2.11) — catastrophically wrong for the canonical 1-of-1 treatment. Root cause: SUPER weapon is definitionally one-of-one per `assets/data/rarity-model.json` (`weaponTier.SUPER.label = "one_of_one"`, `distributionTier 5`, `foilOnlyWeapons` includes it), but Super cards aren't physically numbered — they ARE the unique copy — so OCR never picks up a "/1" stamp and `printRun` stays None on every Super card. The similarity scorer treats `weapon_match` as a flat 4 points whether matching SUPER↔SUPER or BRAWL↔BRAWL, so the model couldn't distinguish 1-of-1 chase cards from same-treatment commons. With zero Super tracker comps in existence today, the closest-comp pool filled with cheaper Battlefoils that happened to share the cardType + variation + set + power-tier attributes (avg sim 11–12, above `MIN_SIM=9`), and the model dutifully reported the cross-tier mean as a low-confidence "estimate."

**Principle — when the canonical rarity model says a class is one-of-one, an estimate from non-peers is structurally a lie.** Lesser factors (cardType, variation, set, power-tier) describe the *kind of thing* a card is, not its *market position*. A Super hero and a Base Set hero with otherwise identical attributes occupy entirely different markets — the rarity tier IS the signal. Crossing tiers misrepresents the entire market regardless of how closely the secondary factors match. PRICING_PLAYBOOK §6's provenance-honest framing applies: better to emit nothing than the wrong number.

**Two-layer fix.** (1) The `printRun=1` inference makes Super-with-Super matches score `printRun_match=10` (the heaviest weight in `SIM_WEIGHTS`), so when real Super tracker data DOES accrue the model clusters Super peers exclusively (sim 21+) and the `MAX_SIM_GAP=4` filter excludes non-Super comps from the pool automatically. (2) The tier-lock filter closes the door when no Super peer has data — instead of falling through to cross-tier comps. The two work together: layer 1 is the long-run signal, layer 2 is the honest backstop for today's empty-pool state. Verified output: all 455 Super cards now correctly emit no estimate; coverage drops from 95% to 94% with the 217 previously-bogus estimates moved into the "honest no-comparable-data" bucket.

**How to apply.** When the canonical rarity model identifies a class as exclusively one-of-one (today: SUPER weapon; future: any treatment or weapon that lands at `weaponTier.label == "one_of_one"` or `distributionLabel == "*_1of1"`), apply both layers in `build_price_estimates.py`: (a) infer `printRun=1` so the similarity model clusters within-tier when data exists; (b) gate the comp pool to same-class peers before scoring so the model emits nothing when within-tier comps are absent. Don't extend tier-lock to non-1-of-1 rarity classes (HEX/GUM "secret rare", GLOW "ultra rare", FIRE/ICE "rare") — OCR data shows their print runs vary card-to-card (DECISIONS.md #061), so cross-rarity similarity is the right signal for them.

## 063 amendment (2026-05-29) — Super estimator emits hedged range, not silent

Original #063 silenced the estimator for SUPER cards when no tier-locked tracker peers existed (today's state — 0 Super cards in listings / sold_events / Whatnot / live eBay, verified across all four sources). Ben pushed back: silent emit loses the user signal entirely, and the cross-tier comps (same-treatment Battlefoils, same-cardType Heroes) ARE valid data points conceptually — they just need a rarity-premium adjustment + a wider band to honestly reflect the 1-of-1 chase market.

**Revised behavior** — two-mode emission:

1. **Tier-locked mode** (preferred — fires when Super tracker peers exist): the closest-comp model runs against Super-only peers exclusively. `printRun_match=10` ensures Super-with-Super clusters at sim 21+; `MAX_SIM_GAP=4` excludes any non-Super noise. Standard `low/mid/high` percentiles + `conf="med"` when avg sim is tight.

2. **Rarity-extrapolated mode** (fallback — fires when no Super peer has data): the closest-comp model runs against the full pool (cross-tier same-treatment matches dominate), then the resulting `(p25, p50, p75)` are multiplied by `SUPER_PREMIUM_(LOW, MID, HIGH) = (5, 15, 50)` to produce a hedged band reflecting where 1-of-1 chase cards trade vs same-treatment commons in adjacent sports-card markets. `conf="low"`. `basis` explicitly says "rarity-extrapolated from same-treatment comps (no Super tracker data yet; premium 5–50×)" so the UI can render the appropriate "estimated, no tracker data" framing.

**Verified output (2026-05-29 rebuild)**: 217 of 455 SUPER cards now emit hedged estimates (low/mid/high), 238 still emit nothing (those with no same-treatment-family peers at all — Inspired Ink Superfoil cards mostly). Median mid is $61 (up from $3.07); minimum mid is $32 (up from $2.11); maximum mid is $4,243 for top-chase cards like Cruze Control Inspired Ink Superfoil. None under $20.

**Multiplier tunability**: `SUPER_PREMIUM_LOW/MID/HIGH` are config constants at the top of `build_price_estimates.py` — Ben fits them once real Super tracker data accrues. The 5/15/50 defaults are pre-data sports-card-market priors; they intentionally err wide on the high side to communicate "this card sits somewhere in a wide range; the tracker doesn't have a precise number yet."

## 063 amendment 2 (2026-05-29) — Estimator audit framework

`scripts/audit_estimator.py` ships as the standing audit framework — Ben's explicit ask after the Palmer SFA-24 investigation: "I'd like to not tell you individual cards I notice are not getting estimated correctly. Document what you need so I can compact and keep working on these pricing issues."

The script runs seven audits, each capturing a real failure mode this codebase has hit (full catalog in [[reference_estimator_audit_framework]]). Cards flagged by ≥2 audits surface as the cross-audit priority list — the highest-confidence wrong estimates. Output is also written to `assets/data/price-estimates-audit.json` so the next session can diff against the prior run.

**Codifies the workflow.** When picking up any estimator outlier work going forward: (1) run `scripts/audit_estimator.py` FIRST; (2) read by pattern, not by card; (3) tune the script's constants (SIM_WEIGHTS, multipliers, MIN_SIM, etc.), not the catalog — except for canonical truth (the SUPER → printRun=1 catalog change was correct because the rarity model says SUPER IS 1-of-1); (4) re-run the audit after every fix to verify no regressions elsewhere.

The script's first run already surfaced multiple actionable patterns the previous spot-check workflow had missed: SUPER median ($46) below HEX ($225) and GUM ($228) — the tier-locked path needs SUPER_PREMIUM bump or analogous tier-extrapolation for HEX/GUM if Ben wants strict ordering; /5 median ($2.87) far below /10 median ($287) — needs hedged premium for low-population printRun buckets analogous to Super; Inspired Ink Metallic Battlefoil STEEL cards at $1.84 across the board — cross-treatment-tier leak needing same-distribution-tier filter or analogous Super-style hedge; 22 missing estimates in ≥99% covered clusters; 7 cards flagged by both suspect_low + cluster_outlier audits as top-priority investigations.

**How to apply.** Future estimator work picks tasks from the audit output, not from individual user-reported cards. After every `build_price_estimates.py` rebuild, run the audit and skim the cross-audit list before committing the new artifact. Multipliers (SUPER_PREMIUM_LOW/MID/HIGH = 5/15/50 currently) tune in response to audit findings — bump them when SUPER median falls below tier-4 medians; reduce them when SUPER median exceeds tier-4 medians by more than rarity-model semantics warrant. Same calibration loop applies to any future tier-extrapolated class.

## 064 — Estimator strict-treatment matching + Whatnot title-parsed synthetics
*2026-05-29*

Closes the cross-treatment / cross-weapon pool-contamination patterns the audit framework (#063 amendment 2) surfaced on its first systematic run. Pre-fix headline outliers: 240 Inspired Ink Metallic Battlefoil STEEL cards estimating at $1.84 (the rarer treatment priced *below* the common Inspired Ink Battlefoil at $225); Inspired Ink Battlefoil FIRE cards estimating at $2.86 (against a real per-card market of $175-$2,000); /5 print-run cards at $2.87 median (vs /10 at $287); 7 cards flagged by ≥2 audits. Post-fix: 53 / $19+ floor (-78%), CMA-5 Mullin Debut FIRE at $205, /5 cards honestly skipped, 2 cards flagged by ≥2 audits.

**Three coordinated changes in `scripts/build_price_estimates.py`**:

(1) **Whatnot synthetic entries label themselves with title-parsed treatment, not search-query treatment.** Whatnot's search endpoint does loose word matching — a query for "Inspired Ink Metallic Battlefoil" returns 7 listings none of which actually mention "Metallic", so the pre-fix synthetic entries got labeled `treatment="Inspired Ink Metallic Battlefoil"` while carrying prices that were really for Inspired Ink Battlefoil ($99-$328). The IIMBF pool filled with prices that didn't belong, and 240 cards averaged to a wrong-treatment median. Fix: parse treatment from the listing TITLE (longest substring match wins → most specific treatment). When title and search disagree, the listing still contributes — to its CORRECT treatment's pool, leaving the rarer treatment honestly empty. Listings with no parseable treatment get dropped (was: kept as ambiguously-labeled synthetics).

(2) **Strict-treatment requirement for tier ≥ 1 (non-Base) targets.** Combined-factor scoring is right for Base Set commons — LeBoss Base Set FIRE and Maverick Base Set FIRE are genuinely the same market at $3-5, and the model correctly bridges them via weapon+cardType+power_tier. But for treatment-tier ≥ 1 (every non-Base treatment: Battlefoil family, Inspired Ink family, Blasts, Headlines, etc.), each treatment is its OWN market, and cross-treatment matches let cheap Base Set FIRE commons (sim 11 via weapon+cardType+power_tier+both_unserialized) leak into chase Inspired Ink Battlefoil FIRE pools, dragging the chase to $2.86. Fix: when target's `treatment.distributionTier >= 1`, peer must match treatment exactly or it can't comp. Coverage drops 96% → 76% — that's the right trade: lose 20pp of fabricated cross-treatment estimates, gain honest "no comparable data" for cards whose treatment-specific market doesn't have tracker data yet. Strict-treatment skips in rarity-extrapolated mode (the SUPER 1-of-1 hedge path, #063 amendment 1) since that path's whole purpose is to use cross-treatment comps with a multiplier — gating it on treatment would empty the fallback too.

(3) **Wide-gap fallback when MAX_SIM_GAP clips below MIN_CARDS.** The gap filter (`top_sim - 4`) exists to keep a /5 chase top-comp from being averaged with sim-9 Base Set commons. But when the priced pool has 2 unusually-tight peers (e.g., the Whatnot per-card hits for BLBF-249/255 GLOW at sim 22) and the rest of the same-treatment pool sits at sim 13-17, the filter drops the next tier and leaves < MIN_CARDS comps — the card gets skipped despite a well-covered cluster. Fix: when gap-filter clips below MIN_CARDS, fall back to top-MIN_CARDS regardless of gap and mark `conf="low"` with a "few in-cluster peers — wide-gap fallback" basis suffix. This closes the missing-in-cluster pattern audit #6 catches (22 → 0).

Plus a config bump (`SUPER_PREMIUM_LOW/MID/HIGH = 25/75/250` first, then `35/100/300`) to lift the rarity-extrapolated SUPER median above tier-4 GUM/HEX medians so the canonical weapon-tier ordering (audit #1) holds at the top end.

**Principle — each treatment is its own market; tier ≥ 1 means "respect the market boundary".** Combined-factor scoring is generous by design — it lets a card find comps via any combination of factors reaching `MIN_SIM`. That's the right model when the catalog factor-space genuinely shares pricing (Base Set commons), and it's the wrong model when treatments encode market segments (every non-Base treatment). The fix doesn't override the scoring; it adds a gate before scoring runs. Same shape as #063's tier-lock for SUPER weapons.

**Verified output** (2026-05-29 rebuild): suspect-low estimates 240 → 53 (-78%); cards flagged by ≥2 audits 7 → 2 (-71%); missing-in-cluster 22 → 0 (-100%); SUPER median $46 → $307 (canonical tier ordering: SUPER > GUM > HEX > GLOW > FIRE/ICE > STEEL); IIB FIRE Mullin Debut $2.86 → $205; IIMBF STEEL honestly skipped (no tracker data). Coverage 96% → 76% — the 3,775 cards that lost estimates are now in the honest "no comparable data" bucket (consistent with PRICING_PLAYBOOK §6's provenance honesty: better to emit nothing than the wrong number).

**How to apply.** New treatment in catalog → check `rarity-model.json` lists its `distributionTier` (build_rarity_model.py mints these from `promo.bobattlearena.com` guides). New estimator failure pattern → first run `scripts/audit_estimator.py`, find which audit fires, then tune the relevant constant: `SIM_WEIGHTS`, `SUPER_PREMIUM_*`, `STRICT_PRINTRUN`, the treatment-tier threshold (currently `>= 1`), or `MAX_SIM_GAP`. Don't extend strict-treatment to Base Set — base-set cross-comping is what gives common commons a useful estimate. Don't extend strict-printRun to /10, /25, /50 — those have wider markets that the closest-comp model handles correctly. The two strict gates exist to enforce market boundaries that the combined-factor score genuinely can't see; further gates need a similar concrete failure pattern in the audit before they're justified.

## 064 amendment (2026-05-29) — Strict-weapon for tier-4 + weapon-tier extrapolated fallback

Same workflow loop as DECISIONS.md #064: rerun the audit, find the next pattern, fix it, repeat. After the strict-treatment + title-parsed-synthetic landing, the audit still flagged 2 cards as top-priority (cluster_outlier + suspect_low both): **RAD-306 Time 80's Rad Battlefoil First Edition HEX at \$12.30** and **BGBF-12 Cruze-Control Battlefoil First Edition GUM at \$10.65** — both tier-4 (secret_rare) weapons priced like tier-1 commons.

Root cause: strict-treatment forces same-treatment peers, but combined-factor scoring still lets cross-weapon peers within the same treatment dominate. 80's Rad Battlefoil has only 10 D1 listings (4 BRAWL median \$80, 4 ICE \$17, 2 STEEL \$21) — zero HEX. So RAD-306 HEX target matched the cheap STEEL/ICE peers at sim 14 (treatment+cardType+variation+power_tier+both_unserialized) and inherited their median. The strict-weapon gate is what's needed — HEX/GUM/SUPER targets must find same-weapon peers within their treatment market or skip honestly.

**Two-mode emission for tier-4 weapons** (mirrors SUPER's tier-locked + rarity-extrapolated pattern from #063 amendment 1):

1. **Tier-locked mode** (preferred): when ≥ MIN_CARDS same-treatment same-weapon peers exist, use them exclusively. Tight estimate, conf="low" (small pool typical for tier-4 weapons within a single treatment).

2. **Weapon-extrapolated mode** (fallback): when fewer than MIN_CARDS same-weapon peers exist, retry without the weapon gate and apply a weapon-tier premium multiplier downstream. `WEAPON_TIER4_PREMIUM_LOW/MID/HIGH = 3/6/12` reflects HEX/GUM trading at 3-12× same-treatment STEEL/BRAWL commons in adjacent sports-card markets. Smaller spread than SUPER's 35/100/300 because HEX/GUM populations vary card-to-card (not strict 1-of-1), so the band is tighter. `basis = "rarity-extrapolated from same-treatment cross-weapon comps (no {weapon} peers in this treatment; premium 3–12×)"`, `conf="low"`.

**Verified audit deltas (2026-05-29 rebuild)**: 2 → 0 cards flagged by ≥2 audits (-100%); suspect-low 53 → 5 (-90%); HEX coverage restored 65.7% (strict-only had crashed it to 17.5%); HEX median \$295 (was \$147 pre-#064, \$245 with strict-only — \$295 is in canonical tier-4 zone); RAD-306 HEX \$12.30 → \$73.80; BGBF-12 GUM \$10.65 → \$225.50. The /1 vs /10 weapon-tier inversion (SUPER median \$307 < /10 median \$1722) is now an honest market signal: /10 cards have real chase tracker data (LeBoss IIS Glow style listings at \$287+), /1 SUPER has zero — the SUPER hedge tops out at \$307 mid because the rarity-extrapolated base is small. Audit's "/1 < /10" warning is the right pattern to surface; the resolution is "honest data limitation, not a scoring bug."

**Why a different multiplier band than SUPER** (3-12× vs 35-300×): SUPER cards are canonically 1-of-1 (every SUPER card is unique, period). HEX/GUM cards have varied print runs (Inspired Ink Hex /5, regular HEX unnumbered with population in hundreds, etc.) — the rarity tier signals "rare", not "unique". The market premium over same-treatment commons should be 1 order of magnitude (~10×), not 2-3 orders (~100×).

**How to apply.** Tune `WEAPON_TIER4_PREMIUM_*` in response to audit drift, same loop as `SUPER_PREMIUM_*`. Don't extend strict-weapon to GLOW (tier 3) without similar audit evidence — GLOW's coverage already dropped to 63.8% with just strict-treatment; adding strict-weapon without a fallback would tank it. Don't extend to FIRE/ICE (tier 2) — those genuinely cross-weapon comp within treatments (FIRE/ICE Inspired Ink Battlefoil pricing is similar). The weapon-extrapolated fallback works specifically for tier-4 because HEX/GUM markets are sparse enough to need both gates AND backfill.

## 065 — Daily pricing automation: GitHub Actions ONLY (no laptop dependency), NOT Cloudflare Worker cron
*2026-05-29 · amended 2026-05-30*

The post-#064 audit-driven calibration loop made the estimator improvable PER REBUILD; the open question was how to drive rebuilds without manual intervention. The answer ratified by Ben: a daily **GitHub Actions workflow** (`.github/workflows/pricing-daily-refresh.yml`) that refreshes stale tracker data, rebuilds the artifact, runs the 9-audit framework, tracks history, gates regressions, emits calibration recommendations, and `git push`es the new artifact. End-to-end documentation: `PRICING_AUTOMATION.md`.

**One alternative rejected**:

**Cloudflare Worker cron** — wrong fit. Worker free-plan has a 50-subrequest-per-invocation cap (the same wall that pushed the tracker to the push model in #058) and a 10ms-CPU cap. The daily refresh makes ~1,700 sequential HTTP calls (eBay + Whatnot refresh + stratified crawl) and runs a Python statistical pipeline on 17,974 cards. That's structurally not a Worker workload — Workers are for short, latency-sensitive client-path requests, not long batch jobs. Also: Workers can't `git push` to the repo, and the artifact lives in the repo so GitHub Pages can serve it to the `boba-price-estimator` Worker's `ESTIMATES_ARTIFACT_URL`.

**Why GitHub Actions (and only GH Actions)**:

1. **Independence from any laptop**. The whole point of the pipeline is continuous improvement without dependence on any single machine being awake. Ben's Mac sleeps, travels, restarts, and occasionally drops off Wi-Fi. The estimator shouldn't pause for any of those.
2. **One credential, well-scoped, in a known place**. `CLOUDFLARE_API_TOKEN` with `D1:Read` on `boba-pricing` lives in repo secrets — visible to repo admins, rotatable, revokable. Versus a local OAuth cache that's invisible to anyone but the laptop owner.
3. **Failure surfaces in one place**. The Actions UI shows red runs at a glance; the regression gate opens issues with the `pricing,regression,automated` label. Compare to: launchd logs only on the originating Mac.
4. **Reproducibility**. Ubuntu-latest is a deterministic environment; manual test runs via `workflow_dispatch` are first-class. The workflow file IS the build spec — the repo carries everything needed to reconstruct + audit the daily loop.

**Trade-off accepted**: one new credential (`CLOUDFLARE_API_TOKEN`) added as a repository secret. That's the cost of decoupling the pipeline from any laptop. The token has minimum scope (`D1:Read` only) and can be rotated in <5 minutes at [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens).

**2026-05-30 amendment**: an earlier version of this entry shipped a parallel local-launchd path (`scripts/com.bobaplaybook.pricing-daily.plist` + `scripts/daily_pricing_refresh.sh` + `scripts/install_pricing_cron.sh`) as a documented alternative. Ben removed it: *"I want to make sure that we are transitioning to the cloudflare workers entirely for the future. … the whole point is to make it so that the estimator and the data is getting better over time without being dependent upon my mac running."* The launchd files were deleted; the documentation was rewritten to position GH Actions as the only path. Local execution of the scripts during development is fine for diagnosis, but **the artifact ships only from CI**, never via force-push from a local rebuild. (The principle: local rebuilds drift from CI in subtle ways — Whatnot proxy response variation, D1 query timing, Python version diffs. When a regression happens, fix the SCRIPTS in the repo, push, and let CI rebuild.)

**Why daily, not hourly or weekly** — daily matches the cadence of (a) tracker D1 growth (push-model fills proportional to user traffic which has 24-hr periodicity), (b) eBay's typical listing-vanish window (most vanish-inferred sold events resolve in 1-3 days), and (c) the Worker's 10-min memo + 10-min edge cache (anything sub-daily would just serve cached data anyway). Weekly would miss the post-#064 "tier ordering drift" window where a single chase listing's vanish moves a multi-day median.

**Why a `recommendations` file, not auto-applied tunes** — the calibration script (`scripts/calibrate_estimator.py`) writes `assets/data/pricing-calibration-recommendations.json` for Ben to review periodically; the cron does NOT edit `build_price_estimates.py` constants. Auto-applying creates feedback loops on noisy days (a single fresh chase listing inflates a weapon's median → calibration lowers the multiplier → next day the listing vanishes → multiplier is too low → entirely new set of suspect-low cards → calibration bumps it back). Human-in-the-loop breaks the loop. (PRICING_AUTOMATION §6.)

**Why the regression gate is critical-only, not strict** — strict gating (fail on every warning) would block legitimate days where, e.g., a small tracker D1 shift moved a weapon median 50%+ once and then stabilised. Critical-only gating (`two_plus_flagged`, `missing_in_covered_clusters`, `outlier_rich_clusters` reappearing from 0 → ≥1, or coverage dropping >5pp) catches the structural-bug class without being noisy. The Worker still serves yesterday's artifact when the gate fires, so users never see a bad estimate — a tradeoff that prioritises correctness over latest data.

**Future-proofing**: the layer separation is the load-bearing decision. `audit_estimator.py` writes JSON → `track_audit_history.py` reads JSON → `check_audit_regressions.py` reads history → `calibrate_estimator.py` reads history. Each layer is schema-agnostic where possible — new audits append to history's `audit_counts` dict automatically; new regression gates are one-line additions to `CRITICAL_RULES`; new calibration patterns are one-function additions. The orchestrator's only hard-coupled assumption is the file paths. Switching from launchd to GH Actions (or back) doesn't change any script — only the trigger.

**Free-tier budget verification** (across all daily steps): ~1,200 eBay Browse calls (24% of 5K/day free), ~1,700 Cloudflare Worker requests (1.7% of 100K/day free), ~5 D1 reads, ~25 GH Actions minutes (unlimited on the public BOBA repo), ~50 KB/day storage growth. The single repository secret needed is `CLOUDFLARE_API_TOKEN` with `D1:Read` on `boba-pricing` (PRICING_AUTOMATION §7).

**How to apply.** When extending the loop with a new step, the questions are: (a) does it fit a GH Actions step (Python/wrangler/curl/git) or does it need to be a Worker (latency-sensitive client-path)? (b) does it cost <100 calls on any quota in the daily budget? (c) does it write to a file in the repo or to an external state store? Almost always the answer is "yes-yes-file" and the extension fits the existing orchestrator shape. The first time the answer is "no" to (a), reach for a separate Worker; the first time it's "no" to (b), shard the load across days or weeks.
