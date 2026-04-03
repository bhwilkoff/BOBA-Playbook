# BOBA Playbook — App Transition Plan
*From Cowork Research → Claude Code Production Build*
*Last updated: 2026-04-03*

---

## What We're Building

**BOBA Playbook** — the definitive companion app for the Bo Jackson Battle Arena (BOBA) trading card game. Available as both a **native iOS app** and a **GitHub Pages web app**, built simultaneously using the `DualAppTemplate` structure with Claude Code.

**App Name:** `BOBA Playbook`
**Repo name:** `BOBACardApp` (no spaces — Xcode Cloud requirement)
**Tagline:** `"Search. Scan. Collect. Play."`

---

## Design Direction

The design language is a deliberate fusion of four aesthetics that mirror the energy of BOBA cards themselves:

- **Retro-futurism** — bold geometry, neon accents on dark fields, nostalgic sci-fi shapes
- **Hyper-realism** — photographic card art front and center, no abstraction of the cards themselves
- **Cyberpunk UI** — glitch effects, scanline overlays, high-contrast color banding, grid textures
- **Glassmorphism** — frosted panels floating over card art, blurred depth layers

**Design principles:**
- Card artwork is always the hero — UI chrome steps back, art steps forward
- Big, legible stat numbers at a glance (Power, Element, Set)
- Intuitive flows that feel native to both iOS and web — no learning curve
- Opinionated, engaging, pulls you in — not sterile or purely utilitarian

**Design tokens for CLAUDE.md:**
```css
/* Core palette */
--boba-orange:     #FF4D00;   /* battle orange — primary CTA */
--boba-cyan:       #00F5FF;   /* cyber cyan — links, highlights */
--boba-violet:     #8B00FF;   /* deep violet — HEX element, accents */
--boba-near-black: #080810;   /* dark base — glass panel backgrounds */
--boba-glass:      rgba(255,255,255,0.08);  /* glassmorphism surface */
--boba-glass-border: rgba(255,255,255,0.15);

/* Element colors (always UPPERCASE in cards.json) */
--element-FIRE:    #FF4D00;
--element-ICE:     #00BFFF;
--element-HEX:     #8B00FF;
--element-STEEL:   #8A9BB0;
--element-BRAWL:   #C0392B;
--element-GLOW:    #FFD700;
--element-GUM:     #FF69B4;
--element-SUPER:   #FF00FF;
--element-NONE:    #666680;

/* Typography */
--font-display:    'Syne', sans-serif;     /* card names, hero names */
--font-mono:       'JetBrains Mono', monospace; /* card numbers, stats */
--font-body:       'Inter', sans-serif;    /* body copy */

/* Glassmorphism recipe */
background: var(--boba-glass);
backdrop-filter: blur(20px) saturate(180%);
border: 1px solid var(--boba-glass-border);
border-radius: 16px;
```

---

## Feature Specifications

### Feature 1 — Search Mode (Card Database)
A fully functional, searchable, filterable database of all 17,793 BOBA cards.

