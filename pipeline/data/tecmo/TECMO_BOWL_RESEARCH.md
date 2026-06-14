# Tecmo Bowl Edition — pre-release research (2026-06-08)

**Set:** "Tecmo Bowl Edition" (2026 Release) · **Drops:** June 18, 2026 (10 days out).
We already carry the 4 sealed products (Hobby/Double-Mega Box + Cases) in the catalog;
**zero individual cards** — that's the gap this research targets.

> ## UPDATE 2026-06-14 — BV crawl run with Ben's cookie: Tecmo NOT loaded yet
> Authenticated against BV (two-cookie auth confirmed: `_bazooka_vault_session`
> **+** `user_id`; session alone silently redirects to /login — see
> `bv_catalog_scraper.py` header). Findings (4 days before the June 18 drop):
> - **Highest valid BV card ID = 17751.** IDs 17752+ return HTTP 500 (BV errors on
>   non-existent records), so nothing is hidden above the frontier.
> - Our existing `bv_scan_results.csv` already covered IDs 1–17743; the frontier
>   moved only **8 IDs** since (a 160-card set would jump it ~160+).
> - The entire recent band (16000–17751, 1,752 cards) is **set='Griffey'** — zero
>   `set='Tecmo'`, zero "8-bit"/"Tecmo" keyword hits. The newest 8 IDs are Griffey
>   "The Kid" promo placeholders (P-1…P-10, card-back art).
> - The revealed-hero keyword matches (e.g. "Troy of Dallas" = Aikman) are all
>   **Griffey-set** cards of players who also appear in Tecmo — false positives.
> **Conclusion:** BV has not loaded the Tecmo set (not even hidden) as of 2026-06-14.
> BV loads sets at/just-before release — **re-run `bv_catalog_scraper.py probe`
> at/after June 18.** Cookie required each run (rotates/expires).

