-- 0007_pipeline_drop_radish_source.sql
--
-- Per DECISIONS.md #056 / RADISH_REMOVAL_LOOP.md, BOBA Playbook no
-- longer scrapes Radish Price Guide in any pipeline. The 10 historical
-- rows in pipeline_image_candidates with source='radish' were stuck in
-- non-actionable states (review/rejected/quarantined). This migration:
--
--   1. Deletes those orphan rows.
--   2. Drops 'radish' from the allowed source values so future inserts
--      can't reintroduce the value at the DB layer.
--
-- Applied via the Supabase MCP on 2026-05-23; this file mirrors that
-- change for re-applicability from a fresh clone / new environment.

delete from public.pipeline_image_candidates where source = 'radish';

alter table public.pipeline_image_candidates
  drop constraint if exists pipeline_image_candidates_source_check;

alter table public.pipeline_image_candidates
  add constraint pipeline_image_candidates_source_check
    check (source = ANY (ARRAY['ebay'::text, 'bazookavault'::text, 'dbs'::text, 'whatnot'::text, 'manual'::text, 'research_queue'::text, 'discord'::text]));
