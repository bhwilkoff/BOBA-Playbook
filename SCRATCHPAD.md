# BOBA Playbook — Project Scratchpad

## Current State

- **Status**: M0 in progress — data files needed, Xcode project not yet created
- **Active milestone**: M0
- **Last session**: 2026-04-03 — Cowork research completed; transition files merged into Claude Code repo
- **Next actions**:
  1. Copy card data JSONs from Research folder → `assets/data/` (see HANDOFF_MANIFEST.md)
  2. Upload images to Cloudflare R2 (`unified-cards/images-optimized/` → `full/`, `unified-cards/thumbs/` → `thumbs/`)
  3. Create Supabase project, run `supabase_schema.sql`
  4. Create Xcode project at repo root: product name `BOBAPlaybook`
  5. Enable GitHub Pages on main branch (if not already live)
  6. Start M1: Search Mode web version
- **Open questions**:
  - What is the Cloudflare R2 public URL (CDN_BASE)?
  - What is the Supabase project URL and anon key?

---

## Feature Parity Status

✅ Complete on both | 🌐 Web only | 📱 iOS only | ⏳ Planned | ❌ Deferred

| Feature | Web | iOS | Notes |
|---|---|---|---|
| Search Mode (card browser) | ⏳ | ⏳ | M1 |
| Collection Mode (portfolio) | ⏳ | ⏳ | M2 |
| Scan Mode (camera OCR) | ❌ | ⏳ | M3 — iOS only by design |
| Book Mode (rules + decks) | ⏳ | ⏳ | M4 |
| Discord Trading Channel | ❌ | ❌ | M5 — future, pending research |

---

## Milestones

### M0 — Project Setup
- [ ] Card data JSONs copied to `assets/data/` (cards.json, cards-slim.json, categories.json, search-index.json)
- [ ] Images uploaded to Cloudflare R2 (`full/` + `thumbs/` tiers)
- [ ] Supabase project created, schema applied, URL + anon key saved
- [ ] CLAUDE.md, DECISIONS.md, SCRATCHPAD.md filled in (done ✅)
- [ ] Xcode project created at repo root (`BOBAPlaybook`, no spaces, iOS 17+)
- [ ] GitHub Pages enabled, index.html live at https://bhwilkoff.github.io/BOBA-Playbook/
- [ ] `.env.local` created with SUPABASE_URL, SUPABASE_ANON, CDN_BASE
- [ ] First substantive commit pushed

---

### M1 — Search Mode (Read-Only Card Browser)
**Goal:** Users can browse, search, and filter all 17,793 BOBA cards with images.
- **Learning check**: [x] Deepens understanding [x] Invites participation [x] Supports agency
- **Acceptance criteria**: A user can arrive at the app, search for any BOBA card by name or number, filter by element/set/treatment, see the card art, all stats, and pricing comps.

**Web:**
- [ ] Card grid view — lazy-load thumbs as user scrolls
- [ ] Search bar — instant results using `search-index.json`
- [ ] Filter panel — set, element, treatment, power range (data from `categories.json`)
- [ ] Card detail modal — full art (load from `full/`), all stats, athlete bio
- [ ] No-image placeholder for 1,903 cards without images
- [ ] Pricing comps section in card detail (Radish + eBay)
- [ ] Box lookup page

**iOS:**
- [ ] Card grid/list view — `LazyVGrid` with thumb images
- [ ] Search — `searchable` modifier, filter against `cards-slim.json` (SwiftData cached)
- [ ] Filter sheet — bottom sheet with set/element/treatment/power filters
- [ ] Card detail view — `NavigationLink` push, full art from CDN
- [ ] No-image placeholder
- [ ] Pricing comps in card detail
- [ ] Box lookup

**Parity gate:** Both platforms complete before M2 starts.

---

### M2 — Collection Mode (Auth + Portfolio Tracker)
**Goal:** Logged-in users track owned cards with designations and a value dashboard.
- **Learning check**: [x] Deepens understanding [x] Invites participation [x] Supports agency

