# Deferred features audit — 2026-05-20

Sources scanned: SCRATCHPAD.md, PARITY.md, DECISIONS.md, DESIGN.md,
WEB-DESIGN.md, ANDROID-DESIGN.md, TRADE-DESIGN.md, ARCHIVE.md,
COWORK.md, and code-comment TODOs.

Notes on what's NOT here: items already in §12 / §17 "Out of scope"
of the design docs (walkthroughs on web+Android, Cmd-K, web push,
COMC, custom-domain branding, foldable optimization, Mac Catalyst,
PWA Badging) are intentionally excluded — these are accepted
non-targets, not "deferred". Same for hard-blocked items (OKC art
sourcing, R2 /full/ regen — both need Ben's local source images;
Practice IP review — needs BoBA team; LA-20 anomaly — needs BoBA).

---

## Trivial (< 30 min each)

| # | Title | Source | Platforms | Notes |
|---|---|---|---|---|
| 1 | Web parity: per-tab grid density tokens audit | SCRATCHPAD.md:78 "Web parity batches 1+2" | web | "already in parity" claim — verify and close |
| 2 | Web parity: Weapon/Treatment terminology audit | SCRATCHPAD.md:78 | web | DECISIONS.md #027 — confirm no "Rarity" leakage outside Learn-collect |
| 3 | Web parity: offline indicator visible parity | SCRATCHPAD.md:78 | web | iOS has BOBAOfflinePill; verify web equiv lives |
| 4 | DeckBuilderStore.swift:1007 TODO — verify end-to-end | code TODO | iOS | One known iOS Swift TODO in active code |
| 5 | scripts/build_radish_url_map.py TODO | code TODO | tools | Per RADISH_PARTNERSHIP_CALL.md §8 |
| 6 | Sealed set normalization ("Alpha Edition" → "Alpha" filter incl.) | SCRATCHPAD.md (Cowork notes) | web + iOS | UX micro-decision; flagged for future pass |
| 7 | Compat shim removal: `submit_mod_request` / `get_pending_mod_requests` / `review_mod_request` | DECISIONS.md #038 | backend | "should be dropped in the next release" |
| 8 | "Bulk-add" Android stubs (Find multi-select) | PARITY.md:54 (🔮) | android | iOS already mobile uses long-press; web has it |

## Low (30-90 min each)

| # | Title | Source | Platforms | Notes |
|---|---|---|---|---|
| 9 | Web parity: sign-in method pill on Profile | SCRATCHPAD.md:78; PARITY.md:185 | web | iOS already ships; mirror on web Profile |
| 10 | Web parity: Terms link on Profile | SCRATCHPAD.md:78 | web | https://bobaplaybook.com/terms/ link in Profile section |
| 11 | Web parity: generalized role request (mod OR streamer) | SCRATCHPAD.md:78; DECISIONS.md #038 | web | iOS uses `request_role` RPC; web admin queue surface needs same call |
| 12 | Web parity: Delete Account button | SCRATCHPAD.md:78 | web | Worker shipped (`boba-account-delete`); web UI deferred |
| 13 | Web parity: username inline edit | SCRATCHPAD.md:78 | web | iOS has it; web Profile lacks |
| 14 | Web parity: Custom Rainbows (display + progress) | PARITY.md:106-107 (🔮) | web | iOS shipped v2.219-v2.221; web read-only render is doable; editor deferred |
| 15 | Web parity: Value history chart | PARITY.md:105 (🔮) | web | iOS push destination exists |
| 16 | Web parity: Wall view + Price Overlay | PARITY.md:109-110 (⏳ M-future) | web | DECISIONS.md #036 lifted gate; iOS shipped |
| 17 | iPad: scan-view landscape guide scaling | SCRATCHPAD.md:74 "Deferred iPad work" | iOS | `kGuideW=300, kGuideH=420` scale for regular width |
| 18 | iPad: 3-column Decks (saved-decks sidebar) | SCRATCHPAD.md:56 | iOS | Currently 2-column; saved-decks sidebar deferred as additive polish |
| 19 | iPad: walkthrough anchor verification | SCRATCHPAD.md:72 | iOS | Simulator validation across NavigationSplitView |
| 20 | Mod corrections: in-app cropper edge cases follow-up | DECISIONS.md / project_mod_add_card | iOS | After v2.218 5-iteration UIKit landing — light polish |

## Medium (3-8 hr each)

