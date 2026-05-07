# BOBA Image-Sourcing Pipeline

Automated discovery + recognition + catalog-update for missing card art. Runs entirely on free-tier infrastructure (GitHub Actions + Cloudflare Workers + R2 + Supabase). No local Mac dependency for ongoing operation.

This document is the orienting reference for the pipeline. Implementation details live in subdirectory READMEs and the binding docs ([CLAUDE.md](../CLAUDE.md), [DECISIONS.md](../DECISIONS.md)).

---

## Why this exists

The catalog ships ~17,968 cards but only ~90% have art on R2. The remaining ~1,800 are split between (a) cards we have candidate images for but haven't reviewed/cropped, and (b) cards with zero sourced art. The previous workflow required manual review on Ben's Mac (eBay review server on port 5050, manual crop, manual approve) — unsustainable as a sole-developer process.

Goal: every card with zero art either gets art shipped automatically OR lands in a high-confidence review queue, on a weekly cadence, with no manual intervention beyond email-skim audit.

---

## Hard constraints

1. **$0 ongoing cost forever.** Free GitHub Actions on public repos (Linux + macOS unlimited), Cloudflare Workers free plan, R2 free tier (10 GB / 1M Class A ops), Supabase free tier, Resend free tier (3000 emails/mo).
2. **No local Mac dependency for ongoing operation.** One-time research-queue migration runs locally; everything after is cloud-only.
3. **Methodology fidelity.** Card recognition uses the iOS scanner's exact pipeline ([DECISIONS.md #035](../DECISIONS.md)) via macOS GitHub runners — Apple Vision `VNGenerateImageFeaturePrintRequest` rev 2 + `VNRecognizeTextRequest` + the `feature-prints.bin` index iOS ships. No CLIP/Tesseract substitution.
4. **Collision detection is non-negotiable.** [DECISIONS.md #026](../DECISIONS.md) — md5 cross-check against R2 before any commit. New image bytes matching an existing card with a different `bobaId` is a hard stop.
5. **Audit trail.** Every weekly run sends a single summary email to ben@bobaplaybook.com with thumbnails, scores, and Universal Links to verify each merged card in 60 seconds.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  CLOUDFLARE WORKER (cron, hourly)                           │
│  Discovers candidate URLs from Radish / BV / eBay search    │
│  → INSERTs into Supabase pipeline_image_candidates          │
│  Pure orchestration; no image work (10ms CPU cap on free)   │
└────────────────────┬────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  GH ACTIONS — Linux (weekly, fast)                          │
│  STAGE A · SCRAPE                                           │
│  Selects discovered candidates, downloads w/ Playwright     │
│  (BV needs cookie auth), pre-crops to 5:7 with OpenCV,      │
│  uploads raw + crop to R2 staging/, sets state=cropped      │
└────────────────────┬────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  GH ACTIONS — macOS-15 (weekly, MATRIX-sharded)             │
│  STAGE B · RECOGNIZE  (load-bearing)                        │
│  Swift CLI mirroring iOS ScanMatching.resolve              │
│  • Vision OCR → cardNumber + hero text                      │
│  • feature-prints.bin lookup → top-30 fingerprint matches   │
│  • Score + hero-veto + confidence/margin floors             │
│  Writes recognition_result + score to Supabase              │
│  ≥0.95 + margin → AUTO; 0.70-0.95 → REVIEW; <0.70 → QUARANTINE│
└────────────────────┬────────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  GH ACTIONS — Linux (after Stage B)                         │
│  STAGE C · COMMIT (collision-checked, PR-mediated)          │
│  • md5 every accepted crop vs existing R2 (DECISIONS #026)  │
│  • Collision → state=collision, hard stop                   │
│  • Else → upload to R2 full/ + thumbs/, update cards.json,  │
│    regenerate downstream bundles via reconcile steps 5-10   │
│  • Open PR with thumbnails + scores in body                 │
│  • AUTO tier → workflow auto-merges; REVIEW tier → awaits   │
│  • Resend email summary to ben@bobaplaybook.com             │
└─────────────────────────────────────────────────────────────┘
```

---

## Autonomy gradient

| Score / margin | Tier | Action |
|---|---|---|
| Top score ≥ 0.95 AND margin ≥ 0.5 to next-different-hero | **AUTO** | PR opens, auto-merges, ships in next iOS/web pull. Email logs the merge. |
| Top score 0.70 – 0.95 | **REVIEW** | PR opens but doesn't auto-merge. Email flags it. Ben one-tap approves. |
| Top score < 0.70 | **QUARANTINE** | Stays in Supabase `pipeline_image_candidates` with `state=quarantined`. Not surfaced. Re-evaluable when the index improves or new sources arrive. |
| Any md5 collision with existing R2 image | **HARD STOP** | Never auto-merges regardless of score. Logged for manual investigation. |

Threshold values are placeholders — Phase 4 of the rollout calibrates them against the existing 1,193+377 research-queue corpus (which carries implicit ground-truth from prior human approvals).

---

## Directory layout

```
pipeline/
├── README.md                     ← this file
├── migrations/                   ← Supabase SQL migrations
│   ├── 0001_pipeline_initial.sql ← schema for the three pipeline tables
│   └── README.md                 ← how to apply migrations
├── scripts/                      ← Python pipeline glue (consolidated from research folder)
│   ├── import_research_queue.py  ← one-time migration of existing queue → Supabase
│   ├── scrape_radish.py          ← (Stage A) Radish scraper
│   ├── scrape_bazookavault.py    ← (Stage A) BazookaVault w/ Playwright auth
│   ├── scrape_ebay.py            ← (Stage A) eBay Browse API sourcer
│   ├── pre_crop.py               ← (Stage A) OpenCV 5:7 pre-crop
│   ├── commit_run.py             ← (Stage C) collision check + R2 + cards.json + PR
│   └── send_audit_email.py       ← (Stage C) Resend integration
├── recognition/                  ← Swift CLI (Stage B, runs on macOS-15)
│   └── CardRecognitionCLI/       ← mirrors tools/GridDetectorCLI; consumes feature-prints.bin
├── workers/                      ← Cloudflare Worker source (discovery cron)
│   └── boba-pipeline-discovery/
└── docs/
    ├── SETUP.md                  ← Resend + GH secrets + Supabase first-time setup
    └── THRESHOLDS.md             ← Phase 4 calibration results (TBD)
```

---

## Data model (Supabase)

All pipeline tables prefixed `pipeline_*` and RLS-locked to service-role only. They live in the same Supabase project as `user_cards` / `decks` / `user_profiles` but are walled off from any user-facing query path.

- **`pipeline_image_candidates`** — every image we've ever discovered. State machine: `discovered → downloaded → cropped → recognized → (accepted | review | quarantined | collision | rejected | error)`.
- **`pipeline_card_images`** — current state of which catalog `bobaId`s have art. Mirrors `imageAvailable` in `cards.json` but with attempt history.
- **`pipeline_runs`** — one row per workflow run (Stage A, B, or C). Observability surface for debugging weekly batches.

Full schema in [`migrations/0001_pipeline_initial.sql`](./migrations/0001_pipeline_initial.sql).

---

## Workflow files (top-level)

```
.github/workflows/
├── pipeline-discovery.yml         ← scheduled by CF Worker via repository_dispatch
├── pipeline-stage-a-scrape.yml    ← Linux, weekly cron + dispatch
├── pipeline-stage-b-recognize.yml ← macos-15, weekly, matrix
└── pipeline-stage-c-commit.yml    ← Linux, after Stage B finishes
```

Each workflow is independently testable via `workflow_dispatch`. Stages A/B/C chain via `workflow_run` triggers.

---

## Phased rollout

| Phase | Days | Deliverable |
|---|---|---|
| **0** Foundation | 1–2 | Pipeline directory + Supabase schema + research-queue import script + Resend/secrets runbook + this README |
| **1** Stage A — Scrape | 3–4 | Linux workflow: ports of Radish + eBay + BV scrapers from research folder, pre-crop, R2 staging upload |
| **2** Stage B — Recognize | 3–4 | `recognition/CardRecognitionCLI/` mirroring `tools/GridDetectorCLI`; macOS workflow w/ matrix sharding; threshold calibration against research-queue corpus |
| **3** Stage C — Commit | 2–3 | Collision check + R2 upload + cards.json delta + PR opener + Resend email |
| **4** Backfill + tune | 1–2 | Run end-to-end on existing 1,570-card backlog; manual audit of first auto-merged PRs |

---

## See also

- [`CLAUDE.md`](../CLAUDE.md) — project mantra "One Image per Card. One ID per Card."
- [`DECISIONS.md`](../DECISIONS.md) #008 (R2 strategy), #009 (static catalog), #026 (image-byte collision guard), #035 (unified card recognition)
- [`SCRATCHPAD.md`](../SCRATCHPAD.md) — current milestone state, the OKC art sourcing open question
- [`tools/GridDetectorCLI/`](../tools/GridDetectorCLI/) — reference implementation of the macOS Vision pipeline that Stage B builds on
- [`scripts/boba_id.py`](../scripts/boba_id.py) — canonical `bobaId` formula
