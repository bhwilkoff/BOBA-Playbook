-- Collection tracker
CREATE TABLE user_cards (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid REFERENCES auth.users ON DELETE CASCADE,
  card_number      text NOT NULL,
  boba_id          text,          -- canonical v2 key: "{cardNumber}-{hero}-{treatment??''}-{variation??''}" (One ID per Card)
  designation      text DEFAULT 'personal' CHECK (designation IN ('personal','for_sale','for_trade','wanted','grails')),
  condition        text,
  serial_number    int,
  grade            text,
  grading_company  text,
  purchase_price   decimal(10,2),
  asking_price     decimal(10,2),
  estimated_value  decimal(10,2),
  last_price_check timestamptz,
  acquired_at      timestamptz DEFAULT now(),
  notes            text
);

-- Decks
CREATE TABLE decks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES auth.users ON DELETE CASCADE,
  name        text NOT NULL,
  description text,
  is_public   boolean DEFAULT false,
  archetype   text,
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);

CREATE TABLE deck_cards (
  deck_id     uuid REFERENCES decks(id) ON DELETE CASCADE,
  card_number text NOT NULL,
  quantity    int DEFAULT 1,
  PRIMARY KEY (deck_id, card_number)
);

-- RLS
ALTER TABLE user_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE decks ENABLE ROW LEVEL SECURITY;
ALTER TABLE deck_cards ENABLE ROW LEVEL SECURITY;

-- user_cards: separate policies per operation so INSERT sets user_id = auth.uid()
CREATE POLICY "select own cards"   ON user_cards FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "insert own cards"   ON user_cards FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "update own cards"   ON user_cards FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "delete own cards"   ON user_cards FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "own rows" ON decks USING (auth.uid() = user_id);
CREATE POLICY "own deck rows" ON deck_cards
  USING (deck_id IN (SELECT id FROM decks WHERE user_id = auth.uid()));
CREATE POLICY "public decks" ON decks FOR SELECT USING (is_public = true);

-- ============================================================
-- Moderator / Admin roles
-- ============================================================

-- User profiles: one row per auth.users entry, stores role
CREATE TABLE user_profiles (
  user_id    uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  email      text,
  role       text NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'moderator', 'admin')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Every authenticated user can read their own profile
CREATE POLICY "read own profile"
  ON user_profiles FOR SELECT
  USING (auth.uid() = user_id);

-- Admins can read all profiles (for admin panel)
CREATE POLICY "admins read all profiles"
  ON user_profiles FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM user_profiles up WHERE up.user_id = auth.uid() AND up.role = 'admin')
  );

-- Only admins can update roles
CREATE POLICY "admins update profiles"
  ON user_profiles FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM user_profiles up WHERE up.user_id = auth.uid() AND up.role = 'admin')
  );

-- Auto-create a profile row on new signup via trigger (captures email)
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.user_profiles (user_id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (user_id) DO UPDATE SET email = EXCLUDED.email;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Card corrections: mods submit field-level fixes to static card data
CREATE TABLE card_corrections (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  boba_id      text,             -- canonical 4-field ID: "{cardNumber}-{hero}-{treatment}-{variation}"
                                  -- Mantra: One Image per Card. One ID per Card.
  card_number  text NOT NULL,
  corrections  jsonb NOT NULL,   -- e.g. {"hero": "BoJax", "element": "FIRE"}
  notes        text,
  submitted_by uuid NOT NULL REFERENCES auth.users ON DELETE SET NULL,
  status       text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by  uuid REFERENCES auth.users ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE card_corrections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mods submit corrections"
  ON card_corrections FOR INSERT
  WITH CHECK (
    submitted_by = auth.uid() AND
    EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role IN ('moderator', 'admin'))
  );

CREATE POLICY "mods read corrections"
  ON card_corrections FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role IN ('moderator', 'admin'))
  );

CREATE POLICY "admins review corrections"
  ON card_corrections FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role = 'admin')
  );

