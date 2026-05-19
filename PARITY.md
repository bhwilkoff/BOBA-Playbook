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
| **Find** (explore) | ✅ | ✅ | ⏳ M1 | DESIGN.md §8.1 · WEB-DESIGN.md §14.1 · ANDROID-DESIGN.md §8.1 |
| **Learn** (understand) | ✅ | ✅ | ⏳ M5 | DESIGN.md §8.2 · WEB-DESIGN.md §14.2 · ANDROID-DESIGN.md §8.2 |
| **Decks** (build) | ✅ | ✅ | ⏳ M4 | DESIGN.md §8.3 · WEB-DESIGN.md §14.3 · ANDROID-DESIGN.md §8.3 |
| **Collection** (own) | ✅ | ✅ | ⏳ M2 | DESIGN.md §8.4 · WEB-DESIGN.md §14.4 · ANDROID-DESIGN.md §8.4 |
| **Purchase** (acquire) | ✅ | ✅ | ⏳ M6 | DESIGN.md §8.5 · WEB-DESIGN.md §14.5 · ANDROID-DESIGN.md §8.5 |

---

## 2. Find — explore

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Card grid with 17,974 cards | ✅ | ✅ | ⏳ M1 | `LazyVerticalGrid(GridCells.Adaptive)` |
| `SearchBar` (search-first IA) | ✅ | ✅ | ⏳ M1 | `Tab(role: .search)` / `<input type="search">` / `ExpandedFullScreenSearchBar` |
| Search tokens / chips | ✅ | ✅ | ⏳ M1 | `BOBAFilterToken` / URL params / `InputChip` |
| Filter rows (weapon, cost, hero, treatment) | ✅ | ✅ | ⏳ M1 | `FilterChip` flow row |
| Featured shelves (no-search state) | ✅ | ✅ | ⏳ M1 | `HorizontalMultiBrowseCarousel` on Android |
| Multi-select + bulk add | n/a | ✅ | 🔮 | Web-only today; mobile uses long-press add |
| Card detail push w/ hero zoom | ✅ | ✅ | ⏳ M1 | `.matchedTransitionSource` / View Transitions API / `sharedBounds` |
| Card-size picker (S/M/L density) | ✅ | ✅ | ⏳ M1 | Toolbar Menu → 1/2/3 cols |
| Profile entry (Find-only) | ✅ | ✅ | ⏳ M1 | TopAppBar leading icon — per `feedback_profile_only_on_find` |
| Saved Searches | ✅ | ✅ | ⏳ M1 | Featured shelf |
| Walkthrough on first visit | ✅ | 🚫 §11 | 🚫 §6.10 | Web + Android skip; replaced by EmptyState + tooltip |

---

## 3. Learn — understand

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Categories: Rules / Strategy / Collect / Glossary / Tournament | ✅ | ✅ | ⏳ M5 | Single-stream article rendering |
| Skill-level scope (Rookie / Sub / Playmaker) | ✅ | ✅ | ⏳ M5 | `SegmentedButton` scope inside article |
| Read/Watch toggle (when video exists) | ✅ | ✅ | ⏳ M5 | Same scope pattern |
| In-corpus search | ✅ | ✅ | ⏳ M5 | `.searchable` / search input / `SearchBar` |
| Glossary lookup (inline definitions) | ✅ | ✅ | ⏳ M5 | TooltipBox on Android |
| Browse-by-hero | n/a | n/a | n/a | Moved to Find per DESIGN.md §1.1 verb separation |

---

## 4. Decks — build

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Card pool (deck builder canvas) | ✅ | ✅ | ⏳ M4 | `LazyVerticalGrid` |
| Pool search + filter | ✅ | ✅ | ⏳ M4 | Format chips + weapon/cost/hero |
| Current deck summary | ✅ DeckSummaryPill | ✅ inline | ⏳ M4 DeckSummaryBar | Bottom-anchored |
| Deck editor sheet w/ zoom | ✅ | ⏳ desktop pattern | ⏳ M4 | `.fullScreenCover` / web side-by-side / `ModalBottomSheet` |
| Deck stats (counts + cost curve) | ✅ | ✅ | ⏳ M4 | Same canonical layout |
| Save deck (Supabase `decks` table) | ✅ | ✅ | ⏳ M4 | Auth-required write |
| Manage saved decks | ✅ | ✅ | ⏳ M4 | NavigationLink push within editor |
| Rules + Legality push surfaces | ✅ | ✅ | ⏳ M4 | Push as destinations (not stacked sheets) |
| Drag-and-drop add | ✅ iPad only | n/a | ⏳ M4 | `dragAndDropSource` + `dragAndDropTarget` |
| Long-press add on pool | ✅ | n/a | ⏳ M4 | Canonical mobile add |
| 3-column tablet layout (saved / pool / editor) | ✅ iPad | ⏳ desktop | ⏳ M8 | `NavigableListDetailPaneScaffold` 3-pane |
| Template gallery (empty editor) | ✅ | 🔮 | ⏳ M4 | Empty-state action |
| Walkthrough | ✅ | 🚫 | 🚫 | Same skip rule |

---

