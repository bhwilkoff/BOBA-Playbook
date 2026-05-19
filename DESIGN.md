# BOBA Playbook — Design Theory

> **Binding.** Every new view, sheet, button, filter in the iOS app must trace to a rule here. When something feels overwhelming or inconsistent, fix the document, then fix the feature.
>
> Companion to [`CLAUDE.md`](./CLAUDE.md), [`DECISIONS.md`](./DECISIONS.md), [`WEB-DESIGN.md`](./WEB-DESIGN.md) (web), [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md) (Android), [`PARITY.md`](./PARITY.md) (cross-platform feature matrix). This doc owns iOS-specific rules; sibling docs translate the principles to web and Android. Reference, don't duplicate.

---

## 0. How to use this document

**Ben's job:** when a UI choice contradicts a rule, point at the rule.

**Claude's job:** before proposing any new view / sheet / filter / picker / nav level / toolbar item, quote the rule that justifies it. No fitting rule = needs a new rule (and discussion) before it ships.

**Living document.** §§5–7 follow Apple platform changes (update when iOS 27 ships, WWDC 2026 June 8). §§1–4 are principles and shouldn't change.

---

## 1. The six binding principles

0. **Native first.** Every interaction = built-in iOS API before custom code. `.searchable` before custom search bars. `.navigationTransition(.zoom)` before custom modal animation. `.fullScreenCover` + `.matchedTransitionSource` before custom drawers. `Tab(role: .search)` before custom bottom-anchored search pills. If iOS doesn't provide it, accept iOS's pattern over building custom — maintenance cost compounds every iOS update. **The repeated failure mode in this codebase was reaching for custom when native would have done.** Established 2026-05-04 after the v2.038 custom-drawer-flash (12+ iterations) and v2.054→v2.061 forehead-bug (10+ iterations) — both vanished the moment we used the native equivalent.

1. **Each tab owns one verb.** Find = explore · Learn = understand · Decks = build · Collection = own · Purchase = acquire. Verb collision = structural bug; resolve before adding.

2. **Navigation depth ≤ 2 inside a tab.** Tab → list → detail. Anything deeper = Russian-doll navigation; the user loses orientation. A would-be third level is actually a parallel filter axis (§6) or belongs in a different tab.

3. **Search is the universal navigator.** Find uses `Tab(role: .search)`; other tabs get `.searchable` over their domain. >~50 items: search beats taxonomy. Filters become tokens, not nav levels.

4. **Density comes from removing chrome.** Three weights × two sizes = six hierarchy levels with zero added pixels. Every divider/shadow/badge/chip removed = remaining info reads denser. (Tufte / Things 3 / Reeder lineage.)

5. **Liquid Glass = navigation only.** Card grid never gets `.glassEffect()`. Tab bar / toolbar / sheets / floating overlays do. One glass per stacking context. ([WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/), [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass))

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
One glass per stacking context. Glass cannot sample other glass; layered glass produces muddy backdrops and fails WCAG AA. Use `GlassEffectContainer` for ≥2 co-located glass elements. List rows / cards / content get NO glass — ever. ([conorluddy/LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference))

### 3.6 Settings dump (every config knob visible at once)
Progressive disclosure. `Form` + `Section` + `DisclosureGroup`. Default advanced collapsed; lead with the 3 most-changed.

### 3.7 NavigationLink on settings-style rows
A row that looks like a push but is actually a picker destroys chevron trust. Use `Picker(_:selection:)` inline or `Menu` — never a fake push.

