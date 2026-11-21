# BOBA Playbook — Sunset Plan

> Drafted 2026-11-21. **Why we're shutting down:** BOBA Playbook never got approval from Bo Jackson Battle Arena or its parent company. It also takes up a Cloudflare account and a Supabase org that other projects need.
> This is the checklist for the teardown. The public write-up is in [POSTMORTEM.md](./POSTMORTEM.md).

## What's still running (inventory, 2026-11-21)

**Users (Supabase `boba-card-app`, ref `pazkimtkwwwekuguxkff`):**
- 32 accounts. 14 of them have saved collections (2,691 `user_cards` rows) and there are 10 decks.
- 13 accounts signed in within the last 90 days and 3 within the last 30. The newest signup was 2026-10-30. The database is 38 MB.

**Cloudflare (the account is SHARED with other projects, so only remove `boba-*` resources):**
- **Workers (10):** `boba-ebay-proxy`, `boba-pricing-tracker`, `boba-pricing-snapshot`, `boba-price-estimator`, `boba-mod-merge`, `boba-avatar-upload`, `boba-account-delete`, `boba-comc-proxy`, `boba-youtube-feed` (cron every 4 hours), `boba-xcode-discord`.
- **R2:** `boba-card-images` (card art, sealed products, user avatars under `avatars/`).
- **D1:** `boba-pricing` (24 MB).
- **KV:** `COMC_CACHE`, `SNAPSHOT_KV`, `ESTIMATES`, `YT_KV`.
- **Do NOT touch:** `humanshaped-*`, `eardrama-*`, `archivewatch-*`, `tidbits-auth`, `lic-github-auth`, and the `eardrama` and `archivewatch-pulse` D1 databases.

**Supabase org:** also holds `humanshaped-hub`. Delete only `boba-card-app`.

**GitHub Actions (all still active and running daily):**
- pricing daily refresh
- pipeline stages A / B / C
- blog, events and store-locator refreshes
- pHash weekly refresh
- the Android and App Store build workflows
- Pages deploy

**Store presence:**
- Google Play: `com.bobaplaybook.app` (versionCode 8, 1.0.0).
- Apple: TestFlight builds only. The App Store review rejected it on 2026-06-18 (4.1 copycat, plus 2.1(a) and 5.1.1(v)) and it was never resubmitted.

**Third-party registrations:**
- Google Cloud: OAuth web client, Android OAuth client, Maps API key.
  - ⚠️ The Maps key is committed in plain text at `android/SETUP.md:303`. Delete or rotate it.
- Firebase project.
- Discord application (OAuth).
- Apple: Services ID and Sign in with Apple key.
- App Store Connect API key (`AuthKey_Y97R9U9WMG.p8`, kept locally and gitignored).
- eBay developer keyset.
- YouTube Data API key.
- Domain `bobaplaybook.com` (DNS at WordPress.com).

## Timeline (accelerated: shut down 2026-11-21, data deleted by 2026-11-28)

### Day 0 (2026-11-21): announce and go dark
- [x] Disable the scheduled GitHub Actions workflows (pricing, pipeline A/B/C, blog, events, stores, pHash).
- [x] Replace bobaplaybook.com with a static shutdown page. `/privacy/`, `/terms/` and `/data-deletion/` stay live.
- [x] Remove the publisher's IP from the repo tree. Add the MIT LICENSE, the archive README, and POSTMORTEM.md.
- [x] Export collection/deck CSVs for the 11 users with data (Ben's own accounts excluded). Saved locally, outside the repo, in `~/Documents/BOBA-Sunset-Exports/`.
- [ ] Send the 12 Gmail drafts in ben@learningischange.com: 11 individual emails with CSVs attached, plus 1 BCC to the 18 users with no data.
- [x] Pause the Supabase project `boba-card-app`, which frees the free-tier slot for CentMemo. The data stays restorable for 90 days.
- [ ] **Google Play:** Unpublish via Test and release → Advanced settings → App availability → Unpublish.
- [ ] **App Store Connect:**
  - Expire every TestFlight build, then remove the testers and the public link.
  - Remove the app from sale in all regions.
  - Then App Information → **Remove App**.

### By 2026-11-28: delete user data
- [ ] **Sign in with Apple:** call `/auth/revoke` for every Apple-linked user that has a stored token. Do this BEFORE deleting the Services ID or key.
- [ ] Delete all accounts and user rows. FK cascade covers `user_cards`, `decks` and `deck_cards`. Also delete `user_profiles`, `card_corrections`, `community_comps`, etc.
- [x] Delete `avatars/` from R2. Covered by the expire-all lifecycle rule below.
- [x] Delete the `boba-pricing` D1 database and the 4 KV namespaces. The D1 was first backed up to `~/Documents/BOBA-Sunset-Exports/boba-pricing-d1.sql`. Done 2026-11-21.

### Right after: tear down infrastructure
- [x] Delete all 10 `boba-*` Workers (2026-11-21).
- [~] **R2 `boba-card-images`:** public r2.dev access was disabled and an `expire-all` 1-day lifecycle rule added on 2026-11-21. **On or after 2026-11-23, run `npx wrangler r2 bucket delete boba-card-images`.** Reason for deleting it: The card art is the publisher's IP, and serving it without approval is the reason we're stopping.
- [ ] Delete the Supabase project `boba-card-app`. Pause it first if you want a cool-off week.
- [ ] Revoke and delete: the Google OAuth clients plus the Maps and YouTube keys (or the whole GCP project if it's BOBA-only), the Firebase project, the Discord application, the Apple Services ID / SIWA key / ASC API key, and the eBay keyset.
- [ ] Remove the remaining GitHub secrets (`gh secret list`).

### The repo and website, permanently
- [x] **Replace bobaplaybook.com with a static shutdown page.** It says the app has shut down and links to the post mortem and the source.
  - Keep `/privacy/` and `/data-deletion/` live, because Play requires the deletion URL until the app is deleted.
  - The SPA and the card catalog come off the live site.
- [x] **Remove the publisher's IP from the tip of the repo:**
  - `Game Rules/` (official PDFs)
  - `BOBA Checklists/`
  - the card catalog JSON (`assets/data/cards*.json`, `display-cards.json`, the bundled iOS/Android catalogs)
  - the HeroShotSim test card images and the Play screenshots that show card art
  - Scrubbing git history is optional; see the decision below.
- [x] Add a `LICENSE` covering the CODE only. Rewrite `README.md` as an archive notice that points to POSTMORTEM.md.
- [ ] Archive the GitHub repo (Settings → Archive). It stays readable and forkable but becomes read-only.
- [ ] **Domain:** let `bobaplaybook.com` expire at renewal, or keep it for a year so the shutdown page and deletion URL stay reachable.
