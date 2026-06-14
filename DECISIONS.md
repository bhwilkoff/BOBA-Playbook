# BOBA Playbook — Architecture & Technology Decisions

Entries capture the *why* behind choices — not just what we decided but what principle it encodes. Technical details that anyone can read from the code don't belong here. The question every entry should answer: *what would the next developer get wrong if they didn't know this?*

---

> **Scope.** This file holds the decisions that still actively govern the code —
> the load-bearing "how to apply" rules. Superseded, foundational, and
> operational-tuning decisions live in [DECISIONS-ARCHIVE.md](./DECISIONS-ARCHIVE.md)
> (listed at the bottom of this file). When you write a new decision, add it
> here; move an entry to the archive once it's superseded or has fully baked into
> the codebase.

---

## 005 — Dual-Platform Feature Parity Model
*2026-04-03*
Both platforms implement the same core feature set. Platform-specific implementation is acceptable; platform-exclusive features are the exception, not the rule. Track parity in SCRATCHPAD.md.

## 007 — Supabase for Auth and User Data Only
*2026-04-03*
Supabase handles auth, `user_cards`, `decks`, `deck_cards`. Card catalog browsing uses static JSON — no DB query needed. **Supabase Storage is NOT used** — the free tier would exhaust quickly for a card image app.

## 008 — Cloudflare R2 for Image CDN
*2026-04-03*
Card images live on R2 (`boba-card-images`). Zero egress fees and Cloudflare edge caching. Two tiers: `thumbs/` (200px WebP, ~10KB) for grids; `full/` (≤1200px WebP, ~80KB) for detail views. **Never hardcode R2 URLs** — always use CDN helpers in `CDN.swift` / `js/api.js`.

## 010 — Element Color System
*2026-04-03 · amended 2026-05-25*
Each element maps to a canonical UI color: FIRE #FF4D00, ICE #00BFFF, HEX #8B00FF, STEEL #8A9BB0, BRAWL #C0392B, GLOW #FFD700, GUM #FF69B4, SUPER #FF00FF, ALT #B084CC, CYBER #39FF14, NONE #666680. Elements in cards.json are always UPPERCASE. Codified in `Design.swift::element(_:)`, `Color.kt::BobaElements`, and `styles.css` `:root --el-*`.

