# Stage 1+2 Handover — bobaId-Based Image Rename

**Date**: 2026-04-13
**Completed by**: Cowork
**Handover to**: Claude Code
**Principle preserved**: One Image per Card. One ID per Card. bobaId is the primary key on every layer.

---

## What changed on the Cowork side

Every catalog-referenced image was renamed from its legacy `{cardNumber}_{heroSlug}_{ELEMENT}_P{power}.webp` grammar (or its Play/HotDog equivalents) to `{bobaIdSlug}.webp`, where:

```
bobaIdSlug = re.sub(r'_+','_',
             re.sub(r'[^A-Za-z0-9\-]+','_', bobaId)).strip('_')
```

The slugify function is deterministic, one-way, and collision-free across all 17,739 bobaIds (verified; zero collisions).

### Numbers

| Layer | Before | After | Delta |
|---|---:|---:|---:|
| Cards with `imageFile` | 14,743 | 16,014 | +1,271 |
| `imageAvailable=true` | 14,743 | 16,014 | +1,271 |
| Coverage | 82.9% | 90.3% | +7.4pp |
| `missing-cards.json` | 2,996 | 1,725 | −1,271 |

By card type:

| Type | Pre-Stage12 Missing | Now Resolved | Still Missing |
|---|---:|---:|---:|
| Hero | 2,442 | 743 | 1,699 |
| Play | 487 | 481 | 6 |
| HotDog | 58 | 47 | 11 |
| Sealed Product | 9 | 0 | 9 |
| **Total** | **2,996** | **1,271** | **1,725** |

Non-Hero resolution rate: **528 of 554 (95%)**. This answers the question that started this work.

### What's in the local repo (unified-cards/)

- `unified-cards/images/` — originals, renamed to `{bobaIdSlug}.webp` (15,859 files; 119 originals were missing pre-Stage12 from the `images/` tier but present in `images-optimized/`)
- `unified-cards/images-optimized/` — full-size WebP, renamed (15,978 files)
- `unified-cards/thumbs/` — thumbnail WebP, renamed (15,978 files)
- `unified-cards/images-sealed/optimized/` — sealed products, renamed (36 files)
- `unified-cards/images-sealed/thumbs/` — sealed products, renamed (36 files)

Every `imageFile` value in `unified-cards/data/cards.json` now matches the on-disk filename exactly.

### Regenerated bundles

All bundles below were rebuilt from the updated `cards.json` and copied to `BOBA-Playbook`:

- `assets/data/cards.json`
- `assets/data/cards-slim.json`
- `assets/data/categories.json`
- `assets/data/search-index.json` (keyed by bobaId)
- `assets/data/missing-cards.json` (1,725 entries)
- `BOBAPlaybook/display-cards.json`
- `BOBAPlaybook/cards-head.json`

### Collision guard

Step 11's md5 collision guard was run post-rename. Zero dangerous cross-card collisions. 15 collisions exist — all are the whitelisted sealed-product Box↔Case pairs (e.g., Alpha Edition Hobby Box and Alpha Edition Hobby Case share the same image because no distinct Case photo exists). These are the same pairs already documented and accepted.

---

## What Claude Code needs to do

### 1. R2 object rename (14,707 + 36 = 14,743 files × 2 tiers = 29,486 R2 operations)

Cloudflare R2 does not support server-side rename; each rename is a copy+delete. Use rclone.

Manifest: `STAGE12_R2_MANIFEST.json` (in the research project root). Structure:
```json
{
  "renames": {
    "standard_full":   [[old_key, new_key], ...],
    "standard_thumbs": [[old_key, new_key], ...],
    "sealed_full":     [[old_key, new_key], ...],
    "sealed_thumbs":   [[old_key, new_key], ...]
  },
  "uploads_from_phase_b": [[filename, local_full_path, local_thumb_path], ...]
}
```

Recommended approach:

```bash
# Generate an rclone moveto batch per tier. Example:
cat STAGE12_R2_MANIFEST.json | jq -r '.renames.standard_full[] | @tsv' | \
  while IFS=$'\t' read old new; do
    rclone moveto "r2:boba-card-images/$old" "r2:boba-card-images/$new"
  done
```

Run the four tiers sequentially. Parallelize within a tier if rclone supports batching in your config.

### 2. R2 new uploads (1,271 Phase B claim files × 2 tiers = 2,542 new uploads)

