# BOBA Playbook — Web Design (Research Plan)

> **Status: research plan, not a finished design doc.** This document
> captures the questions to answer, sources to read, and decisions to
> make before WEB-DESIGN.md becomes binding the way DESIGN.md is.
>
> When a section here is researched and ratified, replace its TODO
> block with the binding rule, the same way DESIGN.md is structured
> (rule first, "Why" + "How to apply" lines below). Until then,
> nothing in this document is binding — DESIGN.md governs both
> platforms by default, and web defers to it for any decision a
> reasonable native-pattern translates to.
>
> Companion to [`DESIGN.md`](./DESIGN.md) (binding iOS doc),
> [`CLAUDE.md`](./CLAUDE.md) (project context), and
> [`DECISIONS.md`](./DECISIONS.md) (architecture log).

---

## 0. Why this document exists

Per CLAUDE.md, the project is dual-platform with a feature-parity
contract. Per DESIGN.md §12, **web design is explicitly out of scope
for that document** — "Web has different constraints — no Liquid
Glass, no `.tabViewBottomAccessory`, GitHub Pages static-only. Some
principles transfer (verb per tab, search-first IA) but the
implementation patterns don't."

The recurring failure mode without a web design doc:
1. iOS ships a native-pattern UX (e.g., the Music-pattern Decks
   editor with hero zoom)
2. The web app is told to "achieve parity"
3. We try to recreate the iOS pattern in JS/CSS, fall short of the
   native fluidity, ship a worse-feeling version that's both off-
   brand AND off-platform
4. Or we ignore the parity request and the two surfaces drift

WEB-DESIGN.md should answer: **what is the web app's design language,
on its own terms, that consistently produces an experience as good as
the iOS app — not the same, just as good?**

## 0.1 How to use this plan

1. **Pick a section** that's currently a TODO block.
2. **Research the linked sources** + sample 3-5 reference sites that
   exemplify what we'd want.
3. **Draft the binding rule** in the same style as DESIGN.md (the
   rule, then `**Why:**` + `**How to apply:**`).
4. **Run it past Ben.** If approved, replace the TODO block with the
   ratified rule and remove this document's "research plan" framing
   for that section.

When all sections are ratified, drop section 0.1 + the front-matter
status block. WEB-DESIGN.md is then binding alongside DESIGN.md.

---

## 1. Sections this doc should contain (TOC)

A working table of contents for the future binding doc. Match
DESIGN.md structure where principles transfer; add web-specific
sections where they don't.

```
0. How to use this document
1. The binding principles — web equivalents of DESIGN.md §1
2. The IA decision tree — web equivalent of §2
3. Anti-patterns we reject — web-specific list
4. Density rules — web equivalent of §4
5. Material / glass / surface treatment — web equivalent of §5
6. Search-first IA — web equivalent of §6
6.5 Cross-cutting capabilities — share, profile, sign-in
6.6 Per-screen-size adaptations — what changes mobile→tablet→desktop
6.7 Universal states — empty/loading/error/offline
6.8 First-run hints — equivalent of HintsManager
6.9 Header + nav chrome standardization
6.10 Walkthroughs — see §13 below for the open question on whether to add at all
7. Forward-compatibility — what View Transitions API / Container
   Queries / native popover etc. let us inherit
8. Per-tab IA recipes — web equivalent of §8
9. Roadmap — the order of refactors needed to bring web into compliance
10. Daily review test
11. Visual primitives — components + colors
12. Out of scope (intentionally)
13. References
```

---

## 2. Web-specific constraints (input to every other section)

These are non-negotiable inputs from the project:

- **GitHub Pages static hosting** — no server runtime, no Node.js
  (per CLAUDE.md). Anything that looks like SSR or build-step is
  out unless we explicitly migrate to Cloudflare Pages or similar.
