# BOBA Playbook — Android Engineering Reference

> **Binding.** Every Android-specific implementation decision must trace to a rule here. Companion to [`CLAUDE.md`](./CLAUDE.md) (project overview), [`DESIGN.md`](./DESIGN.md) (iOS design), [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md) (Android design — binding), [`WEB-DESIGN.md`](./WEB-DESIGN.md) (web design), [`DECISIONS.md`](./DECISIONS.md), [`PARITY.md`](./PARITY.md).
>
> Ratified 2026-05-19 from four parallel research agents (stack, design mapping, integration, skills). Living document — refresh quarterly as AndroidX / Compose / Material 3 ship updates.

---

## 1. Why a separate Android codebase (and not KMP / Compose Multiplatform / Flutter / RN)

**Decision: Kotlin + Jetpack Compose, native single-platform codebase.** (DECISIONS.md #041.)

The iOS app is already written in Swift 6 + SwiftUI with `@Observable` + SwiftData. Migrating its business logic into a Kotlin "common" module to share with Android means **rewriting iOS at the same time** — and the iOS app is shipping at v2.282+, not a rewrite candidate. KMP works best when you start both platforms together. BOBA didn't.

| Alternative | Why considered | Why rejected for BOBA |
|---|---|---|
| **Kotlin Multiplatform** (KMP — shared logic, native UI per platform) | Mature; Netflix / Cash App / Google Workspace use it in prod. Adoption jumped 7% → 23% from 2024 to 2025. | iOS is Swift-native; can't retrofit without rewriting iOS. |
| **Compose Multiplatform** (CMP — shared UI too) | Stable on iOS since CMP 1.8.0 (May 2025). Performance near-native. | iOS DESIGN.md depends on Liquid Glass, `Tab(role: .search)`, `.navigationTransition(.zoom)` — CMP can't render those natively. Kills CMP. |
| **Flutter** | Single codebase. | Dart runtime, custom renderer, can't share types with Swift iOS app, can't render Material 3 Expressive natively. Strictly worse than native Android for this monorepo. |
| **React Native (new arch, Fabric)** | Large JS ecosystem. | JS runtime overhead, bridge for every native feature (ML Kit, CameraX, Play Integrity, biometrics). Strictly worse for an Android-only codebase. |
| **Native Android Views (XML)** | Mature. | Compose has been Google's recommended UI toolkit since 2021; all new M3 Expressive components ship Compose-first. No reason to start a new app on Views in 2026. |

**KMP as a future option:** If Web ever wants typed data models or a Desktop companion arrives, KMP is the upgrade path — extract the domain layer (no UI, no platform APIs) into a `:shared` Kotlin module. **Keep that door open by structuring the Android app's domain layer as pure-Kotlin from day one, with no Android imports outside `:app` and `:data` modules.**

---

## 2. Stack snapshot

| Layer | Choice | Why |
|---|---|---|
| Language | **Kotlin 2.2+** | Modern, official, Compose-first |
| UI | **Jetpack Compose** + **Material 3 / Material 3 Expressive** | Native, declarative, SwiftUI-analog |
| `minSdk` | **29 (Android 10)** | >95% device coverage in 2026 |
| `targetSdk` | **36 (Android 16)** at launch; bump to **37 (Android 17)** once stable Q2 2026 + Play deadlines force it | Required for Play Store; ships modern behaviors as contract |
| Build | **Gradle 8.x + Kotlin DSL + Version Catalogs** | Industry default; type-safe deps |
| Plugin: AGP | **9.0+** | Ships built-in Kotlin support |
| Codegen | **KSP 2.x** (NOT KAPT) | Up to 2× faster; KSP2 is default since Kotlin 2.0 |
| DI | **Hilt** (NOT Koin) | Compile-time graph validation; broken DI fails the build |
| Navigation | **Navigation Compose 2.8+** with type-safe routes (Kotlin Serialization-backed) | Compile-time route safety; auto deep-link wiring |
| Persistence | **Room 3.x** (structured) + **DataStore Proto / Preferences** (settings) + **Tink-encrypted DataStore** (secrets) | Coroutines-native; SwiftData analog; EncryptedSharedPreferences is deprecated |
| Networking | **Ktor Client 3.x with OkHttp engine** | Kotlin-native; coroutines / Flow / WebSockets first-class; shares connection pool with Coil 3 |
| Image loading | **Coil 3** | Compose-native; multiplatform; smaller method count than Glide |
| Concurrency | **Kotlin Coroutines + Flow** (`StateFlow` for screen state, `SharedFlow` / `Channel` for events) | Structured concurrency; Swift async/await analog |
| Camera | **CameraX 1.5+** | Modern Camera2 wrapper; lifecycle-aware |
| OCR | **ML Kit Text Recognition v2 (Latin, bundled)** | iOS Vision `VNRecognizeTextRequest` analog |
| Auth | **Credential Manager** + **Sign in with Google** + **Auth Tab / Custom Tabs** (Discord OAuth) | Unified API; passkey-ready; canonical Android auth |
| Notifications | **Firebase Cloud Messaging (FCM)** | Android's APNs equivalent |
| Security | **Android Keystore + Tink-encrypted DataStore** for secrets; **BiometricPrompt** for sensitive gates; **Play Integrity API** for backend verification (when threat model demands) | Modern post-EncryptedSharedPreferences stack |
| Backend (shared) | **Supabase** (auth + RLS data) via **supabase-kt** + **Cloudflare R2 CDN** + **Cloudflare Workers** | All inherited from iOS / web — same backend, second native client |
| Testing | **kotlin.test** / **JUnit 5** + **MockK** + **Turbine** (Flow) + **Compose UI Test (Robolectric)** + **Roborazzi** (screenshot) + **Macrobenchmark** | Modern, Compose-aware |
| Performance | **R8 + Baseline Profiles + Macrobenchmark + JankStats** | 20-40% cold-start improvement, mandatory for the 17K-card grid |
| Distribution | **Google Play Console** (Internal → Closed → Open → Production) + **Play App Signing** (mandatory) | Standard Android distribution |
| Subscription billing | **Google Play Billing Library 7.x** (when BOBA Pro ships) | Standard 3.1.1-analog path |

---

## 3. Project structure

Modular from day one — even if v0 ships as a single module, set up the bones:

```
android/
├── app/                         # composition root, manifest, R8 config, Application class
├── baselineprofile/             # Macrobenchmark module producing baseline-prof.txt
├── core/
│   ├── ui/                      # design system: BobaTheme, typography, M3 ColorScheme, primitives (BOBACardCell, BOBASectionRow, etc.)
│   ├── data/                    # Room DAOs, Repository implementations, sync layer
│   ├── domain/                  # PURE Kotlin (no Android imports!) — Card, Deck models, use cases. Seed for future KMP :shared
│   └── network/                 # Ktor client wrappers — SupabaseRestClient, CloudflareWorkerClient, CDN helpers
├── feature/
│   ├── find/                    # explore — Find tab Composables + ViewModels
│   ├── learn/                   # understand
│   ├── decks/                   # build
│   ├── collection/              # own
│   ├── purchase/                # acquire
│   ├── scan/                    # cross-cutting capability (CameraX + ML Kit)
│   ├── profile/                 # auth + sign-in + settings (Find-only entry per feedback_profile_only_on_find)
│   └── carddetail/              # canonical card detail screen — three entry surfaces share it
└── build-logic/                 # convention plugins for shared Gradle config
```

**Why modular:**
- Compose stability inference works better with smaller modules.
- R8 dead-code elimination has more to chew on.
- Build cache is per-module — faster incremental builds.
- The iOS app already separates `Models/`, `Views/`, `Networking/`, `Store/`, `Components/` — Android modules make that **physical** instead of conventional.

**Same monorepo as iOS + web.** Android lives under `/android/`. Shared assets (`assets/data/cards.json`, fonts, card-back image) get bundled into the Android target during the Gradle copy-task step described in §9. Worker code under `/workers/` is shared with iOS + web verbatim.

---

## 4. Architecture: UDF + State Hoisting

Single-Activity + Compose Navigation. One `MainActivity`, hosts a `NavHost`, no Fragments. Industry standard for Compose apps since 2021.

**State pattern (UDF / unidirectional data flow):**

```
Screen Composable  ←─ injects ViewModel (top level only)
       │
       │ collectAsStateWithLifecycle(uiState)
       ↓
Stateful screen body  →  emits Events (sealed interface) up
       ↓                          ↑
Stateless child composables       │
   (state passed down,            │
    callbacks passed down)        │
                                  │
                            ViewModel reduces event → new UiState
```

**Binding rules:**
- **One immutable `data class UiState`** per screen. Single source of truth. UI reacts only to meaningful changes.
- **Events modeled as sealed interface.** `sealed interface FindEvent { data class QueryChanged(val q: String): FindEvent; data object ScanClicked: FindEvent }`. Kotlin compiler enforces exhaustive handling — same protection Swift gives you with enum + switch.
- **ViewModel is injected at the screen Composable only.** Never pass `ViewModel` instances into child Composables. Pass `uiState` + a single `onEvent: (FindEvent) -> Unit` lambda instead.
- **State hoisting:** any state two siblings share is hoisted to the nearest common ancestor.
- **`remember` / `rememberSaveable`:** transient UI state lives in the composable. `rememberSaveable` for state that survives configuration change + process death. Anything semantic lives in the ViewModel.

**Mapping to iOS:**

| iOS (Swift 6 + SwiftUI) | Android (Kotlin + Compose) |
|---|---|
| `@Observable class CardStore` | `class FindViewModel : ViewModel()` with `StateFlow<FindUiState>` |
| `@Environment(\.cardStore) var cardStore` | `hiltViewModel<FindViewModel>()` at the screen Composable |
| `@State private var query` | `var query by remember { mutableStateOf("") }` |
| `@State` that survives kill | `rememberSaveable { mutableStateOf(...) }` + `SavedStateHandle` in ViewModel |
| Swift `enum` events | `sealed interface` events |
| `Task { ... }` async | `viewModelScope.launch { ... }` coroutine |
| `.onAppear { ... }` | `LaunchedEffect(Unit) { ... }` |
| `.onDisappear { ... }` | `DisposableEffect(Unit) { onDispose { ... } }` |
| `.task { ... }` | `LaunchedEffect(Unit) { ... }` (auto-cancels on leave) |
| `.task(id:)` | `LaunchedEffect(id) { ... }` |
| `AsyncStream` | `Flow<T>` (cold) or `SharedFlow<T>` (hot) |
| `@Observable` published state | `StateFlow<UiState>` (hot, replays latest) |
| One-shot events (navigation, toast) | `Channel<Event>().receiveAsFlow()` or `SharedFlow(replay=0)` |

**Process death + state restoration:**
- Android can kill your app's process at any time when backgrounded — no iOS counterpart.
- **`rememberSaveable { mutableStateOf(...) }`** survives configuration change + process death.
- **`SavedStateHandle` in ViewModel** survives process death. Inject via `@HiltViewModel constructor(savedStateHandle: SavedStateHandle, ...)`.
- **Save the intent, not the data.** Save the query string / filter / selected card ID; re-fetch the actual data from Room/network on restore. Don't try to serialize 17k cards into the Bundle — that's a 1 MB limit you'll hit.

---

## 5. Networking + backend integration

### 5.1 Supabase via supabase-kt

The community-maintained Kotlin Multiplatform Supabase client. Maintained by Jan Tennert + contributors; Supabase docs link to it from the Android Quickstart.

**Modules to install for BOBA:**

```
io.github.jan-tennert.supabase:postgrest-kt      # RLS-aware queries
io.github.jan-tennert.supabase:auth-kt           # email/pw + OAuth + ID-token sign-in
io.github.jan-tennert.supabase:realtime-kt       # future: match-alerts (TRADE-DESIGN.md Phase 7)
io.github.jan-tennert.supabase:compose-auth      # native Google one-tap helper
```

**Do NOT install** `storage-kt` — BOBA uses R2, not Supabase Storage (DECISIONS.md #008, #042).

**Ktor engine: OkHttp on Android** (`io.ktor:ktor-client-okhttp`). Supports HTTP/2 + WebSockets. **Share the same `OkHttpClient` instance with Coil 3** — one connection pool, one DNS cache, one TLS session resumption cache. ~30% memory win on cold start.

### 5.2 Auth flows

**Email/password** — identical to iOS shape. `supabase.auth.signInWith(Email) { ... }`.

**Discord OAuth** — uses **Chrome Custom Tabs / Auth Tab (Chrome 132+)**:
1. Register `bobaplaybook://oauth/callback` as a Discord redirect.
2. AndroidManifest gets an `<intent-filter>` on `MainActivity` (or a dedicated `AuthCallbackActivity`) for `bobaplaybook://oauth`.
3. In `Activity.onCreate(...)` and `onNewIntent(...)`, call `supabase.handleDeeplinks(intent)`.
4. Trigger from Compose: `supabase.auth.signInWith(Discord) { scopes.add("identify"); scopes.add("email") }`.

**PKCE is mandatory** for native apps using custom schemes; supabase-kt uses it by default.

**Sign in with Google (primary on Android, parallel to iOS's Sign in with Apple):**

```kotlin
val credentialManager = CredentialManager.create(context)
val request = GetCredentialRequest.Builder()
  .addCredentialOption(
    GetGoogleIdOption.Builder()
      .setServerClientId(BuildConfig.GOOGLE_CLIENT_ID)
      .build()
  )
  .build()
val credential = credentialManager.getCredential(activity, request)
// then pass to supabase
supabase.auth.signInWith(IdToken) {
  idToken = (credential.credential as GoogleIdTokenCredential).idToken
  provider = Google
}
```

Credential Manager renders the native one-tap bottom sheet — better UX than an in-browser OAuth roundtrip.

### 5.3 JWT refresh — the v2.279 lesson, translated

Same gotcha as iOS. supabase-kt auto-refreshes inside its own HTTP path; **Cloudflare Worker calls + non-SDK Supabase endpoints bypass it.**

**Mitigation:**
- Add a `SupabaseClient.refreshIfNeeded()` extension that checks `auth.currentSessionOrNull()?.expiresAt` against `Clock.System.now()` + 60s, and calls `auth.refreshCurrentSession()` if needed.
- Wrap this in an OkHttp `Interceptor` installed on the **Worker-calling** OkHttp client. Every Worker / Storage / Edge Function call thus gets refresh-aware for free.

```kotlin
class SupabaseAuthInterceptor(private val supabase: SupabaseClient) : Interceptor {
  override fun intercept(chain: Interceptor.Chain): Response {
    runBlocking { supabase.refreshIfNeeded() }
    val token = supabase.auth.currentAccessTokenOrNull() ?: return chain.proceed(chain.request())
    val request = chain.request().newBuilder()
      .header("Authorization", "Bearer $token")
      .build()
    return chain.proceed(request)
  }
}
```

This is the Android analog of [feedback_refresh_jwt_for_workers_and_storage.md](file://./).

### 5.4 Cloudflare Workers

All BOBA Workers accept `Authorization: Bearer {jwt}` + JSON / bytes — **transport-agnostic. Zero server-side changes needed for Android.**

| Worker | Auth | Android wiring |
|---|---|---|
| `boba-ebay-proxy` (eBay + Whatnot) | None | Direct OkHttp/Ktor call |
| `boba-comc-proxy` | None | Same; soft-fail on `challenged: true` (DECISIONS.md #034) |
| `boba-account-delete` | Bearer JWT | Refresh JWT, POST `/account/delete` |
| `boba-avatar-upload` | Bearer JWT | Refresh JWT, multipart POST |
| `boba-mod-merge` | Bearer JWT + role check | Refresh JWT (mod-only Android users hit the same endpoint) |

### 5.5 Image loading: Coil 3

Configure at Application start (parity with iOS `URLCache` setup):

```kotlin
class BOBAApplication : Application(), SingletonImageLoader.Factory {
  override fun newImageLoader(context: PlatformContext): ImageLoader =
    ImageLoader.Builder(context)
      .memoryCache {
        MemoryCache.Builder()
          .maxSizeBytes(60L * 1024 * 1024)   // 60 MB — matches iOS NSCache
          .build()
      }
      .diskCache {
        DiskCache.Builder()
          .directory(context.cacheDir.resolve("image_cache"))
          .maxSizeBytes(500L * 1024 * 1024)  // 500 MB — matches iOS URLCache
          .build()
      }
      .callFactory(sharedOkHttpClient)       // share with supabase-kt
      .crossfade(true)
      .build()
}
```

**WebP support** — native on Android since API 17 (lossy) / API 18 (lossless + alpha + animated). BOBA's R2 catalog is lossy WebP; zero work needed.

**Rounded corners** — **never pre-bake for 2D Compose UI.** Use `Modifier.clip(RoundedCornerShape(8.dp))` on the `AsyncImage`. Coil's docs explicitly recommend this over `RoundedCornersTransformation` because clip uses the GPU compositor; the transformation API pre-bakes pixels and wastes cache space. (The iOS v2.281 pre-bake fix is a 3D-rendering / RealityKit issue; Compose has no equivalent problem.)

**Two-tier loading (thumb-first then full-res), parity with DECISIONS.md #024:**

```kotlin
AsyncImage(
  model = ImageRequest.Builder(LocalContext.current)
    .data(card.fullUrl)
    .placeholderMemoryCacheKey(card.thumbUrl)  // reuse thumb bitmap as placeholder
    .crossfade(150)
    .build(),
  contentDescription = card.heroName,
  modifier = Modifier.aspectRatio(5f / 7f).clip(RoundedCornerShape(8.dp))
)
```

When the user taps a grid cell, the detail's `AsyncImage` is built with `placeholderMemoryCacheKey` pointing at the same URL the grid cell loaded. Coil hits memory cache (zero IO), renders the thumb instantly, then crossfades full-res. **Zero spinner.**

**CDN helpers — single source of truth:** ship a `CDN.kt` module with `thumbUrl(imageFile)` + `fullUrl(imageFile)`. Never hardcode R2 URLs (CLAUDE.md "One Image per Card").

### 5.6 Persistence: Room + DataStore

| Use case | iOS analog | Android pick |
|---|---|---|
| Structured (UserCard, Deck, DeckCard, Show, CustomRainbow) | SwiftData | **Room 3.x** with `Flow<List<T>>` queries |
| Preferences (column counts, hint dismissals, walkthrough state) | UserDefaults / @AppStorage | **DataStore (Preferences or Proto)** — coroutines-native |
| Secrets (Supabase JWT, refresh token) | Keychain | **Android Keystore + Tink-encrypted DataStore** |

**Why Room over SQLDelight:**
- Room 3.0+ has full Compose `Flow<T>` integration — write a `@Query` returning `Flow<List<UserCard>>` and `collectAsStateWithLifecycle` it in the screen.
- Type-safe KSP-based codegen catches schema errors at build time.
- Migration system (`Migration` classes) is well-trodden.

**Schema mirrors iOS SwiftData models** — `UserCard`, `Deck`, `DeckCard`, `Show`, `CustomRainbow`. Remote source of truth is Supabase (DECISIONS.md #007); Room is the local cache + offline write queue.

### 5.7 Token storage — the post-EncryptedSharedPreferences stack

EncryptedSharedPreferences was deprecated in `androidx.security:security-crypto:1.1.0-alpha07`. Modern stack:

1. **Keystore-backed AES-GCM key** (StrongBox if available — Pixel 3+ / most modern devices).
2. **Tink** (`com.google.crypto.tink:tink-android`) wraps Keystore + crypto in a maintained, audited API.
3. **DataStore Preferences** stores the Tink-encrypted ciphertext.

A thin `TokenStore` interface backed by Tink-encrypted DataStore. Holds the supabase-kt session (access token + refresh token + expiresAt + user). **The CLAUDE.md rule "Keychain for all credential storage" becomes "Tink-encrypted DataStore for all credential storage" on Android.**

Override supabase-kt's default `SessionManager` so it routes through `TokenStore`:

```kotlin
createSupabaseClient(URL, KEY) {
  install(Auth) {
    sessionManager = TinkSessionManager(context, tokenStore)
  }
}
```

### 5.8 Concurrency mapping

| Swift / iOS | Kotlin / Android |
|---|---|
| `func fetch() async throws -> [Card]` | `suspend fun fetch(): List<Card>` |
| `Task { ... }` (unstructured root) | `viewModelScope.launch { ... }` (structured) |
| `Task.detached { ... }` | `CoroutineScope(Dispatchers.IO).launch { ... }` — rare; almost always wrong |
| `async let a = fetchA(); async let b = fetchB()` | `coroutineScope { val a = async { fetchA() }; val b = async { fetchB() } }` |
| `AsyncStream` | `Flow<T>` (cold) or `SharedFlow<T>` (hot) |
| `@Observable` published state | `StateFlow<UiState>` (hot, replays latest) |
| One-shot events | `Channel<Event>().receiveAsFlow()` or `SharedFlow(replay=0)` |

**Rules:**
- Always use **structured concurrency** — `viewModelScope`, `lifecycleScope`. Never `GlobalScope`.
- **`StateFlow` for screen state** (hot, replays). Collect with `collectAsStateWithLifecycle()` so collection pauses when off-screen.
- **`SharedFlow(replay=0)` or `Channel` for one-shot events** (navigation, snackbar, dismiss).
- **`Dispatchers.IO` for network/disk** — Ktor and Room handle this internally; wrap explicit blocking I/O in `withContext(Dispatchers.IO)`.
- **Test with Turbine** (Square's Flow test library — §10).

---

## 6. Camera + OCR for Scan

### 6.1 CameraX setup in Compose

There's no native `Camera` composable yet. The production pattern is `LifecycleCameraController` driving a `PreviewView` embedded via `AndroidView`:

```kotlin
val controller = remember {
  LifecycleCameraController(context).apply {
    setEnabledUseCases(CameraController.IMAGE_ANALYSIS)
    cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
    bindToLifecycle(lifecycleOwner)
  }
}
AndroidView(factory = { ctx -> PreviewView(ctx).apply { setController(controller) } })
```

`CameraController.IMAGE_ANALYSIS` feeds frames continuously without consuming the capture pipeline.

### 6.2 ML Kit Text Recognition v2 (Latin, bundled)

```
com.google.mlkit:text-recognition:16.0.1   # Latin model, bundled (~5-7 MB APK delta)
```

DECISIONS.md #043: bundled (~5 MB APK) over unbundled (~260 KB but first-run download) — parity with iOS Vision which works immediately on install.

ML Kit ships five script models; **use Latin only** — BOBA cards are Latin script.

### 6.3 The frame pipeline — use `MLKitAnalyzer`

CameraX's first-class ML Kit adapter handles backpressure, coordinate transforms, frame orientation, and frame-skipping. **Use it; do not roll your own.**

```kotlin
val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
controller.setImageAnalysisAnalyzer(
  ContextCompat.getMainExecutor(context),
  MLKitAnalyzer(
    listOf(recognizer),
    COORDINATE_SYSTEM_VIEW_REFERENCED,
    ContextCompat.getMainExecutor(context),
  ) { result ->
    val text = result.getValue(recognizer) ?: return@MLKitAnalyzer
    scanStore.handleFrame(text)
  }
)
```

**Backpressure:** `ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST` (CameraX default). Frames arriving while ML Kit is busy are dropped → no lag.

**Frame rate:** ML Kit Latin OCR runs at ~30-60 FPS on Pixel 6+ / Galaxy S22+; 15-30 on older. Set analyzer target to 720p; higher doesn't improve accuracy enough to pay for the framerate hit.

### 6.4 Card-number regex

Reuse the iOS regex verbatim: `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)`. Kotlin's `Regex` engine is identical PCRE semantics.

Walk every line of every `Text.TextBlock`, prefer matches in the bottom-left quadrant (BoBA's printed card number lives there), prefer matches with the highest ML Kit confidence. Lookup is `displayCardsByCardNumber[cardNumber]` against the in-memory catalog (§9).

### 6.5 Image fingerprint — defer to v2

iOS uses Vision Feature Prints (768-dim float vector, L2 distance against `feature-prints.bin`). **No exact Android equivalent.**

**Path forward when prioritized:**
- **MediaPipe Image Embedder** (`com.google.mediapipe:tasks-vision`) — Google-maintained MobileNet V3 backbones. Output: normalized feature vector (~1024 or 1280 dim). Same L2-distance logic as iOS but vectors won't match iOS output bit-for-bit — needs a parallel `feature-prints-android.bin` built by running the catalog through the Android model on a desktop tool.

**Recommendation for Android v1: OCR-only matching.** The iOS scan pipeline made fingerprint the primary key because OCR-only had a silent-wrong failure mode **in grid mode specifically**. For single-card live scan, OCR + hero-name veto + confidence threshold is sufficient — it's the iOS pre-fingerprint design that shipped well for months. Document in DECISIONS.md #043 that Android starts OCR-only and adds fingerprinting in v2 if it proves needed.

### 6.6 Grid scanning — defer or use OpenCV

iOS uses Vision's rectangle detection + perspective rectification (DECISIONS.md #035). Android's ML Kit Object Detection caps at 5 objects per frame — not enough for 9/12/20-card grid shots.

**Two real options:**
- **OpenCV via the official Android binding** (`org.opencv:opencv-android`) for contour detection + `getPerspectiveTransform` + `warpPerspective`. Same algorithm as iOS. ~20 MB native library; can be split via dynamic feature delivery.
- **Custom TFLite model** for "trading-card-shaped quadrilateral detection." Higher ceiling, much bigger lift.

**Recommendation:** defer grid scan to v2; single-card live scan is the headline feature and ships fine without it.

### 6.7 Privacy

**All on-device, no uploads.** Add this disclosure explicitly to the Play Store Data Safety form (§8) — "Camera access used only for on-device card recognition; no photos or text leave the device."

---

## 7. Notifications: FCM

### 7.1 Firebase setup

`com.google.firebase:firebase-messaging:24.x` plus a `google-services.json` from the Firebase Console. Create a new "BOBA Playbook (Android)" Firebase app under a Firebase project.

### 7.2 Required Android plumbing

- **Notification channels (mandatory since API 26):** create at `Application.onCreate()`, BEFORE any FCM messages arrive. Channels: `match-alerts`, `breaking-news`, `trade-messages` (deferred). Each has its own importance level — `match-alerts` = `IMPORTANCE_HIGH` for heads-up + vibrate.
- **`POST_NOTIFICATIONS` runtime permission (mandatory since API 33):** request **at the right moment** — NOT at app launch (rejection rate is high). Request when the user enables match alerts in Profile. Use `ActivityResultContracts.RequestPermission`.
- **Token registration:** `FirebaseMessaging.getInstance().token.await()`, save to a `user_devices` Supabase table keyed by `user_id` + `platform=android` + `token`. The dispatcher fans out to both platforms by joining on `user_id`.
- **`FirebaseMessagingService` subclass** to receive push payloads. Notification-only payloads display automatically; data payloads route through `onMessageReceived` and you build the `Notification`.

### 7.3 Cross-platform dispatcher architecture (DECISIONS.md #045)

When the match-alerts pipeline ships (DECISIONS.md #039), **one dispatcher, two transports.** Recommended: a Cloudflare Worker `boba-push-dispatcher` (matches the rest of BOBA's backend pattern):

1. Triggered by Supabase webhook OR a cron Worker scanning `trade_matches`.
2. Joins `user_devices` to get tokens.
3. Routes by `platform` — `apns` → APNs HTTP/2 + JWT; `android` → FCM v1 + Google service-account access token.
4. Both transports support batching.

**Symmetric payload format:**
```json
{
  "type": "match_alert",
  "match_id": "...",
  "other_user": "@handle",
  "card_count": 3,
  "deep_link": "bobaplaybook://matches/{match_id}"
}
```

iOS lands in `aps.alert` + custom keys; Android lands in FCM `data` and `FirebaseMessagingService` builds the notification + tap-action. **Deep-link is the same string on both sides.**

---

## 8. Distribution + Google Play

### 8.1 Play Console tracks

Internal testing (up to 100) → Closed testing (gated email list, may require 12 testers × 14 days for production unlock) → Open testing (public URL) → Production (staged rollout 1% → 10% → 50% → 100%).

### 8.2 Required assets

- **App icon** — 512×512 PNG, no alpha.
- **Feature graphic** — 1024×500. Mandatory.
- **Screenshots** — 2–8, 16:9 or 9:16, min 320px / max 3840px.
- **Short description** — 80 chars.
- **Full description** — 4000 chars.
- **Privacy policy URL** — `bobaplaybook.com/privacy` (already shipped).
- **Content rating** — IARC questionnaire.

### 8.3 Data Safety form

Stricter than Apple's privacy labels. For BOBA, declare:
- **Personal info:** name (username), email, photos (avatar upload).
- **App activity:** in-app interactions.
- **Device or other IDs:** FCM token.
- **Camera access:** declared as not transmitted (on-device OCR per §6.7).
- **Encryption in transit:** YES (TLS everywhere).
- **Data deletion:** YES (account-delete Worker per DECISIONS.md #039).
- **SDK declarations:** every SDK touching user data needs its own row. Firebase auto-discloses if you check the "use SDK Data Safety helper" box.

Budget half a day to fill this out correctly the first time.

### 8.4 Play Integrity API

The Android analog of App Attest. **For BOBA v1: skip.** Threat model doesn't justify the operational overhead. Revisit when trading ships (TRADE-DESIGN.md §4.4 — Apple §1.2 controls echo to Play Console policy; Play Integrity strengthens report/block surfaces).

When added:
1. Android: `IntegrityManagerFactory.createStandard(context).requestIntegrityToken(...)` → opaque JWT.
2. Send as `X-Play-Integrity-Token` header alongside the Supabase JWT.
3. Worker decodes via `https://playintegrity.googleapis.com/v1/{packageName}:decodeIntegrityToken` (server-side service-account).
4. Inspect verdict; allow or reject.

### 8.5 Play App Signing — mandatory

Generate an upload key locally (`keytool -genkey ...`); upload to Play Console. Play resigns every release with its production key. Upload-key credentials live in `gradle.properties` (git-excluded), mirrored to CI secrets.

### 8.6 The 16 KB page size requirement

Hard deadline: November 1, 2025 (extended to May 30, 2026) — all new apps + updates targeting Android 15+ must support 16 KB page sizes on 64-bit devices.

**Action items:**
- **NDK r28+** compiles 16 KB-aligned by default.
- **Audit every native library** transitively. Major SDKs (Firebase, ML Kit, AndroidX) are compatible. Tertiary SDKs may not be.
- ML Kit Text Recognition ships native `.so` but Google rebuilds for 16 KB on time. OpenCV (if used for grid scan): verify the version is aligned.
- Validate via `apkanalyzer` on each release.

**BOBA's planned stack:** ML Kit Text Recognition is the only non-pure-Kotlin/Java dependency, and Google maintains it. No action needed for v1.

### 8.7 Google Play Billing (when BOBA Pro ships)

Per TRADE-DESIGN.md §7 — sub tier 2026. Use `com.android.billingclient:billing-ktx:7.x`. Pricing parity with iOS: $2.99/mo, $19.99/yr.

**Cross-platform subscription state is NOT synced** between Apple and Google. Record subs in Supabase (`user_subscriptions` table, webhook from Apple IAP + RTDN from Google Play Billing). Plan for this from day one.

| | Apple IAP | Google Play Billing |
|---|---|---|
| Standard sub | 30% Y1, 15% Y2+ | 15% new installs, 20% existing, **10% recurring** |
| Small Business | 15% (<$1M/yr) | 15% standard |
| External payment | Allowed post-Epic ruling | Allowed; 5% processing fee if using external |

### 8.8 Trading-card content policy

Same as Apple §1.2 (TRADE-DESIGN.md §4.4) — when trading ships, Play Console policy requires UGC controls (filter / report / block / contact). The bilateral block + email-based reporting + bounded-shape listings pattern from TRADE-DESIGN.md §4.4 satisfies both Apple AND Play.

---

## 9. Cross-platform shared assets

### 9.1 Card catalog (cards.json + categories.json + search-index.json)

**Bundle in `app/src/main/assets/`** — same shape as iOS bundling. Decoded at launch via `context.assets.open("cards.json").bufferedReader()` + `kotlinx.serialization.json.Json.decodeFromStream(...)`.

**Two-phase load (parity with DECISIONS.md #014):**
- **Phase 1 (sync, ≤50 ms):** decode `cards-head.json` (500 cards, ~192 KB) on `Application.onCreate()` on the main thread. Cards available before first Compose frame.
- **Phase 2 (background, ~200–400 ms):** spawn a `CoroutineScope(Dispatchers.IO).launch` to decode the full `cards.json` and atomically swap the in-memory `Map<bobaId, Card>`.

`kotlinx.serialization` beats Moshi by ~20% on large arrays via codegen. Mark `Card` as `@Serializable`. Use `Json { ignoreUnknownKeys = true; encodeDefaults = false }` so schema additions don't break the client.

**Search index:** lazy-decode on first search; ~1–2 second decode in background while user composes their query. Same pattern as iOS.

**Heap budget:** full catalog ~12–15 MB heap (17K Kotlin data classes is more overhead than 17K Swift structs because of JVM object headers + reference wrapping). Verify on lowest-end Android Go-class targets (3 GB RAM) — should be fine.

**Bundling strategy:** Gradle task that copies `assets/data/*.json` from the repo root into `android/app/src/main/assets/data/` at build time. Keeps the iOS + Android + Web catalogs in lockstep — single source of truth.

### 9.2 Fonts

Bundle under `app/src/main/res/font/`:
- `bebas_neue_regular.ttf`
- `russo_one_regular.ttf`
- `chakra_petch_regular.ttf`, `chakra_petch_bold.ttf`, `chakra_petch_light.ttf`, `chakra_petch_italic.ttf`

Wire into Compose via `FontFamily(Font(R.font.bebas_neue_regular, FontWeight.Normal))`. Copy the same TTFs from `BOBAPlaybook/Resources/Fonts/`.

**Skip downloadable fonts** (Google Fonts CDN) — the brand mark uses Bebas Neue throughout including the splash screen, and downloadable fonts add a network dependency to first paint.

### 9.3 Card back + app icon + splash

- **Card back:** copy `BOBAPlaybook/Resources/CardBack.webp` to `res/drawable-nodpi/card_back.webp`. Single-density nodpi avoids unnecessary scaling.
- **App icon — adaptive icon (mandatory since API 26):**
  - `res/mipmap-anydpi-v26/ic_launcher.xml` references `<adaptive-icon>` with `<foreground>`, `<background>`, AND `<monochrome>` (themed-icon variant for Android 13+).
  - All three layers 108×108 dp.
  - Foreground: BOBA XOXO mark on transparent.
  - Background: solid `--boba-near-black` `#080810`.
  - Monochrome: single-color silhouette — launcher tints from wallpaper/theme.
  - Ship a hand-tuned monochrome layer; auto-generation is lossy.
- **Splash:** Android 12+ Splash Screen API. Configure via `res/values-v31/themes.xml` with `windowSplashScreenBackground` + `windowSplashScreenAnimatedIcon`. Same XOXO mark, same background.

---

## 10. Testing

### 10.1 Unit tests

- **kotlin.test** (multiplatform-ready) or **JUnit 5** (Android standard).
- **MockK** — Kotlin-first mocking (`suspend` and `Flow` first-class).
- **Turbine** — Square's library for testing Kotlin Flows. Essential for ViewModel tests:
  ```kotlin
  viewModel.uiState.test {
      assertEquals(FindUiState.Loading, awaitItem())
      assertEquals(FindUiState.Content(cards = [...]), awaitItem())
  }
  ```
- **`kotlinx-coroutines-test`** — `runTest`, `TestDispatcher`, `advanceUntilIdle()` for controllable virtual time.

### 10.2 Compose UI tests

- **`androidx.compose.ui:ui-test-junit4`** — semantics-based; tap nodes by `testTag` or content description.
- Run on **Robolectric** (JVM, fast) or **emulator/device** (slower but realistic).
- Test the integration boundary: ViewModel + Composable, mocked repository.

### 10.3 Screenshot tests: Roborazzi

**Pick Roborazzi over Paparazzi.**

| | Paparazzi | Roborazzi |
|---|---|---|
| Speed | Slightly faster (native JVM) | Slower (Robolectric) but acceptable |
| Activity / Fragment support | No | Yes |
| Interaction during snapshot | No | Yes |
| Hilt integration | Awkward | Native |
| Robolectric compat | No (conflicts) | Yes (it IS Robolectric) |

The ability to snapshot **after** an interaction (e.g., scan-result tile expanded) is decisive. Pair with **ComposablePreviewScanner** to auto-generate screenshot tests from `@Preview` annotations.

### 10.4 Macrobenchmark

For startup, scrolling, frame-jank measurement. Runs against a release build on a device or emulator. Generates the Baseline Profile (§11.2).

---

## 11. Performance

### 11.1 R8 (always on for release)

Per Performance Spotlight Week 2025: "The single most impactful, low-effort change you can make is fully enabling the R8 optimizer."

```kotlin
android {
  buildTypes {
    release {
      isMinifyEnabled = true
      isShrinkResources = true
      proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
  }
}
```

Typical app-size reduction: 30–60%. Kotlin Serialization + Room + Hilt + Coil all ship their own ProGuard rules — usually no extra config needed.

**Audit:** check `app/build/outputs/mapping/release/usage.txt` after a release build for any `@Serializable` class accidentally stripped.

### 11.2 Baseline Profiles — strongly recommended from day one

20-40% cold-start improvement. For an app with 17K cards loading into a grid at launch, this is meaningful.

Setup:
1. Create a `:baselineprofile` module via Android Studio's "New Module" → "Baseline Profile Generator."
2. Emit a Macrobenchmark test that exercises critical paths: launch → Find tab → search "Amon-Ra" → tap a card → scroll Find grid → switch to Collection.
3. Generator produces `baseline-prof.txt` packaged into the production APK. ART pre-compiles those code paths at install time.
4. CI runs the generator nightly via Macrobenchmark 1.4.1+ and AGP 8.0.0+; commits regenerated profiles when they change.

**Target:** ≤ 800ms cold start on a Pixel 6 baseline.

### 11.3 Compose stability / skippability

- **UI state uses `@Immutable` data classes:** `@Immutable data class FindUiState(...)`.
- **Use `kotlinx.collections.immutable.PersistentList`** instead of `List<T>` in UI state — `List<T>` is unstable to Compose.
- **Pass lambdas referentially-stably** — `remember` for callbacks that capture state, or pass `onEvent: (FindEvent) -> Unit` once.
- **Don't chase 100% skippable.** Strong Skipping Mode (Compose Compiler 1.5.4+, default in Kotlin 2.0+) handles most cases. The marginal optimization beyond that isn't worth fighting the compiler.

### 11.4 The Find grid — the most performance-sensitive screen

```kotlin
LazyVerticalGrid(
  columns = GridCells.Fixed(3),
  modifier = Modifier.fillMaxSize(),
  contentPadding = PaddingValues(8.dp),
  verticalArrangement = Arrangement.spacedBy(8.dp),
  horizontalArrangement = Arrangement.spacedBy(8.dp)
) {
  items(
    items = cards,
    key = { card -> card.bobaId },   // STABLE KEY — non-negotiable
    contentType = { _ -> "card" }    // helps recycling
  ) { card ->
    BOBACardCell(card)
  }
}
```

**Stable keys are non-negotiable.** Without `key = { card.bobaId }`, LazyVerticalGrid can't map items to existing compositions across any list mutation (search, filter, sort), triggering full recomposition of every visible slot. Add a unit test that fails if any `LazyVerticalGrid` calls `items(...)` without `key`.

**`derivedStateOf` for scroll-derived UI:** the scroll-edge effect, "first cell visible," "scroll-to-top button visibility" all derive from `lazyGridState.layoutInfo.visibleItemsInfo`. Wrap in `derivedStateOf` so the UI recomposes only when the **derived value** changes.

```kotlin
val showScrollToTop by remember {
  derivedStateOf { lazyGridState.firstVisibleItemIndex > 20 }
}
```

### 11.5 Frame metrics + profiling

- **JankStats** in production — collects frame-render data, hooks to telemetry.
- **`androidx.tracing.perfetto`** for low-level GPU/CPU traces.
- **Macrobenchmark + StrictMode + Compose Layout Inspector** are the three tools to validate. Run cold-start macrobenchmark before every release; fail CI if cold start regresses >5%.

---

## 12. Security

### 12.1 Encrypted storage

§5.7. **Keystore-backed AES-GCM key + Tink + DataStore.** Never SharedPreferences for secrets.

### 12.2 Biometric auth

`androidx.biometric:biometric-compose:1.4.0-alpha05+` — modern Compose API removes the "wrap BiometricPrompt in a Fragment" pattern.

- **Always tie biometric prompts to a Keystore key via `CryptoObject`** — biometric without cryptographic binding is theater.
- **Use `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)`** — `BIOMETRIC_WEAK` can be low-confidence face-unlock.

For BOBA: gate **Profile → Edit account settings** behind biometric (parity with iOS Face ID gate).

### 12.3 Certificate pinning

**Skip for v1.** Supabase and Cloudflare use solid CAs; pinning adds operational risk (cert rotation crashes the app) without commensurate security gain for an app that doesn't carry financial data.

---

## 13. Build + CI/CD

### 13.1 Gradle Kotlin DSL + version catalog

`gradle/libs.versions.toml`:

```toml
[versions]
kotlin = "2.2.0"
agp = "9.0.0"
compose-bom = "2026.05.00"
coil = "3.0.0"
supabase = "3.0.0"
mlkit-text = "16.0.1"
camerax = "1.5.0"
ktor = "3.0.0"
hilt = "2.52"
room = "3.0.0"
nav-compose = "2.8.0"

[libraries]
kotlinx-serialization = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version = "1.7.3" }
supabase-bom = { module = "io.github.jan-tennert.supabase:bom", version.ref = "supabase" }
supabase-auth = { module = "io.github.jan-tennert.supabase:auth-kt" }
supabase-postgrest = { module = "io.github.jan-tennert.supabase:postgrest-kt" }
supabase-realtime = { module = "io.github.jan-tennert.supabase:realtime-kt" }
supabase-compose-auth = { module = "io.github.jan-tennert.supabase:compose-auth" }
ktor-okhttp = { module = "io.ktor:ktor-client-okhttp", version.ref = "ktor" }
coil-compose = { module = "io.coil-kt.coil3:coil-compose", version.ref = "coil" }
coil-network-okhttp = { module = "io.coil-kt.coil3:coil-network-okhttp", version.ref = "coil" }
mlkit-text-recognition = { module = "com.google.mlkit:text-recognition", version.ref = "mlkit-text" }
camerax-core = { module = "androidx.camera:camera-core", version.ref = "camerax" }
camerax-camera2 = { module = "androidx.camera:camera-camera2", version.ref = "camerax" }
camerax-lifecycle = { module = "androidx.camera:camera-lifecycle", version.ref = "camerax" }
camerax-view = { module = "androidx.camera:camera-view", version.ref = "camerax" }
camerax-mlkit = { module = "androidx.camera:camera-mlkit-vision", version.ref = "camerax" }
hilt = { module = "com.google.dagger:hilt-android", version.ref = "hilt" }
hilt-compiler = { module = "com.google.dagger:hilt-compiler", version.ref = "hilt" }
hilt-nav-compose = { module = "androidx.hilt:hilt-navigation-compose", version = "1.2.0" }
room-runtime = { module = "androidx.room:room-runtime", version.ref = "room" }
room-compiler = { module = "androidx.room:room-compiler", version.ref = "room" }
room-ktx = { module = "androidx.room:room-ktx", version.ref = "room" }
nav-compose = { module = "androidx.navigation:navigation-compose", version.ref = "nav-compose" }
nav-compose-typesafe = { module = "androidx.navigation:navigation-compose", version.ref = "nav-compose" }
datastore-preferences = { module = "androidx.datastore:datastore-preferences", version = "1.1.1" }
tink-android = { module = "com.google.crypto.tink:tink-android", version = "1.13.0" }
biometric-compose = { module = "androidx.biometric:biometric-compose", version = "1.4.0-alpha05" }
turbine = { module = "app.cash.turbine:turbine", version = "1.2.0" }
roborazzi = { module = "io.github.takahirom.roborazzi:roborazzi", version = "1.30.1" }
```

### 13.2 GitHub Actions for Android — symmetric with Xcode Cloud

iOS uses Xcode Cloud; Android uses GitHub Actions. Both run on the same repo — Xcode Cloud watches `BOBAPlaybook.xcodeproj`, GitHub Actions watches `android/`.

`.github/workflows/android-build.yml`:
- **PR build:** `:app:assembleDebug` + unit tests + Compose preview lint + R8 dry-run.
- **Tag push (`v*.*.*-android`):** `:app:bundleRelease` + Play Store upload via `r0adkll/upload-google-play@v1` (service-account JSON in GH Secrets).
- **Baseline Profile generation:** nightly cron — `:baselineprofile:connectedReleaseAndroidTest` against emulator. Commits regenerated profile if changed.

### 13.3 Mirror sync for shared assets

Same pattern as `pipeline/recognition/sync_mirror.sh` (the iOS one that just bit us in the GitHub Action). Add `android/scripts/sync_assets.sh` that copies `assets/data/cards.json` → `android/app/src/main/assets/data/cards.json` and fails CI on drift. **Single source of truth: the repo-root `assets/data/`.**

---

## 14. Universal Links / deep linking

### 14.1 Android App Links + assetlinks.json

The verification file lives at the **same path** as iOS's AASA: `https://bobaplaybook.com/.well-known/assetlinks.json`. Both files coexist.

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.bobaplaybook.app",
    "sha256_cert_fingerprints": [
      "AB:CD:...:EF"
    ]
  }
}]
```

Fingerprint from Play Console → Setup → App integrity → "App signing key certificate." Add **both** the upload key AND the Play App Signing key fingerprints (the upload-key signed APKs in internal testing won't verify against the Play-resigned production key otherwise — common gotcha).

**Jekyll exclude:** BOBA's `_config.yml` already excludes `/.well-known/`. Verify `assetlinks.json` is in that exclude.

### 14.2 AndroidManifest intent-filter

```xml
<activity android:name=".MainActivity"
          android:exported="true"
          android:launchMode="singleTask">
  <intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https" android:host="bobaplaybook.com" android:pathPrefix="/u"/>
    <data android:scheme="https" android:host="bobaplaybook.com" android:pathPrefix="/card"/>
    <data android:scheme="https" android:host="bobaplaybook.com" android:pathPrefix="/deck"/>
  </intent-filter>
  <!-- custom scheme deep links for OAuth callbacks + same-app deep links -->
  <intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="bobaplaybook"/>
  </intent-filter>
</activity>
```

`android:autoVerify="true"` triggers Android's automated assetlinks.json fetch on install. Without it, the link opens the disambiguation chooser — same UX as a broken iOS Universal Link.

**Android 15+ dynamically re-fetches `assetlinks.json`** every ~24h on devices with Play Services. Lets you rotate fingerprints server-side without an app update.

### 14.3 Dispatcher matching iOS routeIncoming

Single dispatcher in `MainActivity`:

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
  super.onCreate(savedInstanceState)
  supabase.handleDeeplinks(intent)
  handleAppDeepLink(intent)
  setContent { BOBAApp() }
}

override fun onNewIntent(intent: Intent) {
  super.onNewIntent(intent)
  setIntent(intent)
  supabase.handleDeeplinks(intent)
  handleAppDeepLink(intent)
}

private fun handleAppDeepLink(intent: Intent) {
  val uri = intent.data ?: return
  when (uri.scheme) {
    "https" -> routeUniversalLink(uri)
    "bobaplaybook" -> routeDeepLink(uri)
  }
}
```

**Same architecture as iOS** — single dispatcher, scheme-based switching, route-based push. The MEMORY lesson `feedback_universal_links_onopenurl.md` (iOS-specific) doesn't translate directly — Android doesn't have the `.onContinueUserActivity` confusion — but the meta-lesson does: **dispatch by scheme, not by URL shape.**

---

## 15. Claude Code skills for Android development

Research summary (see `docs/CLAUDE-SKILLS-ANDROID.md` or the agent output for full citations). Android skill ecosystem is scattered across ~10 repos vs iOS's umbrella `all-ios-skills`. **Recommended install set:**

| Tier | Repo | Why |
|---|---|---|
| 1 (official) | `github.com/android/skills` | Google's curated set — AGP migration, adaptive layouts, edge-to-edge, R8 analyzer, theming, Nav 3 |
| 1 (official) | `github.com/Kotlin/kotlin-agent-skills` | JetBrains' official Kotlin skills — early-stage but canonical home |
| 2 (community) | `github.com/chrisbanes/skills` | 16 Compose + Kotlin skills from a Google Android team engineer; closest to `all-ios-skills`-quality |
| 2 (community) | `github.com/rcosteira79/android-skills` | 16 skills covering architecture, testing, M3, debugging, Coil 3, Coroutines, Flows, Compose, Retrofit, Ktor (KMP), Room |
| 2 (community) | `github.com/Drjacky/claude-android-ninja` | Comprehensive single skill — 25+ reference files including Compose M3, Nav 3, Hilt, Room 3, Retrofit, Coil 3, Macrobenchmark, biometrics, Play Integrity |
| 2 (community) | `github.com/skydoves/android-testing-skills` | 54 testing skills across Compose UI, JUnit5, MockK, Espresso, AndroidJUnit4, ADB E2E |
| 2 (community) | `github.com/skydoves/compose-performance-skills` | 26 perf skills — stability, recomposition, lazy lists, Macrobenchmark, baseline profiles |
| 2 (community) | `github.com/aldefy/compose-skill` | 24 Compose refs verified against androidx source |

**Install command set:**

```sh
# Tier 1 — official
# (Google's Android CLI install path varies — see android/skills repo README)
/plugin marketplace add Kotlin/kotlin-agent-skills

# Tier 2 — community
npx skills add chrisbanes/skills
/plugin marketplace add rcosteira79/android-skills
git clone https://github.com/skydoves/android-testing-skills ~/.claude/skills-sources/android-testing-skills
git clone https://github.com/skydoves/compose-performance-skills ~/.claude/skills-sources/compose-performance-skills
npx openskills install drjacky/claude-android-ninja
/plugin marketplace add aldefy/compose-skill
```

That stacks to **~150 Android/Kotlin/Compose-targeted skills**, vs `all-ios-skills`' ~40 — but with significant overlap. Claude Code's auto-trigger handles routing.

**Critical gaps — no high-confidence dedicated skill exists:**

1. **ML Kit** (text recognition, object detection) — directly relevant for BOBA scan
2. **CameraX as a development aid** (only migration-from-Camera1 exists)
3. **Credential Manager** (passkeys, federated sign-in)
4. **BiometricPrompt**
5. **FCM push notifications** (Android-native, not Capacitor-flavored)
6. **App Links / Android deep linking**
7. **Android Keystore / encryption**
8. **Play Billing as a tutorial** (only version-upgrade migration exists)

**For each gap, plan to write a project-local skill** as we work through that feature. The pattern is: hit the gap, write the skill, commit to `/.claude/skills/`. Use the same pattern that produced the iOS skills documented in the `reference_realitykit_ios26_native_apis.md` MEMORY entry.

---

## 16. Open questions to resolve before M0

These need Ben's call before kicking off the Android codebase:

1. **Package name / app ID.** `com.bobaplaybook.app`? `com.bhwilkoff.bobaplaybook`? `app.bobaplaybook.android`? (iOS is `app.bobaplaybook.ios` per the App Store listing.) Affects all signing + Play Console + assetlinks.json + Firebase config.
2. **Subdirectory or sibling repo?** Recommendation: same monorepo, `/android/` at root. Affects CI workflow scope, asset sync, branch policy.
3. **Firebase project: new or shared with future iOS Firebase setup?** Affects FCM token registration + Analytics config.
4. **Subscription monetization (TRADE-DESIGN.md §7) — ship in v1 or defer?** Affects Play Billing wiring + `user_subscriptions` Supabase schema.
5. **Discord-link requirement for trading — hard gate or soft warning?** Same question as iOS in TRADE-DESIGN.md §12; needs a consistent answer across platforms.
6. **Initial supported form factors:** Phone-only for v1, or phone + tablet at v1? Tablet is significant additional work (multi-pane scaffolds) and could be M8 not M1.
7. **Personal Showcase + AirPlay — port to Cast SDK in v1 or skip?** ANDROID-DESIGN.md §12 marks it out-of-scope; confirm.
8. **Hero Shot 3D — port to Filament in v1 or skip?** ANDROID-DESIGN.md §12 marks it out-of-scope; confirm.
9. **Practice executor — admin-gated, deferred per iOS DECISIONS.md #033.** Confirm Android tracks the same gate.

Resolved decisions get added to DECISIONS.md as #041–#046+ (see DECISIONS.md updates).

---

## 17. Things that DON'T carry over from iOS

Three pieces of the iOS playbook that need fresh thinking when (if) they ship on Android:

1. **iOS Hero Shot 3D card rendering** — RealityKit has no exact analog. If ported, it's a Filament or Sceneform-Compose-successor effort and a separate research pass.
2. **iOS Vision Feature Prints** — MediaPipe Image Embedder is the closest analog but produces a different-shape vector; needs a parallel `feature-prints-android.bin`. Defer to v2.
3. **iOS Live Activities / Dynamic Island** — Android has nothing equivalent (Notification Live Updates in Android 16 are close but not). Accept the asymmetry; don't try to emulate.

Two cross-cutting reminders that need to land in DECISIONS.md / MEMORY from day one:

- **Every Worker / Storage / Edge Function call calls `refreshIfNeeded()` first** (the iOS v2.279 lesson translated).
- **Always ensure web parity** (MEMORY `feedback_always_ensure_web_parity.md`) extends to Android too — when shipping any feature on iOS, mirror it on Android in the same change set where feasible.

The Android version is a second client to the same Supabase + R2 + Workers backend with the same static catalog and the same brand. Build it as such; don't fork the IA.

---

## 18. References

**Android Platform + Release:**
- [SDK Platform release notes](https://developer.android.com/tools/releases/platforms)
- [API Levels distribution](https://apilevels.com/)
- [Google Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Behavior changes: Android 15](https://developer.android.com/about/versions/15/behavior-changes-15)
- [Behavior changes: Android 16](https://developer.android.com/about/versions/16/behavior-changes-16)
- [Android 17 timeline (Sammy Fans)](https://www.sammyfans.com/2026/02/14/android-17-development-roadmap-beta-stable/)

**Architecture + Frameworks:**
- [Compose UI Architecture](https://developer.android.com/develop/ui/compose/architecture)
- [State hoisting](https://developer.android.com/develop/ui/compose/state-hoisting)
- [Save UI state in Compose](https://developer.android.com/develop/ui/compose/state-saving)
- [Type-safe Navigation for Compose (Don Turner)](https://medium.com/androiddevelopers/type-safe-navigation-for-compose-105325a97657)
- [Build adaptive apps](https://developer.android.com/develop/ui/compose/build-adaptive-apps)
- [Compose Adaptive Layouts 1.2 beta](https://android-developers.googleblog.com/2025/09/unfold-new-possibilities-with-compose-adaptive-layouts-1-2-beta.html)
- [StateFlow and SharedFlow](https://developer.android.com/kotlin/flow/stateflow-and-sharedflow)
- [Kotlin Coroutines docs](https://kotlinlang.org/docs/coroutines-overview.html)

**Supabase + Android:**
- [supabase-kt (community)](https://github.com/supabase-community/supabase-kt)
- [Supabase Kotlin API Reference](https://supabase.com/docs/reference/kotlin/introduction)
- [Use Supabase with Android Kotlin (Quickstart)](https://supabase.com/docs/guides/getting-started/quickstarts/kotlin)
- [Supabase session refresh](https://supabase.com/docs/guides/auth/sessions)

**Coil 3:**
- [Coil — Image Loaders configuration](https://coil-kt.github.io/coil/image_loaders/)
- [Coil — Getting Started](https://coil-kt.github.io/coil/getting_started/)
- [Coil network plugin](https://coil-kt.github.io/coil/network/)

**CameraX + ML Kit:**
- [CameraX Image Analysis](https://developer.android.com/training/camerax/analyze)
- [CameraX ML Kit Analyzer](https://developer.android.com/media/camera/camerax/mlkitanalyzer)
- [ML Kit Text Recognition v2 for Android](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)
- [On-Device OCR with ML Kit + CameraX (AtomicRobot)](https://atomicrobot.com/blog/mlkit-on-device-ocr-android/)
- [MediaPipe Image Embedder](https://developers.google.com/mediapipe/solutions/vision/image_embedder)

**Authentication:**
- [Android Credential Manager](https://developers.google.com/identity/android-credential-manager)
- [Sign in with Google via Credential Manager](https://developer.android.com/identity/sign-in/credential-manager-siwg)
- [Auth Tab (Chrome 132+)](https://developer.chrome.com/docs/android/custom-tabs/guide-auth-tab)
- [Goodbye EncryptedSharedPreferences (droidcon)](https://www.droidcon.com/2025/12/16/goodbye-encryptedsharedpreferences-a-2026-migration-guide/)
- [BiometricPrompt — biometric-compose 1.4](https://medium.com/@ramadan123sayed/biometric-authentication-in-android-the-complete-guide-fingerprint-face-iris-device-b86e6f77b958)

**Notifications:**
- [Firebase Cloud Messaging on Android](https://firebase.google.com/docs/cloud-messaging/android/get-started)

**Deep linking:**
- [Android App Links — Verify](https://developer.android.com/training/app-links/verify-site-associations)
- [About App Links](https://developer.android.com/training/app-links/about)

**Distribution:**
- [Play Console — Data safety section](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Play Integrity API](https://developer.android.com/google/play/integrity/overview)
- [Support 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)
- [Google Play 16 KB page size extension (May 31, 2026)](https://support.google.com/googleplay/android-developer/thread/369751886/clarification-on-16-kb-page-size-extension-and-monitoring-for-issues-before-may-31-2026)
- [Google Play service fees](https://support.google.com/googleplay/android-developer/answer/112622)

**Build + CI/CD:**
- [Kotlin DSL default for Gradle](https://blog.gradle.org/kotlin-dsl-is-now-the-default-for-new-gradle-builds)
- [Gradle Version Catalogs](https://docs.gradle.org/current/userguide/version_catalogs.html)
- [Migrate from kapt to KSP](https://developer.android.com/build/migrate-to-ksp)
- [Migrate to built-in Kotlin (AGP 9)](https://developer.android.com/build/migrate-to-built-in-kotlin)

**Performance:**
- [Jetpack Compose Performance](https://developer.android.com/develop/ui/compose/performance)
- [Baseline Profiles overview](https://developer.android.com/topic/performance/baselineprofiles/overview)
- [Fully Optimized (Android Developers Blog)](https://android-developers.googleblog.com/2025/11/fully-optimized-wrapping-up-performance.html)

**Security:**
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [Keystore pitfalls (Stytch)](https://stytch.com/blog/android-keystore-pitfalls-and-best-practices/)

**Testing:**
- [Roborazzi](https://github.com/takahirom/roborazzi)
- [Turbine](https://github.com/cashapp/turbine)
- [Snapshot testing libraries compared (Medium)](https://medium.com/@natalia.kulbaka/comparing-snapshot-testing-libraries-paparazzi-roborazzi-compose-previews-screenshot-testing-b7c3b47f7f59)

**Design companion:** See [ANDROID-DESIGN.md](./ANDROID-DESIGN.md) for the binding design rules that govern UI / IA decisions.
