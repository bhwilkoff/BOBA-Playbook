# DECISIONS.md — Architecture Decision Log
<!-- Merge these into the DualAppTemplate DECISIONS.md in the BOBA-Playbook repo -->
<!-- Append new decisions below; never edit existing entries -->

---

## Decision 006 — App Name and Brand Identity
**Date:** 2026-04-03
**Display name:** BOBA Playbook. **GitHub repo:** BOBA-Playbook. **Xcode product name:** BOBAPlaybook (hyphens not valid in Xcode product names).
**Design language:** Retro-futurism + cyberpunk UI + glassmorphism.
**Palette:** battle orange (#FF4D00), cyber cyan (#00F5FF), deep violet (#8B00FF) on near-black (#080810) with frosted glass panels.
**Card art is always the focal point** — UI chrome frames it, never competes with it. Power numbers and element colors are large and immediately legible. Opinionated aesthetic that draws users in, matching the energy of the BOBA cards themselves.

---

## Decision 007 — Supabase for Auth and User Data (Not Images)
**Date:** 2026-04-03
Supabase free tier handles: auth, `user_cards` (collection tracker), `decks`, `deck_cards`.
Static card catalog (`cards.json`, GitHub Pages) handles all browsing — no DB query needed.
**Supabase Storage is NOT used.** The free tier (1 GB storage, 2 GB/month bandwidth) would exhaust in hours for a card image app. Images are hosted on Cloudflare R2 exclusively.

---

## Decision 008 — Cloudflare R2 for Image CDN
**Date:** 2026-04-03
10,751 card images on R2 bucket `boba-card-images`. R2 chosen for: 10 GB free storage, **zero egress fees**, Cloudflare edge caching globally.
Two image tiers:
- `thumbs/` — 200px wide WebP, ~10 KB avg → card grids/lists
- `full/`   — ≤1200px WebP, ~80 KB avg → card detail views
`CDN_BASE` env var holds the public bucket URL. **Never hardcode R2 URLs.** Always use CDN helper functions (`thumbUrl(f)`, `fullUrl(f)`).

---

## Decision 009 — Static Card Catalog JSON (Pre-Generated)
**Date:** 2026-04-03
`cards.json` (13 MB, 17,793 cards) is committed to `assets/data/` and served from GitHub Pages. No database query needed for catalog browsing.
`cards-slim.json` (8.7 MB, no `searchTokens`) is the iOS bundle version.
SwiftData caches the catalog on-device after first load.
To update when new sets release: re-run `reconcile_all.py` in the Research folder, then copy the four JSON files from `unified-cards/data/` to `assets/data/` and commit.
Full schema: `docs/CARD_SCHEMA.md`.

---

## Decision 010 — Element Color System
**Date:** 2026-04-03
Each BOBA element maps to a canonical UI color used consistently throughout the app (backgrounds, borders, badges, glows):
```
FIRE  → #FF4D00  ICE   → #00BFFF  HEX   → #8B00FF
STEEL → #8A9BB0  BRAWL → #C0392B  GLOW  → #FFD700
GUM   → #FF69B4  SUPER → #FF00FF  NONE  → #666680
```
Elements in `cards.json` are always UPPERCASE (normalized by `reconcile_all.py`). The element color is the primary visual differentiator on card components.

---

## Decision 011 — No Images in GitHub Repo
**Date:** 2026-04-03
The repo contains only code and JSON data files. Card images are never committed to git — they live exclusively on Cloudflare R2.
`assets/data/` contains the four JSON files. `assets/images/` does NOT exist.
This keeps clone time fast and avoids GitHub's soft 1 GB storage limit.

---

## Decision 012 — Scan Mode: On-Device Vision Only
**Date:** 2026-04-03
Card identification in Scan Mode uses iOS `Vision` (`VNRecognizeTextRequest`) and `AVFoundation` only. **No image is uploaded to any server.** All processing is on-device.
Match pipeline: OCR text from camera frame → regex for card number pattern → look up in `cards.json` → display result.
Card number regex: `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)` (covers BF-208, T-16/50, BLBF-644, etc.)
Confidence threshold: require card number match OR (hero name + power value both agree).
Fall back to manual search if confidence < 0.7.
Multi-card mode maintains a scan queue in `ScanStore` with running value tally.

---

## Decision 013 — Pricing Comps Strategy
**Date:** 2026-04-03
Pricing data is fetched live at card-detail view time (not pre-cached in cards.json):
- **Radish Price Guide** (`radishpriceguide.com`) — BOBA-specific pricing, primary source
- **eBay sold listings** — secondary source, searched by card number
Pricing calls are made via a lightweight proxy or directly from the client if CORS allows.
Prices are NOT stored in Supabase — they are live lookups only.
The Collection Mode value dashboard uses last-fetched prices cached in `user_cards.estimated_value` with `user_cards.last_price_check` timestamp.
Box lookups (Hobby, Double Mega, Jumbo) use eBay sold listings searched by product name.
