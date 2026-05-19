# BOBA Playbook — Project Scratchpad

> Active working notes only. Completed milestone implementation detail and the full session log live in [ARCHIVE.md](./ARCHIVE.md). See [DECISIONS.md](./DECISIONS.md) for architecture decisions and [DESIGN.md](./DESIGN.md) for binding iOS design rules.

## Current State (2026-05-15)

- **Catalog**: 17,974 cards · ~90% image coverage on R2 · OKC art still pending · 30 invalid-power records repaired
- **Latest version**: iOS 2.223 / 486 — power-value cleanup (truth-from-image) + custom rainbows complete
- **Latest commit**: redo power fixes by reading the printed value off each card image (supersedes v2.222 fallback)

## What Just Shipped (recent)

- **Power-value cleanup — v2.223** (2026-05-15). 30 catalog cards with `power % 5 != 0` (invalid — every BoBA card prints a power ending in 0 or 5) repaired by READING the truth off each card's R2 image, not by sibling-mode fallback. v2.222 used mode-of-siblings and got 23/30 wrong; v2.223's TRUTH dict in `scripts/apply_verified_powers.py` is the canonical record. Beta tester flagged Emmitt-164 cards specifically. Follow-up planned: [[project_power_audit_followup]] for valid-but-wrong values OCR may have landed on by chance. Don't repeat: [[feedback_card_data_truth_from_image]].

- **Custom rainbows — v2.219–v2.221** (2026-05-15). User-defined collecting goals as saved filters over the catalog. Backend: `user_custom_rainbows` Supabase table with own-row RLS + criteria jsonb. iOS: `CustomRainbow` + `RainbowCriteria` Codable + `CustomRainbowStore @Observable`. Editor sheet with eight filter dimensions (heroes/sets/sub-sets/weapons/treatments/cardTypes/releases + inspired-ink toggle) and live progress preview. Shared `RainbowDetailView` for BOTH custom AND per-hero auto-rainbows (`Kind.hero(String)` / `Kind.custom(UUID)`). Custom rainbows sit above the auto-generated per-hero list with a "+ New" button. Architecture in [[project_custom_rainbows_architecture]].

- **Mod add-card + in-app cropping — v2.213, v2.218** (2026-05-15). Moderators can add net-new cards with the same field surface as the edit flow; `card_corrections` extended with `kind text` ('correction'|'addition'), `image_storage_path text`, `merged_at timestamptz`. Merge worker `scripts/merge_approved_additions.py` pulls approved additions → cards.json + R2. In-app 5:7 freeform cropper rebuilt as pure UIKit (CardCropViewController + CardCropOverlayView) after 5 iterations of broken SwiftUI gesture overlays — `hitTest(_:with:)` returning nil passes touches through to the UIScrollView for native pan/zoom. Architecture in [[project_mod_add_card_architecture]]; gesture lesson in [[feedback_swiftui_uiscrollview_gesture_passthrough]].

- **Promo data import — v2.213** (2026-05-15). 6 new cards seeded into the catalog (5 First Reward Promo: A.I. / Amon-Ra / Bojax / Brandi / Cruschman; 1 Top 8 Bojax). 4 with images shipped to R2 via WebP tiers; 2 added without images for the auto-pipeline to find later. Skeee RPU-1 already existed. Reusable script: `scripts/import_new_cards.py`.

