# BOBA Playbook — Android Setup

Step-by-step for Ben. Anything I (Claude) can do via API or files I've already done. The remaining steps require:

- Installing local apps (Android Studio, etc.)
- Visiting external web consoles (Google Play Console, Firebase, Supabase, Google Cloud)
- Generating cryptographic keys (the upload keystore for Play App Signing)

I've broken each step into:
- **Why** — what this unlocks
- **How** — what to click / paste / run
- **Verify** — how you know it worked
- **What I do after** — anything I can wire up once you paste me a value

Work through them in order; later steps depend on earlier ones.

---

## Phase A — Local toolchain (one-time, ~30 min)

### A1. Install Android Studio Panda

**Why:** the only practical way to build/run/debug Android. Gradle wrapper, AGP plugin, emulator, ADB, Layout Inspector — all bundled. **Android Studio Panda 4 Patch 1 (2025.3.4)** is the current stable as of May 2026; that's what the project's version catalog targets (AGP 9.2.0, Gradle 9.1+, JDK 21 bundled).

**How:**
1. Download **Android Studio Panda 4 Patch 1** (or current stable) from <https://developer.android.com/studio>.
2. Drag to `/Applications/` and launch.
3. First-launch wizard: accept the default install (includes Android SDK Platform 36 / Android 16, Build-Tools, emulator image).
4. When asked about JDK: Android Studio Panda ships a bundled **JBR 21** (JetBrains Runtime, Java 21). Accept the bundled one — AGP 9 requires JDK 17 minimum and 21 is the new sweet spot.
5. **Important — AGP 9 sets JDK criteria via Gradle Daemon JVM auto-detection.** This means you do NOT need a separate JDK install on the host; Studio's bundled JBR is auto-detected. If your shell's `java -version` reports anything older than 17, that's fine — Studio uses its bundled JBR independently.
6. Once at the welcome screen, **don't open the project yet** — finish A2 first.

**Verify:**
```sh
ls /Applications/Android\ Studio*.app    # should exist
ls ~/Library/Android/sdk                  # SDK should be here
```

**What I do after:** nothing — this is purely local.

---

### A2. Install command-line tools

**Why:** lets me run `./gradlew`, `keytool`, and `adb` from my session if you ever want me to validate the build without bouncing through Studio.

