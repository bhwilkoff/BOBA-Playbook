# BOBA Playbook — Architecture & Technology Decisions

Entries ordered by number. Append new decisions; do not remove old ones.

---

## 001 — Vanilla HTML/CSS/JS for Web
*2026-04-03*
No framework, no build step. GitHub Pages serves static files directly. Framework abstractions cost more than they save at this scale. Revisit if component count exceeds ~20.

## 002 — Xcode Project at Repository Root
*2026-04-03*
`.xcodeproj` lives at repo root, no subdirectory, no spaces in project name. Required for Xcode Cloud auto-discovery. Lesson learned from Bsky Dreams where a nested path caused persistent "Project does not exist at root" errors.

## 003 — Shared Version Config (xcconfig)
*2026-04-03*
`AppVersion.xcconfig` defines `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. All targets reference it. Editing via Xcode's identity panel creates per-target overrides that cause drift. Always edit the xcconfig file directly.

## 004 — SwiftUI + @Observable + SwiftData (iOS)
*2026-04-03*
SwiftUI for all UI. `@Observable` (iOS 17 macro) for state. SwiftData for local persistence. UIKit only where SwiftUI lacks a native equivalent. Requires iOS 17+ minimum deployment target.

## 005 — Dual-Platform Feature Parity Model
*2026-04-03*
Both platforms implement the same core feature set. Platform-specific implementation is acceptable. Track status in SCRATCHPAD.md. Every feature is effectively built twice — mitigated by shared API contracts and design tokens.

## 006 — App Name and Brand Identity
*2026-04-03*
Display name: BOBA Playbook. Xcode product: BOBAPlaybook (no hyphens). Design language: Retro-futurism + cyberpunk + glassmorphism. Palette: battle orange (#FF4D00), cyber cyan (#00F5FF), deep violet (#8B00FF) on near-black (#080810). Card art is always the focal point — UI chrome frames it, never competes.

## 007 — Supabase for Auth and User Data Only
*2026-04-03*
Supabase handles: auth, `user_cards`, `decks`, `deck_cards`. Card catalog browsing uses static JSON only — no DB query needed. **Supabase Storage is NOT used** — the free tier (1 GB, 2 GB/mo bandwidth) would exhaust quickly for a card image app.

## 008 — Cloudflare R2 for Image CDN
*2026-04-03*
10,751 card images on R2 bucket `boba-card-images`. Chosen for zero egress fees and Cloudflare edge caching. Two tiers: `thumbs/` (200px WebP, ~10KB) for grids; `full/` (≤1200px WebP, ~80KB) for detail views. CDN_BASE env var holds the bucket URL. **Never hardcode R2 URLs** — always use CDN helpers.

## 009 — Static Card Catalog JSON
*2026-04-03*
`cards.json` (13MB, 17,793 cards) committed to `assets/data/` and served from GitHub Pages. No database query for catalog browsing. To update for new sets: re-run `reconcile_all.py`, copy output JSONs to `assets/data/`, commit.

## 010 — Element Color System
*2026-04-03*
Each element maps to a canonical UI color used throughout (backgrounds, borders, badges, glows): FIRE #FF4D00, ICE #00BFFF, HEX #8B00FF, STEEL #8A9BB0, BRAWL #C0392B, GLOW #FFD700, GUM #FF69B4, SUPER #FF00FF, NONE #666680. Elements in cards.json are always UPPERCASE.

## 011 — No Card Images in Git
*2026-04-03*
Card images are never committed to the repo — they live exclusively on Cloudflare R2. `assets/data/` contains only JSON files. Keeps clone fast and avoids GitHub's soft 1 GB storage limit.

## 012 — Scan Mode: On-Device Vision Only
*2026-04-03*
Card identification uses iOS Vision (`VNRecognizeTextRequest`) and AVFoundation only. No image is uploaded to any server. Pipeline: OCR frame → card number regex `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)` → match display-cards.json. Confidence ≥ 0.7 on card number, OR hero name + power must both agree. Falls back to manual search.

## 013 — Pricing Comps Strategy
*2026-04-03*
Pricing fetched live at card-detail view time (not pre-cached). Primary: Radish Price Guide (`radishpriceguide.com`). Secondary: eBay sold listings by card number. Prices not stored in Supabase — live lookups only. Collection value dashboard caches last-fetched price in `user_cards.estimated_value`.

## 014 — iOS Card Catalog: Two-Phase Progressive Loading
*2026-04-03*
Phase 1: synchronous in `CardStore.init()` — decode `cards-head.json` (500 cards, ~192KB) so cards are available before SwiftUI frame 1 (<50ms). Phase 2: `Task.detached(priority: .background)` — decode `display-cards.json` (~12k cards, 4.7MB). Previous approach used `PropertyListEncoder` cache — this caused 30–45s blocking encode on first launch. No persistent cache between launches; re-decoded every launch at background priority.

## 015 — imageAvailable Flag Bypass
*2026-04-03*
`imageAvailable` boolean is NOT used to gate image loading on either platform. Any card with a non-empty `imageFile` always attempts CDN load. Placeholder shows only when `imageFile` is null or CDN returns 404. The flag had false negatives — some cards had `imageAvailable: false` but valid CDN images.

## 016 — Section Named "Play" Not "Rules"
*2026-04-03*
The rules/strategy/deck-builder section is named **Play** on both platforms. Icon: `bolt.square.fill` (iOS) / custom SVG (web). "Rules" implies constraint; "Play" conveys purpose.

## 017 — Web Filter Panel: Mobile Collapsible, Desktop Persistent
*2026-04-03*
Mobile (<768px): filter panel hidden by default, toggled by a button with an active-count badge. Panel lives outside the sticky header so it scrolls with content when open. Desktop (≥768px): always visible. Mirrors iOS bottom sheet pattern.

## 018 — PWA GitHub Pages 404 Handling
*2026-04-03*
`404.html` at repo root redirects unresolvable URLs back to `/`, preserving query string. `manifest.json` has explicit `"scope": "/"`. Without this, PWA homescreen launches hit GitHub's own 404 page.

## 019 — App Icon: XOXO Playbook Mark
*2026-04-03*
XOXO pattern (X, O, O, X in 2×2 grid) in BOBA orange (#FF4D00) on near-black. Legible at small sizes, brand-distinctive, evokes strategy/playbook thinking (X's and O's = play diagrams).

## 020 — Web Layout: Body Flex Column, No viewport-fit=cover
*2026-04-04*
`body { height: 100dvh; display: flex; flex-direction: column; overflow: hidden }` with `main { flex: 1; overflow-y: auto; min-height: 0 }`. The body does not scroll — content scrolls inside `main`. The mobile header is the first flex item (`flex-shrink: 0; position: relative`).

**Rationale**: `position: fixed` headers are placed in a separate GPU compositor layer that Safari browser-mode misorders during address-bar show/hide transitions, causing content to bleed into the Dynamic Island. The body flex-column approach (copied from the Bsky Dreams reference implementation) keeps the header in document flow and delegates scrolling to `main`, so the browser's safe area is never breached.

**Consequences**: `viewport-fit=cover` removed from meta viewport (browser manages safe area automatically). No `env(safe-area-inset-top)` usage. IntersectionObserver for infinite scroll must use `root: document.getElementById('main-content')` since `main` — not the window — is the scroll container. No `position: fixed` overlays on `body` (e.g. the scanline `body::after` was removed).
