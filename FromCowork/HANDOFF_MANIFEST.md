# Claude Code Handoff Manifest
*BOBA Playbook (BOBACardApp)*
*Generated: 2026-04-03*

This folder contains everything Claude Code needs to start building. Copy files to the repo as directed.

---

## Files to Copy into BOBACardApp Repo

### 1. Card Data → `assets/data/`

| Source (Research folder) | Destination (repo) | Size | Description |
|---|---|---|---|
| `unified-cards/data/cards.json` | `assets/data/cards.json` | 13 MB | Full 17,793-card catalog |
| `unified-cards/data/cards-slim.json` | `assets/data/cards-slim.json` | 8.7 MB | iOS bundle (no search tokens) |
| `unified-cards/data/categories.json` | `assets/data/categories.json` | ~135 KB | Sets/treatments/elements/heroes |
| `unified-cards/data/search-index.json` | `assets/data/search-index.json` | ~5.6 MB | Pre-built search indexes |

**Copy command (run from Research folder, replace path):**
```bash
REPO="/path/to/BOBACardApp"
mkdir -p "$REPO/assets/data"
cp unified-cards/data/cards.json        "$REPO/assets/data/"
cp unified-cards/data/cards-slim.json   "$REPO/assets/data/"
cp unified-cards/data/categories.json   "$REPO/assets/data/"
cp unified-cards/data/search-index.json "$REPO/assets/data/"
```

### 2. Documentation → `docs/`

| Source | Destination | Description |
|---|---|---|
| `unified-cards/docs/CARD_SCHEMA.md` | `docs/CARD_SCHEMA.md` | Full cards.json field reference |
| `EBAY_SEARCH_FINDINGS.md` | `docs/EBAY_SEARCH_FINDINGS.md` | What's on eBay vs. not |
| `IMAGE_SOURCING_STRATEGY.md` | `docs/IMAGE_SOURCING_STRATEGY.md` | How images were gathered |
| `CLOUDFLARE_R2_SETUP.md` | `docs/CLOUDFLARE_R2_SETUP.md` | R2 upload & CDN setup |

**Copy command:**
```bash
mkdir -p "$REPO/docs"
cp unified-cards/docs/CARD_SCHEMA.md   "$REPO/docs/"
cp EBAY_SEARCH_FINDINGS.md             "$REPO/docs/"
cp IMAGE_SOURCING_STRATEGY.md          "$REPO/docs/"
cp CLOUDFLARE_R2_SETUP.md              "$REPO/docs/"
```

### 3. Root Files → repo root

| File | Notes |
|---|---|
| `FOR_CLAUDE_CODE/CLAUDE_MD_STARTER.md` | Rename to `CLAUDE.md` in repo, fill placeholders |
| `FOR_CLAUDE_CODE/DECISIONS_STARTER.md` | Merge into or replace `DECISIONS.md` in repo |
| `FOR_CLAUDE_CODE/SCRATCHPAD_STARTER.md`| Merge into or replace `SCRATCHPAD.md` in repo |
| `FOR_CLAUDE_CODE/supabase_schema.sql`  | Copy to repo root for reference |

---

## Images → Cloudflare R2 (NOT in repo)

Upload these two folders to your R2 bucket `boba-card-images`:

| Local folder | R2 prefix | Files | Size |
|---|---|---|---|
| `unified-cards/images-optimized/` | `full/` | 10,751 | ~720 MB |
| `unified-cards/thumbs/` | `thumbs/` | 10,751 | ~114 MB |

**rclone command (after configuring rclone with R2 credentials):**
```bash
rclone copy "unified-cards/images-optimized/" r2:boba-card-images/full/   --progress --transfers=32
rclone copy "unified-cards/thumbs/"           r2:boba-card-images/thumbs/ --progress --transfers=32
```
Full setup guide: `docs/CLOUDFLARE_R2_SETUP.md`

---

## What Stays in Research Folder (Never in Repo)

- All Python scripts (`*.py`) — data pipeline tools, not app code
- `unified-cards/images/` — 1.38 GB originals, archive only
- `bazookavault-images/`, `radish-scrape/`, `ebay-*/` — source data
- `BOBA-Master-Card-Database.xlsx` — source of truth spreadsheet
- `bv_rename_mapping.csv`, `merged_rename_mapping.csv` — pipeline artifacts
- `ebay_token.txt` — credentials, never commit

---

## Quick Stats for CLAUDE.md

```
Total cards:      17,793
With images:      15,890  (89.3% coverage)
Missing images:    1,903

Image tiers:
  thumbs/    10,751 files  ~114 MB  →  R2 thumbs/  (200px WebP, ~10 KB each)
  full/      10,751 files  ~720 MB  →  R2 full/    (≤1200px WebP, ~80 KB each)

Card number format examples:
  BF-208      Battlefoil #208
  BLBF-644    Blizzard Battlefoil #644
  T-16/50     Tournament card 16 of 50 (serialized)
  S-93/100    Starter card 93 of 100 (serialized)
  PHI-33      Philadelphia Eagles set card 33

Image filename format:
  {cardNumber}_{name}_{element}_P{power}.webp
  e.g.:  BF-208_Escape_Artist_ICE_P185.webp
         BLBF-644_Zephyr_STEEL_P100.webp
```
