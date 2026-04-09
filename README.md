# BOBA Playbook

**Search. Scan. Collect. Play.**

Companion app for the [Bo Jackson Battle Arena](https://bojacksonbattlearena.com) (BOBA) trading card game. Available as a progressive web app at [bobaplaybook.com](https://bobaplaybook.com) and as a native iOS app.

---

## Features

### Search
Browse, search, and filter all 17,739 BOBA cards with full images. Instant search via pre-built index, collapsible filter panel (element, set, treatment, power range), card detail with zoom, athlete bio, and pricing comparables.

### Scan (iOS)
Point your camera at any card — on-device OCR identifies it in real time via Apple's Vision framework. No image is ever uploaded. Supports single and multi-card scan queues.

### Collect
Track your personal collection with five designations: **Personal · For Sale · For Trade · Wanted · Grails**. Portfolio value summary, market value estimates, and cloud sync via Supabase.

### Play
Rules reference, strategy guides, deck builder, curated card lists (WOBA, Bo Jackson, Ken Griffey Jr., by sport, by weapon type), collecting tier guide, and tournament quick-reference.

---

## Tech Stack

| Layer | Web | iOS |
|---|---|---|
| UI | Vanilla HTML/CSS/JS | Swift 6, SwiftUI |
| State | Module pattern | `@Observable`, SwiftData |
| Auth | Supabase | Supabase + Keychain |
| Images | Cloudflare R2 CDN | Cloudflare R2 CDN + URLCache |
| Card catalog | Static JSON (GitHub Pages) | Bundled JSON (two-phase load) |
| Pricing | Cloudflare Worker → eBay + Radish | Cloudflare Worker → eBay + Radish |
| Hosting | GitHub Pages | App Store / Xcode Cloud |

**No third-party Swift packages.** Apple frameworks only.

---

## Project Structure

```
/
├── index.html                  Web app entry point
├── css/styles.css              Single stylesheet (mobile-first, CSS custom properties)
├── js/
│   ├── app.js                  Web app logic + view system
│   ├── api.js                  Supabase API abstraction
│   ├── auth.js                 Auth flow
│   ├── collection.js           Collection + admin panel
│   └── discord.js              Discord OAuth2 + trade room (pending)
├── assets/data/
│   ├── cards.json              Full card catalog (17,739 cards)
│   ├── categories.json         Filter dropdown data
│   └── search-index.json       Pre-built search indexes
├── workers/ebay-proxy/         Cloudflare Worker — eBay pricing + Discord token refresh
├── BOBAPlaybook/               iOS Xcode project
│   ├── App/                    Entry point, tab bar
│   ├── Models/                 Card, UserCard, Deck
│   ├── Views/                  SwiftUI views per feature area
│   ├── Components/             Reusable UI (DiscordMessageRow, etc.)
│   ├── Networking/             SupabaseClient, CDN helpers
│   ├── Services/               DiscordService, PricingService
│   └── Store/                  AppStore, ScanStore (@Observable)
├── docs/CARD_SCHEMA.md         Full card data field reference
├── supabase_schema.sql         Supabase table definitions
├── CLAUDE.md                   Project identity + Claude Code standing instructions
├── SCRATCHPAD.md               Milestone status + feature parity tracker
├── DECISIONS.md                Architecture decision log
└── AppVersion.xcconfig         Shared iOS version numbers
```

---

## Data

- **17,739 cards** across all sets and treatments
- **14,701 card images** on Cloudflare R2 (82.9% coverage), two tiers:
  - `thumbs/` — 200px WebP ~10KB, used in grids
  - `full/` — ≤1200px WebP ~80KB, used in detail views
- Card catalog served as static JSON — no database query needed for browsing
- Supabase used only for auth and user data (`user_cards`, `decks`, `deck_cards`)

---

## Design System

Retro-futurism + Cyberpunk + Glassmorphism. Card art is always the focal point.

| Token | Value | Use |
|---|---|---|
| `--boba-orange` | `#FF4D00` | Primary CTA, FIRE element |
| `--boba-cyan` | `#00F5FF` | Links, active states |
| `--boba-violet` | `#8B00FF` | HEX element, accents |
| `--boba-near-black` | `#080810` | Page background |
| `--boba-surface` | `#0D0D1A` | Card/panel surface |

Element colors: FIRE `#FF4D00` · ICE `#00BFFF` · HEX `#8B00FF` · STEEL `#8A9BB0` · BRAWL `#C0392B` · GLOW `#FFD700` · GUM `#FF69B4` · SUPER `#FF00FF`

---

## Cloudflare Worker

`workers/ebay-proxy/` proxies:
- **eBay pricing** — Radish Price Guide (primary) → eBay Marketplace Insights → eBay Browse API fallback, with AI image verification for low-confidence matches
- **Discord token refresh** — holds `client_secret` server-side for OAuth2 PKCE refresh flow
- **Discord messages** — proxies guild channel reads via bot token (pending server bot install)

Deploy: `npx wrangler deploy` from `workers/ebay-proxy/`.

Required secrets: `EBAY_APP_ID`, `EBAY_CERT_ID`, `DISCORD_CLIENT_SECRET`, `DISCORD_BOT_TOKEN`

---

## Moderation

Card corrections and image overrides are submitted through the app and reviewed by admins via the in-app Admin Panel (role-gated). Corrections queue in `card_corrections`; image changes queue in `card_image_overrides`. Both tables use Supabase RLS.

Roles: `user` → `moderator` → `admin` (managed via `user_profiles` table).

---

## iOS — Key Architecture Notes

- **Two-phase catalog load**: `cards-head.json` (500 cards) decoded synchronously before first frame; full `display-cards.json` (~12k cards) decoded in a background task
- **Scan pipeline**: AVFoundation → Vision OCR → card number regex → match catalog — entirely on-device
- **Auth**: Supabase email/password + Sign in with Apple, tokens in Keychain
- **Images**: URLCache (100MB memory / 500MB disk), CDN helpers in `CDN.swift`
- **Version numbers**: edit `AppVersion.xcconfig`, never the Xcode identity panel

---

## Milestones

| # | Name | Status |
|---|---|---|
| M0 | Project setup, data pipeline, infra | ✅ Complete |
| M1 | Search Mode | ✅ Complete (web + iOS) |
| M2 | Collection Mode | ✅ Complete (web + iOS) |
| M3 | Scan Mode + Pricing Comps | ✅ Complete (Scan: iOS only; Pricing: both) |
| M4 | Play Mode | ⏳ In progress |
| M5 | Discord Trade Room | ⏳ Pending bot server install |