| # | Title | Source | Platforms | Notes |
|---|---|---|---|---|
| 21 | iPad drag-and-drop polish (Find↔Decks↔Collection) | SCRATCHPAD.md:73 | iOS | "Significant work; nice-to-have" — base drop wired |
| 22 | Android M1 polish: Container transform / sharedBounds | SCRATCHPAD.md "Deferred follow-ups (post-v1)" | android | Hero zoom into card detail |
| 23 | Android M1 polish: M3 SearchBar full-screen morph | SCRATCHPAD.md (deferred) | android | Currently uses OutlinedTextField |
| 24 | Android M2 polish: Custom Rainbows editor | SCRATCHPAD.md; PARITY.md:106 | android | Mirror iOS v2.219+ |
| 25 | Android M2 polish: Wall view + share | SCRATCHPAD.md; PARITY.md:109 | android | DECISIONS.md #036 |
| 26 | Android M2 polish: My Shows (streamer-gated push) | SCRATCHPAD.md | android | Role-gated lens |
| 27 | Android M5 polish: Article corpus port from iOS Swift | SCRATCHPAD.md "Deferred follow-ups" | android | Content port from iOS Learn |
| 28 | Android M6 polish: Whatnot tile list wiring | SCRATCHPAD.md | android | Worker call exists (`/whatnot/upcoming`); UI wires up |
| 29 | Android M6 polish: Google Maps Find a Store | SCRATCHPAD.md | android | Needs Maps API key + Compose Maps |
| 30 | Android M7 polish: Discord OAuth via Auth Tab / Custom Tabs | SCRATCHPAD.md | android | Sign in with Google is wired; Discord path stubbed |
| 31 | Android M7 polish: Tink-encrypted DataStore for token storage | SCRATCHPAD.md | android | supabase-kt default SessionManager today |
| 32 | Android M7 polish: BiometricPrompt gate for sensitive actions | PARITY.md:173 | android | iOS Face ID parity |
| 33 | Android M7 polish: Passkey support surfacing | PARITY.md:172 | android+iOS+web | Credential Manager bottom-sheet on Android (free), iOS via ASAuthorization |
| 34 | Android polish: 16 KB page size validation | PARITY.md:302 | android | Required for Play Store; apkanalyzer check |
| 35 | Android polish: App Shortcuts (long-press icon) | PARITY.md:299 (⏳ M7) | android | shortcuts + AppActions |
| 36 | Per-designation public-collection toggles | DECISIONS.md #039 (deferred) | web+iOS | Today is global toggle; per-designation deferred |
| 37 | Wanted-as-WTB public list opt-in surface | DECISIONS.md #039 | web+iOS | "needs its own opt-in surface" |
| 38 | Android polish: Material 3 Expressive APIs (FAB Menu, Floating Toolbar, Wavy Indicators) | SCRATCHPAD.md "Deferred follow-ups" | android | compileSdk 37 bump done; APIs ready |
| 39 | Power audit follow-up (sibling-outlier valid-but-wrong powers) | memory: project_power_audit_followup | pipeline | After v2.223; catch values OCR landed on by chance |
| 40 | Cmd-1..5 keyboard shortcuts parity on iPad/Mac Catalyst | SCRATCHPAD.md (iPad shipped) | iOS | Already shipped on iPad; verify Catalyst path |

## High (multi-day each)

| # | Title | Source | Platforms | Notes |
|---|---|---|---|---|
| 41 | TRADE Phase 1: trade_matches table + match-detection cron + user_blocks + Profile Trading section | TRADE-DESIGN.md §9 (~3 days) | iOS+web+android | Backend + Profile UI |
| 42 | TRADE Phase 2: Match list view (iOS + web) | TRADE-DESIGN.md §9 (~4 days) | iOS+web | New top-level surface |
| 43 | TRADE Phase 3: Block + Report flows + EU geo-block on trading endpoints | TRADE-DESIGN.md §9 (~2 days) | iOS+web+android+Worker | Apple §1.2 minimum-viable controls |
| 44 | TRADE Phase 0: ToS + Privacy Policy customization (clauses 4, 7, 8) | TRADE-DESIGN.md §5.2 (~1 day) | docs | Gates Phase 1+; templates per §5.1 |
| 45 | Android M4 polish: Tablet 3-pane Decks + NavigableListDetailPaneScaffold rollout | SCRATCHPAD.md | android | Beyond current functional scaffolding |
| 46 | Android M5.5: Practice executor engine port | SCRATCHPAD.md; DECISIONS.md #048 | android | "multi-session" state machine port to :core:domain |
| 47 | Wall + Price Overlay parity on web (incl. share render) | PARITY.md:109-110 | web | iOS canonical; web M-future |
| 48 | Public collection: Custom Rainbow surfacing on `/u/{slug}` | PARITY.md:113 + #036 lift | web | Today web lacks; iOS has source data |

## Very high (multi-week — likely not ship-this-session)

