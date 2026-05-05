# BOBA Playbook — Web Design

> **This document is binding.** Every new view, screen, dialog,
> sidebar item, and grid in the web app must trace its design back
> to a rule in this document. When something feels overwhelming or
> off-brand, the failure is here, not in the feature — fix the
> document, then fix the feature.
>
> Companion to [`DESIGN.md`](./DESIGN.md) (binding iOS doc),
> [`CLAUDE.md`](./CLAUDE.md) (project context), and
> [`DECISIONS.md`](./DECISIONS.md) (architecture log). DESIGN.md
> still governs cross-platform principles (verb per tab, search-
> first, density-via-removed-chrome). This doc owns every web-
> specific implementation rule.
>
> Ratified 2026-05-05 from the research plan that lived here through
> v2.086. Open questions (§20) were answered, not deferred — see the
> end of the doc.

---

## 0. How to use this document

**Ben's job:** when a UI choice in a session contradicts a rule
here, point at the rule. Don't accept "I added a custom dropdown for
the new filter" — point at §3.0 native-first and the Popover API
adoption in §14.

**Claude's job:** before proposing any new view, dialog, sidebar
item, filter row, or feature, read the relevant section here and
quote the rule that justifies the choice. If no rule fits, the
proposal needs a new rule (and a discussion) before it ships.

**Living document.** Sections 7 (material) and 14 (forward-compat)
follow the web platform; update when Baseline adds a feature we'd
adopt. Sections 1–6 are principles and shouldn't churn.

---

## 1. Web-specific constraints (input to every other section)

Non-negotiable inputs from the project:

- **GitHub Pages static hosting** — no server runtime, no Node.js
  (per CLAUDE.md). Anything that looks like SSR or build-step is
  out unless we explicitly migrate hosts.
