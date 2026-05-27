# BOBA Playbook — Architecture & Technology Decisions

Entries capture the *why* behind choices — not just what we decided but what principle it encodes. Technical details that anyone can read from the code don't belong here. The question every entry should answer: *what would the next developer get wrong if they didn't know this?*

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

## 005 — Dual-Platform Feature Parity Model
*2026-04-03*
Both platforms implement the same core feature set. Platform-specific implementation is acceptable; platform-exclusive features are the exception, not the rule. Track parity in SCRATCHPAD.md.

## 006 — App Name and Brand Identity
*2026-04-03*
Display name: BOBA Playbook. Xcode product: BOBAPlaybook (no hyphens). Design language: Retro-futurism + cyberpunk + glassmorphism. Palette: battle orange / cyber cyan / deep violet on near-black (hexes in #010). Card art is always the focal point — UI chrome frames it, never competes.

## 007 — Supabase for Auth and User Data Only
*2026-04-03*
Supabase handles auth, `user_cards`, `decks`, `deck_cards`. Card catalog browsing uses static JSON — no DB query needed. **Supabase Storage is NOT used** — the free tier would exhaust quickly for a card image app.

## 008 — Cloudflare R2 for Image CDN
*2026-04-03*
Card images live on R2 (`boba-card-images`). Zero egress fees and Cloudflare edge caching. Two tiers: `thumbs/` (200px WebP, ~10KB) for grids; `full/` (≤1200px WebP, ~80KB) for detail views. **Never hardcode R2 URLs** — always use CDN helpers in `CDN.swift` / `js/api.js`.

## 009 — Static Card Catalog JSON
*2026-04-03*
`cards.json` (17,739 cards) committed to `assets/data/` and served from GitHub Pages. No database for catalog browsing. To update for new sets: re-run `reconcile_all.py`, copy outputs to `assets/data/`, commit.

## 010 — Element Color System
*2026-04-03 · amended 2026-05-25*
Each element maps to a canonical UI color: FIRE #FF4D00, ICE #00BFFF, HEX #8B00FF, STEEL #8A9BB0, BRAWL #C0392B, GLOW #FFD700, GUM #FF69B4, SUPER #FF00FF, ALT #B084CC, CYBER #39FF14, NONE #666680. Elements in cards.json are always UPPERCASE. Codified in `Design.swift::element(_:)`, `Color.kt::BobaElements`, and `styles.css` `:root --el-*`.

**ALT + CYBER added 2026-05-25** (bobaId v3 audit #057 surfaced 48 ALT + 28 CYBER cards). Neither is a traditional gameplay weapon — ALT is the weapon-slot value on parallels (Billy Cameo Alt Arts, Sidekicks, etc.), CYBER is the "2025 Cyber Promo" set — but both render in the weapon spot, so they need first-class color tokens. CYBER's neon green matches the promo art; ALT's lavender stays distinct from the other purple-family weapons (HEX, SUPER, GUM).

## 011 — No Card Images in Git
*2026-04-03*
Card images live exclusively on Cloudflare R2. `assets/data/` contains only JSON. Keeps clone fast and avoids GitHub's soft 1 GB storage limit.

## 012 — Scan Mode: On-Device Vision Only
*2026-04-03*
Card identification uses iOS Vision (`VNRecognizeTextRequest`) and AVFoundation only. No image is uploaded. Pipeline: OCR frame → card number regex `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)` → match display-cards.json. Falls back to manual search.

**Principle**: User data stays on user devices. On-device processing is not a technical constraint here — it's the right choice for the user.

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

## 020 — Web Layout: Body Flex Column, No viewport-fit=cover
*2026-04-04*
`body { height: 100dvh; display: flex; flex-direction: column; overflow: hidden }` with `main { flex: 1; overflow-y: auto; min-height: 0 }`. The body does not scroll — content scrolls inside `main`.

**Why**: `position: fixed` headers land in a separate GPU compositor layer that Safari browser-mode misorders during address-bar transitions, causing content to bleed into the Dynamic Island. Body flex-column keeps the header in document flow. Reference: `github.com/bhwilkoff/Bsky-Dreams`.

**Consequences**: No `viewport-fit=cover`, no `env(safe-area-inset-top)`. IntersectionObserver must use `root: document.getElementById('main-content')`.

## 021 — Play Mode: Static Reference Content, Supabase for User Decks
*2026-04-05*
Rules, strategy guides, archetype templates, and the collecting guide are static/local — no auth required. User-created decks save to Supabase `decks` + `deck_cards` and require sign-in.

**Why**: Reference content belongs to everyone, immediately, without friction. Personal decks have identity — your choices, your strategy — and should persist across devices like the collection does.

## 022 — SwiftUI ScrollView Width: VStack Parent Must Have frame(maxWidth: .infinity)
*2026-04-06*
Any `VStack` that directly parents a `ScrollView` AND switches content conditionally must have `.frame(maxWidth: .infinity)`, or the ScrollView receives variable proposed widths per mode, causing horizontal rubber banding.

**Root cause**: SwiftUI's VStack sizes to the max of its children's natural widths. When that width varies by mode (e.g., Rookie = 228pt, Substitution = 361pt), every child ScrollView inherits that instability. Apply the frame constraint at the outermost VStack first.

## 023 — Mod Accounts: Role-Based Access via user_profiles
*2026-04-07*
Moderator roles live in a `user_profiles` Supabase table (`role`: user | moderator | admin). Role is never stored client-side permanently — fetched post-auth and cached in-memory for the session. Card corrections → `card_corrections`; image overrides → `card_image_overrides`; both require mod/admin role enforced by RLS. The catalog is static JSON, so corrections decouple user-submitted fixes from the release cycle.

## 024 — iOS Image Loading: Show Thumb Immediately While Full Loads
*2026-04-13*
When opening a card detail view, `CardImageView` shows the cached grid thumb immediately instead of a spinner (it's almost always cached — the user just saw it), then loads full-res in the background and swaps it in.

**Why**: A spinner for something the user just tapped creates a gap between intention and response. Showing the card immediately — even at grid resolution — confirms the right card is loading. Immediacy builds trust; spinners create anxiety.

## 025 — Feature Gating: Keep Code, Hide UI Entry Point
*2026-04-13*
When a feature is built but blocked on external dependencies (Discord trade room waiting on bot setup, eBay Market Feed waiting on API scope), keep all implementation code in place and gate at the single UI entry point. Don't delete or hollow out working code while waiting.

**Why**: Building ahead of infrastructure is sometimes unavoidable. Half-deleting code is worse — the feature is harder to re-enable and the codebase is ambiguous. A single `if featureEnabled { ... }` flag at the call site is the right level of intervention; re-enabling should be one-line. **Applied to**: Discord FAB in `CollectionView.swift` (commented call site, implementation intact); web `fab.hidden = true`.

## 026 — Image-Byte Collision Guard in Pipeline
*2026-04-13*
`reconcile_all.py::step11_optimize_images` ends with an md5-uniqueness check across the image tiers: any group of files resolving to different `(cardNumber, hero)` keys but sharing identical bytes is flagged to `image_collisions.json` with a per-tier remediation hint.

**Why**: the bobaId scheme enforces "One ID per Card" at the catalog layer, but nothing enforced "One Image per Card" at the CDN-payload layer. Caliber #24 once showed D-Harp's art — an optimizer run had silently overwritten Caliber's webp with D-Harp's bytes (cards.json was correct); only md5 comparison of the outputs catches this (a post-mortem found 35 such pairs).

**How to apply**: if `image_collisions.json` is written after a run, STOP — don't sync to R2 until every group is resolved. The `notes` field says whether to delete bad outputs and re-run step 11 (tier-level) or re-download source art (master-level); when correct art doesn't exist publicly, reclassify into the missing-art queue and let `ebay_missing_images.py` recover it.

**Principle**: Every invariant the app relies on should be enforced where it can be measured. "One Image per Card" lives in binary content, so the check runs against binary content.

## 027 — User-facing terminology: "Weapon" not "Element", "Treatment" not "Rarity"
*2026-04-23 → 2026-04-24*
The catalog field name is `element` (FIRE / ICE / STEEL / etc.); user-facing strings everywhere call it **Weapon**. The `treatment` field carries the print variant; user-facing strings call it **Treatment** — except the one Learn-tab section explicitly discussing *rarity by weapon type*, where "Rarity" is the right word.

**Why**: Every BoBA collector calls them weapons; "Element" is leftover schema language. "Rarity" is a TCG term that conflates two BoBA things: the hero's intrinsic scarcity (tied to weapon) and the print variant (the treatment). Splitting them matches the community vocabulary.

**How to apply**: Field names in code stay (`element`, `treatment`, `rarityLabel`, `rarityTier`). Anything rendered to a user uses Weapon and Treatment. The exceptions: the "RARITY BY WEAPON TYPE" Learn header (intentional) and internal helper names.

## 028 — Treatments vs Parallels are distinct concepts
*2026-04-24*
Sourced from BoBA-expert audit (Griffey checklist + official `bobattlearena.com/collecting-basics`).

**Treatments** are different ways a single card can be printed: Base Set, the Battlefoil family (seven color subsets), the themed foils (Blizzard, Alpha, Linoleum, Icon, Logofoil, Slime, etc.), Inspired Ink (= Serialized), and Superfoil. Each has a card-number prefix mapping to the treatment. **Parallels** are entirely separate card runs with their own numbering: Billy Cameo Alt Arts, SideKicks, Plays, Bonus Plays, Prize/Promos, Hot Dogs. **Inspired Ink = Serialized**, hand-stamped serial numbers tied to the hero's weapon: Hex /5, Glow /10, Fire /25, Ice /50.

**Why**: The prior "Parallels & Treatments" section bundled them, confusing new collectors. Splitting matches how veterans talk and the official taxonomy.

**How to apply**: Learn → Collect has separate "TREATMENTS" and "PARALLELS" sections; card-detail uses "Treatment" for the print variant. Future scrapes / corrections / Cowork handoffs must never collapse a Parallel into a Treatment in the catalog data.

## 029 — Card-detail canonical 6-cell layout
*2026-04-24*
Every card-detail surface (iOS view, web modal) renders the same 6-cell stat grid in a 2-column layout, in this exact reading order:

```
Card #     │ Type
Treatment  │ Weapon
Set        │ Sub-set
```

Card-type-specific extras (Cost + DBS for Plays) render BELOW the canonical 6 — never interleaved.

**Why**: A consistent layout means coaches find any field with one glance. "Same shape on every card" builds visual literacy with the catalog. Sealed products skip Treatment + Weapon; empty Sub-set renders as `—` rather than collapsing the row (which would shift everything beneath).

## 030 — Practice executor: persistent-effect engine architecture
*2026-04-24*
Two parallel state arrays on `PracticeStore`: `persistents` and `weaponTransforms` (split out so the hot-path weapon read consults a flat array). One entry point `installPersistent` routes specs into the right array; one dispatcher `firePersistentTriggers` fires non-continuous effects; every positive HD change routes through `applyHDRecover` (redirect → cap → delta → block, negative bypasses); one `isScopeActive` evaluator (unknown scopes return false — safe no-op).

**Why**: Centralizing install + lifecycle + scope eval in three helpers means future op families need only per-op behavior — plumbing is free.

## 031 — First-run hint system
*2026-04-24*
`HintsManager` (`@Observable`, UserDefaults-backed) tracks dismissed hint IDs per device. `HintBanner(id:title:message:)` renders nothing if dismissed OR the global toggle is off; tapping X dismisses permanently. Settings has a master toggle + "Reset hints".

**Why**: The teaching moments from the practice-battle UI (substitution positioning, deck composition triad, bonus play ceiling, etc.) need to surface at the right moment but never lecture experienced coaches twice. One-shot per device + global silence + reset gives full control without removing teaching value for newcomers.

**Inlined into `Design.swift`** rather than its own file — Xcode's synchronized-group sometimes fails to pick up new Swift files; co-locating with an existing target sidesteps it.

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

## 034 — COMC asking-price as second BUY NOW source (NOT in sold-comp waterfall)
*2026-04-29*
COMC.com exposes 931 BoBA listings matching cards.json. Wired as a parallel BUY NOW source alongside eBay actives (iOS `ComcService` + web `fetchComcListings`).

**Critical: COMC asking stays OUT of the sold-comp waterfall.** eBay sold → Market Est. measures TRANSACTED prices; asking runs ~10-25% above sold, so folding it in inflates the estimate. COMC is purely additive on BUY NOW (where to buy), not pricing (what it's worth); each row reads "COMC asking · Ungraded NM".

**Turnstile blocked.** COMC turned on a Cloudflare managed-JS challenge after recon; `boba-comc-proxy` detects `challenged: true`, returns `count: 0`, clients soft-fail. Bypass requires Browser Rendering API / Playwright. Defer until COMC's WAF stance changes (memory `feedback_comc_blocked_all_platforms`).

## 035 — Unified card recognition: image fingerprint primary, OCR as confirmation
*2026-04-30*
All five scan modes route through `ScanMatching.resolve(...)`. The prior design treated OCR cardNumber as primary, which silently failed when OCR returned a real-but-wrong number (partial "BHBF-37" arriving as "20" returned a real card at "20", no veto, wrong commit).

**Redesign:** image fingerprint (`feature-prints.bin`, 16,123 cards / 12.7 MB) is the primary identifier; every signal contributes candidates and scores: FP top-30 by L2 distance form the pool, refined by OCR cardNumber, hero name, and element/treatment/power. **Hero veto:** any candidate whose hero isn't in a clearly-named top-left set gets −2.0 (the missing piece the waterfall lacked). Confidence floor 1.4, margin floor 0.3 — below either, the resolver returns nil ("Not identified").

**Why FP primary:** OCR fails partially in success-looking ways (silent-wrong); FP fails completely in failure-looking ways (resolver returns nil; user retries). Silent-wrong is the worst possible UX for card recognition. (`GridCardDetector` also perspective-corrects from each anchor's quad with lane-spacing-sized bleed — fixed the prior ~22% under-detection; see `[[feedback_vision_rect_under_detection]]`.)

## 036 — Wall + Price Overlay: lift from streamer-only gate
*2026-05-03*
Per DESIGN.md §8.4 + §8.8, Wall display mode and Price Overlay become first-class for every collector — not streamer-gated. **Partially supersedes [#025](#025)** for these two features (the principle still applies to genuinely-blocked features like the Discord trade room).

**Lifts:** Wall is a Collection display mode + accessible from Decks ("Generate deck wall") + Find multi-select ("Wall these N cards"). Price Overlay is a Wall-view toggle with per-designation defaults (For Sale / Trade / Wanted ON; Grails + Personal OFF). `CollectionWallSheet` wraps `ShowWallComposer` (pure composer; gate was at invocation only).

**Stays gated to streamers:** Whatnot "My Shows" management; per-show wall generation inside the Shows tab; community trade room. **How to apply:** expose Wall + Price Overlay to all signed-in users; don't add new role gates.

## 037 — Profile redesign: username = display name = public handle
*2026-05-04*
Single `username` field doubles as display name AND public-collection slug (`bobaplaybook.com/u/{username}`). No separate `display_name` — two parallel name fields drift confusingly (Discord's conflation is the cautionary tale). iOS auto-derives from the email local-part (suffixes on collision); Discord-OAuth users with no email fall back to `user-{6-char-hash}`. Inline edit with debounced `check_username` → status pill.

**Banned-words gate, two layers:** (1) client `banned-words.json` (~270 entries) for an instant red pill, zero network; (2) server `banned_words` table as the authoritative gate via `check_username` / `set_username`. Reserved infra terms are gated separately.

**Why two layers:** usernames are public + persistent + a harassment vector. Cost of a slur on a public URL >> friction of "try ben2 instead." The server gate also protects from client-bundle drift.

## 038 — Profile redesign: generalized role-request (mod OR streamer)
*2026-05-04*
The mod-request flow generalized to a `request_role(role, reason)` RPC accepting `'moderator'` or `'streamer'`; the admin queue returns both kinds and promotes to whichever was requested. Old mod-only RPCs kept as delegating shims through the deploy window; migration is additive. **Why:** streamer always needed a request flow; one mechanism is cheaper than two.

## 039 — Profile redesign: deferred features
*2026-05-04*
Three Profile features ship with UI ahead of backend so the surface is complete:

**(a) Trade match alerts** — toggle persists to `user_profiles.match_alerts_enabled`; the matching pipeline (Wanted/Grail overlap → APNs fan-out) is multi-week, blocked on a server-side dispatcher.

**(b) Public collection sharing** — IMPLEMENTED 2026-05-04. Toggle on `user_profiles.public_collection_enabled`; web `bobaplaybook.com/u/{username}` live via `get_public_collection(handle)`. Projection excludes prices/notes and filters out Wanted (public = "what they have").

**(c) Account deletion** — IMPLEMENTED 2026-05-05. `boba-account-delete` Worker verifies a Bearer JWT then admin-DELETEs with a service-role secret. FK CASCADE clears user data; `card_corrections` / `card_image_overrides` SET NULL (audit trail survives anonymously).

**Why UI ahead of backend:** removing toggles later = worse UX; opt-in data is useful signal once backend ships; deletion is needed for App Store compliance.

## 040 — Profile pictures: Discord-default, R2-on-upload
*2026-05-05*
Three-tier resolver: **custom (R2) → Discord avatar → default silhouette.** Most users auth via Discord OAuth → recognizable avatar at zero storage cost. Avatars live in the existing R2 bucket; the `boba-avatar-upload` Worker verifies a Bearer JWT, caps at 2MB, writes R2.

**Security:** RPC `set_avatar_url` is own-row + **rejects URLs not matching the R2 avatars prefix** — without this, a malicious client could point `avatar_url` at tracking pixels or inappropriate images rendered on others' devices.

**Why R2+Worker, not Supabase Storage:** R2 (#008) = zero egress + edge cache + auth-free CDN; Supabase Storage avoided per #007.

## 041 — Android: Kotlin + Jetpack Compose (not KMP / CMP / Flutter / RN)
*2026-05-19*
Native Kotlin + Compose, separate from iOS Swift/SwiftUI, same monorepo (`/android/`). iOS is shipped Swift-native (#004); a KMP "common module" migration would mean rewriting iOS — we're not doing that.

**Why:** KMP works best when both platforms start together (BOBA didn't). CMP can't render the iOS-26 Liquid Glass surfaces the iOS DESIGN.md bets on. Flutter / RN add runtime + bridge overhead for every Android API (ML Kit, CameraX, Play Integrity, biometrics) — strictly worse for Android-only.

**Future option:** if Web wants typed models or Desktop arrives, KMP is the upgrade path — keep the door open by structuring Android's domain layer as pure-Kotlin from day one.

## 042 — Android: Material 3 brand-first; dynamic color opt-in
*2026-05-19*
Android ships a fixed brand theme (orange/cyan/violet on near-black) by default — not Material You dynamic color. User can opt into "Use system colors" in Settings.

**Why:** card-art palette is the focal point; a wallpaper-derived primary fighting `#FF4D00` reads muddy. Same rule as iOS §11.2: element on content semantics, brand on chrome. The opt-in toggle recolors `primary` only (Android 12+); element colors never change.

## 043 — Android Scan: CameraX + ML Kit Text Recognition v2 unbundled; OCR-only v1
*2026-05-19 · amended 2026-05-26*
CameraX 1.5+ + ML Kit Text Recognition v2 via Google Play Services dynamic delivery (`play-services-mlkit-text-recognition`). Manifest meta-data `com.google.mlkit.vision.DEPENDENCIES = "ocr"` triggers a one-time model download at install.

**Why OCR-only v1:** #035 made FP primary on iOS due to silent-wrong failure in **grid scan** specifically. Single-card live scan with OCR + hero-name veto + confidence threshold is sufficient. Adding FP needs MediaPipe + a parallel `feature-prints-android.bin` — defer to v2.

**Why unbundled (amended 2026-05-26):** the bundled artifact triggered a Play Console "missing debug symbols" warning (ML Kit ships `.so` pre-stripped → AGP's native-symbol task produces nothing). Unbundling removes the `.so` from the AAB (Play Services hosts them), shrinks it ~11 MB, eliminates the warning, and is a one-line swap in `libs.versions.toml`; API surface is identical (install still requires being online, so the "offline" trade-off was illusory).

**Residual warning:** other pre-stripped Google `.so` files remain; a Gradle task zips them into a BuildID-matched `native-debug-symbols.zip` (`finalizedBy bundleRelease`) Play Console accepts — restores frame→library attribution, not line numbers (Google strips those). ANDROID-DEV.md §6.

## 044 — Android: NO multi-step anchored walkthroughs
*2026-05-19*
Android doesn't ship the iOS-style multi-step walkthroughs (DESIGN.md §6.10). Use `TooltipBox` + `BOBAHintBanner` (DataStore-backed); empty states carry the first-time productive action.

**Why:** iOS walkthroughs exist because tab gestures / fullScreenCover / NavigationStack are novel idioms. Android conventions (NavigationBar / push-back / FAB / ModalBottomSheet) are universally legible; reproducing the ~600-line walkthrough engine in Compose for marginal value-add is wrong-side cost/value. Onboarding splash decks rejected. Revisit only if a future feature genuinely needs anchored teaching; each iOS walkthrough has a documented Android replacement in ANDROID-DESIGN.md §6.10.

## 045 — Cross-platform push: one dispatcher Worker, two transports
*2026-05-19*
When match-alerts ship (#039 + TRADE-DESIGN.md Phase 5), the architecture is **one Cloudflare Worker `boba-push-dispatcher`, two transports (APNs + FCM)**: triggered by a Supabase webhook or cron over `trade_matches`; joins `user_devices`; routes `apns` → HTTP/2 + JWT, `android` → FCM v1 + service-account token; both batch. The payload is **symmetric** — a `match_alert` type plus `match_id`, `other_user`, `card_count`, and a `deep_link` (`bobaplaybook://matches/{id}`) that is the identical string on both platforms.

**Why Worker not Edge Function:** better cold-start; existing secrets pattern; APNs JWT via Web Crypto, FCM v1 via plain HTTPS.

## 046 — Android-specific app ID + signing strategy
*2026-05-19*
Package: **`com.bobaplaybook.app`**. Affects signing + Play Console + `assetlinks.json` + Firebase + every deep link. **Signing:** Play App Signing (mandatory since 2021) — Play resigns each release with its production key; upload-key creds in `gradle.properties` (git-excluded) + CI secrets.

**`assetlinks.json`** sits at the same `/.well-known/` path as `apple-app-site-association`; both coexist. Its fingerprint must include BOTH the upload-key AND the Play App Signing key SHA-256 — internal-testing builds (upload-key-signed) won't verify against the production key otherwise. ANDROID-DEV.md §8.5 + §14.

## 047 — Android v1 form-factor scope: phone + tablet + Chromebook (NO foldable)
*2026-05-19*
Adaptive layouts (size-class-aware scaffolds) are foundation from M1 — not deferred. **Foldable NOT a v1 target.**

**Why:** Ben has a Chromebook for testing; Chromebooks + tablets share the `EXPANDED` size class; foldables are a small share with significant hinge/posture cost. **How to apply:** ANDROID-DESIGN.md §6.6 binding from M1; every screen declares COMPACT / MEDIUM / EXPANDED (PRs without it rejected).

## 048 — Android: Practice executor IS in v1, admin-gated
*2026-05-19*
Practice executor (iOS #030 + #033) ships on Android v1, admin-gated via the same Profile-role-badge bolt-icon unlock.

**Why:** Ben wants to test Battle Practice on Android during development; the game logic is platform-agnostic (UI translation is the work); the admin gate hides it until ready. Reuse the iOS engine (#030) as pure Kotlin in `:core:domain`; Compose translates the SwiftUI screen anatomy.

## 049 — Discord integration: authentication only, NO bot
*2026-05-19*
Discord usage across iOS / web / Android is **strictly authentication-only** until BoBA Discord moderators explicitly authorize a bot. ✅ OAuth sign-in · storing `discord_user_id` · client-side `discord://users/{id}` deep-links. 🚫 No Bot SDK / server-side API calls · no reading/posting server content · no webhooks / Activities / WebViews beyond OAuth.

**Why:** the BoBA Discord server has its own moderators and contracts; a bot changes the social contract. **Trading implications:** TRADE-DESIGN.md §4 (pure introduction → Discord messaging) does NOT require a bot — "Open Discord" is a client-side deep-link URL.

## 050 — Android: Sign in with Apple is NOT offered
*2026-05-19*
Sign in with Apple is iOS+Web branding. Android offers Sign in with Google (primary, Credential Manager one-tap), Discord OAuth (secondary; most-used in the BoBA community), email/password (fallback). Apple-ID accounts created on iOS map to email-based Supabase users; the same email signs in on Android.


**Why:** Sign in with Apple on Android is a foreign brand cue; Sign in with Google is the canonical one-tap; a third path adds complexity without proportional value.

## 051 — Android future 3D rendering: Filament (primary) or raw Vulkan/NDK
*2026-05-19*
If/when Hero Shot or House of BoBA ports to Android (currently deferred): **Filament** (primary) — Google's open-source PBR renderer, RealityKit-shaped API; **raw Vulkan via NDK** as fallback only if Filament's ceiling is hit. **Not Sceneform** (deprecated 2021) or Unity-as-library (wrong fit in a Compose app).

**Translation work when it happens:** `BOBACardEntity` → Filament `Material`/`MaterialInstance` + IBL; `PhysicsBodyComponent` (House of BoBA) → Bullet, since Filament ships no physics — significant additional work.

## 052 — Firebase: stay on Spark (free) plan
*2026-05-19*
Android uses Firebase **only** for FCM push delivery. No Firestore, Realtime DB, Firebase Auth (Supabase + Credential Manager), Hosting, or Storage (R2 per #008). Spark covers unlimited FCM delivery. Single project, one Android app; `google-services.json` committed (public identifiers, safe). No Blaze upgrade needed for v1.

## 053 — No Twitter / X integration, ever
*2026-05-20*
BOBA will **never** ship Twitter / X integration across iOS / web / Android: no Twitter login, share intents (`twitter://post`, intent/tweet), `twitter:*` meta tags, embedded widgets, API consumption, follow buttons, or any Twitter-branded affordance.

**Why:** X is owned and editorially operated by a fascist. Integrating — even passively through metadata — signals endorsement and provides material support. BOBA won't direct any user, viewer, or brand element to that platform. **What still ships:** standard Open Graph (`og:*`), read by Discord / iMessage / Slack / Bluesky / Mastodon / Threads / and every other major link-preview consumer.

**How to apply:** reject PRs adding `twitter:*` meta tags, `twitter.com` URLs, Twitter SDK/API, share-to-Twitter buttons, or "tweet this" copy. Future Twitter-pattern features → Web Share API + OG protocol; gut any third-party template's Twitter integration first.

## 054 — Web Scan re-surfaced as fallback + native-app gateway
*2026-05-22*
Partially supersedes the web-side of [#012](#012). Scan on web is no longer "out of scope" — it's a sidebar destination with three jobs: (1) **camera-capture fallback** for users without the native apps (`getUserMedia` → frame → Worker OCR; functional but less performant); (2) **desktop → phone QR handoff** (desktop shows a QR encoding `?view=scan&rt={refresh_token}`; phone scans → opens BOBA with the desktop session); (3) **native-app gateway** (inline TestFlight + Google Play CTAs).

**Why the reversal:** beta testers asked for it; the web implementation already existed (only the sidebar entry had been removed), so restoring it cost nothing. The on-device-Vision principle from #012 still governs the **canonical** scanner — web is an *adjunct*, not a replacement.

**How to apply:** Web Scan IS in scope for iteration. Reuse `nativeAppCalloutHTML()` in `js/app.js` for *every* surface advertising the native apps. iOS Vision + Android ML Kit remain the canonical on-device scanners.

## 055 — Android scan: multi-pathway OCR recovery for shiny / holographic cards
*2026-05-23*
Real-world testing of **DEKAP GGL-779 (Great Grandma's Linoleum Battlefoil — Glow)** drove a rewrite of the Android matcher to accumulate **multiple independent OCR-recovery paths** rather than rely on one clean read (cross-token reassembly, digit-confusion + digit-to-letter prefix normalisation — `G6L`→`GGL`, most-impactful since OCR reads `G` as `6` on shimmer — missing-dash reconstruction, heroes-gated prefix-only candidates, cross-frame aggregation, fuzzy element matching). iOS #035's strict cardNumber regex + hero veto stays the core. The **killer feature: a parallel preprocessed-OCR pipeline** — a periodic `enhanceContrast` (percentile luma stretch) on a `PreviewView.bitmap` snapshot feeds a SECOND ML Kit pass into the same token buffer, restoring the cardNumber-strip contrast auto-exposure blows out on shimmer. Full path list + don't-touch diagram in memory `[[reference_android_scanner_recovery_paths]]` + SCANNER_LOOP.md.

**Why Android diverges from iOS:** iOS has a cleaner OCR baseline (Vision) + `feature-prints.bin` FP (#035); Android's ML Kit OCR is noisier on shimmer, FP deferred to v2 (#043). **Don't:** lower the stabilizer single-frame tier below 2.5, or relax the 0.3 margin / 1.4 confidence floors (tried iters 46-47, reverted within minutes — wrong-card/element commits). The floors are load-bearing; new paths get a SCANNER_LOOP.md row + `ScanCardMatcherTest` JVM test.

## 056 — Radish Price Guide integration removed (compliance request)
*2026-05-23*
On 2026-05-23 the Radish Price Guide owner + lead developer emailed that they consider BOBA a competing product and revoked authorization for Radish data, images, pricing, mapping, lookup logic, automated workflows, and partner/primary-source language. The ONE thing they remain comfortable with: "ordinary user-facing linking" where the user leaves BOBA to view info directly on Radish.

**What was removed** (full tick log in `RADISH_REMOVAL_LOOP.md`): every Radish fetch/resolver/scraper across Workers, clients, and pipeline; pricing replacement is now its own architecture (#058 — we generate our own sold-history rather than swap one third-party dependency for another). A backfill queue (`scripts/identify_radish_sourced_cards.py`) re-sources the 8,386 Radish-sourced images from the card source.

**The one approved use case — per-card external link.** The email allowed "ordinary user-facing linking"; Ben confirmed direct card-links are within the spirit. Use the legacy frozen `card.radishUrl` field (acquired pre-email), falling back to `https://radishpriceguide.com` when null; "View on Radish" opens the system browser externally.

**Why principle-wise:** operating independently of any single third party is the load-bearing concern. **How to apply:** reject any PR adding a Radish reference (fetch, URL construction beyond the homepage fallback, alias table, lookup logic, source pill, partner language); the only permitted Radish code is the `card.radishUrl` per-card link + homepage fallback. Every other automation — sitemap pulls, HEAD probing, alias tables, runtime URL construction, Worker endpoints — stays deleted.

## 057 — bobaId formula v3 adds weapon as 5th field
*2026-05-25*
Extended the bobaId formula from 4 fields to 5 by appending the card's WEAPON (catalog field `element` per #027; the canonical term in prose is Weapon):

```python
# v3 (2026-05-25) — appended `element` (weapon) to the v2 4-field formula:
bobaId = f"{cardNumber}-{hero or name}-{treatment or ''}-{variation or ''}-{element or ''}"
```

**Why**: The card-art audit found many cards exist as FIRE-weapon + GLOW-weapon variant siblings sharing otherwise-identical (cardNumber, hero, treatment, variation), which collided on the v2 bobaId. The catalog had worked around it with distinct cardNumbers per variant — but that broke when 101 OCR-driven cardNumber merges would have produced true bobaId duplicates. Including weapon in the bobaId lets both weapon variants keep the same physical printed cardNumber without collision.

**Migration**: deterministic old→new mapping for all 17,974 cards, in lockstep across the 3 canonical formula sources (`boba_id.py`, `Card.swift`, `Card.kt`), the 5 catalog bundles, and every Supabase `boba_id` column + pipeline tables; feature-prints index rebuilds automatically. NOT changed: R2 image filenames (`imageFile` is a separate stored string — old keys stay valid) and pipeline staging identifiers (distinct `Auto`-suffix workflow tokens).

**How to apply**: any code reading/writing a bobaId uses the 5-field formula; the three canonical sources share one shape — never redefine inline. A 6th disambiguator (v3 verified zero collisions) repeats this shape: new field at the end, deterministic catalog → mapping table → Supabase UPDATEs.

## 058 — Pricing is provenance-honest; we generate our own sold data
*2026-05-27*

The post-Radish, post-Marketplace-Insights pricing architecture (full build log + per-tier rules: PRICING_PLAYBOOK.md; UI rules: DESIGN.md §8.7 · WEB-DESIGN.md §14.6 · ANDROID-DESIGN.md §8.7, which cite this entry). eBay Marketplace Insights (sold comps) is permanently unavailable — it has rejected applicants for years — so any pipeline depending on a third party for sold data is structurally broken. Supersedes Radish-era #013; generalizes COMC's asks-out-of-waterfall rule (#034) to *every* asking source.

**Principle — provenance is the contract.** Every price states what KIND of data it is; we NEVER present an asking price or derived guess as "what it's worth" (asks run 10-25% above transacted → folding them in silently inflates every card). The most-specific *honestly-labeled* signal wins, in order: (1) **Recent Sales** — transacted comps, each with a source pill (eBay/Whatnot vanish-inferred · community); (2) **Listed Range** — with NO sold data, the active listings ARE the honest signal ("N active · no recent sales yet"), never a fabricated "Market Est."; (3) **Buy Now** — active asks (eBay + COMC + Whatnot), additive, never in a sold number; (4) **Estimate** — the comparability estimator, only when labeled AND fed real comps.

**Why we generate our own data.** No external API gives us sold comps, so `boba-pricing-tracker` snapshots public *active* listings (eBay + Whatnot) into D1 and infers "sold @ last-seen price" + confidence when a listing **vanishes** from a later snapshot (~60 days → a sold-history we own); plus community comps (Tier 3) and the `boba-price-estimator` over our own catalog. All real sold signals merge through one endpoint (`/comps`); asking sources never enter it.

**Match precision is load-bearing — "one card, one bobaId, one price"** (`workers/ebay-proxy/worker.js`): eBay sold requires exact card-number AND hero (partial/hero-only → dropped); **weapon-conflict** reject (FIRE vs GLOW share a cardNumber, #057); **treatment-conflict** reject (Base Set rejects Battlefoil/Inspired/etc.); **ordinal exclusion** ("1" ≠ "1st Edition") + **prefixed-number guard** ("1" ≠ "#OHBF-1"). **Whatnot is adaptive** — sellers title by card NUMBER *or* POWER, so a listing matches on EITHER, same weapon/treatment gates.

**How to apply.** Reject any PR that (a) presents an asking/estimator number as market value without real sold data, (b) folds asks into a sold/value figure, or (c) loosens a match gate so another card's listings count. New *asking* sources → Buy Now / Listed Range; new *sold* sources → `/comps`.
