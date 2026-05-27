# BOBA Playbook — Cross-Platform Feature Parity

> **Single source of truth** for what's shipping where. Updated whenever a feature lands on any platform.
>
> Companion to [`CLAUDE.md`](./CLAUDE.md), [`SCRATCHPAD.md`](./SCRATCHPAD.md) (project state), [`DESIGN.md`](./DESIGN.md) (iOS), [`WEB-DESIGN.md`](./WEB-DESIGN.md) (web), [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md) (Android).
>
> Ratified 2026-05-19.

---

## Legend

- ✅ **Shipped** — feature is live in production on this platform
- 🚧 **In progress** — feature is being built; some parts may already be in main
- ⏳ **Planned** — committed; targeted for an upcoming milestone
- 🔮 **Future** — agreed direction; no timeline yet
- 🚫 **Out of scope** — explicitly not built on this platform (with reason)
- n/a — platform-inapplicable (e.g., AVFoundation specifically on web)

---

## Parity rule

When shipping any user-facing feature:

1. **Confirm the verb is identical across platforms** (Find = explore, Learn = understand, Decks = build, Collection = own, Purchase = acquire — per DESIGN.md §1.1, WEB-DESIGN.md §2.2, ANDROID-DESIGN.md §2.1).
2. **Pick the native idiom on each platform** — iOS Tab(role: .search), web SearchBar + URL params, Android Material 3 SearchBar.
3. **Update this table** in the same PR. Drift here is what blocks "always ensure web parity" (the MEMORY rule we've been burned by).
4. **Cross-link to the binding design doc** for each platform that has one.

---

## 1. Tabs / top-level navigation

| Verb | iOS | Web | Android | Notes |
|---|---|---|---|---|
| **Find** (explore) | ✅ | ✅ | ✅ | DESIGN.md §8.1 · WEB-DESIGN.md §14.1 · ANDROID-DESIGN.md §8.1 — M1 scaffolding shipped + overnight 2026-05-20 polish landed |
| **Learn** (understand) | ✅ | ✅ | ✅ | DESIGN.md §8.2 · WEB-DESIGN.md §14.2 · ANDROID-DESIGN.md §8.2 — Android articles + Archetype Templates + Watch shipped |
| **Decks** (build) | ✅ | ✅ | ✅ | DESIGN.md §8.3 · WEB-DESIGN.md §14.3 · ANDROID-DESIGN.md §8.3 — Android editor + template gallery + DBS shipped |
| **Collection** (own) | ✅ | ✅ | ✅ | DESIGN.md §8.4 · WEB-DESIGN.md §14.4 · ANDROID-DESIGN.md §8.4 — Android designation + display modes + edit copy shipped |
| **Purchase** (acquire) | ✅ | ✅ | ✅ | DESIGN.md §8.5 · WEB-DESIGN.md §14.5 · ANDROID-DESIGN.md §8.5 — Android Whatnot fix + segmented picker shipped |

---

## 2. Find — explore

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Card grid with 17,974 cards | ✅ | ✅ | ✅ | `LazyVerticalGrid(GridCells.Adaptive)` |
| `SearchBar` (search-first IA) | ✅ | ✅ | ✅ | iOS `Tab(role: .search)` · Web `<input type="search">` · Android OutlinedTextField (M3 SearchBar morph is M1 polish) |
| Search tokens / chips | ✅ | ✅ | ✅ | `BOBAFilterToken` / URL params / `InputChip` |
| Filter rows (weapon, cost, hero, treatment) | ✅ | ✅ | ✅ | `FilterChip` flow row — Android shipped overnight 2026-05-20 |
| Featured shelves (no-search state) | ✅ | ✅ | ✅ | Android: `HorizontalMultiBrowseCarousel` showcase carousels |
| Multi-select + bulk add | n/a | ✅ | 🔮 | Web-only today; mobile uses long-press add |
| Multi-select → Wall these N cards | n/a | ✅ | 🔮 | Web-only — selection toolbar `Wall` action calls `openCardsWallSheet` (tick 10). Title defaults to "N cards". |
| Card detail push w/ hero zoom | ✅ | ✅ | ✅ | All three shipped. Android wired via `cardSharedBounds(card.bobaId)` on Find + Decks + Collection grid cells; CardDetailScreen art panel uses the same key. Audit 2026-05-21 confirmed source + destination plumbing in place. |
| Card-size picker (S/M/L density) | ✅ | ✅ | ✅ | Toolbar Menu → 1/2/3 cols on all three; Android persists via `GridDensityStore` (DataStore) |
| Profile entry (Find-only) | ✅ | ✅ | ✅ | TopAppBar leading icon — per `feedback_profile_only_on_find` |
| Saved Searches | 🔮 | 🔮 | 🔮 | **Not built anywhere.** Earlier ✅✅ claim was inaccurate; audit 2026-05-20 found zero `savedSearch` references in any client. Deferred until designed (DESIGN.md §8.1 mentions as no-search-state shelf candidate, but no implementation has landed). |
| Walkthrough on first visit | ✅ | 🚫 §11 | 🚫 §6.10 | Web + Android skip; replaced by EmptyState + tooltip |

---

## 3. Learn — understand

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Categories: Rules / Strategy / Collect / Glossary / Tournament | ✅ | ✅ | ✅ | Single-stream article rendering — Android Tournament richness is M5 polish |
| Skill-level scope (Rookie / Sub / Playmaker) | ✅ | ✅ | ✅ | `SegmentedButton` scope inside Rules article |
| Read/Watch toggle (when video exists) | ✅ | ✅ | ✅ | Same scope pattern |
| In-corpus search | ✅ | ✅ | ✅ | `.searchable` / search input / `SearchBar` |
| Glossary lookup (inline definitions) | ✅ | ✅ | ✅ | iOS GlossaryView + Android LearnArticleScreen::GlossaryPage + web Learn Glossary tab (shipped tick 88) — all three tap-to-copy. Web uses event delegation on `.glossary-row` w/ `navigator.clipboard.writeText`. |
| Browse-by-hero | n/a | n/a | n/a | Moved to Find per DESIGN.md §1.1 verb separation |
| Watch (YouTube feed: Upcoming Live / Vertical / Horizontal) | ✅ | ✅ | ✅ | Worker `boba-youtube-feed`. Android shipped Upcoming-Live/Horizontal/Vertical segmented tabs overnight 2026-05-20 |
| Archetype Templates (5 strategy cards) | ✅ | ✅ | ✅ | Android shipped overnight 2026-05-20 with key-play thumbnails from catalog |

---

## 4. Decks — build

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Card browser (deck builder canvas) | ✅ | ✅ | ✅ | `LazyVerticalGrid` — Android shipped |
| Browser search + filter | ✅ | ✅ | ✅ | Format chips + weapon/cost/hero |
| Current deck summary | ✅ DeckSummaryPill | ✅ inline | ✅ DeckSummaryBar | Bottom-anchored |
| Deck editor sheet w/ zoom | ✅ | ⏳ desktop pattern | ⏳ M4 polish | iOS shipped; web desktop split deferred; Android editor sheet shipped, `sharedBounds` zoom is polish |
| Deck stats (counts + cost curve) | ✅ | ✅ | ✅ | Same canonical layout; Android DBS budget chip shipped overnight |
| Save deck (Supabase `decks` table) | ✅ | ✅ | ✅ | Auth-required write |
| Manage saved decks | ✅ | ✅ | ✅ | Android shipped: rename + search + PTR. Web shipped rename + search tick 13 (`deckRename` API + ✎ icon per row + `db-saved-decks-search` filter). Refresh button (web analog of PTR) added tick 14 — `_renderSavedDecksList` extracted so Refresh shares render path with Load; preserves active search filter across refresh. |
| Rules + Legality push surfaces | ✅ | ✅ | ✅ | Push as destinations (not stacked sheets) |
| Drag-and-drop add | ✅ iPad only | n/a | ⏳ M4 polish | `dragAndDropSource` + `dragAndDropTarget` |
| Long-press add on browser | ✅ | n/a | ✅ | Canonical mobile add |
| 3-column tablet layout (saved / browser / editor) | ✅ iPad | ⏳ desktop | ⏳ M4 polish | `NavigableListDetailPaneScaffold` 3-pane — in v1 from M4 per DECISIONS.md #047 |
| Template gallery (empty editor) | ✅ | ✅ | ✅ | Web upgraded tick 11 — card-style 5-archetype gallery with per-archetype accent color (STEEL/ICE/CYAN/GLOW/BRAWL) matching iOS TemplateCard. |
| Generate deck wall (share image) | ✅ | ✅ | ✅ | Web shipped tick 9 — db-wall-btn reuses the canvas Wall pipeline. Android shipped tick 76 — `DeckWallSheet` reuses `WallShareHelper` (same `graphicsLayer.record` capture + FileProvider + ACTION_SEND). Editor exposes IconButton (modal-sheet) + OutlinedButton "Wall" (tablet inline pane); both gated on `draft.cards.isNotEmpty()`. |
| Walkthrough | ✅ | 🚫 | 🚫 | Same skip rule |

---

## 5. Collection — own

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Designation: Personal / Sale / Trade / Wanted / Grails | ✅ | ✅ | ✅ | `SegmentedButton` — Android shipped |
| In-collection search | ✅ | ✅ | ✅ | iOS `.searchable` with `.navigationBarDrawer(.always)`. Web shipped tick 34. Android `CollectionScreen` compact search pill at line 1007 (`TextField` w/ `CardSearch.matchesFields` filter, audit tick 196). |
| Designation badge per cell | ✅ | ✅ | ✅ | Corner overlay |
| Display modes: Grid / List / Wall | ✅ | ✅ | ✅ | All three modes shipped on Android (audit tick 196 found `CollectionWall` at CollectionScreen.kt:690 — was marked ⏳ in error). |
| Grid density picker (1/2/3 cols) | ✅ | ✅ | ✅ | DataStore-backed on Android via `CollectionPrefsStore` |
| Value summary | ✅ | ✅ | ✅ | `user_cards.estimated_value` |
| Value history chart | 🔮 | 🔮 | 🔮 | **Not built anywhere.** Both DESIGN.md §8.4 and ANDROID-DESIGN.md §8.4 describe it ("tap value summary → chart") but no implementation has landed on any platform. Was marked ✅ iOS in error; audit 2026-05-20 (tick 12) corrected. |
| Custom Rainbows | ✅ | ✅ | ✅ | Per-user filter goals; Supabase `user_custom_rainbows`. Web shipped tick 7 read-only display + tick 15 name editor + tick 16 full 7-dimension filter sub-pickers + Inspired Ink toggle + live progress preview. Android: read + create + delete + tick 61 edit/rename + **tick 81 full 7-dimension parity** — Heroes / Weapons / Treatments / Sets / Sub-sets / Releases / Card types + Inspired Ink toggle, all surfaced in CustomRainbowEditorSheet with chip pickers derived from the live catalog. |
| Per-hero Auto Rainbows | ✅ | ✅ read-only | ✅ read-only | Web synthesizes one row per owned hero × catalog, sorted by completion % desc (tick 8). Android shipped owned-treatments + per-hero label + chevron previously; tick 66 added total-treatments-from-catalog (so users see "5 of 15 treatments · 33% · 8 copies" not just "5 treatments") + completion-% sort. iOS-equivalent rendering. |
| My Shows (streamer-only) | ✅ | 🔮 | ✅ | iOS ships ShowsListView + ShowDetailView + show_cards table. Web has no streamer Shows surface (only Whatnot tile read on Purchase). Android shipped `ShowsListScreen.kt` (audit tick 196). |
| Wall view (display mode + share) | ✅ | ✅ canvas-render | ✅ | Web shipped canvas-rendered PNG (download + clipboard + Web Share) tick 5. Android Wall mode + share-as-PNG via `WallShareHelper` + graphicsLayer capture (CollectionScreen.kt:690, audit tick 196). |
| Price Overlay (in Wall view) | ✅ | ✅ | ✅ | Per-designation defaults (For Sale / Trade / Wanted ON; Personal / Grails OFF). Android FilterChip toggle at CollectionScreen.kt:726 (audit tick 196). |
| Personal Showcase (iTunes-style screensaver) | ✅ | 🚫 | 🚫 v1 §12 | Android: Cast SDK port deferred |
| AirPlay-Video for Showcase | ✅ | 🚫 | 🚫 v1 §12 | Android Cast SDK is the parallel |
| Public collection URL (`/u/{username}`) | n/a (toggle only) | ✅ | ✅ | Web renders; Android toggle in ProfileSheet was always-rendered but hardcoded to false; tick 199 added the server-hydration LaunchedEffect so it reflects the saved state. |

---

## 6. Purchase — acquire

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Upcoming Whatnot breaks | ✅ | ✅ | ✅ | Worker `boba-ebay-proxy /whatnot/upcoming` — Android deserialization fix shipped overnight 2026-05-20 |
| Find a Store (~330 indie + ~1,800 big-box) | ✅ MapKit | ✅ Leaflet | ✅ | Android Google Maps Compose shipped tick 202 (commit 54d2124) — `maps-compose` 6.1.2 + `play-services-maps` 19.0.0 |
| Filters: radius, indie-only | ✅ | ✅ | 🚧 | Android indie-only chip ✅; radius / Near-Me location permission pending |
| Tap break tile → external Whatnot | ✅ | ✅ | ✅ | Android shipped via `CustomTabsIntent` overnight |

---

## 7. Scanning (camera + OCR)

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Live single-card scan | ✅ | 🚧 | ✅ | iOS/Android: on-device Vision / ML Kit. Web: `getUserMedia` → Worker OCR (experimental, less performant). DECISIONS.md #054. |
| Card-number regex match | ✅ | 🚧 | ✅ | Web inherits via Worker response. Worker `boba-ebay-proxy /ocr` (planned) or equivalent. |
| Hero-name veto | ✅ | 🔮 | ✅ | Web OCR doesn't currently veto by hero — iterate per DECISIONS.md #035 once Worker shape is firm. |
| Image-fingerprint matching | ✅ | 🔮 | 🔮 v2 | MediaPipe Image Embedder; parallel `feature-prints-android.bin`. Web could ship a JS port reading the same `feature-prints.bin`. |
| Multi-card grid scan | ✅ | 🔮 | 🔮 v2 | OpenCV port (iOS-only today). |
| Scan queue / review surface | ✅ | 🔮 | ✅ | Android ScanQueueStore (Hilt singleton, 25-cap, de-dup by bobaId) + ScanReviewSheet ModalBottomSheet — commit 54d2124. Web could ship a parallel `localStorage`-backed queue. |
| Per-tab destination routing (Find/Decks/Collection) | ✅ | 🔮 | ✅ | Android ScanCoordinator + ScanDestination enum (BOBAApp.kt:263). Web doesn't have tabs in the same shape; would route by recent-view heuristic. |
| Desktop → phone QR session handoff | n/a | ✅ | n/a | Web-only affordance (DECISIONS.md #054). Desktop shows QR encoding `?view=scan&rt={refresh_token}`; phone scans → opens BOBA on phone with desktop session. |
| Native-app CTA inside Scan view | n/a | ✅ | n/a | TestFlight + Google Play tiles. `nativeAppCalloutHTML()` in `js/app.js`. |

**Scan is canonical on iOS + Android** (on-device Vision / ML Kit per DECISIONS.md #012). **Web Scan is in scope** as (a) a fallback for desktops without the native apps, (b) a desktop → phone QR handoff surface, and (c) the marketing surface for the native apps (DECISIONS.md #054).

---

## 8. Card detail surface

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Canonical 6-cell stats grid | ✅ | ✅ | ✅ | DECISIONS.md #029 |
| Cost + DBS (Plays only) | ✅ | ✅ | ✅ | Rendered below the canonical 6 |
| Pricing panels (Buy Now + Sold) | ✅ | ✅ | ✅ | DECISIONS.md #013 |
| eBay listings | ✅ | ✅ | ✅ | Worker proxy |
| eBay sold comps | ✅ | ✅ | ✅ | Worker proxy |
| Radish recent sales | 🚫 | 🚫 | 🚫 | Removed 2026-05-23 per DECISIONS.md #056 + RADISH_REMOVAL_LOOP.md. Per-card "View on Radish" external link retained on all three platforms (homepage fallback when `card.radishUrl` is null). |
| COMC asking (separate, NOT in waterfall) | ✅ | ✅ | 🚫 | DECISIONS.md #034 — Android skipping per `feedback_comc_blocked_all_platforms` Turnstile gate |
| Whatnot active asks (Buy Now, NOT in waterfall) | ✅ | ✅ | ⏳ | PRICING_PLAYBOOK §4 (Tier 2). `boba-ebay-proxy /whatnot/products` returns current active listings; Hybrid surfacing (this card's matches first, then "Other {hero}"). Asking signal only — never the sold waterfall/Market Est. Web + iOS shipped (`WhatnotProductsService` + `whatnotStrip`); Android client tiles pending. |
| Community comp submission (Tier 3) | ✅ | ✅ | ✅ | PRICING_PLAYBOOK §5 · DESIGN/ANDROID/WEB-DESIGN §8.7/§14.6. Quiet foot link → focused sheet/form (price/date/platform/notes); `submit_community_comp` RPC enforces rate limits (5/day, 1/card/week) + mod review. Text-only v1 (photo upload + mod-queue UI pending). |
| Add to Collection / Deck / Show | ✅ | ✅ | ✅ | Auth-required |
| Edit Designation | ✅ | ✅ | ✅ | Collection context — Android Edit Copy sheet shipped |
| Share (deep link + image) | ✅ | ✅ | ✅ | iOS share sheet · Web Share API · Android `Intent.ACTION_SEND` w/ FileProvider |
| Mod edit (mod-gated) | ✅ | ✅ | 🔮 v2 | Role check; Android admin/mod panel deferred to v2 |
| Other Versions browsing | ✅ | ✅ | ✅ | Same hero, different treatments |
| Hero zoom animation | ✅ compact only | ✅ via View Transitions API | ✅ compact only | Android wires `SharedTransitionLayout` at app root + `cardSharedBounds(bobaId)` on source cells (Find / Decks / Collection) + CardDetailScreen art panel destination. Audit 2026-05-21. |
| DBS explainer modal | ✅ | ✅ | ✅ | iOS sheet · web native `<dialog>` · Android `ModalBottomSheet` |
| Pricing refresh button | ✅ | ✅ | ✅ | All three platforms; web sends `fresh=1` to Worker for cache bypass |
| Tap-price hint | ✅ | n/a | ✅ | Mobile-only first-run hint |
| Card detail swipe nav (left/right) | ✅ | ✅ | ✅ | iOS shipped v2.287 across Find / Decks / Collection + v2.315 added Cmd+arrow keyboard parity. Web shipped in modal: ArrowLeft/Right keys + touch-swipe (>60px threshold + dx > 1.5×dy) wired to `navigateModal(±1)`. Android shipped: CardNavigationStore (Hilt singleton) populated by Find / Decks / Collection LaunchedEffects; CardDetailScreen owns `detectHorizontalDragGestures` (80dp threshold, wrap-around). Audit 2026-05-22. |

---

## 9. Authentication + Profile

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Sign in with Apple | ✅ | ✅ | 🚫 §12 | iOS brand; Android uses Sign in with Google |
| Sign in with Google | 🔮 | 🔮 | ✅ | Android Credential Manager (one-tap + passkey-capable bottom sheet) |
| Email/password | ✅ | ✅ | ✅ | Same Supabase shape on all three |
| Discord OAuth | ✅ | ✅ | ✅ | Android `AuthManager.signInWithDiscord()` wired via supabase-kt's Discord provider + Custom Tabs (DECISIONS.md #049); ProfileSheet Discord-link row branches on linked state (tick 211) |
| Passkey support | 🔮 | 🔮 | ✅ | Free via Credential Manager bottom sheet on Android |
| Biometric gate (sensitive actions) | ✅ Face ID | n/a | ⏳ M7 polish | `BiometricPrompt` wiring still pending on Android |
| Username (banned-words gated) | ✅ | ✅ | ✅ | Same `set_username` / `check_username` RPCs |
| Avatar upload | ✅ | ✅ | ✅ | Same `boba-avatar-upload` Worker; bind in ProfileSheet w/ avatarPicker |
| Public collection toggle | ✅ | ✅ | ✅ | Hydration fix landed tick 199 (commit a5c72e9) |
| Generalized role request (mod / streamer) | ✅ | ✅ | ✅ | Same `request_role` RPC |
| Account deletion | ✅ | ✅ | ✅ | Same `boba-account-delete` Worker |
| Discord identity link (for trading) | ✅ | ✅ | ✅ | Android Profile Discord-link row branches on linked state (tick 211) — captureDiscordIdentity persists discord_user_id + avatar_url |
| Notification toggle (match alerts) | ✅ UI only | ✅ UI only | ✅ UI only | Match-alerts pipeline deferred per DECISIONS.md #039 |
| Trading toggle (Discord-gated) | ✅ UI only | ✅ UI only | ⏳ | Surfaces with Discord OAuth M7 polish; TRADE-DESIGN.md Phase 1 |
| Admin panel | ✅ | ✅ | 🔮 | Role-gated; defer to v2 |
| Mod panel | ✅ | ✅ | 🔮 | Role-gated; defer to v2 |
| Mod card edits (add / edit) | ✅ | ✅ | 🔮 | Same Worker `boba-mod-merge` |
| Community comp review queue (mod) | ✅ | 🔮 | 🔮 | PRICING_PLAYBOOK §5 · Tier 3. Web: Profile → Moderation → "Review Sold Comps" (`get_pending_community_comps` / `review_community_comp`, mod+admin). iOS/Android parity is a follow-up — moderation happens on web today. |
| Sign-in method pill on Profile | ✅ | ✅ | ✅ | Android ProviderPill — Google = #4285F4, Discord = #5865F2, Apple = black, email = unmarked default (matches iOS) |

---

## 10. Universal Links / Deep Linking

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Universal Links / App Links (HTTPS) | ✅ | n/a | ✅ | Android AndroidManifest intent-filter `autoVerify=true` + assetlinks.json at /.well-known/ |
| Custom scheme (`bobaplaybook://`) | ✅ | n/a | ✅ | Android intent-filter ships |
| `card`, `search`, `scan`, `learn` routes | ✅ | ✅ | ✅ | Same URL shape across all platforms |
| `/u/{username}` (public collection) | n/a | ✅ | ✅ | Web renders the page; mobile deep-links route to it |
| OAuth callback handling | ✅ via `routeIncoming` | ✅ | ✅ | Android `supabase.handleDeeplinks(intent)` ships in MainActivity |

---

## 11. Notifications

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| APNs / FCM token registration | 🔮 | 🚫 §17 | 🔮 | Web push out of scope per WEB-DESIGN.md §17 |
| Notification permission request | 🔮 | 🚫 | 🔮 | At opt-in moment, not launch |
| Notification channels (Android-specific) | n/a | n/a | 🔮 | Match-alerts, breaking-news, trade-messages |
| Cross-platform push dispatcher | 🔮 | n/a | 🔮 | One Worker, two transports (DECISIONS.md #045) |
| Match-alert notification | 🔮 | 🚫 | 🔮 | Pipeline deferred per DECISIONS.md #039 |

---

## 12. Payments / Subscription

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| BOBA Pro subscription | 🔮 | 🔮 | 🔮 | TRADE-DESIGN.md §7 — sub tier as the only monetization path |
| Apple IAP integration | 🔮 | n/a | n/a | 30% Y1, 15% Y2+ |
| Google Play Billing | n/a | n/a | 🔮 | 15% standard, 10% recurring subs |
| Stripe / external subscription on web | n/a | 🔮 | n/a | Phase 4 |
| Cross-platform subscription state sync | 🔮 | 🔮 | 🔮 | `user_subscriptions` Supabase table; webhooks from Apple + Google |

---

## 13. Trading (TRADE-DESIGN.md)

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Match detection (`trade_matches` table) | 🔮 | 🔮 | 🔮 | Phase 1 |
| Match list view | 🔮 | 🔮 | 🔮 | New top-level surface |
| "Open Discord" deep-link to other user | 🔮 | 🔮 | 🔮 | Discord identity required (TRADE-DESIGN.md §4.2) |
| Block user (`user_blocks` table) | 🔮 | 🔮 | 🔮 | Bilateral hide |
| Report user (mailto:) | 🔮 | 🔮 | 🔮 | Apple §1.2 / Play Console requirement |
| Push notifications on new match (Pro-gated) | 🔮 | 🚫 | 🔮 | Subscription-gated |
| EU geo-block on trading endpoints | 🔮 | 🔮 | 🔮 | DSA Art. 30 avoidance |
| Trading-required ToS clauses | 🔮 | 🔮 | 🔮 | TRADE-DESIGN.md §5 |

---

## 14. Practice executor (admin-gated)

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Battle simulator engine | ✅ admin-gated | n/a | ⏳ M5.5 admin-gated | iOS DECISIONS.md #030; Android DECISIONS.md #048. State machine ports as pure Kotlin in `:core:domain` |
| Practice setup screen | ✅ | n/a | ⏳ M5.5 | Deck + opponent selection |
| Active battle UI | ✅ | n/a | ⏳ M5.5 | 5-phase flow: bench / plays / battle / resolve / next |
| Tutorial overlay | ✅ | n/a | ⏳ M5.5 | First-launch tutorial |
| Admin gate (bolt icon on Profile role badge) | ✅ | n/a | ⏳ M5.5 | Same `user_profiles.role` lookup |

---

## 15. Easter eggs + extras

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| House of BoBA (card-tower playground) | ✅ | n/a | 🚫 v1 | iOS RealityKit-specific; Filament/Vulkan port future (DECISIONS.md #051) |
| Hero Shot (3D card video) | ✅ | n/a | 🚫 v1 | Filament port a separate effort (DECISIONS.md #051) |

---

## 16. Web-specific affordances

These are web-only by design; mobile platforms handle the same need natively.

| Feature | Web | Why |
|---|---|---|
| URL params reflect filter state | ✅ | Shareable deep links; not relevant on mobile |
| Public collection page (`/u/{username}`) renderer | ✅ | Web is the only platform that renders for unauthenticated viewers |
| Web Share API + clipboard fallback | ✅ | Native iOS/Android handle this via system share sheet |
| View Transitions API (cross-view fade + hero zoom) | ✅ | iOS uses `.navigationTransition(.zoom)`; Android uses `sharedBounds` |
| Container queries on `.card-item` | ✅ | iOS/Android use compose-time size class branching |

---

## 17. iOS-specific affordances

These are iOS-only by design; other platforms handle the same need with platform-native equivalents.

| Feature | iOS | Why |
|---|---|---|
| Multi-step anchored walkthroughs | ✅ | Web rejects per §11; Android rejects per §6.10 — replaced with empty states + tooltips |
| Liquid Glass tab bar / toolbar | ✅ | Web uses `backdrop-filter`; Android uses Material 3 tonal elevation |
| Hero Shot 3D RealityKit rendering | ✅ | Web / Android out-of-scope for v1 |
| House of BoBA RealityKit-based playground | ✅ | Out-of-scope on other platforms |
| Hero Shot entry from Collection card detail | ✅ | RealityKit-specific; out of scope on other platforms |
| House of BoBA invocation from Profile menu | ✅ | Same RealityKit dependency |
| Personal Showcase (iTunes-style screensaver) | ✅ | Cast SDK port deferred on Android; web 🚫 |
| AirPlay-Video for Personal Showcase | ✅ | Android Cast SDK is the parallel — deferred |
| Live Activities / Dynamic Island | 🔮 | Android has no exact equivalent; accept asymmetry |
| `.matchedTransitionSource` + `.navigationTransition(.zoom)` | ✅ | Web uses View Transitions API; Android uses `sharedBounds` |
| Hardware-keyboard shortcuts (Cmd+1..5 tabs) | ✅ | Web n/a (browser shortcuts conflict); Android ships Ctrl+1..5 on tablets/Chromebooks |

---

## 18. Android-specific affordances

These are Android-only by design; iOS / web handle the same need with platform-native equivalents.

| Feature | Android | Why |
|---|---|---|
| Predictive back gesture | ⏳ | iOS swipe-back is fixed-animation; Android is user-driven |
| Adaptive icon (foreground / background / monochrome) | ⏳ | iOS uses static app icon |
| App Shortcuts (long-press app icon) | ⏳ M7 | iOS has AppIntent; Android has shortcuts + AppActions |
| Edge-to-edge with predictive back | ⏳ | Mandatory on Android 15+; iOS has its own safe-area model |
| Material 3 dynamic color (Material You) opt-in | ⏳ | iOS / web have brand-only theming |
| 16 KB page size support | ⏳ | Android 15+ on 64-bit native libs (Play Store requirement) |
| Play Integrity API server verification | 🔮 | iOS App Attest is the parallel; deferred on both |

---

## 19. Backend services (shared)

All three clients consume the same backend:

| Service | Purpose | Used by |
|---|---|---|
| **Supabase** Postgres + Auth | RLS-protected user data; auth tokens | iOS, web, Android |
| **Cloudflare R2** | Image CDN (17,734 cards, ~5MB JSON) | iOS, web, Android |
| **Cloudflare Worker `boba-ebay-proxy`** | eBay Browse + Whatnot upcoming shows | iOS, web, Android |
| **Cloudflare Worker `boba-comc-proxy`** | COMC asking-price proxy (Turnstile-blocked) | iOS, web, Android |
| **Cloudflare Worker `boba-account-delete`** | User account deletion (auth-gated) | iOS, web, Android |
| **Cloudflare Worker `boba-avatar-upload`** | R2 avatar storage (2MB cap) | iOS, web, Android |
| **Cloudflare Worker `boba-mod-merge`** | Mod card-image overrides (auth + role) | iOS, web, Android |
| **(Future) `boba-push-dispatcher`** | Single dispatcher, two transports (APNs + FCM) | iOS, Android |

**Compatibility:** all Workers accept `Authorization: Bearer {jwt}` + JSON / bytes — transport-agnostic. **Zero server-side changes needed for an Android client.** (ANDROID-DEV.md §5.4 documents the per-Worker matrix.)

---

## Maintenance protocol

When you ship a feature:

1. **Find the row** in this table. Add new rows under the right section if needed.
2. **Update each platform's status** with one of the legend symbols.
3. **Link to the relevant section of DESIGN.md / WEB-DESIGN.md / ANDROID-DESIGN.md** that governs the feature's design rules.
4. **Note any platform-specific deltas** in the Notes column.

When a feature ships on one platform but is meaningfully different elsewhere, **add an entry to §16 / §17 / §18** explaining why.

When a platform explicitly rejects a feature (e.g., walkthroughs on web + Android), **add an "Out of scope" row in the relevant design doc's §12** and link from this table.
