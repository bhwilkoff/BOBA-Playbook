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
- n/a — platform-inapplicable (e.g., scan on web — needs camera + on-device OCR)

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
| Card detail push w/ hero zoom | ✅ | ✅ | ⏳ M1 polish | iOS + web shipped; Android destination scaffolding done, `sharedBounds` zoom is M1 polish |
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
| Glossary lookup (inline definitions) | ✅ | ✅ | ✅ | TooltipBox on Android |
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
| Generate deck wall (share image) | ✅ | ✅ | 🔮 | Web shipped tick 9 — db-wall-btn in Decks toolbar reuses the shared canvas Wall pipeline (price overlay disabled for deck context). |
| Walkthrough | ✅ | 🚫 | 🚫 | Same skip rule |

---

## 5. Collection — own

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Designation: Personal / Sale / Trade / Wanted / Grails | ✅ | ✅ | ✅ | `SegmentedButton` — Android shipped |
| In-collection search | ✅ | ✅ | ⏳ M2 polish | iOS `.searchable` with `.navigationBarDrawer(.always)`. Web shipped tick 34 — `<input type="search">` in the Collection toolbar, 220ms debounce, matches hero / name / cardNumber / treatment / notes. Persists across tab switches; cleared on sign-out. |
| Designation badge per cell | ✅ | ✅ | ✅ | Corner overlay |
| Display modes: Grid / List / Wall | ✅ | ✅ | ⏳ M2 polish — Wall pending | Grid + List shipped on Android; Wall is M2 polish |
| Grid density picker (1/2/3 cols) | ✅ | ✅ | ✅ | DataStore-backed on Android via `CollectionPrefsStore` |
| Value summary | ✅ | ✅ | ✅ | `user_cards.estimated_value` |
| Value history chart | 🔮 | 🔮 | 🔮 | **Not built anywhere.** Both DESIGN.md §8.4 and ANDROID-DESIGN.md §8.4 describe it ("tap value summary → chart") but no implementation has landed on any platform. Was marked ✅ iOS in error; audit 2026-05-20 (tick 12) corrected. |
| Custom Rainbows | ✅ | ✅ | ✅ basic (3 dimensions) | Per-user filter goals; Supabase `user_custom_rainbows`. Web shipped tick 7 read-only display + tick 15 name editor + tick 16 full 7-dimension filter sub-pickers + Inspired Ink toggle + live progress preview. Android shipped read + create + delete + (tick 61) edit/rename via ✎ icon → CustomRainbowEditorSheet now opens in edit mode with state pre-filled. Android editor still surfaces only 3 of the 8 criterion dimensions (Heroes / Weapons / Treatments + Inspired Ink toggle) — Sets / Sub-sets / Releases land in a polish pass. |
| Per-hero Auto Rainbows | ✅ | ✅ read-only | ✅ read-only | Web synthesizes one row per owned hero × catalog, sorted by completion % desc (tick 8). Android shipped owned-treatments + per-hero label + chevron previously; tick 66 added total-treatments-from-catalog (so users see "5 of 15 treatments · 33% · 8 copies" not just "5 treatments") + completion-% sort. iOS-equivalent rendering. |
| My Shows (streamer-only) | ✅ | 🔮 | ⏳ M2 polish | iOS ships ShowsListView + ShowDetailView + show_cards table. Web has no streamer Shows surface (only Whatnot tile read on Purchase). Audit 2026-05-20 (tick 12) corrected the prior ✅ web claim. |
| Wall view (display mode + share) | ✅ | ✅ canvas-render | ⏳ M2 polish | Web shipped canvas-rendered PNG (download + clipboard + Web Share) tick 5. Lifted from streamer-only per DECISIONS.md #036. |
| Price Overlay (in Wall view) | ✅ | ✅ | ⏳ M2 polish | Per-designation defaults (For Sale ON / My price · For Trade ON / Market · Wanted ON / Market w/ WTB · Personal/Grails OFF) + source override dropdown. Live re-render on toggle (no image reload). |
| Personal Showcase (iTunes-style screensaver) | ✅ | 🚫 | 🚫 v1 §12 | Android: Cast SDK port deferred |
| AirPlay-Video for Showcase | ✅ | 🚫 | 🚫 v1 §12 | Android Cast SDK is the parallel |
| Public collection URL (`/u/{username}`) | n/a (toggle only) | ✅ | ⏳ M7 | Web renders; Android sets the toggle |

---

## 6. Purchase — acquire

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Upcoming Whatnot breaks | ✅ | ✅ | ✅ | Worker `boba-ebay-proxy /whatnot/upcoming` — Android deserialization fix shipped overnight 2026-05-20 |
| Find a Store (~330 indie + ~1,800 big-box) | ✅ MapKit | ✅ Leaflet | ⏳ M6 polish | Android needs Google Maps Compose + API key |
| Filters: radius, indie-only | ✅ | ✅ | ⏳ M6 polish | DropdownMenu on Android pending Maps |
| Tap break tile → external Whatnot | ✅ | ✅ | ✅ | Android shipped via `CustomTabsIntent` overnight |

---

## 7. Scanning (camera + OCR)

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Live single-card scan | ✅ | 🚫 | ⏳ M3 | CameraX + ML Kit Text Recognition v2 |
| Card-number regex match | ✅ | 🚫 | ⏳ M3 | Reuse iOS regex verbatim |
| Hero-name veto | ✅ | 🚫 | ⏳ M3 | Per DECISIONS.md #035 |
| Image-fingerprint matching | ✅ | 🚫 | 🔮 v2 | MediaPipe Image Embedder; parallel `feature-prints-android.bin` |
| Multi-card grid scan | ✅ | 🚫 | 🔮 v2 | OpenCV port |
| Scan queue / review surface | ✅ | n/a | ⏳ M3 | `BottomAppBar` action slot when active |
| Per-tab destination routing (Find/Decks/Collection) | ✅ | n/a | ⏳ M3 | Single `ScanCoordinator` |

