# BOBA Playbook — Claude Code Project Context

## Why We Build

Every feature is built in service of human learning and growth — not to replace thinking, but to deepen it. Ask at each decision point: Does this invite the user to engage more fully, think more critically, or connect more meaningfully? The goal is never a slick product — it is a tool that makes someone more human.

---

## Project Mantra: One Image per Card. One ID per Card.

Every unique card gets exactly one canonical identifier (`bobaId`) and
exactly one canonical image (`imageFile`). No two cards share either.
All scripts, tools, lookups, corrections, and UIs disambiguate by
`bobaId` whenever possible — it is the primary key for the card catalog.

**`bobaId` formula** (v2, 4-field, lives in `scripts/boba_id.py` — do
not redefine inline anywhere):
```python
bobaId = f"{cardNumber}-{hero or name}-{treatment or ''}-{variation or ''}"
```
Sealed Products fall back to `name` when `hero` is absent. Trailing
dashes are intentional and stable. Verified 17,739 unique bobaIds
across 17,739 cards (zero collisions).

`bobaId` is stored as a real field in every JSON bundle (master
`unified-cards/data/cards.json` plus the 6 downstream bundles in
`assets/data/` and `BOBAPlaybook/`). Read the field — do not recompute
it at runtime unless the field is missing.

The Supabase `card_corrections` and `card_image_overrides` tables carry
a `boba_id` column and any new row written from either iOS or web MUST
populate it. See `COWORK.md` for the full correction sync protocol
between Claude Code and Cowork.

---

## Debugging Philosophy

**Do not iterate blindly on behavior you cannot observe.** When the root cause is unclear, instrument first — don't guess.

1. Add console diagnostics before trying another implementation
2. Design diagnostics to answer a specific question
3. Isolate layers independently before changing any
4. For iOS interaction bugs, add a temporary visual overlay when the user can't share a console
5. Remove all diagnostics before closing a fix

---

## What This App Does

**Display name:** BOBA Playbook | **Repo:** BOBA-Playbook | **Xcode:** BOBAPlaybook
**Tagline:** "Search. Scan. Collect. Play."

Companion app for the Bo Jackson Battle Arena (BOBA) trading card game:
1. **Search** — Browse, search, filter 17,739 cards with images
2. **Scan** — iOS camera identifies cards on-device via Vision OCR
3. **Play** — Rules, per-card strategy, deck builder
4. **Collection** — Portfolio tracker with designations, synced via Supabase

Available as both a **web app** (GitHub Pages) and **native iOS app**. Maintain feature parity — when adding to one platform, note the other in SCRATCHPAD.md.

---

## Web App

### Tech Stack
- Vanilla HTML/JS — no framework, no build step
- Custom CSS (mobile-first, CSS custom properties)
- Supabase (auth + user data) via `js/api.js`; card catalog from static JSON
- GitHub Pages static hosting (branch: main, root: /)

### Key Directories
- `/css/styles.css` — single main stylesheet
- `/js/app.js`, `js/api.js`, `js/auth.js`, `js/collection.js`
- `/assets/data/` — cards.json, categories.json, search-index.json
- `/docs/` — CARD_SCHEMA.md and other reference docs

### Run Locally
```
python3 -m http.server 8080  # visit http://localhost:8080
```
Deploy: push to `main` — GitHub Pages serves automatically.

### Web Conventions
- All API calls through `js/api.js` — never `fetch` directly from other files
- CSS custom properties defined in `:root` in `styles.css`
- Mobile-first: all media queries use `min-width` breakpoints
- No inline styles — all styling via CSS classes
- Error states must be user-visible (not just console logs)
- Navigation: all nav items live inside `#channels-sidebar`
- View system: use `showView(name)` to switch views; each view is a `<section>` with `hidden` toggled
- **IntersectionObserver**: must pass `root: document.getElementById('main-content')` since `main` is the scroll container. Disconnect on view leave to prevent memory leaks.

### Web Layout — Safari Mobile (Critical)
The body is a **fixed-height flex column** — this is the only reliable way to prevent content from bleeding into the Dynamic Island in Safari browser mode.

