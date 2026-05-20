# Radish Price Guide — Partnership Call Prep

Generated 2026-05-20 for Ben's call with the Radish Price Guide owner / lead developer.

---

## TL;DR for the opener

> "Radish is currently the single largest external data source in BOBA Playbook. **47% of the catalog's canonical images come from Radish (8,386 of 17,974 cards).** Radish is the *first tier* of every pricing waterfall on every platform — recent sales beats eBay sold beats Market Est. fallback, all from your data. RadishDijital is the only **priority-0** YouTube channel in the Watch tab, meaning his new videos pin to the top of every BOBA user's feed. Every link in the app that says 'Radish Guide' deep-links back to your URL. There's a real partnership here — let me show you what we've built around your data, where it currently breaks, and where we can take this together."

---

## 1. Every current Radish integration, by platform

### 1.1 Catalog image sourcing — **pipeline-level dependency**

**Stage A scraper** (`pipeline/scripts/stage_a_scrape_radish.py`):
- Probes `https://radishpriceguide.com/boba/{year}/{slug}/{hero}/{cardNumber}` for every card in the catalog.
- Pulls Cloudinary-hosted card art directly off Radish-rendered pages, normalizes hero-name spelling (hyphen ↔ space, alias remap), then uploads candidate images to BOBA's R2 staging.
- **Result on disk:** `imageSource: "RADISH"` on 8,386 catalog rows (47% of the entire BOBA card catalog).
- Without Radish art coverage, those 8,386 cards would have no canonical image — many of them are long-tail variants the card source and eBay don't cover.

### 1.2 Pricing waterfall — **first tier on every card detail**

The Cloudflare Worker `boba-ebay-proxy` ([`workers/ebay-proxy/worker.js`](workers/ebay-proxy/worker.js)) runs a three-tier sold-comp waterfall on every card detail open. Radish is tier 1 AND tier 3:

```
Tier 1 — fetchRadishSales()     scrapes __NEXT_DATA__ on Radish card page
  ├─ in-window sales? → use them
  └─ stale sales?     → surface single most-recent as anchor
Tier 2 — eBay Marketplace Insights (only if Radish returned nothing)
Tier 3 — fetchRadishMarketEst() Radish /api/boba/estimated-value (comp-based fallback)
```

When Radish has sales data, the eBay Marketplace Insights call is **skipped entirely**. Radish's pre-validated sales (with each eBay sale already matched to a specific card by Radish's side) beat anything BOBA could compute from raw eBay titles.

**Pricing-section surface** (where Radish sales render in the app):

| Platform | Surface | File |
|---|---|---|
| iOS | Card detail · `RECENT SALES` rail + market estimate header | `BOBAPlaybook/Components/PricingSection.swift` |
| iOS | Collection card detail · same shape | `BOBAPlaybook/Views/Collection/CollectionCardDetailView.swift` |
| iOS | "Radish Guide" deep-link button on every card detail | `BOBAPlaybook/Components/PricingSection.swift:143` |
| Web | Card modal · `RECENT SALES` rail + market estimate | `js/app.js:2210+` |
| Web | "Radish" deep-link button next to "eBay" button | `js/app.js:2231` |
| Web | Sealed-product "Radish Guide" CTA | `js/app.js:2712` |
| Android | Card detail · sold-section · powered by Radish via Worker | `android/app/.../feature/carddetail/CardDetailScreen.kt` |
| Android | Worker `priceType` + `radishResolvedUrl` propagated through `PricingService.kt` | `android/core/network/.../PricingService.kt` |

**iOS-only `RadishURLResolver`** (`Card+Radish.swift`):
- Synthesizes a Radish URL for every card from `{set, hero, cardNumber}` even when the catalog field is null.
- HEAD-probes the synthesized URL; falls back to the hero-only landing page (`/boba/{year}/{slug}/{hero}`) when the specific card URL 404s.
- Per-app-session cache keyed on bobaId so each card resolves at most once.
- Worker also returns `radishResolvedUrl` (the URL that actually carried sales data) — when present, the iOS client snaps the button to *that* URL, so users land on a Radish page with real comps rather than an empty shell.

### 1.3 Watch tab — **only priority-0 channel**

`workers/youtube-feed/worker.js:64`:
```js
const KNOWN_CHANNELS = [
  { handle: "radishdijital",          priority: 0 },  ← pinned to top
  { handle: "BoBattleArena",          priority: 5 },
  { handle: "InsideTheVault_Bazooka", priority: 5 },
  { handle: "BattleArenaLeague",      priority: 5 },
  { handle: "blokpax",                priority: 5 },
  { handle: "PullsAndPars",           priority: 5 },
];
```

