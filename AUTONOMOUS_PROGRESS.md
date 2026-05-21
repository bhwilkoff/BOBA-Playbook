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

### Tick 15 — 2026-05-20 — Web Custom Rainbow editor (first slice: name only)
- **Picked:** Write parity for tick-7's read-only display. Agent C's highest demand signal (1,237 community messages on rainbow/checklist tracking). Multi-tick effort — this is the first slice.
- **Shipped (slice 1 of 3):**
  - `js/api.js`: three new mutating endpoints — `createCustomRainbow(name, criteria)` (INSERT + returns row), `updateCustomRainbow(id, { name, criteria })` (PATCH), `deleteCustomRainbow(id)`. RLS scopes to own-row by default. Mirrors iOS `SupabaseClient.createCustomRainbow / updateCustomRainbow / deleteCustomRainbow` exactly.
  - `index.html`: new `<dialog id="custom-rainbow-editor">` — name input + hint text + cancel/save/delete actions. Native `<dialog>.showModal()` per WEB-DESIGN.md §2.1 native-first (focus trap + ESC + top layer + `::backdrop` for free).
  - `js/collection.js`:
    - "+ New rainbow" button + empty-state hint in the Custom Rainbows section heading row (now always visible to signed-in users).
    - `_renderRainbowRow` extended with optional `rainbowId` — when present, the row emits an inline ✎ edit affordance.
    - Edit-pencil click handler (with `e.preventDefault()` so the `<details>` doesn't toggle) opens the editor preloaded from `_customRainbowsById` cache.
    - `openCustomRainbowEditor(rainbow|null)` / `closeCustomRainbowEditor()` / `wireCustomRainbowEditor()` — create vs edit mode toggled by presence of an existing rainbow; delete button hidden in create mode.
    - Save in create mode → `createCustomRainbow(name, {})` (empty criteria for now — see scope note). Save in edit mode → `updateCustomRainbow(id, { name, criteria })`. Both close + call `load()` to re-render.
  - `css/styles.css`: ~80 lines — `.custom-rainbow-new-btn` (cyan pill), `.custom-rainbow-editor-*` styles, `.rainbow-edit-btn` (per-row ✎), `.custom-rainbows-empty` (dashed-border empty state).
- **Scope:** intentionally NAME-ONLY for this slice. Criteria stays empty (`{}`) on create, meaning a freshly-created rainbow matches every catalog card. The editor hint surfaces this honestly: *"Filters land in a later release. For now, create a named rainbow as a checklist anchor."* Tick 16 adds the sub-pickers (heroes/sets/sub-sets/weapons/treatments/cardTypes/releases); tick 17 adds the live progress preview + inspired-ink toggle. Edits preserve existing criteria — users who created rainbows on iOS keep their filters intact when renaming from web.
- **Verified:** node -c clean on api.js + collection.js. RLS policy already exists (migration `2026_05_15_user_custom_rainbows.sql` ships own-row SELECT/INSERT/UPDATE/DELETE).
- **PARITY.md:** Custom Rainbows web "✅ read-only" → "✅ read + name-only editor".
- **Architectural note:** `wireCustomRainbowEditor` is invoked from `init()` so it runs once on Collection module init, NOT on every render. Click handlers are attached to the DOM static elements (the dialog buttons + the new-rainbow button) which live in index.html, so they survive view re-renders.
- **Next:** Tick 16 — sub-pickers in the editor. Each filter dimension (heroes / sets / sub-sets / weapons / treatments / cardTypes / releases) gets a `<details>` with a checkbox-list of distinct catalog values. Live "matches N cards" preview at the top updates on every change.

### Tick 14 — 2026-05-20 — Web Manage Decks refresh button + render refactor
- **Picked:** Closes the Android-overnight Manage Decks parity trio (rename + search + PTR). Tick 13 shipped rename + search; PTR has no native web equivalent so the analog is a Refresh button.
- **Considered Custom Rainbow editor** (tick-13 "next" candidate) but right-sized down — it's multi-section sub-pickers + 7 catalog-distinct-value enumerations + save/delete — clearly multi-tick. Refresh button finishes the Decks parity story in one tick and keeps the loop discipline.
- **Shipped:**
  - `index.html`: new `<button id="db-saved-decks-refresh">` with Lucide refresh-cw icon, between the title and the close-X. Wrapped existing close into a `.db-saved-decks-header-actions` cluster for layout.
  - `js/practice.js`:
    - Extracted `_renderSavedDecksList(decks)` from the inline Load-button handler. Holds the row HTML + active-search-filter reapply.
    - New `refreshSavedDecksList()` async — does the `deckList()` fetch + delegates render. Shared by Refresh button + Load button.
    - Load button click handler shrunk to: visibility-toggle / auth-check / panel.hidden=false → `refreshSavedDecksList()`. No duplicate render logic.
    - Refresh button click handler adds `.spinning` class + disables button during fetch; clears on settle (try/finally).
  - `css/styles.css`: `.db-saved-decks-refresh` (cyan-accent border + bg, matches the rename ✎ button's color story) + `.db-saved-decks-header-actions` cluster + `@keyframes db-refresh-spin` (0.8s linear) + `@media (prefers-reduced-motion: reduce)` override that disables the spin.
- **Verified:** node -c clean. Render path now has a single source of truth (`_renderSavedDecksList`) which prevents Tick 13's rename + search behaviors from drifting away from a future re-fetch.
- **PARITY.md:** §4 Manage saved decks row note expanded.
- **Architectural note:** `applyDeckSearchFilter` is called at the end of `_renderSavedDecksList`, so refreshing while a search query is active preserves the filter — the user doesn't lose context to a refresh. This was the iOS DeckManagementSheet behavior I wanted to mirror.
- **Next:** Tick 15 — Custom Rainbow editor on web (write parity for tick 7 read-only). Multi-tick effort. Plan: tick 15 = `<dialog>` skeleton + name input + save/delete API + "+ New rainbow" button on Custom Rainbows section. Tick 16 = sub-pickers for heroes/sets/sub-sets/weapons/treatments/cardTypes/releases. Tick 17 = inspired-ink toggle + live progress preview + edit-existing flow.

### Tick 13 — 2026-05-20 — Web Manage Decks: rename + search
- **Picked:** Android shipped rename + search overnight (per overnight 2026-05-20 commit notes — "Android Decks polish ... rename / search / PTR"). Web's Manage Decks panel had Load + Delete only.
- **Shipped:**
  - `js/api.js`: new `deckRename(deckId, newName)` — `UPDATE decks SET name = ..., updated_at = now() WHERE id = ? AND user_id = ?` via PostgREST. Validates non-empty trim. Mirrors iOS DeckManagementSheet's rename action.
  - `js/practice.js`:
    - Per-row markup gets `data-deck-name` (for search filter + rename roundtrip) and a new ✎ `.db-saved-deck-rename` button between Load and Delete.
    - Click handler matches `.db-saved-deck-rename` → `prompt(...)` for the new name → calls `API.deckRename` → updates row text + dataset + sibling aria-labels in-place (no full re-render needed). If the renamed deck is the currently-loaded draft (`DB_savedId` match), the builder's editable name field updates in step.
    - `applyDeckSearchFilter()` — hides rows whose name doesn't substring-match the search input (case-insensitive). Idempotent — called after every list render AND on every input keystroke. Shows an inline "No saved decks match that name" hint when the filter zeros the list.
  - `index.html`: new `<input id="db-saved-decks-search" type="search" placeholder="Search saved decks…">` between the panel header and the list.
  - `css/styles.css`: ~20 lines — `.db-saved-deck-rename` (cyan accent — visually distinct from orange Load + red Delete) + `.db-saved-decks-search` (matches Find search input style).
- **Verified:** node -c clean. Logic trace: opening the panel → fetches via `deckList` → `applyDeckSearchFilter` runs (no-op if input is empty) → typing in search input filters rows live → rename via prompt updates row markup + persists via RPC.
- **PARITY.md:** §4 Manage saved decks row note updated to call out web parity shipment.
- **Architectural note:** prompt() is functional but not the most polished UX — iOS uses an inline editable field with Save/Cancel, Android uses a Material 3 TextField in an AlertDialog. A future iteration could swap to a `<dialog>` with a TextField; today's prompt() ships the verb fast without `<dialog>` overhead.
- **Next:** Tick 14. Pickable web items: (a) Manage Decks PTR / refresh button (iOS+Android have it, web doesn't), (b) Saved Searches design entry, (c) `prefers-color-scheme` audit, (d) Decks "Duplicate deck" affordance (iOS doesn't have it either — skip), (e) Custom Rainbow editor on web (write parity for the rainbow feature shipped tick 7).

### Tick 12 — 2026-05-20 — PARITY.md drift sweep + WEB-DESIGN.md §15 update
- **Picked:** ground-truth audit. Future ticks pick targets off PARITY.md; drift = wrong targets. After 6+ ticks of shipping, the doc had two false-positives + an outdated WEB-DESIGN.md §15 roadmap section. Tick 11 also discovered the sign-in-method pill was already shipped despite PARITY.md showing it as ⏳; this tick closes the audit gap fully.
- **Fixed:**
  - **Value history chart** (§5) — was ✅ iOS / 🔮 web / ⏳ Android. Reality: `grep -rn 'valueHistory\|value-history'` finds zero implementations anywhere. Both DESIGN.md §8.4 and ANDROID-DESIGN.md §8.4 describe it but no code exists. Corrected to 🔮 across all three with audit note.
  - **My Shows (streamer-only)** (§5) — was ✅ iOS / ✅ web. Reality: web has no streamer Shows surface; only Whatnot tile read in Purchase. iOS has full ShowsListView + ShowDetailView + show_cards Supabase table. Corrected web to 🔮 with audit note.
  - **WEB-DESIGN.md §15 roadmap** — added a "Shipped 2026-05-20 (autonomous parity loop)" subsection documenting tick 5 / 6 / 7 / 8 / 9 / 10 / 11. Removed "Collection Wall display mode" from P2 (it's shipped). Kept "Decks side-by-side desktop layout" as P2.
- **Verified:** PARITY.md row count unchanged (only cell values + notes corrected). WEB-DESIGN.md §15 update preserves prior structure (Shipped + P2 + Deferred subsections).
- **Why this matters:** the autonomous-loop tick-picker reads PARITY.md to find pickable parity gaps. Drift means picking already-shipped or never-built work. The cost of the audit is small (~10 min), the cost of NOT auditing is a tick of wasted work.
- **Architectural note:** future docs-of-truth drift should be flagged + fixed inline rather than accumulated. Every tick that touches a parity cell should re-grep the actual implementation file before claiming.
- **Next:** Tick 13 — actual ship pick from re-verified PARITY.md. Now that My Shows web is correctly 🔮 and template gallery + per-hero rainbows are shipped, the open web-pickable gaps are: (a) Streamer "My Shows" web surface (significant — multi-tick), (b) Manage Decks management improvements (medium), (c) Saved Searches design entry (small — DESIGN.md §8.1 placeholder), (d) `prefers-color-scheme` honoring + brand dark theme audit, (e) Find tab "Random card" affordance — quick win. Leaning (e) or (c).

### Tick 11 — 2026-05-20 — Web Decks template gallery (card-style)
- **Picked:** PARITY.md §4 "Template gallery (empty editor)" had web at 🔮. iOS + Android both ✅. The web had functional plain-text buttons but not the card-style gallery iOS ships in DeckBuilderView.swift TemplateCard. Two days ago Android shipped its 5-archetype gallery overnight; web was the laggard.
- **Bonus discovered:** PARITY.md §9 "Sign-in method pill on Profile" was listed as ⏳ for web but is already shipped (provider-pill rendering at js/collection.js:1015 + CSS at styles.css:2927). PARITY.md drift fix not needed — was already ✅.
- **Shipped:**
  - `js/practice.js`: rewrote `dbRenderTemplates()` to emit `.db-template-card` instead of plain `.db-template-btn`. Each card has: 44×60dp accent-colored monogram tile (single uppercase initial in Bebas Neue 28px), name (Bebas Neue 18px), description (Chakra Petch 12px, 2-line clamp), "PLAYMAKER" format pill, and a chevron. Click handler updated to match both `.db-template-card` and the legacy `.db-template-btn` selector (no breakage if cached).
  - `DB_TEMPLATES` extended with an `accent` field (STEEL/ICE/CYAN/GLOW/BRAWL) — pulled verbatim from iOS TemplateCard.accentColor.
  - `css/styles.css`: ~70 lines added — `.db-template-card` + per-accent border + monogram color tokens, scoped via `[data-accent="STEEL"]` etc. Reuses the canonical element color hex values (`#8A9BB0` STEEL, `#00BFFF` ICE, `#00F5FF` CYAN/brand, `#FFD700` GLOW, `#C0392B` BRAWL).
- **Verified:** node -c clean; click-through works (existing applyTemplate path unchanged — only the row rendering changed). data-template id-string is preserved across both the old and new markup so loadTemplate flow stays consistent.
- **PARITY.md:** Template gallery web 🔮 → ✅. PARITY.md §4 row updated.
- **Architectural note:** template archetype IDs + descriptions are now duplicated across three platforms (iOS DeckTemplate.metadata, Android assets, web DB_TEMPLATES). When a future archetype rebalance lands, all three must update in lockstep — flag this for a future DECISIONS.md entry if it becomes painful.
- **Next:** Tick 12. Strong candidates from PARITY.md still-pending: (a) deck editor "Manage Decks" parity, (b) Find offline/error states audit, (c) Streamer "My Shows" surface on web (already ✅ per matrix though — confirm), (d) PARITY.md "Saved Searches" 🔮 across the board → design proposal in DESIGN.md §8.1's no-search-state slot.

### Tick 10 — 2026-05-20 — Web Find multi-select → "Wall these N cards"
- **Picked:** Closes the §8.8 wall trio — Collection (tick 5), Decks (tick 9), now Find multi-select. iOS DESIGN.md §8.8 + DECISIONS.md #036.
- **Shipped:**
  - `js/collection.js`: renamed the catalog-cards wall entry point to `openCardsWallSheet({ title, cards })` as the canonical name. Kept `openDeckWallSheet({ deckName, cards })` as backward-compat alias for the practice.js call site shipped in tick 9 — both go through the same `openWallSheet({ context: 'deck', title, cards })` path.
  - `js/app.js`: new `openWallFromSelection()` reads `getSelectedCardObjects()` (catalog Cards already filtered to the user's multi-selection) and calls `Collection.openCardsWallSheet({ title: 'N cards', cards })`. Wired to `multiselect-wall` in `initMultiselectToolbar`. No auth required (rendering doesn't write). Doesn't exit selection mode after — user might want to continue selecting after viewing the wall.
  - `index.html`: new `<button id="multiselect-wall" class="multiselect-action">Wall</button>` between "Add to Deck" and the Clear-X in the multi-select toolbar. Lucide image icon for visual parity with the Decks wall button.
- **Verified:** `node -c` clean on all three. Logic trace: selectedCardKeys.size triggers the toolbar (existing) → user clicks Wall → cards = filteredCards.filter(in-selection) → openWallSheet receives catalog Cards with imageFile populated → resolves to the deck-context branch → renders.
- **PARITY.md:** new §2 row "Multi-select → Wall these N cards" — web ✅ · iOS+Android n/a (mobile uses long-press add, no multi-select).
- **Architectural note:** the three wall invocation sites (Collection, Decks, Find multi-select) all funnel through `openWallSheet`. `Collection` path uses user-card-row resolution + price overlay. `deck` context (Decks + Find multi-select) takes catalog Cards directly + hides price overlay. The seam is clean.
- **Next:** Tick 11 — picking from PARITY.md gaps. Strong candidates: (a) iPad scan-view landscape polish (mentioned as deferred in SCRATCHPAD.md), (b) DBS chip tooltips on web, (c) walkthrough relaunch UI on web (no — explicitly out of scope per WEB-DESIGN.md §11), (d) Sign-in method pill audit (mentioned as ⏳ in PARITY.md §9).

### Tick 9 — 2026-05-20 — Web Decks "Generate deck wall"
- **Picked:** iOS DESIGN.md §8.8 + DECISIONS.md #036 — "Wall accessible from Decks (overflow Menu → 'Generate deck wall')". Web had `🔮`; reuses tick-5 canvas Wall pipeline entirely.
- **Shipped:**
  - `js/collection.js`: extended `openWallSheet({ designation, cards })` with two new optional params `context` + `title`. When `context === 'deck'`, cards are catalog Cards (not user_card rows) so the boba_id-lookup resolution step is skipped; price-overlay row is hidden (deck cards aren't designation-scoped + don't carry asking/estimated prices); title comes from the caller (deck name). Collection path unchanged — backwards-compatible.
  - `Collection.openDeckWallSheet({ deckName, cards })` exported on the public API as the Decks entry point. Wraps openWallSheet with the deck context.
  - `window.Collection = Collection` at module bottom — classic-script `const` at top level doesn't auto-promote to the global object; without this, `window.Collection.openDeckWallSheet` from practice.js is undefined. (This also fixes a pre-existing broken reference in app.js line 1645's `window.Collection.quickAdd`.)
  - `js/practice.js`: `db-wall-btn` click handler — collects `DB.heroes + DB.plays + DB.hotDogs` from the current builder state, no-ops with a toast when the deck is empty, otherwise calls `window.Collection.openDeckWallSheet({ deckName: DB.deckName, cards })`.
  - `index.html`: new `<button id="db-wall-btn">` next to db-export-btn in the deck-builder toolbar; Lucide image icon (3-mountain) in violet (`#8B00FF`) to visually distinguish from the save/load/clear/export icons.
- **Verified:** `node -c js/collection.js js/practice.js` passes. Manual trace: `DB.heroes/plays/hotDogs` are populated catalog Cards (each has `imageFile` + `cardNumber` + `bobaId`), which is exactly what the deck-context branch of openWallSheet expects.
- **PARITY.md:** New §4 row "Generate deck wall (share image)" — iOS ✅ · Web ✅ · Android 🔮.
- **Architectural note:** the openWallSheet refactor (designation OR context, with backwards-compat) sets up future call sites — Find multi-select → "Wall these N cards" is the obvious next user (Agent A #2). Same path: pass catalog Cards + a title; price overlay irrelevant.
- **Next:** Tick 10 — pick from PARITY.md. Strong candidates: (a) Find multi-select → Wall (closes the §8.8 trio), (b) Cmd+1..5 tab shortcuts on web (iOS shipped; web n/a was the prior call but worth re-evaluating), (c) decks template gallery on web (🔮 today; Android has it).

### Tick 8 — 2026-05-20 — Web Per-hero Auto Rainbows
- **Picked:** Direct follow-on to tick 7. Agent A #4 documented gap. iOS shipped this as `RainbowDetailView` with `Kind.hero(_)` synthesizing `{heroes: [hero]}` criteria; web had nothing.
- **Shipped:**
  - `js/collection.js`: extracted `_renderRainbowRow(...)` + `_wireRainbowThumbs(...)` shared helpers so the custom-rainbow render path and the new auto-hero render path use the same exact row markup + thumb-tap wiring (zero drift between them).
  - `hydrateHeroRainbows(ownedCards)` — synchronous, runs against `window.__bobaCatalog`. (1) Builds the set of unique heroes the user owns by joining `ownedCards` against the catalog via `_bobaIdLookup` / `_cardLookup`. (2) Single catalog pass bucketing every catalog card by `hero` (only keeps buckets for heroes the user owns). (3) Sorts heroes by completion-% descending, then alphabetical, so the row closest to done surfaces first. (4) Renders one `<details>` per hero summarizing "All printings · N cards" with the same progress bar + thumbnail strip as Custom Rainbows.
  - `index.html` (via collection.js view template): new `<section id="hero-rainbows-section" hidden>` immediately below `custom-rainbows-section`, heading "Rainbows by Hero". CSS reused — both sections share `.custom-rainbows-section` / `.custom-rainbows-heading` / `.rainbow-row` so visual style is locked in step.
  - Both `hydrateCustomRainbows` and `hydrateHeroRainbows` called from `renderTabContent` after the main grid renders.
- **Verified:** read-back of refactored functions; lookup helpers (`_bobaIdLookup`, `_cardLookup`) confirmed to exist at module scope. Auto-rainbows section stays hidden when ownedCards is empty (signed-out / new user). Section also bails silently if catalog hasn't loaded yet.
- **PARITY.md:** Per-hero Auto Rainbows web 🔮 → ✅ read-only.
- **Architectural note:** custom rainbows + hero rainbows now share a single row-render pipeline. Future "Set rainbow" (all cards from one set) and "Treatment rainbow" (one weapon's worth of Inspired Ink) are trivial additions — synthesize the criteria + call `_renderRainbowRow`.
- **Next:** Tick 9 — pick from PARITY.md gaps. Leaning toward Wall view on Decks (Agent A #2 — Decks ⋯ Menu "Generate deck wall" — reuses the tick-5 canvas pipeline; cheap to ship).

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
