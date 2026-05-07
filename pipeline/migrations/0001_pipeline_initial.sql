-- ─────────────────────────────────────────────────────────────────────────
-- BOBA Image-Sourcing Pipeline — Initial Schema
-- ─────────────────────────────────────────────────────────────────────────
-- Three tables, all prefixed `pipeline_*` and RLS-locked to service-role.
-- They live in the same Supabase project as user_cards/decks/user_profiles
-- but are walled off from every user-facing query path.
--
-- Apply via Supabase SQL editor (Dashboard → SQL Editor → New query →
-- paste this file → Run). Idempotent: safe to re-run.
--
-- See pipeline/README.md for the architectural context.
-- ─────────────────────────────────────────────────────────────────────────

-- ─── pipeline_runs ────────────────────────────────────────────────────────
-- One row per workflow execution. Observability surface for debugging
-- weekly batches and proving no-op runs are real.
create table if not exists public.pipeline_runs (
    id                       uuid        primary key default gen_random_uuid(),
    run_type                 text        not null
        check (run_type in ('discovery', 'scrape', 'recognize', 'commit', 'backfill')),
    gh_actions_run_id        text,
    gh_actions_run_url       text,
    started_at               timestamptz not null default now(),
    finished_at              timestamptz,

    -- counters (filled in as the run progresses)
    candidates_processed     int         not null default 0,
    candidates_accepted      int         not null default 0,
    candidates_review        int         not null default 0,
    candidates_quarantined   int         not null default 0,
    candidates_rejected      int         not null default 0,
    candidates_collision     int         not null default 0,
    errors_encountered       int         not null default 0,

    summary                  jsonb       not null default '{}'::jsonb,
    error_log                jsonb
);

create index if not exists pipeline_runs_started_idx
    on public.pipeline_runs (started_at desc);
create index if not exists pipeline_runs_type_idx
    on public.pipeline_runs (run_type, started_at desc);

-- ─── pipeline_image_candidates ────────────────────────────────────────────
-- Every image we've ever discovered, regardless of source. The state column
-- drives the workflow:
--
--   discovered  → URL known, image not yet downloaded
--   downloaded  → raw bytes in R2 staging/, not yet cropped
--   cropped     → 5:7 crop in R2 staging/, ready for Stage B recognition
--   recognized  → Stage B has scored it; recognition_* columns populated
--   accepted    → AUTO tier (≥0.95 + margin); committed to R2 + cards.json
--   review      → REVIEW tier (0.70–0.95); PR opened, awaiting Ben's tap
--   quarantined → low confidence (<0.70); not surfaced, re-evaluable later
--   collision   → md5 matched existing R2 image of a different bobaId
--   rejected    → manually rejected (legacy queue migration only)
--   error       → terminal failure during processing
create table if not exists public.pipeline_image_candidates (
    id                       uuid        primary key default gen_random_uuid(),

    source                   text        not null
        check (source in ('ebay', 'radish', 'bazookavault', 'dbs',
                          'whatnot', 'manual', 'research_queue')),
    source_url               text        not null,
    source_id                text,                      -- listing/page/asset ID
    source_metadata          jsonb       not null default '{}'::jsonb,

    -- targeting (when we know which card we were looking for)
    target_card_number       text,
    target_boba_id           text,

    -- R2 keys (full path under boba-card-images/staging/)
    raw_image_r2_key         text,
    crop_image_r2_key        text,
    image_md5                text,                      -- of the cropped bytes

    -- recognition result (Stage B output)
    recognition_score        numeric(6,3),
    recognition_margin       numeric(6,3),
    recognized_boba_id       text,
    recognition_result       jsonb,                     -- full signal breakdown

    -- collision detection (Stage C)
    collision_with_boba_id   text,

    -- terminal error
    error                    text,

    -- state machine
    state                    text        not null default 'discovered'
        check (state in ('discovered', 'downloaded', 'cropped',
                         'recognized', 'accepted', 'review', 'quarantined',
                         'collision', 'rejected', 'error')),

    -- audit trail of which run touched this row at each stage
    discovered_by_run_id     uuid        references public.pipeline_runs(id),
    scraped_by_run_id        uuid        references public.pipeline_runs(id),
    recognized_by_run_id     uuid        references public.pipeline_runs(id),
    committed_by_run_id      uuid        references public.pipeline_runs(id),

    discovered_at            timestamptz not null default now(),
    updated_at               timestamptz not null default now(),

    -- per-source dedup: a (source, source_id) pair can only exist once
    constraint pipeline_image_candidates_source_id_unique
        unique (source, source_id)
);

