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
*2026-04-03*
Each element maps to a canonical UI color: FIRE #FF4D00, ICE #00BFFF, HEX #8B00FF, STEEL #8A9BB0, BRAWL #C0392B, GLOW #FFD700, GUM #FF69B4, SUPER #FF00FF, NONE #666680. Elements in cards.json are always UPPERCASE.

## 011 — No Card Images in Git
*2026-04-03*
Card images live exclusively on Cloudflare R2. `assets/data/` contains only JSON. Keeps clone fast and avoids GitHub's soft 1 GB storage limit.

## 012 — Scan Mode: On-Device Vision Only
*2026-04-03*
Card identification uses iOS Vision (`VNRecognizeTextRequest`) and AVFoundation only. No image is uploaded. Pipeline: OCR frame → card number regex `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)` → match display-cards.json. Falls back to manual search.

**Principle**: User data stays on user devices. On-device processing is not a technical constraint here — it's the right choice for the user.

## 013 — Pricing Comps Strategy
*2026-04-03*
Pricing fetched live at card-detail view time via Cloudflare Worker (eBay Browse API + Radish Price Guide in parallel). Prices not stored in Supabase — live lookups only. Collection value dashboard caches last-fetched price in `user_cards.estimated_value`.

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

**Master-level fallback**: When a master-level collision cannot be resolved because the correct source art does not exist publicly (verified against Radish, BazookaVault, Cardeio, and any other known source), the card is reclassified into the missing-art queue instead: set `imageFile=null, imageSource=null, imageAvailable=false` in `cards.json`, regenerate `missing-cards.json` via `step5`, and let `ebay_missing_images.py` recover the art on its next run. First applied 2026-04-13 to the three Griffey Edition Blizzard Battlefoils (BLBF-95 D-Harp, BLBF-120 Zephyr, BLBF-174 Highway to Helton) — their correct art turned out to not exist on any surveyed CDN.

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
Two parallel state arrays on `PracticeStore` drive every persistent effect:
- `persistents: [PersistentEffect]` — every persistent block from a played card's `persistent[]` array except weapon-transform ops
- `weaponTransforms: [WeaponTransform]` — split out separately so the hot-path weapon read (`ctx.weapon(of:as:)`) consults a flat array instead of re-walking persistent specs

**Install**: `installPersistent(owner:spec:)` is the single entry point. It splits weapon-transform specs into the dedicated array; everything else routes to `persistents`. Both player + CPU play-resolution sites call this helper (no direct `.append` allowed).

**Lifecycle triggers**: `firePersistentTriggers(trigger:winner:)` is the single dispatcher for non-continuous effects. Called at:
- top of `resolveCurrentBattle` → `on_plays_resolved` (deltas land in slot.effectPower so end-of-turn boosts can swing the verdict)
- end of `resolveCurrentBattle` → `on_battle_win` + `on_battle_loss` filtered by owner side
- inside `moveToNextBattle` → `on_battle_start` (after honors + block-purge, before marked-battle on-reveal effects)
- inline in `resolveCurrentBattle` for B.8 `auto_lose_battle` checks (supersedes normal compare)

**HD recover pipeline**: Every positive HD change routes through `applyHDRecover(side:amount:)`, which runs redirect → cap → delta → block in that order. Negative HD (spend) bypasses the pipeline.

**Scope vocabulary**: Single `isScopeActive(_:installedAt:at:spec:)` helper recognizes `rest_of_game`, `this_battle`, `next_battle`, `this_and_next`, `next_2_battles`, `next_N_battles` (with `n:` field), `battle_1`–`battle_7`, `battles_4_7`, plus legacy aliases. Unknown scopes return false (silent no-op safety net for new scopes authored before the host learns them).

**Why this architecture**: Centralizing install + lifecycle + scope eval in three single-source-of-truth helpers means future op families (B.6 / B.7 / B.10 / B.11 / B.13) need only their per-op behavior — they get all the plumbing for free.

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
Three items from the bobaleagues handoff (and the 2026-04-27 BoBA DBS
update) are blocked on either the BoBA team or real-world signal we
don't yet have. Cementing them here so they don't get lost between
handoffs.

**(a) `LA - 20 — Series MVP Award` anomaly.** One row in BoBA's
2026-04-27 DBS update PDF reads `LA - 20  Series MVP Award  0  If
MVFree is your Hero in the current Battle he gets +30.  6`. The `LA`
prefix doesn't match any other release in our catalog (A / U / G / HTD
all map to existing sets; LA does not). Three live possibilities:

1. PDF parser glitch — should be `U - PL-20` or similar
2. A new "Limited Alpha" / promo subset that arrived with this patch
3. A Legendary-Alt or hero-bonus card tied specifically to "MVFree"

