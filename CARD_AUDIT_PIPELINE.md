# Card Art → Catalog Audit Pipeline

> **Goal:** The card art tells the full story. Every catalog field that
> can be verified by looking at a card should be verified by looking
> at the card — not inferred from siblings, BV CSV, blog scrapes, or
> any external source. The database becomes the premier reference set
> for BOBA cards, with every value traceable to a specific region of
> a specific image.

Authored 2026-05-24 in response to Ben's directive after the COWORK.md
§2 power-misalignment incident + the corner-badge cleanup.

---

## 0. Scope

**In scope** — read these fields from every card image that has art:

| Card type | Fields extracted from art |
|---|---|
| **Hero** (17,277) | `cardNumber`, `name`/`hero`, `power`, `element` (weapon), `treatment`, `isInspiredInk` (+ `printRun` from serial stamp), special variation flags (background change, Power Glove, etc.) |
| **Play** (515) | `cardNumber`, `name`, `playCost`, `playAbility` (text), `dbs` (Damage Boost Slot value), `treatment` |
| **HotDog** (137) | `cardNumber`, `name`, `playCost`, ability text, `treatment` |
| **Sealed Product** (45) | Out of scope — packs/boxes have product photography, not a card structure |

**16,396 / 17,974 cards** have art today. The 1,578 art-pending cards
(`imageFile=null` in cards.json) are excluded from the audit; they're
already in a separate sourcing queue.

**Note on app rendering** — this audit produces catalog data only.
The previous overlay pills on Find / Decks / Collection cells were
removed (commit `a786b66`); the audit is NOT trying to recreate
them. The data lives in `cards.json` for queries, search, and
card-detail surfaces — not as overlays on grid thumbnails. Per Ben:
"we are attempting to have the most exhaustive set of data for every
single card based upon what is observable on the card."

