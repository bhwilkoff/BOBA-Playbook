# Mirror — DO NOT EDIT in this directory

These files are byte-identical copies (or extracted-without-modification
slices) of code from the iOS app target. They are mirrored into the
SwiftPM package so the CLI can compile + ship the same recognition
algorithm the iOS scanner uses.

| Mirror file | Authoritative source |
|---|---|
| `Card.swift` | `BOBAPlaybook/Models/Card.swift` (copy) |
| `ScanMatching.swift` | `BOBAPlaybook/Views/Scan/ScanMatching.swift` (copy) |
| `ScannerTypes.swift` | extracted from `BOBAPlaybook/Views/Scan/CardScanner.swift` — the `ScanObservation` struct and `FeaturePrintIndex` class only, with `loadFromBundle()` replaced by `load(from:)` that takes an explicit file URL |

## Sync rule

When iOS scoring logic changes, run:

```sh
pipeline/recognition/sync_mirror.sh
```

That script copies the authoritative files over the mirror copies and
runs `git diff --no-index` to flag drift. CI runs this same script on
every push and fails if the mirror has drifted from source — so the
copies stay in lock-step with the iOS app.

## Why mirror instead of symlink or shared module

- A SwiftPM symlink to `BOBAPlaybook/Views/Scan/CardScanner.swift` would
  drag in `import UIKit` and `import AVFoundation` — both unavailable
  on macOS-only Vision builds.
- Refactoring the iOS app to extract a shared "ScannerCore" module is
  the long-term right answer but touches the live TestFlight target.
  Mirror-with-drift-check is the safer interim.
- Whenever the iOS scanner ships a scoring change, `sync_mirror.sh`
  surfaces the delta in the next CI run; we re-run mirror sync as a
  separate commit and ship the CLI update.
