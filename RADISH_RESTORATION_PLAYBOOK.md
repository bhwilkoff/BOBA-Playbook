# Radish Restoration Playbook

> If Radish Price Guide ever re-authorizes integration with BOBA Playbook,
> **this document is the recipe to bring everything back.** Every removed
> piece is catalogued below with the exact git SHA where the code still
> lives + step-by-step restoration instructions.
>
> Current status (2026-05-23): all Radish data flows, lookups, alias
> tables, automation, partner language, and Watch-tab pinning are
> removed per Scot + Rob's email. The only Radish surface that remains
> is per-card "View on Radish" external-browser links. See
> `RADISH_REMOVAL_LOOP.md` for the removal log + `DECISIONS.md` #056
> for the architectural decision.

## Quick reference — the removal commits

The original removal landed across three commits in May 2026. To
view the deleted code, `git show <SHA>` or `git diff <SHA>~1 <SHA>`.

| SHA | Commit subject |
|---|---|
| `54e7dfb` | radish: remove pricing waterfall, lookup logic, Watch-tab pin (all platforms + Workers) |
| `9eef3f3` | radish: replacement infra + pipeline cleanup + docs purge + scorer tuning |
| `a18ca31` | radish: final audit — kill GitHub workflows, dormant script, DB constraint |

To restore any single piece: `git show <SHA>~1:<path>` outputs the
file's contents from the commit BEFORE removal — copy-paste from there.

## Pre-restoration checklist

If/when Radish re-authorizes:

- [ ] Get the written authorization in hand (replace the original 2026-05-23
      revocation email in the project record). Reference any specific
      partnership terms — e.g. attribution string, affiliate ID,
      brand colors — they'll affect which restoration paths apply.
- [ ] Decide which tiers of integration to re-enable. The original
      coverage was: pricing tier 1 + tier 3 (Radish sales + Market Est.),
      catalog-image source, Watch tab priority pin, per-card deep links.
      A partnership might re-authorize all or only some.
- [ ] If pricing is back: confirm the eBay-proxy and price-estimator
      Workers can be modified without breaking the new
      `card_prices_history` persistence layer (Phase 19) and
      `boba-pricing-snapshot` Worker (Phase 19).
- [ ] If images are back: decide whether to re-source the 4,590 cards
      that flipped RADISH→BV. Their R2 bytes are now BV-sourced; flipping
      back is mechanically the inverse of the same script.

---

## 1 — Worker: `boba-ebay-proxy` Radish integration

**What was removed.** The full pricing waterfall integration (Tier 1 +
Tier 3) plus the standalone URL resolver endpoints.

| Surface | Old location (pre-`54e7dfb`) | What it did |
|---|---|---|
| `fetchRadishHTML(url)` | `workers/ebay-proxy/worker.js` ~lines 501-526 | Cloudflare-friendly fetch of a Radish page with body-drain to avoid the stalled-response trap |
| `stripCardNumberFromRadishURL(url)` | ~lines 528-542 | URL helper |
| `RADISH_NAMESPACES` constant | ~lines 544-563 | 12-entry `(year, slug)` array sweeping known Radish set pages |
| `fetchRadishSales(radishUrl, days)` | ~lines 565-650 | Tier 1: parallel namespace sweep, extracts `allSales` from `__NEXT_DATA__`, stale-sale fallback |
| `parseRadishURL(url)` | ~lines 652-692 | Parses 4- and 5-segment Radish URL paths |
| `tryRadishURL(url, days)` | ~lines 694-735 | Per-URL probe + in-window filter + allItems sort |
| `getRadishBuildId()` | ~lines 762-776 | Scrapes the Next.js buildId from a Radish page; 24h cache |
| `fetchRadishCardId(year, slug, hero, cardNumber)` | ~lines 778-808 | Hits `/_next/data/{id}/...` to get Radish's internal numeric card_id |
| `fetchRadishMarketEst(radishUrl)` | ~lines 810-848 | Tier 3: hits `/api/boba/estimated-value?card_id=...` for comp-based range |
| `RADISH_SITEMAP_URL` + `fetchRadishURLMap()` + `getRadishURLMap()` + `handleRadishURL(request)` + `handleRadishURLMapDump(request)` | ~lines 1438-1612 | `/radish-url` endpoint (sitemap-driven URL lookup) + `/radish-url-map` (full dump for offline catalog baking) |

