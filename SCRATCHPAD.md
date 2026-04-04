# BOBA Playbook — Project Scratchpad

## Current State

- **Status**: M1 complete on both platforms (minus pricing comps + box lookup, deferred to M3)
- **Active milestone**: M2 — Collection Mode
- **Last session**: 2026-04-03 — iOS Search Mode built from scratch; web Search Mode polished; app icons, favicons, PWA fixes, filter UX improvements
- **Open questions**:
  - eBay pricing API — does CORS allow direct client calls, or do we need a proxy?
  - Rules/strategy content for Book Mode — source? (manual entry, PDF parse, etc.)

---

## Feature Parity Status

✅ Complete on both | 🌐 Web only | 📱 iOS only | ⏳ Planned | ❌ Deferred

| Feature | Web | iOS | Notes |
|---|---|---|---|
| Search Mode (card browser) | ✅ | ✅ | M1 complete on both — parity gate cleared |
| App icon + branding | ✅ | ✅ | XOXO logo, BOBA Playbook wordmark, bolt.square Play tab |
| Collection Mode (portfolio) | ⏳ | ⏳ | M2 |
| Scan Mode (camera OCR) | ❌ | ⏳ | M3 — iOS only by design |
| Book Mode (rules + decks) | ⏳ | ⏳ | M4 |
| Discord Trading Channel | ❌ | ❌ | M5 — future, pending research |

---

## Milestones

### M0 — Project Setup ✅ COMPLETE
- [x] Card data JSONs in `assets/data/` (display-cards.json, cards-head.json, categories.json, search-index.json)
- [x] Images on Cloudflare R2 (`full/` + `thumbs/` tiers) — 10,751 images, 89.3% coverage
- [x] Supabase project created, schema applied, URL + anon key saved
- [x] CLAUDE.md, DECISIONS.md, SCRATCHPAD.md filled in
- [x] Xcode project at repo root (`BOBAPlaybook`, no spaces, iOS 26.4 deployment target)
- [x] GitHub Pages live at https://bhwilkoff.github.io/BOBA-Playbook/
- [x] `.env.local` created with SUPABASE_URL, SUPABASE_ANON, CDN_BASE

---

### M1 — Search Mode (Read-Only Card Browser) ✅ COMPLETE (both platforms)

**Goal:** Users can browse, search, and filter all BOBA cards with images.

**Web:** ✅ Complete
- [x] Card grid — lazy-load thumbs, IntersectionObserver pagination (60 per page)
- [x] Search bar — instant results via `search-index.json`, debounced
- [x] Filter panel — collapsible on mobile (hidden by default, toggle button with active badge), always visible on desktop; element pills, set/treatment selects, power range (min/max + presets)
- [x] Card detail modal — full art (pinch/scroll/drag zoom), all stats, athlete bio
- [x] No-image placeholder — branded "BOBA PB / Image Pending" with element tint
- [x] Treatment ribbons on card grid tiles (Battlefoil, Superfoil, Blizzard, etc.)
- [x] Element-reactive glows, set badges, modal element gradient
- [x] Font system — Bebas Neue / Russo One / Chakra Petch
- [x] App icon — XOXO logo (assets/icons/); favicon, apple-touch-icon, PWA manifest icons
- [x] PWA — manifest with scope, 404.html redirect, add-to-homescreen support
- [x] Image display — loads any card with imageFile regardless of imageAvailable flag
- [ ] Pricing comps in card detail — deferred to M3
- [ ] Box lookup page — deferred to M3