```css
body   { height: 100dvh; display: flex; flex-direction: column; overflow: hidden; }
main   { flex: 1; overflow-y: auto; min-height: 0; overscroll-behavior: none; }
header { flex-shrink: 0; position: relative; }
```

- **No `viewport-fit=cover`** in the meta viewport tag. Without it, Safari automatically clips content to the safe area — no `env(safe-area-inset-top)` handling needed.
- **No `position: fixed`** on the mobile header. It stays pinned at top naturally as the first flex item.
- **No `body::after { position: fixed }`** overlays — these can break Safari's compositor layering.
- Reference implementation: `github.com/bhwilkoff/Bsky-Dreams`

### Web Constraints
- GitHub Pages static only — no server runtime, no Node.js
- Zero-cost tools only
- No build pipeline — plain HTML/CSS/JS

---

## iOS App

### Tech Stack
- Swift 6, SwiftUI (`@Observable`, iOS 17+)
- SwiftData for local persistence
- Keychain via Security framework for auth storage
- URLSession directly to Supabase REST API (no third-party packages)
- Fonts: Bebas Neue / Russo One (display), Chakra Petch (mono/body)

### Project Structure
```
/
├── BOBAPlaybook.xcodeproj/   ← at repo root (Xcode Cloud requirement)
├── BOBAPlaybook/
│   ├── App/                  ← entry point
│   ├── Models/               ← Card, UserCard, Deck
│   ├── Views/                ← SwiftUI views per feature
│   ├── Components/           ← reusable UI
│   ├── Networking/           ← Supabase client + CDN helpers
│   ├── Store/                ← @Observable AppStore, ScanStore
│   └── Resources/Fonts/
├── AppVersion.xcconfig       ← MARKETING_VERSION + CURRENT_PROJECT_VERSION
├── assets/data/              ← shared card catalog JSONs
```

### iOS Conventions
- All API calls through a shared client singleton — never URLSession directly from views
- Auth state owned by one manager — views read via `@Environment`
- Global nav state in `@Observable` store with `NavigationPath`
- All views use `.toolbarBackground(.regularMaterial, for: .navigationBar)` + `.toolbarBackground(.visible, for: .navigationBar)`
- **Sidebar header**: use `VStack` with `.background()` modifier — never `ZStack` with a `Color` sibling
- **fullScreenCover with data**: use `fullScreenCover(item:)` with an `Identifiable` carrier struct
- **Image grid cells**: constrain both width AND height before `.clipped()`
- **URLCache**: configure at launch — 100 MB memory / 500 MB disk
- **Version numbers**: edit `AppVersion.xcconfig`, never the Xcode identity panel

### iOS Constraints
- iOS 17+ minimum deployment target
- No third-party Swift packages — Apple frameworks only
- Keychain for all credential storage — never UserDefaults for secrets

---

## Shared Design System

**Design language:** Retro-futurism + Cyberpunk + Glassmorphism. Card art is always the focal point — UI chrome frames it, never competes. Bold, legible stats at a glance.

**Core tokens** (defined in `styles.css` `:root` and `BOBAPlaybook/Design.swift`):
- `--boba-orange: #FF4D00` — primary CTA, FIRE element
- `--boba-cyan: #00F5FF` — links, highlights, active states
- `--boba-violet: #8B00FF` — HEX element, secondary accents
- `--boba-near-black: #080810` — page background
- `--boba-surface: #0D0D1A` — card/panel surface
- Element colors: FIRE #FF4D00, ICE #00BFFF, HEX #8B00FF, STEEL #8A9BB0, BRAWL #C0392B, GLOW #FFD700, GUM #FF69B4, SUPER #FF00FF, NONE #666680

---

## Data Architecture

### Card Catalog (Static JSON)
- **Web:** `assets/data/cards.json` — 17,739 cards
- **iOS:** `BOBAPlaybook/display-cards.json` (~12k cards, 4.7MB) + `cards-head.json` (first 500, ~192KB for instant first frame)
- **Filter data:** `assets/data/categories.json`
- **Search index:** `assets/data/search-index.json`
- Full schema: `docs/CARD_SCHEMA.md`

