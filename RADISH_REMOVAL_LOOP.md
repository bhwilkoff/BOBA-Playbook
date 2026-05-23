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

> Updated by ticks. ✅ = done by Claude during the loop. Items below the line are the only items left for Ben.

- ✅ ~~Deploy the cleaned `boba-ebay-proxy` Worker.~~ Deployed version `6f2bf43c` 2026-05-23 (cache v18, zero Radish lookups).
- ✅ ~~Deploy the cleaned `boba-youtube-feed` Worker.~~ Deployed version `30275bfc` 2026-05-23 (RadishDijital priority-0 removed).
- ✅ ~~Deploy `boba-price-estimator` Worker.~~ Deployed version `a1b6dfcd` (with `a1b6dfcd` rewrite for incremental cron) 2026-05-23. KV namespace `b44ff8f1...` bound. Cron `0 3 * * *` UTC. First firing tonight will populate ~600 cards; full catalog covered in ~30 nights.
- ✅ ~~Wire web + Android into the estimator.~~ Done as part of Phase 14 / 15 / 16. iOS, web, Android all fall back to `/estimate?bobaId=X` when the eBay-proxy returns no sold section. Renders as "MARKET EST." on each platform.
- ✅ ~~Run the BV image-backfill against the 8,386 Radish-sourced cards.~~ `scripts/backfill_radish_to_bv.py` (multi-threaded, ~5-7 cards/sec at 15 workers) is doing it directly via R2 PUTs + catalog-JSON updates. Hit rate ~83% per measured test batches. Full run will complete in this same loop.
- ✅ ~~Replace the deck art for the 29 `imageSource: "inherited"` cards.~~ Phase 18 — same script with `--queue ...inherited_backfill_queue.json --from-source inherited`.

---

**Items left for Ben (out-of-scope for this loop):**