**Core capabilities:**
- Full-text search by hero name, card name, athlete inspiration, card number
- Filter by: Set, Treatment/Variation, Element, Power range
- Pre-built browsable categories from card taxonomy (sets, variations, heroes, elements)
- Card detail view with full art, all stats, treatment info, athlete bio
- **Pricing comps** pulled live from:
  - [Radish Price Guide](https://radishpriceguide.com) — BOBA-specific pricing
  - eBay — live sold listings for the specific card number
- **Box lookup** — search for Hobby, Double Mega, Jumbo boxes; show eBay comps for boxes

**Data source:** `assets/data/cards.json` (17,793 cards, static, served from GitHub Pages)
**Filter data:** `assets/data/categories.json` (sets, treatments, elements, heroes)
**Search index:** `assets/data/search-index.json` (pre-built token index for instant results)

---

### Feature 2 — Scan Mode (iOS Camera Card Recognition)
Use the iOS camera to identify BOBA cards in real-time using entirely on-device processing.

**Core capabilities:**
- Point camera at a card → app identifies it automatically
- Recognition based on BOBA card structure:
  - Power number printed prominently (top-right corner area)
  - Element/weapon symbol (color coded, distinct position)
  - Card number (bottom of card, e.g., "BF-208", "T-16/50")
  - Game name "Bo Jackson Battle Arena" printed at bottom center
  - Hero name in large display font
- **Single card mode:** identify one card, pull up full detail + pricing
- **Multi-card queue mode:** scan several cards sequentially, build a running tally of total collection value based on Radish/eBay comps
- All processing happens **on-device** — no image sent to a server
- Fallback: manual search if scan confidence is low

**iOS implementation:**
- `AVFoundation` for camera feed
- `Vision` framework for text recognition (`VNRecognizeTextRequest`) and card boundary detection
- Parse recognized text against `cards.json` card numbers, hero names, power values
- `CoreImage` for card region isolation and perspective correction
- Confidence threshold gating before showing a match

**What Claude Code needs to build:**
- `ScanView.swift` — camera preview with card overlay guide frame
- `CardScanner.swift` — Vision pipeline, text extraction, matching logic
- `ScanResultView.swift` — matched card detail sheet with "Add to Collection" button
- `MultiScanQueueView.swift` — running list of scanned cards with total value

---

### Feature 3 — Book Mode (Rules, Strategy & Deck Advice)
Rules lookup, card strategy guidance, and AI-powered deck building advice.

**Core capabilities:**
- Full BOBA rulebook browsable and searchable in-app
- Per-card strategy tips: how to play this card effectively, combo opportunities
- **Deck builder:** construct decks from the full card catalog following game rules
- **My Collection deck builder:** filter deck suggestions to cards the user actually owns
- Advice for building competitive decks (offensive, defensive, balanced archetypes)
- Deck sharing (public/private, share link)

**Data:** Rules content, strategy tips, and card interactions stored as structured content (JSON or Markdown). Deck building logic uses game rules (hero + play card construction constraints).

---

### Feature 4 — Collection Mode (Portfolio Tracker)
Track your personal card portfolio with value tracking, designations, and cross-platform sync.

**Core capabilities:**
- Add cards to your collection from Search Mode or Scan Mode
- Per-card designations:
  - 🔒 **Personal Collection** — keeping it
  - 💰 **For Sale** — with asking price
  - 🔄 **For Trade** — with trade preferences
- Track: condition (NM, EX, VG, G, PR), serial number, grade (PSA, BGS, CGC), purchase price
- **Collection value dashboard:**
  - Total portfolio value (sum of Radish/eBay comps)
  - Value over time chart
  - Breakdown by set, treatment, element
- Collection saved to **Supabase** — available on both iOS and web, synced across devices
- Offline support on iOS (SwiftData caches local state, syncs when online)

**Supabase tables needed:**
```sql
-- user_cards: one row per card in collection
id, user_id, card_id, designation,
condition, serial_number, grade, grading_company,
purchase_price, estimated_value, last_price_check, acquired_at, notes

-- decks + deck_cards: user-created decks
-- marketplace_listings: future Feature 6
```

---

### Feature 5 — Future Release: Discord Trading Channel
Embed the BOBA community Discord trading channel directly in the app for in-app card trading discussion.

**Channel:** `https://discord.com/channels/1305710603440095252/1306146115757936650`

**Implementation note for Claude Code:** Discord does not support direct iframe/WebView embedding of channels without the Discord OAuth widget flow. Explore Discord's [Activity SDK](https://discord.com/developers/docs/activities/overview) or a read-only WebView of the channel for the future release. Flag this as a research task when starting Feature 5 work.

---

## Repository & File Structure

### Repository
- **Name:** `BOBACardApp` (this is what Xcode Cloud requires — keep even though app display name is "BOBA Playbook")
- **Template:** Fork from `https://github.com/bhwilkoff/DualAppTemplate`
- **Live web URL:** `https://bhwilkoff.github.io/BOBACardApp/`

### What Goes in the Repo (from this research folder)

```
BOBACardApp/
├── assets/
│   └── data/
│       ├── cards.json          ← unified-cards/data/cards.json (17,793 cards, 13 MB)
│       ├── cards-slim.json     ← unified-cards/data/cards-slim.json (iOS bundle, 8.7 MB)
│       ├── categories.json     ← unified-cards/data/categories.json (filter options)
│       └── search-index.json   ← unified-cards/data/search-index.json (search index)
├── docs/
│   ├── CARD_SCHEMA.md          ← unified-cards/docs/CARD_SCHEMA.md
│   ├── EBAY_SEARCH_FINDINGS.md ← EBAY_SEARCH_FINDINGS.md
│   ├── IMAGE_SOURCING_STRATEGY.md
│   └── CLOUDFLARE_R2_SETUP.md
├── CLAUDE.md                   ← fill from this doc (Step 2)
├── DECISIONS.md                ← add Decisions 006–012 (see Step 10)
├── SCRATCHPAD.md               ← add milestones M1–M4 (see Step 3)
└── supabase_schema.sql         ← from Step 5
```

**Images are NEVER in the repo.** They live on Cloudflare R2.

### What Stays in the Research Folder (Not in Repo)

| Folder/File | Why it stays here |
|---|---|
| `unified-cards/images/` | 1.38 GB originals — too large, archive only |
| `unified-cards/images-optimized/` | 720 MB — upload to R2 as `full/` |
| `unified-cards/thumbs/` | 114 MB — upload to R2 as `thumbs/` |
| `source-images/` | Source images, already processed |
| `radish-scrape/` | Source images, already processed |
| `ebay-*/` | eBay pipeline, ongoing research |
| All `.py` scripts | Research/data tools, not app code |
| `BOBA-Master-Card-Database.xlsx` | Source of truth for card data |
| `bv_rename_mapping.csv` | Pipeline artifact |
| `ebay_token.txt` | Never commit credentials |

---

## Step-by-Step Actions to Start Building

### Step 1 — Fork and Configure the Repo

1. Go to `https://github.com/bhwilkoff/DualAppTemplate` → click **"Use this template"**
2. Name the repo: **`BOBACardApp`** (no spaces)
3. Clone locally: `git clone https://github.com/bhwilkoff/BOBACardApp`
4. In **GitHub Settings → Pages**: source = `main` branch, root `/`
5. Verify GitHub Pages is live at `https://bhwilkoff.github.io/BOBACardApp/`

---

### Step 2 — Fill in CLAUDE.md

Open `CLAUDE.md` and replace every `<!-- FILL IN -->` placeholder:

**App description:**
```
App display name: BOBA Playbook
Repo/Xcode name: BOBACardApp
Tagline: "Search. Scan. Collect. Play."

This is the definitive companion app for the Bo Jackson Battle Arena (BOBA)
trading card game — a retro-futurist / cyberpunk / glassmorphism card database,
scanner, collection tracker, and strategy guide available on iOS and web.

Modes:
  1. Search Mode — browse/filter/search all 17,793 BOBA cards with pricing comps
  2. Scan Mode   — iOS camera identifies cards on-device using Vision framework
  3. Book Mode   — rulebook, per-card strategy tips, deck builder
  4. Collection Mode — portfolio tracker with value dashboard, synced via Supabase

The card catalog is assets/data/cards.json (17,793 cards, static, served from
GitHub Pages). Card images come from Cloudflare R2. No images are in the repo.
Backend is Supabase for auth and user data (collections, decks) ONLY.
```

**Design tokens (copy verbatim into CLAUDE.md design section):**
```css
--boba-orange:      #FF4D00;
--boba-cyan:        #00F5FF;
--boba-violet:      #8B00FF;
--boba-near-black:  #080810;
--boba-glass:       rgba(255,255,255,0.08);
--boba-glass-border: rgba(255,255,255,0.15);
--element-FIRE: #FF4D00; --element-ICE: #00BFFF; --element-HEX: #8B00FF;
--element-STEEL: #8A9BB0; --element-BRAWL: #C0392B; --element-GLOW: #FFD700;
--element-GUM: #FF69B4; --element-SUPER: #FF00FF; --element-NONE: #666680;
Font display: Syne | Font mono: JetBrains Mono | Font body: Inter
Design language: retro-futurism + cyberpunk UI + glassmorphism
```

**Image CDN (copy verbatim into CLAUDE.md):**
```
CDN_BASE env var controls the Cloudflare R2 public URL.
Thumb URL:  {CDN_BASE}/thumbs/{imageFile}   ← use in card grids (200px wide WebP)
Full URL:   {CDN_BASE}/full/{imageFile}     ← use in card detail (max 1200px WebP)
imageFile field comes from cards.json (e.g. "BF-208_Escape_Artist_ICE_P185.webp")
Never hardcode R2 URLs. Always use the CDN helper functions.
```

---

### Step 3 — Fill in SCRATCHPAD.md

```markdown
## M1 — Search Mode (Read-Only Card Browser)
Goal: Users can browse, search, and filter all 17,793 BOBA cards with images.
Web: Card grid (lazy-load thumbs), search bar, filter panel (set/element/treatment),
     card detail modal with full art + all stats
iOS: NavigationStack card list/grid, search, filter sheet, card detail view
Parity: Both platforms complete before M2

## M2 — Collection Mode (Auth + Portfolio)
Goal: Logged-in users track owned cards with designations and value dashboard
Web: Auth flow (Supabase), "Add to Collection" button, My Collection view,
     value dashboard (total, by set, by element)
iOS: Same + SwiftData offline persistence + Supabase sync
Designations: Personal Collection | For Sale (with price) | For Trade

## M3 — Scan Mode (iOS Camera)
Goal: Point iPhone camera at a BOBA card → app identifies it in real-time
iOS only: AVFoundation camera feed, Vision text recognition, match to cards.json
Modes: Single card detail | Multi-card queue with running value tally
Fallback: Manual search if scan confidence < threshold

## M4 — Book Mode (Rules + Strategy + Deck Builder)
Goal: In-app rulebook, per-card strategy tips, deck builder using your collection
Web + iOS: Rulebook browser, card strategy tips, deck builder UI
Collection integration: Filter deck suggestions to cards you own
Deck sharing: Public/private deck links
```

---

### Step 4 — Create the Xcode Project

Follow the template's exact instructions (critical — deviations break Xcode Cloud):

1. Open Xcode → File → New → Project → iOS → App
2. Product Name: **`BOBACardApp`** (repo name, not display name)
3. Display name in Info.plist: **`BOBA Playbook`**
4. Organization Identifier: `com.bhwilkoff`
5. **Save location: the repository root** (not a subdirectory)
6. Interface: SwiftUI | Language: Swift | Storage: None (add SwiftData manually)
7. Move starter files from `ios/` into `BOBACardApp/` group in Xcode:
   - `ios/App/AppNameApp.swift` → rename `BOBACardAppApp.swift`
   - `ios/ContentView.swift`
   - `ios/Networking/APIClient.swift`
   - `ios/Store/AppStore.swift`
8. Add `AppVersion.xcconfig` to both Debug and Release configurations
9. Delete the empty `ios/` directory after migration
10. Commit: `git add -A && git commit -m "Init Xcode project: BOBA Playbook (BOBACardApp)"`

---

### Step 5 — Set Up Supabase

1. Create a free project at `https://supabase.com` — Project name: `boba-card-app`
2. Run this schema:

```sql
-- Collection tracker
CREATE TABLE user_cards (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid REFERENCES auth.users ON DELETE CASCADE,
  card_number      text NOT NULL,        -- matches cards.json cardNumber field
  designation      text DEFAULT 'personal' CHECK (designation IN ('personal','for_sale','for_trade')),
  condition        text,                 -- NM, EX, VG, G, PR
  serial_number    int,
  grade            text,                 -- PSA 10, BGS 9.5, CGC 10, etc.
  grading_company  text,
  purchase_price   decimal(10,2),
  asking_price     decimal(10,2),        -- if designation = 'for_sale'
  estimated_value  decimal(10,2),
  last_price_check timestamptz,
  acquired_at      timestamptz DEFAULT now(),
  notes            text
);

-- Decks
CREATE TABLE decks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES auth.users ON DELETE CASCADE,
  name        text NOT NULL,
  description text,
  is_public   boolean DEFAULT false,
  archetype   text,                     -- 'offensive','defensive','balanced','control'
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);

CREATE TABLE deck_cards (
  deck_id     uuid REFERENCES decks(id) ON DELETE CASCADE,
  card_number text NOT NULL,            -- matches cards.json cardNumber field
  quantity    int DEFAULT 1,
  PRIMARY KEY (deck_id, card_number)
);

-- RLS: users can only access their own rows
ALTER TABLE user_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE decks ENABLE ROW LEVEL SECURITY;
ALTER TABLE deck_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own rows" ON user_cards USING (auth.uid() = user_id);
CREATE POLICY "own rows" ON decks USING (auth.uid() = user_id);
CREATE POLICY "own deck rows" ON deck_cards
  USING (deck_id IN (SELECT id FROM decks WHERE user_id = auth.uid()));
-- Public decks readable by all
CREATE POLICY "public decks" ON decks FOR SELECT USING (is_public = true);
```

3. Copy your **Supabase URL** and **anon public key** → add to `js/api.js` and `ios/Networking/APIClient.swift`

> ⚠️ **Do NOT use Supabase Storage for images.** 1 GB free limit is exhausted in hours by a card app. Images live on Cloudflare R2 only.

---

### Step 5.5 — Upload Images to Cloudflare R2

Full walkthrough: `docs/CLOUDFLARE_R2_SETUP.md`

Quick steps:
1. Create free Cloudflare account → R2 → Create bucket: `boba-card-images`
2. Enable public access on the bucket
3. Install rclone: `brew install rclone` → configure with R2 credentials
4. Upload both image tiers from your local Research folder:
```bash
# From "Bo Jackson Battle Arena Research/" folder:
rclone copy "unified-cards/images-optimized/" r2:boba-card-images/full/ --progress
rclone copy "unified-cards/thumbs/"           r2:boba-card-images/thumbs/ --progress
```
5. Note your public URL: `https://pub-XXXX.r2.dev`
6. Add to `.env.example`:
```
CDN_BASE=https://pub-XXXX.r2.dev
```

**Image counts as of 2026-04-03:**
- `images-optimized/` (upload as `full/`): **10,751 files, ~720 MB**
- `thumbs/` (upload as `thumbs/`): **10,751 files, ~114 MB**

---

### Step 6 — Copy Card Catalog Data to Repo

```bash
# Run from "Bo Jackson Battle Arena Research/" folder:
mkdir -p /path/to/BOBACardApp/assets/data
mkdir -p /path/to/BOBACardApp/docs

cp unified-cards/data/cards.json        /path/to/BOBACardApp/assets/data/cards.json
cp unified-cards/data/cards-slim.json   /path/to/BOBACardApp/assets/data/cards-slim.json
cp unified-cards/data/categories.json   /path/to/BOBACardApp/assets/data/categories.json
cp unified-cards/data/search-index.json /path/to/BOBACardApp/assets/data/search-index.json

cp unified-cards/docs/CARD_SCHEMA.md       /path/to/BOBACardApp/docs/CARD_SCHEMA.md
cp EBAY_SEARCH_FINDINGS.md                 /path/to/BOBACardApp/docs/EBAY_SEARCH_FINDINGS.md
cp IMAGE_SOURCING_STRATEGY.md              /path/to/BOBACardApp/docs/IMAGE_SOURCING_STRATEGY.md
cp CLOUDFLARE_R2_SETUP.md                  /path/to/BOBACardApp/docs/CLOUDFLARE_R2_SETUP.md
```

**Key data file facts for CLAUDE.md:**

| File | Size | Purpose |
|---|---|---|
| `cards.json` | 13 MB | Full catalog, 17,793 cards — web app primary |
| `cards-slim.json` | 8.7 MB | No search tokens — smaller iOS bundle |
| `categories.json` | ~135 KB | Sets, treatments, elements, heroes with counts |
| `search-index.json` | ~5.6 MB | Pre-built token/filter indexes for instant search |

**cards.json card object schema:**
```json
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

---

### Step 7 — Add Supabase Client to Both Platforms

**Web (`js/api.js`):**
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
```
```javascript
const SUPABASE_URL  = window.ENV?.SUPABASE_URL  || 'https://your-project.supabase.co';
const SUPABASE_ANON = window.ENV?.SUPABASE_ANON || 'your-anon-key';
const supabase      = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
const CDN_BASE      = window.ENV?.CDN_BASE || 'https://pub-XXXX.r2.dev';
export const thumbUrl = f => `${CDN_BASE}/thumbs/${f}`;
export const fullUrl  = f => `${CDN_BASE}/full/${f}`;
```

**iOS (`Networking/APIClient.swift`):** Use `URLSession` directly to Supabase REST API — no Swift SDK (no third-party packages constraint):
```swift
private let supabaseURL     = ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "https://your-project.supabase.co"
private let supabaseAnonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON"] ?? "your-anon-key"
static let cdnBase          = ProcessInfo.processInfo.environment["CDN_BASE"] ?? "https://pub-XXXX.r2.dev"
static func thumbURL(for imageFile: String) -> URL { URL(string: "\(cdnBase)/thumbs/\(imageFile)")! }
static func fullURL (for imageFile: String) -> URL { URL(string: "\(cdnBase)/full/\(imageFile)")! }
```

---

### Step 8 — Define Swift Data Models

```swift
// BOBACardApp/Models/Card.swift — decoded from cards-slim.json, cached in SwiftData
@Model final class Card {
    @Attribute(.unique) var cardNumber: String
    var bvId: Int
    var name: String
    var hero: String
    var cardType: String       // "Hero" | "Play"
    var set: String
    var subSet: String
    var variation: String
    var treatment: String
    var element: String        // "FIRE","ICE","HEX","STEEL","BRAWL","GLOW","GUM","SUPER","NONE"
    var power: Int
    var playCost: Int
    var playAbility: String?
    var athleteInspiration: String?
    var isInspiredInk: Bool
    var imageFile: String?     // nil = no image yet; construct URL with CDN helpers
    var imageAvailable: Bool
}

// BOBACardApp/Models/UserCard.swift — synced with Supabase user_cards table
struct UserCard: Codable, Identifiable {
    let id: UUID
    let cardNumber: String
    var designation: Designation
    var condition: String?
    var serialNumber: Int?
    var grade: String?
    var gradingCompany: String?
    var purchasePrice: Decimal?
    var askingPrice: Decimal?
    var estimatedValue: Decimal?
    var notes: String?
    var acquiredAt: Date

    enum Designation: String, Codable, CaseIterable {
        case personal    = "personal"
        case forSale     = "for_sale"
        case forTrade    = "for_trade"
    }
}

// BOBACardApp/Models/Deck.swift
struct Deck: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String
    var isPublic: Bool
    var archetype: String?
    var cards: [DeckCard]
}
struct DeckCard: Codable {
    let cardNumber: String
    var quantity: Int
}
```

---

### Step 9 — Navigation Structure

**iOS Tab Bar:**
```
Tab 1: 🔍 Search       — card grid/list, search bar, filters, card detail
Tab 2: 📷 Scan         — camera view with card detection overlay
Tab 3: 📖 Book         — rulebook, strategy tips, deck builder
Tab 4: 🗂️ Collection  — portfolio dashboard, owned cards, value tracking
Tab 5: 👤 Profile      — auth, settings, sync status
```

**Web Sidebar Nav:**
```
🔍 Search Cards     (default)
📖 Rules & Strategy
🗂️ My Collection
👤 Profile / Sign In
```

**Key iOS navigation patterns (from template conventions):**
- `NavigationStack` with `NavigationPath` for all drill-down navigation
- `selectedTab` in `AppStore` drives root view switch
- Card detail → `NavigationLink` push (depth navigation)
- "Add to Collection" / scan result → `sheet` (modal create flow)
- Filter panel → `sheet` (bottom sheet)

---

### Step 10 — DECISIONS.md Entries to Add Before Claude Code

Add these as Decision entries in `DECISIONS.md`:

```
Decision 006 — App Name and Brand Identity
Display name: BOBA Playbook. Repo/Xcode name: BOBACardApp (Xcode Cloud requirement).
Design language: retro-futurism + cyberpunk UI + glassmorphism.
Primary palette: battle orange (#FF4D00), cyber cyan (#00F5FF), deep violet (#8B00FF)
on near-black (#080810) backgrounds with frosted glass panels.
Card artwork is always the focal point — UI chrome serves it, not the reverse.

Decision 007 — Supabase as Backend (Auth & User Data Only)
Supabase free tier for auth, user_cards (collection), decks, deck_cards.
Static card catalog (cards.json, GitHub Pages) for browsing — no DB query needed.
Supabase Storage is NOT used — 1 GB free + 2 GB/month bandwidth would exhaust in days.
Images go on Cloudflare R2 exclusively.

Decision 008 — Cloudflare R2 for Image CDN
10,751 card images on R2 bucket boba-card-images. R2 chosen for: 10 GB free,
zero egress fees, Cloudflare edge caching globally.
Two tiers: thumbs/ (200px WebP, ~10 KB) for grids; full/ (≤1200px WebP, ~80 KB) for detail.
CDN_BASE env var holds public bucket URL. Never hardcode R2 URLs in code.

Decision 009 — Static Card Catalog JSON (Already Generated)
cards.json (13 MB, 17,793 cards) committed to assets/data/, served from GitHub Pages.
No DB query for browsing. cards-slim.json (8.7 MB, no tokens) for iOS bundle.
SwiftData caches on iOS after first load. Re-run reconcile_all.py for new card releases,
then re-copy output files to assets/data/ and commit.

Decision 010 — Element Color System
Each BOBA element maps to a canonical UI color used throughout the app.
FIRE:#FF4D00 ICE:#00BFFF HEX:#8B00FF STEEL:#8A9BB0 BRAWL:#C0392B
GLOW:#FFD700 GUM:#FF69B4 SUPER:#FF00FF NONE:#666680
Elements in cards.json are always UPPERCASE (normalized by reconcile_all.py).

Decision 011 — No Images in GitHub Repo
Repo contains only code and JSON data. Images never committed to git.
assets/data/ has the four JSON files. assets/images/ does NOT exist.

Decision 012 — Scan Mode: On-Device Only (Vision Framework)
Card scanning uses iOS Vision (VNRecognizeTextRequest) + AVFoundation only.
No image is uploaded to a server. Processing is entirely on-device.
Match pipeline: extract text → parse card number pattern → match cards.json →
if ambiguous, also match hero name and power number.
Confidence threshold: require card number OR (hero name + power) to confirm a match.
Fallback to manual search if confidence < 0.7.
```

---

## What to Tell Claude Code on Day 1

When you start your first Claude Code session in `BOBACardApp`:

> "We're building **BOBA Playbook**, a companion app for the Bo Jackson Battle Arena trading card game — iOS + web, built in parallel with DualAppTemplate.
>
> The card catalog is `assets/data/cards.json` — 17,793 cards, already committed. Card images are on Cloudflare R2 at CDN_BASE (env var) as `thumbs/{imageFile}` (~10 KB WebP) and `full/{imageFile}` (~80 KB WebP). `imageFile` is the field in each card object.
>
> Backend is Supabase for auth and user data (collections, decks) only — **no images in Supabase**.
>
> Design language: **retro-futurism + cyberpunk UI + glassmorphism**. Card art is always the hero. Big bold stat numbers. Dark backgrounds (#080810) with frosted glass panels and neon accents (orange #FF4D00, cyan #00F5FF). Each element has a color — see Decision 010.
>
> **Start with M1: Search Mode web version.** Build the card grid view that lazy-loads thumb images as the user scrolls. Use `categories.json` for filter options and `search-index.json` for instant in-browser search. No auth needed for M1. Style it with the design tokens in CLAUDE.md."

---

## Current Status (2026-04-03)

### ✅ Completed in Cowork
- Full card database scraped (The card source, Radish, GCS, eBay): **17,793 cards**
- Image reconciliation pipeline: **89.3% image coverage (15,890 cards)**
- Image optimization: **10,751 files** in `thumbs/` + `images-optimized/`
- Static JSON exports: `cards.json`, `cards-slim.json`, `categories.json`, `search-index.json`
- eBay search pipeline with human review gate (58 eBay images in database)
- eBay search research findings documented: `EBAY_SEARCH_FINDINGS.md`

### 🔲 Still Needed Before Starting Claude Code

| Task | Priority | Notes |
|---|---|---|
| **Upload images to R2** | 🔴 Must-do first | `unified-cards/images-optimized/` → R2 `full/` + `unified-cards/thumbs/` → R2 `thumbs/` (~834 MB total) |
| **Fork DualAppTemplate → BOBACardApp** | 🔴 Must-do first | Step 1 above |
| **Copy data JSONs to repo** | 🔴 Must-do first | Step 6 above |
| **Fill in CLAUDE.md** | 🔴 Must-do first | Use text from Step 2 |
| **Add DECISIONS.md entries** | 🔴 Must-do first | Step 10 above |
| **Create Supabase project** | 🟡 Before M2 | Not needed for M1 card browsing |
| **eBay token refresh + re-run** | 🟢 Nice-to-have | Run `ebay_missing_images.py` again when token refreshed |
| **Sketch 3 wireframes** | 🟢 Nice-to-have | Card grid, card detail, collection dashboard |

### Image Coverage Summary

| Source | Cards | Notes |
|---|---|---|
| The card source (BV) | 4,756 | Highest res (745×1040), all sets |
| Radish/Cloudinary | 5,630 | 477×667, Griffey Edition |
| GCS Bucket | 287 | Alpha legacy |
| eBay (human-verified) | 58 | QC'd through review pipeline |
| **Total with images** | **15,890 / 17,793** | **89.3% coverage** |

**Missing (1,903 cards):**
- 1,093 BLAST treatment cards — not listed individually on eBay
- 364 Inspired Ink Battlefoil — ~12% findable on eBay, rest unavailable
- 97 Paper base cards — not commonly listed individually
- 349 other treatments (Superfoil, Metallic, etc.)

---

*Read alongside: `docs/CARD_SCHEMA.md`, `docs/IMAGE_SOURCING_STRATEGY.md`, `docs/CLOUDFLARE_R2_SETUP.md`, `docs/EBAY_SEARCH_FINDINGS.md`*