### Image CDN (Cloudflare R2)
**CDN_BASE:** `https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev`
- Thumbnail: `{CDN_BASE}/thumbs/{imageFile}` — 200px WebP ~10KB — use in grids
- Full: `{CDN_BASE}/full/{imageFile}` — ≤1200px WebP ~80KB — use in detail
- **Never hardcode R2 URLs.** Use CDN helpers: `thumbUrl(f)` / `fullUrl(f)` (web: `js/api.js`; iOS: `CDN.swift`)
- Load any card with a non-empty `imageFile` regardless of `imageAvailable` flag

### Backend (Supabase — Auth & User Data Only)
- Tables: `user_cards`, `decks`, `deck_cards` — see `supabase_schema.sql`
- **Supabase Storage NOT used** — images are on R2 only
- 17,739 total cards · 14,701 images on R2 · **82.9% coverage**

---

## Navigation

**iOS tabs:** Find · Learn · Decks · Collection · Purchase
- **Find** — card search (formerly "Search"). Scan shortcut lives inside the search bar (right edge). Profile opens as a sheet from a toolbar icon (left of the BOBA wordmark). Default landing tab; rendered larger than the others to signal that.
- **Learn** — rules, strategy, browse-by-athlete lists, collecting guide, tournament reference. Sub-sections: Setup (match flow + edge cases) · Rules · Strategy · Browse · Collect · Glossary · Tournament.
- **Decks** — deck builder.
- **Collection** — owned cards + Rainbow + Shows (streamer-only).
- **Purchase** — Upcoming Breaks (Whatnot feed) + Find a Store.

**Web sidebar:** Learn · Decks · Find · Collection · Purchase · Profile.

**iOS app display name:** `CFBundleDisplayName = "Playbook"` (under the icon on the home screen). In-app wordmark + App Store listing still read "BOBA Playbook." See DECISIONS.md #032.

---

## Card Taxonomy (User-Facing)

