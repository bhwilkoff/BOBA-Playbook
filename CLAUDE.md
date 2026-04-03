# BOBA Playbook — Claude Code Project Context

## A Note on Why We Build

Before writing a single line of code, take a moment to understand the
orientation of this work. Every feature in this app is built in service of
human learning and growth — not to replace thinking, but to deepen it. At
each decision point, ask: Does this design invite the user to engage more
fully, think more critically, or connect more meaningfully? If a feature
makes a person more passive, reconsider it. If it opens a door to curiosity
or collaboration, prioritize it. The goal is never a slick product — it is a
tool that makes someone more human.

---

## Debugging and Diagnostic Philosophy

**Do not iterate blindly on behavior you cannot observe.** When a feature
does not work correctly and the root cause is not immediately clear from
reading the code, the first move is always diagnostics — not another
implementation attempt.

### Rule: Instrument before iterating

1. **Add console diagnostics immediately.** One round of real data is worth
   more than ten rounds of guessing.
2. **Design diagnostics to answer a specific question.** Write down what you
   expect to see vs. what would indicate the bug.
3. **Isolate layers.** Verify each layer independently before changing any.
4. **For iOS interaction bugs, add a temporary visual overlay** when the user
   cannot easily share a console.
5. **Remove all diagnostics before considering a fix complete.**

---

## What This App Does

**Display name:** BOBA Playbook
**GitHub repo:** BOBA-Playbook · **Xcode product name:** BOBAPlaybook
**Tagline:** "Search. Scan. Collect. Play."

BOBA Playbook is the definitive companion app for the **Bo Jackson Battle Arena (BOBA)** trading card game. Features:

1. **Search Mode** — Browse, search, and filter all 17,793 BOBA cards with images and pricing comps
2. **Scan Mode** — iOS camera identifies cards on-device in real-time using Vision framework
3. **Book Mode** — Rules, per-card strategy tips, and deck builder using your collection
4. **Collection Mode** — Portfolio tracker with designations, value dashboard, synced via Supabase

This app is available as both a **web app** and a **native iOS app**. The two
platforms are developed separately but maintain **feature parity** as a goal.
When adding a feature to one platform, note in SCRATCHPAD.md whether the
equivalent work is needed on the other.

---

## Platforms

### Feature Parity Model

Both platforms implement the same core feature set. Platform-specific
implementation choices are acceptable and expected. What should stay in sync:

- Which views/features exist
- Core UX flows
- Design language and color tokens
- API usage patterns

---

## Web App

### Tech Stack

- **Rendering:** Vanilla HTML/JS — no framework, no build step required
- **Styling:** Custom CSS (mobile-first, CSS custom properties for theming)
- **API:** Supabase (auth + user data) via `js/api.js`; card catalog from static JSON
- **Auth:** Supabase email/password + magic link
- **Deployment:** GitHub Pages static hosting (branch: main, root: /)

### Key Directories

- `/` — Root: index.html, CLAUDE.md, SCRATCHPAD.md, DECISIONS.md
- `/css/` — Stylesheets (styles.css is the single main stylesheet)
- `/js/` — JavaScript modules (app.js, api.js)
- `/assets/` — Static assets (icons, images, data JSONs)
- `/assets/data/` — Card catalog JSON files (cards.json, categories.json, search-index.json)
- `/docs/` — Reference documentation (CARD_SCHEMA.md, etc.)

### How to Run Locally

```
open index.html
# or
python3 -m http.server 8080  # then visit http://localhost:8080
```

### How to Deploy

1. Push changes to `main` branch
2. GitHub Pages serves from root of `main` automatically
3. Live URL: https://bhwilkoff.github.io/BOBA-Playbook/

### Web Conventions

- All API calls go through `js/api.js` — never call `fetch` directly from other files
- Auth state is managed exclusively in a single module
- CSS custom properties (variables) are defined in `:root` in `styles.css`
- Mobile-first: all media queries use `min-width` breakpoints
- Semantic HTML throughout — use `<article>`, `<section>`, `<nav>`, `<button>`
- No inline styles — all styling via CSS classes
- Error states must be user-visible (not just console logs)
- **Navigation**: All nav items live inside `#channels-sidebar`
- **IntersectionObserver cleanup**: Any `IntersectionObserver` created for a
  view must be disconnected when leaving that view to prevent memory leaks
- **View system**: Use `showView(name)` to switch between views; each view is
  a `<section>` with `hidden` attribute toggled

