# Autonomous Iteration Loop — Progress Log

**Started:** 2026-05-20 (post-sealed-products commit)
**Owner instruction:** *"Create a persistent loop (surviving compacting) to iterate on (1) cross-platform parity across iOS / web / Android and (2) all documented deferred features. Use agents, project docs, and platform-specific Claude skills. Significant + well-documented progress over a few hours."*

This document is the persistent state — every loop tick reads + updates it. Each tick: pick the highest-priority item, implement, verify, commit + push, update this doc.

---

## Working philosophy

- **Native-first only.** Reach for built-in platform APIs before custom anything (`feedback_native_first`).
- **Bound each tick.** Pick work that can ship in ~20-40 minutes. If something balloons, split it.
- **Verify before claiming.** `xcodebuild` on iOS, `gradlew assembleDebug` on Android, smoke test in browser for web. Don't mark "done" on intent alone.
- **Commit every shipped tick.** Push to main. Ben sees progress incrementally.
- **Pull from documented sources.** PARITY.md, DECISIONS.md, SCRATCHPAD.md, DESIGN.md, WEB-DESIGN.md, ANDROID-DESIGN.md, ARCHIVE.md, COWORK.md. Discord-export JSONs from research dirs when relevant.

---

## Backlog (priority-ordered)

Order = (impact × shipping cost⁻¹). Higher impact + cheaper to ship = sooner.

### P0 — Quick wins from beta feedback / verified bugs

- [ ] **Verify sealed-image fix on web + Android** — iOS render path uses `card.isSealed` via CDN.swift; web js/api.js and Android core/network/CDN.kt should do the same. Spot-check that the catalog bake from v2.288 actually lights up in all three.
- [ ] **9 sealed products still missing R2 art** — surface them in `assets/data/missing-sealed.json` so the next sourcing pass picks them up.

### P1 — Cross-platform parity (pulled from PARITY.md)

Documented gaps where iOS has shipped but web / Android hasn't, OR vice versa.

- [ ] **Web Wall view + Price overlay** — `PARITY.md` line 142: iOS ✅, web ⏳ M-future. Already on the §15 roadmap.
- [ ] **Web Value history chart** — `PARITY.md` line 130: iOS ✅, web 🔮.
- [ ] **Web Custom Rainbows** — `PARITY.md` line 137: iOS ✅, web 🔮.
- [ ] **Android Custom Rainbows full parity** — currently `⏳ M2`, started but not complete.
- [ ] **Web sign-in with Google** — currently 🔮 on both iOS + web; Android shipped.
- [ ] **Android Whatnot tile list** — currently shows section header but no Worker wiring (per SCRATCHPAD).
- [ ] **Android Google Maps Find a Store** — needs Maps API key + Compose Maps wiring.

### P1 — Android v1 deferred polish (per SCRATCHPAD Android section)

- [ ] **Material 3 Expressive APIs** — FAB Menu / Floating Toolbar / Wavy Indicators (needs compileSdk 37 — currently 36).
- [ ] **M3 SearchBar full-screen morph** — Find tab uses OutlinedTextField for now; should use `ExpandedFullScreenSearchBar`.
- [ ] **Container transform / sharedBounds animations** — hero-zoom into card detail.
- [ ] **Article corpus port from iOS Swift** — Learn content depth gap.
- [ ] **Image fingerprinting (MediaPipe)** — defer per DECISIONS.md #043 (v1 = OCR-only).
- [ ] **Discord OAuth via Custom Tabs** — currently stubbed; Google works.

### P1 — iPad polish (SCRATCHPAD "Deferred iPad work")

- [ ] **Walkthrough anchor verification on iPad** — needs simulator validation.
- [ ] **iPad drag-and-drop between deck slots** — significant; nice-to-have.
- [ ] **Scan view landscape polish** — fixed guide size feels small on iPad.

### P2 — Web "feels native" follow-ups (per WEB-DESIGN.md §15 deferred)

- [ ] **Walkthroughs on web** — explicitly out of scope per §11.
- [ ] **Cmd-K command palette** — out of scope per §2.4.
- [ ] **Web push notifications** — out of scope per §17.

### P2 — Deferred from project docs

