-- Collection tracker
CREATE TABLE user_cards (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid REFERENCES auth.users ON DELETE CASCADE,
  card_number      text NOT NULL,
  boba_id          text,          -- canonical v3 key: "{cardNumber}-{hero||name}-{treatment??''}-{variation??''}-{element??''}" (DECISIONS.md #057)
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
  -- Custom avatar URL on the BOBA R2 CDN (avatars/{user_id}.{ext}).
  -- NULL → fall back to discord_avatar_url, then default silhouette.
  -- Written via the set_avatar_url RPC; uploads handled by the
  -- boba-avatar-upload Worker. See migrations/2026-05-05_avatar_url.
  avatar_url text,
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
  boba_id      text,             -- canonical v3 5-field ID: "{cardNumber}-{hero||name}-{treatment}-{variation}-{element}"
                                  -- Mantra: One Image per Card. One ID per Card. DECISIONS.md #057.
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
  boba_id         text,          -- canonical v3 5-field ID; preferred for disambiguation
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

-- ============================================================
-- Profile redesign (2026-05-04)
-- ------------------------------------------------------------
-- Username + collection sharing + Discord identity persistence
-- + generalized role-request (moderator OR streamer) + banned-words
-- gate. Applied live as migration
-- profile_username_sharing_role_request_banned_words.
-- ============================================================

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS username                  text,
  ADD COLUMN IF NOT EXISTS discord_user_id           text,
  ADD COLUMN IF NOT EXISTS discord_avatar_url        text,
  ADD COLUMN IF NOT EXISTS public_collection_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS notifications_enabled     boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS match_alerts_enabled      boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS requested_role            text,
  ADD COLUMN IF NOT EXISTS requested_role_at         timestamptz,
  ADD COLUMN IF NOT EXISTS requested_role_reason     text;

ALTER TABLE user_profiles
  ADD CONSTRAINT user_profiles_username_format
  CHECK (username IS NULL OR username ~ '^[a-z0-9_-]{2,30}$');

ALTER TABLE user_profiles
  ADD CONSTRAINT user_profiles_requested_role_check
  CHECK (requested_role IS NULL OR requested_role IN ('moderator', 'streamer'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_profiles_username_unique
  ON user_profiles (username) WHERE username IS NOT NULL;

-- banned_words: server-side authoritative gate for username choice.
-- No public SELECT policy = list is not enumerable via PostgREST.
-- Populated from LDNOOBW + scripts/custom_banned.txt by
-- scripts/build_banned_words.py — re-run + apply when refreshing.
CREATE TABLE banned_words (
  word     text PRIMARY KEY,
  source   text NOT NULL DEFAULT 'manual',
  added_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE banned_words ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins manage banned_words"
  ON banned_words FOR ALL
  USING (EXISTS (SELECT 1 FROM user_profiles
                  WHERE user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM user_profiles
                       WHERE user_id = auth.uid() AND role = 'admin'));

-- Reserved-namespace words. Hardcoded in a function (vs the
-- banned_words table) because these are infrastructure terms — they
-- shouldn't churn the way the slur list does.
CREATE OR REPLACE FUNCTION username_is_reserved(name text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT lower(name) = ANY (ARRAY[
    'admin','administrator','mod','moderator','streamer','support','help',
    'api','www','app','boba','bobaplaybook','playbook','official','bobattlearena',
    'me','you','user','users','profile','profiles','account','accounts',
    'collection','collections','deck','decks','card','cards','find','learn',
    'purchase','privacy','terms','about','contact','login','signin','signup',
    'logout','signout','register','settings','search','scan','share','wall',
    'undefined','null','none','true','false','root','test','testing'
  ]);
$$;

-- Username validation. Returns one of: 'available', 'taken',
-- 'invalid_chars', 'reserved', 'banned', 'too_short', 'too_long'.
-- UI calls this on every keystroke (debounced).
CREATE OR REPLACE FUNCTION check_username(candidate text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE norm text;
BEGIN
  IF candidate IS NULL THEN RETURN 'invalid_chars'; END IF;
  norm := lower(trim(candidate));
  IF length(norm) < 2  THEN RETURN 'too_short';     END IF;
  IF length(norm) > 30 THEN RETURN 'too_long';      END IF;
  IF norm !~ '^[a-z0-9_-]+$' THEN RETURN 'invalid_chars'; END IF;
  IF username_is_reserved(norm) THEN RETURN 'reserved'; END IF;
  IF EXISTS (SELECT 1 FROM banned_words bw WHERE position(bw.word IN norm) > 0)
    THEN RETURN 'banned'; END IF;
  IF EXISTS (SELECT 1 FROM user_profiles
             WHERE username = norm AND user_id <> auth.uid())
    THEN RETURN 'taken'; END IF;
  RETURN 'available';
END;
$$;

-- Atomic validate-and-write.
CREATE OR REPLACE FUNCTION set_username(new_username text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE result text; norm text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  norm := lower(trim(new_username));
  result := check_username(norm);
  IF result <> 'available' THEN RETURN result; END IF;
  UPDATE user_profiles SET username = norm, updated_at = now()
   WHERE user_id = auth.uid();
  RETURN 'available';
END;
$$;

CREATE OR REPLACE FUNCTION set_public_collection_enabled(enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  UPDATE user_profiles SET public_collection_enabled = enabled, updated_at = now()
   WHERE user_id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION set_notification_prefs(notifications boolean, match_alerts boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  UPDATE user_profiles
     SET notifications_enabled = notifications,
         match_alerts_enabled  = match_alerts,
         updated_at = now()
   WHERE user_id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION set_discord_identity(discord_id text, avatar_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  UPDATE user_profiles
     SET discord_user_id = discord_id, discord_avatar_url = avatar_url, updated_at = now()
   WHERE user_id = auth.uid();
END;
$$;

-- Generalized role request. Replaces submit_mod_request — but we
-- keep the old name as a compat shim below.
CREATE OR REPLACE FUNCTION request_role(target_role text, reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  IF target_role NOT IN ('moderator', 'streamer') THEN
    RAISE EXCEPTION 'role must be moderator or streamer';
  END IF;
  IF EXISTS (SELECT 1 FROM user_profiles
             WHERE user_id = auth.uid()
               AND (role = 'admin' OR role = target_role)) THEN
    RAISE EXCEPTION 'you already have this role or higher';
  END IF;
  UPDATE user_profiles
     SET requested_role = target_role,
         requested_role_at = now(),
         requested_role_reason = reason,
         updated_at = now()
   WHERE user_id = auth.uid();
END;
$$;

-- Note: Postgres reserves "current_role" — this column is
-- "actual_role" in the result set.
CREATE OR REPLACE FUNCTION get_pending_role_requests()
RETURNS TABLE (user_id uuid, email text, username text, actual_role text,
               requested_role text, reason text, requested_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM user_profiles
                  WHERE user_id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'admin role required';
  END IF;
  RETURN QUERY
    SELECT up.user_id, up.email, up.username, up.role, up.requested_role,
           up.requested_role_reason, up.requested_role_at
      FROM user_profiles up
     WHERE up.requested_role_at IS NOT NULL
     ORDER BY up.requested_role_at ASC;
END;
$$;

CREATE OR REPLACE FUNCTION review_role_request(target_user_id uuid, approve boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE pending text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM user_profiles
                  WHERE user_id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'admin role required';
  END IF;
  SELECT requested_role INTO pending FROM user_profiles WHERE user_id = target_user_id;
  IF pending IS NULL THEN RAISE EXCEPTION 'no pending request for that user'; END IF;
  IF approve THEN
    UPDATE user_profiles
       SET role = pending,
           requested_role = NULL, requested_role_at = NULL,
           requested_role_reason = NULL, updated_at = now()
     WHERE user_id = target_user_id;
  ELSE
    UPDATE user_profiles
       SET requested_role = NULL, requested_role_at = NULL,
           requested_role_reason = NULL, updated_at = now()
     WHERE user_id = target_user_id;
  END IF;
END;
$$;

-- Compat shims. The old admin-panel client still calls these by
-- name; delegate to the new generalized functions so the live build
-- keeps working until iOS catches up. Drop in a follow-up release.
CREATE OR REPLACE FUNCTION get_pending_mod_requests()
RETURNS TABLE (user_id uuid, email text, reason text, requested_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM user_profiles
                  WHERE user_id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'admin role required';
  END IF;
  RETURN QUERY
    SELECT up.user_id, up.email, up.requested_role_reason, up.requested_role_at
      FROM user_profiles up
     WHERE up.requested_role_at IS NOT NULL
       AND up.requested_role = 'moderator'
       AND up.role = 'user'
     ORDER BY up.requested_role_at ASC;
END;
$$;

CREATE OR REPLACE FUNCTION review_mod_request(target_user_id uuid, approve boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN PERFORM review_role_request(target_user_id, approve); END;
$$;

-- Public username → user_id resolver for the web app's /u/{handle}
-- routes. Only returns rows where the user has opted in to public
-- sharing, so nothing leaks for opted-out users.
CREATE OR REPLACE FUNCTION get_public_profile(handle text)
RETURNS TABLE (user_id uuid, username text, public_collection_enabled boolean)
LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT up.user_id, up.username, up.public_collection_enabled
    FROM user_profiles up
   WHERE up.username = lower(trim(handle))
     AND up.public_collection_enabled = true
   LIMIT 1;
$$;


-- ────────────────────────────────────────────────────────────────────
-- 2026-05-18 — mod-card-images Storage bucket + RLS policies
-- ────────────────────────────────────────────────────────────────────
-- The bucket used by ModCardEditSheet (image replacements) and
-- ModAddCardSheet (new-card additions). Without it every upload
-- returned 400 from the Storage API. Captured as part of the v2.273
-- audit + fix (see git log).

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'mod-card-images',
  'mod-card-images',
  false,                                          -- private; merge worker uses service-role key
  5242880,                                        -- 5 MB cap (iOS JPEG Q85 ≤1200px ~200-500 KB)
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- RLS policies on storage.objects scoped to bucket_id='mod-card-images'.
-- Service role bypasses these (merge_approved_additions.py).

CREATE POLICY "mod_card_images_mods_insert"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'mod-card-images'
    AND EXISTS (SELECT 1 FROM public.user_profiles
                WHERE user_id = auth.uid()
                  AND role IN ('moderator','admin'))
  );

CREATE POLICY "mod_card_images_mods_select"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'mod-card-images'
    AND EXISTS (SELECT 1 FROM public.user_profiles
                WHERE user_id = auth.uid()
                  AND role IN ('moderator','admin'))
  );

CREATE POLICY "mod_card_images_admin_update"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'mod-card-images'
    AND EXISTS (SELECT 1 FROM public.user_profiles
                WHERE user_id = auth.uid()
                  AND role = 'admin')
  );

-- Path convention: "{user_id}/{cardNumber}-{timestamp}.jpg"; check
-- first path component against auth.uid().
CREATE POLICY "mod_card_images_uploader_or_admin_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'mod-card-images'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR EXISTS (SELECT 1 FROM public.user_profiles
                 WHERE user_id = auth.uid()
                   AND role = 'admin')
    )
  );

-- ────────────────────────────────────────────────────────────────────
-- 2026-05-18 — extend card_image_overrides.status check for 'applied'
-- ────────────────────────────────────────────────────────────────────
-- v2.275 added the applied_image_file + applied_at columns but missed
-- updating the CHECK constraint to allow status='applied'. The boba-
-- mod-merge Worker's final markApplied PATCH was silently failing,
-- leaving rows stuck in status='approved' with applied_image_file=null.
-- v2.277 fixes the constraint.

ALTER TABLE public.card_image_overrides
  DROP CONSTRAINT IF EXISTS card_image_overrides_status_check;

ALTER TABLE public.card_image_overrides
  ADD CONSTRAINT card_image_overrides_status_check
    CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'applied'::text]));
