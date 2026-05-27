# BOBA Playbook — Android Design Theory

> **Binding.** Every new screen, sheet, dialog, filter in the Android app must trace to a rule here. Fix the document, then the feature.
>
> Companion to [`DESIGN.md`](./DESIGN.md) (iOS), [`WEB-DESIGN.md`](./WEB-DESIGN.md), [`TRADE-DESIGN.md`](./TRADE-DESIGN.md), [`DECISIONS.md`](./DECISIONS.md), [`PARITY.md`](./PARITY.md). DESIGN.md governs cross-platform principles; this doc owns Android-specific rules. Engineering reference: [`ANDROID-DEV.md`](./ANDROID-DEV.md). Ratified 2026-05-19.

---

## 0. How to use this document

**Ben's job:** when an Android UI choice contradicts a rule, point at the rule.

**Claude's job:** before proposing any new screen / sheet / dialog / picker / nav level / FAB, quote the rule that justifies it. No fitting rule = needs a new rule (and discussion) before it ships.

**Living document.** §§5–7 follow Material updates (M3 Expressive graduations, Android 17). §§1–4 are principles.

**Cross-platform parity** is governed by DECISIONS.md #005 + #041. Verbs are identical across iOS / web / Android (Find / Learn / Decks / Collection / Purchase); native idiom wins per platform. **Android is its own discipline** — don't port iOS shapes; translate iOS intent into M3 components.

---

## 1. Android-specific constraints

