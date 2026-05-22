# BOBA Playbook — Web Design

> **Binding.** Every new view/dialog/sidebar item/grid in the web app must trace to a rule here. Fix the document, then the feature.
>
> Companion to [`DESIGN.md`](./DESIGN.md) (iOS), [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md) (Android), [`CLAUDE.md`](./CLAUDE.md), [`DECISIONS.md`](./DECISIONS.md), [`PARITY.md`](./PARITY.md) (cross-platform feature matrix). DESIGN.md governs cross-platform principles; this doc owns web-specific implementation rules.
>
> Ratified 2026-05-05 from the prior research plan. Cross-references to ANDROID-DESIGN.md added 2026-05-19.

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

## 1. Web-specific constraints

Non-negotiable inputs:

- **GitHub Pages static hosting** — no server runtime, no Node.js. SSR/build-step out unless we migrate hosts.
- **Vanilla HTML/CSS/JS** (DECISIONS.md #001) — no framework, no build step. Plain DOM, plain CSS, ES2022+, Supabase SDK via CDN. No npm/bundler/TS transpile.
- **Mobile-first.** 375px before 1440px.
- **WCAG AA from line one.**
- **Body flex-column** (DECISIONS.md #020) — no `viewport-fit=cover`, no fixed headers, no `position:fixed` overlays.
- **Feature parity** (DECISIONS.md #005) with web-as-own-discipline carve-out (DESIGN.md §12). Don't chase iOS-specific patterns when a better web-native exists.

**Locked decisions:**

- **No build step, ever.** Native CSS Nesting + Container Queries + `:has()` killed Sass/PostCSS need. JSDoc + `// @ts-check` covers 80% of TS without transpile.
- **GitHub Pages stays.** 17k cards / ~5MB JSON ships fine through Pages CDN. Re-evaluate only if catalog crosses 50MB or we need server runtime that can't be a Cloudflare Worker.

---

## 2. The six binding principles

Each rule names the iOS DESIGN.md §1 equivalent then specifies the web form.

### 2.1 Native first.

**Rule:** every interaction = built-in HTML element or browser API before custom code.

- `<dialog>` + `showModal()` before custom modal overlays
- `<input type="search">` before custom search bars
- Popover API before hand-rolled dropdowns + click-outside listeners
- `<details>`/`<summary>` before custom collapsibles
- View Transitions API before custom cross-view animation
- `<form>` native validation (`required`, `pattern`, `:invalid`) before inline JS errors
- CSS `scroll-snap` before JS scroll-tracking
- Container Queries before viewport-only `@media`

**Why:** the v2.0xx failure mode was reaching for custom code (overlay divs, hand-rolled dropdowns, state-class toggles) when a baseline-supported native API existed. The 2026 baseline platform is nearly as expressive as the iOS SDK.

**Apply:** before writing a component, ask "is there a native API that does 80% of this?" Yes → build on it, accept native behavior. Fallback = graceful degradation (`@supports`, feature-detect) — not framework polyfills.

### 2.2 Each tab owns one verb.

Find = explore · Learn = understand · Decks = build · Collection = own · Purchase = acquire (verbatim from DESIGN.md §1.1). Verb collisions are structural bugs. Cross-cutting affordances (scan/share/sign-in) follow §8.

### 2.3 Navigation depth ≤ 2 inside a tab.

view → list → detail. Anything deeper = parallel filter axis (`<select>` inline) or different tab. Modals over a view do NOT count as a third nav level (no back-button drill, ESC dismisses). Web has cheap nav but not free orientation — depth 3 = user no longer knows what tab they're in.

### 2.4 Search is the universal navigator.

Every catalog ≥50 items gets a sticky-top search input. URL params reflect filter state so URLs share as deep links. Filters = URL-encodable tokens (chip-style display), not nav levels.

**No Cmd-K palette for now.** Justifying audiences (Linear, Raycast, Notion) are pro tool-runners; BOBA's audience is collectors with phones. Re-evaluate when desktop analytics justify or a user asks.

### 2.5 Density comes from removing chrome.

Verbatim from DESIGN.md §1.4. Web's desktop pixel ceiling tempts more decoration; resist. Most common offender: `background: rgba(255,255,255,0.05)` on rows for "separation." Use `<hr>` or 8px vertical spacing.

### 2.6 Backdrop-filter = navigation chrome only.

Web equivalent of DESIGN.md §1.5 Liquid Glass. `backdrop-filter: blur()` on mobile header, sidebar, modal backdrops — never on grids/rows/content. Layered backdrop-filter is GPU-expensive on low-end Android (Chromium falls back to flat color silently above ~3 layers).

**Apply:**
- Header / sidebar: `backdrop-filter: blur(8px); background: rgba(13,13,26,0.85);`
- `<dialog>::backdrop`: `blur(4px); background: rgba(0,0,0,0.6);`
- Grid / rows / content: solid `--boba-surface`, no filter.
- Every rule wrapped in `@media not (prefers-reduced-transparency: reduce)` — drop to flat color when set.

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
| Global app state (active scan, draft) | Scan view is sidebar destination (DECISIONS.md #054); deck-draft persists to Supabase. A `position: sticky` bottom strip is acceptable for in-progress state if/when needed |
| Cross-cutting capability (share, profile, sign-in) | See §6 |
| Inline option (toggle, one-of-several) | `<input type="checkbox">` / `<input type="radio">` / `<select>` inside a `<form>` |

**If you reach the bottom without a match, you don't need a new
view — you need to fold the feature into an existing one.** Same
principle as iOS.

---

## 4. Anti-patterns we reject

- **Pages that aren't pages.** Every `showView()` writes URL + `document.title`. URL params are human-readable (`?view=collection&designation=grails`) so links share.
- **Dialog soup.** Two `<dialog>`s open at once = focus-trap conflict. Dismiss the first before opening the second; for chained flows, swap content in the same dialog.
- **Scroll prison.** Per DECISIONS.md #020 body has `overflow: hidden`. Every inner scroll container needs: keyboard scroll (PgDn/Home/End), IntersectionObserver `root: <scrollContainer>` (not null), `popstate` scroll-restore.
- **Divitis.** Use `<section>`, `<article>`, `<aside>`, `<nav>`, `<main>`, `<header>`, `<footer>`, `<dialog>` where they fit. `<div>` only when no semantic element does.
- **Custom focus rings.** Never `outline: none`. Customize via `:focus-visible` only (keyboard focus, not mouse click). Default 2px cyan outline + `outline-offset`.
- **Fixed-px typography.** `rem` for type, `em` for component-relative spacing. Hard px OK for borders / shadows / small icons.
- **JS-rendered everything.** Static HTML shell + brand in `index.html`; JS hydrates dynamic content. 404.html → SPA pattern (DECISIONS.md #018) + skeleton placeholders covers shared-link paint.
- **Leaky global event listeners.** Per-view listeners removed in teardown, or use event delegation at a stable root (`#main-content`).
- **Hand-rolled dropdowns + click-outside.** Use `popover="auto"`. Existing hand-rolled migrate when touched.
- **Unverified field assumptions** (e.g. `card.id`). Web cards.json ships `bobaId` (CLAUDE.md "One ID per Card"). `console.log` an example before writing logic; use the `cardKey()` helper for card identity.

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
- **Decks:** the deck-builder card-browser view inherits Find's
  search shape but scoped to the current format's eligible cards.
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

### 8.1 Scan — sidebar destination (DECISIONS.md #054).

Web Scan is a fallback + adjunct surface, not a replacement for
the canonical iOS Vision / Android ML Kit on-device path. The
sidebar entry is real (re-surfaced 2026-05-22 per beta-tester
request); three responsibilities:

1. **Mobile-web camera capture** — `getUserMedia` → frame →
   Cloudflare Worker OCR. Experimental; less performant than
   on-device but functional for users without the native apps.
2. **Desktop → phone QR handoff** — desktop browsers see a QR
   encoding `?view=scan&rt={refresh_token}`. Phone scans →
   opens BOBA on phone with desktop session carried over.
   Refresh token regenerates every 30s.
3. **Native-app gateway** — TestFlight (iOS) + Google Play
   (Android) CTA tiles surfaced inside the Scan view. Reuse
   `nativeAppCalloutHTML()` in `js/app.js` for any other
   surface that wants to advertise the native apps; don't
   re-invent.

**Anti-patterns:**
- Surfacing the camera path as "the way to scan." It's a
  fallback — the native apps are canonical. Copy + CTAs should
  always present the native apps as the better option.
- Hardcoding TestFlight / Play Store URLs anywhere outside
  `nativeAppCalloutHTML()`. One source of truth.

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

The iOS walkthrough engine (DESIGN.md §6.10) does not get a web equivalent.

**Why:** (1) iOS patterns (tab bar, gestures, bottom sheets) are non-obvious to first-time users; web primitives (sidebar nav, links, `<dialog>`) are universally understood. (2) On web, the real UI IS the screen the user lands on — no first-launch sequence to compete with. (3) ~400 lines of overlay/anchor/persistence code for marginal value-add over inline help.

**Ship instead:** `?` icon in top-right of complex views → `<dialog>` with 3-5 sentence explainer. Empty states (§10) carry the productive-next-action a walkthrough's first step would have shown. No `bp_walkthroughSeen_*` localStorage entries on web.

Revisit if a future feature (practice executor, complex multi-step workflow) genuinely demands per-step teaching.

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
  (DESIGN.md §8.3). Web uses a side-by-side browser + deck pattern:
  - Left column (~60% width on desktop): card-browser grid with
    search + format chips + filter chips.
  - Right column (~40% width on desktop): current deck list
    grouped by Hero / Plays / Bonus / Hot Dogs with stat counts at
    top.
- On mobile (<768px): browser and deck stack vertically; deck list
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

### Shipped 2026-05-05

- **Popover API** for designation/deck pickers in multi-select bulk-add (`window.bobaShowPopoverMenu` helper). Filter panel stays inline-accordion. Mod panels would fit `<dialog>` better when migrated.
- **`<dialog>` migration** for all three modal overlays: card-detail, auth, add-collection. Native focus trap + ESC + top-layer + `::backdrop` scrim. Mod panels (admin) deferred — working correctly.
- **`prefers-reduced-transparency` overrides** in single `@media` block at top of styles.css; drops backdrop-filter on chrome surfaces, bumps to opaque `--boba-surface`.
- **View Transitions** in `showView()` — feature-detected + `prefers-reduced-motion` aware. `openModalWithHeroZoom` pairs grid cell with modal hero via `view-transition-name: card-hero` (iOS hero-zoom analog).
- **Container queries** on `.card-item` — `container-type: inline-size; container-name: card-cell;` with `@container` blocks for typography scaling. Same cell at S/M/L density without media-query forks; inherited by public-collection grid.
- **CSS Nesting pattern** established (incremental, on new popover CSS). Full rewrite of 9000-line file deferred.
- **Web Share API** — `shareTarget({title,text,url})` helper / `window.bobaShareTarget`. `navigator.share` when available, `clipboard.writeText` + "Link copied!" fallback. AbortError silenced.
- **Profile picture upload** — DECISIONS.md #040.

### Shipped 2026-05-20 (autonomous parity loop)

- **Wall view** (§14.4 / DESIGN.md §8.8) — canvas-rendered share image (1080×1080) of any Collection scope. Per-designation overlay defaults match iOS (For Sale / Trade / Wanted ON · Personal / Grails OFF). Web Share API + clipboard fallback. R2 CORS configured for `crossOrigin='anonymous'` so `toBlob` doesn't taint the canvas. Tick 5.
- **Price Overlay** in Wall view — live re-renders on toggle without image reload via `drawWall({showPrices, source})` closure. Tick 6.
- **Custom Rainbows** (read-only display) — `fetchCustomRainbows()` + `rainbowCriteriaMatches()` verbatim port of iOS RainbowCriteria. Render shared with auto-rainbows via `_renderRainbowRow`. Tick 7.
- **Per-hero Auto Rainbows** — synthesized one-row-per-owned-hero × catalog, sorted by completion % desc. Tick 8.
- **Decks "Generate deck wall"** — `db-wall-btn` in deck-builder toolbar reuses the canvas Wall pipeline via a deck-context branch on `openWallSheet` (catalog Cards directly, no user-card-row resolution, price overlay disabled). Tick 9. **Also fixed** `window.Collection` exposure — classic-script `const` at top level doesn't auto-promote to the global object, which made `window.Collection.quickAdd` in app.js silently broken too.
- **Find multi-select → "Wall these N cards"** — closes the §8.8 wall trio. New `multiselect-wall` action in the bulk-select toolbar calls the same shared `openCardsWallSheet({ title, cards })`. Selection mode stays active so the user can continue without re-selecting. Tick 10.
- **Card-style deck-template gallery** (§14.3 empty-state — parity with iOS DeckBuilderView.TemplateCard) — 44×60 monogram tile with per-archetype accent color (STEEL / ICE / CYAN / GLOW / BRAWL) + name + description + format pill + chevron. Replaces the prior row of plain text buttons. Click handler accepts both the new `.db-template-card` and legacy `.db-template-btn` selectors so cached pages don't break. Tick 11.

### P2 (when a feature requires it)

- **Decks side-by-side desktop layout** (§14.3) — refactor when Decks gets touched substantively.

### Deferred (see §17)

Walkthroughs on web · Cmd-K palette · Web Push · Two-column desktop split-view.

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
<!-- Tick 2026-05-22: Camera scan on mobile web removed from out-of-scope per DECISIONS.md #054. Web Scan is now a sidebar destination — fallback + QR handoff + native-app gateway. iOS Vision / Android ML Kit remain canonical. See WEB-DESIGN.md §8.1 for the new spec. -->
| **Practice executor on web** | DESIGN.md §12 — different design language; iOS-only when shipped. |
| **Native iOS hero-zoom emulation** | View Transitions API gives us a web-native equivalent (§13). Don't try to emulate the iOS exact behavior — use the platform's primitive. |
| **`.tabViewBottomAccessory` analog** | iOS-specific. The mobile header + per-view sticky chrome cover the web's needs. |
| **Twitter / X integration (any form)** | DECISIONS.md #053 — binding. No `twitter:*` Card meta tags, no `twitter.com` share intents, no Twitter OAuth, no Twitter SDK / API, no "Share to Twitter" buttons. The OG protocol covers every other major link-preview consumer. |

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

- **Design language:** [Refactoring UI](https://www.refactoringui.com/) · [Linear](https://linear.app/method) · [Vercel](https://vercel.com/design) · [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/)
- **Web standards:** [web.dev/baseline](https://web.dev/baseline) · [View Transitions](https://web.dev/articles/view-transitions) · [Container Queries](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_containment/Container_queries) · [Popover API](https://developer.mozilla.org/en-US/docs/Web/API/Popover_API) · [`<dialog>`](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/dialog) · [Web Share](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API) · [`:has()`](https://developer.mozilla.org/en-US/docs/Web/CSS/:has) · [`prefers-reduced-transparency`](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-transparency)
- **Accessibility:** [WCAG 2.2 AA](https://www.w3.org/WAI/WCAG22/quickref/?levels=a%2Caa) · [Inclusive Components](https://inclusive-components.design/) · [APG](https://www.w3.org/WAI/ARIA/apg/)
- **Performance / PWA:** [web.dev/measure](https://web.dev/measure) · [PageSpeed Insights](https://pagespeed.web.dev/) · [Learn PWA](https://web.dev/articles/learn/pwa) · [Offline cookbook](https://web.dev/articles/offline-cookbook)
- **Study:** iOS DESIGN.md · bsky.app (vanilla-JS dark density) · linear.app (Cmd-K) · raycast.com (keyboard-first)
