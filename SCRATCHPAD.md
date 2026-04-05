# BOBA Playbook — Project Scratchpad

## Current State

- **Active milestone**: M3 — Scan Mode (iOS) + Pricing Comps (both)
- **Last session**: 2026-04-05 — Sealed products fully synced: 45 products, 36 images on R2. JSON patched across all files (cards.json, sealed_products.json, display-cards.json, cards-head.json).
- **Open questions**:
  - eBay pricing API — does CORS allow direct client calls, or do we need a proxy?
  - Rules/strategy content for Play Mode — source? (manual entry, PDF parse, etc.)

---

## Feature Parity Status

✅ Both | 🌐 Web only | 📱 iOS only | ⏳ Planned | ❌ Deferred

| Feature | Web | iOS | Notes |
|---|---|---|---|
| Search Mode | ✅ | ✅ | M1 complete |
| App icon + branding | ✅ | ✅ | XOXO logo, wordmark, PWA |
| Mobile Safari layout | ✅ | n/a | Body flex column, no viewport-fit=cover |
| Collection Mode | ⏳ | ✅ | M2 iOS done; web deferred, runs alongside M3 |
| Scan Mode (camera OCR) | ❌ | ✅ | M3 iOS complete — iOS only by design |
| Pricing comps | ⏳ | ✅ | M3 iOS done (needs Worker deploy); web pending |
| Play Mode (rules + decks) | ⏳ | ⏳ | M4 |
| Discord Trading Channel | ❌ | ❌ | M5 — future |

---

## Milestones

### M0 — Project Setup ✅ COMPLETE
Card data JSONs, R2 images (89.3% coverage), Supabase schema, GitHub Pages live, Xcode project at repo root.

---

### M1 — Search Mode ✅ COMPLETE (both platforms)

**Web:** Card grid (IntersectionObserver pagination, 60/page), instant search via search-index.json, collapsible filter panel (element pills, set/treatment selects, power range + presets), card detail modal (zoom/pan, full stats, athlete bio), CDN thumb/full images, treatment ribbons, element glows, branded placeholder. PWA with 404 redirect. XOXO app icon + favicon.

**iOS:** LazyVGrid 2-column, two-phase progressive loading (cards-head.json sync → display-cards.json background), .searchable + debounce, filter bottom sheet, pinch/drag zoom detail (1–6x), CDN images, URLCache (100MB/500MB).

---

### M2 — Collection Mode 🔨 IN PROGRESS

**Goal:** Logged-in users track owned cards with 5 designations and a value dashboard.
**Designations:** Personal · For Sale · For Trade · Wanted · Grails

**iOS:** ✅ Complete
Auth (email/password + Sign in with Apple), Keychain session, Supabase REST CRUD, CollectionView (designation tabs + value summary), CollectionCardDetailView (copies + variations panel), EditCollectionEntrySheet, ProfileView. Injected via `@Environment` in BOBAPlaybookApp.

**⚠️ Before building:** Fill `BOBAPlaybook/Config.swift` with Supabase URL + anon key from `.env.local`.

**⚠️ Supabase SQL migration** (run in SQL editor if not done):
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

**⚠️ Apple Sign In** (Apple Developer Console): App Services → Identifiers → your App ID → Enable "Sign In with Apple". Then Supabase → Auth → Providers → Apple.

**Web:** ⏳ Pending (building alongside M3)
- [ ] Auth flow (Supabase JS client: email/password + magic link)
- [ ] "Add to Collection" button in card detail modal
- [ ] My Collection view — designation tabs, card list
- [ ] Value dashboard
- [ ] Profile / sign out

---

### M3 — Scan Mode (iOS) + Pricing Comps (both) 🔨 IN PROGRESS