### Web Constraints

- GitHub Pages static deployment only — no server runtime, no Node.js
- Zero-cost tools only — no paid APIs, no paid hosting
- No build pipeline — everything must work as plain HTML/CSS/JS

### Do Not Touch (Web)

- `.git/` directory
- GitHub Pages deployment settings

---

## iOS App

### Tech Stack

- **Language / UI:** Swift 6, SwiftUI (`@Observable`, iOS 17+)
- **Local persistence:** SwiftData
- **Auth storage:** Keychain via Security framework
- **API:** URLSession directly to Supabase REST API (no third-party packages); CDN enum for R2 image URLs
- **Fonts:** Syne (display), JetBrains Mono (stats/numbers), Inter (body)
- **Deployment:** Xcode build → App Store Connect → TestFlight / App Store

### Project Structure — Xcode Cloud Compatible

The `.xcodeproj` lives at the **repository root** so Xcode Cloud finds it
automatically. No subdirectory nesting, no spaces in project names.

```
/                              ← repo root
├── BOBAPlaybook.xcodeproj/    ← Xcode project at root (Xcode Cloud requirement)
├── BOBAPlaybook/              ← iOS source code
│   ├── App/                   ← Entry point, app delegate
│   ├── Models/                ← Data models (Card, UserCard, Deck)
│   ├── Views/                 ← SwiftUI views (one subfolder per feature)
│   ├── Components/            ← Reusable UI components
│   ├── Networking/            ← API client (Supabase + CDN)
│   ├── Store/                 ← @Observable global state (AppStore, ScanStore)
│   ├── Resources/Fonts/       ← Custom font files
│   ├── Assets.xcassets/       ← App icons, colors, images
│   └── Info.plist
├── AppVersion.xcconfig        ← Shared version numbers (both targets read this)
├── ci_scripts/                ← Xcode Cloud build scripts
│   └── ci_post_clone.sh
├── index.html                 ← Web app (GitHub Pages serves from root)
├── css/                       ← Web stylesheets
├── js/                        ← Web JavaScript
├── assets/                    ← Shared static assets
│   └── data/                  ← Card catalog JSON files
└── docs/                      ← Reference documentation
```

### How to Create the Xcode Project

1. Open Xcode → File → New → Project → iOS → App
2. Product Name: `BOBAPlaybook` (no hyphens — critical for Xcode Cloud)
3. Display name in Info.plist: `BOBA Playbook`
4. Organization Identifier: `com.bhwilkoff`
5. **Save location: the repository root** (not a subdirectory)
6. Interface: SwiftUI, Language: Swift, Storage: None (add SwiftData manually)
7. In project settings, add `AppVersion.xcconfig` to both Debug and Release
   configurations (Project → Info → Configurations → set config file)
8. Verify: `BOBAPlaybook.xcodeproj` should be directly in the repo root

### iOS Conventions (Learned from Production)

- All API calls go through a shared client singleton — never call `URLSession` directly from views
- Auth state owned exclusively by one manager — views read via `@Environment`
- Global navigation state lives in an `@Observable` store with `NavigationPath`
- All views use `.toolbarBackground(.regularMaterial, for: .navigationBar)` +
  `.toolbarBackground(.visible, for: .navigationBar)` to prevent content
  scrolling behind the nav bar
- **Sidebar header**: use `VStack` with `.background()` modifier — never a
  `ZStack` with a `Color` sibling (layout-greedy, expands to fill height)
- **fullScreenCover with data**: use `fullScreenCover(item:)` with an
  `Identifiable` carrier struct. Never use `fullScreenCover(isPresented:)` +
  separate `@State` arrays (SwiftUI may evaluate content before state applies)
- **Image grid cells**: always constrain both width AND height before
  `.clipped()`. `scaledToFill()` without width constraint overflows columns
- **VideoPlayer animation crash**: wrap `VideoThumbnailView` (or any view
  containing `AVPlayerViewController`) with `.transaction { $0.animation = nil }`
  to block SwiftUI animation propagation into AVKit
- **Video fullscreen**: present `AVPlayerViewController` directly via UIKit
  `present(_:animated:completion:)` — NOT via SwiftUI `fullScreenCover`.
  Create a fresh `AVPlayer` at current seek position to avoid shared-player conflicts
- **Image resize for uploads**: keep a single shared static resize function.
  Never duplicate resize logic across compose and inline-reply paths
