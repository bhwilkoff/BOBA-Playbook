-- ─────────────────────────────────────────────────────────────────────────
-- Pipeline schema migration 0005 — 'already_imaged' state
-- ─────────────────────────────────────────────────────────────────────────
-- The imported research-queue was sourced when a different set of cards
-- needed art. cards.json has been updated through other paths since;
-- ~60% of recognized rows now target bobaIds that ALREADY have
-- imageAvailable=true. Without filtering, Stage C would overwrite
-- existing art with re-scraped versions.
--
-- New terminal state 'already_imaged' marks candidates whose target /
-- recognized bobaId is already present in cards.json with art. Stage B
-- skips fetching them; Stage C defensively filters too.
--
-- The BOBA mantra is "One Image per Card. One ID per Card." If a card
-- has art, that art stays — we don't replace it without an explicit
-- upgrade flow (which doesn't exist yet and isn't on the v1 roadmap).
-- ─────────────────────────────────────────────────────────────────────────

alter table public.pipeline_image_candidates
    drop constraint if exists pipeline_image_candidates_state_check;

alter table public.pipeline_image_candidates
    add constraint pipeline_image_candidates_state_check
    check (state in (
        'discovered', 'downloaded', 'cropped',
        'recognized', 'accepted', 'review', 'quarantined',
        'collision', 'rejected', 'error',
        'committed', 'superseded',
        'already_imaged'
    ));
