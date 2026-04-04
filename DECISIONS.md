# BOBA Playbook — Architecture & Technology Decisions

Entries are ordered by date. This file is **append-only** — never edit or
remove past decisions. Platform noted where specific; unlabeled = both.

---

## Decision 001 — Vanilla HTML/CSS/JS for Web
*Date: 2026-04-03*

**Decision**: No framework, no build step, no dependencies for the web app.

**Rationale**: GitHub Pages serves static files directly. Framework
abstractions cost more than they save at this scale. Aligns with
clarity-over-cleverness.

**Alternatives considered**: React, Vue, Svelte — all require a build step.

**Trade-offs**: Manual DOM manipulation, no reactive state. Revisit if
component count exceeds ~20.

---

## Decision 002 — Xcode Project at Repository Root
*Date: 2026-04-03*

**Decision**: The `.xcodeproj` lives at the repository root, not in a
subdirectory. Project name has no spaces.

**Rationale**: Xcode Cloud requires `.xcodeproj` at the repository root.
Spaces in paths cause issues with shell scripts, CI/CD, and Xcode Cloud's
project discovery. Lesson learned from Bsky Dreams where
`BskyDreams-iOS/Bsky Dreams/Bsky Dreams.xcodeproj` (two levels deep, spaces)
caused persistent "Project does not exist at root" errors.

**Alternatives considered**: Subdirectory with Xcode Cloud custom workspace
path — fragile, undocumented, breaks on Xcode updates.

**Trade-offs**: Web and iOS files share the same root directory. Use
`.gitignore` to keep build artifacts out of the web deployment.

---

## Decision 003 — Shared Version Config (xcconfig)
*Date: 2026-04-03*

**Decision**: `AppVersion.xcconfig` at repo root defines
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. All targets reference it.

**Rationale**: Editing version numbers via Xcode's identity panel creates
per-target overrides in `project.pbxproj` that shadow the xcconfig, causing
targets to drift. A single xcconfig is the single source of truth.

**Trade-offs**: Must remember to edit the xcconfig, not the Xcode UI.

---

## Decision 004 — SwiftUI + @Observable + SwiftData (iOS)
*Date: 2026-04-03*

**Decision**: SwiftUI for all UI. `@Observable` (iOS 17 macro) for state
management. SwiftData for local persistence. UIKit only where SwiftUI lacks
a native equivalent.

**Rationale**: Modern Apple stack, minimal boilerplate, no third-party
dependencies.

**Trade-offs**: iOS 17+ minimum deployment target.

---

## Decision 005 — Dual-Platform Feature Parity Model
*Date: 2026-04-03*

**Decision**: Both platforms implement the same core feature set. Track
parity in SCRATCHPAD.md. Platform-specific implementation choices are
acceptable (e.g., Keychain vs localStorage for auth).

**Rationale**: Users expect the same capabilities regardless of platform.
Implementation details can differ to leverage each platform's strengths.

**Trade-offs**: Every feature is effectively built twice. Mitigated by
shared API contracts and design tokens.

---

## Decision 006 — App Name and Brand Identity
*Date: 2026-04-03*