**iOS Scan:** ✅ Complete
- [x] `ScanStore.swift` — `@Observable` queue, multi-card mode, dedup by cardNumber
- [x] `CardScanner.swift` — AVFoundation + Vision OCR, 3-frame stability, 2s cooldown
- [x] `CameraPreviewView.swift` — `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer`
- [x] `ScanDetectionChipView.swift` — bottom chip with thumb, name, power, element glow
- [x] `ScanView.swift` — camera layer, guide frame (280×200), top bar, multi/single toggle
- [x] `ScanQueueView.swift` — queue list, swipe-delete, Save All, Clear All
- [x] `ContentView.swift` — Scan tab added as Tab 2 (`camera.viewfinder`)
- [x] `BOBAPlaybookApp.swift` — `ScanStore` injected via `@Environment`
- [x] `Info.plist` — `NSCameraUsageDescription` added

**Pricing — iOS:** ✅ Complete (pending Worker deploy)
- [x] `PricingService.swift` — actor, Cloudflare Worker proxy, 1hr in-memory cache
- [x] `SafariView.swift` — `SFSafariViewController` wrapper for Radish deep link
- [x] `PricingSection.swift` — LOW/AVG/HIGH grid, 7d/30d/90d picker, Radish link
- [x] `CardDetailView.swift` — `PricingSection` added after athlete inspiration block
- [x] `Config.swift` — `WorkerConfig.ebayProxyURL` placeholder ready

**⚠️ Worker deploy needed before pricing shows in app:**
1. `cd workers/ebay-proxy`
2. `npx wrangler secret put EBAY_APP_ID` → paste `BenWilko-BOBAPlay-PRD-24c5abbf0-7a77c68d`
3. `npx wrangler deploy`
4. Copy the Worker URL → paste into `BOBAPlaybook/Config.swift` → `WorkerConfig.ebayProxyURL`

**Pricing — Web:** ⏳ Pending
- [ ] Add pricing section to web card detail modal (`js/app.js` + `css/styles.css`)
- [ ] Call Worker endpoint from browser JS (same Worker, CORS enabled)

**Both platforms:**
- [ ] Box lookup page (Hobby, Double Mega, Jumbo — eBay sold listings)

---

### M4 — Play Mode ⏳ PLANNED
Rulebook browser, per-card strategy tips, deck builder (full catalog + collection mode), archetype templates, deck sharing, deck value.

---

### M5 — Discord Trading Channel ❌ FUTURE
Embed community trading channel. `discord.com/channels/1305710603440095252/1306146115757936650`
Research Discord Activity SDK vs WebView feasibility before committing.

---

## Session Log

**2026-04-03** — M0 complete. Web M1 built: card grid, search, filters, modal, CDN images, PWA, branding. iOS M1 built: two-phase loading, filter sheet, zoom detail. Shared polish: XOXO icon, Play tab, collapsible web filters, imageAvailable bypass.

**2026-04-03** — iOS M2 complete: Supabase auth (email + Apple), CRUD, CollectionView, CollectionCardDetailView, value summary, ProfileView.

**2026-04-04** — Web mobile Safari fixes: header alignment, modal image layout (mobile height, desktop sticky art), profile padding (undefined CSS vars), non-sticky search header, hamburger toggle + iOS hover fix, Play icon SVG. Dynamic Island: removed `viewport-fit=cover`, changed to body flex-column + `main` as scroll container (Bsky Dreams pattern). IntersectionObserver updated to `root: main-content`.

**2026-04-04** — M3 iOS Scan Mode complete: ScanStore, CardScanner (Vision OCR, 3-frame stability), CameraPreviewView, ScanDetectionChipView, ScanView (guide frame, multi/single toggle), ScanQueueView (Save All). Pricing iOS complete: PricingService (actor + 1hr cache), SafariView, PricingSection (LOW/AVG/HIGH, 7d/30d/90d, Radish link), CardDetailView updated. Cloudflare Worker created at workers/ebay-proxy/. ⚠️ Worker still needs deployment — see M3 section for steps.
