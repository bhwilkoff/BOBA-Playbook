# CardRecognitionCLI

macOS Swift package that runs the iOS scanner's recognition pipeline against still-image candidates from the pipeline staging queue. Designed to run on a `macos-15` GitHub Actions runner.

This is **Stage B** of the automated image-sourcing pipeline — see [`pipeline/README.md`](../../README.md) for the full architecture context.

## Build

```sh
cd pipeline/recognition/CardRecognitionCLI
swift build -c release
```

The release binary lands at `.build/release/cardreckon`.

## Run

```sh
./.build/release/cardreckon \
    --cards-json     ../../../BOBAPlaybook/display-cards.json \
    --feature-prints ../../../BOBAPlaybook/feature-prints.bin \
    --input          /tmp/candidates.jsonl \
    --output         /tmp/results.jsonl
```

`--input` and `--output` default to stdin / stdout if omitted.

## I/O contract

**Input** (one JSON per line):
```json
{"id": "any-string-id", "image_path": "/abs/or/rel/path-to-image.jpg"}
```

**Output** (one JSON per line):
```json
{
  "id": "any-string-id",
  "recognized_boba_id": "A-100-Maverick--",
  "score": 1.85,
  "margin": 0.40,
  "top_candidates": [
    {"boba_id": "A-100-Maverick--",            "score": 1.85, "normalized": 1.0},
    {"boba_id": "A-100-Maverick-Battlefoil-",  "score": 1.45, "normalized": 0.78}
  ],
  "ocr": {
    "card_number_hint": "A-100",
    "raw_name": "MAVERICK",
    "full_text": "MAVERICK A-100 BATTLE 320 FIRE..."
  },
  "error": null
}
```

`recognized_boba_id` is `null` when ScanMatching's confidence floor (1.4) or hero-margin floor (0.3) reject the top candidate. The Python wrapper interprets `null` + `score < 0.7` as QUARANTINE; null + score ≥ 0.7 as REVIEW; non-null + score ≥ 0.95 as AUTO. Thresholds calibrated in pipeline Phase 4.

`error` is non-null on per-candidate failures (image won't load, etc.). The line stays valid JSON so the Python wrapper can stream-parse without try/except scaffolding.

## Source layout

```
Sources/CardRecognitionCLI/
├── CardRecognitionCLI.swift   # @main entry, JSONL I/O, orchestration
├── VisionOCR.swift            # still-image OCR adapter (no AVFoundation)
└── Mirror/                    # byte-identical mirror of iOS sources
    ├── _MIRROR.md             # sync rule + drift tooling
    ├── Card.swift             # ← BOBAPlaybook/Models/Card.swift
    ├── ScanMatching.swift     # ← BOBAPlaybook/Views/Scan/ScanMatching.swift
    └── ScannerTypes.swift     # extracted ScanObservation + FeaturePrintIndex
                               # from CardScanner.swift, w/ load(from:) instead
                               # of loadFromBundle() — manually maintained
```

## Drift sync

Whenever iOS scoring logic changes:

```sh
pipeline/recognition/sync_mirror.sh           # update mirror in place
pipeline/recognition/sync_mirror.sh --check   # CI-mode (nonzero on drift)
pipeline/recognition/sync_mirror.sh --diff    # show drift without copying
```

`Card.swift` and `ScanMatching.swift` are byte-checked. `ScannerTypes.swift` is intentionally diverged (file-path init replaces bundle init) and isn't checked — `swift build` catches real API changes.

## Performance

On a `macos-15` runner with M-series silicon:

- Catalog load (~12 K cards as JSON): ~150 ms
- Feature-prints load (12.7 MB BFPI v2): ~80 ms
- Per-candidate processing (Vision OCR + FP search + ScanMatching):
  - ~250 ms first call (Vision warm-up + Neural Engine spin-up)
  - ~80–120 ms steady state
  
At ~100 ms/card, 500 candidates fit in ~50 sec — well under the 6 h job timeout. A single Stage B run can comfortably handle 5,000+ candidates without sharding; matrix-shard only if backlogs spike.

## Local testing without a macOS runner

You can build + run on your own Mac (as a sanity check before pushing to CI):

```sh
swift build -c release
echo '{"id":"smoke","image_path":"path/to/some/cropped/card.jpg"}' \
    | ./.build/release/cardreckon \
        --cards-json ../../../BOBAPlaybook/display-cards.json \
        --feature-prints ../../../BOBAPlaybook/feature-prints.bin
```

The output line is the recognition result. If `recognized_boba_id` matches what the iOS scanner would have picked, the parity is confirmed.
