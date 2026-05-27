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

## 4. Tier 2 — Whatnot PRODUCTS (current active asks)

**Revised 2026-05-27 (Ben's direction).** The original Tier 2 was a
post-stream *sold-archive* scraper. Ben killed that: *"Whatnot doesn't
publish sold data in a format that actually works for our purposes. The
only thing we should do for Whatnot is to provide the 'Products' that are
currently being sold… the same thing that we are doing with eBay outside
of our API access."* Example surface:
`https://www.whatnot.com/search?query=bojax&searchVertical=PRODUCT`.

So Tier 2 is now **current active product listings**, treated exactly like
eBay *active* listings:

- **A listed/asking signal, NOT a sold comp.** Whatnot Products go in the
  card-detail **Buy Now** section, never the sold-comp waterfall — asks run
  10–25% above transacted (same rule as COMC asking, DECISIONS.md #034, and
  the honest-framing rule of Tier 5 §7). They never move the Market Est.
- **Fetched LIVE per card-detail, like eBay actives — no cron, no D1.**
  eBay actives are fetched on demand through `boba-ebay-proxy` when a card
  opens; Whatnot Products follow the same model. This sidesteps the 5-cron
  account cap entirely (the Tier-1 tracker already holds a slot) and keeps
  Whatnot data as fresh as the user's view.
- **No write to `community_comps`.** That table is Tier-3 user-submitted
  *sold* comps; active asks don't belong there.

### 4.1 Research (in flight)

A subagent is researching the Products data shape + anti-bot posture
(launched 2026-05-27): is there a JSON/GraphQL endpoint the search page
calls server-side, or is it `__NEXT_DATA__` in the HTML, or does it need a
headless browser; does a datacenter-IP fetch hit Turnstile; robots.txt +
ToS posture. The brief picks one of: (A) direct JSON/GraphQL fetch, (B)
`__NEXT_DATA__` parse, (C) Cloudflare Browser Rendering required, (D) not
feasible / too ToS-risky.

ToS framing: there is no public Whatnot API, so — exactly as Ben framed it
— we'd fetch the same public product-search data a browser sees, the
equivalent of what we do against eBay (which *does* have an official API we
use). If the research returns (C)/(D) or a Turnstile wall (COMC-style), we
do NOT proceed — we don't fight anti-bot for a secondary asking signal.

### 4.2 Architecture (pending research outcome A or B)

- New endpoint on `boba-ebay-proxy` (reuse its infra + keyword→bobaId
  scoring): `GET /whatnot/products?query={hero/cardNumber}` → returns active
  listings `[{ title, price, currency, url, seller, imageUrl }]`, short
  KV-cached. Soft-fail to empty on any error or anti-bot block (clients show
  nothing, never an error — same posture as COMC `challenged:true`).
- Clients add a Whatnot tile group to the Buy Now section beside eBay
  actives. Source pill: **"Whatnot · @{seller}"**. Tap-through opens the
  listing (`CustomTabsIntent` / `SafariView` / `target=_blank`).

### 4.3 Surfacing — honest + subordinate

Buy Now section only. Never in the Market Est. line, never in `/comps`,
never in the sold waterfall. If a card has Whatnot asks but no eBay/sold
data, the headline stays the honest "Listed Range" (Tier 5 §7) — Whatnot
asks are part of that listed range, clearly sourced.

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

### 6.4 Rarity model — robust, tier-based, learned (the estimator's foundation)

Built from the two official guides (Alpha Update + 2026 Edition "Parallels, Rarity & Checklist" PDFs, promo.bobattlearena.com). **Deliberately NOT pinned to exact print-run numbers.** The old Hex /5 · Glow /10 figures (DECISIONS #028 / CLAUDE.md) were an estimate that's already stale, and the official guides don't price by serialization counts at all — they use **ordinal rarity tiers + distribution + power**, which is robust and survives set changes. Ben's directive (2026-05-27): build a strong, robust, data-learned estimator, not a brittle rarity-fact table. So the below are **features with priors**, never fixed weights.

**Feature 0 — Observed serialization (`printRun`) — the hardest signal when present.** 464 catalog cards carry a real `printRun` from the data/OCR pull: /5 (53 cards), /10 (46), /25 (104), /50 (261); the other 17,510 are un-numbered. This is a *fact* about the print run, not an assumption — a /5 is objectively far scarcer than a /50, which is far scarcer than an un-numbered base card — so when `printRun` is populated it dominates the scarcity estimate (lower = rarer, roughly inverse). Crucially, the data shows weapon does NOT map to a single count — **FIRE and ICE each appear as both /5 AND /50** — which is exactly why we read the real per-card field instead of assuming a weapon→count table (the stale #028 assumption). Where `printRun` is missing, fall back to the ordinal features below.

**Feature 1 — Weapon rarity tier** (the spine; 2026 Weapons chart, ordinal): `BRAWL` Common · `STEEL` Common → `FIRE` Rare · `ICE` Rare → `GLOW` Ultra Rare → `HEX` Secret Rare · `GUM` Secret Rare → `SUPER` 1-of-1. Brawl/Steel/Fire/Ice come Battlefoil AND non-foil; Glow/Hex/Gum are Battlefoil-only; Super is Superfoil-only — so **foil-only status is itself a scarcity bump**.

**Feature 2 — Distribution tier** (which SKU a parallel is pulled from = how hard to get; 2026 Parallels chart, more-restricted = rarer):
- **All SKUs:** Inspired Ink autos · Alpha · 80's Rad · Colosseum · Logofoil · Blizzard · Miami Ice · Fire Tracks · Mixtape.
- **Jumbo/Hobby only:** Metallic Inspired Ink · the 6 Colors (Red/Silver/Blue/Orange/Green/Pink Battlefoil) · Grandma's Linoleum · Gum.
- **Double Mega & Blaster:** Great Grandma's Linoleum · Grillin' · Chillin' · Slime · Icons (per-weapon: Brawl/Steel/Ice/Fire/Glow/Hex).
- **Double Mega only:** Bonus Plays · Power Glove.
- **Blaster only:** Silver/Blue/Orange/Red Headlines.

**Feature 3 — Power** — correlates with tier on the official cards (Common ~120–130, Rare ~135, Ultra/Secret ~155–185, Super ~190–200). A continuous feature, not a hard rule.

**Feature 4 — Card class** — `cardType` (Hero/Play/HotDog/Sealed) + parallel flags (`isInspiredInk` = autograph, `isBonusPlay`, `isHTD`, `rookieInspired`).

**Feature 5 — Treatment family** — the 59 catalog `treatment` values, tiered via Feature 2 distribution + foil status + catalog population, refined by comps.

**Feature 6 — Hero** — a secondary learned multiplier (star athletes lift price within a rarity class; the autograph checklists in the guides map hero → athlete). Never the base.

**How they combine — LEARN, don't hardcode.** Once Tier 1+2+3 produce comps, fit a hedonic model (§6.3) so each feature's price contribution is learned from real sales; the guides' ordinal tiers are the prior + the cold-start fallback for comp-less cards. Robustness comes from (a) ordinal tiers that don't break when print runs change, (b) distribution as an orthogonal scarcity axis, (c) learned weights over hardcoded facts. What's intentionally NOT load-bearing is any *assumed* weapon→print-run table (the data shows weapon isn't 1:1 with count); the *observed* `printRun` (Feature 0) is a hard input used directly whenever present. The guide tier/distribution mappings are encoded once as a reference table the estimator Worker + clients read.

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

### 2026-05-27 — Cloudflare confirmed unblocked + Tier 1 foundation deployed

**No token needed** — `wrangler` is already authenticated on the dev machine (benwilkoff@gmail.com) with `workers`/`workers_kv`/`d1` write scope. Backend tiers are buildable now.

**Rarity model shipped** (`scripts/build_rarity_model.py` → `assets/data/rarity-model.json`): the official guides encoded as a factual reference table (weapon tier · foil-only · treatment→distribution tier, 35/59 mapped + 24 population-fallback · observed `printRun`), validated over 17,929 cards (SUPER 1/1 top, common base bottom).

**Tier 1 foundation live:**
- D1 `boba-pricing` created (id in wrangler.toml) + schema applied (`listings`, `snapshot_runs`).
- `boba-pricing-tracker` Worker deployed. `GET /comps?bobaId=X` read endpoint **live + validated** (clean empty result over the empty DB, §3.5 shape). Snapshot/vanish/confidence implemented; **cron OFF**.

**The two-part build (next).** Reliable vanish-inference needs the FULL active-listing set + stable item ids. The proxy's main endpoint returns only the **top ~10 of N** with `{title,price,date,url}` and no format/seller/endDate; worse, its unmatched-path fall-through silently serves that truncated set. So the snapshot is **hard-gated**: `activeListingsFor` consumes a listing set ONLY if the response is marked `full:true` (returns [] otherwise — verified the snapshot is a no-op, writes nothing). **Step 1 — DONE + validated (2026-05-27):** `boba-ebay-proxy` now serves `GET /tracker/active?…&full=1` returning every matched active listing with `{itemId, price, buyingOption, endDate, seller, condition, image, url, full:true}`. Extracted a shared `matchActiveCandidates` so the live `/` response stays byte-structure-identical (verified before/after with `fresh=1`). A manual `POST /snapshot?budget=5` wrote **98 real listings across 5 cards** to D1 with format/seller populated — the tracker gate opened automatically once the proxy returned `full:true`. **Step 2 — DONE (2026-05-27): cron LIVE.** Sized against MEASURED quota, not a guess — added a `/tracker/ratelimit` endpoint on the proxy (eBay `getRateLimits`): **Browse limit = 5,000/day**, ~4,850 remaining mid-day, so organic usage is light (the v18 cache absorbs most card opens; heavy crons run pre-07:00-UTC-reset). Browse quota is SHARED with live user pricing, so: `PER_RUN_BUDGET=400` (×4 runs/day = ≤1,600/day) + a pre-run quota check that **skips the run if Browse remaining < 1,500** — the tracker can never starve live pricing. Hit the account's **5-cron cap**; reclaimed the slot from `comc-proxy`'s daily sweep (dead weight — COMC Turnstile-blocked #034; cleared with explicit `crons=[]`). Cron `0 */6 * * *` registered. Vanish-inference begins ~14 days out; full sold-history ~60 days. Monitor via `/tracker/ratelimit`, `snapshot_runs`, and `/comps`.

**Supabase (Tier 3):** likely reachable via the connected Supabase integration — to check when Tier 3 starts.

### 2026-05-27 — Tier 4 (estimator) overhauled rarity-first + deployed

`boba-price-estimator` rewritten per §6.2/§6.3 and live (version 1db88530):
- **Comparability is rarity-first, hero last.** Axes tightest→loosest: `rarity_class` (treatment-family + weapon + power-tier + cardType) → `serial` (identical `printRun` — the hard scarcity peer) → `treatment_weapon` → `treatment` → `hero`. The old hero=0.6 weighting is gone.
- **No weighted-sum of arbitrary axis weights.** `computeEstimate` takes the **MEDIAN** of the tightest axis that has enough priced comps (robust to eBay's wild asking outliers — the LeBoss case spanned $3.40–$902). Returns null when no comp data exists (honest; Tier 5 Listed Range covers it). Per-feature weights get learned once the dataset grows.
- **Comp source = the Tier 1 tracker.** `fetchCompPrices` now reads `boba-pricing-tracker /comps` (real inferred-sold medians) via a new `PRICING_TRACKER_SVC` binding, replacing the dead eBay-MI sold path. KV bumped to `estimate:v2:` so stale v1 entries don't serve.
- Validated: `/estimate` → `no_comps_yet`; `/refresh?budget=3` → processed 3, wrote 0 (no errors; produces estimates automatically as the tracker accrues inferred sales). Nightly cron unchanged (still within the 5-cron cap — it already had a slot).

**Remaining:** Tier 2 (Whatnot Products), Tier 3 (community comps — the fastest path to comp data ahead of the 14-day tracker), and #6 (unify `marketValue` + wire the estimator/comps into clients as a clearly-labeled "Estimated"/"Recent Sales" signal per §8.7, re-enabling what Tier 5 suppressed — only when real data backs it).

### 2026-05-27 — Tier 3 data foundation built + wired into the estimator

The community-comp backbone is live on Supabase (project `pazkimtkwwwekuguxkff`) and feeding the estimator — the *fastest* path to real comp data (no 14-day wait):
- **`community_comps` table + RLS** (migration `community_comps_tier3`): own/approved/mod read policies; review = mods/admins. `user_id` ON DELETE SET NULL so approved comps survive account deletion (anonymized).
- **RPCs** mirroring the `card_corrections`/`request_role` pattern: `submit_community_comp` (authenticated, rate-limited 5/user/day + 1/bobaId/user/week), `get_pending_community_comps` (mod queue), `review_community_comp` (approve/reject), `get_approved_comps` (public). Grants tightened (`_tighten_grants`) per the security advisor — submit/review/pending are authenticated-only; `get_approved_comps` is anon-callable by design.
- **Estimator wiring:** `boba-pricing-tracker /comps` now MERGES approved community comps (Supabase `get_approved_comps`, anon key as a wrangler secret) with the D1 inferred-sold — one sold-comps endpoint, `source: "inferred_sold+community"`, each row tagged (`community-{platform}` / `ebay-inferred`). The estimator reads `/comps` median, so approved comps flow straight through.
- **Validated end-to-end:** seeded an approved comp → it appeared in `/comps` (count 1, `$14.25`, `community-whatnot`) → cleaned up. Security advisor clean for the new objects.
- DDL version-controlled in `supabase_schema.sql`.

**Tier 3 remaining (client work):** submission UI on CardDetail (iOS/web/Android — price/date/platform/photo/notes), the `boba-comp-upload` Worker (R2 photo, reuse avatar-upload), and the mod-queue UI (extend the `card_corrections` admin panel). Photo fingerprint-verify deferred to v2 (mod approval gates v1).

### 2026-05-27 — Tier 3 web submission UI (quiet + subordinate, per Ben)

Design rule ratified in DESIGN.md §8.7 + ANDROID-DESIGN.md §8.7 + WEB-DESIGN.md §14.6: the submission affordance must NOT displace why people open a card (art / current price / collection). So it's a **single low-emphasis link at the foot of the pricing section** ("Saw one sell? Add a price") that toggles a **compact inline form** (price · sold date · platform · notes) — inline rather than a second `<dialog>` to avoid web's dialog-soup anti-pattern, and visually understated. The 95% who came for art/price/collection see only a tiny link; the engaged collector taps in.

Web shipped: `API.submitCommunityComp` (api.js) → `submit_community_comp` RPC (auth-gated; server enforces the rate limits); `appendCompSubmit` renders the link+form at the foot of `renderPricingData`; toast on submit ("a moderator will review your comp"); CSS understated. `node --check` clean on api.js + app.js. Photo upload deferred (text-only v1; `boba-comp-upload` Worker is the next piece).

**Still remaining:** iOS + Android submission affordance (same quiet pattern, native idiom — `.medium` sheet / `ModalBottomSheet`), `boba-comp-upload` Worker (R2 photo), mod-queue UI.

### 2026-05-27 — Tier 3 iOS + Android submission UI (parity complete)

Same quiet/subordinate pattern as web, native idiom each side. The 95%
who open a card for art / price / collection see only a low-emphasis cyan
link at the FOOT of the pricing section; the engaged collector taps in.

- **iOS** (`PricingSection.swift`, v2.380): foot link "Saw one sell? Add a
  price" → `.medium` `.sheet` hosting an inlined `SubmitCommunityCompSheet`
  (`Form`: price `.decimalPad` · `DatePicker(in: ...Date())` · platform
  `Picker` · notes). Auth-gated via `@Environment(AuthManager.self)` —
  signed-out shows "Sign in from Profile". Submit →
  `SupabaseClient.submitCommunityComp` (date as `yyyy-MM-dd` UTC); success
  shows a confirmation then auto-dismisses. Sheet inlined into
  `PricingSection.swift` (not a new file) per the Xcode synchronized-group
  reliability note.
- **Android** (`CardDetailScreen.kt` + `ProfileService.kt` +
  `CardDetailViewModel.kt`): foot `TextButton` (cyan = `colorScheme.secondary`)
  → `ModalBottomSheet(skipPartiallyExpanded)` with `OutlinedTextField`
  (price, `KeyboardType.Decimal`) · M3 `DatePickerDialog` (`SelectableDates`
  caps at today) · `FilterChip` `FlowRow` for platform · notes (≤280). Auth
  via `AuthViewModel.authState is SignedIn`. Submit →
  `CardDetailViewModel.submitCommunityComp` → `ProfileService` RPC, mapped to
  a typed `CommunityCompResult` (SUCCESS / RATE_LIMITED / ALREADY_THIS_WEEK /
  ERROR) so the Snackbar copy is specific. `:app:compileDebugKotlin` +
  `:core:network:compileDebugKotlin` BUILD SUCCESSFUL.

All three platforms send `photo_url = null` for now (text-only v1; mod
approval is the v1 gate). PARITY.md updated.

**Still remaining (Tier 3):** `boba-comp-upload` Worker (R2 photo, reuse
`boba-avatar-upload`), mod-queue UI (extend the `card_corrections` admin
panel with `get_pending_community_comps` / `review_community_comp`).

### 2026-05-27 — Tier 3 mod-queue review UI (web) — comps now reach the estimator

The submission flow was inert without a review surface (comps sit
`status='pending'` until a mod approves; only approved comps flow through
`get_approved_comps` → the estimator). Built the review queue on **web** —
the most ergonomic surface for the sole admin (desktop, and where photo
review will live). Mod workflows are intentionally low-chrome per DESIGN.md
§12, so this reuses the existing admin-panel overlay shell rather than
inventing new design language.

- **api.js:** `getPendingCommunityComps()` (→ `get_pending_community_comps`,
  SETOF rows; RLS + RPC both gate to mod/admin) + `reviewCommunityComp(id,
  approve, rejectReason)` (→ `review_community_comp`). Both registered in the
  API export.
- **collection.js:** a "Review Sold Comps" row in the Profile → Moderation
  section (visible to moderator + admin, alongside "Open Mod Panel"), with a
  best-effort pending-count badge. Opens `openCompsReviewPanel()` — a
  `.mod-edit-overlay` dialog listing each pending comp (card label resolved
  via `window.__bobaCatalog`, price · sold date · platform · notes) with
  per-row Approve / Reject (reject prompts an optional reason). Re-renders +
  refreshes the badge after each action.
- **styles.css:** `.comp-review-*` rows + `.profile-comps-badge` (low-chrome).
- `node --check` clean on api.js + collection.js + app.js.

End-to-end now closed: a user submits a comp on any platform → Ben approves
on web → the approved comp flows through `boba-pricing-tracker /comps` into
the estimator on all platforms. iOS/Android mod-queue parity is a follow-up
(mobile mod panels are lower priority; moderation happens on web).

**Still remaining (Tier 3):** `boba-comp-upload` Worker (R2 photo, reuse
`boba-avatar-upload`); iOS/Android mod-queue parity (optional — web covers
the sole-admin case today). Photo fingerprint-verify stays v2.

### 2026-05-27 — Tier 2 Whatnot Products Worker endpoint (built + verified)

`GET /whatnot/products?query=...` on `boba-ebay-proxy` returns current
active Whatnot listings: `{ query, count, summary:{low,average,high,count},
listings:[{ title, price, priceCents, currency, condition, listingId,
listingUrl, seller, sellerUrl, imageUrl, format:"buy_now"|"auction" }],
challenged? }`. Live-verified against `query=bojax` → 17 real listings,
$6.00–$25,000, correct sellers/images/formats.

**Reverse-engineering notes (the hard part):**
- Whatnot's public search is Next.js **App Router (React Flight stream)** —
  NO `__NEXT_DATA__`, and the rich feed is NOT in the 3 `ApolloSSRDataTransport`
  pushes. The listing entities are emitted as **raw, un-escaped JSON objects**
  in the HTML, so the robust extractor scans `{"__typename":"ListingNode"` and
  brace-matches each object directly (more durable than chasing the Flight/
  Apollo wrapper, which changes more often than the entity shape).
- Entity shape: `ListingNode { title, price:{__typename:"Money",amount,currency},
  currentBid, transactionType:"BUY_IT_NOW"|"AUCTION", listingStatus:"ACTIVE",
  user:{username}, salesChannels:[{channelId}], id(base64 "ListingNode:<num>") }`.
- **`Money.amount` is in CENTS** — calibrated against live data (699=$6.99,
  199900=$1,999.00, 1500000=$15,000); a dollars assumption would have been a
  100× error. Each listing is inlined ~6× per page → de-dupe by decoded
  listingId.
- Worker egress passes Whatnot's IP-reputation anti-bot (same as the shipping
  `/whatnot/upcoming` shows feed); `api.whatnot.com/graphql` is Turnstile-
  walled so we never touch it. Challenge detection → `challenged:true` soft-
  fail (COMC contract). 12-min edge cache. Diagnostics removed post-fix.

**Open design question before client integration (for Ben):** Whatnot's
search tokenizer is loose. A single distinctive hero token (`bojax`) returns
clean BoBA-only results, but a multi-word query (`bojax day one`) gets diluted
by unrelated "one/day" listings (Xbox Day One, Spider-Man One More Day). So
per-card surfacing needs a query/match strategy: query by the distinctive BoBA
hero token, then filter the returned titles to the specific card by cardNumber/
weapon tokens (the eBay-scoring approach). Since these render in **Buy Now only**
(never the Market Est., never the sold waterfall — asks inflate, #034 + §7),
some fuzziness is tolerable: the user scans titled tiles and taps through, just
like eBay actives. Client integration (iOS/web/Android Buy Now tiles) is next.

### 2026-05-27 — Card-match PRECISION tightening (eBay + Whatnot) — "one card, one price"

Ben flagged both matchers pulling in the wrong card: eBay surfacing near-miss
siblings/other-hero cards, Whatnot returning non-BoBA junk entirely. All in
`workers/ebay-proxy/worker.js`:

- **eBay sold (`normaliseSoldEnriched`):** a listing now must carry an EXACT
  card-number match AND a hero match to be shown OR aggregated. Partial-number
  / hero-only matches are a different (or unidentifiable) card → dropped, not
  even surfaced as "probable". Trades long-tail recall for precision (the
  honest Tier-5 "Listed Range"/"no data" fallback covers sparse cards).
- **eBay active (`matchActiveCandidates`):** the numeric-cardNumber path
  matched on hero ALONE (→ every card for that hero). Now requires the card
  number as a bounded title token too; the loose numPart fallback also
  requires the hero. Live check: P-8 Bojax Steel went ~95 → 10 actives, all
  containing "P-8".
- **Weapon-variant sibling reject (both paths):** a title naming a different
  BoBA weapon than the card (FIRE P-8 vs GLOW P-8 — same cardNumber, #057) is
  rejected. `element` threaded through the active matcher + `/tracker/active`.
  Conservative weapon word-list (fire/ice/hex/steel/brawl/glow/cyber — excludes
  "super"/"alt"/"gum" to avoid "super rare"/"alt art" false-rejects). Live
  check: 0 of 10 Steel actives name a conflicting weapon.
- **Whatnot BoBA-relevance gate (`wnAbsorbProduct`):** drop any listing whose
  title lacks a BoBA brand marker (battle arena / bo jackson / boba / bojax).
  Live check: "bojax day one" went from Xbox/Spider-Man/One-Day-Magnet junk →
  3 real "Bo Jackson Battle Arena" listings; clean "bojax" query unaffected (17).

`/` response shape unchanged; verified intact. Deployed.

### 2026-05-27 — card-match precision round 2 (treatment + ordinal + prefixed-number)

Ben flagged card #1 Maverick Base Set FIRE (bobaId `1-Maverick-Base Set-
First Edition-FIRE`, set "Griffey Edition") still showing wrong cards.
Diagnosed three leaks, all in `workers/ebay-proxy/worker.js`:

1. **Card number "1" matched "1st Edition".** The boundary regex treated the
   "1" in "1st" as the card number → almost any Maverick listing matched #1.
   Fix: `cardNumberTitleRegex` excludes ordinals (`(?!st|nd|rd|th)`). NOTE the
   card's *variation* is literally "First Edition" — but a listing saying only
   "1st Edition" (no separate "#1") is ambiguous (any first-ed Maverick), so
   excluding it is correct; "#1" listings still match.
2. **No treatment/parallel gate.** "Inspired Ink", "Colosseum Battlefoil"
   listings showed for the Base Set card. Fix: `titleHasTreatmentConflict` —
   a Base Set card rejects any title naming a distinctive special-treatment
   marker (battlefoil / inspired ink / superfoil / colosseum / linoleum /
   blizzard / mixtape / logofoil / kanjifoil / chillin). Decisive reject in
   the sold scorer + active matcher. `treatment` threaded through the active
   matcher + `/tracker/active`.
3. **Numeric card number matched a prefixed number's suffix.** "#OHBF-1"
   (Orange Battlefoil #1) matched card "1" (the "1" after "OHBF-"). Fix: the
   leading boundary for a numeric card number is start / whitespace / "#"
   only — not any non-digit — so "1" no longer matches "OHBF-1" / "GGL-1".
   Alphanumeric cards are unaffected (they use the full-token includes path).

Wrong-edition reject (`wrongEditionInTitle`) now also runs on actives (set
threaded through). The card's set is "Griffey Edition" so Griffey listings
correctly stay; the conservative edition-token check doesn't false-reject the
"2026" listings.

Live result for card #1: Inspired Ink / Colosseum / "#OHBF-1" all gone; the
10 actives are all exact (#1 · Maverick/Cooper Flagg · Fire · Griffey/First
Edition); avg $14.36 → $10.63. `/` shape unchanged. Deployed.

### 2026-05-27 — Whatnot match made adaptable (card number OR power) + weapon/treatment gates

Ben flagged card #149 J-Cam Base Set STEEL showing wrong Whatnot cards.
Root cause: BoBA Whatnot sellers title a card by its card NUMBER
("J-Cam #149") OR its POWER ("J-Cam Steel 110 Power") — often one, not the
other. The matcher required the card number, so #149 (whose listings are
power-titled) got bestMatchCount 0 and the old "Other" fallback showed
wrong cards.

Fix (`/whatnot/products`): `matchesCard = (cardNumberHit OR powerHit)` gated
by `titleNamesConflictingWeapon` (rejects FIRE/ICE/BRAWL listings for a
STEEL card — siblings share a cardNumber, #057) and `titleHasTreatmentConflict`
(rejects Battlefoil/Inspired/Icon listings for a Base Set card). Threaded
`power` + `treatment` params through the endpoint (cache key v3) and from all
three clients (web `fetchWhatnotProducts`, iOS `WhatnotProductsService.products`,
Android `PricingService.fetchWhatnotProducts`).

Live result for J-Cam #149 STEEL (power 110, Base Set): bestMatchCount 1 —
exactly "J-Cam Steel 110 Power" ($3); Battlefoil/Brawl/Fire/Ice/Icon
correctly excluded. node --check (web) + :app:compileDebugKotlin (Android)
clean. iOS v2.383.
