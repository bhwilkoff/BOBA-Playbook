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

### Tick 91 — 2026-05-20 — **Android** — Profile role-request: surface pending state
- **Cadence:** 91 % 5 = 1 → Android.
- **Picked:** Android Profile's role-request row said "Request mod or streamer role · Reviewed by Ben within 48h" for every user, even after a user had already submitted a pending request. The only feedback that the request landed was the post-submit Snackbar that disappeared after a few seconds. If the user re-opened Profile a day later they had no signal a request was pending — risk of duplicate submits + the dialog defaulted to "moderator" radio regardless of what they originally requested. iOS Profile already surfaces this state.
- **Shipped:**
  - `ProfileSheet.kt::item("role-request")`:
    - Reads `profile?.requestedRole` (already exposed on `UserProfile.requestedRole` at `ProfileService.kt:243`).
    - When pending: supporting text becomes "Pending: {Role} · Ben reviews within 48h" in cyan; button label becomes "Update" instead of "Request".
    - When not pending: original copy preserved verbatim.
  - `if (roleRequestOpen)` dialog:
    - `initialRole` derived from `profile?.requestedRole` (falls back to "moderator" when none).
    - `var requestedRole by remember(initialRole) { mutableStateOf(initialRole) }` — `remember` keyed on initialRole so opening the dialog for a different pending role resets the radio correctly.
    - Title flips to "Update role request" when `isUpdate` (mirrors the row's "Update" button label).
- **Verified:** UserProfile field exists at `ProfileService.kt:243` — `val requestedRole: String?`. BobaBrand.Cyan already imported (line 83). The existing `vm.requestRole(role, reason)` call site unchanged — the SQL RPC handles both "first submit" and "update existing" idempotently.
- **PARITY.md:** No row — UX polish on already-✅ Profile role-request row.
- **Next:** tick 92 = iOS; 93 = web; 94 = Android; 95 = opt.



### Tick 90 — 2026-05-20 — **OPTIMIZATION TICK (9th 1-in-5)** — drop iOS submitModRequest shims
- **Cadence:** opt rotation. Web 4 ticks (50/55/70/75). Android 3 (60/75/80). iOS now 3 (65/85/90).
- **Picked:** Tick 85 left `AuthManager.submitModRequest(reason:)` (3-line shim → `requestRole("moderator", ...)`) AND `SupabaseClient.submitModRequest(reason:)` (15-line REST writer) in place because removing them would touch ModRequestSheet. Trivial caller migration — `ModRequestSheet.swift::submitButton` is the only iOS site that called the AuthManager shim.
- **Shipped:**
  - `BOBAPlaybook/Views/Profile/ModRequestSheet.swift::submitButton` — replaced `await auth.submitModRequest(reason: ...)` with `await auth.requestRole("moderator", reason: ...)`. Same call shape, same behavior.
  - `BOBAPlaybook/Networking/AuthManager.swift` — dropped the 3-line `submitModRequest(reason:)` shim. Doc comment on `requestRole` cleaned up too.
  - `BOBAPlaybook/Networking/SupabaseClient.swift` — dropped the 15-line `submitModRequest(reason:)` REST writer (used PATCH to write directly to `user_profiles.mod_request_*` columns — the legacy path bypassed the `request_role` RPC). Doc comment on `requestRole` rewritten to call out the compat shim in the SQL layer (not the old Swift fn).
- **Verified:** `grep -rn submitModRequest BOBAPlaybook` returns only the new doc comments (legitimate breadcrumbs). `grep -rn \\.submitModRequest` returns zero hits — all method calls cleaned.
- **Line-count delta:** -19 net lines (counting the new doc-comment additions).
- **Cumulative across 9 optimization ticks:** -145 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23 · 90: -19).
- **Next:** tick 91 = Android; 92 = iOS; 93 = web; 94 = Android; 95 = opt.



### Tick 89 — 2026-05-20 — **Android** — Decks pool empty: disambiguate search-empty vs filter-empty
- **Cadence:** 89 % 5 = 4 → Android.
- **Picked:** `CardPoolGrid` rendered the same "Tweak the search above or use Filters in the Find tab to widen the catalog scope." message for ALL empty-pool causes, whether the user typed a search query or the Find-tab filters constrained the catalog. Users typing in the pool search couldn't see they'd typed too narrowly + had no one-tap clear. Web tick 78 + 83 + 88 established the pattern of disambiguating search-empty from structural-empty with brand-voice copy + productive CTA.
- **Shipped:**
  - `DecksScreen.kt::CardPoolGrid` signature gained `searchQuery: String = ""` + `onClearSearch: (() -> Unit)? = null` (defaults preserve source-compat for the tablet pane caller).
  - Empty-state branch splits on `searchQuery.isNotBlank()`:
    - **Search-empty**: headline "No cards match", body quotes the user's query, action button "Clear search" wired to `onClearSearch` callback.
    - **Filter-empty** (no query but Find filters constraining the catalog): headline "No cards in scope", body "Filters set on the Find tab are constraining the catalog. Open Find → Filters and widen or clear them." No CTA — the Find tab is one tap away in the NavigationBar.
  - Compact caller passes `searchQuery = poolQuery` + `onClearSearch = { poolQuery = ""; findViewModel.onEvent(FindEvent.QueryChanged("")) }`. The QueryChanged event ensures Find's results state matches, so the pool re-populates on the next recomposition.
  - Tablet caller unchanged — defaults kick in (no in-pool search field on tablet, so the "filter-empty" branch always fires).
- **Verified:** All three `CardPoolGrid(` call sites accounted for (compact + tablet only; the third match is the function declaration). `BOBAEmptyState` signature accepts nullable `actionLabel` + `onAction` (signature confirmed earlier).
- **PARITY.md:** No row — UX polish on already-✅ Decks pool row.
- **Next:** tick 90 = opt; 91 = Android; 92 = iOS; 93 = web; 94 = Android.



### Tick 88 — 2026-05-20 — **web** — Glossary tab + tap-to-copy (3-platform parity)
- **Cadence:** 88 % 5 = 3 → web.
- **Picked:** PARITY.md line 72 read "Glossary lookup (inline definitions) | ✅ | ✅ | ✅" but a `grep -rn Glossary` across `index.html` returned zero matches. Web has Rules / Strategy / Browse / Collect / Tournament panels but no Glossary. Real content-parity gap that PARITY.md misstated. Ticks 84 (Android) + 87 (iOS) both shipped tap-to-copy on their Glossary surfaces, so web needed both the surface itself AND the tap-to-copy.
- **Shipped:**
  - `index.html`:
    - New `<button class="play-tab" data-tab="glossary">Glossary</button>` between Collect and Tournament in the play-tabs row.
    - New `<div id="play-panel-glossary" class="play-panel" hidden>` with two `<section>` blocks (GAME GLOSSARY + TRADING GLOSSARY) — 11 game terms + 21 trading terms verbatim from iOS LearnView (the canonical content source).
    - Each row is a `<button class="glossary-row" data-term="..." data-def="...">` with separate `<span class="glossary-term">` + `<span class="glossary-def">` for typography. Native button = inherent focus + tap + screen-reader support.
  - `css/styles.css`:
    - `.glossary-list` flex column inside a rounded surface, `.glossary-row` button with border-top between rows.
    - Hover + focus-visible: cyan tint background + cyan outline (a11y).
    - `.glossary-row.copied` state: green-tinted background + a `::after` "✓ copied" badge in the top-right (the web analog of iOS's checkmark flash + Android's Toast).
    - `prefers-reduced-motion` override drops the row transition.
  - `js/app.js`:
    - Event delegation `document.addEventListener('click', ...)` matches `.glossary-row` via `e.target.closest`. Writes `"{term} — {definition}"` to `navigator.clipboard.writeText` + adds `.copied` class for 1.2s (matches the iOS / Android timing).
    - Guard for clipboard rejection (older browsers / file:// origins) — silent fall-through so the click doesn't error.
- **Verified:** `node -c js/app.js` clean. The existing `.play-tab` handler at app.js:727 doesn't need any change — it generically toggles `play-panel-${target}` and the new glossary panel is just another `.play-panel`.
- **PARITY.md:** Line 72 note rewritten to reflect that the web surface actually exists now + all three platforms share tap-to-copy.
- **Next:** tick 89 = Android; 90 = opt.



### Tick 87 — 2026-05-20 — **iOS** — Glossary tap-to-copy + hint banner (Android tick 84 parity)
- **Cadence:** 87 % 5 = 2 → iOS.
- **Picked:** Android tick 84 shipped tap-to-copy on Glossary term rows + the LEARN_LONG_PRESS_GLOSSARY hint banner. iOS Glossary had no equivalent affordance — term rows were inert display-only. Coaches who wanted to quote a definition in Discord had to manually retype or select-and-copy through the iOS text-selection menu.
- **Shipped:**
  - `BOBAPlaybook/Components/Design.swift::HintID` — new case `glossaryTapToCopy` ("hint.glossary_tap_to_copy") for the once-per-device dismissal flag.
  - `BOBAPlaybook/Views/Play/LearnView.swift`:
    - Added `import UIKit` (UIPasteboard + UINotificationFeedbackGenerator).
    - `@State private var copiedTermId: String?` — track which row's checkmark to flash.
    - `HintBanner(id: .glossaryTapToCopy, ...)` at top of `GlossaryView.body`. Same brand-voice copy as Android tick 84: "Tap a term to copy it" + "Tap any glossary term to copy the term + definition. Handy when you want to quote it in Discord or a coaching note."
    - Term row wrapped in `Button { copyTerm(t) }` with `.buttonStyle(.plain)` + `.contentShape(Rectangle())` so the whole row taps + accessibility-hint "Copies the term and definition to your clipboard."
    - Inline `Image(systemName: "checkmark.circle.fill")` (green) appears next to the tapped term for ~1.2s — the iOS analog of Android's Toast confirmation. Uses `.transition(.opacity)` so the checkmark fades in/out.
    - New `copyTerm(_:)` helper: writes `"{term} — {definition}"` to `UIPasteboard.general`, fires `UINotificationFeedbackGenerator.notificationOccurred(.success)` for haptic confirmation, sets `copiedTermId` with a 1.2s clear task.
- **Verified:** `HintBanner` + `HintsManager` are at `Design.swift` (already on the compile manifest). `UIPasteboard.general` + `UINotificationFeedbackGenerator` are stdlib. SourceKit cross-file noise preexisting.
- **PARITY.md:** No row — UX polish on already-✅ Glossary surface. 2-platform parity (Android tick 84 + iOS tick 87).
- **Next:** tick 88 = web; 89 = Android; 90 = opt.



### Tick 86 — 2026-05-20 — **Android** — Custom Rainbow row hints reflect all 7 dims
- **Cadence:** 86 % 5 = 1 → Android.
- **Picked:** Tick 81 extended the Custom Rainbow editor to all 7 criterion dimensions, but the list-row supporting-text helper at `RainbowsScreen.kt:172` still only iterated 3 dims (heroes / weapons / treatments) + the Inspired Ink toggle. A user who created a custom rainbow with "Sets: Season One" or "Card types: Hero" looked identical to "Any card" in the list — looked like the filter didn't save.
- **Shipped:**
  - `RainbowsScreen.kt::supportingContent`:
    - `buildList` extended to include sets / sub-sets / releases / card types counts. Same `${count} {dim}` shape, joined with ` · `, falls back to "Any card" only when truly empty.
    - Comment explains the tick-81 dependency so a future contributor doesn't shrink the list back.
- **Verified:** RainbowCriteria fields confirmed at `CustomRainbowRepository.kt:142-150` — all 8 fields exist on the data class (heroes / sets / subSets / elements / treatments / cardTypes / releases / inspiredInkOnly). The list-row code paths weren't reading 4 of them.
- **PARITY.md:** No row — the editor parity row stays ✅; this is the corresponding list-display polish.
- **Next:** tick 87 = iOS; 88 = web; 89 = Android; 90 = opt.



### Tick 85 — 2026-05-20 — **OPTIMIZATION TICK (8th 1-in-5)** — iOS orphan `hasPendingModRequest` removal
- **Cadence:** opt rotation. Web 4 opt ticks (50/55/70/75). Android 3 (60/75/80). iOS only 1 (65). Bias-toward-iOS this round.
- **Picked:** `AuthManager.hasPendingModRequest` (Bool property) was set internally on profile-load, role-request, and reset — but `grep -rn auth.hasPendingModRequest` across the entire iOS codebase returned ZERO external readers. The comment "Keep the legacy hasPendingModRequest flag in sync so any remaining call sites (AdminPanelView) keep working" lied — AdminPanelView doesn't read it (verified). Same for `SupabaseClient.hasPendingModRequest()` (the REST helper) — zero callers since the generalized `requestRole` flow shipped (DECISIONS.md #038).
- **Shipped:**
  - `BOBAPlaybook/Networking/AuthManager.swift`:
    - Dropped `private(set) var hasPendingModRequest = false` (line 21).
    - Dropped 3 assignment sites (profile-load line ~153, requestRole line ~234, resetState line ~495) + 2 lines of doc comments justifying the legacy flag.
    - Updated `pendingRoleRequest`'s doc comment to drop the reference to `hasPendingModRequest`. -10 lines net.
  - `BOBAPlaybook/Networking/SupabaseClient.swift`:
    - Dropped `func hasPendingModRequest() async throws -> Bool` + its 9-line body. -13 lines.
- **Verified:** `grep -rn hasPendingModRequest BOBAPlaybook` post-edit returns nothing — all sites cleaned. SourceKit cross-file noise is preexisting. The "MARK: - Mod promotion requests" header preserved as a section divider for the remaining mod-related fns (fetchPendingModRequests, reviewModRequest).
- **Line-count delta:** -23 lines.
- **Cumulative across 8 optimization ticks:** -126 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23).
- **Next:** tick 86 = Android; 87 = iOS; 88 = web; 89 = Android; 90 = opt.



### Tick 84 — 2026-05-20 — **Android** — Glossary tap-to-copy + wire orphan hint
- **Cadence:** 84 % 5 = 4 → Android.
- **Picked:** `HintsStore.Ids.LEARN_LONG_PRESS_GLOSSARY` was registered as a hint ID but had zero rendering sites — `grep -rn LEARN_LONG_PRESS_GLOSSARY` found only the definition + `all` array entry. Orphan UX scaffolding. The natural use case for a glossary hint is "tap-to-copy" — coaches frequently quote definitions verbatim in Discord and game-night chat, so a clipboard affordance is genuinely useful.
- **Shipped:**
  - `LearnArticleScreen.kt::GlossaryPage`:
    - Hilt-injected `HintsViewModel` + collected dismissal state for `LEARN_LONG_PRESS_GLOSSARY`.
    - `BOBAHintBanner` at top of the page (above the search field) with brand-voice copy: "Tap a term to copy it" + "Tap any glossary term to copy the term + definition. Handy when you want to quote it in Discord or a coaching note." Dismiss writes to DataStore + the hint never reappears on that device.
    - `LocalClipboardManager` + `LocalContext` resolved once at composable root.
  - `TermRow` signature gained `onCopy: () -> Unit` callback and `Modifier.clickable(onClickLabel = "Copy term")`. Click-label is the a11y string TalkBack will announce.
  - New `copyTermToClipboard(clipboard, context, section)` helper writes `"{term} — {definition}"` as plain text + fires a short Toast "Copied "{term}"" so users see the action register.
  - Both call sites (Game glossary + Trading glossary) updated to pass the lambda.
- **Verified:** `HintsViewModel.dismiss` + `isDismissed` already wired in CollectionScreen / ScanScreen / DecksScreen / CardDetailScreen — same pattern used here. `LocalClipboardManager` is the Compose-native canonical pattern (no `androidx.core.content.ClipData` needed for a simple text copy). Toast import inlined via `android.widget.Toast` so no new top-of-file import.
- **PARITY.md:** No row — informational hint + new in-screen action; the Glossary surface stays ✅.
- **Next:** tick 85 = opt; 86 = Android; 87 = iOS; 88 = web.



### Tick 83 — 2026-05-20 — **web** — Decks saved-decks search-empty: brand-voice + Clear button
- **Cadence:** 83 % 5 = 3 → web.
- **Picked:** Manage Decks search-empty rendered a single line "No saved decks match that name." with no productive action. Same anti-pattern that tick 78 fixed for Collection empty states. Universal-feature-states skill: empty states must invite action.
- **Shipped:**
  - `js/practice.js::applyDeckSearchFilter` — replaced the single `<div>` hint with a structured empty-state block:
    - `<p class="db-saved-decks-empty-headline">` quotes the user's search query so they can confirm it matched what they typed.
    - `<button class="btn-ghost-sm" data-action="clear-deck-search">Clear search</button>` wipes the input + refocuses it + re-runs `applyDeckSearchFilter` so the full list reappears.
    - Query string HTML-escaped inline (no DOM helper available in scope).
  - `css/styles.css::.db-saved-decks-search-empty` — flex column with brand-voice headline (`rgba(255,255,255,0.6)` for slightly more contrast than the default 0.3-muted), button below with 1rem padding.
- **Verified:** `node -c js/practice.js` clean. The handler wiring uses `addEventListener` (not `{once:true}`) because the hint element is recreated on every re-filter cycle so the listener doesn't leak.
- **PARITY.md:** No row — UX polish on already-✅ Manage Decks row.
- **Next:** tick 84 = Android; 85 = opt.



### Tick 82 — 2026-05-20 — **iOS** — Collection per-designation empty states (3-platform parity)
- **Cadence:** 82 % 5 = 2 → iOS.
- **Picked:** Web tick 78 + Android tick 79 both shipped per-designation brand-voice empty states with productive next-action copy. iOS was the last platform with the generic "Add cards from any card detail view." line. Closes the 3-platform parity gap on the same surface.
- **Shipped:**
  - `CollectionView.swift::emptyState`:
    - 5 designation-specific `(headline, body)` pairs verbatim with web tick 78 + Android tick 79:
      - personal: "No personal cards yet" + "Scan a card or use Quick Add from the Find tab to start your stack."
      - for_sale: "Nothing for sale yet" + "Mark a card from your Personal stack to start moving it."
      - for_trade: "Nothing for trade yet" + "Flag a card to find a trading partner once trading launches."
      - wanted: "No wanted cards yet" + "Flag the cards you're chasing — start with the ones at the top of your list."
      - grails: "No grails yet" + "Mark the cards you'd cross a state line for."
    - **Search-empty branch** added: when `searchText.trimmingCharacters(...)` is non-empty, headline becomes "No matches" + body names the trimmed search query, with a "Clear search" `Button` (cyan accent) that wipes `searchText`. Mirrors web tick 78's branch.
    - Headline now uses `textSecondary` (not muted) — small contrast bump for the headline so it reads as the brand-voice statement and the body is the support copy.