### 3.8 Action tabs (`+`, `Scan`, `Buy` as a tab)
We don't do this. Find rendered larger than peers is **size differentiation, not an action tab** — it's still a navigation destination. ([Hanin on iOS 26 tab bar anti-patterns](https://medium.com/design-bootcamp/dont-design-junk-in-the-new-ios-26-tab-bar-4de8e842da89))

### 3.9 Equal-weight horizontal scroll bars
Horizontal scroll hides content below the fold and doesn't paginate predictably. Use vertical list (`Form` / `LazyVGrid`), `Menu`, or sidebar on iPad. Reserve horizontal scroll for genuinely-content shelves (featured cards, recently-viewed).

### 3.10 Custom presentation backgrounds on sheets
Strip every `.presentationBackground` modifier. Let the system apply inset Liquid Glass. ([WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/))

### 3.11 Hand-rolled scroll-edge fade overlays
Use `.scrollEdgeEffectStyle(.soft|.hard, for: .top)` — iOS 26 native. `.hard` for dense scrolls (card grids), `.soft` for reading content.

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

1. **Glass = navigation chrome only.** Tab bar, toolbar, sheets, floating overlays, FABs. Lists, cards, content — never. ([WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/))
2. **One glass per stacking context.** Glass cannot sample glass. For ≥2 co-located, wrap in `GlassEffectContainer`. ([conorluddy/LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference))
3. **Variants mutually exclusive.** `.regular` (default) · `.clear` (only when bg is media-rich, dim doesn't hurt, fg is bold+bright) · `.identity` (toggle off without layout shift).
4. **Tinting = primary action only.** Save button gets a tint; deck name field doesn't.
5. **Strip custom presentation backgrounds.** Sheets get inset Liquid Glass automatically. ([WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/))
6. **`scrollEdgeEffectStyle(.hard)` for dense scrolls** (Find / Decks pool / Collection grids — Calendar is the canonical reference). `.soft` for reading. ([createwithswift](https://www.createwithswift.com/define-the-scroll-edge-effect-style-of-a-scroll-view-for-liquid-glass/))
7. **Never hard-code glass opacity.** Test all chrome at every iOS 26.1+ Tinted Mode setting; bottom-row grid cells must remain readable when tab bar is near-opaque.
8. **Test Reduce Transparency / Reduce Motion / Increase Contrast on.** iOS auto-adjusts; don't override — verify content survives.
9. **Glass over uncontrolled bg (card art) requires `.tint()`** anchored against dominant hue. Without it, material reads muddy.
10. **Don't animate glass during scroll.** Restrict morphs to discrete state changes.

---

## 6. Search-first IA

iOS 26's `Tab(role: .search)` + `.searchable` are the center of every dense view.

1. **Find = `Tab(role: .search)`** (full-screen expansion, tab bar minimizes during search). Don't use plain `.searchable` at the top of a regular tab. ([WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/), [nilcoalescing](https://nilcoalescing.com/blog/SwiftUISearchEnhancementsIniOSAndiPadOS26/))
2. **Every other tab `.searchable` over its own domain.** Decks = decks + pool. Learn = articles + glossary. Collection = owned cards. Purchase = stores + breaks.
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

While a session is open, `.tabViewBottomAccessory` shows *"Scanning · 7 cards · tap to review"* across tab switches ([Donny Wals on TabView accessory](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)).

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

**Decks on iPad is canonical:** 3-column `NavigationSplitView` (saved decks | pool | current deck w/ stats+legality+rules inline). Same verb, same components; different spatial arrangement.

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

Applies to Find / Decks pool / Collection / Learn cell taps and the Decks summary-pill → editor zoom. Not a content choice — a screen-size constraint.

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

`HintsManager` + `HintBanner` per DECISIONS.md #031.

**Use:** non-obvious behavior the design itself can't cleanly carry (e.g., bonus play ceiling at count ≥7).
**Don't use:** to compensate for confusing UI — fix the UI instead.

**Visual:** cyan accent, X-dismiss-permanent, distinct from `ContentUnavailableView` (structural, no dismiss) and `BOBAErrorBanner` (orange, attention). Profile has global silence + reset.

**No cascades.** One hint per surface at a time. Hints teach a tip on a known surface; walkthroughs (§6.10) teach a brand-new surface.

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

Scripts live in `BOBAPlaybook/Components/BOBAWalkthrough.swift` (the `extension BOBAWalkthrough.Script` block). **The code is the source of truth.** A script that exceeds 12 words/step or 5 steps signals either a wrong anchor or a too-complex feature.

---

## 7. Forward-compatibility (iOS 27 ready)

Bloomberg/Gurman April 2026 — iOS 27 (WWDC 2026 June 8) focuses on Siri overhaul, Apple Intelligence integration, Liquid Glass refinement (opacity slider), AI photo editing. **No navigation paradigm shift expected.** ([Bloomberg](https://www.bloomberg.com/news/newsletters/2026-04-19/apple-ios-27-siri-interface-ios-27-details-mac-studio-touch-macbook-release-mo5u23o7))

Rules to inherit iOS 27 gains automatically:

1. **Every primary action is an `AppIntent`** — Spotlight / Siri / Action Button / Shortcuts / iOS 27 Siri all consume them. ([Apple docs](https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence))
2. **Content has stable IDs.** Cards have `bobaId`, decks have UUIDs. Learn articles need slug IDs (`setup.match-flow`) for AI summaries / deep links.
3. **Search is central** (§6) — only way to inherit future natural-language search without rewriting IA.
4. **Don't hard-code glass opacity** — Tinted Mode slider exists (iOS 26.1+), expanding in 27.
5. **Don't predict iOS 27 specifics.** Build clean to iOS 26; inherit refinements when they ship.

---

## 8. Per-tab IA recipes

This is the binding redesign target. Every existing tab gets refactored
to match. New tabs (if any) follow the same pattern templates.

### 8.1 Find — the explorer

**Verb:** explore. Absorbs the prior Browse-in-Learn verb collision.

**Pattern:** `Tab(role: .search)` with full-screen search expansion.

**Anatomy:**
- **No-search state:** featured ribbons (Heroes by Weapon, Athletes by Sport, Recently Added, Coaching Staff, Saved Searches). Horizontal scrolls of `BOBACardCell`.
- **Search active:** tab bar minimizes, field takes canvas. Tokens (hero/element/treatment/cost/format/set). Optional scopes (Cards/Heroes/Featured).
- **Grid:** uniform `BOBACardCell`, 3 cols, `.scrollEdgeEffectStyle(.hard, for: .top)`.
- **Tap:** push to `CardDetailView`.
- **Toolbar:** scan trailing, profile leading on collapse.

**Anti-patterns:** filter pills above grid (use tokens). Multiple "browse by" pickers (use scopes).

### 8.2 Learn — the educator

**Verb:** understand. No card details / add actions — those belong in Find. Purely educational.

**Pattern:** `NavigationStack` push from single root list (Music Library pattern).

**Anatomy:**
- **Root:** 5 categories (Rules / Strategy / Collect / Glossary / Tournament) as `BOBASectionRow`. Browse moved to Find.
- **Category → article-list** (short categories push direct to content).
- **Article view:** Rookie / Sub / Playmaker = `searchScopes` scope bar inside the article. NOT a third nav level. Read/Watch is also a scope (only when video exists).
- **`.searchable`** spans whole Learn corpus; `ContentUnavailableView.search` for zero-results.
- **Toolbar:** glossary lookup trailing — inline definition popup.

**Stable IDs:** every article+section gets a slug (`rules.match-flow`, `tournament.scoring.divisions`) for AppIntent / deep links / future AI targeting (§7).

### 8.3 Decks — the builder

**Verb:** *build*. Card pool is contextual to current deck, separate from Find's exploration.

**Pattern (REVISED 2026-05-04):** Music's mini-player + fullScreenCover with hero zoom. Card pool = canvas; current deck = non-draggable summary pill that zooms into full-screen editor on tap. **The Maps-canvas-with-sheet pattern was abandoned after 12+ iterations of fighting custom-drawer flash** — see §1.0 native first. Drag was the problem; tap → zoom-into-editor is the answer.

**Anatomy:**
- **Canvas:** full-screen card pool grid using `BOBACardGridItem`. `.scrollEdgeEffectStyle(.hard, for: .top)`.
- **Summary pill:** non-draggable `DeckSummaryPill` via `.safeAreaInset(edge: .bottom)`. Shows draft name + section breakdown (`8/8 H · 30/30 P · 6 BP · 10/10 HD`) + format badge. Empty: "Build a deck · Tap to open the editor."
- **Pill → editor:** `.fullScreenCover` + `.matchedTransitionSource(id:"deck-draft",in:ns)` paired with `.navigationTransition(.zoom(...))`. Photos-app hero zoom.
- **Editor:** `NavigationStack(path: $editorPath)` — deck header (name + stats), format chip strip, grouped list. Toolbar: Close leading + SAVE/SIGN IN trailing + ⋯ Menu (Manage Decks, Rules, Legality, Clear).
- **Editor secondary surfaces:** Manage Decks / Rules / Legality push as NavigationLinks within the editor's NavigationStack — NOT stacked sheets. Each sheet struct accepts `wrapInNavStack: Bool = true` so it works as sheet OR destination.
- **Pool filter:** native `.searchable(text:tokens:suggestedTokens:placement:.navigationBarDrawer(.always))` with `BOBAFilterToken` (weapon/cost/hero). Tap bar → suggested tokens.
- **Card tap:** NavigationLink push to detail + zoom (§8.6). **Long-press:** adds to draft (canonical add gesture).
- **Pool toolbar:** wordmark principal + ⋯ Menu (1/2/3 columns, Scan, walkthrough). NO Save on pool — Save lives in editor.
- **Grid density:** `@AppStorage("bp_decksGridColumns_v1")` defaults 3. 1/2-across pulls full-size images.
- **Empty state:** template gallery in editor.
- **Scan:** lives in pool ⋯ Menu; results land in active draft via scanStore queue.

**Anti-patterns:** custom/draggable drawer (iOS 26 has no native one that keeps tab bar visible — use fullScreenCover-from-pill OR standard `.sheet + .presentationDetents` that hides tab bar). Quick-add toggle. Per-tab status banner. Sheets stacked on editor (push as NavigationDestination instead). At most one sheet at a time.

### 8.4 Collection — the owner

**Verb:** *own*. Owned cards + designations + display modes + sharing. Public-facing dimension is first-class, not afterthought.

**Pattern (REVISED 2026-05-04 — Music Library shape):** Root = **My Cards** (owned cards by designation). Rainbow Progress + My Shows push from toolbar ⋯ Menu, NOT a top-level mode picker (the prior 5-row chrome stack was the anti-pattern this overhaul killed).

**Anatomy:**
- **Root grid:** owned cards using `BOBACardGridItem` (§11.1).
- **Designation segmented Picker:** Personal / Sale / Trade / Wanted / Grails via `Designation.shortDisplayName` — fits one row per §3.9.
- **`.searchable`** with `.navigationBarDrawer(.always)` — composes with filter + designation scope.
- **Display mode picker** (toolbar ⋯ Menu): List (compact rows + value + edit chip) / Grid (visual scan) / Wall (tile-able share image).
- **Grid density:** when mode=grid, Menu adds 1/2/3 column picker via `@AppStorage("bp_collectionGridColumns_v1")`. 1/2-across pulls full-size images.
- **Other lenses** (toolbar ⋯ Menu): Rainbow Progress (push, own chrome — no designation/display/search competing); My Shows (streamer-only push to `ShowsListView`).
- **Designation badge** on each cell (corner overlay) so multi-designation cards scan across scopes.
- **Tap card:** NavigationLink push to `CollectionCardDetailView` via parent `navigationPath`; hero zoom per §8.6.
- **Scan invocation:** toolbar button → brief "Add to which designation?" sheet (defaults Personal, remembers last) → routes via §6.5.
- **Share invocation:** iOS share sheet with deep link + Wall image of current scope. Deep link = `bobaplaybook.com/u/{username}/{designation}` (Universal Link to iOS, web fallback). Per-designation public/private set in Profile.
- **Profile** is Find-only. Collection's auth surfaces are inline `BOBASignInPrompt` rows.
- **Value summary header:** single line, no decoration. Total + designation breakdown; tap → value-history chart.

**Wall + Streamer reconciliation.** Wall is a display mode for every collector (per DECISIONS.md #036). Whatnot "My Shows" stays streamer-gated; Wall rendering generalizes.

**Public web fallback.** `bobaplaybook.com/u/ben/grails` renders the same wall in-browser, no sign-in required for public designations. Same designation scopes + public/private toggle.

### 8.5 Purchase — the acquirer

**Verb:** *acquire*. Upcoming breaks + find-a-store.

**Pattern:** segmented picker (`Picker(.segmented)`) at the top — 2
options is within the ≤4 segmented limit.

**Anatomy:**
- **Top:** segmented picker — "Upcoming Breaks" | "Find a Store".
- **Upcoming Breaks:** vertical list of large card tiles (host, time,
  viewer count). Tap → deep link to Whatnot.
- **Find a Store:** MapKit map with annotations + bottom sheet with
  store list (Apple Maps pattern). `[.height(120), .medium, .large]`
  detents.
- **Toolbar:** filters Menu (radius, indie-only toggle).

---

### 8.6 Card detail surface — the universal card view

Pushed from Find, Decks (pool tap), Collection (cell tap). Three structs (`CardDetailView`, `BrowserCardDetailSheet`, `CollectionCardDetailView`) share artPanel + toolbar verbatim — only body content below differs.

**Pattern:** Music-style hero zoom into NavigationLink-pushed view (NOT sheet). Source uses `.matchedTransitionSource(id:in:)` as OUTERMOST modifier; destination uses `.navigationTransition(.zoom(sourceID:in:))`.

**Canonical artPanel + toolbar** live verbatim in `BOBAPlaybook/Views/CardDetailView.swift`. Modifier ORDER: `.scrollEdgeEffectStyle(.soft, for: .top)` BEFORE `.background`. After-background doesn't register on the underlying ScrollView. **All three detail structs share these blocks — drift is the bug.**

**Wrap-in-NavStack pattern:** each struct takes `wrapInNavStack: Bool = true`. Default true for sheet usage; push usage passes false so parent NavigationStack provides chrome (avoids nested-stack back-button conflict). Done button conditional on sheet mode.

**Anatomy (body below artPanel):** Stats grid (canonical 6-cell per DECISIONS.md #029) → Cost+DBS (Plays only) → Pricing panels (§8.7) → Per-context body (Collection: copies/decks/variations; Decks: Add/Remove CTA; Find: Add menu in toolbar).

**Toolbar action bar by context:**

| Entry | Trailing items |
|---|---|
| Find | Add menu (Collection/Deck/Show) + Mod-edit (mods) + Share |
| Decks tap | Add to Deck CTA in body |
| Collection tap | Edit Designation + Add menu in body |

Canonical verbs: `Add to Collection`, `Add to Deck`, `Share`, `Edit Designation`.

**Anti-patterns:** per-surface artPanel variants (one shape). Per-surface toolbar accumulation from forehead-iteration guesses (stick to canonical setup). Sheets for drill-in (Manage/Rules/Legality push instead). Prev/next chevrons in bottom toolbar (removed; they cluttered).

**Hero zoom rules:**

| Where | What |
|---|---|
| Source | `.matchedTransitionSource(id:, in:)` as OUTERMOST modifier |
| Destination | `.navigationTransition(.zoom(sourceID:, in:))` |
| Namespace | One `@Namespace` per parent, shared source↔destination |
| Push | NavigationLink or `path.append(_)` + `.navigationDestination(for:)` |
| ID | `card.id` for Find/Decks, `bobaId: String` for Collection |

**"nil view" warning** = iOS couldn't find matching source ID = fallback transition (parent nav bar inherits, content overlays as extended header). Causes: matchedTransitionSource on INNER view wrapped by Button/overlay/modifier (fix: apply as outermost), or applied INSIDE a function-returning-view (fix: apply at call site as outermost on the function result).

---

### 8.7 Pricing panels — Buy Now + Sold history

Lives inside `CardDetailView`. Live-fetched per DECISIONS.md #013; COMC asking stays OUT of sold-comp waterfall per #034 (asking inflates 10-25%).

**Two sections, top to bottom:**

1. **Buy Now** (asking — where to buy now): eBay active listings + COMC asking with *"COMC asking · Ungraded NM"* pill. Soft-fail COMC silently when Worker returns `challenged: true` or `count: 0`.
2. **Sold history** (transacted — what's it worth): Radish recent (preferred TCG comps) + eBay sold (fallback). Market est = Radish-first waterfall.

**Per-section:** horizontal scroll of price tiles (thumb + price + source pill + tap-through). Empty = section-local `ContentUnavailableView` w/ refresh. Loading = 3-tile skeleton, not spinner.

**Market estimate header** (single line above sections): *"~$24 · based on 8 recent sales (Radish + eBay)"*. Basis exposed for audit; asking NEVER folded in.

**Cached value:** `user_cards.estimated_value` for Collection value-summary; grid doesn't re-fetch live.

**Anti-patterns:** asking+sold combined (inflation). One source when both available. Sources hidden behind disclosure — provenance is the trust mechanism.

---

### 8.8 Wall view + Price Overlay — display & share for everyone

Both lifted from streamer-only gate per DECISIONS.md #036.

#### Wall view

**Purpose:** render N cards as a single shareable image (bragging, sale lists, trade lists, deck composition, teaching).

**Invocation:** Collection display-mode picker (§8.4); Decks ⋯ Menu ("Generate deck wall"); Find multi-select ("Wall these N cards").

**Anatomy:** full-screen small-multiples grid (`BOBACardCell`, near-black bg). Inline-editable title strip. Toolbar: Save / Share / Copy / aspect picker (iPhone wallpaper 9:19.5, IG square 1:1, web 16:9, iPad 3:4) / Price Overlay toggle. Default aspect = source-context (Collection→IG square, Deck→16:9). **Honors current scope** — never re-filter inside Wall.

#### Price Overlay

**Purpose:** price chips on card images for sale/trade communication.

**Invocation:** toggle in Wall view toolbar only. Never during browsing — sharing affordance, not display.

**Chip anatomy:** lower-third inset, source pill (eBay / COMC / Radish / Custom) + price. Default source = lowest-asking; toggle to "My price" (`user_cards.estimated_value` or per-card override). Glass with `.tint()` per §5. Optional condition chip (NM/EX/GD) for Sale/Trade.

**Per-designation defaults:** For Sale = ON / My price · For Trade = ON / market est · Grails/Personal = OFF · Wanted = ON / market est / "WTB" prefix.

---

## 9. The redesign roadmap

Original 30-item roadmap is substantially complete (all tab rebuilds shipped, walkthroughs landed, Liquid Glass adopted, scan unified, Wall+Overlay un-gated). Historical roadmap preserved in git at v2.072. Open work tracked in [SCRATCHPAD.md](./SCRATCHPAD.md) — per-feature one-offs at this stage.

---

## 10. The daily review test

Before any feature ships:

1. **Gruber (§4.6):** could a competent designer recreate this screen from a one-paragraph description? If no, decoration — strip.
2. **Verb (§1.1):** what verb does this own? Colliding with another tab's verb? Structural bug; resolve first.
3. **Depth (§1.2):** count nav levels from tab root. If >2, the third should be a scope, sheet, or different tab.

When answer is "no" or "I'm not sure," reread the relevant section. When the doc is silent or contradicts itself, the doc is wrong — propose an edit before proceeding.

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

**Element (content semantic only):** FIRE `#FF4D00` · ICE `#00BFFF` · STEEL `#8A9BB0` · BRAWL `#C0392B` · GLOW `#FFD700` · HEX `#8B00FF` · GUM `#FF69B4` · SUPER `#FF00FF` · NONE `#666680`.

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

**Add an entry when intentionally not-designed.** Remove when it comes into scope and gets designed elsewhere — don't leave stale "future" markers.

---

## 13. References

Sources cited inline above:

- [Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Apple AppIntents — Integrating actions with Siri](https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence)
- [Apple HIG — Materials / Search / Sheets / Sidebars / Tab Bars / Toolbars](https://developer.apple.com/design/human-interface-guidelines/) (root)
- [Bloomberg / Gurman — iOS 27 Siri overhaul](https://www.bloomberg.com/news/newsletters/2026-04-19/apple-ios-27-siri-interface-ios-27-details-mac-studio-touch-macbook-release-mo5u23o7)
- [conorluddy — Liquid Glass Reference (verbatim HIG)](https://github.com/conorluddy/LiquidGlassReference)
- [createwithswift — `scrollEdgeEffectStyle`](https://www.createwithswift.com/define-the-scroll-edge-effect-style-of-a-scroll-view-for-liquid-glass/)
- [Donny Wals — iOS 26 tab bars](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)
- [Hanin — Don't Design Junk in the iOS 26 Tab Bar](https://medium.com/design-bootcamp/dont-design-junk-in-the-new-ios-26-tab-bar-4de8e842da89)
- [nilcoalescing — SwiftUI search enhancements iOS 26](https://nilcoalescing.com/blog/SwiftUISearchEnhancementsIniOSAndiPadOS26/)
- [WWDC25 219 — Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25 323 — Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
