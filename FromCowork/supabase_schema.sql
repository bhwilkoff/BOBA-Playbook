-- BOBA Playbook — Supabase Schema
-- Run this in the Supabase SQL Editor after creating the project

-- ─────────────────────────────────────────
-- User Card Collection
-- ─────────────────────────────────────────
CREATE TABLE user_cards (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid REFERENCES auth.users ON DELETE CASCADE NOT NULL,
  card_number      text NOT NULL,       -- matches cardNumber in cards.json
  designation      text NOT NULL DEFAULT 'personal'
                   CHECK (designation IN ('personal', 'for_sale', 'for_trade')),
  condition        text CHECK (condition IN ('NM', 'EX', 'VG', 'G', 'PR')),
  serial_number    int,
  grade            text,               -- "PSA 10", "BGS 9.5", "CGC 10", etc.
  grading_company  text,               -- "PSA", "BGS", "CGC", "SGC"
  purchase_price   decimal(10,2),
  asking_price     decimal(10,2),      -- used when designation = 'for_sale'
  estimated_value  decimal(10,2),      -- last fetched comp value
  last_price_check timestamptz,
  acquired_at      timestamptz NOT NULL DEFAULT now(),
  notes            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX user_cards_user_id_idx ON user_cards(user_id);
CREATE INDEX user_cards_card_number_idx ON user_cards(card_number);

-- ─────────────────────────────────────────
-- Decks
-- ─────────────────────────────────────────
CREATE TABLE decks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES auth.users ON DELETE CASCADE NOT NULL,
  name        text NOT NULL,
  description text,
  is_public   boolean NOT NULL DEFAULT false,
  archetype   text CHECK (archetype IN ('offensive', 'defensive', 'balanced', 'control', 'combo')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE deck_cards (
  deck_id     uuid REFERENCES decks(id) ON DELETE CASCADE NOT NULL,
  card_number text NOT NULL,           -- matches cardNumber in cards.json
  quantity    int NOT NULL DEFAULT 1 CHECK (quantity > 0),
  PRIMARY KEY (deck_id, card_number)
);

CREATE INDEX decks_user_id_idx ON decks(user_id);
CREATE INDEX decks_public_idx ON decks(is_public) WHERE is_public = true;

-- ─────────────────────────────────────────
-- Row Level Security
-- ─────────────────────────────────────────
ALTER TABLE user_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE decks      ENABLE ROW LEVEL SECURITY;
ALTER TABLE deck_cards ENABLE ROW LEVEL SECURITY;

-- user_cards: users can only read/write their own rows
CREATE POLICY "user_cards_own_rows" ON user_cards
  USING      (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- decks: users own their decks; public decks readable by all
CREATE POLICY "decks_own_rows" ON decks
  USING      (auth.uid() = user_id OR is_public = true)
  WITH CHECK (auth.uid() = user_id);

-- deck_cards: accessible if user owns the deck
CREATE POLICY "deck_cards_via_deck" ON deck_cards
  USING (deck_id IN (
    SELECT id FROM decks WHERE user_id = auth.uid() OR is_public = true
  ))
  WITH CHECK (deck_id IN (
    SELECT id FROM decks WHERE user_id = auth.uid()
  ));

-- ─────────────────────────────────────────
-- Auto-update updated_at triggers
-- ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER user_cards_updated_at BEFORE UPDATE ON user_cards
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER decks_updated_at BEFORE UPDATE ON decks
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