Scan is iOS+Android only by design (DECISIONS.md #012). Web users see scan results when iOS/Android users share them.

---

## 8. Card detail surface

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Canonical 6-cell stats grid | ✅ | ✅ | ✅ | DECISIONS.md #029 |
| Cost + DBS (Plays only) | ✅ | ✅ | ✅ | Rendered below the canonical 6 |
| Pricing panels (Buy Now + Sold) | ✅ | ✅ | ✅ | DECISIONS.md #013 |
| eBay listings | ✅ | ✅ | ✅ | Worker proxy |
| eBay sold comps | ✅ | ✅ | ✅ | Worker proxy |
| Radish recent sales | ✅ | ✅ | ✅ | Worker proxy |
| COMC asking (separate, NOT in waterfall) | ✅ | ✅ | 🚫 | DECISIONS.md #034 — Android skipping per `feedback_comc_blocked_all_platforms` Turnstile gate |
| Add to Collection / Deck / Show | ✅ | ✅ | ✅ | Auth-required |
| Edit Designation | ✅ | ✅ | ✅ | Collection context — Android Edit Copy sheet shipped |
| Share (deep link + image) | ✅ | ✅ | ✅ | iOS share sheet · Web Share API · Android `Intent.ACTION_SEND` w/ FileProvider |
| Mod edit (mod-gated) | ✅ | ✅ | 🔮 v2 | Role check; Android admin/mod panel deferred to v2 |
| Other Versions browsing | ✅ | ✅ | ✅ | Same hero, different treatments |
| Hero zoom animation | ✅ compact only | ✅ via View Transitions API | ⏳ M1 polish | Android destination scaffolding done; `sharedBounds` zoom is polish |
| DBS explainer modal | ✅ | ✅ | ✅ | iOS sheet · web native `<dialog>` · Android `ModalBottomSheet` |
| Pricing refresh button | ✅ | ✅ | ✅ | All three platforms; web sends `fresh=1` to Worker for cache bypass |
| Tap-price hint | ✅ | n/a | ✅ | Mobile-only first-run hint |
| Card detail swipe nav (left/right) | ✅ | ✅ | 🔮 | iOS shipped v2.287 across Find / Decks / Collection. Web shipped in modal: ArrowLeft/Right keys + touch-swipe (>60px horizontal threshold + dx > 1.5×dy) wired to `navigateModal(±1)` in app.js. Audit 2026-05-20 corrected the prior "n/a" claim. |

---

## 9. Authentication + Profile

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Sign in with Apple | ✅ | ✅ | 🚫 §12 | iOS brand; Android uses Sign in with Google |
| Sign in with Google | 🔮 | 🔮 | ⏳ M7 | Credential Manager on Android |
| Email/password | ✅ | ✅ | ⏳ M7 | Same Supabase shape |
| Discord OAuth | ✅ | ✅ | ⏳ M7 | Auth Tab (Chrome 132+) on Android |
| Passkey support | 🔮 | 🔮 | ⏳ M7 | Free via Credential Manager bottom sheet |
| Biometric gate (sensitive actions) | ✅ Face ID | n/a | ⏳ M7 | `BiometricPrompt` on Android |
| Username (banned-words gated) | ✅ | ✅ | ⏳ M7 | Two-layer client + server check |
| Avatar upload | ✅ | ✅ | ⏳ M7 | Same `boba-avatar-upload` Worker |
| Public collection toggle | ✅ | ✅ | ⏳ M7 | Sharing flag |
| Generalized role request (mod / streamer) | ✅ | ✅ | ⏳ M7 | Same `request_role` RPC |
| Account deletion | ✅ | ✅ | ⏳ M7 | Same `boba-account-delete` Worker |
| Discord identity link (for trading) | ✅ | ✅ | ⏳ M7 | Same OAuth flow, different Custom Tab on Android |
| Notification toggle (match alerts) | ✅ UI only | ✅ UI only | ⏳ M7 | Match-alerts pipeline deferred per DECISIONS.md #039 |
| Trading toggle (Discord-gated) | ✅ UI only | ✅ UI only | ⏳ M7 | TRADE-DESIGN.md Phase 1 |
| Admin panel | ✅ | ✅ | 🔮 | Role-gated; defer to v2 |
| Mod panel | ✅ | ✅ | 🔮 | Role-gated; defer to v2 |
| Mod card edits (add / edit) | ✅ | ✅ | 🔮 | Same Worker `boba-mod-merge` |
| Sign-in method pill on Profile | ✅ | ✅ | ⏳ M7 | Visual indicator |

---

## 10. Universal Links / Deep Linking

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Universal Links / App Links (HTTPS) | ✅ | n/a | ⏳ M0 | `apple-app-site-association` + `assetlinks.json` coexist at `/.well-known/` |
| Custom scheme (`bobaplaybook://`) | ✅ | n/a | ⏳ M0 | Intent filter on Android |
| `card`, `search`, `scan`, `learn` routes | ✅ | ✅ | ⏳ M0 | Same URL shape across all platforms |
| `/u/{username}` (public collection) | n/a | ✅ | ⏳ M7 | Web renders the page; mobile deep-links to it |
| OAuth callback handling | ✅ via `routeIncoming` | ✅ | ⏳ M0 | `supabase.handleDeeplinks(intent)` on Android |

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
