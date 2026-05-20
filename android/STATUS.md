# BOBA Playbook Android — Current State

Snapshot after Round 3 iOS-parity push (2026-05-19).

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
| Compose BOM | 2026.05.00 + Material 3 1.5.0-alpha19 |
| Navigation Compose | 2.8.5 |
| Hilt | 2.59.2 |
| Coil 3 / Ktor 3.4 / supabase-kt 3.0.2 / CameraX 1.4 / ML Kit 16.0.1 / Firebase BOM 34.13 |
| minSdk 29 · targetSdk 36 · compileSdk 37 · JDK 21 |

## iOS parity status

### ✅ Find — full parity

- M3 SearchBar w/ ExpandedDockedSearchBar full-screen morph
- Featured carousels (Recently Added, By Weapon, Coaching Staff, Showcases)
- Live suggestions (card hits + token chips for weapon/treatment)
- **Full FilterSheet** w/ 8 dimensions + 9 sorts + 5 power-range presets
- **Filter button w/ active-count badge** in the SearchBar
- **Overflow menu**: columns picker, Card Showcases toggle, Quick Add toggle, walkthrough re-launcher
- Active filter chip strip below the bar (tap-to-remove)
- Showcase smart-match (typing "WoBA" auto-narrows)
- Quick Add mode pill below results
- Long-press card → Quick Add
- Container transform → card detail
- Shimmer skeletons on initial load
- BrowseFeaturedData (4 Featured Collections, 7 sports w/ athlete lists) ported from iOS

### ✅ Card Detail — canonical anatomy + actions

- LargeTopAppBar collapse + canonical 6-cell stats grid
- Power/Cost/DBS (Plays only), Ability/Bonus text
- Pricing panels (eBay active + sold + Radish via Worker; COMC NOT wired)
- Market estimate header w/ Radish-first waterfall
- Other Versions thumbnail row
- **Add menu** opens proper sheets:
  - Add to Collection → AddToCollectionSheet with designation, condition, grading, pricing, notes
  - Add to Deck → AddToDeckSheet with current draft + saved-deck list
  - Add to Show → Snackbar role hint
- Share via Intent.ACTION_SEND with deep link
- Container transform from grid

### ✅ Collection — parity

- Designation SegmentedButton w/ live counts (5 designations)
- Three display modes (Grid / List / Wall)
- Designation badge + quantity badge overlays on cells
- Value summary header
- **Filter button** (Tune icon) w/ BadgedBox count → same FilterSheet as Find
- Overflow Menu: Grid/List/Wall, **Rainbow Progress**, **My Shows**
- Tap card → **CollectionCardDetailScreen** (multi-copy + designation switcher per copy)
- Share intent (text-link, PNG export deferred)
- Sign-in / sign-out branching

### ✅ Decks — parity

- Compact: persistent DeckSummaryBar + ModalBottomSheet editor with rename / stats / sectioned list / remove / save
- Tablet: NavigableListDetailPaneScaffold 3-pane (saved / pool / inline editor)
- **Pool search bar** w/ tap-to-clear, filters into FindViewModel
- **Overflow Menu**: Templates, Saved decks, Import CSV, Export CSV, Deck rules, Legality, Scan into deck, Clear draft
- Long-press pool card → add to draft (canonical mobile add gesture)
- Scan→add routing via ScanCoordinator
- Hint banner ("Long-press to add") via DataStore-backed HintsStore
- Manage / Rules / Legality push destinations

### ✅ Learn — parity

- 5 categories × multiple articles
- Skill-level SegmentedButton scope (Rookie / Substitution / Playmaker)
- Glossary TooltipBox on highlighted terms via GlossaryRichText
- Tablet list-detail scaffold

### ✅ Purchase — parity (no maps yet)

- Whatnot tile list (live from boba-ebay-proxy)
- PullToRefreshBox
- **Find a Store** — full list from bobaplaybook.com/assets/data/stores.json
  - Filter by name/city/state
  - Indie-only chip
  - Tap → maps via geo: URI
- ~330 indie + 1800 big-box stores

### ✅ Profile — parity

- Avatar header + sign-in pill + username field
- Discord link (Custom Tabs to server invite stub; real OAuth deferred)
- Public collection toggle
- Match-alerts toggle (deferred per DECISIONS.md #039)
- Role request
- My Shows (streamer-gated, disabled)
- **Mod panel + Admin panel entries** (role-gated, disabled until M7)
- Terms / Privacy via Chrome Custom Tabs
- Sign out + Delete Account AlertDialog

### ✅ Cross-cutting — parity

- Container transforms via SharedTransitionLayout + cardSharedBounds
- App-scoped Snackbar via LocalAppSnackbar CompositionLocal
- Connectivity-aware BOBAOfflinePill (animated overlay)
- BOBAHintBanner DataStore-backed dismissals
- **Deep links** — both `https://bobaplaybook.com/...` (App Links) and `bobaplaybook://...` route via PendingDeepLink → BOBAApp dispatches to right NavController
- DeepLinkRoute.parse handles card/scan/search/learn/u segments

### ⏳ Deferred — known thin spots

- **Live data writes** — Supabase user_cards write path needs M7 to come online
- **Discord OAuth via Auth Tab / Custom Tabs** — full OAuth (not just server invite)
- **Find a Store Google Maps Compose** — Maps API key required
- **PNG export of Wall view** — GraphicsLayer.toImageBitmap() + FileProvider
- **Custom Rainbow editor** — sheet w/ 8 criterion dimensions
- **Practice executor engine port** — multi-session
- **Mod panel + Admin panel actual UIs** — role-gated stubs only
- **Articles corpus expansion** — Tournament + Strategy + Glossary content

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

Run on Pixel 9 Pro emulator (compact) or Pixel Tablet emulator (3-pane Decks, list-detail Learn).
