# Card Audit — Runbook

How to run the catalog-vs-card-art audit end-to-end. Companion to
[`CARD_AUDIT_PIPELINE.md`](../../CARD_AUDIT_PIPELINE.md) (architecture).

## TL;DR

```bash
# 1. Fetch every card image to local cache (~10–15 min)
python3 pipeline/scripts/fetch_card_images.py \
    --catalog assets/data/cards.json \
    --cache   ~/.boba-card-audit/images \
    --workers 8

# 2. Run Vision OCR on every Hero / Play / HotDog (~22 min full catalog)
swift tools/CardAuditCLI/main.swift \
    --catalog assets/data/cards.json \
    --cache   ~/.boba-card-audit/images \
    --output  ~/.boba-card-audit/ocr_results.json \
    --types   Hero Play HotDog \
    --concurrency 4

# 3. Reconcile against catalog, emit patch + HTML review report
python3 pipeline/scripts/reconcile_audit_results.py \
    --catalog assets/data/cards.json \
    --ocr     ~/.boba-card-audit/ocr_results.json \
    --out     handoff-updates-$(date +%Y-%m-%d)/audit

# 4. Open the review HTML, ratify the proposed UPDATES
open handoff-updates-$(date +%Y-%m-%d)/audit/review.html

# 5. After human review, apply the patch
python3 scripts/apply_handoff_batch.py \
    handoff-updates-$(date +%Y-%m-%d)/audit/patch.json
```

Total wall-clock: ~45–60 minutes for the full 16k-card catalog on
a developer Mac. Zero external API cost; all local.

---

## Pilot validation (600-card Hero sample)

Run the same three commands with `--limit 600 --types Hero` on Phase
2 to validate before the full pass:

```bash
swift tools/CardAuditCLI/main.swift \
    --catalog assets/data/cards.json \
    --cache   ~/.boba-card-audit/images \
    --output  /tmp/audit-pilot.json \
    --limit 600 --types Hero --concurrency 4

python3 pipeline/scripts/reconcile_audit_results.py \
    --catalog assets/data/cards.json \
    --ocr     /tmp/audit-pilot.json \
    --out     /tmp/audit-pilot-out
```

**Pilot measured (2026-05-24):**
- 600 Hero cards in 36.9s (~16/s)
- **577/600 CONFIRMS (96.2% clean)**
- 9 UPDATES — 3-4 likely catalog fixes (power + name), 5 OCR edge
  cases to iterate
- 14 REVIEW — low-conf or ambiguous, mostly stylized card edge cases
- 0 NEEDS_IMAGE

Per-field stats on Hero pilot:
- **Power:** 585 MATCH, 4 LOW_CONF, 2 MISMATCH, 9 NULL_OCR — 97.5%
  accurate on extracted; 2 high-confidence mismatches are real
  catalog candidates
- **Name:** 593 MATCH, 7 MISMATCH — 98.8% accurate; the 7 are mostly
  OCR clipping / subtitle grabs (`Dr. J → DR.`, `JPEG → DESSICA
  PEGULA DEB`)
- **cardNumber:** 44 MATCH, 0 MISMATCH (extractable subset);
  555 NOT_EXTRACTABLE (bare-digit Base Set cards where number isn't
  printed on art — catalog is authoritative)
- **Serial:** 0 found (no Inspired Ink in this pilot sample — needs
  a separate IK-focused test)

---

## How the pipeline buckets every card

Every card lands in exactly one of these four bins, written to
`{out}/summary.json`:

