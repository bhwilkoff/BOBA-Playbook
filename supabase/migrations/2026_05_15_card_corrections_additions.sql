-- 2026-05-15: extend card_corrections to handle new-card ADDITIONS
--
-- The same table now carries two kinds of records:
--   kind='correction' — existing behavior. corrections jsonb is a DELTA
--                       of fields to change on an existing card. card_number
--                       references the existing card.
--   kind='addition'   — NEW. corrections jsonb contains the FULL spec for a
--                       new card. card_number is the new card's number. The
--                       boba_id column carries the pre-computed bobaId per
--                       the canonical formula (see scripts/boba_id.py).
--
-- Adding a column with a default + CHECK constraint is safe online; existing
-- rows pick up 'correction' automatically.
--
-- image_storage_path points into the existing `mod-card-images` Supabase
-- Storage bucket. The merge_approved_additions.py worker reads this path,
-- pulls the image, re-encodes to WebP tiers, and PUTs to R2.

ALTER TABLE card_corrections
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'correction'
    CHECK (kind IN ('correction', 'addition')),
  ADD COLUMN IF NOT EXISTS image_storage_path text,
  -- Set by scripts/merge_approved_additions.py after the new card has
  -- been written into cards.json + uploaded to R2. The merge worker
  -- filters on `merged_at IS NULL` so a re-run skips already-processed
  -- rows.
  ADD COLUMN IF NOT EXISTS merged_at timestamptz;

-- Filter index for the admin queue + merge worker — both query
-- (kind, status) and want results sorted by created_at.
CREATE INDEX IF NOT EXISTS idx_card_corrections_kind_status_created
  ON card_corrections (kind, status, created_at);

-- Index the merge worker's exact filter shape.
CREATE INDEX IF NOT EXISTS idx_card_corrections_pending_additions
  ON card_corrections (kind, status, merged_at)
  WHERE kind = 'addition' AND merged_at IS NULL;

-- The 'mods submit corrections' INSERT policy already covers additions
-- since the row still passes the moderator/admin role check. No new
-- policy needed; verified via `\d card_corrections` after running this
-- migration in dev.