- **Verified:** All five Designation cases at `Models/UserCard.swift:94-99`. `Design.Colors.bobaCyan` + `textSecondary` confirmed at Design.swift. SourceKit cross-file noise (Cannot find 'CardStore'/'Card') is preexisting per project state — not real errors.
- **PARITY.md:** No row — UX polish on already-✅ Collection row. 3-platform parity now in lockstep on the same five copy strings.
- **Next:** tick 83 = web; 84 = Android; 85 = opt.



### Tick 81 — 2026-05-20 — **Android** — Custom Rainbow editor: full 7-dimension parity
- **Cadence:** 81 % 5 = 1 → Android.
- **Picked:** PARITY.md line 111 read "✅ basic (3 dimensions)" for Android Custom Rainbows. Web tick 16 + iOS surface all 7 criterion dimensions; Android editor only had Heroes / Weapons / Treatments + Inspired Ink. The remaining 4 dimensions (Sets / Sub-sets / Releases / Card types) were already in the data layer (`RainbowCriteria` already had them; `toJsonString`/`fromJson` already round-tripped). The editor UI was the gap.
- **Shipped:**
  - `CustomRainbowEditorSheet.kt`:
    - 4 new `rememberSavedSet` state vars (`sets`, `subSets`, `releases`, `cardTypes`) pre-filled from `existing?.criteria` so edit mode round-trips cleanly.
    - 4 new option-derivation `remember(catalog) { ... }` blocks — pulled from `Card.set` / `Card.subSet` / `Card.release` / `Card.cardType`, distinct + sorted, capped at 40 for sub-sets to keep the picker manageable on phones.
    - 4 new `BOBASectionHeader + ChipsPicker` sections in the scrollable column body — same shape as the existing Weapons / Heroes / Treatments sections.
    - Save payload extended to populate all 4 new fields on the `RainbowCriteria` constructor.
    - Header comment updated to reflect full parity (was "Sets / Sub-sets / Releases land in a polish pass").
- **Verified:** Card fields confirmed at `core/domain/model/Card.kt:33-39`. RainbowCriteria already had all 8 fields at `CustomRainbowRepository.kt:142`. `toJsonString` already serializes all 8 keys (lines 156-162). `fromJson` already round-trips (line 173+). No schema migration needed — the data layer was always ready.
- **PARITY.md:** Line 111 flipped from "✅ basic (3 dimensions)" to "✅" with the tick-81 note + the 7-dimension list spelled out.
- **Next:** tick 82 = iOS; 83 = web; 84 = Android; 85 = opt.



### Tick 80 — 2026-05-20 — **OPTIMIZATION TICK (7th 1-in-5)** — Android orphan `onProfileClick` param
- **Cadence:** opt rotation. Web 4 opt ticks (50/55/70/75). iOS 1 (65). Android 2 (60/75). Bias toward iOS or Android. Picked Android — clean orphan signal.
- **Shipped:**
  - `CollectionScreen.kt::CollectionScreen` — dropped `onProfileClick: () -> Unit` param. The comment "unused per feedback_profile_only_on_find; kept for nav signature symmetry" was a weak justification — Profile button is iOS+Android-only on Find tab; CollectionScreen has no use for the callback. -1 line.
  - `BOBAApp.kt:452` — dropped the matching `onProfileClick = onProfileClick` wiring on the only call site. -1 line.
- **Verified:** Single call site at BOBAApp.kt:450 (`grep -rn CollectionScreen(`). FindScreen still receives + uses `onProfileClick` (`IconButton(onClick = onProfileClick)` at FindScreen.kt:188) — unchanged. No other Compose callers to break.
- **Line-count delta:** -2 lines (Android).
- **Cumulative across 7 optimization ticks:** -103 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2).
- **Next:** tick 81 = Android; 82 = iOS; 83 = web; 84 = Android; 85 = opt.



### Tick 79 — 2026-05-20 — **Android** — Collection per-designation empty states (web tick 78 parity)
- **Cadence:** 79 % 5 = 4 → Android.
- **Picked:** Android Collection's empty state was generic — every designation rendered "No {designation} cards yet · Scan a card or browse Find to add your first one." Tick 78 just shipped tuned per-designation copy on web; Android lagged. Real cross-platform parity gap on the same surface.
- **Shipped:**
  - `CollectionScreen.kt::CollectionScreen` empty-state branch:
    - `when (designation)` → 5 brand-voice `headline + body` pairs matching web tick 78 verbatim:
      - PERSONAL: "No personal cards yet" + "Scan a card or use Quick Add from the Find tab to start your stack."
      - FOR_SALE: "Nothing for sale yet" + "Mark a card from your Personal stack to start moving it."
      - FOR_TRADE: "Nothing for trade yet" + "Flag a card to find a trading partner once trading launches."
      - WANTED: "No wanted cards yet" + "Flag the cards you're chasing — start with the ones at the top of your list."
      - GRAILS: "No grails yet" + "Mark the cards you'd cross a state line for."
    - **Only PERSONAL gets a "Scan a card" CTA button**. Other designations need the user to switch to Find (or Personal) — but Android's NavigationBar is permanently visible at the bottom, so a "Go to Find" CTA would be no-op chrome. Body copy carries the wayfinding instead. (Web tick 78 has "Browse Find" because web's mobile nav drawer is collapsible; Android doesn't have that constraint.)
    - `BOBAEmptyState`'s `actionLabel` + `onAction` accept null cleanly (signature verified).
- **Verified:** Designation enum at `core/domain/model/Designation.kt` has the five expected values. BOBAEmptyState signature at `core/ui/.../BOBAEmptyState.kt:37` accepts `actionLabel: String? = null` + `onAction: (() -> Unit)? = null`. Search-empty branch (existing) preserved verbatim — "Clear search" CTA still wired.
- **PARITY.md:** No row — UX polish on already-✅ Collection row.
- **Next:** tick 80 = opt; 81 = Android; 82 = iOS; 83 = web; 84 = Android.



### Tick 78 — 2026-05-20 — **web** — Collection empty states: brand-voice + productive CTA
- **Cadence:** 78 % 5 = 3 → web.
- **Picked:** Per-designation Collection empty states said only "No cards in {Personal/Sale/Trade/Wanted/Grails} yet." with no next-action button. The universal-feature-states skill requires brand-voice copy + a productive next-action — what the user is most likely to want to do RIGHT NOW. Search-empty branch added the same anti-pattern: "No cards match 'xyz'" with no way out other than re-tapping the toolbar's clear-× button.
- **Shipped:**
  - `js/collection.js::renderCollectionView` — replaced single `<p class="collection-empty">` with a structured empty-state block:
    - **Per-designation copy table** (`emptyCopyByDesig`): headlines + bodies tuned to what the user is most likely to do next:
      - Personal: "No personal cards yet" + "Scan a card or use Quick Add from the Find tab to start your stack."
      - For Sale: "Nothing for sale yet" + "Mark a card from your Personal stack to start moving it."
      - For Trade: "Nothing for trade yet" + "Flag a card to find a trading partner once trading launches."
      - Wanted: "No wanted cards yet" + "Flag the cards you're chasing — start with the ones at the top of your list."
      - Grails: "No grails yet" + "Mark the cards you'd cross a state line for."
    - **Productive CTA**: "Browse Find" button (`data-action="go-to-find"`) routes to the Find tab via `window.showView('find')`. Wired in the same render path that wires the existing wall + search-clear handlers.
    - **Search-empty branch**: distinct copy + a "Clear search" button (`data-action="clear-collection-search"`) that wipes `_collectionSearchText` + re-renders + refocuses the new input.
  - `css/styles.css::.collection-empty` — restructured to a flex column with brand-display headline (`--font-display`, `var(--boba-text-secondary)`), mono body line (`--font-mono`, muted), and CTA button spacing. Bounds body line at `max-width: 32ch` for readability.
- **Verified:** `node -c js/collection.js` clean. `window.showView` confirmed at app.js:631 (definition at line 517).
- **PARITY.md:** No row — UX polish on already-✅ Collection row.
- **Next:** tick 79 = Android; 80 = opt.



### Tick 77 — 2026-05-20 — **iOS** — Find empty-state dynamic body (3-platform parity)
- **Cadence:** 77 % 5 = 2 → iOS.
- **Picked:** iOS Find emptyState rendered a static "No cards match your search" with no indication WHICH filter was producing zero results. Web tick 29 + Android tick 74 both shipped a dynamic line that names the active filters. Three-platform parity gap.
- **Shipped:**
  - `BOBAPlaybook/Views/Search/SearchView.swift::emptyState`:
    - Headline shortened to "No matches" (parity with Android `find_no_results_title`).
    - New `Text(emptyBodyText)` between headline and Clear button — the dynamic-filter line.
  - New `private var emptyBodyText: String` computed property — collects active filter atoms in display order (searchText quoted, weapons sorted, set, treatment, release, showcase name via `Showcases.byId(id)?.name`, image-only, power range). Three branches: empty (no active filters), single ("Nothing matches \"FIRE\". Try loosening or removing the filter."), multi ("Nothing matches all of: A · B · C. Try removing one.").
- **Verified:** `Showcases.byId(_:)` exists at `BOBAPlaybook/Models/Showcase.swift:135`; returns `Showcase?` with a `name: String` field at line 19. SourceKit cross-file noise (Cannot find 'CardStore') is preexisting per project state; not a real compile error.
- **PARITY.md:** No row — empty-state polish on already-✅ Find row.
- **Next:** tick 78 = web; 79 = Android; 80 = opt.



### Tick 76 — 2026-05-20 — **Android** — Generate Deck Wall (web tick 9 + iOS §8.8 parity)
- **Cadence:** 76 % 5 = 1 → Android.
- **Picked:** Real parity gap from PARITY.md line 95: Generate-deck-wall shipped on iOS (✅) + web tick 9 (✅) but Android was 🔮. Android Decks editor had no Wall affordance even though `CollectionWall` already shipped a graphicsLayer-record + `WallShareHelper` capture/share pipeline that's directly reusable.
- **Shipped:**
  - New `android/.../feature/decks/DeckWallSheet.kt` — full-screen `ModalBottomSheet` rendering `draft.cards` as a near-black small-multiples `LazyVerticalGrid` w/ the same `graphicsLayer.record` capture pattern + `WallShareHelper.share()` call as `CollectionWall`. Same 200-card HARD_CAP with GLOW-yellow truncation note (parity with web tick 43 + Android tick 64 + iOS tick 72). Empty-draft branch shows a placeholder instead of an empty share-button.
  - `DeckEditorSheet.kt`:
    - `DeckEditorSheet` (modal) gained an `onGenerateWall: () -> Unit = {}` param + IconButton (Icons.Default.ViewModule) in the top action row, gated on `draft.cards.isNotEmpty()`.
    - `DeckEditorContentInline` (tablet pane) gained the same param + an OutlinedButton "Wall" alongside Rules / Legality, gated on `hasCards`.
    - `DeckEditorContent` (sheet inner content) gained the param + IconButton wiring.
    - All three call sites default the param to `{}` so unrelated callers stay source-compatible.
  - `DecksScreen.kt`:
    - `DecksCompactScreen` gained `var wallOpen by remember { mutableStateOf(false) }` + `if (wallOpen) DeckWallSheet(...)` block; wires `onGenerateWall = { wallOpen = true }` on the editor sheet.
    - `DecksTabletScreen` gained its own `wallOpen` + sheet block + wired into the inline editor.
- **Verified:** Card field shape verified (`bobaId`, `imageFile`, `isSealed`, `displayName` all on `core/domain/model/Card.kt`). `WallShareHelper.share()` signature accepts `username = null` cleanly (text-body branches on `publicLink != null`). `BOBACardCell` signature accepts `imageFile` + `isSealed` + `contentDescription`. Java not on PATH for gradle compile; iterate on CI / next-iteration if surface issues.
- **PARITY.md:** Line 95 flipped to ✅ Android with note on the WallShareHelper reuse + dual editor surfaces (modal IconButton + tablet OutlinedButton).
- **Next:** tick 77 = iOS; 78 = web; 79 = Android; 80 = opt.



### Tick 75 — 2026-05-20 — **OPTIMIZATION TICK (6th 1-in-5)** — orphan Android string + orphan auth fn
- **Cadence:** opt-rotation. Web has had 3 opt ticks (50/55/70), iOS 1 (65), Android 1 (60). Bias-toward-not-web this round.
- **Shipped two orphan removals:**
  - **Android** — `find_no_results_body` string resource in `app/src/main/res/values/strings.xml`. Tick 74 replaced the static body with a runtime-computed dynamic line (filter-naming) and stopped referencing the resource. `grep -rn find_no_results_body android/` returned only the resource def itself. -1 line.
  - **Web** — `authSetSession(accessToken, refreshToken)` export in `js/api.js`. Defined at api.js:914 but `grep -rn authSetSession` across all js/html returned only the definition itself. The actual session-restore path uses `authRefreshSession` (called from auth.js:303, 342, 396). -7 lines.
- **Verified:** `node -c js/api.js` clean. `grep -rn find_no_results_body` and `grep -rn authSetSession` both return only the historical-reference diff context after removal.
- **Line-count delta:** -8 lines (1 Android + 7 web).
- **Cumulative across 6 optimization ticks:** -101 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8).
- **Next:** tick 76 = Android (76 % 5 = 1); tick 77 = iOS; 78 = web; 79 = Android; 80 = opt.



### Tick 74 — 2026-05-20 — **Android** — Find empty-state body line (web tick 29 parity)
- **Cadence:** 74 % 5 = 4 → Android.
- **Picked:** Android Find empty state surfaced a single static body line "Try a different search, or remove a filter." regardless of what filters were active. Web tick 29 already shipped a dynamic body line ("Nothing matches FIRE. Try loosening or removing the filter.") that names the active filters back to the user. Real parity gap on the same surface — Android user with five filters active had no clue WHICH one was producing the empty results.
- **Shipped:**
  - `android/app/src/main/java/com/bobaplaybook/app/feature/find/FindScreen.kt`:
    - Replaced static `stringResource(R.string.find_no_results_body)` with a runtime-computed `body` string.
    - `buildList` collects active filter atoms in display order: query (quoted), weapons, set, treatment, release, showcase name, image-only flag, power range.
    - Three branches based on `active.size`: empty (no active filters — generic "Try a different search."), single-filter (names the one filter — "Nothing matches FIRE. Try loosening or removing the filter."), multi-filter (joins with " · " — "Nothing matches all of: FIRE · power 100–160. Try removing one.").
    - `Showcases.byId(id)?.name` resolves the showcase enum back to a human-readable name (already imported at top of file).
- **Verified:** FindUiState fields verified (lines 24–36): query / activeWeapons / activeSet / activeTreatment / activeRelease / showcaseId / hasImageOnly / powerMin / powerMax all present. `Showcases.byId` exists at Showcase.kt:154. Showcases import already at FindScreen.kt:87. Pure-Kotlin string builder — no Compose API risk.
- **PARITY.md:** No row — empty-state polish on already-✅ Find row.
- **Next:** tick 75 = opt (5th-in-5 cadence); tick 76 = Android (76%5=1).



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

### Tick 73 — 2026-05-20 — **web** — Active-filter chips row
- **Cadence:** 73 % 5 = 3 → web.
- **Picked:** Find tab showed only a numeric badge count + empty-state hint to communicate active filters. The filter panel itself was inline-accordion (collapsed by default). A user with WOBA + FIRE + power 100-160 + a Set chose had no always-visible way to see WHAT was filtering — they had to expand the panel + scan all controls to find each one.
- **Shipped:**
  - `index.html`: new `<div id="active-filter-chips" hidden>` between the multi-select toolbar and the filter panel.
  - `js/app.js`:
    - `renderActiveFilterChips()` — iterates current filter state, builds a chip per active filter (Element / Set / Treatment / Release / Showcase / Image-only / Power range), each with × icon. Click → calls a per-filter remove function (resetting that field + UI control + calling applyFilters). `{ once: true }` listener since the chip gets re-rendered on next badge update anyway.
    - Called from `updateFilterBadge` so the chip row stays in lockstep with the badge.
  - `css/styles.css`: `.active-filter-chips` cyan-tinted bar with wrapping pill chips. Focus-visible cyan outline for keyboard a11y. Matches the design language of the other cyan pill affordances (Wall button etc.).
- **Verified:** node -c clean. Trace: pick FIRE + WOBA + power 100-160 → three chips appear. Click each × → filter cleared + chip disappears + grid re-filters.
- **PARITY.md:** No row — UX polish.

### Tick 72 — 2026-05-20 — **iOS** — Wall caller surface tick-67 cap to user
- **Cadence:** 72 % 5 = 2 → iOS.
- **Picked:** Tick 67 added `ShowWallComposer.HARD_CAP = 200` as a safety net, with a comment noting "caller is responsible for messaging the user when they pass > HARD_CAP." Today the only Wall caller, `CollectionWallSheet`, doesn't surface the truncation — a user with 500 owned cards who taps "Select all" silently gets a 200-card wall and loses their grails without explanation.
- **Shipped:**
  - `CollectionWallSheet.swift::cardSelector`: when `included.count > ShowWallComposer.HARD_CAP`, render a GLOW-yellow `Label` with `info.circle` icon beneath the "N of M · ★ K" line: "Only the first 200 cards will render — narrow the selection for a wall of every card." Mirrors web tick 43 + Android tick 64 truncation notes.
- **Verified:** SourceKit isolation pre-existing. Color(hex:) helper exists in Design.swift (used elsewhere).
- **PARITY.md:** No row — informational polish on already-✅ Wall row.

