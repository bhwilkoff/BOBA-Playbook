-- ─────────────────────────────────────────────────────────────────────────
-- Pipeline schema migration 0002 — add Stage C state values
-- ─────────────────────────────────────────────────────────────────────────
-- Stage C of the pipeline transitions accepted candidates into one of
-- two new terminal states:
--
--   committed  — winning candidate per bobaId; image shipped to R2
--                and catalog bundles patched. The audit email lists
--                these.
--   superseded — lost the per-bobaId tournament (another candidate
--                scored higher for the same bobaId). Row kept for
--                audit; not surfaced.
--
-- 'collision' was already in the 0001 enum; no change there.
-- ─────────────────────────────────────────────────────────────────────────

alter table public.pipeline_image_candidates
    drop constraint if exists pipeline_image_candidates_state_check;

alter table public.pipeline_image_candidates
    add constraint pipeline_image_candidates_state_check
    check (state in (
        'discovered', 'downloaded', 'cropped',
        'recognized', 'accepted', 'review', 'quarantined',
        'collision', 'rejected', 'error',
        'committed', 'superseded'   -- new in 0002
    ));

-- ─── Verification ─────────────────────────────────────────────────────────
-- 1. Confirm the new constraint:
--    select conname, pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'public.pipeline_image_candidates'::regclass
--      and conname = 'pipeline_image_candidates_state_check';
--
-- 2. Smoke-test the new states accept:
--    insert into public.pipeline_image_candidates
--      (source, source_url, source_id, state)
--    values
--      ('manual', 'test://committed',  'test_committed_001',  'committed'),
--      ('manual', 'test://superseded', 'test_superseded_001', 'superseded');
--    delete from public.pipeline_image_candidates
--    where source_id in ('test_committed_001', 'test_superseded_001');
