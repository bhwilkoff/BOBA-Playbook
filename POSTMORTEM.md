# BOBA Playbook — Post Mortem

**BOBA Playbook** was an unofficial companion app for the Bo Jackson Battle Arena (BoBA) trading card game. It ran from April to November 2026 on the web, Android (Google Play) and iOS (TestFlight only). It let collectors and players search the full card catalog, scan physical cards, track a collection, build decks and look up rules.

It shut down on **2026-11-21**. This document explains why, what we built, what we'd do differently, and what in this repo is still useful to someone exploring the space.

> **BOBA Playbook was never affiliated with, endorsed by, or licensed by Bo Jackson Battle Arena or its parent company.** All card names, card art, rules text and trademarks belong to their owners. This repository no longer contains them.

---

## Why it shut down

We never got approval from the game's publisher to operate the app.

<!-- BEN: in your own words — who you contacted, when, and what (if anything) came back. One short paragraph is enough. -->

A fan tool can exist for a while without permission. It can't become a durable product that way. Without approval, every important dependency was borrowed: the card data, the card art, the brand name, and the community's trust.

Apple made the same point formally. The June 2026 App Store review rejected the iOS app under **Guideline 4.1 (Copycats)** for using the "BOBA" brand without the rights holder's permission. A disclaimer doesn't solve that; only a license does. We never resubmitted.

Running the backend also cost real resources: a Cloudflare account and a Supabase org that other projects needed. That was hard to justify for an app that couldn't grow.

## By the numbers

| | |
|---|---|
| Active development | 2026-04-03 → 2026-06-30 (~13 weeks), then automation only |
| Commits | ~1,850 by hand, plus ~600 automated data refreshes |
| Platforms | Web (vanilla JS, GitHub Pages), Android (Kotlin/Compose, Google Play), iOS (SwiftUI, TestFlight) |
| Code | ~69K lines Swift · ~29K Kotlin · ~23K web JS · ~5K Workers · ~16K Python pipeline/scripts |
| Card catalog | 31,313 cards (including the Tecmo Bowl Edition set), ~90% with images |
| Accounts at shutdown | 32 (14 had saved collections, 3 were active in the final month) |
| Backend | Supabase (auth + user data), Cloudflare R2 (image CDN), 10 Cloudflare Workers, 1 D1 database |

## What went well

- **One ID per card.** Every card got exactly one deterministic key, the `bobaId` (`cardNumber-hero-treatment-variation-weapon`), and exactly one image. That made deduplication, cross-platform sync, corrections and pricing match-gating tractable for a catalog full of near-identical variants. It's the most reusable idea in the repo.
- **A static catalog with a thin backend.** The whole card catalog shipped as static JSON. Supabase held only accounts and collections. Hosting cost was close to zero, and every read worked signed-out and offline.
- **Binding design docs.** `DESIGN.md`, `WEB-DESIGN.md` and `ANDROID-DESIGN.md` gave every UI decision a rule to cite. That kept three platforms coherent with one developer.
- **On-device scanning.** iOS used Vision OCR plus image-fingerprint matching, and Android used ML Kit. Card identification never uploaded a photo.
- **Honest pricing.** After losing our pricing sources (below), we refused to show a guessed "market value" that real sales didn't back. Every number said what kind of data it was: recent sales, a listed range, or an asking price.

## What went wrong, and what we'd do differently

1. **We built before we had permission.** This is the root cause; everything else is downstream. We built three native-quality clients, a pricing pipeline and an image-sourcing pipeline before getting a yes from the rights holder. **If you build for someone else's IP, make the licensing conversation the first milestone, not the last.** A one-page pitch and a web prototype would have been enough to ask the question.
2. **We depended on third parties we didn't control.** A large share of our card art and our first-tier pricing came from a community price guide. In May 2026 its owners asked us to stop using their data, and we complied. eBay's sold-listings API (Marketplace Insights) is effectively closed to new applicants. COMC sits behind a bot challenge. Each loss forced a rebuild. Before building on someone's data, get written permission or assume it can disappear overnight.
3. **We scaled scope ahead of users.** AI-assisted development made it cheap to ship features on three platforms in parallel: practice battles, 3D card videos, trading designs, store locators. Engineering effort was never the constraint. Audience and permission were, and adding platforms did nothing about either. One platform done well, plus a conversation with the publisher, would have told us more, sooner.
4. **We used the free tier as a CDN.** Images were served from R2's public `r2.dev` URL, which is rate-limited and weakly cached. Cache misses on the long tail of the catalog took 7–10 seconds. If you use R2, attach a custom domain from day one.
5. **App Store review found real bugs.** Beyond 4.1, Apple found that iPad sign-in was broken and that account deletion was unreachable as a result. Test on every device class you ship to, not just the phone you develop on.

## If you want to build in this space

**Talk to the publisher first.** The game has an active, enthusiastic community, and a licensed companion app could serve it well. An unlicensed one will hit the same wall we did.

**What's in this repo is the code, not the content.** The card catalog, card images, rules PDFs and checklists have been removed from the current tree. You'll need your own licensed data source. The code is released under the license in [`LICENSE`](./LICENSE).

### Pieces worth borrowing

| Piece | Where | Why it's useful |
|---|---|---|
| `bobaId` scheme + collision audit | `scripts/boba_id.py`, `DECISIONS.md` #057 | A deterministic primary key for card catalogs full of variants |
| Vanilla-JS web app with no build step | `index.html`, `js/`, `css/styles.css` | A full PWA on GitHub Pages: view system, URL state, offline catalog |
| iOS-Safari-safe layout | `WEB-DESIGN.md`, DECISIONS #020 | A body flex-column pattern that avoids Dynamic Island bleed |
| On-device card scanning | `BOBAPlaybook/` (Vision), `android/feature/scan` (ML Kit) | OCR card number + fingerprint matching, with no image upload |
| Provenance-honest pricing | `PRICING_PLAYBOOK.md`, `workers/pricing-*` | Infers sales from vanishing listings when no sold-data API exists |
| Supabase auth across iOS / Android / web | `js/api.js`, `BOBAPlaybook/Networking`, `android/core/network` | Raw REST on iOS, supabase-kt on Android, one schema (`supabase_schema.sql`) |
| Cloud App Store submission | `.github/workflows/appstore-build.yml`, `docs/CLOUD-SUBMISSION.md` | Ship to the App Store from CI when your dev Mac runs a beta OS |
| Binding design docs | `DESIGN.md`, `WEB-DESIGN.md`, `ANDROID-DESIGN.md`, `PARITY.md` | A template for keeping multiple platforms coherent with a tiny team |

### Running the web app locally

```
python3 -m http.server 8080   # then visit http://localhost:8080
```

The production backends (Supabase project, Workers, image CDN) have been deleted. To bring the app up you'll need:

- a card catalog at `assets/data/cards.json` in the shape described in `docs/CARD_SCHEMA.md`
- your own image host, set as `CDN_BASE` in `js/api.js`
- optionally, your own Supabase project created from `supabase_schema.sql`

Signed-out browsing works with just the catalog.

## Thanks

Thank you to the beta testers who scanned their binders, filed bugs and asked for features, and to the BoBA community, whose enthusiasm made this worth trying.

— Ben
