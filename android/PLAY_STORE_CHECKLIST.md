# BOBA Playbook Android — Play Store Submission Checklist (M8)

When you're ready to push the first AAB to the **Internal Testing** track on Play Console, work through this list. Steps Claude can do are marked ✅; steps that require Ben in the Play Console UI are marked 👤.

---

## Phase 1 — Pre-flight (one-time, ~30 min)

| | Task | Where |
|---|---|---|
| ✅ | Confirm `applicationId = com.bobaplaybook.app` | `android/app/build.gradle.kts` |
| ✅ | Confirm `versionCode + versionName` bump policy | `android/app/build.gradle.kts` defaultConfig |
| ✅ | Confirm R8 + resource shrinker enabled for release | `android/app/build.gradle.kts` buildTypes.release |
| ✅ | Confirm `proguard-rules.pro` keeps Kotlinx Serialization + Hilt + ML Kit | `android/app/proguard-rules.pro` |
| ✅ | Confirm Firebase wiring + `google-services.json` committed | `android/app/google-services.json` |
| ✅ | Confirm `assetlinks.json` has BOTH cert fingerprints | `.well-known/assetlinks.json` |
| 👤 | Generate the signed release AAB | Android Studio → **Build → Generate Signed App Bundle** → keystore `~/.android/boba-upload.jks` |
| 👤 | Verify 16 KB page-size alignment | `apkanalyzer files list android/app/build/outputs/bundle/release/app-release.aab` — check all `.so` libs report 16384-aligned |

---

## Phase 2 — Play Console release setup (~1 hr)

| | Task | Where |
|---|---|---|
| 👤 | Open Play Console → BOBA Playbook → **Test and release → Latest releases and bundles** → **Create new release** | <https://play.google.com/console/u/2/developers/7973176709446146294/app/4974004192219343786/internal-testing> |
| 👤 | Upload `app-release.aab` to **Internal testing** track | Internal testing wizard |
| 👤 | Release notes (≤500 chars) — describe what beta testers will find | Internal testing → Releases |
| 👤 | Add testers — your email + 1-2 close beta testers | Internal testing → Testers tab |
| 👤 | Copy the opt-in URL Play Console generates → send to testers | Internal testing → Tester opt-in URL |
| 👤 | First-time main store listing — title, short + full description, screenshots, feature graphic, app icon | Grow → **Main store listing** |

---

## Phase 3 — Required content (~1 hr)

### Data safety form (per Play Console policy)
| | Item | Value |
|---|---|---|
| 👤 | Personal info collected | name (username), email (when signed in), photos (avatar upload) |
| 👤 | App activity | in-app interactions (collection, decks, scans) |
| 👤 | Device or other IDs | FCM token (used for push) |
| 👤 | Camera access | "Used only on-device for card recognition; no photos leave the device" (DECISIONS.md #012) |
| 👤 | Encryption in transit | Yes (TLS everywhere) |
| 👤 | Data deletion | Yes — `boba-account-delete` Worker per DECISIONS.md #039 |
| 👤 | SDK declarations | Firebase Cloud Messaging (auto-discloses via SDK Data Safety helper if enabled) |

### Content rating
| | Task | Where |
|---|---|---|
| 👤 | Complete the IARC questionnaire | Grow → **Content rating** |
| 👤 | Target audience: 13+ recommended (matches iOS App Store rating) | Same questionnaire |

### Privacy policy
| | Task | Where |
|---|---|---|
| ✅ | URL: <https://bobaplaybook.com/privacy/> (already live) | Existing |
| 👤 | Paste URL into **Privacy policy** field | Grow → App content → Privacy policy |

---

## Phase 4 — Launch preparation

| | Task | Where |
|---|---|---|
| 👤 | Get Play App Signing certificate SHA-256 (Google generates it on first AAB upload; should already be in `assetlinks.json`) | Test and release → keymanagement (direct URL) |
| 👤 | Verify App Links — open `https://bobaplaybook.com/card/RBF-72` on test device with the app installed; should open the app, not the browser | Manual smoke test on device |
| 👤 | Run cold-start macrobenchmark — confirm ≤ 800 ms on a Pixel 6 baseline | Android Studio → Run → `:baselineprofile` (M8 polish step) |
| 👤 | Verify the FCM device-token round trip works (M7 follow-up) | Manual test |

---

## Phase 5 — Open testing → Production

Only do this after the Internal testing track has shipped + you're satisfied with the build's stability.

| | Task | Where |
|---|---|---|
| 👤 | Promote Internal → Closed testing (gated email list) | Test and release → Closed testing |
| 👤 | Wait through Google's required testing window (currently 12 testers × 14 days for new developer accounts) | Patience |
| 👤 | Promote Closed → Open testing (public opt-in URL) | Test and release → Open testing |
| 👤 | Promote Open → Production with staged rollout (1% → 10% → 50% → 100%) | Test and release → Production |

---

## What Claude can do once you say "we're ready for M8"

- Bump versionCode + versionName in `app/build.gradle.kts`
- Write release notes from recent commit messages
- Help draft Play Store description + short description (4000 chars + 80 chars)
- Help write the data safety form responses based on the actual code paths
- Configure the GitHub Actions workflow to auto-upload AABs to Internal testing on `v*-android` tag push (the stub in `.github/workflows/android-build.yml` is ready; just needs the `PLAY_SERVICE_ACCOUNT_JSON` GitHub secret)
- Generate Baseline Profile if you set up the `:baselineprofile` module + run the generator once

For all of those, just say "draft M8 release notes" or "set up Play Store upload CI" and I'll do it.