**How:**
```sh
# adb / fastboot / platform-tools
brew install --cask android-platform-tools

# Point shell at Panda's bundled JBR 21 (the path is stable across
# Studio versions on macOS — same /Contents/jbr/ path that worked
# for Otter, Narwhal, etc.):
echo 'export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"' >> ~/.zshrc
echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Verify:**
```sh
java -version       # should print openjdk 21.x (Panda's bundled JBR)
adb --version       # should print Android Debug Bridge version
keytool -h          # should print keytool usage
```

**What I do after:** once Java is on your PATH, I can run `./gradlew` myself and validate builds without bouncing back to you.

---

### A3. Open the project + sync

**Why:** generates the Gradle wrapper (`gradlew`, `gradle-wrapper.jar`, `gradle-wrapper.properties`) which the rest of the workflow depends on. Studio detects Gradle 9.1+ is required (AGP 9.x) and downloads/auto-configures the wrapper.

**How:**
1. Launch Android Studio Panda → **Open** → navigate to `/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/android` → **Open**.
2. Studio prompts: "Gradle wrapper not found. Generate?" → **Yes** (or auto-generates silently). Studio fetches Gradle 9.1+ to match AGP 9.2.0.
3. Studio then runs the first **Gradle sync** (~3-5 min first time — downloading every dependency in the version catalog).
4. **AGP 9 first-sync note:** Studio may show a one-time "AGP includes built-in Kotlin support" info card. That's expected; it confirms the catalog config worked. Dismiss it.
5. **If sync fails with a version-conflict error**, paste the error to me. The most common cause in a Panda + AGP 9.2 setup is one library catalog entry needing a small bump (e.g., a `kotlin.compose` patch level), and I'll fix it in `gradle/libs.versions.toml`.

**Verify:**
- Bottom-right of Studio shows "Gradle build finished" without red errors.
- The **Build** tool window has zero compilation errors.
- `android/gradle/wrapper/gradle-wrapper.properties` now exists.
- The Project view shows all five modules: `app`, `core:ui`, `core:domain`, `core:network`, `core:data`.

**What I do after:** I can run gradle locally now. If you paste me any sync error, I fix the version catalog and we re-trigger.

---

### A4. Create an emulator + Chromebook profile (optional but useful)

**Why:** lets you run the app on a virtual Pixel for compact-width testing, and on a virtual Chromebook for expanded-width / desktop-windowing testing (per DECISIONS.md #047, Chromebook support is a v1 priority from M1).

**How:**
1. **Tools → Device Manager** → **Create Device**.
2. Pick **Pixel 9 Pro** (or any modern phone) → next → choose an **Android 16 (API 36) "Google APIs"** system image → **Finish**.
3. Repeat with **Tablet → Pixel Tablet** for tablet adaptation testing.
4. **Resizable emulator** — Panda ships a "Resizable" device profile under Phone / Foldable / Desktop. Create one to swap between phone / unfolded / desktop layouts at runtime — closest local proxy for Chromebook windowing.
5. Real Chromebook (you mentioned having one): enable Linux/ARC Android app support on the Chromebook, then run from Studio via `adb connect` once you have the IP.

**Verify:** click ▶ next to each emulator in Device Manager — it should boot to the home screen.

**What I do after:** nothing locally — but once you've validated the build on at least one emulator, I can write Roborazzi screenshot tests that run against the same profiles in CI.

---

## Phase B — Google services (one-time, ~1 hr)

### B1. Generate the upload keystore

**Why:** Play App Signing requires you to sign every release with an upload key. Google then resigns with its production key. **The production key never leaves Google.** Without an upload keystore, you can't publish.

**How:**
```sh
# Pick a path you'll keep forever — NEVER commit this file. NEVER lose it.
keytool -genkeypair -v \
  -keystore ~/.android/boba-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias boba-upload