> ## UPDATE 2026-06-14 (b) — deeper promo-art harvest + new channel leads
> A second research pass (web + promo media API) past the original ~10 cards.
> **Still no full ~160-card checklist anywhere** (tcdb / Beckett / Cardboard
> Connection / Ludex all empty; `bobattlearena.com/checklists/tecmo-bowl/` → 404;
> no Tecmo Collector-Guide PDF — only the Griffey set has one). But card numbers
> were read off the official auto art (verify against the official checklist
> before catalog ingest, per `feedback_card_data_truth_from_image`):
>
> | Player | Hero name | Card # (art-read) | Power | Weapon | Treatment / Serial | Art URL (promo.bobattlearena.com/wp-content/uploads/2026/03/) |
> |---|---|---|---|---|---|---|
> | John Elway | Duke of Denver | JE43 | 200 | HEX | Inspired Ink on-card auto (Debut) | ElwayHex-1.png |
> | Dan Marino | Marino | DM93 | 195 | HEX | Inspired Ink on-card auto | MarinoHexwsig.png |
> | Eric Dickerson | Goggles | EDAS | 175 | FIRE | Inspired Ink auto · 29/50 · "HOF 99" | ericdickersonfinal.png |
> | Lawrence Taylor | Fear Himself | LTA4 | 190 | GLOW | Inspired Ink auto · 5/25 (Debut) | ltautofinal.png |
> | Bo Jackson | Touchdown! Bo Jackson | TBJ-R prefix | 250/200 | — | Superfoil 1/1 auto + Battlefoil /34 | Touchdown-Bo-Jackson-Blog.png |
>
> - **Card-number scheme:** base autos = hero-initials+number (JE43, DM93); an
>   autograph-series code appears on some (EDAS, LTA4 = initials + "AS"/"A#").
>   Feed both shapes to the scan regex when the set ingests.
> - **Hero names corrected/added:** Dickerson = "Goggles", Taylor = "Fear Himself"
>   (the earlier doc left these blank). A **"Cutback"** hero exists (player IG
>   tease, instagram.com/p/DV9Ij5rD1DL/) — likely a RB (Faulk/Thomas), art not yet
>   found. NOTE the earlier doc listed Elway as "JE03"; art-read here is "JE43" —
>   reconcile at ingest.
> - **Goldmine channel:** `promo.bobattlearena.com/wp-json/wp/v2/media?search=<surname>`
>   returns full-res (~1100×1500) card PNGs and gets new art BEFORE the checklist
>   page. The daily watcher + the `tecmo-release-watch` cloud routine now poll it
>   per-signer. Art lives under /uploads/2026/03/ and /2026/06/.
> - **New lead — `play.bobattlearena.com/cards`** (Blokpax-backed card DB,
>   JS-rendered): the Tecmo records will likely populate here at/near launch with
>   full structured data. Its XHR/JSON endpoint isn't found yet (`/api/cards?set=tecmo`
>   → 404). Worth finding the real API — it could be a cleaner full-checklist
>   source than the BV ID-crawl. (BV itself is also a Blokpax/Cardeio-class SPA.)
> - **Dead ends (don't repeat):** tcdb/Beckett/Cardboard Connection/Ludex/SCI,
>   GTS/gogts detail pages (403), ICv2 (403), eBay singles (still sealed-only),
>   media search for `8bit`/`cutback`/`touchdown` (not yet uploaded).

> ## UPDATE 2026-06-14 (c) — Carde.io play API mapped + set-size correction
> **SET SIZE: "160" is the per-BOX card count, NOT the checklist size.** Tecmo is
> a HUGE set (every hero × treatment × parallel × serial). When BV loads it the
> frontier will jump by THOUSANDS of IDs, not ~160 — don't size any crawl/probe
> around 160. (Reference scale: BV's Griffey slice alone is ~18k rows; our full
> catalog is 17,974; BV's collectible frontier is ID 17,751.)
>
> **play.bobattlearena.com card API — FOUND (public, no auth, paginated):**
> `https://api.carde.io/api/v1/cards/651f3b0e5f72a5fca3f6fe34?page=N&limit=200`
> → `{pagination:{totalResults,totalPages,...}, data:[{id,name,slug,element,
> cardType,subtype,imageUrl}]}`. IDs:
> - Mongo game id `651f3b0e5f72a5fca3f6fe34` · UUID `e30530dd-73f7-45be-bfe3-1044edec034a`
>   · slug `bo-jackson-battle-arena`.
> - App config (also public): `https://play-api.carde.io/v1/app/init?game=bo-jackson-battle-arena`.
> - Single card: `https://api.carde.io/api/v1/cards/{mongoGameId}/{cardId}`.
> - The set name is encoded in each card's `slug` prefix (e.g. `alphaedition-sets-rad…`).
>
> **BUT it does NOT have Tecmo** — and it LAGS BV: only 2,461 cards, all Alpha
> Edition / 2024 National Show / World Champions / Sandstorm. It has **no Griffey**
> even. This is the **gameplay** catalog (deck-buildable definitions), which loads
> a set LATER than the BV collectible vault. So for Tecmo ART, BV is still the
> earliest source; the play API is a SECONDARY signal.
>
> **Why it still matters:** it's the ONLY public, no-cookie, *structured* BoBA card
> source (clean hero/element/type/imageUrl + pagination), so it CAN run in the
> unattended cloud watcher (BV can't — needs a manual cookie). `tecmo_release_watch.py`
> now polls its `totalResults` count + scans for a Tecmo slug; a jump past the
> baseline (2,461) or a Tecmo slug fires an alert.
>
> **BV ≠ Carde.io-play.** bazookavault.com is a separate Rails app (shares only the
> `cardeio-images` GCS bucket); it has NO clean paginated public API, so the BV
> ID-crawl (`bv_catalog_scraper.py`) remains the collectible-side method.

## TL;DR

**The full Tecmo Bowl checklist is NOT published anywhere public yet.** Only an
official *sneak-peek* of ~10 cards (autographs + the Bo grail + a 4-card alt-art
teaser) is out. I harvested all of it. The base 160-card list will appear when
BoBA publishes the official checklist **or** when Bazooka Vault loads the set —
BV is the highest-leverage early source but is login+Turnstile gated and needs
your account.

## What's confirmed about the set

- **Config:** Double-Mega = 16 packs / 160 cards / **8 exclusive inserts & parallels per box**.
- **Autos:** on-card autographs **only** (no sticker autos).
- **New:** Battle Arena's **first-ever 8-bit alt-art** cards (Tecmo-era styled); SP & SSP chase; a reimagined framework redesigned for the collaboration.
- **Grail:** *Touchdown! Bo Jackson* — 1/1 on-card auto + **/34 Black Variation** (gold-ink sig).
- **Card-number format (read from art, verify):** hero-initials + number — e.g. `DM93` Marino, `JE03` Elway.

## Revealed cards (harvested art → `pipeline/data/tecmo/art/`, manifest in `tecmo_revealed_cards.json`)

| BoBA hero name | Player | Power | Weapon | Treatment | Serial |
|---|---|---|---|---|---|
| MARINO | Dan Marino | 195 | HEX | Inspired Ink auto | — |
| DUKE OF DENVER (Debut) | John Elway | 200 | HEX | Inspired Ink auto | /13 |
| ATTAK | Dak Prescott | 195 | GLOW | Inspired Ink auto | — |
| ALLENWRENCH | Marcus Allen | 170 | — | alt-art/foil | — |
| TROY OF DALLAS | Troy Aikman | 175 | — | alt-art/foil | — |
| — | Barry Sanders | 175 | — | alt-art | — |
| — | Lawrence Taylor | — | — | Inspired Ink auto | — |
| — | Eric Dickerson | — | — | Inspired Ink auto | — |
| — | Randall Cunningham | — | ICE | Inspired Ink auto | — |
| TOUCHDOWN! BO JACKSON | Bo Jackson | — | — | grail | 1/1 + /34 |

**Announced signers (24):** Bo Jackson, Elway, Brees, L. Taylor, Dak Prescott, Aikman,
Puka Nacua, Randy Moss, Marino, Steve Young, Gronkowski, Ronnie Lott, Dickerson,
Thurman Thomas, Bettis, Jim Kelly, Barry Sanders, Marcus Allen, Cunningham, McMahon,
Tony Dorsett, Marshall Faulk, Warren Moon, Mike Singletary.

## Sources checked (exhaustive)

| Source | Result |
|---|---|
| bobattlearena.com/checklists/ | ✗ no Tecmo checklist yet (only Griffey 2026 + older) |
| bobattlearena.com /wp-json | ✗ REST API disabled |
| **promo.bobattlearena.com /wp-json** | ✓ **open** — full media library enumerated (80 items, ~10 cards revealed) |
| bobattlearena.com blog (5 Tecmo posts) | ✓ sneak-peek signers + grail; no card numbers |
| shop.bobattlearena.com | ✗ sealed product only |
| eBay (our Worker proxy) | ✗ sealed boxes/presales only — **no singles yet** |
| Beckett Gaming | ✗ no Tecmo set page yet |
| Distributors (GTS, Midwest, Collection Realm) | ✗ marketing copy, no checklist |
| Forums (Blowout/Net54/SCF) | ✗ nothing |
| Radish | read-only signal only (compliance, #056) — not surfaced in search |
| **Bazooka Vault** | ⚠ catalog gated behind login + Turnstile — pullable via **session-cookie** crawl (see below); needs Ben's cookie |

## Bazooka Vault — how we pull it (investigated 2026-06-08)

The original `bv_scan_results.csv` came from the research-repo `scrape_bazookasvault.py`,
which **authenticates** and crawls `/cards/{id}` (the embedded JSON carries imageUrl +
metadata); images then download from the public CDN `images.bazookavault.com`.

Two access methods, evaluated against BV's *current* state:

- **Public GCS bucket listing** (`rescan_gcs_bucket.py`, the "bucket scraping" method):
  the `cardeio-images` bucket (Cardeio is BV's platform) is still publicly listable, BUT
  its BoBA slice is **stale** — newest object ~mid-2025, no 2026 Griffey, **no Tecmo**.
  New art moved to `images.bazookavault.com`, a Cloudflare-fronted image *API* that is
  **not** bucket-listable. → dead end for Tecmo.
- **Authenticated `/cards/{id}` crawl** — still works, but BV added a **Turnstile** widget
  to /login, so an automated email/password form-POST may now be rejected. The robust,
  Turnstile-proof path is **session-cookie auth**.

**Ready-to-run tool:** `pipeline/scripts/bv_catalog_scraper.py` (cookie-auth).
  1. Log into bazookavault.com in a browser (you solve Turnstile once).
  2. DevTools → Cookies → copy `_bazooka_vault_session`.
  3. `export BV_COOKIE='<value>'`
  4. `python3 pipeline/scripts/bv_catalog_scraper.py probe --start 17000 --end 40000`
     (finds the highest valid card ID + set histogram — tells us if Tecmo is loaded yet)
  5. `python3 .../bv_catalog_scraper.py scan --start <lo> --end <hi> --set "Tecmo"`
  6. `python3 .../bv_catalog_scraper.py download`  (public CDN, no auth)

  Caveat: BV may not have **loaded** the Tecmo card pages yet pre-release (the checklist
  isn't public anywhere). `probe` will tell us immediately. Re-run at/after June 18.

## Tooling built (reusable)

- `pipeline/scripts/scrape_promo_tecmo.py` — enumerates the promo WP media library, filters to card-art candidates, downloads them. Re-run anytime to pull new spoilers.
- `pipeline/scripts/tecmo_release_watch.py` — daily watcher: official checklist page, new promo media, and first eBay singles. Persists state and flags only deltas. **Run daily until June 18** (or wire as a GH Actions cron).

## Recommended next steps

1. **Bazooka Vault unlock (highest leverage):** paste your `_bazooka_vault_session`
   cookie (Turnstile-proof — see "Bazooka Vault — how we pull it" above) and run
   `bv_catalog_scraper.py probe`. BV is the catalog partner and typically loads sets
   at/just-before release — that's where the full checklist + art will appear first.
2. **Run `tecmo_release_watch.py` daily** — it will catch the official checklist PDF and
   the first eBay singles the moment they appear; both unlock automated art sourcing.
3. **On checklist publish:** parse it → mint v3 bobaIds → stage sealed+singles into the
   catalog so the app is populated for June 18.
4. **eBay singles** will become a viable art source at/after release (the Worker query is
   already wired); the watcher flags when they appear.