| # | Title | Source | Platforms | Notes |
|---|---|---|---|---|
| 49 | TRADE Phase 4: Apple IAP + web Stripe subscription (BOBA Pro) | TRADE-DESIGN.md §9 (~5 days) | iOS+web+android | Pro tier gates push notifications |
| 50 | TRADE Phase 5: APNs match-notification dispatcher (Pro-gated) | TRADE-DESIGN.md §9 (~5 days); DECISIONS.md #045 | iOS+android+Worker | `boba-push-dispatcher` Worker; one dispatcher, two transports |
| 51 | Cross-platform push dispatcher (FCM + APNs unified) | DECISIONS.md #045; PARITY.md:208 | iOS+android+Worker | Architecture decided; implementation post-IAP |
| 52 | Notification channels + permission flows (Android-specific) | PARITY.md:206-207 | android | Per-channel (match/breaking/trade) |
| 53 | Cross-platform subscription state sync (user_subscriptions table + webhooks) | PARITY.md:221 | backend | Apple + Google webhooks |
| 54 | R2 /full/ tier resolution upgrade (Hero Shot crispness) | SCRATCHPAD.md:104 Open Questions | pipeline | Needs Ben's local source images (not in repo) |
| 55 | Image fingerprinting on Android (MediaPipe Image Embedder) | DECISIONS.md #043; PARITY.md:135 | android | "Defer to v2" |
| 56 | Multi-card grid scan on Android (OpenCV port) | DECISIONS.md #043; PARITY.md:136 | android | v2 |
| 57 | Personal Showcase + Cast SDK port to Android | PARITY.md:111-112; DECISIONS.md #051 | android | Filament/raw Vulkan path documented |
| 58 | House of BoBA port to Android | DECISIONS.md #051 | android | RealityKit→Filament physics is multi-week |
| 59 | Hero Shot 3D port to Android | DECISIONS.md #051; PARITY.md:258 | android | Filament primary |
| 60 | Web public-collection mobile parity for Match list | TRADE Phase 2 follow | web | After core trade UI |
| 61 | Live Activities / Dynamic Island | PARITY.md:286 | iOS | 🔮; future iOS-specific affordance |
| 62 | Play Integrity API server verification | PARITY.md:303 | android | Mirrors iOS App Attest; deferred on both |

---

## Top 10 ship-now recommendations

For an autonomous loop with ~2-4 hours of total runtime, ordered by
value-to-effort and minimal cross-cutting risk:

1. **#7 Drop compat shims** (`submit_mod_request` etc.) — DECISIONS.md
   #038 explicitly says "should be dropped in the next release."
   One-file SQL migration. Reduces surface area before more mod work.

2. **#4 + #5 Resolve the two known code TODOs** —
   `DeckBuilderStore.swift:1007` and `scripts/build_radish_url_map.py`.
   Either close or convert to issues; clears the in-code clutter.

3. **#9 Web parity: sign-in method pill on Profile** — Trivial-to-low
   effort, ships visible parity with iOS. Memory rule
   `feedback_always_ensure_web_parity` is explicit.

4. **#10 + #11 + #12 + #13 Web Profile parity quartet** (Terms link,
   generalized role request, Delete Account button, username inline
   edit) — these are documented as already-deferred parity gaps with
   iOS shipped. Each is low effort; together they close out the
   SCRATCHPAD.md "Web parity batches 1+2" list.

5. **#1 + #2 + #3 Web parity audits** (grid density, terminology,
   offline indicator) — SCRATCHPAD.md asserts these are "already in
   parity"; verify with grep + confirm. Cheap to close; valuable to
   leave verified.

6. **#39 Power audit follow-up** — memory:project_power_audit_followup
   has the methodology. After v2.223's truth-from-image cleanup of
   `power % 5 != 0` cases, this is the natural next sweep:
   sibling-outlier detection for valid-but-wrong powers. Pipeline
   script + manual review.

7. **#14 Web Custom Rainbows (read-only render)** — iOS ships
   v2.219-v2.221; web parity is 🔮 today. Read-only render of
   `user_custom_rainbows` rows on the existing collection page is
   medium effort and unlocks #48 (public Custom Rainbows).

8. **#33 + #32 Passkey + Biometric surfacing** — Credential Manager
   bottom sheet is free on Android once Sign in with Google is wired
   (already done); iOS biometric gate already exists. Surfacing on
   web via WebAuthn is the larger piece; iOS+Android surfacing is
   straightforward.

9. **#17 + #18 + #19 iPad polish trio** — scan-view guide scaling
   (low), walkthrough anchor verification (low), 3-column Decks
   (low-medium). All flagged as "additive polish" with the
   foundation already shipped.

10. **#15 + #16 Wall view + Price Overlay on web** — DECISIONS.md
    #036 lifted the streamer-only gate. iOS has shipped; web is
    📅 M-future. Mirror the iOS toolbar Menu + render path. Medium
    effort but high visible-parity payoff per the parity rule.

**Explicitly NOT recommended for the loop:**
- Anything in TRADE Phases 1-5 (#41-#50) without Ben review — design
  has $0-cost constraints and ToS gates (#44 Phase 0) that need his
  sign-off before code lands.
- R2 /full/ regen (#54) — needs Ben's local source images.
- Power audit (#39) sweep that *changes* card data without
  truth-from-image verification — `feedback_card_data_truth_from_image`
  is an explicit don't-repeat.
- Anything that touches money flow (TRADE §2 hard rule).
- Practice executor IP review (admin-gated; no timeline).
