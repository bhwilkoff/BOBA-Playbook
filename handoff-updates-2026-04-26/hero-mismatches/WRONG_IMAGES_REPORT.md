# Hero/image mismatch scan

Catalog-wide scan for cases where the R2 image at a bobaId's slug
shows a DIFFERENT hero than the catalog row's `hero` field.
Caused by past R2 sync bugs / image-overwrite collisions
(DECISIONS.md #026). Patching `power` on these rows is unsafe —
what's needed is a re-source of the correct art onto the catalog's
slug.

## Summary

- Hero records scanned:                              **15,691**
- Confirmed image matches catalog hero:              **15,301** (97.5%)
- **Confirmed WRONG image** (OCR found a different known hero): **155** (1.0%)
- Mismatched but OCR too noisy to identify:          **48** (0.3%)
- Inconclusive (OCR captured no hero text at all):   **187** (1.2%)

The 'confirmed wrong' bucket is the actionable one — for each row,
the OCR captured a hero name that matches a DIFFERENT real hero in
the catalog. There's no plausible OCR-noise explanation; the file
at the catalog row's slug is genuinely the art for a different
hero. The 'too noisy to identify' bucket may include real wrong-
image cases the OCR couldn't disambiguate from glyph noise on
stylized art (Mixtape, Miami Ice, Kanjifoil etc.) — manual review
is the only reliable disposition for those.

## By treatment

| Treatment | wrong-image rows |
|---|---:|
| Mixtape Battlefoil | 38 |
| Miami Ice Battlefoil | 21 |
| Inspired Ink Battlefoil | 13 |
| Grandma's Linoleum Battlefoil | 9 |
| Alpha Battlefoil | 7 |
| Battlefoil | 7 |
| Prize & Promos | 7 |
| Blizzard Battlefoil | 6 |
| Great Grandma's Linoleum Battlefoil | 5 |
| 80's Rad Battlefoil | 5 |
| Superfoil | 5 |
| Base Set | 4 |
| Icon Battlefoil | 4 |
| Colosseum Battlefoil | 3 |
| Kanjifoil | 3 |
| Silver Blast | 2 |
| Green Battlefoil | 2 |
| Logofoil | 2 |
| Bubble Gum Battlefoil | 1 |
| Orange Blast | 1 |
| Chillin' Battlefoil | 1 |
| Fire Tracks Battlefoil | 1 |
| Headlines Battlefoil | 1 |
| Orange Battlefoil | 1 |
| Pink Battlefoil | 1 |
| Power Glove Battlefoil | 1 |
| Red Battlefoil | 1 |
| Inspired Ink Superfoil | 1 |
| Silver Battlefoil | 1 |
| Paper | 1 |

## By cardNumber prefix

| Prefix | wrong-image rows |
|---|---:|
| MIX | 38 |
| MI | 21 |
| BFA | 9 |
| GLBF | 9 |
| ABF | 7 |
| BF | 7 |
| P | 7 |
| BLBF | 6 |
| GGL | 5 |
| RAD | 5 |
| SF | 5 |
| IBF | 4 |
| CBF | 3 |
| LA | 3 |
| BBFA | 2 |
| GBF | 2 |
| LOGO | 2 |
| RJA | 2 |
| 12 | 1 |
| 88 | 1 |
| 120 | 1 |
| 148 | 1 |
| BGBF | 1 |
| BL | 1 |
| CHILL | 1 |
| FT | 1 |
| HBF | 1 |
| HLA | 1 |
| OBF | 1 |
| PBF | 1 |
| PG | 1 |
| RBF | 1 |
| SBF | 1 |
| SGA | 1 |
| T | 1 |
| THRA | 1 |

## What to do with this

Each row in `wrong_images.json` lists the catalog hero, OCR-captured
hero candidates, and the imageFile slug. The fix is to:

1. Decide whether the catalog's hero+treatment combo is correct
   (look up the canonical checklist) and the IMAGE was wrongly
   uploaded under that slug
2. OR the catalog's hero is wrong and the IMAGE matches a real
   different hero

In case (1) — re-source the correct art onto R2 under the slug.
In case (2) — fix the catalog row's hero (and bobaId).

Either fix is OUTSIDE the scope of this script — it just surfaces
the rows that need attention.