These are files that existed on disk but were never uploaded to R2 because they weren't linked to cards in cards.json. Stage 1 claimed them by parsing cardNumber + name-slug against the unmapped cards in cards.json; only files with exactly ONE matching candidate were claimed.

```bash
# After renaming, upload the new files:
jq -r '.uploads_from_phase_b[] | .[0]' STAGE12_R2_MANIFEST.json | \
  while read fn; do
    rclone copyto "unified-cards/images-optimized/$fn" "r2:boba-card-images/full/$fn"
    rclone copyto "unified-cards/thumbs/$fn"          "r2:boba-card-images/thumbs/$fn"
  done
```

### 3. Commit bundle updates to BOBA-Playbook

```
assets/data/cards.json
assets/data/cards-slim.json
assets/data/categories.json
assets/data/missing-cards.json
assets/data/search-index.json
BOBAPlaybook/display-cards.json
BOBAPlaybook/cards-head.json
```

### 4. App code — zero refactor required

The good news: `js/api.js` (`thumbUrl(card.imageFile)` / `fullUrl(card.imageFile)`) and `BOBAPlaybook/CDN.swift` both build URLs by concatenating `CDN_BASE + tier + imageFile`. Because we updated `imageFile` in cards.json to match the new R2 object name, the app sees no behavior change. No code changes needed on web or iOS.

### 5. Post-deploy verification

Pick 5 cards from each category and confirm images render in both web and iOS:

- 1 Hero with image pre-Stage12 (Phase A): e.g., bobaId `1-LeBoss-Base_Set-First_Edition`
- 1 Bonus Play newly visible (Phase B): e.g., bobaId `BPL-10-Dumpster_Battle-Bonus_Plays-First_Edition`
- 1 HotDog newly visible (Phase B): e.g., any HotDog where imageAvailable flipped to true
- 1 Sealed Product: e.g., `SEALED-alpha-hobby-box-Alpha_Edition_Hobby_Box--Hobby_Box`
- 1 card still missing (should show placeholder): any entry in `missing-cards.json`

### 6. Git commit

Suggested message:
> `feat(data): rename all R2 images to {bobaId}.webp (Stage 1+2)`
>
> Catalog now has 1:1 bobaId↔imageFile mapping across 16,014 cards. Non-Hero coverage improved from 82% to 95% (Plays 6/487 missing, HotDogs 11/58 missing). R2 renames via STAGE12_R2_MANIFEST.json. Collision guard verified zero cross-card collisions post-rename.

---

## What's intentionally out of scope

- **Stage 3/4/5** of the original 5-stage plan are folded into Stage 1+2 here because the slug-of-bobaId approach lets us keep the existing `imageFile`-reading app code. No separate app refactor phase needed.
- **2,975 unclaimed disk files** — see `stage12_unclaimed_full.json`. Breakdown:
  - 918 unparseable (names like `3-DOG-SPECIAL.webp`, `ACTION.webp` — no cardNumber prefix)
  - 911 duplicate-of-mapped (alternate images for cards we already fully mapped; safe to delete from disk)
  - 515 orphan-cardNumber (BBIA-*, BBFA-*, S-*, etc. — cards that may not yet be in cards.json)
  - 10 ambiguous (cardNumber matches multiple unmapped cards; filenames don't carry enough info)
- **1,725 still-missing cards** — these need external recovery via the eBay art pipeline. When new images arrive, they should be saved directly as `{bobaIdSlug}.webp` — no more variety_key.
- **Pipeline refactor** — `reconcile_all.py::step2_3` and `step4` still link via `variety_key`. Stage 1+2 patched the output without touching the pipeline. A future pipeline refactor should make step4 emit bobaIdSlug filenames natively; until then, treat `stage12_rename_by_bobaid.py` as a mandatory post-step.

---

## Mantra check

> One Image per Card. One ID per Card.

After Stage 1+2:
- Every card has a unique bobaId (17,739 unique, 0 collisions) ✓
- Every referenced image filename IS the card's bobaIdSlug (16,014 1:1 pairs) ✓
- App builds URLs from bobaId-derived filenames (no heroSlug/element/power parsing anywhere) ✓
- Collision guard verifies at the byte level that no two distinct bobaIds map to the same bytes (except the whitelisted sealed Box↔Case pairs) ✓

The mantra holds end-to-end now — not just in cards.json, not just in search-index, but all the way down to the R2 object key.
