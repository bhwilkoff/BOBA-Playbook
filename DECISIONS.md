# BOBA Playbook — Architecture & Technology Decisions

Entries capture the *why* behind choices — not just what we decided but what principle it encodes. Technical details that anyone can read from the code don't belong here. The question every entry should answer: *what would the next developer get wrong if they didn't know this?*

---

## 001 — Vanilla HTML/CSS/JS for Web
*2026-04-03*
No framework, no build step. GitHub Pages serves static files directly. Framework abstractions cost more than they save at this scale; adding one now would require a build pipeline, a CI step, and a mental model that every future contributor has to carry.

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
Both platforms implement the same core feature set. Platform-specific implementation is acceptable; platform-exclusive features are the exception, not the rule. Track parity in SCRATCHPAD.md. Every feature is effectively built twice — mitigated by shared API contracts and design tokens.

## 006 — App Name and Brand Identity
*2026-04-03*
Display name: BOBA Playbook. Xcode product: BOBAPlaybook (no hyphens). Design language: Retro-futurism + cyberpunk + glassmorphism. Palette: battle orange (#FF4D00), cyber cyan (#00F5FF), deep violet (#8B00FF) on near-black (#080810). Card art is always the focal point — UI chrome frames it, never competes.

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
Each element maps to a canonical UI color: FIRE #FF4D00, ICE #00BFFF, HEX #8B00FF, STEEL #8A9BB0, BRAWL #C0392B, GLOW #FFD700, GUM #FF69B4, SUPER #FF00FF, ALT #B084CC, CYBER #39FF14, NONE #666680. Elements in cards.json are always UPPERCASE.

ALT and CYBER added 2026-05-25 after the bobaId v3 audit (#057) surfaced 48 ALT cards and 28 CYBER cards in the catalog. They aren't gameplay weapons in the traditional sense — ALT is the weapon-slot value used on parallels (Billy Cameo Alt Arts, Sidekicks, Inspired Ink Battlefoils, Rookie Power Up, etc.) and CYBER is the cyberpunk-themed "2025 Cyber Promo" set — but both render in the weapon spot on the printed card, so they need first-class color tokens to display correctly. CYBER's neon green matches the chartreuse palette of the actual promo art; ALT's lavender is chosen to stay distinct from the existing purple-family weapons (HEX violet, SUPER magenta, GUM pink) since ALT spans many treatments and has no single visual signature.

Codified across `BOBAPlaybook/Components/Design.swift::element(_:)`, `android/core/ui/.../theme/Color.kt::BobaElements`, and `css/styles.css` `:root --el-*` + `modal-layout[data-element=]` overrides.

## 011 — No Card Images in Git
*2026-04-03*
Card images live exclusively on Cloudflare R2. `assets/data/` contains only JSON. Keeps clone fast and avoids GitHub's soft 1 GB storage limit.

## 012 — Scan Mode: On-Device Vision Only
*2026-04-03*
Card identification uses iOS Vision (`VNRecognizeTextRequest`) and AVFoundation only. No image is uploaded. Pipeline: OCR frame → card number regex `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)` → match display-cards.json. Falls back to manual search.

**Principle**: User data stays on user devices. On-device processing is not a technical constraint here — it's the right choice for the user.

## 013 — Pricing Comps Strategy
*2026-04-03*
Pricing fetched live at card-detail view time via Cloudflare Worker (eBay Browse + Marketplace Insights APIs). Prices not stored in Supabase — live lookups only. Collection value dashboard caches last-fetched price in `user_cards.estimated_value`. **Radish Price Guide integration was removed 2026-05-23** per the partner's request — see #056.

Worker URL: `boba-ebay-proxy.benwilkoff.workers.dev` — stored in `BOBAPlaybook/Config.swift` and `js/app.js`.

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

**Why**: Reference content belongs to everyone, immediately, without friction. Personal decks have identity — your choices, your strategy — and should persist across devices like the collection does. These are meaningfully different things.

## 022 — SwiftUI ScrollView Width: VStack Parent Must Have frame(maxWidth: .infinity)
*2026-04-06*
Any `VStack` that directly parents a `ScrollView` AND switches content conditionally must have `.frame(maxWidth: .infinity)`, or the ScrollView receives variable proposed widths per mode, causing horizontal rubber banding.

**Root cause**: SwiftUI's VStack sizes to the max of its children's natural widths. When that width varies by mode (e.g., Rookie = 228pt, Substitution = 361pt), every child ScrollView inherits that instability. Apply the frame constraint at the outermost VStack first.

## 023 — Mod Accounts: Role-Based Access via user_profiles
*2026-04-07*
Moderator roles live in a `user_profiles` Supabase table (`role`: user | moderator | admin). Role is never stored client-side permanently — fetched post-auth and cached in-memory for the session.

Card corrections → `card_corrections` table. Image overrides → `card_image_overrides`. Both require mod/admin role enforced by RLS. The catalog is static JSON, so corrections decouple user-submitted fixes from the release cycle.

## 024 — iOS Image Loading: Show Thumb Immediately While Full Loads
*2026-04-13*
When opening a card detail view, `CardImageView` checks NSCache for the thumb URL before showing a spinner. If the thumb is in cache (it almost always is — the user just saw it in the grid), it displays immediately. The full-res image loads in the background and replaces it when ready.

**Why**: A spinner for something the user just tapped creates a gap between intention and response. Showing the card immediately — even at grid resolution — confirms that the tap was registered and the right card is loading. Immediacy builds trust; spinners create anxiety.

## 025 — Feature Gating: Keep Code, Hide UI Entry Point
*2026-04-13*
When a feature is built but blocked on external dependencies (e.g., Discord trade room waiting on bot setup, eBay Market Feed waiting on API scope approval), we keep all implementation code in place and gate at the single UI entry point. We do not delete or hollow out working code while waiting.

**Why**: Building ahead of infrastructure is sometimes unavoidable. Half-deleting code creates a worse problem — the feature is harder to re-enable and the codebase is in an ambiguous state. A single `if featureEnabled { ... }` flag at the call site is the right level of intervention. When the dependency arrives, re-enabling should be one-line.

**Applied to**: Discord FAB in `CollectionView.swift` (commented call site, full implementation intact). Web Discord `fab.hidden = true` in the render loop.

## 026 — Image-Byte Collision Guard in Pipeline
*2026-04-13*
`reconcile_all.py::step11_optimize_images` ends with an md5-uniqueness check over every catalog-referenced file across `images/`, `images-optimized/`, and `thumbs/`. Any group of files that resolve to different `(cardNumber, hero)` keys but share identical bytes is flagged to `unified-cards/data/image_collisions.json`, with a per-tier remediation hint.

**Why**: The bobaId scheme enforces "One ID per Card" at the catalog layer, but nothing was enforcing "One Image per Card" at the CDN-payload layer. On 2026-04-13 we discovered Caliber card #24 was showing D-Harp's art in the app — not because cards.json was wrong, but because an earlier run of the image optimizer had silently overwritten Caliber's optimized webp with D-Harp's bytes. Catalog-layer validation couldn't catch it; only md5 comparison of the actual outputs can.

A post-mortem scan found 35 such pairs catalog-wide. Without a guard, the next rebuild could easily regress: a single bad source image, a race in the PIL worker pool, or a caching bug in a future script can cause the same silent overwrite.

**How to apply**: If `image_collisions.json` is ever written after a pipeline run, STOP — do not sync to R2 until every group is resolved. The file's `notes` field explains whether the fix is "delete bad outputs, re-run step 11" (tier-level collision) or "re-download the correct source art" (master-level collision). Sealed-product `_eBay` placeholders are whitelisted and will not trigger the guard.

**Master-level fallback**: When a master-level collision cannot be resolved because the correct source art does not exist publicly (verified against Radish, the card source, Cardeio, and any other known source), the card is reclassified into the missing-art queue instead: set `imageFile=null, imageSource=null, imageAvailable=false` in `cards.json`, regenerate `missing-cards.json` via `step5`, and let `ebay_missing_images.py` recover the art on its next run. First applied 2026-04-13 to the three Griffey Edition Blizzard Battlefoils (BLBF-95 D-Harp, BLBF-120 Zephyr, BLBF-174 Highway to Helton) — their correct art turned out to not exist on any surveyed CDN.

**Principle**: Every invariant the app relies on should be enforced where it can be measured. "One Image per Card" lives in binary content, so the check has to run against binary content.

## 027 — User-facing terminology: "Weapon" not "Element", "Treatment" not "Rarity"
*2026-04-23 → 2026-04-24*
The catalog field name is `element` (FIRE / ICE / STEEL / etc.). User-facing strings everywhere call it **Weapon**. The `treatment` field carries the print variant (Base Set, Battlefoil, Superfoil, Inspired Ink, etc.). User-facing strings everywhere call it **Treatment** — except the one Learn-tab section that explicitly discusses *rarity by weapon type*, where "Rarity" is the right word.

**Why**: Every BoBA collector and player calls them weapons. "Element" is leftover schema language from when the game was being modeled, not what people actually say at the table. Same with "Rarity" — it's a TCG term that conflates two things in BoBA: the hero's intrinsic scarcity (tied to weapon) and the print variant (the treatment). Splitting them gives users a vocabulary that matches the community.

**How to apply**: Field names in code stay (`element`, `treatment`, `rarityLabel`, `rarityTier`). Anything rendered to a user — labels, headers, copy, accessibility strings — uses Weapon and Treatment. The two exceptions are the "RARITY BY WEAPON TYPE" section header in Learn (intentional) and internal helper names that don't appear in the UI.

## 028 — Treatments vs Parallels are distinct concepts
*2026-04-24*
Sourced from BoBA-expert audit (Griffey checklist + the official `bobattlearena.com/collecting-basics` page).

**Treatments** are different ways a single card can be printed: Base Set, Battlefoil family (with seven color subsets — Red/Silver/Blue/Orange/Green/Pink/Bubble Gum), themed foils (Blizzard, Alpha, Headlines, Power Glove, Grandma's Linoleum, Great Grandma's Linoleum, Chillin', Grillin', Icon, Mixtape, Miami Ice, Fire Tracks, Colosseum, Logofoil, Slime), Inspired Ink (= Serialized) variants, and Superfoil. Each has a card-number prefix that maps directly to the treatment.

**Parallels** are entirely separate card runs sharing the format but with their own numbering: Billy Cameo Alt Arts, SideKicks, Plays, Bonus Plays, Prize/Promos, Hot Dogs.

**Inspired Ink = Serialized.** Inspired Ink cards carry hand-stamped serial numbers tied to the hero's weapon: Hex /5, Glow /10, Fire /25, Ice /50.

**Why this matters for the app**: The previous "Parallels & Treatments" section bundled them, which confused new collectors who heard the terms used differently in the community. Splitting into two sections matches how veteran collectors talk and matches the official collecting-basics taxonomy.

**How to apply**: The Learn → Collect page has separate "TREATMENTS" and "PARALLELS" sections. The card detail's stat grid uses "Treatment" (not "Rarity") for the print variant. Future scrapes / data corrections / Cowork handoffs should preserve this distinction — never collapse a Parallel into a Treatment in the catalog data.

## 029 — Card-detail canonical 6-cell layout
*2026-04-24*
Every card-detail surface (iOS card-detail view, web card modal) renders the same 6-cell stat grid in a 2-column layout, in this exact reading order:

```
Card #     │ Type
Treatment  │ Weapon
Set        │ Sub-set
```

Card-type-specific extras (Cost + DBS for Plays) render BELOW the canonical 6 — never interleaved.

**Why**: A consistent layout means coaches can find any field with one glance, no matter what they're looking at. "Same shape on every card" is part of building visual literacy with the catalog. Sealed products skip Treatment + Weapon (they don't apply); empty Sub-set renders as `—` rather than collapsing the row, which would shift everything beneath.

## 030 — Practice executor: persistent-effect engine architecture
*2026-04-24*
Two parallel state arrays on `PracticeStore`: `persistents` (every non-weapon-transform persistent block) and `weaponTransforms` (split out so the hot-path weapon read consults a flat array). Single entry point `installPersistent(owner:spec:)` routes specs into the right array — no direct `.append`.

`firePersistentTriggers(trigger:winner:)` is the single dispatcher for non-continuous effects, called at `on_plays_resolved` (top of `resolveCurrentBattle`), `on_battle_win` / `on_battle_loss` (end), `on_battle_start` (in `moveToNextBattle`), and inline for B.8 `auto_lose_battle`. Every positive HD change routes through `applyHDRecover` (redirect → cap → delta → block); negative HD bypasses. `isScopeActive(...)` is the single scope evaluator for `rest_of_game`, `this_battle`, `next_battle`, `this_and_next`, `next_N_battles`, `battle_1`–`battle_7`, `battles_4_7`; unknown scopes return false (safe no-op for new scopes).

**Why**: centralizing install + lifecycle + scope eval in three helpers means future op families (B.6 / B.7 / B.10 / B.11 / B.13) need only per-op behavior — plumbing is free.

## 031 — First-run hint system
*2026-04-24*
`HintsManager` (`@Observable`, UserDefaults-backed) tracks dismissed hint IDs per device. `HintBanner(id:title:message:)` renders nothing if the hint is dismissed OR the global toggle is off. Tapping the X dismisses permanently. Settings has a master toggle + "Reset hints" button.

**Why**: The eight teaching moments from the practice-battle UI handoff (substitution positioning, deck composition triad, bonus play ceiling, etc.) need to surface at the right moment but never lecture experienced coaches twice. One-shot per device + global silence + reset gives users full control without removing the teaching value for newcomers.

**Inlined into `Design.swift`** rather than living in its own file — Xcode's PBXFileSystemSynchronizedRootGroup intermittently fails to pick up newly-added Swift files even after Clean Build Folder. Co-locating with an existing compile target sidesteps the issue. If/when Xcode's synchronized-group reliability improves, this can be moved back into a standalone file.

## 032 — iOS home-screen display name: "Playbook" not "BOBA Playbook"
*2026-04-24*
`INFOPLIST_KEY_CFBundleDisplayName = Playbook` in both Debug + Release configs. The full "BOBA Playbook" name still appears in `BOBAWordmark` everywhere inside the app, in `CFBundleName` (Settings → iPhone Storage), and on the App Store listing.

**Why**: "BOBA Playbook" truncates to "BOBA Pl…" under the icon on every iPhone home screen tested. Truncation reads as broken; the shorter name is intentional. The XOXO icon already carries enough brand to identify the app — the under-icon label only needs to disambiguate from other apps the user has installed.

## 033 — Open questions deferred to BoBA / real-world data
*2026-04-27*
Three items blocked on external signal — documented so they don't get lost.

**(a) `LA - 20 — Series MVP Award` anomaly.** A 2026-04-27 BoBA DBS PDF row references hero `MVFree` and a release prefix `LA` not in our catalog (A / U / G / HTD do; LA doesn't). Could be a PDF-parser glitch, a new Limited Alpha promo subset, or a hero-bonus card. Skipped from `dbs_merge.py` (only 1/411 rows that didn't land). **Ben TODO:** confirm with BoBA team; rerun merge.

**(b) bobaleagues CSV roundtrip verification.** Phase C ships v2 (`id,name,type,release,number,cost,dbs,ability,bonus`) alongside legacy v1 (`Slot,Card#,...`). **Ben TODO:** export a real Playbook from bobaleagues + drop in recon folder; adjust if shape drifts. Both paths kept.

**(c) Elo tier-band tuning.** Phase D bands (200-pt: Brawl 0–999 … Super 2200+) are live-derived from rating, never stored. Needs ~1k production practice matches to tell if widths should narrow at the bottom. Revisit then.

**Why defer**: all three are blocked on external confirmation / artifact / production data. Cost of waiting is zero; cost of guessing is silent drift.

## 034 — COMC asking-price as second BUY NOW source (NOT in sold-comp waterfall)
*2026-04-29*
COMC.com exposes 931 BoBA listings matching cards.json. Wired as a parallel BUY NOW source alongside eBay actives (iOS `ComcService` + web `fetchComcListings`).

**Critical: COMC asking stays OUT of the sold-comp waterfall.** eBay sold → Market Est. measures TRANSACTED prices. Asking runs ~10-25% above sold; folding it in inflates the estimate. COMC is purely additive on BUY NOW (where to buy now), not pricing (what it's worth). Each COMC row shows "COMC asking · Ungraded NM" so users read it as a list price.

**Turnstile blocked.** COMC turned on Cloudflare managed-JS challenge after recon. `boba-comc-proxy` detects `challenged: true` and returns `count: 0`; clients soft-fail. Bypass requires Browser Rendering API / Playwright / cf_clearance persistence. Defer until COMC's WAF stance changes (memory `feedback_comc_blocked_all_platforms`).

## 035 — Unified card recognition: image fingerprint primary, OCR as confirmation
*2026-04-30*
All five scan modes (single live / multi live / show live / photo still / grid burst) route through `ScanMatching.resolve(observation:allCards:)`. Prior design had two parallel matchers, both treating OCR cardNumber as primary — that silently failed when OCR returned a real-but-wrong number (partial "BHBF-37" arriving as "20"; catalog returned a real card at "20", no veto from printed hero, wrong commit).

**Redesign:** image fingerprint (`feature-prints.bin`, 16,123 cards / 12.7 MB) is the primary identifier. Every signal contributes both candidates and scores:
- FP top-30 by L2 distance → candidate pool
- OCR cardNumber exact: +1.0 · bare-digit suffix: +0.4
- Hero name in top-left: +1.5 · elsewhere: +0.6
- **Hero veto:** any candidate whose hero isn't in a clearly-named top-left set gets −2.0 (the missing piece — what the waterfall lacked)
- Element / treatment / power → small additives

Confidence floor 1.4, margin floor 0.3. Below either → resolver returns nil ("Not identified") — better UX than a confident wrong answer.

**Why FP primary:** OCR fails partially in success-looking ways (silent-wrong); FP fails completely in failure-looking ways (resolver returns nil; user retries). Silent-wrong is the worst possible UX for card recognition.

**Grid-cell perspective rectification:** `GridCardDetector` perspective-corrects from each anchor's quad with adaptive bleed sized from lane spacing — fixes the prior ~22% under-detection from anchor-clipped bottom-left card numbers. Cells without anchors fall back to axis-aligned crops at predicted positions.

## 036 — Wall + Price Overlay: lift from streamer-only gate
*2026-05-03*
Per DESIGN.md §8.4 + §8.8, Wall display mode and Price Overlay become first-class for every collector — not streamer-gated. **Partially supersedes [#025](#025)** for these two features (the principle still applies to genuinely-blocked features like Discord trade room, eBay Market Feed).

**Lifts:** Wall is a Collection display mode (Grid / List / Wall in toolbar Menu) + accessible from Decks ("Generate deck wall") + Find multi-select ("Wall these N cards"). Price Overlay is a Wall-view toggle with per-designation defaults (For Sale ON / My price · For Trade ON / market est · Grails+Personal OFF · Wanted ON / WTB prefix). `CollectionWallSheet` wraps `ShowWallComposer` (pure composer; gate was at invocation only).

**Stays gated to streamers:** Whatnot "My Shows" management; per-show wall generation inside the Shows tab; community trade room.

**How to apply:** expose Wall + Price Overlay to all signed-in users when implementing display-mode pickers / share affordances. Don't add new role gates. `ShowWallComposer` stays unchanged.

## 037 — Profile redesign: username = display name = public handle
*2026-05-04*
Single `username` field doubles as display name AND public-collection slug (`bobaplaybook.com/u/{username}`). No separate `display_name` — two parallel name fields drift confusingly (Discord's conflation is the cautionary tale).

**Auto-derivation:** iOS UsernameRow derives from email local-part (lowercased, `[a-z0-9_-]`), suffixes on collision, writes via `set_username` RPC. Discord-OAuth users with no email fall back to `user-{6-char-hash}`. Inline edit anytime with debounced `check_username` → status pill (✓ available / ✗ taken / ✗ not allowed / ✗ reserved).

**Banned-words gate** — two layers:
1. Client (`BOBAPlaybook/banned-words.json`, ~270 entries) — instant red pill, zero network.
2. Server (`banned_words` table, populated by `scripts/build_banned_words.py`) — authoritative gate via `check_username` / `set_username`.

Source: LDNOOBW EN list filtered to ≥4 chars (Scunthorpe-resistant). Reserved infra terms (`admin`, `boba`, `api`, etc.) live separately in `username_is_reserved` Postgres function. Custom additions in `scripts/custom_banned.txt`; rerun + re-apply SQL to refresh in lockstep.

**Why two layers:** usernames are public + persistent + harassment vector. Cost of a slur on a public URL >> friction of "try ben2 instead." Server gate also protects from client-bundle drift.

## 038 — Profile redesign: generalized role-request (mod OR streamer)
*2026-05-04*
Original mod-request flow generalized to `requested_role` / `requested_role_at` / `requested_role_reason` columns + `request_role(role, reason)` RPC accepting `'moderator'` or `'streamer'`. Admin queue (`get_pending_role_requests`) returns both kinds; `review_role_request` promotes to whichever role was requested.

Old `submit_mod_request` / `get_pending_mod_requests` / `review_mod_request` kept as delegating shims through the deploy window; drop in next release. Migration is additive — old columns linger nullable; new columns backfilled via one-shot UPDATE. **Why:** streamer always needed a request flow; one mechanism cheaper than two.

## 039 — Profile redesign: deferred features
*2026-05-04*
Three Profile features ship with UI ahead of backend so the surface is complete:

**(a) Trade match alerts** — toggle persists to `user_profiles.match_alerts_enabled` via `set_notification_prefs`. Matching pipeline (Wanted/Grail overlap → APNs fan-out) is multi-week and blocked on an APNs server-side dispatcher. Footer: "Coming soon — toggle to opt in early."

**(b) Public collection sharing** — IMPLEMENTED 2026-05-04. Toggle on `user_profiles.public_collection_enabled`. Web `bobaplaybook.com/u/{username}` live (404.html redirect → SPA `view-public-collection`; `get_public_collection(handle)` RPC, SECURITY DEFINER + STABLE). Projection excludes `purchase_price` / `asking_price` / `notes` and filters out Wanted (public = "what they have"). Card detail opens read-only. Per-designation toggles + Wanted-as-WTB-list deferred (DESIGN.md §8.4).

**(c) Account deletion** — IMPLEMENTED 2026-05-05. `boba-account-delete` Worker: POST w/ Bearer JWT → verifies vs Supabase auth → admin DELETE w/ service-role secret. FK CASCADE clears `user_cards` / `decks` / `shows` / `user_profiles`; `card_corrections` / `card_image_overrides` SET NULL (audit trail survives anonymously). Wired iOS + web; both sign out on success.

**Why UI ahead of backend:** removing toggles later = worse UX; opt-in data is useful signal once backend ships; deletion needed for App Store compliance.

## 040 — Profile pictures: Discord-default, R2-on-upload
*2026-05-05*

Three-tier resolver: **custom (R2) → Discord avatar → default silhouette.** Most users auth via Discord OAuth → recognizable avatar at zero storage cost.

**Storage:** existing `boba-card-images` bucket, `avatars/{user_id}.{ext}` prefix. Public URL `{CDN_BASE}/avatars/{user_id}.{ext}`. Pre-write delete sweep clears prior extensions.

**Worker** `boba-avatar-upload`: POST `/avatar` w/ Bearer JWT + ≤2MB bytes → verifies vs `/auth/v1/user` → writes R2 → `{url, version}`. DELETE clears all extensions.

**Supabase:** `user_profiles.avatar_url` (NULL = fall back). RPC `set_avatar_url` is own-row + **rejects URLs not matching the R2 avatars prefix** — without this, a malicious client could point `avatar_url` at tracking pixels or inappropriate images rendered on others' devices. `get_public_profile(handle)` returns `username, avatar_url, discord_avatar_url` for the public-collection page.

**Why R2+Worker, not Supabase Storage:** R2 (#008) = zero egress + edge cache + auth-free CDN. Supabase Storage avoided per #007.



## 041 — Android: Kotlin + Jetpack Compose (not KMP / CMP / Flutter / RN)
*2026-05-19*

Native Kotlin + Compose, separate from iOS Swift/SwiftUI. Same monorepo (`/android/`). iOS is shipped Swift-native (#004); KMP "common module" migration would mean rewriting iOS — we're not doing that.

**Why:** KMP works best when both platforms start together (BOBA didn't). CMP can't render iOS-26 Liquid Glass surfaces (`Tab(role: .search)`, `.navigationTransition(.zoom)`) the iOS DESIGN.md bets on. Flutter / RN add runtime + bridge overhead for every Android API (ML Kit, CameraX, Play Integrity, biometrics) — strictly worse for Android-only.

**Future option:** if Web ever wants typed models or Desktop arrives, KMP is the upgrade path — keep the door open by structuring Android's domain layer as pure-Kotlin from day one. See ANDROID-DEV.md §1 + ANDROID-DESIGN.md §1.

## 042 — Android: Material 3 brand-first; dynamic color opt-in
*2026-05-19*

Android ships fixed brand theme (orange/cyan/violet on near-black) by default — not Material You dynamic color. User can opt into "Use system colors" in Settings.

**Why:** card-art palette is the focal point; wallpaper-derived primary fighting `#FF4D00` reads muddy. Same rule as iOS §11.2: element on content semantics; brand on chrome. `BobaTheme.kt` builds brand `colorScheme` from fixed seeds; toggle ON applies `dynamicDarkColorScheme(LocalContext.current)` to `primary` only on Android 12+. Element colors never change. ANDROID-DESIGN.md §6.8 + §11.2.

## 043 — Android Scan: CameraX + ML Kit Text Recognition v2 unbundled; OCR-only v1
*2026-05-19 · amended 2026-05-26*

CameraX 1.5+ + ML Kit Text Recognition v2 via Google Play Services dynamic delivery (`com.google.android.gms:play-services-mlkit-text-recognition`). Manifest meta-data `com.google.mlkit.vision.DEPENDENCIES = "ocr"` triggers a one-time model download at install. Matches iOS Vision shape.

**Why OCR-only v1:** #035 made FP primary on iOS due to silent-wrong failure in **grid scan** specifically. Single-card live scan with OCR + hero-name veto + confidence threshold is sufficient (iOS pre-FP design ran fine for months). Adding FP needs MediaPipe Image Embedder + parallel `feature-prints-android.bin` — defer to v2.

**Why unbundled (amended 2026-05-26):** the original 2026-05-19 decision picked the bundled artifact (`com.google.mlkit:text-recognition`) for "works offline immediately" iOS parity. After uploading the first signed AAB to Play Console closed testing on 2026-05-25, the upload surfaced "App Bundle contains native code, and you've not uploaded debug symbols" — ML Kit ships its `.so` files pre-stripped (verified via `readelf -S libmlkit_google_ocr_pipeline.so`), so AGP's `extractReleaseNativeSymbolTables` task produces nothing and no `native-debug-symbols.zip` can be generated. The warning is cosmetic today but is exactly the kind of thing Google Play could promote to a hard release blocker on no notice.

Reversing to unbundled removes the `.so` files from the AAB entirely (Play Services hosts them), shrinks the AAB ~11 MB, eliminates the warning permanently, and reframes the original "offline-immediate" trade-off correctly: the user already had to be online to install the app, so the marginal cost of a ~3-5 MB Play Services model download at install is zero. Manifest meta-data ensures the model lands before the first scan so the user-facing scan experience matches the bundled posture.

**How to apply:** if a future scenario needs offline-immediate OCR on a device that has never been online post-install, switch back to bundled — but that scenario can't exist for a Play Store install. API surface is identical (`com.google.mlkit.vision.text.*` imports), so swapping the dependency is a one-line change in `libs.versions.toml`.

ANDROID-DEV.md §6.1–§6.5.

## 044 — Android: NO multi-step anchored walkthroughs
*2026-05-19*

Android doesn't ship the iOS-style multi-step walkthroughs (DESIGN.md §6.10). Use `TooltipBox` + `BOBAHintBanner` (DataStore-backed); empty states (§6.7) carry the first-time productive action.

**Why:** iOS walkthroughs exist because tab gestures / fullScreenCover / NavigationStack are novel idioms. Android conventions (NavigationBar / push-back / FAB / ModalBottomSheet) are universally legible. Reproducing the ~600-line walkthrough engine in Compose for marginal value-add is wrong-side cost/value. Onboarding splash decks rejected (same as iOS §6.10).

Revisit if a future feature (Practice executor on launch, complex new flow) genuinely needs anchored teaching. Each iOS walkthrough has a documented Android replacement (EmptyState / TooltipBox / HintBanner) in ANDROID-DESIGN.md §6.10.

## 045 — Cross-platform push: one dispatcher Worker, two transports
*2026-05-19*

When match-alerts ship (#039 + TRADE-DESIGN.md Phase 5), architecture is **one Cloudflare Worker `boba-push-dispatcher`, two transports (APNs + FCM)**:

1. Triggered by Supabase webhook OR cron scanning `trade_matches`.
2. Joins `user_devices` (`user_id`, `platform`, `token`).
3. Routes: `apns` → HTTP/2 + JWT; `android` → FCM v1 + Google service-account token.
4. Both batch.

**Symmetric payload** (deep_link is the same string on both sides):
```json
{ "type": "match_alert", "match_id": "...", "other_user": "@handle", "card_count": 3, "deep_link": "bobaplaybook://matches/{match_id}" }
```

**Why Worker not Edge Function:** Workers have better cold-start; existing secrets pattern; APNs JWT via Web Crypto, FCM v1 via plain HTTPS. ANDROID-DEV.md §7.3 + SCRATCHPAD.md Android M7.

## 046 — Android-specific app ID + signing strategy
*2026-05-19*

Package: **`com.bobaplaybook.app`**. Affects signing + Play Console + `assetlinks.json` + Firebase + every deep link.

**Signing:** Play App Signing (mandatory since 2021). Generate upload key via `keytool -genkey`; upload to Play Console; Play resigns each release with its production key. Upload-key creds in `gradle.properties` (git-excluded) + CI secrets.

**`assetlinks.json`** at the same `/.well-known/` path as `apple-app-site-association`. Both coexist. Fingerprint must include BOTH upload-key AND Play App Signing key SHA-256 — internal-testing builds (upload-key-signed) won't verify against production key otherwise. ANDROID-DEV.md §8.5 + §14.

## 047 — Android v1 form-factor scope: phone + tablet + Chromebook (NO foldable)
*2026-05-19*

Adaptive layouts (`NavigationSuiteScaffold`, `NavigableListDetailPaneScaffold`, `WindowSizeClass`) are foundation from M1 — not deferred. **Foldable NOT a v1 target.**

**Why:** Ben has a Chromebook for testing; Chromebooks + tablets share `EXPANDED` size class; foldables are a small share with significant hinge/posture cost.

**How to apply:** ANDROID-DESIGN.md §6.6 binding from M1; every screen declares COMPACT / MEDIUM / EXPANDED behavior (PRs without it rejected); don't optimize for foldable-specific APIs (standard size-class works *adequately*, not optimized).

## 048 — Android: Practice executor IS in v1, admin-gated
*2026-05-19*

Practice executor (iOS #030 + #033) ships on Android v1, admin-gated via the same Profile-role-badge bolt-icon unlock.

**Why:** Ben wants to test Battle Practice on Android during development; the game logic is platform-agnostic (UI translation is the work); admin gate hides from production users until ready.

Reuse iOS engine (#030) — `PersistentEffect` + `WeaponTransform` arrays, `firePersistentTriggers`, `applyHDRecover` — as pure Kotlin in `:core:domain`. Compose layer translates SwiftUI screen anatomy. Same `user_profiles.role` admin gate.

## 049 — Discord integration: authentication only, NO bot
*2026-05-19*

Discord usage across iOS / web / Android is **strictly authentication-only** until BoBA Discord moderators explicitly authorize a bot.

✅ OAuth sign-in · storing `user_profiles.discord_user_id` · client-side `discord://users/{id}` deep-link URLs.
🚫 No Discord Bot SDK / API calls from BOBA servers · no reading or posting BoBA server content · no webhooks / Activities / embedded WebViews beyond OAuth.

**Why:** the BoBA Discord server has its own moderators and contracts; a bot changes the social contract.

**Trading implications:** TRADE-DESIGN.md §4 (pure introduction → Discord messaging) does NOT require a bot — "Open Discord" is a client-side deep-link URL.

## 050 — Android: Sign in with Apple is NOT offered
*2026-05-19*

Sign in with Apple is iOS+Web branding. Android offers: Sign in with Google (primary, Credential Manager one-tap), Discord OAuth (secondary; most-used in BoBA community; via Auth Tab / Custom Tabs), email/password (fallback). Apple-ID accounts created on iOS map to email-based Supabase users; same email signs in on Android.

**Why:** Sign in with Apple on Android is a foreign brand cue; Sign in with Google is the canonical one-tap; a third path adds complexity without proportional value.

## 051 — Android future 3D rendering: Filament (primary) or raw Vulkan/NDK
*2026-05-19*

If/when Hero Shot or House of BoBA ports to Android (currently deferred):

1. **Filament** (primary) — Google's open-source PBR renderer (Vulkan/OpenGL under, RealityKit-shaped API). Used by Google Maps / Earth / Wear OS.
2. **Raw Vulkan via NDK** — fallback if Filament's API ceiling is hit. More work; pick only if needed.

**Not Sceneform** (deprecated 2021). **Not Unity-as-library** (JS+Mono runtime is wrong fit for a card-rendering feature in a Compose app).

**Translation work when it happens:** `BOBACardEntity` (front/back textured planes, rounded-corner alpha mask, edge box) → Filament `Material` / `MaterialInstance` + IBL pipeline. `PhysicsBodyComponent` (House of BoBA) → Bullet (`org.physics:bullet`) since Filament ships no physics — significant additional work.

## 052 — Firebase: stay on Spark (free) plan
*2026-05-19*

Android uses Firebase **only** for FCM push delivery. No Firestore, Realtime DB, Firebase Auth (Supabase + Credential Manager + supabase-kt), Firebase Hosting, Firebase Storage (R2 per #008).

Spark covers it: unlimited FCM delivery; everything else we don't use. Single Firebase project, one Android app under it (`com.bobaplaybook.app`), `google-services.json` committed to `android/app/` (public identifiers, safe), `firebase-messaging:24.x` dependency. No Blaze upgrade needed for v1.

## 053 — No Twitter / X integration, ever
*2026-05-20*

BOBA will **never** ship Twitter / X integration across iOS / web / Android. Includes: Twitter login (OAuth), share intents (`twitter://post`, `twitter.com/intent/tweet`), Card meta tags (`twitter:*`), embedded widgets / timelines, API consumption, follow buttons, any Twitter-branded affordance.

**Why:** X is owned and editorially operated by a fascist. Integrating — even passively through metadata — signals endorsement and provides material support. BOBA won't direct any user, viewer, or brand element to that platform.

**What still ships:** standard Open Graph (`og:*`) is read by Discord / iMessage / Slack / Bluesky / Mastodon / Threads / Facebook / LinkedIn / WhatsApp / Signal / Telegram / search engines. Other social platforms (Bluesky / Mastodon / Threads / Discord) fine when use cases arise.

**How to apply:** reject PRs adding `twitter:*` meta tags, `twitter.com` URLs, Twitter SDK / API, share-to-Twitter buttons, or "tweet this" copy. Future Twitter-pattern features → Web Share API + OG protocol so other platforms inherit naturally. If a third-party template ships with Twitter integration, gut it before integrating.

## 054 — Web Scan re-surfaced as fallback + native-app gateway
*2026-05-22*

Partially supersedes the web-side of [#012](#012). Scan on web is no longer "out of scope" — it's a sidebar destination with three jobs:

1. **Camera-capture fallback** for users who don't have the native apps. `getUserMedia` → frame → Cloudflare Worker OCR. Less performant than iOS Vision / Android ML Kit (server round trip, no fingerprint matching) but functional.
2. **Desktop → phone QR session handoff.** Desktop browsers see a QR encoding `?view=scan&rt={refresh_token}`. Phone scans → opens BOBA on phone with desktop session carried over. Refresh token regenerates every 30s to track Supabase's rotation.
3. **Native-app gateway.** Inline TestFlight (iOS) + Google Play (Android) CTAs surfaced inside the Scan view — most contextually natural place to advertise the canonical scanner.

**Why the reversal:** beta testers explicitly asked for it. The web implementation already existed (hidden in commit `013cf90` 2026-04-27); only the sidebar entry was removed. Restoring the sidebar entry costs nothing because the code never left. The on-device-Vision principle from #012 still governs the **canonical** scanner — web is now framed as an *adjunct*, not a replacement.

**How to apply:**
- Web Scan IS in scope for iteration. PRs improving the Worker OCR path, QR handoff, or native-app CTA copy are welcome.
- The native-app CTA tiles are the spec for *every* surface that wants to advertise iOS / Android — reuse `nativeAppCalloutHTML()` in `js/app.js` rather than re-inventing.
- DESIGN.md / WEB-DESIGN.md / PARITY.md updated in tandem so this isn't whiplash-driven.
- iOS Vision + Android ML Kit remain the canonical on-device scanners; web is the only platform with a server-OCR + QR-handoff posture.

## 055 — Android scan: multi-pathway OCR recovery for shiny / holographic cards
*2026-05-23*

Real-world testing of **DEKAP GGL-779 (Great Grandma's Linoleum Battlefoil — Glow treatment)** drove a rewrite of the Android matcher to accumulate **six independent recovery paths** instead of relying on a single clean OCR read. iOS DECISIONS.md #035's strict cardNumber regex + hero veto stays as the core, but Android adds:

1. **Joined-text cross-token reassembly** (split `BHBF` + `37` → `BHBF-37`)
2. **Digit-confusion suffix normalisation** (`GGL-T79` → `GGL-779` via T→7, S→5, etc.)
3. **Missing-dash reconstruction** (`GGL779` → `GGL-779`)
4. **Prefix-only candidate gathering** (gated on heroesMentioned to prevent 786-card pool broadcast)
5. **Digit-to-letter prefix normalisation** (`G6L` → `GGL` via 6→G, 0→O, etc.) — the most-impactful path; OCR consistently mis-reads `G` as `6` on shimmery prints
6. **Reconstructed cardNumber** (prefix `GGL` + bareDigit `779` → synthesized `GGL-779`)

Plus three signal-side enhancements:
- **Cross-frame OCR token aggregation** (last 10 frames' tokens unioned before matching)
- **Loose bare-digit recovery** (standalone garbled tokens like `T79` normalised)
- **Fuzzy element matching** (`BRAWI` / `BRANL` → `BRAWL` via Levenshtein 1)

And the **killer feature: a parallel preprocessed-OCR pipeline.** Every 600ms a custom `enhanceContrast` (5th/95th-percentile luma stretch) is applied to a `PreviewView.bitmap` snapshot and fed through a SECOND ML Kit pass. Output tokens join the same aggregation buffer. This dramatically expands mid-tone contrast in the cardNumber-strip area that AE blows out on shimmer.

**Why Android diverges from iOS here:** the iOS scanner has a vastly cleaner OCR baseline (Vision + iPhone camera tuning) and `feature-prints.bin` image-fingerprint matching for hard cases (DECISIONS.md #035). Android's ML Kit OCR is noisier on shimmer + image-fingerprint matching is deferred to v2 (DECISIONS.md #043). The matcher-side recovery paths + preprocessing pipeline close that gap to "consistently scans at least as well as iOS for this card" (Ben validated 2026-05-23).

**Why we DIDN'T do** (cautionary tale at iters 46-47):
- Lowering the stabilizer single-frame tier below 2.5 → wrong-card commits at lower margin.
- Relaxing the matcher's 0.3 margin floor → wrong-element-variant commits when OCR confused element on shiny prints, locked `lastCommittedBobaId`.

Both reverted within minutes of install. The matcher's confidence + margin floors are load-bearing.

**How to apply:**
- New recovery paths get a SCANNER_LOOP.md iter row + a JVM test in `ScanCardMatcherTest`
- Don't tune confidence floor < 1.4 or margin floor < 0.3
- Don't lower stabilizer single-frame tier below 2.5
- ALL changes verified via `adb logcat -s ShinyScanDiag` showing the signal breakdown PER FRAME — see iter 49 + 54b for the diagnostic shape
- 29 JVM matcher tests + 9 stabilizer + 9 guide math + 10 queue + 10 canonicalize = 67 total — the test suite IS the safety net for further matcher tweaks

The `[[reference_android_scanner_recovery_paths]]` memory has the full architecture diagram + don't-touch list.

## 056 — Radish Price Guide integration removed (compliance request)
*2026-05-23*

Email from Scot + Rob (Radish Price Guide owner / lead developer) on 2026-05-23 stated they consider BOBA Playbook a potentially competing product and revoked authorization for Radish data, images, pricing, catalog mapping, lookup logic, automated workflows, and partner/primary-source language. The ONE thing they remain comfortable with is "ordinary user-facing linking to Radish Price Guide" where the user leaves BOBA Playbook to view information directly on Radish.

**What was removed** (`RADISH_REMOVAL_LOOP.md` has the full tick log):

- **Worker (`boba-ebay-proxy`)** — `fetchRadishSales`, `fetchRadishMarketEst`, `fetchRadishCardId`, `getRadishBuildId`, `RADISH_NAMESPACES`, hero/casing alias tables, sitemap-driven URL resolver, `/radish-url` + `/radish-url-map` endpoints, `radishResolvedUrl` response field. Pricing collapsed to eBay sold + active only. Cache namespace bumped to v18.
- **Worker (`boba-youtube-feed`)** — `radishdijital` removed from `KNOWN_CHANNELS`; priority-0 channel pin emptied. Their YouTube content can still surface organically via the BoBA search-query path (ordinary public-content discovery), but BOBA no longer specifically pulls or elevates their channel.
- **iOS** — `Card+Radish.swift` deleted in full (URL resolver + alias tables + `RadishURLResolver` HEAD-probe logic). `Card.radishUrl` field retained as frozen legacy reference data. New helper `Card.radishDisplayURL` returns `radishUrl` when present, else the Radish homepage. "Radish Guide" Button + SafariView sheet replaced with SwiftUI `Link` to that URL — opens the system default browser externally, never `SFSafariViewController`.
- **Web** — `SET_SLUG_MAP`, `RADISH_HERO_ALIASES`, `buildRadishUrl` deleted from `js/app.js`. Per-card anchor reads `radishDisplayUrl(card)` (legacy `card.radishUrl` when present, else homepage). `target="_blank" rel="noopener noreferrer"`.
- **Android** — `PricingSource` enum collapsed to `{EBAY}`. `radishResolvedUrl` field stripped from Worker response model + `PricingBundle` + `CardDetailUiState` + `PricingState`. New "View on Radish" `TextButton` at the bottom of pricing panels using `Intent.ACTION_VIEW` with `card.radishUrl ?: homepage` — opens the system default browser (not `CustomTabsIntent`).
- **Pipeline** — deleted `pipeline/scripts/stage_a_scrape_radish.py`, `scripts/build_radish_url_map.py`, `scripts/apply_radish_urls.py`, `scripts/probe_radish_urls.py`, and `assets/data/radish-url-map.json`. New helper `scripts/identify_radish_sourced_cards.py` emits a backfill queue for the 8,386 cards whose images came from Radish; Ben runs the existing `pipeline/scripts/stage_a_scrape_src.py` against the queue to re-source from the card source.
- **Docs** — `DECISIONS.md` #013 amended; this entry added; `DESIGN.md` §8.7, `ANDROID-DESIGN.md` §8.7, `PARITY.md`, `README.md`, `PITCH.md`, `SCRATCHPAD.md`, `terms/index.html`, `LearnView.swift` glossary, `index.html` glossary, `LearnContent.kt` glossary all updated.

**The one approved use case — per-card external link.** Email allowed "ordinary user-facing linking." Ben confirmed mid-loop that direct-linking to specific cards is within the spirit. Reconciliation: use the legacy `card.radishUrl` field already in `cards.json` (acquired pre-email from Radish's sitemap; treated as frozen static data going forward) as the per-card link destination; fall back to `https://radishpriceguide.com` when the field is null. Every form of automation the email prohibits — sitemap pulls, HEAD probing, alias tables, runtime URL construction, Worker `/radish-url` endpoint — stays fully deleted. Button label is "View on Radish."

**Pricing replacement plan** (separate entry coming when shipped):
- Tier 1 (sold history) — tuned `normaliseSoldEnriched` over eBay Marketplace Insights, 180-day window, AI image-verification on ambiguous matches.
- Tier 2 (Market Est. for cards with no eBay activity) — new `boba-price-estimator` Worker. Comparability function over our own catalog (hero / weapon / power-tier / treatment-family / set / cardType), KV-cached, cross-set hero anchoring as bootstrap. Replaces what Radish's Market Est. previously did.
- Tier 3 (long-term coverage moat) — community-submitted comps. Auth-gated form + mod queue piggybacking on the existing `card_corrections` plumbing.
- External-source research (separate sub-agent) returned: no third-party source is worth integrating to replace Radish. PSA APR is graded-only (near-zero BOBA coverage), 130point has no API and derives from eBay, TCDb forbids scraping, Whatnot post-stream sales have no public API, COMC sold is Turnstile-blocked, Goldin / Sportlots have no APIs. eBay Marketplace Insights is the only first-party-licensed long-tail source for the foreseeable future.

**Why this matters principle-wise:** preserving the ability to operate independently of any single third party is the load-bearing concern. The removal cost was bounded (~3 weeks per walk-away §8.4), and the replacement plan deepens BOBA's own moat (community comps + our own comparability model) rather than swapping one external dependency for another. CLAUDE.md "Why We Build": tools that make users more capable, not more dependent.

**How to apply:** any PR adding a Radish reference (data fetch, URL construction beyond the homepage fallback, alias table, lookup logic, source pill, partner language) is rejected. The only Radish-related code permitted: the `Card.radishUrl` field's per-card link destination + the homepage fallback string. Worker, scrapers, alias tables — all permanently gone.

## 057 — bobaId formula v3 adds weapon as 5th field
*2026-05-25*

Extended the bobaId formula from 4 fields to 5 by appending the card's
WEAPON (catalog field `element` per DECISIONS.md #027 — the BoBA-canonical
term in any human-readable prose is Weapon):

```python
# v2 (2026-04-09):
bobaId = f"{cardNumber}-{hero or name}-{treatment or ''}-{variation or ''}"

# v3 (2026-05-25):
bobaId = f"{cardNumber}-{hero or name}-{treatment or ''}-{variation or ''}-{element or ''}"
```

**Why**: The card-art audit pipeline (CARD_AUDIT_PIPELINE.md) surfaced
that many cards exist as FIRE-weapon + GLOW-weapon variant siblings
sharing otherwise-identical (cardNumber, hero, treatment, variation).
On the v2 formula those collided on bobaId. The catalog had been
working around the collision by assigning distinct cardNumbers to the
weapon variants — e.g. `GLBF-43 = GLOW Grandma's Linoleum Battlefoil
BoJax Founding Hero Alpha Update` AND `GLBF-85 = FIRE Grandma's
Linoleum Battlefoil BoJax Founding Hero Alpha Update`, even though
both physical cards may share other field values. The workaround
broke when the audit's OCR read the printed cardNumber on the FIRE
variant as the lower number (matching the GLOW variant's catalog
cardNumber) — Ben approved 101 cardNumber changes to merge them
which would have produced true bobaId duplicates.

**The right schema fix**: include weapon in the bobaId so the same
physical printed cardNumber can be retained for both weapon variants
without collision.

**Migration shape**: deterministic mapping from old (4-field) bobaIds
to new (5-field) bobaIds for every catalog card (17,974 entries).
Applied in lockstep across:

- 3 canonical formula sources: `scripts/boba_id.py`,
  `BOBAPlaybook/Models/Card.swift`, `android/core/.../Card.kt`
- 5 catalog bundles: `assets/data/cards.json` (master) +
  `assets/data/cards-head.json`, `BOBAPlaybook/display-cards.json`,
  `BOBAPlaybook/cards-head.json`, `android/app/.../cards.json`
- Supabase tables: `user_cards.boba_id`, `card_corrections.boba_id`,
  `card_image_overrides.boba_id`, `show_cards.boba_id`,
  `deck_cards.boba_id`, plus pipeline tables
- iOS feature-prints index (`feature-prints.bin`): rebuilds
  automatically on next pipeline run; keys are opaque strings
  per `scripts/build_feature_print_index.swift`

**What was NOT changed**: R2 image filenames (`imageFile` field per
card is a separate stored string, not derived from the formula at
lookup time — old image keys stay valid). Pipeline-internal staging
identifiers in `pipeline_image_candidates.target_boba_id` that use a
distinct underscore-separated `Auto` suffix format were left alone;
those are workflow tokens, not user-facing bobaIds.

**How to apply**: any future code reading or writing a bobaId must
use the 5-field formula. The canonical sources (boba_id.py +
Card.swift + Card.kt) all share the same shape — never redefine the
formula inline anywhere. If a new pipeline script imports
`from boba_id import boba_id`, it automatically picks up the v3
formula.

**Future expansion**: if a 6th disambiguator becomes necessary
(today's catalog already verified zero v3 collisions across 17,974
cards), repeat this migration shape: new field at the end of the
formula, deterministic catalog → mapping table → Supabase UPDATEs
via PostgREST bulk insert + SQL UPDATE.
