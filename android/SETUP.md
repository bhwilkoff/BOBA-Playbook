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

### A1. Install Android Studio

**Why:** the only practical way to build/run/debug Android. Gradle wrapper, AGP plugin, emulator, ADB, the Layout Inspector — all bundled. The wrapper auto-generates on first project open.

**How:**
1. Download **Android Studio Otter (2024.x stable)** or whatever current stable is from <https://developer.android.com/studio>.
2. Drag to `/Applications/` and launch.
3. First-launch wizard: accept the default install (includes Android SDK Platform-Tools, Build-Tools, an emulator image).
4. When asked about JDK: Android Studio ships its own bundled JDK 17 — accept the bundled one.
5. Once at the welcome screen, **don't open the project yet** — finish A2 first.

**Verify:**
```sh
ls /Applications/Android\ Studio*.app    # should exist
ls ~/Library/Android/sdk                  # SDK should be here
```

**What I do after:** nothing — this is purely local.

---

### A2. Install command-line tools

**Why:** lets me run `./gradlew sync`, `gradle wrapper`, and `keytool` from my session if you ever want me to validate the build.

**How:**
```sh
# Adopted from Homebrew
brew install --cask android-platform-tools

# Add Android Studio's bundled JDK to your PATH (replace 'Otter' if a newer
# Android Studio is current):
echo 'export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"' >> ~/.zshrc
echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Verify:**
```sh
java -version       # should print openjdk 17.x or 21.x
adb --version       # should print Android Debug Bridge version
keytool -h          # should print keytool usage (uses Java's keytool)
```

**What I do after:** once Java is on your PATH, I can run `./gradlew` myself and validate builds without bouncing back to you.

---

### A3. Open the project + sync

**Why:** generates the Gradle wrapper (`gradlew`, `gradle-wrapper.jar`, `gradle-wrapper.properties`) which the rest of the workflow depends on.

**How:**
1. Launch Android Studio → **Open** → navigate to `/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook/android` → **Open**.
2. Android Studio prompts: "Gradle wrapper not found. Generate?" → **Yes** (or it'll auto-generate silently).
3. Wait for Gradle sync to complete (~3-5 min first time — it's downloading every dependency in the version catalog).
4. If sync fails with a version-conflict error (it might — AGP 8.7 / Kotlin 2.0.21 are pinned but the version catalog may need a small bump): note the error, paste it to me, and I'll bump the relevant versions in `gradle/libs.versions.toml`.

**Verify:**
- Bottom-right of Android Studio shows "Gradle build finished" without red errors.
- The "Build" tool window has no compilation errors.
- `android/gradle/wrapper/gradle-wrapper.properties` now exists.

**What I do after:** I can run gradle locally now. If you paste me any sync error, I fix the version catalog and re-trigger.

---

### A4. Create an emulator + Chromebook profile (optional but useful)

**Why:** lets you run the app on a virtual Pixel for compact-width testing, and on a virtual Chromebook for expanded-width / desktop-windowing testing (per DECISIONS.md #047, Chromebook support is a v1 priority).

**How:**
1. **Tools → Device Manager** → **Create Device**
2. Pick **Pixel 8** (or any modern phone) → next → choose an Android 15 (API 35) system image → **Finish**.
3. Repeat with **Tablet → Pixel Tablet** for tablet adaptation testing.
4. For Chromebook simulation, run the app in Resizable mode (Android Studio Otter's "Resizable" emulator profile) — that's the closest local-emulator option for Chromebook layout testing.

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

These don't block M0 but you'll hit them in M7-M8:

- **Add Discord OAuth redirect to Discord application** — visit <https://discord.com/developers/applications>, find the BOBA Playbook OAuth app, add `bobaplaybook://oauth/callback` to redirect URIs. The same URI iOS uses works on Android (custom-scheme deep links route via Intent).
- **eBay Browse API + Whatnot proxy** — no changes needed; the existing `boba-ebay-proxy` Worker accepts cross-platform Bearer JWT calls.
- **Play Integrity API** — defer to M7+ when threat model justifies.
- **Beta tester invitations** — set up after M8 internal testing track lands.

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

- ✅ Project scaffold + Gradle build files + version catalog (this commit)
- ✅ BobaTheme + 5 primitive Composables + Type/Color/Shape tokens
- ✅ Two-phase catalog loader (CardCatalogLoader + CardRepository)
- ✅ Cloudflare R2 CDN helpers + Worker config (URLs)
- ✅ Shared asset sync (cards-slim.json + categories.json + fonts) committed
- ✅ AndroidManifest with App Links + custom-scheme deep links
- ✅ Adaptive launcher icon (XOXO mark + monochrome variant)
- ✅ Splash screen via Android 12+ API
- ✅ Edge-to-edge + predictive back enabled
- ✅ `.well-known/assetlinks.json` placeholder added to web root
- ✅ `_config.yml` updated to exclude `android/` from Jekyll Pages build
- ⏳ Gradle wrapper (Android Studio generates on first open — A3 above)
- ⏳ `google-services.json` (B3)
- ⏳ Upload keystore + SHA fingerprints (B1)
- ⏳ Sign in with Google OAuth client ID (B4)
- ⏳ Supabase config values (B5)
