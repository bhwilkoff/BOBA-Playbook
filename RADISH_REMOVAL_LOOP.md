# Radish Removal Loop

Autonomous removal of all Radish-sourced data, lookups, partner language, and dependencies from BOBA Playbook across iOS / web / Android / Workers / pipeline. Triggered 2026-05-23 by an email from Scot + Rob (Radish owner / lead dev) treating BOBA Playbook as a competing product.

> Each tick = one hypothesis + one change + one observed result. Same format as SCANNER_LOOP.md.

## Source-of-truth requirements (from Scot + Rob's email, all binding for the next shipping version)

Per the email, BOBA Playbook MUST NOT:
- Use Radish pricing
- Use Radish as part of any pricing waterfall
- Display, cache, store, reproduce, or republish Radish pricing or sales data
- Use Radish-sourced catalog images for new ingestion
- Use Radish-derived catalog data, URL mappings, card relationships, or lookup logic
- Run automated lookups, scraping, probing, crawling, or API-style workflows against Radish
- Send push notifications or surface in-app features triggered by Radish pricing or sales updates
- Use "Powered by Radish," "official pricing partner," "pricing data partner," or similar language
- Use Radish assets, data, structure, or reputation to power a competing pricing or collection-management experience

The ONE thing allowed: ordinary user-facing linking to Radish Price Guide where the user leaves BOBA Playbook and views the information directly on Radish. Those links cannot be used as part of an automated extraction, lookup, validation, pricing, or routing system.

## Ben's additional constraints

1. Keep ONE single per-card Radish link on every card-detail view (opens external browser on iOS / Android, new tab on web — never inside a WebView or SFSafariViewController where it would look "powered by" BOBA).
2. **NEVER substitute another card's art for a different card.** The "one card, one image, one bobaId" mantra is preserved. This rules out the sister-card-inheritance compositor that the walk-away plan §8.1 floated. Image-gap recovery must use independent sources (the card source expansion, eBay-image-sourcer for the long tail, community submissions).
3. Don't stop until both (a) email requirements are met and (b) full functional replacement is in place.

## Replacement architecture (preview)

| Surface today | Tomorrow |
|---|---|
| Radish recent sales (Tier 1) | Tuned `normaliseSoldEnriched` on eBay sold + 180-day window + AI image-verification on sold |
| Radish Market Est. (Tier 3) | New `boba-price-estimator` Worker — comparability function over our own catalog + cross-set hero anchoring + nightly KV cache |
| Radish image scrape (8,386 cards) | (a) Existing bytes stay on R2 — they're ours per DECISIONS.md #008. (b) Future-discovery via the card source re-sweep + new `stage_a_scrape_ebay_images.py` + community submissions. **No sibling inheritance.** |
| Radish "Guide" deep-link | One external-browser link per card, no probing |
| RadishDijital Watch tab priority-0 pin | Removed; BoBattleArena promoted |
| "Radish recent sales" / source pills | "RECENT SALES" with eBay sold as the sole source |

## Things Ben will need to do (running list)

> Updated by ticks.

- [ ] **Apply to eBay for extended Marketplace Insights access if available.** Current access is 90-day cap on completed transactions, "Limited Release" / by-application only. Walk-away §8.3 banks on this window staying 90 days. Worth a developer-program application asking for longer history (cite "card-game companion app, ~18k catalog cards, most are long-tail / rare-sale"). Filed as a low-effort, asymmetric upside item — they may say no.

## Research outcomes (tick 1 — 2026-05-23)

External pricing-source research returned a clear verdict: **no third-party source is worth integrating to replace Radish.**

| Source | Verdict | Why |
|---|---|---|
| **PSA Auction Prices Realized** | SKIP | Graded-only; near-zero BOBA coverage (BOBA cards are essentially ungraded today) |
| **130point.com** | SKIP | No API; ToS-protected; derives from eBay + auction houses we already cover |
| **TCDb** | SKIP | ToS explicitly forbids scraping/data-mining |
| **Whatnot post-stream sales** | SKIP | No public API; only seller-self-export. Existing upcoming-shows integration stays |
| **Sportlots, COMC sold, Goldin** | SKIP | No APIs; same takedown-letter risk as Radish |
| **eBay Marketplace Insights** | KEEP — load-bearing | Already integrated; first-party-licensed; only legitimate long-tail comp source |
| **Community-submitted comps** | BUILD | Only path to grow BOBA-specific coverage no third party will ever index. Long-term moat |
| **Our own Market Est. estimator** | BUILD | Comparability function over our own catalog data; KV-cached; no external dependency |