- **Vanilla HTML / CSS / JS — no framework, no build step**
  (DECISIONS.md #001). Plain DOM, plain CSS, ES2022+ vanilla JS,
  Supabase JS SDK loaded via CDN. No npm install, no bundler,
  no TypeScript transpile.
- **Mobile-first** (CLAUDE.md). Test at 375px before 1440px.
- **WCAG AA from line one** (CLAUDE.md "Standing Instructions").
- **Body flex-column layout** (DECISIONS.md #020) — no
  `viewport-fit=cover`, no fixed headers, no `position: fixed`
  overlays that fight Safari's compositor.
- **Cross-platform feature-parity contract** (DECISIONS.md #005) —
  but with the explicit DESIGN.md §12 carve-out that web design is
  its own discipline. Web does not chase iOS-specific patterns
  (Liquid Glass, hero zoom, `.tabViewBottomAccessory`) when a
  better-feeling web-native pattern exists.

**Locked decisions** (formerly "open questions" in this doc):

- **No build step, ever.** Native CSS Nesting + Container Queries +
  `:has()` removed the last reason to want Sass / PostCSS in 2026.
  Vanilla JS with ES modules removed the last reason to want
  TypeScript transpile. If we want stronger type checking, JSDoc
  comments + `// @ts-check` give us 80% of TS in-editor without a
  build pipeline.
- **GitHub Pages stays.** The 17k-card catalog at ~5MB JSON ships
  fine through Pages' CDN. Re-evaluate only if catalog crosses 50MB
  or we need a server runtime for a feature that can't be a
  Cloudflare Worker.

---

## 2. The six binding principles

Each rule names the iOS DESIGN.md §1 equivalent it descends from,
then specifies the web-native form.

### 2.1 Native first.

**Rule:** every interaction is a built-in HTML element or browser
API before it is custom code.

- `<dialog>` + `showModal()` before custom modal overlays.
- `<input type="search">` before custom search bars.
- Popover API (`popover` attribute) before hand-rolled dropdown
  positioning + click-outside listeners.
- `<details>` / `<summary>` before custom collapsible sections.
- View Transitions API (`document.startViewTransition`) before
  custom CSS animation orchestration for cross-view changes.
- `<form>` with native validation (`required`, `pattern`,
  `:invalid`) before inline JS error rendering.
- CSS `scroll-snap` before JS scroll-tracking.
- CSS Container Queries before viewport-only `@media` rules for
  components that can render in multiple containers.

**Why:** the recurring failure mode in the v2.0xx web batches was
reaching for custom code (overlay divs, hand-rolled dropdowns, JS
state-class toggles) when a baseline-supported native API existed
and would have shipped a better-feeling result in less code. The
baseline web platform in 2026 is almost as expressive as the iOS
SDK; treat it that way.

**How to apply:** before writing any new component, ask "is there a
native HTML element or browser API that does 80% of this?" If yes,
build on it and accept its native behavior over a hand-rolled
variant. The fallback strategy for the few unsupported browsers is
graceful degradation (`@supports`, feature-detect for JS APIs) —
not framework polyfills.

### 2.2 Each tab owns one verb.

**Rule:** Find = explore, Learn = understand, Decks = build,
Collection = own, Purchase = acquire. Same verb assignment as iOS
DESIGN.md §1.1 — transfers verbatim.

**Why:** verb collisions are structural bugs, not feature requests.
A web user navigates between tabs at the same conceptual rate as
an iOS user (every few minutes); inconsistent verb mapping between
platforms costs them every time they switch.

**How to apply:** if a feature feels like it could land in two
tabs, the one that owns the verb wins. Cross-cutting affordances
(scan, share, sign-in) follow §6 — not "drop the same UI in every
tab."

### 2.3 Navigation depth ≤ 2 inside a tab.

**Rule:** view → list → detail. Anything deeper is a parallel
filter axis or it belongs in a different tab.

**Why:** the web has cheaper navigation than iOS (browser back is
always available), but cheap navigation isn't free orientation. By
depth 3 the user no longer remembers what tab they're in or what
the back button will do. URL-driven view state means the URL bar
also gets harder to read.

**How to apply:** if a feature feels like it needs a third level,
it's actually a `<select>` filter inside the detail view OR a
parallel `<dialog>` that opens over the current view. Modals
opened over a view do **not** count as a third nav level (no back-
button drill, ESC dismisses).

### 2.4 Search is the universal navigator.

**Rule:** every tab whose content has a meaningful catalog has a
search input. Find owns the catalog-wide search; Learn searches
its articles; Decks searches the card pool; Collection searches
owned cards. The browser URL bar is a parallel search surface (URL
deep links to filtered views) — design URL params to be readable.

**No command palette (Cmd-K) for now.** The 8 keyboard-power-user
sites that justify a command palette (Linear, Raycast, Notion,
GitHub, Vercel, Stripe Dashboard, Slack, Figma) all have user
bases dominated by professional tool-runners. BOBA's audience is
trading-card collectors with phones; a command palette is not the
right cross-platform investment vs. tightening the per-tab
search inputs. Re-evaluate when desktop usage analytics justify it
or when one user explicitly asks.

**Why:** web users search-first by habit (URL bar, browser find,
in-page search). A buried filter is a design failure when the
catalog crosses ~50 items.

**How to apply:** every catalog ≥50 items gets a sticky-top search
input. URL params reflect the current filter state so the URL
shares as a deep link. Filters become URL-encodeable tokens (chip-
style on display) rather than nav levels.

### 2.5 Density comes from removing chrome, not adding affordances.

**Rule:** transfers verbatim from DESIGN.md §1.4 — three weights ×
two sizes = six hierarchy levels with zero added pixels. Every
divider, shadow, badge, and chip you remove makes the remaining
info read denser.

**Why:** same Tufte / Things 3 / Reeder lineage. The web's higher
pixel ceiling on desktop tempts more decoration; resist it.

**How to apply:** before adding visual chrome (border, shadow,
tinted background), try removing other chrome instead. The most
common offender on web is `background: rgba(255,255,255,0.05)`
sprinkled on rows for "separation." Use a `<hr>` or 8px of vertical
spacing instead.

### 2.6 Backdrop-filter is for navigation chrome only — content
stays unfiltered.

**Rule:** the web equivalent of DESIGN.md §1.5's Liquid Glass rule.
`backdrop-filter: blur()` on the mobile header, sidebar, and modal
backdrops — never on card grids, list rows, or content surfaces.

**Why:** layered backdrop-filter elements are GPU-expensive on
low-end Android (Chromium falls back to flat color silently above
~3 layers). Using it everywhere gets slow without making the chrome
feel any better. Restricting it to navigation surfaces preserves
the "frame, never compete" principle that DESIGN.md §1.5 codified.

**How to apply:**
- Header: `backdrop-filter: blur(8px); background: rgba(13, 13, 26, 0.85);`
- Sidebar: same treatment.
- `<dialog>::backdrop`: `backdrop-filter: blur(4px); background: rgba(0,0,0,0.6);`
- Card grid, rows, content panels: solid color from
  `--boba-surface`, no backdrop-filter.
- Wrap every backdrop-filter rule in
  `@media not (prefers-reduced-transparency: reduce)` — when the
  user prefers reduced transparency, drop to a flat color
  (`--boba-surface`) automatically.

---

## 3. The IA decision tree

Same shape as DESIGN.md §2 — different leaves.

| Question | Web leaf |
|---|---|
| Top-level mode of the entire app | Sidebar nav item in `#channels-sidebar` (max 6, not counting Profile) |
| Hierarchical drill-down with one path in / one back | `showView(name)` + `history.pushState`. Max 2 levels inside a tab |
| Parallel filter axis over the same data | Token-style filter chip ABOVE the content OR `<select>` inline. Never a new view |
| Contextual action that needs full focus | `<dialog>` + `showModal()` (gets native focus trap, ESC dismiss, `::backdrop` styling) |
| Glance-and-return action (filter, quick edit) | `<dialog>` with a smaller `max-width`, dismiss on click outside (ESC + backdrop click) |
| Side panel for inspection (iPad/desktop) | Skip — not a current target. Re-evaluate when desktop usage justifies a `NavigationSplitView` analog |
| Destructive / one-shot config | `<details>` overflow menu OR Popover API + `confirm()` for destructive |
| Global app state (active scan, draft) | N/A on web (scan is iOS-only; deck-draft persists to Supabase) — a `position: sticky` bottom strip is acceptable for in-progress state if/when needed |
| Cross-cutting capability (share, profile, sign-in) | See §6 |
| Inline option (toggle, one-of-several) | `<input type="checkbox">` / `<input type="radio">` / `<select>` inside a `<form>` |

**If you reach the bottom without a match, you don't need a new
view — you need to fold the feature into an existing one.** Same
principle as iOS.

---

## 4. Anti-patterns we reject

Each one with a concrete current-code or recently-burned example.

### 4.1 Pages that aren't pages.

JS-routed views without updating the URL or document title. Most
of `showView()` does this right today (URL gets `?view=...`); audit
that every `showView` call also updates `document.title` and that
the URL params are semantic enough to be shareable.
**Fix:** every view transition writes URL + title. URL params are
human-readable (`?view=collection&designation=grails`).

### 4.2 Dialog soup (modal opens a modal).

Same principle as iOS DESIGN.md §3.4. Two `<dialog>`s open at once
is a debugging nightmare and a focus-trap conflict.
**Fix:** dismiss the first dialog before opening the second. If you
need to chain (sign-in → continue purchase), use the same dialog
and swap its content.

### 4.3 Scroll prison.

Per DECISIONS.md #020 the body has `overflow: hidden` to prevent
Dynamic Island bleed in mobile Safari. That means every inner
scroll container needs:
- Keyboard scroll handling (PageDown / Home / End work).
- IntersectionObserver `root: <scrollContainer>` not `null`.
- Scroll restoration on view back (manual `scrollTop` save +
  restore via `popstate`).

### 4.4 Divitis.

`<div>` wrappers with no semantic meaning. Use `<section>`,
`<article>`, `<aside>`, `<nav>`, `<main>`, `<header>`, `<footer>`,
`<dialog>` where the meaning fits.
**Fix:** if a `<div>` exists only to apply a class, ask "what does
this represent?" If "a section of related content" → `<section>`.
If "a card" → `<article>`. If nothing semantic → keep the `<div>`,
but log it as a TODO during refactor.

### 4.5 Custom focus rings.

Overriding `:focus { outline: none; }` destroys keyboard
navigation for every user.
**Fix:** customize via `:focus-visible` only — that pseudo-class
fires for keyboard focus, not mouse click. Default to a 2px cyan
outline that respects `outline-offset`.

### 4.6 Fixed pixel sizing for typography.

Hard-coded `font-size: 14px` doesn't scale with the user's browser
text-size preference. Critical for users with visual impairments.
**Fix:** use `rem` for typography, `em` for component-relative
spacing. Hard pixels OK for borders, shadows, and small icons.

### 4.7 JS-rendered everything.

Pages that render nothing until JS runs are a parity gap with
shared-link expectations and a SEO nightmare. The user shares
`bobaplaybook.com/u/ben/grails`; the recipient should see *something*
before JS hydrates.
**Fix:** static HTML in `index.html` for first-paint shell + brand.
JS hydrates the dynamic content. The 404.html → SPA pattern
(DECISIONS.md #018) plus skeleton placeholders covers the gap.

### 4.8 Global event listeners that never get removed.

`document.addEventListener('click', ...)` inside a per-view init
function leaks across `showView()` transitions. Memory + double-
firing.
**Fix:** every per-view listener is removed in the view's teardown.
Or use event delegation at a stable root (`#main-content`) so a
single listener serves every view.

### 4.9 Hand-rolled dropdowns with click-outside listeners.

Captured by §2.1 native-first. The Popover API kills this entire
class of bug (auto-dismiss, focus, ESC, top layer all native).
**Fix:** every new dropdown uses `popover="auto"`. Existing
hand-rolled ones get migrated when touched.

### 4.10 `card.id` (and other unverified field assumptions).

The web cards.json ships `bobaId` (per CLAUDE.md "One ID per
Card"); iOS Card has a computed `var id` from the bobaId formula.
The multi-select V1 used `card.id` everywhere assuming parity, got
`undefined` on every card, and shipped a feature where only the
first card could be selected. Cost ~2 days.
**Fix:** when you start working with a new field, `console.log` an
example object before writing logic. When you assume parity with
iOS, look at the actual JSON. Use the `cardKey()` helper for card
identity going forward.

---

## 5. Density rules

Same six rules as DESIGN.md §4, web-translated:

1. **No tinted box backgrounds on content.** No
   `background: rgba(255,255,255,0.05)` on cards or rows. If a row
   needs separation from its neighbor, use `<hr>` or vertical
   spacing. If it needs separation from its container, the container
   gets `--boba-surface` — not the row.

2. **Three weights × two sizes.** Bebas Neue Bold for level 1
   (page title), Russo One for level 2 (section header), Chakra
   Petch Semibold for level 3 (body bold), Chakra Petch Regular for
   level 4 (body), Chakra Petch Light at small size for level 5
   (caption / de-emphasis), Chakra Petch monospace numerics for
   level 6 (tabular data). Refuse a seventh; refactor instead.

3. **Small multiples.** Every card grid uses the same `.card-item`
   class. Audit for one-off layouts when extending. The single
   `.card-item` should render in Find search, Collection grid,
   public-collection page, and Wall view without forks.

4. **Show the data; let the user filter it.** A persistent search
   input is denser than a category picker because it's zero-overhead
   access to everything.

5. **Progressive disclosure must be predictable.** `<details>` for
   inline, `showView()` for push, `<dialog>` for full-focus modal.
   Don't overload — a `<details>` that sometimes navigates instead
   of expanding destroys trust.

6. **The Gruber test.** Could a competent designer recreate this
   page from a one-paragraph description? If no, decoration; strip.

**Web-specific additions:**

7. **Container queries before media queries** for component
   responsiveness. The card cell adapts to its container, not the
   viewport, so it can render in the search grid (~140px wide), the
   sidebar recents ribbon (~80px), and the Wall view (~220px)
   without three separate components. Reserve `@media` queries for
   page-layout breakpoints (sidebar collapse, etc.).

8. **CSS custom properties for theming.** All colors, spacing, and
   font-family decisions live in `:root` `--boba-*` tokens. Never
   hard-code a color hex outside `:root`.

9. **`rem` for typography, `em` for component-relative spacing,
   `px` for borders/shadows.** See §4.6.

---

## 6. Material treatment + reduced-transparency parity

`backdrop-filter` rules from §2.6, expanded with reduced-
transparency handling.

**Standard treatment** (mobile header, sidebar, dialog backdrop):
```css
.surface-glass {
  background: rgba(13, 13, 26, 0.85);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);  /* Safari ≤ 17 */
}
@media (prefers-reduced-transparency: reduce) {
  .surface-glass {
    background: var(--boba-surface);  /* opaque fallback */
    backdrop-filter: none;
    -webkit-backdrop-filter: none;
  }
}
```

**Browser support** (per the §14 research): `backdrop-filter` is
Baseline since 2024. `prefers-reduced-transparency` is Newly
available 2024 — Chrome 118+, Safari 17.1+, Firefox 113+. Stable
across all three engines.

**Performance rules:**
- Maximum 3 layered `backdrop-filter` elements in any stacking
  context. Above that, GPU performance degrades on low-end Android.
- Never apply `backdrop-filter` to content that animates
  (transforms, opacity transitions). The compositor invalidates the
  filter region every frame.
- The mobile header, sidebar, and one open dialog count as 3
  layers — that's the ceiling.

**Reduced-motion parity:** every `transition:` and `animation:`
gets a `@media (prefers-reduced-motion: reduce)` override that
sets `transition: none; animation: none;`. View Transitions are
auto-disabled by the browser when reduced-motion is on — but
double-check via `@supports`.

---

## 7. Search-first IA

Per §2.4, every tab with a meaningful catalog has a search input.
Specifics:

- **Find:** sticky-top `<input type="search">` always visible. URL
  param `?q=...` reflects the query so search results share as deep
  links. Filter chips below the search input represent token-style
  filters (weapon, treatment, cost, format, set). Each chip is a
  `<button>` that toggles a URL param.
- **Learn:** in-view search input above the article list filters
  the corpus. URL param `?learn=...` reflects the query.
- **Decks:** the deck-pool view inherits Find's search shape but
  scoped to the current format's eligible cards.
- **Collection:** in-view search input filters owned cards.
  Combined with the active designation tab.

**Cross-tab search is NOT supported on web.** A user in Decks
searching for "Maverick" should not get Learn-article hits. The
sidebar's text input scope is tab-specific. (Re-evaluate if/when
we add a Cmd-K palette per §2.4.)

**Suggested tokens (autocomplete):** when the user types into a
catalog-aware search input, suggest tokens (weapon names, cost
values, hero names matching the typed prefix) below the input as a
Popover. Tap a suggestion → it becomes a chip. Same UX as iOS
DESIGN.md §6.5.

---

## 8. Cross-cutting capabilities (web)

iOS DESIGN.md §6.5 covers scan, share, profile/auth as cross-
cutting verbs. Web equivalents:

### 8.1 Scan — N/A on web.

Scanning requires camera access + on-device Vision OCR (DECISIONS.md
#012). Mobile-web Camera API exists but the OCR pipeline doesn't.
**Web users see scan results when iOS users share them via the
share-sheet.** Document this in the Find empty state ("Scan a card
in the iOS app to add it to your collection").

### 8.2 Share — Web Share API with copy-link fallback.

```js
async function shareTarget({ title, text, url }) {
  if (navigator.share) {
    try { await navigator.share({ title, text, url }); return; }
    catch (e) { if (e.name === 'AbortError') return; }
  }
  // Fallback: copy URL to clipboard + toast.
  await navigator.clipboard.writeText(url);
  showToast('Link copied to clipboard');
}
```

Trigger pattern: every shareable surface (card detail, deck detail,
collection wall) has a single Share button (top-right toolbar slot)
that fires this helper. The button is `<button>` with `aria-label`,
not an icon-only div.

### 8.3 Profile / Sign-in — sidebar nav item OR `<dialog>`.

Currently a sidebar nav item that opens a full view (`view-profile`).
Profile is fine as a view because it has multiple sections (Account,
Sharing, Security, Notifications, About) and benefits from a real
URL. **Sign-in is a `<dialog>` triggered by an inline `Sign In to do
this` row** at the point of action, OR by the Profile sidebar item
when the user is signed out.

**Auth-required vs auth-optional** (per iOS DESIGN.md §6.5):
- Optional: Find, Learn, Decks (draft), Collection browse, Purchase.
  No prompt; the feature works client-only.
- Required: Save deck, designate card, edit Profile.
  Inline `BOBASignInPrompt`-equivalent row at the action point with
  a Sign In button that opens the auth `<dialog>`.

**No app-launch sign-in wall, ever.**

### 8.4 Sharing target (recipient view).

When someone shares `bobaplaybook.com/u/{username}`, the recipient
sees the read-only public collection at that URL (already shipped
per DECISIONS.md #039). The recipient does not need to be signed
in. Only when they hit a write action (e.g., "Save to my Wanted")
does an inline sign-in prompt appear.

---

## 9. Per-screen-size adaptations

Mobile-first is the rule. The breakpoints below are the ONLY
canonical breakpoints — every `@media` query in the project must
use one of these unless there's a documented exception.

| Breakpoint | Width | Layout shape |
|---|---|---|
| Mobile | <768px | Single column. Sidebar hidden behind hamburger. Card grid auto-fills with min 110-155px cells. Filter panel collapsible. |
| Tablet | 768-1023px | Sidebar visible (pinned, 240px wide). Single content column. Card grid auto-fills with 155-180px cells. Filter panel persistent. |
| Desktop | 1024px+ | Sidebar visible (pinned, 280px wide). Single content column with wider max-width (1280px). Card grid auto-fills with 180-220px cells. Filter panel persistent in a sidebar slot if implemented. |

**Container queries replace media queries for component-level
responsiveness.** A card cell adapts to its container width via
`@container` rules, not viewport width. This lets the same cell
render correctly in the search grid (~140px), the sidebar recents
ribbon (~80px), and the Wall view (~220px) without forks.

**Two-column desktop layout (sidebar + detail like iPad's
NavigationSplitView)** is OUT OF SCOPE until desktop analytics
justify it. Today's web users are dominated by mobile. When this
changes, add a `@media (min-width: 1280px) { ... }` block that
splits the main content into a list-detail pattern using CSS Grid.

---

## 10. Universal states

Every list / grid / search / dialog defines behavior for four
states beyond happy path. Same shape as DESIGN.md §6.7.

1. **Loading.** Skeleton (3-5 placeholder rows shaped like real
   rows) for initial loads. Spinner only for operations >300ms.
   Never a full-screen spinner; loading happens *in place* so
   layout doesn't jump.

2. **Empty.** A `<div class="empty-state">` block with brand-voice
   copy + a productive next-action button. Bad: "No cards." Good:
   *"No cards in your collection yet — scan a card in the iOS app
   or browse Find to get started."* + button to Find.

3. **Error.** Inline `<div class="error-banner">` orange-bordered
   block above the action that failed. Always include a retry
   button for transient errors. Never silently fail. Network errors
   distinguished from server errors with different copy.

4. **Offline.** Subtle pill in the mobile header (bottom of
   sidebar on desktop) when `navigator.onLine === false`. Cached
   reads (catalog browse, owned-cards) work offline; cloud writes
   (save deck, designate card) disable with inline tooltip
   explaining what's offline-blocked.

Use the canonical helpers in `js/states.js` (TODO: extract from
inline patterns once the multi-tab refactor lands). Inconsistent
state handling is the #1 source of "feels janky" feedback.

---

## 11. First-run hints + walkthroughs — web does NOT get walkthroughs

**Decision (formerly TODO §12):** the iOS walkthrough engine
(DESIGN.md §6.10, 12 walkthroughs / ~40 anchored steps) does
**not** get a web equivalent.

**Why:**
1. iOS walkthroughs justify themselves because the tab bar +
   navigation gestures + bottom-sheet patterns are non-obvious to
   first-time iOS users. The web equivalents (sidebar nav, links,
   `<dialog>`) are universally understood.
2. The iOS rule (DESIGN.md §6.10 anti-pattern "slide-deck
   onboarding") was "teach with the real UI on the real screen."
   On web, the real UI **is** the screen the user lands on — there's
   no first-launch sequence to compete with.
3. Building a web walkthrough engine adds 400+ lines of overlay /
   anchor / persistence code for a feature whose value-add over
   inline help text is marginal.

**What we ship instead:** inline contextual help.
- A `?` icon in the top-right of complex views opens a `<dialog>`
  with a short explainer (3-5 sentences max).
- Empty states (§10) carry the productive-next-action that a
  walkthrough's first step would have shown.
- No `bp_walkthroughSeen_*` localStorage entries on web.

If a future feature genuinely demands per-step teaching (a future
practice executor, a complex multi-step workflow), revisit this
decision then — not preemptively.

---

## 12. Header + nav chrome standardization

Three chrome surfaces, three rules:

1. **Mobile header** (`<header class="mobile-header">`). Hamburger
   (left) + brand wordmark (center) + offline pill (right). Same
   on every view. Hidden on tablet/desktop. Pinned at top of body
   via `flex-shrink: 0`.

2. **Sidebar** (`<nav id="channels-sidebar">`). Brand wordmark
   (top) + nav items + sign-in state (bottom). Slides in from left
   on mobile (z-index 1200, above Leaflet map per the §8 fix).
   Pinned-visible on tablet/desktop.

3. **Per-view header** — every view's first DOM child is a
   `<header class="view-header">` with: title (`<h1 class="view-
   heading">`), optional actions (right-aligned `<button>`s), and
   optional sticky context (search input, designation picker).
   Standardize this pattern across all views; the current code is
   inconsistent.

**No floating action buttons (FABs).** The FAB pattern is iOS-
specific (`.tabViewBottomAccessory`); web uses the toolbar slot or
the sticky per-view header.

---

## 13. Forward-compatibility — modern web standards adoption

Per the §14 research, the 2026 web platform is mature enough to
adopt the following. Each row names the feature, its Baseline
status, and the BOBA-specific use case. Adopt = build new code on
it; Wait = use a fallback; Skip = not for us.

| Feature | Baseline | Verdict | Use case in BOBA |
|---|---|---|---|
| **View Transitions API (same-document)** | Newly available 2024 | **ADOPT** | Wrap `showView()` in `document.startViewTransition()` for tab→tab transitions. Add `view-transition-name: card-{bobaId}` to grid cells + detail view to mirror iOS hero zoom. ~20 lines of CSS+JS. |
| **Container Queries (`@container`)** | Widely available 2024 | **ADOPT** | The `.card-item` cell adapts to its container (search grid / Wall / sidebar ribbon) via `@container` rules — no media-query forks. |
| **CSS `:has()`** | Widely available 2023 | **ADOPT** | Kill the JS class-toggle pattern (e.g., `.card-grid:has(.card-item--selected) { ... }` to dim non-selected cards in multi-select mode). |
| **Popover API** | Newly available 2024 | **ADOPT** | Every dropdown / autocomplete / tooltip uses `popover="auto"`. Auto-dismiss + focus + ESC + top-layer all native. |
| **`<dialog>` + `showModal()`** | Widely available 2023 | **ADOPT** | Every modal uses `<dialog>`. Card detail, Profile sheet (when not a view), sign-in, share fallback. Native focus trap + ESC + `::backdrop` styling. |
| **CSS Anchor Positioning** | Limited (Firefox holdout) | **WAIT** | Tooltip / popover positioning. Use Popover API + JS positioning (Floating UI pattern) until Firefox ships. Re-evaluate late 2026. |
| **Web Share API** | Limited (no Firefox; no Chrome desktop) | **ADOPT with fallback** | Share verb (§8.2). Feature-detect, fall back to `navigator.clipboard.writeText` + toast. |
| **CSS Nesting** | Widely available 2024 | **ADOPT** | Refactor `css/styles.css` to use native nesting — no preprocessor needed. |
| **CSS Subgrid** | Widely available 2024 | **ADOPT** | Canonical 6-cell card-stat grid (DECISIONS.md #029) where parent grid defines columns and child sections inherit them. |
| **CSS Scroll-driven Animations** | Limited (Chrome only) | **SKIP / progressive enhancement** | Scroll-edge fade on card grid analog to iOS `.scrollEdgeEffectStyle`. Gate with `@supports (animation-timeline: scroll())`. |
| **PWA Manifest basics** | Universal | **ADOPT** (already shipped) | Install prompt, homescreen icon. |
| **PWA Badging API + share_target** | Limited (no Safari/iOS) | **SKIP** | Audience is iOS-heavy via the iOS app; investing in Chrome-only PWA features is low ROI. |
| **`prefers-reduced-motion`** | Widely available 2020 | **BINDING** | Every transition/animation has a reduce override. |
| **`prefers-reduced-transparency`** | Newly available 2024 | **BINDING** | Drop `backdrop-filter` to flat color when set (§6). |

**Roadmap consequence:** §15 lists which existing modules need
which adoption. Don't refactor speculatively — do it when the
relevant view is being touched anyway.

---

## 14. Per-tab IA recipes

iOS DESIGN.md §8 has detailed per-tab recipes. Web equivalents:

### 14.1 Find — the explorer

**Verb:** explore.

**Anatomy:**
- Sticky-top `<header class="view-header">` with brand wordmark +
  Profile gear (top-right).
- `<input type="search">` below the header, also sticky on scroll.
- Filter chips row below search (token-style: weapon, treatment,
  cost, format, set). Each chip is a `<button>` toggling a URL
  param.
- Card-size picker (S/M/L per the v2.082 redesign).
- Card grid: `.card-grid` with auto-fill `minmax` per density.
- Tap card → opens card-detail `<dialog>` (NOT a new view) with
  full info, pricing, comps, add-to-collection, add-to-current-deck.
- Multi-select via the Select pill + drag-marquee + shift-click +
  long-press (per the v2.085 fixes).

**Anti-patterns to avoid:** filter pills above the grid that aren't
URL-encoded. Multiple "browse by" pickers — use scopes inside the
search instead.

### 14.2 Learn — the educator

**Verb:** understand.

**Anatomy:**
- Single-stream article rendering (`<article>` per Learn entry).
- Skill-level scope (Rookie / Substitution / Playmaker) as a
  segmented control INSIDE each article (not a top-level filter).
- Read/Watch toggle inline within an article when the article has a
  video version; hidden when text-only.
- Sticky search above the article list.
- Glossary lookup as a Popover triggered by `?` icon in the
  top-right.

**Anti-patterns to avoid:** card details rendered inside Learn.
Learn is purely educational; card details belong in Find / Decks /
Collection.

### 14.3 Decks — the builder

**Verb:** build.

**Anatomy:**
- Web does NOT replicate the iOS Music-pattern pill + zoom editor
  (DESIGN.md §8.3). Web uses a side-by-side pool + slot pattern:
  - Left column (~60% width on desktop): card pool grid with search
    + format chips + filter chips.
  - Right column (~40% width on desktop): current deck list
    grouped by Hero / Plays / Bonus / Hot Dogs with stat counts at
    top.
- On mobile (<768px): pool and deck stack vertically; deck list
  appears in a `position: sticky` summary at the bottom that
  expands on tap into a `<dialog>` (the web analog of the iOS pill
  → fullScreenCover).
- Save / Manage / Rules / Legality live in an overflow menu in the
  view-header.

**Why a different pattern from iOS:** the iOS rule (DESIGN.md
§8.3) was "Music's mini-player + fullScreenCover" because iOS has
no native side-by-side layout in compact width. The web on desktop
has the screen real estate for genuinely-side-by-side without
modals — use it.

### 14.4 Collection — the owner

**Verb:** own.

**Anatomy:**
- Designation segmented control (Personal / For Sale / For Trade /
  Wanted / Grails) at the top of the view.
- Sticky search input below.
- Display mode picker (Grid / List / Wall) — same options as iOS
  DESIGN.md §8.4.
- Card grid uses the canonical `.card-item`.
- Each cell shows the designation badge as a corner overlay so
  multi-designation cards are scannable across scopes.
- Public-collection sharing toggle + URL copy in the Profile view
  (already shipped per DECISIONS.md #039).
- Wall display mode renders all visible cards as a single tile-able
  image (parity with iOS DESIGN.md §8.8). Per-designation defaults
  for Price Overlay match iOS.

**Anti-patterns to avoid:** burying the public-collection URL.
Anyone toggling sharing on should immediately see the URL with a
copy button (already shipped — codified here).

### 14.5 Purchase — the acquirer

**Verb:** acquire.

**Anatomy:**
- Two segmented sections (segmented control at top): "Upcoming
  Breaks" + "Find a Store".
- Upcoming Breaks: vertical list of break tiles with host, time,
  viewer count. Tap → deep link to Whatnot.
- Find a Store: Leaflet map + scrollable store list below. Per the
  v2.067 fix, the sidebar overlay z-index is above the Leaflet
  panes so the nav drawer doesn't disappear behind the map.

**Anti-patterns to avoid:** sidebar overlap with map (already fixed
v2.067 — codified here).

---

## 15. Roadmap — refactors implied by ratifying this doc

Now that §2-§14 are binding, the existing web app drifts from
several rules. This is the prioritized work list. Each item names
the rule it addresses and the rough effort.

### P0 (touched the next time the relevant view is edited)

1. **Replace hand-rolled dropdowns with Popover API.** Currently
   the filter panel toggle + designation picker + a few overlay
   menus use click-outside JS. (§4.9 + §13 Popover ADOPT). ~1 day
   each, do as part of the next refactor that touches the view.

2. **Migrate modal overlays to `<dialog>`.** Card detail modal,
   sign-in modal, share fallback. (§4.10 + §13 dialog ADOPT). ~2
   hours each.

3. **Add `prefers-reduced-transparency` overrides** to every
   `backdrop-filter` rule. (§6 + §13 BINDING). ~30 min sweep.

### P1 (planned refactor)

4. **Wrap `showView()` in View Transitions.** Add `view-
   transition-name` to card grid cells + detail. (§13 ADOPT). ~1
   day. Highest visual-impact item.

5. **Container query refactor of `.card-item`.** Same cell renders
   in search / Wall / public-collection / sidebar without forks.
   (§13 ADOPT). ~1 day.

6. **CSS Nesting refactor of `css/styles.css`.** Cleaner without a
   build step. (§13 ADOPT). ~half day.

### P2 (when a feature requires it)

7. **Decks side-by-side desktop layout** (§14.3) — currently the
   web Decks tab doesn't follow this pattern. Refactor when Decks
   tab gets touched substantively.

8. **Collection Wall display mode** (§14.4) — parity with iOS
   DESIGN.md §8.8. Build when Collection tab is the focus.

9. **Profile picture upload** — separate work item; touches both
   web and iOS. Not blocked on this doc.

### Deferred (rationale below in §17)

- Walkthroughs on web (§11 — explicit no).
- Cmd-K command palette (§2.4 — re-evaluate later).
- Web Push notifications (out of scope; iOS APNs is the canonical
  surface).
- Two-column desktop split-view (§9 — wait for analytics).

---

## 16. Visual primitives — components + colors

Components (CSS classes) the web app composes from. Adding a new
view = composing existing primitives. Inventing a new primitive =
first edit this section.

| Class | Purpose | Used in |
|---|---|---|
| `.card-item` | Canonical card cell — uniform aspect, padding, badge placement (§5.3 small multiples). | Every card grid: Find, Collection, Wall, public-collection. |
| `.card-grid` | Auto-fill grid container with density-aware `minmax`. | Every card grid. |
| `.view-header` | Title + actions + optional sticky context. | Every view's first child. |
| `.profile-section` | Grouped settings block — uppercase label + content. | Profile view sections. |
| `.profile-stat-list` | List container inside `.profile-section`. | Profile rows. |
| `.profile-toggle-row` | Settings toggle with title + sub + native switch. | Profile sharing/notification toggles. |
| `.empty-state` | Empty-state block with copy + productive action. | Every list/grid empty state. |
| `.error-banner` | Orange-bordered inline error message. | Every action that can fail. |
| `.offline-pill` | Subtle "Offline" pill in mobile header. | Mobile header always; desktop top-right when offline. |
| `.app-toast` | Bottom-center transient confirmation. | Bulk-add operations, copy confirmations. |
| `.multiselect-toolbar` | Floating action toolbar for bulk operations. | Find tab when ≥1 card selected. |
| `.marquee-rect` | Drag-selection rectangle. | Find tab during marquee drag. |
| `.btn-primary` | Primary CTA button (orange). | Save, Sign In, primary actions. |
| `.btn-ghost-sm` | Secondary muted button. | Cancel, dismiss, secondary actions. |
| `.quick-add-pill` | Toolbar pill (Quick Add, Select). | Find results bar. |

**Rule:** if you're about to write a custom-styled component that
overlaps with one of these, use the primitive. If the primitive
doesn't quite fit, edit the primitive (and document the change
here) — never one-off.

**Color tokens** — same brand vs element split as iOS DESIGN.md
§11.2. Brand: `--boba-orange #FF4D00`, `--boba-cyan #00F5FF`,
`--boba-violet #8B00FF`, `--boba-near-black #080810`,
`--boba-surface #0D0D1A`. Element semantic colors per `--el-*`
tokens. Never use a brand color for content meaning; never use an
element color for navigation chrome. The orange/FIRE overlap is
intentional (DESIGN.md §11.2).

---

## 17. Out of scope (intentionally)

Documented so future sessions don't re-add these as parity gaps.

| Feature | Why out of scope |
|---|---|
| **Walkthroughs / first-run tutorials** | §11 — web's primitives are universally understood; inline contextual help is sufficient. |
| **Cmd-K command palette** | §2.4 — BOBA's audience isn't keyboard-power-users. Re-evaluate when desktop usage analytics justify it. |
| **Web Push notifications** | iOS APNs is the canonical match-alerts surface (DECISIONS.md #039). Web push has different infrastructure, weaker UX. Skip. |
| **Build step (Vite, esbuild, TypeScript transpile)** | §1 locked decision — no build step ever. Native CSS Nesting + JSDoc remove the last reasons to want one. |
| **Two-column desktop split-view** | §9 — wait for desktop usage analytics. |
| **PWA Badging + share_target** | §13 — Safari iOS doesn't ship them; investment is low ROI vs the iOS app. |
| **Custom-domain branding for shared collections** (`ben.bobaplaybook.com`) | Out of scope — `bobaplaybook.com/u/ben` is sufficient. |
| **Camera scan on mobile web** | DECISIONS.md #012 — on-device Vision OCR is iOS-only. |
| **Practice executor on web** | DESIGN.md §12 — different design language; iOS-only when shipped. |
| **Native iOS hero-zoom emulation** | View Transitions API gives us a web-native equivalent (§13). Don't try to emulate the iOS exact behavior — use the platform's primitive. |
| **`.tabViewBottomAccessory` analog** | iOS-specific. The mobile header + per-view sticky chrome cover the web's needs. |

The rule for adding to this list: when a feature is intentionally
not-designed, add the entry. The existence of an "Out of scope"
entry tells future sessions "we thought about this and chose not
to design it now."

The rule for removing from this list: when the feature comes into
scope, draft its design rules in the appropriate section and remove
the out-of-scope entry. Don't leave stale "future" markers.

---

## 18. The daily review test

Same shape as DESIGN.md §10. Before any feature ships, three
checks:

1. **The Gruber test** (§5.6): could a competent designer recreate
   this page from a one-paragraph description?
2. **The verb test** (§2.2): what verb does this surface own? Is
   it colliding with a verb owned by a different tab?
3. **The depth test** (§2.3): count nav levels from the sidebar
   nav. If > 2, the third level should be a `<select>`, a
   `<dialog>`, or a different tab.

When the answer to any of these is "no" or "I'm not sure," reread
the relevant section. When the document is silent or contradicts
itself, the document is wrong — propose an edit before
proceeding.

---

## 19. Parity-checking workflow when iOS ships changes

Process when an iOS change lands that's not pure implementation
detail:

1. Author of the iOS change updates SCRATCHPAD.md feature-parity
   table to mark the relevant feature as iOS-only or both.
2. If the change introduces new design patterns:
   - If it refines a principle already in this doc, no further
     action.
   - If it introduces a new pattern, add an entry here as a TODO
     for the web equivalent, OR explicitly add it to §17 if web
     shouldn't pursue it.
3. Periodic (~monthly) audit: compare iOS DESIGN.md last-modified
   sections against this doc.

This workflow is intentionally lightweight — heavyweight process
will get skipped, and the parity gap will widen silently.

---

## 20. References

Validated sources backing this document.

**Design language:**
- [Refactoring UI](https://www.refactoringui.com/) — visual hierarchy + density
- [Things 3 design](https://culturedcode.com/things/) — single-pane density references
- [Linear's design system](https://linear.app/method) — modern dark-theme density
- [Vercel's design system](https://vercel.com/design) — modern web typography
- [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/) — for principles to translate

**Modern web standards:**
- [web.dev/baseline](https://web.dev/baseline) — Baseline-supported feature catalog
- [web.dev/articles/view-transitions](https://web.dev/articles/view-transitions) — page transitions
- [MDN Container Queries](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_containment/Container_queries)
- [MDN Popover API](https://developer.mozilla.org/en-US/docs/Web/API/Popover_API)
- [MDN dialog element](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/dialog)
- [MDN Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API)
- [MDN `:has()`](https://developer.mozilla.org/en-US/docs/Web/CSS/:has)
- [MDN `prefers-reduced-transparency`](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-transparency)

**Accessibility:**
- [WCAG 2.2 AA](https://www.w3.org/WAI/WCAG22/quickref/?levels=a%2Caa)
- [Inclusive Components](https://inclusive-components.design/) by Heydon Pickering
- [APG Authoring Practices](https://www.w3.org/WAI/ARIA/apg/) — patterns for native-feel widgets

**Performance:**
- [web.dev/measure](https://web.dev/measure) — Core Web Vitals
- [PageSpeed Insights](https://pagespeed.web.dev/) — site-specific testing

**PWA:**
- [web.dev/articles/learn/pwa](https://web.dev/articles/learn/pwa) — fundamentals
- [Service Worker recipes](https://web.dev/articles/offline-cookbook)

**Reference implementations to study:**
- iOS DESIGN.md (this repo's binding doc — for principles to translate)
- bsky.app web (reference for vanilla-JS dark-theme density at scale)
- linear.app (reference for command-K + density when re-evaluating §2.4)
- raycast.com (reference for keyboard-first interaction patterns when relevant)
