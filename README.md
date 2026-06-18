# BOBA Playbook

**Search. Scan. Collect. Play.**

[bobaplaybook.com](https://bobaplaybook.com) — the independent companion app for the [Bo Jackson Battle Arena](https://bobattlearena.com) (BOBA) trading card game. Available as a progressive web app and a native iOS / iPadOS app.

BOBA Playbook is built by fans, for fans. It is not affiliated with or endorsed by the game's publisher — it exists because the community deserves great tools.

---

## What It Does

The app is organized around five verbs — one per tab.

### Find — explore
Browse, search, and filter all 17,968 BOBA cards. Token-style filters by hero, weapon, treatment, cost, format, and set. Tap any card for the detail view: full art, the canonical 6-cell stat grid, live eBay pricing, and one-tap add to your collection or current deck.

### Learn — understand
Rules reference for all three skill levels (Rookie / Substitution / Playmaker), strategy guides, the collecting-basics taxonomy (treatments vs parallels, weapon rarity, Inspired Ink serialized variants), curated YouTube tutorials, glossary, and the BoBA tournament reference.

### Decks — build
Native deck builder with format-aware composition rules, legality auditor, distribution charts, CSV import / export, and saved-decks sync via the cloud. iPad gets a 3-column layout — saved decks sidebar, card pool, and the active deck editor all visible at once.

### Collection — own
Track your personal collection across five designations: **Personal · For Sale · For Trade · Wanted · Grails**. Synced across devices via the cloud. Portfolio value summary draws from live market data. Optional public collection page at `bobaplaybook.com/u/{username}` so you can share your binder. Custom avatars (or auto-imported from Discord) and Rainbow Progress lens for set completion.

### Purchase — acquire
Live Whatnot upcoming-breaks feed (filterable by host) and a card-store locator with ~330 indie shops + ~1,800 big-box locations across the US, on MapKit (iOS) and Leaflet (web).

### Scan (iOS only) — identify
Point your iPhone or iPad camera at any card and it identifies it in real time — entirely on-device via Apple's Vision framework + a custom image-fingerprint index. **No image is ever uploaded.** Supports single-card live scan, grid-burst scan (lay out multiple cards on a flat surface), and a queue with running value tally.

---

## iPad

iPad is a first-class device, not a stretched-iPhone afterthought. Each tab uses a `NavigationSplitView` appropriate to its content:

- **Decks** — saved decks · pool · editor (3-column)
- **Collection** — lens picker (My Cards / Rainbow / My Shows) + designation grid
- **Learn** — category list + article detail
- **Purchase** — mode picker + content
- **Find** — full-screen search

iPad also gets **drag-and-drop** (drag a card from Find / Decks pool / Collection straight into the deck editor), **hardware-keyboard shortcuts** (Cmd+1..5 to switch tabs), action-shaped sheets adapt to popovers, and the whole app rotates — landscape works everywhere.

---

## Pricing Data

Pricing comes from **eBay** — sold listings for the market-estimate / sold-history panel, and active "Buy Now" listings for the asking panel. Asking and sold are kept separate. The market estimate uses sold data only — mixing in asking prices would inflate it 10-25%.

---

## Public Collections

When you toggle "Public collection" on in Profile, your collection becomes shareable at `bobaplaybook.com/u/{your-username}`. The page renders read-only (no sign-in required to view), excludes your purchase prices and notes, and filters out the Wanted designation (the public page reads as "what they have," not "what they want"). Toggle off any time and the page 404s.

---

## Privacy

- **Card identification runs on your device.** The scan pipeline never sends card images to a server.
- **Your collection lives in your account, not in our analytics.** We don't sell, share, or aggregate user collection data.
- **Public collection pages are opt-in.** Off by default; the URL only resolves when you explicitly enable sharing.
- See the [privacy policy](https://bobaplaybook.com/privacy/) and [terms of service](https://bobaplaybook.com/terms/).

---

## The BOBA Ecosystem

BOBA Playbook is one tool in a growing ecosystem. These others are excellent and worth knowing:

- **[Bo Jackson Battle Arena](https://bobattlearena.com)** — the official game site

---

## Tech

Built with vanilla HTML / CSS / JavaScript on the web and Swift 6 / SwiftUI (iOS 17+) on iOS. No frameworks, no third-party Swift packages — Apple SDK + a single Supabase JS SDK loaded via CDN on the web.

- **Card catalog** — static JSON (17,968 cards · ~90% image coverage), served from GitHub Pages and bundled into the iOS app
- **Card images** — Cloudflare R2 (zero egress, edge-cached). Two tiers: 200px thumbs for grids ≥5-across, ≤1200px full WebP otherwise
- **Auth + user data** — Supabase (Postgres + auth). Card browsing never touches a database
- **Integrations** — Cloudflare Workers for eBay pricing, Whatnot upcoming breaks, account deletion, avatar uploads, YouTube feed. Each Worker is a single-purpose proxy
- **Scan pipeline** — Apple Vision (text + image fingerprint) on-device, with a parallel macOS CLI for offline iteration
- **Web app** — PWA installable from Safari, View Transitions API for native-feeling page transitions, container queries on the card grid, native `<dialog>` modals, no build step

Engineering principles live in [`CLAUDE.md`](./CLAUDE.md). Architecture decisions are logged in [`DECISIONS.md`](./DECISIONS.md). Binding design rules: [`DESIGN.md`](./DESIGN.md) (iOS), [`WEB-DESIGN.md`](./WEB-DESIGN.md) (web), and [`TRADE-DESIGN.md`](./TRADE-DESIGN.md) (P2P trading — design ratified, implementation pending).

---

## What's Built

| Surface | iOS | Web |
|---|---|---|
| Find | ✅ | ✅ |
| Learn | ✅ | ✅ |
| Decks | ✅ | ✅ |
| Collection | ✅ | ✅ |
| Purchase (Breaks + Stores) | ✅ | ✅ |
| Scan | ✅ | n/a (Apple Vision is iOS-only) |
| Public collections (`/u/{handle}`) | ✅ opt-in toggle | ✅ read-only viewer |
| iPad first-class layout | ✅ | n/a |
| Walkthroughs | ✅ | n/a (web primitives are self-explanatory) |

Some surfaces are role-gated:

- **Streamer role** — Whatnot show management + generate-wall surfaces. Request via Profile → Role Request
- **Moderator role** — card correction queue, image override. Request the same way
- **Admin** — admin panel, practice executor (still in development)

---

## Contributing

Card data corrections, missing images, and rule clarifications are welcome:

- **Sign in to the app and use the correction flow.** Submissions are reviewed by moderators before going live.
- **Code contributions** — read [`CLAUDE.md`](./CLAUDE.md) for conventions, [`DESIGN.md`](./DESIGN.md) / [`WEB-DESIGN.md`](./WEB-DESIGN.md) for design rules, and [`DECISIONS.md`](./DECISIONS.md) for architecture context.
- **Moderator role** — request via Profile → Role Request once you've used the app for a while.

---

## License

Code is offered as-is for community-tool purposes. Card art, hero names, and game terminology are property of their respective rights holders; this repository contains none of those — only the code that displays them via public CDN URLs and the JSON metadata that the BOBA community has reconciled across public sources.
