# BOBA Playbook — Project Scratchpad

## Current State

- **Active milestone**: M5 — Discord Trading Channel (in progress)
- **Last session**: 2026-04-11 — Three bug fixes. (1) Discord auth restored on both platforms: web had `fab.hidden = true` hardcoded unconditionally in `render()` (js/app.js), blocking the panel and auth flow entirely; iOS had `tradeRoomFAB` defined but removed from the view hierarchy with no `.sheet` wired up (CollectionView.swift). Both restored. Trade Room channel content still requires the bot/Worker to be deployed before messages work. (2) Scan view stale image: `CardImageView` `@State loadedImage` persisted across card changes because `url` changing didn't clear it; added `.onChange(of: url)` to clear immediately. (3) Comprehensive `CardImageView` image-loading overhaul: cancellation errors (URLError.cancelled, Task.isCancelled, CancellationError) no longer set `failed = true`; `failed` moved inside the task branch so `.task` stays in scope and can be retried; `loadID` counter replaces `url` as task identity to enable forced retries; `.onAppear` resets `loadFailed` and increments `loadID` on every appearance so cards retry after scroll-back-in or post-filter-change.
- **Open questions**:
  - Rules/strategy content for Play Mode — source? (manual entry, PDF parse, structured JSON?)
  - Deck builder: local-only or save/share via Supabase?
  - Archetype templates: curated by us, or user-created?

---

## Feature Parity Status

✅ Both | 🌐 Web only | 📱 iOS only | ⏳ Planned | ❌ Deferred

| Feature | Web | iOS | Notes |
|---|---|---|---|
| Search Mode | ✅ | ✅ | M1 complete |
| App icon + branding | ✅ | ✅ | XOXO logo, wordmark, PWA |
| Mobile Safari layout | ✅ | n/a | Body flex column, no viewport-fit=cover |
| Collection Mode | ✅ | ✅ | M2 complete |
| Scan Mode (camera OCR) | ❌ | ✅ | M3 iOS complete — iOS only by design |
| Pricing comps (links) | ✅ | ✅ | M3 complete; Worker deploy still needed for live data |
| Play Mode (rules + decks) | ⏳ | ⏳ | M4 — active |
| Discord Trading Channel | ⏳ | ⏳ | M5 — in progress; needs Worker deploy + Discord redirect URI |

---

## Milestones

### M0 — Project Setup ✅ COMPLETE
Card data JSONs, R2 images (89.3% coverage), Supabase schema, GitHub Pages live, Xcode project at repo root.

---

### M1 — Search Mode ✅ COMPLETE (both platforms)

**Web:** Card grid (IntersectionObserver pagination, 60/page), instant search via search-index.json, collapsible filter panel (element pills, set/treatment selects, power range + presets), card detail modal (zoom/pan, full stats, athlete bio), CDN thumb/full images, treatment ribbons, element glows, branded placeholder. PWA with 404 redirect. XOXO app icon + favicon.

**iOS:** LazyVGrid 2-column, two-phase progressive loading (cards-head.json sync → display-cards.json background), .searchable + debounce, filter bottom sheet, pinch/drag zoom detail (1–6x), CDN images, URLCache (100MB/500MB).

---

### M2 — Collection Mode ✅ COMPLETE (both platforms)

**iOS:** Auth (email/password + Sign in with Apple), Keychain session, Supabase REST CRUD, CollectionView (designation tabs + value summary), CollectionCardDetailView, EditCollectionEntrySheet, ProfileView.

**Web:** Auth modal (email/password + Apple), "Add to Collection" in card detail, My Collection view (designation tabs, card list), ProfileView.

**Designations:** Personal · For Sale · For Trade · Wanted · Grails

---

### M3 — Scan Mode (iOS) + Pricing Comps (both) ✅ COMPLETE

**iOS Scan:** ScanStore, CardScanner (Vision OCR, 3-frame stability), CameraPreviewView, ScanDetectionChipView, ScanView (280×200 guide frame, multi/single toggle), ScanQueueView (Save All / Clear All). QR code on web opens `bobaplaybook://scan` to jump straight to Scan tab (bypasses broken web auth in restricted Safari).