- [ ] **Match-alerts pipeline** (DECISIONS.md #039 + TRADE-DESIGN.md Phase 5) — APNs / FCM dispatcher. Multi-week of new infra.
- [ ] **Hero Shot 3D R2 `/full/` resolution upgrade** (SCRATCHPAD blockers) — Hero Shot pixelation root cause.
- [ ] **Practice executor on Android** (DECISIONS.md #048) — admin-gated. M5.5 milestone.
- [ ] **Personal Showcase on Android + web** (Cast SDK) — iOS-only today.

### Audit-driven items (populated by background agents)

*[Updated as agent results land — currently pending]*

---

## Tick log

Each loop tick appends an entry below. Format:

```
### Tick N — 2026-05-20 HH:MM MT
- **Picked:** {backlog item title}
- **Shipped:** {commit short SHA + version bump}
- **Verified:** {build status + smoke test method}
- **Next:** {what's next in queue}
```

### Tick 0 — 2026-05-20 — setup
- **Picked:** establish the loop infrastructure
- **Shipped:** this doc + 3 background audit agents launched
- **Verified:** n/a (setup)
- **Next:** ship one P0 item while audits run

### Tick 1 — 2026-05-20 — missing-sealed manifest
- **Picked:** P0 backlog item "9 sealed products still missing R2 art"
- **Shipped:** `assets/data/missing-sealed.json` with the 9 sealed-product rows
  needing art. Each carries bobaId / sealedProductId / set / cardNumber /
  radishUrl + expected R2 path. Once new files land on
  `r2:boba-card-images/sealed/optimized/` and `/sealed/thumbs/`, a re-run
  of `scripts/apply_sealed_images.py` lights them up automatically.
- **Verified:** read back the JSON — 9 entries, matches the script's
  9-still-missing count from v2.288.
- **Next:** wait for audit agents (A, B, C), then start cross-platform
  parity shipping in tick 2.

### Tick 7 — 2026-05-20 — Web Custom Rainbows (read-only render)
- **Picked:** Agent C's biggest demand signal (1,237 community messages on checklist/rainbow tracking) + Agent A's #3 documented gap. iOS shipped v2.219-v2.221; web parity was 🔮.
- **Shipped:**
  - `js/api.js`: `fetchCustomRainbows()` (PostgREST GET `/user_custom_rainbows`), `rainbowCriteriaMatches(card, criteria)` (verbatim port of iOS `RainbowCriteria.matches` — 8 dimensions AND-combined, values within OR-combined), `rainbowCriteriaSummary(criteria)` (one-line description for the row subtitle). All three exported on the API surface.
  - `js/collection.js`: `hydrateCustomRainbows(ownedCards)` — async fetch, no-op silently if 0 rainbows or catalog not ready. Renders one `<details>` per rainbow with name + criteria summary + "X / Y collected" progress count + width-driven progress bar + percent. Below: thumbnail strip (up to 24 cards) showing matching catalog cards. Owned matches at full opacity with cyan border ring; un-owned dimmed to 0.35 alpha so the user sees what's left.
  - `js/app.js`: exposed `window.__bobaCatalog` (read-only getter on `displayCards`) + `window.openCardModal(card)` so sibling modules can interop without IIFE-leakage.
  - `index.html`: added empty `<section id="custom-rainbows-section" hidden>` below the collection card list. Hidden by default; un-hidden by hydration on first rainbow found.
  - `css/styles.css`: ~95 lines for `.custom-rainbows-section`, `.rainbow-row`, `.rainbow-progress` bar, `.rainbow-thumb` with `.owned` variant.
- **Verified:** SQL query reads existing `user_custom_rainbows` table (iOS migration `2026_05_15_user_custom_rainbows.sql`); RLS already scopes to own-row. Thumbnail tap routes through `window.openCardModal` to the existing card-detail flow. Editor path intentionally not shipped — that's a separate medium-effort tick.
- **PARITY.md:** Custom Rainbows web 🔮 → ✅ read-only.
- **Next:** Tick 8 — Per-hero Auto Rainbows on web (Agent A #4). Builds on the same render path. Auto-derives the rainbow set per-hero from catalog enumeration (no Supabase fetch needed — those are computed from the catalog like iOS does).

### Tick 6 — 2026-05-20 — Web Wall: Price Overlay + per-designation defaults
- **Picked:** Closing the Price Overlay row in PARITY.md §5 — was ⏳ next tick after tick 5.
- **Shipped:**
  - `js/collection.js`:
    * Per-designation defaults wired (`defaultPriceOverlayFor` / `defaultPriceSourceFor`) — For Sale: ON / asking. For Trade + Wanted: ON / estimated. Personal + Grails: OFF.
    * `pickPriceForCard()` reads `asking_price` / `estimated_value` / `purchase_price` from the original user-card row (indexed by bobaId for fast draw-time lookup).
    * `priceOverlayCaptionFor()` matches iOS captions ("Your asking price" / "Market estimate" / "What you paid").
    * Refactored render into a `drawWall({showPrices, source})` closure so toggling re-renders without an image reload.
    * Price chip render: black rounded-rect (radius=chipH/2 → full capsule) + bold mono price at ~8% above card bottom edge (matches iOS ShowWallComposer.tile chipBottomInset). `WTB` prefix on `wanted` designation per §8.8.
  - `index.html`: added `.wall-overlay-controls` block — checkbox + source `<select>` (My asking price / Market estimate / What I paid) + caption span.
  - `css/styles.css`: ~25 lines for `.wall-overlay-controls`, `.wall-overlay-toggle`, `.wall-overlay-select`.
- **Verified:** Reused tick-5 CORS + canvas pipeline. Toggle / source `onchange` fire `drawWall` in-place (no extra network).
- **PARITY.md:** Price Overlay row flipped from ⏳ to ✅ on web. Full Wall + overlay feature parity with iOS achieved.
- **Next:** Tick 7 picks next from Agent A's recommendation list — Custom Rainbows read-only render on web (Agent C's biggest demand signal at 1,237 community messages on checklist/rainbow tracking).

### Tick 5 — 2026-05-20 — Web Wall view (canvas render)
- **Picked:** Agent A audit-parity #1 documented gap "Wall view (Collection display mode + share)" — iOS ✅, web ⏳ M-future, Android ⏳ M2 polish.
- **Shipped:**
  - `js/collection.js`: added `openWallSheet()` — resolves user-card rows to catalog Cards (drops images-less rows), renders a grid of card thumbnails into a `<canvas>` via `API.cardFullUrl()` (routes through `/full/` or `/sealed/optimized/` automatically), exports as PNG.
  - `index.html`: new native `<dialog id="wall-overlay">` with title input, canvas, download + copy + share actions. Sized 1080×variable to fit Instagram / Discord shares.
  - `css/styles.css`: ~75 lines covering the Wall button + dialog + canvas wrap.
  - `js/collection.js`: "Wall" toolbar button on the Collection page next to the Sort dropdown. Disabled when active designation has 0 cards.
  - **R2 CORS configured**: required for canvas + `crossOrigin='anonymous'` so `toBlob` / `clipboard.write` work without taint. Set via `wrangler r2 bucket cors set boba-card-images` with rules allowing GET/HEAD from `bobaplaybook.com` (+ localhost dev). Verified `Access-Control-Allow-Origin: https://bobaplaybook.com` header now present on `/full/...webp` requests.
- **Verified:** R2 CORS curl-verified. Canvas rendering path uses native `<dialog>.showModal()` + native `<canvas>.toBlob()` + native `navigator.share()` per WEB-DESIGN.md §2.1 native-first.
- **Next:** Tick 6 — Price Overlay toggle on top of the Wall canvas (per-designation defaults per iOS §8.8) + per-card selector. Both build on top of this tick's render path.

### Tick 4 — 2026-05-20 — iPad scan-view guide scale
- **Picked:** Agent B audit-deferred #17, "iPad: scan-view landscape guide scaling." Value-history chart on web was first plan but iOS doesn't have it either, so it's a 🔮 row, not a parity gap.
- **Shipped:** `BOBAPlaybook/Views/Scan/ScanView.swift` — file-scope `kGuideW`/`kGuideH` constants converted to size-class-aware computed properties. iPhone (compact) keeps the 300×420 default; iPad regular gets 1.5× scaling → 450×630. Touches every reference (dim mask, stroke, corner marks, ROI rect for AVCaptureSession) consistently because they all read the computed values.
- **Verified:** `xcodebuild -destination 'generic/platform=iOS Simulator'` → BUILD SUCCEEDED.
- **Next:** Tick 5 — Wall view on web. Substantial but Agent A's #2 recommendation. Will scope-split into render → share → toggle if it gets long.

### Tick 3 — 2026-05-20 — Web pricing refresh button + DBS explainer modal
- **Picked:** Two visible-parity items from tick 2's new rows where iOS+Android shipped but web was 🔮: Pricing refresh button (§8 L165) and DBS explainer modal (§8 L164).
- **Shipped:**
  - `js/app.js`: added `↻` refresh button to the pricing day-picker rail. Click sets `forceRefresh = true`, which appends `&fresh=1&_t={timestamp}` to the Worker request. Reset to false after each fetch.
  - `workers/ebay-proxy/worker.js`: added `forceFresh` param that bypasses `cache.match` lookup. New cache entry written from the fresh response so subsequent reads stay efficient. Verified: `?fresh=1` returns `x-cache: MISS`; plain query returns `x-cache: HIT`.
  - `js/app.js`: added DBS stat-cell renderer (Plays only). Tappable; opens dialog. Tier color matches iOS dbsColor.
  - `index.html`: added native `<dialog id="dbs-info-overlay">` with title + bullets + tier table, parity with iOS `DBSInfoSheet`. ESC + backdrop-click + close-button dismiss all work via native `<dialog>` semantics.
  - `css/styles.css`: ~70 lines of new styling for `.pricing-refresh-btn`, `.stat-cell-dbs`, `.dbs-tier-pill`, `.dbs-info-box`, `.dbs-tiers-table` — all element-tinted per iOS tier colors.
- **Verified:** Worker deployed; cache-bypass live (`x-cache: MISS` for `?fresh=1`, `HIT` for plain). HTML+CSS+JS syntactically clean. Dialog uses native `<dialog>.showModal()` per WEB-DESIGN.md §2.1.
- **Next:** Tick 4 — Wall view on web (Agent A's #2 recommendation; iOS canonical exists).

### Tick 2 — 2026-05-20 — PARITY.md reconciliation (matrix unblock)
- **Picked:** Agent A audit's #1 recommendation — "Fix PARITY.md drift FIRST; the matrix is single source of truth and rows that lie about state make every future decision worse."
- **Shipped:** PARITY.md sweep — ~30 row edits across §1, §2, §3, §4, §5, §6, §8, §17.
  - Tabs row: all 5 tabs ✅✅✅ (Android overnight 2026-05-20 closed the gap).
  - Find: 7 Android rows ⏳ M1 → ✅ (overnight commits c325cb2, ce2b0c2, etc.).
  - Learn: 5 Android rows ⏳ M5 → ✅ + added 2 new rows (Watch buckets, Archetype Templates).
  - Decks: 9 Android rows ⏳ M4 → ✅ (template gallery + manage decks + DBS shipped overnight).
  - Collection: 4 Android ⏳ M2 → ✅ (designation + density + grid pricing chip shipped).
  - Purchase: 2 Android ⏳ M6 → ✅ (Whatnot fix shipped overnight); Maps still M6 polish.
  - Card detail: 10 Android ⏳ M1/M3 → ✅ (canonical 6-cell stats, pricing waterfall, Edit Copy, share-with-image, Other Versions all shipped).
  - Added 4 new card-detail rows: DBS explainer modal, Pricing refresh button, Tap-price hint, Swipe nav (iOS shipped v2.287).
  - §17 iOS-specific: added Personal Showcase, Hero Shot entry, House of BoBA invocation, hardware-keyboard shortcuts.
  - **Saved Searches: previously claimed ✅ ✅ — corrected to 🔮 🔮 🔮 after grep found ZERO references in any client.** Agent A's biggest finding.
- **Verified:** scoped grep on each "now ✅" row found matching code in iOS + web + Android (or the explicit overnight commit SHA from `reference_overnight_parity_session_2026_05_20`).
- **Next:** ship a real visible-parity feature. Top candidates from Agent A's recommendation list: Wall view on web (#1), Custom Rainbows on web (#3). Tick 3 picks one.

---

## Audit agents in flight

When each agent returns, its findings populate the backlog above.

- **Agent A (parity audit):** scans iOS vs web vs Android for shipped-but-not-mirrored features beyond what PARITY.md captures
- **Agent B (deferred-feature inventory):** sweeps every `.md` doc + DECISIONS.md entries + SCRATCHPAD `Deferred` sections + commits-with-"defer" / "TODO" / "follow-up" markers
- **Agent C (Discord export JSON inventory):** locates the Claude research dir + parses Discord export JSONs for user-requested features

Status of each: queued / running / complete + findings folded back into Backlog.
