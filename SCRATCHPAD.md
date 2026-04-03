# BOBA Playbook — Project Scratchpad

## Current State

- **Status**: M1 web complete (minus pricing comps + box lookup); iOS not yet started
- **Active milestone**: M1 → M2 transition
- **Last session**: 2026-04-03 — M1 web Search Mode built and polished; full UI redesign complete
- **Open questions**:
  - eBay pricing API — does CORS allow direct client calls, or do we need a proxy?
  - Rules/strategy content for Book Mode — source? (manual entry, PDF parse, etc.)

---

## Feature Parity Status

✅ Complete on both | 🌐 Web only | 📱 iOS only | ⏳ Planned | ❌ Deferred

| Feature | Web | iOS | Notes |
|---|---|---|---|
| Search Mode (card browser) | 🌐 | ⏳ | M1 — web done, iOS not started |
| Collection Mode (portfolio) | ⏳ | ⏳ | M2 |
| Scan Mode (camera OCR) | ❌ | ⏳ | M3 — iOS only by design |
| Book Mode (rules + decks) | ⏳ | ⏳ | M4 |
| Discord Trading Channel | ❌ | ❌ | M5 — future, pending research |

---

## Milestones

### M0 — Project Setup ✅ COMPLETE
- [x] Card data JSONs copied to `assets/data/` (cards.json, cards-slim.json, categories.json, search-index.json)
- [x] Images uploaded to Cloudflare R2 (`full/` + `thumbs/` tiers) — 10,751 images
- [x] Supabase project created, schema applied, URL + anon key saved
- [x] CLAUDE.md, DECISIONS.md, SCRATCHPAD.md filled in
- [x] Xcode project created at repo root (`BOBAPlaybook`, no spaces, iOS 17+)
- [x] GitHub Pages live at https://bhwilkoff.github.io/BOBA-Playbook/
- [x] `.env.local` created with SUPABASE_URL, SUPABASE_ANON, CDN_BASE

---

### M1 — Search Mode (Read-Only Card Browser)
**Goal:** Users can browse, search, and filter all 17,793 BOBA cards with images.

**Web:** 🌐 Substantially complete
- [x] Card grid view — lazy-load thumbs, IntersectionObserver pagination (60 per page)
- [x] Search bar — instant results using `search-index.json`, debounced
- [x] Filter panel — element pills, set/treatment selects, power range (min/max + presets)
- [x] Card detail modal — full art (pinch/scroll/drag zoom), all stats, athlete bio
- [x] No-image placeholder — branded "BOBA PB / Image Pending" with element tint
- [x] Treatment ribbons on card grid tiles (Battlefoil, Superfoil, Blizzard, etc.)
- [x] Element-reactive glows, set badges, modal element gradient
- [x] UI redesign — Bebas Neue / Russo One / Chakra Petch font system
- [ ] Pricing comps in card detail (Radish + eBay) — deferred to M3
- [ ] Box lookup page — deferred to M3

**iOS:** ⏳ Not started
- [ ] Card grid/list view — `LazyVGrid` with thumb images
- [ ] Search — `searchable` modifier, filter against `cards-slim.json` (SwiftData cached)
- [ ] Filter sheet — bottom sheet with set/element/treatment/power filters
- [ ] Card detail view — `NavigationLink` push, full art from CDN, pinch zoom
- [ ] No-image placeholder
- [ ] Pricing comps in card detail
- [ ] Box lookup

**Parity gate:** Both platforms complete before M2 starts.
*(Pricing comps + box lookup deferred on both platforms to M3 since they share dependencies.)*

---

### M2 — Collection Mode (Auth + Portfolio Tracker)
**Goal:** Logged-in users track owned cards with designations and a value dashboard.

**Web:**
- [ ] Auth flow (Supabase email/password + magic link)
- [ ] "Add to Collection" button in card detail
- [ ] Add card modal — designation, condition, serial number, grade, purchase price
- [ ] My Collection view — filterable list by designation
- [ ] Value dashboard — total portfolio value, breakdown by set/element
- [ ] Designation management — Personal / For Sale / For Trade
- [ ] For Sale cards — show asking price, link to eBay

**iOS:**
- [ ] Auth screens (sign in, sign up, forgot password)
- [ ] "Add to Collection" button — sheet modal
- [ ] Collection view — grouped by designation, sortable
- [ ] Value dashboard — charts (Swift Charts)
- [ ] SwiftData offline persistence + Supabase sync on launch

**Parity gate:** Both platforms complete before M3 starts.

---

### M3 — Scan Mode (iOS) + Pricing Comps (both)
**Goal:** Camera card detection on iOS; live pricing on both platforms.

**iOS only:**
- [ ] `ScanView.swift` — camera preview (`AVCaptureSession`) with card guide overlay
- [ ] `CardScanner.swift` — Vision OCR pipeline, card number regex, `cards.json` matching
- [ ] Card detection overlay — border animates when card detected
- [ ] `ScanResultView.swift` — matched card detail sheet with "Add to Collection"
- [ ] Multi-card queue mode — scan queue in `ScanStore`, running value tally
- [ ] `MultiScanQueueView.swift` — list + total value + "Save All"
- [ ] Fallback: "Search manually" if scan fails

**Both platforms:**
- [ ] Pricing comps in card detail (Radish Price Guide + eBay sold listings)
- [ ] Box lookup page (Hobby, Double Mega, Jumbo — eBay sold listings)

---

### M4 — Book Mode (Rules, Strategy, Deck Builder)
**Goal:** In-app rulebook, per-card strategy, and deck builder using your collection.

**Web + iOS:**
- [ ] Rulebook browser — sections, search, deep-link from card detail
- [ ] Per-card strategy tips — "How to play" in card detail
- [ ] Deck builder — full catalog, game rule constraints
- [ ] "My Collection" deck builder mode
- [ ] Archetype templates — starter configurations (offensive, defensive, balanced)
- [ ] Deck sharing — public link
- [ ] Deck value — total comp value based on pricing

---

### M5 (Future) — Discord Trading Channel
**Goal:** Embed BOBA community trading channel in-app.
**Channel:** discord.com/channels/1305710603440095252/1306146115757936650
**Note:** Research Discord Activity SDK vs WebView feasibility before committing.

---

## Session Log

**2026-04-03** — Cowork research phase complete. Card database (17,793 cards, 89.3% image coverage) ready. CLAUDE.md, DECISIONS.md, SCRATCHPAD.md written. M0 setup complete.

**2026-04-03** — M1 web Search Mode built: card grid, search, filters, modal, pagination, R2 image CDN connected. UI redesigned: element glows, treatment ribbons, set badges, missing image placeholder, zoom/pan on modal, power range filter (55–250 actual range), uniform stat cell sizing. Font system consolidated from 5 families to 3 (Bebas Neue / Russo One / Chakra Petch). Wordmark redesigned with centered layout. Pricing comps + box lookup deferred to M3.
