-- Collection tracker
CREATE TABLE user_cards (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid REFERENCES auth.users ON DELETE CASCADE,
  card_number      text NOT NULL,
  designation      text DEFAULT 'personal' CHECK (designation IN ('personal','for_sale','for_trade')),
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

CREATE POLICY "own rows" ON user_cards USING (auth.uid() = user_id);
CREATE POLICY "own rows" ON decks USING (auth.uid() = user_id);
CREATE POLICY "own deck rows" ON deck_cards
  USING (deck_id IN (SELECT id FROM decks WHERE user_id = auth.uid()));
CREATE POLICY "public decks" ON decks FOR SELECT USING (is_public = true);
