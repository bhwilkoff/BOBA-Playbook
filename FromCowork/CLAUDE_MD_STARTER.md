# BOBA Playbook — Claude Code Project Context
<!-- Rename this file to CLAUDE.md in the BOBA-Playbook repo root -->
<!-- Fill in the <!-- FILL IN --> sections after setting up Supabase and R2 -->

## App Overview

**Display name:** BOBA Playbook
**GitHub repo:** BOBA-Playbook · **Xcode product name:** BOBAPlaybook
**Tagline:** "Search. Scan. Collect. Play."
**Platforms:** iOS (SwiftUI) + Web (Vanilla HTML/CSS/JS, GitHub Pages)

BOBA Playbook is the definitive companion app for the **Bo Jackson Battle Arena (BOBA)** trading card game. Features:

1. **Search Mode** — Browse, search, and filter all 17,793 BOBA cards with images and pricing comps
2. **Scan Mode** — iOS camera identifies cards on-device in real-time using Vision framework
3. **Book Mode** — Rules, per-card strategy tips, and deck builder using your collection
4. **Collection Mode** — Portfolio tracker with designations, value dashboard, synced via Supabase

---

## Design System

**Design language:** Retro-futurism + Cyberpunk UI + Glassmorphism

Card artwork is always the focal point. UI chrome serves the art, never competes with it. Bold, legible stat numbers at a glance. Dark backgrounds with frosted glass panels and neon accents.

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

**Source:** `assets/data/cards.json` — 17,793 cards, served as static file from GitHub Pages
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
  "imageSource": "BV",
  "imageAvailable": true,
  "searchTokens": ["escape","artist","ice","bf","alpha","battlefoil"]
}
```

Full schema: `docs/CARD_SCHEMA.md`

**Filter data:** `assets/data/categories.json` — sets, treatments, elements, heroes with counts
**Search index:** `assets/data/search-index.json` — pre-built token/filter indexes for instant results

### Image CDN (Cloudflare R2)

**CDN_BASE:** <!-- FILL IN: your R2 public URL, e.g. https://pub-XXXX.r2.dev -->

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

**iOS helpers:**
```swift
enum CDN {
    static let base = "<!-- FILL IN: R2 URL -->"
    static func thumb(for f: String) -> URL { URL(string: "\(base)/thumbs/\(f)")! }
    static func full (for f: String) -> URL { URL(string: "\(base)/full/\(f)")! }
}
```

Always load thumbs first in grids. Upgrade to full only when user opens card detail.

### Backend (Supabase — Auth & User Data Only)

**Supabase URL:** <!-- FILL IN: https://your-project.supabase.co -->
**Anon key:** <!-- FILL IN: your-anon-key -->

Supabase is used ONLY for: auth, user card collections, decks.
**Supabase Storage is NOT used.** Images are on R2.

Tables: `user_cards`, `decks`, `deck_cards` — see `supabase_schema.sql`

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

## Scan Mode — Technical Notes

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

## iOS Conventions (from DualAppTemplate)

- No third-party packages — URLSession only for networking
- `@Observable` (not `ObservableObject`) for all state
- `NavigationStack` + `NavigationPath` for all drill-down
- `SwiftData` for local persistence (cached card catalog, offline collection)
- Keychain via Security framework for Supabase JWT storage
- `URLCache` for image caching (thumbs in-memory, full images to disk)

---

## Key Files

| File | Purpose |
|---|---|
| `assets/data/cards.json` | Full card catalog (web) |
| `assets/data/cards-slim.json` | Card catalog for iOS bundle |
| `assets/data/categories.json` | Filter dropdown data |
| `assets/data/search-index.json` | Pre-built search indexes |
| `docs/CARD_SCHEMA.md` | Full cards.json field documentation |
| `supabase_schema.sql` | Supabase table definitions |
| `DECISIONS.md` | Architecture decision log (append-only) |
| `SCRATCHPAD.md` | Feature parity tracker across iOS/web |

---

## Current Image Coverage

- 17,793 total cards · 15,890 with images · **89.3% coverage**
- 10,751 images uploaded to R2 in both tiers

---

## Environment Variables

```bash
# .env.local (never commit)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON=your-anon-key
CDN_BASE=https://pub-XXXX.r2.dev
```
