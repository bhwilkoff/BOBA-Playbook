# BOBA Playbook — Android Design Theory

> **Binding.** Every new screen, sheet, dialog, filter in the Android app must trace to a rule here. When something feels overwhelming or inconsistent, fix the document, then fix the feature.
>
> Companion to [`DESIGN.md`](./DESIGN.md) (iOS), [`WEB-DESIGN.md`](./WEB-DESIGN.md), [`TRADE-DESIGN.md`](./TRADE-DESIGN.md), [`CLAUDE.md`](./CLAUDE.md), [`DECISIONS.md`](./DECISIONS.md). DESIGN.md governs cross-platform principles; this doc owns Android-specific implementation rules.
>
> Ratified 2026-05-19 from four parallel research agents (Android stack, Material 3 → BOBA mapping, integration playbook, Claude skills landscape). See [`ANDROID-DEV.md`](./ANDROID-DEV.md) for the engineering reference that pairs with this doc.

---

## 0. How to use this document

**Ben's job:** when an Android UI choice contradicts a rule, point at the rule. Don't accept "I built a custom drawer because Material's didn't fit" — point at §1.0 native-first and the M3 component table in §11.

**Claude's job:** before proposing any new screen / sheet / dialog / picker / nav level / FAB, quote the rule that justifies it. No fitting rule = needs a new rule (and discussion) before it ships. The doc is the source of truth; fix the doc first, then fix the feature.

**Living document.** §§5–7 follow Material updates (refresh when M3 Expressive APIs graduate from `@ExperimentalMaterial3ExpressiveApi`, and when Android 17 (Q2 2026) lands). §§1–4 are principles and shouldn't change.

**Cross-platform parity is governed by DECISIONS.md #005 and DECISIONS.md #041.** Where iOS, web, and Android have a *user-facing* feature, the verb is identical (Find, Learn, Decks, Collection, Purchase). Where the platform diverges, the platform's native idiom wins over cross-platform consistency. **Android is its own discipline** — don't port iOS shapes; translate iOS *intent* into Material 3 components.

---

## 1. Android-specific constraints

Non-negotiable inputs:

- **Kotlin + Jetpack Compose only** (DECISIONS.md #041). No XML layouts, no AppCompat fragments, no legacy ActionBar. `ComponentActivity`, not `AppCompatActivity`.
- **`minSdk = 29` (Android 10)** — covers >95% of active devices; trims the long tail of pre-scoped-storage workarounds.
- **`targetSdk = 36` (Android 16)** at launch in 2026, `compileSdk = 36` or `37` once stable.
- **Material 3 / Material 3 Expressive** — the current Google design language (May 2025 launch, refined through 2026). Stable Compose Material 3 1.4.x, with M3 Expressive APIs from the 1.5.x alpha train as they graduate.
- **Edge-to-edge rendering** — mandatory for `targetSdk >= 35`. Status + navigation bars are translucent overlays; content draws beneath them. `Scaffold` handles its slots automatically; we honor `WindowInsets` everywhere else.
- **Predictive back gesture** — default in Android 15, can't be opted out on `targetSdk >= 36`. Every modal / nav destination animates correctly during the user's back-drag preview.
- **Adaptive layouts** — Android ships across phones, foldables, tablets, Chromebooks, and Android desktop windows. Android 16+ apps cannot lock orientation on >600dp widths. WindowSizeClass adaptation is binding for every screen (§6.6).
- **Brand parity over platform parity** — when Material You's dynamic color clashes with BOBA's brand palette (orange/cyan/violet), brand wins by default; dynamic color is an opt-in user setting.
- **Feature parity** (DECISIONS.md #005) with iOS — Android is a second native client. The verb-set is identical; the implementation is Material-native.

---

## 2. The six binding principles

Each rule names the iOS DESIGN.md §1 equivalent then specifies the Android form.

### 2.0 Material Components first.

**Rule:** every interaction = a Material 3 / Material 3 Expressive component before any custom `@Composable` built from scratch.

- `SearchBar` before a custom `Row { TextField }`
- `ModalBottomSheet` before a custom drag-from-bottom overlay
- `NavigationSuiteScaffold` before a hand-rolled width-class switch
- `SharedTransitionLayout` + `sharedBounds` before a custom hero animation
- `PullToRefreshBox` before custom nested-scroll
- `Modifier.dragAndDropSource` / `dragAndDropTarget` before custom long-press-and-drag plumbing
- `TooltipBox` before custom tooltip overlays
- `DropdownMenu` before custom popover panels

If M3 doesn't provide it, accept the M3 pattern over building custom — maintenance cost compounds every AndroidX release.

**Why:** The iOS DESIGN.md §1.0 failure mode (12 iterations on a custom drawer, 10 on hero zoom) translates straight to Compose: people reach for a `Box { ... }` overlay when `ModalBottomSheet` would have done. The fix is the same — **exhaust the catalog before writing one**.

### 2.1 Each tab owns one verb.

Find = explore · Learn = understand · Decks = build · Collection = own · Purchase = acquire (verbatim from DESIGN.md §1.1). Verb collision is a structural bug; resolve before adding. Cross-cutting capabilities (scan/share/sign-in) follow §6.5.

### 2.2 Navigation depth ≤ 2 inside a tab.

Tab → list → detail. Anything deeper = parallel filter axis (`SegmentedButton` / `FilterChip` inside the destination) or belongs in a different tab. On compact widths the back gesture (predictive back, Android 15+) reinforces this — every push should map cleanly to a `popBackStack()`.

### 2.3 Search is the universal navigator.

Find uses the M3 `SearchBar` family — `ExpandedFullScreenSearchBar` on compact, `ExpandedDockedSearchBar` on medium / expanded. Every other tab gets a docked `SearchBar` (or a pinned `OutlinedTextField` with `IME=Search` if `SearchBar` is overkill) over its own domain. Filters become **`FilterChip` rows** + **`InputChip` inside the SearchBar query**, not nav levels.

### 2.4 Density comes from removing chrome.

M3 Expressive's 30-style type scale (15 baseline + 15 emphasized) pairs down to six clean hierarchy levels with zero added pixels. Every divider / elevation / tonal-shadow removed = remaining info reads denser. Same Tufte / Things 3 / Reeder lineage.

### 2.5 Tonal elevation = navigation chrome only.

The card grid never gets `Modifier.shadow` for "polish." `NavigationBar`, `NavigationRail`, `TopAppBar`, `BottomAppBar`, `ModalBottomSheet`, `FloatingActionButton`, `HorizontalFloatingToolbar`, and FAB Menu surfaces are the only places `tonalElevation > 0dp` and `surfaceContainerHigh` apply. **One elevated surface per stacking context.** Tonal elevation conveys *navigation hierarchy*, never decoration.

This is the Android analog of iOS DESIGN.md §1.5 (Liquid Glass = navigation only) and WEB-DESIGN.md §2.6 (`backdrop-filter` = navigation only).

---

## 3. The IA decision tree

Walk in order. Stop at first match.

| Question | Android leaf |
|---|---|
| Top-level mode of the entire app? | **`NavigationSuiteScaffold` item** (3–5 total on compact; 5–7 ok on rail; cap drawer at 7 inc. dividers) |
| Hierarchical drill-down, one path in/back? | **Navigation Compose `composable(...)` push** with type-safe routes — max depth 2 |
| Parallel filter / view over same data? | **`SingleChoiceSegmentedButtonRow` (≤5)** or **`FilterChip` row (≥3, scrollable)** — never a new destination |
| Full-focus action that might be abandoned? | **`ModalBottomSheet` with `skipPartiallyExpanded = true`** (compact) / **modal side sheet** (expanded) |
| Glance-and-return (filters, quick edit)? | **`ModalBottomSheet`** with partial + expanded states + visible drag handle |
| Side panel for inspection (tablet / foldable / Chromebook / desktop window)? | **`NavigableListDetailPaneScaffold`** (or `SupportingPaneScaffold` for context-only) |
| Critical confirmation / blocking decision? | **M3 `AlertDialog` / `BasicAlertDialog`** — never a sheet |
| Destructive / one-shot config? | **`DropdownMenu` from a toolbar `IconButton`** with leading icons |
| Global state across screens (scan, draft, player)? | **Persistent slot in `BottomAppBar`** OR **`HorizontalFloatingToolbar`** anchored to the FAB position |
| Verb working in ≥2 tabs (scan, share, profile)? | **Cross-cutting capability** (§6.5) |
| Inline option (toggle, one-of-many)? | **`Switch`, `RadioButton`, `Slider`** inside a `Column` with `Text` + `Divider`, OR `DropdownMenu` for >3 options |
| Transient confirmation? | **`Snackbar` via `SnackbarHost`** — never a banner |
| Persistent attention-required message? | **Banner pattern** (`Surface` + `Row` w/ icon + actions, top-anchored below the app bar) |
| None of the above | **Fold into an existing screen** |

If you reach the bottom with no match, fold the feature into an existing screen — almost always the right answer.

---

## 4. Anti-patterns we reject

### 4.1 Russian-doll navigation (depth > 2)
Same as iOS. Collapse middle layers into segmented controls / scopes. Predictive back lets the user drag-peek the previous destination — a four-level stack thrashes the preview.

### 4.2 Pill-bar pile-up (multiple scrolling rows of equal-weight chips)
At most ONE persistent `FilterChip` `FlowRow` per screen. Everything else moves into a `ModalBottomSheet` "Filters" surface or into the `SearchBar` as query chips.

### 4.3 Tab-inside-tab
A second `NavigationBar` is never the answer — it confuses `BackHandler` semantics. Make it a `SegmentedButton` scope at the top of a single destination, or split into a separate top-level tab.

### 4.4 Sheet-on-sheet (modal stacked on modal)
Within a `ModalBottomSheet`, push with an internal `NavHost` to preserve the dismissal contract. Never stack `ModalBottomSheet` on `ModalBottomSheet` on `AlertDialog`. Predictive back can only dismiss one modal layer at a time; deeper stacks defeat the gesture.

### 4.5 Tonal-elevation soup
One elevated surface per stacking context. M3 elevation tokens (`surface`, `surfaceContainerLow`, `surfaceContainer`, `surfaceContainerHigh`, `surfaceContainerHighest`) are *hierarchy markers*, not decoration. List rows / card grid cells / detail panels live at `surface` or `surfaceContainerLow` — never higher unless they actually represent a different navigation layer.

### 4.6 Settings dump
Progressive disclosure via `LazyColumn` + `HorizontalDivider` + collapsible sections (single canonical `BOBAExpandableSection` — Compose has no `DisclosureGroup` equivalent so we own it). Default advanced collapsed.

### 4.7 NavigationLink-on-a-picker-row
A row that looks pushable (chevron at trailing edge) but actually opens a `DropdownMenu` or `ModalBottomSheet`. Use `Switch` / `RadioButton` inline for binary/small choices, `DropdownMenu` for moderate sets, or a clearly-different row affordance (inline chip stack) — never a fake "chevron-push" that opens a picker.

### 4.8 Hamburger drawer with <5 destinations on compact
Per Material 3 Expressive guidance, the **navigation drawer is being de-emphasized**; use the expanded `NavigationRail` instead. BOBA has 5 destinations — that's exactly the `NavigationBar` cap, no drawer needed on compact. **The drawer pattern in BOBA Android v1 = never on compact; expanded `NavigationRail` only on `widthSizeClass >= MEDIUM`.**

### 4.9 Equal-weight horizontal scrolling rails
Horizontal scroll hides content below the fold. Use vertical `LazyVerticalGrid(columns = GridCells.Adaptive(minSize))`, `DropdownMenu`, or `NavigableListDetailPaneScaffold` on tablets. Reserve horizontal scroll for genuine content shelves (M3 `HorizontalMultiBrowseCarousel` or `HorizontalUncontainedCarousel` for "Featured cards" / "Recently viewed").

### 4.10 Custom sheet backgrounds
Strip every custom `containerColor` / `tonalElevation` override on `ModalBottomSheet`. Let M3 apply `surfaceContainerLow` (or `Low` per spec). If you've reached for `Modifier.background()` on a sheet, the design is wrong, not the override.

### 4.11 Hand-rolled scroll-edge fade overlays
Use `TopAppBarScrollBehavior` (`enterAlways`, `pinned`, `exitUntilCollapsed`) — M3 native. The bar's container color tonally elevates as content scrolls under it; that IS the scroll-edge effect on Android. Don't paint a gradient on top.

### 4.12 Legacy ActionBar / AppCompat usage
BOBA Android is Compose-only. `Activity` extends `ComponentActivity`, never `AppCompatActivity`. No `setSupportActionBar()`. No `Toolbar` widget. No XML menus. Everything is M3 Compose composables.

### 4.13 Hard-coded fixed-pixel sizing
All sizes in `dp` (layout) and `sp` (typography). No `px` outside ripple radii. No hard `width = 360.dp` that ignores width size class — use `BoxWithConstraints` or `currentWindowAdaptiveInfo()` when shape depends on space.

### 4.14 Opting out of edge-to-edge
Android 16+ enforces edge-to-edge. Don't add `windowOptOutEdgeToEdgeEnforcement` — it's deprecated and ignored on `targetSdk >= 36`. Every screen handles its own `WindowInsets` via `Scaffold(contentWindowInsets = ...)`, `Modifier.safeContentPadding()`, or `Modifier.systemBarsPadding()`. Card art deliberately extends behind the translucent status bar on hero surfaces — the bar handles its own tonal protection via `TopAppBar`'s `scrolledContainerColor`.

### 4.15 Custom focus indicators
Compose's default `FocusInteraction` ripple/outline is correct for both touch and keyboard (D-pad on tablets / Chromebooks / TVs). Don't override `indication = null`. M3 Expressive's `RippleThemeConfiguration` ships an inset focus ring — adopt the default.

### 4.16 FABs for primary navigation
M3 `FloatingActionButton` exists; **BOBA doesn't use it for primary navigation**. Mirroring iOS DESIGN.md §3.8 (no action tabs), the scan affordance lives in the search bar's trailing icon, not in a floating button. A FAB might appear in the Decks editor for "Add card" if it doesn't compete with the bottom NavigationBar.

---

## 5. Density rules

Each is testable in code review.

1. **No tinted-box backgrounds on content rows or grid cells.** Row separation = `HorizontalDivider` or `Spacer(Modifier.height(8.dp))`. Container separation = `surfaceContainer*` token applied to the *parent* (`TopAppBar`, sheet) — never to the row.

2. **Three weights × two sizes = six levels** via the M3 type scale, paired with **Roboto Flex** (variable axis: `wght` 400/500/700, `opsz` auto) plus the brand display faces:

   | Level | M3 token | Font / weight | BOBA use |
   |---|---|---|---|
   | L1 — Page title (root) | `displaySmall` (36 sp) | Bebas Neue / Russo One | Wordmark, hero pages |
   | L2 — Section header | `headlineSmall` (24 sp) | Roboto Flex 700 | "TREATMENTS", "RULES" |
   | L3 — Card title / row primary | `titleMedium` (16 sp) | Roboto Flex 500 | Hero name on card cell |
   | L4 — Body | `bodyMedium` (14 sp) | Roboto Flex 400 | Description text, settings rows |
   | L5 — Caption | `labelMedium` (12 sp) | Roboto Flex 400 | Element pill text, timestamps |
   | L6 — Tabular | `bodySmall` w/ `tnum` features (12 sp) | Roboto Flex 400 | Card # / power / DBS / cost |

   Refuse a seventh hierarchy level — refactor instead. M3 Expressive's "emphasized" variants (e.g. `displaySmallEmphasized`) are reserved for editorial moments (Practice victory screen, Hero Shot title overlay) — never default body.

3. **Small multiples.** Every card cell in every grid uses the same `BOBACardCell` composable: 5:7 aspect, `RoundedCornerShape(12.dp)`, uniform padding, badge slot. Single canonical implementation, density-adaptive via `columnCount`.

4. **Show the data; filter it.** Persistent `SearchBar` is denser than a category picker — zero-overhead access to everything. Filter chips (M3 `FilterChip` in a `FlowRow`) before nav levels.

5. **Progressive disclosure predictable.** `BOBAExpandableSection` for inline; `composable(...)` push for navigation; `ModalBottomSheet` for focused tasks. Never overload — an expandable that sometimes pushes destroys trust.

6. **Gruber test:** *"Could a competent designer recreate this screen from a one-paragraph description?"* If no, decoration. Strip and rebuild.

7. **Optical sizing via Roboto Flex.** Set `FontFamily` once at theme level using `Typography(defaultFontFamily = RobotoFlex)` — every text style inherits optical sizing for free.

---

## 6. Material 3 Expressive usage rules (the Android "chrome material" rules)

Just as iOS DESIGN.md §5 constrains Liquid Glass to navigation chrome, M3 Expressive's elevation / shape / motion system gets the same discipline.

1. **Tonal elevation = navigation chrome only.** `TopAppBar`, `NavigationBar`, `NavigationRail`, `BottomAppBar`, `ModalBottomSheet`, `FloatingActionButton`, `HorizontalFloatingToolbar`, FAB Menu, `AlertDialog`. List rows, cards, content surfaces — never. Card cells use a flat `Surface(color = surface)` with NO `tonalElevation`.

2. **One elevated surface per stacking context.** A `TopAppBar` at `surfaceContainer` + a `BottomAppBar` at `surfaceContainer` + an open `ModalBottomSheet` at `surfaceContainerLow` = three surfaces, three roles, no overlap. Anything more = stack flat onto `surfaceContainer`.

3. **Shape tokens consistent.** M3 Expressive's 10-step corner-radius scale is used purposefully:
   - **Card cells:** `RoundedCornerShape(12.dp)` (= `shapes.medium`)
   - **Surfaces & sheets:** `shapes.large` (16dp) — sheets default to 28dp top corners, leave that alone
   - **Buttons:** M3 Expressive default — `FilledButton` is fully rounded; don't override
   - **FilterChips:** spec default (8dp); don't override

4. **Shape morphing for state, not decoration.** M3 Expressive supports animated shape transitions (e.g. selected `FilterChip` morphs from rectangle → circle on selection). Use it where M3 ships it — never roll your own shape-morph for visual flair.

5. **Tinting = primary action only.** `FilledButton`, `FloatingActionButton` get `colorScheme.primary` / `primaryContainer`. Cancel and Delete buttons get `colorScheme.error` only for true destruction.

6. **Strip custom containerColor on sheets / dialogs.** Let M3 apply the spec.

7. **`TopAppBarScrollBehavior` is the scroll-edge effect.** Use `enterAlwaysScrollBehavior` on Find / Decks pool / Collection (dense scrolls), `exitUntilCollapsedScrollBehavior` for hero-title screens (card detail, Learn article), `pinnedScrollBehavior` for sheets / dialogs / always-anchored bars.

8. **Brand theme by default; dynamic color is opt-in.** BOBA ships a **fixed brand theme** (orange/cyan/violet on near-black) — *not* dynamic color — because the card-art palette is the focal point and a user's wallpaper-derived primary fighting with `#FF4D00` reads muddy. Provide a "Use system colors" toggle in Settings for users who want dynamic; default OFF. (DECISIONS.md #042.)

9. **Test Reduce Motion / Increase Contrast / Font Scale up to 200%.** Compose auto-honors accessibility flags via `LocalAccessibilityManager`. Don't override; verify content survives.

10. **Motion physics ≠ scroll decoration.** M3 Expressive's spring physics (the 35-shape morph library, `WavyProgressIndicator`, `FloatingActionButtonMenu` open animation) is reserved for *navigation transitions* and *progress*. Don't animate every list row in.

11. **Wavy progress indicators for loading states.** `LinearWavyProgressIndicator` for long content fetches (catalog refresh, sync) — `CircularWavyProgressIndicator` for sub-5s loads. `LoadingIndicator` (the morphing shape) for indeterminate "thinking" states (scan recognition in progress, match dispatch).

12. **Never animate elevation during scroll.** Restrict tonal transitions to discrete state changes (sheet open/close, bar scrolled vs at-rest).

13. **`Dynamic*ColorScheme(seedColor = ...)` only when the user opts in.** Default `darkColorScheme(...)` built from the brand seed lives in `BobaTheme.kt`.

---

## 7. Search-first IA (Android)

M3's `SearchBar` family is the heart of every dense view.

1. **Find = `ExpandedFullScreenSearchBar` on compact, `ExpandedDockedSearchBar` on medium/expanded.** The bar morphs from a docked input at rest into a full-screen overlay when focused; predictive-back collapses it. Use `SearchBarDefaults.InputField(...)` for the input slot.

2. **Every other tab has a docked `SearchBar`** scoped to its own domain. Decks = pool + saved decks. Learn = articles + glossary. Collection = owned cards. Purchase = stores + breaks.

3. **`SegmentedButton` for orthogonal scopes** (e.g. Cards vs Heroes vs Decks within Find). Sits below the search bar; appears only when search is active.

4. **`InputChip` for committed filter tokens.** When a user picks "Weapon: Fire" from suggestions, it commits as an `InputChip` inside the search query. `SuggestionChip` for proposed tokens below the input while typing. `FilterChip` for the persistent filter row below the bar (always-visible options).

5. **Live suggestions in the expanded search content area.** "MAVE" → "Maverick"; "RBF-" → "RBF-72 Maverick (Red Battlefoil)". Render with `ListItem`s in a `LazyColumn` inside the `SearchBar`'s content slot.

6. **Empty state inside the search uses M3 empty-state copy + action.** No results → *"No cards match `MAVE Fire`. Try removing the Weapon filter."* with a `TextButton` to clear filters. (Compose has no `ContentUnavailableView` equivalent; we ship `BOBAEmptyState` per §11.)

7. **Wire every action to an `AppAction` (Android equivalent of iOS `AppIntent`)** so Google Assistant, App Actions, Quick Settings tiles, and Spotlight Search inherit the same intents (§8 forward-compat).

---

## 6.5 Cross-cutting capabilities

Verbs that operate across multiple tabs share **one** implementation, **one** active-state UI, route by invocation context.

### Scanning

Camera path is **CameraX 1.5+** for capture, **ML Kit Text Recognition v2 (bundled)** for OCR — bundled model so first-run requires no model download (DECISIONS.md #043). One `ScanCoordinator`, one `ScanScreen` (live single), one `GridScanScreen` (multi-card still), one queue-review surface. Invoking tab sets destination + default capture action — identical matrix to iOS DESIGN.md §6.5:

| Invoking tab | Destination | Default action | Queue review |
|---|---|---|---|
| **Find** | identify only | hold in queue | tap → push to detail |
| **Decks** | current deck | add immediately | post-capture: dupes + legality |
| **Collection** | designation chosen at start | add to that designation | post-capture: change designation |

While a session is open, the persistent state surfaces in the `BottomAppBar` of every tab as a transient action slot: *"Scanning · 7 cards · tap to review."* On widths ≥ medium, this lives in a `HorizontalFloatingToolbar` instead so it doesn't compete with the navigation rail.

**Anti-pattern:** per-tab scan implementations. Use one `ScanCoordinator.start(destination = ...)`; per-tab button is a `TopAppBar` `IconButton`.

### Share

Single M3 `Intent.ACTION_SEND` chooser from card / deck / collection-scope surfaces. Build a `ShareCompat.IntentBuilder` with:
- Deep link (App Link to `bobaplaybook.com/{type}/{id}` with `autoVerify=true`)
- Rendered image (card art / deck thumb / Wall) attached via `EXTRA_STREAM` + `FileProvider`
- Plain text summary
- `setClipData(...)` for preview thumbnail

On Android 14+ (API 34+) we expose **custom share actions** via `EXTRA_CHOOSER_CUSTOM_ACTIONS` ("Copy bobaId", "Save to Wanted"). Build once in `BobaShare.share(content = ...)`.

### Profile / sign-in / auth

**Profile is Find-only** (top-leading `TopAppBar` `IconButton` with `Icons.Default.AccountCircle`, per `feedback_profile_only_on_find`). Other tabs surface auth via inline `BOBASignInPrompt` composable at point of action — never a full-screen wall. Profile sheet uses partially expanded `ModalBottomSheet` by default, drags to fully expanded.

**Auth via `androidx.credentials` Credential Manager** with **Sign in with Google** as primary (the canonical Android brand button; Sign in with Apple is iOS-only branding). Passkey support comes for free via Credential Manager's bottom-sheet UI. Email fallback under "Use email instead" — same `OutlinedTextField` flow as web.

Discord identity (per DECISIONS.md #023) links via Auth Tab (Chrome 132+) or Custom Tabs (`CustomTabsIntent.launchUrl(...)`) — never an in-app native form for Discord credentials.

**Auth-required vs optional:** identical to iOS DESIGN.md §6.5 — every read verb works signed-out; auth required only for writes (Save deck, designate, edit Profile).

### Adding a new cross-cutting capability

Same 3-test as iOS:
1. Verb relevant in ≥2 tabs (else it's tab-specific).
2. Active state benefits from persistence across tabs.
3. Single coordinator + UI implementation.

---

## 6.6 Per-size-class adaptations (binding for tablet / foldable / Chromebook / desktop window)

Android ships across more form factors than iOS. Every new screen declares its medium- and expanded-width adaptation; PRs without one are rejected.

**Use `currentWindowAdaptiveInfo()` and `windowSizeClass.windowWidthSizeClass`** — never raw `Configuration.screenWidthDp`. Material 3 Adaptive maps to:

- **COMPACT** (<600dp) — phones portrait, foldables folded
- **MEDIUM** (600–839dp) — tablets portrait, foldables unfolded portrait, large phones landscape
- **EXPANDED** (840–1199dp) — tablets landscape, foldables unfolded landscape, small Chromebooks
- **LARGE / EXTRA-LARGE** (≥1200dp) — Chromebooks, ChromeOS windowed mode, foldable desktops

| Pattern (compact) | Medium / expanded |
|---|---|
| `NavigationBar` (NavigationSuiteScaffold default) | `NavigationRail` (5 destinations + optional FAB); drawer-rail hybrid on expanded if ≥6 destinations |
| `composable(...)` push | `NavigableListDetailPaneScaffold` (2-pane) or `SupportingPaneScaffold` (main + supporting context) |
| `ExpandedFullScreenSearchBar` | `ExpandedDockedSearchBar` (stays anchored, doesn't take full screen) |
| `ModalBottomSheet` (content, filters, picker) | **Modal side sheet** (slides in from end side, ~400dp wide) |
| `ModalBottomSheet` (action, Profile, share) | M3 `ModalBottomSheet` w/ centered narrower max-width (~480dp), OR `DropdownMenu` if shorter |
| `FilterChip` flow row (1-line wrap) | Same — chips wrap with more space |
| `LazyVerticalGrid(GridCells.Adaptive(minSize=150.dp))` | Same — cells flow into more columns automatically |
| `BottomAppBar` action slot | Floats as `HorizontalFloatingToolbar` near the FAB |
| Container transform with `sharedBounds` | System fade-through (the destination is in another pane, not pushed) |

**Decks on tablet is the canonical multi-pane shape:** `NavigableListDetailPaneScaffold` with three logical panes — *list* (saved decks), *detail* (current deck editor), *extra* (card pool). Compact = pool only with summary bar; medium = pool + editor; expanded = saved-decks + pool + editor.

**Don't fork per-platform.** One Composable hierarchy; `NavigationSuiteScaffold` + `NavigableListDetailPaneScaffold` + `LazyVerticalGrid(Adaptive)` + `BoxWithConstraints` cover ~95% of size-class needs.

**Chromebook / desktop windowing.** Apps targeting Android 16 must work in arbitrary window sizes. Use `currentWindowAdaptiveInfo().windowSizeClass.windowHeightSizeClass` for cases where height matters (Practice executor stat panel; Find filter sheet height clamp).

### 6.6.1 — Walkthrough / hint overlays on tablet / foldable

Overlays MUST read `WindowInsets.safeContent` from a Compose `LocalView.current` + `Modifier.safeContentPadding()`. Never hardcode bar clearance. Foldable unfolded landscape + Stage Manager-like windowed mode each have different inset math.

### 6.6.2 — Container transform is compact-only

`SharedTransitionLayout` + `sharedBounds` (Photos-app-style hero zoom) applies only when `windowWidthSizeClass == COMPACT`. On medium / expanded, the destination is in a *side pane* (list-detail scaffold), not pushed — system fade-through within the pane is the right effect.

A corner cell zooming to a 1024dp destination reads as broken — same logic as iOS DESIGN.md §6.6.2.

---

## 6.7 Universal states — empty / loading / error / offline

Every list, grid, search, sheet defines behavior for four states beyond happy path.

1. **Loading.** `LinearWavyProgressIndicator` for top-of-screen background syncs. `LoadingIndicator` (M3 Expressive morphing shape) for actions <5s ("scanning…", "saving…"). Initial list renders **3–5 placeholder rows** with `Modifier.placeholder(...)` (shimmer) — never a full-screen `CircularProgressIndicator`. Loading happens in place; preserve layout.

2. **Empty.** Canonical `BOBAEmptyState` composable: optional icon, brand-voice headline (`titleLarge`), productive-next-action button. Bad: "No items." Good: *"No decks yet — start with a template."* + template gallery.

3. **Error.** Distinguish **transient** (snackbar) vs **persistent** (banner):
   - **Transient action failure** (save failed, sync hiccup) → `Snackbar` via `SnackbarHost` with `actionLabel = "Retry"`.
   - **Persistent / blocking** (offline, auth expired, region-blocked) → `BOBABanner` composable: full-width `Surface(color = errorContainer)` above the content with icon + message + action button. Dismiss only on user action.

   The iOS-style `BOBAErrorBanner` (DESIGN.md §6.7) maps to **Banner** on Android — not Snackbar — because Material's clear convention is Snackbar = transient, Banner = persistent.

4. **Offline.** Degraded, not blocked. Catalog cached → Find / Learn / Decks-browse / Collection-browse work. Cloud writes disabled inline. Subtle `BOBAOfflinePill` (`AssistChip` with `Icons.Default.CloudOff`) in `TopAppBar` actions slot. Detect via `ConnectivityManager.NetworkCallback` exposed as a `StateFlow` collected at theme root.

**Anti-pattern:** per-tab empty/error styling. Use canonical `BOBAEmptyState`, `BOBABanner`, `BOBAOfflinePill` (§11).

---

## 6.8 First-run hints

The iOS `HintsManager` + `HintBanner` (DECISIONS.md #031) doesn't have a direct M3 equivalent. **Android's "feature discovery" canon is `TooltipBox`** + persistent prefs (DataStore).

**Rule:** ship a `BOBAHintBanner` composable — a dismissible `Card` with `surfaceContainerLow` background, BOBA cyan accent stripe, X-icon dismissal — for the few cases where the UI itself can't carry the teaching (bonus play ceiling, designation behavior, etc.). Persist dismissals to a `DataStore<Preferences>` (NOT SharedPreferences — DataStore is the M3-era canonical store).

**Use:** non-obvious behavior the design can't cleanly convey.
**Don't use:** to compensate for confusing UI — fix the UI.

Settings has a global silence toggle + "Reset hints" `Button`. Distinct from `BOBABanner` (orange, attention) and `BOBAEmptyState` (structural, no dismiss).

**One hint per surface at a time.** Hints teach a tip on a known surface; walkthroughs (§6.10) teach a brand-new surface — but Android skips multi-step walkthroughs per §6.10.

---

## 6.9 App-bar standardization

1. **Surface tokens by bar:**
   - `TopAppBar`: `surfaceContainer` at-rest, scrolled-elevated to `surfaceContainerHigh`
   - `BottomAppBar`: `surfaceContainer`
   - `NavigationBar`: `surfaceContainer`
   - `NavigationRail`: `surface`
   - `ModalBottomSheet`: `surfaceContainerLow`
   - `HorizontalFloatingToolbar`: `surfaceContainerHigh`

2. **TopAppBar variant by destination:**
   - **Root** (each tab top-level) → `CenterAlignedTopAppBar` with `BOBAWordmark` centered; `pinnedScrollBehavior` so it doesn't move.
   - **Push (list / detail)** → `TopAppBar` (small) with contextual title left-aligned + `Icons.AutoMirrored.Filled.ArrowBack` nav icon; `enterAlwaysScrollBehavior` so it collapses with content.
   - **Hero-content destinations** (Card detail) → `LargeTopAppBar` w/ `exitUntilCollapsedScrollBehavior` so the title scrolls down into the bar.
   - **Modals (full-screen)** → `CenterAlignedTopAppBar` w/ X close icon left + action button right.

3. **Slots:**
   - **Leading**: Profile gear (Find root only, per `feedback_profile_only_on_find`) / back chevron / close icon. Use `Icons.AutoMirrored.Filled.ArrowBack` (RTL-correct).
   - **Trailing**: primary action / overflow `DropdownMenu`. If both, primary right-most.
   - **Center**: wordmark on root, contextual title on push. Never both.

4. **`BottomAppBar` vs `NavigationBar`:** NavigationBar = top-level tab switcher (5 destinations). BottomAppBar = per-screen contextual actions (rare in BOBA — Decks editor uses it for "Save" / "Discard" / "Stats" + a FAB). Never both visible at once.

5. **Don't fight predictive-back.** When the user starts the back gesture, M3 components (SearchBar, ModalBottomSheet) auto-animate. Don't intercept with `BackHandler` unless we need to confirm unsaved changes.

---

## 6.10 Feature walkthroughs — Android takes a position

**Position: Android does NOT ship multi-step anchored walkthroughs.** Use `TooltipBox` for single-step contextual hints and `BOBAHintBanner` for inline teaching. (DECISIONS.md #044.)

**Rationale:**
- iOS DESIGN.md §6.10 walkthroughs exist because the **iOS interaction vocabulary** (tab bar gestures, fullScreenCover, NavigationStack) has many novel idioms a user must learn. Android conventions (NavigationBar, push/back, FAB, ModalBottomSheet) are universally legible across every Android app the user already uses.
- The walkthrough engine in `BOBAPlaybook/Components/BOBAWalkthrough.swift` is ~600 lines (anchor preference plumbing, dim/cutout overlay, multi-step pager). Reproducing that surface in Compose for marginal value-add is on the wrong side of the cost/value line.
- M3 ships `TooltipBox` natively for the single-step case ("Tap any card to see details") and we ship `BOBAHintBanner` (§6.8) for the inline teach.
- Onboarding splash decks are explicitly rejected (DESIGN.md §6.10 anti-pattern; same here).

**If a future Android feature genuinely needs anchored multi-step teaching** (Practice executor when it lands, or a complex new flow), revisit this position and propose a new `BOBAWalkthroughHost`. Don't ship by guess.

**Map iOS walkthrough scripts to Android (catalog):**

| iOS walkthrough | Android replacement |
|---|---|
| Find first visit | `BOBAEmptyState` on the no-search-yet shelf surface: *"Search 17k+ cards. Try a hero name or set."* |
| Learn first visit | `BOBAEmptyState` in the root list w/ a "Where to start?" tile |
| Decks first visit | `BOBAEmptyState` in the empty editor: "Start with a template" gallery (DESIGN.md §8.3) |
| Collection first visit | `BOBAEmptyState`: "Scan a card or browse Find to get started" |
| Purchase first visit | `BOBAEmptyState`: "Find live breaks or a local store" |
| Card detail first | `BOBAHintBanner` on first detail open: *"Long-press to add to a deck"* |
| Pricing panels first | `TooltipBox` on the "Market est." chip |
| Wall first | `BOBAHintBanner` above the canvas: *"Drag the title to reposition"* |
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

### 8.1 Find — the explorer

**Verb:** explore.

**Anatomy:**
- **Root** = `Scaffold` with `CenterAlignedTopAppBar` (BOBAWordmark + Profile icon leading + Scan icon trailing) + `NavigationBar` (5 destinations) + `LazyColumn` content.
- **Top of content** = docked `SearchBar`. Tapping expands to `ExpandedFullScreenSearchBar` on compact; `ExpandedDockedSearchBar` on medium+.
- **No-search state** below the bar = featured shelves rendered as `HorizontalMultiBrowseCarousel` rows (Heroes by Weapon · Athletes by Sport · Recently Added · Coaching Staff · Saved Searches).
- **Search-active state** = collapse shelves; show `LazyVerticalGrid(GridCells.Adaptive(minSize = 150.dp))` of `BOBACardCell` results. `FilterChip` row pinned below SearchBar showing committed tokens.
- **Tap card** = container transform (`sharedBounds(key = "card-${bobaId}")`) into `composable(...)` push destination.

**Anti-patterns:** filter pills above the grid that aren't tokens. Multiple "browse by" pickers — use `SegmentedButton` scopes inside search instead.

### 8.2 Learn — the educator

**Verb:** understand.

**Anatomy:**
- **Root** = `Scaffold` + `LargeTopAppBar` ("Learn", `exitUntilCollapsedScrollBehavior`) + 5 category rows (Rules / Strategy / Collect / Glossary / Tournament) using `ListItem` w/ `leadingContent` icon + `trailingContent` chevron.
- **Category** = `composable(...)` push → `LazyColumn` of articles, each `ListItem`.
- **Article view** = `Scaffold` + `MediumTopAppBar` w/ contextual title + `LazyColumn` of `Text(style = bodyLarge)` blocks. Scope picker (Rookie / Sub / Playmaker) = `SingleChoiceSegmentedButtonRow` inline at top of article — NOT a third nav level. Read/Watch is also a SegmentedButton scope when video exists.
- **Search** = `SearchBar` over Learn corpus; `BOBAEmptyState` for zero-results.
- **Glossary lookup** = `TooltipBox` triggered by tapping highlighted terms.

**Stable IDs:** every article+section gets a slug for App Actions / deep links (§7).

### 8.3 Decks — the builder

**Verb:** build.

**Anatomy (compact / phone):**
- **Card pool** = `LazyVerticalGrid` of `BOBACardCell` as canvas.
- **Summary** = persistent `DeckSummaryBar` (`Surface` anchored as Scaffold `bottomBar`). Shows draft name + section breakdown + format badge. Empty: *"Build a deck · Tap to open the editor."* **Non-draggable.**
- **Tap summary** = full-screen `ModalBottomSheet(skipPartiallyExpanded = true)` opening the editor. Hero zoom via `sharedBounds(key = "deck-draft")`. **NOT a draggable bottom sheet at rest** — same lesson as iOS (DESIGN.md §8.3): drag was the problem, tap-into-editor is the answer.
- **Editor body** = `Scaffold` (inside the sheet) + small `TopAppBar` w/ Close + Save action + overflow `DropdownMenu` (Manage Decks, Rules, Legality, Clear). Editor content = format chip strip + grouped `LazyColumn`.
- **Secondary surfaces** (Manage Decks / Rules / Legality) **push** as `composable(...)` destinations within the editor's inner `NavHost` — never stacked as a second `ModalBottomSheet`.
- **Pool filter** = `SearchBar` docked at top of pool with `FilterChip` row (weapon / cost / hero) below.
- **Card tap** = container transform into card detail.
- **Long-press on pool card** = adds to draft (canonical add gesture, mirroring iOS).
- **Scan** = lives in pool `TopAppBar` overflow `DropdownMenu`; routes through `ScanCoordinator.start(destination = .currentDeck)`.

**Anatomy (medium+ / tablet):**
- `NavigableListDetailPaneScaffold` with **three logical panes**: saved decks (list) · current deck (detail) · card pool (extra). Compact = pool only with summary bar; medium = pool + editor; expanded = saved-decks + pool + editor.
- Hero-zoom into editor is replaced by pane-switch (no shared bounds).

**Anti-patterns:** custom drag-from-bottom drawer. Per-tab "draft" status banner. Sheets stacked on the editor. At most one `ModalBottomSheet` open at a time.

### 8.4 Collection — the owner

**Verb:** own.

**Anatomy:**
- **Root** = `Scaffold` + `LargeTopAppBar` ("Collection") + `SearchBar` docked + `SingleChoiceSegmentedButtonRow` for designation (Personal / Sale / Trade / Wanted / Grails — 5 options fits).
- **Display mode** = trailing overflow `DropdownMenu` (Grid / List / Wall).
- **Grid density** = same Menu adds 1/2/3 column option, persisted via `DataStore<Preferences>` (`bp_collectionGridColumns_v1`).
- **Lenses** (Rainbow / Shows) = additional `composable(...)` destinations from overflow Menu — `LargeTopAppBar` + own chrome on push, no designation/search competing.
- **Designation badge** on each cell as bottom-trailing overlay (`Box` w/ `Modifier.align(Alignment.BottomEnd)`) so multi-designation cards scan across scopes.
- **Tap card** = container transform → `CollectionCardDetailScreen` via shared `NavHost`.
- **Scan** = `TopAppBar` `IconButton` → "Add to which designation?" `ModalBottomSheet` (defaults Personal, remembers last) → routes via §6.5.
- **Share** = `BobaShare.share(...)` (§6.5) — Android Intent chooser sheet with App Link + Wall image of current scope.
- **Profile** = Find-only (per `feedback_profile_only_on_find`). Collection's auth surfaces are inline `BOBASignInPrompt`.
- **Value summary** = single-line `Text(style = titleMedium)` header, no decoration. Tap → value-history chart (`composable(...)` push).

**Wall + Streamer reconciliation:** Wall is a display mode for every collector (DECISIONS.md #036). "My Shows" stays streamer-gated as a `composable(...)` destination from overflow Menu (visible only when role contains `streamer`).

### 8.5 Purchase — the acquirer

**Verb:** acquire.

**Anatomy:**
- **Root** = `Scaffold` + `TopAppBar` ("Purchase") + `SingleChoiceSegmentedButtonRow` at top — "Upcoming Breaks" | "Find a Store".
- **Upcoming Breaks** = `LazyColumn` of large card tiles (M3 `Card` composable, `surfaceContainer`); host + time + viewer count. Tap → `CustomTabsIntent` to Whatnot.
- **Find a Store** = `GoogleMap` composable (`maps-compose`) with `Marker`s + a partially expanded `ModalBottomSheet` of the store list. (Apple Maps pattern translated.)
- **Filters** = `DropdownMenu` from TopAppBar action (radius, indie-only toggle).

**On medium+/tablet:** the SegmentedButton splits into a `NavigableListDetailPaneScaffold` — the picker becomes a left rail entry and the content (Breaks / Stores) takes the detail pane.

### 8.6 Card detail surface — the universal card view

Pushed from Find, Decks (pool tap), Collection (cell tap). Three composables (`CardDetailScreen`, `BrowserCardDetailScreen`, `CollectionCardDetailScreen`) share `artPanel` + `TopAppBar` verbatim — only body content differs.

**Pattern:** **Container transform** (M3 Motion) via `SharedTransitionLayout` + `sharedBounds(key = card.bobaId, ...)` between the grid cell (source) and the detail destination. Compact only (§6.6.2); medium+ uses pane switch.

**Canonical artPanel + toolbar** live in `app/src/main/java/com/bobaplaybook/ui/cards/CardDetailScreen.kt`. **All three card-detail screens import the same canonical composable** — drift is the bug. This mirrors iOS DESIGN.md §8.6.

**Anatomy (body below artPanel):** Stats grid (canonical 6-cell per DECISIONS.md #029) → Cost+DBS (Plays only) → Pricing panels (§8.7) → Per-context body.

**TopAppBar action bar by context:**

| Entry | Trailing actions |
|---|---|
| Find | Add (Menu: Collection / Deck / Show) + Mod-edit (mods) + Share |
| Decks tap | "Add to Deck" `FilledButton` in body |
| Collection tap | "Edit Designation" `OutlinedButton` + Add menu in body |

Canonical verbs: `Add to Collection`, `Add to Deck`, `Share`, `Edit Designation`.

**Anti-patterns:** per-screen artPanel variants (one shape). Per-screen toolbar accumulation. `ModalBottomSheet`s for drill-in (Manage/Rules/Legality push instead). Prev/next chevrons in bottom toolbar (Android predictive back handles "back to grid"; in-bar prev/next is iOS-only).

**Hero-zoom (container transform) rules:**

| Where | What |
|---|---|
| Source | `Modifier.sharedBounds(rememberSharedContentState(key = card.bobaId), animatedVisibilityScope = ...)` |
| Destination | Same key, same `animatedVisibilityScope` from the destination's `AnimatedContent` |
| Scope | `SharedTransitionLayout { ... }` wraps the whole nav graph; `CompositionLocal` provides it deep |
| Push | `navController.navigate(CardDetailRoute(bobaId))` |
| ID | `bobaId` (the canonical key, per CLAUDE.md "One ID per Card") |
| Compact-only | wrap source + destination in `if (windowWidthSizeClass == COMPACT)` — otherwise the destination is in a pane |

---

### 8.7 Pricing panels — Buy Now + Sold history

Lives inside `CardDetailScreen` body, between stats grid and per-context section. Live-fetched per DECISIONS.md #013; COMC asking stays OUT of sold-comp waterfall per #034.

**Two sections (`Column` w/ `HorizontalDivider`):**

1. **Buy Now** — eBay active listings + COMC asking with *"COMC asking · Ungraded NM"* `AssistChip` label. Soft-fail COMC silently when worker returns `challenged: true`.
2. **Sold history** — Radish recent + eBay sold. Market est = Radish-first waterfall.

**Per-section:** horizontal scroll of `BOBAPriceTile` (M3 `Card` w/ `surfaceContainerLow`, thumb + price + source `AssistChip` + tap-through to `CustomTabsIntent`). Empty = section-local `BOBAEmptyState` w/ refresh `TextButton`. Loading = 3-tile skeleton (`Modifier.placeholder`), not spinner.

**Market estimate header** (single line): *"~$24 · based on 8 recent sales (Radish + eBay)"*. Asking NEVER folded in.

---

### 8.8 Wall view + Price Overlay — display & share for everyone

Both lifted from streamer-only gate per DECISIONS.md #036.

**Wall view** is a `composable(...)` destination from Collection display-mode menu, Decks overflow ("Generate deck wall"), and Find multi-select ("Wall these N cards"). Full-screen `LazyVerticalGrid` of `BOBACardCell` on near-black, inline `OutlinedTextField` for title. `TopAppBar`: Save / Share / Copy / aspect picker (`DropdownMenu`) / Price Overlay `Switch`. Default aspect per source context.

**Price Overlay** = lower-third inset `Surface(color = surfaceContainerHigh)` with source `AssistChip` + price. Per-designation defaults match iOS DESIGN.md §8.8.

---

## 9. The Android redesign roadmap

v1 ship list (compact + medium + expanded across phone / tablet / Chromebook, all 5 tabs, container transforms, M3 Expressive surfaces wired, Practice admin-gated). Tracked in [SCRATCHPAD.md](./SCRATCHPAD.md) Android milestone section:

- **M0** — Compose + Material 3 stable + Navigation Compose set up; `BobaTheme` (dark + light + dynamic-opt-in); `BOBACardCell` + `BOBAEmptyState` + `BOBABanner` + `BOBAOfflinePill` primitives; assetlinks.json deployed; Firebase Android app registered.
- **M1 — Find + foundational adaptive layouts** — `NavigationSuiteScaffold` + Find tab w/ `ExpandedFullScreenSearchBar` + featured carousels + container-transform into card detail. **WindowSizeClass adaptation validated on phone + tablet + Chromebook from day one** (per DECISIONS.md #047).
- **M2 — Collection** — designation segmented button + grid/list/wall display modes + share Intent + tablet list-detail panes.
- **M3 — Scan + Pricing** — CameraX + ML Kit Text Recognition v2 bundled; pricing panels in card detail.
- **M4 — Decks** — pool + summary-bar + sheet editor (compact); `NavigableListDetailPaneScaffold` 3-pane on tablet/Chromebook from day one; drag-and-drop via `dragAndDropSource` / `dragAndDropTarget`.
- **M5 — Learn** — single-stream articles + skill-level scope segmented button + glossary tooltips + tablet list-detail panes.
- **M5.5 — Practice executor (admin-gated)** — port iOS state-machine engine to pure Kotlin in `:core:domain`; Practice screens as Compose translations of SwiftUI anatomy. Admin gate via `user_profiles.role` (DECISIONS.md #048).
- **M6 — Purchase** — Whatnot breaks tile list + Find a Store with Google Maps Compose.
- **M7 — Profile + Credential Manager auth + deep-link dispatcher** — Sign in with Google + passkey bottom sheet + Discord OAuth via Auth Tab / CustomTabs; BiometricPrompt; account-delete; avatar upload; Universal Links.
- **M8 — Internal testing + Play Console closed track** — Data Safety form, screenshots, 16 KB page-size validation, R8 + Baseline Profile validation, Macrobenchmark cold-start gate.

**Foldable adaptation is intentionally NOT a v1 target** (DECISIONS.md #047) — the standard `WindowSizeClass` adaptation works adequately on foldables without specific posture-aware optimization.

---

## 10. The daily review test

Before any feature ships:

1. **Gruber (§5.6):** could a competent designer recreate this screen from a one-paragraph description?
2. **Verb (§2.1):** what verb does this own? Colliding with another tab?
3. **Depth (§2.2):** count nav levels from tab root. If >2, the third should be a SegmentedButton, FilterChip row, ModalBottomSheet, or different tab.
4. **Material-native (§2.0):** for every UI element on screen, name the M3 component. Anything that doesn't map to a Material 3 / M3 Expressive component is a candidate for replacement.

When the answer to any of these is "no" or "I'm not sure," reread the relevant section. When the document is silent or contradicts itself, the document is wrong — propose an edit before proceeding.

---

## 11. Visual primitives — components + colors

Adding a new screen = composing existing primitives. New primitive = first edit this section.

### 11.1 Component library

| Composable | Purpose | iOS analog |
|---|---|---|
| `BOBACardCell` | Card thumbnail — 5:7 aspect, `RoundedCornerShape(12.dp)`, uniform padding, badge slot. Takes `size: CardCellSize`. | `BOBACardCell` |
| `BOBACardGridItem` | `BOBACardCell` + caption row (hero name `titleMedium` + weapon `AssistChip` + power `bodySmall` `tnum`). Density-adaptive via `columnCount`. | `BOBACardGridItem` |
| `BOBADeckSummaryBar` | `Surface` anchored as Scaffold `bottomBar`. Draft name + section breakdown + format. Tap → editor via `sharedBounds`. | `DeckSummaryPill` |
| `BOBASectionRow` | `ListItem` w/ leading icon + headline + trailing chevron. | `BOBASectionRow` |
| `BOBASectionHeader` | Uppercase Bebas Neue `headlineSmall`. No colored block. | `BOBASectionHeader` |
| `BOBASearchBarHost` | Wraps `SearchBar` / `ExpandedFullScreenSearchBar` with size-class branching + BOBA token state. | `BOBASearchBar` |
| `BOBAModalSheet` | Wraps `ModalBottomSheet` with canonical drag handle, `skipPartiallyExpanded` opt-in, side-sheet branching on medium+. | `BOBADetentSheet` |
| `BOBAEmptyState` | Icon + headline + body + productive-action button. | `BOBAEmptyState` |
| `BOBABanner` | Top-anchored `Surface(color = errorContainer or tertiaryContainer)` w/ icon + message + action. | `BOBAErrorBanner` |
| `BOBAHintBanner` | Cyan-accent, dismissible-permanent first-run hint per §6.8. DataStore-backed. | `BOBAHintBanner` |
| `BOBASignInPrompt` | Inline "Sign in to do this" row routing to Credential Manager. | `BOBASignInPrompt` |
| `BOBAWordmark` | Brand wordmark in `CenterAlignedTopAppBar` title slot. | `BOBAWordmark` |
| `BOBAFilledButton` / `BOBASecondaryButton` | `FilledButton` w/ brand-orange tint / `OutlinedButton`. | `BOBAGlassButton` / `BOBASecondaryButton` |
| `BOBAOfflinePill` | `AssistChip` w/ `Icons.Default.CloudOff`, lives in TopAppBar actions when offline. | `BOBAOfflinePill` |
| `BOBAStatsGrid` | Canonical 6-cell card-stats layout (DECISIONS.md #029). 2-col grid w/ fixed 3 rows. | `BOBAStatsGrid` |
| `BOBAPriceTile` | M3 `Card` for Buy Now / Sold tile w/ thumb + price + source chip. | `BOBAPriceTile` |
| `BOBAExpandableSection` | Title row + expand/collapse animation w/ `AnimatedVisibility`. No iOS DisclosureGroup equivalent — we own it. | — |

**Rule:** custom composable overlapping a primitive → use the primitive. Primitive doesn't fit → edit it (and document here). Never one-off.

### 11.2 Color usage rules

Two distinct systems — don't mix. Translates iOS DESIGN.md §11.2 verbatim into M3 token style.

**Brand (UI chrome only)** — these are the `colorScheme` overrides at theme construction:

| BOBA brand | M3 role |
|---|---|
| `--boba-orange #FF4D00` | `colorScheme.primary` (and primaryContainer derived) — primary CTA, FIRE |
| `--boba-cyan #00F5FF` | `colorScheme.secondary` — links / highlights / active states |
| `--boba-violet #8B00FF` | `colorScheme.tertiary` — secondary accents, HEX |
| `--boba-near-black #080810` | `colorScheme.background` and `surface` |
| `--boba-surface #0D0D1A` | `colorScheme.surfaceContainerLow` |

**Element (content semantic only)** — NOT in `colorScheme`; they live in a separate `BobaElements` object:

FIRE `#FF4D00` · ICE `#00BFFF` · STEEL `#8A9BB0` · BRAWL `#C0392B` · GLOW `#FFD700` · HEX `#8B00FF` · GUM `#FF69B4` · SUPER `#FF00FF` · NONE `#666680`.

**The split:** element colors only on weapon `AssistChip`s, filter `FilterChip`s, accent dividers, distribution charts (Vico). Brand colors only on chrome (`FilledButton`, `NavigationBar` indicator, FAB). Never element-as-chrome ("FIRE-themed button"); never brand-as-meaning ("orange = urgent" — orange already means FIRE).

**Orange overlap is intentional** — FIRE = brand anchor weapon by design.

**Element UPPERCASE in JSON, mixed-case in UI** ("Fire"). Casing is render-only.

**Dynamic color** — when the "Use system colors" toggle is ON, `dynamicDarkColorScheme(LocalContext.current)` overrides the brand `primary` only on Android 12+. Element colors never change.

---

## 12. Out of scope (intentionally)

Documented so future sessions don't re-add these as parity gaps.

| Surface | Why out | When to revisit |
|---|---|---|
| ~~Practice / Battle simulator~~ | **MOVED INTO SCOPE** per DECISIONS.md #048 — admin-gated on Android same as iOS. M5.5 milestone. | n/a |
| **Moderator corrections workflow** | Internal tool, mod-only audience | When mod tools open publicly |
| **Multi-step anchored walkthroughs** | Android conventions are universally legible (§6.10); TooltipBox + BOBAHintBanner cover the gap | If a future feature genuinely needs one |
| **Widgets / App Widgets / Quick Settings tiles** | No current implementation | When widgets scoped — Glance API for Compose-style widgets |
| **Wear OS** | Own discipline | If/when watchOS-equivalent targeted |
| **Android TV / ChromeOS exclusive** | Compose for TV is a separate framework | If TV ships |
| **Push notifications** | No surface yet — FCM dispatcher deferred per DECISIONS.md #039 | When notifications added (TRADE-DESIGN.md Phase 5+) |
| **Share copy templates** | Content design ≠ UI design | When share ships beyond v1 |
| **Whatnot show management** (streamer-gated) | Streamer-only audience | If/when general |
| **Card pipeline UI** | Internal tooling | Probably never user-facing |
| **App-launch slide-deck onboarding** | Explicitly rejected — universal Android conventions cover this | **Never** |
| **Sign in with Apple on Android** | iOS-only branding; Credential Manager + Sign in with Google + email is the canonical Android shape | Never |
| **Twitter / X integration (any form)** | DECISIONS.md #053 — binding. No Twitter OAuth via Credential Manager, no `ACTION_SEND` `com.twitter.android` targeting, no Twitter SDK / API. Discord remains the primary community channel; other social platforms (Bluesky, Mastodon, Threads) are fine when use cases arise. | **Never** |
| **Hamburger drawer on compact** | M3 Expressive de-emphasizes drawers; we have 5 destinations, NavigationBar handles it | Never |
| **Edge-to-edge opt-out** | Disallowed by Android 16; we honor edge-to-edge always | Never |
| **XML layouts / AppCompat / legacy ActionBar / Toolbar** | 100% Compose | Never |
| **Hero Shot 3D card rendering** | RealityKit-specific; Filament / Sceneform-successor port is a separate research effort | If/when Android Hero Shot prioritized |
| **Personal Showcase AirPlay-Video** | Android Cast (`MediaRouter`, Cast SDK) is the parallel; deserves its own deep dive | If/when Showcase parity prioritized |

**Add an entry when intentionally not-designed.** Remove when it comes into scope and gets designed elsewhere — don't leave stale "future" markers.

---

## 13. Parity-checking workflow when iOS ships changes

Process when an iOS change lands that's not pure implementation detail:

1. Author of the iOS change updates [`PARITY.md`](./PARITY.md) feature-parity table to mark the relevant feature as iOS-only, Android-only, or both.
2. If the change introduces new design patterns:
   - If it refines a principle already in this doc, no further action.
   - If it introduces a new pattern, add an entry here as a TODO for the Android equivalent, OR explicitly add it to §12 if Android shouldn't pursue it.
3. Periodic (~monthly) audit: compare iOS `DESIGN.md` last-modified sections against this doc and web `WEB-DESIGN.md`.

This workflow is intentionally lightweight — heavyweight process gets skipped, and the parity gap widens silently.

---

## 14. Quick translation map — iOS → Android (cheat sheet)

For the next session looking at an iOS surface and wondering "what does this become on Android?":

| iOS pattern | Android pattern |
|---|---|
| `TabView` w/ `Tab(role: .search)` | `NavigationSuiteScaffold` + `ExpandedFullScreenSearchBar` in Find |
| `NavigationStack` push | `NavController.navigate(route)` in `NavHost` |
| `NavigationSplitView` (iPad) | `NavigableListDetailPaneScaffold` (medium / expanded width) |
| `.searchable` | `SearchBar` / `DockedSearchBar` |
| `searchScopes` | `SingleChoiceSegmentedButtonRow` |
| `BOBAFilterToken` chip | `InputChip` (committed) / `SuggestionChip` (proposed) / `FilterChip` (persistent row) |
| `.sheet(detents: [.height(120), .medium, .large])` | `ModalBottomSheet` w/ partial + expanded sheet states |
| `.fullScreenCover` | `ModalBottomSheet(skipPartiallyExpanded = true)` OR full-screen `composable(...)` push |
| `.alert` | `AlertDialog` / `BasicAlertDialog` |
| `.popover` / `Menu` toolbar | `DropdownMenu` from `IconButton` |
| `.confirmationDialog` | `AlertDialog` w/ destructive `FilledTonalButton` |
| `.tabViewBottomAccessory` (scan in-progress) | `BottomAppBar` action slot or `HorizontalFloatingToolbar` |
| `.matchedTransitionSource` + `.navigationTransition(.zoom(...))` | `SharedTransitionLayout` + `Modifier.sharedBounds(key, ...)` |
| `.matchedGeometryEffect` | `Modifier.sharedElement(key, ...)` |
| `.toolbarBackground(.regularMaterial, for: .navigationBar)` | `TopAppBar(scrollBehavior = enterAlwaysScrollBehavior(...))` with `surfaceContainer` |
| `.scrollEdgeEffectStyle(.hard)` | `TopAppBarScrollBehavior.exitUntilCollapsed` w/ scrolledContainerColor token |
| `.glassEffect()` (Liquid Glass) | M3 tonal elevation + scroll-behavior color shift — **chrome only** |
| `Tab(role: .search)` morph to full screen | `SearchBar` `expanded = true` → `ExpandedFullScreenSearchBar` |
| `@AppStorage` | `DataStore<Preferences>` |
| iOS Keychain | Android Keystore + Tink-encrypted DataStore (or Credential Manager for sign-in tokens) |
| `NSCache` + `URLCache` | Coil 3 `MemoryCache` + `DiskCache` (60 MB / 500 MB byte-parity with iOS) |
| `URLSession` + `Codable` | `Ktor Client` + `kotlinx.serialization` |
| `AppIntent` | App Actions (`actions.xml`) + `androidx.core.app.ShortcutManagerCompat` |
| Universal Link (`.onOpenURL`) | App Link w/ `autoVerify=true` consumed by `NavController.deepLinks` + `assetlinks.json` at the same `/.well-known/` path as `apple-app-site-association` |
| `HintsManager` + `HintBanner` | `BOBAHintBanner` + `DataStore<Preferences>` for dismissals |
| Walkthrough engine | NOT shipped on Android — `TooltipBox` + `BOBAHintBanner` cover the gap (§6.10) |
| Sign in with Apple | Sign in with Google via Credential Manager (Apple is iOS-only brand) |
| `UIPasteboard` | `ClipboardManager` via `LocalClipboardManager.current` |
| `ShareLink` | `Intent.ACTION_SEND` + `Intent.createChooser` (+ custom actions on API 34+) |
| AVFoundation + Vision (Scan) | CameraX 1.5+ + ML Kit Text Recognition v2 (bundled) |
| `AVPlayer` (Showcase video) | `Media3 ExoPlayer` + `androidx.media3.ui.compose.PlayerSurface` |
| App Attest | Play Integrity API |
| Sign in with Apple "Apple ID" identity | "Google Account" via Sign in with Google |
| iOS notifications via APNs | Android notifications via FCM |
| `BiometricAuthentication` (Face ID / Touch ID) | `BiometricPrompt` via `androidx.biometric:biometric-compose` |

---

## 15. References

**Material 3 + Compose:**
- [Material 3 Design System (m3.material.io)](https://m3.material.io/)
- [Material 3 Expressive launch (Google blog)](https://blog.google/products-and-platforms/platforms/android/material-3-expressive-android-wearos-launch/)
- [Material 3 Expressive deep dive (Android Authority)](https://www.androidauthority.com/google-material-3-expressive-features-changes-availability-supported-devices-3556392/)
- [Material 3 Expressive: New Components, Motion, Shapes (Supercharge.design)](https://supercharge.design/blog/material-3-expressive)
- [Material Design 3 in Compose (Android Developers)](https://developer.android.com/develop/ui/compose/designsystems/material3)
- [Compose Material 3 release notes](https://developer.android.com/jetpack/androidx/releases/compose-material3)
- [9to5Google — M3 Expressive drops navigation drawer](https://9to5google.com/2025/05/14/material-3-expressive-navigation/)

**Components:**
- [App bars in Compose (TopAppBar variants + BottomAppBar)](https://developer.android.com/develop/ui/compose/components/app-bars)
- [Search bar](https://developer.android.com/develop/ui/compose/components/search-bar)
- [Bottom sheets](https://developer.android.com/develop/ui/compose/components/bottom-sheets)
- [Segmented button](https://developer.android.com/develop/ui/compose/components/segmented-button)
- [Chips (Filter / Assist / Input / Suggestion)](https://developer.android.com/develop/ui/compose/components/chip)
- [Carousel (multi-browse + hero)](https://developer.android.com/develop/ui/compose/components/carousel)
- [Pull to refresh](https://developer.android.com/develop/ui/compose/components/pull-to-refresh)
- [Navigation rail guidelines](https://m3.material.io/components/navigation-rail/guidelines)
- [Navigation drawer guidelines](https://m3.material.io/components/navigation-drawer/guidelines)
- [Snackbar guidelines](https://m3.material.io/components/snackbar/guidelines)
- [Loading indicator (Wavy + morphing shapes)](https://m3.material.io/components/loading-indicator)

**Adaptive layouts (tablet, foldable, Chromebook):**
- [Build adaptive navigation (NavigationSuiteScaffold)](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation)
- [Build a list-detail layout (NavigableListDetailPaneScaffold)](https://developer.android.com/develop/ui/compose/layouts/adaptive/list-detail)
- [Use window size classes](https://developer.android.com/develop/ui/compose/layouts/adaptive/use-window-size-classes)
- [Canonical layouts (list-detail / supporting pane / feed)](https://developer.android.com/develop/ui/compose/layouts/adaptive/canonical-layouts)
- [NavigableListDetailPaneScaffold deep dive (droidcon)](https://www.droidcon.com/2025/06/16/mastering-adaptive-uis-in-jetpack-compose-a-dive-into-navigablelistdetailpanescaffold/)

**Motion / transitions:**
- [Shared element transitions in Compose](https://developer.android.com/develop/ui/compose/animation/shared-elements)
- [Customize shared element transition](https://developer.android.com/develop/ui/compose/animation/shared-elements/customize)
- [Building Transitions with Material Motion for Android (M3 blog)](https://m3.material.io/blog/android-material-motion)

**Predictive back + edge-to-edge:**
- [About Predictive back (Compose)](https://developer.android.com/develop/ui/compose/system/predictive-back)
- [Set up Predictive back (Compose)](https://developer.android.com/develop/ui/compose/system/predictive-back-setup)
- [Behavior changes: Apps targeting Android 16](https://developer.android.com/about/versions/16/behavior-changes-16)
- [Handle edge-to-edge enforcements (codelab)](https://developer.android.com/codelabs/edge-to-edge)
- [System bar protection (Compose)](https://developer.android.com/develop/ui/compose/system/system-bars)

**Identity / cross-cutting capabilities:**
- [Credential Manager overview](https://developer.android.com/identity/sign-in/credential-manager)
- [About Sign in with Google](https://developer.android.com/identity/sign-in/credential-manager-siwg)
- [Send simple data to other apps (ACTION_SEND)](https://developer.android.com/training/sharing/send)
- [Adding Custom Actions to Share Sheets (Joe Birch)](https://joebirch.co/android/adding-custom-actions-to-share-sheets-in-android-14/)
- [Recognize text in images with ML Kit on Android](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)
- [On-Device OCR with ML Kit + CameraX (AtomicRobot)](https://atomicrobot.com/blog/mlkit-on-device-ocr-android/)

**Typography / theming:**
- [Typography (M3)](https://m3.material.io/styles/typography/applying-type)
- [Roboto Flex (Google Fonts)](https://fonts.google.com/specimen/Roboto+Flex)
- [Theming in Compose with Material 3 (codelab)](https://developer.android.com/codelabs/jetpack-compose-theming)
- [Dynamic colors](https://developer.android.com/develop/ui/views/theming/dynamic-colors)

**Accessibility:**
- [Principles for improving app accessibility](https://developer.android.com/guide/topics/ui/accessibility/principles)
- [Accessibility in Jetpack Compose (codelab)](https://developer.android.com/codelabs/jetpack-compose-accessibility)
- [Make apps more accessible](https://developer.android.com/guide/topics/ui/accessibility/apps)
- [WCAG 2.2 AA](https://www.w3.org/WAI/WCAG22/quickref/?levels=a%2Caa)

**Deep links / navigation:**
- [Create deep links](https://developer.android.com/training/app-links/create-deeplinks)
- [Navigation with Compose](https://developer.android.com/develop/ui/compose/navigation)
- [Add Intent filters for App Links](https://developer.android.com/training/app-links/add-applinks)
- [Verify Android App Links](https://developer.android.com/training/app-links/verify-android-applinks)

**Android 17 forward-compat:**
- [Android 17 design changes leak (91mobiles)](https://www.91mobiles.com/hub/android-17-design-changes-worth-knowing/)
- [Android 17 development roadmap (Sammy Fans)](https://www.sammyfans.com/2026/02/14/android-17-development-roadmap-beta-stable/)
- [Material 3 Expressive rollout (droid-life)](https://www.droid-life.com/2025/06/10/android-16s-big-material-3-expressive-update-arrives-in-q3/)

**Engineering companion:** See [ANDROID-DEV.md](./ANDROID-DEV.md) for the full engineering reference covering stack, build tooling, integration, and conventions.