**iOS:** ✅ Complete
- [x] Card grid — `LazyVGrid` 2-column, thumb images from R2 CDN
- [x] Progressive loading — `cards-head.json` (500 cards) loads synchronously in `init()` for instant first frame; `display-cards.json` (12k cards) loads in background `.background` priority task
- [x] Search — `.searchable` modifier, debounced filter (120ms)
- [x] Filter sheet — bottom sheet (`.presentationDetents`), element multi-select, set/treatment pickers, power range with presets, has-image toggle, clear all
- [x] Card detail view — push navigation, full art from CDN, pinch/drag zoom (1–6x), element gradient, stats grid, athlete inspiration
- [x] No-image placeholder — branded, element-tinted
- [x] `BOBAWordmark` — inline nav bar wordmark ("BOBA" orange + "Playbook" white, Bebas Neue)
- [x] Custom fonts — programmatic registration via `CTFontManagerRegisterFontsForURL` at app launch
- [x] App icon — XOXO logo (1024px in asset catalog, all appearances)
- [x] URLCache — 100MB memory / 500MB disk for AsyncImage persistence across sessions
- [x] Play tab — `bolt.square.fill` SF Symbol
- [x] Image display — loads any card with `imageFile` regardless of `imageAvailable` flag
- [ ] Pricing comps in card detail — deferred to M3
- [ ] Box lookup — deferred to M3

**Parity gate:** ✅ Cleared. Both platforms complete (minus deferred pricing/box lookup).

---

### M2 — Collection Mode (Auth + Portfolio Tracker) 🔨 IN PROGRESS
**Goal:** Logged-in users track owned cards with designations and a value dashboard.

**Designations (5):** Personal · For Sale · For Trade · Wanted · Grails
**Collection model:** one tile per unique `card_number`; multiple physical copies shown on detail page.

**iOS:** ✅ Complete
- [x] `Config.swift` — Supabase URL + anon key (fill in from .env.local before building)
- [x] `UserCard.swift` — model with 5 designations, snake_case CodingKeys for Supabase
- [x] `SupabaseClient.swift` — REST API: auth (email/pass, Apple id_token), user_cards CRUD, Keychain session
- [x] `AuthManager.swift` — @Observable, Sign in with Apple + email/password, Keychain restore on launch
- [x] `CollectionStore.swift` — @Observable, load/add/update/delete, derived queries (isOwned, isWanted, totalPurchaseValue)
- [x] `SignInView.swift` — Sign in with Apple button + email/password form, mode toggle sign in/create account
- [x] `AddToCollectionSheet.swift` — full add form (designation, condition, grade, serial, price, notes)
- [x] `CollectionView.swift` — designation tabs, card list (one tile per card_number), value summary header
- [x] `CollectionCardDetailView.swift` — all copies with swipe-delete/edit; variations panel (other hero printings)
- [x] `EditCollectionEntrySheet.swift` — inline edit for an existing entry
- [x] `ProfileView.swift` — signed in (stats, sign out) / signed out (sign in CTA)
- [x] `CardDetailView.swift` — "+" / checkmark toolbar button → AddToCollectionSheet or SignInView
- [x] `ContentView.swift` — Collection and Profile tabs wired to real views
- [x] `BOBAPlaybookApp.swift` — AuthManager + CollectionStore injected as @Environment

**⚠️ Before first build:** Fill in `BOBAPlaybook/Config.swift` with your Supabase URL and anon key from `.env.local`

**⚠️ Supabase migration needed (run in SQL editor):**
```sql
ALTER TABLE user_cards DROP CONSTRAINT IF EXISTS user_cards_designation_check;
ALTER TABLE user_cards ADD CONSTRAINT user_cards_designation_check
  CHECK (designation IN ('personal','for_sale','for_trade','wanted','grails'));
DROP POLICY IF EXISTS "own rows" ON user_cards;
CREATE POLICY "select own cards" ON user_cards FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "insert own cards" ON user_cards FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "update own cards" ON user_cards FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "delete own cards" ON user_cards FOR DELETE USING (auth.uid() = user_id);
```

**⚠️ Apple Sign In setup (Apple Developer Console):**
1. App Services → Identifiers → your App ID → Enable "Sign In with Apple"
2. Supabase dashboard → Authentication → Providers → Apple → add Services ID + key

**Web:** ⏳ Pending
- [ ] Auth flow (Supabase JS client: email/password)
- [ ] "Add to Collection" button in card detail modal
- [ ] My Collection view — designation tabs, card list
- [ ] Value dashboard
- [ ] Profile / sign out

