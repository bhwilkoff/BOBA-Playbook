# BOBA Playbook — Android

Native Kotlin + Jetpack Compose + Material 3 client. Companion to the iOS app (Swift + SwiftUI, `BOBAPlaybook.xcodeproj` at repo root) and the web app (vanilla HTML/CSS/JS, repo root).

## Read first

- [`ANDROID-DESIGN.md`](../ANDROID-DESIGN.md) — **binding** UI/IA design rules. Quote a rule before proposing any new screen.
- [`ANDROID-DEV.md`](../ANDROID-DEV.md) — engineering reference (stack, integration, conventions).
- [`SETUP.md`](./SETUP.md) — first-time install / Play Console / Firebase walkthrough.
- [`PARITY.md`](../PARITY.md) — what ships where across iOS / web / Android.

## Run locally

After Android Studio is installed and the project has been opened once (which generates the Gradle wrapper):

```sh
./gradlew :app:installDebug    # build + push to a connected device
./gradlew :app:assembleDebug   # debug APK at app/build/outputs/apk/debug/
./gradlew test                 # JVM unit tests
./gradlew connectedCheck       # instrumentation + UI tests on a device
```

## Module structure

```
app/                composition root + MainActivity + BOBAApp Composable
baselineprofile/    placeholder for M8 Macrobenchmark
core/
├── ui/             BobaTheme + design tokens + primitives (BOBACardCell, BOBAEmptyState, ...)
├── domain/         PURE Kotlin — Card model + use cases. No Android imports.
├── network/        Ktor client wrappers, CDN helpers, Supabase config, Worker config
└── data/           Repositories (CardRepository), catalog loader, Room (later)
```

Feature modules (`feature/find`, `feature/learn`, `feature/decks`, `feature/collection`, `feature/purchase`, `feature/scan`, `feature/profile`, `feature/carddetail`) land per the milestone plan in [`SCRATCHPAD.md`](../SCRATCHPAD.md).

## Asset sync

The card catalog + brand fonts are SOURCE-OF-TRUTH at the monorepo root (`assets/data/` and `BOBAPlaybook/Resources/Fonts/`). The Gradle `preBuild` task runs `android/scripts/sync_shared_assets.sh` automatically before every build, copying:

- `assets/data/cards-slim.json` → `app/src/main/assets/data/cards.json` (~13 MB)
- `assets/data/categories.json` → `app/src/main/assets/data/categories.json`
- `BOBAPlaybook/cards-head.json` → `app/src/main/assets/data/cards-head.json` (~462 KB)
- Brand fonts → `app/src/main/res/font/`

This is the Android equivalent of `pipeline/recognition/sync_mirror.sh` — single source, multiple consumers, drift caught at CI.

The 23 MB `search-index.json` is NOT bundled — Android generates its own index at first launch (same pattern as iOS).