- **Kotlin + Jetpack Compose only** (DECISIONS.md #041). No XML, no AppCompat, no legacy ActionBar. `ComponentActivity`, not `AppCompatActivity`.
- **`minSdk = 29` (Android 10)** · **`targetSdk = 36` (Android 16)** · `compileSdk = 36+`.
- **Material 3 / M3 Expressive** — stable Compose Material 3 1.4.x + M3 Expressive APIs from 1.5.x alpha as they graduate.
- **Edge-to-edge** mandatory at `targetSdk >= 35` (§4 anti-pattern). `Scaffold` handles slots; honor `WindowInsets` elsewhere.
- **Predictive back gesture** default in Android 15, non-opt-out at `targetSdk >= 36`. Every modal / destination must animate during back-drag preview.
- **Adaptive layouts** binding for every screen (§6.6). Android 16+ forbids orientation lock at >600dp.
- **Brand parity over platform parity** — brand theme by default; dynamic color is opt-in (DECISIONS.md #042).
- **Feature parity with iOS** (DECISIONS.md #005) — verb-set identical; implementation Material-native.

---

## 2. The six binding principles

0. **Material Components first.** Every interaction = an M3 / M3 Expressive component before any custom Composable. `SearchBar` before custom `Row { TextField }`; `ModalBottomSheet` before custom drag-from-bottom; `NavigationSuiteScaffold` before a hand-rolled width-class switch; `SharedTransitionLayout` + `sharedBounds` before a custom hero anim; `PullToRefreshBox`, `Modifier.dragAndDropSource`/`dragAndDropTarget`, `TooltipBox`, `DropdownMenu` before custom equivalents. Exhaust the catalog before writing one — iOS's 12-iteration custom-drawer failure mode translates straight to Compose.

1. **Each tab owns one verb.** Find = explore · Learn = understand · Decks = build · Collection = own · Purchase = acquire (DESIGN.md §1.1). Verb collision = structural bug. Cross-cutting (scan/share/sign-in) per §6.5.

2. **Navigation depth ≤ 2.** Tab → list → detail. Deeper = parallel filter axis (`SegmentedButton` / `FilterChip` inside the destination) or different tab. Predictive back reinforces this — every push maps to `popBackStack()`.

3. **Search is the universal navigator.** Find uses the M3 `SearchBar` family; every other tab gets a docked `SearchBar` over its domain. Filters become `FilterChip` rows + `InputChip` inside the query, not nav levels.

4. **Density comes from removing chrome.** M3 Expressive's 30-style type scale collapses to six clean levels with zero added pixels (Tufte / Things 3 / Reeder lineage).

5. **Tonal elevation = navigation chrome only.** `NavigationBar`/`NavigationRail`/`TopAppBar`/`BottomAppBar`/`ModalBottomSheet`/FAB/`HorizontalFloatingToolbar` are the only places `tonalElevation > 0dp`. List rows / cards / content — never. One elevated surface per stacking context. Android analog of iOS §1.5 + WEB-DESIGN.md §2.6.

---

## 3. The IA decision tree

Walk in order; stop at first match.

| Question | Android leaf |
|---|---|
| Top-level mode of the entire app? | `NavigationSuiteScaffold` (3–5 on compact; 5–7 on rail; ≤7 on drawer) |
| Hierarchical drill-down? | `composable(...)` push w/ type-safe routes — max depth 2 |
| Parallel filter / view over same data? | `SingleChoiceSegmentedButtonRow` (≤5) or `FilterChip` row (≥3, scrollable) |
| Full-focus action that might be abandoned? | `ModalBottomSheet(skipPartiallyExpanded = true)` (compact) / side sheet (expanded) |
| Glance-and-return? | `ModalBottomSheet` with partial + expanded states + drag handle |
| Side panel for inspection? | `NavigableListDetailPaneScaffold` (or `SupportingPaneScaffold`) |
| Critical confirmation / blocking decision? | `AlertDialog` / `BasicAlertDialog` — never a sheet |
| Destructive / one-shot config? | `DropdownMenu` from toolbar `IconButton` |
| Global state across screens? | `BottomAppBar` slot OR `HorizontalFloatingToolbar` |
| Verb in ≥2 tabs? | Cross-cutting capability (§6.5) |
| Inline option? | `Switch` / `RadioButton` / `Slider` inline, or `DropdownMenu` for >3 |
| Transient confirmation? | `Snackbar` via `SnackbarHost` |
| Persistent attention? | Banner (`Surface` + Row, top-anchored under app bar) |
| None of the above | Fold into an existing screen |

---

## 4. Anti-patterns we reject

- **Russian-doll nav (depth > 2).** Predictive-back drag-peeks one level; deep stacks thrash the preview. Collapse middle layers into segmented controls / scopes.
- **Pill-bar pile-up.** At most ONE persistent `FilterChip` `FlowRow` per screen. Everything else → "Filters" `ModalBottomSheet` or `SearchBar` query chips.
- **Tab-inside-tab.** A second `NavigationBar` confuses `BackHandler`. Use `SegmentedButton` scope inside a destination, or split into a top-level tab.
- **Sheet-on-sheet.** Within a `ModalBottomSheet`, push via internal `NavHost`. Never stack sheet-on-sheet-on-dialog — predictive back dismisses one modal layer at a time.
- **Tonal-elevation soup.** One elevated surface per stacking context. `surface`/`surfaceContainer*` tokens are hierarchy markers, not decoration. List rows / card cells / detail panels stay at `surface` or `surfaceContainerLow`.
- **Settings dump.** Progressive disclosure via `BOBAExpandableSection` (Compose has no `DisclosureGroup`; we own it). Advanced collapsed by default.
- **Picker-row faking a push.** A row with a trailing chevron must push, not open a picker. Use `Switch` / `RadioButton` inline, `DropdownMenu`, or chip stack — never a fake-push.
- **Hamburger drawer on compact.** M3 Expressive de-emphasizes drawers. BOBA's 5 destinations fit `NavigationBar` on compact; `NavigationRail` only at `widthSizeClass >= MEDIUM`.
- **Equal-weight horizontal scrolling rails.** Reserve horizontal scroll for genuine content shelves (`HorizontalMultiBrowseCarousel`, "Recently viewed"). For data, use `LazyVerticalGrid(Adaptive)`.
- **Custom sheet backgrounds.** Strip every `containerColor` / `tonalElevation` override on `ModalBottomSheet`. Reaching for `Modifier.background()` on a sheet means the design is wrong.
- **Hand-rolled scroll-edge fades.** `TopAppBarScrollBehavior` is the native scroll-edge effect — the bar's container color tonally elevates as content scrolls under it.
- **AppCompat / ActionBar / XML.** Compose-only. `ComponentActivity` (never `AppCompatActivity`). No `setSupportActionBar()`, no `Toolbar` widget, no XML menus.
- **Fixed pixel sizing.** `dp` (layout) and `sp` (typography). No `px` outside ripple radii. Don't hard-code widths that ignore size class — use `BoxWithConstraints` or `currentWindowAdaptiveInfo()`.
- **Opting out of edge-to-edge.** Android 16 ignores `windowOptOutEdgeToEdgeEnforcement` on `targetSdk >= 36`. Honor `WindowInsets` via `Scaffold`, `safeContentPadding()`, or `systemBarsPadding()`.
- **Custom focus indicators.** Compose's default `FocusInteraction` works for touch + D-pad. Don't override `indication = null`.
- **FABs for primary nav.** Mirroring iOS no-action-tabs rule, scan lives in the SearchBar's trailing icon, not a FAB. A FAB inside the Decks editor for "Add card" is fine if it doesn't compete with `NavigationBar`.

---

## 5. Density rules

1. **No tinted-box backgrounds on content.** Row separation = `HorizontalDivider` or vertical spacing. Container separation = `surfaceContainer*` token on the parent (TopAppBar / sheet) — never on rows.
2. **Six hierarchy levels via M3 type scale** + **Roboto Flex** (`wght` 400/500/700, `opsz` auto) + Bebas Neue / Russo One for display:

   | Level | M3 token | Use |
   |---|---|---|
   | L1 — Page title | `displaySmall` (36sp, Bebas/Russo) | Wordmark, hero pages |
   | L2 — Section header | `headlineSmall` (24sp, Roboto Flex 700) | "TREATMENTS", "RULES" |
   | L3 — Card title | `titleMedium` (16sp, Roboto Flex 500) | Hero name on card cell |
   | L4 — Body | `bodyMedium` (14sp, 400) | Description, settings rows |
   | L5 — Caption | `labelMedium` (12sp, 400) | Element pill, timestamps |
   | L6 — Tabular | `bodySmall` w/ `tnum` (12sp) | Card # / power / DBS / cost |

   Refuse a seventh level. M3 `*Emphasized` variants reserved for editorial moments (Practice victory, Hero Shot title) — never default body.
3. **Small multiples.** Every grid uses the same `BOBACardCell` (5:7 aspect, `RoundedCornerShape(12.dp)`, uniform padding, badge slot). Density-adaptive via `columnCount`.
4. **Show the data; filter it.** Persistent `SearchBar` + `FilterChip FlowRow` before nav levels.
5. **Progressive disclosure predictable.** `BOBAExpandableSection` for inline, `composable(...)` for push, `ModalBottomSheet` for focused tasks. Never overload.
6. **Gruber test:** *Could a competent designer recreate this screen from a one-paragraph description?* If no, decoration — strip.
7. **Optical sizing via Roboto Flex.** Set `Typography(defaultFontFamily = RobotoFlex)` once at theme level; every text style inherits optical sizing free.

---

## 6. Material 3 Expressive usage rules

Android analog of iOS DESIGN.md §5 — elevation / shape / motion get the same discipline.

1. **Tonal elevation = navigation chrome only.** `TopAppBar`, `NavigationBar`, `NavigationRail`, `BottomAppBar`, `ModalBottomSheet`, FAB, `HorizontalFloatingToolbar`, FAB Menu, `AlertDialog`. List rows / cards / content surfaces — never. Card cells use flat `Surface(color = surface)`, no `tonalElevation`.
2. **One elevated surface per stacking context.** TopAppBar at `surfaceContainer` + BottomAppBar at `surfaceContainer` + open sheet at `surfaceContainerLow` = three roles, no overlap. Anything more stacks flat onto `surfaceContainer`.
3. **Shape tokens consistent.** Card cells `RoundedCornerShape(12.dp)` (`shapes.medium`); surfaces/sheets `shapes.large` (sheets default 28dp top — leave alone); `FilledButton` fully rounded (default); `FilterChip` spec default. Don't override.
4. **Shape morphing for state, not flair.** Use where M3 ships it (`FilterChip` selected-state morph). Don't roll your own.
5. **Tinting = primary action only.** `FilledButton` / FAB get `colorScheme.primary`. `colorScheme.error` only for true destruction.
6. **Strip custom `containerColor` on sheets/dialogs.** Let M3 apply the spec.
7. **`TopAppBarScrollBehavior` IS the scroll-edge effect.** `enterAlways` for dense scrolls (Find/Decks/Collection), `exitUntilCollapsed` for hero-title screens (card detail, Learn article), `pinned` for sheets/dialogs.
8. **Brand theme default; dynamic color opt-in.** Fixed brand (`#FF4D00` etc.) by default; "Use system colors" toggle in Settings flips to `dynamicDarkColorScheme(...)` on Android 12+. Element colors never change. (DECISIONS.md #042.)
9. **Honor accessibility flags.** Compose auto-honors Reduce Motion / Increase Contrast / Font Scale up to 200% via `LocalAccessibilityManager`. Don't override; verify content survives.
10. **Motion physics ≠ scroll decoration.** Spring physics, shape morphs, `WavyProgressIndicator` are for navigation transitions and progress — not animating every list row in.
11. **Wavy progress indicators for loading.** `LinearWavyProgressIndicator` for long fetches; `CircularWavyProgressIndicator` for <5s loads; `LoadingIndicator` for indeterminate "thinking" states.
12. **Never animate elevation during scroll.** Tonal transitions on discrete state changes only (sheet open/close, bar scrolled vs at-rest).

---

## 7. Search-first IA (Android)

1. **Find** = `ExpandedFullScreenSearchBar` on compact, `ExpandedDockedSearchBar` on medium+. Predictive-back collapses. Use `SearchBarDefaults.InputField(...)`.
2. **Every other tab** has a docked `SearchBar` over its own domain (Decks = browser+saved · Learn = articles+glossary · Collection = owned · Purchase = stores+breaks).
3. **`SegmentedButton`** for orthogonal scopes (Cards / Heroes / Decks within Find); appears only when search is active.
4. **Filter token chips:** `InputChip` (committed) inside the query · `SuggestionChip` (proposed) below the input · `FilterChip` (persistent row) below the bar.
5. **Live suggestions** render via `ListItem`s in a `LazyColumn` inside the `SearchBar` content slot.
6. **Empty state inside search** = `BOBAEmptyState` w/ refinement copy + clear-filters `TextButton`.
7. **Wire every action to an `AppAction`** (Android equivalent of `AppIntent`) so Assistant / App Actions / Quick Settings tiles inherit free (§8 forward-compat).

---

## 6.5 Cross-cutting capabilities

Verbs that operate across multiple tabs share **one** implementation, **one** active-state UI, route by invocation context.

**Scanning.** **CameraX 1.5+** + **ML Kit Text Recognition v2 bundled** (DECISIONS.md #043). One `ScanCoordinator`, one `ScanScreen` (live single), one `GridScanScreen` (multi-card), one queue-review surface. Invoking tab sets destination — identical matrix to iOS §6.5:

| Invoking tab | Destination | Default action |
|---|---|---|
| **Find** | identify only | hold in queue · tap to detail |
| **Decks** | current deck | add immediately · review dupes + legality |
| **Collection** | chosen designation | add · review allows designation change |

Persistent state during a session: `BottomAppBar` slot on compact ("*Scanning · 7 cards · tap to review*"); `HorizontalFloatingToolbar` on medium+. Anti-pattern: per-tab scan implementations — use `ScanCoordinator.start(destination = ...)`.

**Share.** Single `Intent.ACTION_SEND` chooser. `ShareCompat.IntentBuilder` with App Link (`bobaplaybook.com/{type}/{id}`, `autoVerify=true`), rendered image via `EXTRA_STREAM` + `FileProvider`, plain text, `setClipData(...)` for preview. On API 34+, custom actions via `EXTRA_CHOOSER_CUSTOM_ACTIONS`. Single helper: `BobaShare.share(content = ...)`.

**Profile / sign-in / auth.** Profile is Find-only (`TopAppBar` leading `IconButton`, per `feedback_profile_only_on_find`). Other tabs use inline `BOBASignInPrompt` at point of action — never a full-screen wall. Profile = partially-expanded `ModalBottomSheet`. Auth via `androidx.credentials` Credential Manager: Sign in with Google primary (passkeys for free via the bottom-sheet UI), email fallback, Discord via Auth Tab / Custom Tabs. Auth-required only for writes (Save deck, designate, edit Profile); reads work signed-out.

**Adding a cross-cutting capability:** (1) verb in ≥2 tabs, (2) active state benefits from cross-tab persistence, (3) single coordinator + UI.

---

## 6.6 Per-size-class adaptations (binding)

Android ships across phone / tablet / foldable / Chromebook / desktop window. Every new screen declares its medium- and expanded-width adaptation; PRs without one are rejected.

**Use `currentWindowAdaptiveInfo().windowSizeClass`** — never raw `Configuration.screenWidthDp`. Bands: COMPACT <600dp · MEDIUM 600–839dp · EXPANDED 840–1199dp · LARGE ≥1200dp.

| Compact | Medium / expanded |
|---|---|
| `NavigationBar` (NavigationSuiteScaffold) | `NavigationRail`; drawer-rail hybrid only at ≥6 destinations |
| `composable(...)` push | `NavigableListDetailPaneScaffold` or `SupportingPaneScaffold` |
| `ExpandedFullScreenSearchBar` | `ExpandedDockedSearchBar` |
| `ModalBottomSheet` (content) | Modal side sheet (~400dp from end) |
| `ModalBottomSheet` (action) | Centered narrower sheet (~480dp) or `DropdownMenu` |
| `LazyVerticalGrid(Adaptive(150dp))` | Same — flows into more columns automatically |
| `BottomAppBar` action slot | `HorizontalFloatingToolbar` near FAB |
| Container transform `sharedBounds` | System fade-through within pane (no shared bounds) |

**Decks tablet is canonical multi-pane:** `NavigableListDetailPaneScaffold` with three panes (saved decks · editor · browser). Compact = browser+summary; medium = browser+editor; expanded = all three.

**One hierarchy.** `NavigationSuiteScaffold` + `NavigableListDetailPaneScaffold` + `LazyVerticalGrid(Adaptive)` + `BoxWithConstraints` cover ~95% of size-class needs. Don't fork per-platform.

**Chromebook / desktop.** Android 16 apps must work at arbitrary window sizes. Use `windowHeightSizeClass` where height matters (Practice stat panel, Find filter sheet clamp).

### 6.6.1 Overlays read safeContent insets

Walkthrough / hint overlays MUST use `Modifier.safeContentPadding()` from a `LocalView`-rooted `GeometryReader`. Never hardcode bar clearance — foldable landscape and windowed mode have different inset math.

### 6.6.2 Container transform is compact-only

`SharedTransitionLayout` + `sharedBounds` only when `windowWidthSizeClass == COMPACT`. On medium / expanded the destination is in a side pane (list-detail); system fade-through within the pane is the right effect. A corner cell zooming to a 1024dp destination reads as broken — same logic as iOS §6.6.2.

---

## 6.7 Universal states — empty / loading / error / offline

Every list / grid / search / sheet defines behavior for all four.

- **Loading.** `LinearWavyProgressIndicator` for top-of-screen syncs; `LoadingIndicator` (morphing shape) for <5s actions; **3–5 placeholder rows** w/ `Modifier.placeholder(...)` shimmer for initial lists. Never a full-screen `CircularProgressIndicator`. Loading happens in place.
- **Empty.** `BOBAEmptyState`: icon + brand-voice headline (`titleLarge`) + productive-next-action button. Bad: "No items." Good: *"No decks yet — start with a template."*
- **Error.** Transient (save failed) → `Snackbar` w/ Retry; persistent (offline, auth expired, region-blocked) → `BOBABanner` (`errorContainer` Surface above content). iOS `BOBAErrorBanner` maps to Banner on Android (Material convention: Snackbar=transient, Banner=persistent).
- **Offline.** Degraded, not blocked. Catalog cached → reads work; cloud writes disabled inline. `BOBAOfflinePill` (`AssistChip` w/ `Icons.Default.CloudOff`) in `TopAppBar` actions. Detect via `ConnectivityManager.NetworkCallback` → `StateFlow` at theme root.

Anti-pattern: per-tab empty/error styling. Use canonical primitives from §11.

---

## 6.8 First-run hints

iOS `HintsManager` + `HintBanner` (DECISIONS.md #031) has no direct M3 equivalent. Android canon = `TooltipBox` + DataStore-persisted dismissals.

`BOBAHintBanner` = dismissible `Card` (`surfaceContainerLow`, BOBA cyan accent stripe, X-dismiss). Use for non-obvious behavior the design can't cleanly carry (bonus play ceiling, designation behavior). Don't use to compensate for confusing UI — fix the UI. Profile has global silence toggle + reset. One hint per surface at a time.

---

## 6.9 App-bar standardization

**Surface tokens by bar:** `TopAppBar` = `surfaceContainer` (at-rest) / `surfaceContainerHigh` (scrolled); `BottomAppBar` / `NavigationBar` = `surfaceContainer`; `NavigationRail` = `surface`; `ModalBottomSheet` = `surfaceContainerLow`; `HorizontalFloatingToolbar` = `surfaceContainerHigh`.

**TopAppBar variant by destination:**
- **Root** = `CenterAlignedTopAppBar` w/ `BOBAWordmark` + `pinnedScrollBehavior`.
- **Push (list / detail)** = small `TopAppBar` w/ `Icons.AutoMirrored.Filled.ArrowBack` + `enterAlwaysScrollBehavior`.
- **Hero-content** (Card detail) = `LargeTopAppBar` + `exitUntilCollapsedScrollBehavior`.
- **Full-screen modal** = `CenterAlignedTopAppBar` w/ X close leading + action trailing.

**Slots:** leading = Profile (Find root only) / back / close (use AutoMirrored arrow). Trailing = primary action + overflow `DropdownMenu`. Center = wordmark on root, contextual title on push — never both.

**BottomAppBar vs NavigationBar:** NavigationBar = top-level tab switcher; BottomAppBar = per-screen contextual actions (rare; Decks editor only). Never both visible.

**Don't fight predictive-back.** M3 components (SearchBar, ModalBottomSheet) auto-animate. Use `BackHandler` only for unsaved-changes confirmation.

---

## 6.10 Walkthroughs — Android position

**Android does NOT ship multi-step anchored walkthroughs.** Use `TooltipBox` for single-step hints and `BOBAHintBanner` for inline teaching. (DECISIONS.md #044.)

iOS walkthroughs exist because tab gestures / fullScreenCover / NavigationStack have novel idioms. Android conventions (NavigationBar, push/back, FAB, ModalBottomSheet) are universally legible — the marginal value of porting iOS's ~600-line walkthrough engine doesn't justify it. M3 ships `TooltipBox` natively + we ship `BOBAHintBanner` (§6.8). Onboarding splash decks rejected (same as iOS §6.10).

Revisit only if a future feature genuinely needs anchored multi-step teaching. Map of iOS walkthroughs → Android replacements:

| iOS walkthrough | Android replacement |
|---|---|
| Find / Learn / Decks / Collection / Purchase first visit | `BOBAEmptyState` w/ productive-next-action |
| Card detail first | `BOBAHintBanner`: *"Long-press to add to a deck"* |
| Pricing first | `TooltipBox` on the "Market est." chip |
| Wall first | `BOBAHintBanner`: *"Drag the title to reposition"* |
| Scan first | `BOBAHintBanner`: *"Aim at one card. Hold steady for 2s."* |

---

## 7. Forward-compatibility (Android 17 ready)

Android 17 ships ~Q2 2026 (a few weeks out as of this writing). Leaked design direction: **expanded blur / translucent effects across notification shade + recents**, Material 3 Expressive refinements, more `DropdownMenu` and `Popup` polish. **No navigation paradigm shift expected.**

Rules to inherit Android 17 gains automatically:

1. **Every primary action is an `AppAction`** — Google Assistant, App Actions, Quick Settings tiles, Spotlight Search all consume them.
2. **Content has stable IDs.** Cards have `bobaId`, decks have UUIDs. Learn articles need slug IDs (`setup.match-flow`) for Assistant summaries / deep links.
3. **Deep links autoVerify=true** on `bobaplaybook.com/{type}/{id}` — App Links inherit Android 17 system-pickup improvements free.
4. **Don't hard-code surface alpha or elevation values** — let M3 tokens (`MaterialTheme.colorScheme.*`) resolve so Android 17's translucency expansion is automatic.
5. **Adopt M3 Expressive APIs as they graduate from `@ExperimentalMaterial3ExpressiveApi`** (currently FAB Menu, Floating Toolbar, Wavy Indicators).
6. **Don't predict specifics.** Build clean to Android 16; inherit refinements when they ship.

---

## 8. Per-tab IA recipes

### 8.1 Find — explore
- Root: `Scaffold` + `CenterAlignedTopAppBar` (BOBAWordmark + Profile leading + Scan trailing) + `NavigationBar` (5 destinations).
- Top of content: docked `SearchBar` → `ExpandedFullScreenSearchBar` on compact / `ExpandedDockedSearchBar` on medium+.
- No-search: featured shelves via `HorizontalMultiBrowseCarousel` (Heroes by Weapon · Athletes · Recently Added · Coaching Staff · Saved Searches).
- Search-active: `LazyVerticalGrid(GridCells.Adaptive(150.dp))` of `BOBACardCell`. Committed tokens shown as pinned `FilterChip` row below the bar.
- Tap card: container transform (`sharedBounds("card-${bobaId}")`) → push to detail.
- **Anti-patterns:** non-token filter pills; multiple "browse by" pickers (use `SegmentedButton` scopes inside search).

### 8.2 Learn — understand
- Root: `LargeTopAppBar` ("Learn", `exitUntilCollapsed`) + 5 category `ListItem` rows (Rules / Strategy / Collect / Glossary / Tournament).
- Category push → `LazyColumn` of articles.
- Article: `MediumTopAppBar` + `LazyColumn` of `Text(bodyLarge)`. Skill scope (Rookie / Sub / Playmaker) + Read/Watch are inline `SingleChoiceSegmentedButtonRow` — NOT a third nav level.
- Search: `SearchBar` over corpus; `BOBAEmptyState` for zero-results.
- Glossary: `TooltipBox` on highlighted terms.
- Stable slug per article+section for App Actions / deep links (§7).

### 8.3 Decks — build

**Compact:**
- Browser canvas: `LazyVerticalGrid` of `BOBACardCell`.
- Bottom: persistent `DeckSummaryBar` (`Surface` as Scaffold `bottomBar`) — draft name + section counts + format. **Non-draggable.** Empty: *"Build a deck · Tap to open the editor."*
- Tap summary → full-screen `ModalBottomSheet(skipPartiallyExpanded = true)` editor with `sharedBounds("deck-draft")` hero zoom. Same lesson as iOS §8.3: drag was the problem; tap-into-editor is the answer.
- Editor: inner `Scaffold` + small `TopAppBar` (Close + Save + overflow Menu: Manage Decks, Rules, Legality, Clear) + format chip strip + grouped `LazyColumn`.
- Secondary surfaces push via inner `NavHost` — never stacked sheets.
- Browser filter: docked `SearchBar` + `FilterChip` row (weapon / cost / hero).
- Long-press card → adds to draft. Scan in browser overflow → `ScanCoordinator.start(.currentDeck)`.

**Medium+ / tablet:** `NavigableListDetailPaneScaffold` 3 panes (saved decks · editor · browser). Compact=browser+summary; medium=browser+editor; expanded=all three. Pane-switch replaces hero zoom.

**Anti-patterns:** custom drag-from-bottom drawer; stacked sheets on the editor; per-tab draft status banner.

### 8.4 Collection — own
- Root: `LargeTopAppBar` + docked `SearchBar` + `SingleChoiceSegmentedButtonRow` for designation (Personal / Sale / Trade / Wanted / Grails).
- Trailing overflow `DropdownMenu`: display mode (Grid / List / Wall) + grid density (1/2/3 cols, persisted via `DataStore` `bp_collectionGridColumns_v1`) + lenses (Rainbow / Shows — push with own chrome, streamer-only for Shows).
- Designation badge as bottom-trailing overlay on each cell so multi-designation cards scan across scopes.
- Tap card → container transform → `CollectionCardDetailScreen`.
- Scan → "Add to which designation?" `ModalBottomSheet` (defaults Personal, remembers last) → routes via §6.5.
- Share → `BobaShare.share(...)` with App Link + Wall image of current scope.
- Profile = Find-only; auth surfaces are inline `BOBASignInPrompt`.
- Value summary = `Text(titleMedium)` single line. Tap → value-history chart push.
- Wall is a display mode for every collector (DECISIONS.md #036); My Shows stays streamer-gated.

### 8.5 Purchase — acquire
- `TopAppBar` + `SingleChoiceSegmentedButtonRow` ("Upcoming Breaks" | "Find a Store").
- Breaks: `LazyColumn` of M3 `Card` tiles (host + time + viewer count). Tap → `CustomTabsIntent` to Whatnot.
- Stores: `GoogleMap` composable (`maps-compose`) + partially-expanded `ModalBottomSheet` store list.
- Filters: TopAppBar `DropdownMenu` (radius, indie-only).
- Medium+: SegmentedButton splits into `NavigableListDetailPaneScaffold`.

### 8.6 Card detail — the universal card view

Pushed from Find / Decks / Collection. Three composables (`CardDetailScreen`, `BrowserCardDetailScreen`, `CollectionCardDetailScreen`) **share `artPanel` + `TopAppBar` verbatim** — drift is the bug (mirrors iOS §8.6).

- **Pattern:** container transform via `SharedTransitionLayout` + `sharedBounds(key = card.bobaId)`. Compact only (§6.6.2); medium+ uses pane switch.
- **Body order:** stats grid (canonical 6-cell per DECISIONS.md #029) → Cost+DBS (Plays only) → pricing panels (§8.7) → per-context body.
- **Toolbar by context:** Find = Add menu + Mod-edit + Share. Decks tap = "Add to Deck" `FilledButton` in body. Collection tap = "Edit Designation" + Add menu in body.
- **Canonical verbs:** Add to Collection, Add to Deck, Share, Edit Designation.
- **Anti-patterns:** per-screen artPanel/toolbar variants; sheets for drill-in (push Manage/Rules/Legality instead); prev/next chevrons (predictive back handles "back to grid").

Hero-zoom rules: `SharedTransitionLayout` wraps the nav graph; source + destination share key `card.bobaId` + the same `animatedVisibilityScope` from `AnimatedContent`. Push via `navController.navigate(CardDetailRoute(bobaId))`. Compact-only branch.

### 8.7 Pricing panels — provenance-honest (Recent Sales · Listed Range)

Lives inside `CardDetailScreen` between stats and per-context body. Live-fetched (DECISIONS.md #013). COMC asking stays OUT of any sold-comp number (#034). Mirrors iOS DESIGN.md §8.7.

**Provenance is the contract.** Every number states its data type; never present a derived guess as a "Market Est." when no real sold data backs it (PRICING_PLAYBOOK.md + DECISIONS.md #058). Most-specific honestly-labeled signal, in order:

- **Recent Sales** (transacted): real sold comps, each row a source chip (eBay-inferred / Whatnot / "BoBA Community · @user"). Shown only when real sold data exists.
- **Listed Range** (asking): when there is NO real sold data, active eBay listings are the honest primary signal — header "LISTED RANGE", range + count, line "Active eBay listings · no recent sales data yet", chip "eBay listed". Replaces the old fabricated-Market-Est. fallback.
- **Buy Now**: when Recent Sales exists, active eBay listings + COMC asking ("COMC asking · Ungraded NM" `AssistChip`, soft-fail on `challenged: true`) as a separate section. No Recent Sales → active data is the Listed Range, not a duplicate Buy Now.
- **Estimate** (Tier 4): `boba-price-estimator` surfaces only clearly labeled ("Estimated · based on N comparable cards"), only when fed real comps; suppressed while starved (current state).
- Per-section: horizontal scroll of `BOBAPriceTile` (M3 `Card` w/ `surfaceContainerLow`, thumb + price + source chip + `CustomTabsIntent` tap-through). Empty = `BOBAEmptyState` w/ refresh. Loading = 3-tile skeleton. A single per-card "View on Radish" external link preserved (`Intent.ACTION_VIEW` with `card.radishUrl ?: homepage`, NOT `CustomTabsIntent`; DECISIONS.md #056).
- Real-sold header (single line, only with Recent Sales): *"~$24 · based on 8 recent sales"*. Asking NEVER folded in.

### 8.8 Wall view + Price Overlay

Both lifted from streamer-only gate per DECISIONS.md #036.

- **Wall:** `composable(...)` from Collection display-mode menu, Decks overflow ("Generate deck wall"), Find multi-select. Full-screen `LazyVerticalGrid` on near-black + `OutlinedTextField` title. `TopAppBar`: Save / Share / Copy / aspect picker / Price Overlay `Switch`.
- **Price Overlay:** lower-third inset `Surface(surfaceContainerHigh)` with source `AssistChip` + price. Per-designation defaults match iOS §8.8.

---

## 9. The Android redesign roadmap

Full M0–M8 milestone list lives in [SCRATCHPAD.md](./SCRATCHPAD.md) (Android milestone section). Headline shape: compact + medium + expanded across phone / tablet / Chromebook, all 5 tabs, container transforms, M3 Expressive surfaces, Practice admin-gated (M5.5 per DECISIONS.md #048). Foldable adaptation NOT a v1 target (DECISIONS.md #047).

---

## 10. The daily review test

Before any feature ships, four checks:

1. **Gruber (§5.6):** could a designer recreate this from a one-paragraph description?
2. **Verb (§2.1):** what verb does it own? Colliding?
3. **Depth (§2.2):** >2 levels from tab root → SegmentedButton / FilterChip / Sheet / different tab.
4. **Material-native (§2.0):** name the M3 component for every UI element. Unmapped = candidate for replacement.

If silent or contradictory, doc is wrong — propose an edit before proceeding.

---

## 11. Visual primitives — components + colors

Adding a new screen = composing existing primitives. New primitive = first edit this section.

### 11.1 Component library

| Composable | Purpose |
|---|---|
| `BOBACardCell` | Card thumbnail — 5:7 aspect, `RoundedCornerShape(12.dp)`, uniform padding, badge slot |
| `BOBACardGridItem` | `BOBACardCell` + caption (hero name `titleMedium` + weapon `AssistChip` + power `bodySmall` `tnum`); density-adaptive |
| `BOBADeckSummaryBar` | Scaffold `bottomBar` Surface — draft name + section breakdown + format; tap → editor via `sharedBounds` |
| `BOBASectionRow` / `BOBASectionHeader` | `ListItem` w/ leading icon + chevron / uppercase Bebas Neue `headlineSmall` |
| `BOBASearchBarHost` | `SearchBar` / `ExpandedFullScreenSearchBar` w/ size-class branching + BOBA token state |
| `BOBAModalSheet` | `ModalBottomSheet` w/ canonical drag handle, side-sheet branch on medium+ |
| `BOBAEmptyState` | Icon + headline + body + productive-action button |
| `BOBABanner` | Top-anchored `Surface(errorContainer or tertiaryContainer)` w/ icon + message + action |
| `BOBAHintBanner` | Cyan-accent dismissible first-run hint per §6.8; DataStore-backed |
| `BOBASignInPrompt` | Inline "Sign in to do this" row → Credential Manager |
| `BOBAWordmark` | Brand wordmark in `CenterAlignedTopAppBar` title slot |
| `BOBAFilledButton` / `BOBASecondaryButton` | `FilledButton` brand-orange / `OutlinedButton` |
| `BOBAOfflinePill` | `AssistChip` w/ `Icons.Default.CloudOff` in TopAppBar actions when offline |
| `BOBAStatsGrid` | Canonical 6-cell card-stats layout (DECISIONS.md #029); 2-col × 3-row |
| `BOBAPriceTile` | M3 `Card` for Buy Now / Sold tile w/ thumb + price + source chip |
| `BOBAExpandableSection` | Title row + `AnimatedVisibility` expand/collapse (no iOS DisclosureGroup equivalent) |

Custom composable overlapping a primitive → use the primitive. Doesn't fit → edit it (and document here). Never one-off.

### 11.2 Color usage rules

Two distinct systems — don't mix. (Translates iOS §11.2 into M3 tokens.)

**Brand (UI chrome only)** — `colorScheme` overrides:
- `--boba-orange #FF4D00` → `colorScheme.primary` (FIRE; orange overlap is intentional)
- `--boba-cyan #00F5FF` → `colorScheme.secondary`
- `--boba-violet #8B00FF` → `colorScheme.tertiary` (HEX)
- `--boba-near-black #080810` → `background` / `surface`
- `--boba-surface #0D0D1A` → `surfaceContainerLow`

**Element (content semantic only)** — separate `BobaElements` object, NOT in `colorScheme`:
FIRE `#FF4D00` · ICE `#00BFFF` · STEEL `#8A9BB0` · BRAWL `#C0392B` · GLOW `#FFD700` · HEX `#8B00FF` · GUM `#FF69B4` · SUPER `#FF00FF` · ALT `#B084CC` · CYBER `#39FF14` · NONE `#666680`.

The split: element on weapon chips / filter chips / accent dividers / charts. Brand on chrome (FilledButton, NavigationBar indicator, FAB). Never element-as-chrome ("FIRE-themed button"); never brand-as-meaning. Element UPPERCASE in JSON, mixed-case in UI. Dynamic color (`dynamicDarkColorScheme`) overrides `primary` only when user opts in (Android 12+); element colors never change.

---

## 12. Out of scope (intentionally)

| Surface | Why / when |
|---|---|
| **Multi-step anchored walkthroughs** | §6.10 — TooltipBox + BOBAHintBanner cover it; revisit if a feature genuinely needs anchored teaching |
| **Widgets / Quick Settings tiles** | No surface yet; Glance API when scoped |
| **Wear OS / Android TV / ChromeOS exclusive** | Own disciplines; defer |
| **Push notifications** | FCM dispatcher deferred per DECISIONS.md #039 (TRADE-DESIGN.md Phase 5+) |
| **Whatnot show management** | Streamer-gated; only general "Shows" lens in v1 |
| **Mod / admin / pipeline UIs** | Internal tools; defer to v2 if at all |
| **App-launch slide-deck onboarding** | Explicitly rejected — universal Android conventions cover this. **Never** |
| **Sign in with Apple on Android** | iOS-only brand. **Never** |
| **Twitter / X integration (any form)** | DECISIONS.md #053. **Never** |
| **Hamburger drawer on compact** | M3 Expressive de-emphasizes; 5 destinations fit NavigationBar. **Never** |
| **Edge-to-edge opt-out** | Disallowed by Android 16. **Never** |
| **XML / AppCompat / legacy ActionBar** | Compose-only. **Never** |
| **Hero Shot 3D / Personal Showcase / House of BoBA** | RealityKit-specific; Filament port + Cast SDK are separate research efforts (DECISIONS.md #051). Revisit if/when prioritized |

---

## 13. Parity-checking workflow when iOS ships changes

When an iOS change lands that's not pure implementation detail: (1) author updates [`PARITY.md`](./PARITY.md) row; (2) new pattern adds a TODO here OR an entry to §12 if Android skips it; (3) ~monthly audit compares iOS / web / Android binding-doc deltas. Intentionally lightweight — heavyweight process gets skipped.

---

## 14. iOS → Android cheat sheet

| iOS | Android |
|---|---|
| `Tab(role: .search)` | `NavigationSuiteScaffold` + `ExpandedFullScreenSearchBar` |
| `NavigationStack` push | `NavController.navigate(route)` |
| `NavigationSplitView` (iPad) | `NavigableListDetailPaneScaffold` (medium+) |
| `.searchable` / `searchScopes` | `SearchBar` / `SingleChoiceSegmentedButtonRow` |
| `BOBAFilterToken` | `InputChip` (committed) / `SuggestionChip` (proposed) / `FilterChip` (persistent) |
| `.sheet` / `.fullScreenCover` | `ModalBottomSheet` / `ModalBottomSheet(skipPartiallyExpanded = true)` |
| `.alert` / `.confirmationDialog` / `.popover` / `Menu` | `AlertDialog` / `DropdownMenu` |
| `.tabViewBottomAccessory` | `BottomAppBar` slot / `HorizontalFloatingToolbar` |
| `.matchedTransitionSource` + `.zoom` | `SharedTransitionLayout` + `Modifier.sharedBounds(key)` |
| `.glassEffect()` | M3 tonal elevation — **chrome only** |
| `@AppStorage` / Keychain | `DataStore<Preferences>` / Tink-encrypted DataStore + Keystore |
| `NSCache` + `URLCache` | Coil 3 `MemoryCache` + `DiskCache` (60 / 500 MB) |
| `URLSession` + `Codable` | Ktor Client + `kotlinx.serialization` |
| `AppIntent` | App Actions + `ShortcutManagerCompat` |
| Universal Link `.onOpenURL` | App Link `autoVerify=true` + `NavController.deepLinks` + `assetlinks.json` |
| `HintsManager` + `HintBanner` | `BOBAHintBanner` + `DataStore<Preferences>` |
| Walkthrough engine | NOT shipped — `TooltipBox` + `BOBAHintBanner` (§6.10) |
| Sign in with Apple / Face ID | Sign in with Google (Credential Manager) / `BiometricPrompt` |
| `ShareLink` | `Intent.ACTION_SEND` + chooser (+ custom actions on API 34+) |
| AVFoundation + Vision / `AVPlayer` | CameraX 1.5+ + ML Kit v2 bundled / Media3 ExoPlayer |
| App Attest / APNs | Play Integrity / FCM |

---

## 15. References

- Material 3: [m3.material.io](https://m3.material.io/) · [M3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3) · [release notes](https://developer.android.com/jetpack/androidx/releases/compose-material3)
- Compose components index: [developer.android.com/develop/ui/compose/components](https://developer.android.com/develop/ui/compose/components)
- Adaptive: [Adaptive nav](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation) · [List-detail](https://developer.android.com/develop/ui/compose/layouts/adaptive/list-detail) · [Window size classes](https://developer.android.com/develop/ui/compose/layouts/adaptive/use-window-size-classes)
- Motion: [Shared elements](https://developer.android.com/develop/ui/compose/animation/shared-elements)
- System: [Predictive back](https://developer.android.com/develop/ui/compose/system/predictive-back) · [Edge-to-edge](https://developer.android.com/codelabs/edge-to-edge) · [Android 16 changes](https://developer.android.com/about/versions/16/behavior-changes-16)
- Identity / share / scan: [Credential Manager](https://developer.android.com/identity/sign-in/credential-manager) · [ACTION_SEND](https://developer.android.com/training/sharing/send) · [ML Kit Text Recognition v2](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)
- Theming / a11y: [Typography](https://m3.material.io/styles/typography/applying-type) · [Roboto Flex](https://fonts.google.com/specimen/Roboto+Flex) · [Dynamic colors](https://developer.android.com/develop/ui/views/theming/dynamic-colors) · [WCAG 2.2 AA](https://www.w3.org/WAI/WCAG22/quickref/?levels=a%2Caa)
- Deep links: [Create](https://developer.android.com/training/app-links/create-deeplinks) · [Verify App Links](https://developer.android.com/training/app-links/verify-android-applinks)

Engineering: [ANDROID-DEV.md](./ANDROID-DEV.md).
