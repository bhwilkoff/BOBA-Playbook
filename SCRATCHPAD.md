# BOBA Playbook — Project Scratchpad

## Current State

- **Active milestone**: M4 — Play Mode (M3.5 fully complete and deployed)
- **Last session**: 2026-04-16 — Web deck builder + practice polish (8-item feedback pass): Save/Load deck (auth-gated Supabase, boba_id+card_type schema), SPEC format moved to last, card popup closes after add, CSV "Downloaded!" feedback, bench cards show card images with power overlay, CPU subs at ≥10 deficit (was 20) + 30% opportunistic upgrade, ghost interface fixed (hidden attribute CSS specificity), saved decks panel in deck list header. iOS: interactive HD pips, bench selection+sub button, effect power display, drawPlayCard(), allCardsPool for replay, 6-card bench.
- **⚠️ Pending Claude Code handover** — Stage 1+2 bobaId rename complete on Cowork side. R2 + git commit pending. See `STAGE12_HANDOVER.md` and `STAGE12_R2_MANIFEST.json` at repo root. Bundles in `assets/data/` and `BOBAPlaybook/` are already updated; R2 just needs the rclone batch.
- **Open questions**:
  - Strategy hints: deck evaluation panel in deck builder (pull from research docs)
  - Practice battle icons: user wants redesigned icons for the playmat (source needs clarification)
  - Discord M5: needs bot added to server before re-enabling the hidden FAB

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
| Pricing comps (links) | ✅ | ✅ | M3 complete |
| Buy Now (active listings) | ✅ | ✅ | M3.5 complete — Worker deployed at boba-ebay-proxy.benwilkoff.workers.dev |
| Market Feed (recent sales) | ❌ | ❌ | Deferred — code removed. Research complete (SerpApi), revisit when eBay API scope approved. |
| Play Mode (rules + decks) | ⏳ | ⏳ | M4 active — Deck Builder + Practice scaffolded; templates need real bobaIds; Supabase migration pending |
| Discord Trading Channel | ⏳ | ⏳ | M5 — hidden (code intact); needs Discord bot added to server |

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

**Worker:** Deployed at `boba-ebay-proxy.benwilkoff.workers.dev`. URL stored in `BOBAPlaybook/Config.swift` (`WorkerConfig.ebayProxyURL`) and `const WORKER_URL` in `js/app.js`.

**Deferred from M3:**
- Box lookup page (Hobby, Double Mega, Jumbo sealed product pricing)

---

### M3.5 — Pricing Enhancements ✅ COMPLETE

**Feature A: Dual-section pricing ("Buy Now" + sold history) ✅**
- Worker deployed: parallel Radish fetch + eBay OAuth, Browse API for active listings, dual `sold`/`active` response shape, cache v10
- Web: "RECENT SALES" + "BUY NOW" sections with distinct styling
- iOS: `PricingSection.swift` renders both sections

**Feature B: Market Feed ❌ DEFERRED + cleaned up**
- All Market Feed code removed: `MarketFeedView.swift`, `RecentSale.swift`, `fetchRecentSales()`, feed HTML/CSS/JS, Worker cron handler
- Research preserved: SerpApi eBay Search API ($75/mo) is recommended approach when we revisit. Full details: `BOBA_Sold_Data_Research.md`.

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

**2026-04-03** — M0 complete. M1 complete on both platforms: card grid, search, filters, modal, CDN images, PWA, branding (web); two-phase loading, filter sheet, zoom detail (iOS). XOXO icon, Play tab, imageAvailable bypass.

**2026-04-03** — M2 complete on both platforms: Supabase auth (email + Apple), CRUD, CollectionView (designation tabs + value summary), CollectionCardDetailView, ProfileView.

**2026-04-04** — Web mobile Safari layout fixed: body flex-column, no `viewport-fit=cover`, IntersectionObserver uses `main-content` root (Bsky Dreams pattern). M3 iOS Scan Mode complete: Vision OCR, 3-frame stability, multi/single toggle, Save All queue. Cloudflare Worker created.

**2026-04-05** — M3 web pricing links complete: eBay query formula, Radish fallback, both buttons always visible. QR code changed to `bobaplaybook://scan` deep link. iOS sealed product ordering fixed.

**2026-04-07** — Mod account system: `user_profiles` + `card_corrections` + `card_image_overrides` tables, role fetch post-auth, ModPanelView (iOS) + mod panel link (web). Multiple bug fixes: timestamp encoding, collection value display, filter panel cleanup.

**2026-04-11** — Bug fixes: `CardImageView` overhaul (`loadID` counter, `.onAppear` retry, cancellation no longer sets `failed`). Scan view stale image cleared on URL change. Discord FAB restored on both platforms.

**2026-04-11 (Cowork)** — Database quality: search-index.json migrated to bobaId keying — eliminates cross-hero contamination. `bv_name` removed from searchTokens. Step execution order fixed (sealed products before categories/search-index).

**2026-04-12 (Cowork)** — Set taxonomy overhaul: coarse "Alpha"/"Griffey" set names → 10 collector-facing names using Radish as primary source. Treatment normalization: 56→51 unique treatments. ~1,866 cards had bobaId changes. All JSON bundles regenerated.