| Bucket | Definition | Action |
|---|---|---|
| **CONFIRMS** | Every OCR-extracted field matches catalog at high confidence | No-op; logged for audit history |
| **UPDATES** | One or more fields' high-confidence OCR DISAGREES with catalog | Proposed catalog patch — human-gated apply |
| **REVIEW** | One or more fields LOW_CONF or NULL_OCR (catalog has value, OCR couldn't find one) | Walk the HTML report; manually decide each |
| **NEEDS_IMAGE** | Card has `imageFile` but OCR row missing | Re-fetch + re-OCR that specific card |

Per-field statuses (sub-bucket of above):
- **MATCH** — OCR value normalized-equal to catalog at conf ≥ 0.85
- **MISMATCH** — OCR value differs from catalog at conf ≥ 0.85
- **LOW_CONF** — OCR returned something at conf < 0.85
- **NULL_OCR** — OCR found nothing; catalog has a value
- **OK_NULL** — Neither has a value; nothing to compare
- **NOT_EXTRACTABLE** — Field can't be OCR'd from card art (e.g. bare-
  digit cardNumber on Base Set cards); catalog stays authoritative

Name normalization for comparison handles Cyrillic homoglyphs Vision
sometimes returns (`MACHО` → `MACHO`).

---

## Known limitations + iteration path

The v1 pilot identified these OCR misses worth iterating before a
full-catalog production run:

1. **Single-glyph names** like `JPEG` get out-competed by subtitle
   text (`Jessica Pegula Debut`). Mitigation: narrower name region
   on Heroes (drop subtitle band), or score on glyph-height vs
   confidence (the catalog-name biased customWords already helps).

2. **Period-truncated names** like `Dr. J → DR.` — Vision returns
   `DR.` and the comparison fails. Mitigation: strip trailing
   punctuation before normalization OR run a second name pass.

3. **Phantom-glyph names** like `Doublecheck → DOUBLECHECKR` — extra
   character glommed from neighbor text. Mitigation: prefer
   candidates that match the catalog-vocab list at edit-distance 0.

4. **Inspired Ink serial extraction** is implemented but unverified
   — the 600-card pilot was Base Set + Alpha Battlefoil heavy, no
   IK cards. Need a focused IK pilot:
   ```bash
   # First fetch a curated IK sample
   python3 -c "
   import json, urllib.request, os
   cards = json.load(open('assets/data/cards.json'))
   ik = [c for c in cards if c.get('isInspiredInk')][:50]
   cache = os.path.expanduser('~/.boba-card-audit/images')
   for c in ik:
       dest = f'{cache}/{c[\"imageFile\"]}'
       if os.path.exists(dest): continue
       urllib.request.urlretrieve(
           f'https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev/full/{c[\"imageFile\"]}',
           dest)
   "
   swift tools/CardAuditCLI/main.swift --catalog assets/data/cards.json \
       --cache ~/.boba-card-audit/images \
       --output /tmp/audit-ik.json --types Hero
   ```

5. **Play + HotDog card layouts** — region maps in
   `tools/CardAuditCLI/main.swift::CardRegion.roi(for:)` are seeded
   from rough estimates; run a 100-card Play pilot to validate.

6. **Element / weapon icon recognition** — Phase 3 of
   `CARD_AUDIT_PIPELINE.md`. Template-matching script not yet built.
   Until then, the pipeline doesn't audit `element`; rely on
   cardNumber-prefix derivation (BHBF → Blue Battlefoil, GGL →
   Great Grandma's Linoleum, …).

7. **Special variation flags** (Power Glove, background change) —
   needs base-art-per-hero designation + region-diff fingerprinting.
   v2.

---

## Disk usage

- `~/.boba-card-audit/images/` — ~1.3 GB after a full fetch.
- `~/.boba-card-audit/ocr_results.json` — ~5–10 MB.
- `handoff-updates-{date}/audit/` — review.html ~10–50 MB depending
  on UPDATES + REVIEW count (inline image refs).

To wipe and re-run from scratch:
```bash
rm -rf ~/.boba-card-audit
```

---

## What "fully autonomous" means here

The pipeline runs unattended end-to-end and produces a patch JSON.
**The patch is NOT auto-applied.** The final step is human review
of `review.html`, then `apply_handoff_batch.py` merges into
`cards.json`. This gate is intentional:

- The pipeline doesn't have a way to fix its own OCR mistakes
  (subtitle-grab, phantom letters) without human eyes on the card.
- High-confidence-mismatch ≠ catalog-wrong; could be either side.
- Apply-without-review would re-introduce the kind of silent data
  drift COWORK.md §2 flagged in the first place.

The autonomous part is everything UP TO the patch JSON; one human
session walks the HTML and ratifies.