**Pricing — iOS:** PricingService actor (1hr cache), PricingSection (LOW/AVG/HIGH, 7d/30d/90d, Radish + eBay links always visible).

**Pricing — Web:** Radish + eBay links added to card modal. Correct eBay query formula: `"{year} bo jackson battle arena {hero} {treatment} {element}"`. Radish URL uses `card.radishUrl` with programmatic fallback.

**⚠️ Worker deploy still needed before live pricing data appears:**
1. `cd workers/ebay-proxy`
2. `npx wrangler secret put EBAY_APP_ID` → paste `BenWilko-BOBAPlay-PRD-24c5abbf0-7a77c68d`
3. `npx wrangler deploy`
4. Copy the Worker URL → paste into `BOBAPlaybook/Config.swift` → `WorkerConfig.ebayProxyURL`
   Also update `const WORKER_URL` in `js/app.js`.

**Deferred from M3:**
- Box lookup page (Hobby, Double Mega, Jumbo sealed product pricing)

---

### M4 — Play Mode ⏳ ACTIVE

**Content source**: `/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research/unified-cards/docs/M4_PLAY_STRATEGY_COLLECTING_GUIDE.md`
Sourced from official Quick Start Guide, Comprehensive Rules Guide v1, Penalty & Procedure Guide v0, Tournament Rules v0, and 2026 Edition Collector Guide.

**iOS placeholder:** `PlaceholderView` at tab index 2, message: "Rulebook, strategy tips, and deck builder — coming in M4."
**Web placeholder:** Play nav item shows placeholder view.

---

### M4 Content Overview

#### Game Overview
- Best-of-7-Battles game; first to win 4 Battles wins. 3-3 after 7 → Sudden Death.
- Heroes are *inspired by* real athletes (always say "inspired by" — never "is" or "based on")
- Card backs: Heroes = red, Plays = purple, Hot Dogs = green
- Coin flip determines first Honors (right to act first each battle)

#### 3 Game Modes
| Mode | Decks | Summary |
|---|---|---|
| Rookie | Hero only | Pure power comparison, no subs, no plays |
| Substitution | Hero + Hot Dog | Add hand management; substitute by paying 2 Hot Dogs |
| Playmaker | Hero + Hot Dog + Playbook | Full game; tournament standard |

#### Deckbuilding Rules
- **Hero Deck**: Exactly 60 cards; max 6 copies of any single Power value; only 1 copy per variation; up to 6 total of same hero across variations
- **Hot Dog Deck**: Exactly 10 cards; duplicates allowed
- **Playbook**: Exactly 30 Plays; all unique names; Bonus Plays may be added beyond 30
- **SPEC Format**: Hero Deck capped at ≤160 Power; sideboard of up to 45 Plays; swap between games in a match
- **Limited**: Minimum 40-card Hero Deck (instead of 60)

#### Battle Flow (Playmaker)
1. **Reveal** — both players flip Hero simultaneously
2. **Substitution Window** — Honors player decides first; pay 2 Hot Dogs to swap
3. **Play Window** — players alternate playing Play cards (pay Hot Dog cost)
4. **Resolution** — higher Power wins; ties → Sudden Death (unless one Hero is Super weapon type → Super wins)
5. **Cleanup** — draw 1 Play; Honors moves to battle winner

#### Card Types
- **Heroes**: Power 55–250 (234 cards at Power 0 = Hot Dogs/tokens — exclude from standard browsing)
- **Plays**: 275 unique names, 300 total; costs 0–6 Hot Dogs
- **Hot Dogs**: 10-card energy deck; also appears as `cardType: "Hot Dog"` OR hero with `treatment: "Hot Dog"/"Hotdogs"`

