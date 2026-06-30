# Cloud submission runbook — BOBA Playbook

How to ship BOBA Playbook to the **App Store** (iOS/iPadOS) and **Google Play**, built in the cloud.
This is the build/submit PIPELINE; listing copy lives in `APP_STORE_METADATA.md` /
`android/distribution/play-console-listing.md`, and `APP_STORE_RESUBMISSION.md` covers re-review.

> **Why cloud:** the dev Mac runs a *beta* macOS, so a local archive is rejected by App Review
> (**ITMS-90301**); Apple also keeps raising the Xcode floor (**ITMS-90111**). A GitHub-hosted
> **`macos-26`** runner (released macOS + Xcode 26.6) clears both, **free** for this public repo —
> the same pipeline Archive Watch uses, and a no-compute alternative to Xcode Cloud.

---

## Apple App Store (iOS) — DEFAULT

1. **Bump the version + push.** Edit `AppVersion.xcconfig` (`MARKETING_VERSION` +
   `CURRENT_PROJECT_VERSION` +1 — never via the Xcode identity panel), commit, push.
2. **Run the workflow:**
   ```
   gh workflow run appstore-build.yml -f platform=ios
   gh run watch $(gh run list --workflow=appstore-build.yml -L1 --json databaseId -q '.[0].databaseId')
   ```
   `.github/workflows/appstore-build.yml` (runner `macos-26`) selects Xcode 26.6, imports the signing
   `.p12`s from repo secrets into a temp keychain, and runs `tools/submit-appstore.sh ios` — archiving
   the **`BOBAPlaybook`** scheme, creating an App Store profile for `app.bobaplaybook.ios`, and
   uploading to App Store Connect.
3. **Finish in App Store Connect (web):** the build processes, then on the BOBA record → iOS platform →
   **select the build** → **Submit for Review**.

**Signing** is MANUAL via `.p12` secrets (cloud signing fails for this team's API key). They're shared
across the team's apps (team `L2G756LY8N`) and already set: `APPLE_DIST_P12`, `APPLE_INSTALLER_P12`,
`APPLE_P12_PASSWORD`, `APPLE_DIST_CERT_ID`, `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`. (This repo
also has an older ASC key `Y97R9U9WMG` at root for Xcode Cloud — the cloud workflow uses the shared
`G5549XF8RV` via secrets; both are valid for the team.) Re-seed with `tools/ci_make_signing_p12.py`.

Local `tools/submit-appstore.sh ios` works only on a released-macOS machine (ITMS-90301 on the beta box).

---

## Google Play

- **CI (existing, tag-gated → Internal Testing):** `.github/workflows/android-build.yml` builds the AAB
  and uploads to **internal** on a `v*-android` tag push (`r0adkll/upload-google-play`, `packageName:
  com.bobaplaybook.app`). Secrets: `UPLOAD_KEYSTORE_BASE64`, `UPLOAD_KEYSTORE_PASSWORD`,
  `UPLOAD_KEY_PASSWORD`, `MAPS_API_KEY`, `PLAY_SERVICE_ACCOUNT_JSON`. The Play upload is
  `continue-on-error` (Play Console API access is sometimes blocked); the signed AAB is always uploaded
  as a CI artifact for manual upload as a fallback (DECISIONS #043).
- **CLI (new, production-capable):** `tools/submit-play.sh [--track production|internal] [--notes "…"]`
  builds the release AAB and uploads via `tools/play-publish.py` (Play Developer API v3, the Archive
  Watch pathway). Needs the upload keystore in `~/.gradle/gradle.properties` and the service-account
  JSON at `~/.config/play/boba-play.json` (or `PLAY_SERVICE_ACCOUNT_JSON`). NOTE: this faces the same
  Play API-access limitation as the CI path — if it 403s, the CI-artifact fallback still applies.

---

## House rules that still apply
- Versions via `AppVersion.xcconfig` (iOS) / `android/app/build.gradle.kts` (Android), never the Xcode
  identity panel; bumping is step 5 of `feature-shipping-discipline`. iOS 26 baseline; no third-party
  Swift packages; the IOS27_SDK dual-SDK gate (DECISIONS #066) keeps it compiling on the 27 beta SDK too.
- The submission tooling is shared with Archive Watch — see its `apple-app-store-cli-submission` skill +
  `docs/macOS-DESIGN.md` §C for deep details.
