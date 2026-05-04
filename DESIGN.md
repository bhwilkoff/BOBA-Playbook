# BOBA Playbook — Design Theory

> **This document is binding.** Every new view, screen, sheet, button, and
> filter row in the iOS app must trace its design back to a rule in this
> document. When something feels overwhelming or inconsistent, the failure
> is here, not in the feature — fix the document, then fix the feature.
>
> Companion to [`CLAUDE.md`](./CLAUDE.md) (project context) and
> [`DECISIONS.md`](./DECISIONS.md) (architecture log). Reference but do not
> duplicate either.

---

## 0. How to use this document

**Ben's job:** when a UI choice in a session contradicts a rule here, point
at the rule. Don't accept "I added a sub-section to Learn for the new
content" — point at §3 anti-pattern #1 and §8 Learn recipe.

**Claude's job:** before proposing any new view, sheet, filter, picker,
nav level, or toolbar item, read the relevant section of this document
and quote the rule that justifies the choice. If no rule fits, the
proposal needs a new rule (and a discussion) before it ships.

**Living document.** Sections 5–7 follow Apple platform changes; update
when iOS 27 ships (WWDC 2026, June 8, 2026 keynote). Sections 1–4 are
principles and shouldn't change.

---

## 1. The six binding principles

0. **Native first.** Every interaction should be a built-in iOS API
   before it is custom code. `.searchable` before custom search bars.
   `.navigationTransition(.zoom)` before custom modal animation.
   `.fullScreenCover` + `.matchedTransitionSource` before custom
   drawers. `Tab(role: .search)` before custom bottom-anchored search
   pills. If iOS doesn't provide what you want, accept iOS's pattern
   over building custom — the maintenance cost of a custom component
   compounds with every iOS update. **The repeated pattern that
   broke things in this codebase was reaching for custom when native
   would have done.** When a feature is hard to build natively,
   first ask: *am I trying to do something iOS isn't supposed to do?*
   Established 2026-05-04 after the v2.038 custom-drawer-flash
   debacle (12+ iterations) and the v2.054→v2.061 forehead-bug
   debacle (10+ iterations). Both bugs vanished the moment we
   stopped recreating iOS components and used the native equivalent.

1. **Each tab owns one verb.** Find = explore. Learn = understand. Decks
   = build. Collection = own. Purchase = acquire. A feature with a verb
   collision (e.g., "explore cards" in two tabs) is a structural bug, not
   a feature request — resolve the collision before adding the feature.

2. **Navigation depth ≤ 2 inside a tab.** Tab → list → detail. Anything
   deeper is "Russian doll navigation" and the user loses orientation. If
   the content seems to need a third level, it's actually a parallel
   filter axis (see §6) or it belongs in a different tab.

3. **Search is the universal navigator.** Find uses the iOS 26
   `Tab(role: .search)` pattern. Every other tab gets `.searchable` over
   its own domain. When the catalog crosses ~50 items, search beats any
   taxonomy. Filters become search tokens, not nav levels.

4. **Density comes from removing chrome, not adding affordances.** Three
   typography weights × two sizes = six hierarchy levels with zero added
   pixels. Every divider, shadow, badge, and chip you remove makes the
   remaining info read denser. This is the Tufte / Things 3 / Reeder
   lineage.

5. **Liquid Glass is for navigation only — content stays unglassed.**
   The card grid never gets `.glassEffect()`. The tab bar, toolbar,
   sheets, and floating overlays do. One glass surface per stacking
   context. ([WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/),
   ["Adopting Liquid Glass"](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass))

---

## 2. The IA decision tree

For any new feature, walk these in order. Stop at the first match.

| Question | If yes, use | If no |
|---|---|---|
| Is this a top-level mode of the entire app? | **Tab** (only if total tab count stays ≤5) | next |
| Is this a hierarchical drill-down with one path in, one back? | **NavigationStack push** (max depth 2 inside the tab) | next |
| Is this a parallel filter/view over the same data (Rookie/Sub/Playmaker over rules content)? | **`searchScopes` or scope bar inside the destination view** — NOT a third nav level | next |
| Is this a contextual action that needs full focus and might be abandoned? | **Sheet with `presentationDetents([.large])`** | next |
| Is this a glance-and-return action (filters, quick edit)? | **Sheet with `presentationDetents([.height(N), .medium])`** + drag indicator | next |
| Is this a side panel showing properties of the current selection (iPad-relevant)? | **`.inspector()`** — accept that on iPhone it collapses to a sheet, and only use it if iPad parity is genuinely worth the complexity | next |
| Is this a destructive or one-shot config (delete, reset, set theme)? | **Toolbar `Menu`** with leading-icon disclosure (iOS 26 menu style) | next |
| Is this global app state that follows the user across screens (active scan, deck draft, mini-player)? | **`.tabViewBottomAccessory`** (see §6.5 cross-cutting capabilities) ([Donny Wals on TabView accessory](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)) | next |
| Is this a verb that needs to work in ≥2 tabs (scan, share, profile)? | **Cross-cutting capability — see §6.5.** Single implementation, invoked from any tab, destination set by context. | next |
| None of the above — it's an inline option | **Inline control** (Toggle, Picker, Stepper) inside a `Form` `Section` | — |

**If you reach the bottom without a match, you don't need a new view —
you need to fold the feature into an existing one.** That's almost
always the right answer.

---

## 3. Anti-patterns we reject

Each one with a concrete current-code example so we know what to refactor.

### 3.1 Russian-doll navigation (depth > 2)
*Example:* `LearnView` → Read/Watch toggle → 6-section picker → (for
Rules) Rookie/Substitution/Playmaker mode picker → article. That's
depth 4. Users lose orientation by depth 3.
**Fix:** collapse middle layers. Read/Watch becomes scope bar inside
articles; Rookie/Sub/Playmaker becomes scope bar inside the article.
Root list of 5 categories pushes once to article. Done.

### 3.2 Pill-bar pile-up (multiple horizontal scrolling rows of equal-weight chips)
*Example:* `DeckBuilderView` has format / totals / filter1 / filter2 /
search-and-scan = 5 horizontal rows. The eye can't tell which row
controls which axis.
**Fix:** at most ONE persistent filter row. Everything else moves to
`.searchable` tokens, a `Menu`, or a sheet. Format gets a single
prominent picker; totals become a header summary; filters become
search tokens; search and scan are toolbar items.

### 3.3 Tab-inside-tab (segmented control at top of a tab that switches sub-modes)
*Example:* the Read/Watch toggle in `LearnView` is functionally a
second tab bar. Users can't tell whether the back gesture leaves the
inner tab or the outer one.
**Fix:** if you need a second tab bar, you actually need a different
top-level tab OR a `searchScopes` over a single content stream. Read
vs. Watch is one content stream filtered by media type — make it a
scope, not a mode.

### 3.4 Modal-on-modal
*Example:* `DeckBuilderView` → `DeckManagementSheet` (Save/Load/Share
tabs) → CSV import file picker → result alert. Three modal layers.
**Fix:** within a sheet, push with an internal `NavigationStack` to
preserve the dismissal contract. Save / Load / Share become three
toolbar `Menu` actions, each opening at most one sheet.

### 3.5 Glass-on-glass-on-glass
*Example:* applying `.glassEffect()` to every floating element
(toolbar items, FABs, badges, list rows). Glass cannot sample other
glass; layered glass produces muddy backdrops and fails WCAG AA.
**Fix:** one glass per stacking context. Use `GlassEffectContainer`
to share a sampling region when ≥2 glass elements are visually
co-located. List rows / cards / content get NO glass —
ever. ([conorluddy/LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference))

### 3.6 Settings dump (every config knob visible at once)
*Example:* `DeckBuilderView`'s deck rules editor is a separate full
modal with ~20 toggles. Coaches see all 20 at once and freeze.
**Fix:** progressive disclosure. `Form` with `Section`s using
`DisclosureGroup`. Default the advanced ones collapsed. Lead with
the 3 most-changed.

### 3.7 NavigationLink on settings-style rows
*Example:* a row that looks like a push (chevron, arrow) but is
actually a one-shot picker. Users learn to distrust chevrons.
**Fix:** use `Picker(_:selection:)` inline, or `Menu` for the
selector — never a fake push.

