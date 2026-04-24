# BOBA Playbook — Project Scratchpad

> Active working notes only. Completed milestone implementation detail, the closed Unknown Ops Tiering section, and the full session log live in [ARCHIVE.md](./ARCHIVE.md). See [DECISIONS.md](./DECISIONS.md) for architecture decisions.

## Current State

- **Active milestone**: M4 — Play Mode (M3.5 fully complete and deployed)
- **Last session**: 2026-04-24 (Claude Code) — **Massive batch.** Practice executor expansion: scope vocab (this_and_next, next_N_battles, battle_N), persistent weapon transforms with `resolveWeapon` indirection (weapon reads at all 14 sites route through this), formula-literal delta (B.3 — `{factor, metric: {type, target, kind}}` shape now resolved by `evalFormula`), lifecycle hooks (B.2 on_plays_resolved, B.4 on_battle_win/loss with one-shot install variants, B.9 on_battle_start), HD recover modifier pipeline (B.5 — redirect → cap → delta → block in order), B.8 auto-lose-battle for zero-HD, B.12 discard_hand_all kind:hero. Cowork's same-day play-effects audit landed (md5 verified, 7 Part A fixes merged, 38 entries still note-only awaiting B.6/B.7/B.10/B.11/B.13). UI on top: active-effects pill banner under top bar, per-hero weapon badge with ⟲ transform indicator on ActiveBattleView, plays-used-this-battle row, auto-computed power breakdown panel on Resolution, effective-cost display (`3→5` strikethrough) on plays in hand, bonus-play distinction (gold border + ★ BONUS chip), scope tick-down badge on persistent pills, auto-reshuffle on deck empty with notification, discard pile tap-to-inspect (player + CPU sides), Pull The Plug post-fire CANCELLED/UNCHANGED summary, Recycle pre-resolve confirm modal, dice/coin animated reveals (🎲 ⚄ 5 / 🪙 HEADS · TAILS), HintsManager + HintBanner first-run hints (substitution positioning, bonus play ceiling). Plus Setup tab in Learn covering match flow + edge cases + reading-the-playmat key. Web parity for everything. **Taxonomy update**: BoBA-expert audit landed end of day — Treatments vs Parallels split into separate Learn-tab sections (Standard/Themed/Premium grouping for Treatments + dedicated Parallels section), Inspired Ink = Serialized callout with weapon-tied serial chips (Hex /5, Glow /10, Fire /25, Ice /50), card-detail view restructured to canonical 6-cell layout (Card #/Type, Treatment/Weapon, Set/Sub-set), "Rarity" → "Treatment" rename in non-rarity contexts. Other: Web "Play" tab → "Learn" rename for iOS parity, iPhone home-screen display name → "Playbook" (in-app stays "BOBA Playbook"), Store Locator (web + iOS, BoBA-pin Leaflet markers, big-box default filter), CSV export of collection from 3-dots menu, Collection card detail overhaul with market pricing + eBay/Radish + tap-to-edit + decks-containing list, Collection filter button with shared CardStore state, deck-builder collection toggle + hero/weapon repeat breakdown. **All 5 web Practice caveats resolved**: CPU discard hook on opponent zone chip, Recycle confirm with cancelled-effects bullet list, dice/coin emoji reveals, HintsManager system, Settings toggle for hints. md5 of merged play-effects.json: `e1c9beae3076bacb60e441971f1aba56`.
- **Prior session**: 2026-04-23 (Claude Code) — Streamer role + Shows feature end-to-end (Supabase `shows`/`show_cards` tables, `ShowsStore`, Collection → My Shows tab with horizon picker + exclusion + Generate Wall, scanner Show Mode, card-detail "To Show" add, bulk-add via `AddToShowSheet`). Admin panel role picker rewritten as a Menu (Menu shows full User → Streamer → Moderator → Admin ladder with up/down arrows so demotion is discoverable). Find tab: new `Showcases` filter section (WoBA + 7 sport showcases), smart search that resolves showcase names, weapon names, treatments, set names, and alias expansions; Quick Add toggle on iOS + web. Element → Weapon rename across every user-facing label (filter section, card-detail stat grid, mod correction sheet). eBay sold-comp matcher Path A: enriched `scoreSoldListing` with signal-weighted scoring, probable-match tier, MATCH_MODE feature flag, client-side Radish URL synthesis so the Worker actually fetches Radish data.
- **Prior session**: 2026-04-21 pm (Claude Code) — **6-prefix handoff batch applied.** Applied Cowork's `handoff-updates-2026-04-21/` (88 new records across RPU/BILLY/JPA/BLC/SK/CJ). Catalog 17,767 → **17,855**. 19 BV images (12 RPU + 7 BILLY) optimized and uploaded to R2 (38 objects, spot-checks 200 OK). 69 chase/promo records without images auto-queued to `missing-cards.json` for the eBay sourcer. Coverage 91.6% → 91.2% (expected dip — 69 new awaiting-art rows). CJ-8..22 `athleteInspiration` backfilled to `"CJ Maddux"` per user directive ("null is not the right approach for anything"). New reusable pipeline: `scripts/apply_handoff_batch.py` (supersedes single-prefix `apply_cyber_handoff.py`).
- **Prior session**: 2026-04-21 am (Claude Code) — **2025 Cyber Promo set added.** Merged Cowork's `handoff-cyber/` payload: 28 new CYB-* hero records (17,739 → 17,767 cards), 27 BV images optimized + uploaded to R2 (54 objects, all 3 spot-checks HTTP 200), CYB-28 Flav queued to `missing-cards.json` for the eBay sourcer. Coverage 91.5% → **91.6%**. `byElement.CYBER` in `search-index.json` now has 28 bobaIds. Field labels follow BV/Radish precedent (`set="Promo Cards"`, `subSet="Cyber"`, `variation="2025 Cyber Promo"`, `treatment="Cyber"`, `element="CYBER"`). CYB-5 The Kid included per cross-source confirmation. Pipeline lives in `scripts/apply_cyber_handoff.py` (idempotent). iOS testers need a new TestFlight build; web users just refresh.
- **Prior session**: 2026-04-16 (Cowork) — **225 new card images reconciled from eBay review.** User approved 225 new + 112 upgrades. Coverage: **16,014 → 16,239 (90.3% → 91.5%)**. Bundles regenerated; `R2_UPLOAD_MANIFEST.json` lists 225 new imageFile values (all bobaId-slug format) needing R2 upload (17.3 MB opt + 1.6 MB thumbs = 450 rclone ops). 9 ambiguous files skipped (BF-100→105, BFA-2/MBFA-1/SFA-2 A.I. variants). 1 pre-existing source collision (BGA-1 BoJax), not blocking. **Claude Code's next action: R2 upload + commit + spot-check.** See COWORK.md → "📥 Cowork → Claude Code" → "[2026-04-16]".
- **Prior session**: 2026-04-16 (Claude Code) — Tier B + Tier C play-effect ops shipped on both platforms. **383/383 `play-effects.json` entries execute with 0 unknown ops, 0 runtime errors.** iOS `xcodebuild` → BUILD SUCCEEDED. Full op/condition/metric list and design tradeoffs in ARCHIVE.md.
- **Open questions**:
  - Strategy hints: deck evaluation panel in deck builder (pull from research docs)
  - Discord M5: needs bot added to server before re-enabling the hidden FAB
  - **Web parity needed**: Rename "STARTER TEMPLATES"/"Archetype Templates" → "Starter Decks" in index.html + practice.js

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

