# BOBA Playbook — Project Scratchpad

> Active working notes only. Completed milestone implementation detail and the full session log live in [ARCHIVE.md](./ARCHIVE.md). See [DECISIONS.md](./DECISIONS.md) for architecture decisions and [DESIGN.md](./DESIGN.md) for binding iOS design rules.

## Current State (2026-05-05)

- **Catalog**: 17,968 cards · ~90% image coverage on R2 · OKC art still pending
- **Latest version**: iOS 2.113 / 376 — Universal Links validated end-to-end; route-based deep linking pattern shipped
- **Latest commit**: walkthrough diagnostics removed (validated; pattern preserved in memory)

## What Just Shipped (recent)

- **iPad first-class pass — PR 1+2+3** (DESIGN.md §6.6 + §6.6.1 + §6.6.2, ratified binding). Phone path untouched.
  - **PR 1 — visible breakage (P0):** TabView gets `.tabViewStyle(.sidebarAdaptable)` so iPad regular morphs the tab bar to a sidebar. Walkthrough overlays (`BOBAWalkthrough.swift`, `DeckBuilderTutorialOverlay.swift`) read `safeAreaInsets.top` + `.bottom` from a non-ignoring `GeometryReader` instead of the magic 60pt-top/96pt-bottom that broke on iPad menu bar. New `compactZoomSource` / `compactZoomDestination` modifiers in `Design.swift` gate `.matchedTransitionSource` + `.navigationTransition(.zoom)` to compact-only — 15 call sites swept (Find / Decks / Collection / Learn). On regular width these are no-ops; system push fires instead.
  - **PR 2 — structure (P0/P1):** Grid column defaults are now size-class-aware via `Design.GridDensity` helper. Sentinel `0` in `@AppStorage` resolves to compact default (Find=2, Decks=3, Collection=3) or regular default (5). Pickers show 1/2/3 on compact, 3-7 on regular. ProfileView's `ColumnsPickerRow` matches. StoreLocator wraps `mapSection` + `listSection` in `HStack` on regular (true split, 380pt list trailing column) instead of vertical stack with fixed-height map.
  - **PR 3 — polish (P1/P2):** Profile sheet (Find + legacy Collection trigger) uses `.presentationCompactAdaptation(.popover)` so iPad anchors it to the trigger button. Reaction picker (`ReactionPickerView`) does the same. Card detail artPanel/image heights pulled from `Design.CardDetailMetrics` (compact: 420/380, regular: 560/520) — applied to all three §8.6 detail surfaces. `OrientationManager.defaultMask` is now device-aware (iPhone: portrait; iPad: all-but-upside-down) so iPad rotates the whole app, not just Practice.
  - **DecksView NavigationSplitView (iPad)** — SHIPPED 2-column. Pool sidebar (browse) + editor detail (focused work) on iPad regular. Editor body extracted to private `editorStack` ViewBuilder; pool body extracted to `poolStack` ViewBuilder; `var body` branches on `horizontalSizeClass`. Editor toolbar's X close button + wordmark are compact-only (X has nothing to dismiss in detail column; wordmark is already in pool sidebar). Walkthrough handler's open/close calls are compact-only too. Phone path untouched. **3-column with saved-decks sidebar deferred** — additive polish; current 2-column already gives iPad the key win (pool + editor side by side).
  - **LearnView NavigationSplitView (iPad)** — SHIPPED. Slim category list as sidebar + selected category content as detail. Tile grid + push stays on compact. iPad detail has an editorial placeholder ("LEARN BoBA / Everything we know") before any selection. Walkthrough anchors preserved on sidebar rows so the Learn walkthrough fires correctly on both width classes. `categoryView(for:)` shared between paths; `learnRootToolbar` shared too.
  - **Action-shaped sheets adapt to popover on iPad** — DESIGN.md §6.6 sweep across SearchView (FilterSheet), CollectionView (FilterSheet), CardDetailView (Add to Collection / Deck / Show), CollectionCardDetailView (same four + EditCollectionEntry), ShowsListView (rename + new-show), ShowDetailView (wall options + rename). Content-shaped sheets (share, wall composer, deck management, rules / legality, sign-in, card detail, scan / queue / picker) intentionally stay full-canvas.