**Web:**
- [ ] Auth flow (Supabase email/password + magic link)
- [ ] "Add to Collection" button in card detail
- [ ] Add card modal — designation, condition, serial number, grade, purchase price
- [ ] My Collection view — filterable list by designation
- [ ] Value dashboard — total portfolio value, breakdown by set/element
- [ ] Designation management — change between Personal / For Sale / For Trade
- [ ] For Sale cards — show asking price, link to eBay

**iOS:**
- [ ] Auth screens (sign in, sign up, forgot password)
- [ ] "Add to Collection" button — sheet modal
- [ ] Collection view — grouped by designation, sortable
- [ ] Value dashboard — charts (Swift Charts)
- [ ] SwiftData offline persistence + Supabase sync on launch

**Parity gate:** Both platforms complete before M3 starts.

---

### M3 — Scan Mode (iOS Camera Card Detection)
**Goal:** Point iPhone camera at a BOBA card → app identifies it on-device in real-time.
- **Learning check**: [x] Deepens understanding [x] Invites participation [x] Supports agency

**iOS only:**
- [ ] `ScanView.swift` — camera preview (`AVCaptureSession`) with card guide overlay
- [ ] `CardScanner.swift` — Vision OCR pipeline, card number regex, `cards.json` matching
- [ ] Card detection overlay — green border animates when card is detected
- [ ] `ScanResultView.swift` — matched card detail sheet with "Add to Collection"
- [ ] Confidence display — show match confidence; prompt manual search if low
- [ ] Multi-card queue mode — scan several cards, show running value tally
- [ ] `MultiScanQueueView.swift` — list of scanned cards + total value + "Save All" button
- [ ] Fallback: "Search manually" button if scan fails

**No web equivalent** — camera scanning is an iOS-native feature.

---

### M4 — Book Mode (Rules, Strategy, Deck Builder)
**Goal:** In-app rulebook, per-card strategy, and deck builder using your collection.
- **Learning check**: [x] Deepens understanding [x] Invites participation [x] Supports agency

**Web + iOS:**
- [ ] Rulebook browser — sections, search, deep-link to a rule from card detail
- [ ] Per-card strategy tips — "How to play" section in card detail view
- [ ] Deck builder — select cards from full catalog, check game rule constraints
- [ ] "My Collection" deck builder mode — filter to only owned cards
- [ ] Archetype templates — starter deck configurations (offensive, defensive, balanced)
- [ ] Deck sharing — public link, copy to clipboard
- [ ] Deck value — total comp value of deck based on Radish/eBay prices

---

### M5 (Future) — Discord Trading Channel
**Goal:** Embed BOBA community trading channel in-app.
**Channel:** discord.com/channels/1305710603440095252/1306146115757936650
**Note:** Requires research into Discord Activity SDK or WebView approach. Research task: determine feasibility before committing to an implementation approach.

---

## Web App Status

### Completed
- (none yet)

### Next for Web
- M0 setup: copy data files, configure CDN_BASE, start M1 card grid

---

## iOS App Status

### Completed
- (none yet)

### Next for iOS
- M0 setup: create Xcode project at repo root (product name: BOBAPlaybook)

---

## Open Questions

- What is the Cloudflare R2 public URL (CDN_BASE)?
- What is the Supabase project URL and anon key?
- Will eBay pricing API require a proxy endpoint, or does CORS allow direct client calls?
- Rules and strategy content for Book Mode — where does this content come from? (manual entry, rulebook PDF parse, etc.)

---

## Session Log

<!-- Append-only. Format: state found → work done → state left -->

**2026-04-03** — Cowork research phase complete. Card database (17,793 cards, 89.3% image coverage) and all data pipeline artifacts ready. Transition files merged into Claude Code repo: CLAUDE.md, DECISIONS.md, SCRATCHPAD.md updated with full BOBA Playbook context. M0 setup in progress — data files and Xcode project still needed.
