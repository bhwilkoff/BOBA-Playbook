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

-- ── Long-term data layers (PRICING_PLAYBOOK §6.6) ───────────────────────────
-- The `listings` table above is point-in-time — it tells you a card's CURRENT
-- listings and their CURRENT prices. The three tables below build the
-- DURABLE record we own and that compounds into a real estimator-tuning
-- dataset over time. Additive to the listings model — nothing in the
-- existing read path depends on them; they're populated alongside, queried
-- by future weight-learning + accuracy-audit code.

-- Price-trajectory snapshots — one row per OBSERVED price change on a
-- listing. If a listing stays at $20 for 30 days we get 1 row; if it walks
-- $30 → $25 → $20 we get 3 rows, capturing the price discovery process.
-- Lets us learn how asks decay toward sold (the natural sold-haircut signal)
-- and gives us a richer time series than just (first_seen, last_seen, vanished).
CREATE TABLE IF NOT EXISTS listing_snapshots (
  item_id     TEXT    NOT NULL,
  boba_id     TEXT    NOT NULL,
  snapshot_at TEXT    NOT NULL,         -- ISO8601 when we observed this price
  price_usd   REAL    NOT NULL,
  source      TEXT    DEFAULT 'ebay',   -- ebay | whatnot
  PRIMARY KEY (item_id, snapshot_at)
);
CREATE INDEX IF NOT EXISTS idx_listing_snapshots_boba ON listing_snapshots(boba_id, snapshot_at);

-- Immutable sold-event archive. Every vanish-inferred sale (sold_confidence
-- ≥ floor) AND every mod-approved community comp gets one immutable row
-- here. This is the "data we own" — the legacy dataset that grows whether
-- or not we re-ingest, gets queried by the hedonic-model weight learner
-- when there's enough volume (§6.3), and is never overwritten by another
-- ingest cycle. duration_days helps the confidence model learn the
-- listing-duration → sold-confidence relationship from real outcomes.
CREATE TABLE IF NOT EXISTS sold_events (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  boba_id         TEXT    NOT NULL,
  sold_at         TEXT    NOT NULL,     -- ISO8601 (vanish time, or community-reported)
  sold_price_usd  REAL    NOT NULL,
  confidence      REAL,                 -- 0.0-1.0; community comps = 1.0
  source          TEXT    NOT NULL,     -- ebay-inferred | whatnot-inferred | community-{platform}
  item_id         TEXT,                 -- original listing id (when known)
  duration_days   REAL,                 -- how long the listing was active before vanishing
  archived_at     TEXT    NOT NULL,     -- when WE recorded this row
  factors_json    TEXT                  -- card factors at sold time, JSON — for hedonic model
);
CREATE INDEX IF NOT EXISTS idx_sold_events_boba    ON sold_events(boba_id, sold_at);
CREATE INDEX IF NOT EXISTS idx_sold_events_sold_at ON sold_events(sold_at);

-- Estimate-accuracy audit log. When a sold event lands for a card that had
-- an estimate at the time, we log the (estimate, actual) pair so we can
-- measure error and learn weights. This is the LOOP that makes the
-- estimator "really good" — without it, the model can't see how it's doing.
-- model_version lets us A/B compare model iterations on the same sold-event
-- stream.
CREATE TABLE IF NOT EXISTS estimate_audits (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  boba_id             TEXT    NOT NULL,
  estimated_at        TEXT    NOT NULL,   -- ISO8601, when the estimate was generated
  estimate_mid_usd    REAL    NOT NULL,
  estimate_low_usd    REAL,
  estimate_high_usd   REAL,
  estimate_n_comps    INTEGER,
  estimate_avg_sim    REAL,
  model_method        TEXT,
  model_version       TEXT,
  sold_event_id       INTEGER REFERENCES sold_events(id),
  sold_price_usd      REAL,
  sold_at             TEXT,
  error_pct           REAL                -- (sold - estimate_mid) / sold; signed
);
CREATE INDEX IF NOT EXISTS idx_estimate_audits_boba    ON estimate_audits(boba_id);
CREATE INDEX IF NOT EXISTS idx_estimate_audits_model   ON estimate_audits(model_version);
