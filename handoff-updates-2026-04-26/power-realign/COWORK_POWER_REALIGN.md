# Power realignment audit

Built from OCR over the existing R2 thumbnails. The R2 art is the
ground truth for each card's printed power; the catalog metadata is
what the engine reads. Where they disagree, this patch sets the
catalog's `power` to match the print.

## Stats

- Total Hero records inspected:        **15,691**
- Catalog already correct:             **14,788**
- Mismatches (high-confidence, patched): **572**
- Mismatches (low-confidence, queued for review): **303**
- OCR returned no power (queued for review): **28**
- Confidence threshold for auto-patch:  `0.85`

## Power-delta histogram (patched rows only)

| Δ (ocr − catalog) | rows |
|---:|---:|
| -40 | 5 |
| -36 | 1 |
| -30 | 50 |
| -25 | 1 |
| -21 | 1 |
| -20 | 65 |
| -17 | 1 |
| -15 | 1 |
| -10 | 57 |
| -6 | 1 |
| -5 | 114 |
| +5 | 85 |
| +10 | 48 |
| +15 | 24 |
| +16 | 10 |
| +17 | 1 |
| +20 | 21 |
| +23 | 1 |
| +24 | 1 |
| +25 | 33 |
| +28 | 3 |
| +30 | 24 |
| +35 | 21 |
| +40 | 3 |

## Per-cardNumber-prefix counts (patched rows only)

| Prefix | rows |
|---|---:|
| MIX | 137 |
| RAD | 109 |
| BF | 53 |
| SBF | 52 |
| GLBF | 24 |
| ABF | 23 |
| GGL | 23 |
| LOGO | 23 |
| CBF | 22 |
| BLBF | 17 |
| IBF | 12 |
| GBF | 9 |
| PG | 9 |
| RBF | 9 |
| SL | 8 |
| FT | 4 |
| OBF | 4 |
| BGA | 3 |
| CHILL | 3 |
| CJ | 3 |
| MI | 3 |
| BBF | 2 |
| BFA | 2 |
| FHA | 2 |
| GRILL | 2 |
| 24 | 1 |
| ADPA | 1 |
| BBFA | 1 |
| BHBF | 1 |
| BL | 1 |

## Files

- `patch.json` — apply via `scripts/apply_power_realign.py`
  - md5: `476e458e1e8c3ecc568d6ce4d69bfb2c`
- `needs_review.json` — low-confidence rows (OCR was uncertain) and
  rows where OCR couldn't extract a power at all. Operator to spot
  check or skip.

## Migration footprint

Power changes do not affect `bobaId` (the formula is
`cardNumber-hero-treatment-variation`). No R2 renames, no Supabase
row migration needed. Just a JSON field update applied to the
master + 4 downstream bundles.