# BOBA Playbook — Project Scratchpad

## Current State

- **Active milestone**: M4 — Play Mode (M3.5 fully complete and deployed)
- **Last session**: 2026-04-15 (Claude Code) — **Tier A executor ops shipped on both platforms + legality gate for hard-gated cards.** Added 9 ops to web (`js/practice.js`) and iOS (`BOBAPlaybook/Store/PlayEffects.swift`): `swap_hd_counts`, `play_cost_delta` (with scope-based consumption), `shuffle_hand_into_deck`, `shuffle_from_discard_to_deck`, `discard_top`, `discard_hand_all`, `power_reset`, `add_top_hero_power_to_self`, `reclaim_used_play`. Added `effectiveCost(card, side)` helper on both platforms that consumes single-use `next_play_self` mods on play. Added `entryHasUnknownOps(entry)` + honesty note in play-card popup (web: pill in `pmShowPlayCardPopup`; iOS: badge in `PracticePlaysPanel.cardDetail`) — surfaces "⚠ Some effects not yet simulated" for cards whose entry still contains unimplemented ops. Prior fix that landed earlier in the session: `requires` legality gate + 5 hard-gated entries (`Hot Dog Stock Exchange`, `2010's ERA`, `Fairweather Fan`, `Incendiary Dog`, `Surging Power`). Documented Tier B (15 ops) + Tier C (18 ops) remaining gaps in SCRATCHPAD.md "Unknown Ops Tiering" section below. `node -c js/practice.js` clean.
- **Prior session**: 2026-04-15 (Claude Code) — Structured `play-effects.json` executor wired on **both platforms**, replacing the fragile regex resolver. Web: ~400 LOC executor block in `js/practice.js` (pmLoadPlayEffects, pmEvalFormula/Metric/Condition, pmExecStep, pmExecStructured, plus PM.applyContinuousPersistents) — `PM.playerPlayCard` and `PM.cpuDoPlay` now try the structured path first and fall back to the regex resolver only when no entry exists or `hasEffect` is false. iOS: new `BOBAPlaybook/Store/PlayEffects.swift` (529 LOC, JSONSerialization-based executor mirroring JS), `PracticeStore.playerPlayCard`/`cpuPreparePlayTurn` wrap legacy `resolveEffect` with a structured-first path, persistents installed and applied at reveal. Validated against all 383 entries in node — 0 runtime errors; one defensive guard added for `PM.battles` access. CPU perspective handled by re-mapping `selfDelta`/`oppDelta` at the call site. Forward-compat preserved: unknown ops log to `unknownOps` and skip without aborting. Web swiftc-typecheck clean; `node -c js/practice.js` clean.
- **Prior session**: 2026-04-15 (Cowork v3 sync) — Claude Code completed v3 pass: **all new v2 vocabulary PROMOTED** into `PLAY_EFFECTS_SCHEMA.md` (runtime will implement Cowork's names; a few of Claude Code's earlier proposed names were renamed to Cowork's). User sourced the Lucky Seven ability text ("Roll a die two times; if sum is 7 → Hero +100; else discard 1 random Hero from hand"), Claude Code authored it into the bundles. Cowork then synced Lucky Seven into `V2_OVERRIDES` in `scripts/author_play_effects.py` and updated `build()` to honor spec-provided `cost`/`ability` when cards.json has them blank. Final state: **383/383 structured (100%), 0 note-only**. Web + iOS byte-identical at md5 `b36d7b49746f5da5f3427afd90ab8ed6`, 210,519 bytes. Regeneration is stable across reruns. Schema v2 is locked. Claude Code's next steps: runtime executor in `js/practice.js` + `PracticeStore.swift` (~250 LOC each) replacing the regex resolver, then `bobaId`-keyed expansion post-pass.
- **Prior session**: 2026-04-15 (Cowork v2 pass) — `play-effects.json` bumped to **schemaVersion 2**; all 102 remaining `note`-only entries converted to structured ops. Coverage 382/383 structured (99.7%), 1 note-only: `Lucky Seven` (ability text blank in cards.json). Web + iOS bundles byte-identical, md5 `b641fe8920f63c6236301022da4db2a0`, 209,825 bytes. Authoring lives in a new `V2_OVERRIDES` dict at the bottom of `scripts/author_play_effects.py` that `PLAYS.update()`s over the v1 entries — fully reviewable diff. Introduced ~40 new ops / 6 condition types / 15 metrics in the process; all listed and dispositioned (promote/rename/fallback) for schema review in COWORK.md → "📥 Cowork → Claude Code" under "[2026-04-15 v2]".
- **Prior session**: 2026-04-15 (Cowork v1 pass) — `play-effects.json` first authored for all 383 unique Play names (~187 KB, mirrored into web + iOS bundles, md5-matched). 69.2% entries carried structured ops; 30.8% shipped as `note` escape hatches for effects that needed runtime hooks not yet in the schema. Authoring source-of-truth: `scripts/author_play_effects.py` in the research project (reads cost + ability live from cards.json so output stays fresh). Full delivery notes + list of 4 new ops + 7 new condition types + 5 new persistent triggers flagged for schema review in COWORK.md under "📥 Cowork → Claude Code". Replaces the fragile regex resolver in `js/practice.js` + `PracticeStore.swift` with declarative data.
- **Prior session**: 2026-04-14 (Cowork) — 167 OCR+BV-verified hero power corrections applied to cards.json. All 7 downstream bundles regenerated and mirrored. See session log. All three flagged invariants closed: (1) `reconcile_all.py::step4` now emits `{bobaIdSlug}.webp` natively via a per-tier rename-reconcile pass — `stage12_rename_by_bobaid.py` is no longer a required post-step. (2) `ebay_review_server.py` approve handler now saves verified art as `{slug_for_file(bobaId)}.jpg` instead of the legacy canonical_stem form, imports `slug_for_file` from `scripts/boba_id.py` (single source of truth), and the POST payload carries `variation` + `bobaId` end-to-end. (3) New `scripts/r2_upload.py` helper enforces `--s3-no-check-bucket` on every rclone upload to R2; all three rclone-mentioning docs (`STAGE12_HANDOVER.md`, `R2_REUPLOAD_MANIFEST.md`, `IMAGE_SOURCING_STRATEGY.md`) updated with the required flag. Catalog bundles verified in sync across research and playbook (cards.json md5 `a6c4850c` both sides).

- **Prior session**: 2026-04-13 (Claude Code) — Stage 1+2 R2 sync complete: 29,486 renames + 2,542 Phase B uploads, 32,028/32,028 ops succeeded, 30/30 verification spot-checks pass. Practice battle icons replaced with custom SVG sprite sheet (icon-sword, icon-xoxo, icon-hotdog, icon-eye/bolt/cards/scale/cycle/trophy for phases, icon-star for honors, icon-x for exit, icon-discard). See `COWORK_RETURN.md` for full sync details.
- **Open questions**:
  - Strategy hints: deck evaluation panel in deck builder (pull from research docs)
  - Discord M5: needs bot added to server before re-enabling the hidden FAB
  - **Web parity needed**: Rename "STARTER TEMPLATES"/"Archetype Templates" → "Starter Decks" in index.html + practice.js
  - **Deferred iOS items**: (all previously deferred items now implemented — see 2026-04-14 session log)
  - **Play-effect unknown ops (Tier B + Tier C)**: see "Unknown Ops Tiering" section below — Tier A now runtime-wired; Tier B + C are remaining gaps that surface "⚠ Some effects not yet simulated" honesty notes at play time.

---

## Unknown Ops Tiering — Play Effect Executor Gap

Cowork authored 383/383 structured entries in `play-effects.json`, but the runtime executor only implements a subset of the op vocabulary. Entries that reference unimplemented ops still execute (unknown ops log to `unknownOps` and are skipped forward-compat), but their effect is only partially simulated. The UI surfaces this with a `⚠ Some effects not yet simulated` pill so players aren't misled.

**Current state (2026-04-15)**:
- Tier A **SHIPPED**: 9 ops added (`swap_hd_counts`, `play_cost_delta`, `shuffle_hand_into_deck`, `shuffle_from_discard_to_deck`, `discard_top`, `discard_hand_all`, `power_reset`, `add_top_hero_power_to_self`, `reclaim_used_play`). Coverage: ~25 ops → ~34 ops, estimated ~88% of cards now fully simulated. Honesty note surfaces on remaining partial cards.
- Tier B: ~15 ops, moderate complexity — requires small new UI or more context plumbing. **Target: one weekend session.**
- Tier C: ~18 ops, high complexity — requires new UI systems (choice modals, reveal areas, opponent-hand preview) or deeper game-state tracking (per-source power modifier provenance).

### Tier B — Moderate ops (~15, one weekend session)

Each needs a small runtime addition but no new UI dialogs. Ship as a batch; several share plumbing.

| Op | Example card | What's needed |
|---|---|---|
| `swap_active_with_hand` | ? | Swap active hero card with a chosen hero from hand; heuristic pick highest-power hero |
| `swap_active_with_discard` | ? | Swap active with top-of-discard hero (optionally filtered by weapon) |
| `swap_active_with_future_hero` | ? | Replace current battle's hero with next battle's hero — modifies `battles[currentBattle+1].playerCard` |
| `reveal_top_hero_deck` | `Scouting Report` | Peek N cards from heroDeck; store on PracticeStore for UI display (web: toast; iOS: sheet) |
| `mark_future_battle` | ? | Install a persistent with `scope: "next_battle"` or `"battle_N"`; persistent framework already handles scope |
| `transform_to_hot_dog` | ? | Replace hero card in a slot with a hot-dog token (power 0) — affects resolution math |
| `variable_cost_bonus` (expanded) | Already stubbed; needs `min_cost` facet for Big Spender Bonus | Honor `min_cost` when deciding how much HD to spend |
| `mirror_power_effects_to_opponent` | ? | Copy all power deltas applied to self this battle onto opponent — requires tracking `battle.playerEffectPower` source list |
| `flip_opponent_debuffs` | ? | Convert opponent's negative effect power into positive self power — reads `battles[current].cpuEffectPower` if < 0 |
| `cancel_persistent` | `Pulling The Plug` | Remove installed persistent by id/name from `persistents[]` |
| `compound_roll` | ? | Multi-stage dice roll: roll, then re-roll under a condition; extend `dice_roll` executor |
| `shuffle_from_discard_to_deck` (hero kind) | ? | Tier A shipped the Play-kind version; Hero-kind needs `ctx.selfHeroDeck` plumbed as mutable |
| Condition: `weapon_streak` | ? | Count consecutive revealed heroes of same weapon (walk `battles[0..currentBattle]`) |
| Condition: `opponent_played_weapon_match` | ? | Match opponent's played Play cards' element to active hero weapon |
| Condition: `next_hero_power_gt` / `next_hero_weapon_equals` | ? | Peek `heroDeck[0]` and compare |

**Implementation note**: All persistable state (stored peeks, transformed heroes, mirrored deltas) must also make it into `MatchSnapshot` Codable so Resume Match doesn't corrupt mid-state. That's the easy-to-miss part.

### Tier C — Complex ops (~18, multi-session)

These need new UI affordances, deeper game-state tracking, or opponent-hand visibility changes that have downstream design implications.

| Op / System | Example card | What's needed |
|---|---|---|
| Choice modal UI | Many `options`-typed entries | Right now the executor picks the best option heuristically. A proper implementation prompts the player with a choice dialog. Requires web modal + iOS `.confirmationDialog` with card art previews. |
| Reveal-hand UI | ? | Player picks a specific card from own hand (e.g., "choose a Play to discard"). Needs a sheet that lists hand and filters by kind. |
| Opponent-hand preview | ? | "Look at opponent's hand" — opens a privileged view of CPU hand. Design decision needed: do we show real data or spoiler-safe anonymized slots? |
| Per-source power modifier provenance | `Ha! Gotcha`, `Copycat` | Track which play card applied which delta so other ops can nullify "only effects from X source." Requires extending `BattleSlot` to hold `[(source: Card, delta: Int)]` instead of a single `effectPower` int. |
| `if/else` persistent payload form | `Dead Red` | Persistent framework needs to support conditional payloads triggered at resolution time (currently only the install step is conditional). |
| Debuff interception | `Sweet Relish` | Intercept incoming negative power deltas and transform them. Requires ordering of effect resolution (currently all deltas apply in a single pass). |
| Counterplay windows | ? | Some cards say "when opponent plays X, you may play Y" — requires a priority queue + opponent-turn pause for player response. Large UX change. |
| Retroactive semantics | `Pulling The Plug` (cancel_persistent retroactive) | Unwind a persistent's already-applied effects. Needs action log with undo stubs. |
| Hero-deck manipulation beyond peek | ? | Reorder top N hero-deck cards, insert into specific slot. Needs drag-reorder UI. |
| Bonus Plays discovery | `By Any Means Necessary` | Search Playbook for a specific Play and play it free. Needs a filterable Playbook-search sheet. |
| Multi-battle chain effects | ? | Effects that span multiple future battles conditionally; extends persistent scope language. |
| Sudden Death special casing | Super weapon tiebreaker | Partially implemented in resolution; some Plays have "in Sudden Death, X" clauses — needs executor context flag. |

**Architectural watch**: Tier C items that require **per-source power provenance** (Ha! Gotcha, Copycat, Sweet Relish) all share the same data-model change — expanding `playerEffectPower: Int` to `effectStack: [(sourceCardId, delta)]`. Do that refactor once and several Tier C cards become easy.

### How to work through these

1. Start with Tier B batch by batch (the peek/swap ops share plumbing; tackle together).
2. Before coding, re-run the executor against all 383 entries and look at the actual `unknownOps` output to confirm which ops are most-hit — prioritize by card count affected, not by alphabetical order.
3. Each Tier A/B/C op added should also remove itself from `pmEntryHasUnknownOps`/`PlayEffects.entryHasUnknownOps` known-op sets so the honesty note clears.
4. Tier C is a design-first effort. Each new UI (choice modal, reveal area) needs a brand review (Design.Colors, typography) before shipping.

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

**2026-04-15 (Cowork v3 sync)** — Small-task handoff from Claude Code's v3 pass closed. Claude Code PROMOTED all of Cowork's v2-pass new vocabulary into `PLAY_EFFECTS_SCHEMA.md` (no renames of Cowork ops; a few of Claude Code's earlier proposed names yielded to Cowork's — `shuffle_hand_into_deck`, `shuffle_from_discard_to_deck`, `swap_active_with_hand`, `swap_active_with_future_hero`, `reclaim_used_play`, `transfer_sub_cost`, `force_substitute`). User separately sourced the `Lucky Seven` ability text ("Roll a die two times; if sum is 7 your Hero gets +100; if any other number you must discard a random Hero from your hand" — identical mechanics to the existing `Lucky 7` entry). Claude Code authored the structured form directly into both bundles at md5 `1d4e054e1ab56d2deaa696a3604fe81e`. Cowork's small-task return: (1) synced `Lucky Seven` into the `V2_OVERRIDES` dict in `scripts/author_play_effects.py` with the exact encoding Claude Code supplied (`dice_roll count=2 aggregate=sum`, branches for 7 → +100 and else → discard random hero); (2) updated `build()` to prefer spec-provided `cost`/`ability` when `cards.json` has them blank, so `Lucky Seven` (whose `playAbility` is still `null` in catalog) regenerates correctly; (3) re-ran the author script — final bundle md5 is now `b36d7b49746f5da5f3427afd90ab8ed6` on both web + iOS, 210,519 bytes, **383/383 structured (100%)**, **0 note-only**. md5 differs from Claude Code's transient `1d4e054e...` only because the top-of-file summary `note` string auto-updated from "1 note-only" to "0 note-only"; the `Lucky Seven` entry itself is byte-identical. Regeneration is now stable (no more drift — running the script again yields the same bytes). V2_OVERRIDES is locked; Claude Code's next steps are runtime executor wiring in `js/practice.js` + `PracticeStore.swift` (~250 LOC each) replacing the regex resolver, then `bobaId`-keyed expansion post-pass. Outbox item closed in COWORK.md.

**2026-04-15 (Cowork v2 pass)** — `play-effects.json` v2 delivered: schemaVersion bumped to 2, all 102 remaining note-only entries from v1 converted to structured ops. **Coverage: 382/383 structured (99.7%), 1 note-only: `Lucky Seven`** (ability text is blank in `cards.json` — awaiting an official source scan; carried with an inline note explaining why). Web + iOS bundles byte-identical at md5 `b641fe8920f63c6236301022da4db2a0` (209,825 bytes; up from 187,498 in v1 due to structured expansion). Authoring: added a `V2_OVERRIDES` dict (≈740 lines) at the bottom of `scripts/author_play_effects.py` that `PLAYS.update()`s over the v1 entries — keeps the v1 authoring intact and makes the v2 diff reviewable in one block. Fixed a naming collision in the `pwr_formula(_pwr_target, **formula_kw)` helper so the power target (self/opponent) and the formula's metric target (whose metric to measure) can be specified independently. **New vocabulary introduced and flagged for Claude Code's schema decision** in COWORK.md → "📥 Cowork → Claude Code" → "[2026-04-15 v2]": ≈40 new ops (shuffle_hand_into_deck, swap_active_with_discard{weapon_filter}, reveal_top_hero_deck, mark_future_battle, transform_to_hot_dog, variable_cost_bonus, mirror_power_effects_to_opponent, flip_opponent_debuffs, cancel_persistent, compound_roll, etc.), 6 new condition types (weapon_streak, opponent_played_weapon_match, previous_two_heroes_share_weapon, previous_and_current_share_weapon, discarded_hero_weapon_matches_active, next_hero_power_gt / next_hero_weapon_equals), and 15 new formula metrics (previous_hero_power_gained, discard_pile_heroes_weapon_match, battles_lost_streak, opponent_hd_used_this_battle, cards_discarded_by_this_play, etc.). Each gets a promote/rename/fallback disposition from Claude Code. Plays flagged as "v2 vocab felt like a stretch" for expressibility review: Copycat (provenance scoping), Ha! Gotcha (requires power-modifier tracking by source), Sweet Relish (requires debuff interception), Pulling The Plug (cancel_persistent retroactive semantics), Dead Red (if/else persistent payload form), Big Spender Bonus (formula needs min_cost facet). No pipeline changes — this file is authored, not regenerated from a source. Next step is Claude Code's schema lock + runtime executor wiring in `js/practice.js` + `PracticeStore.swift`.

**2026-04-15 (Cowork v1 pass)** — `play-effects.json` authored for all 383 unique Play names (from 505 Play printings in cards.json, collapsing to 383 distinct names with 1 benign ability variant on "No Huddle"). Authoring source: `scripts/author_play_effects.py` in the research project — the `PLAYS` dict there is the hand-authored source of truth, and the script reads cost + ability live from cards.json so the output file stays fresh even as the catalog changes. Written to both `assets/data/play-effects.json` (web) and `BOBAPlaybook/play-effects.json` (iOS), md5-verified identical at `b44c11ac9c8bba6227bee7b0f781756f`. 187,498 bytes. Schema v1, `keyedBy: "name"`. Coverage: 265 entries (69.2%) have structured ops or persistent effects; 118 (30.8%) ship as `{"op": "note", "text": "..."}` for abilities that need runtime hooks not yet in `PLAY_EFFECTS_SCHEMA.md`. All 7 outstanding Play categories exercised: power/power_set/power_swap/power_cap_min, hd/hd_recover, draw/discard, search/reveal, coin_flip/dice_roll with branches + aggregate, cancel_opponent_plays/protect_self/block_sub/block_draw/play_cost_delta, honors_set/substitute_free, plus 21 persistent entries covering rest_of_game/next_battle/next_2_battles/battle_7/this_battle scopes with battle_start/on_win/on_loss/on_coin_flip/on_dice_roll/on_substitute/on_play_run/on_opponent_play_run/continuous triggers. 4 new ops (`block_hd_recover`, `block_plays`, `cap_opponent_plays`, `persistent_delta`), 7 new condition types (`battle_won_nth`, `battles_lost_first_n`, `battles_won_streak`, `hand_count_compare`, `hd_count_compare`, `hero_name`, `power_threshold`), and 5 new persistent triggers (`on_coin_flip`, `on_dice_roll`, `on_substitute`, `on_play_run`, `on_opponent_play_run`) used — all flagged in COWORK.md outbox for Claude Code to promote, rewrite, or leave as notes. Replaces the fragile regex effect resolver (~200 LOC across `js/practice.js` + `PracticeStore.swift`) with declarative data; runtime executor wiring is Claude Code's next step. No pipeline changes needed — this file is authored, not generated. Claude Code → Cowork outbox item closed; Cowork → Claude Code outbox updated with delivery note + schema-gap list.

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

**2026-04-13 (Claude Code) — Stage 1+2 R2 sync complete.** Executed all R2 operations from `STAGE12_R2_MANIFEST.json`: 14,707 standard renames × 2 tiers + 36 sealed renames × 2 tiers = 29,486 total renames; 1,271 Phase B new uploads × 2 tiers = 2,542 uploads. All 32,028 operations succeeded (0 failures). Used Python `ThreadPoolExecutor(32)` for parallel rclone invocations (~9 ops/s renames, ~19 ops/s uploads; ~59 min total). Note: rclone uploads to R2 require `--s3-no-check-bucket` flag to avoid spurious CreateBucket 403 errors. 30/30 verification spot-checks returned HTTP 200. Catalog is now end-to-end bobaId-keyed: cards.json imageFile → R2 object key → CDN URL, all share the same `{bobaIdSlug}.webp` name. Coverage 82.9% → 90.3%. `STAGE12_R2_MANIFEST.json` removed (preserved in git history). See `COWORK_RETURN.md` for full details. Also this session: practice battle icons replaced with custom SVG `<symbol>` sprite sheet.

**2026-04-13 (Cowork) — Stage 1+2 bobaId rename: all catalog images renamed to `{bobaIdSlug}.webp`.** User-authorized initiative to enforce "One Image per Card, One ID per Card" all the way down to the R2 object key. Previously, `reconcile_all.py` linked images via `variety_key` (a filename-stem hash) rather than bobaId, which is why 0 of 14,743 imageFiles contained bobaId as a substring. **Phase A**: renamed every catalog-referenced image on disk (14,743 standard + 36 sealed) to `{bobaIdSlug}.webp` across `images/`, `images-optimized/`, `thumbs/`, and the sealed tiers. **Phase B**: scanned 4,217 unmapped disk files and claimed 1,271 that had exactly one bobaId-strict match to an unmapped card (481 Plays + 47 HotDogs + 743 Heroes). Coverage 82.9% → **90.3%**. Non-Hero missing dropped 554 → 26 (95% recovery). Collision guard: 0 cross-card md5 collisions (only 15 whitelisted sealed Box↔Case pairs). Regenerated all bundles (cards.json, cards-slim.json, categories.json, search-index.json, missing-cards.json, display-cards.json, cards-head.json) and copied into this repo. **Claude Code action required**: R2 rename via `STAGE12_R2_MANIFEST.json` (14,743 renames × 2 tiers = 29,486 ops) + 1,271 new uploads × 2 tiers = 2,542 new ops. Full instructions in `STAGE12_HANDOVER.md` at repo root. App code needs NO refactor — `thumbUrl(card.imageFile)` and `fullUrl(card.imageFile)` just work once R2 objects match cards.json.

**2026-04-13 (Cowork) — Stage 1+2 pipeline invariants closed.** Claude Code's `COWORK_RETURN.md` handover flagged three pipeline invariants for Cowork to patch. All three closed this session in the research project (`/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research/`):

1. **`reconcile_all.py::step4` now emits `{bobaIdSlug}.webp` natively.** Added a per-tier rename-reconcile pass that iterates `[OUT_IMAGES, OUT_OPT, OUT_THUMBS]` and renames/dedupes any legacy `variety_key`-named file to its card's bobaIdSlug, then writes that as the `imageFile` value. Same pass runs for sealed products in step12 across `[SEALED_OPT, SEALED_THUMBS]`. The `any_tier_ready` logic correctly handles the 119 Phase B cards where the original source-tier file was missing (fix for the 119-regression bug surfaced during the first verification run — see COWORK_RETURN.md). `stage12_rename_by_bobaid.py` is no longer a required post-step; any future full pipeline run produces a catalog that's bobaId-keyed end-to-end from the ground up.

2. **`ebay_review_server.py` approve-save uses `{bobaIdSlug}.jpg`.** Imports `slug_for_file` from `scripts/boba_id.py` (the single source of truth — `boba_id.py` gained `slug_for_file` and `image_filename` this session so no other script mirrors the formula inline). POST payload now carries `variation` + `bobaId` end-to-end; approve handler prefers the client-supplied `bobaId` (sourced from `radish_ebay_scan.csv` via the variety_map), falling back to computing it from `(cn, hero, treatment, variation)`. `get_card_groups` now detects already-approved files via three precedence-ordered sets: `verified_boba_slugs` (new canonical form), `verified_varieties` (legacy canonical_stem), `verified_legacy_cns` (bare cardNumber). Smoke test confirms 839 groups surfaced, slug output matches on-disk `imageFile` byte-for-byte (`1-LeBoss-Base_Set-First_Edition.jpg` = `1-LeBoss-Base_Set-First_Edition.webp` stem). New eBay approvals will never introduce a `variety_key`-named file again.

3. **`scripts/r2_upload.py` wrapper enforces `--s3-no-check-bucket`.** A thin Python wrapper around rclone that bakes in the required flag on every upload. Supports `copy`, `copyto`, `sync`, `move`, `moveto`, auto-rewrites tier-prefixed paths (`full/`, `thumbs/`) to `r2:boba-card-images/...`, and supports a `BOBA_R2_DRYRUN=1` mode for preview. All three rclone-mentioning docs updated with the flag inline as well (`STAGE12_HANDOVER.md`, `R2_REUPLOAD_MANIFEST.md`, `IMAGE_SOURCING_STRATEGY.md`). The invariant is now belt-and-suspenders: docs say to use the flag, and the wrapper enforces it if the flag is forgotten.

**Verification**: research `cards.json` md5 = playbook `cards.json` md5 = `a6c4850c...` (byte-identical). `cards-slim.json` synced from playbook (da0829ec) back to research. `categories.json`, `search-index.json`, `missing-cards.json`, `sealed_products.json`, `BOBAPlaybook/display-cards.json`, `BOBAPlaybook/cards-head.json` all match across both repos. (Two stale copies in `assets/data/` — `display-cards.json` and `cards-head.json` — are iOS-variant files left over from a historical mis-copy; iOS reads from `BOBAPlaybook/` which does match, so they're harmless but worth cleaning up later.)

**Next full `reconcile_all.py` run** will produce a catalog with 1,271 cards labeled `imageSource: "disk_claim"` (the new step4 claim label) vs today's `"stage1_claim"` (one-time migration label) — purely a cosmetic diff; the imageFile, imageAvailable, and bobaIdSlug values are identical.

**2026-04-14 (Cowork)** — 167 OCR+BV-verified hero power corrections applied. Three-way audit (cards.json vs the card source vs Vision OCR of printed art) resolved 486 flagged mismatches. Applied only the 167 cards where OCR confirmed BV was right; kept cards.json on the other 319 (BV errors, OCR-unreadable, three-way splits). All 7 bundles regenerated and md5-matched across repos.

**2026-04-14** — iOS deck builder + practice battle fixes. (1) Fixed double template slide-up: separated inline gallery state from sheet presentation state. (2) Fixed Mixed Toolbox and Economy/Attrition starter deck hero violations — both now have 60 diverse heroes respecting max-6-per-hero and 1-per-variation rules. (3) Standardized "Starter Decks" naming (toolbar button). (4) Fixed Battle button icon: `"swords"` (invalid SF Symbol) → `"flag.2.crossed.fill"`. (5) Major practice battle layout overhaul: removed `.ignoresSafeArea(.all, edges: .horizontal)` (fixes Dynamic Island/corner bleed), replaced cramped 7-column HStack with scrollable 3-4 column arena using `containerRelativeFrame` + `scrollTargetBehavior(.viewAligned)`, replaced permanent 110px player zone + 60px opponent zone with compact 50px bottom toolbar and slide-up overlay panels for bench/plays (independently toggleable), panels auto-show during relevant phases. Cards ~3x larger than before. Extracted PracticeView into 6 focused files: PracticeTopBar, PracticeBottomToolbar, PracticeBenchPanel, PracticePlaysPanel, BattleColumnView. Portrait "ROTATE TO PLAY" now properly centered and playmat not rendered until landscape. CPU info moved to compact badge in top bar.

**2026-04-14** — Practice battle polish + deferred items completed. (1) Side-by-side active battle view (ActiveBattleView.swift) — full card art visible for both player and CPU, with future battles as smaller columns scrollable right. (2) Play card detail on tap — tapping a card now selects it and shows card name, cost, and effect description; "PLAY" button to confirm. (3) "PASS PLAYS" renamed to "END TURN" everywhere. (4) Fixed hero deck count (capped to 47, simulating 60-card deck) and bench growth bug (removed draw-from-deck after substitution, bench stays at 6). (5) Rotation fix: `allowLandscape()` doesn't force rotation — user rotates manually; "ROTATE BACK" exit prompt shown until portrait. (6) Icons: flame → "HD" text for hot dogs, person stack → `figure.fencing` for heroes, facedown cards → `shield.fill`. (7) Unified deck management sheet: Templates + My Decks + Export in one tabbed sheet, replacing 3 separate sheets. (8) Card browser scroll/tap fix: replaced `DragGesture(minimumDistance: 0)` with `onTapGesture`. (9) Game state persistence: `MatchSnapshot` Codable struct, auto-save on phase transitions, "Resume Match" button in setup, "Save & Exit" option. (10) Play card effects engine: pattern-matching resolver handles +N power, -N opponent, steal, coin flips, dice rolls, weapon-conditional, tied bonuses, doubled power; fallback formula for 369 unparseable abilities. Shows actual `playAbility` text in card detail. (11) Web parity: "STARTER TEMPLATES"/"Archetype Templates" → "Starter Decks" in index.html.