- **CollectionView NavigationSplitView** — SHIPPED 2026-05-06. Sidebar lens picker (My Cards / Rainbow / Shows) feeds detail; designation segmented Picker stays inside My Cards (familiar UX). Rainbow + Shows now have permanent sidebar entries instead of being buried in the overflow Menu. Same `collectionToolbar` shared across compact + iPad paths via `@ToolbarContentBuilder`. Profile gear NOT added to sidebar (Profile is Find-only per `feedback_profile_only_on_find`).
- **PurchaseView NavigationSplitView** — SHIPPED 2026-05-06. 2-segment picker (Live Breaks / Find a Store) becomes sidebar on iPad regular. Compact keeps the segmented Picker treatment.
- **Cmd+1..5 hardware-keyboard tab shortcuts** — SHIPPED 2026-05-06. Hidden-Button overlay attached to ContentView. iPhone with no keyboard ignores them. Apple's first-party iPad apps (Mail/Music/Settings) all support this.

- **3-column DecksView** — SHIPPED 2026-05-06. Saved-decks sidebar | pool | editor on iPad regular. `loadSavedDeck(_:cards:)` hoisted to `DeckBuilderStore` (DeckManagementSheet's private loadDeck now calls it). Sidebar List shows saved decks with active-deck checkmark + per-row loading spinner; "+ New deck" at top discards draft. Auth-gated (sign-in CTA when signed out, empty-state when authenticated but no saved decks). iPad portrait collapses sidebar via system toggle (NavigationSplitView .balanced default). Column widths hint: sidebar 240/280, pool 380/560, editor takes remainder.
- **iPad toolbar density** — SHIPPED 2026-05-06. Filters surfaces inline on Find (iPad regular) with active-count dot; Scan surfaces inline on Decks (pool) and Collection (My Cards lens). Settings-style items (Columns, Display, walkthrough relaunch) stay in the Menu — they nest naturally and would clutter inline.
- **iPad drag-and-drop** — SHIPPED 2026-05-06. `Card` Transferable via CodableRepresentation(.json) (no custom UTType — was tripping Xcode Info.plist warning). Pool / Find grid / Collection grid cells get `.draggable(card)`; Decks editor's outer VStack gets `.dropDestination(for: Card.self)` calling addCardToDeck. Phone path harmless (no in-app drop target — preview snaps back).
- **Universal Links / deep linking** — SHIPPED 2026-05-07 after seven commits chasing the wrong cause. Final architecture: AASA at `/.well-known/apple-app-site-association` (catch-all `/` with `/privacy/*` and `/terms/*` excludes). `_config.yml` keeps Jekyll filtering working on GitHub Pages. iOS handler dispatches by scheme — `https://` → `handleUniversalLink`, `bobaplaybook://` → `handleDeepLink`. Route-based pattern: `CardRoute` (Hashable) pushed onto `cardStore.findNavigationPath` directly by URL handler; `CardRouteResolver` at the destination handles catalog-not-loaded with a graceful loading state. ALL via .onOpenURL on iOS 17+, NOT .onContinueUserActivity (memory: feedback_universal_links_onopenurl). Lesson: instrument first, guess never.
- **Build number sync** — SHIPPED 2026-05-07. `ci_scripts/ci_post_clone.sh` + `scripts/bump-build.sh` both query App Store Connect API for latest TF build per marketing version. **Pending one-time config**: add `ASC_API_ISSUER_ID` secret to Xcode Cloud workflow Environment Variables (App Store Connect → Xcode Cloud → workflow → Environment) AND `export ASC_API_ISSUER_ID=...` for local archiving. Until configured, both scripts no-op gracefully — Xcode Cloud still uses CI_BUILD_NUMBER and Mac uses xcconfig directly. See memory: reference_build_number_sync.

## Deferred iPad work

- **Walkthrough anchor verification on iPad** — needs simulator validation that anchors registered in NavigationSplitView sidebar/detail columns resolve correctly through the outer `walkthroughOverlay`. SwiftUI preferences flow up the view tree, so should work, but verify in simulator.
- **iPad drag-and-drop** — drag cards between deck slots, between Find→Decks/Collection. Significant work; nice-to-have.
- **Scan view landscape polish** — fixed `kGuideW=300, kGuideH=420` works in iPad landscape but feels small relative to canvas. Could scale guide for regular width.
- **Native-first Decks rebuild** (DESIGN.md §1.0, §8.3): Music-pattern summary pill + fullScreenCover editor with hero zoom; secondary surfaces (Manage Decks / Rules / Legality) push as NavigationDestinations
- **Card detail standardized** across Find / Decks / Collection (canonical artPanel + toolbar; hero zoom transitions per DESIGN.md §8.6)
- **Profile redesign** (DECISIONS.md #037-#039): username field with banned-words gate, generalized role-request (mod OR streamer), Discord identity auto-persist, sign-in method pill, public collection toggle, Terms of Service page (live at https://bobaplaybook.com/terms/)
- **Public collections** (web): get_public_collection RPC + 404.html `/u/{slug}` redirect + `view-public-collection` SPA route
- **Web parity batches 1+2**: username inline edit, sign-in method pill, Terms link, generalized role request, Delete Account, offline indicator, per-tab grid density, Weapon/Treatment terminology audited (already in parity)
- **Walkthroughs** (DESIGN.md §6.10): all 7 walkthroughs validated as visually correct after 8+ iteration round on the Learn anchor (root cause: `anchorPreference` was overwriting parent-side; fix was `transformAnchorPreference` in the helper). Diagnostic instrumentation removed; pattern documented in memory.
- **WEB-DESIGN.md** ratified to binding (978 lines). All 21 TODO sections converted to binding rules in DESIGN.md style; "Out of scope" decisions explicit (walkthroughs, Cmd-K, web push, build step). Roadmap of P0/P1/P2 web refactors implied by the new rules listed in §15.

## Active / Next-Up

- ~~**M4 Purchase view**~~ — SHIPPED. Whatnot upcoming-breaks live at `boba-ebay-proxy.benwilkoff.workers.dev/whatnot/upcoming` (lives inside the existing eBay worker, not a standalone — that's why the older "boba-whatnot-shows" handoff folder doesn't exist). Wired on iOS via `WhatnotShowsService` and on web via `js/purchase.js`. Picker + Find a Store on iOS shipped earlier.
- ~~**Account deletion Worker endpoint**~~ — SHIPPED 2026-05-05 (`workers/account-delete/`). DECISIONS.md #039 updated.
- ~~**Profile picture upload**~~ — SHIPPED 2026-05-05 (`workers/avatar-upload/` + `set_avatar_url`/`get_public_profile` RPCs). Discord-default + R2-on-upload pattern; rendered on iOS Profile, web Profile, and the public-collection page. DECISIONS.md #040.
- **Admin panel public-link visibility** (2026-05-05) — `get_admin_user_stats` RPC now returns `username`, `public_collection_enabled`, `avatar_url`, `discord_avatar_url`. iOS + web admin panels render an avatar thumb, @username with PUBLIC pill, and a copyable `bobaplaybook.com/u/{handle}` URL row when sharing is on. Reuses the avatar resolver from DECISIONS.md #040.
- ~~**Web "feels native" pass**~~ — SHIPPED 2026-05-05. WEB-DESIGN.md §15 P0 + P1 closed (P2 deferred).
  - View Transitions on every `showView()` (cross-fade) + card-grid → modal hero-zoom morph.
  - `prefers-reduced-transparency` + `prefers-reduced-motion` parity overrides.
  - All three modal overlays migrated from `<div>` to native `<dialog>` (card-detail, auth, add-collection): focus trap, ESC, top layer.
  - Web Share API helper with copy-link fallback (window.bobaShareTarget).
  - Native Popover-API menus replacing the blocking `prompt()` designation/deck pickers (window.bobaShowPopoverMenu).
  - `.card-item` uses container queries — same cell renders correctly at S/M/L density without media-query forks. Inherited by the public-collection grid.
  - CSS Nesting pattern established (incremental) on the new popover-menu CSS.
- **Match-alerts pipeline** (Wanted/Grail notifications) — UI toggle ships, APNs server-side dispatcher is multi-week of new infra. See DECISIONS.md #039. **Note 2026-05-05**: TRADE-DESIGN.md (binding) was ratified to constrain HOW the match notifications hand off to a trading flow. Match-alerts pipeline is now Phase 7 of the TRADE-DESIGN.md §14 roadmap; don't ship before Phase 0 (LLC + insurance + ToS) is done.
- **TRADE-DESIGN.md** ratified 2026-05-05 (v2 rewrite for $0-ongoing-cost constraint). Architecture: **pure introduction** — BOBA detects matches, surfaces the other user's Discord handle, steps out. No in-app chat, no thread storage, no insurance, no retained counsel. Apple §1.2 controls satisfied via email-based reporting + bilateral block + bounded-shape listings + published contact (no per-message mod queue). Subscription monetization (Apple IAP) gates push notifications + power-user features. ~3 weeks of v1 dev (vs the original 10-week estimate). Risks Ben is explicitly accepting documented in §3.

## Open Questions / Blockers

- **OKC art sourcing** — 54 OKC records ship with `imageFile=null`. Confirm what's published on bobattlearena.com / the card source / Radish, then trigger a BV-scrape pass scoped to OKC- pages.
- **COMC Cloudflare Turnstile** — `boba-comc-proxy` returns `count: 0, challenged: true`. Bypass requires Cloudflare Browser Rendering API or a Playwright runner. Defer until COMC's WAF stance changes.
- **Practice executor IP review** — admin-gated per DECISIONS.md #033; access via the bolt icon on the Profile role badge. No timeline.

---

## Feature Parity Status

✅ Both | 🌐 Web only | 📱 iOS only | ⏳ Planned | ❌ Deferred

| Feature | Web | iOS | Notes |
|---|---|---|---|
| Search Mode | ✅ | ✅ | M1 complete |
| App icon + branding | ✅ | ✅ | XOXO logo, wordmark, PWA |
| Mobile Safari layout | ✅ | n/a | Body flex column, no viewport-fit=cover |
| Collection Mode | ✅ | ✅ | M2 complete |
| Scan Mode (camera OCR) | ❌ | ✅ | iOS only by design |
| Pricing comps (links) | ✅ | ✅ | M3 complete |
| Buy Now (active listings) | ✅ | ✅ | eBay + COMC (latter Turnstile-blocked) |
| Deck Builder | ✅ | ✅ | iOS rebuilt to Music-pattern pill + zoom editor |
| Streamer Shows | ✅ | ✅ | My Shows + Generate Wall (streamer role only) |
| Find a Store | ✅ | ✅ | MapKit/Leaflet, ~330 indie + ~1,800 big-box |
| Purchase view | ✅ | ✅ | Find a Store + Upcoming Breaks (Whatnot via boba-ebay-proxy `/whatnot/upcoming`) |
| Profile (username, sharing, role-request, etc.) | ✅ | ✅ | v2.064-v2.080 |
| Public collections (`/u/{username}`) | ✅ | n/a (auth) | Web-only render; iOS sets the toggle |
| Walkthroughs | n/a | ✅ | iOS only — see WEB-DESIGN.md §12 for the open question |

---

## Milestones (active)

### ✅ Completed
M0 (setup), M1 (search), M2 (collection), M3/M3.5 (scan + pricing). Profile + Decks rebuild + Public collections (web) + Walkthroughs all shipped post-M3.5. Full notes in ARCHIVE.md.

### ✅ M4 — Purchase view
- **Upcoming Breaks** — done. Whatnot search at `boba-ebay-proxy.benwilkoff.workers.dev/whatnot/upcoming` (consolidated into the eBay worker, not a standalone). iOS uses `WhatnotShowsService`, web uses `js/purchase.js`.
- **Find a Store** — done (moved out of Collection).

### ❌ M5 — Discord Trading Channel (FUTURE)
Embed community trading channel. Research Discord Activity SDK vs WebView feasibility before committing.