**2026-04-12** — Discord PKCE auth fixed: added `/discord/token` Worker endpoint to proxy token exchange with `client_secret`. Admin panel user management: Supabase RPC `get_admin_user_stats()` (SECURITY DEFINER). Set taxonomy integrated into OCR_SET_HINTS and SET_SLUG_MAP.

**2026-04-12** — M3.5 complete: Feature A (dual-section pricing / Buy Now) deployed. Feature B (Market Feed) built then deferred — all code removed. Worker redeployed without cron trigger.

**2026-04-13** — M4 Play tab polish: fixed play card type examples (correct filenames/costs), expanded Collect tab on both platforms (rarity tiers, variations, treatments). Hid Discord FAB without removing code. iOS card detail image load: show cached thumb instantly while full-res loads. Removed zoom hint text on both platforms. Updated DECISIONS.md with values/principles framing.

**2026-04-14** — M4 Play Mode: Deck Builder + Practice Battle implemented on both platforms. iOS: DeckBuilderStore + DeckBuilderView (card browser, grouped hero deck, play sections, validation, template gallery, export sheet), PracticeStore (game state machine, CPU AI), PracticeSetupView, PracticeView (landscape playmat, 7 battle columns, phase disclosure). PlayView toolbar: Deck Builder icon left, Practice icon right of wordmark. Web: floating FABs, deck builder modal (card browser with add/remove, deck list, 5 templates, validation errors, export), practice modal (mode select, deck choice, 7-column playmat, phase advance, match over screen). SupabaseClient: saveDeck + fetchDecks. supabase_schema.sql: M4 migration comments.

**2026-04-13 (Cowork) — Image-content collision incident + guard.** User reported Caliber #24 displaying D-Harp's art. Investigation showed cards.json was correct; the bug was binary content on R2 (identical md5 on two different filenames). Md5 scan found 35 catalog-wide cross-card content collisions. 32 pairs auto-fixed locally by regenerating optimized+thumb from distinct source images. 3 pairs remain source-level duplicates needing art re-download (`BLBF-174 Highway to Helton / Shepherd`, `BLBF-95 D-Harp / Jeesaw`, `BLBF-120 Zephyr / Bandelero`). Added content-collision guard to `reconcile_all.py::step11_optimize_images` — writes `unified-cards/data/image_collisions.json` when md5s collide across distinct cards (DECISIONS.md #026). R2 re-upload of 70 fixed files pending user action (see `R2_REUPLOAD_MANIFEST.md` + `R2_REUPLOAD_LIST.txt` in research project).

**2026-04-13 (Cowork) — 3 source-level pairs routed to missing-art queue.** After verifying the correct Griffey Edition Blizzard Battlefoil art does not exist publicly (Radish, the card source, Cardeio all serve the Alpha Edition art or a placeholder), the 3 remaining source-level pairs were reclassified from "wrong art on R2" to "awaiting art" and added to the existing eBay art-recovery queue. Actions: deleted 9 wrong image files (3 cards × 3 tiers) from the research project; set `imageFile=null, imageSource=null, imageAvailable=false` in `cards.json` for BLBF-95 D-Harp, BLBF-120 Zephyr, BLBF-174 Highway to Helton; regenerated `missing-cards.json` (2,996 cards now pending art), `cards-slim.json`, `cards.csv`, `categories.json`, `search-index.json`; copied all catalog bundles + `display-cards.json` + `cards-head.json` into this repo's `assets/data/` and `BOBAPlaybook/`; collision guard now prints zero cross-card collisions. `R2_REUPLOAD_MANIFEST.md` updated accordingly. Claude Code: see "⚠️ Pending Claude Code handover" in the **Current State** block at the top — the remaining step is the R2 sync + git commit; the bundles themselves are done.

**2026-04-13 (Cowork) — Stage 1+2 bobaId rename: all catalog images renamed to `{bobaIdSlug}.webp`.** User-authorized initiative to enforce "One Image per Card, One ID per Card" all the way down to the R2 object key. Previously, `reconcile_all.py` linked images via `variety_key` (a filename-stem hash) rather than bobaId, which is why 0 of 14,743 imageFiles contained bobaId as a substring. **Phase A**: renamed every catalog-referenced image on disk (14,743 standard + 36 sealed) to `{bobaIdSlug}.webp` across `images/`, `images-optimized/`, `thumbs/`, and the sealed tiers. **Phase B**: scanned 4,217 unmapped disk files and claimed 1,271 that had exactly one bobaId-strict match to an unmapped card (481 Plays + 47 HotDogs + 743 Heroes). Coverage 82.9% → **90.3%**. Non-Hero missing dropped 554 → 26 (95% recovery). Collision guard: 0 cross-card md5 collisions (only 15 whitelisted sealed Box↔Case pairs). Regenerated all bundles (cards.json, cards-slim.json, categories.json, search-index.json, missing-cards.json, display-cards.json, cards-head.json) and copied into this repo. **Claude Code action required**: R2 rename via `STAGE12_R2_MANIFEST.json` (14,743 renames × 2 tiers = 29,486 ops) + 1,271 new uploads × 2 tiers = 2,542 new ops. Full instructions in `STAGE12_HANDOVER.md` at repo root. App code needs NO refactor — `thumbUrl(card.imageFile)` and `fullUrl(card.imageFile)` just work once R2 objects match cards.json.