-- Card image overrides: mods can flag existing R2 images for removal
-- or register an approved replacement (Supabase Storage path)
CREATE TABLE card_image_overrides (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  boba_id         text,          -- canonical 4-field ID; preferred for disambiguation
  card_number     text NOT NULL,
  action          text NOT NULL CHECK (action IN ('replace', 'remove')),
  storage_path    text,   -- Supabase Storage path (for 'replace' action)
  submitted_by    uuid NOT NULL REFERENCES auth.users ON DELETE SET NULL,
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by     uuid REFERENCES auth.users ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE card_image_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "mods submit image overrides"
  ON card_image_overrides FOR INSERT
  WITH CHECK (
    submitted_by = auth.uid() AND
    EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role IN ('moderator', 'admin'))
  );

CREATE POLICY "mods read image overrides"
  ON card_image_overrides FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role IN ('moderator', 'admin'))
  );

CREATE POLICY "admins review image overrides"
  ON card_image_overrides FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role = 'admin')
  );

-- ============================================================
-- MIGRATION (run in Supabase SQL editor for existing projects)
-- ============================================================
--
-- M4 Deck Builder migration (2026-04-13):
-- ALTER TABLE decks ADD COLUMN IF NOT EXISTS format text DEFAULT 'playmaker'
--   CHECK (format IN ('rookie','substitution','playmaker','spec','limited'));
--
-- -- Rebuild deck_cards with boba_id + card_type + sort_order
-- -- (safe to run once — the old table had no real data yet)
-- ALTER TABLE deck_cards ADD COLUMN IF NOT EXISTS boba_id text;
-- ALTER TABLE deck_cards ADD COLUMN IF NOT EXISTS card_type text DEFAULT 'hero'
--   CHECK (card_type IN ('hero','play','bonus_play','hot_dog','sideboard'));
-- ALTER TABLE deck_cards ADD COLUMN IF NOT EXISTS sort_order integer DEFAULT 0;
-- -- After backfill (if any) you can drop the old columns:
-- -- ALTER TABLE deck_cards DROP COLUMN IF EXISTS card_number;
-- -- ALTER TABLE deck_cards DROP COLUMN IF EXISTS quantity;
-- -- ALTER TABLE deck_cards DROP CONSTRAINT IF EXISTS deck_cards_pkey;
-- -- ALTER TABLE deck_cards ADD PRIMARY KEY (id);
-- -- ALTER TABLE deck_cards ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid();
--
-- ALTER TABLE user_cards DROP CONSTRAINT IF EXISTS user_cards_designation_check;
-- ALTER TABLE user_cards ADD CONSTRAINT user_cards_designation_check
--   CHECK (designation IN ('personal','for_sale','for_trade','wanted','grails'));
--
-- -- Replace single "own rows" policy with per-operation policies:
-- DROP POLICY IF EXISTS "own rows" ON user_cards;
-- CREATE POLICY "select own cards" ON user_cards FOR SELECT USING (auth.uid() = user_id);
-- CREATE POLICY "insert own cards" ON user_cards FOR INSERT WITH CHECK (auth.uid() = user_id);
-- CREATE POLICY "update own cards" ON user_cards FOR UPDATE USING (auth.uid() = user_id);
-- CREATE POLICY "delete own cards" ON user_cards FOR DELETE USING (auth.uid() = user_id);
--
-- -- bobaId rollout (2026-04-09): add boba_id to all three tables + indexes
-- ALTER TABLE user_cards            ADD COLUMN IF NOT EXISTS boba_id text;
-- ALTER TABLE card_corrections      ADD COLUMN IF NOT EXISTS boba_id text;
-- ALTER TABLE card_image_overrides  ADD COLUMN IF NOT EXISTS boba_id text;
-- CREATE INDEX IF NOT EXISTS idx_card_corrections_boba_id     ON card_corrections    (boba_id);
-- CREATE INDEX IF NOT EXISTS idx_card_image_overrides_boba_id ON card_image_overrides (boba_id);