### Tick 71 — 2026-05-20 — **Android** — Deck save error messaging
- **Cadence:** 71 % 5 = 1 → Android.
- **Picked:** `DecksViewModel.save(onResult: (Boolean) -> Unit)` collapsed every failure to a single boolean — the caller's Snackbar said "Couldn't save deck. Check connectivity." regardless of cause. Real causes (sign-out race, empty-name silently slipping past button-disable, Supabase RLS rejection) all merged. Sign-out is especially misleading — user looks for connectivity issues that don't exist.
- **Shipped:**
  - `DecksViewModel.kt`: new overload `fun save(onComplete: (errorMessage: String?) -> Unit)` — null = success, otherwise a user-facing message. Branches:
    - Sign-out → "Sign in to save your deck."
    - Empty name → "Give your deck a name before saving."
    - Empty deck → "Add at least one card before saving."
    - Repo returned null → "Couldn't save. Check connectivity and try again."
  - Boolean-result overload preserved as a thin wrapper for backward-compat (one other call site at line 584 uses it; future refactor opportunity).
  - `DecksScreen.kt` editor save callback now uses the richer signature — surfaces `errorMessage` directly in the appSnackbar instead of the static "Couldn't save..." line.
- **Verified:** structural edit — boolean overload kept so existing tablet-pane call site unchanged.
- **PARITY.md:** No row — error-message polish on already-✅ deck save row.

### Tick 70 — 2026-05-20 — **OPTIMIZATION TICK (web, 5th 1-in-5)** — orphan api.js fns
- **Cadence:** opt-rotation back to web (50+55+70 web · 60 Android · 65 iOS so far).
- **Shipped:** removed two truly-orphan exports from api.js:
  - **`hasPendingModRequest()`** — confirmed zero callers via `grep -rE "(API|window\.API)\.hasPendingModRequest"`. The function predated DECISIONS.md #038's generalized role-request; the new path uses `getCachedRole()` + `requested_role` directly.
  - **`submitModRequest(reason)`** — replaced by `requestRole(role, reason)` per #038. The line-737 comment ("Replaces submitModRequest for new...") signaled intent; the deprecated fn was left in place as a compat shim. Zero external callers — confirmed via grep on `API.submitModRequest`.
  - Both were defined + exported but never called outside api.js. Removed function bodies + the export entries.
- **Line-count delta:** -28 lines from api.js.
- **Verified:** node -c clean. `grep -rn` on both function names returns only api.js historical-reference comments (line-737 comment kept as breadcrumb for future contributors who might wonder why the role-request RPC exists alongside `submit_mod_request` SQL compat shim).
- **Not removed:** `adminFetchPendingModRequests` + `adminReviewModRequest` — confirmed still in use by collection.js admin panel (lines 2336 + 2362).
- **Cumulative across 5 optimization ticks:** -93 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28).

### Tick 69 — 2026-05-20 — **Android** — Watch feed: error-vs-empty disambiguation + safe failure
- **Cadence:** 69 % 5 = 4 → Android.
- **Two real bugs found in WatchViewModel:**
  1. **Stuck-loading on exception** — `service.loadAll()` had no try/catch. Worker offline / parse error / timeout would propagate as an unhandled coroutine exception, leaving `state.isLoading = true` forever. User saw infinite spinner with no recovery path.
  2. **Misleading "couldn't load" on empty feed** — the prior logic treated "loaded successfully but all three categories empty" the same as "fetch failed." A BoBA YouTube channel with no current content briefly would surface "Couldn't load the YouTube feed. Pull to retry."
- **Shipped:**
  - `WatchViewModel.kt`:
    - `runCatching { service.loadAll() }` + `.fold(onSuccess, onFailure)` — exceptions now resolve to a proper error state with `isLoading = false`.
    - Success path NO LONGER sets `error` when the bundle is empty — instead sets new `isEmpty: Boolean = true` field on `WatchUiState`.
    - `error` is now reserved for actual fetch failures.
  - `WatchPage.kt::emptyBundle` branch:
    - Headline now branches on `state.error != null` — "Couldn't load videos" only fires on real fetch error; otherwise "No videos right now."
    - Body line same — uses `state.error` when present, falls back to "Check back soon — the BoBA channel updates frequently." for the legitimate empty case.
- **Verified:** changes are additive on WatchUiState (new field with default = false); no destructuring breaks.
- **PARITY.md:** No row — Android-side bug fixes on already-✅ Watch row.

### Tick 68 — 2026-05-20 — **web** — Avatar upload: friendly errors + size guard + success toast
- **Cadence:** 68 % 5 = 3 → web.
- **Picked:** Avatar upload error path used blocking `alert('Could not upload avatar: ' + e.message)` — same anti-pattern as tick 54's multi-select alerts, and the raw error message was often unfriendly ("HTTP 401" or "TypeError: failed to fetch"). Also no client-side size check despite the Worker's 2MB cap, so a too-large image would fail with a server error after the upload trip.
- **Shipped:**
  - `js/collection.js`:
    - **Client-side 2MB guard** BEFORE the upload — fails fast with a clear message if the cropped JPEG exceeds the Worker's cap. (After crop, blobs usually under 200KB; only a high-pixel-density source + low-compression encoder could trip this, but it's possible.)
    - **Friendly error mapping** — 401/expired/"signed in" → "Sign-in expired. Sign in again and retry."; network/fetch errors → "Network error. Check your connection and retry."; everything else falls back to the raw message.
    - **`showToast` instead of `alert`** — non-blocking, matches the tick-54 pattern. Falls back to alert() only when the toast helper isn't loaded (defensive).
    - **Success toast** — "Avatar updated." on success. Closes the feedback loop; was previously silent (just the avatar refreshing in place).
- **Verified:** node -c clean.
- **PARITY.md:** No row — UX polish on already-✅ avatar upload row.

### Tick 67 — 2026-05-20 — **iOS** — ShowWallComposer 200-card safety cap (parity with web 43 + Android 64)
- **Cadence:** 67 % 5 = 2 → iOS.
- **Picked:** Web (tick 43) capped Wall at 200 cards to avoid canvas-height limits; Android (tick 64) capped to avoid bitmap-capture OOM. iOS uses a fixed 1080×1512 canvas so the canvas-size concern doesn't apply, but `fetchFullImages` spawns N parallel URLSession tasks + decodes N UIImage instances into memory simultaneously. At 500 cards = 500 in-flight UIImages on the main actor — meaningful memory pressure on older iPhones (12 mini, SE).
- **Shipped:**
  - `BOBAPlaybook/Components/ShowWallComposer.swift`:
    - New `static let HARD_CAP: Int = 200` constant + comment explaining the three reasons (parallel-decode memory, sub-50pt unreadable cells, JPEG output 2MB limit).
    - `compose(...)` now truncates both `cards` and `bigHits` arrays to HARD_CAP before fetching + rendering. Defensive — callers should message the user when they pass > HARD_CAP, but the cap is the second-of-two defenses.
- **Verified:** SourceKit isolation noise (UIKit unavailable in CLI) not real. Cap math: 1080-wide canvas / sqrt(200 × 1.4) cols ≈ 8 cols × ~135pt cell. Readable. At 500 cards: 8 × 26 = 208 cells, ~52pt each — illegible. Cap is well-chosen.
- **PARITY.md:** No row — iOS-side safety net matching the existing web + Android caps.

### Tick 66 — 2026-05-20 — **Android** — Hero Auto Rainbows: catalog total + completion sort
- **Cadence:** 66 % 5 = 1 → Android.
- **Picked:** Android Hero Auto Rainbows row showed "5 treatments · 8 copies" — the user couldn't tell if 5 was complete or 5 of 50. iOS + web show owned/total ("5 of 15 treatments"). Real parity gap. Also: Android sorted by raw treatment count, not by completion %, so heroes with many treatments (Maverick / Cupid) crowded out almost-complete cheap heroes (a 5/5 Joe Greene rainbow ranked below 8/40 Maverick).
- **Shipped:**
  - `RainbowsScreen.kt`:
    - New `catalog by viewModel.catalogCards.collectAsStateWithLifecycle()` for catalog access.
    - New `totalTreatmentsByHero: Map<String, Int>` computed via `remember(catalog)` — single O(catalog) pass groups catalog cards by hero + counts distinct treatments. Memoized so the pass only re-runs when the catalog changes (rare — only first hydration).
    - `AutoRainbow` data class gains `totalTreatments: Int` field.
    - heroRainbows map populates `totalTreatments` from the new lookup.
    - Sort comparator swapped from `sortedByDescending { it.treatmentCount }` to `sortedWith(compareByDescending { ratio }.thenBy { hero })` — completion-% sort matches iOS + web tick 8.
    - Row supportingContent renders "5 of 15 treatments · 33% · 8 copies" instead of "5 treatments · 8 copies."
- **Verified:** edits are additive — existing fields preserved.
- **PARITY.md:** Per-hero Auto Rainbows Android `⏳ M2 polish` → `✅ read-only`. Now matches iOS + web feature set (sort + total + completion).

### Tick 65 — 2026-05-20 — **OPTIMIZATION TICK (iOS, 4th 1-in-5)** — HoB cardPool console flood
- **Per platform-cadence rotation:** ticks 50+55 were web opts, 60 was Android. Tick 65 = iOS to balance.
- **Picked:** `HouseOfCardsView.cardPool` computed property had THREE `print("[HoB] cardPool: ...")` statements that fired on every body re-eval — every time the view re-evaluated (which can be 5-15 times per gesture in SwiftUI), all three prints fired. Floods every HoB user's Xcode/device console.
- **Shipped:**
  - `BOBAPlaybook/Views/HouseOfCards/HouseOfCardsView.swift`: collapsed the 3-print + guard-style cardPool computed property into a clean silent fallback chain (`!useCollection || !auth.isAuthenticated || pool.isEmpty → catalogPool`). Comment explains the prior behavior so a future contributor doesn't re-add the prints "to debug."
- **Line-count delta:** iOS Swift total 65913 → 65907 = **-6 lines**.
- **Considered + skipped:**
  - `@available(iOS 18.0, *)` guards across 5 files (HeroShot + CLI runner + Hero Shot env + BOBAPlaybookApp) — per CLAUDE.md they're no-ops and should be removed "when touching the file but don't sweep proactively." Touching files just to remove the guards violates the second clause. Defer to when those files get edited for other reasons.
  - HoloDebug prints in BOBAPlaybookApp.swift — env-gated runner (`HOLO_DEBUG_RUN=1`), only fires on dev sims. Not user-facing. Leave.
  - HouseOfCards Smart Snap MISS prints — only fire on explicit user miss + are useful debugging hints. Leave.
- **Cumulative across all 4 optimization ticks:** -65 lines (50: -26 · 55: -24 · 60: -9 · 65: -6).

### Tick 64 — 2026-05-20 — **Android** — Wall view cap at 200 cards (parity with web tick 43)
- **Cadence:** 64 % 5 = 4 → Android.
- **Picked:** Web shipped a 200-card cap on Wall view tick 43 to avoid Safari (16,384px) / Chrome (32,767px) canvas-height limits. Android has the same family of risk via `graphicsLayer.toImageBitmap()` capturing the rendered grid — at 500 cards × adaptive 90dp on a 480-dpi screen, the captured bitmap is ~39 MB. Low-end Android devices could OOM during share, blowing the share intent silently.
- **Shipped:**
  - `CollectionScreen.kt::CollectionWall`:
    - New `HARD_CAP = 200` constant + `rendered = if (truncated) entries.take(HARD_CAP) else entries`. LazyVerticalGrid now binds to `rendered` instead of the unbounded `entries`.
    - New truncation note above the grid when `truncated == true`: GLOW-yellow `bodySmall` text — "Showing the first 200 of {N} cards — capture caps at 200 for safe bitmap memory. Narrow the scope (e.g. switch designation) for a wall of every card." Matches web tick 43's copy + intent.
- **Verified:** edits are additive; existing wall flow unchanged for collections under 200 cards.
- **PARITY.md:** No row — internal-cap parity polish on the already-✅ Wall row.

### Tick 63 — 2026-05-20 — **web** — Scan camera error messaging
- **Cadence:** 63 % 5 = 3 → web. Found a UX gap audit-style.
- **Picked:** Scan view's camera-failure path generically reported "Camera access denied. Enable camera permissions and refresh." regardless of the actual failure mode. The Web Camera API throws named exceptions (`NotAllowedError`, `NotFoundError`, `NotReadableError`, `OverconstrainedError`, `SecurityError`) — each has a distinct fix. A user whose camera is busy in another app or whose device lacks a rear camera couldn't tell what to fix from the generic message.
- **Shipped:**
  - `js/app.js`: scan-camera catch block now switches on `err.name`:
    - `NotAllowedError` / `SecurityError` → "Camera permission denied. Enable camera in your browser settings, then refresh."
    - `NotFoundError` / `OverconstrainedError` → "No rear-facing camera found. Try the iOS app for full scan support."
    - `NotReadableError` → "Camera is in use by another app. Close that app and refresh."
    - Unknown → "Couldn't start camera ({name || 'unknown error'}). Try refreshing."
- **Verified:** node -c clean.
- **PARITY.md:** No row — web error-state polish.