#### Weapon Types (element field)
FIRE, ICE, STEEL, BRAWL, GLOW, HEX, GUM, SUPER, ALT. CYBER listed in rules but 0 cards currently.
- **Super** wins ties in Playmaker mode
- Rarity: Brawl/Steel (common) → Fire/Ice (rare) → Glow (ultra rare) → Hex/Gum (secret rare) → Super (1/1)

#### Curated Card Lists (Play Tab Quick Access)
- **WOBA** (Women of BOBA): filter `athleteInspiration` against 17 female athletes — 884 cards
- **Bo Jackson**: `athleteInspiration == "Bo Jackson"` — 147 cards, hero name: BoJax
- **Ken Griffey Jr.**: `athleteInspiration == "Ken Griffey Jr."` — ~76 cards, hero: The Kid
- **Dr. J**: `athleteInspiration == "Julius Erving"` — 70 cards
- **High-value athlete collections**: Cooper Flagg, Paige Bueckers, Aaron Judge, Jordan Love, Kawhi Leonard, Caleb Williams, Aaron Rodgers, etc. (see guide §8.5)
- **By Sport**: Basketball, Football, Baseball, Hockey, Tennis, Golf, Soccer, Swimming, Skiing, Boxing/Celebrity — full athlete-to-sport JSON mapping in guide §8.6
- **By Weapon**: filter `element` field
- All lists should also support combining filters (e.g., WOBA + Fire weapon)

#### Recommended Starter Deck Archetypes (5 curated)
1. **Fire Aggro** — Fire Boost, Fire Crew, Flame Wall, Burning Fever, Eternal Flame, Smitty
2. **Ice Control** — Ice Boost, Ice Crew, Icy Shield, Frozen Resolve, Frozen Lineup, Unbreakable Ice
3. **Steel Wall** — Steel Boost, Steel Crew, Steel Defense, Steel Shield, Chrome Will, Steel Cage
4. **Mixed Toolbox** — Weapon Mixer, Weapon Tangle, Brothers In Arms, Edge Rush
5. **Economy/Attrition** — Trash Bandit, Victory Dinner, Bun Shortage, Mutually Assured Dogstruction

#### Key Strategy Points
- 6-per-power-value rule requires spreading power curve across levels
- Plays are classified: Tempo (immediate boost), Value (ongoing), Disruption (deny opponent), Economy (resource recovery)
- Notable game-changers: Edge Rush (5 cost, set to 5 above opponent), Deadline Deal (3 cost, swap powers), By Any Means Necessary (6 cost, search + play any Play free)
- Don't substitute reflexively — each sub costs 2 of only 10 Hot Dogs
- Track opponent Hot Dog count and play count (30 total + bonus)

#### Data Quality Notes (handle in M4)
- Normalize "Bojax" → "BoJax" in display
- Athlete spelling variants to treat as same: McCaffrey/McCaffery, Giannis (3 variants), Tatis/Tatís, Bobby Witt Jr/Jr., AJ Brown/A.J. Brown, Paulo/Paolo Banchero, Wembanyama/Wembenyama, Emilio/Emillio Estevez, "Inspried byKatie Ledecky" → Katie Ledecky, Chastain/Brandi Chastain, MIke Evans → Mike Evans
- Exclude Power 0 cards from standard Hero browsing
- SPEC format not yet in app — note it exists in rules reference

#### Collecting Guide (Play Tab Section)
- Rarity tiers: Base Set → Battlefoils (GLBF/RAD most common) → Mid-rarity foils → Color BFs → Premium (Superfoil, Inspired Ink) → Chase (Serialized, Kanjifoil, Billy Cameo Alt Arts)
- 2026 Edition new treatments: Logofoil, Colosseum Battlefoil, Great Grandma Linoleum Battlefoil
- Variations: First Edition (8,926 cards), 2026 Edition (880), Debut (70 each), Unmasked (70 each)

#### Tournament Reference (Play Tab Section)
- REL levels: Casual, Competitive, Professional
- Match = best-of-3 Games (or 5 at Professional)
- Penalty levels: Caution → Warning → Game Loss → Match Loss → Disqualification
- Full infraction table in guide §11