**Display name:** BOBA Playbook. **GitHub repo:** BOBA-Playbook. **Xcode product name:** BOBAPlaybook (hyphens not valid in Xcode product names).
**Design language:** Retro-futurism + cyberpunk UI + glassmorphism.
**Palette:** battle orange (#FF4D00), cyber cyan (#00F5FF), deep violet (#8B00FF) on near-black (#080810) with frosted glass panels.
**Card art is always the focal point** — UI chrome frames it, never competes with it. Power numbers and element colors are large and immediately legible. Opinionated aesthetic that draws users in, matching the energy of the BOBA cards themselves.

---

## Decision 007 — Supabase for Auth and User Data (Not Images)
*Date: 2026-04-03*

Supabase free tier handles: auth, `user_cards` (collection tracker), `decks`, `deck_cards`.
Static card catalog (`cards.json`, GitHub Pages) handles all browsing — no DB query needed.
**Supabase Storage is NOT used.** The free tier (1 GB storage, 2 GB/month bandwidth) would exhaust in hours for a card image app. Images are hosted on Cloudflare R2 exclusively.

---

## Decision 008 — Cloudflare R2 for Image CDN
*Date: 2026-04-03*

10,751 card images on R2 bucket `boba-card-images`. R2 chosen for: 10 GB free storage, **zero egress fees**, Cloudflare edge caching globally.
Two image tiers:
- `thumbs/` — 200px wide WebP, ~10 KB avg → card grids/lists
- `full/`   — ≤1200px WebP, ~80 KB avg → card detail views

`CDN_BASE` env var holds the public bucket URL. **Never hardcode R2 URLs.** Always use CDN helper functions (`thumbUrl(f)`, `fullUrl(f)`).

---

## Decision 009 — Static Card Catalog JSON (Pre-Generated)
*Date: 2026-04-03*

`cards.json` (13 MB, 17,793 cards) is committed to `assets/data/` and served from GitHub Pages. No database query needed for catalog browsing.
`cards-slim.json` (8.7 MB, no `searchTokens`) is the iOS bundle version.
SwiftData caches the catalog on-device after first load.
To update when new sets release: re-run `reconcile_all.py` in the Research folder, then copy the four JSON files from `unified-cards/data/` to `assets/data/` and commit.
Full schema: `docs/CARD_SCHEMA.md`.

---

## Decision 010 — Element Color System
*Date: 2026-04-03*

Each BOBA element maps to a canonical UI color used consistently throughout the app (backgrounds, borders, badges, glows):
```
FIRE  → #FF4D00  ICE   → #00BFFF  HEX   → #8B00FF
STEEL → #8A9BB0  BRAWL → #C0392B  GLOW  → #FFD700
GUM   → #FF69B4  SUPER → #FF00FF  NONE  → #666680
```
Elements in `cards.json` are always UPPERCASE (normalized by `reconcile_all.py`). The element color is the primary visual differentiator on card components.

---

## Decision 011 — No Images in GitHub Repo
*Date: 2026-04-03*

The repo contains only code and JSON data files. Card images are never committed to git — they live exclusively on Cloudflare R2.
`assets/data/` contains the four JSON files. `assets/images/` does NOT exist.
This keeps clone time fast and avoids GitHub's soft 1 GB storage limit.

---

## Decision 012 — Scan Mode: On-Device Vision Only
*Date: 2026-04-03*

Card identification in Scan Mode uses iOS `Vision` (`VNRecognizeTextRequest`) and `AVFoundation` only. **No image is uploaded to any server.** All processing is on-device.
Match pipeline: OCR text from camera frame → regex for card number pattern → look up in `cards.json` → display result.
Card number regex: `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)` (covers BF-208, T-16/50, BLBF-644, etc.)
Confidence threshold: require card number match OR (hero name + power value both agree).
Fall back to manual search if confidence < 0.7.
Multi-card mode maintains a scan queue in `ScanStore` with running value tally.

---

## Decision 014 — iOS Card Catalog: Two-Phase Progressive Loading
*Date: 2026-04-03*

**Decision**: The iOS card catalog loads in two phases. Phase 1 is synchronous inside `CardStore.init()`: decode `cards-head.json` (500 cards, ~192KB) directly, so 500 cards are available before SwiftUI renders frame 1. Phase 2 runs in `Task.detached(priority: .background)`: decode `display-cards.json` (~12k cards, 4.7MB) without competing with UI work.

**Rationale**: Initial approach used `PropertyListEncoder` to cache decoded cards — this caused a 30-45 second blocking encode on first launch. Removing the cache and running full JSON decode in `.background` priority Task.detached eliminates the bottleneck. Synchronous Phase 1 in `init()` (not an async Task) ensures cards are ready before the first render pass, achieving <50ms time-to-first-card.

**Data files**:
- `BOBAPlaybook/cards-head.json` — first 500 cards, ~192KB, generated from display-cards.json head
- `BOBAPlaybook/display-cards.json` — full deduplicated catalog, ~4.7MB, 11,991 cards

**Trade-offs**: No persistent JSON cache between launches; file is re-decoded every launch. Full decode takes 1-3 seconds on device at `.background` priority, which is imperceptible since 500 cards are already showing. `cards-slim.json` deprecated and removed.

---

## Decision 015 — imageAvailable Flag Bypass
*Date: 2026-04-03*

**Decision**: On both platforms, the `imageAvailable` boolean field is NOT used to gate image loading. Instead, any card with a non-null, non-empty `imageFile` will always attempt to load its CDN image. Placeholder is only shown when `imageFile` is null (no image path exists) or on CDN load failure.

**Rationale**: The `imageAvailable` flag in the JSON source data had false negatives — some cards had `imageAvailable: false` but a valid `imageFile` pointing to real CDN images. Bypassing the flag and trusting the CDN (which returns 404 for missing images, gracefully falling back to placeholder) is more accurate.

**Affected files**: `BOBAPlaybook/Components/CardImageView.swift`, `js/app.js` (`buildCardElement`)

---

## Decision 016 — Tab/Section Named "Play" Not "Rules"
*Date: 2026-04-03*

**Decision**: The rules/strategy/deck-builder section is named **Play** (not "Rules & Strategy" or "Book") on both platforms. Icon: `bolt.square.fill` (SF Symbols on iOS; custom SVG on web).

**Rationale**: "Rules" implies constraint. "Play" conveys the purpose — how to play the game, strategy, and deck building. The bolt-square icon evokes the battle/energy feel of BOBA without being sport-specific.

---

## Decision 017 — Web Filter Panel: Mobile Collapsible, Desktop Persistent
*Date: 2026-04-03*

**Decision**: On mobile (<768px), the search filter panel is hidden by default behind a toggle button in the search bar row. Tapping the button slides the panel down with a max-height transition. The panel lives *outside* the sticky `search-header` so it scrolls with page content when open. A badge on the toggle button shows active filter count. On desktop (≥768px), the filter panel is always visible, no toggle needed.

**Rationale**: On mobile, the filter bar consumed significant vertical space on every page load, burying card results before the user has seen them. The iOS app uses a bottom sheet — the web equivalent is a collapsible panel. Desktop users have screen real estate to keep filters visible.

---

## Decision 018 — PWA GitHub Pages 404 Handling
*Date: 2026-04-03*

**Decision**: A `404.html` file at the repo root redirects any unresolvable GitHub Pages URL back to `/BOBA-Playbook/`, preserving query string. The `manifest.json` includes an explicit `"scope": "/BOBA-Playbook/"` field.

**Rationale**: GitHub Pages project sites serve from a subdirectory path. Without a 404 handler, any URL that doesn't map to a real file (e.g. a PWA homescreen launch resolving to an unexpected path) shows GitHub's own 404 page. The redirect catches all such cases. The `scope` field ensures iOS Safari's PWA handling stays within the correct path boundary.

---

## Decision 019 — App Icon: XOXO Playbook Mark
*Date: 2026-04-03*

**Decision**: The app icon is an XOXO pattern (X, O, O, X in a 2×2 grid) in BOBA orange (#FF4D00) on near-black (#000000). Files in `Logos/` folder; deployed to `BOBAPlaybook/Assets.xcassets/AppIcon.appiconset/` (1024px, Xcode generates all sizes) and `assets/icons/` (SVG, 60px, 180px, 512px for web).

**Rationale**: The XOXO mark is immediately legible at small sizes, brand-distinctive (orange on black), and evokes strategy/playbook thinking (X's and O's = play diagrams) while being abstract enough to not be tied to a single sport.

---

## Decision 013 — Pricing Comps Strategy
*Date: 2026-04-03*

Pricing data is fetched live at card-detail view time (not pre-cached in cards.json):
- **Radish Price Guide** (`radishpriceguide.com`) — BOBA-specific pricing, primary source
- **eBay sold listings** — secondary source, searched by card number

Pricing calls are made via a lightweight proxy or directly from the client if CORS allows.
Prices are NOT stored in Supabase — they are live lookups only.
The Collection Mode value dashboard uses last-fetched prices cached in `user_cards.estimated_value` with `user_cards.last_price_check` timestamp.
Box lookups (Hobby, Double Mega, Jumbo) use eBay sold listings searched by product name.
