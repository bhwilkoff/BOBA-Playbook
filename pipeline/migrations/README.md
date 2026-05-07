# Pipeline migrations

SQL files applied to the BOBA-Playbook Supabase project to create + maintain the pipeline tables. They share the project with `user_cards` / `decks` / `user_profiles` but are RLS-locked to service-role only — see `0001_pipeline_initial.sql` for the policy detail.

## Applying a migration

1. Open the [Supabase Dashboard](https://supabase.com/dashboard) → BOBA Playbook project → SQL Editor.
2. New query → paste the migration file's contents → Run.
3. Run the verification queries at the bottom of the file. RLS should be `t` for all three tables; `pg_policies` should show one `_deny_all` policy per table.
4. Smoke-test as anon — the read should return zero rows.

Migrations are idempotent (`create table if not exists`, `drop policy if exists`, etc.) so re-running is safe.

## Naming convention

`NNNN_short_description.sql` — sequence number + snake_case slug. Number wraps at 9999 if we ever get there.

## What lives where

| File | Purpose |
|---|---|
| `0001_pipeline_initial.sql` | Initial schema — `pipeline_runs`, `pipeline_image_candidates`, `pipeline_card_images` + RLS lockdown |
| `0002_pipeline_state_extensions.sql` | Adds `committed` and `superseded` to the candidate state enum (Stage C terminal states) |
