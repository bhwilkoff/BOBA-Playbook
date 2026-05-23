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