**Restoration steps:**

1. `git show 54e7dfb~1:workers/ebay-proxy/worker.js` — copy the
   sections back. The old file is 2,423 lines; the new is 1,888 lines.
2. Re-add the routes `/radish-url` + `/radish-url-map` in the main
   handler (around `if (request.method === "GET" && url.pathname.endsWith("/scrape-ebay"))`).
3. Re-add the parallel-fetch block in the main pricing handler — old
   structure: `Promise.allSettled([radishUrl ? fetchRadishSales(radishUrl, days) : null, getAppToken(env, cache)])`.
4. Re-add the `radishResolvedUrl` to the response shape so clients
   can snap their "View on Radish" link to the URL that actually
   had data.
5. Re-add the Market Est. fallback block (consult `fetchRadishMarketEst`
   when `!soldSection && radishUrl`).
6. Bump the cache key (current is `v18`; bump to `v19` so old
   Radish-free cached responses don't leak through).
7. Update the file header docstring to put Radish back as Tier 1 + 3.
8. Revert the post-Radish scorer tuning in `normaliseSoldEnriched`
   (or leave it; the tuned weights are still defensible). The
   pre-removal values: hero `0.20`, treatment `0.05`, `SCORE_CONFIRMED`
   `0.70`.

**Will require fresh:**

- The current `RADISH_NAMESPACES` list (Radish has shipped sets since
  May 2026 that aren't in the historical list). Refresh with
  `curl https://radishpriceguide.com/boba | grep -oE 'href="/boba/[0-9]+/[A-Za-z_]+"'`.
- The hero-name alias table (`heroVariants` and `RADISH_HERO_ALIASES`).
  Re-verify against current Radish URL patterns.

---

## 2 — Worker: `boba-youtube-feed` RadishDijital priority pin

**What was removed.** The `radishdijital` channel handle was a
priority-0 entry in `KNOWN_CHANNELS`, which pinned their newest
videos to the top of every Watch-tab feed.

| Surface | Old location | What it did |
|---|---|---|
| `KNOWN_CHANNELS` entry | `workers/youtube-feed/worker.js` line 64 (pre-`54e7dfb`) | `{ handle: "radishdijital", priority: 0 }` — channel pull + priority-0 pinning |
| Comment in `categorize()` | line ~84 | Explained that the `📱` emoji is RadishDijital's daily-show phone-edition marker (this was the trigger for vertical classification) |
| Comment in `refreshFeeds()` | lines ~250-255 | Explained that priority-0 pins capped at TOP-3 most-recent items so the feed isn't dominated by one channel |
| Comment in `isVerticalVideo()` | line ~509 | Same `📱` rationale |
| README references | `workers/youtube-feed/README.md` lines 11-13, 72, 82 | Listed RadishDijital as the priority-0 channel + example item shape |

**Restoration steps:**

1. `git show 54e7dfb~1:workers/youtube-feed/worker.js` and
   `git show 54e7dfb~1:workers/youtube-feed/README.md`.
2. Re-add the `KNOWN_CHANNELS` entry. Decide whether priority-0 is the
   right pinning strength for a renewed partnership — the agreement
   may specify a different elevation (e.g. priority-3 "elevated but
   not pinned").
3. Restore the channel-specific comments in `categorize()` /
   `refreshFeeds()` / `isVerticalVideo()`. The `📱` heuristic is
   still useful for ANY creator who uses the emoji to mark vertical
   uploads, so the heuristic itself doesn't need changing — just the
   comment attribution.
4. README's item-shape example needs `"sourceChannel": "radishdijital"`
   + `"channelTitle": "Radish Dijital"` again.

The `📱`-emoji vertical-crop logic in `WatchView.swift` / `WatchPage.kt`
already works for any creator who uses it — no client-side restoration
needed.

---

## 3 — iOS: `Card+Radish.swift` + RadishURLResolver

**What was removed.** The entire `BOBAPlaybook/Models/Card+Radish.swift`
file (400 lines) plus the per-card-URL passthrough from 4 view files.

| Surface | Old location | What it did |
|---|---|---|
| `Card.resolvedRadishURL` | `Card+Radish.swift` lines 47-130 | Synthesized a Radish URL per card from `set` + `hero` + `cardNumber`. Carried the `setMap` (Set name → year/slug) and `heroAliases` (CamelCase mismatches) and `prefixMap` (cardNumber casing). |
| `Card.resolvedRadishUrlString` | line 134 | String form for passing to the Worker as `radishUrl=` |
| `Card.heroOnlyRadishURL` | lines 142-154 | Hero-page fallback when card-detail URL 404s |
| `Card.radishCandidateURLs` | lines 173-195 | Probing fan-out across cardNumber-casing × hero-casing × year-namespace permutations (≤8 candidates per card) |
| Private helpers | lines 201-272 | `heroCasingVariants`, `flippedCasingRadishURL`, `alternateYears`, `withYear` |
| `RadishURLResolver` class | lines 287-399 | Three-tier resolver: pre-baked `radishUrl` field → Worker `/radish-url` endpoint → HEAD-probe of locally-constructed candidates. Per-app-session cache keyed on `card.id`. |

**Restoration steps:**

1. `git show 54e7dfb~1:BOBAPlaybook/Models/Card+Radish.swift` →
   recreate the file in `BOBAPlaybook/Models/`. PBXFileSystemSynchronizedRootGroup
   will pick it up; no `.pbxproj` edit needed (per memory
   `feedback_xcode_synchronized_groups`).
2. Update `BOBAPlaybook/Components/PricingSection.swift`:
   - Re-add `@State private var showRadish = false`
   - Re-add `@State private var resolvedRadishURL: URL?`
   - Restore the `.task` block that calls
     `await RadishURLResolver.shared.resolve(for: card)`
   - Restore the Button + `.sheet(isPresented: $showRadish) { SafariView(url: radishURL) }`
     (or — for full email-compliance even post-restoration — KEEP the
     Link to external browser instead of SafariView)
   - Restore the `radishUrl: radishStr` argument to the `pricing(...)` call
   - Restore the `pricingResult.radishResolvedUrl` snap-the-button block
3. Update `BOBAPlaybook/Networking/PricingService.swift`:
   - Re-add `radishUrl: String?` parameter
   - Re-add `if let radishUrl { queryItems.append(URLQueryItem(name: "radishUrl", value: radishUrl)) }`
   - Re-add `radishResolvedUrl: String?` field on `PricingResult` + `PricingResponse`
4. Update the 4 call sites that previously passed `radishUrl:`:
   `CollectionStore.swift`, `AddToCollectionSheet.swift`,
   `ShowDetailView.swift`, `ScanQueueView.swift`. Pattern is one
   line: `radishUrl: card.resolvedRadishUrlString,`.
5. Update `BOBAPlaybook/Views/Collection/CollectionCardDetailView.swift`
   + `BOBAPlaybook/Views/Search/CardDetailView.swift` to put the
   in-app SafariView Sheet back if that's the partnership's preference.
   (Otherwise leave them as external SwiftUI Links — the per-card link
   target still works via `card.radishUrl`.)
6. Remove the `Card.radishDisplayURL` shim if it's no longer the
   primary path — or leave it as a fallback when `RadishURLResolver`
   times out.

---

## 4 — Web: `js/app.js` Radish URL builder + Worker passthrough

**What was removed.** The set-slug map, hero alias table, and the
`buildRadishUrl()` function that fed the Worker.

| Surface | Old location | What it did |
|---|---|---|
| `SET_SLUG_MAP` constant | `js/app.js` ~lines 3532-3564 (pre-`54e7dfb`) | 22-entry map of catalog set names → `[year, slug]` for Radish URL construction |
| `RADISH_HERO_ALIASES` | ~lines 3579-3589 | `{ BoJax: 'Bojax' }` and similar casing fixes |
| `buildRadishUrl(card)` | ~lines 3591-3627 | Per-card URL builder with prefix-casing, hero-alias, and Sealed-Product handling |
| Sealed CTA `${card.radishUrl ? ...}` block | ~lines 4336-4343 | Per-card "Radish Guide" anchor on sealed-product card detail |
| `radishUrl` param in `loadPricing()` Worker call | ~lines 3679-3693 | Passed the synthesized URL to `boba-ebay-proxy` so the Worker could scrape Radish sales |
| `data.radishResolvedUrl` post-fetch snap | ~lines 3711-3713 | Updated the "Radish" anchor href to the Worker-resolved URL |

**Restoration steps:**

1. `git show 54e7dfb~1:js/app.js` — copy the SET_SLUG_MAP +
   RADISH_HERO_ALIASES + buildRadishUrl back into the PRICING section
   (currently ~line 3532).
2. Restore `const radishUrl = buildRadishUrl(card);` in `loadPricing()`
   and add it to the `params` URLSearchParams.
3. Restore the post-fetch `data.radishResolvedUrl` snap-the-button block.
4. Restore the sealed-product anchor pattern: `${card.radishUrl ? '<a ...>Radish Guide</a>' : ''}`.
5. The "View on Radish" anchor in `loadPricing()` can either:
   - Stay as the homepage-or-radishUrl pattern (no-op since restoring
     buildRadishUrl now produces the deeper URL), or
   - Be reverted to "Radish Guide" branding if the partnership specifies.

---

## 5 — Android: `PricingSource.RADISH` enum + plumbing

**What was removed.** The `RADISH` enum value, URL host-detection
that tagged tiles by source, `radishResolvedUrl` plumbing through
the ViewModel + Screen.

| Surface | Old location | What it did |
|---|---|---|
| `PricingSource` enum | `android/core/network/.../PricingService.kt` line 139 (pre-`54e7dfb`) | `enum class PricingSource { EBAY, RADISH }` — currently just `{ EBAY }` |
| Host-detection in `fetchAll()` | lines 70-87 | Tagged each sold item EBAY vs RADISH based on `url.contains("radishpriceguide.com")` |
| `PricingBundle.radishResolvedUrl` | line 116 | Worker-validated Radish landing URL |
| `EstimatorResponse.radishResolvedUrl` | line 155 (in `PricingResponse`) | Wire field from Worker |
| `CardDetailUiState.radishUrl` | `android/app/.../carddetail/CardDetailViewModel.kt` line 37 | Per-bobaId Worker-resolved URL for tap-through |
| `PricingState.radishUrl` map | line 205 | Cache per-bobaId |
| `fallbackUrlForBlankRadish` param | `android/app/.../carddetail/CardDetailScreen.kt` lines 1418, 1428 | Tap-target for sold tiles where listing.url is blank (Radish sometimes shipped sales without per-item URLs) |
| `radish-stub-$i` URL synthesis | lines 1392-1393 | De-dup workaround for collapsing empty-URL tiles |
| `RADISH -> "Radish"` source label | line 1435 | Source-chip label on the tile |

**Restoration steps:**

1. `git show 54e7dfb~1:android/core/network/src/main/java/com/bobaplaybook/core/network/PricingService.kt`
   → restore the enum value + host-detection + radishResolvedUrl field.
2. Same for `CardDetailViewModel.kt` + `CardDetailScreen.kt`.
3. The current "View on Radish" `TextButton` at the bottom of
   `PricingPanels` can stay (it's the external-browser link) — or
   move back to per-tile tap-through if the partnership re-enables
   the Radish tap-target on listing tiles.
4. Per the email's letter, the current implementation uses
   `Intent.ACTION_VIEW` (system browser) for the per-card link.
   If a renewed partnership prefers an in-app Custom Tab, swap to
   `androidx.browser.customtabs.CustomTabsIntent` (already used
   elsewhere in the screen for eBay tile tap-throughs).

---

## 6 — Pipeline: Radish scraper scripts + cron workflows

**What was deleted.** Four Python scripts + the artifact they
produced + two GitHub Actions workflows.

| File | Pre-removal SHA | What it did |
|---|---|---|
| `pipeline/scripts/stage_a_scrape_radish.py` | `9eef3f3~1` | Stage A image sourcer — probed `radishpriceguide.com/boba/{year}/{slug}/{hero}/{cardNumber}`, pulled Cloudinary URLs, uploaded to R2 staging |
| `scripts/build_radish_url_map.py` | `9eef3f3~1` | Pulled Radish's `sitemap.xml`, built `assets/data/radish-url-map.json` mapping every `bobaId`-tuple to a canonical Radish URL |
| `scripts/apply_radish_urls.py` | `9eef3f3~1` | Took the URL map and stamped `radishUrl` field into every catalog JSON bundle |
| `scripts/probe_radish_urls.py` | `9eef3f3~1` | HEAD-probed existing radishUrls + flagged 404s for re-derivation |
| `assets/data/radish-url-map.json` | `9eef3f3~1` | The 2.5 MB sitemap-derived URL map (one entry per 5-segment Radish URL) |
| `.github/workflows/pipeline-stage-a-scrape-radish.yml` | `a18ca31~1` | Daily 03:30 UTC cron that ran the scraper against the missing-art queue |
| `.github/workflows/radish-url-refresh.yml` | `a18ca31~1` | Weekly Mon 13:00 UTC cron that re-pulled sitemap + applied URLs + opened a PR |

**Restoration steps:**

1. `git show 9eef3f3~1:<path>` for each script. The scripts depend on:
   - Python 3.11+ with `boto3`, `requests`, `dotenv`, `supabase`
   - The pipeline Supabase tables (`pipeline_image_candidates`,
     `pipeline_card_images`) — schema unchanged since `0006_pipeline_discord_source.sql`
   - R2 secrets (`R2_ACCOUNT_ID` / `R2_ACCESS_KEY` / `R2_SECRET_KEY`)
     — already in `.env` for the BV scraper
2. Restore `assets/data/radish-url-map.json` via a fresh
   `python3 scripts/build_radish_url_map.py` run (NOT from git —
   the data will be stale).
3. Reinstate the cron workflows. Re-add `'radish'` to the schedule-
   ordering comments in `pipeline-stage-a-scrape-bv.yml` and
   `pipeline-stage-b-recognize.yml` if you want documentation parity.
4. **Database constraint:** the `pipeline_image_candidates.source`
   CHECK currently excludes `'radish'` (removed via
   `pipeline/migrations/0007_pipeline_drop_radish_source.sql`). Add
   it back via:
   ```sql
   alter table public.pipeline_image_candidates
     drop constraint if exists pipeline_image_candidates_source_check;
   alter table public.pipeline_image_candidates
     add constraint pipeline_image_candidates_source_check
       check (source = ANY (ARRAY['ebay'::text, 'radish'::text, 'bazookavault'::text, 'dbs'::text, 'whatnot'::text, 'manual'::text, 'research_queue'::text, 'discord'::text]));
   ```
5. **Catalog image flip-back (optional):** of the 4,590 cards that
   were re-sourced RADISH→BV in Phase 17, you can run the BV→RADISH
   inverse if the partnership prefers Radish's image-quality.
   `scripts/backfill_radish_to_bv.py` is reversible by swapping
   `--from-source BV --new-source RADISH` and pointing at a fresh
   `radish_backfill_queue.json` regenerated against the current
   catalog. Skip this if both R2 byte sets are equivalent (they
   typically are — both pull from the same upstream art).

---

## 7 — Documentation: language to put back

**What was rewritten.** Every "Powered by Radish" / "official pricing
partner" / waterfall-mentioning Radish passage was rewritten as
eBay-only.

| File | Pre-removal SHA | What changed |
|---|---|---|
| `DECISIONS.md` #013 | `54e7dfb~1` | Read "eBay Browse API + Radish Price Guide in parallel"; now reads "eBay Browse + Marketplace Insights APIs" |
| `DECISIONS.md` #034 | `54e7dfb~1` | Read "Radish sales → eBay sold → Market Est."; now reads "eBay sold → Market Est." |
| `DESIGN.md` §8.7 | `9eef3f3~1` | "Radish recent (preferred TCG comps) + eBay sold. Market est = Radish-first waterfall." → now eBay-only |
| `ANDROID-DESIGN.md` §8.7 | `9eef3f3~1` | Same rewrite |
| `PARITY.md` "Radish recent sales" row | `9eef3f3~1` | ✅✅✅ → 🚫🚫🚫 |
| `README.md` "BOBA Ecosystem" bullet | `9eef3f3~1` | Listed Radish as a sibling tool; removed |
| `PITCH.md` line 16 | `9eef3f3~1` | "plus Radish price-guide links" → "live recent-sales comps" |
| `PLAYTEST.md` "Pricing." | `9eef3f3~1` | "Radish price-guide link" → "View on Radish" external link |
| `CLAUDE.md` Worker description | `9eef3f3~1` | "eBay Browse API + Radish pricing proxy" → "eBay Browse + Marketplace Insights API proxy" |
| `terms/index.html` third-party list | `9eef3f3~1` | Restructured — kept Radish as "ordinary user-facing link only" disclaimer; remove that disclaimer if integration is back |
| `LearnView.swift` glossary entry for "comps" | `54e7dfb~1` | "pulls comps from Radish + eBay" → "pulls comps from eBay's Marketplace Insights API" |
| `LearnContent.kt` glossary | `54e7dfb~1` | Same rewrite |
| `index.html` glossary | `54e7dfb~1` | Same rewrite |

**Restoration steps:**

1. `git show <SHA>~1:<path>` for each doc; copy the relevant paragraph back.
2. Add a new entry to `DECISIONS.md` documenting the re-authorization
   + reference DECISIONS.md #056 as the reverted decision.
3. Update `RADISH_REMOVAL_LOOP.md`'s end-state summary to note the
   reversal date + the new authorization terms.
4. Drop the Radish-specific compliance language from
   `terms/index.html` (or revise to whatever the partnership terms
   specify).

---

## 8 — Catalog data field: `card.radishUrl`

**What's preserved (Option B).** The `radishUrl` field is STILL in
every catalog bundle (master `cards.json` + 7 downstream JSONs). It
was acquired pre-email from Radish's sitemap and is now treated as
frozen static data. **No restoration needed for this field** — it's
already there.

If integration is restored, you'll want to refresh it:

1. Run `scripts/build_radish_url_map.py` (after restoring it per §6).
2. Run `scripts/apply_radish_urls.py` (after restoring it per §6).
3. Both should re-derive the full URL map from Radish's current
   sitemap and re-stamp every catalog entry.

---

## 9 — Cosmetic: "View on Radish" button label

The buttons currently say "View on Radish" with an `arrow.up.right.square`
SF Symbol (iOS) or `OpenInBrowser` Material icon (Android). To
restore the historical "Radish Guide" branding (with chart-line
icon):

| Platform | Old label + icon | Old behavior |
|---|---|---|
| iOS | `"Radish Guide"` + `chart.line.uptrend.xyaxis` SF Symbol | Opened in-app via `SafariView` sheet |
| Web | `"Radish"` (pricing panel) / `"Radish Guide"` (sealed CTA) | New tab via `target="_blank"` |
| Android | (no historical equivalent — Android wasn't shipped with the button pre-removal) | n/a |

**Restoration steps for branding:**

1. Rename the button text in the 3 iOS view files + `js/app.js`
   (anchor inner text + sealed-product CTA inner text) + Android
   `CardDetailScreen.kt`'s TextButton text.
2. Swap the icon constants. iOS: `Image(systemName: "chart.line.uptrend.xyaxis")`.
   Android: pick a Material icon (e.g. `Icons.Default.TrendingUp`).
3. iOS: if the partnership re-authorizes in-app rendering, swap
   `Link(destination: ...)` back to `Button { showRadish = true }`
   plus the `.sheet(isPresented: $showRadish) { SafariView(url: ...) }`.
4. Android: similarly swap `Intent.ACTION_VIEW` for
   `CustomTabsIntent.Builder().build().launchUrl(context, ...)`
   if in-app Custom Tab rendering is back on the table.

---

## 10 — One-time restoration audit checklist

After restoring the pieces above, run this checklist before deploying:

- [ ] All three Workers redeployed via `wrangler deploy`
      (boba-ebay-proxy, boba-youtube-feed if priority pin is back,
      boba-price-estimator if the Radish Market Est. tier supersedes
      our comparability function)
- [ ] Cache bump on `boba-ebay-proxy` (e.g. `v18` → `v19`) so old
      Radish-free responses don't leak through
- [ ] `wrangler tail` while triggering a card-detail open — confirm
      `[sold_match]` logs reach the Radish path
- [ ] iOS, web, Android all show the Radish source pill on sold tiles
      (where applicable) and the "Radish Guide" button on every card
      detail
- [ ] `assets/data/radish_backfill_queue.json` regenerated (post the
      RADISH→BV image flip-back, if you chose to do it)
- [ ] `RADISH_REMOVAL_LOOP.md` end-state-summary updated to note
      reversal date + new authorization terms
- [ ] New `DECISIONS.md` entry documenting the re-authorization
- [ ] `terms/index.html` third-party-services list re-revised
- [ ] PARITY.md row flipped back to ✅✅✅
- [ ] `README.md` ecosystem credit restored (if partnership specifies)
- [ ] Re-run `RADISH_REMOVAL_LOOP.md`'s "End-state summary" check in
      reverse — every removed surface is now confirmed restored

---

## What does NOT need to come back

Even if Radish re-authorizes, some Phase 19+ infrastructure built
during the removal is independently valuable and should STAY:

- **`workers/price-estimator/`** — our own comparability function over
  the BOBA catalog is useful as a Tier 3 fallback even when Radish
  Market Est. is back. If Radish's Market Est. is preferred, gate
  the estimator behind a `if no radish estimate` check.
- **`workers/pricing-snapshot/`** — the persistence layer
  (`card_prices_history` table) speeds up card-detail opens and
  unlocks the value-history chart. Independent of Radish.
- **Tuned `normaliseSoldEnriched` weights** in `boba-ebay-proxy` —
  the bumped hero (0.20→0.25) and treatment (0.05→0.15) weights and
  lowered confidence threshold (0.70→0.60) are defensible
  improvements regardless of whether Radish is back as a fallback.
- **`scripts/backfill_radish_to_bv.py`** — the engine is generic
  (handles arbitrary source-tag transitions via `--from-source`
  / `--new-source`). Keep for future backfill work.
- **`scripts/identify_radish_sourced_cards.py`** — same: it accepts
  any `--source` value, not just RADISH. Useful tooling.

---

## References

- `RADISH_REMOVAL_LOOP.md` — full removal session log (22+ ticks)
- `DECISIONS.md` #056 — architectural decision documenting the removal
- `RADISH_PARTNERSHIP_CALL.md` — the pre-removal partnership-pitch
  + walk-away analysis. Contains a detailed inventory of every
  Radish integration that existed at the time of the call.
- Email from Scot + Rob (2026-05-23) — the trigger for the removal.
  Stored in Ben's records; not committed to the repo.
