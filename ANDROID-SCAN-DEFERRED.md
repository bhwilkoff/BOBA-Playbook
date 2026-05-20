# Android Scan — Deferred Pipeline Improvements

> Companion to [`DECISIONS.md`](./DECISIONS.md) #035 (iOS scan scoring) and #043 (Android scan v1 — CameraX + ML Kit OCR + hero veto, fingerprinting deferred). This document captures every scan-pipeline improvement that's intentionally deferred from v1, the rationale, and the work required to land each.
>
> Last updated 2026-05-19.

---

## What's already in v1 (no follow-up needed)

| Capability | Status | Notes |
|---|---|---|
| Single-card live OCR via CameraX 1.5 + ML Kit Text Recognition v2 (bundled Latin) | ✅ | DECISIONS.md #043 |
| Card-number regex `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)` | ✅ | Verbatim port of iOS DECISIONS.md #012 |
| Multi-signal scoring (cardNumber / hero / element / power / treatment) | ✅ | Port of iOS DECISIONS.md #035, commit `c5c88cb` |
| Hero-name veto for top-left-quadrant disambiguation | ✅ | Port of iOS DECISIONS.md #035, commit `c5c88cb` |
| Multi-frame stability gate (3-of-5 agreement before commit) | ✅ | **Better than iOS** — iOS commits per-frame. Commit `0d212ce` |
| Fuzzy hero matching (Levenshtein-bounded by name length) | ✅ | **Better than iOS** — iOS uses exact substring. Commit `cd67172` |
| Treatment text bonus (+0.2 when treatment label OCR'd) | ✅ | Commit `cd67172` |
| Live in-progress scoring feedback (`Scoring 2/3 · Maverick · 2.5`) | ✅ | **Better than iOS** — iOS shows nothing during scoring. Commit `72cccdd` |
| Confidence floor (1.4) + margin floor (0.3) gates | ✅ | Returns null on weak match → live UI keeps scanning |
| Per-tab destination routing (Find / Decks / Collection) | ✅ | `ScanCoordinator.onMatch(destination=…)` |
| Collection scan → designation prompt sheet | ✅ | `ScanDesignationSheet` — commit `bfe01d2` |

15 unit tests lock the scoring math.

---

## Deferred items

### 1. Image Fingerprint Matching (MediaPipe Image Embedder)

**Status:** DECISIONS.md #043 v2. Not in v1. Highest-value remaining improvement.

**Why deferred from v1:**
- Requires generating embedding vectors for all 17,974 cards. Per DECISIONS.md #011 the original card images don't live in git — they're on Ben's local machine. New pipeline step would download R2 thumbnails server-side, run MediaPipe Image Embedder per image, write a parallel `feature-prints-android.bin` artifact.
- Artifact size: ~17,974 × 512 floats × 4 bytes = **~36 MB**. Adding to APK bloats install. Better to bundle a "fingerprint download" first-launch UX or stream from R2.
- Per-frame MediaPipe inference adds ~50-150 ms latency on mid-range Android devices. Not a deal-breaker but the OCR+hero-veto path is already <100ms.
- The iOS-original OCR + hero-veto path shipped for months before iOS DECISIONS.md #035 added fingerprint as the primary key. Android's scan accuracy is currently in the same league; FP is the second-derivative improvement.

**What it would unlock:**
- Visual matching catches cards where OCR is blocked (sleeve glare, motion blur on the card-number area, top-loader fog, holographic battlefoils that scatter the OCR).
- Recovers from full OCR failure — even if the camera reads zero text, FP can identify the card from its art alone.

**Implementation plan:**

1. **Server-side embedding generation** (~1 day of work)
   - New `unified-cards/scripts/generate_android_fingerprints.py` that:
     - Loads each card's `/thumbs/` image from R2
     - Runs `mediapipe.tasks.vision.ImageEmbedder` against the standard `mobilenet_v3_small` model
     - Writes a packed binary: `[bobaId_length:u16, bobaId:utf8, embedding:512×f32]` per row
     - Sorted by bobaId for deterministic ordering
   - Targets ~36 MB output file (`feature-prints-android.bin`)
   - Upload to R2 alongside `cards.json`

2. **Android-side bundle delivery** (~2 days)
   - First-launch flow:
     - Check if local `feature-prints-android.bin` exists in app cache
     - If not, download from R2 with progress UI ("Downloading scan fingerprints — 36 MB, one-time")
     - Cache forever; bump version + re-download when catalog grows
   - Memory-map the file at app start (not load into heap)
   - Build an in-memory `Map<String, FloatArray>` lazily on first scan

3. **Per-frame FP inference** (~1 day)
   - `ScanFingerprintMatcher` Composable-scope object holds the MediaPipe `ImageEmbedder`
   - On each frame: convert `ImageProxy` → bitmap → embedding (512 floats)
   - Compute L2 distance to every catalog entry (~17k comparisons, <10ms on JIT)
   - Return top-30 candidates as `Map<String, Double>` keyed by bobaId, value = distance

4. **Scoring integration** (~1 day)
   - `ScanCardMatcher.match(tokens, fingerprints)` extends to accept an optional FP candidate set
   - New signal weights:
     - `+1.5` if FP nearest-neighbor matches this candidate
     - `+1.0` if FP top-3 contains this candidate
     - `+0.5` if FP top-10 contains this candidate
   - FP becomes the **primary** signal when OCR is sparse (no cardNumber + no hero); the OCR signals become refinement.
   - Confidence floor adjusts: with FP present, floor drops to 1.2 (FP-only commits at 1.5 → margin to lift the threshold).

5. **Tests** (~half day)
   - Mocked FP candidate set + tokens
   - Assert FP-only commits when OCR is empty
   - Assert OCR + FP agreement = high confidence
   - Assert FP disagreement with OCR doesn't override hero veto (FP is one signal among many)

**Total scope:** ~5 days of focused work plus the server-side image embedding which depends on Ben's local pipeline machine.

**Trigger:** when a real-world scan failure shows up that the OCR + hero-veto path can't solve. Until then the v1 pipeline is sufficient.

---

### 2. Multi-Card Grid Scan

**Status:** DECISIONS.md #043 v2. Not in v1.

**Why deferred:**
- Requires OpenCV-equivalent on Android (probably JNI / Android's `androidx.camera.core.ImageProcessor` + custom shaders OR a port of the iOS `GridCardDetector` logic to Kotlin).
- The use case (binder page scan, show layout scan) is iOS-specific UX so far; Android v1 ships single-card live as the canonical scan flow.
- Real-world Android usage data will show whether grid scan is a frequently-requested feature.

**Implementation plan:**

1. **Card-edge detection** (~3 days)
   - Port iOS `GridCardDetector` to Kotlin. Steps:
     - Convert frame to grayscale + adaptive threshold
     - Find contours with `androidx.camera.core` or a pure-Kotlin implementation (OpenCV is heavy; ~30 MB native lib).
     - Filter contours by area + aspect ratio (BoBA cards are 5:7)
     - Compute homography to rectify each detected card region
   - Alternative: ML Kit Object Detection v2 with custom card-trained model (better accuracy, model training is multi-week effort).

2. **Per-cell OCR** (~1 day)
   - For each detected card region:
     - Crop the rectified region
     - Run ML Kit Text Recognition v2 on it
     - Feed into `ScanCardMatcher` independently

3. **UI** (~2 days)
   - Multi-card preview overlay (8-12 detected cells per frame for a 3×3 or 4×3 binder page)
   - Per-cell match indicator (green checkmark / yellow scoring / red unmatched)
   - "Add all matched" bulk action button at bottom

**Total scope:** ~6 days plus model selection / training decision.

**Trigger:** explicit user request OR competitive parity push.

---

### 3. Hardware Card-Recognition (Pixel Visual Core / NPU)

**Status:** Future research item.

**Why not now:**
- Pixel-only hardware path
- Requires Pixel-specific NNAPI delegate code
- Marginal speed improvement over the bundled MLKit path on already-fast devices

**Trigger:** when a Pixel-flagship user complains about scan latency.

---

### 4. Server-Side Scan Verification

**Status:** Future research item.

**Why not now:**
- Adds a network round-trip per scan (latency, offline failure mode)
- Server would need to receive the captured image which conflicts with the "scan stays on device" privacy posture (DECISIONS.md #012)

**Trigger:** if abuse detection becomes important (e.g. someone scanning to inflate collection value for trade matchmaking).

---

### 5. Improved Card-Edge Detection for Single-Card Scan

**Status:** Optional enhancement.

**Why not now:**
- Current single-card flow trusts the user to center the card in the viewfinder
- Edge detection would let the user hold any framing
- Modest UX win; not critical

**Implementation plan:**
- Re-use the GridCardDetector card-edge code (Section 2)
- Apply to single-card scan: detect the largest card in frame, rectify, OCR
- Improves accuracy when the user holds the card at an angle

**Trigger:** when card-rectification becomes the bottleneck for accuracy.

---

## Pipeline regression-test data

When we eventually wire FP or multi-card scan, the per-frame test cases below should pass without regression:

| Test scenario | v1 behavior | Future expected |
|---|---|---|
| BHBF-37 JacHammer, OCR catches hero only | Commits JacHammer via hero top-left at 1.5 | Same |
| BHBF-37 JacHammer, OCR catches "20" only (partial) | Returns null (hero veto blocks Tigre) | Commits JacHammer via FP |
| Base-set Maverick (cardNumber=1), OCR catches hero + element + power | Commits Maverick at 2.3 (above 1.4 floor, clear margin over LeBoss) | Same |
| MAVERIK (OCR typo) | Fuzzy hero match recovers | Same |
| Empty OCR + card in clear view | Returns null | Commits via FP nearest-neighbor |
| Card in sleeve glare, no OCR text | Returns null | Commits via FP nearest-neighbor |
| Two cards visible, both heroes named | Returns null (margin gate blocks ambiguity) | Same OR multi-card scan handles |

---

## Cross-references

- **DECISIONS.md #012** — iOS scan-mode (Vision + on-device, no upload)
- **DECISIONS.md #035** — iOS multi-signal scoring + hero veto (the source for the Android port)
- **DECISIONS.md #043** — Android scan v1: CameraX + ML Kit OCR; image fingerprinting deferred
- **ANDROID-DESIGN.md §6.5** — scan as cross-cutting capability, per-tab destination routing
- **ANDROID-DEV.md §6.1–§6.5** — CameraX + MLKitAnalyzer pipeline reference