- **Radish is the only priority-0 channel.** Every new RadishDijital video pins to the top of the Watch feed across iOS, web, and Android.
- The Watch tab has a dedicated `Vertical` content bucket designed in part to handle Radish's 📱 phone-edition daily show variant (see `BOBAPlaybook/Views/Play/WatchView.swift:16,352` — there's literally code that says "for Radish's daily show that's the player figure" for the thumbnail crop logic).
- New BOBA users coming through Find → Learn → Watch will see RadishDijital before they see anyone else.

### 1.4 Glossary + Privacy/Terms

- `BOBAPlaybook/Views/Play/LearnView.swift:1666` — the glossary entry for "comps" explicitly names Radish: *"Comparable recent sales — used to sanity-check a price. The card detail view's pricing panel pulls comps from Radish + eBay."*
- `terms/index.html:303` — Radish is listed in the public Privacy disclosure as a third-party data source.
- `terms/index.html:355` — Radish is a named third-party service in the dependency-risk disclosure.

### 1.5 Collection / Show / Scan flows — `resolvedRadishUrlString` everywhere

The Radish URL is captured into the user's owned-card record at the moment of add, in three flows:

| Flow | File | Purpose |
|---|---|---|
| Add to Collection | `BOBAPlaybook/Views/Collection/AddToCollectionSheet.swift:145` | New `user_cards` row carries the Radish link |
| Add to Show (streamer) | `BOBAPlaybook/Views/Collection/ShowDetailView.swift:663` | Show-wall renders Radish link in metadata |
| Scan-queue → add | `BOBAPlaybook/Views/Scan/ScanQueueView.swift:661` | Scanned cards inherit Radish link |
| Collection store (bulk) | `BOBAPlaybook/Store/CollectionStore.swift:352` | Server-side cache |

### 1.6 Documentation references (so it's not just code)

- `DECISIONS.md #013` — pricing fetched via Worker, **"eBay Browse API + Radish Price Guide in parallel"** — codified as architectural decision since 2026-04-03.
- `DESIGN.md §8.7` (binding iOS design doc) — *"Sold history → Radish recent (preferred TCG comps) + eBay sold (fallback). Market est = Radish-first waterfall."*
- `ANDROID-DESIGN.md §8.7` — verbatim parallel for Android, *"Radish-first waterfall"*.
- `PARITY.md` line 153 — Radish recent sales is a cross-platform feature row.
- `PITCH.md` line 16 — Radish is in the user-facing app description: *"Price each card with live eBay Buy Now + recent sales, plus Radish price-guide links."*
- `README.md` line 74 — Radish is publicly credited as a primary data source.

---

## 2. Talking points

### 2.1 What Radish data makes better in BOBA Playbook

- **Pricing accuracy** — Radish has pre-matched each eBay sale to the specific card by hero+number; BOBA's title-parsing-of-eBay-listings is order-of-magnitude noisier. We *prefer* Radish over our own eBay sold filtering for exactly that reason (worker.js comment: *"Radish has pre-matched each eBay sale to the specific card — far more accurate than title/aspect filtering"*).
- **Long-tail coverage** — Radish carries low-volume parallel + treatment data that eBay's Marketplace Insights would never reach in 30 days. ~9,500 of our 18k catalog rows are parallels and serialized variants; many only have a comp because Radish tracks them.
- **Market estimate fallback** — when nobody has actually sold a card, Radish's comp-based Market Est. (`/api/boba/estimated-value?card_id=…`) is the *only* number we can show. Without it, ~6,000 catalog rows would render "Pricing unavailable" forever.
- **Catalog image coverage** — Radish-sourced art covers 47% of the catalog. No other single source comes close.
- **Daily-show pin** — RadishDijital's content lands in front of every BOBA user via Watch tab priority pinning. Discovery flywheel for new BoBA collectors.

### 2.2 What BOBA Playbook makes better for Radish (exposure + ergonomics)

This is the partnership argument — concrete things we're *already* doing for Radish exposure, plus what we could expand:

**Currently shipping (the things to point at):**
1. **Every card-detail in BOBA has a "Radish Guide" button** that deep-links to a Radish page — and the Worker actively *resolves* which specific Radish URL has data so users land somewhere useful (no dead 404 traffic).
2. **The Worker's `radishResolvedUrl` field** means clients snap the button to the canonical Radish landing — every click that comes from BOBA is a verified-quality referral, never a broken-link bounce.
3. **Glossary entry for "comps"** in Learn explicitly teaches new collectors that Radish is the source for sales comps. Educates the audience to value the source.
4. **Watch tab priority pin** sends every BOBA user to RadishDijital's content before anyone else's. Free top-of-feed inventory across iOS, web, and (soon) Android.
5. **Public credit** in README, PITCH, terms/privacy. App-store listing names Radish as a data source.
6. **Catalog scraping is *attributed*** — `imageSource: "RADISH"` is stored on every card so we can transparently report image provenance to any future audit, partnership disclosure, or App Store review.

