# BOBA Playbook — Beta Test Plan

**Last TestFlight build available to testers:** 1.61 (build 62)
**Current build:** 1.870 (build 142)
**Span:** ~80 build bumps · roughly 6–8 weeks of work

The list below is grouped by surface so testers can divide and conquer. Items marked **NEW** are entirely new since build 62; everything else has been substantially reworked.

---

## Deck Builder — **NEW**

- **Formats**: Standard, SPEC, SPEC+, Limited, Elite. The legality audit panel should call out which Nationals events the deck qualifies for.
- **CSV import/export**: round-trip with the official BoBA deckbuilder format on both web and iOS.
- **Scanner integration**: tap the scan icon in the search bar → scans route into the in-progress deck (and optionally Collection). The SHOW pill should be hidden in deck-builder sessions.
- **Auto-save + silent resume**: leave a deck mid-edit, close the app, return — should land back where you left off.
- **Rule-set presets**: 14 Nationals events + 3 casual baselines. Confirm deck constraints flip correctly.
- **DBS budget**: the chip on each Play card matches the running deck total.

## Streamer Shows — **NEW**

> Streamer-only — request the role from admin first.

- **My Shows tab** (Collection): create show, add cards via card-detail "To Show", scanner Show Mode, or bulk add.
- **Show detail**: row legend (Include / Highlight), star a card → big-hit; uncheck → exclude from total.
- **Pricing walk**: should show "Pricing X of Y" and complete in seconds (sequential, 7s per-card timeout); cards with no comps no longer hang the spinner forever.
- **Generate Wall**: full-res card art (no thumb pixelation); big-hit tiles render in hero rows above the standard grid (1 / 2–3 / 4+ layouts).
- **Wall options sheet**: title-only mode, "Disable Playbook Branding", JPEG share.

## Find Tab

- **Showcases section**: WoBA (Women of BoBA), every sport, **Rookie Inspired** (catalog-backed — should hit ~2,733 cards), Bo Jackson, Ken Griffey Jr., etc.
- **Smart search**: typing "WOBA", "Baseball", "Rookie" should resolve to the showcase without opening Filter.
- **Quick Add toggle**: stamps/edits collection from the grid without opening detail.
- **Card detail 6-cell layout**: Card # / Type · Treatment / Weapon · Set / Sub-set; Cost + DBS for Plays render underneath.

## Scanner

- **OCR robustness**: vocab boost + digit↔letter substitution should match cards with rough lighting or stylized art. Try Mixtape, Inspired Ink, foils.
- **Single / Multi / Show modes**: SHOW only renders for streamers AND not in deck-builder context.
- **Multi-card session**: queue several, "Save All" routes correctly per source (Find → Collection, Deck → deck, Show → show).

## Store Locator — **NEW**

- Map + list with BoBA pins (~330 independent retailers); Big Box filter ON by default.
- Detail sheet, directions link.

## Settings

- **App icon picker**: 8 weapon colors (FIRE / ICE / HEX / STEEL / BRAWL / GLOW / GUM / SUPER).

## Catalog quality

- **Sealed Products** appear in iOS bundles.
- **Power values** should be correct (~826 rows recently corrected via OCR audit).
- **Hot Dog cards** disambiguate cleanly across sets (no bobaId collisions).
- **Cyber Promo set** (28 CYB-* cards) is browsable.

## iOS Navigation

- 5-tab structure: **Find** · **Learn** · **Play** · **Decks** · **Collection**. Confirm tabs are reachable in any order without state corruption.

## Learn Tab

- **Setup section** (new): Before Battle 1, 5 phases of a battle, common edge cases, reading the playmat.
- **Glossary** (new) with DBS tooltip on card detail.
- **Tournament section** rewritten for the 2026 draft.
- **Treatments vs Parallels**: separate sections, Inspired Ink = Serialized callout with weapon-tied serial chips (Hex /5, Glow /10, Fire /25, Ice /50).

---

## Known issues (not for tester reports)

- **eBay Worker slowness**: cards with no comps can take 30–40s to respond. iOS now caps at 7s per call and negatively caches the result, but the Worker itself still needs a follow-up fix.

---

## How to file feedback

Concise repro steps + screenshot or screen recording is gold. Tag with the surface (e.g. "Find — Filters"), the build number from Settings, and one of: bug · UX · perf · catalog data.

---

## Discord post (short version)

> 🎮 **BOBA Playbook — Big Beta Update Coming**
>
> Last build you tested was 1.61. The new build has ~80 builds of work on top of it. Highlights:
>
> 🃏 **Deck Builder (NEW)** — All 5 formats (Standard / SPEC / SPEC+ / Limited / Elite). CSV import/export matches the official BoBA deckbuilder. Auto-save, format-legality audit, scanner integration.
>
> 📺 **Streamer Shows (NEW, streamer role)** — Build a show, mark "big hits" as oversized tiles, generate a Whatnot-ready wall image with full-res card art and price totals.
>
> 🗺️ **Store Locator (NEW)** — Map of ~330 independent retailers, Big Box filter on by default with nearly 2000 additional big box options.
>
> 🔎 **Find tab Showcases** — WoBA, Rookie Inspired (~2,733 cards), every sport, smart-search resolves chip names directly.
>
> 📷 **Scanner upgrades** — Better OCR on stylized art, deck-builder routing, hidden Show mode in deck context.
>
> 💰 **Catalog quality** — 826 power corrections, Hot Dog bobaId collisions fixed, 2025 Cyber Promo set added.
>
> ⚙️ **Other** — App icon picker (8 weapon colors), 5-tab nav (Find/Learn/Play/Decks/Collection), Glossary in Learn, Tournament section rewritten.
>
> Full test plan in the repo if you want every detail. Drop bugs in this channel with build number + repro steps. 🙏