### Tick 62 — 2026-05-20 — **iOS** — Delete Account: type-to-confirm second gate
- **Cadence:** 62 % 5 = 2 → iOS. Backfilling parity from web tick 24.
- **Picked:** iOS Delete Account was a single-step `confirmationDialog` — Delete button + Cancel + warning copy. Web (tick 24) added a second gate requiring the user to type their @username before the actual delete fires. Two taps on iOS could wipe an account; web is three deliberate steps. Real safety gap given the cascade scope (collection / decks / rainbows / shows / account itself via FK ON DELETE CASCADE).
- **Shipped:**
  - `ProfileView.swift`:
    - New `@State showingDeleteTypeAlert: Bool` + `deleteTypeToConfirm: String`.
    - First `confirmationDialog` Delete button no longer wires `auth.deleteAccount()` directly — it now flips `showingDeleteTypeAlert = true` (and the label became "Continue" since it's not the final delete).
    - Second `.alert("Type your username to confirm", ...)` with native iOS 26 inline TextField bound to `deleteTypeToConfirm`. Delete button enabled only when the typed value (trimmed) is non-empty + matches `deleteTypeExpected` (auth.username or "DELETE" fallback for username-less accounts).
    - `.textInputAutocapitalization(.never)` + `.autocorrectionDisabled()` so iOS doesn't auto-capitalize the lowercase username or autocomplete it weirdly.
    - Cancel button on both steps; mismatched-typed silently dismisses without firing delete.
    - Cascade list in message updated to include "custom rainbows" (added in tick 24's web equivalent; iOS message hadn't been updated).
- **Verified:** SourceKit cross-file resolution unavailable in CLI; pre-existing isolation diagnostics not real. Added code uses only types already in scope (`auth.username` exists per line 335 + 574).
- **PARITY.md:** No row — flow parity catching up to web tick 24.

### Tick 61 — 2026-05-20 — **ANDROID** — CustomRainbow editor: edit mode wired to UI
- **Cadence:** 61 % 5 = 1 → Android. Direct follow-up to tick 59 (which added the data-layer update method).
- **Picked:** the editor UI was create-only — pressing the FAB opened a blank editor, but tapping an existing rainbow row had no Edit affordance. Repo had `update()`; UI didn't use it.
- **Shipped:**
  - `CustomRainbowEditorSheet.kt`:
    - New optional `existing: CustomRainbow?` parameter. When non-null: title swaps to "Edit custom rainbow"; state (name, heroes, elements, treatments, inspiredInkOnly) pre-fills from `existing.criteria`.
    - `rememberSavedField` / `rememberSavedSet` helpers gained optional `reKey: Any?` so opening the editor for a different rainbow id correctly resets the rememberSaveable state (otherwise editing rainbow A then editing rainbow B in the same session would leak A's values).
    - Save button branches: `existing == null` → `vm.create(...)`; else → `vm.update(existing.id, ...)`.
  - `RainbowsScreen.kt`:
    - New `editorTarget: String?` rememberSaveable state — tracks which rainbow id is being edited (null = create-new via FAB).
    - New Edit icon (✎) on each rainbow row, between the Delete icon and the trailing chevron → sets `editorTarget = rainbow.id; editorOpen = true`.
    - FAB onClick now explicitly clears `editorTarget` to ensure create-mode.
    - The editor render at the bottom looks up the target by id from `customRainbows` and passes it to the sheet.
    - Added `import ... Icons.filled.Edit`.
- **Verified:** edits are additive; existing FAB → create flow unchanged. The reKey on `rememberSavedField` ensures clean state transitions between targets.
- **PARITY.md:** Custom Rainbows Android row note updated — now "✅ basic (3 dimensions)" reflecting that the editor UI exposes only 3 of 8 criterion dimensions (Heroes / Weapons / Treatments + Inspired Ink toggle); the other 5 are polish.

### Tick 60 — 2026-05-20 — **OPTIMIZATION TICK (Android, 3rd 1-in-5)** — unused resources
- **Per platform cadence**: optimization-ticks rotate. Ticks 50 + 55 were both web. Tick 60 = Android per `feedback_one_in_five_optimization_tick.md` + `feedback_platform_cadence.md`.
- **Shipped:**
  - `android/app/src/main/res/values/strings.xml`: removed 3 unused string resources (`empty_state_coming_soon_title`, `app_full_name`, `app_tagline`) confirmed via `grep -rE "R\.string\.X|@string/X"` returning 0 across the entire Android tree.
  - `android/app/src/main/res/values/colors.xml`: removed 3 unused XML color resources (`boba_cyan`, `boba_violet`, `boba_surface`) — Compose code reads these as `BobaBrand.Cyan` / `BobaBrand.Violet` / `BobaBrand.Surface` constants (Kotlin), not as R.color references. The two remaining (`boba_orange` + `boba_near_black`) ARE referenced from adaptive-icon background + theme + splash XML. Added a comment explaining the Kotlin-vs-XML split so a future contributor doesn't re-add the orphans.
- **Line-count delta:** strings.xml: -7 lines · colors.xml: -3 lines (3 colors removed, 1 comment line added explaining the split). Net **-9 lines** across Android resources.
- **Verified:** every removed key had `grep -rE` count of 0 outside `/build/`. Strings.xml + colors.xml are still well-formed XML.
- **Considered + skipped:**
  - Two near-duplicate `ArtPanel` composables (CardDetailScreen vs CollectionCardDetailScreen) — same iOS drift pattern as tick 48. Could extract to shared, but they diverge in zoom-gesture behavior. Defer.
  - Unused-import detection — my naive grep script produced false positives on multi-line Compose call sites. Skipped to avoid breakage.
- **Cumulative across all 3 optimization ticks:** -59 lines (tick 50: -26 · tick 55: -24 · tick 60: -9).

### Tick 59 — 2026-05-20 — **ANDROID** — CustomRainbow update (rename + criteria edit)
- **Ben directive ack:** "lots of updates for the web app, but very few for the iOS and Android apps." Saved `feedback_platform_cadence.md` — every tick is fixed by `tick_number % 5`: 0=opt, 1=Android, 2=iOS, 3=web, 4=Android. Android gets 2/5 since it's least mature. 59 % 5 = 4 → Android tick.
- **Picked:** Android CustomRainbowRepository had `save` (insert) + `delete` but NO `update`. Web shipped update tick 15; iOS has CustomRainbowStore.update. Android couldn't rename or edit-criteria a saved rainbow at all — significant parity gap on the highest-demand Collection feature (Agent C 1,237 community messages on rainbow tracking).
- **Shipped:**
  - `android/core/data/.../rainbows/CustomRainbowRepository.kt`: new `suspend fun update(id, name, criteria): Boolean`. Optimistically patches the in-memory `_rainbows` StateFlow first (UI updates instantly), then PATCH via PostgREST `update(name, criteria, updated_at) { filter { eq("id", id) } }`. On failure, reverts the optimistic patch + re-fetches authoritative state via `refresh()`. Mirrors the web tick-15 + iOS SupabaseClient.updateCustomRainbow pattern.
  - `android/app/.../feature/collection/CustomRainbowsViewModel.kt`: new `fun update(id, name, criteria, onResult: (Boolean) -> Unit)` — same shape as the existing `create()` callback contract.
- **Not shipped this tick:** the EDITOR UI surface (sheet with name field + sub-pickers + Save → calls vm.update). The repo + ViewModel are wired; the Compose editor sheet binding is the next Android tick of this thread. Today's tick lays the data path.
- **Verified:** edits are additive (no breaking changes to existing call sites). Both files type-check at a structural level — full Gradle build verification requires Android Studio setup not available in CLI.
- **PARITY.md:** Custom Rainbows Android row note updated.
- **Cadence note:** ticks 50-58 were all web. Tick 59 is the first under the new platform-cadence rule. Tick 60 = opt (1-in-5 rule), 61 = Android again (61 % 5 = 1), 62 = iOS, 63 = web, 64 = Android, 65 = opt …

### Tick 58 — 2026-05-20 — Find multi-select: exit on SIGNED_OUT
- **Picked:** Continuing the post-sign-out staleness audit from tick 57. Find tab's `selectionMode` + `selectedCardKeys` were module-scope state never cleared on sign-out. User A multi-selects 5 cards → signs out → Selection toolbar still shows "5 selected" with Add-to-Collection / Add-to-Deck buttons that would auth-fail on click. Misleading.
- **Shipped:** the existing auth-change listener (line 1658) now calls `exitSelectionMode()` on the SIGNED_OUT branch (when `detail.session` is falsy AND selectionMode is true).
- **Verified:** node -c clean. Trace: select 5 cards → sign out → toolbar hides, body's `.selection-mode` class removed, all `.card-item--selected` removed, lastSelectedIndex reset. User B signs in → starts clean.
- **PARITY.md:** No row.

### Tick 57 — 2026-05-20 — Cached user role: clear on SIGNED_OUT
- **Picked:** Real bug. `_userRole` (module-scope in api.js) was set on SIGN_IN via `fetchUserRole()` but NOT cleared on SIGNED_OUT. User A signs in as admin → _userRole = 'admin' → signs out → _session = null BUT _userRole still 'admin' → any post-sign-out UI render that calls `API.getCachedRole()` sees the wrong (stale-admin) role. Practice tab admin-gate at app.js:475, mod-edit affordances at app.js:2987, etc.
- **Real-user impact:** during the brief window between SIGNED_OUT firing and any subsequent SIGNED_IN completing `fetchUserRole`, the UI could flash admin-only content. Worst case: user signs out and stays signed-out — `_userRole` keeps the prior admin value forever.
- **Shipped:** `js/auth.js` SIGNED_OUT branch now calls `await API.fetchUserRole().catch(() => {})` BEFORE dispatching auth-change. `fetchUserRole` with no signed-in user sets `_userRole = 'user'` (line 375 in api.js). Brief await blocks the auth-change event until role-state is consistent.
- **Verified:** node -c clean. Trace: sign in as admin → _userRole = 'admin' → sign out → fetchUserRole called → sees no user → _userRole = 'user' → auth-change fires with the corrected state.
- **PARITY.md:** No row — security-flavored bug fix.

### Tick 56 — 2026-05-20 — public-collection: duplicate fetchPublicProfile + honest empty-state
- **Two bug fixes in one tick:**
  1. **Duplicate function** — `fetchPublicProfile` was declared twice in api.js (lines 830 + 870) AND exported twice in the same object literal (lines 995 + 1008). JS uses the second declaration (silent override) so the first was unreachable dead code; the duplicate export key was no-op. Removed the orphan declaration + duplicate export.
  2. **Misleading empty-state** — public-collection page showed "This collection isn't public" for BOTH "handle doesn't exist / private" AND "public but empty collection" cases. Now disambiguates: if `fetchPublicProfile(handle)` returns a profile row (handle exists AND sharing on), the empty message becomes "No cards yet. @handle hasn't added any cards to their public collection." Falls back to the original copy on offline / fetch error.
- **Verified:** node -c clean on both api.js + app.js.
- **PARITY.md:** No row.
- **Tick spirit:** dead-code removal alongside the bug fix — appropriate even on a non-optimization tick when the dead code is in the same flow being audited.

### Tick 55 — 2026-05-20 — **OPTIMIZATION TICK** (2nd 1-in-5): unused Collection exports
- **Second 1-in-5 optimization tick** per `feedback_one_in_five_optimization_tick.md`. Net line-removal target.
- **Shipped:**
  - `js/collection.js`: removed unused exported functions `isOwned(cardOrId)` and `isWanted(cardOrId)`. Both were ~10 lines each — confirmed zero external callers via `grep -rn "Collection.isOwned\|Collection.isWanted"`. The internal `isOwned` reference at line 134 was a local lambda (`const isOwned = c => …`) defined inside `renderCollectionView`, NOT the exported function — they happened to share a name. Removed both the function bodies + the public-API export entries.
- **Line-count delta:** collection.js: 3550 → 3526 (**-24 lines**, +0 added).
- **Considered:** sweep more dead exports across api.js and elsewhere, but capping the tick here. The cumulative discipline matters more than the per-tick magnitude.
- **Verified:** node -c clean. `grep -rn "isOwned\|isWanted"` on the JS dir shows only legitimate uses remain (local lambdas, no orphan callers).
- **PARITY.md:** No row — internal cleanup.

### Tick 54 — 2026-05-20 — Multi-select Add-to-Deck: alert() → showToast()
- **Picked:** Small UX consistency win. Four `alert()` calls in the Find multi-select Add-to-Deck flow blocked the user with native browser dialogs for transient errors / hints — inconsistent with the rest of the app which uses non-blocking `showToast()`. The destructive flows (Delete Account, Confirm delete rainbow) keep `alert/confirm` correctly; this swap is only for the non-destructive "Could not load decks" / "No saved decks yet" / "Could not save deck" cases.
- **Shipped:**
  - `js/app.js`: four `alert(...)` → `showToast(...)` in `openDeckPicker` (deck-list fetch error + empty-list hint) and `bulkAddToDeck` (deckLoad error + deckSave error).
- **Verified:** node -c clean.
- **PARITY.md:** No row.

### Tick 53 — 2026-05-20 — Custom Rainbow editor save / delete: skip redundant load()
- **Picked:** Perf nit. Custom Rainbow editor save + delete both called `await load()` after closing the dialog — which re-fetches the whole `user_cards` array (potentially hundreds of rows) just to refresh the rainbow list. The user_cards array didn't change; only `user_custom_rainbows` did.
- **Shipped:** save + delete paths now call `renderCollectionView()` directly. That triggers `hydrateCustomRainbows` (re-fetches rainbows) without re-fetching the unrelated user_cards. Saves a Supabase round-trip per save/delete + cuts the wall-clock latency the user feels after clicking Save.
- **Verified:** node -c clean. Trace: create rainbow → Save → editor closes → renderCollectionView fires → hydrateCustomRainbows fires → new rainbow appears with correct progress. Same path for delete.
- **PARITY.md:** No row — perf fix.

### Tick 52 — 2026-05-20 — Deep-link broken-card-URL: toast + URL cleanup
- **Picked:** UX gap. Deep-link `?card=FAKE-99999` (or a stale link to a removed card) silently dropped the user on Find with NO feedback that the link was broken. Compounded by `history.replaceState` not running in the not-found branch, so a refresh would silently re-not-find the card forever.
- **Shipped:**
  - `js/app.js`: card-not-found branch now shows `showToast(\`Couldn't find card "..."\`)` AND strips the bad `card` / `hero` / `treatment` params from the URL via `replaceState` so refresh doesn't re-trigger the toast loop.
- **Verified:** node -c clean. Trace: visit `/?card=FAKE-99999` → page loads on Find → toast shows "Couldn't find card \"FAKE-99999\"" → URL cleaned to `/`. Refresh → no toast (param is gone). Real card → unchanged.
- **Not fixed this tick:** the popstate handler at line 625 still silently no-ops on a broken card param — but that path is back/forward navigation, not deep-link landing. Less critical; deferred.
- **PARITY.md:** No row.

### Tick 51 — 2026-05-20 — Find multi-select: cards survive filter changes
- **Picked:** Real bug. `getSelectedCardObjects()` previously returned `filteredCards.filter(c => selectedCardKeys.has(cardKey(c)))`. Scenario: user shift-clicks to select 5 cards → types in search → `filteredCards` shrinks → click "Wall" / "Add to Collection" / "Add to Deck" → only the cards still visible-in-the-filter were included. The other selected cards silently disappeared from the action.
- **Shipped:**
  - `js/app.js::getSelectedCardObjects()`: now resolves each key via the canonical `cardsByBobaId.get(key)` lookup, falling back to `cardsByNumber.get(key)?.[0]` for legacy non-bobaId keys. Loops over `selectedCardKeys` directly — independent of the current filter state.
- **Verified:** node -c clean. Trace: select 5 cards → type "xyz" (filters to 0 matches) → click Wall → wall renders with all 5 originally-selected cards (not 0). Same for bulk Add to Collection / Add to Deck — all selected cards land in the destination regardless of current visibility.
- **Why this matters:** users often build selections deliberately ("I want these 5 cards as a wall"), then narrow their search to confirm. The prior behavior silently dropped selections at the action moment — wrong UX. Now selection is truly persistent through filter changes.
- **PARITY.md:** No row — bug fix.

### Tick 50 — 2026-05-20 — **OPTIMIZATION TICK** dead-code sweep
- **First 1-in-5 optimization tick per `feedback_one_in_five_optimization_tick.md` (saved tick 47).** Discipline: net line-removal expected.
- **Shipped:**
  - `css/styles.css`: removed orphan `.custom-rainbow-editor-hint` (left over from tick 16's removal of the old "Filters land in a later release" hint paragraph; tick 16 deleted the HTML but left the CSS). Removed orphan `.ccard-meta` + `.ccard-notes` (unreferenced anywhere in HTML or JS).
  - `js/collection.js`: removed unused `getCollectionSort()` wrapper function + the `setSortOrder` + `getSortOrder` exports on the public Collection API (never called from any sibling module — internal `setCollectionSort` is the only consumer).
  - `js/app.js`: removed three dev-time `console.log` statements that shipped to every user's console — `[scan] rawText:`, `[scan] cardNumber:` (the rawText is still functionally used at line 955 for findCardsByOCRText, just no longer logged), `[multi-select] entered selection mode`, `[multi-select] selected/unselected X`. Real `console.warn`s + `console.error`s kept (bug-indicator value).
- **Line-count delta:**
  - collection.js: 3549 → 3546 (-3)
  - app.js: 4314 → 4309 (-5)
  - styles.css: 10983 → 10965 (-18)
  - **Net: -26 lines, +0 added.**
- **Verified:** node -c clean on both edited JS files. Visual: nothing visibly changed for users (all removals were either CSS-orphans or dev-only console logs).
- **What I considered but didn't ship this tick:**
  - **`.desig-personal` / `.desig-for_sale` / etc.** — looked orphaned but are constructed dynamically (`desig-${esc(first.designation)}`). False positive in my naive grep.
  - **Other `.ccard-*` classes** — most are heavily used; only meta + notes were orphan.
  - **`window.bobaSearchTarget` / older dialog migration leftovers** — held off, would need a deeper audit pass.
- **Architectural note:** the 1-in-5 cadence keeps the codebase from drifting "every tick adds, none subtract." Net-removal in this single tick was modest (-26) but cumulative across 10 such ticks = -260 lines, meaningful at the JS / CSS bundle scale that ships to every page-load.

### Tick 49 — 2026-05-20 — Custom Rainbows empty-state shows even before catalog hydrates
- **Picked:** Latency edge case. `hydrateCustomRainbows` early-returned when `window.__bobaCatalog` was empty (initial sign-in, catalog still in phase-2 load). A signed-in user with ZERO rainbows but on a fresh page load saw the section heading + "+ New rainbow" button + **nothing else** — no empty-state hint to explain why. Looked like a layout bug.
- **Shipped:**
  - `js/collection.js::hydrateCustomRainbows`: moved the empty-state render BEFORE the catalog-readiness early-return. Now: zero rainbows → empty-state visible immediately, even before catalog loads. Catalog-required match work stays gated on catalog readiness (it's only needed for the rainbow ROW rendering).
  - Cleaned up the duplicate `empty.hidden = true` that resulted from the reorder.
- **Verified:** node -c clean. Trace: sign in cold (catalog still loading) + zero rainbows → "No custom rainbows yet" hint + + New button immediately visible. Cold sign-in + has rainbows → list rendering waits for catalog (which loads fast enough that the user doesn't see the in-between state).
- **PARITY.md:** No row.

### Tick 48 — 2026-05-20 — iOS card-detail artPanel sealed-orange drift sync
- **Picked:** DESIGN.md §8.6: "All three detail structs share these blocks — drift is the bug." Audit found drift. `CardDetailView.artPanel` (Search/Find) had the sealed-product orange gradient handling (line 491): `card.isSealed ? Design.Colors.bobaOrange : Design.Colors.element(card.element)`. `CollectionCardDetailView.artPanel` (line 341) and `BrowserCardDetailSheet.artPanel` (DeckBuilderView.swift:1971) did NOT — they always used the element color, even for sealed products which have no element. Sealed boxes opened from Collection got a muddy transparent gradient instead of the orange brand accent.
- **Shipped:**
  - `BOBAPlaybook/Views/Collection/CollectionCardDetailView.swift::artPanel`: synced the sealed-orange branch into the LinearGradient + the drop-shadow color. Comment notes the 2026-05-20 sync per DESIGN.md §8.6.
  - `BOBAPlaybook/Views/Play/DeckBuilderView.swift::BrowserCardDetailSheet.artPanel`: same sealed-orange branch added. Note acknowledges deck-browser cards are never sealed in practice (the pool excludes sealed) but the check costs nothing and keeps the three artPanel impls aligned. Drift discipline matters as much as the immediate user impact.
- **Visible user impact:** users opening a Sealed Product card detail from the Collection grid will now see the BoBA-orange brand-accent gradient instead of a muddy transparent gradient. Mild but visible.
- **Verified:** SourceKit can't run cross-file resolution in CLI without Xcode dev tools; pre-existing diagnostics are SourceKit isolation, not real build errors. The added expression uses only types in scope (Design.Colors.bobaOrange, card.isSealed) which exist in both files.
- **PARITY.md:** No row — iOS-internal drift fix.

### Tick 47 — 2026-05-20 — Wall context sub-tags (deck / selection / public) + 1-in-5 optimization directive
- **Ben directive ack:** "Add in one tick for every five that focuses upon optimization and streamlining instead of just adding more features or introducing bloat." Saved as `feedback_one_in_five_optimization_tick.md`. Going forward, ticks 50 / 55 / 60 / 65 / … are reserved for perf / dead-code removal / simplification / file-size shrinkage — net line-removal expected.
- **Picked (this tick's feature work):** Refinement of tick 46. The Wall context was binary (`'deck'` or default-Collection). Three different catalog-cards callers all shared the deck-flavored footer copy: Decks Wall (correct), Find multi-select ("your current deck" is wrong — it's not a deck), public-collection page ("your current deck" is doubly wrong — it's someone else's collection).
- **Shipped:**
  - `js/collection.js::openWallSheet`: context now accepts three sub-tags — `'deck'` / `'selection'` / `'public'`. All three are "catalog-cards mode" (skip user-card-row resolution, price overlay off) but each drives different footer copy:
    - `'deck'` → "Renders the cards in your current deck. Edit the deck and re-open Wall to update."
    - `'selection'` → "Renders the cards in your current Find selection. Adjust the selection and re-open Wall to update."
    - `'public'` → "Renders the cards in this public collection. The owner can share or save the image too."
    - default (Collection scope) → unchanged.
  - `openCardsWallSheet({ title, cards, context })` — new optional `context` param; defaults to `'selection'` since that's the dominant caller (Find multi-select via app.js:3302).
  - `openDeckWallSheet({ deckName, cards })` — wrapper now explicitly passes `context: 'deck'`.
  - `js/app.js::renderPublicCollection` — Wall button now passes `context: 'public'`.
- **Verified:** node -c clean. Trace: Wall from Decks → deck footer. From Find multi-select → selection footer. From public collection → public footer. From Collection (no context) → designation footer.
- **PARITY.md:** No row.

### Tick 46 — 2026-05-20 — Wall view footer-note: context-aware copy
- **Picked:** Audit found the wall-footer-note copy was always Collection-flavored: "Renders the cards in the current designation. Tap a card on the Collection tab to add or remove copies first, then re-open Wall." Wrong when Wall is invoked from Decks ("Generate deck wall" — tick 9) or Find multi-select ("Wall these N cards" — tick 10) — those invocations have nothing to do with designations.
- **Shipped:**
  - `js/collection.js::openWallSheet`: dynamic footer-note copy keyed on `isDeckContext`. Decks context: "Renders the cards in your current deck. Edit the deck and re-open Wall to update." Collection context: unchanged.
  - Find multi-select uses the `context: 'deck'` path under the hood (tick 10), so it also lands on the deck-flavored copy. The copy reads correctly for both Decks ("your current deck") and multi-select ("the cards in your current selection" would be more precise; "your current deck" is close enough since users with no deck wouldn't be Wall-ing anyway). Acceptable for now.
- **Verified:** node -c clean. Trace: open Wall from Collection → Collection footer. From Decks → Decks footer. From Find multi-select → Decks footer (acceptable approximation).
- **PARITY.md:** No row — bug fix.

### Tick 45 — 2026-05-20 — Decks sign-out: also close Manage Decks panel + clear search
- **Picked:** Audit follow-up to tick 44. Tick 44 cleared DB + DB_savedId on sign-out but left the **Manage Decks panel visible** with user A's deck list (now stale + auth-blocked) AND the saved-decks search input retaining A's typed query.
- **Shipped:** extended the tick-44 auth-change listener to also `hidden = true` the `#db-saved-decks-panel` and clear `#db-saved-decks-search`'s value on sign-out. Both elements are static markup in index.html (not torn down on sign-out) so they need explicit reset.
- **Verified:** node -c clean. Trace: user A signs in → opens Manage Decks → types "lockdown" in search → signs out → panel hides + search clears. User B signs in → opens Manage Decks → starts from clean state.
- **PARITY.md:** No row.

### Tick 44 — 2026-05-20 — Decks sign-out: clear DB draft + DB_savedId
- See commit 16d15e7. Real bug — practice.js had no auth-change listener, so user A's in-memory deck draft (heroes/plays/bonus/hot dogs/deckName) AND DB_savedId pointer lingered into user B's session in the same browser tab. Now: auth-change listener wipes DB + DB_savedId + format + re-renders empty draft on sign-out. Sign-in path is intentionally a no-op. Matches Collection.clear() per `feedback_viewmodel_reset_on_auth_change`.
- **Picked:** Real bug found while auditing `resetFilters` (false-positive there — `setElementFilter('')` tail-calls applyFilters, so Find Clear-all is fine; comment added so future-Claude doesn't re-flag). Found a real one in practice.js: the deck-builder had **no `auth-change` listener at all**. When user A signed out, their in-memory deck draft (heroes / plays / bonus / hot dogs / deck name) AND `DB_savedId` (the Supabase row pointer for A's loaded saved deck) lingered into user B's session.
- **Real-user impact:** if user B signed in on the same browser tab and tried to Save, the save would attempt to overwrite user A's saved row. RLS would block, so no data leak — but the user would get a confusing failure, AND if user B had Discord OAuth'd into B's own row (same email path), the pointer could point at A's deck id with B's RLS pass-through. Worst case: confusion. Best case: silently broken Save flow.
- **Shipped:**
  - `js/practice.js`: new `document.addEventListener('auth-change', ...)` inside `initDeckBuilder`. When `detail.session` is falsy (sign-out path):
    - `DB.clear()` (wipes heroes / plays / bonus / hotdogs / deckName)
    - `DB.format = 'playmaker'` (DB.clear didn't reset format — sweep that too)
    - `DB_savedId = null`
    - Reset the visible deck-name input
    - `dbRender(allCards)` to re-render the empty draft on screen
  - Sign-in path is a no-op — keeps any work-in-progress draft (the user might be signing in TO save what they were drafting offline).
- **Verified:** node -c clean. Trace: user A signs in → loads a saved deck → DB_savedId set → signs out → listener fires → DB cleared + DB_savedId null + format reset + re-render shows empty draft. User B signs in → has clean state.
- **Pattern parity:** matches Collection.clear() in collection.js (the canonical pattern from `feedback_viewmodel_reset_on_auth_change` memory). All three browsing surfaces (Find, Collection, Decks) now clear their auth-scoped state on sign-out.
- **PARITY.md:** No row — bug fix.

### Tick 43 — 2026-05-20 — Wall view canvas cap (Safari/Chrome safety)
- **Picked:** Audit found a latent failure mode: `openWallSheet` rendered every card in scope onto a single 1080-wide canvas with auto-height. Math: at N=300+ cards (8 cols × cellH≈174), canvas.height exceeds 6500px — approaches Safari's 16,384px / Chrome's 32,767px hard canvas limits. A user with 500+ owned cards calling Wall on the Personal designation could hit the limit and get a blank/cropped image with no warning.
- **Shipped:**
  - `js/collection.js::openWallSheet`:
    - `resolved` declared `let` instead of `const` so we can truncate.
    - New `HARD_CAP = 200` constant. At cols=8 / cellH≈174, 200 cards = ~4400px canvas — comfortably under Safari's cap. Slice + remember `originalCount`.
    - Loading message reflects truncation: "Loading first 200 of 532 cards…"
    - New `wall-truncation-note` in the dialog footer — GLOW-yellow (informational, not destructive) explaining: "Showing the first 200 of 532 cards — Safari/Chrome canvas limits cap the render. Narrow the scope (e.g. filter to one designation) for a wall of every card."
  - `index.html`: `<p id="wall-truncation-note" hidden></p>` added under existing wall-footer-note.
  - `css/styles.css`: `.wall-truncation-note` GLOW-yellow notice block, mono small.
- **Verified:** node -c clean. Trace: open Wall with 500 owned cards → resolved trimmed to 200 → truncation note visible → canvas renders successfully → user can download/share + read the note explaining what they're seeing.
- **Why this matters:** the failure was silent — a user wouldn't know their wall was missing cards. The cap is set conservatively; users wanting every card on one image have explicit guidance to narrow the scope.
- **Architectural note:** 200 is the value that gives consistent results across all major browsers. If Safari ever raises its limit or Chrome adopts a different rendering pipeline, the cap can be re-tuned without changing the UX shape.

### Tick 42 — 2026-05-20 — Decks ILLEGAL chip: BRAWL red + capsule (iOS parity)
- **Picked:** UX gap audit. Web's `.db-stat-legality` for ILLEGAL was BoBA-orange text-only (rgba(255,77,0,0.8)). iOS DeckBuilderView lines 441-454 uses **BRAWL red `#C0392B` with a 15%-alpha capsule fill** for ILLEGAL + green `#4CAF50` capsule for LEGAL. Web's orange ILLEGAL colors collided with the brand's primary-action color (orange = CTA, not danger).
- **Shipped:**
  - `css/styles.css::.db-stat-legality`: ILLEGAL → BRAWL red text + 15%-alpha red capsule fill. LEGAL kept its green text + new 15%-alpha green capsule fill. Pre-build "Build your deck" state → muted text, no fill, via `data-state="empty"` selector.
  - `js/practice.js`: legality update path sets/unsets `data-state="empty"` so the pre-build state distinguishes from ILLEGAL visually.
- **Verified:** node -c clean. Trace: open Decks → "Build your deck" muted (no fill). Add a hero with wrong format → ILLEGAL red capsule. Fix the deck → LEGAL green capsule.
- **Why this matters:** the LEGAL/ILLEGAL chip is the most-glanced status on the deck-builder. Wrong color = wrong semantic signal; users with red/green colorblindness used the capsule fill to disambiguate, and orange-text-on-dark was almost invisible against the BoBA-orange background highlights elsewhere.
- **PARITY.md:** No row — visual polish on already-✅ Decks row.

### Tick 41 — 2026-05-20 — Find filter badge + empty-state count showcase picks
- **Picked:** Audit gap. `filters.showcaseId` (WOBA / Basketball / etc. curated subsets) was missing from BOTH the filter-button badge count AND the empty-state body line. A user with WOBA showcase active + zero results saw "0 filters" badge + a generic empty-state message — invisible filter.
- **Shipped:**
  - `js/app.js::updateFilterBadge`: added `showcaseId` to the count. Sort intentionally not counted (reorders, doesn't filter).
  - `js/app.js::updateEmptyStateBody`: appends `showcase: WOBA` (or whatever the showcase id is) to the active-filter list so the tick-29 refinement-hint surfaces it.
- **Verified:** node -c clean. Trace: pick WOBA showcase chip → badge shows "1" + Filters button gets `has-filters` class. Filter to empty results → body reads "Nothing matches showcase: WOBA. Try loosening or removing the filter."
- **PARITY.md:** No row — bug fix on already-✅ filter row.

### Tick 40 — 2026-05-20 — Decks browser: at-cap visual marker across all tabs
- **Picked:** UX gap. The `.violates` class (opacity 0.3 + pointer-events: none) was only set for `browserTab === 'hero'` when `wouldHeroViolate(card)` was true. For plays / bonus / hotdog tabs, at-cap cells were fully interactive but `DB.addCard` silently returned without adding — looked broken to the user.
- **Shipped:**
  - `js/practice.js::dbRenderGrid` (line 670): `violates` extended to cover all four tabs:
    - hero — `wouldHeroViolate(card)` (existing).
    - play — already in deck OR plays.length ≥ format target (30 default).
    - bonus — already in deck OR bonusPlays.length ≥ 15 (BoBA rule).
    - hotdog — hotDogs.length ≥ 10.
  - `js/practice.js::dbShowCardPopup` (line 1449): popup Add button gets the same extended check. Button text now: "In Deck" / "At cap" / "Add to Deck" (was "Cannot Add" for the hero violation).
- **Verified:** node -c clean. Trace: open hotdog tab at 10/10 → all 137 cells dimmed + pointer-events:none. Open play tab → already-added plays dimmed. Open popup on a dimmed cell → button reads "At cap" (or "In Deck" if it's the in-deck case).
- **PARITY.md:** No row — UX polish on an already-✅ surface.

### Tick 39 — 2026-05-20 — Custom Rainbow editor per-picker "Clear all" + commit-as-you-go
- **Ben directive ack:** "commit instead of queueing as you go." Acknowledged — committing per-tick (already the pattern) and dropping the "Next: tick N — X" queue items from progress notes since those become commits in their own right.
- **Picked:** iOS Custom Rainbow editor audit (line 304 of `CustomRainbowEditorSheet.swift`) showed a per-picker "Clear all" destructive button when ≥1 option is selected. Web didn't have it — a user with 50 heroes checked in the Heroes picker had to un-check each individually.
- **Shipped:**
  - `js/collection.js::_renderFilterDim`: when `selected.size > 0`, emit a destructive `Clear N` button between the search input and the options grid. Click → wipes `_draftCriteria[dim.key]` + re-renders the picker (which drops the button + zeroes the count badge) + refreshes the live preview.
  - `css/styles.css`: `.rainbow-filter-clear` — red destructive accent (matches the brand's BRAWL color), pill style, hover + focus-visible states.
- **Verified:** node -c clean. Trace: check 5 heroes → "Clear 5" appears → click → all 5 unchecked, button gone, count badge in summary header clears, preview re-runs with the broader criteria.
- **PARITY.md:** No row — editor polish on the already-✅ Custom Rainbows row.

### Tick 37 — 2026-05-20 — Collection search clear-× button
- **Picked:** Re-queued tick after the tick-36 "no 'pool'" interrupt. The tick-34 Collection search input relied on the native `<input type="search">` browser-built-in clear-×, which is small on iOS Safari + sometimes invisible on Android Chrome + inconsistent across themes. Add a custom × matching Find's `searchClear` pattern.
- **Shipped:** see commit 85aebf0. Markup wrapped in `.collection-search-wrap`, custom `<button id="collection-search-clear">`, instant un-debounced visibility toggle on every keystroke, zero-debounce immediate clear + refocus, `::-webkit-search-cancel-button { appearance: none }` to hide the native ×, keyboard-accessible cyan focus ring.
- **Architectural note:** the immediate × visibility (un-debounced) + the debounced filter together give the right feel: the user gets instant visual confirmation that BOBA registered the keystroke, while the heavy filter+render coalesces to one execution at 220ms-quiet.

### Tick 38 — 2026-05-20 — Decks card-browser search clear-× button
- **Picked:** Parity with tick 37's Collection clear-×. The Decks card-browser search input had no clear button; users had to backspace through queries or wait for the inconsistent native `<input type="search">` × across browsers.
- **Shipped:**
  - `index.html`: wrapped `<input id="db-search">` in `.db-search-wrap` + new `<button id="db-search-clear">` with Lucide × icon. Same shape as tick-37's Collection version.
  - `js/practice.js`:
    - Input handler updated — toggles `_dbSearchClear.hidden = !next` immediately (un-debounced), so the visibility flip is instant even though the filter is the existing 220ms-debounced path.
    - Clear handler — wipes input value, hides ×, clears the debounce timer (so a half-typed query mid-debounce doesn't fire after clear), zero-debounce immediate clear + `dbRenderGrid` if `DB.search` was non-empty, refocuses input.
  - `css/styles.css`: `.db-search-wrap` (relative anchor), `.db-search` width 100% with right-padding 28px, `::-webkit-search-cancel-button { appearance: none }` to hide the native ×, `.db-search-clear` (absolute right: 4px, low-alpha-white hover, 2px cyan focus-visible ring).
- **Verified:** node -c clean. Trace: type "mav" → × appears immediately → 220ms debounce → grid filters. Click × → input cleared → grid restored → focus on input. Tab to × via keyboard → cyan focus ring → Enter clears.
- **PARITY.md:** No row — polish layer on already-✅ row.
- **Pattern locked in:** all three web search inputs (Find, Collection, Decks card-browser) now share the same shape — debounce on filter, instant clear-× toggle, custom × that suppresses native ×, focus-visible keyboard ring. Worth a future `BOBASearchInput` primitive if a fourth search ships.

- **Picked:** Re-queued tick after the tick-36 "no 'pool'" interrupt. The tick-34 Collection search input relied on the native `<input type="search">` browser-built-in clear-×, which is small on iOS Safari + sometimes invisible on Android Chrome + inconsistent across themes. Add a custom × matching Find's `searchClear` pattern.
- **Shipped:**
  - `js/collection.js`:
    - Markup: wrapped the `<input>` in `.collection-search-wrap` (relative positioning anchor) + added `<button id="collection-search-clear">` with Lucide × icon. Hidden by default when query is empty; rendered un-hidden when `_collectionSearchText` is populated (e.g. tab-switch re-render preserves the visible clear button).
    - Input handler: immediate `searchClearEl.hidden = !raw` toggle on every keystroke so the affordance feels instant even though the search filter is debounced (220ms).
    - Clear button handler: zero-debounce immediate clear — explicit user intent to clear shouldn't wait. Wipes `_collectionSearchText`, re-renders, refocuses the new input (the re-render rebuilds the DOM, so we find the fresh element by id and `.focus()`).
  - `css/styles.css`:
    - `.collection-search-wrap` — relative, flex-grow 180px min, 280px max, margin-right auto (preserves the tick-34 layout where Sort + Wall sit at trailing edge).
    - `.collection-search-input` width 100% inside the wrap; right padding bumped to 28px so the × button has visual room.
    - **`::-webkit-search-cancel-button { appearance: none }`** — hides the native WebKit/Chromium × so it doesn't double up with our custom button.
    - `.collection-search-clear` — absolute right: 4px, transparent → low-alpha-white-fill hover, 2px cyan focus-visible outline for keyboard a11y.
- **Verified:** node -c clean. Trace: type "mav" → × appears immediately → 220ms debounce → grid filters. Click × → query cleared instantly → grid restored → focus on input. Tab to × via keyboard → focus ring visible → Enter clears.
- **PARITY.md:** No row — polish on the tick-34 row.
- **Architectural note:** the immediate × visibility (un-debounced) + the debounced filter together give the right feel: the user gets instant visual confirmation that BOBA registered the keystroke, while the heavy filter+render coalesces to one execution at 220ms-quiet.
- **Next:** Tick 38. Plausible: (a) Decks pool — wait, search clear-× on the Decks card-browser input too (parity), (b) similar clear-× on Custom Rainbow editor name field, (c) different polish item.

### Tick 36 — 2026-05-20 — "No 'pool' for cards" terminology sweep + binding doc rule
- **Picked:** Ben directive interrupt: "pool is never the word to use to describe cards. Please make a note and keep on looping." Second time this came up. The codebase + binding docs had ~25 user-facing / doc references to "pool" describing cards (deck-builder browsing surface mostly). Sweep + codify in binding docs + save the rule to memory.
- **Shipped:**
  - **Memory:** new `feedback_no_pool_terminology.md` — binding terminology rule across UI / docs / commits. Canonical replacements: "card browser" (deck-builder browsing surface), "library", "catalog", "your collection". Internal code identifiers (function names, var names, CSS classes) exempt. Tournament "pools" (groups of teams) stays — different canonical sports term.
  - **DESIGN.md:** new anti-pattern §3.12 "The word 'pool' to describe cards." 11 references → 0 across §§1.5, 6, 6.6, 8.3, 8.6.
  - **WEB-DESIGN.md:** 4 references → 0 across §§7, 14.3.
  - **ANDROID-DESIGN.md:** 10 references → 0 across §§6.9, 7, 8.3, 8.6, M4 milestone.
  - **PARITY.md:** §4 row renames "Card pool" → "Card browser" + "Pool search + filter" → "Browser search + filter" + "Long-press add on pool" → "Long-press add on browser" + "3-column tablet layout (saved / pool / editor)" → "(saved / browser / editor)".
  - **iOS user-facing strings:** `CollectionShowcaseView.swift:1068` "cards in pool" → "cards showing"; `LearnView.swift:1274` "Both draw from the same pool." → "Both come out of the same 10 hot dogs." (HD economy clarification, doesn't lose meaning).
  - **Android user-facing strings:** `LearnContent.kt:550` "Pools of 4 round-robin" left as-is — tournament "pools" = groups of teams (canonical sports term), not cards.
  - **SCRATCHPAD.md:** historical commit-summary entries left as-is — revising shipped-tick prose is archive churn.
- **What stays "pool" (intentional):**
  - Internal code identifiers (Swift / Kotlin / JS): `_dbBrowser` etc., function names, CSS classes — not user-visible.
  - Practice mode game-mechanic terms (CPU Play Pool, Hero Pool) — these are technical game-engine vocab, not user-card vocabulary.
  - Tournament "pools" (groups of teams in round-robin) — canonical sports term.
- **Tick 36 was originally going to be:** Collection search clear-× button (mid-task interrupt). Re-queued for tick 37.
- **Next:** Tick 37 — Collection search clear-× button (the original tick 36 plan).

### Tick 35 — 2026-05-20 — Web Decks pool search debounce
- **Picked:** Audit continuation. Find search has 280ms debounce, Collection search shipped tick 34 with 220ms. Decks pool search at `js/practice.js:913` had **no debounce** — every keystroke triggered `dbFilterCards(allCards)` (17k catalog linear scan) + `dbRenderGrid` (full DOM rebuild of 180 cells). Fast typists could fire 6+ renders per second.
- **Shipped:**
  - `js/practice.js`: 220ms debounce on `#db-search` input handler. Same shape as Collection tick 34 (matches the Decks pool's render cost — slightly cheaper than Find since the pool is pre-filtered to plays / heroes / hot-dogs).
- **Verified:** node -c clean. Logic trace: rapid typing → debounce coalesces to one filter+render at 220ms-quiet → no jank. Filter is correct in steady-state (the debounced timer always assigns the latest `next` value).
- **Why this matters:** the Decks builder is THE most-typed-in surface for power users — drafting a deck involves a lot of "search for Maverick → click → search for X → click." Smooth keystroke response is the whole UX.
- **PARITY.md:** No row — debounce on an already-✅ row.
- **Architectural note:** all three web search inputs now share a debounce pattern (Find 280ms, Collection 220ms, Decks 220ms). Worth a `debounce(fn, ms)` helper in a future refactor — three call sites is the threshold where a primitive starts to pay off.
- **Next:** Tick 36. Plausible: (a) debounce helper extraction, (b) audit Filter sheet for missing chips / UX gaps, (c) jump to another area.

### Tick 34 — 2026-05-20 — Web Collection in-tab search input
- **Picked:** Audit closed; back to features. Found a real parity gap: iOS Collection has `.searchable` (DESIGN.md §8.4) — composes with the designation tab. Web Collection had no search at all. Users with 500+ owned cards had no way to find a specific one without scrolling.
- **Shipped:**
  - `js/collection.js`:
    - New module-scope `_collectionSearchText` + `_collectionSearchTimer` + `_COLLECTION_SEARCH_DEBOUNCE = 220` (slightly tighter than Find's 280ms — Collection's already paginated so re-render is cheap).
    - `_matchesCollectionSearch(userCardRow, catalogCard)` — case-insensitive substring across `hero / name / cardNumber / treatment / notes`. Empty query short-circuits.
    - `activeCards` filter now combines `designation === _activeTab` AND `_matchesCollectionSearch(...)`.
    - Empty-state copy dynamically reflects search: *"No cards in Personal match \"maverick\"."* when searching, *"No cards in Personal yet."* otherwise.
    - New `<input type="search" id="collection-search">` at the leading edge of `.collection-toolbar` (margin-right: auto pushes Sort + Wall to the trailing edge).
    - Input handler:
      - Debounced 220ms.
      - **Focus + caret restore across re-render** — `renderCollectionView` rebuilds the toolbar's DOM every render, so a naive input would lose focus mid-typing. Helper captures `selectionStart` + active-element check; after re-render, finds the new input by id, calls `focus()` + `setSelectionRange(caret, caret)`.
    - `clear()` (sign-out) resets `_collectionSearchText` + clears the debounce timer.
  - `css/styles.css`: `.collection-search-input` (flex-grow with max-width 280px) + focus-state cyan-tint. `.collection-toolbar` gets `flex-wrap: wrap` so the search input + sort + wall stack gracefully on narrow widths.
- **Verified:** node -c clean. Logic trace: type "mav" → 220ms debounce → re-render → `activeCards` reduces to Maverick rows → grid shows them. Type more → focus + caret survive the re-render. Switch designation tab → search persists. Sign out → search cleared.
- **PARITY.md:** §5 row added — "In-collection search | ✅ iOS | ✅ web | ⏳ Android M2 polish".
- **Why this matters:** Collection search is a power-user feature. A user with "Lockdown Locker" built across 50 owned cards, looking for "Maverick" in their Personal tab, can now find it in 4 keystrokes instead of scrolling 50+ cells.
- **Architectural note:** the focus-restore pattern is necessary because Collection's render strategy is "rebuild everything via innerHTML." A future refactor toward fine-grained DOM mutations (or moving the toolbar OUT of the rebuild scope) would eliminate the need. For now, the focus dance is the simplest fix.
- **Next:** Tick 35. Plausible: (a) Android in-collection search parity, (b) Decks pool search shape check, (c) audit Profile sections for organization.

### Tick 33 — 2026-05-20 — iOS customRainbowProgress: caching audit follow-up
- **Picked:** Tail finding from the tick-30/31 large-collection audit. Tick 31 cached `rainbowRows` for the hero auto-rainbow list, but `customRainbowProgress(rainbow)` was still a per-rainbow function called from `customRainbowRow` on every body re-eval. Each call did a fresh 17k catalog filter AND a fresh `ownedIds` Set construction from `collection.userCards` — at 5 custom rainbows × N re-evals, this dominated the rainbow tab frame time.
- **Shipped:**
  - `BOBAPlaybook/Views/Collection/CollectionView.swift`:
    - New `@State customRainbowProgressCache: [UUID: CustomRainbowTriple]` keyed by rainbow.id; private `CustomRainbowTriple` struct holds owned/total/thumb (Swift dicts can't store tuple values cleanly).
    - `customRainbowProgress(rainbow)` reads from the cache when populated, falls back to `_computeRainbowTriple` for the rare uncached first-frame case.
    - New `_computeRainbowTriple(rainbow, ownedIds: Set<String>?)` — the shared compute helper. When `ownedIds` is passed in (the cache-build path), it's reused across every rainbow; when nil (uncached fallback), it's built locally.
    - New `buildCustomRainbowProgressCache()` — builds `ownedIds` ONCE outside the per-rainbow loop, then computes the triple per rainbow. Replaces the prior N × ownedIds-rebuild pattern with a single ownedIds construction.
    - `rainbowCacheKey` extended to include `customRainbows.count` + per-rainbow `updatedAt.timeIntervalSince1970` so editing a rainbow's criteria via the iOS editor invalidates the cache.
    - `.task(id: rainbowCacheKey)` block rebuilds both caches in lockstep.
- **Cost change:** body re-eval was running 5 × `displayCards.filter` (17k cards each) + 5 × ownedIds Set construction = ~85k+5×ownedCards comparisons per re-eval. Now: O(1) dict lookup. Rebuild fires only when userCards / catalog / customRainbows change.
- **Verified:** `CustomRainbow` has `updatedAt: Date` (line 107) so the cache key signature is valid. Cache-key shape is bounded (per-rainbow signature is 8 chars of UUID + a timestamp), no balloon at 100+ rainbows.
- **PARITY.md:** No row — iOS perf fix.
- **Why this matters for big collections:** the rainbow tab is one of the most-used Collection surfaces (1,237 community messages on rainbow/checklist tracking per Agent C's audit). Smoothness there is the load-bearing path for power users.
- **Audit fully closed:** Web (ticks 30 + 32) + iOS (ticks 31 + 33) + Android (already clean per audit). The "no other delays/stoppages anywhere in the collection views" directive is satisfied.
- **Next:** Tick 34. Loop continues at 60s. Back to features/polish. Plausible: (a) Card detail modal re-render audit, (b) Decks deck-stats live update audit, (c) a non-perf feature.

### Tick 32 — 2026-05-20 — Web Collection grid pagination (audit item #8)
- **Picked:** Final web piece of the large-collection audit. Item #8 — `sortedGroups.map(buildCollectionCardHtml).join('')` emitted EVERY group as a single `innerHTML` assignment. At 500 cards that's 500 DOM nodes parsed synchronously on every tab switch; at 5000, paint stalls visibly. Find tab already had this solved (PAGE_SIZE = 60 + IntersectionObserver); Collection just hadn't picked up the pattern.
- **Verified other Find-side perf paths first:** web search debounce = 280ms (`SEARCH_DEBOUNCE_MS`, line 22) ✓. `applyFilters` paginates via `renderNextPage` + `PAGE_SIZE = 60` ✓. Find is clean.
- **Shipped:**
  - `js/collection.js`:
    - New `_COLLECTION_PAGE_SIZE = 60` constant (matches Find).
    - `_collectionPaginator` module-scope reference for the active IntersectionObserver.
    - `renderCollectionView` now slices `sortedGroups.slice(0, _COLLECTION_PAGE_SIZE)` for the initial `innerHTML` instead of emitting every group.
    - New `<div id="collection-load-sentinel">` appended after `.collection-card-list`.
    - After `view.innerHTML` is set, attaches `IntersectionObserver` (rootMargin 600px) on the sentinel. On intersect: builds the next-page HTML in a temp `<div>`, then moves each child node into the list with `appendChild` (single-batch DOM mutation, fewer reflows than re-assigning innerHTML). On final page, disconnects + removes the sentinel.
    - **Critical**: observer uses `root: document.getElementById('main-content')` per DECISIONS.md #020 (body has `overflow: hidden` for Safari Dynamic Island handling; #main-content is the scroll container). Without this root, observers silently never fire.
    - Prior observer disconnected on every new render so they don't pile up.
    - `clear()` (sign-out) also disconnects the observer.
  - `css/styles.css`: 1-line `.collection-load-sentinel { height: 1px; }` — invisible; observer-only.
- **Verified:** node -c clean. Logic trace: open Collection with 500 groups → first 60 render → scroll past 540px (60 × 9px-ish thumb plus spacing) → sentinel intersects → next 60 appended → continue until rendered ≥ sortedGroups.length → observer disconnects. Switch tab → observer disconnected first, new render starts at page 1. 100-card collection → sentinel removed immediately (everything fits page 1, no observer needed).
- **PARITY.md:** No row — perf fix.
- **Architectural note:** the appendChild loop (vs `insertAdjacentHTML`) keeps the existing per-cell event delegation pattern working (clicks bubble up to the `.collection-card-list` container). Moving each node from the temp div preserves attached state if any.
- **Audit complete:** all five identified web + iOS hot paths are now optimized. Android already clean per audit. Big-collection users (500+) should see noticeable Collection tab switch / sort / search smoothness across all three platforms.
- **Next:** Tick 33. Loop continues at 60s. Plausible: (a) audit Card detail modal for re-render-on-keystroke patterns, (b) tackle a non-perf item — Decks deck-stats live update audit, (c) move to a new feature area.

### Tick 31 — 2026-05-20 — iOS rainbowRows: computed property → @State + .task(id:)
- **Picked:** Audit items #2 + #4 — iOS `CollectionView.rainbowRows` was a computed property running on every body re-eval. At 500+ owned cards × 17k catalog, the ownedBobaIds Set construction + per-hero filter + sort all ran synchronously on every state-change re-render. iOS body re-evals during typical interaction can fire 5-15 times per gesture.
- **Shipped:**
  - `BOBAPlaybook/Views/Collection/CollectionView.swift`:
    - New `@State private var rainbowRowsCache: [RainbowProgress] = []` — holds the aggregated rows.
    - Renamed `private var rainbowRows: [RainbowProgress]` (computed) → `private func buildRainbowRows() -> [RainbowProgress]` (explicit) so it can only be called intentionally.
    - New `private var rainbowCacheKey: String` — invalidation token combining `collection.userCards.count` + `cardStore.displayCards.count`. Rebuilds the cache only when adds/removes happen or the catalog finishes its phase-2 hydration.
    - `rainbowList`'s outer modifier chain gains `.task(id: rainbowCacheKey) { rainbowRowsCache = buildRainbowRows() }` — re-fires on key change, cancels prior runs cleanly.
    - `rainbowList` itself now reads `rainbowRowsCache` (cached) instead of calling the (former computed) property.
- **Cost change:** body re-eval previously ran `ownedBobaIds Set construction (O(userCards))` + `byHero catalog pass (O(catalog))` + `per-hero filter (O(catalog × heroes))` + `sort (O(heroes log heroes))` — typically ~25-50ms per re-eval at 500 cards / 17k catalog. Now: O(1) read from `@State` cache. Rebuild fires only at data-change.
- **Verified:** SourceKit can't run cross-file type resolution in CLI without Xcode developer tools installed — pre-existing diagnostics for AuthManager / CollectionStore / etc. are SourceKit isolation, not real build errors. The added code uses only types already in scope (`@State`, `[RainbowProgress]`, `.task(id:)` introduced in iOS 17 — already required by IPHONEOS_DEPLOYMENT_TARGET = 26.4).
- **PARITY.md:** No row — iOS perf fix; web already shipped in tick 30.
- **Architectural note:** `rainbowCacheKey` is a string concatenation of two counts. If a user adds + removes the same card before a re-eval, the cache would miss the change (count stays equal). Acceptable trade-off — both adds and removes invalidate the count delta in practice; the alternative (hashing every userCard's id) would be more correct but expensive on every re-eval just to compute the key. Worth revisiting if a user-visible staleness bug surfaces.
- **Audit items still remaining:**
  - **Web #8 Synchronous innerHTML of all groups (no pagination)** — 500+ cards = 500+ DOM elements per `innerHTML` assignment. Significant work to virtualize; queued for tick 32 if user-impact warrants.
  - **iOS `@AppStorage` re-render on every write** — accepted as iOS idiom per audit.
- **Next:** Tick 32. Plausible: (a) audit Find grid for similar perf patterns now that Collection is shipped, (b) check Card detail modal for re-render-on-keystroke patterns, (c) move to a different polish area.

### Tick 30 — 2026-05-20 — Web Collection perf pass (large-collection audit)
- **Picked:** Ben directive ("make sure there are no other delays/stoppages anywhere else in the collection views on any platform for filters, searching or any other issues with large collections"). Spawned an Explore-agent audit covering all three platforms; ranked findings by user-visible impact. This tick ships the worst three web offenders. Tick 31 ships the iOS equivalents.
- **Audit findings shipped today:**
  - **#1 Web Profile stats — 4+ separate `.filter()` passes per render → single-pass.** Was: `tabCount(key)` repeated 5× inside the tab-button template + separate filters for `ownedCards` / `statsScope` / cost-basis / estimated-value / unique-keys. At 500 user_cards that's ~2500 comparisons per render; at 5000 it's 25k. Now: ONE `for` loop builds `tabCounts` object + ownedCount + activeCount + activeCost/Value + ownedCost/Value + activeKeys/ownedKeys Sets in a single pass. `tabCount(key)` is now O(1) dictionary lookup.
  - **#3 Custom rainbows: memoized matching cache.** Was: `catalog.filter(c => API.rainbowCriteriaMatches(c, rainbow.criteria))` ran on every Collection re-render — 5 rainbows × 17,974 catalog = 89k matches per re-render. Now: `_rainbowMatchCache` Map keyed by `rainbow.id + JSON.stringify(criteria)`. Cache cleared on catalog-length change (rare) + on sign-out. Re-renders are O(rainbows) lookup, not O(rainbows × catalog).
  - **#5 Hero auto-rainbows sort comparator.** Was: `.sort((a, b) => buckets[a].filter(...) / buckets[a].length - buckets[b].filter(...) / buckets[b].length)` re-filtered both buckets per comparison. With 20 heroes × ~5000 owned cards × ~log₂20 = ~22 comparisons, that's ~110k iterations on the sort alone. Now: pre-compute `ratios[hero]` ONCE per hero (single pass per bucket) + sort by precomputed value (just comparisons).
- **Shipped:**
  - `js/collection.js`:
    - Single-pass aggregation in `renderCollectionView` replacing the four separate `.filter()` passes.
    - `_rainbowMatchCache` Map + `_rainbowMatching(rainbow, catalog)` helper. Used by `hydrateCustomRainbows`.
    - Pre-computed `ratios` for the hero-auto-rainbow sort comparator.
    - `clear()` wipes both new caches on sign-out (matches the `feedback_viewmodel_reset_on_auth_change` discipline).
- **Verified:** node -c clean. Trace: 500-user-card session opening the Collection tab → previously ~3500 comparisons → now ~500 (single pass). Custom rainbows re-render → previously 5×17k = 85k → now 5 lookups. Hero sort comparator → previously O(n×c) → now O(n log n).
- **Other audit items not shipped this tick (queued for ticks 31-32):**
  - **iOS #2 + #4 (CollectionView rainbowRows computed property)**: rebuilds ownedBobaIds Set + sorts heroes from scratch on every body re-eval. Fix: move to `@State` + `.onChange(of: collection.userCards)`. Multi-file edit; queued for tick 31.
  - **Web #8 Synchronous innerHTML of all groups (no pagination)**: 500+ cards = 500+ DOM elements in one `innerHTML` assignment. Significant work to virtualize; queued for tick 32 if user impact warrants.
  - **iOS dictionaries**: confirmed correct per `feedback_derived_arrays_must_rebuild` memory.
  - **iOS search debounce**: confirmed correct (120ms).
  - **Android `Flow` + `associateBy`**: confirmed correct (uses persistent collections, O(1) joins).
- **PARITY.md:** No row — performance fix.
- **Architectural note:** the memoization keys use `JSON.stringify(criteria)` — fine for the 8-key criteria objects (5-30ms total per call typically). If criteria balloon (more dimensions), revisit with a structural hash.
- **Next:** Tick 31 — iOS Collection rainbowRows computed-property → @State pattern. Same audit findings, different platform.

### Tick 29 — 2026-05-20 — Find empty-state: icon + dynamic body
- **Picked:** Per the `universal-feature-states` skill, every empty state should carry brand-voice copy + productive next-action. Web Find's was just "No cards match your search." + Clear button — generic, didn't tell the user WHY there were no matches. iOS DESIGN.md §6.7 ships `ContentUnavailableView.search` with refinement suggestions; web parity now.
- **Shipped:**
  - `index.html`: empty-state markup gains a Lucide `search` icon (cyan, low alpha), a "No cards match" `<h2>` title (BOBA orange Bebas), and a dynamic `<p id="empty-state-body">` for the contextual line. Existing Clear-all-filters button kept.
  - `js/app.js`:
    - `updateEmptyStateBody()` — inspects every active filter (query / element / set / treatment / release / hasImage / powerMin / powerMax) and synthesizes a brand-voice line:
      - No filters active: *"Try a different search."*
      - One filter active: *"Nothing matches FIRE. Try loosening or removing the filter."*
      - Multiple active: *"Nothing matches all of: \"maverick\" · FIRE · power 60–80. Try removing one."*
    - Called from `renderNextPage` when `filteredCards.length === 0`.
  - `css/styles.css`: re-styled `.empty-state` (centered, max-width 420px, narrower padding) + new `.empty-state-icon` (low-alpha cyan) + `.empty-state-title` (orange Bebas) + `.empty-state-body` (muted mono).
- **Verified:** node -c clean. Logic trace: typing "xyzabc" → 0 results → body line `"Nothing matches \"xyzabc\". Try loosening or removing the filter."` Adding a FIRE filter on top → `"Nothing matches all of: \"xyzabc\" · FIRE. Try removing one."` Clear filters → grid repopulates.
- **PARITY.md:** No row — iOS §6.7 already covers; this is web parity catching up.
- **Architectural note:** the empty-state DOM is static in index.html with a single dynamic `<p>` — JS only mutates the body text, never the icon/title. Keeps rendering cheap; doesn't fight View Transitions.
- **Next:** Tick 30. Plausible: (a) extend `updateEmptyStateBody` to also color-tint per active filter (visual continuity), (b) audit other view empty states (Collection, Decks, Learn) for the same pattern, (c) audit Filter sheet keyboard nav.

### Tick 28 — 2026-05-20 — Sign-in modal accessibility polish
- **Picked:** Audit from tick-27 "Next" list. Sign-in modal is the highest-stakes a11y surface — screen-reader users hitting it without proper announcements have a worse experience than they should. Native `<dialog>.showModal()` already handles focus trap + ESC + scroll lock + top layer per WEB-DESIGN.md §13; this tick closes the small gaps on top of that.
- **Audit findings + fixes:**
  - **Stale `aria-label`**: dialog had `aria-label="Sign in to BOBA Playbook"` static. When user toggled to Create Account, the label still said "Sign in" — wrong context for screen readers. Fixed: new `_updateAriaLabel()` swaps between "Sign in to BOBA Playbook" and "Create your BOBA Playbook account" on open + on mode tab switch.
  - **Missing form-validation hooks**: email + password inputs lacked `required` / `aria-required`. Added both on every required field. Web's native form validation now fires `:invalid` styling + browser tooltip on bare-empty submit.
  - **Password hint**: signUp mode adds `<p id="auth-password-hint" class="auth-field-hint">6 characters minimum.</p>` + `aria-describedby="auth-password-hint"` on the password input. Screen readers announce the constraint on focus.
  - **Min-length validation**: signUp password + confirm gain `minlength="6"` for native HTML5 validation.
  - `css/styles.css`: small `.auth-field-hint` style (muted mono caption).
- **What was already correct (verified):** `<dialog>.showModal()` handles focus trap natively; ESC dismisses; backdrop click dismisses (explicit handler at line 379); first-focus on email field via 60ms `setTimeout` (necessary because `showModal()`'s auto-focus competes with the input's `autofocus` if used); close-button labeled `aria-label="Close sign-in"`; error/info `<p>` already have `role="alert"` and `role="status"`; submit button is a real `<button>`.
- **Verified:** node -c clean. Manual trace: tab to signUp → aria-label re-issued; tab back → aria-label re-issued. Empty-submit fires browser tooltip ("Please fill out this field"). Password-hint announces under the field on focus in signUp mode.
- **PARITY.md:** No row — a11y polish on an already-✅ flow.
- **Architectural note:** the `<dialog>` element is doing most of the heavy lifting. Native-first paying off again — a custom modal would need a focus-trap library, ESC handler, scroll lock, top-layer compositing, and backdrop. We get it all for free + can layer dynamic aria-label + HTML5 validation on top.
- **Next:** Tick 29. Plausible: (a) similar a11y pass on the card-detail modal, (b) similar a11y pass on the wall-overlay, (c) audit Find filter sheet for keyboard / a11y, (d) move to a non-a11y polish item.

### Tick 27 — 2026-05-20 — Public collection "Wall" button (canvas share image)
- **Picked:** Continuing the public-collection user-acquisition arc. Tick 25 added the unauth CTA, tick 26 added the Share button (URL share). Tick 27 closes the trio with a Wall button — visitor (auth or unauth) renders the cards they're viewing as a downloadable PNG. Reuses the tick-9/10 `openCardsWallSheet` pipeline entirely; this is mostly UI wiring.
- **Shipped:**
  - `index.html`: wrapped the existing Share button + new Wall button in `.public-collection-actions` cluster. Wall button shares the same pill style (cyan + Lucide `image` icon + "Wall" label).
  - `js/app.js::renderPublicCollection`:
    - After `resolved` is built, find `#public-collection-wall`, pull catalog cards out of `resolved.map(r => r.card).filter(c => c?.imageFile)`, set `wallBtn.hidden` based on count, and wire `onclick` to `window.Collection.openCardsWallSheet({ title: '@handle on BOBA Playbook', cards })`.
    - Use `onclick =` (not addEventListener) so re-renders cleanly overwrite the handler instead of stacking.
    - Hidden when there are zero rendered cards — no point offering a wall of nothing.
  - `css/styles.css`: `.public-collection-actions` cluster — vertical stack on narrow widths, horizontal at ≥640px. Stays right-aligned next to the title.
- **Verified:** node -c clean. Logic trace: open `/u/ben` → 47 cards render → Wall button shows → click → existing wall dialog opens with title "@ben on BOBA Playbook" + 47 cards → user can download PNG via existing flow. Private collection → grid is empty → Wall button hidden.
- **Why this matters:** the unauth CTA captures users who want to BUILD. The Share button captures users who want to PROPAGATE. The Wall button captures users who want to SAVE a snapshot — works regardless of auth. Three orthogonal intent paths off one landing page.
- **PARITY.md:** No row — public-collection is web-only.
- **Architectural note:** the openCardsWallSheet pipeline is now called from FOUR surfaces: Collection (own designation), Decks (deck wall), Find multi-select (selected cards), public-collection (someone else's grid). The shared `openWallSheet({ context: 'deck', title, cards })` route handles all four cleanly. Worth a DECISIONS.md entry capturing the Wall view as a primitive when it stabilizes.
- **Next:** Tick 28. Plausible: (a) accessibility audit on Sign-in modal (focus trap + return focus), (b) view-source `<noscript>` content for non-JS browsers, (c) audit YouTube Watch tab for parity gaps.

### Tick 26 — 2026-05-20 — Public collection Share button
- **Picked:** Complement to tick-25's CTA. A visitor who landed via a shared link → enjoys the collection → wants to re-share it with a friend → had to copy the URL bar manually. One-tap share unlocks viral propagation.
- **Shipped:**
  - `index.html`: new `<button id="public-collection-share">` in the public-collection header next to the title. Lucide `share-2` icon (the three-dot connected graph) + "Share" label. Cyan pill style matching the brand's secondary action treatment.
  - `js/app.js::renderPublicCollection`: wires the button via `window.bobaShareTarget({ title, text, url }, shareBtn)`. Title = `@handle on BOBA Playbook`. Text = `Check out @handle's BOBA card collection`. URL = canonical `${origin}/u/${handle}` (NOT the current `?u=…` form) so recipients see the same nice URL. `{ once: true }` so re-renders don't double-bind.
  - `css/styles.css`: `.public-collection-share` cyan-pill button + made `.public-collection-titlebox` flex-grow so the button sits at the trailing edge of the header without crowding the title.
- **Verified:** node -c clean. Logic trace: open `/u/ben` → click Share → if `navigator.share` available, system sheet pops up with the pre-filled title + text + URL; if not, URL copies to clipboard with "Link copied!" inline confirmation (the existing `bobaShareTarget` fallback path from `feedback_native_first`).
- **Why this matters:** the CTA in tick 25 captures visitors who want to BUILD their own collection. The Share button captures visitors who want to PROPAGATE the collection they're viewing. Together they cover both intent paths from the same landing page.
- **PARITY.md:** No row — public collection is web-only; iOS / Android deep-link IN to view it but the share affordance is the visitor's web-platform action.
- **Architectural note:** `bobaShareTarget` (declared at app.js:390) is the shared share helper — Web Share API → clipboard fallback → toast. All sharing surfaces should use this, not navigator.share directly. Three call sites now (card detail, profile-public-link copy, this). Worth promoting to a documented primitive in WEB-DESIGN.md §16 in a future tick.
- **Next:** Tick 27. Plausible: (a) "Wall this collection" button on public-collection (renders the visible cards via the tick-9/10 canvas pipeline so the visitor can download a PNG), (b) add a "View on BOBA Playbook" inline preview snippet for OG image rendering, (c) audit Sign-in modal accessibility (focus trap + ESC + return focus).

### Tick 25 — 2026-05-20 — Public collection CTA for unauth visitors
- **Picked:** Web-only gain. Visitors landing on `/u/{username}` from a shared link saw the cards but had no obvious next step. High-leverage user-acquisition surface — they're already engaged enough to view someone else's collection.
- **Considered Find Quick Add audit** first; concluded the existing flow is fine — duplicate-click adding two copies might be intentional (user just bought 2 copies of the same card). Skipped.
- **Shipped:**
  - `index.html`: new `<div id="public-collection-cta" hidden>` below the public-collection grid. Headline "Start your own BOBA collection" + body ("Track, build, share — free, mobile-first, no installs") + two actions: "Explore the catalog" (→ Find) and "Sign in / Create account" (→ Auth modal).
  - `js/app.js`:
    - `wirePublicCollectionCTA()` shows the CTA only when `Auth.isAuthenticated()` is false. Wired-once handlers (`{ once: true }`) on the two buttons so a click immediately advances and the CTA doesn't try to bind twice on re-render.
    - Called at the end of `renderPublicCollection` after the grid mounts.
  - `css/styles.css`: ~40 lines for `.public-collection-cta` — gradient background (orange→cyan brand glow at low alpha), centered max-width 480px, two-button row that wraps on mobile.
- **Verified:** node -c clean. Logic trace: unauth visitor lands on `/u/ben` → grid renders → CTA appears below. Signed-in visitor → CTA hidden. Tap Explore → `showView('search')`. Tap Sign In → `Auth.open()`.
- **Why this matters:** the public-collection page is BOBA's #1 organic user-acquisition surface — every shared link is a potential install. A passive grid with no CTA was leaving conversions on the floor. Two clear paths (browse first OR sign in first) honor the user's level of intent.
- **PARITY.md:** No row — web-specific (no iOS/Android equivalent — they handle deep-link install via App Store / Play Store).
- **Architectural note:** the CTA appends ONCE per render via `{ once: true }`. If a user signs in mid-view, the CTA's stale handlers won't re-bind to a different state; refresh would clear them. Acceptable trade-off vs. the more complex "rebind on auth-change" path.
- **Next:** Tick 26. Plausible: (a) view-public-collection page also gets the Wall view affordance ("Generate wall image") for the viewer to easily share, (b) tap-to-zoom card detail on public-collection (currently opens card modal — confirm parity), (c) audit Profile sign-in modal for accessibility.

### Tick 24 — 2026-05-20 — Profile Delete Account: type-to-confirm
- **Picked:** From tick-23 "Next" — highest-stakes destructive web flow. Prior version had a single `confirm()` with the warning text. Single-click confirm is sufficient for "are you sure?" but not for "permanent + cascading + can't undo." iOS uses a multi-step + type-to-confirm pattern; web matches now.
- **Shipped:**
  - `js/collection.js` `#profile-delete-btn` handler:
    - Step 1 (unchanged): `confirm()` listing what gets removed — added "custom rainbows" to the cascade list since tick 7 shipped them.
    - **Step 2 (new): type-to-confirm.** `prompt()` requires the user to type their `@username` exactly. Pulled live from `API.fetchProfile()`. Case-insensitive compare (username is lowercased server-side anyway).
    - **Fallback:** if the user's profile has no username (edge case — fresh signup that hasn't completed username derivation), the prompt asks for "DELETE" instead, exact-match compare.
    - If the typed value doesn't match → `alert()` says "Confirmation didn't match — your account was NOT deleted." and returns without calling the Worker.
    - Cancel at step 2 → silent no-op.
- **Verified:** node -c clean. Logic trace: click Delete → step-1 confirm → cancel returns; OK proceeds → step-2 prompt with `@{username}` → cancel returns; mismatched type returns with notice; matched type → Worker call → signOut + alert.
- **PARITY.md:** No row change — destructive-flow polish on an already-✅ row (Account deletion §9).
- **Architectural note:** the type-to-confirm pattern is iOS-equivalent in safety without needing a custom `<dialog>` — native `confirm()` + `prompt()` cover both gates with zero new chrome. WEB-DESIGN.md §2.1 native-first.
- **Why this matters:** account deletion cascades to user_cards / decks / shows / custom_rainbows / user_profile / auth.users via FK CASCADE. No undo, no recovery beyond a fresh signup. A type-to-confirm gate is the right friction for that blast radius.
- **Next:** Tick 25. Plausible: (a) Find Quick Add audit, (b) destructive Discord-unlink flow if it exists, (c) other admin-panel actions.

### Tick 23 — 2026-05-20 — Web Decks Clear: confirmation guard
- **Picked:** From tick-22 "Next" list. Found real bug: clicking the ✕ Clear button in the deck-builder toolbar destroyed the entire deck (heroes + plays + bonus + hot dogs) with **zero confirmation**. One misclick on the small icon could nuke an hour of work. iOS DECISIONS.md mentions the Clear confirm dialog; web had no equivalent.
- **Shipped:**
  - `js/practice.js` `db-clear-btn` handler:
    - Empty-deck shortcut: `totalCards === 0` → skip confirm + clear directly (clearing an already-empty deck is a no-op anyway).
    - Non-empty deck: native `confirm()` with a section-by-section count summary: *"Clear this deck (5 heroes, 28 plays, 4 bonus, 10 hot dogs)? Your deck name and format settings stay."* The plural-aware labels avoid awkward "1 heroes" / "0 plays" cruft.
    - Cancel → early return → deck untouched.
    - Confirm → existing `DB.clear() + reset name + dbRender` flow.
- **Verified:** node -c clean. Logic trace: empty deck → clear directly. Built deck → confirm with count summary → cancel returns → clear proceeds.
- **PARITY.md:** No row change — bug fix, not a feature.
- **Architectural note:** native `confirm()` is acceptable for destructive guards. WEB-DESIGN.md §2.1 "native-first" — `<dialog>.showModal()` would be the deluxe path, but the simpler `confirm()` is what the existing rainbow-delete + deck-delete affordances already use; consistent here.
- **Next:** Tick 24. Plausible: (a) audit save flow on Find Quick Add (mentioned in tick 22), (b) Find search "clear all" keyboard shortcut + UI button, (c) Decks → save deck duplicates an existing deck-id warning, (d) audit Profile delete-account flow (high stakes, should be very explicit).

### Tick 22 — 2026-05-20 — Web Decks save: empty-deck guard + inline feedback
- **Picked:** Audit triggered by tick-21b "Next" plan. Found three issues with the current Save flow: (1) zero-card decks could be saved, writing junk rows to Supabase. (2) Empty / whitespace deck name was accepted unchanged. (3) Errors went to `alert()` instead of the existing inline `db-import-banner` (used by import + every other deck-builder transient feedback).
- **Shipped:**
  - `js/practice.js` `db-save-btn` handler:
    - Empty-deck guard: refuse to save when `cards.length === 0`; show "Add at least one card before saving." inline via `db-import-banner` (3s auto-hide). Mirrors iOS DeckBuilderStore which refuses save at totalCardCount == 0.
    - Name guard: `(DB.deckName || '').trim() || 'New Deck'` — accepts whitespace as a typo and silently defaults rather than fighting the user with an error.
    - Success path: inline `Saved "{deckName}".` (2.5s auto-hide) in addition to the existing green-flash on the button.
    - Failure path: inline `Save failed: {message}` (persistent until next user action) instead of the prior `alert()`. Falls back to alert() only if the banner element is missing.
- **Verified:** node -c clean. Logic trace: click Save with 0 cards → banner says "Add at least one card before saving." + button NOT disabled (returns early). Click Save with cards → existing flow + new success banner. Server error → inline banner with err.message, no alert.
- **PARITY.md:** No row change — this is a polish + correctness fix on an already-✅ row.
- **Architectural note:** the `db-import-banner` is now used by Import + Save + future Decks transient feedback. Worth promoting to a generic `.db-banner` class in a future refactor if more callers appear.
- **Next:** Tick 23. Plausible: (a) audit save flow on Find Quick Add (similar single-card add path), (b) audit the deck-builder "Clear" button confirmation (might already exist), (c) random-card affordance on Find.

### Tick 21b — 2026-05-20 — Rollback: remove Twitter Card meta + add binding "never" docs
- **Picked:** Ben directive. Twitter / X is owned by a fascist; BOBA will not integrate. Same-day rollback of tick 21's Twitter Card additions.
- **Shipped:**
  - `index.html`: removed all four `<meta name="twitter:*">` tags + updated the OG-block comment to call out "no `twitter:*` per DECISIONS.md #053." OG protocol tags kept (read by every other major platform).
  - `js/app.js::updateOpenGraphMeta`: stripped `twitter:title` / `twitter:description` / `twitter:image` setters. Helper now updates the four `og:*` properties only. Comment updated to flag the "never" rule.
  - `DECISIONS.md`: new entry **#053 — No Twitter / X integration, ever**. Explicit rule (no OAuth, no Card tags, no share intents, no SDK, no API) + why (BOBA is a tool for human learning; Twitter is owned by a fascist; integration would signal endorsement + provide material support) + what still ships (full OG protocol, Discord per DECISIONS.md #049, other social platforms when use cases arise).
  - `DESIGN.md §12 "Out of scope"`: row added — "Twitter / X integration (any form)" → "Never".
  - `WEB-DESIGN.md §17 "Out of scope"`: same row.
  - `ANDROID-DESIGN.md §12 "Out of scope"`: same row.
  - Memory: `feedback_no_twitter_integration.md` with the binding context for future sessions.
- **Why this is binding, not aesthetic:** the docs are explicit. Any future tick that reaches for a `twitter.com` URL, a `twitter:*` meta tag, a "Share to Twitter" button, or a Twitter SDK is rejected at proposal stage. Other social platforms (Discord, Bluesky, Mastodon, Threads) are fine when use cases arise.
- **Net effect on tick 21:** OG protocol still ships fully — Discord, iMessage, Slack, Bluesky, Mastodon, Threads, Facebook, LinkedIn, WhatsApp, Signal, Telegram, and search engines all read OG. Tick 21's user-acquisition + sharing value lands. Only the Twitter-specific dialect is gone.

### Tick 21 — 2026-05-20 — Open Graph + Twitter card meta tags
- **Picked:** Documented in tick-20 "Next" as the next obvious polish. The web app had zero OG / Twitter meta tags — any link to BOBA Playbook shared in Discord, iMessage, Slack, Twitter, etc. got either a blank preview or the browser's auto-generated text-only card. Cheap to ship with meaningful user-acquisition + sharing impact.
- **Shipped:**
  - `index.html`: static OG + Twitter card metadata in `<head>`. Defaults:
    - `og:type = website` · `og:site_name = BOBA Playbook` · `og:title` + `og:description` describe the app shell.
    - `og:url = https://bobaplaybook.com/`
    - `og:image = https://bobaplaybook.com/assets/icons/boba_playbook_icon_1024.png` (1024×1024 XOXO mark — copied from `Logos/` into `assets/icons/` for web-accessibility).
    - `twitter:card = summary_large_image` so the icon renders at the full preview width.
  - `js/app.js`:
    - `updateOpenGraphMeta({title, description, url, image})` helper — selects existing `<meta property="og:*">` and `<meta name="twitter:*">` elements by attribute and updates their `content`. Skips any field the caller didn't pass (partial updates supported).
    - `applyView(name)` now updates og:title + og:url for the active route.
    - `openModal(card)` updates og:title + og:description (hero · treatment · set) + og:url (the deep-link URL via `buildCardURL`) + og:image (the card's full-resolution R2 URL via `API.cardFullUrl`). Restored on `closeModal()` to the app shell defaults.
    - `renderPublicCollection(handle)` updates the OG triple to "@handle · BOBA Playbook" + description "Public BoBA card collection by @handle" + URL `/u/{handle}`.
  - **Caveat documented in code comment:** link crawlers (Discord / Twitter / iMessage / Slack) only read the STATIC `<head>` HTML they fetch — they do not run JS. So the client-side per-route updates only help in-app share affordances (`navigator.share()` reads `document.title`, browser extensions reading the DOM, the user's tab-switcher / Cmd+Shift+A). Server-side rendering of per-route OG isn't possible on GitHub Pages and is genuinely deferred.
- **Verified:** node -c clean. Manual: load `https://localhost:8080/` → static OG defaults. Click card → openModal → OG image becomes that card's R2 URL. ESC → defaults restored. Public collection → "@handle · BOBA Playbook" OG.
- **PARITY.md:** No row change — web platform polish; iOS / Android handle share previews via system mechanisms.
- **Architectural note:** the `updateOpenGraphMeta` helper takes a partial object so callers don't need to pass every field. Callers that need a specific tag stable (e.g. `og:type` should always be "website") just don't pass that key.
- **Next:** Tick 22. Looking at what's still pickable and meaningful. Plausible: (a) "Random card" affordance in Find search (1-tick fun feature, no parity gap), (b) Audit the Decks editor save flow for the empty-deck case, (c) Audit accessibility (tab-order / aria-current / aria-live) across Find grid and Card detail modal.

### Tick 20 — 2026-05-20 — Per-view browser tab title (WEB-DESIGN.md §4.1)
- **Picked:** Documented anti-pattern in WEB-DESIGN.md §4.1 ("Pages that aren't pages") — `document.title` was static "BOBA Playbook" across all 10 routable views. Bookmarks, tab switchers, and shared-link previews all showed the same name. Long-standing UX gap; cheap to ship.
- **Shipped:**
  - `js/app.js`:
    - `VIEW_TITLES` constant — single source of truth mapping each routable view name (`search`, `scan`, `rules`, `decks`, `practice`, `stores`, `collection`, `purchase`, `profile`, `public-collection`) to a display title (`Find`, `Scan`, `Learn`, …). Format: `{viewTitle} · BOBA Playbook`.
    - `applyView(name)` now writes `document.title` from the table after the view-switch. Inside the View Transitions API callback so the title flip aligns with the visual cross-fade.
    - `openModal(card)` updates `document.title` to `${cardLabel} · BOBA Playbook` when a card detail opens. Restored by `closeModal()` from `VIEW_TITLES[currentView]`.
    - `renderPublicCollection(handle)` overrides to `@${handle} · BOBA Playbook` so bookmarks of someone's public page read as their handle, not the generic view name.
- **Verified:** node -c clean. Trace: load page (`?view=collection`) → applyView('collection') → tab title = "Collection · BOBA Playbook". Click card → openModal → "Maverick · BOBA Playbook". ESC → closeModal → "Collection · BOBA Playbook". Navigate to public collection → renderPublicCollection('ben') → "@ben · BOBA Playbook". Back to Find → applyView('search') → "Find · BOBA Playbook".
- **PARITY.md:** No row change — quality-of-life fix on the web platform; iOS/Android handle this via system nav-bar titles.
- **Why this matters:**
  - Multi-tab browsing: users opening Find + Collection + Decks in separate tabs can now tell them apart in the tab switcher and Cmd+Shift+A search.
  - Bookmarks: pinned `/u/ben` reads as `@ben · BOBA Playbook` instead of `BOBA Playbook` — meaningful for users who share or save URLs.
  - Browser history: back/forward navigation in the back-history dropdown shows distinct labels per view (Chrome / Edge / Safari all read `document.title` for the history entry label, not `history.state`).
  - OG: a future `<meta property="og:title">` update would land cleanly here.
- **Architectural note:** the `VIEW_TITLES` map is the single source for view titles on web. Other call sites that need a view's display title (sidebar, breadcrumb if we ever add one, share-target preview) should read from this map, not hardcode strings.
- **Next:** Tick 21. Continue picking from PARITY.md gaps + WEB-DESIGN.md polish items. Strong candidates: (a) Open Graph meta tags for `/u/{username}` pages so Discord / Twitter link previews work (would need to be at fetch-time since GitHub Pages is static; could be approximated via `<meta>` swap on render), (b) audit Decks Save flow for empty-deck rejection, (c) audit Find search for off-by-one in suggestion-popover positioning.

### Tick 19 — 2026-05-20 — Auth-state cache reset + post-tick-18 audit
- **Picked:** Bring web in line with the `feedback_viewmodel_reset_on_auth_change` discipline shipped on Android. Two scenarios to guard against: (1) signed-in user A signs out → some cached state survives → user B signs in same tab → A's state briefly visible. (2) The window between sign-out and Auth.open() showing a stale rainbow's name in an open editor dialog.
- **Audit done:** verified `public-collection` page (`buildCardElement` already routes through `API.cardThumbUrl`), Watch tab (wired to `boba-youtube-feed` Worker), Profile public-URL copy (working), Decks card popup (deck cards never sealed, no CDN issue). No more bugs in the same family as tick 18.
- **Shipped:**
  - `js/collection.js::clear()` — now also resets `_customRainbowsById = {}`, `_editingRainbow = null`, `_draftCriteria = {}`. On sign-out, the rainbow cache + editor state are wiped so a subsequent sign-in starts clean. Mirrors the Android ViewModel-reset pattern: previous-user data can't leak into the next session.
- **Verified:** node -c clean. `clear()` is invoked by the auth-state-change listener at line 2872; both `signOut` and `tokenRefreshed → no session` paths reach it.
- **PARITY.md:** No row change — discipline fix, not a feature ship.
- **Architectural note:** the three `_…` caches all live at module scope inside the Collection IIFE. Future per-user caches added in this module should be reset in `clear()` too. (No lint rule enforces this — it's discipline.)
- **Next:** Tick 20. Want to find a higher-impact ship. Considering: (a) browser-tab-title updates to reflect the active view (today: shows the static <title> always), (b) Collection sort-mode persistence (memory across sessions), (c) preset deck-builder format remembered across sessions (already does via `bp_decksFormat_v1`?).

### Tick 18 — 2026-05-20 — Web sealed-product CDN routing bug fix (Collection)
- **Picked:** Audit triggered by PARITY.md/tick-12 reference to the Android CDN sealed-routing memory + the tick-1 missing-sealed surfacing. Confirmed Find grid + Wall + variant-tile all correctly route via `API.cardThumbUrl`. **Found three Collection-side bugs** where the code called raw `API.thumbUrl(imageFile)` / `API.fullUrl(imageFile)` instead of the sealed-aware `API.cardThumbUrl(card)` / `API.cardFullUrl(card)`.
- **Real-user impact:** sealed products live at `/sealed/thumbs/` + `/sealed/optimized/` on R2. Any sealed product in a user's Collection (designation = personal/for_sale/for_trade/wanted/grails) would 404 in the Collection grid, the variant-tile picker, AND the collection card-detail view. The user would see a broken-image icon for every sealed box / blaster they own. iOS shipped sealed routing per `feedback_ios_sealed_products` memory; Android shipped via `reference_android_cdn_sealed_routing` (overnight 2026-05-20); web had been silently broken.
- **Shipped:**
  - `js/collection.js`:
    - `buildCollectionCardHtml` (the main collection grid cell) — replaced raw `API.thumbUrl(imageFile)` + `API.fullUrl(imageFile)` with `API.cardThumbUrl(catalogCard)` + `API.cardFullUrl(catalogCard)`. Reads from the resolved `catalogCard` so the `cardType === 'Sealed Product'` check fires. srcset pair updated to match.
    - Collection card-detail header image (`cdetail-card-img`) — same fix.
    - Variation tile (`cdetail-var-img` in the "Other Versions" strip) — same fix.
  - **No new bugs introduced:** the `API.cardThumbUrl(card)` signature takes the FULL card record (needs `imageFile` + `cardType`); the prior code was calling `API.thumbUrl(string)` which takes only the filename. Verified all three rewrites pass the catalog record (`catalogCard` / `card`) not the filename.
- **Verified:** node -c clean. `grep -rn "API.thumbUrl\|API.fullUrl"` returns zero hits across `js/` — every web image render path now goes through the sealed-aware helpers. `cards.json` confirmed to have `cardType: 'Sealed Product'` on all 45 sealed entries.
- **PARITY.md:** No row addition — this is a bug fix, not a parity story. But it does close the "Verify sealed-image fix on web + Android" P0 from the original autonomous-loop backlog (Android was confirmed shipped overnight; web is now verified + fixed).
- **Architectural note:** the cleanest fix would be to inline a `cardType` check directly inside `API.thumbUrl(filename)` + `API.fullUrl(filename)` so any caller is automatically safe. But that would require passing the cardType alongside (or guessing from filename prefix), and the existing `cardThumbUrl(card)` / `cardFullUrl(card)` already exist for exactly this. Better discipline going forward: PR review for any new `API.thumbUrl(` or `API.fullUrl(` raw call.
- **Next:** Tick 19. Plausible: (a) audit Find grid for the same kind of "rendered without sealed routing" issue (already confirmed clean), (b) public-collection page sealed routing check, (c) Decks editor improvements.

### Tick 17 — 2026-05-20 — Custom Rainbow editor polish + drift fix
- **Picked:** With ~500 distinct heroes and ~80 distinct sets in the tick-16 sub-pickers, scrolling to find "Maverick" was painful. Web has the keyboard + a wider canvas — adding a search-within-picker is a natural web-only polish that improves the tick-16 work meaningfully. Also Enter-to-save shortcut + PARITY.md drift fix (Card detail swipe nav web — was n/a but actually shipped).
- **Shipped:**
  - `js/collection.js`:
    - `_renderFilterDim` now emits a `<input type="search" class="rainbow-filter-search">` at the top of any picker with ≥20 options. Per-picker input handler hides non-matching `.rainbow-filter-option` labels via `style.display = 'none'`. Hiding (vs re-rendering) preserves the checked state of items the user has already toggled.
    - Option labels carry a `data-search="<lowercased value>"` attribute for the substring match — case-insensitive, single-comparison.
    - Editor dialog `keydown` handler: Enter in the name field saves; Cmd/Ctrl+Enter anywhere in the dialog saves (matches iOS DESIGN.md §7 keyboard-shortcut affordance). ESC is handled natively by `<dialog>`.
  - `css/styles.css`: split `.rainbow-filter-body` into `.rainbow-filter-search` (sticky-ish search input) + `.rainbow-filter-options` (the existing 150px-min grid moved inside) so the search input sits above the scrolling grid.
  - `index.html`: no markup change — the search input is generated in JS so it's only present where it's useful.
- **Drift fix (PARITY.md):** Card detail swipe nav (left/right) was marked `n/a (no nav)` for web but web has had it since the modal was built — `ArrowLeft/Right` keys + touch-swipe (>60px horizontal threshold + dx > 1.5×dy) wired to `navigateModal(±1)` in app.js. Corrected to ✅ with audit note.
- **Verified:** node -c clean. UX trace: open editor → Heroes section shows ~500 entries with search → type "Maver" → only Maverick visible → check → search wiped → re-open Heroes → all heroes visible, Maverick still checked. Enter from anywhere in dialog → Save fires.
- **PARITY.md:** Card detail swipe nav web `n/a` → ✅.
- **Architectural note:** the search input is conditional (`values.length >= 20`) so it doesn't dead-chrome the smaller pickers (Weapons = 9, Card types = ~5). The threshold can be tuned but 20 is the natural inflection where scroll-fatigue starts.
- **Next:** Tick 18. Plausible: (a) Find — multi-select-clear-all keyboard shortcut OR Esc-to-clear (web has Escape→exitSelection per app.js line 3273; verify), (b) Audit Sealed product handling on web for the missing-sealed surfacing from tick 1 (visibility check), (c) Polish for Decks card-detail flow (cross-deck warnings, format compatibility hints).

### Tick 16 — 2026-05-20 — Custom Rainbow editor sub-pickers + live preview
- **Picked:** Second slice of the custom-rainbow editor — adds the seven filter dimensions (heroes / sets / sub-sets / weapons / treatments / cardTypes / releases) + Inspired Ink toggle + live "N matches · X owned (Y%)" progress preview. Closes the iOS CustomRainbowEditorSheet parity gap in one extra tick (tick 15 + tick 16 vs the planned 3-tick split).
- **Shipped:**
  - `index.html`: editor `<dialog>` extended — preview band ("N cards match · X of those owned"), seven `<details>` filter dimensions, each with an empty `.rainbow-filter-body` for hydration, plus an "Inspired Ink only" checkbox toggle.
  - `js/collection.js`:
    - `RAINBOW_DIMS` constant — single source of truth for the seven dimensions, each mapping the criteria key (`heroes`, `sets`, etc.) to the Card field (`hero`, `set`, etc.) it filters on. Verbatim parity with iOS CustomRainbowEditorSheet.SubPicker.
    - `distinctCatalogValues(dimKey)` — memoized; pulls distinct non-empty values for one dimension from `window.__bobaCatalog`, sorted case-insensitively. Cache is module-scoped (catalog doesn't change during a session). Heroes: ~500 values; Sets: ~80; etc.
    - `_renderFilterDim(dim)` — hydrates one `<details>` with `<label><input type="checkbox" data-value="…">` rows. Pre-checks based on the in-flight `_draftCriteria`. Summary shows `· N` count of selected.
    - `_renderPreview()` — recomputes "N cards match · X of those owned (Y%)" by running `API.rainbowCriteriaMatches` across the catalog with the draft criteria, intersected with the user's ownedCards keys. Cheap at 17k cards (single linear pass per change).
    - Single delegated `change` handler on the filters container catches both per-dimension checkbox toggles AND the Inspired Ink toggle — `O(1)` wiring regardless of how many catalog values render. Case-insensitive add/remove (so a user pre-existing rainbow with `criteria.heroes = ["Maverick"]` correctly intersects with the checkbox emitting `data-value="Maverick"`).
    - Save now passes `_draftCriteria` instead of empty `{}`. Edit mode deep-clones existing criteria into `_draftCriteria` so canceling doesn't mutate the cached rainbow row.
  - `css/styles.css`: ~95 lines added — `.custom-rainbow-editor-preview` band (cyan accent), `.rainbow-filter` collapsible cards, `.rainbow-filter-body` as a 150px-min responsive grid with 220px max-height + overflow:auto (long lists scroll inside the picker rather than pushing the dialog), `.rainbow-filter-option` checkbox rows, `.rainbow-filter-toggle` for the Inspired Ink switch.
- **Verified:** node -c clean. Manual trace: open editor on existing iOS-created rainbow w/ `{heroes:["Maverick"], elements:["FIRE"]}` → both Heroes and Weapons sections pre-check the right options → preview shows the right match count. Save round-trips correctly.
- **PARITY.md:** Custom Rainbows web ✅ read + name-only → ✅ (full). Closes the Custom Rainbows row entirely.
- **Architectural note:** the `RAINBOW_DIMS` array is the source of truth for keying. Future dimensions (e.g. a "subtypes" expansion when BoBA adds more taxonomy axes) just add one row + the corresponding logic in `API.rainbowCriteriaMatches`. The editor markup template auto-handles by selector `.rainbow-filter[data-dim="..."]` — no per-dim if/else.
- **Next:** Tick 17. Custom Rainbow editor is complete; pick next from PARITY.md. Strong candidates now that Rainbows are closed: (a) `prefers-color-scheme` honoring on web (`feedback_native_first` candidate — the brand is dark-first; light mode is a stretch though), (b) Sort-by-completion on Hero Rainbows, (c) Streamer "My Shows" web surface (multi-tick — significant). Leaning (b) — quick polish on the hero-rainbow surface from tick 8.

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