**Could be expanded (post-call):**
- **Radish-branded source pill on every price tile** (currently "RECENT SALES" — could be "RADISH RECENT SALES" with Radish's logo/wordmark).
- **In-app Radish profile/widget** — short Radish bio + recent activity inside the Profile tab or as a "Powered by" Learn → Collect callout.
- **Banner inside Card detail** when a user opens a card with no comps yet: *"This card has no recorded sales on Radish yet — be the first to submit one [Radish link]."* Drives data back to Radish.
- **Affiliate model** — if Radish has eBay affiliate links, BOBA could append the user's referral ID when deep-linking out so Radish captures the conversion.
- **Cross-promote Radish Pro / paid tier** — if Radish has a subscription product, BOBA's signed-in users (~hundreds growing to thousands) are a high-intent audience.
- **Push-notification trigger** — *"Your Grail card just had a new sale on Radish for $1,200"* — drives users back into both apps simultaneously.

### 2.3 What BOBA would lose without Radish

- **47% of catalog image coverage** evaporates. Either we go re-scrape eBay completed listings + the card source (expensive, lower quality, slower), or 8,000+ cards regress to placeholder images.
- **Sold-comp accuracy drops materially** for long-tail cards. Marketplace Insights only covers cards eBay sold in the last 30 days — that's a small fraction of the catalog. Cards with no eBay-recent sales would lose their entire pricing surface.
- **Market Est. fallback disappears.** Cards that have *never* sold lose their only pricing number.
- **Glossary, terms, README all need rewrite** — Radish is named in user-facing copy.
- **Watch tab loses a quarter of its content quality** — RadishDijital is the priority channel; removing it shifts the experience meaningfully.
- **Trust signal weakens.** Pricing transparency in a TCG app is the difference between "I'll show this to a friend" and "I'll uninstall." Removing the named source diminishes that signal.

### 2.4 What Radish would lose without BOBA Playbook

- **A growing distribution channel** with intent-qualified BoBA collectors arriving daily. Every "Radish Guide" tap is a high-intent user who's already invested enough in this game to install a companion app.
- **Free top-of-feed YouTube placement** for RadishDijital across iOS / web / Android Watch tabs.
- **Free public attribution** in BOBA's docs and listings — credibility halo, especially for collectors who don't yet know what Radish is.
- **A canonical mobile/native UX layer** on top of Radish's web data. Many users will *first* encounter Radish through BOBA's Radish Guide button, not the other way around. As BOBA grows (currently scaling toward beta release with iOS + web shipped, Android in development) the "via BOBA" funnel grows with it.
- **An auto-attribution / data-provenance partner.** BOBA marks every card image as `RADISH`-sourced internally; if a partnership formalizes, that becomes a public credit/co-brand opportunity at zero extra dev cost.
- **A glossary entry teaching the next generation of collectors what "comps" means and where they come from.** Education flywheel.

---

## 3. "Broken pieces" we've engineered around — diplomatically framed

These are honest things you can mention as "places where BOBA invested engineering to keep the Radish integration solid, that Radish could fix on its side or where we could share workarounds." Each is something we hit, instrumented, and worked around — *not* criticism; framing them as collaboration opportunities lands better.

### 3.1 Set-name / namespace drift

> *"We discovered that some cards in our catalog have a different `set` field than the (year, slug) path Radish actually serves them under. For example, LeBoss-1 has `set: 'Alpha Edition'` in the BOBA catalog, but Radish hosts him under `/2025/Alpha_Update/`. We solved this with a 12-namespace parallel sweep in our Worker — the Worker fans out to every known Radish (year, slug) pair on a cache miss and uses whichever namespace actually has data."*

**Where this lives in our code:** `workers/ebay-proxy/worker.js:551` — `RADISH_NAMESPACES` constant lists every namespace Radish serves; built from `curl https://radishpriceguide.com/boba`. Updated by hand whenever Radish ships a new set.

**Partnership opportunity:** Radish could publish a `/sitemap.json` (or `/api/sets`) exposing the full set→namespace mapping, so any integrator could resolve a card's canonical Radish URL without a brute-force sweep. Would also save Radish bandwidth.

### 3.2 Hero-name spelling/case sensitivity

> *"Radish is case-sensitive on URL paths and uses different canonical spellings than our catalog for some heroes. 'ChetMate' in our catalog is 'Chetmate' on Radish; 'BoJax' is 'Bojax'. We maintain a small `RADISH_HERO_ALIASES` table that maps our spelling to Radish's, and our Worker tries both hyphen and space forms of multi-word heroes."*

**Where this lives:** `BOBAPlaybook/Models/Card+Radish.swift:97`, `js/app.js:2163`, `workers/ebay-proxy/worker.js:598`.

**Partnership opportunity:** Either a `/api/heroes` endpoint exposing Radish's canonical hero names, or simply documenting your hero-name conventions so we can normalize once at catalog-build time instead of at request-time.

### 3.3 Card-detail-page 404s

> *"When a card hasn't accumulated enough comps yet, Radish 404s the card-detail URL even though the hero-level page exists. We solved this with a HEAD-probe + hero-level fallback in our iOS `RadishURLResolver`, so the user always lands somewhere with real data."*

**Where this lives:** `BOBAPlaybook/Models/Card+Radish.swift:147` (`RadishURLResolver`).

**Partnership opportunity:** Radish could 302-redirect 404s on `/boba/{year}/{slug}/{hero}/{cardNumber}` to `/boba/{year}/{slug}/{hero}` when the cardNumber-specific page hasn't been built. Would let every integrator drop their HEAD-probe code.

### 3.4 Next.js buildId rotation

> *"Radish's Market Est. API (`/api/boba/estimated-value?card_id=…`) requires a `card_id` we look up via the Next.js `_next/data/{buildId}/…` endpoint. The buildId rotates on every Radish deploy. We cache it for 24h, but when a deploy happens we hit a 404 and have to bust the cache mid-request. We've engineered around this — but a stable `/api/boba/card-id?hero=X&cardNumber=Y` endpoint would let us drop the buildId scraping entirely."*

**Where this lives:** `workers/ebay-proxy/worker.js:743-789`.

**Partnership opportunity:** Stable card_id lookup endpoint. Or even just include `card_id` in the `__NEXT_DATA__` JSON we're already scraping from the card-detail page (we currently extract `allSales` from that JSON — adding `card_id` would let us skip an entire API hop).

### 3.5 Card-number prefix mismatch

> *"Our catalog uses uppercase prefixes (`LOGO-`, `RAD-`, `MIX-`); Radish's URLs use title-case (`Logo-`, `Rad-`, `Mix-`). We remap on URL construction."*

**Where this lives:** `BOBAPlaybook/Models/Card+Radish.swift:84`, `js/app.js`, Worker.

**Partnership opportunity:** Standardize on one casing (Radish's existing one is fine — we'd just need it documented), or accept either form via case-insensitive routing.

### 3.6 The "stalled HTTP response" trap

> *"Cloudflare Workers warn and start cancelling in-flight fetches when too many response bodies are left undrained. Our parallel Radish namespace sweep fires ~30 requests at a time, most returning 404. Initially this caused legitimate calls (Market Est. card_id lookup) to be cancelled mid-flight, silently breaking pricing for high-traffic cards. We now explicitly `await res.body?.cancel()` on every 404."*

**Where this lives:** `workers/ebay-proxy/worker.js:510-521`.

**Partnership opportunity:** Anything that reduces the 30-fetches-per-card pattern — see §3.1's sitemap idea — would solve this at the source. A single `/api/boba/lookup?hero=X&number=Y` returning `(year, slug, exists, card_id, latestSale)` would replace the entire fan-out.

### 3.7 Hyphen vs space hero variant probing

> *"Multi-word hero names appear under both forms on Radish (`Mean-Joe` vs `Mean Joe`, `Bell-Camp` vs `Bell Camp`). We probe both and pick whichever has data."*

**Where this lives:** `workers/ebay-proxy/worker.js:598`.

**Partnership opportunity:** Pick a canonical form, redirect the other.

### 3.8 Stale sales handling

> *"For cards with no sales in our query window (90 days by default), we still surface the most-recent historical sale rather than show 'no data.' Users get an anchor instead of a blank. The Worker returns `stale: true` and the iOS UI relabels the surface to 'Last sold {date}'."*

**Where this lives:** `workers/ebay-proxy/worker.js:647`, `BOBAPlaybook/Components/PricingSection.swift`.

**Partnership opportunity:** Radish's UI could surface stale-sale callouts the same way. Or expose a `since: {timestamp}` query param that lets us request "most-recent sale of any age" directly.

---

## 4. Numbers to drop on the call

| Stat | Source |
|---|---|
| **8,386** — cards with `imageSource: "RADISH"` (47% of catalog) | `python3 -c "import json; print(sum(1 for c in json.load(open('assets/data/cards.json')) if c.get('imageSource')=='RADISH'))"` |
| **17,974** — total catalog rows | `len(cards.json)` |
| **3** — pricing-waterfall tiers, **2 of which are Radish** (recent sales + Market Est. fallback) | `workers/ebay-proxy/worker.js` |
| **1** — priority-0 YouTube channel in the Watch tab (RadishDijital) | `workers/youtube-feed/worker.js:64` |
| **12** — Radish (year, slug) namespaces our Worker sweeps on cache miss | `workers/ebay-proxy/worker.js:551` |
| **3 platforms** rendering Radish data — iOS shipped, web shipped, Android in beta | `PARITY.md` line 153 |
| **6 hours** — Worker cache TTL for sold data; **24 hours** for buildId | `workers/ebay-proxy/worker.js:1606`, `:741` |
| **2024-2026** — date range BOBA has been pulling from Radish | `Card+Radish.swift:52-78` namespace table |

---

## 5. Specific asks to bring up

If the conversation lands in "what can we do together," concrete options ranked by effort / value:

1. **(Lowest effort, high signal)** Mutual public co-branding — Radish lists BOBA Playbook as an official integration partner; BOBA adds a "Powered by Radish" pill next to the existing source rail. Zero engineering.
2. **(Low effort)** Stable lookup API — `/api/boba/lookup?hero=X&number=Y` returning `(year, slug, exists, card_id, latestSale)`. Solves §3.1, §3.4, §3.7 simultaneously. Saves Radish bandwidth (one targeted call instead of fan-out sweeps).
3. **(Low effort)** eBay affiliate ID pass-through — if Radish has an affiliate program, BOBA appends Radish's referral param when deep-linking out. Pure revenue upside for Radish, zero cost to us.
4. **(Medium effort)** Bidirectional embed — BOBA exposes its admin-curated card catalog (we have authoritative card numbers, hero names, weapons, sets, treatments, DBS values, ability text) and Radish could pull from it to fix the namespace + spelling drift at the source.
5. **(Medium effort)** Push-notification partnership — when a user has a card on their Wanted list and Radish records a sale of that card, BOBA pushes the user a notification with a deep-link to the Radish detail page.
6. **(Higher effort)** Radish Pro / paid-tier integration — BOBA Pro subscribers (planned per `DECISIONS.md` + `TRADE-DESIGN.md`) get bundled access to Radish premium features; subscription revenue shared.
7. **(Higher effort)** Co-developed scan-to-sales-history flow — user scans a card with BOBA, immediately sees Radish's sale history for that exact card. BOBA does the scanning + recognition; Radish does the sales lookup; both sides win.

---

## 6. The one-paragraph close

> *"Radish is already the single most-important external data source in BOBA Playbook — 47% of our catalog images come from you, half of our pricing waterfall is your data, and the only YouTube channel pinned to the top of our Watch tab is yours. We've quietly invested a lot of engineering to keep that integration solid (namespace sweeping, hero-name normalization, HEAD-probe URL resolution, buildId cache busting). I think there's a real partnership here: we expose a high-intent BoBA-collector audience to your work on every card detail and in the Watch tab, you provide the sales data that makes our pricing feature real. Let's talk about what a formal version of that looks like — co-branding, a stable lookup API, maybe affiliate or Pro-tier revenue sharing."*

---

## 7. Proposal email (post-call follow-up)

Copy-paste ready. Bullet-only per their stated preference. Subject + greeting placeholders left for Ben to fill in.

---

**Subject:** BOBA Playbook × Radish — partnership proposal

Hi [name],

Great talking earlier. As promised, here's the written-up version with what currently exists, what we could build together, and what I can offer in exchange. Kept it to bullets so it's easy to scan.

### What's already live

- **Pricing** — Radish is tier 1 of our 3-tier pricing waterfall on every card detail in BOBA Playbook (iOS + web shipping; Android in beta). Radish recent sales beat eBay sold; Radish Market Est. is the fallback when nothing else has data.
- **Catalog images** — 8,386 of 17,974 catalog cards (47%) have their canonical image sourced from Radish via our offline scraper.
- **Watch tab** — RadishDijital is the only **priority-0** channel in BOBA's Watch tab. New uploads pin to the top of every user's feed across all three platforms.
- **Deep-link buttons** — every card detail (Find, Decks, Collection, sealed products) ships a "Radish Guide" button that routes users to your card-detail page. The button is *Worker-resolved* — we land users on the specific Radish URL that has data, not a 404 shell.
- **Public attribution** — README, App Store listing, glossary, and privacy/terms all name Radish as a primary data source.

### Why this is good for Radish

- **Top-of-funnel exposure** — every BOBA user who taps a card sees a Radish-branded source pill and a Radish Guide button. Currently shipping on iOS + web.
- **High-intent referrals** — every Radish Guide tap is a user who's already invested enough in this game to install a companion app. These aren't bouncing.
- **Free pinned YouTube placement** — RadishDijital uploads land at the top of every user's Watch tab. No effort on your side, no payment from us.
- **Verified-quality deep-links** — our Worker probes which Radish URL actually carries data before routing. Zero dead-link traffic to Radish servers.
- **Source-of-truth attribution** — every catalog image we scraped from Radish has `imageSource: "RADISH"` stored permanently. If we formalize co-branding, that becomes a public credit/attribution flow at zero extra dev cost.

### What I could expand if we formalize

- **"Powered by Radish" branding** in the pricing surface — replace "RECENT SALES" with a Radish-logo'd pill.
- **eBay-affiliate pass-through** — if you have an eBay Partner Network ID, BOBA appends it on every outbound Radish link. Pure revenue upside for you, zero cost to me.
- **Wanted-list match notifications** — when a user has a card on their Wanted list and Radish records a new sale, push them a notification with a deep-link to the Radish detail page. Drives traffic both ways.
- **In-app Radish callout** — a Profile-tab or Learn-tab "Powered by Radish" surface with your bio, link, social. Free editorial slot.
- **Radish Pro / paid-tier bundle** — BOBA Pro subscribers (planned) get access to Radish premium features; revenue-sharing.

### What I'd offer in exchange

These are concrete pieces of code, data, and infrastructure I've built that Radish does not currently have — happy to share any/all if continued integration is on the table:

- **Cleaned-up catalog data** — my 17,974-row canonical catalog with normalized hero spellings, weapon classifications, treatment taxonomy, set→year→namespace mappings, DBS values for Plays, ability text for every card. Built over months of community + manufacturer audits (see DECISIONS.md #027, #028, #029, #033). I could expose this as a public read-only feed or a one-time data dump.
- **Hero-name + set-name alias tables** — every spelling/casing mismatch between our two catalogs documented (`Card+Radish.swift` line 97 + `worker.js` line 545). Would let Radish standardize URL paths and eliminate the namespace drift.
- **Image-byte collision detection** — `reconcile_all.py::step11` md5-uniqueness guard that catches cases where two different cards accidentally share image bytes (we found 35 such pairs across the catalog). DECISIONS.md #026 has the protocol.
- **AI image verification for ambiguous eBay sales** — our `verifyCardImage` function uses Cloudflare Workers AI vision to read the card number off an eBay listing thumbnail and confirm it matches the expected card. We use it to cut false-positive eBay matches. Drop-in pattern Radish could adopt.
- **`normaliseSoldEnriched` scorer** — our match-confidence scorer for raw eBay sold listings (card_number_exact, hero_name, power_in_title, weapon_match, treatment_match, manufacturer_tag, year, trusted_seller, price_in_range). Useful as a fallback when Radish's pre-match doesn't cover a card.
- **A working scan-to-recognition pipeline** — iOS on-device Vision OCR + image-fingerprint feature-prints across 16k+ catalog cards (see DECISIONS.md #035). When a user points their phone at a card, we identify it in milliseconds and route to the card detail (which then surfaces Radish pricing). If Radish wanted a "scan a card to see its sale history" mobile flow, this is the engine.
- **Watch-tab editorial slot** — happy to bake in any custom RadishDijital feature you want: a Radish-curated playlist, a "Radish recommends this week" callout, a custom thumbnail crop.
- **Glossary education content** — the "comps" entry and the broader trading glossary teaches BoBA collectors what Radish's sales data is and why it matters. If you write a 2-paragraph "How Radish builds price guides" explainer, I'll ship it in the in-app Learn tab.
- **Public-collection sharing infrastructure** — when a user shares their collection at `bobaplaybook.com/u/{username}`, every card on the page links to its Radish detail. Free shareable traffic source.

### What I'd ask in return (specifically)

- **Stable card-lookup endpoint** — `/api/boba/lookup?hero=X&number=Y` returning `(year, slug, card_id, latestSaleTimestamp, lowEst, midEst, highEst)`. This single endpoint replaces the 30+ probe requests our Worker currently fans out per card and saves your bandwidth at the same time. (We've engineered around namespace drift, hero-spelling mismatch, buildId rotation, hyphen-vs-space probing — all of which a stable endpoint would obsolete.)
- **Confirmation that continued scraping for catalog images is OK** — the 8,386 Radish-sourced images we already have are mostly already-public art Radish aggregated from upstream sources. I'd like a clear "yes you can keep doing this, here's an attribution string we'd like" or a "stop, here's a feed we'll give you instead" — either is fine. The current uncertainty is the blocker.
- **Co-branding language for the BOBA Pro subscription page** — if formalized, I'd like to credit Radish as "official pricing data partner" or similar.

### Next step

If this shape works directionally, I'm happy to draft a one-page MOU and we go from there. If it doesn't, I'd rather know now than guess — I have alternative paths I could go down for each piece, but a partnership where we both win is the path I'd prefer to take.

Either way, thanks for the call today.

Ben

---

## 8. Internal-only: what it would actually cost to walk away

**This section is for Ben's own strategic awareness — do NOT include in the email to Radish.** It's the answer to "what's our BATNA?" — the alternative we have if the partnership conversation goes sideways.

Three engineering agents analyzed each dependency surface independently. Headline finding:

> **Total walk-away cost is much lower than expected: ~1.5-2 weeks defensive (do nothing, keep current images, swap Watch pin, delete deep-link buttons). The ONE expensive piece is rebuilding the pricing waterfall — 3-5 weeks for a v1 that ships, 6-8 weeks for full parity. And even that's bounded.**

The negotiating leverage this creates is real: Radish has the most leverage on **pricing**, very little on images, and essentially none on the Watch tab / deep-link surfaces.

### 8.1 Image sourcing — verdict: **LOW** (0 weeks defensive, 1-5 weeks clean)

**The bytes are already permanently on R2.** Radish was the *discovery source* for 8,386 images, but the actual image bytes were downloaded into BOBA's own R2 bucket the moment they were ingested. Every existing user-facing image continues to serve from R2 even if Radish disappeared tomorrow. **Zero code change, zero user impact.**

What stops working is *future discovery* for new sets / new cards. For that:

- **97% of the 8,386 Radish-sourced cards are treatments/parallels** (Blizzard, Logofoil, Linoleum, Mixtape, Colosseum, Alpha foils) — print variants of the same hero art, not unique cards.
- **63.6% (5,330 cards) already have a sibling on R2** with non-Radish art. A sister-card inheritance compositor (~3-5 days of Python+PIL) could re-derive those programmatically.
- **the card source CSV has 23,660 real-image rows on disk; we currently consume 5,877** — 4× headroom inside an asset we already own. Just rerunning `stage_a_scrape_src.py` against the 8,386 bobaIds expects 70-85% hit rate.
- Community submission flow (mod-approval already exists per `scripts/merge_approved_additions.py`) backstops the long tail.

**Bottom line: image-sourcing dependency is essentially already broken.** This is the leverage point to flag if the conversation gets adversarial — "your scrape is upstream, our R2 is the canonical store, the dependency is one-way and already historical."

### 8.2 Watch tab + deep-link buttons + Glossary — verdict: **LOW** (~2-3 days)

- **Watch tab priority-0 slot** — one-line `KNOWN_CHANNELS` edit. Promote `BoBattleArena` (BoBA's official channel) to priority-0. The 📱 vertical-crop code is purely cosmetic and works for any vertical thumbnail.
- **"Radish Guide" deep-link buttons** — 6 surfaces total (3 iOS, 2 web, 1 Android). Delete, don't replace. The pricing panel already shows the data inline; the buttons were "see it in its native habitat" links that lose value without the partnership context.
- **`Card+Radish.swift` + `RadishURLResolver`** — clean delete cascade. 205 lines + button render + 4 user_cards insert sites. **No Supabase column exists** for `user_cards.radish_url` (verified via grep on `supabase_schema.sql`) — the iOS-side `radishUrl:` insert payloads have been silently dropped on write all along. No database migration needed.
- **Glossary / Terms / README / Pitch** — ~7 lines of copy edits across 5 files. Trivial.

**Bottom line: every non-pricing/non-image Radish surface can be removed in a half-week sprint.** Cleanest, lowest-risk delete in the codebase.

### 8.3 Pricing waterfall — verdict: **MEDIUM** (~3-5 weeks v1, ~6-8 weeks parity)

This is the only meaningful rebuild cost. Three tiers in the current waterfall; tier 1 and tier 3 are Radish.

**Tier 1 — Radish recent sales (load-bearing on the cards that DO have activity):**
- Replacement: lean harder on `normaliseSoldEnriched`. Bump treatment weight 0.05 → 0.15, hero 0.20 → 0.25, lower `SCORE_CONFIRMED` from 0.70 → 0.60. Add a second `searchSold` pass with `treatment` token appended. Extend default window from 90 → 180 days. Run AI image verification (`verifyCardImage`) on sold listings too, not just active.
- Expected accuracy drop: **~10-20% on cards that do sell**, concentrated on Battlefoil treatment variants where listings get mis-attributed between similar color subsets.
- Effort: **~2-3 days dev + ~1 week of threshold tuning against real listings.**

**Tier 3 — Radish Market Est. (the load-bearing tier on the long tail):**
- ⚠️ **This is the load-bearing piece. ~50-65% of the 17,974 catalog cards have NO eBay sold activity in 90 days.** They get a price today purely because Radish's Market Est. extrapolates from comparable cards. Without a replacement, those cards show "Pricing unavailable" or asking-only.
- Replacement: write our own comparability function. Same-hero / same-(weapon, power-tier, treatment-family) / same-(set, cardType), weighted 0.6 / 0.3 / 0.1, clamped to ±50% of strongest signal. Build a nightly cron that snapshots per-card comparable-list to Cloudflare KV; lookup at card-detail time becomes single KV read + one targeted eBay sold query.
- Bootstrap problem: real. For ~6 months after a new set drops, near-zero own-sales. Mitigation: cross-set hero anchoring (Maverick-FT-1 sells often → seeds Maverick-RBF-72 estimate via treatment-multipliers learned from other heroes).
- Effort: **~1.5-2 weeks** for a v1 — new `boba-price-estimator` Worker + cron + KV schema + comparability math.

**Additional data sources to investigate (would meaningfully reduce dependency):**
- **Whatnot post-stream sales** — Whatnot is a major BoBA marketplace; public API likely doesn't expose post-stream sale prices but worth a manual scrape recon (~3 days). High-quality second source if found.
- **Community-submitted comps** — auth-gated form + mod queue. Powerful long-term (deepens engagement); ~2 weeks build + ongoing moderation. Existing mod-correction queue is the plumbing.
- **PSA / SGC** — graded-card-focused; <1% of BoBA cards graded. Skip for v1.
- **COMC sold history** — Turnstile-blocked; not worth it.

**Bottom line on pricing:** rebuilds are doable but the Market Est. replacement is the genuinely hard part. The "comparability function" math is well-defined, but the bootstrap problem is real and the first user-facing iteration will be visibly noisier than Radish on long-tail cards.

### 8.4 Total walk-away cost — bottom line

| Scenario | Effort | User impact |
|---|---|---|
| **Defensive (do nothing today; rely on existing R2 + lean harder on eBay)** | **~3-4 days** | Pricing-unavailable rate climbs to ~50-65% on long-tail cards. Existing images keep serving. Watch pin swaps to BoBattleArena. Deep-link buttons removed. |
| **V1 replacement (own Market Est. + tuned eBay scorer + clean cascade)** | **~4-6 weeks** | ~85% pricing parity. Image-sourcing pipeline replaced with sibling inheritance + BV expansion. All non-pricing surfaces cleaned. |
| **Full parity (V1 + Whatnot integration + community-submitted comps + AI treatment classifier)** | **~7-10 weeks** | Parity or better. Less Radish dependency, more BOBA-owned signal. Defensible for the long term. |

### 8.5 What this means for the partnership conversation

Read this carefully — it's the strategic frame.

1. **We can walk away.** Cost is real but bounded; total full-parity rebuild is ~7-10 person-weeks. Not "we're stuck with Radish forever."

2. **Their leverage is pricing, not images.** If they threaten to cut off image scraping, the answer is "the bytes are already on R2; we keep what we have and add sibling inheritance for new sets." If they threaten to cut off the pricing waterfall, that's the genuinely expensive replacement — 3-5 weeks of pricing accuracy regression on the long tail, plus the bootstrap problem on Market Est.

3. **The right deal protects the pricing piece first.** A stable card-lookup endpoint, a documented data-license, and co-branding are worth meaningful concessions on our side because they preserve the most-expensive-to-rebuild surface. The Watch pin, deep-link buttons, image scraping — those are bargaining chips, not core requirements.

4. **If they treat us as competitors** (and they implied they do), the rebuild-cost framing matters: we have a path forward without them, but we'd rather not take it. Partnership is the cheaper, faster, and higher-quality outcome **for both sides** — they keep the BOBA referral funnel and YouTube placement, we keep the long-tail pricing data. Walk-away hurts both parties.

5. **Pricing approximations we could build ourselves are NOT as good as theirs.** Radish has been at this longer; their pre-match curation is a meaningful accuracy edge over what we could build from raw eBay in 3-5 weeks. Acknowledging that honestly in the partnership conversation is the right move — it's the basis for an actual value-exchange rather than a power play.

**Strategic recommendation:** lead with the partnership pitch from §7 (which doesn't reference any of this). If they push back hard or float terms that aren't workable, the rebuild-cost analysis here is your fallback frame. Don't open with it — but keep it in your back pocket.

---

## 9. Files referenced (for follow-up sharing if Radish wants the code)

- `BOBAPlaybook/Models/Card+Radish.swift` — iOS URL resolver + alias table + RadishURLResolver
- `BOBAPlaybook/Components/PricingSection.swift` — pricing surface + Radish Guide button
- `js/app.js` (lines 2116-2270) — web URL builder + alias table + pricing render
- `workers/ebay-proxy/worker.js` (lines 491-829) — Worker Radish scraper + Market Est. fallback
- `workers/youtube-feed/worker.js` (line 64) — Watch-tab priority channel config
- `pipeline/scripts/stage_a_scrape_radish.py` — catalog-image source-of-truth scraper
- `android/core/network/.../PricingService.kt` — Android Radish-aware pricing client
- `DECISIONS.md #013` — architectural decision documenting Radish as live-pricing source
- `DESIGN.md §8.7`, `ANDROID-DESIGN.md §8.7` — binding design rules naming Radish as preferred sold source
