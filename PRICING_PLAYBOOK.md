# BOBA Playbook — Pricing Pipeline Playbook (post-Radish, post-MI)

> Build doc. Picks up where [`RADISH_REMOVAL_LOOP.md`](./RADISH_REMOVAL_LOOP.md) ends. Ratified direction 2026-05-26 after the first replacement attempt (cron-driven `boba-price-estimator` over our own catalog) was confirmed insufficient: it depends on eBay sold-comp data from Marketplace Insights, which we will never have. **The replacement must work using only APIs we have permanent access to + data we generate ourselves.**

---

## 0. Why this document exists

The original Radish-removal plan (DECISIONS.md #056, RADISH_REMOVAL_LOOP.md) shipped three replacement tiers:

1. **Tier 1** — tuned `normaliseSoldEnriched` over eBay sold (via `boba-ebay-proxy`)
2. **Tier 2** — `boba-price-estimator` Worker comparability function over our own catalog
3. **Tier 3** — community-submitted comps (designed, not built)

Diagnostic pass 2026-05-26 confirmed:

- Tier 1 returns **zero sold comps** for popular catalog cards. Sample of 5 popular cards (#1 Maverick / LeBoss / Showtime, #2 Merlomes / Showtime): all returned `priceType: "listed"` with no `sold` section. The Worker hits the Marketplace Insights API and gets either 403 (`noScope: true`) or empty `itemSales` for the 90-day window we have.
- Tier 2 is dependent on Tier 1 — the estimator computes per-card estimates by averaging eBay sold prices for comparable cards. With Tier 1 returning nothing, Tier 2 writes ~1 estimate per 50 cards processed.
- Tier 3 is not built.

**Constraint reality (binding):** eBay Marketplace Insights production access is no longer accepting applications. Every applicant for the past ~5 years has been denied. We will never have sold-comp data from eBay's API. Any pricing pipeline that depends on it is structurally broken.

**This playbook designs a pipeline that doesn't.**

---

## 1. What "done" looks like

**User-facing experience:**

- Every card with eBay activity shows a price — even if no sold-comp data exists from any external source.
- Pricing labels are honest about provenance. No card shows "Market Est." derived from nothing; it shows "Listed Range · 12 active · median $24" when that's what we have. The user knows what kind of data is in front of them.
- After ~60 days of pipeline operation, popular cards show real sold-history we generated ourselves — derived from Browse API snapshot deltas, Whatnot archive scrapes, and community submissions. Each row carries its source pill ("eBay · 12d ago", "Whatnot · 3d ago", "BoBA Community · @user").
- Power-user features (Collection value, deck-pricing-aggregate) consume the same data via a single `marketValue(bobaId) -> { value, confidence, source }` helper across iOS / web / Android.

**Technical state:**

- One `boba-pricing-tracker` Worker continuously snapshots eBay Browse listings into Cloudflare D1. After 14 days, vanish-detection starts inferring sold listings. After 60 days, we have a sold-history dataset we own.
- One Whatnot archive scraper Worker pulls per-stream sale prices and matches them to bobaIds via the existing image-fingerprint pipeline.
- One community-comp submission flow (auth-gated, mod-queued, photo-verified) lives on top of the existing `card_corrections` plumbing.
- `boba-price-estimator` is overhauled to consume Tiers 1–3 instead of starving on Marketplace Insights.
- Client pricing UI shows the most-specific-available signal with a clear provenance pill. Refresh button bypasses all caches.

---

## 2. The 5-tier architecture

| Tier | Source | Data type | Build effort | Ships in |
|---|---|---|---|---|
| **1** | `boba-pricing-tracker` Worker — Browse API snapshot delta + D1 historical store | Inferred sold (with confidence score) | NEW (medium) | Week 2–3 |
| **2** | Whatnot post-stream archive scraper | Real sold prices | NEW (medium) | Week 3–4 |
| **3** | Community-submitted comps | User-attested sold prices + photo proof | NEW (small-medium) | Week 4–5 |
| **4** | `boba-price-estimator` (existing, overhauled) | Comparability-derived estimate | REFACTOR | Week 5 |
| **5** | eBay Browse API live asking (existing) | Active-listing median/range | EXISTS — needs honest reframing | **Week 1 — ships immediately** |

Tier 5 is what we have **today**. The fastest user-facing win is to stop calling it "Market Est." (which implies a real estimate that doesn't exist) and start calling it "Listed Range" with honest median + count + range.

---

## 3. Tier 1 — `boba-pricing-tracker` Worker (the foundational build)

The big idea: we generate our own sold-history dataset from the public Browse API over time. Every 6 hours, snapshot active listings per card into D1. When a listing vanishes from a later snapshot, infer sold @ last-seen price with a confidence score derived from listing format, duration, and seller behavior. After 60 days we have what Marketplace Insights would have given us — sourced from public APIs we permanently own access to.

### 3.1 Worker structure

```
workers/pricing-tracker/
├── worker.js                 # main entry
├── lib/
│   ├── snapshot.js           # poll Browse API per bobaId, write D1 rows
│   ├── vanish.js             # diff snapshots, infer sold
│   ├── confidence.js         # score sold-inference from signals
│   └── api.js                # GET /comps?bobaId=X — read endpoint
├── wrangler.toml
└── README.md
```

### 3.2 D1 schema (`boba_pricing_history`)

```sql
-- Every listing snapshot we've ever seen.
CREATE TABLE listings (
  item_id        TEXT    PRIMARY KEY,                  -- eBay listing ID
  boba_id        TEXT    NOT NULL,                     -- our card identifier
  price_usd      REAL    NOT NULL,                     -- current asking
  shipping_usd   REAL,                                 -- separated when known
  condition      TEXT,                                 -- e.g. "Near Mint"
  format         TEXT    NOT NULL,                     -- BUY_IT_NOW | AUCTION | FIXED_PRICE_WITH_BO
  end_time       TEXT,                                 -- ISO8601 for AUCTION
  seller_id      TEXT,                                 -- to detect bulk delist
  image_url      TEXT,                                 -- for AI verify (Tier-3 future)
  first_seen     TEXT    NOT NULL,                     -- ISO8601 first snapshot
  last_seen      TEXT    NOT NULL,                     -- ISO8601 most recent snapshot
  vanished_at    TEXT,                                 -- ISO8601 first snapshot it was missing
  inferred_sold  INTEGER DEFAULT 0,                    -- 0 | 1
  sold_confidence REAL,                                -- 0.0–1.0 (see §3.4)
  sold_price_usd REAL                                  -- price at last_seen if inferred sold
);
CREATE INDEX idx_listings_boba_id ON listings(boba_id);
CREATE INDEX idx_listings_vanished ON listings(vanished_at);

-- Per-snapshot run metadata so we can audit gaps.
CREATE TABLE snapshot_runs (
  run_id        INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at    TEXT    NOT NULL,
  finished_at   TEXT,
  cards_polled  INTEGER NOT NULL DEFAULT 0,
  listings_seen INTEGER NOT NULL DEFAULT 0,
  vanish_count  INTEGER NOT NULL DEFAULT 0,
  error         TEXT
);
```

### 3.3 Snapshot loop

Cron every 6 hours (`0 */6 * * *`). Per run:

1. Read rotating cursor from KV (so cron can fit inside Cloudflare's 30-min wallclock).
2. For each catalog bobaId in this run's slice:
   - Service-bind into `boba-ebay-proxy` (avoid duplicating Browse API OAuth + scoring) → query active listings.
   - Upsert each returned item into `listings` (new row OR update `last_seen` + `price_usd`).
3. Vanish-detection pass: any `listings` row where `last_seen` is more than `2 × CADENCE` old and `vanished_at IS NULL` gets `vanished_at = now()`. Then runs confidence scoring (§3.4) and writes `inferred_sold`.
4. Save cursor; emit run metadata.

Budget: 600 cards/run × 4 runs/day = 2,400 cards/day full-catalog coverage. Whole catalog (17,974) rotates every ~7.5 days. After 60 days we have ~8 full rotations of data.

### 3.4 Sold-inference confidence formula

Signals (additive, capped at 1.0):

| Signal | Weight |
|---|---|
| Auction format AND `end_time` passed before vanish | **+0.70** (auction ended = sold or no-bid; cross-ref bid count) |
| Auction format AND `end_time` more than 24h after vanish | **−0.50** (seller pulled before end) |
| BIN listing duration > 14 days before vanish | **+0.40** (long-listed BIN that finally moves = real sale) |
| BIN listing duration < 24h before vanish | **−0.30** (likely edit/delist/typo) |
| Seller's other listings continued (same window) | **+0.20** (individual sale, not bulk pull) |
| Seller's other listings ALL vanished same window | **−0.40** (bulk pull, not sales) |
| Identical-treatment relisting at similar price within 30d | **+0.10** (confirms range, suggests real market) |
| AI image match verified (Claude API + image-fingerprint) | **+0.15** (gates obviously-wrong listings out — Tier 3+) |

Threshold: only `sold_confidence >= 0.55` rolls into the read endpoint as "Recent Sales." Lower-confidence rows still write to D1 (audit + future-tuning) but don't surface to users.

The formula is a starting point — first week of real data informs tuning. Skill: **invoke `learning-orientation-design`** before adopting (does the confidence threshold help users *understand* market state, or just feed them a number?).

### 3.5 Read endpoint — `GET /comps?bobaId=X&days=90`

Returns:

```json
{
  "bobaId": "1-Maverick-Base Set-First Edition-FIRE",
  "comps": [
    { "price": 22.50, "soldAt": "2026-05-04T...", "confidence": 0.82, "format": "AUCTION", "itemId": "...", "imageUrl": "..." },
    { "price": 24.00, "soldAt": "2026-04-18T...", "confidence": 0.71, "format": "BUY_IT_NOW", "itemId": "...", "imageUrl": "..." }
  ],
  "summary": { "low": 22.50, "median": 23.25, "high": 24.00, "count": 2 },
  "windowDays": 90,
  "source": "inferred_sold"
}
```

### 3.6 Wiring

- Same client integration pattern as `boba-price-estimator`. iOS `PricingService.swift`, web `js/app.js`, Android `PricingService.kt` add a fetch to `boba-pricing-tracker /comps?bobaId=X` as the **first** sold-source fallback (before the estimator).
- Renders as the "RECENT SALES" section with source pill "eBay · vanish-inferred."
- Refresh button bypasses cache.

### 3.7 Deploy

```bash
cd workers/pricing-tracker
npx wrangler d1 create boba-pricing
# paste returned database_id into wrangler.toml
npx wrangler d1 execute boba-pricing --file=schema.sql
npx wrangler deploy
```

KV cursor namespace can be the same `ESTIMATES` we already use (different key prefix).

---

## 4. Tier 2 — Whatnot post-stream archive scraper

Whatnot is a primary BoBA sales channel. Stream archives are public per-stream pages that show sold prices. Aggregating these gives us real (not inferred) sold data with high confidence.

### 4.1 Research required first (before implementing)

- Whatnot archive URL pattern (per-stream, per-seller, per-search)
- Whether archives expose price data in DOM HTML or in an embedded JSON blob (`__NEXT_DATA__` style)
- Whether they rate-limit or Cloudflare-Turnstile the archive pages (COMC-style block would route us to Browser Rendering API)
- Whether per-card images on archives are good enough for the existing image-fingerprint pipeline to match BoBA cards reliably
- ToS check — Whatnot's robots.txt + ToS posture on archive scraping (public-archive scraping has historically been judged fair use; we'd cite eBay v. Bidder's Edge boundaries)

Spawn a research subagent for this — output a 1-page brief on (a) URL/data shape, (b) anti-bot posture, (c) the most efficient per-card matching strategy. Reuse `boba-ebay-proxy`'s scoring logic for keyword-to-bobaId mapping.

### 4.2 Architecture sketch

Two paths depending on the research outcome:

**Path A — direct Worker scrape.** If archives serve HTML/JSON without aggressive anti-bot:
- Worker cron every 12h
- Hits archive pages per known BoBA seller (research output gives us the list)
- Per item: OCR'd card name + price + sale date → matched to bobaId via fingerprint or fuzzy text
- Writes to D1 `community_comps` (same table as Tier 3) with `source: "whatnot"`, `confidence: 0.95`

**Path B — Cloudflare Browser Rendering.** If archives require JS rendering or have Turnstile (per COMC):
- Same logic but via Browser Rendering API
- Costs ~$0.075/browser-hour; budget cap on cron

### 4.3 Surfacing to users

Same `/comps` endpoint as Tier 1, with `source: "whatnot"` per row. Source pill: "Whatnot · stream @ {seller}".

---

## 5. Tier 3 — Community-submitted comps

### 5.1 Supabase schema

```sql
CREATE TABLE community_comps (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  boba_id         TEXT NOT NULL,
  price_usd       NUMERIC(10,2) NOT NULL CHECK (price_usd > 0),
  sold_at         DATE NOT NULL,
  source_platform TEXT NOT NULL CHECK (source_platform IN ('ebay','whatnot','mercari','in-person','other')),
  photo_url       TEXT,           -- R2 URL via boba-comp-upload Worker
  notes           TEXT,           -- ≤280 chars
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewed_by     UUID REFERENCES auth.users(id),
  reviewed_at     TIMESTAMPTZ,
  reject_reason   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_community_comps_boba_id_status ON community_comps(boba_id, status);
```

RLS: insert by authenticated users; update by mods/admins only.

### 5.2 Submission UI

CardDetail surface on all three platforms gets a "Submit a sold comp" affordance below the pricing panels (auth-gated). Form: price, sold date, platform, photo (optional but boosts confidence), notes.

Photo upload reuses the `boba-avatar-upload` Worker pattern (new Worker: `boba-comp-upload`, R2 prefix `comps/{user_id}/{uuid}.{ext}`, 5MB cap, content-type allowlist).

### 5.3 Mod queue

Reuse the `card_corrections` admin queue UI. Mods see: card art, submitted photo (if any), price + date + platform + notes, submitter username, comp-submission history. One-click approve / reject. Approved comps surface to the public read endpoint with source pill "BoBA Community · @{username}".

### 5.4 Anti-abuse

- Rate limit: 5 submissions / user / day
- Per-bobaId rate limit: 1 / user / week (no spam-submitting the same card)
- Photo verification: if photo provided, run through existing image-fingerprint pipeline; reject if it doesn't match the bobaId's catalog art ± a confidence threshold
- Mod approval required before surfacing — no auto-approve in v1

### 5.5 Future — reputation system

Approved-rate over time becomes a per-user trust score. Once ≥10 approved comps with ≥95% approve-rate, future submissions auto-approve with a "Community-verified" pill. Punt to v2.

---

## 6. Tier 4 — `boba-price-estimator` overhaul

Replace the eBay-proxy fetch inside the estimator (which currently returns nothing useful) with a query against the Tier 1 comp store — AND re-weight the comparability function, which is wrong for BoBA today (§6.2). The estimator's sophistication is the heart of "accurate pricing"; it gets the most design care.

### 6.1 Changes

- `fetchCompPrices(allCompIds, catalog, env)` in `workers/price-estimator/worker.js:193` swaps from `env.EBAY_PROXY_SVC` to `env.PRICING_TRACKER_SVC` (new service binding).
- The query path: instead of "fetch eBay sold for each comparable," it's "select aggregate from D1 listings where boba_id IN (...) and inferred_sold = 1 and last_seen > now() - 90d."
- KV cache key changes from `estimate:{bobaId}` → `estimate:v2:{bobaId}` so we don't serve stale v1 entries.

### 6.2 Rarity-first comparability (REPLACES "cross-set hero anchoring")

**The current estimator is weighted wrong.** `workers/price-estimator/worker.js` weights `same_hero` at **0.6** (the dominant axis), `same_weapon_power` 0.3, `same_set`/cardType 0.1. For BoBA that's backwards: price is driven by **rarity**, not hero. Two cards of the same hero — a Base Set common vs a serialized Inspired Ink — sell at wildly different prices; two *different* heroes of the same treatment + serialization + power tier sell close. Hero is a *multiplier on top of* the rarity structure, not the base. (Ben's call, 2026-05-27.)

**Comparability key, rarity-first.** Nearest neighbors share a **rarity class**, NOT a hero:
- **treatment family** — the single richest axis (59 distinct treatments; the cardNumber prefix encodes it, e.g. `GGL-` = Great Grandma's Linoleum Battlefoil).
- **serialization tier** — Inspired Ink is serialized BY WEAPON (Hex /5, Glow /10, Fire /25, Ice /50, DECISIONS.md #028); for serialized cards the weapon IS the print-run, a hard rarity signal.
- **card class** — `cardType` (Hero/Play/HotDog/Sealed) + parallel flags (`isInspiredInk`, `isBonusPlay`, `isHTD`, `rookieInspired`).
- **power tier** (gameplay desirability; existing `powerTier` buckets), **weapon**, **set/subSet/release** (era).
- **hero** — a secondary similarity *bonus* only.

**No stored rarity field exists** (`rarityTier`/`rarityLabel` are empty across all 17,974 cards), so we DERIVE a scarcity index from: (1) serialization print-run where known (Inspired Ink weapon → /5…/50); (2) catalog **population per treatment-family** as a scarcity proxy (e.g. "Battlefoil" 1028 cards vs "Great Grandma's Linoleum Battlefoil" 786 — rarer treatments run smaller); (3) parallel/type flags (parallels + serialized run scarcer than base).

### 6.3 Learn the weights from comps — don't hardcode them

The 0.6/0.3/0.1 weights are a guess, and re-guessing new weights repeats the mistake. Once Tier 1+2+3 produce real sold comps, **fit a hedonic model**: `log(price) ~ treatment_family + serialization_tier + cardType + power_tier + weapon + set + hero`, learning each factor's actual price contribution from observed sales. A comp-less card's estimate = the model's feature-based prediction blended with its nearest-rarity-class comps. Hero enters as one learned coefficient (expected: a modest multiplier), never a 0.6 prior. **This is why Tier 1 must land first — the estimator is only as good as the comp data feeding it.** Until enough comps exist, fall back to the derived-scarcity heuristic (§6.2) with rarity axes dominant + hero a small bonus. Validate any model on a held-out set of cards that DO have comps before shipping; spot-check the long tail (Battlefoils especially).

**Open (Ben's domain call):** how to establish the treatment rarity ORDER pre-comps — derive purely from catalog population + serialization (data-only, no manual ranking), or seed with a canonical treatment-rarity tier list from Ben, or both (his tiers as prior, population/comps as refinement). See build-log.

---

## 7. Tier 5 — Listed Range honest reframing (Week 1 — ships immediately)

The fastest user-facing improvement. Three files, no new infrastructure.

### 7.1 Copy changes

| Current state | New state |
|---|---|
| Section header: "MARKET EST." | "LISTED RANGE" |
| Body: "~$24 · based on 8 recent eBay sold comps" (rendered when `priceType: "estimator"` but the estimator returned null → falls back to error/skeleton) | "$18 – $42 · median $24 · 12 listed" |
| Subhead: nothing | "Active eBay listings · no recent sales data" |
| Source pill: "eBay sold" | "eBay listed" |

When Tier 1 starts producing real comps (Week 2+), the "RECENT SALES" section reappears alongside "LISTED RANGE."

### 7.2 File changes

- **iOS:** `BOBAPlaybook/Networking/PricingService.swift` — rename `estimated` flag, update copy in `BOBAPriceTile.swift`
- **Web:** `js/app.js::renderPricingSection` — update header + subhead + pill copy when `priceType === 'listed'`
- **Android:** `android/feature/carddetail/src/main/java/.../CardDetailScreen.kt` — same

### 7.3 Why this ships first

- Costs nothing — no new infrastructure
- De-pressures the Tier 1 timeline — users see useful data TODAY
- Honest framing builds trust (the previous "no Market Est." state read like a bug to users)
- The data was already there; we were just labeling it badly

---

## 8. Week-by-week shipping plan

### Week 1 (this week, kickoff tomorrow)
- **Day 1 (tomorrow):** Spawn research subagent on Whatnot archive structure (output: 1-page brief). Start Tier 5 reframing — iOS + web + Android client copy changes. Ship to TestFlight + Pages same day. Time budget: ~2 hours.
- **Day 2–3:** Scaffold `workers/pricing-tracker/` skeleton — `wrangler.toml`, `worker.js` stub, D1 create + schema apply, README. Wire empty `/comps` endpoint.
- **Day 4–5:** Implement snapshot loop (§3.3). Deploy. First cron run logs what it sees. No client wiring yet.

### Week 2
- Vanish-detection pass implemented (§3.3 step 3).
- Sold-inference confidence formula v1 (§3.4) — use first week's data to tune.
- Read endpoint `/comps?bobaId=X` (§3.5) live.
- Client wiring: add Tier 1 fetch to iOS / web / Android pricing panels, BEHIND a feature flag so we can A/B with the current behavior.

### Week 3
- Whatnot archive scraper — Path A or B per Week 1 research output.
- D1 schema gets `source` column (already in the spec); Whatnot rows write with `source: 'whatnot'`.
- AI image verification gate (Claude API + existing image-fingerprint pipeline) on incoming Whatnot rows. Skill: **invoke `claude-api`** for the implementation.

### Week 4
- Community comp Supabase schema + RLS deploy.
- Submission UI on iOS / web / Android (CardDetail).
- `boba-comp-upload` Worker.
- Mod queue extension to existing `card_corrections` admin panel.

### Week 5
- `boba-price-estimator` overhaul to consume Tiers 1–3.
- Cross-set hero anchoring (§6.2).
- Feature flag flipped on for all users — Tier 1+2+3+4 chain replaces the current pipeline.
- DECISIONS.md amendment: write a #058 entry crystallizing the architecture. Skill: **invoke `architectural-decision-log`**.

### Ongoing (Week 6+)
- Tune confidence threshold weekly based on observed user reports + spot-checks
- Add reputation-based auto-approve for community comps (§5.5)
- Investigate Cloudflare D1 read-replica + edge caching for the `/comps` endpoint (it's a hot path)

---

## 9. Risk register

| Risk | Mitigation |
|---|---|
| **eBay rate-limits the Browse API on heavy snapshot polling.** | Service-bind through existing `boba-ebay-proxy` which already has OAuth pool + per-token throttling. 600 cards × 4 runs/day = 2,400 calls/day, well under eBay's published Browse API limits. |
| **Vanish ≠ sold.** Sellers delist, edit-relist, accidentally pull listings. | Confidence formula (§3.4) reduces false positives. Threshold 0.55 conservative. First week of data informs tuning. |
| **D1 cost overrun.** | D1 free tier is 5M reads/day, 100K writes/day. Snapshot writes: 2,400 cards × ~10 listings each = 24K writes/day. Well under free tier. Reads scale with user pricing-detail opens. |
| **Whatnot anti-bot evolves and blocks us.** | Path B (Browser Rendering) is the fallback. If both paths fail, Whatnot becomes the community-submission case (users tell us about Whatnot sales they witnessed). |
| **Community comps get gamed.** | Mod approval gate. Rate limits. Photo verification via existing image-fingerprint. No auto-approve in v1. |
| **Estimator over-weights hero** (current code: `same_hero` = 0.6) — rarity (treatment / serialization / power / type) is the real price driver. | Re-weight rarity-first (§6.2); learn factor weights from real comps via a hedonic model (§6.3) instead of hardcoding; validate on a held-out comp set; spot-check the long tail (Battlefoils). |
| **AI image verification (Claude API) cost overrun.** | Only invoked on Whatnot-scraped + community-submitted comps (not on every Browse snapshot). At ~$0.003 per Haiku call × ~100 incoming comps/day = $0.30/day. Reasonable. |
| **Estimator caches stale during the rollout.** | KV cache key bumped to `estimate:v2:{bobaId}` so v1 entries don't serve. |

---

## 10. Open questions

These need answers before the relevant phase ships. Listed in chronological order.

| # | Question | Blocks | Owner |
|---|---|---|---|
| 1 | What's the Whatnot archive URL pattern + data shape? | Tier 2 | Week 1 research subagent |
| 2 | Is the confidence threshold of 0.55 the right starting point, or should we anchor to a different value based on observed week-1 data? | Tier 1 read endpoint going live (Week 2) | Ben + first week of cron data |
| 3 | Should community comps require a photo, or is text-only acceptable for the trusted-user tier? | Tier 3 (Week 4) | Ben — UX call |
| 4 | What's the right surfacing order in the pricing panel when multiple tiers have data for the same card? Current proposal: **Whatnot (real) → Community (real) → Tier 1 (inferred) → Estimator (derived) → Listed Range (asking)** | Tier 4 client wiring (Week 5) | Ben |
| 5 | Do we want a "trade-in value" estimate (typically 60–70% of market) as a separate signal for the Collection value summary? | v2 polish | Punt |

---

## 11. Success metrics

How we know this is working.

**After Week 1:**
- Tier 5 copy reframing live on all three platforms. Zero user reports of "broken pricing" (the previous state had complaints). Logs show fewer empty-pricing-panel renders.

**After Week 4:**
- `boba_pricing_history.listings` has ≥150K rows across ≥10K unique bobaIds.
- ≥30% of catalog cards have at least one inferred sold comp.
- Whatnot scraper contributing ≥20 real comps/day.
- Community submissions: ≥5/week steady state.

**After Week 8:**
- ≥70% of popular cards (cardNumber ≤ 100, base set) show a Recent Sales section instead of just Listed Range.
- Estimator v2 cache populated for ≥60% of catalog (vs. <1% on the old MI-dependent path).
- User-facing pricing-related support contacts trending down month-over-month.

**Anti-metric to watch:** false-positive sold inferences. Sample audit weekly — Ben spot-checks 20 random inferred-sold rows; if more than 3 are clearly wrong (seller relisted, item didn't sell), tighten confidence formula.

---

## 12. References

- `RADISH_REMOVAL_LOOP.md` — what we removed and why
- `DECISIONS.md #013` — original pricing strategy (eBay Worker, live lookups, Supabase caches)
- `DECISIONS.md #034` — COMC asking-price posture (parallel BUY NOW, NOT in sold waterfall)
- `DECISIONS.md #056` — Radish removal trigger + compliance scope
- `workers/ebay-proxy/worker.js` — current Worker that returns active listings + (failing) sold queries
- `workers/price-estimator/worker.js` — current estimator we'll overhaul in Tier 4
- `DESIGN.md §8.7`, `WEB-DESIGN.md §15`, `ANDROID-DESIGN.md §8.7` — binding pricing-panel rules per platform

## 13. Skills to invoke during build

- `claude-api` — Tier 3 image verification + Tier 1 AI listing-match gate (Week 3+)
- `learning-orientation-design` — review the confidence threshold + UI labeling against "does this deepen user understanding of pricing?" (Week 2)
- `architectural-decision-log` — DECISIONS.md #058 entry at end of Week 5
- `mobile-first-density-design` — pricing panel layout review on iOS / web / Android (Week 2 + Week 5)
- `universal-feature-states` — loading / empty / error / offline states for the new `/comps` endpoint (Week 2)
- `binding-design-doc-discipline` — invoke before any new UI surface (CardDetail submit-comp form is the main one — Week 4)

---

## 14. Build log + ground-truth reconciliation (living)

### 2026-05-27 — kickoff: ground-truth vs. the plan

Mapped the real codebase before building. Corrections to this doc's assumptions:

- **`workers/pricing-snapshot/` already exists** (not in the original plan). A nightly cron writes *aggregate* eBay sold/active/estimator snapshots to Supabase `card_prices_history`; iOS reads the `card_prices_latest` view as a `<24h` fast path before hitting the eBay proxy. This is **not** the Tier 1 vanish-inference tracker — it stores per-card aggregates, not per-*listing* rows (no `item_id`/`first_seen`/`last_seen`/`vanished_at`), so it cannot infer sold-from-disappearance. **Tier 1 is still genuinely new.** Open decision for Tier 1: build a new Cloudflare **D1** store (playbook §3) for per-listing granularity, *or* extend `card_prices_history` with a per-listing table in Supabase. D1 keeps the hot `/comps` read off the Supabase quota; lean D1 unless a reason emerges.
- **WEB-DESIGN.md had no pricing section.** The "§15" reference in §7.2/§12 was wrong (§15 is the web Roadmap). Added **WEB-DESIGN.md §14.6 — Card detail · pricing panels (provenance-honest)**; that is now the binding web rule. iOS DESIGN.md §8.7 + ANDROID-DESIGN.md §8.7 rewritten to match.
- eBay-proxy already returns dual `{sold, active, priceType}` (`priceType ∈ {sold, listed}`); estimator returns `{low, mid, high, comparableCount, method}`. Confirmed.

### 2026-05-27 — Tier 2 (Whatnot): RESEARCH DONE, BUILD HELD on a ToS decision

Research brief complete (Open Question #1 answered). **Path A (direct Worker fetch) is technically viable** — `boba-ebay-proxy` already parses Whatnot Apollo-SSR HTML in production (for *upcoming* shows); sold prices are server-rendered (no JS/Browser-Rendering needed); image-fingerprint-primary + title-fuzzy matching mirrors scan #035.

**Blocker:** Whatnot's ToS prohibits automated access in plain language ("scrape, spider, crawl… harvest or manipulate data"). CFAA exposure is low (public data; *hiQ v. LinkedIn*) but ToS-breach + trespass-to-chattels (*eBay v. Bidder's Edge*) are real. Given the Radish walk-away (DECISIONS.md #056), **this is Ben's risk-acceptance call, not an autonomous one.**

**RESOLVED 2026-05-27 (Ben):** do NOT pursue sold archives — Whatnot doesn't publish usable sold data, and that's the ToS-weighted part. Instead surface Whatnot **Products** (`whatnot.com/search?...&searchVertical=PRODUCT` — currently-for-sale items = active ASKING prices) as a where-to-buy / Listed source, exactly like eBay active listings. Ben's posture: fetching public PRODUCT listings for attributed display is the same as the already-shipped Whatnot upcoming-shows SSR fetch and our eBay actives feature — acceptable. Asking data → feeds "Listed Range"/"Buy Now" + a "Whatnot" pill, NEVER a sold/value number (#034). Research relaunched on the PRODUCT node shape + integration (extends the existing `boba-ebay-proxy` Whatnot Apollo-SSR extractor to the PRODUCT vertical).

### 2026-05-27 — Tier 5 shipped (v2.379): provenance-honest reframing

Web + iOS landed. The starved-estimator "Market Est." (which fabricated a number from comparables that mostly returned nothing) is **suppressed**; when a card has no real sold data, the active eBay listings now surface honestly as **"Listed Range"** (LOW/AVG/HIGH + "N active eBay listings · no recent sales data yet"). "Recent Sales" + "Buy Now" still render together when real sold data exists. `fetchEstimatorBucket` kept intact (DECISIONS.md #025) for the Tier 4 overhaul. Binding docs updated first (doc-then-code).

**Android Tier 5 shipped** (gradle `:app:compileDebugKotlin` ✓): dropped the top "MARKET ESTIMATE" headline + the "Market Est." tri-grid fallback; "Buy Now" → "Listed Range" with "no recent sales data yet" provenance when no sold; extracted `TapPriceHint`. **Tier 5 is now at full iOS / web / Android parity.** Next: Tier 1 (vanish-inference tracker) + Tier 2 design from the Whatnot-Products research.

### 2026-05-27 — Tier 2 (Whatnot Products): research done, build-ready spec

Supersedes §4's sold-archive design. Whatnot PRODUCT search = **active asking listings**, surfaced exactly like eBay actives.

- **Endpoint:** new `GET /whatnot/products?query=…` (or `?bobaId=…`) on `boba-ebay-proxy`, routed next to `/whatnot/upcoming` (worker.js ~line 1109). Clone `handleWhatnotUpcoming`: reuse `WHATNOT_HEADERS` (browser UA + `Sec-Fetch-*`, worker.js:1341), `buildWhatnotSearchUrl` with `searchVertical=PRODUCT` (drop the LIVESTREAM `status` filter), the `WN_APOLLO_PUSH_RE` + `wnFindMatchingBrace` + `wnParseLooseJson` SSR walk (worker.js:1553/1722/1740). Add `wnWalkProductNodes` (mirror `wnWalkShowNodes`) matching `__typename ∈ {Listing, Product, MarketplaceProduct}`. Fetch **sequentially** (parallel trips anti-bot, worker.js:1388); cache ~2h (match eBay active TTL).
- **PRODUCT node fields (TRIANGULATED — confirm against a live edge response before trusting):** `priceCents` (÷100; fixed BIN ask OR auction *starting bid* — both asking, never sold), `title`/`productName`, `images[].{bucket,key,url}` (Whatnot image URL = `https://images.whatnot.com/{urlsafe_b64(JSON{bucket,key,edits:{resize},outputFormat:"webp"})}` — server-side resize, request a clean square for FP), `conditionName`, `quantity`, `status` (**filter to buyable; drop SOLD/ENDED**), `user.username`, `product.slug` (→ public URL). Write the walker defensively (`a || b || c` fallbacks like the shows path) since names are inferred. **First implementation step: deploy a one-off probe that fetches a real PRODUCT page from the edge and logs the node JSON to confirm exact paths.**
- **Response shape:** the eBay `active` bucket shape (`{low,average,high,count,items[]}`) so clients reuse the renderer; each item `{title, price, url, image, source:"whatnot", seller, condition, listingType, bobaId}`. `priceType` stays `"listed"`, never `"sold"`.
- **Matching (Worker-side, matched-only):** FP primary (`feature-prints.bin`) + title fuzzy/veto, reusing the eBay path's `norm`/card-number regex/`HERO_ALIASES`/`TREATMENT_TOKENS`/`LOT_PATTERNS`. Below confidence floor → omit the listing (nil-over-wrong, #035). Whatnot seller titles are noisier than eBay's, so FP carries more weight.
- **Clients:** third source in the Buy-Now/Listed row with a **"Whatnot" pill** (iOS `BOBAPriceTile`, web `.pricing-item`, Android `BOBAPriceTile`+`AssistChip`). **Android SHOULD render Whatnot** (unlike COMC, which is Turnstile-blocked — Whatnot has no such block; the shows fetch already works on Android) — a parity win. Soft-fail silently on count 0.
- **#034 compliance (binding):** Whatnot asks NEVER feed the value number — not into `normaliseSoldEnriched`, `sold`, `user_cards.estimated_value`, or `boba-price-estimator`. Buy-Now/Listed source only. Auction starting bids especially are floors, not clearing prices.
- **Effort:** ~120-line Worker endpoint + thin per-platform pill. **Needs a Cloudflare deploy to verify** (field-name confirmation + live test).

### Blocker for the backend tiers — Cloudflare/Supabase deploy access

Tiers 1, 2, and 4 are Cloudflare Workers (+ Tier 1 a new D1 DB); Tier 3 is Supabase. Building them "no-shortcuts" means deploy + verify in a tight loop, not shipping un-runnable code. **Next action requires a `CLOUDFLARE_API_TOKEN`** (Workers+D1 edit scope) so wrangler can deploy non-interactively, and confirmation of Supabase migration access. Until then, autonomous progress is limited to client-side scaffolding + the #058 ADR.