- **House of BoBA (Easter egg) — called complete 2026-05-15** at v2.212. Paused-physics card-tower playground in Profile → easter-eggs menu. Five intent-named snap kinds (aFrame, shareFoot, spanRoof, sitOnTop, sideBySide) with slot-occupancy guards + stack-aware column filter. Undo button next to PLAY with 25-deep state stack; Reset moved to ⋯ menu; Smart-snap toggle there too as the creative escape valve. Live level counter tracks A-frame tiers only (flat-roof transitions don't count). Help sheet rewritten in the app's playful voice. Architecture in [[project_house_of_boba_architecture]].


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
- **R2 /full/ tier resolution upgrade** (Hero Shot pixelation root cause). v7.x ships Lanczos 2× upscale + PBR matte + mipmaps as a stopgap that masks the issue perceptually, but the authoritative fix is regenerating R2's `/full/` tier at higher resolution. Measured today: `/full/` serves cards at 477×667 (1-Maverick) to 745×1040 (1-LeBoss) — far smaller than CARD_SCHEMA's "≤1200px WebP" claim. At Hero Shot's 1080×1920 output, the card art is UPsampled 1.5-2.3× from source = "thumbnail blown up" look at push-climax frame.
  - **Pipeline**: re-run `unified-cards/scripts/reconcile_all.py::step11_optimize_images` with a new long-side cap (target 1500 or 2100). Requires Ben's local source images (per DECISIONS.md #011, not in repo). Storage delta on R2 ≈ 5-10× current `/full/` tier (~5-15 GB total). One-shot re-upload pass.
  - **Two paths**: (a) replace `/full/` in place — simpler, but invalidates Cloudflare edge cache for every card; (b) add a new `/uhd/` tier with `CDN.uhdURL()` helper + Hero Shot opt-in, fallback to `/full/` during rollout — safer.
  - **Payoff**: Hero Shot renders crisp at every camera distance, including a future Detail arc. Removes the need for Lanczos pre-upscale entirely; can revert to HouseOfCards' simpler texture loading.

---

## Feature Parity Status

> **Full parity matrix lives in [PARITY.md](./PARITY.md) (single source of truth).** The snapshot below is a quick scan of high-level feature areas. Detail rows for sub-features (per-tab anatomy, specific affordances) are in PARITY.md.

✅ Shipped | 🚧 In progress | ⏳ Planned | 🔮 Future | 🚫 Out of scope | n/a — inapplicable

| Feature | Web | iOS | Android | Notes |
|---|---|---|---|---|
| Find / Search | ✅ | ✅ | ⏳ M1 | All three platforms |
| App icon + branding | ✅ | ✅ | ⏳ M0 | Adaptive icon on Android (foreground + background + monochrome) |
| Mobile Safari layout | ✅ | n/a | n/a | Body flex column, no viewport-fit=cover |
| Collection | ✅ | ✅ | ⏳ M2 | All three platforms |
| Scan Mode (camera OCR) | 🚫 | ✅ | ⏳ M3 | CameraX + ML Kit on Android; web has no camera/Vision parity |
| Pricing comps | ✅ | ✅ | ⏳ M3 | Same Worker proxy, same waterfall |
| Buy Now (active listings) | ✅ | ✅ | ⏳ M3 | eBay + COMC; COMC Turnstile-blocked |
| Decks builder | ✅ | ✅ | ⏳ M4 | iOS Music-pattern pill + zoom; Android `ModalBottomSheet + sharedBounds`; web side-by-side desktop |
| Streamer Shows | ✅ | ✅ | ⏳ M2 | Role-gated, push destination |
| Find a Store | ✅ | ✅ | ⏳ M6 | MapKit / Leaflet / Google Maps Compose |
| Purchase view | ✅ | ✅ | ⏳ M6 | Find a Store + Upcoming Breaks (Whatnot) |
| Profile (username, sharing, role-request) | ✅ | ✅ | ⏳ M7 | Sign in with Google primary on Android (vs Sign in with Apple iOS) |
| Public collections (`/u/{username}`) | ✅ | n/a | ⏳ M7 | Web renders; iOS/Android set the toggle + deep-link in |
| Walkthroughs | 🚫 §11 | ✅ | 🚫 §6.10 | iOS-only; web + Android use EmptyState + tooltips |
| Hero Shot 3D | n/a | ✅ | 🚫 v1 | Filament port deferred |
| House of BoBA easter egg | n/a | ✅ | 🚫 v1 | RealityKit-specific |
| Personal Showcase | n/a | ✅ | 🚫 v1 | Cast SDK port deferred |
| Custom Rainbows | n/a | ✅ | ⏳ M2 | Web parity 🔮 |
| Practice executor | n/a | ✅ admin-gated | ⏳ M5.5 admin-gated | Both mobile platforms admin-gated per DECISIONS.md #033 + #048 |
| Trading (match alerts + Discord deep-link) | 🔮 Phase 1+ | 🔮 Phase 1+ | 🔮 Phase 1+ | TRADE-DESIGN.md governs all three |

**See [PARITY.md](./PARITY.md)** for the detail-level matrix (per-tab anatomy, auth surfaces, deep linking, notifications, payments, etc.).

---

## Milestones (active)

### ✅ Completed
M0 (setup), M1 (search), M2 (collection), M3/M3.5 (scan + pricing). Profile + Decks rebuild + Public collections (web) + Walkthroughs all shipped post-M3.5. Full notes in ARCHIVE.md.

### ✅ M4 — Purchase view
- **Upcoming Breaks** — done. Whatnot search at `boba-ebay-proxy.benwilkoff.workers.dev/whatnot/upcoming` (consolidated into the eBay worker, not a standalone). iOS uses `WhatnotShowsService`, web uses `js/purchase.js`.
- **Find a Store** — done (moved out of Collection).

### ❌ M5 — Discord Trading Channel (FUTURE)
Embed community trading channel. Research Discord Activity SDK vs WebView feasibility before committing.

---

## Android v1 Milestone Plan (2026)

Research + binding docs ratified 2026-05-19. All open questions resolved (DECISIONS.md #041–#052). See [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md), [`ANDROID-DEV.md`](./ANDROID-DEV.md), [`PARITY.md`](./PARITY.md).

**Resolved direction:**
- Package: `com.bobaplaybook.app`. Same monorepo, `/android/` at root.
- Firebase Spark (free) plan — new Android app under one BOBA Firebase project.
- **Tablet + Chromebook supported from M1** (Ben has Chromebook for early testing); foldable NOT v1.
- **Practice executor IS in v1, admin-gated** (M5.5).
- Sign in with Google primary; Sign in with Apple removed from Android.
- Discord = authentication only across all platforms (no bot until BoBA server permission).
- Subscription monetization, Personal Showcase, House of BoBA, Hero Shot all deferred post-v1.
- 3D path when prioritized: Filament (primary) / Vulkan via NDK.

### 🚧 Android M0 — Foundation (2026-05-19, in progress)

**Scaffold landed:**
- ✅ `/android/` Gradle project on the **current modern May 2026 stack**: Android Studio Panda 4 / **AGP 9.2.0** (Kotlin support built-in, no `kotlin.android` plugin) / Kotlin 2.1.21 / Compose BOM 2026.05.00 / Material 3 1.5 (Expressive APIs) / Material 3 Adaptive / Navigation 3 (1.0.1; supersedes Nav Compose 2.x) / Coil 3.4.0 / Ktor 3.4.3 / Hilt 2.57.1 / Room 2.7 (KMP-capable)
- ✅ Version catalog (`gradle/libs.versions.toml`) — 60+ dependencies pinned
- ✅ Modular structure: `:app`, `:core:ui`, `:core:domain` (pure Kotlin), `:core:network`, `:core:data`
- ✅ Single Activity (`MainActivity`) + Compose Navigation (NavHost wiring lands in M1)
- ✅ `BobaTheme` with brand `colorScheme` (default) + dynamic-color opt-in path
- ✅ Six design primitives in `:core:ui`: `BOBAWordmark`, `BOBACardCell`, `BOBAEmptyState`, `BOBABanner`, `BOBAOfflinePill`, `BOBASignInPrompt`
- ✅ Coil 3 `ImageLoader` configured at App start (60 MB memory / 500 MB disk parity with iOS DECISIONS.md #024)
- ✅ Shared OkHttp client between Coil and Supabase/Worker calls
- ✅ Two-phase catalog loader (`CardCatalogLoader` + `CardRepository`) mirroring iOS DECISIONS.md #014
- ✅ CDN helpers (`CDN.thumbUrl`/`fullUrl`) — never-hardcode-R2-URLs rule honored
- ✅ Worker config (`WorkerConfig.kt`) — single source of truth
- ✅ `sync_shared_assets.sh` syncs `cards-slim.json` + `categories.json` + fonts from repo root; wired to Gradle `preBuild`
- ✅ Catalog bundle initially populated (~13 MB) so Android Studio first-open doesn't show empty grids
- ✅ AndroidManifest with App Links (`https://bobaplaybook.com/{u,card,deck,learn,search}`) + custom-scheme `bobaplaybook://` intent-filter
- ✅ Adaptive launcher icon (XOXO mark + monochrome variant for themed icons)
- ✅ Splash screen via Android 12+ API; edge-to-edge enabled
- ✅ `/.well-known/assetlinks.json` placeholder at web root; `_config.yml` updated to exclude `android/` from Jekyll Pages build
- ✅ Hilt + KSP wiring (`@HiltAndroidApp` Application, empty `DataModule` placeholder)
- ✅ Domain-model smoke tests in `:core:domain/src/test/` — verifies `bobaId` formula + JSON decoder
- ✅ GitHub Actions workflow (`.github/workflows/android-build.yml`): PR builds, debug APK upload, Play Store upload stub for M8
- ✅ Comprehensive `android/SETUP.md` walking Ben through every external-service setup

**Pending Ben (SETUP.md):**
- ⏳ Install Android Studio + JDK on PATH (Phase A1–A2)
- ⏳ First Gradle sync — generates `gradle/wrapper/gradle-wrapper.jar` (Phase A3)
- ⏳ Generate upload keystore via `keytool` + send SHA-256 + SHA-1 fingerprints back to Claude (Phase B1)
- ⏳ Create Play Console developer account ($25 one-time fee, 24-48h verify, Phase B2)
- ⏳ Create Firebase project + register Android app + download `google-services.json` (Phase B3)
- ⏳ Generate Sign in with Google OAuth client ID + send to Claude (Phase B4)
- ⏳ Send Supabase URL + anon key to Claude (Phase B5)
- ⏳ First-build smoke test: app launches, BOBA wordmark renders on near-black background, no crash (Phase C1)

### ⏳ Android M1 — Find + foundational adaptive layouts (phone + tablet + Chromebook)
- `NavigationSuiteScaffold` (5 destinations) — adapts to NavigationBar (compact) / NavigationRail (medium) / PermanentNavigationDrawer (expanded)
- Find tab with `ExpandedFullScreenSearchBar` on compact / `ExpandedDockedSearchBar` on medium+
- Featured `HorizontalMultiBrowseCarousel` rows (no-search state)
- `LazyVerticalGrid(GridCells.Adaptive)` for search results
- `FilterChip` row for committed tokens
- Container transform (`sharedBounds`) into card detail — compact only; medium+ uses pane switch
- `CardDetailScreen` with canonical 6-cell stats grid
- **WindowSizeClass adaptation validated on Chromebook + Pixel Tablet emulator + phone** — every screen has explicit `COMPACT` / `MEDIUM` / `EXPANDED` behavior
- Edge-to-edge + predictive back validated

### ⏳ Android M2 — Collection
- Designation `SingleChoiceSegmentedButtonRow`
- Grid / List / Wall display modes
- Designation badges
- Custom Rainbow editor (mirrors iOS v2.219+)
- My Shows (role-gated push destination)
- Tablet: `NavigableListDetailPaneScaffold` for Rainbow + Custom Rainbow detail panes

### ⏳ Android M3 — Scan + Pricing
- CameraX + ML Kit Text Recognition v2 bundled (Latin)
- `ScanCoordinator` + per-tab destination routing
- Pricing panels in card detail (eBay + COMC + Radish)
- `BottomAppBar` scan-active state surface
- `HorizontalFloatingToolbar` for medium+ widths

### ⏳ Android M4 — Decks (3-pane on tablet from day one)
- Card pool + persistent `DeckSummaryBar` (compact)
- Tap-summary → `ModalBottomSheet` editor with `sharedBounds` hero zoom (compact)
- **Tablet/Chromebook: `NavigableListDetailPaneScaffold` with 3 panes (saved decks / pool / editor)** — no hero-zoom, pane switching instead
- Manage Decks / Rules / Legality push destinations
- Drag-and-drop via `Modifier.dragAndDropSource` / `dragAndDropTarget`
- Long-press to add (canonical mobile add gesture)

### ⏳ Android M5 — Learn
- Single-stream articles + skill-level `SegmentedButton` scope
- In-corpus `SearchBar`
- Glossary `TooltipBox` for highlighted terms
- Tablet: `NavigableListDetailPaneScaffold` (category list pane + article detail pane)

### ⏳ Android M5.5 — Practice executor (admin-gated)
- Port iOS state-machine engine to pure Kotlin in `:core:domain` (`PersistentEffect`, `WeaponTransform`, `firePersistentTriggers`, `applyHDRecover` pipeline per DECISIONS.md #030)
- `PracticeView` + bench / plays / battle Composables
- Setup screen + tutorial overlay
- Active-battle UI with the 5 phases
- Admin gate via `user_profiles.role` lookup (mirrors iOS DECISIONS.md #033)
- Practice content stays admin-only at production; admins (Ben + close beta) test on Android device + Chromebook

### ⏳ Android M6 — Purchase
- `SingleChoiceSegmentedButtonRow` ("Upcoming Breaks" | "Find a Store")
- Whatnot tile list via `boba-ebay-proxy /whatnot/upcoming`
- Google Maps Compose for Find a Store with `ModalBottomSheet` store list
- Tablet: segmented button splits into `NavigableListDetailPaneScaffold`

### ⏳ Android M7 — Profile + Auth + deep-link dispatcher
- Credential Manager (Sign in with Google primary + passkey support)
- Discord OAuth via Auth Tab (Chrome 132+) / Custom Tabs fallback
- Email/password fallback
- Tink-encrypted DataStore for token storage
- BiometricPrompt gate for sensitive Profile actions
- Avatar upload via `boba-avatar-upload` Worker
- Account deletion via `boba-account-delete` Worker
- Universal Links / deep-link dispatch
- `assetlinks.json` SHA-256 fingerprints (upload key + Play App Signing key) deployed to `bobaplaybook.com/.well-known/`
- Public collection deep-link receiver (`/u/{username}`)

### ⏳ Android M8 — Internal testing + Play Store closed track
- Play Console setup (Internal testing track)
- Data Safety form filled out
- Screenshots + feature graphic + listing assets
- Closed testing track with ≥12 testers × 14 days for production unlock (current Google requirement)
- 16 KB page-size validation via `apkanalyzer` on each release
- R8 + Baseline Profile validation
- Macrobenchmark cold-start regression gate in CI (≤ 5%)

### 🔮 Android Post-v1 Future
- Image fingerprinting (MediaPipe Image Embedder + parallel `feature-prints-android.bin`)
- Multi-card grid scanning (OpenCV port)
- Push notifications (FCM dispatcher via `boba-push-dispatcher` Worker; cross-platform symmetric payload per DECISIONS.md #045)
- Google Play Billing for BOBA Pro subscription (cross-platform launch with iOS + web)
- Personal Showcase + Cast SDK port
- House of BoBA + Hero Shot 3D port (Filament primary, raw Vulkan/NDK fallback per DECISIONS.md #051)
- Home-screen widgets via Glance API
- App Shortcuts + App Actions for Google Assistant integration
- Wear OS companion (if ever)
