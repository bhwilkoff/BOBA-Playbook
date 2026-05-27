-- boba-pricing D1 — Tier 1 vanish-inference store (PRICING_PLAYBOOK.md §3.2)
--
-- We generate our own sold-history from public eBay Browse listings over
-- time: snapshot active listings per card, and when a listing vanishes from
-- a later snapshot, infer "sold @ last-seen price" with a confidence score.
-- Apply:  wrangler d1 execute boba-pricing --remote --file=workers/pricing-tracker/schema.sql

CREATE TABLE IF NOT EXISTS listings (
  item_id         TEXT    PRIMARY KEY,   -- eBay /itm/{id}, or "wn-{id}" for Whatnot
  boba_id         TEXT    NOT NULL,      -- our card identifier
  source          TEXT    DEFAULT 'ebay',-- 'ebay' | 'whatnot' (marketplace the listing came from)
  price_usd       REAL    NOT NULL,      -- current asking
  shipping_usd    REAL,                  -- separated when known
  condition       TEXT,                  -- e.g. "Near Mint" (when proxy exposes it)
  format          TEXT,                  -- BUY_IT_NOW | AUCTION (when known)
  end_time        TEXT,                  -- ISO8601 for AUCTION (when known)
  seller_id       TEXT,                  -- to detect bulk delist (when known)
  image_url       TEXT,
  title           TEXT,
  first_seen      TEXT    NOT NULL,      -- ISO8601 first snapshot
  last_seen       TEXT    NOT NULL,      -- ISO8601 most recent snapshot
  vanished_at     TEXT,                  -- ISO8601 first snapshot it was missing
  inferred_sold   INTEGER DEFAULT 0,     -- 0 | 1
  sold_confidence REAL,                  -- 0.0-1.0 (§3.4)
  sold_price_usd  REAL                   -- price at last_seen if inferred sold
);
CREATE INDEX IF NOT EXISTS idx_listings_boba_id  ON listings(boba_id);
CREATE INDEX IF NOT EXISTS idx_listings_vanished ON listings(vanished_at);
CREATE INDEX IF NOT EXISTS idx_listings_lastseen ON listings(last_seen);

-- Per-run metadata so we can audit gaps + cadence.
CREATE TABLE IF NOT EXISTS snapshot_runs (
  run_id        INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at    TEXT    NOT NULL,
  finished_at   TEXT,
  cards_polled  INTEGER NOT NULL DEFAULT 0,
  listings_seen INTEGER NOT NULL DEFAULT 0,
  vanish_count  INTEGER NOT NULL DEFAULT 0,
  error         TEXT
);
