-- ─────────────────────────────────────────────────────────────────────────
-- Pipeline schema migration 0003 — tight_crop_r2_key column
-- ─────────────────────────────────────────────────────────────────────────
-- Stage B's CardRecognitionCLI now produces a tight 5:7 perspective-
-- corrected crop before running OCR / feature-print recognition. The
-- rectified bytes are uploaded to R2 at staging/tight-crops/{id}.jpg
-- and the key stored here.
--
-- Stage C uses tight_crop_r2_key as the source for production tiers
-- when set; falls back to crop_image_r2_key for legacy rows that ran
-- before the tight-crop step shipped (the imported research-queue
-- corpus from Phase 0).
--
-- Also adds two diagnostic columns so we can audit how recognition
-- inputs were prepared (Vision rect detection vs center fallback)
-- without re-running Stage B.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.pipeline_image_candidates
    add column if not exists tight_crop_r2_key   text,
    add column if not exists tight_crop_method   text
        check (tight_crop_method is null
               or tight_crop_method in ('vision_rect', 'center_57', 'uncropped')),
    add column if not exists tight_crop_confidence numeric(4,3);

create index if not exists pipeline_candidates_tight_crop_idx
    on public.pipeline_image_candidates (tight_crop_r2_key)
    where tight_crop_r2_key is not null;
