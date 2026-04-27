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

-- User profiles: one row per auth.users entry, stores role.
-- 'streamer' role added 2026-04-23 (migration add_streamer_role_and_shows)
-- — a streamer preps for Whatnot shows via the Shows feature (see below).
CREATE TABLE user_profiles (
  user_id    uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  email      text,
  role       text NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'moderator', 'admin', 'streamer')),
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

-- ============================================================
-- Mod promotion requests (2026-04-21)
-- ------------------------------------------------------------
-- Users can request moderator access from the Profile tab. Admins
-- see pending requests in the Admin panel and either promote the
-- user (role → moderator) or clear the request.
-- ============================================================

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS mod_request_reason text,
  ADD COLUMN IF NOT EXISTS mod_request_at     timestamptz;

-- Users can update their OWN mod request fields (but not role/email/etc).
CREATE POLICY "users submit own mod request"
  ON user_profiles FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- RPC for admins: list pending mod requests (email + reason + timestamp).
-- SECURITY DEFINER + role-gated so regular users can't enumerate profiles.
CREATE OR REPLACE FUNCTION get_pending_mod_requests()
RETURNS TABLE (user_id uuid, email text, reason text, requested_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'admin role required';
  END IF;
  RETURN QUERY
    SELECT up.user_id, up.email, up.mod_request_reason, up.mod_request_at
    FROM user_profiles up
    WHERE up.mod_request_at IS NOT NULL AND up.role = 'user'
    ORDER BY up.mod_request_at ASC;
END;
$$;

-- RPC for admins: approve (promote to moderator + clear request) or
-- deny (clear request only). Single function — pass approve=true/false.
CREATE OR REPLACE FUNCTION review_mod_request(target_user_id uuid, approve boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'admin role required';
  END IF;
  IF approve THEN
    UPDATE user_profiles
      SET role = 'moderator',
          mod_request_reason = NULL,
          mod_request_at = NULL,
          updated_at = now()
      WHERE user_id = target_user_id;
  ELSE
    UPDATE user_profiles
      SET mod_request_reason = NULL,
          mod_request_at = NULL,
          updated_at = now()
      WHERE user_id = target_user_id;
  END IF;
END;
$$;

-- ============================================================
-- Streamer Shows (2026-04-23)
-- ============================================================
--
-- A "show" is a streamer's pre-curated list of cards used to prep for
-- a live Whatnot broadcast — giveaways, chasers, running totals. Cards
-- in a show are NOT in the user's collection; shows are a separate
-- top-level container. Applied live via migration
-- add_streamer_role_and_shows.

CREATE TABLE shows (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  name        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_shows_user_id ON shows (user_id);

CREATE TABLE show_cards (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  show_id             uuid NOT NULL REFERENCES shows(id) ON DELETE CASCADE,
  boba_id             text NOT NULL,
  sort_order          int  NOT NULL DEFAULT 0,
  excluded_from_total boolean NOT NULL DEFAULT false,
  -- Streamer marks a card as a "big hit" — wall generator promotes it
  -- to a hero-row tile that's much larger than the standard grid
  -- thumbnails. Layout flows responsively: 1 big hit alone in a wide
  -- row, 2–3 big hits sharing one row, 4+ split across multiple
  -- big-hit rows above the standard grid.
  is_big_hit          boolean NOT NULL DEFAULT false,
  added_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_show_cards_show_id ON show_cards (show_id);

ALTER TABLE shows      ENABLE ROW LEVEL SECURITY;
ALTER TABLE show_cards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own shows" ON shows
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "own show rows" ON show_cards
  FOR ALL
  USING     (show_id IN (SELECT id FROM shows WHERE user_id = auth.uid()))
  WITH CHECK (show_id IN (SELECT id FROM shows WHERE user_id = auth.uid()));

-- Auto-bump updated_at on every show mutation.
CREATE OR REPLACE FUNCTION touch_shows_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER trg_shows_touch_updated_at
  BEFORE UPDATE ON shows
  FOR EACH ROW EXECUTE FUNCTION touch_shows_updated_at();
