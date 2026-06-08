# Tecmo Bowl Edition — pre-release research (2026-06-08)

**Set:** "Tecmo Bowl Edition" (2026 Release) · **Drops:** June 18, 2026 (10 days out).
We already carry the 4 sealed products (Hobby/Double-Mega Box + Cases) in the catalog;
**zero individual cards** — that's the gap this research targets.

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