The card text references *MVFree*, which appears to be a hero name we
don't currently have in `cards.json`. Until BoBA confirms what `LA` is
and whether MVFree exists as a hero record, the row is intentionally
skipped from the DBS merge — it's the only one of 411 update rows that
didn't land. **Ben TODO**: ask the BoBA team directly. Once resolved,
rerun `dbs_merge.py` with the corrected mapping (and add MVFree as a
hero record if needed).

**(b) bobaleagues CSV roundtrip verification.** Phase C shipped a v2
CSV format (`id,name,type,release,number,cost,dbs,ability,bonus`) per
handoff §6, alongside the legacy v1 format (`Slot,Card#,...`) that's
designed to load into bobaleagues' deck-builder upload form. The
verification step is unblocked but unfinished: **Ben TODO** is to
build a real Playbook on bobaleagues, export a CSV from there, and
drop it in the recon folder so we can adjust our exporter shape to
match if anything drifts. Until then we keep both v1 + v2 export
paths — v1 stays untouched for bobaleagues compat, v2 is the
canonical full-deck format for in-app roundtrips.

**(c) Elo tier-band tuning.** The Phase D rating system uses 200-pt
bands keyed to BoBA's weapon vocabulary (Brawl 0–999, Steel 1000–1199,
Ice 1200–1399, Fire 1400–1599, Glow 1600–1799, Hex 1800–1999, Gum
2000–2199, Super 2200+). The bands are live-derived from rating —
never stored — so we can re-tune without lying about historical state.
But the tuning itself needs **real practice-distribution data** before
we have signal: a K=32 ladder seeded at 1000 will pile up around
800–1200 for most users, and the question is whether band widths
should narrow at the bottom (so most users see at least 2–3 tier-up
moments early) or stay uniform (so the climb to Super means
something). Revisit once we have ~1k practice matches in production.

**Why deferring is right**: All three are blocked on something we
don't control — BoBA's confirmation, a Ben-side artifact, or
production data. Fabricating answers now would mean either guessing
about LA-20 (and silently drifting from the canonical list), shipping
a CSV that doesn't actually roundtrip with bobaleagues (breaking the
courtesy interop), or tier-band tuning against synthetic data (which
won't predict where real users cluster). The cost of waiting is zero;
the cost of guessing is silent drift.

## 034 — COMC asking-price as second BUY NOW source (NOT in sold-comp waterfall)
*2026-04-29*
Per Cowork's `handoff-updates-2026-04-29/comc-feasibility/`, COMC.com
exposes 931 BoBA listings with cardNumbers matching cards.json
exactly. Wired up as a parallel source to the BUY NOW panel
(alongside eBay active listings) on both iOS (`ComcService.swift` →
`PricingSection.comcStrip`) and web (`fetchComcListings` →
`renderComcStrip`).

**Critical: COMC asking prices stay OUT of the sold-comp waterfall.**
The Radish sales → eBay sold → Market Est. chain that produces the
"what's this card worth" number measures TRANSACTED prices. Mixing
COMC's asking prices in would inflate the estimate (asking runs
~10-25% above sold for trading cards). COMC is purely additive on
the BUY NOW panel where the question is "where can I buy this card
right now," not "what's the market value."

Each COMC row carries a "COMC asking · Ungraded NM" pill so users
read the number as a list price, not a transaction. Tap-through
opens the COMC detail page — no in-app purchase flow.

**Turnstile caveat (live state 2026-04-29)**: COMC turned on
Cloudflare's managed JS challenge hours after Cowork's recon.
The worker (`boba-comc-proxy`) is fully wired and detects the
challenge as `challenged: true`, returning `count: 0` so clients
soft-fail to "no COMC items." Bypass options when revisiting:
Cloudflare Browser Rendering API, Playwright runner, or
out-of-band cf_clearance cookie persistence. Defer until COMC's
WAF stance changes or COMC integration becomes a higher priority
than the cost of bypass tooling.

## 035 — Unified card recognition: image fingerprint as primary, OCR as confirmation
*2026-04-30*
Every scan mode (single live, multi live, show live, photo-picker
still, grid burst) now routes through a single recognition function:
`ScanMatching.resolve(observation:allCards:)`. The previous design
ran two parallel matchers — `ScanView.handleDetected` filtered by
OCR cardNumber and tiebroke ties via FP, while `resolveGrid` ran an
8-stage waterfall with magic thresholds. Both treated the OCR
cardNumber as the primary key, which is exactly what failed when
OCR returned a real-but-wrong number (a partial read of "BHBF-37"
arriving as "20"). The catalog returned a legitimate card at "20"
(Tigre, base set), the printed hero on the photographed card
(JacHammer) had no veto, and the wrong card committed.

