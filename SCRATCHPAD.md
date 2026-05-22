# BOBA Playbook — Project Scratchpad

> Active working notes only. Completed milestone implementation detail and the full session log live in [ARCHIVE.md](./ARCHIVE.md). See [DECISIONS.md](./DECISIONS.md) for architecture decisions and [DESIGN.md](./DESIGN.md) for binding iOS design rules.

## Pickup state — 2026-05-21 (pre-compaction)

### What shipped this session

**Cross-platform features**
- Events refresh: dropped Whatnot from `assets/data/events.json` (lives on Purchase tab only via the existing Worker — see DECISIONS.md #034-adjacent update); stripped "Status: published" boilerplate from Carde.io entries; June 18 Tecmo Bowl release added as a curated entry with the official blog URL; OKC pending-art entry removed.
- Refresh workflow (`refresh-events.yml`) now mirrors `events.json` to iOS (`BOBAPlaybook/events.json`) + Android (`android/app/src/main/assets/data/events.json`) bundles in the same commit so they can't drift.
- Web Tournament tab `_eventsHydrated` idempotency removed; fetch revalidates on every tab activate via `cache: 'no-cache'` so stale cache no longer surfaces old "wrong info" rows.
- Glossary long-press → Copy/Share menu shipped 3-platform (iOS contextMenu, Android DropdownMenu via long-press, web Popover API). Always-visible instruction text added above each glossary list.
- iOS events parity: new `UpcomingEventsSection` + `EventRow` + `LearnEvent` + `LearnEventsLoader` inlined into `LearnView.swift` per the synchronized-group memory.
- Daily blog cron: `scripts/refresh_blog.py` scrapes `bobattlearena.com/blog/all` (45 posts) + WP REST dates; `scripts/build_blog_digest.py` writes `docs/blog-digest.md` for autonomous loop mining; new `.github/workflows/refresh-blog.yml` runs daily at 05:17 UTC.
- Doc trim: DESIGN.md / WEB-DESIGN.md / ANDROID-DESIGN.md / DECISIONS.md all under 40K (was 43.3K / 42.1K / 67.2K / 57.3K — saved ~52K total). TRADE-DESIGN.md was already under.

**Android beta-prep**
- Maps SDK wired (`maps-compose` + `play-services-maps` deps; `MAPS_API_KEY` from `local.properties` or env via manifestPlaceholder; new in-app `StoresMap` Composable above the Find a Store list — replaces the list-only `geo:` fallback. Markers capped at 500 mirroring iOS, auto-fit camera to filtered set.)
- Card-detail swipe-nav (Android parity with iOS v2.287): new `CardNavigationStore` (Hilt singleton) + `CardNavigationHolderViewModel`; Find / Decks-compact / Collection screens populate sibling-bobaId list via `LaunchedEffect`; CardDetailScreen owns mutable `currentBobaId` + `detectHorizontalDragGestures` (80dp threshold, wrap-around).
- Scan queue + review surface: new `ScanQueueStore` (Hilt singleton, 25-cap, de-dup by bobaId) + `ScanQueueHolderViewModel` + `ScanReviewSheet` (ModalBottomSheet w/ card name + number + tap-to-route + per-row remove + Clear all). `ScanScreen` adds "Recent · N" TopAppBar action when queue is non-empty.
- Release signing config wired in `app/build.gradle.kts` (reads env / local.properties); `ndk.debugSymbolLevel = "SYMBOL_TABLE"` added so every release ships `native-debug-symbols.zip` alongside the AAB.
- CI `play-store-internal` job uncommented + plumbed with all 5 secrets including `MAPS_API_KEY` + `debugSymbols`. Gated on `v*-android` tag push.

**Play Console asset pipeline**
- `tools/play-assets/` — full HTML/PIL-based render pipeline. Outputs ready: `out/icon-512.png` (sourced from iOS canonical icon, alpha-flattened) + `out/feature-graphic-1024x500.png` (XOXO + brand wordmark + glows). Plus ONE real Find screenshot at `out/screenshot-real-find.png` (real BOBA cards: Leboss / Showtime / Maverick / Mustang / Burrocious / Dart-Board).
- `tools/play-assets/capture-screens.sh` — adb-driven real-app capture script. Working for Find; the other 4 screen captures need re-running with Android Studio booting the emulator (CLI cold-boot is unreliable; see `reference_screenshot_capture_pipeline`).
- `android/distribution/play-console-listing.md` — paste-ready answers for short/long descriptions, Data Safety, IARC content rating, target audience, app access, ads, news/financial/health/government, release notes.

### What's queued for next session (Ben action)

See `WAKE_UP.md` "Things you need to do" for the canonical Ben-action list. Critical path: manual Play Console upload of `app-release.aab` per `reference_android_beta_upload_state` memory + `android/distribution/play-console-listing.md`. Blocker: Play Console API access UI missing for this org account (`reference_play_console_api_access_missing`).

### Autonomous loop pickup hints

- New `docs/blog-digest.md` is now available as a content-mining source. Every blog post on `bobattlearena.com/blog/all` is summarized with date + title + excerpt + URL.
- `feedback_no_mockup_screenshots` + `feedback_ios_icon_is_canonical_brand_source` + `feedback_kotlin_extension_calls_unqualified` are new memories worth reading before any visual / Kotlin work.
- Android v0.1.0 build is green; debug APK + signed release AAB both built. Don't waste a tick rebuilding.

---

## Current State (2026-05-20)

- **Catalog**: 17,974 cards · ~90% image coverage on R2 · OKC art still pending · 30 invalid-power records repaired
- **Latest version**: iOS 2.223 / 486; Android shipped 65 parity items overnight (see below)
- **Hero Shot iteration**: headless CLI runner shipped (`tools/render-hero-shot-variants.sh`) — boots a simulator, renders 4 material variants to `/tmp/hero-shot-variants/grid.png` in ~20-30s

## What Just Shipped (overnight 2026-05-20)

Autonomous /loop ran from ~03:00 → ~09:30 MT closing Android iOS-parity gaps. Full commit-by-area index in memory: [[reference_overnight_parity_session_2026_05_20]]. Headline:

- **iOS Hero Shot CLI runner** (e0a4b87). Env-gated `HeroShotCLIRunner` in BOBAPlaybookApp + `tools/render-hero-shot-variants.sh`. Pairs with `tools/HeroShotSim/sim3d.swift` for offline iteration without driving HeroShotView manually.

- **Android Whatnot deserialization fix** (c325cb2). The worker emits camelCase (`showId`/`host`/`startTimeMs`/`thumbnailUrl`/`viewerCount`/`isLive`) but Android's `WhatnotRow` was `@SerialName("host_username")`/`scheduled_at`/`thumbnail` — every field except `title` deserialized to null. Side-effect: thumbnails / host names / viewer counts / stream-time labels / LIVE pill all surfaced for the first time. Lesson in [[reference_worker_field_shapes]].

- **Android CDN sealed-routing** (b18d005 + 184cc9b + 9289344). Sealed products live at `/sealed/thumbs/` + `/sealed/optimized/` on R2 (not `/thumbs/` + `/full/`). Every BOBACardCell call site now threads `isSealed = card.isSealed`. Booster Boxes / Blasters that were silently 404'ing now render. Lesson in [[reference_android_cdn_sealed_routing]].

- **Android prefs persistence** (ce2b0c2 + 0af2ccf + 2d7e728). New DataStore-backed stores (`FindPrefsStore`, `CollectionPrefsStore`, existing `GridDensityStore` wired) so Find showcase / quickAdd / grid density + Collection display mode / sort survive process death. iOS @AppStorage parity. Pattern in [[reference_android_prefs_pattern]].

- **Android pricing parity** (df7e799 + 27796a4 + 9d7f8d7 + 6e5f6a8 + 19abc3d). Market estimate now prefers the Worker's pre-computed canonical average (with `priceType` / `count` context) instead of recomputing client-side. USD format clamped to Locale.US. Refresh IconButton. Buy URLs open in Custom Tab. Lesson in [[feedback_worker_canonical_average]] + [[feedback_usd_locale_format]].

- **Android Decks polish** (multiple commits). DBS budget chip + Legality DBS row + AddToDeck post-add projection + over-cap StatChip tints + long-press add snackbar + remove-with-Undo snackbar + name validation + clear-draft confirm + Manage Decks rename / search / PTR + editor empty-state + pool empty-state + CSV export as FileProvider attachment + Rules screen DBS section.

- **Android Card detail polish**. DBS explainer ModalBottomSheet + "Decks with this card" tap-to-load + "In your collection" summary + Other Versions treatment labels + image attached to share + Add-to-Show role-gated + tap-price hint + Worker market average + pricing refresh button + Custom Tab buy URLs.

- **Android Profile polish**. Hints section + Public URL copy/share + Version row + Send Feedback row + Change Password row + Auth-state cache reset + Username 30-char clamp + Avatar refresh on upload + spinner-backed loading state + Find tab avatar leading icon.

- **Android Collection polish**. Edit Copy sheet (purchase/asking/condition/notes) + condition domain round-trip + search field + display-mode persisted + Wall share enriched + display-mode hint + PTR + Scan empty-state action.

- **Android Custom Rainbow delete** (60eb9fb). Delete IconButton + AlertDialog. Editor still create-only.

- **Android cross-cutting**. Ctrl+1..5 keyboard shortcuts + new AuthViewModel adapter + Scan permanent-denial handler + USD formatter shared helper.

**Patterns to remember:** [[feedback_state_from_prop_antipattern]] · [[feedback_viewmodel_reset_on_auth_change]] · [[reference_worker_field_shapes]] · [[reference_android_cdn_sealed_routing]] · [[reference_android_prefs_pattern]] · [[feedback_usd_locale_format]] · [[feedback_worker_canonical_average]].

## What Just Shipped (recent — 2026-05-15)

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

## Active / Next-Up

- **Match-alerts pipeline** (Wanted/Grail notifications) — UI toggle ships, APNs server-side dispatcher is multi-week of new infra. See DECISIONS.md #039. Match-alerts pipeline is now Phase 7 of the TRADE-DESIGN.md §14 roadmap; don't ship before Phase 0 (LLC + insurance + ToS) is done.

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

### ✅ Android M0–M7 — Foundation through Auth (2026-05-19 → 2026-05-19)

**M0 through M7 shipped in a single rapid-pace session.** All eight milestones are at "fast-progress" state — screens render, build is green, key infrastructure (auth, scanning, navigation) is wired. Polish items called out in each milestone's commit message.

Final stack in production: Android Studio Panda 4 / AGP 9.2.0 / Kotlin 2.3.21 / Compose BOM 2026.05.00 / Material 3 / Hilt 2.59.2 / Coil 3.4.0 / Ktor 3.4.3 / supabase-kt 3.0.2 / CameraX 1.4 / ML Kit 16.0.1 / Credential Manager 1.3.0 / Firebase BOM 34.13.0.

**Shipped screens:** Find (search + filter + grid) · Card detail (canonical 6-cell stats) · Collection (designation segmented + sign-in prompt) · Scan (CameraX + ML Kit live OCR) · Decks (pool + summary bar) · Learn (category list + push) · Purchase (segmented Breaks/Stores) · Profile sheet (Sign in with Google via Credential Manager + supabase-kt).

**Deferred follow-ups (post-v1):**
- Material 3 Expressive APIs (FAB Menu / Floating Toolbar / Wavy Indicators) — needs compileSdk 37
- M3 SearchBar full-screen morph (uses OutlinedTextField for M1)
- Container transform / sharedBounds animations (M2 polish)
- Whatnot tile list + Google Maps Find a Store (M6 polish — Worker wiring + Maps API key)
- Article corpus port from iOS Swift (M5 polish — content work)
- Custom Rainbows, Wall view, Shows (M2 polish)
- Tablet 3-pane Decks editor + NavigableListDetailPaneScaffold rollout (post-M7 polish)
- **Practice executor engine port** (M5.5 — admin-gated placeholder shipped; full state-machine port is multi-session)
- Discord OAuth via Auth Tab / Custom Tabs (M7 polish — current Sign in with Google flow is wired; Discord path stubbed)
- Tink-encrypted token storage (M7 polish — supabase-kt's default SessionManager used today)
- Image fingerprinting (MediaPipe) + multi-card grid scan (DECISIONS.md #043 — v2)

### Archived M0 details (kept for reference)

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

### ⏳ Android M4 — Decks (3-pane on tablet polish)
- **Tablet/Chromebook: `NavigableListDetailPaneScaffold` with 3 panes (saved decks / pool / editor)** — no hero-zoom, pane switching instead
- Drag-and-drop via `Modifier.dragAndDropSource` / `dragAndDropTarget`
- Container transform / `sharedBounds` hero zoom on the compact editor sheet
- (Card pool + DeckSummaryBar + Manage Decks / Rules / Legality push surfaces shipped tick 196+ audit)

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
