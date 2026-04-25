-- ════════════════════════════════════════════════════════════════
-- Practice stats + CPU strategies (forward-looking schema)
-- ════════════════════════════════════════════════════════════════
--
-- Two tables that the practice setup view references aspirationally
-- ("Coming soon — player ranking" / "Coming soon — named CPU
-- opponents"). Schema lands now so we can start writing data on
-- match completion ahead of the user-facing surfaces.
--
-- Apply via Supabase dashboard (SQL editor) or the CLI:
--   supabase db push --include supabase/migrations/2026_04_25_*

-- ── user_practice_stats ─────────────────────────────────────────
-- One row per authenticated user, populated lazily on first
-- match completion. ELO mirrors the chess-style 1200 baseline so
-- the future ranking surface has familiar magnitudes.

create table if not exists public.user_practice_stats (
    user_id            uuid primary key references auth.users(id) on delete cascade,
    matches_played     int  not null default 0,
    matches_won        int  not null default 0,
    matches_lost       int  not null default 0,
    matches_drawn      int  not null default 0,
    elo                int  not null default 1200,
    peak_elo           int  not null default 1200,
    last_match_at      timestamptz,
    favorite_mode      text,            -- 'rookie' / 'substitution' / 'playmaker'
    favorite_format    text,            -- 'standard' / 'spec' / 'spec_plus' / 'limited'
    streak_current     int  not null default 0,
    streak_best        int  not null default 0,
    -- Per-CPU-difficulty record stored as JSONB so we can iterate
    -- on the difficulty taxonomy without a migration each time.
    -- Shape: { "rookie": {"w":N,"l":N}, "coach": {...}, ... }
    record_by_cpu      jsonb not null default '{}'::jsonb,
    updated_at         timestamptz not null default now()
);

alter table public.user_practice_stats enable row level security;

create policy if not exists "users read own stats"
    on public.user_practice_stats for select
    using (auth.uid() = user_id);

create policy if not exists "users write own stats"
    on public.user_practice_stats for insert
    with check (auth.uid() = user_id);

create policy if not exists "users update own stats"
    on public.user_practice_stats for update
    using (auth.uid() = user_id);

-- ── cpu_strategies ──────────────────────────────────────────────
-- Static catalog of named CPU opponents. Read-only for clients;
-- seeded by a service-role migration. We drive the practice view
-- "CPU Opponents" picker from this table.
--
-- Strategy parameters live in JSONB so the engine can read them
-- without a schema migration each time we add a knob (e.g. sub
-- aggression curve, play-pacing weights, weapon-bias).

create table if not exists public.cpu_strategies (
    id              text primary key,
    name            text not null,
    elo             int  not null default 1200,
    avatar_emoji    text,
    blurb           text,                                  -- 1-line description for the picker
    parameters      jsonb not null default '{}'::jsonb,    -- engine knobs
    unlock_after_matches int not null default 0,           -- gate harder opponents on early-game progression
    sort_order      int  not null default 0,
    created_at      timestamptz not null default now()
);

alter table public.cpu_strategies enable row level security;

create policy if not exists "all read cpu strategies"
    on public.cpu_strategies for select
    using (true);

-- Seed the initial difficulty ladder. Parameters intentionally
-- spare — the engine will start with a single strategy lookup
-- and we'll grow the parameter shape as we go.
insert into public.cpu_strategies (id, name, elo, avatar_emoji, blurb, parameters, unlock_after_matches, sort_order)
values
    ('rookie',  'Rookie',  900,  '🎒', 'Plays randomly. Misses obvious counters.',
        '{"sub_aggression":0.2,"play_density":0.3,"weapon_bias":null}'::jsonb, 0, 10),
    ('coach',   'Coach',   1200, '📋', 'Balanced — current default heuristic.',
        '{"sub_aggression":0.5,"play_density":0.6,"weapon_bias":null}'::jsonb, 0, 20),
    ('captain', 'Captain', 1400, '🛡️', 'Plays to weapon synergy and defends late battles.',
        '{"sub_aggression":0.6,"play_density":0.7,"weapon_bias":"matchup"}'::jsonb, 5, 30),
    ('master',  'Master',  1600, '🏆', 'Pressures HD economy and runs the comeback path.',
        '{"sub_aggression":0.8,"play_density":0.85,"weapon_bias":"matchup","economy_pressure":true}'::jsonb, 15, 40),
    ('gm',      'Grandmaster', 1800, '👑', 'Reads your tendencies. Don''t feed her info.',
        '{"sub_aggression":0.9,"play_density":0.95,"weapon_bias":"matchup","economy_pressure":true,"reads_player":true}'::jsonb, 40, 50)
on conflict (id) do nothing;