**ALT + CYBER added 2026-05-25** (bobaId v3 audit #057 surfaced 48 ALT + 28 CYBER cards). Neither is a traditional gameplay weapon — ALT is the weapon-slot value on parallels (Billy Cameo Alt Arts, Sidekicks, etc.), CYBER is the "2025 Cyber Promo" set — but both render in the weapon spot, so they need first-class color tokens. CYBER's neon green matches the promo art; ALT's lavender stays distinct from the other purple-family weapons (HEX, SUPER, GUM).

## 011 — No Card Images in Git
*2026-04-03*
Card images live exclusively on Cloudflare R2. `assets/data/` contains only JSON. Keeps clone fast and avoids GitHub's soft 1 GB storage limit.

## 012 — Scan Mode: On-Device Vision Only
*2026-04-03*
Card identification uses iOS Vision (`VNRecognizeTextRequest`) and AVFoundation only. No image is uploaded. Pipeline: OCR frame → card number regex `#?([A-Z]{1,6}-[A-Z]?\d{1,4}(?:[/-]\d{1,4})?)` → match display-cards.json. Falls back to manual search.

**Principle**: User data stays on user devices. On-device processing is not a technical constraint here — it's the right choice for the user.

## 020 — Web Layout: Body Flex Column, No viewport-fit=cover
*2026-04-04*
`body { height: 100dvh; display: flex; flex-direction: column; overflow: hidden }` with `main { flex: 1; overflow-y: auto; min-height: 0 }`. The body does not scroll — content scrolls inside `main`.

**Why**: `position: fixed` headers land in a separate GPU compositor layer that Safari browser-mode misorders during address-bar transitions, causing content to bleed into the Dynamic Island. Body flex-column keeps the header in document flow. Reference: `github.com/bhwilkoff/Bsky-Dreams`.

**Consequences**: No `viewport-fit=cover`, no `env(safe-area-inset-top)`. IntersectionObserver must use `root: document.getElementById('main-content')`.

## 023 — Mod Accounts: Role-Based Access via user_profiles
*2026-04-07*
Moderator roles live in a `user_profiles` Supabase table (`role`: user | moderator | admin). Role is never stored client-side permanently — fetched post-auth and cached in-memory for the session. Card corrections → `card_corrections`; image overrides → `card_image_overrides`; both require mod/admin role enforced by RLS. The catalog is static JSON, so corrections decouple user-submitted fixes from the release cycle.

## 025 — Feature Gating: Keep Code, Hide UI Entry Point
*2026-04-13*
When a feature is built but blocked on external dependencies (Discord trade room waiting on bot setup, eBay Market Feed waiting on API scope), keep all implementation code in place and gate at the single UI entry point. Don't delete or hollow out working code while waiting.

**Why**: Building ahead of infrastructure is sometimes unavoidable. Half-deleting code is worse — the feature is harder to re-enable and the codebase is ambiguous. A single `if featureEnabled { ... }` flag at the call site is the right level of intervention; re-enabling should be one-line. **Applied to**: Discord FAB in `CollectionView.swift` (commented call site, implementation intact); web `fab.hidden = true`.

## 026 — Image-Byte Collision Guard in Pipeline
*2026-04-13*
`reconcile_all.py::step11_optimize_images` ends with an md5-uniqueness check across the image tiers: any group of files resolving to different `(cardNumber, hero)` keys but sharing identical bytes is flagged to `image_collisions.json` with a per-tier remediation hint.

**Why**: the bobaId scheme enforces "One ID per Card" at the catalog layer, but nothing enforced "One Image per Card" at the CDN-payload layer. Caliber #24 once showed D-Harp's art — an optimizer run had silently overwritten Caliber's webp with D-Harp's bytes (cards.json was correct); only md5 comparison of the outputs catches this (a post-mortem found 35 such pairs).

**How to apply**: if `image_collisions.json` is written after a run, STOP — don't sync to R2 until every group is resolved. The `notes` field says whether to delete bad outputs and re-run step 11 (tier-level) or re-download source art (master-level); when correct art doesn't exist publicly, reclassify into the missing-art queue and let `ebay_missing_images.py` recover it.

**Principle**: Every invariant the app relies on should be enforced where it can be measured. "One Image per Card" lives in binary content, so the check runs against binary content.

## 027 — User-facing terminology: "Weapon" not "Element", "Treatment" not "Rarity"
*2026-04-23 → 2026-04-24*
The catalog field name is `element` (FIRE / ICE / STEEL / etc.); user-facing strings everywhere call it **Weapon**. The `treatment` field carries the print variant; user-facing strings call it **Treatment** — except the one Learn-tab section explicitly discussing *rarity by weapon type*, where "Rarity" is the right word.

**Why**: Every BoBA collector calls them weapons; "Element" is leftover schema language. "Rarity" is a TCG term that conflates two BoBA things: the hero's intrinsic scarcity (tied to weapon) and the print variant (the treatment). Splitting them matches the community vocabulary.

**How to apply**: Field names in code stay (`element`, `treatment`, `rarityLabel`, `rarityTier`). Anything rendered to a user uses Weapon and Treatment. The exceptions: the "RARITY BY WEAPON TYPE" Learn header (intentional) and internal helper names.

## 028 — Treatments vs Parallels are distinct concepts
*2026-04-24*
Sourced from BoBA-expert audit (Griffey checklist + official `bobattlearena.com/collecting-basics`).

**Treatments** are different ways a single card can be printed: Base Set, the Battlefoil family (seven color subsets), the themed foils (Blizzard, Alpha, Linoleum, Icon, Logofoil, Slime, etc.), Inspired Ink (= Serialized), and Superfoil. Each has a card-number prefix mapping to the treatment. **Parallels** are entirely separate card runs with their own numbering: Billy Cameo Alt Arts, SideKicks, Plays, Bonus Plays, Prize/Promos, Hot Dogs. **Inspired Ink = Serialized**, hand-stamped serial numbers tied to the hero's weapon: Hex /5, Glow /10, Fire /25, Ice /50.

**Why**: The prior "Parallels & Treatments" section bundled them, confusing new collectors. Splitting matches how veterans talk and the official taxonomy.

**How to apply**: Learn → Collect has separate "TREATMENTS" and "PARALLELS" sections; card-detail uses "Treatment" for the print variant. Future scrapes / corrections / Cowork handoffs must never collapse a Parallel into a Treatment in the catalog data.

## 029 — Card-detail canonical 6-cell layout
*2026-04-24*
Every card-detail surface (iOS view, web modal) renders the same 6-cell stat grid in a 2-column layout, in this exact reading order:

```
Card #     │ Type
Treatment  │ Weapon
Set        │ Sub-set
```

Card-type-specific extras (Cost + DBS for Plays) render BELOW the canonical 6 — never interleaved.

**Why**: A consistent layout means coaches find any field with one glance. "Same shape on every card" builds visual literacy with the catalog. Sealed products skip Treatment + Weapon; empty Sub-set renders as `—` rather than collapsing the row (which would shift everything beneath).

## 030 — Practice executor: persistent-effect engine architecture
*2026-04-24*
Two parallel state arrays on `PracticeStore`: `persistents` and `weaponTransforms` (split out so the hot-path weapon read consults a flat array). One entry point `installPersistent` routes specs into the right array; one dispatcher `firePersistentTriggers` fires non-continuous effects; every positive HD change routes through `applyHDRecover` (redirect → cap → delta → block, negative bypasses); one `isScopeActive` evaluator (unknown scopes return false — safe no-op).

**Why**: Centralizing install + lifecycle + scope eval in three helpers means future op families need only per-op behavior — plumbing is free.

## 031 — First-run hint system
*2026-04-24*
`HintsManager` (`@Observable`, UserDefaults-backed) tracks dismissed hint IDs per device. `HintBanner(id:title:message:)` renders nothing if dismissed OR the global toggle is off; tapping X dismisses permanently. Settings has a master toggle + "Reset hints".

**Why**: The teaching moments from the practice-battle UI (substitution positioning, deck composition triad, bonus play ceiling, etc.) need to surface at the right moment but never lecture experienced coaches twice. One-shot per device + global silence + reset gives full control without removing teaching value for newcomers.

**Inlined into `Design.swift`** rather than its own file — Xcode's synchronized-group sometimes fails to pick up new Swift files; co-locating with an existing target sidesteps it.

## 034 — COMC asking-price as second BUY NOW source (NOT in sold-comp waterfall)
*2026-04-29*
COMC.com exposes 931 BoBA listings matching cards.json. Wired as a parallel BUY NOW source alongside eBay actives (iOS `ComcService` + web `fetchComcListings`).

**Critical: COMC asking stays OUT of the sold-comp waterfall.** eBay sold → Market Est. measures TRANSACTED prices; asking runs ~10-25% above sold, so folding it in inflates the estimate. COMC is purely additive on BUY NOW (where to buy), not pricing (what it's worth); each row reads "COMC asking · Ungraded NM".

**Turnstile blocked.** COMC turned on a Cloudflare managed-JS challenge after recon; `boba-comc-proxy` detects `challenged: true`, returns `count: 0`, clients soft-fail. Bypass requires Browser Rendering API / Playwright. Defer until COMC's WAF stance changes (memory `feedback_comc_blocked_all_platforms`).

## 035 — Unified card recognition: image fingerprint primary, OCR as confirmation
*2026-04-30*
All five scan modes route through `ScanMatching.resolve(...)`. The prior design treated OCR cardNumber as primary, which silently failed when OCR returned a real-but-wrong number (partial "BHBF-37" arriving as "20" returned a real card at "20", no veto, wrong commit).

**Redesign:** image fingerprint (`feature-prints.bin`, 16,123 cards / 12.7 MB) is the primary identifier; every signal contributes candidates and scores: FP top-30 by L2 distance form the pool, refined by OCR cardNumber, hero name, and element/treatment/power. **Hero veto:** any candidate whose hero isn't in a clearly-named top-left set gets −2.0 (the missing piece the waterfall lacked). Confidence floor 1.4, margin floor 0.3 — below either, the resolver returns nil ("Not identified").

**Why FP primary:** OCR fails partially in success-looking ways (silent-wrong); FP fails completely in failure-looking ways (resolver returns nil; user retries). Silent-wrong is the worst possible UX for card recognition. (`GridCardDetector` also perspective-corrects from each anchor's quad with lane-spacing-sized bleed — fixed the prior ~22% under-detection; see `[[feedback_vision_rect_under_detection]]`.)

## 036 — Wall + Price Overlay: lift from streamer-only gate
*2026-05-03*
Per DESIGN.md §8.4 + §8.8, Wall display mode and Price Overlay become first-class for every collector — not streamer-gated. **Partially supersedes [#025](#025)** for these two features (the principle still applies to genuinely-blocked features like the Discord trade room).

**Lifts:** Wall is a Collection display mode + accessible from Decks ("Generate deck wall") + Find multi-select ("Wall these N cards"). Price Overlay is a Wall-view toggle with per-designation defaults (For Sale / Trade / Wanted ON; Grails + Personal OFF). `CollectionWallSheet` wraps `ShowWallComposer` (pure composer; gate was at invocation only).

**Stays gated to streamers:** Whatnot "My Shows" management; per-show wall generation inside the Shows tab; community trade room. **How to apply:** expose Wall + Price Overlay to all signed-in users; don't add new role gates.

## 037 — Profile redesign: username = display name = public handle
*2026-05-04*
Single `username` field doubles as display name AND public-collection slug (`bobaplaybook.com/u/{username}`). No separate `display_name` — two parallel name fields drift confusingly (Discord's conflation is the cautionary tale). iOS auto-derives from the email local-part (suffixes on collision); Discord-OAuth users with no email fall back to `user-{6-char-hash}`. Inline edit with debounced `check_username` → status pill.

**Banned-words gate, two layers:** (1) client `banned-words.json` (~270 entries) for an instant red pill, zero network; (2) server `banned_words` table as the authoritative gate via `check_username` / `set_username`. Reserved infra terms are gated separately.

**Why two layers:** usernames are public + persistent + a harassment vector. Cost of a slur on a public URL >> friction of "try ben2 instead." The server gate also protects from client-bundle drift.

## 039 — Profile redesign: deferred features
*2026-05-04*
Three Profile features ship with UI ahead of backend so the surface is complete:

**(a) Trade match alerts** — toggle persists to `user_profiles.match_alerts_enabled`; the matching pipeline (Wanted/Grail overlap → APNs fan-out) is multi-week, blocked on a server-side dispatcher.

**(b) Public collection sharing** — IMPLEMENTED 2026-05-04. Toggle on `user_profiles.public_collection_enabled`; web `bobaplaybook.com/u/{username}` live via `get_public_collection(handle)`. Projection excludes prices/notes and filters out Wanted (public = "what they have").

**(c) Account deletion** — IMPLEMENTED 2026-05-05. `boba-account-delete` Worker verifies a Bearer JWT then admin-DELETEs with a service-role secret. FK CASCADE clears user data; `card_corrections` / `card_image_overrides` SET NULL (audit trail survives anonymously).

**Why UI ahead of backend:** removing toggles later = worse UX; opt-in data is useful signal once backend ships; deletion is needed for App Store compliance.

## 041 — Android: Kotlin + Jetpack Compose (not KMP / CMP / Flutter / RN)
*2026-05-19*
Native Kotlin + Compose, separate from iOS Swift/SwiftUI, same monorepo (`/android/`). iOS is shipped Swift-native (#004); a KMP "common module" migration would mean rewriting iOS — we're not doing that.

**Why:** KMP works best when both platforms start together (BOBA didn't). CMP can't render the iOS-26 Liquid Glass surfaces the iOS DESIGN.md bets on. Flutter / RN add runtime + bridge overhead for every Android API (ML Kit, CameraX, Play Integrity, biometrics) — strictly worse for Android-only.

**Future option:** if Web wants typed models or Desktop arrives, KMP is the upgrade path — keep the door open by structuring Android's domain layer as pure-Kotlin from day one.

## 042 — Android: Material 3 brand-first; dynamic color opt-in
*2026-05-19*
Android ships a fixed brand theme (orange/cyan/violet on near-black) by default — not Material You dynamic color. User can opt into "Use system colors" in Settings.

**Why:** card-art palette is the focal point; a wallpaper-derived primary fighting `#FF4D00` reads muddy. Same rule as iOS §11.2: element on content semantics, brand on chrome. The opt-in toggle recolors `primary` only (Android 12+); element colors never change.

## 043 — Android Scan: CameraX + ML Kit Text Recognition v2 unbundled; OCR-only v1
*2026-05-19 · amended 2026-05-26*
CameraX 1.5+ + ML Kit Text Recognition v2 via Google Play Services dynamic delivery (`play-services-mlkit-text-recognition`). Manifest meta-data `com.google.mlkit.vision.DEPENDENCIES = "ocr"` triggers a one-time model download at install.

**Why OCR-only v1:** #035 made FP primary on iOS due to silent-wrong failure in **grid scan** specifically. Single-card live scan with OCR + hero-name veto + confidence threshold is sufficient. Adding FP needs MediaPipe + a parallel `feature-prints-android.bin` — defer to v2.

**Why unbundled (amended 2026-05-26):** the bundled artifact triggered a Play Console "missing debug symbols" warning (ML Kit ships `.so` pre-stripped → AGP's native-symbol task produces nothing). Unbundling removes the `.so` from the AAB (Play Services hosts them), shrinks it ~11 MB, eliminates the warning, and is a one-line swap in `libs.versions.toml`; API surface is identical (install still requires being online, so the "offline" trade-off was illusory).

**Residual warning:** other pre-stripped Google `.so` files remain; a Gradle task zips them into a BuildID-matched `native-debug-symbols.zip` (`finalizedBy bundleRelease`). ANDROID-DEV.md §6.

**Amended 2026-06-08 — embed the symbols IN the AAB, don't upload a zip.** The standalone zip can only be ingested via the Play Developer API (`edits.deobfuscationfiles.upload`, type `nativeCode`); that API is blocked for this account by the Play Console "API access" ACL issue, so the manual UI upload was the only route and it does not reliably take. Fix: `embedNativeDebugSymbols` (Gradle task, `finalizedBy bundleRelease` → `android/scripts/embed_native_debug_symbols.sh`) injects each `.so` as `BUNDLE-METADATA/com.android.tools.build.debugsymbols/<abi>/<lib>.so.dbg` (path + `.dbg` suffix confirmed against AGP's `ExtractNativeDebugMetadataTask.kt`) and re-signs with the upload key (jarsigner v1). Play reads symbols straight out of the uploaded bundle → warning never fires, **nothing is uploaded manually**. BuildID-only (stripped) symbols are accepted — verified, since the prior stripped zip cleared the warning. The zip task stays as a fallback artifact. **Load-bearing gotcha:** when injecting, use `zip -D` — AABs forbid directory zip entries, and Play reports that as a misleading "invalid signature" rejection (cost us v0.1.5). Verified the fixed bundle with `bundletool validate`. **How to apply:** never tell Ben to manually upload native symbols; the AAB is self-contained.

## 044 — Android: NO multi-step anchored walkthroughs
*2026-05-19*
Android doesn't ship the iOS-style multi-step walkthroughs (DESIGN.md §6.10). Use `TooltipBox` + `BOBAHintBanner` (DataStore-backed); empty states carry the first-time productive action.

**Why:** iOS walkthroughs exist because tab gestures / fullScreenCover / NavigationStack are novel idioms. Android conventions (NavigationBar / push-back / FAB / ModalBottomSheet) are universally legible; reproducing the ~600-line walkthrough engine in Compose for marginal value-add is wrong-side cost/value. Onboarding splash decks rejected. Revisit only if a future feature genuinely needs anchored teaching; each iOS walkthrough has a documented Android replacement in ANDROID-DESIGN.md §6.10.

## 045 — Cross-platform push: one dispatcher Worker, two transports
*2026-05-19*
When match-alerts ship (#039 + TRADE-DESIGN.md Phase 5), the architecture is **one Cloudflare Worker `boba-push-dispatcher`, two transports (APNs + FCM)**: triggered by a Supabase webhook or cron over `trade_matches`; joins `user_devices`; routes `apns` → HTTP/2 + JWT, `android` → FCM v1 + service-account token; both batch. The payload is **symmetric** — a `match_alert` type plus `match_id`, `other_user`, `card_count`, and a `deep_link` (`bobaplaybook://matches/{id}`) that is the identical string on both platforms.

**Why Worker not Edge Function:** better cold-start; existing secrets pattern; APNs JWT via Web Crypto, FCM v1 via plain HTTPS.

## 047 — Android v1 form-factor scope: phone + tablet + Chromebook (NO foldable)
*2026-05-19*
Adaptive layouts (size-class-aware scaffolds) are foundation from M1 — not deferred. **Foldable NOT a v1 target.**

**Why:** Ben has a Chromebook for testing; Chromebooks + tablets share the `EXPANDED` size class; foldables are a small share with significant hinge/posture cost. **How to apply:** ANDROID-DESIGN.md §6.6 binding from M1; every screen declares COMPACT / MEDIUM / EXPANDED (PRs without it rejected).

## 048 — Android: Practice executor IS in v1, admin-gated
*2026-05-19*
Practice executor (iOS #030 + #033) ships on Android v1, admin-gated via the same Profile-role-badge bolt-icon unlock.

**Why:** Ben wants to test Battle Practice on Android during development; the game logic is platform-agnostic (UI translation is the work); the admin gate hides it until ready. Reuse the iOS engine (#030) as pure Kotlin in `:core:domain`; Compose translates the SwiftUI screen anatomy.

## 049 — Discord integration: authentication only, NO bot
*2026-05-19*
Discord usage across iOS / web / Android is **strictly authentication-only** until BoBA Discord moderators explicitly authorize a bot. ✅ OAuth sign-in · storing `discord_user_id` · client-side `discord://users/{id}` deep-links. 🚫 No Bot SDK / server-side API calls · no reading/posting server content · no webhooks / Activities / WebViews beyond OAuth.

**Why:** the BoBA Discord server has its own moderators and contracts; a bot changes the social contract. **Trading implications:** TRADE-DESIGN.md §4 (pure introduction → Discord messaging) does NOT require a bot — "Open Discord" is a client-side deep-link URL.

## 051 — Android future 3D rendering: Filament (primary) or raw Vulkan/NDK
*2026-05-19*
If/when Hero Shot or House of BoBA ports to Android (currently deferred): **Filament** (primary) — Google's open-source PBR renderer, RealityKit-shaped API; **raw Vulkan via NDK** as fallback only if Filament's ceiling is hit. **Not Sceneform** (deprecated 2021) or Unity-as-library (wrong fit in a Compose app).

**Translation work when it happens:** `BOBACardEntity` → Filament `Material`/`MaterialInstance` + IBL; `PhysicsBodyComponent` (House of BoBA) → Bullet, since Filament ships no physics — significant additional work.

## 053 — No Twitter / X integration, ever
*2026-05-20*
BOBA will **never** ship Twitter / X integration across iOS / web / Android: no Twitter login, share intents (`twitter://post`, intent/tweet), `twitter:*` meta tags, embedded widgets, API consumption, follow buttons, or any Twitter-branded affordance.

**Why:** X is owned and editorially operated by a fascist. Integrating — even passively through metadata — signals endorsement and provides material support. BOBA won't direct any user, viewer, or brand element to that platform. **What still ships:** standard Open Graph (`og:*`), read by Discord / iMessage / Slack / Bluesky / Mastodon / Threads / and every other major link-preview consumer.

**How to apply:** reject PRs adding `twitter:*` meta tags, `twitter.com` URLs, Twitter SDK/API, share-to-Twitter buttons, or "tweet this" copy. Future Twitter-pattern features → Web Share API + OG protocol; gut any third-party template's Twitter integration first.

## 054 — Web Scan re-surfaced as fallback + native-app gateway
*2026-05-22*
Partially supersedes the web-side of [#012](#012). Scan on web is no longer "out of scope" — it's a sidebar destination with three jobs: (1) **camera-capture fallback** for users without the native apps (`getUserMedia` → frame → Worker OCR; functional but less performant); (2) **desktop → phone QR handoff** (desktop shows a QR encoding `?view=scan&rt={refresh_token}`; phone scans → opens BOBA with the desktop session); (3) **native-app gateway** (inline TestFlight + Google Play CTAs).

**Why the reversal:** beta testers asked for it; the web implementation already existed (only the sidebar entry had been removed), so restoring it cost nothing. The on-device-Vision principle from #012 still governs the **canonical** scanner — web is an *adjunct*, not a replacement.

**How to apply:** Web Scan IS in scope for iteration. Reuse `nativeAppCalloutHTML()` in `js/app.js` for *every* surface advertising the native apps. iOS Vision + Android ML Kit remain the canonical on-device scanners.

## 056 — Radish Price Guide integration removed (compliance request)
*2026-05-23*
On 2026-05-23 the Radish Price Guide owner + lead developer emailed that they consider BOBA a competing product and revoked authorization for Radish data, images, pricing, mapping, lookup logic, automated workflows, and partner/primary-source language. The ONE thing they remain comfortable with: "ordinary user-facing linking" where the user leaves BOBA to view info directly on Radish.

**What was removed** (full tick log in `RADISH_REMOVAL_LOOP.md`): every Radish fetch/resolver/scraper across Workers, clients, and pipeline; pricing replacement is now its own architecture (#058 — we generate our own sold-history rather than swap one third-party dependency for another). A backfill queue (`scripts/identify_radish_sourced_cards.py`) re-sources the 8,386 Radish-sourced images from BazookaVault.

**The one approved use case — per-card external link.** The email allowed "ordinary user-facing linking"; Ben confirmed direct card-links are within the spirit. Use the legacy frozen `card.radishUrl` field (acquired pre-email), falling back to `https://radishpriceguide.com` when null; "View on Radish" opens the system browser externally.

**Why principle-wise:** operating independently of any single third party is the load-bearing concern. **How to apply:** reject any PR adding a Radish reference (fetch, URL construction beyond the homepage fallback, alias table, lookup logic, source pill, partner language); the only permitted Radish code is the `card.radishUrl` per-card link + homepage fallback. Every other automation — sitemap pulls, HEAD probing, alias tables, runtime URL construction, Worker endpoints — stays deleted.

## 057 — bobaId formula v3 adds weapon as 5th field
*2026-05-25*
Extended the bobaId formula from 4 fields to 5 by appending the card's WEAPON (catalog field `element` per #027; the canonical term in prose is Weapon):

```python
# v3 (2026-05-25) — appended `element` (weapon) to the v2 4-field formula:
bobaId = f"{cardNumber}-{hero or name}-{treatment or ''}-{variation or ''}-{element or ''}"
```

**Why**: The card-art audit found many cards exist as FIRE-weapon + GLOW-weapon variant siblings sharing otherwise-identical (cardNumber, hero, treatment, variation), which collided on the v2 bobaId. The catalog had worked around it with distinct cardNumbers per variant — but that broke when 101 OCR-driven cardNumber merges would have produced true bobaId duplicates. Including weapon in the bobaId lets both weapon variants keep the same physical printed cardNumber without collision.

**Migration**: deterministic old→new mapping for all 17,974 cards, in lockstep across the 3 canonical formula sources (`boba_id.py`, `Card.swift`, `Card.kt`), the 5 catalog bundles, and every Supabase `boba_id` column + pipeline tables; feature-prints index rebuilds automatically. NOT changed: R2 image filenames (`imageFile` is a separate stored string — old keys stay valid) and pipeline staging identifiers (distinct `Auto`-suffix workflow tokens).

**How to apply**: any code reading/writing a bobaId uses the 5-field formula; the three canonical sources share one shape — never redefine inline. A 6th disambiguator (v3 verified zero collisions) repeats this shape: new field at the end, deterministic catalog → mapping table → Supabase UPDATEs.

## 058 — Pricing is provenance-honest; we generate our own sold data
*2026-05-27*

The post-Radish, post-Marketplace-Insights pricing architecture (full build log + per-tier rules: PRICING_PLAYBOOK.md; UI rules: DESIGN.md §8.7 · WEB-DESIGN.md §14.6 · ANDROID-DESIGN.md §8.7, which cite this entry). eBay Marketplace Insights (sold comps) is permanently unavailable — it has rejected applicants for years — so any pipeline depending on a third party for sold data is structurally broken. Supersedes Radish-era #013; generalizes COMC's asks-out-of-waterfall rule (#034) to *every* asking source.

**Principle — provenance is the contract.** Every price states what KIND of data it is; we NEVER present an asking price or derived guess as "what it's worth" (asks run 10-25% above transacted → folding them in silently inflates every card). The most-specific *honestly-labeled* signal wins, in order: (1) **Recent Sales** — transacted comps, each with a source pill (eBay/Whatnot vanish-inferred · community); (2) **Listed Range** — with NO sold data, the active listings ARE the honest signal ("N active · no recent sales yet"), never a fabricated "Market Est."; (3) **Buy Now** — active asks (eBay + COMC + Whatnot), additive, never in a sold number; (4) **Estimate** — the comparability estimator, only when labeled AND fed real comps.

**Why we generate our own data.** No external API gives us sold comps, so `boba-pricing-tracker` snapshots public *active* listings (eBay + Whatnot) into D1 and infers "sold @ last-seen price" + confidence when a listing **vanishes** from a later snapshot (~60 days → a sold-history we own); plus community comps (Tier 3) and the `boba-price-estimator` over our own catalog. All real sold signals merge through one endpoint (`/comps`); asking sources never enter it.

**Match precision is load-bearing — "one card, one bobaId, one price"** (`workers/ebay-proxy/worker.js`): eBay sold requires exact card-number AND hero (partial/hero-only → dropped); **weapon-conflict** reject (FIRE vs GLOW share a cardNumber, #057); **treatment-conflict** reject (Base Set rejects Battlefoil/Inspired/etc.); **ordinal exclusion** ("1" ≠ "1st Edition") + **prefixed-number guard** ("1" ≠ "#OHBF-1"). **Whatnot is adaptive** — sellers title by card NUMBER *or* POWER, so a listing matches on EITHER, same weapon/treatment gates.

**How to apply.** Reject any PR that (a) presents an asking/estimator number as market value without real sold data, (b) folds asks into a sold/value figure, or (c) loosens a match gate so another card's listings count. New *asking* sources → Buy Now / Listed Range; new *sold* sources → `/comps`.

## 060 — Pricing time-window picker removed; fixed days everywhere
*2026-05-28*

The 7/30/90 day-window picker on iOS + web (`@State selectedDays` / `let days = 30`) is removed. All three platforms now send fixed Worker params: `days=90` for the eBay Worker call, `days=365` for `/comps` on the tracker. The picker's slot in the pricing-section header becomes the **Refresh button** (iOS got it new; web kept it; Android already had it).

**Why removed.** The picker had two structural problems and zero functional value:

1. **Misleading scope.** Visually it appeared to control the whole pricing panel, but it ONLY set the `days` query param on the eBay Worker call — which controls the **Marketplace Insights sold-comp lookback window**. Active eBay listings + Whatnot asks + the `/comps` (tracker) endpoint are NOT affected by it; they're either inherently current (active asks) or use a separately-defaulted window (`/comps` defaults to 365 days, picker-independent on all three platforms). Ben's audit (#104 Superbaby Ice, 2026-05-28): *"if there are current/active ebay or whatnot listings, it doesn't really matter when they were posted, right?"* — exactly right; active asks have no meaningful time dimension.

2. **Vestigial functionality.** Marketplace Insights production access is permanently unavailable (DECISIONS.md #058) — the application has been universally denied for 5+ years. So the ONE thing the picker controlled (MI sold-comp window) is always empty. The user-facing affordance was operating on a signal that doesn't exist.

3. **Cache-key divergence.** Worse, the Worker's 6-hour response cache is keyed by `(card_params, days)` — and iOS sent `days=30`, Android sent `days=90`, web sent `days=30`. Different platforms hit different cache buckets and saw different active-listing counts for the same card at the same moment. Ben's report: iOS showed 1, web showed 2, Android showed 11 for the same #104 Superbaby Ice. The underlying eBay state was identical — divergent `days` values produced divergent cache snapshots.

**Principle — every user-visible affordance must control something real.** A picker that visually scopes a panel but actually only filters an empty data source isn't a "no-op control," it's a trust-erosion device. The user reads the panel under the picker's apparent scope and forms a wrong mental model. (Web `:has()`-style "decorative" controls are not in this category — they're inert and read as inert. A segmented picker mid-panel reads as load-bearing.) When picker-controlled data becomes meaningful again (volume of real sold comps justifies scoping), re-add as **Recent Sales · 30d ▼** scoped inside the Recent Sales section header — not floating at the top scoping the whole panel.

**How to apply.** Reject any PR re-introducing a global pricing-panel time picker. Filter time-scope per signal: Recent Sales rows ALREADY carry per-row `soldAt` dates (eBay-inferred / Whatnot / community) — the user reads freshness off the rows. Active listings show their `count` and source; no time dimension needed. New asking/sold sources inherit the fixed `days=90` (eBay) / `days=365` (`/comps`) defaults; never wire them to a user-facing global picker. Refresh button stays — bypasses the Worker cache + Supabase 24h snapshot so users can force-pull live data (DECISIONS.md #013 + PARITY.md §8).

## 061 — Rarity values come from card art (OCR), never from client-side inference
*2026-05-28*

Retires the weapon→print-run table in DECISIONS.md #028. The catalog now carries a per-card `printRun` field populated by card-art OCR for the 464 numbered cards in the catalog (PRICING_PLAYBOOK §6.4 Feature 0). That field — never any client-side inference — is the only valid source for the user-facing print-run label. Two specific overlay surfaces (`print-run-cell-badge` + treatment-ribbon on web; `PrintRunBadge` + `FormatLegalityHintBadge` on iOS/Android cells; "version-print-run" on Other Versions tiles) are removed entirely. The only on-card-art overlay allowed anywhere is Collection's price chip (DESIGN.md §8.8 / DECISIONS.md #036).

**Principle — rarity is a fact about a physical card, not a guess from its other attributes.** The #028-era assumption "Inspired Ink Hex = /5, Glow = /10, Fire = /25, Ice = /50" treated weapon as a print-run proxy. Card-art OCR proved this wrong at scale: **FIRE and ICE each appear at BOTH /5 AND /50** in the real per-card data, and 174 FIRE cards have a real `printRun ≠ 25` (the inferred mapping). Shipping the inferred number meant 174+ FIRE cards rendered the wrong scarcity at every grid cell + every Other Versions tile + every card-detail chip — silently, with no flag to the user that they were reading a guess instead of a fact. The OCR work corrected the data; the client renderers continued reading the stale inference. This entry closes the loop: derived rarity is banned, only OCR-populated `printRun` displays.

**Why removed entirely from card art** (not just "fixed to use real data"). Ben's directive 2026-05-28 — *"no card overlays on the cards other than the pricing overlay on the grid view for the collection tab"* — applies even when the data is correct. Card art is the focal point of every grid (CLAUDE.md "Why We Build" + DESIGN.md §1.5). Overlays compete with art. The art-clean grid is the binding rule; rarity information lives in the card-detail stats grid (DECISIONS.md #029) where labels are explicit, not corner-badge guesses. The "Other Versions" disambiguator is the treatment label below the thumb, not a chip on the thumb.

**Why `printRunLabel` is kept as a computed property at all.** The card-detail surface still renders the chip when present (`/5`, `/10`, `/25`, or `/50`) — but only for the 464 cards with real OCR data, and only in the labeled stats area, not as an overlay. The computed property is now a thin wrapper: `printRun?.let { "/$it" }` on Android/iOS, `card.printRun ? "/" + card.printRun : null` on web. The prior weapon-switch + Superfoil→SSP derivation is gone. SSP went too because "Superfoil" is a treatment label, not a card-art-OCR scarcity number; the treatment field already names it in the canonical 6-cell grid.

**How to apply.** Reject any PR that (a) infers a print-run label from weapon, treatment, or any other catalog field (rarity from OCR `printRun` only; nothing else); (b) renders any overlay on card art outside the Collection price chip (treatment ribbon, print-run badge, format-legality hint, ownership pip-on-art, etc. — all out); (c) re-introduces `getCardRarity` / `rarityTier`-style hardcoded-derivation helpers (the web dead-code one was removed in this entry). New rarity-relevant data → catalog field → client reads field. New visual decoration → outside the card image (caption below, stats grid in detail, etc.).

---

## 066 — iOS 27 adopted additively above an iOS 26 deployment floor
*2026-06-14*

The app builds against the iOS 27 SDK (`SDKROOT = iphoneos27.0`) but keeps `IPHONEOS_DEPLOYMENT_TARGET = 26.4` through fall 2026, because real device share stays meaningfully on iOS 26 until then. So **every iOS-27-only API is adopted additively behind `if #available(iOS 27, *)`, with the iOS 26 behavior preserved as the fallback** — never as a hard floor bump, never as an unconditional call (which fails type-check on the deployment target).

**Principle — newest-OS polish must never cut off the prior-OS user.** A companion app's job is to be in the collector's hand at the table; a release that demands the just-shipped OS strands the majority mid-season. iOS 27 is a *finish*, not a *gate*. The same rule that governs feature parity across platforms (#005) governs OS versions within iOS: pick the native idiom for the newest OS, degrade gracefully on the older one.

**The gate lives in one place.** View-level adoptions route through `Components/iOS27Compat.swift` wrappers (`bobaMinimizeNavBarOnScroll`, `bobaSharedImageCache`, `bobaSwipeActionsContainer`, `bobaItemAlert`) so the `#available` check isn't copy-pasted across call sites; the helper returns `self` unchanged on iOS 26. `ToolbarContent`-level adoptions (`topBarPinnedTrailing`, `contentMarginsRemoved`) can't be a generic modifier, so they're gated inline by branching the `ToolbarItem` around an extracted button builder.

**What was adopted (v2.414):** `toolbarMinimizeBehavior(.onScrollDown)` on the Find / Collection / Decks dense grids; `contentMarginsRemoved()` on the Find profile avatar (the native answer to the v2.412/2.413 fill-the-button work); `topBarPinnedTrailing` on the primary Add action of both card-detail surfaces (survives large Dynamic Type when Mod-edit / Share / Hero-Shot compete); `alert(_:item:)` on the six optional-driven alerts; `asyncImageURLSession` routing every non-card `AsyncImage` through the shared 100/500 MB `URLCache`; `swipeActionsContainer()` to make the Collection card-detail copies-list swipe-to-delete actually fire (it was a silent no-op pre-27 — those rows are a `VStack`, not a `List`). Plus a non-gated cleanup: `LocationPermissionManager` migrated `ObservableObject` → `@Observable` (last legacy observer in the app; `Combine` import dropped).

**Judgment calls — adopt only where there's a real problem to solve.** Three identified APIs were deliberately NOT forced, because forcing them would regress UX or add speculative surface (clarity over cleverness, "fix only the bug"):
- **`ToolbarOverflowMenu` was NOT swapped in for the hand-rolled `⋯` menus.** Those menus carry active-filter-count badges and custom glyphs that the system overflow affordance erases, and the bars don't actually overflow at default sizes — the existing menus are already DESIGN.md §6.9-compliant. `visibilityPriority` was likewise skipped where items already fit.
- **Deck-card `reorderable()` was NOT added.** The deck editor presents heroes *grouped/sorted by power* (a computed order) with no persisted or gameplay-meaningful free order, so drag-reorder has no semantic home and would fight the power grouping. The SCRATCHPAD "iPad drag between deck slots" item stays deferred as the nice-to-have it was classed as.
- **The live Vision OCR scanner was NOT rewritten** to the async `RecognizeTextRequest` API. `VNRecognizeTextRequest` is not deprecated on iOS 27; the live path is a tuned multi-request synchronous pass on a core, camera-dependent feature that can't be validated without a device — rewriting it blind violates the debugging philosophy ("do not iterate blindly on behavior you cannot observe"). Revisit on-device.

**How to apply.** New iOS-27 API → add a gated wrapper to `iOS27Compat.swift` (or branch the `ToolbarItem` inline) with the iOS 26 fallback; never an unconditional call while the floor is 26.x. When the deployment floor eventually rises to 27, delete the `else` branches and inline the new APIs. Don't adopt a newest-OS API that regresses an existing affordance (badges, custom glyphs) or invents a feature with no backing semantics just because the API exists.

---

## Archived decisions

Moved to [DECISIONS-ARCHIVE.md](./DECISIONS-ARCHIVE.md) — superseded, foundational, or
operational-detail. Numbers are stable; cross-references resolve by number.

- **001 — Vanilla HTML/CSS/JS for Web**
- **002 — Xcode Project at Repository Root**
- **003 — Shared Version Config (xcconfig)**
- **004 — SwiftUI + @Observable + SwiftData (iOS)**
- **006 — App Name and Brand Identity**
- **009 — Static Card Catalog JSON**
- **013 — Pricing Comps Strategy**
- **014 — iOS Card Catalog: Two-Phase Progressive Loading**
- **015 — imageAvailable Flag Bypass**
- **016 — Section Named "Play" Not "Rules"**
- **017 — Web Filter Panel: Mobile Collapsible, Desktop Persistent**
- **018 — PWA GitHub Pages 404 Handling**
- **019 — App Icon: XOXO Playbook Mark**
- **021 — Play Mode: Static Reference Content, Supabase for User Decks**
- **022 — SwiftUI ScrollView Width: VStack Parent Must Have frame(maxWidth: .infinity)**
- **024 — iOS Image Loading: Show Thumb Immediately While Full Loads**
- **032 — iOS home-screen display name: "Playbook" not "BOBA Playbook"**
- **033 — Open questions deferred to BoBA / real-world data**
- **038 — Profile redesign: generalized role-request (mod OR streamer)**
- **040 — Profile pictures: Discord-default, R2-on-upload**
- **046 — Android-specific app ID + signing strategy**
- **050 — Android: Sign in with Apple is NOT offered**
- **052 — Firebase: stay on Spark (free) plan**
- **055 — Android scan: multi-pathway OCR recovery for shiny / holographic cards**
- **059 — Pricing UI parity: unified labels, slim-catalog carries radishUrl**
- **062 — Pricing parity is verified end-to-end, not "the function exists"**
- **063 — Estimator tier-locks SUPER (1-of-1) cards to same-tier comps**
- **063 amendment (2026-05-29) — Super estimator emits hedged range, not silent**
- **063 amendment 2 (2026-05-29) — Estimator audit framework**
- **064 — Estimator strict-treatment matching + Whatnot title-parsed synthetics**
- **064 amendment (2026-05-29) — Strict-weapon for tier-4 + weapon-tier extrapolated fallback**
- **065 — Daily pricing automation: GitHub Actions ONLY (no laptop dependency), NOT Cloudflare Worker cron**
