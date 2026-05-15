-- 2026-05-15: user_custom_rainbows
--
-- User-defined collecting goals — e.g., "Cupid in Griffey only,"
-- "All Glows," "Every Hot Dog." A custom rainbow is a saved filter
-- expression over the catalog plus a user-given name; the app
-- renders progress (owned / total matching cards) on top of it.
--
-- Filter shape (criteria jsonb):
--   {
--     "heroes":          [String], // OR within, AND across categories
--     "sets":            [String],
--     "subSets":         [String],
--     "elements":        [String], // catalog element / "weapon"
--     "treatments":      [String],
--     "cardTypes":       [String], // Hero | Play | HotDog | Sealed Product
--     "releases":        [String],
--     "inspiredInkOnly": Boolean    // toggle, true = only InspiredInk cards
--   }
-- Any missing/empty dimension means "no filter on that dimension."
-- The cards.json catalog is the source of truth for valid values;
-- the iOS editor pulls picker options from the user's current
-- bundle so options stay in sync as the catalog grows.

CREATE TABLE IF NOT EXISTS user_custom_rainbows (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
    name        text NOT NULL CHECK (length(trim(name)) > 0),
    criteria    jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_custom_rainbows_user_created
    ON user_custom_rainbows (user_id, created_at DESC);

ALTER TABLE user_custom_rainbows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users read their own rainbows"
    ON user_custom_rainbows FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "users insert their own rainbows"
    ON user_custom_rainbows FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "users update their own rainbows"
    ON user_custom_rainbows FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "users delete their own rainbows"
    ON user_custom_rainbows FOR DELETE
    USING (user_id = auth.uid());

-- Refresh updated_at on UPDATE so the iOS store can show
-- "edited today" / "edited 2d ago" later if we want it.
CREATE OR REPLACE FUNCTION touch_user_custom_rainbows_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS user_custom_rainbows_touch_updated_at
    ON user_custom_rainbows;

CREATE TRIGGER user_custom_rainbows_touch_updated_at
    BEFORE UPDATE ON user_custom_rainbows
    FOR EACH ROW EXECUTE FUNCTION touch_user_custom_rainbows_updated_at();
