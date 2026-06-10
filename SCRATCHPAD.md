# BOBA Playbook — Project Scratchpad

> Active working notes only. Completed milestone implementation detail and the full session log live in [ARCHIVE.md](./ARCHIVE.md). See [DECISIONS.md](./DECISIONS.md) for architecture decisions and [DESIGN.md](./DESIGN.md) for binding iOS design rules.

## Current State

- **Catalog**: 17,974 cards · ~90% image coverage on R2 · OKC art still pending · 30 invalid-power records repaired
- **Latest version**: edit `AppVersion.xcconfig` for iOS; Android tracks via `app/build.gradle.kts` versionCode/versionName (CI bumps on tag push)
- **Hero Shot iteration**: headless CLI runner shipped (`tools/render-hero-shot-variants.sh`) — boots a simulator, renders 4 material variants to `/tmp/hero-shot-variants/grid.png` in ~20-30s

## Recently shipped — pattern memory pointers

Pattern memories from the pre-compaction sessions (preserved across compaction):
[[reference_overnight_parity_session_2026_05_20]] · [[feedback_state_from_prop_antipattern]] · [[feedback_viewmodel_reset_on_auth_change]] · [[reference_worker_field_shapes]] · [[reference_android_cdn_sealed_routing]] · [[reference_android_prefs_pattern]] · [[feedback_usd_locale_format]] · [[feedback_worker_canonical_average]] · [[feedback_card_data_truth_from_image]] · [[project_custom_rainbows_architecture]] · [[project_mod_add_card_architecture]] · [[feedback_universal_links_onopenurl]] · [[reference_build_number_sync]] · [[feedback_profile_only_on_find]].

## Deferred iPad work

- **Walkthrough anchor verification on iPad** — needs simulator validation that anchors registered in NavigationSplitView sidebar/detail columns resolve correctly through the outer `walkthroughOverlay`. SwiftUI preferences flow up the view tree, so should work, but verify in simulator.
- **iPad drag-and-drop** — drag cards between deck slots, between Find→Decks/Collection. Significant work; nice-to-have.

## Active / Next-Up

- **Match-alerts pipeline** (Wanted/Grail notifications) — UI toggle ships, APNs server-side dispatcher is multi-week of new infra. See DECISIONS.md #039. Match-alerts pipeline is now Phase 7 of the TRADE-DESIGN.md §14 roadmap; don't ship before Phase 0 (LLC + insurance + ToS) is done.

## Open Questions / Blockers

