# BOBA Playbook

**Search. Scan. Collect. Play.**

[bobaplaybook.com](https://bobaplaybook.com) — the independent companion app for the [Bo Jackson Battle Arena](https://bobattlearena.com) (BOBA) trading card game. Available as a progressive web app and a native iOS app.

BOBA Playbook is built by fans, for fans. It is not affiliated with or endorsed by the game's publisher — it exists because the community deserves great tools.

---

## What It Does

### Search
Browse, search, and filter all 17,739 BOBA cards with full images. Instant search, filters by element, set, treatment, and power range, card detail view with athlete bio, zoom, and live eBay pricing data.

### Scan (iOS)
Point your camera at any card and it identifies it in real time — entirely on-device using Apple's Vision framework. No image is ever uploaded to a server. Supports single-card and multi-card scan queues with a running value tally.

### Collect
Track your personal collection with five designations: **Personal · For Sale · For Trade · Wanted · Grails**. Synced across devices via the cloud. Portfolio value summary draws from eBay sold data to give you a real market picture.

### Play
Rules reference for all three game modes (Rookie, Substitution, Playmaker), strategy guides, deck builder, curated card lists (WOBA, athlete collections, by sport, by weapon type), rarity and collecting tier guide, and tournament quick-reference.

---

## Pricing Data

Pricing comparables are sourced from **eBay sold listings** — the closest thing to a real market price for any individual card. The app surfaces low, average, and high sale prices across 7, 30, and 90-day windows.

---

## The BOBA Ecosystem

BOBA Playbook is one tool in a growing ecosystem. These other community resources are excellent and worth knowing:

- **[Radish Price Guide](https://radishpriceguide.com)** — detailed eBay sales history and price tracking
- **[Bazooka Vault](https://bazookavault.com)** — card database and collection management
- **[Bo Jackson Battle Arena](https://bobattlearena.com)** — the official game site

---

## What's Built

| Milestone | Feature | Status |
|---|---|---|
| M1 | Search Mode | ✅ Web + iOS |
| M2 | Collection Mode | ✅ Web + iOS |
| M3 | Scan Mode | ✅ iOS |
| M3 | Pricing Comps | ✅ Web + iOS |
| M4 | Play Mode | ⏳ In progress |
| M5 | Discord Trade Room | ⏳ Pending |

---

## Tech

Built with vanilla HTML/CSS/JS on the web and Swift/SwiftUI on iOS. No frameworks, no third-party packages — just fast, reliable tools that work.

Card data is served from static JSON (17,739 cards, 14,701 images at 82.9% coverage). The cloud backend (Supabase) handles only auth and personal collection data — card browsing never touches a database.

The iOS scan pipeline runs entirely on-device via Apple's Vision framework. The web app is a PWA installable on any device.

---

## Contributing

Corrections to card data, missing images, and rule clarifications are welcome. Sign in to the app and use the correction flow — submissions are reviewed by moderators before going live.

For code contributions, see `CLAUDE.md` for project conventions and `DECISIONS.md` for architecture context.
