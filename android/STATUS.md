# BOBA Playbook Android — Current State

Snapshot after first-class native M3 overhaul (2026-05-19).

For the full picture (architectural patterns, deferred follow-ups, credential index), Claude reads the **`reference_android_v1_status.md`** memory file. This doc is the human-readable quick-reference.

---

## Build status

✅ `./gradlew :app:assembleDebug` — **BUILD SUCCESSFUL**
✅ Zero deprecation warnings
✅ `:core:domain:test` — 6 Card tests green

## Stack

| | |
|---|---|
| Android Studio | Panda 4 Patch 1 |
| AGP | 9.2.1 |
| Kotlin | 2.3.21 / KSP 2.3.8 |
| Compose BOM | 2026.05.00 + Material 3 1.5.0-alpha19 (Expressive APIs unlocked) |
| Navigation Compose | 2.8.5 + Navigation 3 1.0.1 (deps wired) |
| Hilt | 2.59.2 |
| Coil 3 / Ktor 3.4 / supabase-kt 3.0.2 / CameraX 1.4 / ML Kit 16.0.1 / Firebase BOM 34.13 |
| minSdk 29 · targetSdk 36 · compileSdk 37 · JDK 21 |

## What's wired (post-overhaul)

| Surface | Status | Notes |
|---|---|---|
| **Find** | ✅ M3 SearchBar morph | Featured carousels (Recently Added / Heroes by Weapon / Coaching Staff), live suggestions w/ token chips + card hits, InputChip filter row, shimmer skeletons on initial load, container transform into detail |
| **Card detail** | ✅ canonical anatomy | LargeTopAppBar collapse, 6-cell stats, Power/Cost/DBS, Ability/Bonus text, pricing panels (eBay + Radish via Worker; COMC NOT wired — blocked all platforms), Other Versions row, real Add menu w/ Snackbar feedback, Share via Intent.ACTION_SEND, container transform from grid |
| **Collection** | ✅ full anatomy | Designation SegmentedButton w/ live counts, three display modes (Grid / List / Wall), designation + quantity badge overlays, value summary header, signed-in vs signed-out branches, Share text intent |
| **Decks (compact)** | ✅ summary bar + sheet editor | Persistent DeckSummaryBar w/ live stats + "Legal" chip, full-screen ModalBottomSheet editor with rename / stats row / sectioned card list / remove / save, long-press add, scan→add routing via ScanCoordinator, Manage/Rules/Legality push destinations, first-run hint banner |
| **Decks (tablet)** | ✅ 3-pane | NavigableListDetailPaneScaffold w/ saved-decks sidebar (placeholder until M7 Supabase) + pool + always-visible editor pane. Inline editor reuses the same content as the sheet editor. |
| **Learn (compact)** | ✅ corpus + skill scope | 5 categories × multiple articles each, skill-level SegmentedButton scope per article, glossary tooltips via TooltipBox on highlighted terms |
| **Learn (tablet)** | ✅ list-detail | NavigableListDetailPaneScaffold w/ categories pane + articles + body |
| **Purchase** | ✅ Whatnot live | Worker-backed Whatnot tile list with thumb + host avatar + viewer count, PullToRefreshBox, tap-through to Whatnot. Find a Store still a polished placeholder (waiting on Maps API key + store dataset) |
| **Profile** | ✅ full sections | Header w/ avatar + sign-in pill, username field, Discord link, public collection toggle, match-alerts toggle (deferred), role request, Terms/Privacy via Chrome Custom Tabs, sign out + account delete AlertDialog |
| **Scan** | ✅ working | CameraX + ML Kit live OCR. Routes match by ScanCoordinator: Find→detail, Decks→deck add, Collection→detail |
| **Practice** | ⏳ admin-gated placeholder | Multi-session engine port post-v1 |

## Native M3 components in production

`SearchBar` w/ `ExpandedDockedSearchBar` morph · `SharedTransitionLayout` + `sharedBounds` container transforms · `NavigationSuiteScaffold` (NavigationBar/Rail adaptive) · `NavigableListDetailPaneScaffold` on Learn + Decks (tablet) · `ModalBottomSheet` (editor + profile) · `LargeTopAppBar` w/ `exitUntilCollapsedScrollBehavior` · `SingleChoiceSegmentedButtonRow` (designations, skill levels) · `FilterChip` / `InputChip` / `SuggestionChip` / `AssistChip` · `DropdownMenu` (display modes, overflow actions) · `PullToRefreshBox` · `TooltipBox` + `PlainTooltip` (Glossary) · `Snackbar` + app-scoped `SnackbarHost` via `LocalAppSnackbar` · `AlertDialog` (delete confirm) · `HorizontalDivider` / `VerticalDivider` · `LinearProgressIndicator` / `CircularProgressIndicator` · Predictive back via NavHost.

## Custom primitives in `:core:ui`

`BOBACardCell` · `BOBACardSkeleton` (shimmer) · `BOBASectionHeader` · `BOBAEmptyState` · `BOBABanner` · `BOBAHintBanner` (cyan accent + dismissible) · `BOBAOfflinePill` · `BOBASignInPrompt` · `BOBAWordmark` · `BOBAStatsGrid` · `BOBAPriceTile` · `LocalSharedTransition` / `LocalNavAnimatedVisibilityScope` / `LocalAppSnackbar` CompositionLocals · `cardSharedBounds(bobaId)` Modifier · `isCompactWidth() / isMediumOrExpandedWidth()` adaptive helpers

## Credentials all wired

✅ Upload keystore (`~/.android/boba-upload.jks`) + assetlinks.json fingerprints
✅ Play Console app `com.bobaplaybook.app`
✅ Firebase project `boba-playbook-7f292` + `google-services.json` committed
✅ Google OAuth (Web + Android clients)
✅ Supabase URL + publishable key in `SupabaseConfig.kt`

## How to build / run

```sh
cd /Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew :app:assembleDebug --no-configuration-cache
```

Or in Android Studio: ▶ Run on a Pixel 9 Pro (API 36) emulator or Pixel Tablet (for 3-pane Decks / list-detail Learn).

## Pending follow-ups (post-test)

Listed in priority of impact:
1. Whatever Ben reports broken during smoke test
2. **M7 polish** — wire CollectionRepository to live Supabase user_cards (RLS auto-scopes by auth.uid)
3. **M7 polish** — Discord OAuth via Auth Tab / Custom Tabs (today: sign-in path uses Google; Discord link button opens server invite as a stand-in)
4. **M6 polish** — Find a Store Google Maps Compose (waiting on Maps API key + indie-store Worker)
5. **M7 polish** — Tink-encrypted token storage (supabase-kt's default DataStore SessionManager today)
6. **M5 polish** — clickable-span TooltipBox on every glossary term (today's RichText shows for the first term only)
7. **Wall PNG export** — GraphicsLayer.toImageBitmap() + FileProvider + cache cleanup (today: text-link share intent)
8. **M5.5** — Practice engine port (multi-session)
9. **M8** — first AAB upload to Internal Testing
