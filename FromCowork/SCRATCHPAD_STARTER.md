# SCRATCHPAD.md — Feature Parity Tracker
<!-- Merge this into the DualAppTemplate SCRATCHPAD.md in the BOBA-Playbook repo -->

---

## M1 — Search Mode (Read-Only Card Browser)
**Goal:** Users can browse, search, and filter all 17,793 BOBA cards with images.

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

## M2 — Collection Mode (Auth + Portfolio Tracker)
**Goal:** Logged-in users track owned cards with designations and a value dashboard.

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
- [ ] Push notification opt-in for price alerts (future)

**Parity gate:** Both platforms complete before M3 starts.

---

## M3 — Scan Mode (iOS Camera Card Detection)
**Goal:** Point iPhone camera at a BOBA card → app identifies it on-device in real-time.

**iOS only:**
- [ ] `ScanView.swift` — camera preview (`AVCaptureSession`) with card guide overlay
- [ ] `CardScanner.swift` — Vision OCR pipeline, card number regex, `cards.json` matching
- [ ] Card detection overlay — green border animates when card is detected
- [ ] `ScanResultView.swift` — matched card detail sheet with "Add to Collection"
- [ ] Confidence display — show match confidence; prompt manual search if low
- [ ] Multi-card queue mode — scan several cards, show running value tally
- [ ] `MultiScanQueueView.swift` — list of scanned cards + total value + "Save All" button
- [ ] Fallback: "Search manually" button if scan fails

**No web equivalent for Scan Mode** (camera scanning is iOS-native feature).

---

## M4 — Book Mode (Rules, Strategy, Deck Builder)
**Goal:** In-app rulebook, per-card strategy, and deck builder using your collection.

**Web + iOS:**
- [ ] Rulebook browser — sections, search, deep-link to a rule from card detail
- [ ] Per-card strategy tips — "How to play" section in card detail view
- [ ] Deck builder — select cards from full catalog, check game rule constraints
- [ ] "My Collection" deck builder mode — filter to only owned cards
- [ ] Archetype templates — starter deck configurations (offensive, defensive, balanced)
- [ ] Deck sharing — public link, copy to clipboard
- [ ] Deck value — total comp value of deck based on Radish/eBay prices

---

## M5 (Future) — Discord Trading Channel
**Goal:** Embed BOBA community trading channel in-app.
**Channel:** discord.com/channels/1305710603440095252/1306146115757936650
**Note:** Requires research into Discord Activity SDK or WebView approach.
Research task: determine feasibility before committing to implementation approach.