```

When prompted:
- Choose a strong password (you'll use it for the keystore AND the key alias)
- Name: your full name
- Org unit: leave blank or "BOBA Playbook"
- Org: "BOBA Playbook"
- City / State / Country: as appropriate

**Verify:**
```sh
ls -la ~/.android/boba-upload.jks    # file exists, ~2 KB
keytool -list -v -keystore ~/.android/boba-upload.jks -alias boba-upload
# should print certificate details including a SHA-256 fingerprint
```

**Save the SHA-256 fingerprint somewhere.** It looks like `A1:B2:C3:...:EF` — colons every two hex characters. You'll need it twice in the next two steps.

**What I do after:** once you paste me the **SHA-256 fingerprint** AND the **SHA-1 fingerprint** (run `keytool -list -v ...` and copy both), I:
1. Replace `REPLACE_WITH_UPLOAD_KEY_SHA256` in `/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/.well-known/assetlinks.json` with your real fingerprint.
2. Commit the change. App Links verification works the moment the site redeploys.

---

### B2. Create the Google Play Console developer account

**Why:** you can't publish an Android app — even to internal testing — without a Play Console developer account. One-time $25 fee, lifetime account.

**How:**
1. Visit <https://play.google.com/console/signup>.
2. Sign in with the Google account you want associated with BOBA Playbook (probably your personal one).
3. Choose **Personal** (vs Organization — Personal is fine for solo dev; you can upgrade later if needed).
4. Pay the $25 USD one-time registration fee.
5. Verify your identity (passport / driver's license — Google Wallet flow).
6. **Wait 24-48 hours** for Google's identity verification. You can keep working in the meantime; you just can't publish until verified.

**Verify:** the Play Console at <https://play.google.com/console/> shows your developer dashboard.

**What I do after:** nothing yet. We'll come back here in M8 to set up the Internal Testing track. For now, you just need the account active.

---

### B3. Create the Firebase project + Android app

**Why:** Firebase Cloud Messaging (FCM) is the only Android push transport (DECISIONS.md #052). Even if we don't ship push notifications in M0, the Firebase Android app needs to be registered so the `google-services.json` config file can land in `app/`.

**How:**
1. Visit <https://console.firebase.google.com/>.
2. **Add project** → name it **BOBA Playbook** → **Continue**.
3. **Enable Google Analytics** → **No** (we don't need it; less data-safety disclosure overhead).
4. After project creation, click **Add app** → choose **Android**.
5. Package name: **`com.bobaplaybook.app`** (exactly this — must match `applicationId` in `app/build.gradle.kts`).
6. App nickname: **BOBA Playbook (Android)**
7. Debug signing certificate SHA-1: paste the **SHA-1** you saved from B1.
8. **Register app** → **Download google-services.json**.
9. Save the downloaded `google-services.json` to `/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/android/app/google-services.json`.
10. Skip the SDK setup step — I've already wired the Gradle config.
11. Confirm the Firebase project shows the registered Android app.

**Verify:**
```sh
ls /Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/android/app/google-services.json
# should exist, ~3-5 KB
```

**What I do after:**
1. Uncomment the `alias(libs.plugins.google.services)` line in `android/app/build.gradle.kts`.
2. Uncomment the Firebase BOM + `firebase-messaging` dependencies in the same file.
3. Commit. M0 builds; FCM is now wired (we won't actually use it until M7).

**Firebase Spark (free) plan note:** we're staying on Spark for now (DECISIONS.md #052). Don't upgrade to Blaze unless I tell you we need Cloud Functions or Firebase Storage — none of which are planned for v1.

---

### B4. Configure Sign in with Google (OAuth 2.0 client ID)

**Why:** Credential Manager's `GetGoogleIdOption` requires a server-side OAuth 2.0 client ID. This is what tells Google "this app is allowed to request ID tokens."

**How:**
1. Visit <https://console.cloud.google.com/apis/credentials> — make sure the project selector at top shows your **BOBA Playbook** Firebase project (Firebase auto-creates a matching GCP project).
2. **Create credentials** → **OAuth client ID**.
3. Application type: **Web application** (yes, web — this is the **server-side** client ID that the Android Credential Manager uses, NOT an "Android" client).
4. Name: **BOBA Playbook Web (for Credential Manager)**.
5. Authorized redirect URIs: leave blank (Android doesn't need them).
6. **Create** → copy the **Client ID** (looks like `123456789-abcdef.apps.googleusercontent.com`).
7. Paste it to me.

**Verify:** the OAuth client appears in the credentials list with status **OK**.

**What I do after:** I add a `BuildConfig.GOOGLE_CLIENT_ID` field to `app/build.gradle.kts` referencing the value you paste, and the Sign in with Google flow has what it needs in M7.

You should ALSO create an Android-type OAuth client (Application type: Android, package name `com.bobaplaybook.app`, SHA-1 fingerprint from B1) so the Firebase / Supabase OAuth handoff works. Add it the same way; it doesn't need a separate Client ID I have to wire up — Firebase / Supabase just need to know it exists.

---

### B5. Supabase: wire the Android client

**Why:** the Supabase project handles auth + RLS data. Android needs the same URL + anon key the iOS app uses.

**How:**
1. Visit <https://supabase.com/dashboard> → select the BOBA Playbook project.
2. **Project Settings** → **API** → copy these two values:
   - **Project URL** (looks like `https://xxxxxxxxxxxx.supabase.co`)
   - **anon / public key** (the long `eyJ...` JWT — this is safe to bundle; it's gated by RLS)
3. Paste both to me. If you can't find the project (multiple Supabase projects), check `BOBAPlaybook/Networking/SupabaseClient.swift` — the URL is hardcoded there.

**What I do after:**
1. Replace `REPLACE_WITH_SUPABASE_URL` and `REPLACE_WITH_SUPABASE_ANON_KEY` in `android/core/network/src/main/java/com/bobaplaybook/core/network/SupabaseConfig.kt`.
2. Commit.

**Also:** in the Supabase dashboard, under **Authentication → URL Configuration**, add the Android OAuth callback URL: **`bobaplaybook://oauth/callback`**. The iOS callback is already registered; Android uses the same scheme on a different host (`oauth`). Tell me when that's done and I'll verify the dispatch wiring matches.

---

## Phase C — First build (~5 min once Phase A is complete)

### C1. Sync + build

**Why:** confirms the entire stack assembles. M0's deliverable is "the app launches and shows the BOBA wordmark on a black screen" — that proves theme + edge-to-edge + Compose + Hilt + the multi-module stack all wire up.

**How:**
1. Open `/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/android` in Android Studio.
2. Wait for Gradle sync.
3. Run ▶ on `app` against your Pixel emulator (or a connected device).

**Verify:**
- Splash screen with XOXO mark → fades to a near-black screen with "BOBA Playbook" in orange + the tagline "Search. Scan. Collect. Play." in muted grey beneath.
- No crash. No red errors in the **Run** window.

**What I do after:** if any errors come back, paste them and I'll fix them.

---

### C2. First commit + push

**Why:** lock the Android M0 work into the repo.

**How:**
```sh
cd /Users/bhwilkoff/Documents/GitHub/BOBA-Playbook
git add android/ .well-known/assetlinks.json _config.yml
git commit -m "Android M0 — Gradle scaffold + BobaTheme + primitives + asset sync"
git push origin main
```

I'll handle the commit if you say "commit M0" — I won't push without explicit authorization.

---

## Phase D — Things to do later (not blocking M0)

These don't block M0 but you'll hit them later:

- **Add Discord OAuth redirect to Discord application** — visit <https://discord.com/developers/applications>, find the BOBA Playbook OAuth app, add `bobaplaybook://oauth/callback` to redirect URIs. Same URI iOS uses.
- **eBay Browse API + Whatnot proxy** — no changes needed; the existing `boba-ebay-proxy` Worker accepts cross-platform Bearer JWT calls.
- **Play Integrity API** — defer to v2 when threat model justifies (DECISIONS.md §8.4).

---

## Phase E — First beta upload to Play Console

Once the M1+ code is on `main` and you can build/run the app from Android Studio, this phase puts a signed AAB on the Play Console Internal Testing track. ~3 hours of active work plus Google identity-verification wait.

### E1. Upload keystore credentials → GitHub Secrets

**Why:** the CI workflow signs release builds with your upload keystore. Without these secrets, `bundleRelease` produces an unsigned AAB that Play Console rejects.

**Prereq:** keystore at `~/.android/boba-upload.jks` (B1 above).

**How** — run from the repo root:
```sh
# Base64 the keystore so it round-trips through GH Secrets cleanly
KEYSTORE_B64=$(base64 -i ~/.android/boba-upload.jks | tr -d '\n')

# Set the secrets (gh CLI required — `brew install gh` if missing)
gh secret set UPLOAD_KEYSTORE_BASE64   --body "$KEYSTORE_B64"
gh secret set UPLOAD_KEYSTORE_PASSWORD --body "YOUR_KEYSTORE_PASSWORD"
gh secret set UPLOAD_KEY_PASSWORD      --body "YOUR_KEY_PASSWORD"

# Maps API key for the Find a Store map (same value as in
# android/local.properties)
gh secret set MAPS_API_KEY --body "AIzaSyBLWDpGY5K0fLaw8HI-2EaOVkKm5PxOZPc"
```

**What Claude does after:** if you paste the keystore + key passwords to me (or run the above and tell me you've done it), I'll verify the secrets exist + run a dry release-build locally to confirm signing wires up.

### E2. Create the Play service account → upload to secrets

**Why:** the CI job uses a service account to push the AAB to Play Console. The account needs **Release Manager** rights on the BOBA app.

**How:**
1. Visit <https://console.cloud.google.com/iam-admin/serviceaccounts> with the **boba-playbook-7f292** project selected.
2. **Create service account** — name "boba-play-uploader." Skip role grant in GCP; the Play side handles it.
3. After creation → ⋮ → **Manage keys** → **Add key → Create new key → JSON**. The JSON downloads.
4. Visit <https://play.google.com/console> → Setup → **API access** → **Link** to the GCP project → grant the new service account **Release manager** (or **Admin** for first run).
5. From the repo root:
   ```sh
   gh secret set PLAY_SERVICE_ACCOUNT_JSON < /path/to/downloaded.json
   ```

**Verify:** in Play Console → Users and permissions, the service account appears with the Release Manager role.

### E3. Listing assets (manual, Play Console UI)

These can't be automated — you upload via the browser. The first beta needs:

- **App icon** — 512×512 PNG, no alpha. The adaptive icon is already in `app/src/main/res/mipmap-anydpi-v26/`; rasterize at 512 with a non-alpha background. **Ask Claude to render this if needed.**
- **Feature graphic** — 1024×500. Required. Ask Claude to draft via the screenshot pipeline.
- **Phone screenshots** — 2 minimum, 8 max. 16:9 or 9:16, min 320px / max 3840px. Capture from emulator or device.
- **Short description** — ≤80 chars. Suggested: *"Search · Scan · Collect. The Bo Jackson Battle Arena companion app."*
- **Full description** — ≤4000 chars. **Ask Claude to draft** from existing iOS App Store copy.
- **Privacy policy URL** — `https://bobaplaybook.com/privacy` (already live).
- **Category** — Tools (or Entertainment).
- **Contact info** — your email; required.

### E4. Play Console required forms

In Play Console → Policy → App content:

- **Privacy Policy** — paste the URL.
- **App access** — *"All functionality is available without restrictions"* is false (Profile / Save deck / Designate need login). Provide a reviewer test account: create `reviewer+google@learningischange.com` in Supabase or share an existing tester account; paste the credentials in the form.
- **Ads** — *No ads*.
- **Content rating** — fill out IARC questionnaire. ~15 questions. Card game, no violence/gambling/profanity → likely PEGI 3 / ESRB Everyone. **Ask Claude for a draft answer set** that matches the BOBA content profile.
- **Target audience and content** — pick age range. 13+ is the safest for the card-game audience; "Designed for Families" requires the Families program enrollment which is more onerous.
- **News apps** — No.
- **COVID-19 contact tracing** — No.
- **Data Safety** — ~30 min. Declare:
    - **Personal info:** name (username), email, photos (avatar)
    - **App activity:** in-app interactions, in-app search history
    - **App info and performance:** crash logs (FCM passes through Firebase)
    - **Device IDs:** FCM registration token (when notifications ship)
    - Encryption in transit: **Yes**
    - Data deletion: **Yes — in-app** (account-delete Worker, DECISIONS.md #039)
    - Camera: declared but **not transmitted** (on-device OCR per DECISIONS.md #043)
    - **Ask Claude for the field-by-field walkthrough** to paste into the form.
- **Government apps** — No.
- **Financial features** — No.
- **Health** — No.

### E5. Push the first tagged release

The CI job uploads to **Internal Testing** when a `v*-android` tag lands.

```sh
# Bump versionCode + versionName for the first beta
# (Manual for now — auto-bump from Play Console latest-build is on the
# polish list; the CI pipeline reads the values out of build.gradle.kts.)
# In android/app/build.gradle.kts:
#   versionCode = 2          // or whatever increment
#   versionName = "0.2.0"    // first beta — pick a number you like

git commit -am "Android: bump to 0.2.0 for first beta"
git tag v0.2.0-android
git push origin main v0.2.0-android
```

CI then:
1. Decodes the keystore from `UPLOAD_KEYSTORE_BASE64`.
2. Runs `./gradlew :app:bundleRelease` with signing credentials in env.
3. Uploads the signed `app-release.aab` to the Internal Testing track.

**Verify:** Play Console → Testing → Internal testing → Releases shows version 0.2.0 with status `Completed`.

### E6. Add internal testers

In Play Console → Testing → Internal testing → **Testers** tab:

- Create a new tester list (or use an existing one).
- Add email addresses (Google accounts) of beta testers. Up to 100.
- Copy the **opt-in URL** — looks like `https://play.google.com/apps/internaltest/12345678901234567890`. Share that URL with your testers.

After a tester opts in and waits ~10 min for Play Console propagation, the BOBA Playbook app appears on the Play Store for them (looks identical to a production listing on their device).

### E7. Iterate

For each subsequent beta build:
- Bump `versionCode` + `versionName` in `android/app/build.gradle.kts`.
- Tag `v0.x.y-android` and push.
- CI uploads automatically. Internal Testing track gets staged updates within minutes.

**Promotion to Production:** Internal → Closed → Open → Production is a Play Console UI flow. The CI job currently uploads only to Internal. When you're ready to promote, edit the `.github/workflows/android-build.yml` `track:` value, or do the promotion manually in Play Console.

---

## Quick troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Gradle sync fails: "AGP version X is not compatible" | Catalog's AGP version doesn't match Android Studio's bundled Gradle | Paste the error to me; I bump `agp` in `gradle/libs.versions.toml` |
| Sync fails: "Plugin com.google.gms.google-services not found" | `google-services.json` is missing | Complete B3 — download and place the file |
| App crashes on launch: "HiltAndroidApp" missing | Hilt KSP didn't run | Right-click `app/` → **Refresh Gradle Project**; if it still fails, paste the logcat |
| Build fails: "Cannot find symbol BOBAWordmark" | `:core:ui` didn't compile | Build → Clean Project → Rebuild Project; paste compilation errors if it persists |
| App link doesn't open the app (opens the browser instead) | `assetlinks.json` still has REPLACE_WITH_… markers | Complete B1, paste me the fingerprints |
| Catalog renders empty (zero cards) | `sync_shared_assets.sh` didn't run | Run manually: `bash android/scripts/sync_shared_assets.sh` |

---

## Status

**Phase A — Local toolchain:** ✅ Android Studio + JDK + Gradle wrapper.
**Phase B — Google services:** ✅ keystore + SHA fingerprints (assetlinks.json populated) · ✅ Play Console developer account · ✅ Firebase project + `google-services.json` · ✅ Sign in with Google OAuth web client (`GOOGLE_WEB_CLIENT_ID` in build.gradle.kts) · ✅ Supabase URL + publishable key wired.
**Phase C — First build:** ✅ App boots + tabs render + Find/Decks/Collection/Purchase/Learn screens shipped.
**M0–M8 functional:** ✅ all five tabs functional · ✅ scan with ML Kit v2 bundled · ✅ Hilt + Credential Manager + supabase-kt auth · ✅ App Links verified · ✅ R8 release config.

**Phase E — Beta upload prerequisites:**
- ✅ Google Maps API key (Find a Store in-app map)
- ✅ Release signing config in build.gradle.kts (env / local.properties)
- ✅ CI `play-store-internal` job uncommented (tag-driven AAB upload)
- ⏳ GH Secrets: `UPLOAD_KEYSTORE_BASE64`, `UPLOAD_KEYSTORE_PASSWORD`, `UPLOAD_KEY_PASSWORD`, `MAPS_API_KEY` (E1)
- ⏳ Play service-account JSON + `PLAY_SERVICE_ACCOUNT_JSON` secret (E2)
- ⏳ Play Console listing assets (icon, feature graphic, screenshots, descriptions) (E3)
- ⏳ Data Safety + content rating + app-access forms (E4)
- ⏳ Tagged release `v0.2.0-android` (E5)
- ⏳ Internal testers added in Play Console (E6)