**Treatments vs Parallels** — distinct concepts per the BoBA-expert audit (see DECISIONS.md #028). Treatments are print variants of a single card (Base Set, Battlefoil family with seven color subsets, themed foils, Inspired Ink = Serialized variants, Superfoil). Parallels are entirely separate runs (Billy Cameo Alt Arts, SideKicks, Plays, Bonus Plays, Prize/Promos, Hot Dogs).

**Inspired Ink = Serialized** with weapon-tied print numbers: Hex /5, Glow /10, Fire /25, Ice /50.

**User-facing language** (DECISIONS.md #027):
- The catalog field is `element` → render as **Weapon** in UI
- The catalog field is `treatment` → render as **Treatment** in UI (not "Rarity")
- "Rarity" is reserved for the *rarity-by-weapon-type* discussion in the Learn → Collect → Weapon Rarity section. Nowhere else.

**Card-detail canonical layout** (DECISIONS.md #029): every card-detail surface uses the same 6-cell 2-col grid:
```
Card #     │ Type
Treatment  │ Weapon
Set        │ Sub-set
```
Cost + DBS for Plays render BELOW the canonical six.

---

## Scan Mode (iOS Only)
- `AVFoundation` for camera feed, `Vision` for OCR (`VNRecognizeTextRequest`)
- Pipeline: frame → OCR → card number regex → match `display-cards.json` → show result
- Card number regex: `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)`
- Match if card number confidence ≥ 0.7, OR hero name + power both agree
- **All processing on-device. No image uploaded.**
- Multi-card: scan queue in `@Observable ScanStore`, running value tally

---

## Key Files

| File | Purpose |
|---|---|
| `assets/data/cards.json` | Full card catalog (web) |
| `assets/data/categories.json` | Filter dropdown data |
| `assets/data/search-index.json` | Pre-built search indexes |
| `BOBAPlaybook/display-cards.json` | Full catalog for iOS |
| `BOBAPlaybook/cards-head.json` | First 500 cards for instant iOS load |
| `supabase_schema.sql` | Supabase table definitions |
| `docs/CARD_SCHEMA.md` | Full cards.json field documentation |
| `workers/ebay-proxy/worker.js` | Cloudflare Worker: eBay Browse API + Radish pricing proxy (deployed: boba-ebay-proxy.benwilkoff.workers.dev) |
| `DECISIONS.md` | Architecture decision log |
| `DESIGN.md` | iOS design theory — binding rules for every iOS UI feature |
| `WEB-DESIGN.md` | Web design theory — binding rules for every web UI feature |
| `TRADE-DESIGN.md` | P2P trading design — binding rules for matching, messaging, payment guidance, fraud prevention, dispute flow |
| `SCRATCHPAD.md` | Feature parity tracker and milestone status |
| `docs/HERO_SHOT_ARCHITECTURE.md` | Hero Shot 3D card-video feature — architecture, iteration journal, and how to use the sim for self-validation |
| `tools/HeroShotSim/sim3d.swift` | macOS RealityFoundation sim mirroring the iOS Hero Shot scene — render PNG contact sheets to validate visual changes before shipping |

---

## Standing Instructions

**Learning Orientation:** Before implementing any feature, ask:
1. Does it deepen understanding? (active engagement, not passive delivery)
2. Does it invite participation?
3. Does it support human agency — more capable, not more dependent?
4. Clarity over cleverness — simpler always wins
5. Accessible by default — WCAG AA from line one
6. Mobile-first — test at 375px before 1440px

**Autonomous guidelines:**
- When uncertain between approaches, document in DECISIONS.md and choose simpler
- Fix only the bug — don't refactor surrounding code
- No feature additions beyond what's requested
- **Feature gating**: when a feature is hidden (Discord FAB, etc.), keep all implementation code intact — gate only at the single UI entry point (see DECISIONS.md #025)

---

## Available Claude Skills

- **UI/UX:** `KUI:system/brand/screen/review/code/a11y/darkmode`, `ui-ux-pro-max`, `frontend-design`
- **iOS:** `all-ios-skills:<name>` — swiftui-patterns, swiftui-navigation, swiftui-animation, swiftui-performance, swiftdata, ios-networking, ios-security, vision-framework, photos-camera-media, storekit, swift-charts, swift-concurrency, swift-testing, debugging-instruments, app-store-review, codable-patterns
- **3D / RealityKit:** `realitykit-3d-card-rendering`, `3d-feature-sim-validation`, `3d-feature-debug-loop` — patterns + methodology for offline-sim-validated iteration on 3D card features. Read `docs/HERO_SHOT_ARCHITECTURE.md` for the BOBA-specific context.
- **Workflow / discipline:**
  - `binding-design-doc-discipline` — invoke before proposing any UI work; quote the rule from DESIGN.md / WEB-DESIGN.md / TRADE-DESIGN.md that justifies the change.
  - `architectural-decision-log` — invoke when about to write a DECISIONS.md entry, or auditing one.
  - `feature-shipping-discipline` — the end-to-end 7-step ship sequence (read docs → propose with rule quote → build → validate → bump version → commit with user-quote → push on authorization).
- **Design principles:**
  - `learning-orientation-design` — invoke before proposing any new feature; the four-question test (deepens understanding? invites participation? supports agency? clarity over cleverness?).
  - `mobile-first-density-design` — invoke when designing any UI surface; density rules from DESIGN.md §4 / WEB-DESIGN.md §5.
  - `native-platform-first` — invoke before reaching for custom UI; exhaust native iOS / web APIs first.
  - `universal-feature-states` — invoke when designing any list / grid / feed / sheet; loading + empty + error + offline must be defined.
- **Assets:** `app-store-screenshots`
- **Quality:** `simplify`, `claude-api`

---

## Current State
See @SCRATCHPAD.md for milestone status. See @DECISIONS.md for architecture decisions. **For any UI / IA work, consult @DESIGN.md (iOS) or @WEB-DESIGN.md (web) before proposing — both are binding.** **For any P2P trading / matching / messaging / payment-guidance work, consult @TRADE-DESIGN.md — binding.**
