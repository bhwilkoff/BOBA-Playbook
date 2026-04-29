# BOBA Playbook — Project Scratchpad

> Active working notes only. Completed milestone implementation detail and the full session log live in [ARCHIVE.md](./ARCHIVE.md). See [DECISIONS.md](./DECISIONS.md) for architecture decisions.

## Current State

- **Active work**: Purchase view (Whatnot upcoming-shows feed + Find a Store) + nav restructure (Find / Learn / Decks / Collection / Purchase). Find tab is the default landing surface and renders larger than the others.
- **Catalog**: 17,968 cards (+54 OKC Thunder World Champions, 2026-04-28) · ~90% image coverage on R2 (OKC art still pending source). Cumulative power-realign audit landed 831 corrections across 15,691 Hero records.
- **Open questions**:
  - Whatnot Worker — three-layer extraction (DOM regex + Apollo SSR + `__NEXT_DATA__`); see Cowork's `handoff-updates-2026-04-27/whatnot-shows-worker/` for the full plan.
  - **OKC art sourcing** — all 54 OKC records ship with `imageFile=null`. Spawning a research agent to confirm what's currently published on bobattlearena.com / BazookaVault / Radish; once located, trigger a BV-scrape pass scoped to OKC- pages.
  - **COMC Cloudflare Turnstile** — `boba-comc-proxy` (workers/comc-proxy/) is wired into iOS+web BUY NOW panel per Cowork's `handoff-updates-2026-04-29/comc-feasibility/`. Hours after the recon, COMC turned on a Cloudflare-managed JS challenge for all anonymous browsers (residential IPs too). Worker currently returns `count: 0, challenged: true` and clients soft-fail to no COMC items. Bypass requires Cloudflare Browser Rendering API or migrating to a Playwright runner — defer until COMC's WAF stance changes or we decide it's worth the cost.

---

## Feature Parity Status

✅ Both | 🌐 Web only | 📱 iOS only | ⏳ Planned | ❌ Deferred

| Feature | Web | iOS | Notes |
|---|---|---|---|
| Search Mode | ✅ | ✅ | M1 complete |
| App icon + branding | ✅ | ✅ | XOXO logo, wordmark, PWA |
| Mobile Safari layout | ✅ | n/a | Body flex column, no viewport-fit=cover |
| Collection Mode | ✅ | ✅ | M2 complete |
| Scan Mode (camera OCR) | ❌ | ✅ | M3 iOS complete — iOS only by design |
| Pricing comps (links) | ✅ | ✅ | M3 complete |
| Buy Now (active listings) | ✅ | ✅ | M3.5 complete — Worker deployed at boba-ebay-proxy.benwilkoff.workers.dev |
| Deck Builder | ✅ | ✅ | Templates + saved decks, format-aware (Standard/SPEC/SPEC+/Limited). |
| Streamer Shows | ✅ | ✅ | My Shows + Generate Wall (streamer role only). |
| Find a Store | ✅ | ✅ | MapKit/Leaflet, ~330 indie retailers + ~1,800 big-box. |
| Purchase view (Upcoming Breaks + Find a Store) | ⏳ | ⏳ | In-progress. |

---

## Milestones

### ✅ Completed
- **M0 — Project Setup**: Card data JSONs, R2 images, Supabase schema, GitHub Pages live, Xcode project at repo root.
- **M1 — Search Mode** (both platforms): card grid, search, filters, modal, CDN images, PWA, branding.
- **M2 — Collection Mode** (both platforms): Supabase auth (email + Apple), Keychain (iOS), CRUD, designation tabs, value summary, ProfileView. Designations: Personal · For Sale · For Trade · Wanted · Grails.
- **M3 — Scan Mode (iOS) + Pricing Comps (both)**: Vision OCR with 3-frame stability, multi/single toggle, Save All queue. Radish + eBay links on both platforms.
- **M3.5 — Pricing Enhancements**: Dual-section Buy Now + sold history shipped on both platforms.

Full implementation notes for M1–M3.5 live in [ARCHIVE.md](./ARCHIVE.md).

---

### ⏳ M4 — Purchase view (ACTIVE)

Two sections:

1. **Upcoming Breaks** — Whatnot upcoming-shows feed for the search "Bo Jackson Battle Arena", surfaced as large card tiles with host, scheduled time, viewer/interested count, and a deep link into the Whatnot show. Backed by a Cloudflare Worker (`boba-whatnot-shows`) that scrapes the search page server-side; Worker spec in `handoff-updates-2026-04-27/whatnot-shows-worker/`.
2. **Find a Store** — moved here from inside Collection. ~330 independent retailers + ~1,800 big-box (with default filter to indies); MapKit on iOS, Leaflet on web.

---

### ❌ M5 — Discord Trading Channel (FUTURE)
Embed community trading channel. `discord.com/channels/1305710603440095252/1306146115757936650`
Research Discord Activity SDK vs WebView feasibility before committing.