- **OKC art sourcing** — 54 OKC records ship with `imageFile=null`. Confirm what's published on bobattlearena.com / the card source, then trigger a BV-scrape pass scoped to OKC- pages.
- **Radish removal backfill** — see RADISH_REMOVAL_LOOP.md. 8,386 cards still ship with `imageSource: "RADISH"` attribution; bytes stay on R2 (they're ours per DECISIONS.md #008), but provenance needs to flip as BV / eBay-image-sourcer / community submissions re-source each one. Backfill queue at `assets/data/radish_backfill_queue.json` (regenerate via `scripts/identify_radish_sourced_cards.py`).
- **COMC Cloudflare Turnstile** — `boba-comc-proxy` returns `count: 0, challenged: true`. Bypass requires Cloudflare Browser Rendering API or a Playwright runner. Defer until COMC's WAF stance changes.
- **Practice executor IP review** — admin-gated per DECISIONS.md #033; access via the bolt icon on the Profile role badge. No timeline.
- **R2 custom domain — image-load latency root cause (needs Ben: DNS).** Measured 2026-06-10: 9KB thumbs from `pub-…r2.dev` take **6.8–9.6s on Cloudflare edge-cache misses** (~0.2s on hits; no `cf-cache-status` header — r2.dev is rate-limited + weakly cached by design, documented as not-for-production). With 17,974 cards the long tail is perpetual misses — this is why Other Versions / deep-catalog images crawl on all three platforms. Fix: attach a custom domain (e.g. `cdn.bobaplaybook.com`) to the `boba-card-images` bucket → full CDN caching. Blocker: R2 custom domains require the zone on Cloudflare DNS, and bobaplaybook.com's nameservers are at WordPress.com. Once DNS moves, flipping `CDN_BASE` is one line each in `CDN.swift` / `js/api.js` / Android CDN helper (never hardcoded, per DECISIONS.md #008). The iOS-side amplifiers (eager HStack, main-thread decode, per-render 17K filter) were fixed in v2.409. Do the domain move BEFORE the /full/ tier regen below so the new bytes land behind a real CDN.
- **R2 /full/ tier resolution upgrade** (Hero Shot pixelation root cause). v7.x ships Lanczos 2× upscale + PBR matte + mipmaps as a stopgap that masks the issue perceptually, but the authoritative fix is regenerating R2's `/full/` tier at higher resolution. Measured today: `/full/` serves cards at 477×667 (1-Maverick) to 745×1040 (1-LeBoss) — far smaller than CARD_SCHEMA's "≤1200px WebP" claim. At Hero Shot's 1080×1920 output, the card art is UPsampled 1.5-2.3× from source = "thumbnail blown up" look at push-climax frame.
  - **Pipeline**: re-run `unified-cards/scripts/reconcile_all.py::step11_optimize_images` with a new long-side cap (target 1500 or 2100). Requires Ben's local source images (per DECISIONS.md #011, not in repo). Storage delta on R2 ≈ 5-10× current `/full/` tier (~5-15 GB total). One-shot re-upload pass.
  - **Two paths**: (a) replace `/full/` in place — simpler, but invalidates Cloudflare edge cache for every card; (b) add a new `/uhd/` tier with `CDN.uhdURL()` helper + Hero Shot opt-in, fallback to `/full/` during rollout — safer.
  - **Payoff**: Hero Shot renders crisp at every camera distance, including a future Detail arc. Removes the need for Lanczos pre-upscale entirely; can revert to HouseOfCards' simpler texture loading.

---

## Feature Parity Status

> **Full parity matrix lives in [PARITY.md](./PARITY.md) (single source of truth).** The snapshot below is a quick scan of high-level feature areas. Detail rows for sub-features (per-tab anatomy, specific affordances) are in PARITY.md.

✅ Shipped | 🚧 In progress | ⏳ Planned | 🔮 Future | 🚫 Out of scope | n/a — inapplicable

| Feature | Web | iOS | Android | Notes |
|---|---|---|---|---|
| Find / Search | ✅ | ✅ | ⏳ M1 | All three platforms |
| App icon + branding | ✅ | ✅ | ⏳ M0 | Adaptive icon on Android (foreground + background + monochrome) |
| Mobile Safari layout | ✅ | n/a | n/a | Body flex column, no viewport-fit=cover |
| Collection | ✅ | ✅ | ⏳ M2 | All three platforms |
| Scan Mode (camera OCR) | 🚧 | ✅ | ✅ | iOS canonical (Vision); Android shipped (CameraX + ML Kit); web re-surfaced 2026-05-22 (DECISIONS.md #054) — fallback + desktop QR handoff + native-app gateway |
| Pricing comps | ✅ | ✅ | ⏳ M3 | Same Worker proxy, same waterfall |
| Buy Now (active listings) | ✅ | ✅ | ⏳ M3 | eBay + COMC; COMC Turnstile-blocked |
| Decks builder | ✅ | ✅ | ⏳ M4 | iOS Music-pattern pill + zoom; Android `ModalBottomSheet + sharedBounds`; web side-by-side desktop |
| Streamer Shows | ✅ | ✅ | ⏳ M2 | Role-gated, push destination |
| Find a Store | ✅ | ✅ | ⏳ M6 | MapKit / Leaflet / Google Maps Compose |
| Purchase view | ✅ | ✅ | ⏳ M6 | Find a Store + Upcoming Breaks (Whatnot) |
| Profile (username, sharing, role-request) | ✅ | ✅ | ⏳ M7 | Sign in with Google primary on Android (vs Sign in with Apple iOS) |
| Public collections (`/u/{username}`) | ✅ | n/a | ⏳ M7 | Web renders; iOS/Android set the toggle + deep-link in |
| Walkthroughs | 🚫 §11 | ✅ | 🚫 §6.10 | iOS-only; web + Android use EmptyState + tooltips |
| Hero Shot 3D | n/a | ✅ | 🚫 v1 | Filament port deferred |
| House of BoBA easter egg | n/a | ✅ | 🚫 v1 | RealityKit-specific |
| Personal Showcase | n/a | ✅ | 🚫 v1 | Cast SDK port deferred |
| Custom Rainbows | n/a | ✅ | ⏳ M2 | Web parity 🔮 |
| Practice executor | n/a | ✅ admin-gated | ⏳ M5.5 admin-gated | Both mobile platforms admin-gated per DECISIONS.md #033 + #048 |
| Trading (match alerts + Discord deep-link) | 🔮 Phase 1+ | 🔮 Phase 1+ | 🔮 Phase 1+ | TRADE-DESIGN.md governs all three |

**See [PARITY.md](./PARITY.md)** for the detail-level matrix (per-tab anatomy, auth surfaces, deep linking, notifications, payments, etc.).

---

## Milestones (active)

### ✅ Completed
M0 (setup), M1 (search), M2 (collection), M3/M3.5 (scan + pricing). Profile + Decks rebuild + Public collections (web) + Walkthroughs all shipped post-M3.5. Full notes in ARCHIVE.md.

### ✅ M4 — Purchase view
- **Upcoming Breaks** — done. Whatnot search at `boba-ebay-proxy.benwilkoff.workers.dev/whatnot/upcoming` (consolidated into the eBay worker, not a standalone). iOS uses `WhatnotShowsService`, web uses `js/purchase.js`.
- **Find a Store** — done (moved out of Collection).

### ❌ M5 — Discord Trading Channel (FUTURE)
Embed community trading channel. Research Discord Activity SDK vs WebView feasibility before committing.

---

## Android v1 Milestone Plan (2026)

Research + binding docs ratified 2026-05-19. All open questions resolved (DECISIONS.md #041–#052). See [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md), [`ANDROID-DEV.md`](./ANDROID-DEV.md), [`PARITY.md`](./PARITY.md).

**Resolved direction:**
- Package: `com.bobaplaybook.app`. Same monorepo, `/android/` at root.
- Firebase Spark (free) plan — new Android app under one BOBA Firebase project.
- **Tablet + Chromebook supported from M1** (Ben has Chromebook for early testing); foldable NOT v1.
- **Practice executor IS in v1, admin-gated** (M5.5).
- Sign in with Google primary; Sign in with Apple removed from Android.
- Discord = authentication only across all platforms (no bot until BoBA server permission).
- Subscription monetization, Personal Showcase, House of BoBA, Hero Shot all deferred post-v1.
- 3D path when prioritized: Filament (primary) / Vulkan via NDK.

### ✅ Android M0–M7 — Foundation through Auth (2026-05-19 → 2026-05-19)

**M0 through M7 shipped in a single rapid-pace session.** All eight milestones are at "fast-progress" state — screens render, build is green, key infrastructure (auth, scanning, navigation) is wired. Polish items called out in each milestone's commit message.

Final stack in production: Android Studio Panda 4 / AGP 9.2.0 / Kotlin 2.3.21 / Compose BOM 2026.05.00 / Material 3 / Hilt 2.59.2 / Coil 3.4.0 / Ktor 3.4.3 / supabase-kt 3.0.2 / CameraX 1.4 / ML Kit 16.0.1 / Credential Manager 1.3.0 / Firebase BOM 34.13.0.

**Shipped screens:** Find (search + filter + grid) · Card detail (canonical 6-cell stats) · Collection (designation segmented + sign-in prompt) · Scan (CameraX + ML Kit live OCR) · Decks (pool + summary bar) · Learn (category list + push) · Purchase (segmented Breaks/Stores) · Profile sheet (Sign in with Google via Credential Manager + supabase-kt).

**Deferred follow-ups (post-v1):**
- Material 3 Expressive APIs (FAB Menu / Floating Toolbar / Wavy Indicators) — needs compileSdk 37
- M3 SearchBar full-screen morph (Android Find uses stable M3 SearchBar; ExpandedFullScreenSearchBar variant pending)
- Tablet 3-pane Decks editor + NavigableListDetailPaneScaffold rollout (post-M7 polish)
- **Practice executor engine port** (M5.5 — admin-gated placeholder shipped; full state-machine port is multi-session)
- Tink-encrypted token storage (M7 polish — supabase-kt's default SessionManager used today)
- Image fingerprinting (MediaPipe) + multi-card grid scan (DECISIONS.md #043 — v2)

### ⏳ Android M4 — Decks (3-pane on tablet polish)
- **Tablet/Chromebook: `NavigableListDetailPaneScaffold` with 3 panes (saved decks / pool / editor)** — no hero-zoom, pane switching instead
- Drag-and-drop via `Modifier.dragAndDropSource` / `dragAndDropTarget`
- Container transform / `sharedBounds` hero zoom on the compact editor sheet
- (Card pool + DeckSummaryBar + Manage Decks / Rules / Legality push surfaces shipped tick 196+ audit)

### ⏳ Android M5.5 — Practice executor (admin-gated)
- Port iOS state-machine engine to pure Kotlin in `:core:domain` (`PersistentEffect`, `WeaponTransform`, `firePersistentTriggers`, `applyHDRecover` pipeline per DECISIONS.md #030)
- `PracticeView` + bench / plays / battle Composables
- Setup screen + tutorial overlay
- Active-battle UI with the 5 phases
- Admin gate via `user_profiles.role` lookup (mirrors iOS DECISIONS.md #033)
- Practice content stays admin-only at production; admins (Ben + close beta) test on Android device + Chromebook

### ✅ Android M6 — Purchase (shipped tick 202 + onward)
- Whatnot tile list + Google Maps Compose Find a Store + segmented picker all shipped. Tablet split-pane is the remaining nice-to-have.

### ⏳ Android M7 — Profile + Auth (mostly shipped, polish remaining)
- ✅ Credential Manager Sign in with Google · Email/password · Avatar upload · Account deletion · Universal Links / assetlinks · Public collection deep-link · Sign-in method pill · Discord-link state row
- ⏳ Discord OAuth via Auth Tab / Custom Tabs (stubbed; Google works)
- ⏳ Tink-encrypted DataStore for token storage (supabase-kt default today)
- ⏳ BiometricPrompt gate for sensitive Profile actions

### ⏳ Android M8 — Internal testing + Play Store closed track
- Play Console setup (Internal testing track)
- Data Safety form filled out
- Screenshots + feature graphic + listing assets
- Closed testing track with ≥12 testers × 14 days for production unlock (current Google requirement)
- 16 KB page-size validation via `apkanalyzer` on each release
- R8 + Baseline Profile validation
- Macrobenchmark cold-start regression gate in CI (≤ 5%)

### 🔮 Android Post-v1 Future
- Image fingerprinting (MediaPipe Image Embedder + parallel `feature-prints-android.bin`)
- Multi-card grid scanning (OpenCV port)
- Push notifications (FCM dispatcher via `boba-push-dispatcher` Worker; cross-platform symmetric payload per DECISIONS.md #045)
- Google Play Billing for BOBA Pro subscription (cross-platform launch with iOS + web)
- Personal Showcase + Cast SDK port
- House of BoBA + Hero Shot 3D port (Filament primary, raw Vulkan/NDK fallback per DECISIONS.md #051)
- Home-screen widgets via Glance API
- App Shortcuts + App Actions for Google Assistant integration
- Wear OS companion (if ever)