## Tick log

| Tick | Phase | Hypothesis | Change | Result | Commit |
|---|---|---|---|---|---|
| 1 | 0 | Need file:line inventory before any deletion to avoid missing surfaces | grep across 73 files; classify per phase; spawn research agent in parallel | 472 code-line refs across 52 files. Research returned: no third-party source worth integrating (PSA graded-only, 130point no API, TCDb anti-scrape, etc.) — eBay Marketplace Insights + community comps + our own estimator is the path | — |
| 2 | 1 | Worker is the centerpiece: delete `fetchRadishSales`/`fetchRadishMarketEst`/`RADISH_NAMESPACES`/buildId/URL-resolver, bump cache v17→v18, strip `radishResolvedUrl` from response | Stream-build via `sed -e '491,849d' -e '1438,1613d'` (535 lines deleted), then 6 inline Edits | Worker passes `node --check`. Goes from 2423→1888 lines. Radish refs from 100→3 (all in removal-marker comments). Pricing path is now eBay-only: searchSold → normaliseSoldEnriched → searchActive. Market Est. tier removed (Phase 7 separate Worker will replace it) | — |
| 3 | 5 | Remove `radishdijital` priority-0 pin from Watch tab — email prohibits special partner treatment; switch to "no current priority-0" with infra preserved for future explicit invitation | Edit KNOWN_CHANNELS, rewrite 4 comments that named RadishDijital, update README | YT worker passes `node --check`. 0 Radish refs remain in either file. RadishDijital videos will still appear in feeds via the BoBA search query (ordinary public-content surfacing — allowed) but without channel-pull or priority pinning | — |

## Design decisions logged this run

**Per-card "View on Radish" link target.** The email prohibits "URL mappings" + "lookup logic" + "Radish-derived catalog data" + automation. Ben wants ONE link per card opening externally so users can see the card directly on Radish.

Reconciliation (Ben confirmed 2026-05-23, mid-loop): use the **legacy `card.radishUrl` field already in `cards.json`** as the link target, falling back to `https://radishpriceguide.com` (homepage) when the field is null. The data already exists on disk (pre-acquired before the email); we're using it ONLY for static rendering of the approved "ordinary user-facing linking" use case. **Every form of automation the email prohibits stays fully deleted:**

- ❌ `scripts/build_radish_url_map.py` — deleted (won't re-pull sitemap)
- ❌ `scripts/apply_radish_urls.py` — deleted (won't re-apply URLs to catalog)
- ❌ `scripts/probe_radish_urls.py` — deleted (won't HEAD-probe)
- ❌ `pipeline/scripts/stage_a_scrape_radish.py` — deleted (won't scrape images)
- ❌ Hero alias tables (`RADISH_HERO_ALIASES`) — deleted on iOS + web
- ❌ Set-slug maps (`SET_SLUG_MAP`) — deleted on iOS + web
- ❌ `RadishURLResolver` (HEAD-probing + sitemap-driven Worker lookups) — deleted
- ❌ Worker `/radish-url` + `/radish-url-map` endpoints — deleted
- ❌ Worker `fetchRadishSales` / `fetchRadishMarketEst` / `fetchRadishCardId` / buildId scraping — deleted
- ❌ Passing `radishUrl=` to the Worker as a lookup hint — deleted (Worker doesn't accept it either)

The catalog `radishUrl` field is treated as **frozen static data** — never refreshed, never validated, never appended to. New cards added post-2026-05-23 have `radishUrl: null` and their button falls back to the homepage. Button label "View on Radish" sets the right expectation regardless of which path.

## Cumulative file changes

> Updated at the end of each phase commit. Same shape as SCANNER_LOOP.md's running summary.

(empty)