#### Play Tab UI Plan (from guide Appendix C)
1. **Rules** — tabbed Rookie/Substitution/Playmaker, progressive disclosure
2. **Strategy** — expandable guides + archetype templates
3. **Curated Lists** — preset filter buttons (WOBA, Bo Jackson, etc.) + browsable by sport/weapon
4. **Collecting** — rarity tier visualization, set checklists
5. **Tournament Reference** — collapsible penalty/rules quick-ref

#### Deck Builder Persistence (Decision 021)
- **Templates** (Fire Aggro, Ice Control, etc.) — static/local, no auth required
- **User-created decks** — saved to Supabase `decks` + `deck_cards` tables, requires sign-in
- Unauthenticated users can browse templates but see sign-in prompt to save

#### Open/Deferred
- Per-card strategy tips: guide provides Play-specific synergy info; per-hero tips not yet authored

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

**2026-04-07** — Multi-bug fix session: (1) Mod account system added — `user_profiles` + `card_corrections` + `card_image_overrides` tables in Supabase schema; iOS `AuthManager` fetches role post-auth; `ModPanelView` + `ModCardEditSheet` added; web `api.js` exposes role/correction/image methods; `collection.js` profile view shows role badge + mod panel link. (2) iOS play cost removed from `CardDetailView`. (3) Web hero associations removed from card modal. (4) "Each battle - all phases" label centered + top padding. (5) Timestamp bug fixed — `addUserCard` and `updateUserCard` now use ISO8601-encoded `JSONEncoder`. (6) CollectionView "PORTFOLIO VALUE" now shows estimated market value when available, falls back to cost basis; web collection stats show separate "Est. Value" + "Cost Basis". (7) "Has image" dedicated button removed from both platforms; filter stays in filter sheet/panel.

**2026-04-05** — M3 web pricing links complete: correct eBay query formula with treatment map + set year map, Radish fallback URL construction, both buttons always visible (not conditional on sale data). QR code changed from `?rt=TOKEN` web auth (broken in restricted Safari view) to `bobaplaybook://scan` deep link; iOS app added `onOpenURL` handler + `TabView(selection:)` binding to jump to Scan tab. iOS sealed product ordering fixed: `applyFilters()` now called in `init()` (was bypassing it), sealed-tier added to sort comparator. Starting M4 — Play Mode.

**2026-04-11** — Three bug fixes. (1) Discord auth restored on both platforms: web `fab.hidden = true` was hardcoded unconditionally in `app.js` `render()`; iOS `tradeRoomFAB` was defined but removed from view hierarchy with no `.sheet` wired — both restored in CollectionView.swift. (2) Scan view stale image: `CardImageView` `loadedImage` persisted across card changes; added `.onChange(of: url)` to clear it immediately. (3) Comprehensive `CardImageView` overhaul: cancellation no longer sets `failed`; `failed` moved inside the task branch; `loadID` counter forces retries without URL change; `.onAppear` resets and retries on every appearance (covers scroll-back-in and post-filter-change).

**2026-04-11** — Database quality fixes from TestFlight beta feedback. (1) Search index migrated from cardNumber→bobaId keying in `reconcile_all.py` step9: all indexes (tokenIndex, byElement, bySet, byTreatment, byCardType, byHero, byPowerRange, hasImage) now store bobaIds — eliminates cross-hero search contamination (e.g. "Spider" returning BrockNess). (2) searchTokens builder fixed: removed `bv_name` from token sources so BV cross-reference data doesn't leak into wrong cards' tokens. (3) Step execution order fixed: steps 8/9/10 (categories, search-index, summary) now run AFTER step 12 (sealed products), so 8 sealed-product-only sets appear in categories.json. (4) categories.json and step8 migrated from cardNumber to bobaId in sample references. Web app `computeResults()` must be updated to resolve bobaIds instead of cardNumbers (detailed migration guide in COWORK.md). iOS unaffected — filters against in-memory array, doesn't use search-index.json. Colosseum Battlefoil confirmed as correct treatment name (786 cards); UX display enhancement noted for Claude Code.