**The redesign**: image fingerprint (already shipped as
`feature-prints.bin`) is now the primary identifier. The 9,206-entry
"shared cardNumber only" filter (built when FP was a tiebreaker) is
gone — the index now covers all 16,123 imaged cards in a 12.7 MB
bundle. Every signal contributes BOTH candidates and scores:

  * FP top-30 by L2 distance → ranked candidate pool
  * OCR cardNumber exact match → +1.0
  * OCR cardNumber bare-digit suffix match → +0.4 (recovers prefix-stripped reads)
  * Hero name in top-left quadrant → +1.5
  * Hero name elsewhere → +0.6
  * **Hero veto**: when one or more heroes are clearly named in
    top-left text, ANY candidate whose hero isn't in that set gets
    −2.0. This is the missing piece — it's why the 8-stage waterfall
    occasionally trusted an OCR cardNumber match that the printed
    hero contradicted.
  * Element + treatment + power → small additives

A confidence floor (1.4) and margin floor (0.3) gate the commit.
When neither is met, the resolver returns nil ("don't guess") and
the cell renders as "Not identified" — better UX than a confident
wrong answer.

**Why this works for every mode, not just grid**: the live scan
chain `AVCaptureSession → CardScanner → ScanObservation` and the
grid chain `Photo → GridCardDetector → CardScanner.scanGridImageBurst
→ ScanObservation` produce the same shape. The unified resolve
consumes ScanObservation regardless of source. Every improvement —
better FP coverage, hero veto, perspective-rectified grid crops —
applies to all five scan entry points simultaneously.

**Why FP is right as the primary**: text OCR fails partially in
ways that look like success — a real-but-wrong cardNumber matches
the catalog and silently commits the wrong card. Image fingerprint
fails completely in ways that look like failure — distance to every
catalog entry is large, the resolver returns nil, and the user
retries. The mode of failure is what matters: silent-wrong is the
worst possible UX for a card-recognition app.

**Grid-cell perspective rectification**: GridCardDetector now
perspective-corrects from each anchor's quad with an ADAPTIVE
bleed sized to lane-derived dimensions. The previous "anchors clip
the bottom-left cardNumber" issue (~22% under-detection) is fixed
by inflating the quad to match the lane-spacing-derived card size
before rectifying. Cells without anchors fall back to axis-aligned
crops at predicted positions.

## 036 — Wall + Price Overlay: lift from streamer-only gate to general collector use
*2026-05-03*
Per DESIGN.md §8.4 and §8.8, the Wall display mode (renders
multiple cards as a single image for sharing) and the Price Overlay
(renders price chips on top of card images) become first-class
features for every collector — not gated to the streamer role.