### ✅ Completed
- **M0 — Project Setup**: Card data JSONs, R2 images, Supabase schema, GitHub Pages live, Xcode project at repo root.
- **M1 — Search Mode** (both platforms): card grid, search, filters, modal, CDN images, PWA, branding.
- **M2 — Collection Mode** (both platforms): Supabase auth (email + Apple), Keychain (iOS), CRUD, designation tabs, value summary, ProfileView. Designations: Personal · For Sale · For Trade · Wanted · Grails.
- **M3 — Scan Mode (iOS) + Pricing Comps (both)**: Vision OCR with 3-frame stability, multi/single toggle, Save All queue. Radish + eBay links on both platforms. Worker at `boba-ebay-proxy.benwilkoff.workers.dev` (URL in `BOBAPlaybook/Config.swift` and `js/app.js`). *Deferred:* Box lookup for sealed product pricing.
- **M3.5 — Pricing Enhancements**: Dual-section Buy Now + sold history shipped on both platforms. Market Feed deferred, code removed (SerpApi the recommended approach when revisited).

Full implementation notes for M1–M3.5 live in [ARCHIVE.md](./ARCHIVE.md).

---

### ⏳ M4 — Play Mode (ACTIVE)

**Content source**: `/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research/unified-cards/docs/M4_PLAY_STRATEGY_COLLECTING_GUIDE.md`
Sourced from official Quick Start Guide, Comprehensive Rules Guide v1, Penalty & Procedure Guide v0, Tournament Rules v0, and 2026 Edition Collector Guide.

**Shipped to date:**
- Deck Builder + Practice Battle on both platforms
- `play-effects.json` authored for 383/383 unique Play names; structured executor replaces the legacy regex resolver on both platforms
- All Tier A/B/C executor ops implemented — 0 unknown ops, 0 honesty warnings

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
FIRE, ICE, STEEL, BRAWL, GLOW, HEX, GUM, SUPER, ALT, CYBER (28 cards in the 2025 Cyber Promo set).
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

### ❌ M5 — Discord Trading Channel (FUTURE)
Embed community trading channel. `discord.com/channels/1305710603440095252/1306146115757936650`
Research Discord Activity SDK vs WebView feasibility before committing.