- **Share sheet with Safari**: use `UIActivityViewController` presented via
  UIKit with a custom `UIActivity` subclass for "Open in Safari". SwiftUI's
  `ShareLink` and `.sheet`-wrapped `UIActivityViewController` both suppress
  Safari when presented from within a WKWebView context
- **URLCache**: configure at app launch with large capacity (100 MB memory /
  500 MB disk) to persist `AsyncImage` and `URLSession` responses
- **Seen posts**: use in-memory `@State` `Set<String>` cache instead of
  `@Query` to avoid ForEach cascade re-renders on every SwiftData insert
- **NSFW filtering**: add `isAdultContent` computed property on your post
  model checking labels. Apply in all feed merge steps. Keep search
  intentionally unfiltered (user controls via toggle)
- **Hybrid feeds**: when merging multiple API feeds, fetch in parallel with
  `async let`, deduplicate by URI, sort by trending score. Secondary feeds
  use `try?` so failures never break the primary source
- **Version numbers**: use `AppVersion.xcconfig` at repo root with
  `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Both targets reference
  it. Never edit versions via the Xcode identity panel (creates per-target
  overrides that cause drift)

### iOS Constraints

- iOS 17+ minimum deployment target
- No third-party Swift packages — use only Apple frameworks
- Keychain for all credential storage — never UserDefaults for secrets

---

## Shared Design System

### Design Language

**Retro-futurism + Cyberpunk UI + Glassmorphism**

Card artwork is always the focal point. UI chrome serves the art, never competes with it. Bold, legible stat numbers at a glance. Dark backgrounds with frosted glass panels and neon accents.

### Design Tokens (both platforms)

```css
/* Core colors */
--boba-orange:       #FF4D00;   /* battle orange — primary CTA, FIRE element */
--boba-cyan:         #00F5FF;   /* cyber cyan — links, highlights, active states */
--boba-violet:       #8B00FF;   /* deep violet — HEX element, secondary accents */
--boba-near-black:   #080810;   /* dark base — page backgrounds */
--boba-surface:      #0F0F1A;   /* card/panel surface */
--boba-glass:        rgba(255,255,255,0.08);
--boba-glass-border: rgba(255,255,255,0.15);

/* Element colors — always UPPERCASE in cards.json */
--element-FIRE:   #FF4D00;
--element-ICE:    #00BFFF;
--element-HEX:    #8B00FF;
--element-STEEL:  #8A9BB0;
--element-BRAWL:  #C0392B;
--element-GLOW:   #FFD700;
--element-GUM:    #FF69B4;
--element-SUPER:  #FF00FF;
--element-NONE:   #666680;

/* Typography */
--font-display: 'Syne', sans-serif;          /* hero names, card names */
--font-mono:    'JetBrains Mono', monospace; /* card numbers, power, stats */
--font-body:    'Inter', sans-serif;         /* body copy, filters */

