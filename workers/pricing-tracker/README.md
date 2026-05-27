# boba-pricing-tracker (Tier 1)

Generates BOBA's **own** sold-history from public eBay Browse listings over
time — because eBay Marketplace Insights (real sold comps) is permanently
unavailable to us (PRICING_PLAYBOOK.md §0). Every cadence we snapshot active
listings per card into D1; when a listing **vanishes** from a later snapshot
we infer "sold @ last-seen price" with a confidence score (§3.4). After ~60
days we own a sold-history dataset no external API gives us.

Full design: [`PRICING_PLAYBOOK.md`](../../PRICING_PLAYBOOK.md) §3.

## Status

- `GET /comps?bobaId=X&days=90` — **live + complete.** Returns inferred-sold
  "Recent Sales" (rows with `sold_confidence >= 0.55`) in the §3.5 shape.
  Returns an empty comp set until the snapshot populates D1.
- `POST /snapshot?budget=N` and the cron — **implemented but GATED off.**

## The two-part build (why the snapshot is gated)

Reliable vanish-inference needs the **full** active-listing set per card with
**stable item ids**. The current `boba-ebay-proxy` main endpoint returns only
the **top ~10 of N** listings, each `{title, price, date, url}` — no item id
field (we parse it from the `/itm/{id}` URL), no `buyingOption`/`endDate`/
`seller`/`condition`. Inferring "sold" from a truncated top-10 would fire
false positives the moment a listing drops out of the top 10 by ranking
rather than by selling.

So Tier 1 ships in two steps:

1. **Enrich the eBay-proxy** with a tracker endpoint
   `GET /tracker/active?cardNumber=…&full=1` that returns *every* matched
   active listing with `{itemId, price, buyingOption, endDate, seller,
   condition, image, url}` straight from the Browse API (the proxy already
   holds the OAuth + scoring). This is a change to a **production** Worker the
   whole app depends on for pricing, so it gets its own careful pass + a
   verify that existing `/` pricing responses are unchanged.
2. **Enable the snapshot** here (`activeListingsFor` already targets that
   endpoint), validate one manual `POST /snapshot?budget=20` writes sane rows,
   then turn on the 6h cron in `wrangler.toml`.

`worker.js` is written for step 2 already — `activeListingsFor` returns `[]`
until the proxy endpoint exists, so the snapshot is a safe no-op meanwhile.

## Deploy / operate

```bash
# one-time: DB created (id in wrangler.toml) + schema applied
wrangler d1 execute boba-pricing --remote --file=workers/pricing-tracker/schema.sql
cd workers/pricing-tracker && wrangler deploy            # read endpoint only (no cron)

# after step 1 (enriched proxy) lands + validated:
#   1) uncomment [triggers] crons in wrangler.toml
#   2) wrangler deploy
#   3) curl -X POST .../snapshot?budget=20   # sanity-check first run
```

## Confidence (§3.4)

v1 `soldConfidence` scores vanish-inference from listing **duration** (long
BIN that finally moves = likely sale; <24h = likely delist/typo). The richer
signals (auction end vs vanish, seller bulk-delist) activate automatically
once the enriched proxy populates `format`/`end_time`/`seller_id`. Only
`sold_confidence >= 0.55` surfaces to users; lower rows stay in D1 for tuning.
