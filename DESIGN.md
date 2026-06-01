# BOBA Playbook — Design Theory

> **Binding.** Every new view, sheet, button, filter in the iOS app must trace to a rule here. When something feels overwhelming or inconsistent, fix the document, then fix the feature.
>
> Companion to [`CLAUDE.md`](./CLAUDE.md), [`DECISIONS.md`](./DECISIONS.md), [`WEB-DESIGN.md`](./WEB-DESIGN.md) (web), [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md) (Android), [`PARITY.md`](./PARITY.md) (cross-platform feature matrix). This doc owns iOS-specific rules; sibling docs translate the principles to web and Android. Reference, don't duplicate.

---

## 0. How to use this document

**Ben:** when a UI choice contradicts a rule, point at the rule. **Claude:** before proposing any new view / sheet / filter / picker / nav level / toolbar item, quote the rule that justifies it — no fitting rule means a new rule (and discussion) before it ships. **Living document:** §§5–7 follow Apple platform changes (update when iOS 27 ships); §§1–4 are principles and shouldn't change.

---

## 1. The six binding principles

0. **Native first.** Every interaction = built-in iOS API before custom code. `.searchable` before custom search bars. `.navigationTransition(.zoom)` before custom modal animation. `.fullScreenCover` + `.matchedTransitionSource` before custom drawers. `Tab(role: .search)` before custom bottom-anchored search pills. If iOS doesn't provide it, accept iOS's pattern over building custom — maintenance cost compounds every iOS update. **The repeated failure mode in this codebase was reaching for custom when native would have done** (the v2.038 custom-drawer-flash and the v2.054→v2.061 forehead-bug each took 10+ iterations and vanished the moment we used the native equivalent).

1. **Each tab owns one verb.** Find = explore · Learn = understand · Decks = build · Collection = own · Purchase = acquire. Verb collision = structural bug; resolve before adding.

2. **Navigation depth ≤ 2 inside a tab.** Tab → list → detail. Anything deeper = Russian-doll navigation; the user loses orientation. A would-be third level is actually a parallel filter axis (§6) or belongs in a different tab.

3. **Search is the universal navigator.** Find uses `Tab(role: .search)`; other tabs get `.searchable` over their domain. >~50 items: search beats taxonomy. Filters become tokens, not nav levels.

4. **Density comes from removing chrome.** Three weights × two sizes = six hierarchy levels with zero added pixels. Every divider/shadow/badge/chip removed = remaining info reads denser. (Tufte / Things 3 / Reeder lineage.)

5. **Liquid Glass = navigation only.** Card grid never gets `.glassEffect()`. Tab bar / toolbar / sheets / floating overlays do. One glass per stacking context. (WWDC25 219, Adopting Liquid Glass)

---

## 2. The IA decision tree

Walk in order. Stop at first match.

| Question | If yes |
|---|---|
| Top-level mode of the entire app? | **Tab** (≤5 total) |
| Hierarchical drill-down, one path in/back? | **NavigationStack push** (max depth 2) |
| Parallel filter/view over same data? | **`searchScopes` / scope bar inside destination** — NOT a third nav level |
| Full-focus action that might be abandoned? | **Sheet `presentationDetents([.large])`** |
| Glance-and-return (filters, quick edit)? | **Sheet `[height(N), .medium]`** + drag indicator |
| Side panel for selection (iPad)? | **`.inspector()`** — only if iPad parity worth complexity |
| Destructive/one-shot config? | **Toolbar `Menu`** w/ leading-icon disclosure |
| Global state across screens (scan, draft, player)? | **`.tabViewBottomAccessory`** (§6.5) |
| Verb working in ≥2 tabs (scan, share, profile)? | **Cross-cutting capability** (§6.5) |
| None of the above | **Inline control** in `Form` `Section` |

**If you reach the bottom with no match, fold the feature into an existing view** — almost always the right answer.

---

## 3. Anti-patterns we reject

Each one with a concrete current-code example so we know what to refactor.

### 3.1 Russian-doll navigation (depth > 2)
Collapse middle layers into scope bars or different tabs. Tab → list → detail; anything deeper is a parallel filter axis or it's misplaced.

### 3.2 Pill-bar pile-up (multiple horizontal scrolling rows of equal-weight chips)
At most ONE persistent filter row. Everything else moves to `.searchable` tokens, a `Menu`, or a sheet.

### 3.3 Tab-inside-tab (segmented control at top of a tab that switches sub-modes)
If you need a second tab bar, you need a different top-level tab OR `searchScopes` over a single content stream. Make it a scope, not a mode.

### 3.4 Modal-on-modal
Within a sheet, push with an internal `NavigationStack` to preserve the dismissal contract. Never stack sheet-on-sheet-on-alert.

### 3.5 Glass-on-glass-on-glass
One glass per stacking context. Glass cannot sample other glass; layered glass produces muddy backdrops and fails WCAG AA. Use `GlassEffectContainer` for ≥2 co-located glass elements. List rows / cards / content get NO glass — ever. (conorluddy/LiquidGlassReference)

### 3.6 Settings dump (every config knob visible at once)
Progressive disclosure. `Form` + `Section` + `DisclosureGroup`. Default advanced collapsed; lead with the 3 most-changed.

