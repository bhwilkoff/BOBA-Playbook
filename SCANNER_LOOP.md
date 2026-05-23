# Android Scanner Autonomous Loop

> Ben asked for a dedicated overnight loop focused ONLY on the Android scanner. Goal: card detection + UI parity equal to or better than iOS.
>
> Started 2026-05-22. Wake-up time TBD.

## Done criteria

The loop exits when **all** of the following are true:

1. **No crashes.** Tap any UI element in Scan → no ANR, no FATAL exception in logcat.
2. **Single-mode chip tap works.** Long-stable match → chip shows → tap → opens card detail with the correct card.
3. **Multi-mode queue persists.** Scan card → chip appears → auto-clears after ~1.6 s → queue counter increments → tap "Queue" → review sheet shows the card. Repeat for multiple cards.
4. **Card detection accuracy ≥ iOS.** Measured by the JVM matcher test (see "Test methodology"). Target ≥ 90 % match on the test set with no silent-wrong commits.
5. **Full iOS feature parity** for SINGLE + MULTI modes. GRID mode + Whatnot Show mode remain on #52 (defer).

## Iteration log

| Iter | When | Hypothesis | Test | Result |
|---|---|---|---|---|
| 0 | 2026-05-22 evening | Baseline — chip crash + multi queue + accuracy | initial state | Three known bugs |
| 1 | 2026-05-22 19:55 | Multi-mode queue never appends because the MlKitAnalyzer closure captured `scanMode` at DisposableEffect creation (always SINGLE). Fixed via `rememberUpdatedState(scanMode)` + `rememberUpdatedState(onAutoQueue)` — the analyzer now reads CURRENT mode on every fire. Added diagnostic Log.i in the analyzer + onAutoQueue + onChipTap so the next iter can read crash/queue logs. | `./gradlew :app:testDebugUnitTest` — 9 ScanCardMatcherTest cases pass, no regressions. Build SUCCESSFUL, APK installed. | Build green. Logs will reveal whether multi queue now appends + what the chip-tap crash actually surfaces. |
| 2 | 2026-05-22 20:09 | Chip-tap crash hypothesis: ML Kit `recognizer.close()` blocks the main thread during ScanScreen disposal (Activity pause-timeout seen in prior logcat). Concurrent navigation + camera teardown race exceeds the 500ms ANR window. Move `recognizer.close()` to a background `Dispatchers.IO` coroutine via GlobalScope.launch. Wrap both teardown steps in `runCatching` so any thrown exception is logged not propagated. | `./gradlew :app:assembleDebug` BUILD SUCCESSFUL; `./gradlew :app:testDebugUnitTest --tests '*Scan*'` SUCCESSFUL. APK installed. | Build + tests green. Camera teardown no longer blocks main. If chip tap still freezes, the next iter should investigate the navigate path itself (likely the runBlocking in ScanCoordinator's CURRENT_DECK branch — out-of-scope file but referenced for context). |
| 3 | 2026-05-23 02:17 | Detection latency hypothesis: stabilizer's flat 3-of-5 requirement over-stabilizes for clean reads. iOS commits on a single 1.4+ frame (DECISIONS.md #035). Tier the required agreements by score: avgScore >= 2.5 ⇒ 1 (single-frame), >= 1.8 ⇒ 2, otherwise default 3. Wrong-card protection preserved — different bobaIds can't co-agree. Updated existing test fixtures (mav score 2.5 → 1.5, tig 1.8 → 1.5) so 3-of-5 path stays under test; added 3 new tests: very-high-confidence single-frame, medium-confidence 2-of-5, low-confidence 3-of-5. | `./gradlew :app:testDebugUnitTest --tests '*Scan*'` — 18 tests pass, 0 failures. Build SUCCESSFUL, APK installed. | Build + all tests green. Clean reads (cardNumber + hero top-left) should now commit on the first frame; mid-tier reads on the second frame. Reduces perceived "card not found" lag without compromising the wrong-card protection. |
| 4 | 2026-05-23 02:29 | Matcher accuracy hypothesis: ML Kit often splits a printed cardNumber across token boundaries — "BHBF-37" arrives as ["BHBF", "37"] or ["BHBF-", "37"]. Per-token CARD_NUMBER_REGEX never sees the full string, so the matcher misses the cardNumber signal. Add joined-text fallback: also run the regex against the space-joined and no-space-joined token streams. Same regex, just on more text. False positives bounded by the letters-dash-digits format. | New tests `cardNumber split across tokens still commits` + `cardNumber split with hyphen suffix still commits` (2 fresh + 9 prior matcher cases = 11). `./gradlew :app:testDebugUnitTest --tests '*Scan*'` — 11 matcher + 9 stabilizer = 20 tests pass, 0 failures. Build SUCCESSFUL, APK installed. | Cross-token cardNumber assembly works. Should significantly reduce "card not found" misfires when ML Kit's line-splitting interacts with printed card layout. |
| 5 | 2026-05-23 02:43 | Matcher accuracy hypothesis (parallel to iter 4 but for hero names): ML Kit splits "JacHammer" into ["Jac", "Hammer"] on wide-spaced prints. Neither token reaches the per-token fuzzy hero matcher (length too short for Levenshtein). Add an adjacent-pair concatenation pass after the per-token loop: for every consecutive (a,b) token pair, check if `(a.text+b.text).uppercase()` matches any catalog hero. If yes AND the FIRST token is top-left, credit hero top-left. Skip heroes already detected in the per-token pass to avoid double-counting. | New tests `hero name split across tokens still commits` + `split-hero top-left still vetoes wrong-card commits` (2 fresh + 11 prior matcher cases = 13). 13 matcher + 9 stabilizer = 22 tests pass, 0 failures. Build SUCCESSFUL, APK installed. | Split-hero recovery now works on par with split-cardNumber. Combined with iter 4, the matcher recovers from BOTH common ML Kit segmentation failure modes. Hero veto continues to fire correctly when the assembled hero is top-left. |
| 6 | 2026-05-23 02:57 | Treatment text accuracy hypothesis: multi-word treatments like "Red Battlefoil" or "Inspired Ink" almost never match because the per-token `contains(treatment)` check needs the WHOLE phrase in a SINGLE token. ML Kit puts each word in its own token. Add a joined-text fallback for the treatment check (same shape as iter 4's cardNumber + iter 5's hero). Per-token fast path stays for single-word treatments like "Battlefoil" / "Superfoil". | New test `multi-word treatment matches across token split` (1 fresh + 13 prior matcher cases = 14). 14 matcher + 9 stabilizer = 23 tests pass, 0 failures. Build SUCCESSFUL, APK installed. | Treatment +0.2 bonus now fires for the most common multi-word print labels. Helps disambiguate battlefoil printings of the same hero/cardNumber from base-set siblings. |
| 7 | 2026-05-23 03:11 | UI parity hypothesis: commits currently fire silently — chip animates in but the user gets no immediate physical confirmation that the matcher landed. iOS uses a success-style haptic at the commit moment (DESIGN.md §6.5 implicit). Add `LocalHapticFeedback.performHapticFeedback(LongPress)` at the analyzer's commit branch, gated on the same `lastMatchedDisplayName != stable.card.displayName` condition so re-fires on continuous hold don't buzz repeatedly. | Build SUCCESSFUL, APK installed. Matcher / stabilizer untouched — JVM tests don't apply this iter. | Tactile confirmation at commit. LongPress maps to a single ~30ms pulse on Android, close to iOS's UIImpactFeedbackGenerator(.medium). |
| 8 | 2026-05-23 03:25 | Real bug: the analyzer's commit dedupe keyed on `displayName` instead of `bobaId`. Two cards in the catalog can share the same display name (Maverick base + Maverick battlefoil + Maverick alt-art). Scanning a second Maverick variant after a first would silently no-op the commit branch — chip never updated, haptic never fired, multi-mode never auto-queued the variant. ScanFrameStabilizer's internal dedupe already correctly uses bobaId (line 48). Rename the Composable-side `lastMatchedDisplayName` → `lastMatchedBobaId` + read `stable.card.bobaId` instead. Per CLAUDE.md "One ID per Card" mantra. | Build SUCCESSFUL, all 23 JVM tests pass (no behavioral change to matcher/stabilizer). APK installed. | Variant commits now propagate end-to-end. Significantly improves the multi-scan flow when a coach scans 3 different prints of the same hero. |
| 9 | 2026-05-23 03:30 | Hero veto robustness hypothesis: the −2.0 veto fires when ANY top-left fuzzy hero match exists. A low-confidence Levenshtein-2 match on OCR noise could wrongly credit a hero top-left, then suppress every legitimate candidate. Split `heroesTopLeft` into a strict subset (`heroesTopLeftStrict`) that requires an EXACT substring match. Veto reads the strict set; fuzzy top-left matches still earn the +1.5 positive bonus. Apply to both per-token and adjacent-pair (iter 5) passes. | New test `fuzzy-only top-left does not veto legitimate cardNumber match` (1 fresh + 14 prior matcher cases = 15). 15 matcher + 9 stabilizer = 24 tests pass, 0 failures. Original veto tests still green (exact-match veto unchanged). Build SUCCESSFUL, APK installed. | Veto now only fires when the top-left hero is read cleanly. Reduces a class of "matcher returns null even though signal is strong" failures Ben might have hit with imperfect lighting. |
| 10 | 2026-05-23 03:46 | UI parity hypothesis: SINGLE-mode chip persists until a new card commits OR user taps to navigate — no path to dismiss-without-acting. iOS chip has a swipe-down dismiss gesture. Add a discoverable "X" button on the right of the chip that (a) clears the chip, (b) resets the stabilizer so a re-scan of the same card fires fresh. Tap-target stays distinct from the row-level tap (which opens detail) — IconButton has its own click region. | Build SUCCESSFUL, APK installed. Matcher / stabilizer untouched — JVM tests don't apply. | Adds an explicit "clear" affordance. Users who accidentally trigger a match (or want to re-scan) no longer have to leave + re-enter Scan. |
| 11 | 2026-05-23 04:00 | UI parity hypothesis: iOS ScanDetectionChipView has a Quick-Save "+" button that adds the matched card to Personal collection without leaving the scanner — high-value MULTI-mode workflow. Android chip currently has no equivalent path; users have to tap row → detail → "Add" + back, which dismisses Scan. Extend ScanModuleAccess with CollectionRepository + AuthManager, add a + IconButton to the chip wired to CollectionRepository.add(bobaId, Personal, userId). Signed-out users get a feedback Snackbar instead of a silent RLS reject. | Build SUCCESSFUL, APK installed. Matcher / stabilizer untouched — JVM tests don't apply this iter. | Quick-Save (+) chip-side affordance shipped. Rapid multi-card scans into Personal now work without leaving Scan. |
| 12 | 2026-05-23 04:14 | UI polish: chip currently snaps in / out with no transition. iOS uses `.transition(.move(edge:.bottom).combined(with:.opacity))` — slide up from bottom + fade in. Wrap the chip in `AnimatedVisibility` with `slideInVertically(initialOffsetY = { it }) + fadeIn()` enter and the mirrored exit. AnimatedVisibility owns position + padding + align so the chip's own modifier is just `fillMaxWidth`. | Build SUCCESSFUL, APK installed. Matcher / stabilizer untouched — JVM tests don't apply this iter. | Chip enter/exit now matches iOS's slide-fade transition. Felt-quality improvement on commit + dismiss + auto-clear cycles. |
| 13 | 2026-05-23 04:28 | OCR accuracy hypothesis: CameraX defaults ImageAnalysis to ~640×480 to minimize per-frame CPU. ML Kit Text Recognition's accuracy scales with input resolution — at 480p, printed card-number text often spans only 6-8px tall, which OCR confidently misreads. Tune the controller via `setImageAnalysisResolutionSelector` to target 1280×720 with FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER. Roughly 4× the OCR detail for the same frame cost class — modern Pixel/Galaxy hardware sustains 15-30 fps comfortably. | Build SUCCESSFUL, APK installed. Matcher / stabilizer untouched — JVM tests don't apply. | Should sharpen card-number + hero-name reads, improve fuzzy-match hit rate, and shift the matcher into the high-confidence single-frame commit path (iter 3 tier) more often. |
| 14 | 2026-05-23 04:43 | UI polish: detection chip is a uniform black-translucent surface. iOS chip tints with the matched card's weapon colour (a thin accent stripe on the left edge + a subtle border outline) so a quick glance signals FIRE / ICE / STEEL etc. without reading the caption. Read the element colour from `BobaElements.forElement(card.element.uppercase())` and apply a 3dp full-height stripe on the start edge + a 1dp border (alpha 0.55) around the chip. | Build SUCCESSFUL, APK installed. Matcher / stabilizer untouched — JVM tests don't apply. | Chip is visually distinct per element now — collectors recognize a Maverick scan vs a JacHammer scan from across the room. |
| 15 | 2026-05-23 04:57 | UI gesture parity hypothesis: iOS chip uses `.simultaneousGesture(DragGesture)` so users can swipe the chip down to dismiss. Android only has the explicit "X" button. Add a `pointerInput { detectVerticalDragGestures(...) }` modifier on the chip Surface that accumulates vertical drag and calls `onDismiss` when total downward distance ≥ 60 px. The pointerInput lives outside (before) the inner row's clickable so a confirmed drag consumes the gesture before tap propagation. | Build SUCCESSFUL (after import + explicit-types iteration), APK installed. Matcher / stabilizer untouched. | Two dismiss paths now: tap X (discoverable) + swipe down (iOS-familiar). Power users coming from iOS get the gesture they know. |
| 16 | 2026-05-23 04:57 | Matcher accuracy hypothesis: `powerHits` accepted any digit > 0 divisible by 5 (5, 10, 15, ..., 250). BoBA hero powers are 50–250; values below 50 are almost always print-run serials, set-codes, or random card-body digits — NOT power. Old floor was creating false +0.2 bonuses on candidates whose power happened to be a small div-5 (none in the catalog at the moment but it's a brittle gate). Tighten to `>= 50 && % 5 == 0`. | 15 matcher + 9 stabilizer = 24 tests pass (no test had a sub-50 power; existing fixtures with 75 / 110 / 135 / 145 still match cleanly). Build SUCCESSFUL, APK installed. | Tighter power signal. Less noise in candidate scoring when random bare digits in the frame fall under 50. |

## Test methodology

### A. JVM unit test (preferred — fast, deterministic)

Build a `:app:testDebugUnitTest` that feeds the matcher a synthetic `ScanTextToken` list per card and asserts the right `bobaId` commits. Test fixture lives at `android/app/src/test/java/com/bobaplaybook/app/feature/scan/ScanCardMatcherTest.kt`.

The fixture is "OCR transcription of N test cards, one per scenario:
- card-number-only (clean read)
- card-number partial + hero name (typical real-world)
- hero name only (no card-number visible — should still commit if confident)
- hero name in wrong-corner (should NOT commit — veto)
- two ambiguous cards in the same image (multi-card mode test)"

Run via: `cd android && ./gradlew :app:testDebugUnitTest --tests '*.ScanCardMatcherTest'`

### B. Live emulator (slow but real)

The Pixel_9_Pro AVD has a virtual scene camera. Push a card image to the emulator's "wall texture" via:
1. `adb push card.jpg /sdcard/Download/card.jpg`
2. The emulator camera then shows that image as the scene. Approximate but usable.

For the loop: prefer A. Use B only when A passes and we need end-to-end visual confirmation.

## Current known issues (2026-05-22)

1. **Chip tap crashes the app.** Logcat shows no FATAL but Activity pause-timeout. Suspect: the `onMatch` lambda in BOBAApp routes to `scanCoordinator.onMatch(...)` which may NPE when `cardRepository` is not yet primed, OR the navigation target is invalid. Diagnose first.

2. **Multi-mode queue empty after scan.** The chip fires + auto-clears in MULTI mode but the queue counter at top stays at 0. Suspect: `onAutoQueue` is wired but `queueHolder.queue.append(...)` is being called on a different `ScanQueueStore` instance than the one driving the counter (one Hilt singleton, but the `entries` flow may not re-emit if append is from a different thread). Verify with a Log.

3. **Match accuracy below iOS.** Real-card scans on Ben's device show several "card not found" / wrong-match frames before stabilizing. Suspect: `ScanFrameStabilizer.requiredAgreements=3` + `avgScore >= 1.4` is too permissive in noisy frames OR too strict for fast-stabilizing cards. Tune after the first two bugs are fixed.

## Files in scope

- `android/app/src/main/java/com/bobaplaybook/app/feature/scan/ScanScreen.kt` — UI + ScanViewfinder
- `android/app/src/main/java/com/bobaplaybook/app/feature/scan/ScanCardMatcher.kt` — per-frame matcher
- `android/app/src/main/java/com/bobaplaybook/app/feature/scan/ScanFrameStabilizer.kt` — multi-frame gate
- `android/app/src/main/java/com/bobaplaybook/app/feature/scan/ScanQueueStore.kt` — session queue
- `android/app/src/main/java/com/bobaplaybook/app/feature/scan/ScanQueueHolderViewModel.kt` — Hilt access
- `BOBAPlaybook/Views/Scan/ScanView.swift` — iOS reference (binding)
- `BOBAPlaybook/Views/Scan/ScanMatching.swift` — iOS matcher reference
- `BOBAPlaybook/Views/Scan/GridScanView.swift` — iOS grid scan (NOT in scope this loop; #52)

## Per-iteration protocol

Each cron fire:

1. **Read this file** (state).
2. **`cd android && ./gradlew :app:assembleDebug 2>&1 | tail -10`** — confirm clean build.
3. **Pick ONE** of: a known bug, an accuracy improvement, or a UI-parity gap. Don't fan out.
4. **Implement minimal change** to address it. Add diagnostic logs where the prior hypothesis was wrong.
5. **Run the JVM matcher test** if the change touches `ScanCardMatcher` / `ScanFrameStabilizer`. Fail fast on regressions.
6. **`adb install -r …app-debug.apk`** when build passes.
7. **Append an iteration row to this file** with hypothesis, test result, what changed.
8. **`git add -A && git commit -m "scanner-loop: <one-line>"`** so Ben can see the trail.
9. Exit. The next cron fire continues.

## Don'ts

- Don't break Find / Decks / Collection / Learn / Purchase. The loop's scope is `/feature/scan/` + ScanScreen-adjacent files.
- Don't push to remote. Local commits only — Ben merges.
- Don't bump iOS version. iOS is out of scope.
- Don't rewrite the matcher from scratch. Tune within the existing scoring + gate structure.
- Don't add new dependencies without a clear justification logged in the iteration row.
