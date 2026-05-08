-- 0006_pipeline_discord_source.sql
--
-- Add 'discord' to the allowed sources for pipeline_image_candidates.
-- Discord-export attachments arrive blindly (no a-priori target_boba_id);
-- Stage B identifies via Vision, Stage C have_art filter still gates
-- shipping for already-imaged cards. Source flag tracks provenance.

alter table public.pipeline_image_candidates
    drop constraint if exists pipeline_image_candidates_source_check;

alter table public.pipeline_image_candidates
    add constraint pipeline_image_candidates_source_check
    check (source in ('ebay', 'radish', 'bazookavault', 'dbs',
                      'whatnot', 'manual', 'research_queue', 'discord'));