### 3.8 Action tabs (`+`, `Scan`, `Buy` as a tab)
We don't currently do this and we won't start. The current Find tab
being rendered larger than peers is **size differentiation, not an
action tab** — it's still a navigation destination. ([Hanin on
iOS 26 tab bar anti-patterns](https://medium.com/design-bootcamp/dont-design-junk-in-the-new-ios-26-tab-bar-4de8e842da89))

### 3.9 Equal-weight horizontal scroll bars
*Example:* the section picker in `LearnView` (6 horizontally-scrolling
chips) and several filter rows in `DeckBuilderView`. Horizontal
scroll hides content below the fold and doesn't paginate predictably.
**Fix:** vertical list (`Form` / `LazyVGrid`), `Menu`, or a sidebar
on iPad. Reserve horizontal scroll for genuinely-content shelves
(featured cards, recently-viewed) where the row metaphor is the point.

### 3.10 Custom presentation backgrounds on sheets
*Example:* anywhere we set `.presentationBackground(.regularMaterial)`
or `.background(BOBAColor)` on a sheet. This fights iOS 26's automatic
Liquid Glass treatment.
**Fix:** strip every `.presentationBackground` modifier. Let the
system apply inset Liquid Glass. ([WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/))

### 3.11 Hand-rolled scroll-edge fade overlays
*Example:* gradient `LinearGradient` overlays at the top of scroll
regions to fake a content-fades-under-chrome effect.
**Fix:** use `.scrollEdgeEffectStyle(.soft|.hard, for: .top)` —
iOS 26 native API. Use `.hard` for dense scrolls (card grids), `.soft`
for reading content.

---

## 4. Density rules

These enforce principle #4. Each is testable in code review.

1. **No `.background(Color.gray.opacity(0.1))` on lists or cards.** If a
   row needs separation from its neighbor, use a `Divider()` or a unit
   of vertical spacing. If it needs separation from its container, the
   container needs Liquid Glass — not a tinted box.

2. **Three weights × two sizes = six hierarchy levels.** Use Bebas Neue
   / Russo One bold for level 1 (page title), Chakra Petch semibold for
   level 2 (section header), Chakra Petch regular at smaller size for
   level 3 (body), Chakra Petch regular at small size for level 4
   (caption), Chakra Petch light for level 5 (de-emphasis), and
   Chakra Petch monospace for tabular data. Refuse the urge to add a
   seventh level — refactor instead.

3. **Small multiples.** Every card cell in every grid in the app must
   share the same shape (aspect, padding, badge placement). The eye
   scans content when the frame is invariant. The moment one cell is
   bigger or shaped differently, scanning breaks. The single canonical
   `BOBACardCell` should be used everywhere — Find, Decks, Collection,
   Learn (if it ever shows cards again).

4. **Show the data; let the user filter it.** A persistent search field
   (or `Tab(role: .search)`) is denser than a category picker because
   it's zero-overhead access to everything. Reach for filters before
   reaching for nav levels.

5. **Progressive disclosure must be predictable.** A disclosure triangle
   that always works the same way (Settings, Reminders subtasks) adds
   density without overwhelm. A disclosure widget that *sometimes* opens
   inline and *sometimes* pushes destroys it. Use `DisclosureGroup` for
   inline, `NavigationLink` for push, never overload the meaning.

6. **The Gruber test (run before merging any new view).** *"Could a
   competent designer recreate this screen from a one-paragraph
   description?"* If yes, the screen is coherent. If no, you've added
   decoration. Strip and rebuild.

---

## 5. Liquid Glass usage rules (iOS 26)

Each rule cites the source so it can be revisited when iOS 27 ships.

1. **Glass = navigation chrome only.** Tab bar, toolbar, sheets, floating
   overlays, FABs. Lists, tables, card grids, media — never. ([WWDC25
   219 "Meet Liquid Glass"](https://developer.apple.com/videos/play/wwdc2025/219/))

2. **One glass per stacking context.** Glass cannot sample other glass.
   For ≥2 co-located glass elements, wrap in a single
   `GlassEffectContainer` so they share one sampling region.
   ([conorluddy/LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference))

3. **Three glass variants are mutually exclusive.**
   - `.regular` — default, adaptive, all backgrounds
   - `.clear` — only when ALL three: media-rich background, dimming
     layer doesn't hurt content, foreground is bold and bright
   - `.identity` — toggle off without layout shift (animation pivot)

4. **Tinting = primary action only.** Convey semantic meaning (this is
   the call-to-action), never decoration. The Save button on Decks gets
   a tint. The deck name field doesn't.

5. **Strip custom presentation backgrounds.** Sheets get the new
   inset-Liquid-Glass treatment automatically — only when you don't
   override it. ([WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/))

6. **`scrollEdgeEffectStyle(.hard, for: .top)` for dense scrolls.** Apple
   uses `.hard` for Calendar (the canonical high-density UI). Use it for
   the Find card grid, Decks card pool, Collection grid. Use `.soft` for
   Learn articles where reading flow matters more than dividing line.
   ([createwithswift on scroll edge styles](https://www.createwithswift.com/define-the-scroll-edge-effect-style-of-a-scroll-view-for-liquid-glass/))

7. **Respect user opacity (iOS 26.1+ Tinted Mode slider).** Never
   hard-code glass opacity. Test the card grid + tab bar at every
   Tinted Mode setting — at maximum opacity the tab bar will be
   near-opaque and overlap with the bottom row of card grid cells must
   remain readable. Bloomberg reports iOS 27 will give users even more
   control. ([Bloomberg / Gurman April 2026](https://www.bloomberg.com/news/newsletters/2026-04-19/apple-ios-27-siri-interface-ios-27-details-mac-studio-touch-macbook-release-mo5u23o7))

8. **Test with Reduce Transparency, Reduce Motion, Increase Contrast
   enabled.** iOS auto-adjusts: Reduce Transparency increases frosting,
   Increase Contrast adds borders, Reduce Motion disables elastic
   effects. Don't override; verify our content survives the auto-treatment.

9. **Glass over uncontrolled background (card art) requires `.tint()`
   that anchors against dominant hue.** Without a tint, the material
   reads muddy over busy art.

10. **Don't animate glass during scroll.** The morph is GPU-cheap but
    visually competes with the user's scroll-tracking. Restrict morphs
    to discrete state changes (button → sheet, toolbar item appears).

---

## 6. Search-first IA

Search is the universal navigator. iOS 26's `Tab(role: .search)` and
`.searchable` modifier are the center of every dense view.

1. **Find tab uses `Tab(role: .search)`.** This is the iOS 26 dedicated
   search pattern — full-screen search expansion when active, the tab
   bar minimizes during search, results take the canvas. Don't put a
   `.searchable` field at the top of a regular Find tab; promote it to
   the search role. ([WWDC25 323](https://developer.apple.com/videos/play/wwdc2025/323/),
   [nilcoalescing on iOS 26 search](https://nilcoalescing.com/blog/SwiftUISearchEnhancementsIniOSAndiPadOS26/))

2. **Every other tab gets `.searchable` over its own domain.** Decks tab
   searches decks + cards-in-pool. Learn tab searches articles +
   glossary. Collection tab searches owned cards. Purchase tab searches
   stores + upcoming breaks. Each scope is "the thing this tab owns."

3. **Use `searchScopes(_:activation:_:)` for orthogonal axes.** When the
   user might be searching across two ontologies (cards vs. heroes vs.
   decks), expose a scope bar that appears only when the search field is
   active.

4. **Use search tokens for filter narrowing.** Tokens are passed as
   `Binding<[T]>` where `T: Identifiable`. For BOBA: a `BOBAFilterToken`
   enum case for hero, element, treatment, cost, format, set. The user
   types and accepts a token; it appears as a chip in the search field;
   results narrow. Replaces every "filter pill" row currently in the
   Decks builder.

5. **Use `searchSuggestions` to complete partial queries.** When the user
   types "MAVE", suggest "Maverick" with the hero icon. When they type
   "RBF-", suggest "RBF-72 Maverick (Red Battlefoil)".

6. **Always ship `ContentUnavailableView.search` for zero-result
   states.** Generic "No results" is not enough; suggest a refinement
   ("Try removing the Cost filter").

7. **Wire search through `AppIntent`** so iOS 27's natural-language
   layer (and Spotlight, Siri) inherit it for free. (See §7.)

---

## 6.5 Cross-cutting capabilities

Some verbs operate across multiple tabs. They share **one** implementation,
**one** active-state UI, and route by invocation context. The pattern:
*invoke from any tab; the destination is set by context; active state
lives in `.tabViewBottomAccessory` so the user never loses it across tab
switches.*

This is distinct from §1.1's "each tab owns one verb." Tabs own
**primary** verbs (explore, understand, build, own, acquire). Cross-cutting
capabilities are **sub-verbs** (scan, share, sign-in) that serve whichever
primary verb the user is currently inside. Same implementation, contextual
destination — no verb collision.

### Scanning — the canonical example

The scan capability appears in Find, Decks, and Collection. There is
**one** `ScanStore` (queue), **one** `ScanView` (live single-card),
**one** `GridScanView` (multi-card still), and **one** queue review UI.
The invoking tab sets two parameters: *destination* and *default action
on capture*.

| Invoking tab | Destination | Default action on capture | Queue review |
|---|---|---|---|
| **Find** | identify only | hold in queue | tap each → push to `CardDetailView` |
| **Decks** | current deck | add immediately | post-capture review (remove duplicates, confirm format-legality) |
| **Collection** | a designation chosen at session start | add immediately to that designation | post-capture review (change designation per card if needed) |

While a scan session is open, `.tabViewBottomAccessory` shows a
persistent strip — *"Scanning · 7 cards captured · tap to review"* —
that follows the user across tabs. The user can switch to Decks
mid-scan to look up a rule or to Find to compare prices, then return
without losing state. This is the iOS 26 native treatment for in-progress
global state ([Donny Wals on TabView accessory](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)).

**Anti-pattern (currently in code):** separate scan-button-and-routing
implementations per tab. Find has the scan button in the search bar;
Decks has its own in the toolbar; both invoke ScanView with their own
state plumbing. Consolidate to a single invocation API:
`ScanCoordinator.start(destination: .find | .deck(id) | .collection(designation))`.
The button is per-tab toolbar item; the modal is shared.

### Share

Share is a verb that exists wherever there's content worth sharing.
Card detail views, deck detail views, and the entire Collection tab
(per-designation and per-card) all expose a Share affordance. The
implementation is a single iOS share sheet that includes:

- **Deep link** that opens the relevant view in the app, falling back
  to web at `bobaplaybook.com/{type}/{id}` when the app isn't installed
- **Rendered image** — card art for cards, deck thumbnail for decks,
  Wall image for Collection scopes (see §8.4)
- **Plain text** — the card or deck name + summary for quick paste

### Profile / sign-in / authentication

The Profile sheet (sign-in, account, preferences) is invoked from a
single gear icon in the top-leading toolbar position of any tab that
needs auth context — Collection, Decks (Save), Purchase (wishlist). It
is always a sheet, never a nav level. Appears with `.medium` detent for
quick access, expands to `.large` for full account management.

**Auth-required vs. auth-optional.** The app must function fully without
sign-in for every read-only verb: explore in Find, understand in Learn,
build a draft deck in Decks, browse in Collection (returns empty),
acquire in Purchase. Auth is required only for *write to user data*:
Save deck, designate card, edit Profile, manage shows. The pattern:

- **Optional auth** = no prompt. The user can use the feature; result is
  client-only state.
- **Required auth** = inline `BOBASignInPrompt` row at the point of
  action. *"Sign in to save this deck"* with a single Sign In button
  that opens the Profile sheet pre-routed to sign-in. After auth, the
  pending action runs.
- **Never** show a full-screen auth wall on app launch. Never block
  exploration on sign-in.

**Sign in with Apple is preferred.** Email is fallback only — surface it
behind a "More options" disclosure on the auth sheet. Keychain stores
credentials per [DECISIONS.md #007 / iOS Constraints](./DECISIONS.md).

**Deep links + auth.** A shared deep link
(`bobaplaybook.com/u/ben/grails`) opens *without* requiring the
recipient to sign in — public-designation collections render as
read-only walls. Only when the recipient hits a write action (e.g.,
"Save to my Wanted") does an inline sign-in prompt appear.

### When to add a new cross-cutting capability

Three rules:

1. **The verb must be relevant in ≥2 tabs.** A verb that only matters
   in one tab is a tab-specific feature, not cross-cutting.
2. **Active state must benefit from persistence across tabs.** If users
   never need to switch tabs mid-action, no `.tabViewBottomAccessory`
   slot — it's just a tab-specific feature.
3. **The implementation must be a single coordinator + UI.** If you
   find yourself writing per-tab variants, the abstraction is wrong;
   reconsider whether it belongs in §6.5 at all.

---

## 6.6 Per-size-class adaptations

The doc's defaults assume iPhone (compact width). iPad (regular width)
and the unlikely-but-imaginable Mac Catalyst surface need consistent
adaptation rules so we don't ship "iPhone app stretched to iPad."

**The compact → regular adaptation matrix:**

| Pattern (iPhone compact) | iPad regular adaptation |
|---|---|
| `NavigationStack` push | `NavigationSplitView` two-column (sidebar + detail) |
| `Tab(role: .search)` full-screen | Search field always visible in sidebar |
| Bottom sheet with detents (Decks, Maps) | **Trailing column** replacing the sheet — true side panel, not modal |
| `searchScopes` scope bar | Scope rows in sidebar |
| Toolbar `Menu` with disclosure | Inline buttons in toolbar (more horizontal room) |
| Card grid 3 columns | 5–7 columns (`.adaptive(minimum: 140)`) |
| `.tabViewBottomAccessory` | Stays in the same position (auto-adapts in iOS 26) |

**The Decks tab on iPad is the canonical example.** `NavigationSplitView`
with three columns: saved decks list (sidebar) | card pool grid
(canvas) | current deck (trailing column with stats + legality + rules
editor inline). The bottom sheet from §8.3 dissolves into a real panel
because iPad has the screen real estate to keep everything visible.
Same primary verb ("build"); same canonical components; different
spatial arrangement.

**Don't write per-platform forks.** Use SwiftUI's adaptive APIs
(`@Environment(\.horizontalSizeClass)`, `NavigationSplitView` /
`NavigationStack` swap, `.adaptive` LazyVGrid columns). One view
hierarchy that responds to size class, not two parallel hierarchies.

**Mac Catalyst** is not a current target. If we ever ship Catalyst:
sidebar pattern from iPad, plus pointer-aware hover states (`.onHover`),
plus keyboard shortcuts via `.keyboardShortcut(_:)` for primary
actions. Don't design for it now; design *not to preclude it* (avoid
gesture-only interactions for any primary action).

---

## 6.7 Universal states — empty / loading / error / offline

Every list, grid, search, and sheet must define behavior for four
states beyond "happy path." Inconsistent state handling is the most
common source of "this feels janky" feedback.

1. **Loading** — show `ProgressView` only for operations >300ms.
   Anything faster shows nothing (the data appears). Never block UI
   with a full-screen spinner; loading happens *in place*. For initial
   list loads, use a skeleton (3–5 placeholder rows shaped like real
   rows) instead of a spinner — preserves layout, signals what's coming.

2. **Empty** — `ContentUnavailableView` with brand-voice copy and a
   *productive next action*. Bad: "No items." Good: *"No decks yet —
   start with a template or scan a card to begin."* with template
   gallery as actions. Always offer the action that leads out of empty.

3. **Error** — `ContentUnavailableView` with a clear error message,
   distinguishing user-fixable errors (network, auth) from system
   errors (server down). Always include a retry button for transient
   errors. Never silently fail. Errors that occur during a write
   action surface as a banner above the action (`BOBAErrorBanner`),
   not as a navigation interruption.

4. **Offline** — degraded mode, not blocked mode. Cached card catalog
   (CLAUDE.md: static JSON ships in the bundle) means Find / Learn /
   Decks / Collection-browse all work offline. Cloud actions (Save
   deck, sync designations, fetch pricing) disabled with inline
   tooltips. A subtle "Offline" pill appears in the navigation bar
   (top-trailing) when network is unavailable; tap shows what's
   degraded.

**Anti-pattern:** different empty/error styling per tab. Use the
canonical `BOBAEmptyState` and `BOBAErrorBanner` components (§11)
everywhere.

---

## 6.8 First-run hints

Per [DECISIONS.md #031](./DECISIONS.md), the app has a `HintsManager` +
`HintBanner` system for one-shot teaching moments. Codify when to use
it.

**Use a hint when:** the UI implies a behavior that's non-obvious to
a first-run user *and* explaining it via copy in the design itself
would clutter the surface. Example from current code: bonus play
ceiling (deck builder shows tip when count ≥ 7).

**Don't use a hint when:** the behavior should be obvious from
design. If you're writing a hint to compensate for a confusing UI,
fix the UI instead. Hints are for genuinely-non-obvious teaching, not
for design rescue.

**Visual rules:**
- `BOBAHintBanner` has its own visual treatment — distinct from
  `ContentUnavailableView` (no dismiss, structural) and
  `BOBAErrorBanner` (orange, requires attention). Hints are subtle:
  cyan accent, X to dismiss, "Don't show again" implied.
- Always dismissible permanently per device.
- Global silence toggle in Profile (per DECISIONS.md #031).
- Reset hints button in Profile for users who want to revisit.

**No hint cascades.** One hint visible per surface at a time. If two
hints could fire on the same screen, the more important one wins;
the other waits for a future visit.

**See also §6.10 — feature walkthroughs**, which are a different
pattern (anchored, multi-step, fires on first feature open). Hints
are for *one specific tip on an already-known surface*; walkthroughs
are for *teaching a brand-new surface*.

---

## 6.9 Toolbar + app chrome standardization

Every navigation surface inherits these rules so chrome reads as one
app, not five tabs.

1. **Material treatment.** Every view applies
   `.toolbarBackground(.regularMaterial, for: .navigationBar)` +
   `.toolbarBackground(.visible, for: .navigationBar)` (CLAUDE.md
   convention). The iOS 26 Liquid Glass treatment is what `.regularMaterial`
   resolves to under iOS 26.

2. **Wordmark.** Root views show `BOBAWordmark` centered in the title
   slot. Pushed views show contextual title (deck name, card name,
   article title). Modals show their own title — never the wordmark.

3. **Toolbar slot conventions:**
   - **Top-leading:** Profile gear (auth-aware tabs only) OR Cancel
     (modal context) OR back chevron (push context, system-default).
   - **Top-trailing:** primary action OR contextual `Menu`. If both
     exist, primary action right-most, Menu left of it.
   - **Top-center:** wordmark on root, contextual title on push.
     Never both.
   - **Bottom (`.tabViewBottomAccessory`):** active cross-cutting state
     only — scan session, deck draft, audio player. Never tab-specific
     content (per §6.5, Donny Wals).

4. **No custom chrome on top of system chrome.** Don't add a second
   "title bar" inside the content area. The system navigation bar is
   the title bar.

5. **Strip every `.navigationBarHidden(true)`** unless the surface is
   genuinely chromeless (e.g., the camera view). Hiding the nav bar
   to fit more content is a density anti-pattern — find density via
   typography (§4) instead.

6. **Don't fight iOS 26 `.tabBarMinimizeBehavior(.onScrollDown)`.** The
   tab bar shrinks during content scroll; that's correct behavior.
   Don't override unless we're in a context where the tab bar must
   stay (active scan being a candidate).

---

## 6.10 Feature walkthroughs

Walkthroughs are anchored, multi-step tutorials that fire on first
visit to a major feature. They are the BOBA Playbook approach to
onboarding — *just-in-time, per-feature*, not a wall-of-slides on
first launch. The deck-builder walkthrough
(`DeckBuilderTutorialOverlay`, [DECISIONS.md #031](./DECISIONS.md))
is the current implementation template; this section codifies the
pattern so every other major feature gets one consistent treatment.

**Where walkthroughs fire (first visit only, per device):**

| Surface | Trigger |
|---|---|
| **Find** tab | First time the tab is opened |
| **Learn** tab | First time the tab is opened |
| **Decks** tab | First time the deck builder is entered with no existing decks |
| **Collection** tab | First time the tab is opened (signed-in OR signed-out — different copy) |
| **Purchase** tab | First time the tab is opened |
| **Card detail** (§8.6) | First card detail open from any tab |
| **Pricing panels** (§8.7) | First scroll to the pricing section |
| **Wall view** (§8.8) | First Wall render |
| **Scan** (§6.5) | First scan invocation, in the destination tab's context |
| **Multi-card grid scan** | First grid scan (separate from single-card scan walkthrough) |

If a feature is added later that introduces a genuinely new
interaction model (not just new content), it gets a walkthrough on
first use too. Adding new content to an existing feature does *not*
warrant a new walkthrough.

**The 5-step cap.** Walkthroughs ≤ 5 steps. If a feature needs more
than 5 steps to teach, the feature is too complex — refactor before
adding walkthrough steps. The deck-builder's existing walkthrough
should be audited against this cap.

**Anchor-based, not overlay-modal.** Walkthroughs highlight actual
UI elements with a ring/spotlight cutout. Copy floats near the
anchor in a glass tooltip. Background dims to push focus. Never
use a "modal slide deck" of generic illustrations — the user must
see and learn from the *real* UI on the *real* screen, not a
stylized version.

**Skip + Done buttons always visible.** Skip dismisses the entire
walkthrough; Done dismisses on the last step. Never trap the user.
Tap outside the anchor advances to next step (gentle nudge); tap
the anchor itself completes the demonstrated action and advances
(immediate teaching).

**Voice — second person, action-oriented, ≤ 12 words per step:**
- ✅ *"Tap a card to add it to your deck."*
- ✅ *"Drag the deck panel up to see your full list."*
- ✅ *"Use search tokens to filter by element or cost."*
- ❌ *"In this view, you can build out your deck by selecting cards
  from the pool above. Each card you tap will be added based on the
  current mode of operation."*

**Visual treatment** (canonical `BOBAWalkthrough` component, §11):
- **Anchor ring**: 2pt cyan stroke around the highlighted UI element
- **Copy bubble**: glass with cyan accent (per §5 Liquid Glass —
  this is navigation chrome, glass is appropriate), anchored
  above/below the highlighted element with a small connector
  pointer
- **Background dim**: 60% black overlay everywhere except the anchor
  + 12pt padding around it (the cutout)
- **Step indicator**: small dots (• • • • ○) bottom-center
- **Skip / Next / Done buttons**: bottom toolbar in glass; Skip
  always present, Next becomes Done on the last step

**Universal manager.** `WalkthroughsManager` (parallel to
`HintsManager` from DECISIONS.md #031): tracks dismissed walkthrough
IDs per device in `UserDefaults`. Resettable from Profile via
"Reset walkthroughs" button alongside the existing "Reset hints"
button. Global toggle "Show walkthroughs on first visit" alongside
the existing "Show hints" toggle.

**Re-launchable.** Every walkthrough is re-triggerable via a "?"
button in the relevant view's toolbar `Menu` (overflow position,
not primary). Per the existing deck-builder pattern (line 114 of
DeckBuilderView.swift). Walkthroughs are how new users learn the
feature; the "?" button is how returning users *re-learn* it after
a long absence or a major feature update.

**Walkthrough vs. hint vs. empty state vs. error — when to use which:**

| Use case | Component | Example |
|---|---|---|
| User sees the feature for the first time and needs to know what's possible | **Walkthrough** (§6.10) | First Decks visit shows "Tap card → Sheet rises → Save" |
| User is on a screen and there's a non-obvious tip about ONE specific thing | **HintBanner** (§6.8) | "Bonus play count > 6 dilutes your strategy" |
| User is on a screen with no content yet | **EmptyState** (§6.7) | "No decks yet — tap Templates to start" |
| User triggers an action that fails | **ErrorBanner** (§6.7) | "Save failed — try again" |

These four don't overlap. A first visit fires the walkthrough; on
subsequent visits, hints surface contextually; the screen shows an
empty state if nothing's there yet; errors interrupt only if they
happen during a user-triggered action.

**Anti-patterns:**
- Walkthrough that explains UI that's already self-explanatory (skip
  the step, fix the UI)
- Walkthrough that hijacks navigation (don't push a new view; anchor
  the overlay on the current view)
- Walkthrough that competes with `.tabViewBottomAccessory` content
  (pause the accessory while a walkthrough is active)
- Multiple walkthroughs on the same first visit (Find first-visit
  fires ONLY the Find walkthrough — even if scan/wall/card-detail
  walkthroughs are also pending; those fire on their *own* first uses)
- Walkthrough that requires sign-in to view (walkthroughs respect §6.5
  auth-optional rule — every walkthrough must work signed-out)
- Slide-deck walkthroughs ("Welcome to BOBA Playbook" splash with 5
  illustrated screens) — explicitly rejected; teach with the real UI

**The existing deck-builder walkthrough audit.** Per the earlier
code audit, `DeckBuilderTutorialOverlay` (line 185 of
`DeckBuilderView.swift`) exists as a fullscreen overlay with
anchor-based highlight rings. It uses `@AppStorage deckTutorialSeen`
for one-shot logic + the "?" button at line 114 to re-launch. **The
pattern is correct** — extract it into a reusable `BOBAWalkthrough`
component (§11.1) and use it as the template for all walkthroughs in
the catalog below. Note: since Decks is being rebuilt to the §8.3
Maps pattern, the existing walkthrough's *content* is obsolete — the
**new** Decks walkthrough script is in the catalog below; old steps
are replaced wholesale, not patched.

---

### 6.10.1 Walkthrough catalog

Concrete script for every walkthrough in the app, with anchor + copy
per step. Each script complies with the §6.10 rules: ≤5 steps, ≤12
words/step, anchor-based, signed-out-friendly. Implementers build
against this catalog directly — no need to invent copy.

#### Find — first visit (5 steps)
1. **Anchor: search field.** *"Search any of 17,968 cards by name, hero, or weapon."*
2. **Anchor: featured ribbons.** *"Browse by weapon, sport, or featured collections."*
3. **Anchor: a card cell.** *"Tap a card to see details, prices, and decks."*
4. **Anchor: scan toolbar button.** *"Scan a real card to identify it instantly."*
5. **Anchor: profile gear.** *"Sign in to save cards to your collection."* (Done)

#### Learn — first visit (4 steps)
1. **Anchor: root list.** *"Five learning paths, from Rules to Tournament."*
2. **Anchor: first category row.** *"Tap to read articles, strategy, and glossary."*
3. **Anchor: scope bar (inside first article opened during walkthrough).** *"Switch between Rookie, Substitution, and Playmaker views."*
4. **Anchor: search field.** *"Search across every Learn article from here."* (Done)

#### Decks — first visit (5 steps) *(matches §8.3 Maps-pattern rebuild)*
1. **Anchor: card pool grid.** *"Tap any card to add it to your deck."*
2. **Anchor: bottom sheet drag handle.** *"Drag up to see your full deck list."*
3. **Anchor: format chip in sheet.** *"Set your format — it shapes the whole deck."*
4. **Anchor: search bar with token.** *"Filter with tokens for element, cost, or hero."*
5. **Anchor: Save button.** *"Sign in and save to access your deck anywhere."* (Done)

#### Collection — first visit (5 steps)
1. **Anchor: designation scope bar.** *"Personal, For Sale, Trade, Wanted, Grails — switch here."*
2. **Anchor: a card cell.** *"Tap to edit designation, valuation, or notes."*
3. **Anchor: scan toolbar button.** *"Scan to bulk-add cards to a designation."*
4. **Anchor: display-mode picker.** *"Switch to List for triage or Wall for sharing."*
5. **Anchor: share button.** *"Share by URL or as a Wall image."* (Done)

#### Purchase — first visit (3 steps)
1. **Anchor: segmented picker.** *"Upcoming Breaks or Find a Store."*
2. **Anchor: a Whatnot show tile.** *"Tap to open the show in Whatnot."*
3. **Anchor: store finder map.** *"Find indie shops or big-box near you."* (Done)

#### Card detail — first open (3 steps)
1. **Anchor: stats grid.** *"Six cells: Card #, Type, Treatment, Weapon, Set, Sub-set."*
2. **Anchor: pricing panels.** *"Buy Now is asking; Sold is transacted. Kept separate."*
3. **Anchor: action bar.** *"Add to Collection, Add to Deck, or Share."* (Done)

#### Pricing panels — first scroll (2 steps)
1. **Anchor: Buy Now strip.** *"Live asking prices from eBay and COMC."*
2. **Anchor: Sold strip.** *"Recent sales drive the market estimate above."* (Done)

#### Wall view — first render (3 steps)
1. **Anchor: aspect picker.** *"Pick wallpaper, square, or 16:9 sizing."*
2. **Anchor: Price Overlay toggle.** *"Show prices on each card for sale lists."*
3. **Anchor: Share button.** *"Save the image or share it directly."* (Done)

#### Scan — first invocation (varies by destination)

Three destination-specific scripts, since scan from Find / Decks /
Collection (§6.5) does meaningfully different things at the
"default action on capture" step.

**From Find** (2 steps):
1. **Anchor: viewfinder.** *"Cards land in your scan queue as you capture."*
2. **Anchor: mode toggle.** *"Switch to grid mode for 3–9 cards at once."* (Done)

**From Decks** (2 steps):
1. **Anchor: viewfinder.** *"Captured cards add directly to your current deck."*
2. **Anchor: queue review.** *"Tap any card to remove if mis-scanned."* (Done)

**From Collection** (3 steps):
1. **Anchor: destination chooser sheet (pre-scan).** *"Pick a designation — captures land there."*
2. **Anchor: viewfinder.** *"Scan as many cards as you'd like in one session."*
3. **Anchor: queue review.** *"Change a card's designation here before finishing."* (Done)

#### Multi-card grid scan — first use (3 steps)
1. **Anchor: viewfinder.** *"Position 3 to 9 cards in a grid pattern."*
2. **Anchor: shutter.** *"One tap captures all visible cards."*
3. **Anchor: review queue.** *"Confirm matches or pick from alternatives."* (Done)

---

**Step-count audit:** 5 + 4 + 5 + 5 + 3 + 3 + 2 + 3 + 2 + 2 + 3 + 3 =
**40 total anchored steps** across 12 walkthroughs (5 tabs + 7
features). Average 3.3 steps per walkthrough; max 5; all under cap.

**Word-count audit:** every step copy is ≤ 12 words. Re-verify
during implementation; a step that grows past 12 words signals
either (a) the anchor is wrong (try splitting into two steps), or
(b) the underlying UI needs simplification (the §6.10 rule:
walkthrough length is a proxy for UI complexity).

---

## 7. Forward-compatibility (iOS 27 ready)

Bloomberg/Gurman as of April 2026 indicates iOS 27 (WWDC 2026, June 8)
focuses on (a) Siri overhaul, (b) Apple Intelligence integration,
(c) Liquid Glass refinement (system opacity slider), (d) AI photo
editing. **No navigation paradigm shift expected.** ([Bloomberg April
19, 2026](https://www.bloomberg.com/news/newsletters/2026-04-19/apple-ios-27-siri-interface-ios-27-details-mac-studio-touch-macbook-release-mo5u23o7))

Design rules to inherit iOS 27 gains automatically:

1. **Every primary action is an `AppIntent`.** Search a card, open a
   deck, start scan, add to collection, lookup price. App Intents are
   the surface that Spotlight, Siri, Action Button, Shortcuts, and
   the iOS 27 Siri overhaul all consume. ([Apple AppIntents
   docs](https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence))

2. **Content has stable IDs.** Cards already have `bobaId`. Decks have
   UUIDs. Learn articles need stable section IDs (slug-style:
   `setup.match-flow`, `tournament.scoring`) so Apple Intelligence
   summaries / deep links / Siri can target a specific section.

3. **Search is central** (see §6). Building search-first IA is the only
   way to inherit a future natural-language search layer without
   rewriting the IA.

4. **Don't depend on fixed glass opacity.** Tinted Mode slider exists
   today (iOS 26.1+) and will expand in iOS 27. Test our chrome at
   every opacity setting; never override.

5. **Don't predict iOS 27 specifics.** Build to iOS 26 cleanly, inherit
   refinements when they ship. Apple historically refines (not replaces)
   a year-old design language.

---

## 8. Per-tab IA recipes

This is the binding redesign target. Every existing tab gets refactored
to match. New tabs (if any) follow the same pattern templates.

### 8.1 Find — the explorer

**Verb:** *explore*. Resolves the current Browse-in-Learn verb collision
by absorbing it.

**Pattern:** `Tab(role: .search)` with full-screen search expansion.

**Anatomy:**
- **Default state (no search active):** vertical list of *featured
  ribbons* — "Heroes by Weapon", "Athletes by Sport", "Recently Added",
  "Coaching Staff", "Saved Searches". Each ribbon is a horizontal scroll
  of card cells. Featured ribbons absorb the current Learn → Browse
  "Featured Collections" lists.
- **Search activated:** the tab bar minimizes, search field takes the
  canvas. Tokens for hero / element / treatment / cost / format / set.
  Scopes for "Cards / Heroes / Featured" if relevant.
- **Card grid:** uniform `BOBACardCell`, 3 columns,
  `.scrollEdgeEffectStyle(.hard, for: .top)`.
- **Tap card:** push to `CardDetailView` (full info, pricing, comps,
  add-to-collection, add-to-current-deck).
- **Toolbar:** scan button (top-trailing), profile (top-leading on
  collapse).

**Anti-patterns to avoid:** filter pills above the grid (use search
tokens). Multiple "browse by" pickers (use scopes inside search).

### 8.2 Learn — the educator

**Verb:** *understand*. No card details, no card-add actions — those
belong in Find. Keep this surface purely educational.

**Pattern:** `NavigationStack` push from a single root list (Apple Music
Library pattern).

**Anatomy:**
- **Root:** vertical list of 5 categories — Rules / Strategy / Collect /
  Glossary / Tournament. **No Browse — Browse moved to Find.** Each row
  is a `BOBASectionRow` with title + count + chevron.
- **Tap a category:** push to article-list view (or for short categories
  like Glossary, push directly to the content).
- **Article view:** the actual reading surface. Rookie / Substitution /
  Playmaker becomes a `searchScopes` scope bar at the top — articles
  filter to show the version appropriate for that skill level. NOT a
  third nav level.
- **Read vs. Watch:** also a scope inside the article view, not a
  toggle at the root. An article with a video version shows both
  scopes; a text-only article shows only Read.
- **`.searchable`** spans the whole Learn corpus.
  `ContentUnavailableView.search` for zero-result.
- **Toolbar:** glossary lookup (top-trailing) — quick definition popup
  for any selected term inline.

**Stable IDs:** every article + section gets a slug ID
(`rules.match-flow`, `tournament.scoring.divisions`) for AppIntent /
deep linking / future AI summary targeting (see §7).

### 8.3 Decks — the builder

**Verb:** *build*. The card pool inside the builder is *contextual to
the current deck*, separate from Find's standalone exploration.

**Pattern (REVISED 2026-05-04):** Music's mini-player +
fullScreenCover with hero zoom. Card pool = canvas, current deck =
non-draggable summary pill at the bottom that zooms into a
full-screen editor on tap. **The earlier Maps-canvas-with-sheet
detent pattern was abandoned after 12+ iterations of trying to make
a custom drawer not flash during drag** — see §1.0 (native first).
The drag was the problem; tap → zoom-into-editor is the answer.

**Anatomy:**
- **Canvas:** card pool grid, full-screen. Uses the unified
  `BOBACardGridItem` (per §11.1 — image on top, name + weapon +
  power below). `.scrollEdgeEffectStyle(.hard, for: .top)`.
- **Bottom summary pill:** non-draggable `DeckSummaryPill`
  positioned via `.safeAreaInset(edge: .bottom)`. Shows the
  current draft's name + section breakdown
  (`8/8 H · 30/30 P · 6 BP · 10/10 HD` — sections appropriate to
  format) + format badge. Empty draft shows "Build a deck · Tap
  to open the editor."
- **Tap pill → full-screen editor:** `.fullScreenCover` with
  `.matchedTransitionSource(id: "deck-draft", in: ns)` on the
  pill paired with `.navigationTransition(.zoom(sourceID:
  "deck-draft", in: ns))` on the editor. Photos-app hero zoom.
- **Editor (full-screen):** `NavigationStack(path: $editorPath)`
  with the deck header (name field + stat counts), format chip
  strip, and grouped deck list. Toolbar: Close (X) leading +
  SAVE/SIGN IN trailing + ⋯ Menu (Manage Decks, Rules, Legality,
  Clear deck).
- **Editor secondary surfaces:** Manage Decks / Rules / Legality
  Audit are **NavigationLink pushes** within the editor's
  `NavigationStack`, NOT sheets stacked on top. Slide in from
  the right with native back chevron — Music's "drill into next
  layer" pattern. Each sheet struct accepts a
  `wrapInNavStack: Bool = true` parameter so the same struct
  works as a sheet OR as a destination.
- **Filtering the pool:** native `.searchable(text:tokens:
  suggestedTokens:placement:.navigationBarDrawer(.always))` with
  `BOBAFilterToken` enum (weapon / cost / hero) for chip-style
  search tokens. Tap the search bar → suggested tokens appear:
  every weapon + 0–4 HD costs + matching hero names.
- **Card pool tap:** opens card detail via NavigationLink push +
  zoom transition (per §8.6). Long-press: adds card to current
  deck draft (per user feedback — long-press is the canonical
  add gesture).
- **Toolbar (pool tab):** wordmark (principal) + ⋯ Menu (column
  density picker 1/2/3, Scan into deck, walkthrough). NO Save
  button on the pool toolbar — Save lives in the editor.
- **Grid density:** user-selectable 1/2/3 columns via
  `@AppStorage("bp_decksGridColumns_v1")`, defaults to 3. 1/2-
  across pulls full-size images (per §11.1 BOBACardGridItem).
- **Empty state:** template gallery in the editor's empty state.
- **Scan integration:** scan invocation lives in the pool's ⋯
  Menu. Scanned cards land in the active draft via the existing
  scanStore queue.

**Anti-patterns to avoid:** custom drawer / draggable bottom sheet
(the original implementation that flashed; iOS 26 has no native
drawer pattern that keeps the tab bar visible — accept either the
fullScreenCover-from-pill pattern OR the standard `.sheet +
.presentationDetents` that hides the tab bar at large detents).
Quick-add toggle. Per-tab status banner. Stacking secondary sheets
on top of the editor — push them as NavigationDestination instead.
+ at most one sheet at a time.

### 8.4 Collection — the owner

**Verb:** *own*. Owned cards + designations + display modes + sharing.

Collection is the only tab with a public-facing dimension — what you own
is also what you may want to show others. The design must treat *display
how it looks to me* and *display how it looks to others* as first-class
peers, not afterthoughts.

**Pattern (REVISED 2026-05-04 — Music Library shape):** Root view is
**My Cards** (the most common use case — owned cards by designation).
Rainbow Progress and My Shows are NavigationLink pushes from the
toolbar ⋯ Menu, NOT a top-of-view segmented mode picker. The previous
viewMode picker created a 5-row chrome stack (mode picker + designation
tabs + display picker + filter + search) before the user saw any cards
— exactly the "stack of interfaces" anti-pattern the design overhaul
was meant to avoid.

**Anatomy:**
- **Root (My Cards, always shown):** card grid of owned cards, using
  the unified `BOBACardGridItem` (per §11.1).
- **Designation segmented Picker:** Personal / Sale / Trade / Wanted /
  Grails using `UserCard.Designation.shortDisplayName` so all 5
  options fit on one row (§3.9 — no horizontal-scrolling pill rows).
- **Native `.searchable`** with `.navigationBarDrawer(displayMode:
  .always)` — searches owned cards by hero name, card number, hero
  field. Composes with the active filter and designation scope.
- **Display mode picker** (toolbar ⋯ Menu, top section "Display" —
  three options):
  - **List** (default): compact rows — name + designation + value
    + quick designation-edit chip.
  - **Grid**: visual scan, card art is the focal point.
  - **Wall**: renders all visible cards as a single tile-able image,
    sized for sharing.
- **Grid density:** when display mode = .grid, additional toolbar
  Menu section "Columns" with 1/2/3 picker via
  `@AppStorage("bp_collectionGridColumns_v1")`. 1/2-across pulls
  full-size images.
- **Other lenses (toolbar ⋯ Menu, top section):**
  - **Rainbow Progress** — pushes to a full-screen rainbow view with
    its own chrome (no designation tabs, no display mode picker, no
    search field competing for space).
  - **My Shows** (streamer only) — pushes to `ShowsListView`.
  Each pushed lens has only the chrome it needs.
- **Each cell shows the designation badge** (tiny corner overlay) so
  multi-designation cards are scannable across scopes — a card that's
  in both Personal and For Sale shows both.
- **Tap card:** NavigationLink push to `CollectionCardDetailView` via
  the parent NavigationStack's `navigationPath` (also handles
  Rainbow / Shows routes). Hero zoom transition per §8.6.
- **Scan invocation:** toolbar Scan button (per §6.5). On invocation,
  brief sheet asks *"Add scanned cards to which designation?"* —
  defaults to Personal, remembers last choice. Then routes accordingly.
- **Share invocation** (toolbar): generates iOS share sheet with deep
  link + Wall image of current designation scope. The deep link follows
  the format `bobaplaybook.com/u/{username}/{designation}` and opens
  the iOS app if installed, falls back to the web app if not. The web
  app honors a per-designation public/private toggle (set in Profile).
- **Profile** is Find-only per `feedback_profile_only_on_find.md`.
  Collection's auth surfaces are inline `BOBASignInPrompt` rows.
- **Value summary:** persistent header above the grid, single line, no
  decoration. Total value + designation breakdown. Tap → push to a
  value-history detail (chart of total value over time).

**Streamer / Generate Wall reconciliation.** The existing Generate
Wall feature (currently streamer-role-gated per
[DECISIONS.md #025](./DECISIONS.md)) is the implementation foundation
for the general Wall display mode above. With this design, **Wall
becomes a display mode for every collector**, not a streamer-only
sheet. The streamer-specific "My Shows" feature (Whatnot show
management) stays gated; only the Wall rendering generalizes. Discuss
gate-lifting before implementing — it's a deliberate scope expansion.

**Public web fallback.** The web app at `bobaplaybook.com` serves as
the public-facing collection display when iOS isn't available. iOS
share links open the iOS app if installed via Universal Link, fall
back to the web. The web app supports the same designation scopes +
public/private toggle (set in Profile). This means a user can hand
someone a `bobaplaybook.com/u/ben/grails` URL and that person sees the
same wall, formatted for browser, no sign-in required for public
designations.

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

The card detail surface is pushed from Find, Decks (pool tap), and
Collection (cell tap). Because it lives across three contexts, the
design must be invariant to entry context — same `artPanel`, same
toolbar setup, same modifier order. Only the body content BELOW
the artPanel differs by context. Implemented as three structs
(`CardDetailView`, `BrowserCardDetailSheet`, `CollectionCardDetailView`)
that share the artPanel + toolbar pattern verbatim.

**Pattern:** Music-style hero zoom into a `NavigationLink`-pushed
view (NOT a sheet). Source cell uses
`.matchedTransitionSource(id:in:)` as the OUTERMOST modifier;
destination uses `.navigationTransition(.zoom(sourceID:in:))`.

**Canonical artPanel (identical across all three surfaces):**
```swift
ZStack {
    LinearGradient(
        colors: [Design.Colors.element(card.element).opacity(0.25),
                 Design.Colors.nearBlack],
        startPoint: .top, endPoint: .bottom
    )
    .frame(height: 420)

    CardImageView(card: card, size: .full)
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Design.Colors.element(card.element).opacity(0.4),
                radius: 16, y: 6)
        .padding(.horizontal, Design.Spacing.xl)
}
```

**Canonical toolbar setup (identical across all three surfaces) —
modifier ORDER matters:**
```swift
.scrollEdgeEffectStyle(.soft, for: .top)        // BEFORE .background!
.background(Design.Colors.nearBlack)
.navigationTitle("")                            // empty — title via principal
.navigationBarTitleDisplayMode(.inline)
.toolbar { ... + ToolbarItem(.principal) { Text(card.name)... } }
.toolbarBackground(.regularMaterial, for: .navigationBar)
.toolbarBackground(.visible, for: .navigationBar)
```

`.scrollEdgeEffectStyle(_:for:)` MUST come BEFORE `.background(_:)`.
`.background` returns a wrapped view; applying scrollEdgeEffectStyle
after it doesn't register on the underlying ScrollView.

**Wrap-in-NavStack pattern.** Each detail struct accepts
`wrapInNavStack: Bool = true`. Default `true` preserves sheet
usage (e.g., legacy `DeckBuilderView` still presents
`BrowserCardDetailSheet` as a sheet from card detail's "Add to
Custom Deck"); push usage passes `false` so the parent
NavigationStack provides nav chrome and avoids the nested-stack
back-button conflict. The Done button is conditionally rendered
only in sheet mode (push uses native back chevron).

**Anatomy (body content below the artPanel):**
1. **Stats grid** (canonical 6-cell 2-column per DECISIONS.md #029)
2. **Cost + DBS** (Plays only)
3. **Pricing panels** (§8.7)
4. **Per-context body**: Collection adds copies/decks/variations
   sections; Decks adds an "Add to Deck" / "Remove" CTA; Find adds
   the Add menu in the toolbar
5. **Action bar / toolbar items**: contextual actions per entry

**Action bar by context** (toolbar trailing items, NOT a separate
sticky bottom bar):

| Entry from | Toolbar contains |
|---|---|
| **Find** | Add menu (Collection / Deck / Show) + Mod-edit (if mod) + Share |
| **Decks (tap)** | Add to Deck CTA in body |
| **Collection (tap)** | Edit Designation + Add menu (in body sections) |

The vocabulary never changes — `Add to Collection`, `Add to Deck`,
`Share`, `Edit Designation` are the canonical verbs.

**Anti-patterns:**
- Per-surface artPanel variants (different gradient height, different
  image padding, different corner radius). The artPanel is one shape;
  cleaned up 2026-05-04 after surfaces had drifted.
- Per-surface toolbar accumulation (`.toolbarTitleDisplayMode(.inline)`,
  `.toolbarBackground(.hidden)`, etc. added during forehead-iteration
  guesses). Stick to the canonical toolbar setup above.
- Sheets for "drill into next layer" content (Manage Decks, Rules,
  Legality). Use NavigationLink push instead — see §8.3.
- Prev/next chevrons in the bottom toolbar. Removed 2026-05-04 per
  user feedback — they cluttered the simple card-detail surface.

**Hero zoom transition rules** (Music's tap-to-album pattern):

| Where | What |
|---|---|
| Source cell | `.matchedTransitionSource(id: <stable-id>, in: ns)` as the OUTERMOST modifier |
| Destination | `.navigationTransition(.zoom(sourceID: <same-id>, in: <same-ns>))` |
| Namespace | One `@Namespace` per parent view, shared between source and destination |
| Push | NavigationLink push or `path.append(<value>)` with `.navigationDestination(for:)` |
| ID source | `card.id` (Card is Hashable+Identifiable) for Find/Decks, `bobaId: String` for Collection |

**The "nil view" warning** in the iOS console
(*Starting a zoom transition from a nil view will trigger a fallback
transition*) means iOS couldn't find a view with the matching source
ID. Causes encountered:
- `.matchedTransitionSource` applied to an INNER view that subsequent
  modifiers (Button label, .overlay, custom .modifier) wrap. **Fix:**
  apply matchedTransitionSource as the LAST (outermost) modifier on
  the cell.
- `.matchedTransitionSource` applied INSIDE a function-returning-view
  (like `collectionGridCell(identifier:)`). **Fix:** apply it at the
  call site as the outermost modifier on the function's result.

When iOS uses the fallback transition, the destination's nav bar
inherits the parent's nav bar height — including any `.searchable`
drawer — and visually overlays the destination's content as
"extended header" before collapsing. Avoid the fallback by getting
the matched source right.

---

### 8.7 Pricing panels — Buy Now + Sold history

Pricing lives inside `CardDetailView` (§8.6) but has enough complexity
to deserve its own design rules. Per
[DECISIONS.md #013](./DECISIONS.md), pricing is fetched live at view
time via Cloudflare Worker (eBay Browse API + Radish). Per
[DECISIONS.md #034](./DECISIONS.md), COMC asking-prices stay OUT of
the sold-comp waterfall to avoid inflating market estimates.

**Two-section panel, in this order (top to bottom):**

1. **Buy Now** (asking prices — where can I buy this right now?).
   Includes:
   - eBay active listings (with Buy Now eligibility filter)
   - COMC asking listings, each with a *"COMC asking · Ungraded NM"*
     pill so users read the price as a list price, not a transaction
   - Soft-fail: if COMC Worker returns `challenged: true` or `count: 0`,
     COMC strip silently disappears. Never show error UI for COMC
     unavailability — it's a known intermittent state.
2. **Sold history** (transacted prices — what's it actually worth?):
   - Radish recent sales (preferred — TCG-specialized comps)
   - eBay sold listings (fallback when Radish has no data)
   - Computed market estimate = Radish-first waterfall

**Per-section controls:**
- Each section has its own horizontal scroll of price tiles.
- Each tile: thumbnail + price + source pill + tap-through deep link
  to the source listing.
- Each section gets its own `ContentUnavailableView` for empty (after
  loading): *"No active listings on eBay or COMC right now"* with a
  refresh action.
- Each section's loading state is a 3-tile skeleton, not a spinner.

**Market estimate display** (above the two sections, single line):
*"~$24 · based on 8 recent sales (Radish + eBay)"*. The number is
computed; the basis is exposed so users can audit. Per DECISIONS.md
#034, asking prices are NEVER folded into this number.

**Per-card cached value** (per DECISIONS.md #013): the latest
market-estimate value is cached on `user_cards.estimated_value` for
the Collection value-summary header. The Collection grid does not
re-fetch live pricing on every render.

**Anti-patterns:** combining asking + sold into one number (inflates
~10–25%). Showing only one source when both available. Hiding price
sources behind disclosure (always visible — provenance is the trust
mechanism).

---

### 8.8 Wall view + Price Overlay — display & share for everyone

The two display+share features that historically lived behind a
streamer-only gate per [DECISIONS.md #025](./DECISIONS.md): **Wall
view** (renders multiple cards as a single image) and **Price Overlay**
(renders price chips on top of card images). Both are too useful to
keep gated. This document **lifts both gates** for general-collector
use; the streamer-specific "My Shows" Whatnot management feature
stays gated.

> When implementing this scope expansion, write a new DECISIONS.md
> entry that *supersedes* #025's specific application to Wall + Price
> Overlay (the underlying principle of "keep code, hide UI" is still
> valid for other features). Don't delete #025.

#### Wall view

**Purpose:** render N cards as a single image for visual sharing —
collection bragging, sale lists, trade lists, deck composition,
practice teaching.

**Invocation:** Collection tab display-mode picker (§8.4); Decks tab
overflow Menu ("Generate deck wall"); Find tab on multi-select
selection ("Wall these 12 cards").

**Anatomy:**
- Full-screen render with the cards laid out as small multiples
  (uniform `BOBACardCell`, §4.3). Background is near-black.
- Title strip (top): contextual ("Ben's Grails", "Fire Aggro Deck",
  "12 Hand-Picked Heroes"). Editable inline.
- Aspect ratio picker (toolbar `Menu`): iPhone wallpaper (9:19.5),
  Instagram square (1:1), Twitter/X / web (16:9), iPad wallpaper
  (3:4 / 4:3). Default = source-context (Collection wall →
  Instagram square; deck wall → 16:9).
- Toolbar: Save / Share / Copy / aspect picker / overlay toggle
  (turns Price Overlay on/off).
- Optional Price Overlay (next subsection).

**Honors current scope.** A Wall generated from Collection's "Grails"
scope shows only Grails cards. From a deck, only that deck's cards.
The user never has to re-filter inside Wall view.

#### Price Overlay

**Purpose:** render pricing chips on top of card images for sale or
trade communication. *"Here's my For Sale list, with prices."*

**Invocation:** toggle inside Wall view (toolbar). When on, every card
in the wall renders a price chip overlay on its lower-third.

**Anatomy of an overlay chip:**
- Position: lower-third of card image, inset from edges.
- Content: source pill (eBay / COMC / Radish / Custom) + price.
- Source defaults to the lowest-asking visible to the system. User can
  toggle to *"My price"* (custom — uses the value stored in
  `user_cards.estimated_value` or a per-card override).
- Visual: glass chip (per §5 — chip floats over card art, gets
  `.tint()` to anchor against varied backgrounds).
- Optional secondary chip: condition (NM / EX / GD) for For Sale /
  For Trade designations.

**Per-designation defaults:**
- **For Sale** wall: Price Overlay ON by default, source = "My price".
- **For Trade** wall: Price Overlay ON, source = market estimate.
- **Grails / Personal**: Price Overlay OFF by default.
- **Wanted**: Price Overlay ON, source = market estimate, prefixed
  *"WTB"*.

**Anti-pattern:** rendering Price Overlay during browsing (it's not a
display affordance for everyday viewing — it's a sharing affordance).
Only enabled inside Wall view.

---

## 9. The redesign roadmap

The order of operations to bring existing code into compliance. Each
item references the §-rule it implements.

| Order | Refactor | Rule | Impact |
|---|---|---|---|
| 1 | Move `BrowseView` and `CardDetailView` out of `LearnView`; add featured ribbons to Find | §1.1, §8.1, §8.2 | Largest single simplification — kills Learn's tab-in-tab problem and removes ~800 lines from `LearnView.swift` |
| 2 | Convert Decks toolbar pile-up to Maps pattern (canvas + bottom sheet) | §8.3 | Highest perceived density win — kills 5-row toolbar |
| 3 | Add `Tab(role: .search)` to Find | §6.1, §8.1 | Unlocks iOS 26 dedicated search UX |
| 4 | Replace Learn's 6-section middle picker with single root-list `NavigationStack` push | §3.1, §8.2 | Removes Russian-doll nav |
| 5 | Convert all Decks filter rows to `.searchable` tokens | §6.4, §8.3 | Removes pill-bar pile-up |
| 6 | Strip every `.presentationBackground` modifier from sheets | §3.10, §5.5 | Restores iOS 26 automatic Liquid Glass |
| 7 | Replace hand-rolled scroll-edge gradients with `.scrollEdgeEffectStyle` | §3.11, §5.6 | Native iOS 26 chrome |
| 8 | Wire primary actions (Search, Open Deck, Start Scan, Add to Collection) as `AppIntent` | §7.1 | iOS 27 readiness |
| 9 | Add stable section IDs to Learn articles | §7.2 | iOS 27 readiness |
| 10 | Audit every grid for `BOBACardCell` consistency; fix any one-off card layouts | §4.3 | Small-multiples enforcement |
| 11 | Remove `.background(Color.gray.opacity(0.1))` and ad-hoc dividers from lists | §4.1 | Density restoration |
| 12 | QA pass: every screen against Reduce Transparency / Reduce Motion / Increase Contrast / Tinted Mode max | §5.7, §5.8 | Accessibility + iOS 27 forward |
| 13 | Unify scan invocation across Find/Decks/Collection — single `ScanCoordinator(destination:)` API, single ScanView, `tabViewBottomAccessory` strip for active sessions | §6.5 | Removes 3 parallel scan-button-and-routing implementations |
| 14 | Add Collection display-mode picker (Grid / List / Wall); lift Generate Wall from streamer-only gate to a general display mode for all collectors (discuss DECISIONS.md #025 implications first) | §8.4 | Makes collection display + sharing first-class for every user |
| 15 | Wire Share affordance into card detail, deck detail, designation scope; produce deep links + share images via single iOS share sheet with `bobaplaybook.com/{type}/{id}` Universal Links | §6.5, §8.4 | Sharing as a first-class verb; web fallback for non-iOS recipients |
| 16 | Add public/private toggle per Collection designation in Profile; have the web app honor it for `bobaplaybook.com/u/{username}/{designation}` URLs | §8.4 | Public collection sharing without sign-in friction for recipients |
| 17 | Consolidate `CardDetailView` to one source of truth across Find / Decks / Collection; differentiate by action bar only, not anatomy | §8.6 | Removes per-tab drift in the most-visited surface |
| 18 | Audit pricing UI to enforce the §8.7 two-section layout; add COMC soft-fail handling and the audit-able market-estimate caption | §8.7 | Pricing trust + provenance |
| 19 | Lift Wall view from streamer-only gate (DECISIONS.md #025); make it Collection display mode + Decks overflow option + Find multi-select option | §8.8 | Sharing as a first-class feature for every user |
| 20 | Lift Price Overlay from streamer-only gate; integrate as a Wall-view toggle with per-designation defaults | §8.8 | Sale/trade communication for every user |
| 21 | Standardize empty / loading / error / offline states using `BOBAEmptyState` + `BOBAErrorBanner` everywhere; add Offline pill in nav bar | §6.7 | "Feels janky" complaint root cause |
| 22 | Add iPad adaptation for Decks (NavigationSplitView + side panel), Find (sidebar search), Collection (multi-column grid) | §6.6 | iPad becomes a first-class surface, not stretched-iPhone |
| 23 | Audit toolbar / wordmark / material treatment for §6.9 compliance across every view | §6.9 | One-app feel |
| 24 | Codify `BOBASignInPrompt` inline auth pattern (no full-screen wall on launch); refactor existing auth-gate sites to use it | §6.5 Auth | Lower friction for read-only verbs |
| 25 | Audit existing hints against §6.8; add Profile reset button + global silence toggle UI | §6.8 | Predictable teaching moments |
| 26 | Build reusable `BOBAWalkthrough` component (extract pattern from existing `DeckBuilderTutorialOverlay`) + `WalkthroughsManager` (parallel to HintsManager); add Reset Walkthroughs + Show Walkthroughs toggle to Profile | §6.10, §11 | Walkthrough infrastructure |
| 27 | Implement the 5 tab walkthroughs (Find / Learn / Decks / Collection / Purchase) per §6.10.1 catalog — anchor + copy ready, just bind to UI | §6.10.1 | First-visit teaching across all tabs |
| 28 | Implement the 7 per-feature walkthroughs (Card detail / Pricing / Wall / Scan-from-Find / Scan-from-Decks / Scan-from-Collection / Grid scan) per §6.10.1 catalog | §6.10.1 | Just-in-time teaching for novel interactions |
| 29 | Replace existing `DeckBuilderTutorialOverlay` content with the new Decks walkthrough script per §6.10.1, as part of the §8.3 Decks-tab rebuild (item #2). The old script is obsolete — the entire Decks UI changes. Don't patch step-by-step; substitute wholesale. | §6.10.1, §8.3 | Decks walkthrough matches Decks rebuild |
| 30 | Verify every walkthrough survives signed-out (no required-auth interruption). The Find #5 / Decks #5 / Collection #5 steps reference sign-in — must show sign-in *as an option*, not block at sign-in | §6.5 Auth, §6.10 | Walkthroughs respect auth-optional rule |

---

## 10. The daily review test

Before any feature ships, three checks:

1. **The Gruber test (§4.6):** could a competent designer recreate this
   screen from a one-paragraph description? If no, decoration. Strip and
   rebuild.

2. **The verb test (§1.1):** what verb does this surface own? Is it
   colliding with a verb owned by a different tab? If yes, structural
   bug — resolve before merging.

3. **The depth test (§1.2):** count nav levels from tab root. If > 2,
   the third level should be a scope, a sheet, or a different tab.

When the answer to any of these is "no" or "I'm not sure," reread the
relevant section of this document. When the document is silent or
contradicts itself, the document is wrong — propose an edit before
proceeding.

---

## 11. Visual primitives — components + colors

The reusable building blocks every new feature must compose from.
Adding a new view = composing existing primitives. Inventing a new
primitive = first edit this section.

### 11.1 Component library

| Component | Purpose | Used in |
|---|---|---|
| `BOBACardCell` | Card thumbnail — uniform aspect, padding, badge placement (§4.3 small multiples). Takes `size: CardImageView.ImageSize = .thumb`; pass `.full` when rendering at densities ≤ 2 across (BOBACardGridItem does this automatically). | Find / Decks / Collection / Wall view + single-card surfaces (rainbow row, scan chip) |
| `BOBACardGridItem` | Unified grid cell — `BOBACardCell` on top + caption below (hero name + weapon pill + power). Density-adaptive typography via `columnCount: 1 \| 2 \| 3`. Caption uses `textPrimary` text inside an element-tinted capsule so HEX (#8B00FF) stays readable on dark backgrounds. | Find / Decks / Collection card grids — every grid uses the same cell |
| `DeckSummaryPill` | Bottom-anchored summary pill above the tab bar showing the active deck draft. Tap → zooms into full-screen DeckEditor (matchedTransitionSource + navigationTransition.zoom per §8.6). Replaces the v2.038 custom drawer. | Decks tab — `.safeAreaInset(edge: .bottom)` |
| `BOBASectionRow` | Single-line list row — title + count + chevron | Learn root / Profile / Settings forms |
| `BOBASectionHeader` | Typography hierarchy enforcer — uppercase Bebas Neue, no colored block | Every grouped view |
| `BOBASearchBar` | Wraps `.searchable` with the BOBA token type | Decks / Collection / Learn |
| `BOBADetentSheet` | Wraps `presentationDetents` with our standard heights `[120, .medium, .large]` | Decks deck panel / Find a Store / Card detail share |
| `BOBAEmptyState` | Wraps `ContentUnavailableView` with brand voice + canonical productive-next-action slot | Every list / grid / search |
| `BOBAErrorBanner` | Orange-bordered banner above an action — distinct from hints | Save deck failure / Sync failure / Pricing fetch failure |
| `BOBAHintBanner` | Cyan, dismissible-permanent first-run hint per §6.8 | Learn first-visit / Decks bonus play ceiling / etc. |
| `BOBAWalkthrough` | Anchored multi-step first-visit tutorial per §6.10 — extracted from existing `DeckBuilderTutorialOverlay` | Find / Learn / Decks / Collection / Purchase first visits + per-feature first uses (Wall, Scan, Pricing, Grid scan, Card detail) |
| `BOBASignInPrompt` | Inline "Sign in to do this" row — pre-routes Profile sheet | Save deck / Designate card / Edit profile |
| `BOBAWordmark` | Brand wordmark in title slot | Every root view |
| `BOBAGlassButton` | Primary action with tinted glass per §5.4 | Save deck / Add to Collection / Sign in |
| `BOBASecondaryButton` | Non-tinted glass button for secondary actions | Cancel / Skip / Dismiss |
| `BOBAOfflinePill` | Subtle "Offline" pill in nav bar when network is unavailable | All tabs while offline |
| `BOBAStatsGrid` | The canonical 6-cell card-stats layout (DECISIONS.md #029) | `CardDetailView` only |
| `BOBAPriceTile` | Buy Now / Sold tile — thumbnail + price + source pill | `CardDetailView` pricing panels |

**Rule:** if you're about to write a custom view that overlaps with one
of these, use the primitive. If the primitive doesn't quite fit, edit
the primitive (and document the change here) — never one-off.

### 11.2 Color usage rules

BOBA uses two distinct color systems. Don't mix them.

**Brand colors (UI chrome only):**
- `--boba-orange #FF4D00` — primary CTA, FIRE element (the only
  brand/element overlap)
- `--boba-cyan #00F5FF` — links, highlights, active states
- `--boba-violet #8B00FF` — secondary accents, HEX element
- `--boba-near-black #080810` — page background
- `--boba-surface #0D0D1A` — card / panel surfaces

**Element colors (content semantic only):**
- FIRE `#FF4D00` · ICE `#00BFFF` · STEEL `#8A9BB0` · BRAWL `#C0392B` ·
  GLOW `#FFD700` · HEX `#8B00FF` · GUM `#FF69B4` · SUPER `#FF00FF` ·
  NONE `#666680`

**The split:**
- Element colors are **semantic**, not decorative. Use them ONLY for:
  weapon badges on cards, weapon-filter chips, card-detail accent
  line, deck-builder element distribution chart.
- Brand colors are for app chrome — buttons, links, nav highlights,
  CTAs.
- **Never** use an element color for navigation chrome ("FIRE-themed
  button" = wrong). **Never** use a brand color for content meaning
  ("orange means urgent" = wrong; orange already means FIRE).

**The orange overlap is intentional.** FIRE is the BoBA hero element
that maps to the BOBA brand orange — they're the same hue by design,
which is why FIRE is the brand's anchor weapon. This is the only
case where the two systems overlap.

**Element color UPPERCASE in JSON / lowercase in render.** CLAUDE.md:
elements in cards.json are always UPPERCASE strings. UI renders them
mixed-case ("Fire"). Casing is a render concern, not a data concern.

---

## 12. Out of scope (intentionally)

Documented so future Claude sessions don't try to apply these design
rules to surfaces that were deliberately left for separate design
work — and so we have a clean record of why.

| Surface / feature | Out-of-scope reason | When to revisit |
|---|---|---|
| **Practice / Battle simulator** ([DECISIONS.md #030](./DECISIONS.md)) | Different design language (game-as-canvas, not list-as-canvas); deserves its own design doc when the executor stabilizes | When practice is shipped to all users |
| **Moderator corrections workflow** ([DECISIONS.md #023](./DECISIONS.md)) | Internal tool, different audience (mod role only), different UX priorities (auditability over density) | When mod tools graduate to a public-mod-applicant flow |
| **Web app design** | Web has different constraints — no Liquid Glass, no `.tabViewBottomAccessory`, GitHub Pages static-only. Some principles transfer (verb per tab, search-first IA) but the implementation patterns don't | When iOS DESIGN.md stabilizes; consider a parallel `WEB-DESIGN.md` |
| **Widgets / Live Activities** | Future surface; no current implementation. Design when we add them | When widgets are scoped |
| **Apple Watch companion** | Future surface. Watch design is its own discipline | If/when watchOS is targeted |
| **Push notifications** | No current notification surface. When added, will need a design rule for what gets a notification, frequency limits, content style | When notifications are added |
| **Email / share copy templates** | The strings inside iOS share sheets ("Check out my deck on BOBA Playbook!") are content design, not UI design | When share is implemented; consider a separate `COPY.md` |
| **Whatnot show management** (streamer-gated, DECISIONS.md #025) | Specific to streamer role; small audience; design when it expands | If/when streamer features are unrolled to general |
| **Card image optimization pipeline UI** | Internal tooling, not user-facing; lives in `scripts/` and pipeline configs | Probably never user-facing |
| **App-launch onboarding** (slide-deck splash on first install) | Explicitly rejected. BOBA Playbook uses **per-feature walkthroughs** instead (§6.10) — just-in-time, anchored teaching that fires on first feature use, not a wall of slides on first launch. The slide-deck pattern is forbidden by §6.10 anti-patterns | Never (this is a design choice, not a deferred decision) |

**The rule for adding to this list:** if a feature is intentionally
not-designed, write the entry. The existence of an "Out of scope"
entry is itself useful — it tells future sessions "we thought about
this and chose not to design it now."

The rule for removing from this list: when the feature comes into
scope, draft its design rules in the appropriate § and remove the
out-of-scope entry. Don't leave stale "future" markers.

---

## 13. References

Validated sources backing this document. Listed alphabetically.

- [Apple HIG — Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple HIG — Search Fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [Apple HIG — Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [Apple HIG — Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple HIG — Tab Bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Apple HIG — Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Apple — Liquid Glass Design Gallery 2026](https://developer.apple.com/design/new-design-gallery-2026/)
- [Apple AppIntents — Integrating actions with Siri](https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence)
- [Apple SwiftUI — `glassEffect`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [Apple SwiftUI — `inspector`](https://developer.apple.com/documentation/SwiftUI/View/inspector(isPresented:content:))
- [Apple SwiftUI — `NavigationSplitView`](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [Apple SwiftUI — `presentationDetents`](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:))
- [Apple SwiftUI — `scrollEdgeEffectStyle`](https://developer.apple.com/documentation/SwiftUI/View/scrollEdgeEffectStyle(_:for:))
- [Apple SwiftUI — `searchable` + `searchScopes`](https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:))
- [Apple SwiftUI — `TabView(.sidebarAdaptable)`](https://developer.apple.com/documentation/SwiftUI/TabViewStyle/sidebarAdaptable)
- [Bloomberg / Gurman — iOS 27 Siri overhaul](https://www.bloomberg.com/news/newsletters/2026-04-19/apple-ios-27-siri-interface-ios-27-details-mac-studio-touch-macbook-release-mo5u23o7)
- [conorluddy — Liquid Glass Reference (verbatim HIG)](https://github.com/conorluddy/LiquidGlassReference)
- [createwithswift — `scrollEdgeEffectStyle`](https://www.createwithswift.com/define-the-scroll-edge-effect-style-of-a-scroll-view-for-liquid-glass/)
- [Donny Wals — iOS 26 tab bars](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)
- [Frank Rausch — Modern iOS Navigation Patterns](https://frankrausch.com/ios-navigation/)
- [Hanin — Don't Design Junk in the iOS 26 Tab Bar](https://medium.com/design-bootcamp/dont-design-junk-in-the-new-ios-26-tab-bar-4de8e842da89)
- [MacStories / Federico Viticci — iOS 26 Review](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/)
- [nilcoalescing — Inspectors in SwiftUI](https://nilcoalescing.com/blog/InspectorInSwiftUI/)
- [nilcoalescing — SwiftUI search enhancements iOS 26](https://nilcoalescing.com/blog/SwiftUISearchEnhancementsIniOSAndiPadOS26/)
- [NN/G — Liquid Glass Is Cracked](https://www.nngroup.com/articles/liquid-glass/)
- [Ryan Ashcraft — iOS 26 tab bar critique](https://ryanashcraft.com/ios-26-tab-bar-beef/)
- [WWDC25 219 — Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25 244 — Get to know App Intents](https://developer.apple.com/videos/play/wwdc2025/244/)
- [WWDC25 256 — What's New in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/256/)
- [WWDC25 284 — Build a UIKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/284/)
- [WWDC25 323 — Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