### 3.7 NavigationLink on settings-style rows
A row that looks like a push but is actually a picker destroys chevron trust. Use `Picker(_:selection:)` inline or `Menu` — never a fake push.

### 3.8 Action tabs (`+`, `Scan`, `Buy` as a tab)
We don't do this. Find rendered larger than peers is **size differentiation, not an action tab** — it's still a navigation destination. (Hanin on iOS 26 tab bar anti-patterns)

### 3.9 Equal-weight horizontal scroll bars
Horizontal scroll hides content below the fold and doesn't paginate predictably. Use vertical list (`Form` / `LazyVGrid`), `Menu`, or sidebar on iPad. Reserve horizontal scroll for genuinely-content shelves (featured cards, recently-viewed).

### 3.10 Custom presentation backgrounds on sheets
Strip every `.presentationBackground` modifier. Let the system apply inset Liquid Glass. (WWDC25 323)

### 3.11 Hand-rolled scroll-edge fade overlays
Use `.scrollEdgeEffectStyle(.soft|.hard, for: .top)` — iOS 26 native. `.hard` for dense scrolls (card grids), `.soft` for reading content.

### 3.12 The word "pool" to describe cards
**Never** — it collides with BOBA's collector-first audience. The Decks browsing surface is the **card browser** (or **library** / **catalog** / **your collection** by scope). No user-visible string, doc, or commit uses "pool" for cards; internal code identifiers (`dbRenderGrid`, `_dbBrowser`) are exempt (renaming is more churn than value). Tournament "pools" (round-robin team groups) is a separate canonical sports term and stays.

---

## 4. Density rules

Each is testable in code review.

1. **No tinted-box backgrounds on lists/cards.** Row separation = `Divider()` or vertical spacing. Container separation = Liquid Glass, not a tinted box.
2. **Three weights × two sizes = six levels.** Bebas Neue/Russo One bold (L1 page title) · Chakra Petch semibold (L2 section header) · Chakra Petch regular (L3 body) · CP regular small (L4 caption) · CP light (L5 de-emphasis) · CP monospace (L6 tabular). Refuse a seventh — refactor.
3. **Small multiples.** Every card cell in every grid shares aspect/padding/badge placement. Single canonical `BOBACardCell` everywhere.
4. **Show the data; filter it.** Persistent search field is denser than a category picker — zero-overhead access to everything. Filters before nav levels.
5. **Progressive disclosure predictable.** `DisclosureGroup` for inline, `NavigationLink` for push — never overload. A disclosure that sometimes inlines and sometimes pushes destroys trust.
6. **Gruber test:** *"Could a competent designer recreate this screen from a one-paragraph description?"* If no, decoration. Strip and rebuild.

---

## 5. Liquid Glass usage rules (iOS 26)