## 5. Collection — own

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Designation: Personal / Sale / Trade / Wanted / Grails | ✅ | ✅ | ⏳ M2 | `SegmentedButton` |
| Designation badge per cell | ✅ | ✅ | ⏳ M2 | Corner overlay |
| Display modes: Grid / List / Wall | ✅ | ✅ | ⏳ M2 | Toolbar Menu |
| Grid density picker (1/2/3 cols) | ✅ | ✅ | ⏳ M2 | DataStore-backed |
| Value summary | ✅ | ✅ | ⏳ M2 | `user_cards.estimated_value` |
| Value history chart | ✅ | 🔮 | ⏳ M2 | Push destination |
| Custom Rainbows | ✅ | 🔮 | ⏳ M2 | Per-user filter goals; Supabase `user_custom_rainbows` |
| Per-hero Auto Rainbows | ✅ | 🔮 | ⏳ M2 | Same RainbowDetailView pattern |
| My Shows (streamer-only) | ✅ | ✅ | ⏳ M2 | Push destination, role-gated |
| Wall view (display mode + share) | ✅ | ⏳ M-future | ⏳ M2 | Lifted from streamer-only per DECISIONS.md #036 |
| Price Overlay (in Wall view) | ✅ | ⏳ M-future | ⏳ M2 | Toggle on Wall toolbar |
| Personal Showcase (iTunes-style screensaver) | ✅ | 🚫 | 🚫 v1 §12 | Android: Cast SDK port deferred |
| AirPlay-Video for Showcase | ✅ | 🚫 | 🚫 v1 §12 | Android Cast SDK is the parallel |
| Public collection URL (`/u/{username}`) | n/a (toggle only) | ✅ | ⏳ M7 | Web renders; Android sets the toggle |

---

## 6. Purchase — acquire

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| Upcoming Whatnot breaks | ✅ | ✅ | ⏳ M6 | Worker `boba-ebay-proxy /whatnot/upcoming` |
| Find a Store (~330 indie + ~1,800 big-box) | ✅ MapKit | ✅ Leaflet | ⏳ M6 Google Maps Compose | Same data source |
| Filters: radius, indie-only | ✅ | ✅ | ⏳ M6 | DropdownMenu on Android |
| Tap break tile → external Whatnot | ✅ | ✅ | ⏳ M6 | `CustomTabsIntent` on Android |

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
| Canonical 6-cell stats grid | ✅ | ✅ | ⏳ M1 | DECISIONS.md #029 |
| Cost + DBS (Plays only) | ✅ | ✅ | ⏳ M1 | Rendered below the canonical 6 |
| Pricing panels (Buy Now + Sold) | ✅ | ✅ | ⏳ M3 | DECISIONS.md #013 |
| eBay listings | ✅ | ✅ | ⏳ M3 | Worker proxy |
| eBay sold comps | ✅ | ✅ | ⏳ M3 | Worker proxy |
| Radish recent sales | ✅ | ✅ | ⏳ M3 | Worker proxy |
| COMC asking (separate, NOT in waterfall) | ✅ | ✅ | ⏳ M3 | DECISIONS.md #034 |
| Add to Collection / Deck / Show | ✅ | ✅ | ⏳ M1-M4 | Auth-required |
| Edit Designation | ✅ | ✅ | ⏳ M2 | Collection context |
| Share (deep link + image) | ✅ | ✅ | ⏳ M7 | `Intent.ACTION_SEND` on Android |
| Mod edit (mod-gated) | ✅ | ✅ | ⏳ M7 | Role check |
| Other Versions browsing | ✅ | ✅ | ⏳ M1 | Same hero, different treatments |
| Hero zoom animation | ✅ compact only | ✅ via View Transitions API | ⏳ M1 compact only | Compact-only per §6.6.2 each platform |

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

## 14. Easter eggs + extras

| Feature | iOS | Web | Android | Notes |
|---|---|---|---|---|
| House of BoBA (card-tower playground) | ✅ | n/a | 🚫 | iOS RealityKit-specific; ANDROID-DESIGN.md §12 marks 3D out-of-scope for v1 |
| Hero Shot (3D card video) | ✅ | n/a | 🚫 v1 | Filament port a separate effort |

---

## 15. Web-specific affordances

These are web-only by design; mobile platforms handle the same need natively.

| Feature | Web | Why |
|---|---|---|
| URL params reflect filter state | ✅ | Shareable deep links; not relevant on mobile |
| Public collection page (`/u/{username}`) renderer | ✅ | Web is the only platform that renders for unauthenticated viewers |
| Web Share API + clipboard fallback | ✅ | Native iOS/Android handle this via system share sheet |
| View Transitions API (cross-view fade + hero zoom) | ✅ | iOS uses `.navigationTransition(.zoom)`; Android uses `sharedBounds` |
| Container queries on `.card-item` | ✅ | iOS/Android use compose-time size class branching |

---

## 16. iOS-specific affordances

These are iOS-only by design; other platforms handle the same need with platform-native equivalents.

| Feature | iOS | Why |
|---|---|---|
| Multi-step anchored walkthroughs | ✅ | Web rejects per §11; Android rejects per §6.10 — replaced with empty states + tooltips |
| Liquid Glass tab bar / toolbar | ✅ | Web uses `backdrop-filter`; Android uses Material 3 tonal elevation |
| Hero Shot 3D RealityKit rendering | ✅ | Web / Android out-of-scope for v1 |
| House of BoBA RealityKit-based playground | ✅ | Out-of-scope on other platforms |
| AirPlay-Video for Personal Showcase | ✅ | Android Cast SDK is the parallel — deferred |
| Live Activities / Dynamic Island | 🔮 | Android has no exact equivalent; accept asymmetry |
| `.matchedTransitionSource` + `.navigationTransition(.zoom)` | ✅ | Web uses View Transitions API; Android uses `sharedBounds` |

---

## 17. Android-specific affordances

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

## 18. Backend services (shared)

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

When a feature ships on one platform but is meaningfully different elsewhere, **add an entry to §15 / §16 / §17** explaining why.

When a platform explicitly rejects a feature (e.g., walkthroughs on web + Android), **add an "Out of scope" row in the relevant design doc's §12** and link from this table.