**New `printedSerial` field for Inspired Ink cards:** the audit
captures the actual printed serial denominator ("/5", "/10", "/25",
"/50", or "/1") from the card art. This is authoritative — the
IK-rule that maps catalog `element` → expected denominator
(DECISIONS.md #028) has whole-treatment-family exceptions
empirically confirmed in the validation pilot (Silver Blast cards
print `1/5` regardless of FIRE or ICE element; ~95% of audited IK
cards conflict with the rule). The new field becomes the source of
truth for print-run display anywhere the apps need it; the rule is
only used as a fallback for cards we haven't audited yet.

**Out of scope (deferred to v2):**
- Special-variant CHANGE detection (e.g., "this version has Power
  Glove visible" vs base) — needs base-art designation + region diff
- DBS-tier interpretation (numeric DBS value extracted, but tier
  label mapping stays in code)
- Sealed Product photography classification

---

## 1. Architecture

Five sequential phases, each writing to a sidecar file. No phase
mutates `cards.json` directly until the final Apply step gates on
human review.

```
┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ 1. FETCH     │ → │ 2. OCR       │ → │ 3. VISUAL    │ → │ 4. RECONCILE │ → │ 5. APPLY     │
│   R2 → local │   │   Vision +   │   │  Element +   │   │  vs cards.   │   │   patch →    │
│   image      │   │  region      │   │   treatment  │   │  json.       │   │   cards.json │
│   cache      │   │  cropping    │   │  templates   │   │  Bucket per  │   │  via Cowork  │
│              │   │              │   │              │   │  card.       │   │  handoff     │
└──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
       │                  │                  │                  │                  │
       ▼                  ▼                  ▼                  ▼                  ▼
  ~/.boba-card-      audit/ocr_           audit/visual_     audit/reconcile_   handoff-
  audit/images/      results.json         results.json      {date}/            updates-
                                                              patch.json       {date}/
                                                              review.html      audit/
```

**No phase deletes its predecessor's output** — each is an idempotent
read-only consumer of upstream + writer of its own slot. Re-runnable.

---

## 2. Phase-by-phase

### Phase 1 — Image fetcher (`pipeline/scripts/fetch_card_images.py`)

Downloads every `card.imageFile` from R2 to `~/.boba-card-audit/images/{imageFile}`.

- **Source:** `https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev/full/{imageFile}`
  (per DECISIONS.md #008 CDN base).
- **Cache:** local filesystem; skip on existing file unless `--force`.
- **Parallelism:** `ThreadPoolExecutor(max_workers=8)`. Conservative
  to avoid the burst-saturation problem we hit in the wall pipeline
  (DECISIONS.md `wall (web): drop failed-image cards` commit).
- **Retries:** 3 attempts with exponential backoff (200ms → 600ms →
  1500ms — same pattern as wall).
- **Output:** `~/.boba-card-audit/images/{imageFile}`.
- **Size:** 16,396 cards × ~80KB = ~1.3 GB local cache.
- **Runtime estimate:** ~10–15 min on a residential connection.

### Phase 2 — Vision OCR (`tools/CardAuditCLI/main.swift`)

Swift CLI using `VNRecognizeTextRequest`. Extends the working pattern
in `scripts/audit_card_powers.swift` to extract every text field, not
just power.

**Per-card flow:**

1. Load `cards.json`, group cards by `cardType`.
2. For each card with `imageFile`:
   a. Decode image to `CGImage`.
   b. Pre-process: gamma-adjust + desaturate + unsharp mask
      (same recipe as `ocrPrintedPowerSlow` — recovers Fire/Ice
      shimmer cards where the printed glyph is washed out).
   c. Run `VNRecognizeTextRequest(.accurate)` on the full frame
      with `customWords` biased to expected vocab.
   d. Run additional region-of-interest passes per field below.
3. Aggregate observations, score per-field, write per-card row.

**Per-card-type region map** (regions are `(x, y, w, h)` in
normalized image space with origin TOP-LEFT; converted to Vision's
bottom-left ROI internally):

#### Hero card regions

| Field | Region | Pass strategy | Custom vocab bias |
|---|---|---|---|
| `power` | `(0.55, 0.00, 0.45, 0.30)` — top-right | accurate + slow fallback | multiples of 5 from 55–250 |
| `cardNumber` | `(0.00, 0.85, 0.50, 0.15)` — bottom-left | accurate, dash-aware regex | set prefixes (ABF, BHBF, RBF, GGL, BLBF, …) |
| `name`/`hero` | `(0.10, 0.00, 0.80, 0.18)` — top-center | accurate, big-glyph | hero name list from catalog (Maverick, LeBoss, D-Harp, …) |
| `element` | `(0.00, 0.00, 0.20, 0.20)` — top-left | visual primary (Phase 3) + OCR secondary | FIRE / ICE / HEX / GLOW / STEEL / BRAWL / GUM / SUPER |
| `serial` | `(0.20, 0.75, 0.60, 0.20)` — center-bottom | accurate, regex `\d{1,3}\s*/\s*(5\|10\|25\|50)` | "/5", "/10", "/25", "/50" |
| `treatment text` | `(0.00, 0.92, 1.00, 0.08)` — bottom strip | accurate | treatment names (Battlefoil, Superfoil, Inspired Ink, …) |

#### Play card regions

| Field | Region | Notes |
|---|---|---|
| `cardNumber` | bottom-left | same regex as Hero |
| `name` | top-center | larger text than Hero name |
| `playCost` | top-left, small numeric | 0–9 typically |
| `dbs` | bottom-right indicator | 0–4 numeric |
| `playAbility` | body, ~`(0.05, 0.35, 0.90, 0.45)` | full sentence; lowest-confidence field, gets a separate review-only bucket |
| `treatment` | bottom strip | same as Hero |

#### HotDog card regions

| Field | Region | Notes |
|---|---|---|
| `cardNumber` | bottom-left | HTD- prefix |
| `name` | top-center | |
| `playCost` | top-left | |
| ability text | body | review-only |

**Confidence + scoring:**
- Each Vision observation carries a per-token confidence in `[0, 1]`.
- Per field: collect candidates from all passes (default + slow +
  ROI'd), score by `confidence × region_match × vocab_match`.
- A field is "**high-confidence**" when score ≥ 0.85 AND the top
  candidate is ≥ 1.5× the runner-up.
- "**Low-confidence**" routes the card to the manual review queue.

**Output:** `audit/ocr_results.json`:
```json
{
  "schema_version": 1,
  "ran_at": "2026-05-24T15:30:00Z",
  "total_attempted": 16396,
  "results": [
    {
      "bobaId": "1-LeBoss-Base Set-First Edition",
      "imageFile": "1-LeBoss-Base_Set-First_Edition.webp",
      "cardType": "Hero",
      "ocr": {
        "cardNumber":  { "value": "1",        "confidence": 0.97, "candidates": ["1", "I"] },
        "name":        { "value": "LeBoss",   "confidence": 0.99 },
        "power":       { "value": 135,        "confidence": 0.95 },
        "element":     { "value": "FIRE",     "confidence": 0.88 },
        "serial":      { "value": null,       "confidence": 0.00 },
        "treatment":   { "value": "Base Set", "confidence": 0.72 }
      }
    },
    ...
  ]
}
```

### Phase 3 — Visual classification (`pipeline/scripts/classify_card_visuals.py`)

For fields where text OCR is unreliable but visual signal is strong:

- **Element/weapon icon recognition** — Each weapon has a canonical
  symbol (flame for FIRE, snowflake for ICE, hex symbol for HEX,
  etc.). Build a small template library (~9 templates × ~50×50 px),
  do template-matching on the top-left region. Cross-check OCR value
  against template match.
- **Inspired Ink detection** — IK cards have a hand-stamped serial
  with a distinctive script font + texture. Run a small classifier
  (color-histogram + edge density in the center-bottom region) to
  flag "this card looks IK" vs "this card doesn't" — orthogonal
  validation of OCR'd serial.
- **Treatment foil detection** — Border/edge color of the card art
  varies by treatment (gold for Battlefoil family, silver for
  Superfoil, mixtape-style for Mixtape, etc.). Sample the edge
  pixels' dominant color, map to treatment family. Same orthogonal
  check.
- **Special variation detection (v2):** Per-hero base art comparison
  via feature-print diff in specific regions (head, background, hand).
  Out of scope for v1.

**Output:** `audit/visual_results.json` with same `bobaId` key.

### Phase 4 — Reconciliation (`pipeline/scripts/reconcile_audit_results.py`)

Joins OCR + visual results on `bobaId`, compares each field against
`cards.json`, buckets every card:

| Bucket | Definition | Action |
|---|---|---|
| **CONFIRMS** | Every field's high-confidence OCR matches catalog | No-op; record bobaId for audit log |
| **UPDATES** | One or more fields high-confidence OCR DISAGREES with catalog | Add to patch JSON for human review-then-apply |
| **REVIEW** | One or more fields low-confidence OR ambiguous (OCR ≠ visual classification, e.g.) | Add to HTML review report |
| **NEEDS_IMAGE** | Card had `imageFile` but fetch/decode failed | Add to error report |

**Outputs:**

1. `handoff-updates-{date}/audit/patch.json` — Cowork-format patch
   shape with `modify[]` entries:
   ```json
   {
     "modify": [
       {
         "old_bobaId": "ABF-248-Wild Bill-Base Set-",
         "changes": {
           "power": 145,
           "element": "FIRE"
         },
         "evidence": {
           "power":   { "ocr_value": 145, "ocr_confidence": 0.95, "catalog_value": 140 },
           "element": { "ocr_value": "FIRE", "visual_value": "FIRE", "catalog_value": "ICE" }
         }
       }
     ]
   }
   ```
2. `handoff-updates-{date}/audit/review.html` — side-by-side report
   with card image + extracted fields + catalog fields + buttons to
   open the underlying image in a browser.
3. `handoff-updates-{date}/audit/summary.json` — counts per bucket
   + per-field error rate.

### Phase 5 — Apply (`scripts/apply_handoff_batch.py`)

Existing tooling. Reads the patch from Phase 4 and merges into
`cards.json` after human gate. Already understands the `modify[]` /
`changes` / `evidence` schema (used by Cowork handoffs).

---

## 3. Why this approach + alternatives rejected

**Why local Vision over cloud OCR (Google Vision, AWS Textract)?**
- Free vs ~$22 for the catalog (Google Vision is $1.50/1000 calls).
- We already have working Vision patterns in `audit_card_powers.swift`
  and `tools/RecognizerCLI`.
- Vision is the most-accurate OCR for the iOS+macOS pipeline we
  measured against; cards-with-shimmer recovery is well-tuned.

**Why local Python image fetcher over a Worker?**
- 16k requests in a tight loop want a long-running process with
  retry state; a Worker's 30s CPU cap is too tight.
- Local fetcher can resume mid-run via existing-file check.

**Why no sibling fallback?**
- Explicit anti-pattern per Ben's instruction. The catalog should
  reflect what's on the card; siblings are a different physical card.

**Why a sidecar audit file instead of in-catalog fields?**
- Audit metadata (confidence, evidence, OCR raw values) is debug
  context, not user-facing. Keep it out of the bundled `display-
  cards.json` to save bytes shipped to clients.
- Reconcile-then-apply is reversible — if Phase 4's heuristics are
  wrong, we re-run reconciliation without re-fetching/re-OCRing.

---

## 4. Runtime + cost

| Phase | Per-card time | Total (16,396 cards) | Concurrency | Wall-clock |
|---|---|---|---|---|
| Fetch | ~50–100 ms | ~14–28 min | 8 | **~10–15 min** |
| OCR | ~400–800 ms (slow fallback adds 4× when needed) | ~110–220 min | 4 (CPU-bound) | **~30–60 min** |
| Visual | ~100–200 ms | ~30–60 min | 8 | **~5–10 min** |
| Reconcile | <1 ms | <1 min | 1 | **<1 min** |
| **Total wall-clock** | | | | **~45–90 min** |

Cost: $0 (entirely local). One developer-Mac, runs offline.

---

## 5. Validation strategy

**Pilot first** — Run on a curated 100-card sample spanning:
- Multiple sets (Alpha Update, GGL, BHBF, …)
- Multiple treatments (Base Set, Battlefoil family, Superfoil,
  Inspired Ink at each weapon)
- A few intentionally-anomalous cards (the COWORK.md §2 power
  misalignments)

Validate that:
- Power OCR matches `audit_card_powers.swift` output (regression test)
- cardNumber OCR matches the `imageFile` prefix
- Element template-matching agrees with OCR for ≥90% of samples

Iterate on per-field thresholds + region crops based on pilot
mismatches BEFORE running on the full 16k catalog.

**Then full audit** — Run all five phases. Estimate ~50–500 cards
will land in UPDATES (catalog fixes), ~500–2000 in REVIEW. Human
walks the REVIEW HTML, ratifies the UPDATES patch, then
`apply_handoff_batch.py` merges into `cards.json`.

---

## 6. Implementation milestones

| # | Deliverable | Status |
|---|---|---|
| M1 | This doc | ✅ shipped |
| M2 | `fetch_card_images.py` | next |
| M3 | `tools/CardAuditCLI/` Swift OCR CLI | next |
| M4 | `reconcile_audit_results.py` + HTML report | next |
| M5 | Pilot run on 100-card sample | next |
| M6 | Iterate on thresholds / region crops | next |
| M7 | Full catalog run | after pilot |
| M8 | Apply patch via `apply_handoff_batch.py` | human-gated |
| M9 | `classify_card_visuals.py` (Phase 3 visual recognition) | after M5 lands |
| M10 | Special-variation detection (background, Power Glove) | v2 |

---

## 7. Future extensions

Once this pipeline runs cleanly, it unlocks:

- **Continuous validation** — Cron job re-runs on any catalog change
  to flag drift.
- **New-card sourcing** — When BV adds a card image, OCR it first
  and propose the catalog row from the audit, not from BV's
  metadata.
- **Card-art search** — Index OCR'd ability text for full-text
  search inside the app (currently we only search hero name +
  cardNumber + treatment).
- **Image-integrity guard** — Cross-reference OCR'd cardNumber
  against `imageFile` prefix; any mismatch flags an
  image-collision regression (DECISIONS.md #026 extended).
- **Player-facing trust** — Mark every catalog field with the
  audit timestamp / confidence; surface "verified by image" badge
  in card detail.