create index if not exists pipeline_candidates_state_idx
    on public.pipeline_image_candidates (state);
create index if not exists pipeline_candidates_target_idx
    on public.pipeline_image_candidates (target_boba_id)
    where target_boba_id is not null;
create index if not exists pipeline_candidates_md5_idx
    on public.pipeline_image_candidates (image_md5)
    where image_md5 is not null;
create index if not exists pipeline_candidates_recognized_boba_idx
    on public.pipeline_image_candidates (recognized_boba_id)
    where recognized_boba_id is not null;
create index if not exists pipeline_candidates_score_idx
    on public.pipeline_image_candidates (recognition_score desc nulls last)
    where state = 'recognized';

-- updated_at trigger
create or replace function public.pipeline_touch_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists pipeline_candidates_updated_at on public.pipeline_image_candidates;
create trigger pipeline_candidates_updated_at
    before update on public.pipeline_image_candidates
    for each row execute function public.pipeline_touch_updated_at();

-- ─── pipeline_card_images ─────────────────────────────────────────────────
-- Per-card state of "do we have art for this bobaId yet?" Mirrors the
-- imageAvailable field in cards.json but adds attempt history so we can
-- back off cards we've tried many times without success.
create table if not exists public.pipeline_card_images (
    boba_id                  text        primary key,
    has_image                boolean     not null default false,
    image_file               text,
    last_attempted_at        timestamptz,
    attempt_count            int         not null default 0,
    accepted_candidate_id    uuid        references public.pipeline_image_candidates(id),
    updated_at               timestamptz not null default now()
);

create index if not exists pipeline_card_images_missing_idx
    on public.pipeline_card_images (last_attempted_at nulls first)
    where has_image = false;

drop trigger if exists pipeline_card_images_updated_at on public.pipeline_card_images;
create trigger pipeline_card_images_updated_at
    before update on public.pipeline_card_images
    for each row execute function public.pipeline_touch_updated_at();

-- ─── RLS ──────────────────────────────────────────────────────────────────
-- Lock everything down. The service-role bypasses RLS, so the GH Actions
-- workflows (which use the SUPABASE_SERVICE_KEY) read/write freely.
-- Authenticated users (iOS app) and anon (web) cannot see these tables
-- under any circumstance — they have no business reading internal pipeline
-- state. If we ever need to surface pipeline status in-app, it goes through
-- a SECURITY DEFINER function with explicit, narrow projections.

alter table public.pipeline_runs              enable row level security;
alter table public.pipeline_image_candidates  enable row level security;
alter table public.pipeline_card_images       enable row level security;

-- Drop any prior policies (idempotency)
drop policy if exists pipeline_runs_deny_all              on public.pipeline_runs;
drop policy if exists pipeline_candidates_deny_all        on public.pipeline_image_candidates;
drop policy if exists pipeline_card_images_deny_all       on public.pipeline_card_images;

-- Explicit deny policies for authenticated + anon. Postgres semantics:
-- with RLS enabled and no policy that returns true, all access is denied
-- to non-superuser roles. service_role bypasses RLS by Supabase's
-- configuration. So technically these policies are belt-and-suspenders —
-- but having them spelled out makes the intent unmistakable in audits.
create policy pipeline_runs_deny_all
    on public.pipeline_runs
    for all
    to authenticated, anon
    using (false)
    with check (false);

create policy pipeline_candidates_deny_all
    on public.pipeline_image_candidates
    for all
    to authenticated, anon
    using (false)
    with check (false);

create policy pipeline_card_images_deny_all
    on public.pipeline_card_images
    for all
    to authenticated, anon
    using (false)
    with check (false);

-- ─── Verification queries (run after applying) ────────────────────────────
-- 1. Confirm tables exist + RLS is on:
--    select tablename, rowsecurity from pg_tables
--    where tablename like 'pipeline_%' order by tablename;
--
-- 2. Confirm policies are in place:
--    select tablename, policyname, cmd, roles from pg_policies
--    where tablename like 'pipeline_%' order by tablename, policyname;
--
-- 3. Smoke-test that anon really cannot read:
--    set role anon;
--    select * from public.pipeline_runs limit 1;        -- expect: 0 rows
--    reset role;