/* Glassmorphism recipe */
background: var(--boba-glass);
backdrop-filter: blur(20px) saturate(180%);
border: 1px solid var(--boba-glass-border);
border-radius: 16px;
box-shadow: 0 8px 32px rgba(0,0,0,0.4);
```

---

## Data Architecture

### Card Catalog (Static JSON — no database query needed for browsing)

**Web:** `assets/data/cards.json` — 17,793 cards, served as static file from GitHub Pages
**iOS bundle:** `assets/data/cards-slim.json` — same cards, no `searchTokens` field (smaller)

```json
// Single card object from cards.json:
{
  "cardNumber": "BF-208",
  "bvId": 1234,
  "name": "Escape Artist",
  "hero": "Escape Artist",
  "cardType": "Hero",
  "set": "Alpha",
  "subSet": "2024 Release",
  "variation": "Battlefoils",
  "treatment": "Battlefoil",
  "element": "ICE",
  "power": 185,
  "playCost": 0,
  "playAbility": null,
  "athleteInspiration": "Daniel Norris",
  "isInspiredInk": false,
  "imageFile": "BF-208_Escape_Artist_ICE_P185.webp",
  "imageSource":null,
  "imageAvailable": true,
  "searchTokens": ["escape","artist","ice","bf","alpha","battlefoil"]
}
```

Full schema: `docs/CARD_SCHEMA.md`

**Filter data:** `assets/data/categories.json` — sets, treatments, elements, heroes with counts
**Search index:** `assets/data/search-index.json` — pre-built token/filter indexes for instant results

### Image CDN (Cloudflare R2)

**CDN_BASE:** `https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev`

```
Thumbnail:   {CDN_BASE}/thumbs/{imageFile}   ← 200px wide WebP, ~10 KB — use in grids
Full size:   {CDN_BASE}/full/{imageFile}     ← ≤1200px WebP, ~80 KB — use in detail views
```

`imageFile` is the field from each card's JSON object. If `imageAvailable` is false, show a placeholder.

**Web helpers (`js/api.js`):**
```javascript
export const thumbUrl = f => `${CDN_BASE}/thumbs/${f}`;
export const fullUrl  = f => `${CDN_BASE}/full/${f}`;
```

**iOS (`Networking/APIClient.swift`):**
```swift
enum CDN {
    static let base = ProcessInfo.processInfo.environment["CDN_BASE"] ?? "https://pub-XXXX.r2.dev"
    static func thumb(for f: String) -> URL { URL(string: "\(base)/thumbs/\(f)")! }
    static func full (for f: String) -> URL { URL(string: "\(base)/full/\(f)")! }
}
```

Always load thumbs first in grids. Upgrade to full only when user opens card detail.
**Never hardcode R2 URLs.** Always use the CDN helper functions.

### Backend (Supabase — Auth & User Data Only)

Supabase is used ONLY for: auth, user card collections, decks.
**Supabase Storage is NOT used.** Images are on Cloudflare R2.

Tables: `user_cards`, `decks`, `deck_cards` — see `supabase_schema.sql`

**Web (`js/api.js`):**
```javascript
const SUPABASE_URL  = window.ENV?.SUPABASE_URL  || 'https://your-project.supabase.co';
const SUPABASE_ANON = window.ENV?.SUPABASE_ANON || 'your-anon-key';
const supabase      = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
```

**iOS:** URLSession directly to Supabase REST API — no Swift SDK (no third-party packages constraint)

### Current Image Coverage

- 17,793 total cards · 15,890 with images · **89.3% coverage**
- 10,751 images on R2 in both tiers (thumbs + full)

---

## Navigation Structure

### iOS Tabs
```
Tab 1: 🔍 Search     — card grid, search bar, filters, card detail
Tab 2: 📷 Scan       — camera with on-device card detection
Tab 3: 📖 Book       — rulebook, strategy tips, deck builder
Tab 4: 🗂 Collection — portfolio dashboard, owned cards, value tracking
Tab 5: 👤 Profile    — auth, settings
```

### Web Sidebar
```
🔍 Search Cards   (default landing)
📖 Rules & Strategy
🗂 My Collection
👤 Profile / Sign In
```

---

## Scan Mode — Technical Notes (iOS Only)

- `AVFoundation` for camera feed (`AVCaptureSession`, `AVCaptureVideoPreviewLayer`)
- `Vision` framework: `VNRecognizeTextRequest` for OCR
- Pipeline: camera frame → Vision OCR → parse card number regex → match `cards.json` → display result
- Card number regex: `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)` (e.g. BF-208, T-16/50)
- If card number found with confidence ≥ 0.7: show match immediately
- If ambiguous: also match hero name + power number (both must agree)
- Fallback to manual search if confidence < 0.7
- **All processing is on-device. No image uploaded to any server.**
- Multi-card mode: scan queue in `@Observable ScanStore`, tally running total value

---

## Key Files

| File | Purpose |
|---|---|
| `assets/data/cards.json` | Full card catalog (web) |
| `assets/data/cards-slim.json` | Card catalog for iOS bundle |
| `assets/data/categories.json` | Filter dropdown data |
| `assets/data/search-index.json` | Pre-built search indexes |
| `supabase_schema.sql` | Supabase table definitions |
| `docs/CARD_SCHEMA.md` | Full cards.json field documentation |
| `docs/EBAY_SEARCH_FINDINGS.md` | eBay search research and findings |
| `docs/IMAGE_SOURCING_STRATEGY.md` | How card images were sourced |
| `docs/CLOUDFLARE_R2_SETUP.md` | R2 upload and CDN setup guide |
| `DECISIONS.md` | Architecture decision log (append-only) |
| `SCRATCHPAD.md` | Feature parity tracker across iOS/web |

---

## Environment Variables

```bash
# .env.local (never commit)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON=your-anon-key
CDN_BASE=https://pub-XXXX.r2.dev
```

---

## Standing Instructions for Claude

### Learning Orientation — Six Criteria

Evaluate before implementing any feature:

1. **Does it deepen understanding?** Active engagement, not passive delivery
2. **Does it invite participation?** Ask something of the user
3. **Does it support human agency?** Make people more capable, not dependent
4. **Clarity over cleverness** — simpler implementation always wins
5. **Accessible by default** — WCAG AA from line one
6. **Responsive from the start** — mobile-first, test at 375px before 1440px

### Autonomous Work Guidelines

- When uncertain between approaches, document in DECISIONS.md and choose simpler
- No feature additions beyond what's requested
- Only fix the bug, don't refactor surrounding code
- If a feature conflicts with learning-orientation values, surface the conflict

---

## Claude Skills Reference

The following Claude Code skills were used in Bsky Dreams development and
are available for this project. Invoke them via the Skill tool or by name.

### UI/UX Design — Killer UI (KUI)

These skills live in `.claude/skills/killer-ui/` and `.claude/commands/KUI/`.

| Skill | When to use |
|---|---|
| `KUI:system` | Create a design system (palette, typography, spacing, components) |
| `KUI:brand` | Develop brand identity (strategy, visual language, logo direction) |
| `KUI:screen` | Design screens following platform-native patterns |
| `KUI:review` | Full design critique (heuristic evaluation, visual hierarchy) |
| `KUI:code` | Convert designs into production-ready accessible frontend code |
| `KUI:a11y` | WCAG 2.2 AA accessibility audit with remediation plan |
| `KUI:darkmode` | Audit and fix dark mode issues (contrast, inverted colors) |
| `KUI:trends` | Research current design trends for any industry |
| `KUI:figma` | Generate Figma-ready specs (auto-layout, components, tokens) |

### App Store Assets

| Skill | When to use |
|---|---|
| `app-store-screenshots` | Generate App Store screenshot pages and promotional assets |

### iOS Development — all-ios-skills

40+ specialized iOS skills available. Most relevant for this project:

| Skill | When to use |
|---|---|
| `all-ios-skills:swiftui-patterns` | MV architecture, state management, environment |
| `all-ios-skills:swiftui-navigation` | NavigationStack, NavigationPath, deep linking |
| `all-ios-skills:swiftui-animation` | Animations, transitions, matched geometry |
| `all-ios-skills:swiftui-gestures` | Gesture handling, custom recognizers |
| `all-ios-skills:swiftui-performance` | Audit and improve runtime performance |
| `all-ios-skills:swiftdata` | Data persistence with SwiftData |
| `all-ios-skills:ios-networking` | URLSession, async/await networking |
| `all-ios-skills:ios-security` | Keychain, CryptoKit, secure storage |
| `all-ios-skills:ios-accessibility` | VoiceOver, Dynamic Type, accessibility |
| `all-ios-skills:vision-framework` | Vision OCR for Scan Mode card detection |
| `all-ios-skills:photos-camera-media` | AVFoundation camera feed for Scan Mode |
| `all-ios-skills:storekit` | In-app purchases and subscriptions |
| `all-ios-skills:swift-charts` | Swift Charts for collection value dashboard |
| `all-ios-skills:swift-concurrency` | Async/await, actors, Swift 6 concurrency |
| `all-ios-skills:swift-testing` | Swift Testing framework, test migration |
| `all-ios-skills:debugging-instruments` | LLDB, Memory Graph, Instruments profiling |
| `all-ios-skills:app-store-review` | App Store review prep, rejection prevention |
| `all-ios-skills:codable-patterns` | JSON encoding/decoding patterns |

### Web Development

| Skill | When to use |
|---|---|
| `frontend-design` | Production-grade frontend interfaces |
| `ui-ux-pro-max` | UI/UX design with 50 styles, 21 palettes, 50 font pairings |
| `killer-ui` | Comprehensive UI skill set |

### Code Quality

| Skill | When to use |
|---|---|
| `simplify` | Review changed code for reuse, quality, and efficiency |
| `claude-api` | Build apps with Claude API or Anthropic SDK |

### How to Use Skills

Skills are invoked when relevant to your task. You can also request them
directly: "Use the KUI:system skill to create a design system" or "Run
the app-store-review skill to check for rejection risks."

For iOS skills, prefix with `all-ios-skills:` — e.g., "Use
all-ios-skills:vision-framework to implement the Scan Mode OCR pipeline."

---

## Current State

See @SCRATCHPAD.md for per-platform feature status and planned work.
See @DECISIONS.md for all architecture decisions (web and iOS).