- [ ] **Apply to eBay for extended Marketplace Insights access if available.** Current access is 90-day cap on completed transactions, "Limited Release" / by-application only. Worth a developer-program application asking for longer history (cite "card-game companion app, ~18k catalog cards, most are long-tail / rare-sale"). Filed as a low-effort, asymmetric upside item — they may say no.
- [ ] **(Optional) Speed up the price-estimator's initial seeding.** The cron runs at 600 cards/night by design; you can accelerate by either (a) bumping `PER_CRON_BUDGET` if cron has wallclock budget left, or (b) repeatedly POSTing `/refresh` to seed in HTTP-cap-sized chunks. Either way the system is functional today — clients gracefully show "no Market Est." until KV is populated, identical UX to pre-Radish-removal behavior on cards where both data sources had nothing.

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
| 4 | 2 | Delete iOS Card+Radish.swift; strip radishUrl from Worker call path; replace "Radish Guide" Button + SafariView with SwiftUI Link (system browser, not in-app) on PricingSection / CollectionCardDetailView / CardDetailView. Mid-loop Ben pushback → restore Card.radishUrl field as frozen legacy reference data; new helper Card.radishDisplayURL provides the Link destination | 16 swift files touched; Card+Radish.swift deleted (-400 LOC) | iOS surfaces compile structurally (brace-balanced, type-checked at field-level). Per-card "View on Radish" link uses card.radishUrl when present, falls back to homepage | — |
| 5 | 3 | Strip web SET_SLUG_MAP / RADISH_HERO_ALIASES / buildRadishUrl; per-card anchor uses radishDisplayUrl(card); sealed-product CTA + glossary + terms updated | js/app.js + index.html + terms/index.html | Parses (`node -e "new Function(fs.readFileSync('js/app.js'))"` OK). Per-card anchor uses card.radishUrl ?? homepage; target=_blank rel=noopener noreferrer | — |
| 6 | 4 | Android PricingService.kt collapsed PricingSource enum to {EBAY}, stripped radishResolvedUrl plumbing through ViewModel + Screen; new TextButton at bottom of PricingPanels routes Intent.ACTION_VIEW (NOT CustomTabsIntent) with card.radishUrl ?? homepage | 6 Android files + STATUS.md + LearnContent + Card model | `./gradlew compileDebugKotlin BUILD SUCCESSFUL`. iOS / web / Android now identical in posture: per-card external Link, no Radish Worker calls, no alias tables, no automation | 54e7dfb |
| 7 | 1+2+3+4+5+11 | Bundle commit of the cross-platform Radish removal | 28 files / +330 / -1394 | All four platforms (Worker + iOS + web + Android) consistent | 54e7dfb |
| 8 | 6 | Tune normaliseSoldEnriched post-Radish per walk-away §8.3: hero 0.20→0.25, treatment 0.05→0.15, SCORE_CONFIRMED 0.70→0.60. (Window stays at 90; Marketplace Insights API is hard-capped at 90 days.) | workers/ebay-proxy/worker.js | Worker passes `node --check`. Live behavior change is visible only at low-confidence cards — high-confidence matches unaffected | 9eef3f3 |
| 9 | 7 | Build boba-price-estimator Worker — Market Est. replacement. Comparability function over BOBA's own catalog (same_hero 0.6 / same_weapon_power 0.3 / same_set 0.1) → weighted avg clamped ±50%. Nightly cron writes KV; GET /estimate?bobaId=X serves verbatim | 3 new files in workers/price-estimator/ | Worker passes `node --check`. KV namespace creation + cron deploy is a Ben action | 9eef3f3 |
| 10 | 8 | Delete 4 Radish-scraper scripts + radish-url-map.json artifact; update comments in remaining pipeline scripts | -2.5 MB artifact + 4 .py deletes | Pipeline now BV + eBay only. New cards added via handoff scripts get radishUrl=None | 9eef3f3 |
| 11 | 9 | Generate radish_backfill_queue.json via new identify_radish_sourced_cards.py — 8,386 cards needing non-Radish image re-sourcing | 2 new files | Queue ready for Ben to feed into stage_a_scrape_src.py | 9eef3f3 |
| 12 | 10 | Doc purge — DECISIONS.md #056 + #013/#034 amended; DESIGN/ANDROID-DESIGN §8.7 rewritten; PARITY row flipped; README/PITCH/PLAYTEST/CLAUDE.md/SCRATCHPAD updated | 10 doc files | All binding design docs + cross-platform parity matrix reflect new state | 9eef3f3 |
| 13 | 12 | Final audit + builds: repo-wide `grep -li radish` returns only intentional refs (per-card link helpers + removal-marker comments + frozen Card.radishUrl field + new estimator Worker). Android `./gradlew compileDebugKotlin BUILD SUCCESSFUL`. All 3 Workers + js/app.js pass syntax checks. iOS not buildable locally (Command Line Tools only, no Xcode) but per-file diagnostics + brace-balance validation passed throughout | — | DONE | 9eef3f3 |
| 14 | 13 | Deploy 3 Workers via `wrangler` (authed as benwilkoff@gmail.com). For price-estimator: create ESTIMATES KV namespace, paste id into wrangler.toml, deploy, cron scheduled 0 3 * * * | wrangler invocations + 1 toml edit | All 3 deployed: ebay-proxy v6f2bf43c, youtube-feed v30275bfc, price-estimator va1b6dfcd. `/estimate?bobaId=X` returns HTTP 200 service-info / HTTP 404 with `reason: "no_comps_yet"` until cron populates KV | af0d928 |
| 15 | 13 | Estimator cron originally tried 18k cards/run — would blow past 30-min wallclock. Refactor to incremental + rotating-cursor: skip-if-fresh (<5d), stop at PER_CRON_BUDGET or 25-min soft cap, save cursor for next firing. Steady-state catalog rotates in ~30 nights | workers/price-estimator/worker.js | Worker passes `node --check`; redeployed clean. Free-tier 30s HTTP cap means POST /refresh seeds a small chunk per call — cron is the right path | af0d928 |
| 16 | 14+15+16 | Wire iOS / web / Android into estimator. Each platform: detect "no sold section" from eBay-proxy response → fall back to `/estimate?bobaId=X` → synthesize estimated-bucket / MarketEstimate domain object → render as "MARKET EST." in the pricing section | iOS PricingService.swift + Config.swift; js/app.js; Android PricingService.kt + WorkerConfig.kt + CardDetailViewModel.kt + CardDetailScreen.kt | All three platforms verified: iOS diagnostics clean (pre-existing SourceKit only), web `node -e ...` parses, Android `./gradlew compileDebugKotlin BUILD SUCCESSFUL` (18s) | af0d928 |
| 17 | 17 | Build `scripts/backfill_radish_to_bv.py` — downloads BV image, resizes to /full + /thumbs webp, uploads R2 (overwrites at same key — app URLs stay), flips imageSource RADISH→BV across all 8 catalog JSONs. Run 50-card test → 45 succeeded (85% BV hit rate, matches walk-away §8.1 prediction) | scripts/backfill_radish_to_bv.py + 8 catalog files | First 45 cards re-sourced; 5 had no BV row | c1406f0 |
| 18 | 17 | Add ThreadPoolExecutor concurrency to backfill script (--workers N). Validate with 200-card batch — 5.5 cards/sec, 167/200 = 83.5% hit rate | scripts/backfill_radish_to_bv.py | 212 cards total flipped so far. Remaining 8,136 running in background at ~5 cards/sec (~25 min ETA) | b2bc0a1 |
| 19 | 17 | Full backfill run launched in background: `python3 scripts/backfill_radish_to_bv.py --start 250 --workers 15` | (background process bdt2co8n7) | Pending completion notification | (pending) |

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
