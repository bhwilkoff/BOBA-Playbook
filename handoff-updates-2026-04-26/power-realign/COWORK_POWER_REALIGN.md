# Power realignment audit

Built from OCR over the existing R2 thumbnails. The R2 art is the
ground truth for each card's printed power; the catalog metadata is
what the engine reads. Where they disagree, this patch sets the
catalog's `power` to match the print.

## Stats

- Total Hero records inspected:        **15,691**
- Catalog already correct:             **14,788**
- Mismatches (high-confidence, patched): **649**
- Mismatches (low-confidence, queued for review): **226**
- OCR returned no power (queued for review): **28**
- Confidence threshold for auto-patch:  `0.85`

## Power-delta histogram (patched rows only)

| Δ (ocr − catalog) | rows |
|---:|---:|
| -40 | 5 |
| -36 | 1 |
| -35 | 1 |
| -30 | 60 |
| -25 | 1 |
| -23 | 1 |
| -22 | 1 |
| -21 | 1 |
| -20 | 72 |
| -17 | 1 |
| -15 | 2 |
| -10 | 60 |
| -6 | 1 |
| -5 | 125 |
| -2 | 2 |
| +5 | 90 |
| +10 | 52 |
| +15 | 27 |
| +16 | 10 |
| +17 | 1 |
| +18 | 1 |
| +20 | 26 |
| +22 | 1 |
| +23 | 4 |
| +24 | 1 |
| +25 | 36 |
| +28 | 3 |
| +30 | 31 |
| +33 | 1 |
| +35 | 28 |
| +40 | 3 |

## Per-cardNumber-prefix counts (patched rows only)

| Prefix | rows |
|---|---:|
| MIX | 165 |
| RAD | 119 |
| BF | 59 |
| SBF | 53 |
| ABF | 27 |
| GLBF | 27 |
| GGL | 26 |
| BLBF | 25 |
| LOGO | 24 |
| CBF | 23 |
| IBF | 12 |
| PG | 10 |
| GBF | 9 |
| RBF | 9 |
| SL | 8 |
| FT | 5 |
| OBF | 5 |
| BFA | 4 |
| BGA | 4 |
| CHILL | 4 |
| CJ | 4 |
| MI | 4 |
| BBF | 3 |
| GRILL | 3 |
| FHA | 2 |
| 24 | 1 |
| ADPA | 1 |
| BBFA | 1 |
| BHBF | 1 |
| BL | 1 |

## Files

- `patch.json` — apply via `scripts/apply_power_realign.py`
  - md5: `3892f49545e894c12a1bc3d377ecb716`
- `needs_review.json` — low-confidence rows (OCR was uncertain) and
  rows where OCR couldn't extract a power at all. Operator to spot
  check or skip.

## Migration footprint

Power changes do not affect `bobaId` (the formula is
`cardNumber-hero-treatment-variation`). No R2 renames, no Supabase
row migration needed. Just a JSON field update applied to the
master + 4 downstream bundles.