1. **Glass = navigation chrome only.** Tab bar, toolbar, sheets, floating overlays, FABs. Lists, cards, content — never. (WWDC25 219)
2. **One glass per stacking context.** Glass cannot sample glass. For ≥2 co-located, wrap in `GlassEffectContainer`. (conorluddy/LiquidGlassReference)
3. **Variants mutually exclusive.** `.regular` (default) · `.clear` (only when bg is media-rich, dim doesn't hurt, fg is bold+bright) · `.identity` (toggle off without layout shift).
4. **Tinting = primary action only.** Save button gets a tint; deck name field doesn't.
5. **Strip custom presentation backgrounds.** Sheets get inset Liquid Glass automatically. (WWDC25 323)
6. **`scrollEdgeEffectStyle(.hard)` for dense scrolls** (Find / Decks card browser / Collection grids — Calendar is the canonical reference). `.soft` for reading. (createwithswift)
7. **Never hard-code glass opacity.** Test all chrome at every iOS 26.1+ Tinted Mode setting; bottom-row grid cells must remain readable when tab bar is near-opaque.
8. **Test Reduce Transparency / Reduce Motion / Increase Contrast on.** iOS auto-adjusts; don't override — verify content survives.
9. **Glass over uncontrolled bg (card art) requires `.tint()`** anchored against dominant hue. Without it, material reads muddy.
10. **Don't animate glass during scroll.** Restrict morphs to discrete state changes.

---

## 6. Search-first IA

iOS 26's `Tab(role: .search)` + `.searchable` are the center of every dense view.

1. **Find = `Tab(role: .search)`** (full-screen expansion, tab bar minimizes during search). Don't use plain `.searchable` at the top of a regular tab. (WWDC25 323, nilcoalescing)
2. **Every other tab `.searchable` over its own domain.** Decks = decks + browser. Learn = articles + glossary. Collection = owned cards. Purchase = stores + breaks.
3. **`searchScopes` for orthogonal axes** (Cards vs Heroes vs Decks) — appears only when search is active.
4. **Search tokens for filter narrowing.** `BOBAFilterToken` enum (hero/element/treatment/cost/format/set). Replaces filter-pill rows.
5. **`searchSuggestions` for partial queries.** "MAVE" → "Maverick"; "RBF-" → "RBF-72 Maverick (Red Battlefoil)".
6. **Always ship `ContentUnavailableView.search`** with refinement suggestions ("Try removing the Cost filter").
7. **Wire through `AppIntent`** so Spotlight / Siri / iOS 27 natural-language inherit free (§7).

---

## 6.5 Cross-cutting capabilities

Verbs that operate across multiple tabs share **one** implementation, **one** active-state UI, route by invocation context. Tabs own primary verbs (explore/understand/build/own/acquire); cross-cutting are sub-verbs (scan/share/sign-in) that serve whichever primary verb the user is in.

### Scanning

One `ScanStore`, one `ScanView` (live single), one `GridScanView` (multi-card still), one queue review UI. Invoking tab sets *destination* + *default capture action*:

| Invoking tab | Destination | Default action | Queue review |
|---|---|---|---|
| **Find** | identify only | hold in queue | tap → push to detail |
| **Decks** | current deck | add immediately | post-capture: dupes + legality |
| **Collection** | designation chosen at start | add to that designation | post-capture: change designation |

While a session is open, `.tabViewBottomAccessory` shows *"Scanning · 7 cards · tap to review"* across tab switches (Donny Wals on TabView accessory).

**Anti-pattern:** separate per-tab scan implementations. Use one `ScanCoordinator.start(destination:)`; per-tab button is just a toolbar item.

### Share

Single iOS share sheet from card / deck / collection-scope surfaces. Includes: deep link (Universal Link to iOS, web fallback `bobaplaybook.com/{type}/{id}`), rendered image (card art / deck thumb / Wall), plain text summary.

### Profile / sign-in / auth

**Profile is Find-only** (top-leading toolbar gear). Other tabs surface auth via inline `BOBASignInPrompt` at point of action — never a full-screen wall. Profile sheet uses `.medium` detent default, expands to `.large`.

**Auth-required vs. optional:** the app must work fully signed-out for every read verb (explore, understand, build draft, browse Collection empty, acquire). Auth required only for writes (Save deck, designate, edit Profile). Sign in with Apple preferred; email fallback under "More options." Keychain per DECISIONS.md #007.

**Deep-link recipients** open public collections without sign-in; inline prompt fires only on first write action.

### Adding a new cross-cutting capability

1. Verb relevant in ≥2 tabs (else it's tab-specific).
2. Active state benefits from persistence across tabs (else no `.tabViewBottomAccessory` slot).
3. Single coordinator + UI implementation (per-tab variants = abstraction is wrong).

---

## 6.6 Per-size-class adaptations (binding for iPad)

iPad ships as first-class. Every new view declares its regular-width adaptation; PRs without one are rejected. Test in iPad simulator (portrait + landscape) at every diff.

| Pattern (compact) | Regular (iPad) |
|---|---|
| `NavigationStack` push | `NavigationSplitView` (2- or 3-column) |
| `Tab(role: .search)` full-screen | `Tab(role: .search)` stays full-screen — see TabView note below |
| Bottom sheet with detents | Trailing column / popover — never modal-over-canvas |
| `searchScopes` bar | Scope rows in sidebar |
| Toolbar `Menu` w/ disclosure | Inline toolbar buttons (1000pt+ of horizontal room) |
| Card grid 3 cols | 5–7 cols via size-class-aware `@AppStorage` initial value |
| `.tabViewBottomAccessory` | Auto-adapts in iOS 26 |
| `.matchedTransitionSource` + `.zoom` | System push (see §6.6.2) |
| `.fullScreenCover` for content | NavigationSplitView detail column |
| `.sheet` for actions (Profile, picker) | Popover via `.presentationCompactAdaptation(.popover)` |

**TabView style.** Do NOT apply `.tabViewStyle(.sidebarAdaptable)`. iPadOS 26's sidebar mode (which `.sidebarAdaptable` opts into) puts the tab list in a left sidebar, which then visually competes with our per-tab `NavigationSplitView` sidebars (saved decks, lens picker, mode picker, category list). Floating tab pill stays on every device; iPad gets richer in-tab navigation via per-tab `NavigationSplitView` than the system tab sidebar (which is just 5 tab names) would provide.

**Decks on iPad is canonical:** 3-column `NavigationSplitView` (saved decks | browser | current deck w/ stats+legality+rules inline). Same verb, same components; different spatial arrangement.

**Don't fork per-platform.** Use `@Environment(\.horizontalSizeClass)`, `NavigationSplitView`/`NavigationStack` swap, `.adaptive` LazyVGrid. One hierarchy, size-class-responsive — never two parallel view hierarchies.

**Mac Catalyst** stays not-targeted. Avoid gesture-only primary actions.

### 6.6.1 — Walkthroughs on iPad

Overlays MUST read `safeAreaInsets` from a GeometryReader at the root. Never hardcode nav-bar / tab-bar clearance. iPad portrait, iPad landscape, and Stage Manager / Split View have different safe-area math; the v2.0xx 60pt-top / 96pt-bottom magic numbers were a phone-only assumption and cut tooltips off on iPad.

- Anchor cutouts respect host's `safeAreaInsets`.
- Skip / Next / Done bar lives at trailing-edge vertical column on iPad landscape ≥1024pt; bottom-bar is compact-only.
- Walkthrough scripts authored once; same script runs both width classes — visual treatment is the only fork.

### 6.6.2 — Hero zoom is compact-only

`.matchedTransitionSource` + `.navigationTransition(.zoom(...))` apply only when `horizontalSizeClass == .compact`. Regular width falls back to system push.

A corner cell zooming to a 1024pt destination reads as broken — the "slingshot" travels too far and the 200pt thumbnail can't sample 1024pt of detail cleanly. System push lets the wider canvas read as a destination, not the same cell expanded.

Applies to Find / Decks card browser / Collection / Learn cell taps and the Decks summary-pill → editor zoom. Not a content choice — a screen-size constraint.

---

## 6.7 Universal states — empty / loading / error / offline

Every list, grid, search, sheet defines behavior for four states beyond happy path.

1. **Loading.** `ProgressView` only for >300ms operations. Initial lists use 3–5 row skeletons (shape-of-real-row), not full-screen spinners. Loading happens in place — preserve layout.
2. **Empty.** `ContentUnavailableView` with brand-voice copy + productive next action. Bad: "No items." Good: *"No decks yet — start with a template."* + template gallery as actions.
3. **Error.** `ContentUnavailableView` with clear message, distinguishing user-fixable (network/auth) from system errors. Retry button for transient. Errors during write surface as `BOBAErrorBanner` above the action, never a nav interruption.
4. **Offline.** Degraded, not blocked. Cached catalog → Find/Learn/Decks/Collection-browse work. Cloud writes disabled w/ inline tooltips. Subtle "Offline" pill in top-trailing nav.

**Anti-pattern:** per-tab empty/error styling. Use canonical `BOBAEmptyState` + `BOBAErrorBanner` (§11).

---

## 6.8 First-run hints

`HintsManager` + `HintBanner` per DECISIONS.md #031. **Use** for non-obvious behavior the design can't cleanly carry (e.g., bonus play ceiling at count ≥7); **don't use** to paper over confusing UI — fix the UI. **Visual:** cyan accent, X-dismiss-permanent, distinct from `ContentUnavailableView` (structural) and `BOBAErrorBanner` (orange, attention); Profile has global silence + reset. **No cascades** — one hint per surface; hints teach a tip on a known surface, walkthroughs (§6.10) teach a brand-new one.

---

## 6.9 Toolbar + app chrome standardization

1. **Material:** every view sets `.toolbarBackground(.regularMaterial, for: .navigationBar)` + `.toolbarBackground(.visible, for: .navigationBar)`. iOS 26 resolves `.regularMaterial` to Liquid Glass.
2. **Wordmark:** root = `BOBAWordmark` centered. Push = contextual title. Modals = own title.
3. **Slots:**
   - Leading: Profile gear (auth-aware) / Cancel (modal) / back chevron (push, system).
   - Trailing: primary action / contextual `Menu`. If both, primary right-most, Menu left.
   - Center: wordmark on root, contextual title on push. Never both.
   - Bottom (`.tabViewBottomAccessory`): cross-cutting state only (scan, deck draft, player). Never tab-specific content.
4. **No custom chrome on top of system chrome.** System nav bar IS the title bar.
5. **Strip `.navigationBarHidden(true)`** unless genuinely chromeless (camera). Density comes from typography (§4), not hiding chrome.
6. **Don't fight `.tabBarMinimizeBehavior(.onScrollDown)`.** Tab bar shrinks during scroll — correct behavior.

---

## 6.10 Feature walkthroughs

Anchored, multi-step tutorials that fire on first visit to a major feature. *Just-in-time, per-feature* — not a slide-deck on first launch.

**Where walkthroughs fire (first visit only, per device):**

| Surface | Trigger |
|---|---|
| **Find / Learn / Decks / Collection / Purchase** | First time the tab is opened (Decks: with no existing decks) |
| **Card detail** (§8.6) | First card detail open from any tab |
| **Pricing panels** (§8.7) | First scroll to the pricing section |
| **Wall view** (§8.8) | First Wall render |
| **Scan** (§6.5) | First scan invocation, in the destination tab's context |
| **Multi-card grid scan** | First grid scan (separate from single-card) |

A new feature gets a walkthrough only if it introduces a genuinely new interaction model — not new content.

**Binding rules:**
- **≤5 steps, ≤12 words/step.** If a feature needs more, refactor the feature, not the walkthrough.
- **Anchor-based, not modal.** Highlight real UI with a ring; copy floats nearby in a glass tooltip; background dims. Never a slide deck of stylized illustrations.
- **Skip + Done always visible.** Tap outside = advance; tap anchor = complete the demonstrated action + advance.
- **Voice:** second person, action-oriented. *"Tap a card to add it to your deck."* — not *"In this view, you can build out your deck by..."*
- **Visual:** 2pt cyan ring, glass copy bubble (chrome glass per §5), 60% black dim with 12pt anchor cutout, dot step indicator, glass Skip/Next/Done bar.
- **Universal manager.** `WalkthroughsManager` parallels `HintsManager` (DECISIONS.md #031): per-device dismissal in `UserDefaults`, Profile reset button + global toggle.
- **Re-launchable.** Every walkthrough re-triggers from a "?" overflow Menu item. New users learn; returning users *re-learn*.

**When to use which teaching surface:**

| Use case | Component |
|---|---|
| First-time feature discovery | **Walkthrough** (§6.10) |
| Non-obvious tip on a known surface | **HintBanner** (§6.8) |
| Screen has no content yet | **EmptyState** (§6.7) |
| User-triggered action fails | **ErrorBanner** (§6.7) |

**Anti-patterns:**
- Explaining self-explanatory UI (fix the UI instead)
- Hijacking navigation (anchor on current view; don't push)
- Competing with `.tabViewBottomAccessory` (pause accessory while active)
- Multiple walkthroughs on same first visit (each fires on its own first use)
- Requiring sign-in (walkthroughs honor §6.5 auth-optional rule)
- Slide-deck onboarding splash (explicitly rejected — teach with real UI)

### 6.10.1 Walkthrough catalog

Scripts live in `BOBAPlaybook/Components/BOBAWalkthrough.swift` (`extension BOBAWalkthrough.Script`) — **the code is the source of truth.** A script exceeding 12 words/step or 5 steps signals a wrong anchor or a too-complex feature.

---

## 7. Forward-compatibility (iOS 27 ready)

iOS 27 (WWDC 2026 June 8) focuses on Siri/Apple Intelligence + Liquid Glass refinement (opacity slider); **no navigation paradigm shift expected.** Rules that inherit those gains automatically: (1) **every primary action is an `AppIntent`** (Spotlight/Siri/Action Button/Shortcuts consume them); (2) **content has stable IDs** — `bobaId`, deck UUIDs, Learn article slugs (`setup.match-flow`); (3) **search is central** (§6) — the only path to future natural-language search without an IA rewrite; (4) **don't hard-code glass opacity** (Tinted Mode slider, iOS 26.1+); (5) **don't predict iOS 27 specifics** — build clean to iOS 26, inherit refinements when they ship.

---

## 8. Per-tab IA recipes

Binding redesign target. New tabs follow these templates.

### 8.1 Find — explore

`Tab(role: .search)` with full-screen search expansion.
- **No-search:** featured ribbons (Heroes by Weapon, Athletes, Recently Added, Coaching Staff, Saved Searches) — horizontal `BOBACardCell` scrolls.
- **Search-active:** tab bar minimizes; field takes canvas. Tokens (hero / element / treatment / cost / format / set). Optional scopes (Cards / Heroes / Featured).
- Grid: uniform `BOBACardCell`, 3 cols, `.scrollEdgeEffectStyle(.hard, for: .top)`. Tap → push `CardDetailView`.
- Toolbar: scan trailing, profile leading on collapse.
- **Anti-patterns:** filter pills above grid (use tokens); multiple "browse by" pickers (use scopes).

### 8.2 Learn — understand

`NavigationStack` push from single root list (Music Library pattern). No card details/add actions — those belong in Find.
- Root: 5 categories (Rules / Strategy / Collect / Glossary / Tournament) as `BOBASectionRow`.
- Article: Rookie / Sub / Playmaker = `searchScopes` scope bar — NOT a third nav level. Read/Watch is also a scope when video exists.
- `.searchable` spans the corpus; `ContentUnavailableView.search` for zero-results.
- Toolbar: glossary trailing — inline definition popup.
- Stable slugs per article+section for AppIntent / deep links (§7).

### 8.3 Decks — build

Music's mini-player + `fullScreenCover` with hero zoom. **Card browser = canvas; current deck = non-draggable summary pill that zooms into a full-screen editor on tap.** Maps-canvas-with-sheet was abandoned after 12+ iterations of custom-drawer flash (§1.0 native-first).
- Canvas: `BOBACardGridItem` grid + `.scrollEdgeEffectStyle(.hard, for: .top)`.
- `DeckSummaryPill` via `.safeAreaInset(edge: .bottom)` — draft name + section breakdown (e.g. `8/8 H · 30/30 P · 6 BP · 10/10 HD`) + format badge. Empty: "Build a deck · Tap to open the editor."
- Pill → editor: `.fullScreenCover` + `.matchedTransitionSource(id:"deck-draft",in:ns)` + `.navigationTransition(.zoom(...))`.
- Editor: `NavigationStack(path:)` — deck header + format chip strip + grouped list. Toolbar: Close leading + SAVE/SIGN IN trailing + ⋯ Menu (Manage Decks, Rules, Legality, Clear).
- Editor secondaries (Manage / Rules / Legality) push as `NavigationLink` within editor's stack — NOT stacked sheets. Sheet structs accept `wrapInNavStack: Bool = true` to work in both modes.
- Browser filter: `.searchable(text:tokens:suggestedTokens:placement:.navigationBarDrawer(.always))` with `BOBAFilterToken` (weapon / cost / hero).
- Card tap → detail push + zoom (§8.6). Long-press → adds to draft (canonical add gesture).
- Browser toolbar: wordmark principal + ⋯ Menu (1/2/3 cols, Scan, walkthrough). NO Save in browser.
- Grid density: `@AppStorage("bp_decksGridColumns_v1")` default 3; 1/2-across pulls full-size images.
- **Anti-patterns:** custom/draggable drawer; quick-add toggle; per-tab status banner; sheets stacked on editor (push instead).

### 8.4 Collection — own

Root = **My Cards** (owned cards by designation). Rainbow + My Shows push from ⋯ Menu — NOT a top-level mode picker (the prior 5-row chrome stack was what this overhaul killed).
- Grid: `BOBACardGridItem`.
- Designation segmented Picker: Personal / Sale / Trade / Wanted / Grails (`Designation.shortDisplayName`).
- `.searchable(.navigationBarDrawer(.always))` composes with filter + designation scope.
- ⋯ Menu: display mode (List / Grid / Wall), grid density (1/2/3 via `@AppStorage("bp_collectionGridColumns_v1")`), lenses (Rainbow push; My Shows streamer-only push).
- Designation badge corner overlay so multi-designation cards scan across scopes.
- Tap card → `CollectionCardDetailView` push + zoom (§8.6).
- Scan → "Add to which designation?" sheet (defaults Personal, remembers last) → routes via §6.5.
- Share → iOS share sheet w/ deep link + Wall image. Deep link = `bobaplaybook.com/u/{username}/{designation}` (Universal Link). Per-designation public/private in Profile.
- Profile = Find-only; auth surfaces are inline `BOBASignInPrompt`.
- Value summary: single line, no decoration; tap → value-history chart.
- Wall is a display mode for every collector (DECISIONS.md #036); My Shows stays streamer-gated.
- Public web fallback `bobaplaybook.com/u/ben/grails` renders the same wall in-browser, no sign-in.

### 8.5 Purchase — acquire

- Top: segmented Picker (≤4) — "Upcoming Breaks" | "Find a Store".
- Breaks: vertical card tiles (host / time / viewer count) → Whatnot deep link.
- Stores: MapKit + bottom sheet store list (Apple Maps pattern); detents `[.height(120), .medium, .large]`.
- Toolbar: filters Menu (radius, indie-only).

---

### 8.6 Card detail — the universal card view

Three structs (`CardDetailView`, `BrowserCardDetailSheet`, `CollectionCardDetailView`) **share artPanel + toolbar verbatim** — drift is the bug. Canonical blocks live in `BOBAPlaybook/Views/CardDetailView.swift`.

**Pattern:** Music-style hero zoom into NavigationLink push (NOT sheet). Source = `.matchedTransitionSource(id:in:)` as OUTERMOST modifier; destination = `.navigationTransition(.zoom(sourceID:in:))`. Modifier order: `.scrollEdgeEffectStyle(.soft, for: .top)` BEFORE `.background` (after-background doesn't register on the underlying ScrollView).

**Wrap-in-NavStack:** each struct takes `wrapInNavStack: Bool = true` — default true for sheet usage; push usage passes false so parent stack provides chrome. Done button conditional on sheet mode.

**Body order:** stats grid (canonical 6-cell, DECISIONS.md #029) → Cost+DBS (Plays) → pricing panels (§8.7) → per-context body.

**Toolbar by context:** Find = Add menu (Collection/Deck/Show) + Mod-edit + Share · Decks tap = "Add to Deck" CTA in body · Collection tap = Edit Designation + Add menu in body. Canonical verbs: `Add to Collection`, `Add to Deck`, `Share`, `Edit Designation`.

**Anti-patterns:** per-surface artPanel/toolbar variants; sheets for drill-in (push Manage/Rules/Legality instead); prev/next chevrons in bottom toolbar.

**Hero zoom rules:** source applies `.matchedTransitionSource(id, in:)` as outermost modifier; destination applies `.navigationTransition(.zoom(sourceID:, in:))`; one `@Namespace` per parent shared source↔destination; push via NavigationLink or path-append; ID = `card.id` for Find/Decks, `bobaId` for Collection. **"nil view" warning** = iOS couldn't find matching source ID → fallback transition. Causes: matchedTransitionSource on INNER view wrapped by Button/overlay/modifier (apply as outermost), or applied inside a function-returning-view (apply at call site).

### 8.7 Pricing panels — provenance-honest (Recent Sales · Listed Range)

Lives inside `CardDetailView`. Live-fetched (DECISIONS.md #013). COMC asking stays OUT of any sold-comp number (#034) — asking inflates 10-25%.

**Provenance is the contract.** Every number states what kind of data it is. We NEVER present a derived guess as a "Market Est." when no real sold data backs it — that was the post-Radish/post-Marketplace-Insights failure mode (see PRICING_PLAYBOOK.md + DECISIONS.md #058). The panel shows the most-specific *honestly-labeled* signal available, in this order:

1. **Recent Sales** (transacted — the real thing): real sold comps, each row carrying its own source pill — eBay vanish-inferred (PRICING_PLAYBOOK Tier 1), Whatnot (Tier 2), or community (Tier 3, "BoBA Community · @user"). Shown only when real sold data exists.
2. **Listed Range** (asking — what's on the market now): when there is NO real sold data, the active eBay listings ARE the honest primary signal. Header "LISTED RANGE", LOW/AVG/HIGH range + count, provenance line "Active eBay listings · no recent sales data yet", pill "eBay listed". This replaces the old "fall through to a fabricated Market Est." behavior.
3. **Buy Now** (where to buy): when Recent Sales exists, active eBay listings + COMC asking ("COMC asking · Ungraded NM" pill, soft-fail on `challenged: true`) render as a separate "Buy Now" section. When there is no Recent Sales, the active data is the Listed Range (item 2) — not a duplicate Buy Now.
4. **Estimate** (derived — Tier 4, when it has real comps): the `boba-price-estimator` surfaces ONLY clearly labeled as an estimate ("Estimated · based on N comparable cards") and only when fed real comp data. Never the sole number presented as market value. Suppressed entirely while the estimator is starved (current state).

Per-section: horizontal scroll of price tiles (thumb + price + source pill + tap-through). Empty = section-local `ContentUnavailableView` w/ refresh. Loading = 3-tile skeleton. A single per-card "View on Radish" external-browser link is preserved on every card detail (legacy frozen `card.radishUrl` when present, else the Radish homepage; DECISIONS.md #056).

Real-sold header (single line, only when Recent Sales exists): *"~$24 · based on 8 recent sales"*. Asking NEVER folded in. Cached `user_cards.estimated_value` for Collection value-summary; grid doesn't re-fetch live.

**Anti-patterns:** presenting a derived or empty estimate as "Market Est." (the dishonest-provenance trap PRICING_PLAYBOOK §7 kills); asking+sold combined (inflation); one source when both available; sources behind disclosure (provenance is the trust mechanism); `EST. MID` / `EST. LOW` / `EST. HIGH` labels inside the MARKET EST. tile (cell labels are always `LOW / AVG / HIGH` — the section header carries the "estimated" framing, per DECISIONS.md #059 cross-platform vocabulary lock); **a global time-window picker scoping the whole pricing panel** (the picker visually scopes everything but only controls one signal — DECISIONS.md #060 removed the iOS + web 7/30/90 picker for this reason). Recent Sales freshness reads off per-row `soldAt` dates; active listings are inherently current.

**Community comps (Tier 3) — quiet + subordinate.** A single low-emphasis link at the FOOT of the pricing section ("Saw one sell? Add a price") opens a focused `.medium` sheet (price · sold date · platform · optional photo · notes → `submit_community_comp`). It NEVER sits above the art, NEVER rivals "Add to Collection", and is auth-gated inline via `BOBASignInPrompt` (§6.5 — prompt, not a wall). The collector who has comp data taps in; everyone else sees only a tiny link. Submitted comps are mod-reviewed before surfacing as "Recent Sales · BoBA Community". Rationale (learning-orientation): invite participation in pricing accuracy without displacing why people actually open a card — art, current price, collection.

### 8.8 Wall view + Price Overlay — for everyone

Both lifted from streamer-only gate (DECISIONS.md #036).

**Wall view.** Render N cards as a single shareable image (sale lists, trade lists, deck composition, teaching). Invocation: Collection display-mode picker; Decks ⋯ Menu ("Generate deck wall"); Find multi-select ("Wall these N cards"). Full-screen small-multiples grid (`BOBACardCell`, near-black bg) + inline-editable title strip. Toolbar: Save / Share / Copy / aspect picker (9:19.5, 1:1, 16:9, 3:4) / Price Overlay toggle. Default aspect = source-context (Collection→IG square, Deck→16:9). Honors current scope — never re-filter inside Wall.

**Price Overlay.** Toggle in Wall view only (sharing affordance, not browsing). Chip: lower-third inset, source pill (eBay / COMC / Custom) + price. Default source = lowest-asking; toggle to "My price" (`estimated_value` or per-card override). Glass with `.tint()` per §5. Optional condition chip (NM/EX/GD) for Sale/Trade. Per-designation defaults: Sale ON / My price · Trade ON / market est · Grails+Personal OFF · Wanted ON / market est / "WTB" prefix.

---

## 9. The redesign roadmap

Original 30-item roadmap substantially complete (all tab rebuilds, walkthroughs, Liquid Glass, scan unify, Wall+Overlay un-gate). History in git at v2.072; open work in [SCRATCHPAD.md](./SCRATCHPAD.md).

---

## 10. The daily review test

Before any feature ships: **Gruber (§4.6)** — recreatable from a one-paragraph description, or it's decoration. **Verb (§1.1)** — which verb does it own; colliding = structural bug. **Depth (§1.2)** — >2 nav levels from tab root means the third is a scope/sheet/different tab. When the answer is "no"/"unsure," reread the section; when the doc is silent or self-contradicting, fix the doc first.

---

## 11. Visual primitives — components + colors

Adding a new view = composing existing primitives. New primitive = first edit this section.

### 11.1 Component library

| Component | Purpose |
|---|---|
| `BOBACardCell` | Card thumbnail — uniform aspect, padding, badge placement. Takes `size:` (`.thumb` default; `.full` at ≤2-across, BOBACardGridItem handles this). |
| `BOBACardGridItem` | Unified grid cell: `BOBACardCell` + caption (hero name, weapon pill, power). Density-adaptive via `columnCount: 1\|2\|3`. Element-tinted capsule keeps HEX readable. |
| `DeckSummaryPill` | Bottom-anchored draft summary above tab bar. Tap → zoom into editor (§8.6 transition). Used via `.safeAreaInset(edge: .bottom)`. Replaces v2.038 drawer. |
| `BOBASectionRow` | Single-line row — title + count + chevron. Learn root, Profile, Settings forms. |
| `BOBASectionHeader` | Uppercase Bebas Neue. No colored block. |
| `BOBASearchBar` | Wraps `.searchable` with BOBA token type. |
| `BOBADetentSheet` | Wraps `presentationDetents` with `[120, .medium, .large]`. |
| `BOBAEmptyState` | Wraps `ContentUnavailableView` with brand voice + productive-next-action slot. |
| `BOBAErrorBanner` | Orange banner above an action. Distinct from hints. |
| `BOBAHintBanner` | Cyan, dismissible-permanent first-run hint per §6.8. |
| `BOBAWalkthrough` | Anchored multi-step first-visit tutorial per §6.10. |
| `BOBASignInPrompt` | Inline "Sign in to do this" row pre-routing Profile sheet. |
| `BOBAWordmark` | Brand wordmark in title slot. |
| `BOBAGlassButton` / `BOBASecondaryButton` | Tinted-glass primary action / non-tinted secondary. |
| `BOBAOfflinePill` | Subtle nav-bar pill when offline. |
| `BOBAStatsGrid` | Canonical 6-cell card-stats layout (DECISIONS.md #029). |
| `BOBAPriceTile` | Buy Now / Sold tile in pricing panels. |

**Rule:** custom view overlapping a primitive → use the primitive. Primitive doesn't fit → edit it (and document here). Never one-off.

### 11.2 Color usage rules

Two distinct systems — don't mix.

**Brand (UI chrome only):** `--boba-orange #FF4D00` (primary CTA, FIRE) · `--boba-cyan #00F5FF` (links/highlights) · `--boba-violet #8B00FF` (secondary, HEX) · `--boba-near-black #080810` (bg) · `--boba-surface #0D0D1A` (panel).

**Element (content semantic only):** FIRE `#FF4D00` · ICE `#00BFFF` · STEEL `#8A9BB0` · BRAWL `#C0392B` · GLOW `#FFD700` · HEX `#8B00FF` · GUM `#FF69B4` · SUPER `#FF00FF` · ALT `#B084CC` · CYBER `#39FF14` · NONE `#666680`.

**The split:** element colors only on weapon badges, filter chips, accent lines, distribution charts. Brand colors only on chrome (buttons, links, CTAs). Never element-as-chrome ("FIRE-themed button"); never brand-as-meaning ("orange = urgent" — orange already means FIRE).

**Orange overlap is intentional** — FIRE = brand anchor weapon by design.

**Element UPPERCASE in JSON, mixed-case in UI** ("Fire"). Casing is render-only.

---

## 12. Out of scope (intentionally)

| Surface | Why out | When to revisit |
|---|---|---|
| **Practice / Battle simulator** (DECISIONS.md #030) | Different language (game-as-canvas) | When practice ships to all users |
| **Moderator corrections workflow** (DECISIONS.md #023) | Internal tool, mod-only audience, auditability over density | When mod tools open to public applicants |
| **Web app design** | See `WEB-DESIGN.md` (binding) | n/a — covered there |
| **Widgets / Live Activities** | No current implementation | When widgets scoped |
| **Apple Watch** | Own discipline | If/when watchOS targeted |
| **Push notifications** | No surface yet — will need rule for triggers/frequency/style | When notifications added |
| **Share copy templates** | Content design ≠ UI design | When share ships; possibly `COPY.md` |
| **Whatnot show management** (streamer-gated, #025) | Streamer-only audience | If/when unrolled to general |
| **Card pipeline UI** | Internal tooling | Probably never user-facing |
| **App-launch slide-deck onboarding** | Explicitly rejected — §6.10 walkthroughs replace this | **Never** |
| **Twitter / X integration (any form)** | DECISIONS.md #053 — binding. No Twitter OAuth, no "Share to Twitter" affordances, no Twitter SDK. Other social platforms (Discord, Bluesky, Mastodon, Threads) are fine when use cases arise. | **Never** |

**Add an entry when intentionally not-designed.** Remove when it comes into scope and gets designed elsewhere — don't leave stale "future" markers.

---

## 13. References

Sources cited inline above (search by title): Apple — Adopting Liquid Glass ·
Apple AppIntents (Integrating actions with Siri) · Apple HIG (Materials / Search /
Sheets / Sidebars / Tab Bars / Toolbars) · Bloomberg/Gurman iOS 27 Siri overhaul ·
conorluddy Liquid Glass Reference · createwithswift `scrollEdgeEffectStyle` ·
Donny Wals iOS 26 tab bars · Hanin "Don't Design Junk in the iOS 26 Tab Bar" ·
nilcoalescing SwiftUI search enhancements iOS 26 · WWDC25 219 (Meet Liquid Glass) ·
WWDC25 323 (Build a SwiftUI app with the new design).