This **partially supersedes [DECISIONS.md #025](#025)** ("Feature Gating:
Keep Code, Hide UI Entry Point") for these two specific features.
The underlying principle of #025 is still valid for genuinely-blocked
features (Discord trade room, eBay Market Feed). Wall + Price
Overlay are not blocked on external infrastructure — they're shipped
and working. The streamer-only gate was a scope-control decision
when the features were first built; with the design overhaul, scope
expands.

**What lifts:**
- Wall view becomes a Collection display mode for every collector
  (Grid / List / Wall picker in toolbar Menu)
- Wall view also accessible from Decks (overflow Menu → "Generate
  deck wall") and Find (multi-select → "Wall these N cards") — the
  latter two are §8.8 follow-ups; this entry covers the Collection
  case
- Price Overlay becomes a Wall-view toggle with per-designation
  defaults (For Sale: ON with My price, For Trade: ON with market
  estimate, Grails/Personal: OFF, Wanted: ON with WTB prefix)
- Generic CollectionWallSheet wraps ShowWallComposer (already a
  pure composer with no role coupling — the gate was at invocation
  level only)

**What stays gated to streamers:**
- "My Shows" Whatnot show management (per DECISIONS.md #025 still
  applies — the Whatnot integration is the streamer feature, not the
  Wall rendering)
- ShowDetailView's per-show wall generation (lives inside the
  streamer-gated Shows tab)
- The community trade room (Discord-bot dependency unchanged)

**Why now:** The design overhaul's premise (DESIGN.md "card art is
always the focal point — UI chrome frames it, never competes") is
served by Wall view as a sharing affordance for every collector.
Holding it behind a streamer role meant the most visually-distinctive
sharing surface in the app was invisible to most users. Lifting the
gate aligns invocation with the principle.

**How to apply:** When implementing display-mode pickers or share
affordances, expose Wall and Price Overlay to all signed-in users.
Don't add new role gates around either feature. The underlying
ShowWallComposer enum stays unchanged — it's pure composition logic
with no role coupling.

## 037 — Profile redesign: username = display name = public handle
*2026-05-04*
The Profile sheet (DESIGN.md §6.5) ships a single `username` field
that doubles as the user's display name AND the slug for their
public collection URL (`bobaplaybook.com/u/{username}`). There is no
separate `display_name` — they were collapsed deliberately because
two parallel "what should I be called" fields drift in confusing
ways (Discord's display-vs-username conflation is the cautionary
tale).

**Auto-derivation**: on first profile open, the iOS UsernameRow
derives a candidate from the email local-part (lowercased, stripped
to `[a-z0-9_-]`), then appends a numeric suffix (2…99) on collision
and writes via the `set_username` RPC. Discord-OAuth users with no
email fall back to `user-{6-char-hash}` from their user_id. Users
can edit inline at any time — debounced check_username on every
keystroke renders a status pill (`✓ available` / `✗ taken — try
@ben2` / `✗ not allowed` / `✗ reserved`).

**Banned-words gate**: two-layer per the user's "no slurs / no hate
speech" requirement.
1. Client (`BOBAPlaybook/banned-words.json`, ~270 entries) gives the
   instant red pill in the inline TextField — zero network.
2. Server (`banned_words` table on Supabase, populated from the same
   `scripts/build_banned_words.py` source) is the authoritative gate
   via `check_username` and `set_username` RPCs — defense in depth
   so a modified client can't bypass and squat
   `bobaplaybook.com/u/{slur}`.

Source: LDNOOBW EN list (Shutterstock, Apache 2.0, multilingual)
filtered to ≥4-character entries to reduce Scunthorpe-style false
positives. Reserved infrastructure terms (`admin`, `mod`, `boba`,
`api`, `www`, etc.) live separately in the `username_is_reserved`
Postgres function — they don't churn the way the slur list does.
Custom additions go in `scripts/custom_banned.txt`; rerun the
script + re-apply the SQL to refresh both layers in lockstep.

**Why this matters**: usernames are public-facing, persistent, and
a vector for harassment. The cost of a slur landing on a public URL
is much higher than a brief moment of "let me try ben2 instead"
friction. The two-layer gate also exists to protect us from our
own client bugs — if the bundled JSON ever falls out of sync, the
server still refuses.

## 038 — Profile redesign: generalized role-request (mod OR streamer)
*2026-05-04*
The original mod-request flow (`mod_request_reason` /
`mod_request_at` columns + `submit_mod_request` RPC +
`get_pending_mod_requests` RPC) is generalized to `requested_role` /
`requested_role_at` / `requested_role_reason` columns +
`request_role(role, reason)` RPC that accepts `'moderator'` OR
`'streamer'`. The admin queue (`get_pending_role_requests`) returns
both kinds; review (`review_role_request`) promotes to whatever role
was requested.

**Compat shims**: the old `submit_mod_request`,
`get_pending_mod_requests`, and `review_mod_request` functions are
kept as wrappers that delegate to the new ones, so any unshipped
build of the iOS Admin Panel keeps working through the deploy
window. The shims should be dropped in the next release.

**Why now**: streamer was always going to need a request flow — the
iOS Profile section asks for both, and one mechanism is cheaper to
own than two. The migration is purely additive at the column level
(old columns linger nullable, new columns inherit existing data via
a one-shot `UPDATE … SET requested_role = 'moderator' WHERE
mod_request_at IS NOT NULL`) so no data is lost.

## 039 — Profile redesign: deferred features (UI ships, backend deferred)
*2026-05-04*
Three Profile features ship with functional UI but the backend
work that makes them actually do something is intentionally
deferred. The UI lands now so the surface is complete and users
can opt in early.

**(a) Trade match alerts** — toggle in the Notifications section.
Persists to `user_profiles.match_alerts_enabled` via the
`set_notification_prefs` RPC. The matching pipeline (queries
`user_cards` for cross-user Wanted/Grail overlap, fans out via
APNs) is multi-week of work and is blocked on standing up an APNs
server-side dispatcher we don't have yet. Footer text reads
"Coming soon — toggle to opt in early." When the dispatcher
ships, the toggle is already live and respected.

**(b) Public collection sharing** — IMPLEMENTED 2026-05-04. Toggle persists to `user_profiles.public_collection_enabled`. Web route `bobaplaybook.com/u/{username}` live: `404.html` redirects `/u/{slug}` → `/?u={slug}`; SPA mounts `view-public-collection`; `js/api.js#fetchPublicCollection` calls `get_public_collection(handle)` Supabase RPC (SECURITY DEFINER + STABLE). Returned projection EXCLUDES `purchase_price`/`asking_price`/`notes` and filters out Wanted (public reads as "what they have," not "what they want"). Renders via shared `buildCardElement`; card detail opens read-only.

Per-designation toggles deferred (today's toggle is global). Wanted-as-WTB-list (DESIGN.md §8.4) needs its own opt-in surface.

**(c) Account deletion** — IMPLEMENTED 2026-05-05. `boba-account-delete` Worker (`workers/account-delete/worker.js`): POST `/account/delete` w/ Bearer JWT → verifies vs Supabase `/auth/v1/user` → forwards to admin `/auth/v1/admin/users/{id}` using service-role secret. Postgres FK CASCADE on `auth.users` clears `user_cards`, `decks` (+`deck_cards`), `shows` (+`show_cards`), `user_profiles`. Mod-submitted `card_corrections` / `card_image_overrides` use SET NULL so audit trail survives anonymously.

Wired on iOS + web; both sign out locally on success. Worker URL: `https://boba-account-delete.benwilkoff.workers.dev` (in `WorkerConfig.accountDeleteURL` and `js/api.js`). Secrets: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`.

**Why ship UI ahead of backend**: removing toggles later is much
worse UX than disabling them temporarily. The opt-in data is itself
useful signal once the backend ships ("how many users already
wanted this?"). And the destructive-action shim for deletion is
the right call vs leaving the App Store requirement unmet for the
duration of the backend build.



## 040 — Profile pictures: Discord-default, R2-on-upload
*2026-05-05*

Three-tier resolver: **custom (R2-uploaded) → Discord avatar → default silhouette.** Most users auth via Discord OAuth → recognizable avatar at zero storage cost. Only explicit uploads consume R2 space; ~50KB cropped JPEG × active-user fraction keeps bucket trivially small.

**Storage:** existing `boba-card-images` bucket, `avatars/{user_id}.{ext}` prefix (jpg/png/webp). Public URL `{CDN_BASE}/avatars/{user_id}.{ext}`. Pre-write delete sweep clears prior `avatars/{user_id}.*` with different extension so the resolver doesn't see duplicates.

**Worker** (`workers/avatar-upload/`, `boba-avatar-upload.benwilkoff.workers.dev`): POST `/avatar` w/ Bearer JWT + bytes (≤2MB) → verifies vs `/auth/v1/user` → writes R2 → returns `{url, version}`. DELETE clears all extensions. Secrets: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`.

**Supabase:** `user_profiles.avatar_url` (nullable; NULL = fall back). RPCs: `set_avatar_url(new_url)` (own-row, rejects URLs not matching R2 avatars prefix); `get_public_profile(handle)` returns `username, avatar_url, discord_avatar_url` for public-collection page.

**Why R2+Worker, not Supabase Storage:** R2 (DECISIONS.md #008) = zero egress + edge cache + auth-free CDN URL. Supabase Storage avoided per #007.

**Why server-side URL gating:** without the R2-prefix check on `set_avatar_url`, a malicious client could point `avatar_url` at any host (tracking pixels, inappropriate images rendered on others' devices). Worker controls who writes R2; RPC controls where the column points.



## 041 — Android: Kotlin + Jetpack Compose (not KMP / Compose Multiplatform / Flutter / RN)
*2026-05-19*

Native Kotlin + Compose codebase, separate from iOS Swift/SwiftUI. Same monorepo (`/android/` at root). The iOS app is already shipped Swift-native (DECISIONS.md #004); migrating its business logic to a Kotlin "common" module for sharing means rewriting iOS at the same time, which we are not doing.

**Why:**
- KMP works best when both platforms start together. BOBA didn't — iOS is at v2.282+, web is shipped, Android is starting fresh.
- Compose Multiplatform can't render the iOS-26 Liquid Glass surfaces (`Tab(role: .search)`, `.navigationTransition(.zoom)`, `.searchable` tokens) that the iOS DESIGN.md explicitly bets on. Picking CMP would force re-implementing core iOS components — net loss.
- Flutter / React Native add a runtime layer and a bridge for every Android native API (ML Kit, CameraX, Play Integrity, biometrics). Strictly worse for an Android-only codebase.
- Each platform speaks its native idiom; the verb-set is identical across iOS / web / Android, the implementations are not.

**Future option:** if Web ever wants typed data models or a Desktop companion arrives, KMP is the upgrade path. Keep that door open by structuring Android's domain layer as pure-Kotlin from day one (no Android imports outside `:app` and `:data` modules — see ANDROID-DEV.md §3).

**How to apply:** see ANDROID-DEV.md §1 for the alternatives matrix; ANDROID-DESIGN.md §1 for the binding implementation rules.

## 042 — Android: Material 3 brand-first; dynamic color is opt-in
*2026-05-19*

BOBA Android ships with a **fixed brand theme** by default (orange/cyan/violet on near-black) — *not* dynamic color (Material You wallpaper-derived palette). Brand identity wins; user can opt into "Use system colors" in Settings.

**Why:** the card-art palette is the focal point. A user's wallpaper-derived primary fighting with `#FF4D00` reads muddy and washes out the cards. Same rule as iOS DESIGN.md §11.2: element colors only on content semantics; brand colors only on chrome. Dynamic color is a third *opt-in* tier — not the default.

**How to apply:** `BobaTheme.kt` builds the brand `colorScheme` from fixed seeds. When the user toggles "Use system colors" ON, `dynamicDarkColorScheme(LocalContext.current)` overrides `primary` only on Android 12+. Element colors never change. ANDROID-DESIGN.md §6.8 + §11.2 carry the binding rules.

## 043 — Android Scan: CameraX + ML Kit Text Recognition v2 (bundled, Latin); OCR-only for v1
*2026-05-19*

Android scan uses **CameraX 1.5+** + **ML Kit Text Recognition v2 bundled** (Latin script model, ~5-7 MB APK delta). Matches iOS Vision `VNRecognizeTextRequest` shape.

**Why bundled, not unbundled:** unbundled saves ~260 KB of APK but requires a one-time model download on first scan. Bundled is the iOS-parity choice — scan works offline immediately on install. The APK budget hit is small.

**Why OCR-only for v1 (no image fingerprinting):** iOS DECISIONS.md #035 made fingerprint the primary key because OCR-only had a silent-wrong failure mode **in grid scan mode specifically** (a real-but-wrong card number that the printed hero contradicted). For single-card live scan, OCR + hero-name veto + confidence threshold is sufficient — it's the iOS pre-fingerprint design that shipped well for months.

Adding image fingerprinting on Android requires MediaPipe Image Embedder (closest analog to Vision Feature Prints) + building a parallel `feature-prints-android.bin` artifact. Defer to v2 when scope pressure relaxes.

**How to apply:** ANDROID-DEV.md §6.1–§6.5 covers the CameraX + MLKitAnalyzer pipeline, regex reuse, and fingerprint deferral.

## 044 — Android: NO multi-step anchored walkthroughs
*2026-05-19*

Android doesn't ship the iOS-style multi-step anchored walkthroughs (DESIGN.md §6.10's seven-script catalog). Use M3 `TooltipBox` for single-step contextual hints and `BOBAHintBanner` (DataStore-backed dismissal) for inline teaching. Empty states (§6.7) carry the "first-time productive action" that a walkthrough's first step would have shown.

**Why:**
- iOS walkthroughs exist because the iOS interaction vocabulary (tab gestures, fullScreenCover, NavigationStack) has many novel idioms a first-time user must learn. Android conventions (NavigationBar, push/back, FAB, ModalBottomSheet) are universally legible across every Android app the user already uses.
- The walkthrough engine in `BOBAPlaybook/Components/BOBAWalkthrough.swift` is ~600 lines of anchor preference plumbing, dim/cutout overlay, multi-step pager. Reproducing that in Compose for marginal value-add is on the wrong side of the cost/value line.
- Onboarding splash decks are explicitly rejected (DESIGN.md §6.10 anti-pattern; same here on Android).

**When to revisit:** if a future Android feature genuinely needs anchored multi-step teaching (Practice executor when it lands, or a complex new flow), revisit and propose a `BOBAWalkthroughHost`. Don't ship by guess.

**How to apply:** ANDROID-DESIGN.md §6.10 + the iOS→Android walkthrough-replacement catalog table. Each iOS walkthrough has an Android replacement (EmptyState / TooltipBox / HintBanner).

## 045 — Cross-platform push: one dispatcher Worker, two transports (APNs + FCM)
*2026-05-19*

When the match-alerts pipeline ships (DECISIONS.md #039 + TRADE-DESIGN.md Phase 5), the architecture is **one dispatcher, two transports.** A Cloudflare Worker `boba-push-dispatcher` (matches BOBA's existing backend pattern):

1. Triggered by Supabase webhook OR cron Worker scanning `trade_matches`.
2. Joins `user_devices` (`user_id`, `platform`, `token`) to get tokens.
3. Routes by `platform`: `apns` → APNs HTTP/2 + JWT; `android` → FCM v1 + Google service-account access token.
4. Both transports support batching.

**Symmetric payload format** so the iOS and Android handlers can share the deep-link logic:
```json
{ "type": "match_alert", "match_id": "...", "other_user": "@handle", "card_count": 3, "deep_link": "bobaplaybook://matches/{match_id}" }
```

iOS lands in `aps.alert` + custom keys; Android lands in FCM `data` and `FirebaseMessagingService` builds the notification + tap-action. **Deep-link is the same string on both sides.**

**Why Worker not Supabase Edge Function:** Cloudflare Workers have better cold-start performance; the existing Worker secrets pattern (`SUPABASE_SERVICE_KEY`, etc.) is already set up. Workers handle APNs JWT via Web Crypto API and FCM v1 via plain HTTPS. The pattern composes cleanly with the rest of BOBA's backend infrastructure.

**How to apply:** ANDROID-DEV.md §7.3 details the dispatcher + `user_devices` table shape. SCRATCHPAD.md Android M7 is when this gets wired.

## 046 — Android-specific app ID + signing strategy
*2026-05-19*

Package name: **`com.bobaplaybook.app`** (matches the bobaplaybook.com domain). Affects all signing + Play Console + `assetlinks.json` + Firebase config + every deep-link entry.

**Signing:** Play App Signing is mandatory since 2021. Generate upload key locally via `keytool -genkey`; upload to Play Console. Play resigns every release with its production key. Upload-key credentials live in `gradle.properties` (git-excluded), mirrored to CI secrets.

**`assetlinks.json` lives at the same `/.well-known/` path as `apple-app-site-association`** on `bobaplaybook.com`. Both coexist; iOS reads AASA, Android reads `assetlinks.json`. The fingerprint must include BOTH the upload-key AND Play App Signing key SHA-256 fingerprints — internal-testing builds (upload-key-signed) won't verify against the production key otherwise.

**Why:** centralizing the App Links setup at `/.well-known/` means one Jekyll-exclude config covers both platforms. The same Cloudflare CDN, same hosting setup, same maintenance overhead.

**How to apply:** ANDROID-DEV.md §8.5 (Play App Signing) + §14 (Universal Links).

## 047 — Android v1 form-factor scope: phone + tablet + Chromebook (NO foldable)
*2026-05-19*

Android v1 ships **phone + tablet + Chromebook** support from M1 onward — adaptive layouts (`NavigationSuiteScaffold`, `NavigableListDetailPaneScaffold`, `WindowSizeClass`) are part of the foundation, not deferred to M8. **Foldable is NOT a v1 target.**

**Why:**
- Ben has a Chromebook available for testing right now — it's the fastest path to validating the build during early development.
- Chromebooks running Android apps and Android tablets share the same `EXPANDED` window-size-class adaptation; supporting one essentially supports the other.
- Foldables represent a small fraction of the market and add meaningful complexity (hinge-pose detection, posture-aware layouts, dual-screen mode). Not worth v1 cost.

**How to apply:**
- ANDROID-DESIGN.md §6.6 adaptation matrix is binding from M1.
- M8 collapses into M1: tablet polish work happens alongside foundation, not after.
- Every screen Composable declares its `COMPACT` / `MEDIUM` / `EXPANDED` behavior. PRs without it are rejected.
- Don't optimize for foldable-specific affordances (`WindowInfoTracker.windowLayoutInfo`, posture detection, etc.). The standard `WindowSizeClass` adaptation will work *adequately* on foldables — just not optimized.

## 048 — Android: Practice executor IS in v1, admin-gated
*2026-05-19*

The Practice executor (iOS DECISIONS.md #030 + #033) ships on Android in v1, admin-gated via the same mechanism — bolt icon on Profile role badge unlocks it.

**Why:**
- Ben wants to test the Battle Practice features on Android during development.
- Practice content is largely platform-agnostic (game rules, state machine, deck loading). The UI translation work is the substantial part; the game logic ports straight.
- Admin-gating means production users don't see it until it's ready for general release — same posture as iOS.

**How to apply:**
- ANDROID-DESIGN.md §12 "Practice / Battle simulator" moves from "Out of scope" to "In scope, admin-gated."
- SCRATCHPAD.md Android milestone plan adds Practice work to a dedicated milestone (M5.5 — Practice executor) between Learn and Purchase.
- Reuse the iOS state-machine architecture (DECISIONS.md #030) — `PersistentEffect` + `WeaponTransform` arrays, `firePersistentTriggers`, `applyHDRecover` pipeline. The Compose layer becomes a translation of the SwiftUI screen anatomy; the engine is pure Kotlin in `:core:domain`.
- Same admin gate via `user_profiles.role` lookup.

## 049 — Discord integration: authentication only, NO bot, across all platforms
*2026-05-19*

Discord usage in BOBA Playbook is **strictly authentication-only** across iOS, web, and Android until explicit permission is granted to integrate a bot within the BoBA Discord server.

**What this means in practice:**
- ✅ OAuth-based sign-in via Discord (existing, all three platforms)
- ✅ Storing the authenticated user's Discord ID in `user_profiles.discord_user_id`
- ✅ Constructing client-side deep-link URLs to other users' Discord profiles (`discord://users/{id}`) — this is URL construction, not API integration
- 🚫 No Discord Bot SDK / API calls from BOBA's servers
- 🚫 No reading BoBA Discord server channels, members, or messages from BOBA's servers
- 🚫 No posting to the BoBA Discord server from BOBA's servers
- 🚫 No webhooks, no Discord Activities, no embedded Discord WebViews beyond what's needed for the OAuth flow itself

**Why:** the BoBA Discord server has its own moderators, rules, and community contracts. A bot operating in that server changes the social contract and needs explicit permission from the server operators. Until that permission is granted, BOBA's only Discord touchpoint is the auth handshake.

**Trading implications (TRADE-DESIGN.md):** the architecture in TRADE-DESIGN.md §4 (pure introduction — send users to Discord to message) **does NOT require a bot.** The "Open Discord" deep link is a client-side URL construction using the authenticated user's stored Discord ID. No server-side Discord API calls. The architecture is compatible with this rule.

**When to revisit:** when Ben has explicit permission from BoBA Discord moderators to deploy a bot. Documented here so future sessions don't quietly propose "BOBA Discord bot for [thing]" without checking back.

## 050 — Android: Sign in with Apple is NOT offered
*2026-05-19*

Sign in with Apple is iOS+Web-only branding. Android does not include it.

**Why:**
- Sign in with Apple is technically possible on Android (via WebView OAuth flow), but it's a foreign brand cue on Android.
- Android users expect Sign in with Google as the canonical "one-tap" sign-in.
- Maintaining a third auth path adds complexity without proportional user-value on Android.

**Auth path on Android (ANDROID-DESIGN.md §6.5):**
1. **Sign in with Google** (primary) via Credential Manager — native one-tap bottom sheet
2. **Discord OAuth** (secondary, but the most-used path for BoBA users in practice) via Auth Tab (Chrome 132+) / Custom Tabs fallback
3. **Email / password** (tertiary fallback) — same Supabase shape as iOS + web

Apple ID accounts created via Sign in with Apple on iOS map cleanly to email-based Supabase users; users can sign into Android with the same email address.

**How to apply:** ANDROID-DESIGN.md §12 "Out of scope" already lists Sign in with Apple. Confirmed.

## 051 — Android future 3D rendering: Filament (primary) or raw Vulkan/NDK
*2026-05-19*

If/when Hero Shot or House of BoBA gets ported to Android (currently deferred per ANDROID-DESIGN.md §12), the recommended 3D-rendering paths are:

1. **Filament** (Google's open-source physically-based renderer) — primary recommendation. Built on Vulkan + OpenGL under the hood; written by Google specifically for Android (and macOS / Linux / iOS). Higher-level API similar in shape to RealityKit. Used by Google Maps, Google Earth, Wear OS.
2. **Raw Vulkan via NDK** (https://developer.android.com/ndk/guides/graphics) — lower-level alternative if Filament's abstractions don't fit. More work to write material shaders, manage the swapchain, handle device-specific quirks. Pick only if Filament's API ceiling is hit.

**Why NOT Sceneform:** deprecated by Google in 2021. Don't propose Sceneform.

**Why NOT Unity-as-library:** brings a JS+Mono runtime overhead that doesn't fit BOBA's lean stack. Unity-as-library makes sense for AR/VR games, not for a card-rendering feature embedded in a Compose app.

**RealityKit → Filament translation work (when it happens):**
- iOS uses `BOBACardEntity` static helpers for card construction (front + back textured planes, rounded-corner alpha mask, off-white edge). Translate to Filament's `Material` + `MaterialInstance` + `Filament.IndexBuffer` / `VertexBuffer`.
- iOS uses `PhysicsBodyComponent` for House of BoBA card-tower physics. Filament doesn't ship physics — bring in `Bullet` (`org.physics:bullet`) or a Kotlin-native physics layer. Significant additional work.
- iOS Hero Shot's roughness-texture-keyed treatments + 3-point lighting + IBL all translate to Filament's PBR materials + IBL pipeline. Approximately 1:1 conceptual translation, multi-week implementation work.

**When to revisit:** when Ben prioritizes Android Hero Shot / House of BoBA. Document this here so the future session has the path picked.

## 052 — Firebase: stay on the Spark (free) plan
*2026-05-19*

BOBA Android uses Firebase **only** for Firebase Cloud Messaging (FCM) push notification delivery. No Firestore, no Realtime Database, no Firebase Auth (we use Supabase Auth via Credential Manager + supabase-kt), no Firebase Hosting, no Firebase Storage (R2 covers CDN per DECISIONS.md #008).

**Spark (free) plan covers what we need:**
- Unlimited FCM message delivery (subject to fair-use thresholds — for BOBA's projected match-alert volume, irrelevant)
- 10 GB/month Cloud Functions invocations (we don't use these)
- Other quotas (Firestore reads, Cloud Storage egress, hosting bandwidth) — we don't use these services

**Setup:**
- Single Firebase project (e.g. "BOBA Playbook")
- One Android app registered under it: package `com.bobaplaybook.app`
- `google-services.json` downloaded → committed to `android/app/` (contains only public identifiers; safe to commit per Firebase docs)
- `com.google.firebase:firebase-messaging:24.x` dependency in `:app`

**iOS doesn't currently use Firebase** (APNs directly). If/when iOS Analytics or iOS push routing through Firebase makes sense, a second Firebase app under the same project is the path. Stays on Spark unless we add Firestore / Cloud Functions / Storage (none planned).

**How to apply:** ANDROID-DEV.md §7 + §13.1 — Firebase setup steps. No upgrade to Blaze (pay-as-you-go) needed for v1.