**Parity gate:** Both platforms complete before M3 starts.

---

### M3 — Scan Mode (iOS) + Pricing Comps (both)
**Goal:** Camera card detection on iOS; live pricing on both platforms.

**iOS only:**
- [ ] `ScanView.swift` — camera preview (`AVCaptureSession`) with card guide overlay
- [ ] `CardScanner.swift` — Vision OCR pipeline, card number regex, `display-cards.json` matching
- [ ] Card detection overlay — border animates when card detected
- [ ] `ScanResultView.swift` — matched card detail sheet with "Add to Collection"
- [ ] Multi-card queue mode — scan queue in `ScanStore`, running value tally
- [ ] `MultiScanQueueView.swift` — list + total value + "Save All"
- [ ] Fallback: "Search manually" if scan fails

**Both platforms:**
- [ ] Pricing comps in card detail (Radish Price Guide + eBay sold listings)
- [ ] Box lookup page (Hobby, Double Mega, Jumbo — eBay sold listings)

---

### M4 — Play Mode (Rules, Strategy, Deck Builder)
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

**2026-04-03** — M1 web Search Mode built: card grid, search, filters, modal, pagination, R2 image CDN connected. UI redesigned: element glows, treatment ribbons, set badges, missing image placeholder, zoom/pan on modal, power range filter, uniform stat cell sizing. Font system consolidated (Bebas Neue / Russo One / Chakra Petch). Wordmark redesigned. Pricing comps + box lookup deferred to M3.

**2026-04-03** — iOS M1 Search Mode built from scratch. Key files: Card.swift (model), CardStore.swift (two-phase progressive loading), SearchView/CardGridItemView/CardDetailView/FilterSheetView (search UI), BOBAWordmark.swift (inline nav wordmark), CardImageView.swift (AsyncImage + placeholder), CDN.swift (R2 URL helpers), Design.swift (full token library). Fonts registered programmatically via CoreText. Fixed bvId nullable decode bug. Resolved Xcode 16 PBXFileSystemSynchronizedRootGroup auto-discovery (files must be in BOBAPlaybook/ folder). Resolved JSONDecoder blocking on MainActor (Task.detached). Removed blocking PropertyListEncoder cache (was causing 30-45s load). Two-phase loading: synchronous head load in init() + background full load.

**2026-04-03** — Web + iOS polish pass. App icon (XOXO BOBA orange/black logo) applied to iOS asset catalog and web (favicon SVG/PNG, apple-touch-icon, PWA manifest icons). Rules tab renamed to Play with bolt.square.fill icon (both platforms). BOBA Playbook wordmark in iOS nav bar. iOS filter sheet: bottom sheet with element multi-select, power presets, clear all. Web filters: collapsible on mobile (toggle button with active badge, filter panel outside sticky header, scrolls with content). Fixed imageAvailable flag false negatives on both platforms — now loads any card with imageFile. PWA 404 fix: 404.html redirect + manifest scope. cards-slim.json removed (replaced by display-cards.json + cards-head.json split). Legacy /ios/ scaffold removed.

**2026-04-03** — M2 iOS Collection Mode built. New files: Config.swift (Supabase credentials), UserCard.swift (model, 5 designations), SupabaseClient.swift (REST auth + CRUD, Keychain session), AuthManager.swift (@Observable, Sign in with Apple + email/password), CollectionStore.swift (@Observable, load/CRUD/derived queries), SignInView.swift, AddToCollectionSheet.swift, CollectionView.swift (designation tabs + value summary), CollectionCardDetailView.swift (copies + variations panel), EditCollectionEntrySheet.swift, ProfileView.swift. Updated: CardDetailView (+ button in toolbar), ContentView (real Collection/Profile tabs), BOBAPlaybookApp (AuthManager + CollectionStore injected). Schema migration SQL in supabase_schema.sql. ⚠️ Fill in Config.swift + run migration + enable Apple Sign In before building.