- **Vanilla HTML/CSS/JS — no framework, no build step** (DECISIONS.md
  #001). We have plain DOM, plain CSS, ES2022+ vanilla JS, and the
  Supabase JS SDK loaded via CDN. No npm install, no bundler.
- **Mobile-first** (CLAUDE.md). Test at 375px before 1440px.
- **WCAG AA from line one** (CLAUDE.md "Standing Instructions").
- **Body flex-column layout** (DECISIONS.md #020) — no
  `viewport-fit=cover`, no fixed headers, no `position: fixed`
  overlays that fight Safari's compositor.
- **Cross-platform feature-parity contract** (DECISIONS.md #005) —
  but with the explicit DESIGN.md §12 carve-out that web design
  is its own discipline.

Open question: do we want to relax any of these? Adding even
**TypeScript** would require a build step. Adding **Tailwind** would
require a build step. The answer is probably "no, keep it vanilla,"
but this doc should record that explicitly so future sessions don't
relitigate.

**Research:**
- [ ] Verify GitHub Pages still serves our needs at scale (current
  catalog is 17k cards, ~5MB JSON — fine; what's the ceiling?).
- [ ] Decide on the build-step question once and for all.

---

## 3. The binding principles — web equivalent of DESIGN.md §1

iOS §1 has 6 principles. Translate each to web, drop or rewrite as
appropriate. Working draft below — all of these need ratification.

### TODO 3.0 — "Native first" for web means…?
DESIGN.md §1.0 establishes "every interaction = built-in iOS API
before custom code." The web equivalent is:
- **Native HTML controls before custom widgets.** `<select>` before
  custom dropdown. `<dialog>` before custom modal overlay.
  `<details>/<summary>` before custom disclosure. `<input
  type="search">` before custom search bar.
- **Browser features before JS reimplementations.** CSS
  `scroll-snap` instead of JS scroll-tracking. Native popover API
  (now baseline-supported in Chromium + Safari + Firefox) instead
  of custom positioning. View Transitions API for cross-page
  animation instead of custom CSS animation orchestration.
- **Forms-first.** `<form>` + native validation + `:invalid`
  instead of inline JS error rendering for new surfaces.

**Research:**
- [ ] Which web "natives" are stable enough to depend on (popover,
  view transitions, container queries — Baseline 2024+ status)?
- [ ] What's the fallback strategy for browsers that don't support
  them (graceful degradation acceptable per DESIGN.md §6.7)?

### TODO 3.1 — Each tab owns one verb
Already in DESIGN.md §1.1 and the verb assignment is the same
across platforms (Find=explore, Learn=understand, Decks=build,
Collection=own, Purchase=acquire). **Likely transfers verbatim.**

### TODO 3.2 — Navigation depth ≤ 2 inside a tab
DESIGN.md §1.2 caps at 2 inside a tab. Web has different
navigation primitives — does the same depth cap apply? Web SPA-style
"open a modal over the current view" doesn't add a true nav level
(no back-button drill). Probably applies but needs validation.

### TODO 3.3 — Search is the universal navigator
Native HTML provides `<input type="search">` and the browser-level
URL bar. Decide: does web's "command-K palette" pattern apply here?
Most modern web apps (Linear, GitHub, Notion) use a command palette
as a parallel search surface. Worth evaluating for BOBA's case.

### TODO 3.4 — Density comes from removing chrome, not adding affordances
Same principle, same evidence (Tufte / Things 3 / Reeder).
**Likely transfers verbatim.**

### TODO 3.5 — Liquid Glass is for navigation only — content stays unglassed
This is iOS-specific. Web equivalent: there is no Liquid Glass on web.
**Replace with:** "Backdrop filter / blur effects are for navigation
chrome and overlays only — never on content cards or list rows."

**Research:**
- [ ] Browser support matrix for `backdrop-filter` (Safari has had
  it for years; Firefox added it 2023).
- [ ] Performance implications on lower-end devices.

---

## 4. The IA decision tree — web equivalent of DESIGN.md §2

Same structure, different leaf nodes. The right column changes from
SwiftUI patterns to web patterns:

| Question | iOS leaf | Web leaf |
|---|---|---|
| Top-level mode of the app | `Tab` | nav item in `#channels-sidebar` |
| Hierarchical drill-down | `NavigationStack push` | `showView(name)` + `history.pushState` |
| Parallel filter axis | `searchScopes` | `<select>` or token-style filter chips |
| Contextual full-focus action | `sheet(.large)` | `<dialog>` with full overlay |
| Glance-and-return action | `sheet(.medium)` with detents | `<dialog>` with smaller max-width OR a `position: fixed` panel |
| Side panel for inspection (iPad) | `.inspector()` | (skip — not a current web target) |
| Destructive / one-shot config | `Menu` | `<details>` overflow + `confirm()` for destructive |
| Global app state | `.tabViewBottomAccessory` | … (TBD — see §6.5) |
| Cross-cutting capability | per §6.5 | per §6.5 web equivalent |

Complete the table once each leaf is ratified.

**Research:**
- [ ] What's the right web equivalent of `.tabViewBottomAccessory`?
  Can we reuse the mobile-header pattern, or do we need a separate
  bottom-fixed strip on mobile?
- [ ] Do we want an `<dialog>`-based modal system, or stick with the
  current overlay div + close button pattern?

---

## 5. Anti-patterns to research and codify

DESIGN.md §3 is iOS-specific. Web has its own catalog. Some likely
anti-patterns to research:

- [ ] **Pages that aren't pages** — using JS routing without
  updating the URL or page title. We mostly do this right
  (showView updates URL via pushState), but verify across all
  views.
- [ ] **Dialog soup** — modals that open from modals. Same
  principle as iOS §3.4 modal-on-modal.
- [ ] **Scroll prison** — body has `overflow: hidden` to prevent
  Dynamic Island bleed (DECISIONS.md #020), which means inner
  scroll containers must handle their own keyboard scroll
  (PageDown, Home, End). Audit which ones do.
- [ ] **Divitis** — repeated `<div>` wrappers with no semantic
  meaning. Use `<section>`, `<article>`, `<aside>`, `<nav>`,
  `<main>`, `<header>`, `<footer>` where appropriate.
- [ ] **Custom focus rings** — overriding the browser's :focus
  outline destroys keyboard navigation. Customize with
  `:focus-visible` only.
- [ ] **Fixed pixel sizing** — instead of using `rem`/`em` for
  scalable typography (matters for users with large-text browser
  preferences).
- [ ] **JS-rendered everything** — pages that show nothing until
  JS runs are a parity gap with the user's link sharing
  expectations. Audit which views need server-rendered (or
  static-rendered) HTML for first-paint.
- [ ] **Global event listeners that never get removed** — leak
  memory across showView() transitions.

---

## 6. Density rules — web equivalent of DESIGN.md §4

Likely most of these transfer with small adjustments.

- [ ] **No tinted box backgrounds on content** — replace
  `.background(Color.gray.opacity(0.1))` ban with the same ban on
  `background: rgba(...,0.1)` for cards/rows.
- [ ] **Three weights × two sizes** — already in CSS via
  `--font-display` (Bebas Neue) + `--font-mono` (Chakra Petch).
  Codify: don't introduce a third font family.
- [ ] **Small multiples** — every card grid uses the same
  `.card-item` class. Audit for one-off layouts.
- [ ] **Show the data; let the user filter it** — same.
- [ ] **Progressive disclosure must be predictable** — `<details>`
  for inline, full page navigation for push. Don't overload.
- [ ] **The Gruber test** — same.

**Web-specific additions:**
- [ ] **Container queries before media queries** for component-level
  responsiveness. Most components should respond to their own
  container width, not the viewport width.
- [ ] **CSS custom properties for theming** — already done via
  `:root` `--boba-*` tokens. Codify the convention.

---

## 7. Material / glass / surface treatment — web equivalent of §5

DESIGN.md §5 is iOS Liquid Glass. Web equivalent:

- [ ] Decide on the use of `backdrop-filter` for nav chrome (header,
  sidebar, modals). Currently inconsistent — some places use
  `rgba(...)` flat backgrounds, some use blur.
- [ ] Codify the dark-theme palette (already in `:root` `--boba-*`).
- [ ] Reduce-motion + reduce-transparency parity:
  `@media (prefers-reduced-motion)` and
  `@media (prefers-reduced-transparency)` overrides.

**Research:**
- [ ] [W3C Backdrop Filter](https://www.w3.org/TR/filter-effects-2/#BackdropFilterProperty)
- [ ] [WebKit blog on glass effects](https://webkit.org/blog/)
- [ ] Real-device performance (low-end Android specifically) on
  layered backdrop-filter elements.

---

## 8. Search-first IA — web equivalent of §6

Web has stronger options here than iOS in some ways (browser URL
bar = always-available search) and weaker in others (no native
`Tab(role: .search)` equivalent).

- [ ] Currently the search input is at the top of `view-search`.
  Should it always be visible (sticky-top), or stay scroll-locked?
- [ ] Token-style filter chips — browser native via custom elements?
  Or stick with our current chip+pill pattern?
- [ ] Cross-tab search: should the sidebar's nav search every tab's
  domain, or stay tab-specific?

---

## 9. Cross-cutting capabilities — web equivalent of §6.5

iOS §6.5 covers scan, share, profile/auth. Web equivalents:

- **Scan** — N/A (iOS-only by design).
- **Share** — Web Share API on supported browsers; fallback to
  copy-to-clipboard. Codify the trigger pattern.
- **Profile / Sign-in** — currently a sidebar nav item, opens a
  view. Should it be a dialog instead? Decide.
- **Sharing target** — when someone shares
  `bobaplaybook.com/u/{username}` to another user, what should
  open? Already implemented; document the contract.

**Research:**
- [ ] [Web Share API status](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API)
- [ ] How iOS Universal Links handle the case when the recipient
  doesn't have the app installed (web fallback, what to render).

---

## 10. Per-screen-size adaptations — web equivalent of §6.6

Mobile-first is the rule (CLAUDE.md). Tablet and desktop are
adaptations:

- [ ] Mobile (<768px): single-column, hamburger-driven sidebar.
- [ ] Tablet (768–1023px): sidebar visible, single content column.
- [ ] Desktop (1024px+): wider grids, more content density.

Already partially codified in the existing `@media` queries.
Document them as the canonical breakpoints.

**Research:**
- [ ] Container queries for component-level responsiveness (instead
  of viewport breakpoints). Where do they make sense?
- [ ] When do we add an iPad-style two-column / sidebar+detail
  layout? Probably when desktop becomes a real target — currently
  most users are on mobile.

---

## 11. Universal states — web equivalent of §6.7

Already mostly handled but not codified. Document:

- [ ] **Loading** — skeleton vs spinner; 300ms threshold same as iOS.
- [ ] **Empty** — `ContentUnavailableView` equivalent; what HTML
  pattern?
- [ ] **Error** — banner vs inline; how to surface network errors.
- [ ] **Offline** — offline pill (just shipped in v2.067 — the
  pattern for use elsewhere?).

---

## 12. First-run hints + walkthroughs — DESIGN.md §6.8 / §6.10 equivalents

**Open question:** does web get a walkthroughs system at all?

iOS DESIGN.md §6.10 has 12 walkthroughs / ~40 anchored steps. The
parity-audit agent flagged this as a P1 gap; the human review
deferred it pending this design doc.

- [ ] Decide: is a web walkthrough engine in scope, or are walkthroughs
  iOS-only (with web relying on better self-evident UI + the
  shipped Privacy/Terms/About content for orientation)?
- [ ] If yes: web walkthrough engine technical approach. Anchor
  rings are CSS clip-path overlays; copy bubbles are `<dialog>`s
  positioned relative to the anchor. State persistence via
  localStorage.
- [ ] If no: document why explicitly so future sessions don't
  re-add this as a parity gap.

**Recommendation pending research:** start with **no walkthroughs
on web**. The iOS justification (DESIGN.md §6.10 anti-pattern
"slide-deck onboarding") is "teach with the real UI on the real
screen, not a stylized version." On web, the real UI is already
what the user sees — there's no first-launch screen to compete with.
Inline contextual help (a `?` icon that opens a tooltip) may be
sufficient.

---

## 13. Header + nav chrome standardization — equivalent of §6.9

- [ ] Mobile header: hamburger + brand wordmark + offline pill. Done.
- [ ] Sidebar: pinned items + sign-in state. Done.
- [ ] Per-view headers: should each view have a consistent header
  pattern (title + actions)? Currently inconsistent.

---

## 14. Forward-compatibility — modern web standards to evaluate

iOS DESIGN.md §7 talks about iOS 27 readiness. Web equivalent:

| Modern web feature | Status (Baseline) | Use case in BOBA |
|---|---|---|
| **View Transitions API** | Baseline 2024 | Cross-page transitions when navigating between views |
| **Container Queries** | Baseline 2023 | Component-level responsiveness |
| **CSS Nesting** | Baseline 2023 | Cleaner styles.css organization |
| **CSS `:has()` selector** | Baseline 2023 | State-aware styles (e.g., row with active child) |
| **Popover API** | Baseline 2024 | Replace custom overlay dialogs |
| **`<dialog>` element** | Baseline 2022 | Modal dialogs |
| **`anchor()` positioning** | Limited (Chrome only as of 2025) | Future tooltip/menu positioning |
| **Web Share API** | Wide support | Share collection / deck / card URLs |
| **Service Worker / PWA** | Wide support | Already PWA; deepen offline-first behavior |
| **WebGPU** | Behind flag still on most browsers | Possible future for card-image renderers |
| **CSS Scroll-Driven Animations** | Chrome only | Skip until cross-browser |

**Research action:**
- [ ] For each Baseline-2023+ feature, document whether to adopt and
  on what timeline.
- [ ] PWA improvements: install prompt, badging, share target API
  (so the OS share sheet can target our app).

---

## 15. Per-tab IA recipes — web equivalent of §8

iOS DESIGN.md §8 has detailed per-tab IA. Web equivalents need their
own per-tab plans because the navigation primitives differ.

Stub each section here; flesh out as part of ratification.

### 15.1 Find (web)
- [ ] Sticky search input at top of view-search?
- [ ] Featured ribbons (TODO: do web users want these or just the
  search-first surface?)
- [ ] Filter panel: collapsible on mobile, persistent on desktop
  (already in DECISIONS.md #017 — codify).

### 15.2 Learn (web)
- [ ] Single-stream article rendering (already in HTML).
- [ ] Skill-level scope (Rookie/Substitution/Playmaker) as a
  segmented control INSIDE the article.
- [ ] Read/Watch toggle inline.

### 15.3 Decks (web)
- [ ] Web doesn't (and probably shouldn't) try to replicate the
  iOS Music-pattern pill + zoom editor. Likely keeps the
  current side-by-side pool + slot pattern.
- [ ] Document the chosen paradigm + rationale here.

### 15.4 Collection (web)
- [ ] Designation tabs (Personal/Sale/Trade/Wanted/Grails) —
  segmented across the top.
- [ ] Wall as an action button (parity with iOS) — TODO ship.
- [ ] Public collection link (already shipped per DECISIONS.md
  #039) — link to Profile section.

### 15.5 Purchase (web)
- [ ] Two sections: Upcoming Breaks + Find a Store. Tabs or
  scroll-stacked? (iOS uses segmented Picker.)

---

## 16. Roadmap

iOS DESIGN.md §9 has a numbered refactor roadmap. Web equivalent:
once the principles in §3-§8 are ratified, generate a parallel
roadmap of refactors needed to bring the existing web app into
compliance. Don't write this until the principles are settled —
otherwise the roadmap shifts every time a principle clarifies.

---

## 17. Visual primitives

iOS has BOBASectionRow / BOBACardCell / BOBACardGridItem etc. Web
has `.card-item`, `.card-grid`, `.profile-section`, etc. Audit:

- [ ] Catalog every reusable CSS class that maps to an iOS
  primitive.
- [ ] For ones that don't have a CSS equivalent (e.g., the iOS
  `BOBAGlassButton`), decide whether to add one or keep web's
  current approach.
- [ ] Color usage: same brand vs element split as iOS DESIGN.md
  §11.2. Already enforced via CSS custom properties.

---

## 18. Out of scope (intentionally)

Match iOS DESIGN.md §12 by being explicit about what we're NOT
designing for:

- [ ] Native iOS patterns that don't have a real web equivalent
  (Liquid Glass, hero zoom, `.tabViewBottomAccessory`).
- [ ] Mobile-only iOS patterns where mobile web has weaker
  affordances (camera scan, Vision OCR).
- [ ] Scope items deferred on iOS (Practice executor, push
  notification dispatch).
- [ ] Non-bobaplaybook.com hosting (we're not building a
  white-labeled version).

---

## 19. References to read before drafting

A starter reading list for whoever fleshes this out. Some are evergreen
design references; some are 2024-2025 web platform articles.

**Design language:**
- [Refactoring UI](https://www.refactoringui.com/) — visual hierarchy + density
- [Things 3 design](https://culturedcode.com/things/) — single-pane density references
- [Linear's design system](https://linear.app/method) — modern dark-theme density
- [Vercel's design system](https://vercel.com/design) — modern web typography
- [Apple HIG — applying iOS principles to web](https://developer.apple.com/design/human-interface-guidelines/)

**Modern web standards (Baseline + Web Platform):**
- [web.dev/baseline](https://web.dev/baseline) — Baseline-supported feature catalog
- [web.dev/articles/view-transitions](https://web.dev/articles/view-transitions) — page transitions
- [MDN Container Queries](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_containment/Container_queries)
- [MDN Popover API](https://developer.mozilla.org/en-US/docs/Web/API/Popover_API)
- [MDN dialog element](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/dialog)
- [MDN Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API)

**Accessibility:**
- [WCAG 2.2 AA](https://www.w3.org/WAI/WCAG22/quickref/?levels=a%2Caa)
- [Inclusive Components](https://inclusive-components.design/) by Heydon Pickering
- [APG Authoring Practices](https://www.w3.org/WAI/ARIA/apg/) — patterns for native-feel widgets

**Performance:**
- [web.dev/measure](https://web.dev/measure) — Core Web Vitals
- [PageSpeed Insights](https://pagespeed.web.dev/) — site-specific testing

**PWA:**
- [web.dev/articles/learn/pwa](https://web.dev/articles/learn/pwa) — PWA fundamentals
- [Service Worker recipes](https://web.dev/articles/offline-cookbook)

**Reference implementations to study:**
- iOS DESIGN.md (this repo's binding doc — for principles to translate)
- bsky.app web (reference for vanilla-JS dark-theme density at scale)
- linear.app (reference for command-K + density)
- raycast.com (reference for keyboard-first interaction patterns)

---

## 20. Open questions for Ben

Block list — things to decide before progressing on specific sections.

- [ ] **Walkthroughs on web:** yes (with web engine), no, or "inline
  contextual help only"? Affects §12.
- [ ] **Build step:** keep vanilla forever, or allow Vite/esbuild
  for a typescript transpilation step at some point?
- [ ] **Command palette (Cmd-K):** add as a parallel search surface,
  or rely on browser URL bar + in-view search?
- [ ] **Web push notifications:** out of scope or P3 future? iOS
  match-alerts pipeline is deferred (DECISIONS.md #039) — web
  push has different infrastructure.
- [ ] **Desktop-class layout:** when do we add a true two-column
  detail-view pattern (sidebar + main content)? Driven by analytics
  on desktop usage.
- [ ] **PWA install prompt:** should we surface "install BOBA Playbook"
  to mobile-web users who don't have the iOS app?
- [ ] **Custom domain branding for shared collections:**
  bobaplaybook.com/u/ben works today. Should we sell paid
  custom subdomains (ben.bobaplaybook.com)? Probably no, but
  document.

---

## 21. Parity-checking workflow when iOS ships changes

Process to follow whenever an iOS change lands that's not pure
implementation detail:

1. Author of the iOS change updates SCRATCHPAD.md feature-parity
   table to mark the relevant feature as iOS-only or both.
2. If the change introduces new design patterns, the author
   evaluates against this doc:
   - If the change just refines a principle already in this doc,
     no further action.
   - If the change introduces a new pattern, an entry goes here as
     a TODO pending web equivalent.
3. Periodic (~monthly) audit: compare iOS DESIGN.md last-modified
   sections against this doc. Anything new in iOS gets a TODO here.

This workflow needs to be lightweight — heavyweight process here
will get skipped, and the parity gap will widen silently.
