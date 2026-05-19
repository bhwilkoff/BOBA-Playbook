# BOBA Playbook Android — Current State

Snapshot at end of M0–M8 rapid-pace session (2026-05-19).

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
| Navigation 3 | 1.0.1 (deps wired) |
| Hilt | 2.59.2 |
| Coil 3 / Ktor 3.4 / supabase-kt 3.0.2 / CameraX 1.4 / ML Kit 16.0.1 / Firebase BOM 34.13 |
| minSdk 29 · targetSdk 36 · compileSdk 37 · JDK 21 |

## Screens shipped

| Screen | Status | Polish queued |
|---|---|---|
| Find | ✅ working | M3 SearchBar morph, featured carousel, container transform |
| Card detail | ✅ working | sharedBounds zoom, pricing panels (M3) |
| Collection | ✅ shell | Wire CollectionRepository to Supabase (depends on M7 auth state) |
| Scan | ✅ working — CameraX + ML Kit OCR live | Fingerprint matching, grid scan (v2) |
| Decks | ✅ shell | Deck data layer, editor sheet, tablet 3-pane |
| Learn | ✅ shell | Article corpus port (content work) |
| Purchase | ✅ shell | Whatnot Worker call + Maps Compose |
| Profile sheet | ✅ Sign in with Google works | Discord OAuth, full Profile sections, Tink token storage |
| Practice | ⏳ admin-gated placeholder | Multi-session engine port post-v1 |

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

Or in Android Studio: ▶ Run on a Pixel 9 Pro (API 36) emulator.

## Pending Ben actions

- **First device-test** (this is what's next — open Studio, sync, run)
- Back up `~/.android/boba-upload.jks` to a password manager
- (Future) Internal Testing AAB upload — see `PLAY_STORE_CHECKLIST.md`

## Pending Claude follow-ups (post-test)

Listed in priority of impact:
1. Whatever Ben reports broken during smoke test
2. M2 polish — wire CollectionRepository to live Supabase
3. M6 polish — Whatnot tile list from existing Worker
4. M5 polish — port Learn article corpus from iOS
5. M7 polish — Discord OAuth + full Profile + Tink token storage
6. M4 polish — Deck data layer + editor sheet
7. M3 polish — pricing panels in card detail
8. M5.5 — Practice engine port (multi-session)
9. M8 — first AAB upload to Internal Testing
