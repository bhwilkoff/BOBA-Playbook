# boba-price-estimator

Cloudflare Worker that produces a Market Est. for every catalog card using a comparability function over BOBA's own catalog data. Replaces the Radish Market Est. tier that was removed 2026-05-23 (DECISIONS.md #056 + RADISH_REMOVAL_LOOP.md Phase 7).

## How it works

A nightly cron walks every catalog card. For each card it computes a "comparable set" along three axes:

| Axis | Weight | Definition |
|---|---|---|
| same_hero | 0.6 | Other cards with the same hero |
| same_weapon_power | 0.3 | Same element + power-tier + treatment-family |
| same_set | 0.1 | Same (set, cardType) |

For each comparable, the cron queries `boba-ebay-proxy` for the recent eBay sold average. The weighted mean of those averages becomes the card's mid-point estimate. Low/high are clamped to ±50% of mid so a single outlier comp can't blow up the spread.

Results land in Cloudflare KV at `estimate:{bobaId}` with a 7-day TTL. Clients query `GET /estimate?bobaId={X}` and get the precomputed entry back, or a 404 with `{ "reason": "no_comps_yet" }` when the card hasn't accumulated comps yet (early days post-deploy, brand-new sets).

## What this Worker explicitly does NOT do

- **Does NOT call Radish.** That's prohibited per DECISIONS.md #056. The estimator only consults BOBA's own catalog + eBay (via `boba-ebay-proxy`).
- **Does NOT scrape any third-party HTML.** Everything routes through `boba-ebay-proxy`, which uses eBay's licensed APIs.
- **Does NOT mutate the catalog.** Reads cards.json from GitHub Pages; never writes back.
- **Does NOT sister-card-inherit.** A card with no comps gets `null` estimate, not borrowed art / borrowed price from a different card. Preserves the "one card, one image, one bobaId" mantra at the pricing layer too.

## First-time deploy

```bash
cd workers/price-estimator

# 1. Auth Wrangler against your Cloudflare account (already done if
#    you've deployed boba-ebay-proxy from the same machine).
wrangler login

# 2. Create the KV namespace. Paste the printed id into wrangler.toml's
#    [[kv_namespaces]] block (replace REPLACE_AFTER_CREATE).
wrangler kv:namespace create ESTIMATES

# 3. Deploy.
wrangler deploy

# 4. (Optional but recommended) trigger the first refresh manually so
#    you don't wait up to 24h for the cron to seed KV.
curl -X POST https://boba-price-estimator.<your-subdomain>.workers.dev/refresh
# (expect ~10-20 min runtime for ~18k cards × ~6 concurrent comp queries each)

# 5. Verify a sample card.
curl "https://boba-price-estimator.<your-subdomain>.workers.dev/estimate?bobaId=RBF-72-Maverick--"
# → { "bobaId": "...", "low": ..., "mid": ..., "high": ..., "comparableCount": N,
#     "comparableSources": ["same_hero", ...], "computedAt": "...", "method": "comparability" }
```

## Wire into the clients

The estimator is consulted by iOS / web / Android when `boba-ebay-proxy` returns no sold-section data. The client logic (pseudocode):

```
soldSection = boba-ebay-proxy(card).sold;
if (soldSection == null) {
  estimate = boba-price-estimator(card.bobaId);
  if (estimate) {
    soldSection = {
      low: estimate.low,
      average: estimate.mid,
      high: estimate.high,
      count: estimate.comparableCount,
      estimated: true,
      estimatedSource: "comparability",
    };
  }
}
```

iOS already has the `estimated` / `estimatedSource` fields plumbed through `PricingService.PricingResult` — see `BOBAPlaybook/Networking/PricingService.swift`. Web + Android need a follow-up tick to wire in the second-Worker call.

## Comparability function tuning

| Knob | Default | Effect |
|---|---|---|
| `WEIGHT_SAME_HERO` | 0.6 | Hero matches dominate the weighted average. Drop this if the hero signal is too noisy on long-tail cards. |
| `WEIGHT_SAME_WEAPON_POWER` | 0.3 | Cards with the same element + power-tier + treatment family. The bootstrap path for brand-new sets where no in-hero comps exist. |
| `WEIGHT_SAME_SET` | 0.1 | The set-level anchor — keeps brand-new cards from drifting wildly when other signals are sparse. |
| `CLAMP_FRAC` | 0.5 | Caps the low/high spread to ±50% of mid. Lower this if you want tighter ranges, higher if the catalog tends to spread more. |

Power-tier buckets + treatment families live in `powerTier()` / `treatmentFamily()` in `worker.js` — extend when new treatments ship.

## What's tracked vs. what isn't

The cron logs `[estimator-cron] processed=N written=M elapsedMs=N` per run. Visible via `wrangler tail`. No Supabase write-back — KV is the only persistence layer. If you want long-term accuracy metrics, add a Supabase logger here later.

The Worker does NOT track *which* eBay listings drove each comp. That's only available transiently in `boba-ebay-proxy`'s response. If we want a per-card "see the comps that drove this estimate" UI later, this is where to plumb it in.
