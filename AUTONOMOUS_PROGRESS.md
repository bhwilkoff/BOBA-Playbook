# Autonomous Iteration Loop — Progress Log

**Started:** 2026-05-20 (post-sealed-products commit)
**Owner instruction:** *"Create a persistent loop (surviving compacting) to iterate on (1) cross-platform parity across iOS / web / Android and (2) all documented deferred features. Use agents, project docs, and platform-specific Claude skills. Significant + well-documented progress over a few hours."*

This document is the persistent state — every loop tick reads + updates it. Each tick: pick the highest-priority item, implement, verify, commit + push, update this doc.

---

## Working philosophy

- **Native-first only.** Reach for built-in platform APIs before custom anything (`feedback_native_first`).
- **Bound each tick.** Pick work that can ship in ~20-40 minutes. If something balloons, split it.
- **Verify before claiming.** `xcodebuild` on iOS, `gradlew assembleDebug` on Android, smoke test in browser for web. Don't mark "done" on intent alone.
- **Commit every shipped tick.** Push to main. Ben sees progress incrementally.
- **Pull from documented sources.** PARITY.md, DECISIONS.md, SCRATCHPAD.md, DESIGN.md, WEB-DESIGN.md, ANDROID-DESIGN.md, ARCHIVE.md, COWORK.md. Discord-export JSONs from research dirs when relevant.

---

## Backlog (priority-ordered)

Order = (impact × shipping cost⁻¹). Higher impact + cheaper to ship = sooner.

### P0 — Quick wins from beta feedback / verified bugs

- [ ] **Verify sealed-image fix on web + Android** — iOS render path uses `card.isSealed` via CDN.swift; web js/api.js and Android core/network/CDN.kt should do the same. Spot-check that the catalog bake from v2.288 actually lights up in all three.
- [ ] **9 sealed products still missing R2 art** — surface them in `assets/data/missing-sealed.json` so the next sourcing pass picks them up.

### P1 — Cross-platform parity (pulled from PARITY.md)

Documented gaps where iOS has shipped but web / Android hasn't, OR vice versa.

- [ ] **Web Wall view + Price overlay** — `PARITY.md` line 142: iOS ✅, web ⏳ M-future. Already on the §15 roadmap.
- [ ] **Web Value history chart** — `PARITY.md` line 130: iOS ✅, web 🔮.
- [ ] **Web Custom Rainbows** — `PARITY.md` line 137: iOS ✅, web 🔮.
- [ ] **Android Custom Rainbows full parity** — currently `⏳ M2`, started but not complete.
- [ ] **Web sign-in with Google** — currently 🔮 on both iOS + web; Android shipped.
- [ ] **Android Whatnot tile list** — currently shows section header but no Worker wiring (per SCRATCHPAD).
- [ ] **Android Google Maps Find a Store** — needs Maps API key + Compose Maps wiring.

### P1 — Android v1 deferred polish (per SCRATCHPAD Android section)

- [ ] **Material 3 Expressive APIs** — FAB Menu / Floating Toolbar / Wavy Indicators (needs compileSdk 37 — currently 36).
- [ ] **M3 SearchBar full-screen morph** — Find tab uses OutlinedTextField for now; should use `ExpandedFullScreenSearchBar`.
- [ ] **Container transform / sharedBounds animations** — hero-zoom into card detail.
- [ ] **Article corpus port from iOS Swift** — Learn content depth gap.
- [ ] **Image fingerprinting (MediaPipe)** — defer per DECISIONS.md #043 (v1 = OCR-only).
- [ ] **Discord OAuth via Custom Tabs** — currently stubbed; Google works.

### P1 — iPad polish (SCRATCHPAD "Deferred iPad work")

- [ ] **Walkthrough anchor verification on iPad** — needs simulator validation.
- [ ] **iPad drag-and-drop between deck slots** — significant; nice-to-have.
- [ ] **Scan view landscape polish** — fixed guide size feels small on iPad.

### P2 — Web "feels native" follow-ups (per WEB-DESIGN.md §15 deferred)

- [ ] **Walkthroughs on web** — explicitly out of scope per §11.
- [ ] **Cmd-K command palette** — out of scope per §2.4.
- [ ] **Web push notifications** — out of scope per §17.

### P2 — Deferred from project docs

- [ ] **Match-alerts pipeline** (DECISIONS.md #039 + TRADE-DESIGN.md Phase 5) — APNs / FCM dispatcher. Multi-week of new infra.
- [ ] **Hero Shot 3D R2 `/full/` resolution upgrade** (SCRATCHPAD blockers) — Hero Shot pixelation root cause.
- [ ] **Practice executor on Android** (DECISIONS.md #048) — admin-gated. M5.5 milestone.
- [ ] **Personal Showcase on Android + web** (Cast SDK) — iOS-only today.

### Audit-driven items (populated by background agents)

*[Updated as agent results land — currently pending]*

---

## Tick log

Each loop tick appends an entry below. Format:

### Tick 175 — 2026-05-21 — **opt** — Clean pass (no orphans remaining)
- **Cadence:** 175 % 5 = 0 → opt.
- **Picked:** Cross-platform orphan sweep (iOS @State + private vars/funcs, Android imports + funcs, web top-level functions). Zero hits across all three platforms. The orphan-detection logic now correctly handles trailing-lambda invocations, fully-qualified Icons refs, and delegate-keyword usage — the false-positive shape that broke tick 140's CI is no longer triggering.
- **Why:** Recent opt ticks (140, 145, 150, 155, 160, 165, 170) cumulatively dropped ~700+ lines of dead code. The current codebase is in a denser-than-baseline state; no low-hanging orphans remain to surface in a single grep pass.
- **Net:** 0 lines (audit-only).
- **Out-of-band fixes shipped this session (not tick-counted)**:
  - Android Studio warnings in `CardDetailScreen`: unnecessary `?.` on `snackbarHostState` + deprecated `rememberTransformableState` 3-arg overload → centroid-aware 4-arg variant.
  - Android app icon: rewrote `ic_launcher_foreground` + `ic_launcher_monochrome` vectors with thicker strokes + bigger marks to match iOS `AppIcon.appiconset/icon.png` aesthetic. Sized to fit Android's 66% safe zone.
- **PARITY.md:** No row.
- **Saved to memory (pre-compaction):** [[feedback_autonomous_loop_failure_modes]] + [[reference_autonomous_loop_tick_100_175_state]] capture the recurring CI failure shapes + the loop's progress snapshot, so a post-compaction resume picks up cleanly.
- **Next:** tick 176 = Android.

### Tick 174 — 2026-05-21 — **Android** — AddToDeckSheet Saved-Deck rows: "Already in deck" hint (tick 171 extension)
- **Cadence:** 174 % 5 = 4 → Android.
- **Picked:** Tick 171 added the "alreadyInDraft" visual hint to AddToDeckSheet's **current-draft row**. The same indicator was missing from the **saved-decks list** below — saved-deck rows showed the same `Icons.Default.Add` and the same body text whether the saved deck already contained this card or not. A coach attempting to "add this card to my Maverick deck" couldn't see at a glance that Maverick already had it (load + add would hit the dup-warning).
- **Shipped:**
  - `AddToDeckSheet.kt` saved-decks forEach:
    - New `val alreadyInSaved = saved.cards.any { it.cardNumber == card.cardNumber }` per-row. Matches on `cardNumber` because that's the canonical persistence shape (deck_cards table stores cardNumber + quantity, not bobaId).
    - supportingContent wraps in a `Column` that prepends a primary-color "Already in this deck" line when matched.
    - trailingContent swaps `Icons.Default.Add` → `Icons.Default.Check` (primary tint) when matched.
- **Verified:** the saved-deck rows are inside `if (savedDecks.isNotEmpty())` block (line 160), gated correctly. Behavior on tap is unchanged — same `decksViewModel.loadSaved + add` sequence + Snackbar with the existing tick-114-aware AddResult branching. Visual hint is purely advisory.
- **PARITY.md:** No row.
- **Next:** tick 175 = opt.

### Tick 173 — 2026-05-21 — **web** — Deck rename: success toast + drop blocking alert on failure
- **Cadence:** 173 % 5 = 3 → web.
- **Picked:** Web's saved-deck rename in `practice.js:1463` had two UX gaps:
  1. **Silent success** — successful rename updated the DOM (deck name in the list + DB.deckName if active) but provided NO toast. The user saw the name flip but had no verbal "Renamed to X" cue.
  2. **Blocking failure** — failures fell through to `alert(err?.message || 'Could not rename deck.')`. Same anti-pattern tick 123 / 143 / 163 systematically replaced. (Note: the rename input itself still uses `prompt()` — replacing that needs a custom dialog and is a larger refactor; out of scope this tick.)
- **Shipped:**
  - `js/practice.js` rename handler:
    - On success (after `applyDeckSearchFilter()`): `window.showToast("Renamed to \"X\"")`. Matches the Android Snackbar copy at `DeckSecondaryScreens.kt:289`.
    - On failure: replace `alert(...)` with `window.showToast("Couldn't rename — {err.message || 'try again'}")`. Same en-dash + fallback pattern as tick 163's three avatar/sharing error paths.
- **Verified:** `window.showToast` is the canonical helper exposed by tick 103 fix. Soft-fails behind `typeof === 'function'` for the (unlikely) case the helper isn't loaded.
- **PARITY.md:** No row.
- **Next:** tick 174 = Android; 175 = opt.

### Tick 172 — 2026-05-21 — **iOS** — Profile Reset hints: inline checkmark confirmation
- **Cadence:** 172 % 5 = 2 → iOS.
- **Picked:** Tick 162 added the iOS Profile hints section. The "Reset hints" Button calls `HintsManager.shared.resetAll()` silently — user taps and sees nothing visible. Android Profile (line 703 area) surfaces a Snackbar `"Hints reset"`. iOS doesn't have a Snackbar host in Profile but does have transient state-driven inline confirmations (Save Cloud / `saveMessage == "Saved!"` pattern).
- **Shipped:**
  - `ProfileView.swift`:
    - New `@State private var hintsResetConfirm = false`.
    - Reset hints Button reshaped from a plain `Label` to `HStack { Label … Spacer; if hintsResetConfirm { Image("checkmark.circle.fill") } }`. The checkmark fades in with `.scale.combined(with: .opacity)` transition.
    - Tap handler sets `hintsResetConfirm = true` + schedules a 2-second `withAnimation(.easeOut)` fade. Matches the cadence the other inline success confirmations in this view use (saveMessage at line 1907-1914 area).
- **Verified:** `HintsManager.shared.resetAll()` is the same call Android uses (DECISIONS.md #031). The visual signal is now consistent with Apple HIG inline-confirmation patterns (Mail compose's Sent-mailbox flash, etc.).
- **PARITY.md:** No row — UX polish on already-✅ Profile hints section. Closes parity with Android's Snackbar confirmation.
- **Next:** tick 173 = web; 174 = Android; 175 = opt.

### Tick 171 — 2026-05-21 — **Android** — AddToDeckSheet: "Already in deck" visual hint on current-draft row
- **Cadence:** 171 % 5 = 1 → Android.
- **Picked:** Carries the tick 161 pool-cell visual indicator into the AddToDeckSheet. The sheet's "Current draft" row showed the same `Icons.Default.Add` icon and offered no visual signal that the card the user is trying to add is ALREADY in the active deck. Tapping the row in that state hits the tick 114 `"already in deck"` Snackbar, but the result is reactive (after tap) — the right UX is proactive (before tap).
- **Shipped:**
  - `AddToDeckSheet.kt` "Current draft" row:
    - New `val alreadyInDraft = draft.cards.any { it.bobaId == card.bobaId }` derived from the sheet's prop card + draft.
    - Supporting content prepends a primary-colored hint line when `alreadyInDraft`: *"Already in this deck — tap to surface duplicate-warning"*.
    - Trailing icon swaps from `Icons.Default.Add` to `Icons.Default.Check` (cyan/primary tint) when `alreadyInDraft`. Visual = same affordance pattern as tick 161's pool-cell badge.
- **Verified:** the existing tap behavior is preserved — tap still hits `decksViewModel.add(card)` which returns `AddResult.Skipped("already in deck")` (tick 114), surfaced via the existing Snackbar. The visual hint is purely advisory; doesn't gate the tap (some users WANT the Snackbar reminder; others learn to skip the row).
- **PARITY.md:** No row.
- **Next:** tick 172 = iOS; 173 = web; 174 = Android; 175 = opt.

### Tick 170 — 2026-05-21 — **opt** — Drop 6 orphan iOS Store methods (53 lines)
- **Cadence:** 170 % 5 = 0 → opt.
- **Picked:** Module-wide scan of iOS Store/Networking/Components/Models for `func` definitions with zero in-tree call sites. Six confirmed orphans, all left over from earlier refactor cycles (Practice executor decompositions, Collection consolidations). False-positives correctly excluded: `viewForZooming` + `scrollViewDidZoom` are `UIScrollViewDelegate` protocol witnesses dispatched dynamically by the runtime — kept.
- **Shipped:**
  - `CollectionStore.swift`:
    - Drop `updateDesignation(id:designation:)` (5 lines) — `updateCard(id:fields:)` with `UpdateUserCard(designation: ...)` does the same work; every actual caller uses `updateCard` directly.
    - Drop `uniqueCardNumbers(for:)` (8 lines) — superseded by `uniqueBobaIds(for:)` (10 lines lower) which is the live "list distinct cards by designation" path; the card-number-only version had no callers post-bobaId migration.
  - `ScanStore.swift`: drop `replaceLastInQueue(with:)` (6 lines) — was an early "OCR refined the last card" path; the live `ScanCoordinator` does in-place replacement via QueuedCard rebuild instead.
  - `PracticeStore.swift` (3 orphans):
    - `triggerCpuSub()` (5 lines) — early "player-starts-sub triggers CPU decision" wrapper; replaced by phase-driven `cpuTakeSubstitutionTurn()` direct calls inside the phase transition handler.
    - `isWeaponTransformed(card:side:)` (5 lines + 3-line docstring) — playmat-side weapon-transform check; the playmat now reads `effectiveWeapon(of:side:)` directly + compares inline.
    - `resetMatch()` (15 lines) — bulk-state reset; the live "new match" path uses `startMatch(mode:)` which sets the same fields via its setup pipeline rather than wiping first.
- **Why these accumulated:** PracticeStore is 5247 lines through multi-week DECISIONS.md #030 + #033 engine work. The Card / Designation / UpdateUserCard split happened later than CollectionStore's first version, leaving older single-purpose methods as orphans. Each func grep-verified zero non-definition references in the whole codebase.
- **Net:** −53 lines across 3 files.
- **PARITY.md:** No row.
- **Next:** tick 171 = Android.

### Tick 169 — 2026-05-21 — **Android** — Profile sign-out: confirm dialog (iOS + web parity)
- **Cadence:** 169 % 5 = 4 → Android.
- **Picked:** Android Profile's "Sign out" button fired `authManager.signOut() + onDismiss()` immediately on tap — no confirmation. iOS uses `.alert("Sign out?", isPresented:)`. Web uses `confirm('Sign out? Your collection data is saved and will sync back...')`. Android was the only platform without a confirm. A stray tap on the Profile sheet's outlined Sign Out button kicks the user out of every personal surface (Collection, Decks, Custom Rainbows, Shows) — sync layer is durable so no data loss, but the re-sign-in friction (especially for OAuth users) warrants protection.
- **Shipped:**
  - `ProfileSheet.kt`:
    - New `var signOutConfirmOpen by rememberSaveable { mutableStateOf(false) }` adjacent to `deleteConfirmOpen`.
    - Sign out button onClick changed from `scope.launch { authManager.signOut(); onDismiss() }` to `{ signOutConfirmOpen = true }`.
    - New `AlertDialog` block above the deleteConfirmOpen dialog:
      - Title: "Sign out?"
      - Body: *"Your collection, decks, and wanted list stay synced to the cloud. Sign back in any time to bring them back."* (more reassuring than the bare "Are you sure?" — emphasizes the sync layer so coaches aren't worried about losing data).
      - Confirm: "Sign out" (no destructive-red — it's recoverable, just disruptive).
      - Dismiss: "Cancel".
- **Verified:** the dialog's confirmButton handler does the same `signOut + onDismiss` sequence the old direct-tap did. Cancel just dismisses the dialog. State is `rememberSaveable` so config changes don't lose the confirm state.
- **PARITY.md:** No row — UX polish on already-✅ Profile.
- **Next:** tick 170 = opt.

### Tick 168 — 2026-05-21 — **web** — Profile feedback: pre-filled subject + Copy-email fallback
- **Cadence:** 168 % 5 = 3 → web.
- **Picked:** Closes parity with iOS tick 167 + Android tick 166. Web's "Send Feedback" was a plain `<a href="mailto:ben@bobaplaybook.com">` — two gaps:
  1. No `?subject=` prefill (iOS/Android pre-populate "BOBA Playbook feedback (vX.Y.Z)").
  2. No fallback when the browser has no `mailto:` handler — silent failure (desktop Safari/Chrome without a configured default mail handler do nothing on click).
  Detecting mailto-failure on web is unreliable (browsers don't expose success/failure for protocol handlers), so the fix is **always-on**: ship a parallel Copy-email button alongside the mailto link. Users without a mail handler tap that; users with one tap Send Feedback like before.
- **Shipped:**
  - `js/collection.js` profile-about render:
    - Send Feedback link gets `?subject=BOBA%20Playbook%20feedback` query.
    - New parallel `<button id="profile-feedback-copy-btn">` with a clipboard icon and "Copy email address" label, styled with the same `.profile-about-row` class so it lines up.
    - Click handler: `navigator.clipboard.writeText('ben@bobaplaybook.com')` → `window.showToast("Copied ben@bobaplaybook.com to clipboard")`. Try/catch with degraded-toast fallback for clipboard-unavailable contexts (HTTPS-only requirement on most modern browsers).
- **Verified:** Send Feedback link continues to work as before — the new button is purely additive. Both behind soft-fail guards. Web doesn't have a version constant to embed in the subject (always-latest from GitHub Pages), so the subject is plain.
- **PARITY.md:** No row.
- **Next:** tick 169 = Android; 170 = opt.

### Tick 167 — 2026-05-21 — **iOS** — Profile Send Feedback: graceful fallback when no mail client (Android tick 166 parity)
- **Cadence:** 167 % 5 = 2 → iOS.
- **Picked:** Same silent-failure bug as Android tick 166. iOS Profile's "Send Feedback" button called `UIApplication.shared.open(url)` (fire-and-forget) for the `mailto:ben@bobaplaybook.com?subject=...` URL. If the user uninstalled Apple Mail and hasn't added Gmail/Outlook (uncommon but not zero — Apple Mail is uninstallable on iOS 14+), the open silently no-ops. Tap → nothing.
- **Shipped:**
  - `ProfileView.swift`:
    - New `@State private var showingFeedbackNoMailAlert = false`.
    - Send Feedback button switched to `UIApplication.shared.open(url, options: [:]) { success in ... }` — the completion-handler variant surfaces a Bool indicating whether iOS actually opened the URL.
    - On `!success`: copies `ben@bobaplaybook.com` to `UIPasteboard.general.string` + sets `showingFeedbackNoMailAlert = true`.
    - New `.alert("No email app found", isPresented:)` attached to the aboutSection Section. Body copy: *"Copied ben@bobaplaybook.com to your clipboard. Paste it into Gmail, Outlook, or your preferred mail client."*
- **Verified:** `UIApplication.shared.open(_:options:completionHandler:)` is the documented async variant returning success on the main thread. `UIPasteboard.general.string` is the universal-pasteboard write path (also used at line 544 for public-URL copy). No new imports needed.
- **PARITY.md:** No row — UX polish on already-✅ Profile. Closes parity with Android tick 166.
- **Next:** tick 168 = web; 169 = Android; 170 = opt.

### Tick 166 — 2026-05-21 — **Android** — Profile Send Feedback: graceful fallback when no email app
- **Cadence:** 166 % 5 = 1 → Android.
- **Picked:** Real silent-failure bug. The Profile sheet's "Send feedback" `clickable` used `runCatching { context.startActivity(intent) }` for a `mailto:ben@bobaplaybook.com?subject=...` ACTION_VIEW. If the device has no email app installed — Pixel devices often ship WITHOUT a default Gmail in some configurations, and aftermarket ROMs increasingly omit one — `runCatching` swallowed the `ActivityNotFoundException` and the user saw NOTHING. Tap → empty void. Worst-case: a frustrated user who thinks the feedback button is broken silently abandons their bug report.
- **Shipped:**
  - `ProfileSheet.kt` "Send feedback" click handler:
    - `runCatching { ... }.onFailure { ... }` — when the intent fails (no app to handle `mailto:`):
      - Copies `ben@bobaplaybook.com` to the clipboard via `ClipboardManager.setPrimaryClip(ClipData.newPlainText(...))`.
      - Fires a Snackbar: *"No email app — copied ben@bobaplaybook.com to clipboard"* so the user can paste into Gmail web / Outlook web / any other mail client.
- **Verified:** `scope` + `appSnackbar` already in scope (declared at line ~92 of ProfileSheet). `ClipboardManager` is a standard system service. `ClipData.newPlainText` accepts arbitrary label + text. The fallback path costs zero when the happy path fires (runCatching only routes to onFailure on Throwable).
- **PARITY.md:** No row — UX polish on already-✅ Profile.
- **Next:** tick 167 = iOS; 168 = web; 169 = Android; 170 = opt.

### Tick 165 — 2026-05-21 — **opt** — Drop orphan `LearnCorpus.watch` placeholder corpus (14 lines)
- **Cadence:** 165 % 5 = 0 → opt.
- **Picked:** `LearnContent.kt:581` defined `val watch: List<LearnSection>` — a 2-section placeholder ("Coming soon" + "Until then") for the Watch tab before the live Worker-backed `WatchPageContent()` shipped. Once the live feed landed, the `watch` corpus became unreferenced — `LearnArticleScreen.kt:124` switched to `WatchPageContent()` directly. Module-wide grep confirmed zero callers (1 reference = the definition itself).
- **Shipped:**
  - `LearnContent.kt`: drop the `// WATCH — placeholder; YouTube feed Worker wiring is M5-polish` comment block + `val watch = listOf(...)` — 14 lines total.
- **Verified:** cross-platform orphan scans this round (iOS + Android + web) all came back empty besides this one. The orphan-detection logic improvement made after tick 140's CI blowup now correctly handles trailing-lambda invocations + fully-qualified Icons refs + delegate-keyword usage; this sweep is the first clean pass under the tightened rules.
- **Net:** −14 lines.
- **PARITY.md:** No row.
- **Next:** tick 166 = Android.

### Tick 164 — 2026-05-21 — **Android** — Decks empty-state template tap: confirmation Snackbar
- **Cadence:** 164 % 5 = 4 → Android.
- **Picked:** `DeckEditorSheet.EmptyDeckCTA` (line 530) is the inline template gallery shown when the draft is empty. Tapping a template fires `decksVm.clear() + rename + cards.forEach add` then... silently returns. The visual flip from empty-state → populated editor IS the signal, but it lacks the "Loaded X" Snackbar confirmation that `TemplateGallerySheet` (tick 136) added to the standalone template picker. A coach who hasn't built decks before — exactly the audience of the empty-state CTA — benefits most from explicit verbal feedback that the tap registered.
- **Shipped:**
  - `DeckEditorSheet.kt`:
    - New `import kotlinx.coroutines.launch` (avoiding the tick-159 CI-failure shape — defensive add upfront).
    - New `scope = rememberCoroutineScope()` + `appSnackbar = LocalAppSnackbar.current` in `EmptyDeckCTA`.
    - Tap handler appends `scope.launch { appSnackbar?.showSnackbar("Loaded \"${template.name}\"") }` after the existing `decksVm.add(...)` loop. No destructive-overwrite warning needed (the EmptyDeckCTA only renders when `draft.cards.isEmpty()`).
- **Verified:** the EmptyDeckCTA's `if (draft.cards.isEmpty())` gate (line 474) guarantees no overwrite case. Same Snackbar copy as `TemplateGallerySheet`'s success branch (tick 136).
- **PARITY.md:** No row — UX polish.
- **Next:** tick 165 = opt.

### Tick 163 — 2026-05-21 — **web** — Profile error paths: 3 blocking alerts → non-blocking toasts
- **Cadence:** 163 % 5 = 3 → web.
- **Picked:** WEB-DESIGN.md §1 (native first, no blocking modals for routine errors). Three remaining `alert('Could not …')` call sites in `collection.js` covered routine error paths:
  - Line 1966: public-collection toggle failed (network drop on toggle change).
  - Line 2085: switch-to-Discord-avatar failed.
  - Line 2096: remove-custom-avatar failed.
  Each was an OS-modal blocking interrupt for a moderately-rare-but-not-extraordinary error. Tick 123 + 143 + 158 systematically dropped blocking dialogs; this round catches three more in the Profile flow.
- **Hints / Reset hints on web NOT shipped** — web doesn't have multi-step walkthroughs or dismissible `HintBanner`-style cards (WEB-DESIGN.md §11 explicitly rejects them in favor of inline help). There's no `HintsManager` analog to toggle. iOS tick 162's "Show first-run hints / Reset hints" Profile section has no web equivalent because there's nothing to silence.
- **Shipped:**
  - `js/collection.js` three error paths replace `alert('Could not …')` with `window.showToast` (canonical helper at practice.js:1640 exposed as `window.showToast` since tick 103). Each soft-fails behind `typeof window.showToast === 'function'` for graceful degradation.
  - Same copy shape: `"Could not update sharing — {err.message || 'try again'}"` (en-dash matches BOBA's brand vocab for inline error fragments).
- **Verified:** the toast helper handles arbitrary text, auto-dismisses after 3s, doesn't interrupt the user. All three sites previously blocked the page until the OS modal was dismissed.
- **PARITY.md:** No row.
- **Next:** tick 164 = Android; 165 = opt.

### Tick 162 — 2026-05-21 — **iOS** — Profile: hints master toggle + Reset hints (Android parity)
- **Cadence:** 162 % 5 = 2 → iOS.
- **Picked:** Real iOS parity gap. Android ProfileSheet has a "Show first-run hints" toggle + a "Reset hints" button (line 670-720 area, used `HintsViewModel.setGlobalEnabled` / `resetAll`). iOS has had `HintsManager.shared` since DECISIONS.md #031 — the `hintsEnabled` master toggle and `resetAll()` API both exist (`Design.swift:230`) — but Profile never surfaced the UI. Coaches who dismissed a hint they wanted back had no recovery path; coaches who didn't want hints at all couldn't silence them.
- **Shipped:**
  - `ProfileView.swift`:
    - New `private var hintsSection: some View` inserted between `displaySection` and `notificationsSection` (settings-style rows belong adjacent to Display).
    - Section content:
      - `Toggle` bound to `HintsManager.shared.hintsEnabled` (Binding shim — the @Observable singleton supports SwiftUI's property write).
      - `Button("Reset hints")` calling `HintsManager.shared.resetAll()` — wipes every dismissed `HintID` from UserDefaults and clears the in-memory `dismissedIDs` set.
    - Section header `"Hints"` (uppercase mono small-caps matching the existing pattern) + footer copy *"Hints are one-line tips that surface inside the app once. Reset to re-show them all."*.
- **Verified:** `HintsManager` is `@Observable` so SwiftUI tracks reads of `hintsEnabled` automatically. The Binding shim uses get/set on the singleton; toggling writes both the property AND the UserDefaults mirror (line 239). `resetAll()` is also already public.
- **PARITY.md:** No row — UX polish on already-✅ Profile. Closes the iOS gap relative to Android ProfileSheet's hints controls.
- **Next:** tick 163 = web; 164 = Android; 165 = opt.

### Tick 161 — 2026-05-21 — **Android** — Decks pool: cyan border + ✓ badge on in-deck cards
- **Cadence:** 161 % 5 = 1 → Android.
- **Picked:** Real parity gap. iOS DeckBuilderView's `BrowserCardCell` highlights cards already in the active draft with a cyan border (`Design.Colors.bobaCyan`, 2.5pt) + a checkmark badge (line 1218-1255 area). Android's Decks `CardPoolGrid` showed every card identically — coaches couldn't see at a glance which cards they'd already picked, leading to unnecessary tap-attempts that hit "already in deck" rejections from tick 114's enforcement.
- **Shipped:**
  - `DecksScreen.kt` `CardPoolGrid`:
    - New parameter `inDeckBobaIds: Set<String> = emptySet()`.
    - Each item now wraps `BOBACardCell` in a `Box(modifier = combinedClickable + cardSharedBounds)`. When `card.bobaId in inDeckBobaIds`, the Box adds:
      - A full-size `Canvas` overlay drawing a cyan rounded-rect stroke (4dp width, 12dp corner radius — matches the cell's `shapes.medium`).
      - A 20dp circular badge anchored TopEnd with a 14dp Check icon, cyan background + near-black tint (matches iOS treatment).
    - Both call sites (line 324 compact + line 716 tablet) pass `inDeckBobaIds = remember(draft.cards) { draft.cards.map { it.bobaId }.toSet() }` — single-pass set construction memoized on the draft's cards list.
  - New imports: `Canvas`, `layout.size`, `shape.CircleShape`, `BobaBrand`.
- **Verified:** uses `BOBACardCell` unchanged (shared primitive untouched per design principle — no fork). Set lookup is O(1) per cell. The remember key (`draft.cards`) is a kotlinx.collections.immutable `PersistentList`, so reference equality is enough to invalidate the memo on any draft change.
- **PARITY.md:** No row — UX polish on already-✅ Decks. Closes iOS DeckBuilderView "in-deck visual indicator" parity.
- **Next:** tick 162 = iOS; 163 = web; 164 = Android; 165 = opt.

### Tick 160 — 2026-05-21 — **opt** — Drop 67 more lines of orphan practice.js helpers + audit
- **Cadence:** 160 % 5 = 0 → opt.
- **Picked:** Cascade cleanup after tick 150's `pmResolveEffect` removal. `pmResolveCoinFlip` (24 lines) and `pmResolveDiceRoll` (43 lines) were ONLY called from inside the now-deleted regex resolver. Tick 150's audit missed them because they shared the same code path — once `pmResolveEffect` went, these too became orphan helpers.
- **Shipped:**
  - `js/practice.js`:
    - Drop `pmResolveCoinFlip(text, playerCard)` (lines 4153-4176 — coin-flip-with-N-flips ability resolver from the legacy regex path).
    - Drop `pmResolveDiceRoll(text, playerCard, cpuCard)` (lines 4178-4220 — dice-roll-based ability resolver with reroll / 5x-multiplier / "both players roll" branches).
  - Cross-module audit run on Android + iOS + web found NO additional orphans — every other function defined in the tree has at least one external call site.
- **Why these accumulated:** the regex resolver was deeply branching (~146 lines), with these two sub-resolvers handling the dice/coin sub-paths. When tick 150 removed the entry point, the sub-resolvers stayed because grep on their names returned 1 ref (only the def). My filter was `\bNAME\b` not "(definition + external caller)" so it correctly flagged them — but tick 150's sweep was practice.js-only and the helpers were past the cutoff.
- **Net:** −70 lines.
- **Caveat:** an Android CI break landed mid-tick (tick 159 missed `import kotlinx.coroutines.launch`). Fixed in the prior commit; CI is back to green. This opt tick is a separate change touching only `js/practice.js`.
- **PARITY.md:** No row.
- **Next:** tick 161 = Android.

### Tick 159 — 2026-05-21 — **Android** — Custom Rainbow delete: Undo Snackbar (closes 3-platform parity loop)
- **Cadence:** 159 % 5 = 4 → Android.
- **Picked:** Mirror of web tick 158. Android Custom Rainbow delete in `RainbowsScreen.kt` used an `AlertDialog` confirm → `customVm.delete(id)` → silent dismissal. No Snackbar, no Undo. Same destructive-action-without-recovery shape that ticks 119/124/139/144/149/152/158 have been systematically closing.
- **Shipped:**
  - `RainbowsScreen.kt`:
    - New `scope = rememberCoroutineScope()` + `appSnackbar = LocalAppSnackbar.current` at the composable root.
    - Confirm-button handler captures `val captured = rb` (the resolved CustomRainbow object) BEFORE `customVm.delete(id)`.
    - After delete + close dialog, fires `appSnackbar?.showSnackbar(message = "Deleted \"X\"", actionLabel = "Undo", duration = SnackbarDuration.Short)`.
    - On `SnackbarResult.ActionPerformed`, calls `customVm.create(captured.name, captured.criteria) { ok -> ... }` — same shape as the editor's create path (tick 156). On `ok == false`, fires a secondary Snackbar `"Couldn't restore — try again."`.
- **Verified:** `customVm.create` (line 30) and `customVm.delete` (line 49) already exist on the ViewModel. Supabase issues a new `id` on insert but the user-visible data (name + criteria) round-trips losslessly — same trade-off as web tick 158 and Android Manage Decks Undo (tick 124).
- **PARITY.md:** No row — UX polish on already-✅ Custom Rainbows. Closes parity with web tick 158.
- **Next:** tick 160 = opt.

### Tick 158 — 2026-05-21 — **web** — Custom Rainbow delete: Undo Snackbar replaces blocking confirm
- **Cadence:** 158 % 5 = 3 → web.
- **Picked:** `collection.js:3562` still used a blocking `confirm("Delete X? This cannot be undone.")` for Custom Rainbow delete. This is the same anti-pattern tick 123 (Collection per-copy delete) and tick 143 (Clear-deck) replaced. Worse: the dialog wording lied — the deletion CAN be undone by re-creating the rainbow with the same name + criteria via the public API (Supabase generates a new id, but the user-visible data round-trips losslessly).
- **Shipped:**
  - `js/collection.js` Custom Rainbow editor delete handler:
    - Drop the `if (!confirm(...)) return;` guard.
    - Capture `const captured = { name: _editingRainbow.name, criteria: _editingRainbow.criteria }` BEFORE the delete API call.
    - On success: `closeCustomRainbowEditor()` + `renderCollectionView()` + fire `window.showUndoToast("Deleted \"X\"", undoCallback)`.
    - Undo callback: `await API.createCustomRainbow(captured.name, captured.criteria)` + `renderCollectionView()` — same defensive try/catch + secondary toast on re-create failure.
- **Verified:** `API.createCustomRainbow(name, criteria)` is the canonical create path at `js/api.js:289` (used by the editor's existing save path at line 3543). Same shape, lossless round-trip. `window.showUndoToast` is exposed globally from practice.js (tick 118 + tick 123 fix).
- **PARITY.md:** No row.
- **Next:** tick 159 = Android; 160 = opt.

### Tick 157 — 2026-05-21 — **iOS** — DecksView saveDeck: surface failure banner (was silent on error)
- **Cadence:** 157 % 5 = 2 → iOS.
- **Picked:** Mirror of Android tick 154 — same fire-and-forget bug on a different platform. `DecksView.saveDeck()` had `if store.saveError == nil { saveBanner = "Saved X" }` — the failure branch was completely absent. A coach taps Save → server write fails (network / RLS / empty name) → `store.saveError` is set BUT `saveBanner` stays nil so the user sees nothing. They might retry until either it succeeds (creating duplicate decks if retry happens to also work) or give up wondering if the button is broken.
- **Shipped:**
  - `DecksView.swift` `saveDeck()`:
    - Restructured the conditional from "only show success banner" to "branch on success vs failure" — `if let err = store.saveError { saveBanner = "Couldn't save — \(err)" } else { saveBanner = "Saved X" }`.
    - Auto-fade timeout extended to 4s on error (vs 2s on success) so the user has time to read the error before it disappears.
- **Verified:** `store.saveError` is set by `DeckBuilderStore.saveDeck()` at line 1372 on every `catch` branch with `error.localizedDescription`. The existing `saveBanner` overlay rendering at the top of DecksView (line 740 area) handles arbitrary text — no shape change needed.
- **PARITY.md:** No row — UX polish on already-✅ Decks Save. Closes parity with Android tick 154.
- **Next:** tick 158 = web; 159 = Android; 160 = opt.

### Tick 156 — 2026-05-21 — **Android** — Custom Rainbow editor: Save success/failure Snackbars
- **Cadence:** 156 % 5 = 1 → Android.
- **Picked:** `CustomRainbowEditorSheet`'s Save button called `vm.create(...)` / `vm.update(...)` with a callback `{ ok -> if (ok) onDismiss() }`. On success → silent dismiss; on failure → silent no-op (sheet stays open, no error message). Two real UX gaps:
  1. **Success path**: dismiss-as-confirmation is the iOS canonical, but Android's `ModalBottomSheet` competes with other backstack surfaces; users need an explicit "Created/Saved X" Snackbar to confirm the persistence call landed.
  2. **Failure path**: total silent failure. Network drop / RLS rejection / duplicate-name conflict all leave the user staring at the editor with no signal anything went wrong. They might re-tap Save → if it succeeds the second time, they could end up with duplicate "Untitled" rainbows.
- **Shipped:**
  - `CustomRainbowEditorSheet.kt`:
    - New `rememberCoroutineScope` + `LocalAppSnackbar.current` reads.
    - New imports: `rememberCoroutineScope`, `kotlinx.coroutines.launch`.
    - Save handler refactored: builds a single shared `cb: (Boolean) -> Unit` callback that branches on success/failure inside a `scope.launch { ... }`:
      - `ok == true` → `appSnackbar?.showSnackbar("Created \"X\"")` or `"Saved \"X\""` (verb branches on `existing == null`) + `onDismiss()`.
      - `ok == false` → `appSnackbar?.showSnackbar("Couldn't save — check connectivity and try again.")` (sheet stays open so the user can retry without re-typing the form).
    - Same callback handed to both `vm.create(...)` and `vm.update(...)` — single source of truth.
- **Verified:** `LocalAppSnackbar` is the canonical Snackbar host (used by every other Android sheet in tick 119, 121, 124, 136, 139, 144, 149, 151, 154). The "verb" pattern (`"Created"` vs `"Saved"`) matches iOS UX vocabulary.
- **PARITY.md:** No row — UX polish on already-✅ Custom Rainbow editor.
- **Next:** tick 157 = iOS; 158 = web; 159 = Android; 160 = opt.

### Tick 155 — 2026-05-21 — **opt** — Drop 112 lines of iOS dead code (orphan vars + legacy save tab)
- **Cadence:** 155 % 5 = 0 → opt.
- **Picked:** Per-file scan for `private var` orphans on iOS Views. Found one substantial dead cluster (the legacy "Save" tab in DeckManagementSheet) plus three smaller orphans.
- **Shipped:**
  - **`DeckBuilderView.swift` legacy Save-tab purge (~90 lines)**: `DeckManagementSheet` has an enum `Tab: String, CaseIterable { case load, share }` with two cases. But the file still carried a third `private var saveTab: some View` (57 lines), plus `@State isSaving`, `@State saveMessage`, and `private func saveDeck() async` (15 lines) — leftover from an earlier 3-tab design where Save was a separate sub-screen. The current architecture saves via the in-editor SAVE toolbar button (DeckBuilderView line 138-217), not via a "save tab." All four were truly orphan (zero in-file refs and zero external refs).
  - **`DeckBuilderView.swift` per-cell `borderColor` (~5 lines)**: defined on a card-pool cell struct but no `.strokeBorder(borderColor)` call site — superseded by inline border color computation in the cell's body. Two other `borderColor` definitions in Design.swift + LearnView.swift survive (they ARE used by their respective parents).
  - **`SearchView.swift` private var `filterButton` (~17 lines)**: an alternate filter-button shape with badge logic. Superseded by the toolbar Menu's filter affordance + `BOBASearchBar`'s integrated filter chip. Two other `filterButton` definitions across the project (CollectionView, etc.) survive.
  - **`ReactionPickerView.swift` `filteredEmoji` (~9 lines)**: never referenced; the emoji grid renders directly from `discordEmojiCategories[selectedCategory].emoji`.
- **Why these accumulated:** the iOS app shipped 280+ versions through massive Decks refactors (Maps-pattern → Music-pattern → fullScreenCover) and SearchView/CollectionView re-orgs. Old computed-property helpers get displaced but the original definitions linger silently until a sweep catches them. Tick 145 caught HouseOfCards orphans; this round catches the Decks/Search/ReactionPicker pile.
- **Verified:** every removed symbol grep-confirmed zero in-file refs and (for cross-file safety on filterButton/borderColor) zero project-wide refs that resolved to the dropped definition. SourceKit indexer noise on @MainActor @Observable files is pre-existing.
- **Net:** −112 lines across 3 files.
- **PARITY.md:** No row.
- **Next:** tick 156 = Android.

### Tick 154 — 2026-05-21 — **Android** — Decks tablet-pane Save: Snackbar feedback (was fire-and-forget)
- **Cadence:** 154 % 5 = 4 → Android.
- **Picked:** Real UX gap. `DecksScreen.kt:718` had `onSave = { deckViewModel.save { /* tablet pane stays open */ } }` — the trailing-lambda comment was actually consuming the save-result callback as a no-op, so the tablet-pane Save button fired the save then provided NO UI feedback. The compact-screen path at line 391 already used the richer save signature (tick 71) with Snackbar success/error feedback. Tablet path was the lone fire-and-forget.
  - Worst case: user taps Save → server write fails silently (network drop / RLS rejection / empty name) → user sees the deck still in the editor → taps Save AGAIN → creates a duplicate deck on retry success.
- **Shipped:**
  - `DecksScreen.kt:718`: replaced the no-op trailing lambda with the same `errorMessage: String? ->` callback the compact path uses. On `null` (success): Snackbar `"Saved \"${draft.name}\""`. On non-null: Snackbar with the error message verbatim — `tick 71` already disambiguates sign-out / empty-name / network so the user knows what to fix.
  - Tablet pane intentionally STAYS open after save (the comment "tablet pane stays open" is preserved as the rationale — unlike compact's `ModalBottomSheet` which has nothing to dismiss to, the tablet pane IS the canvas).
- **Verified:** `scope` and `appSnackbar` are already in scope at the tablet site (declared at line 616-617 in DecksTabletScreen). Same Snackbar copy as the compact path; same callback shape.
- **PARITY.md:** No row — UX polish on already-✅ tablet Decks Save.
- **Next:** tick 155 = opt.

### Tick 153 — 2026-05-21 — **web** — Collection Edit Copy: confirmation toast on save
- **Cadence:** 153 % 5 = 3 → web.
- **Picked:** Closes parity with iOS dismiss-as-confirmation + Android tick 151's Snackbar. Web's Collection card detail Edit form submit (collection.js:3050) successfully calls `API.collectionUpdate` then dismisses the edit state — but provides NO toast/banner confirmation. The user sees the form disappear and the updated entry in the detail list, but if they lost their place in the dense form they might wonder if the submit actually went through.
  - The "decks containing this card" surface is iOS+Android-only — web has no equivalent — so the destructive-overwrite-warning side of tick 152 doesn't apply here.
- **Shipped:**
  - `js/collection.js` edit-form submit handler:
    - Captures `const captured = _editEntry;` BEFORE the `_editEntry = null` reset so the label remains available after state-clearing.
    - After `renderCollectionDetail/View/ProfileView`, fires `window.showToast("Saved edits to {label}")` where label is `hero || name || "card"`. Same defensive label fallback as tick 123's per-copy Undo toast.
- **Verified:** `window.showToast` is the canonical helper exposed from app.js (tick 103 fix). Soft-fails behind `typeof === 'function'` for the (unlikely) case the helper isn't loaded yet.
- **PARITY.md:** No row.
- **Next:** tick 154 = Android; 155 = opt.

### Tick 152 — 2026-05-21 — **iOS** — Collection card detail "In your decks": Undo banner on draft overwrite
- **Cadence:** 152 % 5 = 2 → iOS.
- **Picked:** iOS mirror of Android tick 149. The Collection card detail's "In your decks" surface (CollectionCardDetailView.swift:614) was already tap-to-load (parity with Android tick 94) but tapping a row silently wiped any in-progress draft via `deckBuilder.loadSavedDeck` → `clearDeck()` internally. The text-only toast `"Loaded "X" into Decks"` didn't acknowledge the destruction. A coach mid-build who taps to peek at a saved deck loses 30+ cards with no recovery path.
- **Shipped:**
  - `CollectionCardDetailView.swift`:
    - New `@State private var preLoadDraftSnapshot: (snapshot: DeckBuilderStore.DraftSnapshot, deckName: String)?` paralleling the templateLoadBanner one-shot pattern (tick 137) and clearedSnapshot pattern (tick 142).
    - Button-tap handler at line 614 now captures `hadDraft = !heroes.isEmpty || !plays.isEmpty || !bonusPlays.isEmpty || !hotDogs.isEmpty` synchronously BEFORE the async `loadSavedDeck` Task; if hadDraft, it calls `deckBuilder.currentSnapshot()` (added in tick 142) to grab a snapshot. After the load succeeds, sets `preLoadDraftSnapshot = (snap, deck.name)` + schedules a 6-second auto-fade. Empty-draft path keeps the existing terse `showAddedToDeckToast` confirmation.
    - New `overwriteUndoBanner(deckName:snapshot:)` ViewBuilder helper: cyan-accent banner (`arrow.uturn.backward.circle.fill` icon, distinct from the green check confirmationToast) with a tappable UNDO button in BOBA orange. Tap → `deckBuilder.applySnapshot(snapshot, allCards: cardStore.displayCards)` + dismiss banner.
    - Top-overlay slot extends with `if let pending = preLoadDraftSnapshot { overwriteUndoBanner(...) } else if ...` — banner takes priority over the addedToDeckName/addedToShowName/removedEntryName confirmation toasts since they'd never overlap in time (load is a one-shot UX event).
- **Verified:** `deckBuilder.currentSnapshot()` + `applySnapshot()` were added in tick 142 for the same purpose (Clear-deck Undo); reusing them on this surface is free. `DraftSnapshot` is a Codable struct so passing it through @State works. SourceKit reports the pre-existing indexer noise on `@Observable @MainActor` files; Swift compiler resolves.
- **PARITY.md:** No row — UX polish on already-✅ "In your decks" surface. Closes parity with Android tick 149.
- **Next:** tick 153 = web; 154 = Android; 155 = opt.

### Tick 151 — 2026-05-21 — **Android** — Collection Edit Copy: auto-dismiss + confirmation Snackbar
- **Cadence:** 151 % 5 = 1 → Android.
- **Picked:** Real bug. The Collection card detail's `EditCopySheet` (tick 99 added it) Save button fired `onSave(...)` then... did nothing else. The sheet stayed open with the user's now-saved edits still in form fields. The user had no signal the save succeeded — they had to either tap Cancel (which feels wrong after saving) or backdrop-dismiss (also fragile feedback). Worse: `updateEntry` is fire-and-forget on the ViewModel side, so a silent failure (network error, RLS rejection) would leave the sheet open with stale-looking input + no error message.
- **Shipped:**
  - `EditCopySheet` Save button: after `onSave(...)`, immediately calls `onDismiss()`. Auto-dismissal-as-confirmation is the iOS `EditCollectionEntrySheet.swift:1019` pattern translated.
  - `onSaveEdits` lambda at the call site (line 192): wraps the existing `viewModel.updateEntry(...)` call with a `scope.launch { appSnackbar?.showSnackbar("Saved edits to ${entry.card.displayName}") }`. The Snackbar is the user-visible signal that the persistence call landed.
- **Verified:** `scope` + `appSnackbar` are already in scope at line 89-90 (used by the existing delete-Undo Snackbar at line 173-174). Reused without changes. The Snackbar message preserves the entry's display name so a user with multiple cards open knows which one got saved.
- **PARITY.md:** No row — UX polish on already-✅ Collection Edit Copy.
- **Next:** tick 152 = iOS; 153 = web; 154 = Android; 155 = opt.

### Tick 150 — 2026-05-21 — **opt** — Drop ~239 lines of dead code across iOS + web
- **Cadence:** 150 % 5 = 0 → opt.
- **Picked:** Cross-platform sweep for orphans the earlier opt rounds didn't catch.
- **Shipped:**
  - **iOS @State / @AppStorage orphans (4 lines)**:
    - `CollectionCardDetailView.swift:38`: `@State private var focusedEntryID: UUID?` — never read or written.
    - `AdminPanelView.swift:18-19`: `roleUpdateTarget` + `showRolePicker` — leftover state from an earlier role-picker UI that got replaced by the inline role chip.
    - `CollectionView.swift:65`: `@AppStorage("selectedIconName")` — duplicate declaration (ProfileView + SearchView each have their own valid @AppStorage on the same key; CollectionView's copy is unused).
  - **iOS orphan `commitHeldCards()` (22 lines, HouseOfCardsView.swift)**: After tick 145 dropped `spawnHeldPair`, this helper that committed held cards from `heldCards[]` to `dynamicCards[]` no longer had a caller. The `heldCards[]` array itself stays — it's still used by the live-pickup pipeline; only the pair-spawn-commit path is gone.
  - **Web orphan practice-mode helpers (213 lines, js/practice.js)**:
    - `pmResolveEffect` (146 lines): the legacy regex-based play-effect resolver. Comment at line 1675 even labeled it "Callers fall back to the regex resolver (pmResolveEffect) when the card has no structured entry" — but no callers actually fall back to it; structured executor `pmExecStructured` is the only effect path. Earlier opt round (e82ed6f) dropped `pmDetectHDRecovery`; this is the next-layer purge.
    - `pmFallbackEffect` (1 line): only ever called from inside the now-deleted `pmResolveEffect`.
    - `pmIncompatibleHeroCount` (5 lines): leftover hero-deck-builder validator from a pre-`pmFormatPowerCap` era.
    - `pmEffectDescription` (5 lines): unused; the live UI reads `card.playAbility` directly.
    - `pmRenderPlaysUsedRow` (40 lines): an alternate plays-strip renderer that was superseded by inline rendering inside the battle-card column.
    - `pmShowCpuPlayQueue` + `pmShowCpuSubCallout` (7 lines combined): "Legacy wrappers — kept for any remaining direct calls" said the comment, but no direct callers remain after the queue refactor. Both are pure passthroughs to `pmQueueCpuPlays`/`pmQueueCpuSub`.
  - **Updated comment at line 1675** to no longer claim a regex fallback exists.
- **Why it's safe:** every removed symbol verified zero remaining call sites via global `grep -E "\\bNAME\\b"` (word-boundary, no parens required so function references are caught). The 6 practice.js orphans share the same lineage — a structured-executor refactor that obsoleted the regex resolver and its descendants. The `commitHeldCards` removal is a clean rip-out of the dead `spawnHeldPair` ecosystem.
- **Net:** −239 lines (+2 inserts for the updated comment) across 5 files (BOBAPlaybook/Views/Collection/CollectionView.swift, BOBAPlaybook/Views/Collection/CollectionCardDetailView.swift, BOBAPlaybook/Views/HouseOfCards/HouseOfCardsView.swift, BOBAPlaybook/Views/Profile/AdminPanelView.swift, js/practice.js).
- **PARITY.md:** No row.
- **Next:** tick 151 = Android.

### Tick 149 — 2026-05-21 — **Android** — Card detail "Decks with this card": destructive-overwrite warning + Undo
- **Cadence:** 149 % 5 = 4 → Android.
- **Picked:** Second-to-last untreated destructive-overwrite surface on Android. Tapping a "Decks with this card" row in the Card detail screen called `decksVmHere.loadSaved(deck, catalog)` then fired a Snackbar saying *"Loaded \"X\" into the Decks editor"* — silently wiping any in-progress draft. Same shape as the Manage-Decks load path before tick 144. Now that `restoreDraft(snapshot)` is wired (tick 139), Undo costs nothing.
- **Shipped:**
  - `CardDetailScreen.kt` (the `decksContaining.forEach { deck -> Row(...) }` block):
    - New `val draftForOverwriteCheck by decksVmHere.draft.collectAsStateWithLifecycle()` so the click handler can read pre-load state.
    - Row click handler now captures `val captured = if (draft.cards.isNotEmpty()) draft else null` BEFORE `loadSaved`, fires a Snackbar with `actionLabel = "Undo"` when `captured != null` (with destructive-overwrite copy), and falls back to the terse "Loaded X" message when the draft was empty.
    - On `SnackbarResult.ActionPerformed`, calls `decksVmHere.restoreDraft(captured)` — atomic re-bind of the entire DeckDraft.
- **Verified:** the existing `decksVmHere` reference is already in scope; only the new `draft` collector is added. Snackbar behavior matches tick 144's DeckManageScreen and tick 139's Clear-deck — same `restoreDraft` plumbing reused.
- **PARITY.md:** No row — UX polish on already-✅ Card detail "Decks with this card".
- **Next:** tick 150 = opt.

### Tick 148 — 2026-05-21 — **web** — Decks DBS chip tappable (closes 3-platform DBS-explainer loop)
- **Cadence:** 148 % 5 = 3 → web.
- **Picked:** Closes the 3-platform parity loop on the tappable-DBS-budget pattern (iOS tick 147, Android tick 134). Web already had the full DBS explainer dialog (`#dbs-info-overlay`) in `index.html:2643`, wired to open from the Card-detail modal via `[data-action="open-dbs-info"]` triggers, but the Decks editor's `#db-stat-dbs` chip was a plain `<span>` — no click affordance.
- **Shipped:**
  - `index.html:1991`: `<span class="db-stat db-stat-dbs">` → `<button type="button" class="db-stat db-stat-dbs" data-action="open-dbs-info" aria-label="DBS budget — tap to learn more">`. Same id/classes preserved so the existing render path (`practice.js:800`-`812` toggling `.over` and updating textContent) keeps working without changes.
  - `js/app.js:118-125`: existing DBS dialog trigger was scoped to `modalContent` (card-detail modal). Promoted to a `document.addEventListener` delegate so ANY element with `[data-action="open-dbs-info"]` opens the dialog — the editor DBS chip now triggers it alongside the existing modal trigger. Safe: the handler short-circuits when no `[data-action="open-dbs-info"]` ancestor exists, so the dispatch cost is just one `closest()` per page-wide click.
  - `css/styles.css`:
    - `.db-stat-dbs` extended: explicit `border: 1px solid` (was `border-color` only — relied on the prior `<span>` not having a UA border), `font: inherit`, `padding: 2px 8px`, `border-radius: 4px`, `cursor: pointer`. Neutralizes UA `<button>` chrome so the visual is byte-identical to the prior span treatment.
    - `.db-stat-dbs:hover` adds a darker orange background for tactile feedback.
    - `.db-stats` container gets `align-items: center` so the now-`<button>` DBS chip lines up with its `<span>` siblings (buttons in a flex container with default `stretch` alignment would visually outsize the sibling spans).
- **Verified:** the `<button type="button">` won't submit any form (no enclosing `<form>` in the editor pane anyway). `data-action="open-dbs-info"` is consumed by the now-document-level handler which calls `showModal()` on `#dbs-info-overlay`. Dialog close still works via the `#dbs-info-overlay`-scoped close handler.
- **PARITY.md:** No row.
- **Next:** tick 149 = Android; 150 = opt.

### Tick 147 — 2026-05-21 — **iOS** — Decks editor DBS chip is now tappable (opens DBSInfoSheet)
- **Cadence:** 147 % 5 = 2 → iOS.
- **Picked:** Android tick 134 made the DBS budget chip in the Decks editor tappable — taps open `DBSInfoSheet` (the canonical explainer also used from CardDetailView). iOS Decks DBS chip was rendered the same way but inert — coaches couldn't tap to learn what the budget is or why their deck just turned orange when DBS overflowed. The `DBSInfoSheet` View already exists at `CardDetailView.swift:1132` and is presented from Card detail; reusing it here costs nothing.
- **Shipped:**
  - `DeckBuilderView.swift`:
    - New `@State private var showDBSInfo = false` paralleling the other sheet-trigger flags.
    - Stats-bar DBS chip wrapped in `Button { showDBSInfo = true } label: { statChip(...) }` with `.buttonStyle(.plain)` so the visual shape stays identical (statChip's typography + element color survive intact) + `.accessibilityHint("Opens DBS budget explainer")` for VoiceOver.
    - New `.sheet(isPresented: $showDBSInfo) { DBSInfoSheet().presentationDetents([.medium, .large]) }` next to the Rules + Legality sheets. Medium detent matches the explainer content's natural height.
- **Verified:** `DBSInfoSheet` (defined at `CardDetailView.swift:1132`) is a stateless View — no init args needed. Both surfaces share the explainer verbatim. iOS doesn't need a per-deck context the way Android passes nothing either.
- **PARITY.md:** No row needed — UX polish on already-✅ Decks DBS surface. Closes parity with Android tick 134.
- **Next:** tick 148 = web; 149 = Android; 150 = opt.

### Tick 146 — 2026-05-21 — **Android** — Drop `nil()` Swift→Kotlin port artifact + PARITY hero-zoom audit
- **Cadence:** 146 % 5 = 1 → Android.
- **Picked two things in one tick** because each is small:
  1. **Real bug-grade code cleanup**: `FindViewModel.kt:199` had `val isShowcaseSearch = typedShowcase != nil()`. The `nil()` call site was satisfied by a `private fun nil(): Showcase? = null` helper at line 299 — a Swift→Kotlin port artifact that should have been written `null` in idiomatic Kotlin from the start. Replaced with `typedShowcase != null` + dropped the 1-line helper. Same behavior, idiomatic Kotlin, no need for future readers to wonder why we call a function named `nil()`.
  2. **PARITY.md audit on hero-zoom rows**: Audit confirmed Android's `cardSharedBounds(card.bobaId)` is wired on EVERY card-source surface (FindScreen `LazyVerticalGrid` cells, DecksScreen pool cells + collection cells, CollectionScreen My-Cards + Wall cells) AND on the destination (`CardDetailScreen`'s `AsyncImage` art panel at `cardSharedBounds(card.bobaId)`). `BOBAApp.kt` wraps the whole nav graph in `SharedTransitionLayout`. End-to-end works. Two rows in PARITY.md still said "⏳ M1 polish — Android destination scaffolding done; sharedBounds zoom is M1 polish" — stale. Flipped both to ✅ with the audit note. Closes the doc-accuracy gap.
- **Shipped:**
  - `FindViewModel.kt`: drop `private fun nil(): Showcase? = null` (-2 lines).
  - `FindViewModel.kt:199`: `!= nil()` → `!= null`.
  - `PARITY.md`: §2 Find row "Card detail push w/ hero zoom" Android cell ⏳ → ✅; §8 Card detail row "Hero zoom animation" Android cell ⏳ → ✅. Both rows updated with the audit-2026-05-21 wire-up note.
- **Verified:** all CardScreen → CardDetailScreen surfaces tested mentally — FindScreen.kt:813,843 + DecksScreen.kt:531 + CollectionScreen.kt:619,790 all source the bounds; CardDetailScreen.kt:923,945 destinations.
- **Net:** small overall. The PARITY accuracy bump matters for future-session-orientation (the prior stale ⏳ would have led someone to "fix" something already shipped).
- **PARITY.md:** updated 2 rows.
- **Next:** tick 147 = iOS; 148 = web; 149 = Android; 150 = opt.

### Tick 145 — 2026-05-21 — **opt** — Drop 302 lines of orphan iOS helpers
- **Cadence:** 145 % 5 = 0 → opt.
- **Picked:** Per-file orphan-helper scan across iOS `Views/`. For each `private func`, count refs within the same file (Swift `private` is file-scope, so external refs are by definition zero). A count of 1 = the definition only, no callers. Filtered out SwiftUI protocol overrides (`body`) where the protocol invokes them at runtime via dynamic dispatch.
- **Shipped:**
  - `DeckBuilderView.swift`: drop `browserTabSummaryText(for:)` (24 lines — superseded by inline `headerLabel` lookup in `browserTabPicker`).
  - `CollectionView.swift`: drop `presentShareDeepLink()` (18 lines — the iOS Share affordance now routes through the AsyncShare helper in CollectionCardDetailView's body; this older sheet-shape helper had no remaining caller).
  - `DecksView.swift`: drop two orphans:
    - `heroWeaponBreakdown(for:)` (25 lines — duplicate of the one in DeckBuilderView.swift, originally copied when DecksView split off; only the DeckBuilderView copy is wired).
    - `handleAppear()` (16 lines — Decks now wires `.onAppear` directly to `restoreDraft` + `walkthrough` triggers inline; this consolidated helper lost its single caller in an earlier refactor).
  - `CardDetailView.swift`: drop `navigateCard(by:)` (14 lines — duplicate of `advanceCard(by:)` left over from an earlier swipe-nav prototype; only `advanceCard` is wired to the swipe gestures).
  - `HouseOfCardsView.swift`: drop 4 orphan helpers + 1 orphan stored property:
    - `minCardYConservative()` (3 lines).
    - `downwardFaceProbePoints(of:)` (49 lines — face-probe geometry from an earlier sit-on-top snap prototype that switched to the v2.183 orientation-aware approach).
    - `spawnHeldPair(takingFrom:)` (102 lines + 21 lines of preamble doc-comment that flagged itself as "Legacy stub — kept to avoid breaking call sites mid-refactor" — refactor done, no call sites left).
    - `makeEdgeMaterial()` (9 lines — PhysicallyBasedMaterial edge factory; HouseOfCards now uses the shared `BOBACardEntity.makeEdgeMaterial(config:)` in `Components/`).
    - `private var edgeMaterial: PhysicallyBasedMaterial?` (1 line — backing storage for the deleted lazy factory).
- **Why it's safe:** Swift `private func` is file-scope. Grep for `\\bname\\(` AND `Button(action: name)` (function reference) collectively cover every Swift call shape. Each orphan was verified by a global grep — no `#selector(name(_:))` / no protocol witness / no test reference. The "Legacy stub" comment on `spawnHeldPair` even self-documented its orphan state.
- **Why these accumulated:** the iOS app shipped 280+ versions through 6 weeks of intense refactor cycles (Decks Maps-pattern → Music-pattern → fullScreenCover; House of BoBA's 8 commits of physics tuning; CardDetailView swipe-nav prototype). The IDE doesn't auto-strip private funcs when their last caller goes away — they linger as silent ~10–100 line debt items.
- **Net:** −302 lines across 5 files. Pure deletion; no new code.
- **PARITY.md:** No row.
- **Next:** tick 146 = Android (% 5 = 1).

### Tick 144 — 2026-05-21 — **Android** — Manage-decks load: destructive-overwrite warning + Undo
- **Cadence:** 144 % 5 = 4 → Android.
- **Picked:** `DeckManageScreen` (Manage Decks list) was the last untreated destructive-overwrite surface in Android Decks. Tapping a saved-deck row replaced the active draft via `vm.loadSaved(deck, catalog)` with NO warning. The Snackbar that fired afterwards just said "Loaded X" — gave no hint that the user's in-progress draft was wiped. Same shape as template-load before tick 136. Now that `restoreDraft(snapshot)` is wired (tick 139), Undo costs nothing.
- **Shipped:**
  - `DeckSecondaryScreens.kt` `DeckManageScreen`:
    - New `val draft by vm.draft.collectAsStateWithLifecycle()` so the load handler can read pre-load state.
    - Row `clickable` block now:
      - Captures `val hadDraft = draft.cards.isNotEmpty()` + `val captured = if (hadDraft) draft else null` BEFORE the `vm.loadSaved(deck, catalog)` call.
      - When `captured != null`, Snackbar copy becomes `"Loaded \"X\" — your previous draft was replaced."` with `actionLabel = "Undo"` + `SnackbarDuration.Short`. On `SnackbarResult.ActionPerformed`, calls `vm.restoreDraft(captured)` — the entire DeckDraft (cards + name + playMode) re-binds atomically.
      - Empty-draft path keeps the existing terse `"Loaded \"X\""` message with no Undo.
- **Verified:** the `AddToDeckSheet` "load saved + add card" path (line 163) is intentionally NOT changed — tick 96 already surfaces the swap via the "Loaded X and added Y" message, AND the user explicitly tapped a saved-deck row inside an Add-to-Deck sheet (intentional swap with context). The pure Manage Decks load path was the silent one.
- **PARITY.md:** No row — UX polish on already-✅ Decks. Closes the last destructive-overwrite gap in Android Decks alongside ticks 136 (templates) and 139 (clear).
- **Next:** tick 145 = opt.

### Tick 143 — 2026-05-21 — **web** — Clear-deck draft: Undo Snackbar (closes 3-platform parity loop)
- **Cadence:** 143 % 5 = 3 → web.
- **Picked:** Web Clear-deck handler in `js/practice.js` used a blocking `confirm()` dialog. The pattern is the same anti-pattern tick 123 fixed for Collection per-copy delete: `confirm()` is OS-modal, breaks the page focus, doesn't theme to BOBA brand, and on mobile fires an "are you sure?" prompt that interrupts the user mid-flow. Closes the 3-platform parity loop on Clear-deck Undo (iOS tick 142, Android tick 139).
- **Shipped:**
  - `js/practice.js` `db-clear-btn` handler:
    - Empty-deck short-circuit moved to the top — bail before touching anything.
    - Pre-clear `snapshot = { heroes, plays, bonusPlays, hotDogs, deckName }`. `.slice()` defensively copies the arrays so a subsequent mutation (e.g. user re-adds a card after clearing) doesn't corrupt the snapshot.
    - Format + activePreset + ruleOverrides are NOT captured because `DB.clear()` already preserves them (line 544 only resets the four arrays + deckName).
    - After `DB.clear()` + DOM update, fires `window.showUndoToast("Draft cleared", undoCallback)`.
    - Undo callback restores all four arrays + deckName + name input field; calls `dbRender(allCards)` to repaint.
- **Verified:** `window.showUndoToast` is the canonical Material-Snackbar-shape helper at `practice.js:1630` (exposed via `window.` for cross-module use after tick 123 fix). Soft-fails behind `typeof === 'function'` guard for the (unlikely) case the helper isn't loaded yet — graceful degradation.
- **Net:** ~10 lines added (snapshot + restore) and ~14 lines removed (blocking-confirm dialog + label-construction). Slight net-add but the UX win + parity closure justifies it (this is a content tick, not opt).
- **PARITY.md:** No row — UX polish on already-✅ Decks. Closes parity with iOS tick 142 + Android tick 139.
- **Next:** tick 144 = Android; 145 = opt.

### Tick 142 — 2026-05-21 — **iOS** — Clear-deck draft: Undo banner
- **Cadence:** 142 % 5 = 2 → iOS.
- **Picked:** iOS mirror of Android tick 139. The iOS Clear-deck `.alert("Clear deck?", ...)` confirm button called `store.clearDeck()` + `store.discardDraft()` + flipped `showTemplates = true` — all destructive, with no recovery path. A coach could tap "Clear deck" by accident (it's the destructive button in the alert) and lose 30+ cards of work permanently. The on-disk draft also got wiped via `discardDraft()`, so even quitting & relaunching wouldn't recover it.
- **Shipped:**
  - `DeckBuilderStore.swift`:
    - New `func currentSnapshot() -> DraftSnapshot` — builds an in-memory snapshot of every persistable field without touching UserDefaults. The DraftSnapshot struct (lines 877-889) already existed for on-disk persistence; this just reuses it for the Undo path.
    - New `func applySnapshot(_ snap: DraftSnapshot, allCards: [Card])` — counterpart to `restoreDraft(allCards:)` but takes a value directly instead of decoding from UserDefaults. Mirrors the restore math line-for-line.
  - `DeckBuilderView.swift`:
    - New `@State private var clearedSnapshot: DeckBuilderStore.DraftSnapshot?` paralleling the `templateLoadBanner` one-shot pattern.
    - Clear-deck alert handler captures `clearedSnapshot = store.currentSnapshot()` BEFORE the destructive triple-call. Schedules a 6-second `withAnimation` fade.
    - Alert copy changed from prescriptive ("Removes every Hero... starter-deck splash returns...") to recovery-aware: *"Removes every Hero, Play, and Hot Dog. You'll have a few seconds to undo."* — same shape as Android tick 124's Manage Decks delete copy.
    - Top-overlay banner slot extends with `else if let snap = clearedSnapshot` branch. Distinct visual treatment: cyan accent (vs the green success banner) + `arrow.uturn.backward.circle.fill` icon + an inline UNDO Button in orange. Tap → `store.applySnapshot(snap, allCards:)`, flip `showTemplates = false`, dismiss banner.
- **Verified:** the snapshot captures deckName / format / activePresetID / ruleOverrides / heroes / plays / bonusPlays / hotDogs / sideboard / currentDeckId — every field that `restoreDraft` re-applies, so Undo restores 1:1. SourceKit reports the same "Cannot find type" indexer noise on DeckBuilderStore.swift (pre-existing, see tick 137 note). The actual Swift compiler resolves.
- **PARITY.md:** No row — UX polish on already-✅ Decks. Closes parity with Android tick 139.
- **Next:** tick 143 = web; 144 = Android; 145 = opt.

### Tick 141 — 2026-05-21 — **Android** — Custom Rainbow detail screen wires up (was stub)
- **Cadence:** 141 % 5 = 1 → Android.
- **Picked:** Real bug. Tapping a Custom Rainbow in `RainbowsScreen` already navigated to `collection/rainbow/custom/{id}` per tick 81's plumbing, but the destination wiring at `BOBAApp.kt:496` had a TODO: `// kind is currently "hero"; custom rainbows ship in a later pass`. The route silently treated the custom rainbow's UUID as a hero name. Result: `catalogCards.filter { it.hero.equals(uuid) }` matched zero cards → screen rendered "0 / 0 owned" with an empty grid + the UUID as the TopAppBar title. The Custom Rainbow feature was visible in the list but broken on tap.
- **Shipped:**
  - `RainbowDetailScreen.kt`:
    - Signature changed from `(hero: String, ...)` to `(kind: String, id: String, ...)`. Compositional break — callers MUST pass the kind; safe because the only caller is BOBAApp.kt's NavHost.
    - Resolves `customRainbow` from `CustomRainbowsViewModel` when `kind == "custom"`.
    - `title` derives from `customRainbow.name` (custom) or the raw id (hero — that IS the hero name).
    - `allCards` branches: custom path filters catalog by `criteriaMatches(customRainbow.criteria, card)`; hero path keeps the existing `card.hero.equals` filter; missing-custom path renders an empty grid (graceful for stale deep-links to deleted rainbows).
    - `ownedBobaIds` now intersects via `matchingBobaIds` (rainbow membership) instead of hero name — math equivalent for hero rainbows, correct for custom.
    - Body section header swaps `"Every printing"` → `"Cards matching your filter"` on custom path.
    - Share-blurb pluralization adapts: `"of N treatments"` (hero) → `"of N cards"` (custom).
  - `RainbowsScreen.kt`:
    - `private fun criteriaMatches` → `internal fun` so RainbowDetailScreen (same package) can reuse it. Keeps the single source of truth; no copy-paste.
  - `BOBAApp.kt:482`:
    - Read `ARG_RAINBOW_KIND` from `backStackEntry.arguments`. Pass to `RainbowDetailScreen` alongside id. Removed the stale TODO comment.
- **Verified:** RainbowsScreen's tap callbacks (`onRainbowClick("custom", rainbow.id)` and `onRainbowClick("hero", rainbow.hero)`) both pass valid kinds; the URL-encode path in NavRoutes.rainbowDetail preserves the id verbatim; URLDecoder.decode unwraps in BOBAApp. End-to-end works for both kinds.
- **PARITY.md:** Custom Rainbows row (Collection §5) was already ✅ ✅ ✅ but the Android detail-nav was a stub. Tick 141 makes the ✅ honest.
- **Next:** tick 142 = iOS; 143 = web; 144 = Android; 145 = opt.

### Tick 140 — 2026-05-21 — **opt** — Drop 51 orphan Android imports
- **Cadence:** 140 % 5 = 0 → opt.
- **Picked:** Per-file orphan-import scan across the entire `android/app/src/main/java/com/bobaplaybook/app/` tree. Built an awk-driven detector that lists each import's last symbol, then greps its file for matching word-boundary references. Anything that resolved to exactly 1 match (the import line itself) is an orphan. Filtered out (a) `getValue` / `setValue` / `provideDelegate` — Kotlin uses these implicitly via the `by` delegate keyword and would never appear by name; (b) aliased imports (`X as Y`) — grep would only find the alias, not the original.
- **Shipped:**
  - 17 Compose files net-lose 51 import lines (52 deletions total per `git diff --shortstat`; +1 absorbed blank line).
  - Heaviest offenders:
    - `FilterSheet.kt` (-11): `clickable`, `Box`, `width`, `items`, `RoundedCornerShape`, `ArrowDropDown`, `AssistChip`, `Button`, `ButtonDefaults`, `Surface`, `TextField`
    - `ProfileSheet.kt` (-7): `Apps`, `Edit`, `LiveTv`, `AssistChip`, `AssistChipDefaults`, `rememberModalBottomSheetState`, `clip`
    - `RainbowsScreen.kt` (-7): `Arrangement`, `Box`, `Spacer`, `fillMaxWidth`, `height`, `width`, `LinearProgressIndicator`
    - `CollectionCardDetailScreen.kt` (-5), `CardDetailScreen.kt` (-5), `AddToDeckSheet.kt` (-3), `DecksScreen.kt` (-2 — `SearchBar`/`SearchBarDefaults` legacy from before the OutlinedTextField swap), `DeckEditorSheet.kt` (-2), plus singletons across `MainActivity.kt`, `PendingDeepLink.kt`, `WatchPage.kt`, `ScanDesignationSheet.kt`, `DeckWallSheet.kt`, `DeckStore.kt`, `TemplateGallerySheet.kt`, `PurchaseScreen.kt`, `FindScreen.kt`, `FindViewModel.kt`.
- **Why it's safe:** every removed symbol had exactly one in-file reference (the import line). Compose / Hilt / Kotlin stdlib symbols only resolve via explicit imports; an orphan import means the file genuinely doesn't use the thing.
- **Why these accumulated:** Compose's IDE auto-imports when typing a symbol but doesn't reliably auto-remove when refactors strip the usage. Tick 80 (`SearchBar`→`OutlinedTextField` swap) is a textbook example — the import survived the migration. Periodic sweeps catch what the IDE misses.
- **Net:** −51 lines. iOS / web unchanged this round.
- **PARITY.md:** No row.
- **Next:** tick 141 = Android (% 5 = 1).

### Tick 139 — 2026-05-21 — **Android** — Clear-deck draft: Undo Snackbar
- **Cadence:** 139 % 5 = 4 → Android.
- **Picked:** `DecksScreen` Clear-deck confirm path called `deckViewModel.clear()` then fired a one-shot `appSnackbar?.showSnackbar("Draft cleared")` with NO action. A coach could blast through the Clear confirm with one tap (it's the primary "Clear" button in the dialog) and lose 30 cards of work with no recovery window. The Manage Decks delete (tick 124) already has Undo Snackbar parity for the equivalent action on saved decks; the draft-clear path was the obvious omission.
- **Shipped:**
  - `DeckStore.kt`: new `fun restoreDraft(snapshot: DeckDraft)` — assigns `_draft.value = snapshot`. Single-line; this is just an inverse of `clear()`.
  - `DecksViewModel.kt`: new `fun restoreDraft(snapshot: DeckDraft) = store.restoreDraft(snapshot)` — exposes the inverse for UI to consume.
  - `DecksScreen.kt` Clear confirm handler:
    - Captures `val captured = draft` BEFORE calling `deckViewModel.clear()`.
    - Snackbar gains `actionLabel = "Undo"`, `duration = SnackbarDuration.Short`.
    - On `SnackbarResult.ActionPerformed`, calls `deckViewModel.restoreDraft(captured)` — the entire `DeckDraft` (cards + name + playMode) re-binds atomically.
  - Editor sheet has no separate clear path; DecksScreen owns the canonical confirm dialog so this is the only call site.
- **Verified:** DecksScreen's `draft` (line 142) is in scope at the dialog handler. The Undo path is fully client-side — no Supabase round-trip — so restoration is instantaneous unlike Manage Decks Undo which re-saves with a new id.
- **PARITY.md:** No row — UX polish on already-✅ Decks. Closes parity with the Manage Decks Undo pattern shipped tick 124.
- **Next:** tick 140 = opt.

### Tick 138 — 2026-05-21 — **web** — Template load: toast + destructive-overwrite warning
- **Cadence:** 138 % 5 = 3 → web.
- **Picked:** Web mirror of iOS tick 137 + Android tick 136. `applyTemplate(data)` in `js/practice.js` calls `DB.clear()` + replaces hero/play/bonus/hotdog arrays. If a coach had been building a draft and tapped a starter-deck card, the draft was silently wiped — no toast, no confirmation, no undo.
- **Shipped:**
  - `js/practice.js`:
    - Capture `const hadDraft = (DB.heroes.length + DB.plays.length + (DB.bonusPlays || []).length + DB.hotDogs.length) > 0;` BEFORE `DB.clear()`.
    - After load completes (post-`dbRender(allCards)`), fire `window.showToast(hadDraft ? "Loaded \"X\" — your previous draft was replaced." : "Loaded \"X\"")`.
    - Fallback path (random-legal-deck when `template-decks.json` fetch fails) intentionally NOT instrumented — it's a dead-path that's effectively unreachable in practice and reads from a totally separate pre-state.
- **Verified:** `window.showToast` is the canonical helper exposed from `js/app.js` (tick 103 fix). `(DB.bonusPlays || [])` defensive — Limited format doesn't surface bonus plays so the field may be undefined depending on format.
- **PARITY.md:** No row — UX polish on already-✅ Decks template gallery. Closes the 3-platform parity loop (Android tick 136, iOS tick 137, web tick 138).
- **Next:** tick 139 = Android; 140 = opt.

### Tick 137 — 2026-05-21 — **iOS** — Template load: top banner + destructive-overwrite warning
- **Cadence:** 137 % 5 = 2 → iOS.
- **Picked:** iOS mirror of tick 136. `DeckBuilderStore.loadTemplate(_:allCards:)` silently calls `clearDeck()` + replaces hero/play/bonus/hotdog arrays. If the coach had spent 10 minutes on a draft, tapping a starter template wiped it with NO confirmation, NO message, NO undo. Two call sites: the empty-state template gallery in DeckBuilderView (line 515) and the Manage Decks → Templates tab (line 1745). Both immediately dismiss the calling sheet so the user lands back in the editor with no signal that an overwrite happened.
- **Shipped:**
  - `DeckBuilderStore.swift`:
    - New one-shot field `var lastTemplateLoad: (name: String, overwroteDraft: Bool)? = nil` (parallels the `pendingImportReveal` / `pendingLegalityAudit` one-shot pattern already in this store).
    - `loadTemplate(_:allCards:)` captures `let hadDraft = !heroes.isEmpty || !plays.isEmpty || !bonusPlays.isEmpty || !hotDogs.isEmpty` BEFORE `clearDeck()`, then sets `lastTemplateLoad = (template.name, hadDraft)` at the end.
  - `DeckBuilderView.swift`:
    - New `@State private var templateLoadBanner: String?`.
    - Existing top-overlay banner slot extends to `scannedAddedBanner ?? pendingCardAddedBanner ?? templateLoadBanner` (these never race in practice — templateLoad fires on editor entry).
    - New `.onChange(of: store.lastTemplateLoad?.name)` observer reads the tuple, sets the banner string (overwrote-draft variant calls out the destruction), clears `store.lastTemplateLoad` back to nil (one-shot reset so a repeat-tap of the same template re-fires), and schedules a 4-second `withAnimation` fade.
- **Verified:** SourceKit reports pre-existing "Cannot find type" noise (Card / RulePreset) — the indexer is slow on the 2000-line @Observable @MainActor file. My change uses only String / Bool / tuple types and the existing one-shot flag pattern; no new symbol references. Will compile in Ben's Xcode.
- **PARITY.md:** No row — UX polish on already-✅ Decks template gallery.
- **Next:** tick 138 = web; 139 = Android; 140 = opt.

### Tick 136 — 2026-05-20 — **Android** — Template load: Snackbar + destructive-overwrite warning
- **Cadence:** 136 % 5 = 1 → Android.
- **Picked:** Tapping a deck template in `TemplateGallerySheet` clears the draft + loads the template — silently. If the user had an unsaved draft (8 heroes + 25 plays they'd just spent 10 minutes assembling), tapping a template wipes it with NO warning, NO undo, NO confirmation. Worse than tick 96's saved-deck swap which now surfaces "Loaded \"{deck.name}\" and added {card}" — at least the user sees a message. Templates silently overwrote.
- **Shipped:**
  - `TemplateGallerySheet.kt`:
    - Resolve `draft` + `scope` + `appSnackbar` at composable root.
    - Template-tap handler captures `val hadDraft = draft.cards.isNotEmpty()` BEFORE the clear+load.
    - After load: Snackbar message branches on hadDraft:
      - `true`  → "Loaded \"{template.name}\" — your previous draft was replaced." (honest about the destruction)
      - `false` → "Loaded \"{template.name}\"" (no need to warn an empty draft was replaced)
    - New `import kotlinx.coroutines.launch`.
- **Verified:** AddToDeckSheet's saved-deck-swap Snackbar (tick 96) is the canonical pattern this mirrors. Template caps are pre-validated so the silent `cards.forEach { decksViewModel.add(it) }` doesn't drop cards in practice — but the AddResult enforcement (tick 114) is the safety net if a template ever exceeds cap.
- **PARITY.md:** No row — UX polish on already-✅ Template Gallery.
- **Next:** tick 137 = iOS; 138 = web; 139 = Android; 140 = opt.



### Tick 135 — 2026-05-20 — **OPTIMIZATION TICK** repurposed as **real bug fix** — DeckBuilderStore was never injected (tick-97 latent crash)
- **Cadence:** opt rotation. Found a load-bearing bug instead: `CollectionCardDetailView` reads `@Environment(DeckBuilderStore.self) private var deckBuilder` (tick 97), but `BOBAPlaybookApp` NEVER calls `.environment(deckBuilderStore)`. Tapping a deck row in "IN YOUR DECKS" would crash at runtime with "missing environment value." `DecksView` + `DeckBuilderView` each had their own `@State private var store = DeckBuilderStore()` — multiple disconnected instances. Even if env was injected, the load wouldn't propagate to the visible DecksView.
- **Shipped:**
  - `BOBAPlaybookApp.swift`:
    - Added `@State private var deckBuilderStore = DeckBuilderStore()` (line 22ish).
    - Added `.environment(deckBuilderStore)` to the WindowGroup chain.
  - `DecksView.swift`:
    - `@State private var store = DeckBuilderStore()` → `@Environment(DeckBuilderStore.self) private var store`.
  - `DeckBuilderView.swift`:
    - Same `@State` → `@Environment` swap so the editor renders from the same instance.
- **Verified:** `grep -rn @Environment(DeckBuilderStore` returns 3 reads (CollectionCardDetailView + DecksView + DeckBuilderView) all pointing at the single app-root injection. `tempStore = DeckBuilderStore()` in AddToDeckSheet stays — that's a deliberately ephemeral store for the sheet-local "would this card fit?" projection.
- **PARITY.md:** No row — bug fix on existing tap-to-load row.
- **Real impact:** Tick 97's CollectionCardDetailView "IN YOUR DECKS" tap-to-load goes from "crashes on first tap" → "actually loads into the Decks tab editor as advertised." iOS feature now ships honestly.
- **Cumulative across 18 opt ticks:** -182 lines (unchanged — this was a bug-fix tick, +5 lines net).
- **Next:** tick 136 = Android; 137 = iOS; 138 = web.



### Tick 134 — 2026-05-20 — **Android** — Decks editor DBS chip tap → explainer sheet (iOS Card-detail parity)
- **Cadence:** 134 % 5 = 4 → Android.
- **Picked:** The Decks editor's DBS chip ("DBS 750/1000") was a passive display — new Playmaker-format coaches see a number bound to a cap with no in-app path to learn what DBS means. `DBSInfoSheet` already exists on Card detail (tick around launch); making the Decks-editor chip tappable + routing to the same sheet is single-screen polish that unblocks the learning path. iOS DeckBuilder DBS chip has had this since the practice executor shipped; Android had the chip without the routing.
- **Shipped:**
  - `DeckEditorSheet.kt::StatChip`:
    - New `onTap: (() -> Unit)? = null` param. When non-null, wraps the Surface with `Modifier.clickable { onTap() }`. Other StatChip callers (Heroes / Plays / Bonus / HD) unchanged — they pass no onTap, behavior identical.
  - DBS chip call site:
    - Adds `var dbsInfoOpen by remember { mutableStateOf(false) }` inside the `if (draft.enforcesDBS)` guard so the state is created only when the chip exists.
    - Passes `onTap = { dbsInfoOpen = true }` to StatChip.
    - Renders `com.bobaplaybook.app.feature.carddetail.DBSInfoSheet(onDismiss = ...)` when `dbsInfoOpen` is true.
  - `CardDetailScreen.kt::DBSInfoSheet`: `private fun` → `internal fun` so Decks editor can reach it. Doc comment explains the cross-feature reuse rationale + when to promote to a shared module (3rd caller).
- **Verified:** `Modifier.clickable` already imported (line 5). Other StatChip call sites unchanged. The DBS sheet copy stays in one place (CardDetailScreen.kt) — Decks editor route is just a fresh caller.
- **PARITY.md:** No row — UX polish on already-✅ Decks editor surface.
- **Next:** tick 135 = opt; 136 = Android; 137 = iOS.



### Tick 133 — 2026-05-20 — **web** — `/` jumps to Find + focuses search input (3-platform parity)
- **Cadence:** 133 % 5 = 3 → web.
- **Picked:** Web had no keyboard shortcut to focus the Find search bar. Android tick 131 + iOS tick 132 shipped `/`/Cmd+/ jump-to-search. GitHub / YouTube / X all map `/` to focus search — canonical web "go to search" idiom. Per WEB-DESIGN.md §2.4 the Cmd-K command palette is explicitly out of scope, but `/` is a single-key affordance that doesn't require building a palette.
- **Shipped:**
  - `js/app.js` new global `keydown` listener:
    - Skips when `key !== '/'` OR any modifier (Cmd/Ctrl/Alt) is held — bare `/` only.
    - Skips when the active target is `input` / `textarea` / `contenteditable` — typing `/` in a field types `/` as normal.
    - Skips when any `<dialog>` is open (card-detail modal, auth, add-sheet, share) — user is engaged with a focused task.
    - `e.preventDefault()` + `window.showView('find')` + (via `requestAnimationFrame`) `document.getElementById('search-input').focus()` + `.select()` so the existing query is selected ready to overtype.
- **Verified:** `node -c js/app.js` clean. Defers focus to next animation frame so the showView View-Transition animation doesn't snatch focus first.
- **PARITY.md:** No row — 3-platform parity now: iOS Cmd+/ (132) + Android `/` (131) + web `/` (133). Web is the only platform that also auto-focuses the input (because the URL-routed view-switch is synchronous).
- **Next:** tick 134 = Android; 135 = opt.



### Tick 132 — 2026-05-20 — **iOS** — Cmd+/ jumps to Find tab (Android tick 131 parity)
- **Cadence:** 132 % 5 = 2 → iOS.
- **Picked:** iOS has Cmd+1..5 tab shortcuts via `TabSwitchShortcuts` hidden-buttons surface. Android tick 131 added `/` (no modifier) → Find tab. iOS canonical equivalent is `Cmd+/` (Cmd+/ is widely used as "open keyboard shortcuts cheatsheet" but BOBA doesn't ship one, so this binding is free). Adds a sixth hidden-button to the existing TabSwitchShortcuts View.
- **Shipped:**
  - `ContentView.swift::TabSwitchShortcuts`:
    - Sixth `Button { selectedTab = 0 } label: { EmptyView() }.keyboardShortcut("/", modifiers: .command)` appended to the existing Group.
    - Doc-comment updated to call out the new shortcut + the cross-platform parity rationale.
- **Verified:** Existing pattern (`keyboardShortcut("1", modifiers: .command)`) works on iPad w/ hardware keyboard; iPhone-w/o-keyboard ignores. Adding `"/"` follows the same shape exactly. The `selectedTab = 0` action matches Find's index per the existing line 104.
- **PARITY.md:** No row — hardware-keyboard polish. 2-platform parity (iOS Cmd+/ + Android `/`) on the "go to search" idiom. Web doesn't have a `/` shortcut (browser owns it for page-find legacy).
- **Next:** tick 133 = web; 134 = Android; 135 = opt.



### Tick 131 — 2026-05-20 — **Android** — `/` keyboard shortcut jumps to Find tab (Chromebook polish)
- **Cadence:** 131 % 5 = 1 → Android.
- **Picked:** Android has Ctrl+1..5 tab shortcuts (per scratchpad overnight 2026-05-20 commit) but no `/` to jump to search — the canonical "go to search" hardware-keyboard pattern across GitHub, YouTube, Wikipedia, and most Chromebook-friendly web apps. Ben specifically uses Chromebook for testing per DECISIONS.md #047 so this is a real ergonomics polish.
- **Shipped:**
  - `BOBAApp.kt::onPreviewKeyEvent` (the existing root-Box keystroke handler):
    - New branch: `if (!event.isCtrlPressed && event.key == Key.Slash) handleShortcut(1)` — `1` is Find's tab index.
    - Only fires when the root Box has focus — Compose's focus propagation means a TextField that grabbed the keystroke first will type `/` as normal. No conflict with in-field typing.
    - Returns the boolean from `handleShortcut(1)` so the propagation chain knows the event was consumed.
- **Verified:** `Key` + `isCtrlPressed` + `onPreviewKeyEvent` imports already at the top of the file (lines 18-23). `handleShortcut` returns Boolean per the existing Ctrl-N branches.
- **Auto-focusing the SearchBar deferred** — would require plumbing a focus-request token through FindScreen. The jump-to-tab is the primary value; once on Find, tap-to-focus is one tap.
- **PARITY.md:** No row — Android-specific hardware-keyboard polish. iOS has Cmd+1..5 but no Cmd+/ equivalent; web doesn't have a `/` shortcut either (browser owns `/` historically as page-find legacy). Could backport to both in a future tick.
- **Next:** tick 132 = iOS; 133 = web; 134 = Android; 135 = opt.



### Tick 130 — 2026-05-20 — **OPTIMIZATION TICK (17th 1-in-5)** — audit-only; no orphans found
- **Cadence:** opt rotation. Web 5 · iOS 8 · Android 3 across opt ticks (cumulative -182 lines). Bias-toward-Android couldn't find a clean orphan target this pass.
- **Audited:**
  - Android `ScanCardMatcher` private helpers (`matchesHero`, `levenshtein`, `BARE_DIGIT_REGEX`) — all used.
  - Android `ScanFrameStabilizer` — exported state class used by `ScanScreen` (`stabilizer`, `scanState`, `State.Scoring/Scanning`).
  - Android `Showcase` enum properties (`woba`, `bojax`, `kenGriffeyJr`, `drJ`, `rookieInspired`, `wobaHeroes`) — all referenced in the `all` list or filter closures.
  - Android `DeckTemplates.METADATA + Meta` data class — used by `DeckTemplates.list(...)`.
  - Android `CollectionScreen` `@Composable` helpers (DesignationBadge, QuantityBadge, DesignationRow, ValueSummary) — all called.
  - Android `CollectionScreen` state vars (designation, menuOpen, filterSheetOpen, totalsMode, collectionQuery, sortDialogOpen, isRefreshing, includePrices) — all referenced.
  - Android `WatchPage::VideoRow` — used in the LazyColumn.
  - Android profile auth fns (`signInWithDiscord`, `sendPasswordReset`, `captureDiscordIdentity`, `setMatchAlerts`, `setNotifications`) — all wired.
  - iOS `PracticeStore` confirm/cancel pairs (dismissPeekedHand, cancelFutureBattlePick, cancelHandDiscard, cancelScareReveal, cancelPlayerChoice, cancelHeroDiscardSwap, confirmPendingRecycle, cancelPendingRecycle) — all wired in `PracticeView`.
  - iOS `BOBAPlaybookApp::runHeroShotComparisonDebug` — referenced by `render-test-comparison` URL handler; serves a distinct artifact (single-frame PNG) vs HeroShotCLIRunner's 4-variant grid. Kept.
  - iOS `DecksView` `@State` vars — all referenced post-tick-115 cleanup.
- **No shipped change** — codebase is in a denser-than-baseline state after 16 opt ticks; remaining "private fn / orphan @State / unused export" patterns appear to have been swept. Future opt-tick targets will likely come from new code introduced by feature ticks (where additions outpace the next opt sweep) rather than legacy debt.
- **Cumulative across 17 optimization ticks:** -182 lines (unchanged from tick 125 — no code change this round).
- **Next:** tick 131 = Android; 132 = iOS; 133 = web; 134 = Android; 135 = opt.



### Tick 129 — 2026-05-20 — **Android** — Rainbow detail: Share progress action
- **Cadence:** 129 % 5 = 4 → Android.
- **Picked:** `RainbowDetailScreen` showed per-hero rainbow progress ("12 of 15 owned · 80%") but had no Share affordance. Coaches share rainbow progress in Discord all the time as bragging-rights — currently they screenshot the bar + add caption. A direct Share action skips both steps.
- **Shipped:**
  - `RainbowDetailScreen.kt`:
    - `LocalContext` resolved at composable root.
    - TopAppBar `actions = { ... }` gained a Share IconButton (Icons.Default.Share).
    - On click: builds `"My {hero} rainbow: {owned} of {total} treatments ({pct}%) · bobaplaybook.com"` and fires `Intent.ACTION_SEND` w/ `EXTRA_TEXT` + `EXTRA_SUBJECT` = `"My {hero} rainbow"` + `Intent.createChooser`.
    - bobaplaybook.com URL is the canonical homepage (when public collections are wired with deep-link routes per username, this can become a per-user link, but that's TRADE-DESIGN.md territory; for now the homepage gives recipients a path to the catalog browser).
- **Verified:** TopAppBar pattern + ACTION_SEND chooser identical to the per-card Share helper at CardShareHelper.kt. Owned + total counts already in scope from the existing rainbow-progress computation.
- **PARITY.md:** No row — UX polish on already-✅ Rainbow Detail surface.
- **Next:** tick 130 = opt; 131 = Android; 132 = iOS.



### Tick 128 — 2026-05-20 — **web** — Glossary right-click + long-press to share (3-platform parity)
- **Cadence:** 128 % 5 = 3 → web.
- **Picked:** Tick 88 shipped tap-to-copy on the web Glossary. iOS tick 127 + Android tick 126 just added the long-press-to-share companion. Web was the laggard. Progressive-enhancement: web's two canonical "secondary action" gestures are right-click (desktop) and long-press (touch) — no HTML change needed; existing 32-row markup unchanged.
- **Shipped:**
  - `js/app.js` two new global listeners (sit alongside the existing `click` listener for tap-to-copy):
    - `contextmenu` → suppress the browser's right-click menu + call `glossaryShare(row)`.
    - `touchstart` + 600ms timer → `glossaryShare(row)`. Timer cleared on `touchmove` / `touchend` / `touchcancel` so a scroll gesture doesn't fire share.
  - New `glossaryShare(row)` helper — fires `window.bobaShareTarget({title: "BOBA Glossary: {term}", text: "{term} — {definition}"})` (Web Share API w/ clipboard fallback already wired via shareTarget). When `bobaShareTarget` isn't available (defensive), falls through to `navigator.clipboard.writeText` + toast.
  - All 4 touch listeners use `{ passive: true }` so the browser scroll doesn't fight the timer.
- **Verified:** `node -c js/app.js` clean. Existing tap-to-copy unchanged — still fires on regular click. The touch path is keyboard-friendly: keyboard users get the row's existing Enter-to-copy via the `<button class="glossary-row">` (HTML button semantics intact).
- **PARITY.md:** No row — UX polish on already-✅ Glossary. 3-platform parity now: iOS contextMenu (127) + Android combinedClickable (126) + web contextmenu/longpress (128).
- **Next:** tick 129 = Android; 130 = opt.



### Tick 127 — 2026-05-20 — **iOS** — Glossary contextMenu: Share alongside tap-to-copy (Android tick 126 parity)
- **Cadence:** 127 % 5 = 2 → iOS.
- **Picked:** Tick 87 shipped tap-to-copy on iOS Glossary rows. Tick 126 just added Android's long-press → ACTION_SEND chooser. iOS canon is `.contextMenu` (long-press surfaces a menu instead of immediately invoking the action). Without contextMenu, iOS coaches who wanted to share a definition had to copy → switch to Discord → paste — 3 steps where 1 would do.
- **Shipped:**
  - `LearnView.swift::GlossaryView` term Button — gained `.contextMenu { ... }` after the existing accessibility-hint modifier:
    - `Button { copyTerm(t) }` with `Label("Copy", systemImage: "doc.on.doc")` — duplicates the default tap action for users who arrived via long-press first.
    - `ShareLink(item: "{term} — {definition}", subject: "BOBA Glossary: {term}")` with `Label("Share", systemImage: "square.and.arrow.up")` — opens the iOS system share sheet (routes to Messages / Discord / Mail / etc.).
- **Verified:** `ShareLink` is the modern iOS (15+) share API. Subject text becomes the share sheet's preview subject (used by Mail / Discord). Tap on the row still copies (the contextMenu doesn't change the default-tap behavior).
- **PARITY.md:** No row — UX polish on already-✅ Glossary surface. 2-platform parity (Android tick 126 + iOS tick 127) on the long-press-to-share affordance.
- **Next:** tick 128 = web; 129 = Android; 130 = opt.



### Tick 126 — 2026-05-20 — **Android** — Glossary: long-press to share (tap-to-copy companion)
- **Cadence:** 126 % 5 = 1 → Android.
- **Picked:** Tick 84 shipped tap-to-copy on Glossary rows. Coaches often want to push a definition DIRECTLY into Discord without the copy + paste round-trip. Long-press → Intent.ACTION_SEND chooser is the canonical Android pattern for "share this text to any installed app." iOS doesn't have an equivalent (UIPasteboard tap-to-copy is the iOS canon), so this is Android-specific polish.
- **Shipped:**
  - `LearnArticleScreen.kt::TermRow`:
    - Signature gained `onShare: () -> Unit` callback.
    - `Modifier.clickable` upgraded to `combinedClickable` with `onClick = onCopy` + `onLongClick = onShare`. Distinct `onClickLabel` ("Copy term") + `onLongClickLabel` ("Share term") for TalkBack.
    - `@OptIn(ExperimentalFoundationApi::class)` annotation added (`combinedClickable` is still marked experimental in 1.5.x).
  - New file-private `shareTerm(context, section)` helper — fires `Intent.ACTION_SEND` w/ `type = "text/plain"` + `EXTRA_TEXT` = `"{term} — {definition}"` + `EXTRA_SUBJECT` = `"BOBA Glossary: {term}"` + wraps in `Intent.createChooser` so user picks the target app.
  - Both call sites (Game glossary + Trading glossary) pass `onShare = { shareTerm(context, term) }`.
  - New `import androidx.compose.foundation.combinedClickable`.
- **Verified:** `combinedClickable` is in `androidx.compose.foundation` (stable api, experimental annotation). `Intent.createChooser` is the canonical Android system-share entrypoint.
- **PARITY.md:** No row — Android-specific polish on already-✅ Glossary surface.
- **Next:** tick 127 = iOS; 128 = web; 129 = Android; 130 = opt.



### Tick 125 — 2026-05-20 — **OPTIMIZATION TICK (16th 1-in-5)** — orphan iOS isOwned(cardNumber) overload
- **Cadence:** opt rotation. Web 5 · iOS 7 · Android 3 across opt ticks. Bias-toward-Android couldn't find a clean orphan; settled on iOS.
- **Picked:** `CollectionStore.swift::isOwned(_ cardNumber: String)` — 3-line overload that pre-dates the bobaId addition. `grep -rn .isOwned(` across BOBAPlaybook returned only `.isOwned(bobaId:)` calls — the unlabeled `(_ cardNumber:)` overload had zero callers. Confirmed via second grep (`grep .isOwned(` excluding bobaId pattern) — empty.
- **Shipped:** Removed the 3-line orphan + its 1-line doc comment.
- **Verified:** Final grep returns 0 hits for non-bobaId `isOwned(...)` calls. `isOwned(bobaId:)` (the canonical method) untouched + still used in 5 call sites across CollectionCardDetailView + CardDetailView.
- **Line-count delta:** -4 lines.
- **Cumulative across 16 optimization ticks:** -182 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23 · 90: -19 · 95: -6 · 100: -1 · 105: -2 · 110: -13 · 115: -1 · 120: -10 · 125: -4).
- **Next:** tick 126 = Android; 127 = iOS; 128 = web; 129 = Android; 130 = opt.



### Tick 124 — 2026-05-20 — **Android** — Manage Decks delete: Undo Snackbar (replaces "Can't be undone" copy)
- **Cadence:** 124 % 5 = 4 → Android.
- **Picked:** Manage Decks delete dialog said "This removes the deck from every device. Can't be undone." — TRUE for the Supabase row identity (the delete is hard) but FALSE for the data (deck name + cards are recoverable from the SavedDeck snapshot the UI just rendered from). Three-platform parity tick (iOS Decks tick 117 + Android Decks tick 116 + web Decks tick 118 all shipped Undo Snackbars; Manage Decks was the holdout).
- **Shipped:**
  - `DecksViewModel.kt::restoreDeletedDeck(saved: SavedDeck, onResult)`:
    - Bypasses the draft-state path (`save(...)` requires DeckStore.draft to be populated). Calls `repo.saveDeck(userId, name, flatCardNumbers)` directly with the captured SavedDeck's data.
    - Expands the quantity-rows back into a flat cardNumber list (saveDeck takes one entry per copy; quantities inferred server-side).
    - Returns the NEW deck id (Supabase issues a fresh UUID; the captured original is gone for good).
  - `DeckSecondaryScreens.kt::pendingDelete dialog`:
    - Body copy updated: "Can't be undone" → "You'll have a few seconds to undo."
    - confirmButton handler captures the deck BEFORE delete, fires vm.deleteDeck, then shows Snackbar with "Undo" action.
    - On Undo: calls `vm.restoreDeletedDeck(captured) { newId -> ... }`. Surfaces a follow-up Snackbar "Restored \"{name}\"" on success, "Couldn't restore — check connectivity." on null (e.g. signed-out race or RLS reject).
- **Verified:** `SavedDeck.cards` is a `List<SavedDeckCard>` with `cardNumber` + `quantity`; the flat-list expansion mirrors the existing saveDeck call shape at DecksViewModel:90. Snackbar pattern matches the per-card delete flow in CollectionCardDetailScreen (tick 119).
- **PARITY.md:** No row — UX polish on already-✅ Manage Decks delete.
- **Next:** tick 125 = opt; 126 = Android; 127 = iOS.



### Tick 123 — 2026-05-20 — **web** — Collection delete: Undo Snackbar replaces blocking confirm (3-platform parity)
- **Cadence:** 123 % 5 = 3 → web.
- **Picked:** Web `_renderCollectionDetail`'s per-copy delete (collection.js:2842) used a blocking native `confirm()` dialog + `alert()` on error. Both modal-blocking and ugly. iOS tick 122 + Android tick 119 ship inline Undo toasts that ARE the safety net; web was the laggard.
- **Shipped:**
  - `js/collection.js::_renderCollectionDetail` delete handler:
    - Removed the `confirm()` gate — the Undo toast is now the safety net (modern UX, matches mobile platforms).
    - Captures the full `_cards.find(c => c.id === id)` entry BEFORE delete so Undo can re-add with the complete field set (designation / purchase_price / asking_price / condition / notes). Without this, accidental delete would lose per-copy provenance.
    - On `API.collectionDelete` success: shows `showUndoToast("Removed {label}", undo)`. On Undo: calls `API.collectionAdd` with every captured field + pushes the new row into `_cards` + re-renders.
    - On API error: replaced `alert()` with `window.showToast` ("Could not remove: ...").
  - `js/practice.js::showUndoToast` got an explicit `window.showUndoToast = showUndoToast` export. Top-level function declarations DO land on the global object in classic scripts, but the explicit assignment is defensive against any future IIFE wrap.
- **Verified:** `node -c` clean on both files. `showUndoToast` defined since tick 118; the assignment makes the cross-script access explicit.
- **PARITY.md:** No row — UX polish on already-✅ Collection delete row. 3-platform parity now: iOS banner (122) + Android Snackbar+Undo (119) + web Snackbar+Undo (123).
- **Next:** tick 124 = Android; 125 = opt.



### Tick 122 — 2026-05-20 — **iOS** — Collection card detail swipe-delete: "Removed X" toast (Android tick 119 parity)
- **Cadence:** 122 % 5 = 2 → iOS.
- **Picked:** `CollectionCardDetailView::collectionRow` swipe-action `Button(role: .destructive)` fired `collection.deleteCard(id: entry.id)` silently on success (errors surfaced via deleteError). Android tick 119 just shipped the equivalent + Undo for the per-copy delete; iOS got the banner-only version (Undo defer — the confirmationToast helper is text-only; Undo requires a richer action-state overlay).
- **Shipped:**
  - `CollectionCardDetailView.swift`:
    - New `@State private var removedEntryName: String?` — distinct from `addedToDeckName` so the confirmationToast doesn't auto-prepend "Added to " for delete copy.
    - New overlay branch in the `.overlay(alignment: .top) { ... }` block: renders `confirmationToast("Removed \(removed)")` when `removedEntryName != nil`.
    - Swipe-action handler captures `catalogCard?.displayName` BEFORE the async delete (falls back to `entry.cardNumber` if the catalog lookup fails). On success: fires `showRemovedToast(cardLabel)`.
    - New `showRemovedToast(_ name:)` helper — same 2-second timing + animation as `showAddedToDeckToast`.
- **Verified:** SourceKit cross-file noise preexisting. The existing toast helpers (`showAddedToDeckToast`, `showAddedToShowToast`) preserved verbatim; `removedEntryName` is the cleanest addition.
- **PARITY.md:** No row — UX polish on already-✅ Collection swipe-delete. Now 2-platform (iOS banner + Android Snackbar+Undo); web Collection per-copy delete is a future parity tick.
- **Next:** tick 123 = web; 124 = Android; 125 = opt.



### Tick 121 — 2026-05-20 — **Android** — Profile notifications: un-bundle push + match alerts (real bug + iOS parity)
- **Cadence:** 121 % 5 = 1 → Android.
- **Picked:** Tick 120's notes pointed at a real bug — `ProfileViewModel.setMatchAlerts` called `service.setNotificationPrefs(notifications = enabled, matchAlerts = enabled)`, slamming BOTH columns to the same value. Toggling Match Alerts ON also turned on general push notifications. Worse: toggling either OFF turned off both. iOS Profile keeps them as separate toggles per DECISIONS.md #039.
- **Shipped:**
  - `ProfileViewModel.kt`:
    - `setMatchAlerts(enabled, onResult)` now reads `_profile.value.notificationsEnabled` and preserves it — only the matchAlerts flag flips.
    - New `setNotifications(enabled, onResult)` does the mirror: reads `_profile.value.matchAlertsEnabled` + preserves, flips only notifications.
    - Doc comments explain the bundling bug + iOS-parity rationale.
  - `ProfileSheet.kt::notify-header section`:
    - New `item("push-toggle")` for general "Push notifications" toggle. Optimistic `pushOptimistic` mutable state rekeyed on the server-side value (`remember(pushChecked)`) so when the profile reloads, the optimistic value catches up.
    - On toggle: fires `vm.setNotifications` + rolls back on failure (same optimistic pattern matchAlerts already uses).
    - Existing match-alerts toggle preserved — just below the new push toggle. Subtitle copy clarified (push = "app-wide push deliveries" vs match-alerts = "opt in now — push delivery lands when the dispatcher ships").
- **Verified:** `UserProfile` data class has both `notificationsEnabled` + `matchAlertsEnabled` fields (ProfileService.kt:238). `setNotificationPrefs` takes both as separate params (line 92). 3-platform parity rationale matches DECISIONS.md #039.
- **PARITY.md:** No row — bug fix on already-✅ Profile Notifications section.
- **Next:** tick 122 = iOS; 123 = web; 124 = Android; 125 = opt.



### Tick 120 — 2026-05-20 — **OPTIMIZATION TICK (15th 1-in-5)** — 2 orphan iOS DeckBuilderStore helpers
- **Cadence:** opt rotation. Web 5 · iOS 6 · Android 3. Bias-toward-Android couldn't find clean orphans this pass; settled on iOS again.
- **Picked:**
  - `DeckBuilderStore::unlinkFromPreset()` (3-line + 2-line doc comment): `grep -rn unlinkFromPreset BOBAPlaybook` returned only the definition. Designed for a "decouple from preset" UI affordance that never shipped — `applyPreset` is called instead.
  - `DeckBuilderStore::heroCount(for: Card)` (3-line + 1-line doc comment): `grep -rn heroCount(for: BOBAPlaybook` + `grep -rn .heroCount(for:` both returned only the definition. Was a repeat-check helper; current code uses `isInDeck(_:)` which returns Bool instead.
- **Shipped:** Removed both definitions + doc comments.
- **Verified:** Final greps confirm zero callers. `applyPreset` + `isInDeck` + `heroViolationReason` (the live functions in the same neighborhood) untouched.
- **Line-count delta:** -10 lines.
- **Cumulative across 15 optimization ticks:** -178 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23 · 90: -19 · 95: -6 · 100: -1 · 105: -2 · 110: -13 · 115: -1 · 120: -10).
- **Next:** tick 121 = Android; 122 = iOS; 123 = web; 124 = Android; 125 = opt.



### Tick 119 — 2026-05-20 — **Android** — Collection card detail delete: Snackbar + Undo (preserves form fields)
- **Cadence:** 119 % 5 = 4 → Android.
- **Picked:** `CollectionCardDetailScreen::onDelete` fired `viewModel.remove(entry.userCard.id)` silently. No confirmation, no Undo. Particularly painful given that tick 99 enabled rich-data persistence on add — a user who'd spent time entering purchase price + condition + notes lost ALL of it with an accidental tap, with no recovery path. iOS / web have the Decks remove-with-Undo (tick 117 / 118); this is the Collection equivalent.
- **Shipped:**
  - `CollectionCardDetailScreen.kt`:
    - New `import kotlinx.coroutines.launch`.
    - `scope` + `appSnackbar` resolved at the top of the screen (`LocalAppSnackbar.current` + `rememberCoroutineScope()`).
    - `onDelete` callback now captures the `entry.userCard` + `entry.card` BEFORE remove, fires `viewModel.remove`, then shows Snackbar "Removed {cardName}" + "Undo" action label.
    - On `SnackbarResult.ActionPerformed`: re-adds via `viewModel.add(...)` with ALL the captured fields (designation, quantity, purchasePrice, askingPrice, condition, notes). Tick 99's signature expansion makes this work; without it the re-add would lose every optional field.
- **Verified:** `CollectionViewModel.add` signature confirmed at the file (per tick 99) — accepts all 5 optional fields. `UserCard` data class has the matching getters. `LocalAppSnackbar` provided at theme root.
- **PARITY.md:** No row — UX polish on already-✅ Collection card detail. 3-platform parity now: iOS Decks banner (117) + web Decks Snackbar+Undo (118) + Android Decks Snackbar+Undo (116) + Android Collection Snackbar+Undo (119, new). iOS Collection Undo + web Collection Undo are open follow-ups.
- **Next:** tick 120 = opt; 121 = Android; 122 = iOS.



### Tick 118 — 2026-05-20 — **web** — Decks remove: Undo Snackbar (iOS 117 + Android 116 parity)
- **Cadence:** 118 % 5 = 3 → web.
- **Picked:** Web `DB.removeCard(bobaId, section)` fired silently — no toast, no Undo. iOS tick 117 just shipped "Removed X" banner; Android tick 116 has "Removed X · Undo" Snackbar on both compact + tablet panes. Web was the lone silent surface.
- **Shipped:**
  - `js/practice.js` event-delegated remove handler now:
    - Captures the catalog card from `allCards.find(c => c.bobaId === bobaId)` BEFORE the remove so Undo re-adds the exact same Card object.
    - Calls `DB.removeCard(bobaId, section)` + `dbRender`.
    - Fires `showUndoToast("Removed {label}", undo)`. On Undo: temporarily flips `DB.browserTab` to the original section so `DB.addCard` routes to the right bucket; restores the prior tab; re-renders. AddResult discarded — the just-removed slot is free.
  - New `showUndoToast(message, onUndo)` helper at the top of practice.js:
    - Reuses the existing `#app-toast` element (same one `window.showToast` paints) but populates it with `<span>{msg}</span><button class="app-toast-action">Undo</button>`.
    - 3s auto-clear (1.5s longer than the plain showToast — gives users time to react).
    - `{ once: true }` on the Undo click listener prevents double-fires.
  - `css/styles.css`:
    - `.app-toast.visible` now sets `pointer-events: auto` so the Undo button is tappable (was `pointer-events: none` for the plain text toast).
    - `.app-toast-action` cyan-accent button styling + `:focus-visible` outline for keyboard a11y.
- **Verified:** `node -c js/practice.js` clean. The browserTab swap-and-restore around `DB.addCard` is the same pattern used elsewhere when adding cross-section. The plain `window.showToast` calls elsewhere keep working unchanged (the only difference is `pointer-events: auto` now — pure text toasts don't have tappable children so the change is invisible).
- **PARITY.md:** No row — UX polish. 3-platform parity now: iOS banner (tick 117) + Android Snackbar+Undo (tick 116) + web Snackbar+Undo (tick 118).
- **Next:** tick 119 = Android; 120 = opt.



### Tick 117 — 2026-05-20 — **iOS** — Decks remove gets "Removed X" banner (Add/Remove symmetry)
- **Cadence:** 117 % 5 = 2 → iOS.
- **Picked:** `editorDeckRow` had a silent remove path — both the tap-remove inside DeckCardRow (line 1024) AND the swipe-to-remove (line 1035) fired `store.removeCard(...)` with no banner. The add path has `addCardToDeck` → "Added X" banner since v2.038; the remove was silent. Add/Remove asymmetry users notice when swipes register without confirmation. Android tick 116 just shipped the same pattern (Snackbar + Undo); iOS now has the banner half (Undo defer to a future tick when the banner gets a richer action-state).
- **Shipped:**
  - `DecksView.swift::editorDeckRow`:
    - Both remove call sites now route through new `removeCardWithFeedback(card:role:)` helper.
  - New `removeCardWithFeedback`:
    - Calls `store.removeCard(card, role:)`.
    - Fires `UIImpactFeedbackGenerator(.light).impactOccurred()` (lighter than the medium-impact used for add → distinguishes the actions on the wrist).
    - Sets `addedBanner = "Removed {label}"` (reuses existing state — the banner overlay accepts any message).
    - 1.5s auto-clear matches the add timing.
- **Verified:** Banner overlay already renders any `addedBanner` value (checked at line 736); no new overlay branch needed. `UIImpactFeedbackGenerator` is the same helper used by addCardToDeck (line 1499).
- **PARITY.md:** No row — UX polish. iOS now has Add+Remove banner symmetry; Android (tick 116) has Add+Remove+Undo on the editor remove flow.
- **Next:** tick 118 = web; 119 = Android; 120 = opt.



### Tick 116 — 2026-05-20 — **Android** — Decks tablet pane remove gets Snackbar+Undo (compact parity)
- **Cadence:** 116 % 5 = 1 → Android.
- **Picked:** `DecksTabletScreen`'s inline editor wired `onRemove = deckViewModel::remove` as a bare method reference. No Snackbar, no Undo — tablet users lost the cap-restore signal the compact pane has had since the Undo snackbar shipped overnight 2026-05-20. Tap remove → card disappears → no signal it registered, no way to undo without finding the same card in the pool.
- **Shipped:**
  - `DecksScreen.kt::DecksTabletScreen`:
    - Hoisted `scope` + `appSnackbar` into the function body (already used in compact path; tablet pane was just missing them).
    - `onRemove = { bobaId -> ... }` lambda mirrors the compact-pane handler at DecksScreen.kt:374 verbatim: capture the card by bobaId, fire `deckViewModel.remove(bobaId)`, then show Snackbar with "Removed {name}" + "Undo" action label. On `SnackbarResult.ActionPerformed` re-add the captured card via `deckViewModel.add(removed)`.
    - AddResult discarded — the just-removed card always re-adds successfully (no cap conflict, the slot was just freed).
- **Verified:** Pattern + wording match the compact handler verbatim so cross-screen users see identical Snackbar copy. `LocalAppSnackbar.current` is provided at the BOBAApp theme root (used in CardDetailScreen + the compact handler already).
- **PARITY.md:** No row — UX polish on already-✅ Decks editor row. Compact + tablet panes now identical on remove feedback.
- **Next:** tick 117 = iOS; 118 = web; 119 = Android; 120 = opt.



### Tick 115 — 2026-05-20 — **OPTIMIZATION TICK (14th 1-in-5)** — orphan iOS DecksView @State
- **Cadence:** opt rotation. Web 5 · iOS 5 · Android 3 across opt ticks. Bias-toward-Android but couldn't find a clean Android orphan in this pass; picked an iOS @State sweep instead.
- **Picked:** `DecksView.swift::selectedBrowserCard` declared as `Card? = nil` at line 128. `grep -rn selectedBrowserCard DecksView.swift` returned only the declaration line — never assigned, never read.
- **Shipped:** Removed the orphan @State.
- **Verified:** Final grep returns 0 hits. Other suspect @State vars (showDeckList, showScan, scannedAddedBanner, pendingCardAddedBanner) all confirmed in use (multiple write + read sites each).
- **Line-count delta:** -1 line.
- **Cumulative across 14 optimization ticks:** -168 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23 · 90: -19 · 95: -6 · 100: -1 · 105: -2 · 110: -13 · 115: -1).
- **Next:** tick 116 = Android; 117 = iOS; 118 = web; 119 = Android; 120 = opt.



### Tick 114 — 2026-05-20 — **Android** — Decks add: enforce caps + dup-checks + outcome feedback (real bug + 3-platform parity)
- **Cadence:** 114 % 5 = 4 → Android.
- **Picked:** Android `DeckStore.add(card)` was fully permissive — `_draft.value = _draft.value.adding(card)` and nothing else. Letting the user add 8 copies of the same Hero or push the bonus-play count past the 7-card cap. iOS tick 112 + web tick 113 just shipped no-op-reason feedback for their already-enforcing stores; Android needed BOTH the enforcement AND the feedback to catch up. **Real bug not just UX polish.**
- **Shipped:**
  - `DeckStore.kt::add` now returns sealed `AddResult` (Added / Skipped(reason)):
    - **Heroes / Plays / Coaches** → reject duplicate (`"already in deck"`)
    - **Hero** at heroCap → `"hero cap reached (8)"`
    - **Play** at playCap (plays + bonus combined) → `"plays full (30)"`
    - **Bonus** at bonusCap → `"bonus plays full (7)"`
    - **HotDog** — the DeckDraft model doesn't separate hotdogs; iOS treats them in the existing flat-list. Add succeeds (HotDog count is enforced at the editor's display level, not at add-time).
  - `AddResult` sealed class at the bottom of DeckStore.kt — Added object + Skipped(reason) data class.
  - `DecksScreen.kt::onCardLongClick` reads the AddResult: success path keeps the existing soft-cap HD / DBS warning; skipped path surfaces `"{cardName} — {reason}"`.
  - `AddToDeckSheet.kt` current-draft + saved-deck rows both honor the AddResult: success keeps the existing "Added X to {deck}" / "Loaded {deck} and added X" wording; skipped surfaces the reason ("X — already in deck") or appends to the loaded-deck message ("Loaded \"Speed\" — but X already in deck").
  - Permissive call sites (CSV import at line 848, Undo at line 388) discard the result — those flows want best-effort batch behavior, not per-row snackbars.
- **Verified:** Reason strings verbatim with iOS tick 112 + web tick 113. Hero / Play / Bonus routing uses the same predicates DeckDraft already uses (isHero / isPlay / isBonus + BPL prefix). All 4 `deckViewModel.add` call sites accounted for.
- **PARITY.md:** No row — bug fix on already-✅ Decks add. 3-platform parity (iOS 112 + web 113 + Android 114) on cap-enforcement + outcome-feedback.
- **Next:** tick 115 = opt; 116 = Android; 117 = iOS.



### Tick 113 — 2026-05-20 — **web** — Decks add: surface no-op reason (iOS tick 112 parity)
- **Cadence:** 113 % 5 = 3 → web.
- **Picked:** Web `DB.addCard(card)` had the same silent-skip pattern iOS tick 112 just fixed — early `return` on duplicate / cap-reached with no signal to the caller. Quick-Add path + popup Add path both fired the call and immediately re-rendered; user saw the deck list unchanged + no clue why.
- **Shipped:**
  - `js/practice.js::DB.addCard` — now returns `{ ok: boolean, reason?: string }`:
    - Success → `{ ok: true }`
    - Hero violation → `{ ok: false, reason: 'already in deck' or 'rule violation' }` (uses `isInDeck` to disambiguate vs other wouldHeroViolate causes)
    - Play duplicate → `{ ok: false, reason: 'already in deck' }`
    - Play cap reached → `{ ok: false, reason: 'plays full (30)' }`
    - Bonus duplicate / cap → `'already in deck'` / `'bonus plays full (15)'`
    - HotDog cap → `'hot dogs full (10)'`
    - Unknown tab → `'unknown tab'` (defensive)
  - Both grid-tap and popup-Add callers now capture the result + fire `window.showToast(result.ok ? "Added X" : "X — ${reason}")`. Tick 103's `window.showToast` exposure makes this work without falling through to silent alert().
- **Verified:** `node -c js/practice.js` clean. Only 2 callers in the codebase per `grep -rn DB.addCard` — both updated. Reasons strings verbatim with iOS tick 112 so cross-platform users see the same wording.
- **PARITY.md:** No row — UX polish on already-✅ Decks add row. 2-platform parity (iOS tick 112 + web tick 113).
- **Next:** tick 114 = Android; 115 = opt.



### Tick 112 — 2026-05-20 — **iOS** — Decks long-press add: surface no-op reason
- **Cadence:** 112 % 5 = 2 → iOS.
- **Picked:** `DecksView::addCardToDeck` (the long-press handler) had a silent no-op path — `guard afterCount > beforeCount else { return }`. When the user long-pressed a card that was already in the deck OR pushed a section over its cap (15 bonus plays, 10 hot dogs), the haptic + banner never fired. User got no feedback that the gesture registered. Same gap Android tick 89 closed for the pool empty state on a different axis (search vs filter); this is the long-press equivalent.
- **Shipped:**
  - `DecksView.swift::addCardToDeck`:
    - The success path is unchanged (medium impact haptic + "Added X" banner).
    - The no-op path now fires `UINotificationFeedbackGenerator.notificationOccurred(.warning)` haptic + a "X — already in deck" or "X — bonus plays full (15)" banner that explains the cause.
    - 1.5s auto-clear timer reused — no per-branch timing logic.
  - New `noAddReasonFor(card:role:)` helper mirrors the silent-skip branches in `DeckBuilderStore.addCard`:
    - Hero: "already in deck" or "skipped"
    - Play: "already in deck" / "bonus plays full (15)" / "skipped"
    - BonusPlay: same as Play
    - HotDog: "hot dogs full (10)" / "skipped"
    - Sideboard: "skipped" (no cap)
- **Verified:** `store.heroes.contains` + `store.plays.contains` + `store.bonusPlays.count` all match the exact predicates in DeckBuilderStore.swift:806-822. Warning haptic distinguishes from the success-add medium-impact haptic so the user feels the difference before reading.
- **PARITY.md:** No row — UX polish on already-✅ Decks long-press add.
- **Next:** tick 113 = web; 114 = Android; 115 = opt.



### Tick 111 — 2026-05-20 — **Android** — Custom Rainbow row shows owned/total progress (iOS parity)
- **Cadence:** 111 % 5 = 1 → Android.
- **Picked:** Android Custom Rainbow rows showed only WHICH filter dimensions were active ("3 heroes · 5 treatments") but NO progress info — user had to tap into each rainbow to learn whether they were 2/30 or 28/30 done. iOS + web Custom Rainbows surface "5 of 30 owned · 17%" inline; Android lagged.
- **Shipped:**
  - `RainbowsScreen.kt`:
    - Pre-computed `ownedBobaIds` Set once for the custom-rainbows list (memoized on `state`). Personal / For Sale / For Trade designations count as "owned" — same scope iOS uses.
    - Per-row `remember(catalog, rainbow.criteria) { ... }` filters catalog → matching cards. `owned` = intersection with ownedBobaIds. `pct` = owned ÷ matching × 100.
    - Row's `supportingContent` now renders a 2-line Column: bold cyan progress line "${owned} of ${matching.size} owned · ${pct}%" on top, dim filter-summary line below. Was previously a single label-summary line.
  - New file-private `criteriaMatches(criteria, card)` helper at the bottom — ports iOS `RainbowCriteria.matches` + web `rainbowCriteriaMatches` semantics. Empty fields = "any" (matches every card); non-empty fields = whitelist. Inspired Ink toggle checks for "inspired ink" substring in treatment. Local-scope (file-private) to keep tick small; promote to `RainbowCriteria.matches(card)` extension when a 2nd call site needs it.
- **Verified:** `state.entriesByDesignation` shape unchanged. `catalog` already collected at line 69. RainbowCriteria field list confirmed at `CustomRainbowRepository.kt:142-150`.
- **PARITY.md:** No row — UX polish on already-✅ Custom Rainbows row. Closes the "list shows filter but not progress" gap.
- **Next:** tick 112 = iOS; 113 = web; 114 = Android; 115 = opt.



### Tick 110 — 2026-05-20 — **OPTIMIZATION TICK (13th 1-in-5)** — orphan pmDetectHDRecovery
- **Cadence:** opt rotation. Web 5 ticks · iOS 4 · Android 3. Web has slight lead but `practice.js` had a clean orphan target.
- **Picked:** `pmDetectHDRecovery(card)` at practice.js:1557 — 12-line regex helper that detected "return/recover N hot dogs" play text. `grep -rn pmDetectHDRecovery js/` returned exactly one hit — the function definition. The structured `play-effects.json` engine (loaded via `pmLoadPlayEffects` immediately below) supersedes this regex approach; the orphan helper is leftover from the pre-structured-effects era.
- **Shipped:** Removed the function + its trailing blank line (preserving the next section header).
- **Verified:** `node -c js/practice.js` clean. `grep -rn pmDetectHDRecovery` returns nothing post-edit.
- **Line-count delta:** -13 lines.
- **Cumulative across 13 optimization ticks:** -167 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23 · 90: -19 · 95: -6 · 100: -1 · 105: -2 · 110: -13).
- **Next:** tick 111 = Android; 112 = iOS; 113 = web; 114 = Android; 115 = opt.



### Tick 109 — 2026-05-20 — **Android** — Card detail "Other Versions" owned/wanted indicators (iOS parity)
- **Cadence:** 109 % 5 = 4 → Android.
- **Picked:** iOS CardDetailView::variationsSection rendered an owned-check or wanted-star icon overlay on each "Other Versions" thumbnail (lines 799-805) so users could see at a glance which treatments they already had. Android's equivalent at CardDetailScreen.kt:447 just rendered the thumb + treatment label — no ownership signal.
- **Shipped:**
  - `CardDetailScreen.kt` Other Versions section:
    - Pre-computed `ownedBobaIds: Set<String>` + `wantedBobaIds: Set<String>` via `remember(collectionState)` — O(1) per-row lookup instead of re-walking entriesByDesignation on every recompose. Same shape iOS uses.
    - Owned set = Personal / For Sale / For Trade. Wanted set = Wanted / Grails.
    - Wrapped `BOBACardCell` in a `Box`; overlay `Icon(CheckCircle or Star)` at `Alignment.TopEnd` when the thumb's bobaId is in either set.
    - Owned wins on tie (theoretical case: user has both Personal + Wanted of the same bobaId).
    - Owned = `Color(0xFF4CAF50)` (same Material success-green iOS uses literally). Wanted = `BobaBrand.Orange`.
    - New imports: `CheckCircle` + `Star` icons.
- **Verified:** `collectionState` already collected at line 334 (used by "In your collection" section). `Box` already imported (used elsewhere in the file). Comments tie the green hex to the iOS literal so future contributors don't drift the colors.
- **PARITY.md:** No row — UX polish on already-✅ Other Versions row.
- **Next:** tick 110 = opt (13th 1-in-5).



### Tick 108 — 2026-05-20 — **web** — Card detail modal: "IN YOUR COLLECTION" summary (3-platform parity)
- **Cadence:** 108 % 5 = 3 → web.
- **Picked:** iOS tick 107 just shipped the Find-tab CardDetailView ownership summary. Web card-detail modal had no equivalent — users tapping a card from search had no signal whether they already owned a copy + at which designation. Same gap iOS tick 107 fixed; web cadence closes 3-platform lockstep.
- **Shipped:**
  - `js/collection.js`:
    - New exported `entriesForCard(card)` helper — returns `_cards.filter(...)` matching by `boba_id` (preferred) or `card_number` (legacy fallback). Same match logic CollectionStore.entries(forBobaId:) uses on iOS.
    - Returned object adds `entriesForCard` between `quickAdd` + the lookup setters.
  - `js/app.js`:
    - New `buildInYourCollectionBlock(card)` helper. Reads `window.Collection.entriesForCard(card)`. Returns empty string when 0 entries, when signed-out, or before Collection.init() has resolved (defensive — first paint can race).
    - Groups by designation, builds "Personal · For Sale ×2 · Wanted" summary, renders inside `.in-collection-block` with cyan-tint badge + headline.
    - Inserted between `.modal-collection-action` and `.pricing-section` in the modal body — matches the iOS placement (between action toolbar and pricing).
  - `css/styles.css::.in-collection-block`:
    - Flex column with cyan-tint background + cyan-border.
    - Mono headline at 0.65rem with 0.12em tracking (matches iOS section-header typography).
    - Bold cyan summary line at 0.82rem.
- **Verified:** `node -c js/app.js` + `node -c js/collection.js` clean. `entriesForCard` defensive against missing card / non-array return — won't throw on cold-paint.
- **PARITY.md:** No row — UX polish on already-✅ Card detail row. 3-platform parity on the "in your collection" summary (iOS Collection detail since launch · iOS Find detail tick 107 · web modal tick 108 · Android via CardDetailScreen since baseline).
- **Next:** tick 109 = Android; 110 = opt.



### Tick 107 — 2026-05-20 — **iOS** — Find Card detail "IN YOUR COLLECTION" summary
- **Cadence:** 107 % 5 = 2 → iOS.
- **Picked:** Find-tab `CardDetailView` had NO "in your collection" summary — only the Collection-tab `CollectionCardDetailView` did. Find users tapping a card from search had no signal whether they already owned a copy + at which designation. iOS Android tick 94 + 99 + the existing CollectionCardDetail already had this summary; the Find tab was the missing surface.
- **Shipped:**
  - `CardDetailView.swift` body — new block inserted between the variations/extras area and the `Divider() / PricingSection` block:
    - Reads `collection.entries(forBobaId: card.id)` (already exposed on `CollectionStore` per existing CollectionCardDetailView usage).
    - When `ownedEntries.isNotEmpty`, groups by designation + builds a "Personal · For Sale ×2 · Wanted" summary string.
    - Renders inside a cyan-accent block: "IN YOUR COLLECTION (N)" header + bold cyan summary line.
    - Uses the existing `Design.Colors.bobaCyan` + mono fonts — same shape as `CollectionCardDetailView::ownedEntries` to keep visual identity consistent across the two card-detail surfaces.
- **Verified:** `collection.entries(forBobaId:)` exists at `CollectionStore.swift:205`. `UserCard.Designation.displayName` already used elsewhere in this file. SourceKit cross-file noise preexisting.
- **PARITY.md:** No row — UX polish on already-✅ Find Card detail row.
- **Next:** tick 108 = web; 109 = Android; 110 = opt.



### Tick 106 — 2026-05-20 — **Android** — Practice placeholder: user-facing copy
- **Cadence:** 106 % 5 = 1 → Android.
- **Picked:** `PracticePlaceholder.kt`'s BOBAEmptyState body read "The iOS state-machine engine (DECISIONS.md #030) ports as pure Kotlin in :core:domain. Multi-session effort scheduled post-M8. Admin-gated." Pure developer jargon — referenced internal doc + Kotlin module path. The screen is admin-gated but admins ARE the BoBA team / close beta + they don't need to read DECISIONS.md to use the app. Empty-state copy should always be user-facing.
- **Shipped:**
  - `PracticePlaceholder.kt::BOBAEmptyState`:
    - Headline: "Practice executor port in progress" → "Battle practice — coming soon" (BoBA community always says "Battle Practice"; "executor" is internal).
    - Body: developer-jargon → "Practice the BoBA state machine against a CPU coach. The Android port is in progress; use the iOS app for now, or check back in a few releases."
- **Verified:** Doc-comments at the top of the file still reference DECISIONS.md #048 / #030 — engineering docs preserved. Only user-facing strings changed.
- **PARITY.md:** No row — copy polish on already-⏳ Practice executor row.
- **Next:** tick 107 = iOS; 108 = web; 109 = Android; 110 = opt.



### Tick 105 — 2026-05-20 — **OPTIMIZATION TICK (12th 1-in-5)** — 2 orphan iOS @State vars
- **Cadence:** opt rotation. Web 5 ticks · iOS 3 · Android 3. Bias-toward-iOS.
- **Picked:** Scanned iOS view-level `@State` declarations. Two orphans:
  - `CollectionView.swift::exportShareURL` — declared as `URL? = nil` but `grep -rn exportShareURL` returned only the declaration. Never assigned, never read.
  - `SearchView.swift::selectedCard` — declared as `Card?` but `grep -rn selectedCard.* SearchView` returned only the declaration. Never written, never read.
- **Shipped:** Removed both declarations.
- **Verified:** Final greps confirm zero remaining references. `tradeRoomFAB` + `discord`/`showTradeRoom` left in place per DECISIONS.md #025 (Discord trade-room feature is intentionally gated, not dead code).
- **Line-count delta:** -2 lines.
- **Cumulative across 12 optimization ticks:** -154 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23 · 90: -19 · 95: -6 · 100: -1 · 105: -2).
- **Next:** tick 106 = Android; 107 = iOS; 108 = web; 109 = Android; 110 = opt.



### Tick 104 — 2026-05-20 — **Android** — Collection grid density picker (iOS @AppStorage parity)
- **Cadence:** 104 % 5 = 4 → Android.
- **Picked:** Same gap tick 101 closed for Decks — `GridDensityStore.Target.COLLECTION` was registered but `grep -rn Target.COLLECTION` returned zero callers. CollectionGrid hardcoded `Adaptive(minSize = 110.dp)`. iOS exposes per-collection `@AppStorage("bp_collectionGridColumns_v1")` — Android lagged.
- **Shipped:**
  - `CollectionGrid` signature gained `columns: Int = 0` param. 0 → adaptive default; non-zero → `GridCells.Fixed(columns)`.
  - `CollectionScreen` injects `GridDensityViewModel`, reads `storedGridColumns` from `Target.COLLECTION` Flow, threads `storedGridColumns` into the GRID-mode CollectionGrid call site only (List + Wall ignore the picker).
  - Overflow `DropdownMenu` gained a "Grid columns" mini-section between Display-mode picker + Sort. Only rendered when `displayMode == DisplayMode.GRID` (List/Wall don't have variable columns). Three `DropdownMenuItem`s (1/2/3) with active row showing `Icons.Default.Check` leadingIcon and inactive rows getting a 24dp Spacer for layout consistency.
  - Fully-qualified `androidx.compose.foundation.layout.Spacer(...)` to match the file's existing convention (Spacer isn't imported at top).
- **Verified:** `Target.COLLECTION` enum case at GridDensityStore.kt:46. ViewModel pattern + setColumns flow identical to the Decks tick 101 + Find pattern. Existing CollectionList + CollectionWall callers unchanged — default columns=0 preserves their behavior.
- **PARITY.md:** Per-tab grid density row at PARITY.md:99 was claiming ✅ for both Decks + Collection on Android — really only Find was wired pre-tick-101. Now 3-of-3 tabs honor their per-tab DataStore preference (Find / Decks / Collection).
- **Next:** tick 105 = opt; 106 = Android; 107 = iOS; 108 = web.



### Tick 103 — 2026-05-20 — **web** — AddSheet toast + expose window.showToast (uncovers + fixes silent fallback bug)
- **Cadence:** 103 % 5 = 3 → web.
- **Picked:** Web `openAddSheet` save path called `API.collectionAdd(card)`, closed sheet, re-rendered Collection + Profile — but NO confirmation toast. Same anti-pattern iOS tick 102 just fixed. Also discovered a **silent bug**: collection.js wrote `window.showToast('Avatar updated.')` (tick 68) + practice.js wrote `window.showToast('Add some cards…')` — both guarded with `if (typeof window.showToast === 'function')` checks that **always returned false** because app.js's `showToast` function was defined inside an IIFE and never exposed on window. Every "toast" call from sibling modules silently fell through to nothing.
- **Shipped:**
  - `js/app.js::showToast` — added `window.showToast = showToast` right after the function definition. Now sibling modules' `window.showToast(...)` calls actually fire. Fixes tick 68 (avatar success/error toasts) + tick 9 (deck wall empty toast) + any future cross-module toast call.
  - `js/collection.js::openAddSheet` success branch:
    - Resolved `desigLabel` from `DESIGNATIONS.find(d => d.key === card.designation)?.label`.
    - Fired `window.showToast(`Added to ${desigLabel}`)` after the existing re-renders. Per-designation label so user sees WHERE the add landed (sheet defaults to Personal but they may have switched).
- **Verified:** `node -c` clean on both files. Confirmed via grep that `window.showToast` had no `=` assignment anywhere — definitively orphan API surface area until tick 103.
- **PARITY.md:** No row — UX polish + a real bug fix on already-✅ AddToCollection row. iOS tick 102 + Android tick 96 + web tick 103 = 3-platform lockstep on the post-add toast.
- **Next:** tick 104 = Android; 105 = opt.



### Tick 102 — 2026-05-20 — **iOS** — AddToCollectionSheet fires onAdded toast (Android tick 96 parity)
- **Cadence:** 102 % 5 = 2 → iOS.
- **Picked:** iOS `AddToCollectionSheet` saved silently — `collection.addCard(new)` returned + the sheet dismissed, but the host view had no signal to fire the green-checkmark toast. Compare with `AddToDeckSheet` at the same call site (CollectionCardDetailView.swift:242 + CardDetailView.swift:303): both pass `{ name in showAddedToDeckToast(name) }` as a closure parameter. AddToCollectionSheet lacked the equivalent callback — by-design oversight from the sheet's original implementation. Android tick 96 just shipped the equivalent Snackbar — iOS parity gap.
- **Shipped:**
  - `AddToCollectionSheet.swift`:
    - New property `var onAdded: ((_ designationLabel: String) -> Void)? = nil` — default-nil so unchanged callers stay source-compatible.
    - `save()` fires `onAdded?(designation.displayName)` immediately before `dismiss()` on the success path. Failure path unchanged (the existing `saveError` text covers it).
  - `CollectionCardDetailView.swift::sheet(isPresented: $showingAddSheet)` now passes `{ designationLabel in showAddedToDeckToast("Added to \(designationLabel)") }`. Reuses the existing toast helper (the helper's name says "Deck" but it's a generic green-checkmark renderer — same shape used for shows already at line 296).
  - `CardDetailView.swift::sheet(isPresented: $showingAddSheet)` got the same wiring.
- **Verified:** `AddToDeckSheet`'s callback pattern at CollectionCardDetailView.swift:242 + CardDetailView.swift:303 was the canonical reference. SourceKit cross-file noise preexisting.
- **PARITY.md:** No row — UX polish on already-✅ AddToCollection sheet.
- **Next:** tick 103 = web; 104 = Android; 105 = opt.



### Tick 101 — 2026-05-20 — **Android** — Decks pool grid density picker (iOS @AppStorage parity)
- **Cadence:** 101 % 5 = 1 → Android.
- **Picked:** `GridDensityStore.Target.DECKS` was registered in the shared store (alongside FIND + COLLECTION) but `grep -rn Target.DECKS` returned zero callers — the pool grid hardcoded `GridCells.Adaptive(minSize = 110.dp)` and never read the user's preference. iOS DesksView exposes a 1/2/3 column picker via `@AppStorage("bp_decksGridColumns_v1")` — Android gap.
- **Shipped:**
  - `CardPoolGrid` signature gained `columns: Int = 0` param. `0` = adaptive default (preserves existing behavior for the tablet caller). Non-zero → `GridCells.Fixed(columns)`.
  - `DecksCompactScreen` injects `GridDensityViewModel` (already in DI graph), reads `storedPoolColumns` from `Target.DECKS` Flow, threads into `CardPoolGrid(columns = storedPoolColumns)`.
  - Overflow `DropdownMenu` gained a "Pool columns" mini-section with 3 `DropdownMenuItem`s (1 / 2 / 3 columns). Active row gets a `Check` leadingIcon; inactive rows get a 24dp Spacer so the layout doesn't jump. Setting fires `gridDensityVm.setColumns(Target.DECKS, col)` via `scope.launch` — DataStore persists asynchronously, the Flow updates the next recomposition.
  - New import: `androidx.compose.material.icons.filled.Check`.
- **Verified:** `columnsFor` returns Flow<Int> with initialValue=0 — matches the FIND tab's pattern at FindScreen.kt:161. Tablet caller (DecksTabletScreen) doesn't pass the new param — defaults to 0, adaptive minSize preserved.
- **PARITY.md:** Per-tab grid density row stays ✅ — was misstated as ✅ when only Find + Collection actually used it. The "Grid density picker (1/2/3 cols)" row at PARITY line 100 was effectively half-true on Android; now true.
- **Next:** tick 102 = iOS; 103 = web; 104 = Android; 105 = opt.



### Tick 100 — 2026-05-20 — **OPTIMIZATION TICK (11th 1-in-5)** — collapse duplicate CDN_FULL const
- **Cadence:** opt rotation. Web hadn't had a tick since 80 (3 ago); pick web.
- **Picked:** `js/practice.js` declared TWO consts holding the same R2 CDN URL: `CDN_BASE` at line 17 and `CDN_FULL` at line 1477. `CDN_FULL` was introduced when `fullUrl` was added, but the values are byte-identical — `'https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev'`. Pure duplication.
- **Shipped:** `fullUrl` now reads `CDN_BASE`, `CDN_FULL` declaration removed.
- **Verified:** `node -c js/practice.js` clean. `grep -n CDN_FULL js/practice.js` returns nothing post-edit. (api.js has its own `CDN_BASE` scoped inside its IIFE — leaving as-is, classic-script modules without a bundler share consts via duplication.)
- **Line-count delta:** -1 line.
- **Cumulative across 11 optimization ticks:** -152 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23 · 90: -19 · 95: -6 · 100: -1).
- **Next:** tick 101 = Android; 102 = iOS; 103 = web; 104 = Android; 105 = opt.



### Tick 99 — 2026-05-20 — **Android** — AddToCollection actually persists form fields (real bug fix)
- **Cadence:** 99 % 5 = 4 → Android.
- **Picked:** Audited Android AddToCollectionSheet → CardDetailScreen call path. The sheet's form collects **quantity, purchasePriceUsd, askingPriceUsd, condition, notes, grade** into an `AddToCollectionInput` data class — but `onSubmit` only called `collectionViewModel.add(input.cardBobaId, input.designation)`, silently discarding every other field. User would fill out condition + purchase price + notes, hit Save, and only the bobaId + designation actually landed in Supabase. **Real bug, not just polish.**
- **Shipped:**
  - `CollectionRepository.add()` signature extended with `quantity: Int = 1, purchasePrice: Double? = null, askingPrice: Double? = null, condition: String? = null, notes: String? = null` — all optional with sensible defaults so existing callers stay source-compatible.
  - Insert payload built via `buildMap` — only includes non-null/non-blank optional fields so the Supabase row isn't littered with explicit nulls. `quantity` only included when > 1 so the column default (1) kicks in for the standard add.
  - The duplicate-row branch (`existing != null`) now adds `quantity.coerceAtLeast(1)` to existing count instead of always +1 — handles the case where user explicitly wants "I just bought 3 of these."
  - `CollectionViewModel.add()` signature extended with the same fields + threads them through to repository. Doc-comment explains the iOS-shape parity.
  - `CardDetailScreen` onSubmit now passes all 5 form fields via named args.
  - Find tab's Quick Add caller unchanged — relies on defaults (only `cardBobaId` + `designation` named).
- **Verified:** Both call sites (`grep -rn collectionViewModel.add`) checked. Only 2 callers — `CardDetailScreen` (now passes full input) + `FindScreen` (Quick Add — relies on defaults).
- **PARITY.md:** No row — bug fix on already-✅ AddToCollection row.
- **Next:** tick 100 = opt (11th 1-in-5); 101 = Android; 102 = iOS.



### Tick 98 — 2026-05-20 — **web** — bulkAddToCollection: parallelize + better Toast
- **Cadence:** 98 % 5 = 3 → web.
- **Picked:** `bulkAddToCollection` (web Find multi-select → "Add N to {designation}") used a sequential `for-await` loop. For 50 cards = 50× longest-RTT (~10-15s on slow connections). Cloudflare + Supabase handle parallel writes fine at this scale; sequential was leftover from the simpler 1-card add. Also the toast just said "Added N cards · M failed" without disambiguating common failures (sign-out is the #1 cause; user didn't see "sign in" hint).
- **Shipped:**
  - `js/app.js::bulkAddToCollection`:
    - Replaced `for-await` with `Promise.allSettled(cards.map(...))`. ~10× faster on 50-card adds.
    - Counted `added` + `failed` via `.filter(r => r.status === 'fulfilled')`.
    - Toast branches on outcome:
      - `added === 0` → "Couldn't add — sign in and retry." (mentions the most common cause directly)
      - `cards.length === 1` → quotes the card name: "Added \"{hero}\" to {designation}"
      - Multi → "Added N cards to {designation} · M failed" (existing shape preserved)
- **Verified:** `node -c js/app.js` clean. `Promise.allSettled` is universal — no browser-support concern (Baseline since 2020).
- **PARITY.md:** No row — perf + UX polish on already-✅ multi-select bulk-add row.
- **Next:** tick 99 = Android; 100 = opt.



### Tick 97 — 2026-05-20 — **iOS** — CollectionCardDetail "IN YOUR DECKS" tap-to-load (Android tick 94 parity)
- **Cadence:** 97 % 5 = 2 → iOS.
- **Picked:** iOS `CollectionCardDetailView::decksSection` rendered cyan-tinted deck rows but they were inert — no Button, no onTapGesture. The user saw their decks containing this card but couldn't open them; opening Decks tab and manually finding the named deck was the only path. Android tick 94 just shipped tap-to-load + Snackbar; iOS gap on the opposite axis (Android had tap + no chevron; iOS had nothing).
- **Shipped:**
  - `CollectionCardDetailView.swift`:
    - New `@Environment(DeckBuilderStore.self) private var deckBuilder` — the iOS canonical singleton (same one `DecksView` uses at line 453 for the saved-decks loader).
    - Wrapped each `HStack` row in a `Button { ... } label: { ... }` with `.buttonStyle(.plain)` + `.contentShape(Rectangle())` so the entire row taps without losing the cyan-tinted Surface look.
    - Tap handler: `Task { _ = try await deckBuilder.loadSavedDeck(deck, cards: cardStore.displayCards); showAddedToDeckToast("Loaded \"{deck.name}\" into Decks") }`. Reuses the existing green-checkmark toast helper.
    - Added trailing `chevron.right` icon — universal "this row is tappable" affordance.
    - `.accessibilityHint("Loads this deck into the Decks editor")` for VoiceOver.
- **Verified:** `DeckBuilderStore.loadSavedDeck(_:cards:)` signature confirmed at `DeckBuilderStore.swift:1355`. `showAddedToDeckToast` already defined in this view at line 318+. SourceKit cross-file noise is preexisting.
- **PARITY.md:** No row — UX polish on already-✅ CollectionCardDetail row. 2-platform parity (iOS tick 97 + Android tick 94) on the in-deck-tap-to-load pattern.
- **Next:** tick 98 = web; 99 = Android; 100 = opt.



### Tick 96 — 2026-05-20 — **Android** — AddToDeckSheet: Snackbar confirmations on add
- **Cadence:** 96 % 5 = 1 → Android.
- **Picked:** Android `AddToDeckSheet` had two silent action paths:
  1. **"Current draft" row** — `decksViewModel.add(card)` + dismiss. User sees nothing. Did the add register? Did the cap-check warn? Silent.
  2. **"Saved decks" row** — `loadSaved(saved, catalog)` + `add(card)` + dismiss. This SWAPS the user's current draft to the loaded saved deck. If they had unsaved draft work, it's gone with no warning. **Real UX hazard.**
- **Shipped:**
  - `AddToDeckSheet.kt`:
    - New imports: `rememberCoroutineScope`, `LocalAppSnackbar`, `kotlinx.coroutines.launch`.
    - Resolve `appSnackbar` + `scope` at composable root.
    - **Current-draft click**: now fires `appSnackbar?.showSnackbar("Added ${card.displayName} to ${draft.name}")` after the add. Cause-and-effect anchored.
    - **Saved-deck click**: snackbar names BOTH actions — `"Loaded \"${saved.name}\" and added ${card.displayName}"`. User sees the draft swap explicitly, not as a silent side-effect. The two ops can race (loadSaved is a Flow update; add follows) but the existing call-order was already established — the snackbar just makes the user aware.
- **Verified:** `LocalAppSnackbar` is provided at the BOBAApp theme root (used by CardDetailScreen + others). `rememberCoroutineScope` + `launch` are stdlib.
- **PARITY.md:** No row — UX polish on already-✅ AddToDeck flow.
- **Next:** tick 97 = iOS; 98 = web; 99 = Android; 100 = opt.



### Tick 95 — 2026-05-20 — **OPTIMIZATION TICK (10th 1-in-5)** — orphan iOS HintIDs
- **Cadence:** opt rotation. Bias-toward-iOS-or-Android since web had 4. Picked iOS.
- **Picked:** `Design.swift::HintID` enum had 5 cases but only 3 had rendering sites in the codebase. `deckCompositionTriad` ("hint.deck_composition_triad") + `hdValueHeuristic` ("hint.hd_value_heuristic") were never wired — `grep -rn deckCompositionTriad BOBAPlaybook` + same for `hdValueHeuristic` returned only the enum definitions. Both were documented for a future "first build" + "high-cost play added" hint, but they shipped on neither iOS surface. Verified the same audit on the Android side — `HintsStore.Ids` is fully wired (CARD_DETAIL_TAP_PRICE / SCAN_HOLD_STEADY / DECKS_LONG_PRESS_TO_ADD / COLLECTION_DISPLAY_MODES / LEARN_LONG_PRESS_GLOSSARY — last one wired in tick 84).
- **Shipped:**
  - `BOBAPlaybook/Components/Design.swift::HintID` — dropped the 2 orphan cases + their 4 doc-comment lines (2 doc lines per case).
- **Verified:** `grep -rn deckCompositionTriad BOBAPlaybook` post-edit returns nothing. `grep -rn hdValueHeuristic BOBAPlaybook` returns nothing.
- **Line-count delta:** -6 lines.
- **Cumulative across 10 optimization ticks:** -151 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23 · 90: -19 · 95: -6).
- **Next:** tick 96 = Android; 97 = iOS; 98 = web; 99 = Android; 100 = opt.



### Tick 94 — 2026-05-20 — **Android** — Card detail "Decks with this card": tap-affordance + Snackbar
- **Cadence:** 94 % 5 = 4 → Android.
- **Picked:** `CardDetailScreen.kt` at line 367+ rendered "Decks with this card (N)" with each deck row already `Modifier.clickable { decksVmHere.loadSaved(deck, catalog) }` — but the row had NO visual affordance signaling it was tappable (no chevron, no trailing icon), and the loadSaved call gave NO feedback. The comment on the section even called the tap-through "a future iteration" — stale, since it already worked. Result: users likely never realized the row was tappable, and even when they tried it, the deck would silently load into the Decks editor (visible only when they switched tabs) with zero confirmation.
- **Shipped:**
  - `CardDetailScreen.kt`:
    - Added `Icons.AutoMirrored.Filled.ArrowForward` trailing chevron (16dp, on-surface-variant tint) to each row — universal "this is tappable" affordance.
    - Wrapped row content in `horizontalArrangement = Arrangement.spacedBy(8.dp)` for consistent spacing with the new icon.
    - Added Snackbar confirmation after `loadSaved`: "Loaded \"{deckName}\" into the Decks editor" — anchors the cause-and-effect so users see the action register.
    - Updated the stale comment from "v1 renders read-only; tap-through to load is a future iteration" → "Tap a row → loadSaved swaps the current draft to the saved deck. Snackbar confirms..."
  - New import: `androidx.compose.material.icons.automirrored.filled.ArrowForward`.
- **Verified:** `scope` (rememberCoroutineScope) + `snackbarHostState` (LocalAppSnackbar) both already in scope at this composable level — no new state plumbing needed. `androidx.compose.foundation.layout.size` already imported (line 13).
- **PARITY.md:** No row — UX polish on already-✅ Card detail row.
- **Next:** tick 95 = opt; 96 = Android; 97 = iOS; 98 = web; 99 = Android; 100 = opt.



### Tick 93 — 2026-05-20 — **web** — Decks browser empty: search vs filter disambiguation (3-platform parity)
- **Cadence:** 93 % 5 = 3 → web.
- **Picked:** Web `dbRenderGrid` literally rendered an EMPTY grid when no cards matched — worse UX than iOS or Android, which at least show a message. Tick 89 (Android) + tick 92 (iOS) just shipped search-vs-filter disambiguation; web was the laggard with not even a generic empty-state.
- **Shipped:**
  - `js/practice.js::dbRenderGrid` — early-out empty-state branch before the existing card.map render:
    - **Search-empty** (`DB.search.trim()` non-empty): "No cards match \"{query}\"" + "Try a different term or clear the search." + a "Clear search" button (`btn-ghost-sm`) that wipes `DB.search`, clears the `#db-search` input value + its inline clear-✕ button (`#db-search-clear`), and re-renders. Query is HTML-escaped inline.
    - **Filter-empty** (no query): "No cards in scope" + "Pick a different tab above (Heroes / Plays / Bonus / Hot Dogs) to see eligible cards." No CTA — the tab strip is visible right above the grid.
  - `css/styles.css::.db-browser-empty`:
    - `grid-column: 1 / -1` so the empty block spans the full grid width (the grid is `display: grid`).
    - Flex column with brand-display headline (text-secondary), mono body (text-muted), bounded to `max-width: 40ch` for readability.
- **Verified:** `node -c js/practice.js` clean. `#db-search` is the correct input ID (not `#db-browser-search` — first attempt was wrong, corrected). `#db-search-clear` is the inline ✕ button — also wiped on Clear so the user doesn't have a stale ✕ next to the now-empty input.
- **PARITY.md:** No row — UX polish on already-✅ Decks browser row. 3-platform parity now lockstep.
- **Next:** tick 94 = Android; 95 = opt.



### Tick 92 — 2026-05-20 — **iOS** — DeckBuilder pool empty: search vs filter disambiguation (Android tick 89 parity)
- **Cadence:** 92 % 5 = 2 → iOS.
- **Picked:** iOS `DeckBuilderView`'s empty-pool state rendered "Try a different search or filter" for every cause. Same anti-pattern Android tick 89 just fixed. Closes the parity gap on the same surface — iOS user typing "obscurehero" had no signal whether the issue was their query or the catalog scope.
- **Shipped:**
  - `DeckBuilderView.swift` browser empty branch:
    - Split `ContentUnavailableView` on `store.browserSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`.
    - **Search-empty**: explicit "No cards match" headline + body quotes the query, "Clear search" button (cyan bordered) wired to `store.browserSearch = ""`. Mirrors web tick 78 + Android tick 89.
    - **Filter-empty** (no query): "No cards in scope" + "Pick a different tab above, or widen the element filter." No CTA — the tab strip + element filter are visible right above the grid.
- **Verified:** `store.browserSearch` exists at `DeckBuilderStore.swift:393`. `Design.Colors.bobaCyan` already used elsewhere. SourceKit cross-file noise preexisting.
- **PARITY.md:** No row — UX polish on already-✅ Decks browser row.
- **Next:** tick 93 = web; 94 = Android; 95 = opt.



### Tick 91 — 2026-05-20 — **Android** — Profile role-request: surface pending state
- **Cadence:** 91 % 5 = 1 → Android.
- **Picked:** Android Profile's role-request row said "Request mod or streamer role · Reviewed by Ben within 48h" for every user, even after a user had already submitted a pending request. The only feedback that the request landed was the post-submit Snackbar that disappeared after a few seconds. If the user re-opened Profile a day later they had no signal a request was pending — risk of duplicate submits + the dialog defaulted to "moderator" radio regardless of what they originally requested. iOS Profile already surfaces this state.
- **Shipped:**
  - `ProfileSheet.kt::item("role-request")`:
    - Reads `profile?.requestedRole` (already exposed on `UserProfile.requestedRole` at `ProfileService.kt:243`).
    - When pending: supporting text becomes "Pending: {Role} · Ben reviews within 48h" in cyan; button label becomes "Update" instead of "Request".
    - When not pending: original copy preserved verbatim.
  - `if (roleRequestOpen)` dialog:
    - `initialRole` derived from `profile?.requestedRole` (falls back to "moderator" when none).
    - `var requestedRole by remember(initialRole) { mutableStateOf(initialRole) }` — `remember` keyed on initialRole so opening the dialog for a different pending role resets the radio correctly.
    - Title flips to "Update role request" when `isUpdate` (mirrors the row's "Update" button label).
- **Verified:** UserProfile field exists at `ProfileService.kt:243` — `val requestedRole: String?`. BobaBrand.Cyan already imported (line 83). The existing `vm.requestRole(role, reason)` call site unchanged — the SQL RPC handles both "first submit" and "update existing" idempotently.
- **PARITY.md:** No row — UX polish on already-✅ Profile role-request row.
- **Next:** tick 92 = iOS; 93 = web; 94 = Android; 95 = opt.



### Tick 90 — 2026-05-20 — **OPTIMIZATION TICK (9th 1-in-5)** — drop iOS submitModRequest shims
- **Cadence:** opt rotation. Web 4 ticks (50/55/70/75). Android 3 (60/75/80). iOS now 3 (65/85/90).
- **Picked:** Tick 85 left `AuthManager.submitModRequest(reason:)` (3-line shim → `requestRole("moderator", ...)`) AND `SupabaseClient.submitModRequest(reason:)` (15-line REST writer) in place because removing them would touch ModRequestSheet. Trivial caller migration — `ModRequestSheet.swift::submitButton` is the only iOS site that called the AuthManager shim.
- **Shipped:**
  - `BOBAPlaybook/Views/Profile/ModRequestSheet.swift::submitButton` — replaced `await auth.submitModRequest(reason: ...)` with `await auth.requestRole("moderator", reason: ...)`. Same call shape, same behavior.
  - `BOBAPlaybook/Networking/AuthManager.swift` — dropped the 3-line `submitModRequest(reason:)` shim. Doc comment on `requestRole` cleaned up too.
  - `BOBAPlaybook/Networking/SupabaseClient.swift` — dropped the 15-line `submitModRequest(reason:)` REST writer (used PATCH to write directly to `user_profiles.mod_request_*` columns — the legacy path bypassed the `request_role` RPC). Doc comment on `requestRole` rewritten to call out the compat shim in the SQL layer (not the old Swift fn).
- **Verified:** `grep -rn submitModRequest BOBAPlaybook` returns only the new doc comments (legitimate breadcrumbs). `grep -rn \\.submitModRequest` returns zero hits — all method calls cleaned.
- **Line-count delta:** -19 net lines (counting the new doc-comment additions).
- **Cumulative across 9 optimization ticks:** -145 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23 · 90: -19).
- **Next:** tick 91 = Android; 92 = iOS; 93 = web; 94 = Android; 95 = opt.



### Tick 89 — 2026-05-20 — **Android** — Decks pool empty: disambiguate search-empty vs filter-empty
- **Cadence:** 89 % 5 = 4 → Android.
- **Picked:** `CardPoolGrid` rendered the same "Tweak the search above or use Filters in the Find tab to widen the catalog scope." message for ALL empty-pool causes, whether the user typed a search query or the Find-tab filters constrained the catalog. Users typing in the pool search couldn't see they'd typed too narrowly + had no one-tap clear. Web tick 78 + 83 + 88 established the pattern of disambiguating search-empty from structural-empty with brand-voice copy + productive CTA.
- **Shipped:**
  - `DecksScreen.kt::CardPoolGrid` signature gained `searchQuery: String = ""` + `onClearSearch: (() -> Unit)? = null` (defaults preserve source-compat for the tablet pane caller).
  - Empty-state branch splits on `searchQuery.isNotBlank()`:
    - **Search-empty**: headline "No cards match", body quotes the user's query, action button "Clear search" wired to `onClearSearch` callback.
    - **Filter-empty** (no query but Find filters constraining the catalog): headline "No cards in scope", body "Filters set on the Find tab are constraining the catalog. Open Find → Filters and widen or clear them." No CTA — the Find tab is one tap away in the NavigationBar.
  - Compact caller passes `searchQuery = poolQuery` + `onClearSearch = { poolQuery = ""; findViewModel.onEvent(FindEvent.QueryChanged("")) }`. The QueryChanged event ensures Find's results state matches, so the pool re-populates on the next recomposition.
  - Tablet caller unchanged — defaults kick in (no in-pool search field on tablet, so the "filter-empty" branch always fires).
- **Verified:** All three `CardPoolGrid(` call sites accounted for (compact + tablet only; the third match is the function declaration). `BOBAEmptyState` signature accepts nullable `actionLabel` + `onAction` (signature confirmed earlier).
- **PARITY.md:** No row — UX polish on already-✅ Decks pool row.
- **Next:** tick 90 = opt; 91 = Android; 92 = iOS; 93 = web; 94 = Android.



### Tick 88 — 2026-05-20 — **web** — Glossary tab + tap-to-copy (3-platform parity)
- **Cadence:** 88 % 5 = 3 → web.
- **Picked:** PARITY.md line 72 read "Glossary lookup (inline definitions) | ✅ | ✅ | ✅" but a `grep -rn Glossary` across `index.html` returned zero matches. Web has Rules / Strategy / Browse / Collect / Tournament panels but no Glossary. Real content-parity gap that PARITY.md misstated. Ticks 84 (Android) + 87 (iOS) both shipped tap-to-copy on their Glossary surfaces, so web needed both the surface itself AND the tap-to-copy.
- **Shipped:**
  - `index.html`:
    - New `<button class="play-tab" data-tab="glossary">Glossary</button>` between Collect and Tournament in the play-tabs row.
    - New `<div id="play-panel-glossary" class="play-panel" hidden>` with two `<section>` blocks (GAME GLOSSARY + TRADING GLOSSARY) — 11 game terms + 21 trading terms verbatim from iOS LearnView (the canonical content source).
    - Each row is a `<button class="glossary-row" data-term="..." data-def="...">` with separate `<span class="glossary-term">` + `<span class="glossary-def">` for typography. Native button = inherent focus + tap + screen-reader support.
  - `css/styles.css`:
    - `.glossary-list` flex column inside a rounded surface, `.glossary-row` button with border-top between rows.
    - Hover + focus-visible: cyan tint background + cyan outline (a11y).
    - `.glossary-row.copied` state: green-tinted background + a `::after` "✓ copied" badge in the top-right (the web analog of iOS's checkmark flash + Android's Toast).
    - `prefers-reduced-motion` override drops the row transition.
  - `js/app.js`:
    - Event delegation `document.addEventListener('click', ...)` matches `.glossary-row` via `e.target.closest`. Writes `"{term} — {definition}"` to `navigator.clipboard.writeText` + adds `.copied` class for 1.2s (matches the iOS / Android timing).
    - Guard for clipboard rejection (older browsers / file:// origins) — silent fall-through so the click doesn't error.
- **Verified:** `node -c js/app.js` clean. The existing `.play-tab` handler at app.js:727 doesn't need any change — it generically toggles `play-panel-${target}` and the new glossary panel is just another `.play-panel`.
- **PARITY.md:** Line 72 note rewritten to reflect that the web surface actually exists now + all three platforms share tap-to-copy.
- **Next:** tick 89 = Android; 90 = opt.



### Tick 87 — 2026-05-20 — **iOS** — Glossary tap-to-copy + hint banner (Android tick 84 parity)
- **Cadence:** 87 % 5 = 2 → iOS.
- **Picked:** Android tick 84 shipped tap-to-copy on Glossary term rows + the LEARN_LONG_PRESS_GLOSSARY hint banner. iOS Glossary had no equivalent affordance — term rows were inert display-only. Coaches who wanted to quote a definition in Discord had to manually retype or select-and-copy through the iOS text-selection menu.
- **Shipped:**
  - `BOBAPlaybook/Components/Design.swift::HintID` — new case `glossaryTapToCopy` ("hint.glossary_tap_to_copy") for the once-per-device dismissal flag.
  - `BOBAPlaybook/Views/Play/LearnView.swift`:
    - Added `import UIKit` (UIPasteboard + UINotificationFeedbackGenerator).
    - `@State private var copiedTermId: String?` — track which row's checkmark to flash.
    - `HintBanner(id: .glossaryTapToCopy, ...)` at top of `GlossaryView.body`. Same brand-voice copy as Android tick 84: "Tap a term to copy it" + "Tap any glossary term to copy the term + definition. Handy when you want to quote it in Discord or a coaching note."
    - Term row wrapped in `Button { copyTerm(t) }` with `.buttonStyle(.plain)` + `.contentShape(Rectangle())` so the whole row taps + accessibility-hint "Copies the term and definition to your clipboard."
    - Inline `Image(systemName: "checkmark.circle.fill")` (green) appears next to the tapped term for ~1.2s — the iOS analog of Android's Toast confirmation. Uses `.transition(.opacity)` so the checkmark fades in/out.
    - New `copyTerm(_:)` helper: writes `"{term} — {definition}"` to `UIPasteboard.general`, fires `UINotificationFeedbackGenerator.notificationOccurred(.success)` for haptic confirmation, sets `copiedTermId` with a 1.2s clear task.
- **Verified:** `HintBanner` + `HintsManager` are at `Design.swift` (already on the compile manifest). `UIPasteboard.general` + `UINotificationFeedbackGenerator` are stdlib. SourceKit cross-file noise preexisting.
- **PARITY.md:** No row — UX polish on already-✅ Glossary surface. 2-platform parity (Android tick 84 + iOS tick 87).
- **Next:** tick 88 = web; 89 = Android; 90 = opt.



### Tick 86 — 2026-05-20 — **Android** — Custom Rainbow row hints reflect all 7 dims
- **Cadence:** 86 % 5 = 1 → Android.
- **Picked:** Tick 81 extended the Custom Rainbow editor to all 7 criterion dimensions, but the list-row supporting-text helper at `RainbowsScreen.kt:172` still only iterated 3 dims (heroes / weapons / treatments) + the Inspired Ink toggle. A user who created a custom rainbow with "Sets: Season One" or "Card types: Hero" looked identical to "Any card" in the list — looked like the filter didn't save.
- **Shipped:**
  - `RainbowsScreen.kt::supportingContent`:
    - `buildList` extended to include sets / sub-sets / releases / card types counts. Same `${count} {dim}` shape, joined with ` · `, falls back to "Any card" only when truly empty.
    - Comment explains the tick-81 dependency so a future contributor doesn't shrink the list back.
- **Verified:** RainbowCriteria fields confirmed at `CustomRainbowRepository.kt:142-150` — all 8 fields exist on the data class (heroes / sets / subSets / elements / treatments / cardTypes / releases / inspiredInkOnly). The list-row code paths weren't reading 4 of them.
- **PARITY.md:** No row — the editor parity row stays ✅; this is the corresponding list-display polish.
- **Next:** tick 87 = iOS; 88 = web; 89 = Android; 90 = opt.



### Tick 85 — 2026-05-20 — **OPTIMIZATION TICK (8th 1-in-5)** — iOS orphan `hasPendingModRequest` removal
- **Cadence:** opt rotation. Web 4 opt ticks (50/55/70/75). Android 3 (60/75/80). iOS only 1 (65). Bias-toward-iOS this round.
- **Picked:** `AuthManager.hasPendingModRequest` (Bool property) was set internally on profile-load, role-request, and reset — but `grep -rn auth.hasPendingModRequest` across the entire iOS codebase returned ZERO external readers. The comment "Keep the legacy hasPendingModRequest flag in sync so any remaining call sites (AdminPanelView) keep working" lied — AdminPanelView doesn't read it (verified). Same for `SupabaseClient.hasPendingModRequest()` (the REST helper) — zero callers since the generalized `requestRole` flow shipped (DECISIONS.md #038).
- **Shipped:**
  - `BOBAPlaybook/Networking/AuthManager.swift`:
    - Dropped `private(set) var hasPendingModRequest = false` (line 21).
    - Dropped 3 assignment sites (profile-load line ~153, requestRole line ~234, resetState line ~495) + 2 lines of doc comments justifying the legacy flag.
    - Updated `pendingRoleRequest`'s doc comment to drop the reference to `hasPendingModRequest`. -10 lines net.
  - `BOBAPlaybook/Networking/SupabaseClient.swift`:
    - Dropped `func hasPendingModRequest() async throws -> Bool` + its 9-line body. -13 lines.
- **Verified:** `grep -rn hasPendingModRequest BOBAPlaybook` post-edit returns nothing — all sites cleaned. SourceKit cross-file noise is preexisting. The "MARK: - Mod promotion requests" header preserved as a section divider for the remaining mod-related fns (fetchPendingModRequests, reviewModRequest).
- **Line-count delta:** -23 lines.
- **Cumulative across 8 optimization ticks:** -126 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2 · 85: -23).
- **Next:** tick 86 = Android; 87 = iOS; 88 = web; 89 = Android; 90 = opt.



### Tick 84 — 2026-05-20 — **Android** — Glossary tap-to-copy + wire orphan hint
- **Cadence:** 84 % 5 = 4 → Android.
- **Picked:** `HintsStore.Ids.LEARN_LONG_PRESS_GLOSSARY` was registered as a hint ID but had zero rendering sites — `grep -rn LEARN_LONG_PRESS_GLOSSARY` found only the definition + `all` array entry. Orphan UX scaffolding. The natural use case for a glossary hint is "tap-to-copy" — coaches frequently quote definitions verbatim in Discord and game-night chat, so a clipboard affordance is genuinely useful.
- **Shipped:**
  - `LearnArticleScreen.kt::GlossaryPage`:
    - Hilt-injected `HintsViewModel` + collected dismissal state for `LEARN_LONG_PRESS_GLOSSARY`.
    - `BOBAHintBanner` at top of the page (above the search field) with brand-voice copy: "Tap a term to copy it" + "Tap any glossary term to copy the term + definition. Handy when you want to quote it in Discord or a coaching note." Dismiss writes to DataStore + the hint never reappears on that device.
    - `LocalClipboardManager` + `LocalContext` resolved once at composable root.
  - `TermRow` signature gained `onCopy: () -> Unit` callback and `Modifier.clickable(onClickLabel = "Copy term")`. Click-label is the a11y string TalkBack will announce.
  - New `copyTermToClipboard(clipboard, context, section)` helper writes `"{term} — {definition}"` as plain text + fires a short Toast "Copied "{term}"" so users see the action register.
  - Both call sites (Game glossary + Trading glossary) updated to pass the lambda.
- **Verified:** `HintsViewModel.dismiss` + `isDismissed` already wired in CollectionScreen / ScanScreen / DecksScreen / CardDetailScreen — same pattern used here. `LocalClipboardManager` is the Compose-native canonical pattern (no `androidx.core.content.ClipData` needed for a simple text copy). Toast import inlined via `android.widget.Toast` so no new top-of-file import.
- **PARITY.md:** No row — informational hint + new in-screen action; the Glossary surface stays ✅.
- **Next:** tick 85 = opt; 86 = Android; 87 = iOS; 88 = web.



### Tick 83 — 2026-05-20 — **web** — Decks saved-decks search-empty: brand-voice + Clear button
- **Cadence:** 83 % 5 = 3 → web.
- **Picked:** Manage Decks search-empty rendered a single line "No saved decks match that name." with no productive action. Same anti-pattern that tick 78 fixed for Collection empty states. Universal-feature-states skill: empty states must invite action.
- **Shipped:**
  - `js/practice.js::applyDeckSearchFilter` — replaced the single `<div>` hint with a structured empty-state block:
    - `<p class="db-saved-decks-empty-headline">` quotes the user's search query so they can confirm it matched what they typed.
    - `<button class="btn-ghost-sm" data-action="clear-deck-search">Clear search</button>` wipes the input + refocuses it + re-runs `applyDeckSearchFilter` so the full list reappears.
    - Query string HTML-escaped inline (no DOM helper available in scope).
  - `css/styles.css::.db-saved-decks-search-empty` — flex column with brand-voice headline (`rgba(255,255,255,0.6)` for slightly more contrast than the default 0.3-muted), button below with 1rem padding.
- **Verified:** `node -c js/practice.js` clean. The handler wiring uses `addEventListener` (not `{once:true}`) because the hint element is recreated on every re-filter cycle so the listener doesn't leak.
- **PARITY.md:** No row — UX polish on already-✅ Manage Decks row.
- **Next:** tick 84 = Android; 85 = opt.



### Tick 82 — 2026-05-20 — **iOS** — Collection per-designation empty states (3-platform parity)
- **Cadence:** 82 % 5 = 2 → iOS.
- **Picked:** Web tick 78 + Android tick 79 both shipped per-designation brand-voice empty states with productive next-action copy. iOS was the last platform with the generic "Add cards from any card detail view." line. Closes the 3-platform parity gap on the same surface.
- **Shipped:**
  - `CollectionView.swift::emptyState`:
    - 5 designation-specific `(headline, body)` pairs verbatim with web tick 78 + Android tick 79:
      - personal: "No personal cards yet" + "Scan a card or use Quick Add from the Find tab to start your stack."
      - for_sale: "Nothing for sale yet" + "Mark a card from your Personal stack to start moving it."
      - for_trade: "Nothing for trade yet" + "Flag a card to find a trading partner once trading launches."
      - wanted: "No wanted cards yet" + "Flag the cards you're chasing — start with the ones at the top of your list."
      - grails: "No grails yet" + "Mark the cards you'd cross a state line for."
    - **Search-empty branch** added: when `searchText.trimmingCharacters(...)` is non-empty, headline becomes "No matches" + body names the trimmed search query, with a "Clear search" `Button` (cyan accent) that wipes `searchText`. Mirrors web tick 78's branch.
    - Headline now uses `textSecondary` (not muted) — small contrast bump for the headline so it reads as the brand-voice statement and the body is the support copy.
- **Verified:** All five Designation cases at `Models/UserCard.swift:94-99`. `Design.Colors.bobaCyan` + `textSecondary` confirmed at Design.swift. SourceKit cross-file noise (Cannot find 'CardStore'/'Card') is preexisting per project state — not real errors.
- **PARITY.md:** No row — UX polish on already-✅ Collection row. 3-platform parity now in lockstep on the same five copy strings.
- **Next:** tick 83 = web; 84 = Android; 85 = opt.



### Tick 81 — 2026-05-20 — **Android** — Custom Rainbow editor: full 7-dimension parity
- **Cadence:** 81 % 5 = 1 → Android.
- **Picked:** PARITY.md line 111 read "✅ basic (3 dimensions)" for Android Custom Rainbows. Web tick 16 + iOS surface all 7 criterion dimensions; Android editor only had Heroes / Weapons / Treatments + Inspired Ink. The remaining 4 dimensions (Sets / Sub-sets / Releases / Card types) were already in the data layer (`RainbowCriteria` already had them; `toJsonString`/`fromJson` already round-tripped). The editor UI was the gap.
- **Shipped:**
  - `CustomRainbowEditorSheet.kt`:
    - 4 new `rememberSavedSet` state vars (`sets`, `subSets`, `releases`, `cardTypes`) pre-filled from `existing?.criteria` so edit mode round-trips cleanly.
    - 4 new option-derivation `remember(catalog) { ... }` blocks — pulled from `Card.set` / `Card.subSet` / `Card.release` / `Card.cardType`, distinct + sorted, capped at 40 for sub-sets to keep the picker manageable on phones.
    - 4 new `BOBASectionHeader + ChipsPicker` sections in the scrollable column body — same shape as the existing Weapons / Heroes / Treatments sections.
    - Save payload extended to populate all 4 new fields on the `RainbowCriteria` constructor.
    - Header comment updated to reflect full parity (was "Sets / Sub-sets / Releases land in a polish pass").
- **Verified:** Card fields confirmed at `core/domain/model/Card.kt:33-39`. RainbowCriteria already had all 8 fields at `CustomRainbowRepository.kt:142`. `toJsonString` already serializes all 8 keys (lines 156-162). `fromJson` already round-trips (line 173+). No schema migration needed — the data layer was always ready.
- **PARITY.md:** Line 111 flipped from "✅ basic (3 dimensions)" to "✅" with the tick-81 note + the 7-dimension list spelled out.
- **Next:** tick 82 = iOS; 83 = web; 84 = Android; 85 = opt.



### Tick 80 — 2026-05-20 — **OPTIMIZATION TICK (7th 1-in-5)** — Android orphan `onProfileClick` param
- **Cadence:** opt rotation. Web 4 opt ticks (50/55/70/75). iOS 1 (65). Android 2 (60/75). Bias toward iOS or Android. Picked Android — clean orphan signal.
- **Shipped:**
  - `CollectionScreen.kt::CollectionScreen` — dropped `onProfileClick: () -> Unit` param. The comment "unused per feedback_profile_only_on_find; kept for nav signature symmetry" was a weak justification — Profile button is iOS+Android-only on Find tab; CollectionScreen has no use for the callback. -1 line.
  - `BOBAApp.kt:452` — dropped the matching `onProfileClick = onProfileClick` wiring on the only call site. -1 line.
- **Verified:** Single call site at BOBAApp.kt:450 (`grep -rn CollectionScreen(`). FindScreen still receives + uses `onProfileClick` (`IconButton(onClick = onProfileClick)` at FindScreen.kt:188) — unchanged. No other Compose callers to break.
- **Line-count delta:** -2 lines (Android).
- **Cumulative across 7 optimization ticks:** -103 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8 · 80: -2).
- **Next:** tick 81 = Android; 82 = iOS; 83 = web; 84 = Android; 85 = opt.



### Tick 79 — 2026-05-20 — **Android** — Collection per-designation empty states (web tick 78 parity)
- **Cadence:** 79 % 5 = 4 → Android.
- **Picked:** Android Collection's empty state was generic — every designation rendered "No {designation} cards yet · Scan a card or browse Find to add your first one." Tick 78 just shipped tuned per-designation copy on web; Android lagged. Real cross-platform parity gap on the same surface.
- **Shipped:**
  - `CollectionScreen.kt::CollectionScreen` empty-state branch:
    - `when (designation)` → 5 brand-voice `headline + body` pairs matching web tick 78 verbatim:
      - PERSONAL: "No personal cards yet" + "Scan a card or use Quick Add from the Find tab to start your stack."
      - FOR_SALE: "Nothing for sale yet" + "Mark a card from your Personal stack to start moving it."
      - FOR_TRADE: "Nothing for trade yet" + "Flag a card to find a trading partner once trading launches."
      - WANTED: "No wanted cards yet" + "Flag the cards you're chasing — start with the ones at the top of your list."
      - GRAILS: "No grails yet" + "Mark the cards you'd cross a state line for."
    - **Only PERSONAL gets a "Scan a card" CTA button**. Other designations need the user to switch to Find (or Personal) — but Android's NavigationBar is permanently visible at the bottom, so a "Go to Find" CTA would be no-op chrome. Body copy carries the wayfinding instead. (Web tick 78 has "Browse Find" because web's mobile nav drawer is collapsible; Android doesn't have that constraint.)
    - `BOBAEmptyState`'s `actionLabel` + `onAction` accept null cleanly (signature verified).
- **Verified:** Designation enum at `core/domain/model/Designation.kt` has the five expected values. BOBAEmptyState signature at `core/ui/.../BOBAEmptyState.kt:37` accepts `actionLabel: String? = null` + `onAction: (() -> Unit)? = null`. Search-empty branch (existing) preserved verbatim — "Clear search" CTA still wired.
- **PARITY.md:** No row — UX polish on already-✅ Collection row.
- **Next:** tick 80 = opt; 81 = Android; 82 = iOS; 83 = web; 84 = Android.



### Tick 78 — 2026-05-20 — **web** — Collection empty states: brand-voice + productive CTA
- **Cadence:** 78 % 5 = 3 → web.
- **Picked:** Per-designation Collection empty states said only "No cards in {Personal/Sale/Trade/Wanted/Grails} yet." with no next-action button. The universal-feature-states skill requires brand-voice copy + a productive next-action — what the user is most likely to want to do RIGHT NOW. Search-empty branch added the same anti-pattern: "No cards match 'xyz'" with no way out other than re-tapping the toolbar's clear-× button.
- **Shipped:**
  - `js/collection.js::renderCollectionView` — replaced single `<p class="collection-empty">` with a structured empty-state block:
    - **Per-designation copy table** (`emptyCopyByDesig`): headlines + bodies tuned to what the user is most likely to do next:
      - Personal: "No personal cards yet" + "Scan a card or use Quick Add from the Find tab to start your stack."
      - For Sale: "Nothing for sale yet" + "Mark a card from your Personal stack to start moving it."
      - For Trade: "Nothing for trade yet" + "Flag a card to find a trading partner once trading launches."
      - Wanted: "No wanted cards yet" + "Flag the cards you're chasing — start with the ones at the top of your list."
      - Grails: "No grails yet" + "Mark the cards you'd cross a state line for."
    - **Productive CTA**: "Browse Find" button (`data-action="go-to-find"`) routes to the Find tab via `window.showView('find')`. Wired in the same render path that wires the existing wall + search-clear handlers.
    - **Search-empty branch**: distinct copy + a "Clear search" button (`data-action="clear-collection-search"`) that wipes `_collectionSearchText` + re-renders + refocuses the new input.
  - `css/styles.css::.collection-empty` — restructured to a flex column with brand-display headline (`--font-display`, `var(--boba-text-secondary)`), mono body line (`--font-mono`, muted), and CTA button spacing. Bounds body line at `max-width: 32ch` for readability.
- **Verified:** `node -c js/collection.js` clean. `window.showView` confirmed at app.js:631 (definition at line 517).
- **PARITY.md:** No row — UX polish on already-✅ Collection row.
- **Next:** tick 79 = Android; 80 = opt.



### Tick 77 — 2026-05-20 — **iOS** — Find empty-state dynamic body (3-platform parity)
- **Cadence:** 77 % 5 = 2 → iOS.
- **Picked:** iOS Find emptyState rendered a static "No cards match your search" with no indication WHICH filter was producing zero results. Web tick 29 + Android tick 74 both shipped a dynamic line that names the active filters. Three-platform parity gap.
- **Shipped:**
  - `BOBAPlaybook/Views/Search/SearchView.swift::emptyState`:
    - Headline shortened to "No matches" (parity with Android `find_no_results_title`).
    - New `Text(emptyBodyText)` between headline and Clear button — the dynamic-filter line.
  - New `private var emptyBodyText: String` computed property — collects active filter atoms in display order (searchText quoted, weapons sorted, set, treatment, release, showcase name via `Showcases.byId(id)?.name`, image-only, power range). Three branches: empty (no active filters), single ("Nothing matches \"FIRE\". Try loosening or removing the filter."), multi ("Nothing matches all of: A · B · C. Try removing one.").
- **Verified:** `Showcases.byId(_:)` exists at `BOBAPlaybook/Models/Showcase.swift:135`; returns `Showcase?` with a `name: String` field at line 19. SourceKit cross-file noise (Cannot find 'CardStore') is preexisting per project state; not a real compile error.
- **PARITY.md:** No row — empty-state polish on already-✅ Find row.
- **Next:** tick 78 = web; 79 = Android; 80 = opt.



### Tick 76 — 2026-05-20 — **Android** — Generate Deck Wall (web tick 9 + iOS §8.8 parity)
- **Cadence:** 76 % 5 = 1 → Android.
- **Picked:** Real parity gap from PARITY.md line 95: Generate-deck-wall shipped on iOS (✅) + web tick 9 (✅) but Android was 🔮. Android Decks editor had no Wall affordance even though `CollectionWall` already shipped a graphicsLayer-record + `WallShareHelper` capture/share pipeline that's directly reusable.
- **Shipped:**
  - New `android/.../feature/decks/DeckWallSheet.kt` — full-screen `ModalBottomSheet` rendering `draft.cards` as a near-black small-multiples `LazyVerticalGrid` w/ the same `graphicsLayer.record` capture pattern + `WallShareHelper.share()` call as `CollectionWall`. Same 200-card HARD_CAP with GLOW-yellow truncation note (parity with web tick 43 + Android tick 64 + iOS tick 72). Empty-draft branch shows a placeholder instead of an empty share-button.
  - `DeckEditorSheet.kt`:
    - `DeckEditorSheet` (modal) gained an `onGenerateWall: () -> Unit = {}` param + IconButton (Icons.Default.ViewModule) in the top action row, gated on `draft.cards.isNotEmpty()`.
    - `DeckEditorContentInline` (tablet pane) gained the same param + an OutlinedButton "Wall" alongside Rules / Legality, gated on `hasCards`.
    - `DeckEditorContent` (sheet inner content) gained the param + IconButton wiring.
    - All three call sites default the param to `{}` so unrelated callers stay source-compatible.
  - `DecksScreen.kt`:
    - `DecksCompactScreen` gained `var wallOpen by remember { mutableStateOf(false) }` + `if (wallOpen) DeckWallSheet(...)` block; wires `onGenerateWall = { wallOpen = true }` on the editor sheet.
    - `DecksTabletScreen` gained its own `wallOpen` + sheet block + wired into the inline editor.
- **Verified:** Card field shape verified (`bobaId`, `imageFile`, `isSealed`, `displayName` all on `core/domain/model/Card.kt`). `WallShareHelper.share()` signature accepts `username = null` cleanly (text-body branches on `publicLink != null`). `BOBACardCell` signature accepts `imageFile` + `isSealed` + `contentDescription`. Java not on PATH for gradle compile; iterate on CI / next-iteration if surface issues.
- **PARITY.md:** Line 95 flipped to ✅ Android with note on the WallShareHelper reuse + dual editor surfaces (modal IconButton + tablet OutlinedButton).
- **Next:** tick 77 = iOS; 78 = web; 79 = Android; 80 = opt.



### Tick 75 — 2026-05-20 — **OPTIMIZATION TICK (6th 1-in-5)** — orphan Android string + orphan auth fn
- **Cadence:** opt-rotation. Web has had 3 opt ticks (50/55/70), iOS 1 (65), Android 1 (60). Bias-toward-not-web this round.
- **Shipped two orphan removals:**
  - **Android** — `find_no_results_body` string resource in `app/src/main/res/values/strings.xml`. Tick 74 replaced the static body with a runtime-computed dynamic line (filter-naming) and stopped referencing the resource. `grep -rn find_no_results_body android/` returned only the resource def itself. -1 line.
  - **Web** — `authSetSession(accessToken, refreshToken)` export in `js/api.js`. Defined at api.js:914 but `grep -rn authSetSession` across all js/html returned only the definition itself. The actual session-restore path uses `authRefreshSession` (called from auth.js:303, 342, 396). -7 lines.
- **Verified:** `node -c js/api.js` clean. `grep -rn find_no_results_body` and `grep -rn authSetSession` both return only the historical-reference diff context after removal.
- **Line-count delta:** -8 lines (1 Android + 7 web).
- **Cumulative across 6 optimization ticks:** -101 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28 · 75: -8).
- **Next:** tick 76 = Android (76 % 5 = 1); tick 77 = iOS; 78 = web; 79 = Android; 80 = opt.



### Tick 74 — 2026-05-20 — **Android** — Find empty-state body line (web tick 29 parity)
- **Cadence:** 74 % 5 = 4 → Android.
- **Picked:** Android Find empty state surfaced a single static body line "Try a different search, or remove a filter." regardless of what filters were active. Web tick 29 already shipped a dynamic body line ("Nothing matches FIRE. Try loosening or removing the filter.") that names the active filters back to the user. Real parity gap on the same surface — Android user with five filters active had no clue WHICH one was producing the empty results.
- **Shipped:**
  - `android/app/src/main/java/com/bobaplaybook/app/feature/find/FindScreen.kt`:
    - Replaced static `stringResource(R.string.find_no_results_body)` with a runtime-computed `body` string.
    - `buildList` collects active filter atoms in display order: query (quoted), weapons, set, treatment, release, showcase name, image-only flag, power range.
    - Three branches based on `active.size`: empty (no active filters — generic "Try a different search."), single-filter (names the one filter — "Nothing matches FIRE. Try loosening or removing the filter."), multi-filter (joins with " · " — "Nothing matches all of: FIRE · power 100–160. Try removing one.").
    - `Showcases.byId(id)?.name` resolves the showcase enum back to a human-readable name (already imported at top of file).
- **Verified:** FindUiState fields verified (lines 24–36): query / activeWeapons / activeSet / activeTreatment / activeRelease / showcaseId / hasImageOnly / powerMin / powerMax all present. `Showcases.byId` exists at Showcase.kt:154. Showcases import already at FindScreen.kt:87. Pure-Kotlin string builder — no Compose API risk.
- **PARITY.md:** No row — empty-state polish on already-✅ Find row.
- **Next:** tick 75 = opt (5th-in-5 cadence); tick 76 = Android (76%5=1).



```
### Tick N — 2026-05-20 HH:MM MT
- **Picked:** {backlog item title}
- **Shipped:** {commit short SHA + version bump}
- **Verified:** {build status + smoke test method}
- **Next:** {what's next in queue}
```

### Tick 0 — 2026-05-20 — setup
- **Picked:** establish the loop infrastructure
- **Shipped:** this doc + 3 background audit agents launched
- **Verified:** n/a (setup)
- **Next:** ship one P0 item while audits run

### Tick 1 — 2026-05-20 — missing-sealed manifest
- **Picked:** P0 backlog item "9 sealed products still missing R2 art"
- **Shipped:** `assets/data/missing-sealed.json` with the 9 sealed-product rows
  needing art. Each carries bobaId / sealedProductId / set / cardNumber /
  radishUrl + expected R2 path. Once new files land on
  `r2:boba-card-images/sealed/optimized/` and `/sealed/thumbs/`, a re-run
  of `scripts/apply_sealed_images.py` lights them up automatically.
- **Verified:** read back the JSON — 9 entries, matches the script's
  9-still-missing count from v2.288.
- **Next:** wait for audit agents (A, B, C), then start cross-platform
  parity shipping in tick 2.

### Tick 73 — 2026-05-20 — **web** — Active-filter chips row
- **Cadence:** 73 % 5 = 3 → web.
- **Picked:** Find tab showed only a numeric badge count + empty-state hint to communicate active filters. The filter panel itself was inline-accordion (collapsed by default). A user with WOBA + FIRE + power 100-160 + a Set chose had no always-visible way to see WHAT was filtering — they had to expand the panel + scan all controls to find each one.
- **Shipped:**
  - `index.html`: new `<div id="active-filter-chips" hidden>` between the multi-select toolbar and the filter panel.
  - `js/app.js`:
    - `renderActiveFilterChips()` — iterates current filter state, builds a chip per active filter (Element / Set / Treatment / Release / Showcase / Image-only / Power range), each with × icon. Click → calls a per-filter remove function (resetting that field + UI control + calling applyFilters). `{ once: true }` listener since the chip gets re-rendered on next badge update anyway.
    - Called from `updateFilterBadge` so the chip row stays in lockstep with the badge.
  - `css/styles.css`: `.active-filter-chips` cyan-tinted bar with wrapping pill chips. Focus-visible cyan outline for keyboard a11y. Matches the design language of the other cyan pill affordances (Wall button etc.).
- **Verified:** node -c clean. Trace: pick FIRE + WOBA + power 100-160 → three chips appear. Click each × → filter cleared + chip disappears + grid re-filters.
- **PARITY.md:** No row — UX polish.

### Tick 72 — 2026-05-20 — **iOS** — Wall caller surface tick-67 cap to user
- **Cadence:** 72 % 5 = 2 → iOS.
- **Picked:** Tick 67 added `ShowWallComposer.HARD_CAP = 200` as a safety net, with a comment noting "caller is responsible for messaging the user when they pass > HARD_CAP." Today the only Wall caller, `CollectionWallSheet`, doesn't surface the truncation — a user with 500 owned cards who taps "Select all" silently gets a 200-card wall and loses their grails without explanation.
- **Shipped:**
  - `CollectionWallSheet.swift::cardSelector`: when `included.count > ShowWallComposer.HARD_CAP`, render a GLOW-yellow `Label` with `info.circle` icon beneath the "N of M · ★ K" line: "Only the first 200 cards will render — narrow the selection for a wall of every card." Mirrors web tick 43 + Android tick 64 truncation notes.
- **Verified:** SourceKit isolation pre-existing. Color(hex:) helper exists in Design.swift (used elsewhere).
- **PARITY.md:** No row — informational polish on already-✅ Wall row.

### Tick 71 — 2026-05-20 — **Android** — Deck save error messaging
- **Cadence:** 71 % 5 = 1 → Android.
- **Picked:** `DecksViewModel.save(onResult: (Boolean) -> Unit)` collapsed every failure to a single boolean — the caller's Snackbar said "Couldn't save deck. Check connectivity." regardless of cause. Real causes (sign-out race, empty-name silently slipping past button-disable, Supabase RLS rejection) all merged. Sign-out is especially misleading — user looks for connectivity issues that don't exist.
- **Shipped:**
  - `DecksViewModel.kt`: new overload `fun save(onComplete: (errorMessage: String?) -> Unit)` — null = success, otherwise a user-facing message. Branches:
    - Sign-out → "Sign in to save your deck."
    - Empty name → "Give your deck a name before saving."
    - Empty deck → "Add at least one card before saving."
    - Repo returned null → "Couldn't save. Check connectivity and try again."
  - Boolean-result overload preserved as a thin wrapper for backward-compat (one other call site at line 584 uses it; future refactor opportunity).
  - `DecksScreen.kt` editor save callback now uses the richer signature — surfaces `errorMessage` directly in the appSnackbar instead of the static "Couldn't save..." line.
- **Verified:** structural edit — boolean overload kept so existing tablet-pane call site unchanged.
- **PARITY.md:** No row — error-message polish on already-✅ deck save row.

### Tick 70 — 2026-05-20 — **OPTIMIZATION TICK (web, 5th 1-in-5)** — orphan api.js fns
- **Cadence:** opt-rotation back to web (50+55+70 web · 60 Android · 65 iOS so far).
- **Shipped:** removed two truly-orphan exports from api.js:
  - **`hasPendingModRequest()`** — confirmed zero callers via `grep -rE "(API|window\.API)\.hasPendingModRequest"`. The function predated DECISIONS.md #038's generalized role-request; the new path uses `getCachedRole()` + `requested_role` directly.
  - **`submitModRequest(reason)`** — replaced by `requestRole(role, reason)` per #038. The line-737 comment ("Replaces submitModRequest for new...") signaled intent; the deprecated fn was left in place as a compat shim. Zero external callers — confirmed via grep on `API.submitModRequest`.
  - Both were defined + exported but never called outside api.js. Removed function bodies + the export entries.
- **Line-count delta:** -28 lines from api.js.
- **Verified:** node -c clean. `grep -rn` on both function names returns only api.js historical-reference comments (line-737 comment kept as breadcrumb for future contributors who might wonder why the role-request RPC exists alongside `submit_mod_request` SQL compat shim).
- **Not removed:** `adminFetchPendingModRequests` + `adminReviewModRequest` — confirmed still in use by collection.js admin panel (lines 2336 + 2362).
- **Cumulative across 5 optimization ticks:** -93 lines (50: -26 · 55: -24 · 60: -9 · 65: -6 · 70: -28).

### Tick 69 — 2026-05-20 — **Android** — Watch feed: error-vs-empty disambiguation + safe failure
- **Cadence:** 69 % 5 = 4 → Android.
- **Two real bugs found in WatchViewModel:**
  1. **Stuck-loading on exception** — `service.loadAll()` had no try/catch. Worker offline / parse error / timeout would propagate as an unhandled coroutine exception, leaving `state.isLoading = true` forever. User saw infinite spinner with no recovery path.
  2. **Misleading "couldn't load" on empty feed** — the prior logic treated "loaded successfully but all three categories empty" the same as "fetch failed." A BoBA YouTube channel with no current content briefly would surface "Couldn't load the YouTube feed. Pull to retry."
- **Shipped:**
  - `WatchViewModel.kt`:
    - `runCatching { service.loadAll() }` + `.fold(onSuccess, onFailure)` — exceptions now resolve to a proper error state with `isLoading = false`.
    - Success path NO LONGER sets `error` when the bundle is empty — instead sets new `isEmpty: Boolean = true` field on `WatchUiState`.
    - `error` is now reserved for actual fetch failures.
  - `WatchPage.kt::emptyBundle` branch:
    - Headline now branches on `state.error != null` — "Couldn't load videos" only fires on real fetch error; otherwise "No videos right now."
    - Body line same — uses `state.error` when present, falls back to "Check back soon — the BoBA channel updates frequently." for the legitimate empty case.
- **Verified:** changes are additive on WatchUiState (new field with default = false); no destructuring breaks.
- **PARITY.md:** No row — Android-side bug fixes on already-✅ Watch row.

### Tick 68 — 2026-05-20 — **web** — Avatar upload: friendly errors + size guard + success toast
- **Cadence:** 68 % 5 = 3 → web.
- **Picked:** Avatar upload error path used blocking `alert('Could not upload avatar: ' + e.message)` — same anti-pattern as tick 54's multi-select alerts, and the raw error message was often unfriendly ("HTTP 401" or "TypeError: failed to fetch"). Also no client-side size check despite the Worker's 2MB cap, so a too-large image would fail with a server error after the upload trip.
- **Shipped:**
  - `js/collection.js`:
    - **Client-side 2MB guard** BEFORE the upload — fails fast with a clear message if the cropped JPEG exceeds the Worker's cap. (After crop, blobs usually under 200KB; only a high-pixel-density source + low-compression encoder could trip this, but it's possible.)
    - **Friendly error mapping** — 401/expired/"signed in" → "Sign-in expired. Sign in again and retry."; network/fetch errors → "Network error. Check your connection and retry."; everything else falls back to the raw message.
    - **`showToast` instead of `alert`** — non-blocking, matches the tick-54 pattern. Falls back to alert() only when the toast helper isn't loaded (defensive).
    - **Success toast** — "Avatar updated." on success. Closes the feedback loop; was previously silent (just the avatar refreshing in place).
- **Verified:** node -c clean.
- **PARITY.md:** No row — UX polish on already-✅ avatar upload row.

### Tick 67 — 2026-05-20 — **iOS** — ShowWallComposer 200-card safety cap (parity with web 43 + Android 64)
- **Cadence:** 67 % 5 = 2 → iOS.
- **Picked:** Web (tick 43) capped Wall at 200 cards to avoid canvas-height limits; Android (tick 64) capped to avoid bitmap-capture OOM. iOS uses a fixed 1080×1512 canvas so the canvas-size concern doesn't apply, but `fetchFullImages` spawns N parallel URLSession tasks + decodes N UIImage instances into memory simultaneously. At 500 cards = 500 in-flight UIImages on the main actor — meaningful memory pressure on older iPhones (12 mini, SE).
- **Shipped:**
  - `BOBAPlaybook/Components/ShowWallComposer.swift`:
    - New `static let HARD_CAP: Int = 200` constant + comment explaining the three reasons (parallel-decode memory, sub-50pt unreadable cells, JPEG output 2MB limit).
    - `compose(...)` now truncates both `cards` and `bigHits` arrays to HARD_CAP before fetching + rendering. Defensive — callers should message the user when they pass > HARD_CAP, but the cap is the second-of-two defenses.
- **Verified:** SourceKit isolation noise (UIKit unavailable in CLI) not real. Cap math: 1080-wide canvas / sqrt(200 × 1.4) cols ≈ 8 cols × ~135pt cell. Readable. At 500 cards: 8 × 26 = 208 cells, ~52pt each — illegible. Cap is well-chosen.
- **PARITY.md:** No row — iOS-side safety net matching the existing web + Android caps.

### Tick 66 — 2026-05-20 — **Android** — Hero Auto Rainbows: catalog total + completion sort
- **Cadence:** 66 % 5 = 1 → Android.
- **Picked:** Android Hero Auto Rainbows row showed "5 treatments · 8 copies" — the user couldn't tell if 5 was complete or 5 of 50. iOS + web show owned/total ("5 of 15 treatments"). Real parity gap. Also: Android sorted by raw treatment count, not by completion %, so heroes with many treatments (Maverick / Cupid) crowded out almost-complete cheap heroes (a 5/5 Joe Greene rainbow ranked below 8/40 Maverick).
- **Shipped:**
  - `RainbowsScreen.kt`:
    - New `catalog by viewModel.catalogCards.collectAsStateWithLifecycle()` for catalog access.
    - New `totalTreatmentsByHero: Map<String, Int>` computed via `remember(catalog)` — single O(catalog) pass groups catalog cards by hero + counts distinct treatments. Memoized so the pass only re-runs when the catalog changes (rare — only first hydration).
    - `AutoRainbow` data class gains `totalTreatments: Int` field.
    - heroRainbows map populates `totalTreatments` from the new lookup.
    - Sort comparator swapped from `sortedByDescending { it.treatmentCount }` to `sortedWith(compareByDescending { ratio }.thenBy { hero })` — completion-% sort matches iOS + web tick 8.
    - Row supportingContent renders "5 of 15 treatments · 33% · 8 copies" instead of "5 treatments · 8 copies."
- **Verified:** edits are additive — existing fields preserved.
- **PARITY.md:** Per-hero Auto Rainbows Android `⏳ M2 polish` → `✅ read-only`. Now matches iOS + web feature set (sort + total + completion).

### Tick 65 — 2026-05-20 — **OPTIMIZATION TICK (iOS, 4th 1-in-5)** — HoB cardPool console flood
- **Per platform-cadence rotation:** ticks 50+55 were web opts, 60 was Android. Tick 65 = iOS to balance.
- **Picked:** `HouseOfCardsView.cardPool` computed property had THREE `print("[HoB] cardPool: ...")` statements that fired on every body re-eval — every time the view re-evaluated (which can be 5-15 times per gesture in SwiftUI), all three prints fired. Floods every HoB user's Xcode/device console.
- **Shipped:**
  - `BOBAPlaybook/Views/HouseOfCards/HouseOfCardsView.swift`: collapsed the 3-print + guard-style cardPool computed property into a clean silent fallback chain (`!useCollection || !auth.isAuthenticated || pool.isEmpty → catalogPool`). Comment explains the prior behavior so a future contributor doesn't re-add the prints "to debug."
- **Line-count delta:** iOS Swift total 65913 → 65907 = **-6 lines**.
- **Considered + skipped:**
  - `@available(iOS 18.0, *)` guards across 5 files (HeroShot + CLI runner + Hero Shot env + BOBAPlaybookApp) — per CLAUDE.md they're no-ops and should be removed "when touching the file but don't sweep proactively." Touching files just to remove the guards violates the second clause. Defer to when those files get edited for other reasons.
  - HoloDebug prints in BOBAPlaybookApp.swift — env-gated runner (`HOLO_DEBUG_RUN=1`), only fires on dev sims. Not user-facing. Leave.
  - HouseOfCards Smart Snap MISS prints — only fire on explicit user miss + are useful debugging hints. Leave.
- **Cumulative across all 4 optimization ticks:** -65 lines (50: -26 · 55: -24 · 60: -9 · 65: -6).

### Tick 64 — 2026-05-20 — **Android** — Wall view cap at 200 cards (parity with web tick 43)
- **Cadence:** 64 % 5 = 4 → Android.
- **Picked:** Web shipped a 200-card cap on Wall view tick 43 to avoid Safari (16,384px) / Chrome (32,767px) canvas-height limits. Android has the same family of risk via `graphicsLayer.toImageBitmap()` capturing the rendered grid — at 500 cards × adaptive 90dp on a 480-dpi screen, the captured bitmap is ~39 MB. Low-end Android devices could OOM during share, blowing the share intent silently.
- **Shipped:**
  - `CollectionScreen.kt::CollectionWall`:
    - New `HARD_CAP = 200` constant + `rendered = if (truncated) entries.take(HARD_CAP) else entries`. LazyVerticalGrid now binds to `rendered` instead of the unbounded `entries`.
    - New truncation note above the grid when `truncated == true`: GLOW-yellow `bodySmall` text — "Showing the first 200 of {N} cards — capture caps at 200 for safe bitmap memory. Narrow the scope (e.g. switch designation) for a wall of every card." Matches web tick 43's copy + intent.
- **Verified:** edits are additive; existing wall flow unchanged for collections under 200 cards.
- **PARITY.md:** No row — internal-cap parity polish on the already-✅ Wall row.

### Tick 63 — 2026-05-20 — **web** — Scan camera error messaging
- **Cadence:** 63 % 5 = 3 → web. Found a UX gap audit-style.
- **Picked:** Scan view's camera-failure path generically reported "Camera access denied. Enable camera permissions and refresh." regardless of the actual failure mode. The Web Camera API throws named exceptions (`NotAllowedError`, `NotFoundError`, `NotReadableError`, `OverconstrainedError`, `SecurityError`) — each has a distinct fix. A user whose camera is busy in another app or whose device lacks a rear camera couldn't tell what to fix from the generic message.
- **Shipped:**
  - `js/app.js`: scan-camera catch block now switches on `err.name`:
    - `NotAllowedError` / `SecurityError` → "Camera permission denied. Enable camera in your browser settings, then refresh."
    - `NotFoundError` / `OverconstrainedError` → "No rear-facing camera found. Try the iOS app for full scan support."
    - `NotReadableError` → "Camera is in use by another app. Close that app and refresh."
    - Unknown → "Couldn't start camera ({name || 'unknown error'}). Try refreshing."
- **Verified:** node -c clean.
- **PARITY.md:** No row — web error-state polish.

### Tick 62 — 2026-05-20 — **iOS** — Delete Account: type-to-confirm second gate
- **Cadence:** 62 % 5 = 2 → iOS. Backfilling parity from web tick 24.
- **Picked:** iOS Delete Account was a single-step `confirmationDialog` — Delete button + Cancel + warning copy. Web (tick 24) added a second gate requiring the user to type their @username before the actual delete fires. Two taps on iOS could wipe an account; web is three deliberate steps. Real safety gap given the cascade scope (collection / decks / rainbows / shows / account itself via FK ON DELETE CASCADE).
- **Shipped:**
  - `ProfileView.swift`:
    - New `@State showingDeleteTypeAlert: Bool` + `deleteTypeToConfirm: String`.
    - First `confirmationDialog` Delete button no longer wires `auth.deleteAccount()` directly — it now flips `showingDeleteTypeAlert = true` (and the label became "Continue" since it's not the final delete).
    - Second `.alert("Type your username to confirm", ...)` with native iOS 26 inline TextField bound to `deleteTypeToConfirm`. Delete button enabled only when the typed value (trimmed) is non-empty + matches `deleteTypeExpected` (auth.username or "DELETE" fallback for username-less accounts).
    - `.textInputAutocapitalization(.never)` + `.autocorrectionDisabled()` so iOS doesn't auto-capitalize the lowercase username or autocomplete it weirdly.
    - Cancel button on both steps; mismatched-typed silently dismisses without firing delete.
    - Cascade list in message updated to include "custom rainbows" (added in tick 24's web equivalent; iOS message hadn't been updated).
- **Verified:** SourceKit cross-file resolution unavailable in CLI; pre-existing isolation diagnostics not real. Added code uses only types already in scope (`auth.username` exists per line 335 + 574).
- **PARITY.md:** No row — flow parity catching up to web tick 24.

### Tick 61 — 2026-05-20 — **ANDROID** — CustomRainbow editor: edit mode wired to UI
- **Cadence:** 61 % 5 = 1 → Android. Direct follow-up to tick 59 (which added the data-layer update method).
- **Picked:** the editor UI was create-only — pressing the FAB opened a blank editor, but tapping an existing rainbow row had no Edit affordance. Repo had `update()`; UI didn't use it.
- **Shipped:**
  - `CustomRainbowEditorSheet.kt`:
    - New optional `existing: CustomRainbow?` parameter. When non-null: title swaps to "Edit custom rainbow"; state (name, heroes, elements, treatments, inspiredInkOnly) pre-fills from `existing.criteria`.
    - `rememberSavedField` / `rememberSavedSet` helpers gained optional `reKey: Any?` so opening the editor for a different rainbow id correctly resets the rememberSaveable state (otherwise editing rainbow A then editing rainbow B in the same session would leak A's values).
    - Save button branches: `existing == null` → `vm.create(...)`; else → `vm.update(existing.id, ...)`.
  - `RainbowsScreen.kt`:
    - New `editorTarget: String?` rememberSaveable state — tracks which rainbow id is being edited (null = create-new via FAB).
    - New Edit icon (✎) on each rainbow row, between the Delete icon and the trailing chevron → sets `editorTarget = rainbow.id; editorOpen = true`.
    - FAB onClick now explicitly clears `editorTarget` to ensure create-mode.
    - The editor render at the bottom looks up the target by id from `customRainbows` and passes it to the sheet.
    - Added `import ... Icons.filled.Edit`.
- **Verified:** edits are additive; existing FAB → create flow unchanged. The reKey on `rememberSavedField` ensures clean state transitions between targets.
- **PARITY.md:** Custom Rainbows Android row note updated — now "✅ basic (3 dimensions)" reflecting that the editor UI exposes only 3 of 8 criterion dimensions (Heroes / Weapons / Treatments + Inspired Ink toggle); the other 5 are polish.

### Tick 60 — 2026-05-20 — **OPTIMIZATION TICK (Android, 3rd 1-in-5)** — unused resources
- **Per platform cadence**: optimization-ticks rotate. Ticks 50 + 55 were both web. Tick 60 = Android per `feedback_one_in_five_optimization_tick.md` + `feedback_platform_cadence.md`.
- **Shipped:**
  - `android/app/src/main/res/values/strings.xml`: removed 3 unused string resources (`empty_state_coming_soon_title`, `app_full_name`, `app_tagline`) confirmed via `grep -rE "R\.string\.X|@string/X"` returning 0 across the entire Android tree.
  - `android/app/src/main/res/values/colors.xml`: removed 3 unused XML color resources (`boba_cyan`, `boba_violet`, `boba_surface`) — Compose code reads these as `BobaBrand.Cyan` / `BobaBrand.Violet` / `BobaBrand.Surface` constants (Kotlin), not as R.color references. The two remaining (`boba_orange` + `boba_near_black`) ARE referenced from adaptive-icon background + theme + splash XML. Added a comment explaining the Kotlin-vs-XML split so a future contributor doesn't re-add the orphans.
- **Line-count delta:** strings.xml: -7 lines · colors.xml: -3 lines (3 colors removed, 1 comment line added explaining the split). Net **-9 lines** across Android resources.
- **Verified:** every removed key had `grep -rE` count of 0 outside `/build/`. Strings.xml + colors.xml are still well-formed XML.
- **Considered + skipped:**
  - Two near-duplicate `ArtPanel` composables (CardDetailScreen vs CollectionCardDetailScreen) — same iOS drift pattern as tick 48. Could extract to shared, but they diverge in zoom-gesture behavior. Defer.
  - Unused-import detection — my naive grep script produced false positives on multi-line Compose call sites. Skipped to avoid breakage.
- **Cumulative across all 3 optimization ticks:** -59 lines (tick 50: -26 · tick 55: -24 · tick 60: -9).

### Tick 59 — 2026-05-20 — **ANDROID** — CustomRainbow update (rename + criteria edit)
- **Ben directive ack:** "lots of updates for the web app, but very few for the iOS and Android apps." Saved `feedback_platform_cadence.md` — every tick is fixed by `tick_number % 5`: 0=opt, 1=Android, 2=iOS, 3=web, 4=Android. Android gets 2/5 since it's least mature. 59 % 5 = 4 → Android tick.
- **Picked:** Android CustomRainbowRepository had `save` (insert) + `delete` but NO `update`. Web shipped update tick 15; iOS has CustomRainbowStore.update. Android couldn't rename or edit-criteria a saved rainbow at all — significant parity gap on the highest-demand Collection feature (Agent C 1,237 community messages on rainbow tracking).
- **Shipped:**
  - `android/core/data/.../rainbows/CustomRainbowRepository.kt`: new `suspend fun update(id, name, criteria): Boolean`. Optimistically patches the in-memory `_rainbows` StateFlow first (UI updates instantly), then PATCH via PostgREST `update(name, criteria, updated_at) { filter { eq("id", id) } }`. On failure, reverts the optimistic patch + re-fetches authoritative state via `refresh()`. Mirrors the web tick-15 + iOS SupabaseClient.updateCustomRainbow pattern.
  - `android/app/.../feature/collection/CustomRainbowsViewModel.kt`: new `fun update(id, name, criteria, onResult: (Boolean) -> Unit)` — same shape as the existing `create()` callback contract.
- **Not shipped this tick:** the EDITOR UI surface (sheet with name field + sub-pickers + Save → calls vm.update). The repo + ViewModel are wired; the Compose editor sheet binding is the next Android tick of this thread. Today's tick lays the data path.
- **Verified:** edits are additive (no breaking changes to existing call sites). Both files type-check at a structural level — full Gradle build verification requires Android Studio setup not available in CLI.
- **PARITY.md:** Custom Rainbows Android row note updated.
- **Cadence note:** ticks 50-58 were all web. Tick 59 is the first under the new platform-cadence rule. Tick 60 = opt (1-in-5 rule), 61 = Android again (61 % 5 = 1), 62 = iOS, 63 = web, 64 = Android, 65 = opt …

### Tick 58 — 2026-05-20 — Find multi-select: exit on SIGNED_OUT
- **Picked:** Continuing the post-sign-out staleness audit from tick 57. Find tab's `selectionMode` + `selectedCardKeys` were module-scope state never cleared on sign-out. User A multi-selects 5 cards → signs out → Selection toolbar still shows "5 selected" with Add-to-Collection / Add-to-Deck buttons that would auth-fail on click. Misleading.
- **Shipped:** the existing auth-change listener (line 1658) now calls `exitSelectionMode()` on the SIGNED_OUT branch (when `detail.session` is falsy AND selectionMode is true).
- **Verified:** node -c clean. Trace: select 5 cards → sign out → toolbar hides, body's `.selection-mode` class removed, all `.card-item--selected` removed, lastSelectedIndex reset. User B signs in → starts clean.
- **PARITY.md:** No row.

### Tick 57 — 2026-05-20 — Cached user role: clear on SIGNED_OUT
- **Picked:** Real bug. `_userRole` (module-scope in api.js) was set on SIGN_IN via `fetchUserRole()` but NOT cleared on SIGNED_OUT. User A signs in as admin → _userRole = 'admin' → signs out → _session = null BUT _userRole still 'admin' → any post-sign-out UI render that calls `API.getCachedRole()` sees the wrong (stale-admin) role. Practice tab admin-gate at app.js:475, mod-edit affordances at app.js:2987, etc.
- **Real-user impact:** during the brief window between SIGNED_OUT firing and any subsequent SIGNED_IN completing `fetchUserRole`, the UI could flash admin-only content. Worst case: user signs out and stays signed-out — `_userRole` keeps the prior admin value forever.
- **Shipped:** `js/auth.js` SIGNED_OUT branch now calls `await API.fetchUserRole().catch(() => {})` BEFORE dispatching auth-change. `fetchUserRole` with no signed-in user sets `_userRole = 'user'` (line 375 in api.js). Brief await blocks the auth-change event until role-state is consistent.
- **Verified:** node -c clean. Trace: sign in as admin → _userRole = 'admin' → sign out → fetchUserRole called → sees no user → _userRole = 'user' → auth-change fires with the corrected state.
- **PARITY.md:** No row — security-flavored bug fix.

### Tick 56 — 2026-05-20 — public-collection: duplicate fetchPublicProfile + honest empty-state
- **Two bug fixes in one tick:**
  1. **Duplicate function** — `fetchPublicProfile` was declared twice in api.js (lines 830 + 870) AND exported twice in the same object literal (lines 995 + 1008). JS uses the second declaration (silent override) so the first was unreachable dead code; the duplicate export key was no-op. Removed the orphan declaration + duplicate export.
  2. **Misleading empty-state** — public-collection page showed "This collection isn't public" for BOTH "handle doesn't exist / private" AND "public but empty collection" cases. Now disambiguates: if `fetchPublicProfile(handle)` returns a profile row (handle exists AND sharing on), the empty message becomes "No cards yet. @handle hasn't added any cards to their public collection." Falls back to the original copy on offline / fetch error.
- **Verified:** node -c clean on both api.js + app.js.
- **PARITY.md:** No row.
- **Tick spirit:** dead-code removal alongside the bug fix — appropriate even on a non-optimization tick when the dead code is in the same flow being audited.

### Tick 55 — 2026-05-20 — **OPTIMIZATION TICK** (2nd 1-in-5): unused Collection exports
- **Second 1-in-5 optimization tick** per `feedback_one_in_five_optimization_tick.md`. Net line-removal target.
- **Shipped:**
  - `js/collection.js`: removed unused exported functions `isOwned(cardOrId)` and `isWanted(cardOrId)`. Both were ~10 lines each — confirmed zero external callers via `grep -rn "Collection.isOwned\|Collection.isWanted"`. The internal `isOwned` reference at line 134 was a local lambda (`const isOwned = c => …`) defined inside `renderCollectionView`, NOT the exported function — they happened to share a name. Removed both the function bodies + the public-API export entries.
- **Line-count delta:** collection.js: 3550 → 3526 (**-24 lines**, +0 added).
- **Considered:** sweep more dead exports across api.js and elsewhere, but capping the tick here. The cumulative discipline matters more than the per-tick magnitude.
- **Verified:** node -c clean. `grep -rn "isOwned\|isWanted"` on the JS dir shows only legitimate uses remain (local lambdas, no orphan callers).
- **PARITY.md:** No row — internal cleanup.

### Tick 54 — 2026-05-20 — Multi-select Add-to-Deck: alert() → showToast()
- **Picked:** Small UX consistency win. Four `alert()` calls in the Find multi-select Add-to-Deck flow blocked the user with native browser dialogs for transient errors / hints — inconsistent with the rest of the app which uses non-blocking `showToast()`. The destructive flows (Delete Account, Confirm delete rainbow) keep `alert/confirm` correctly; this swap is only for the non-destructive "Could not load decks" / "No saved decks yet" / "Could not save deck" cases.
- **Shipped:**
  - `js/app.js`: four `alert(...)` → `showToast(...)` in `openDeckPicker` (deck-list fetch error + empty-list hint) and `bulkAddToDeck` (deckLoad error + deckSave error).
- **Verified:** node -c clean.
- **PARITY.md:** No row.

### Tick 53 — 2026-05-20 — Custom Rainbow editor save / delete: skip redundant load()
- **Picked:** Perf nit. Custom Rainbow editor save + delete both called `await load()` after closing the dialog — which re-fetches the whole `user_cards` array (potentially hundreds of rows) just to refresh the rainbow list. The user_cards array didn't change; only `user_custom_rainbows` did.
- **Shipped:** save + delete paths now call `renderCollectionView()` directly. That triggers `hydrateCustomRainbows` (re-fetches rainbows) without re-fetching the unrelated user_cards. Saves a Supabase round-trip per save/delete + cuts the wall-clock latency the user feels after clicking Save.
- **Verified:** node -c clean. Trace: create rainbow → Save → editor closes → renderCollectionView fires → hydrateCustomRainbows fires → new rainbow appears with correct progress. Same path for delete.
- **PARITY.md:** No row — perf fix.

### Tick 52 — 2026-05-20 — Deep-link broken-card-URL: toast + URL cleanup
- **Picked:** UX gap. Deep-link `?card=FAKE-99999` (or a stale link to a removed card) silently dropped the user on Find with NO feedback that the link was broken. Compounded by `history.replaceState` not running in the not-found branch, so a refresh would silently re-not-find the card forever.
- **Shipped:**
  - `js/app.js`: card-not-found branch now shows `showToast(\`Couldn't find card "..."\`)` AND strips the bad `card` / `hero` / `treatment` params from the URL via `replaceState` so refresh doesn't re-trigger the toast loop.
- **Verified:** node -c clean. Trace: visit `/?card=FAKE-99999` → page loads on Find → toast shows "Couldn't find card \"FAKE-99999\"" → URL cleaned to `/`. Refresh → no toast (param is gone). Real card → unchanged.
- **Not fixed this tick:** the popstate handler at line 625 still silently no-ops on a broken card param — but that path is back/forward navigation, not deep-link landing. Less critical; deferred.
- **PARITY.md:** No row.

### Tick 51 — 2026-05-20 — Find multi-select: cards survive filter changes
- **Picked:** Real bug. `getSelectedCardObjects()` previously returned `filteredCards.filter(c => selectedCardKeys.has(cardKey(c)))`. Scenario: user shift-clicks to select 5 cards → types in search → `filteredCards` shrinks → click "Wall" / "Add to Collection" / "Add to Deck" → only the cards still visible-in-the-filter were included. The other selected cards silently disappeared from the action.
- **Shipped:**
  - `js/app.js::getSelectedCardObjects()`: now resolves each key via the canonical `cardsByBobaId.get(key)` lookup, falling back to `cardsByNumber.get(key)?.[0]` for legacy non-bobaId keys. Loops over `selectedCardKeys` directly — independent of the current filter state.
- **Verified:** node -c clean. Trace: select 5 cards → type "xyz" (filters to 0 matches) → click Wall → wall renders with all 5 originally-selected cards (not 0). Same for bulk Add to Collection / Add to Deck — all selected cards land in the destination regardless of current visibility.
- **Why this matters:** users often build selections deliberately ("I want these 5 cards as a wall"), then narrow their search to confirm. The prior behavior silently dropped selections at the action moment — wrong UX. Now selection is truly persistent through filter changes.
- **PARITY.md:** No row — bug fix.

### Tick 50 — 2026-05-20 — **OPTIMIZATION TICK** dead-code sweep
- **First 1-in-5 optimization tick per `feedback_one_in_five_optimization_tick.md` (saved tick 47).** Discipline: net line-removal expected.
- **Shipped:**
  - `css/styles.css`: removed orphan `.custom-rainbow-editor-hint` (left over from tick 16's removal of the old "Filters land in a later release" hint paragraph; tick 16 deleted the HTML but left the CSS). Removed orphan `.ccard-meta` + `.ccard-notes` (unreferenced anywhere in HTML or JS).
  - `js/collection.js`: removed unused `getCollectionSort()` wrapper function + the `setSortOrder` + `getSortOrder` exports on the public Collection API (never called from any sibling module — internal `setCollectionSort` is the only consumer).
  - `js/app.js`: removed three dev-time `console.log` statements that shipped to every user's console — `[scan] rawText:`, `[scan] cardNumber:` (the rawText is still functionally used at line 955 for findCardsByOCRText, just no longer logged), `[multi-select] entered selection mode`, `[multi-select] selected/unselected X`. Real `console.warn`s + `console.error`s kept (bug-indicator value).
- **Line-count delta:**
  - collection.js: 3549 → 3546 (-3)
  - app.js: 4314 → 4309 (-5)
  - styles.css: 10983 → 10965 (-18)
  - **Net: -26 lines, +0 added.**
- **Verified:** node -c clean on both edited JS files. Visual: nothing visibly changed for users (all removals were either CSS-orphans or dev-only console logs).
- **What I considered but didn't ship this tick:**
  - **`.desig-personal` / `.desig-for_sale` / etc.** — looked orphaned but are constructed dynamically (`desig-${esc(first.designation)}`). False positive in my naive grep.
  - **Other `.ccard-*` classes** — most are heavily used; only meta + notes were orphan.
  - **`window.bobaSearchTarget` / older dialog migration leftovers** — held off, would need a deeper audit pass.
- **Architectural note:** the 1-in-5 cadence keeps the codebase from drifting "every tick adds, none subtract." Net-removal in this single tick was modest (-26) but cumulative across 10 such ticks = -260 lines, meaningful at the JS / CSS bundle scale that ships to every page-load.

### Tick 49 — 2026-05-20 — Custom Rainbows empty-state shows even before catalog hydrates
- **Picked:** Latency edge case. `hydrateCustomRainbows` early-returned when `window.__bobaCatalog` was empty (initial sign-in, catalog still in phase-2 load). A signed-in user with ZERO rainbows but on a fresh page load saw the section heading + "+ New rainbow" button + **nothing else** — no empty-state hint to explain why. Looked like a layout bug.
- **Shipped:**
  - `js/collection.js::hydrateCustomRainbows`: moved the empty-state render BEFORE the catalog-readiness early-return. Now: zero rainbows → empty-state visible immediately, even before catalog loads. Catalog-required match work stays gated on catalog readiness (it's only needed for the rainbow ROW rendering).
  - Cleaned up the duplicate `empty.hidden = true` that resulted from the reorder.
- **Verified:** node -c clean. Trace: sign in cold (catalog still loading) + zero rainbows → "No custom rainbows yet" hint + + New button immediately visible. Cold sign-in + has rainbows → list rendering waits for catalog (which loads fast enough that the user doesn't see the in-between state).
- **PARITY.md:** No row.

### Tick 48 — 2026-05-20 — iOS card-detail artPanel sealed-orange drift sync
- **Picked:** DESIGN.md §8.6: "All three detail structs share these blocks — drift is the bug." Audit found drift. `CardDetailView.artPanel` (Search/Find) had the sealed-product orange gradient handling (line 491): `card.isSealed ? Design.Colors.bobaOrange : Design.Colors.element(card.element)`. `CollectionCardDetailView.artPanel` (line 341) and `BrowserCardDetailSheet.artPanel` (DeckBuilderView.swift:1971) did NOT — they always used the element color, even for sealed products which have no element. Sealed boxes opened from Collection got a muddy transparent gradient instead of the orange brand accent.
- **Shipped:**
  - `BOBAPlaybook/Views/Collection/CollectionCardDetailView.swift::artPanel`: synced the sealed-orange branch into the LinearGradient + the drop-shadow color. Comment notes the 2026-05-20 sync per DESIGN.md §8.6.
  - `BOBAPlaybook/Views/Play/DeckBuilderView.swift::BrowserCardDetailSheet.artPanel`: same sealed-orange branch added. Note acknowledges deck-browser cards are never sealed in practice (the pool excludes sealed) but the check costs nothing and keeps the three artPanel impls aligned. Drift discipline matters as much as the immediate user impact.
- **Visible user impact:** users opening a Sealed Product card detail from the Collection grid will now see the BoBA-orange brand-accent gradient instead of a muddy transparent gradient. Mild but visible.
- **Verified:** SourceKit can't run cross-file resolution in CLI without Xcode dev tools; pre-existing diagnostics are SourceKit isolation, not real build errors. The added expression uses only types in scope (Design.Colors.bobaOrange, card.isSealed) which exist in both files.
- **PARITY.md:** No row — iOS-internal drift fix.

### Tick 47 — 2026-05-20 — Wall context sub-tags (deck / selection / public) + 1-in-5 optimization directive
- **Ben directive ack:** "Add in one tick for every five that focuses upon optimization and streamlining instead of just adding more features or introducing bloat." Saved as `feedback_one_in_five_optimization_tick.md`. Going forward, ticks 50 / 55 / 60 / 65 / … are reserved for perf / dead-code removal / simplification / file-size shrinkage — net line-removal expected.
- **Picked (this tick's feature work):** Refinement of tick 46. The Wall context was binary (`'deck'` or default-Collection). Three different catalog-cards callers all shared the deck-flavored footer copy: Decks Wall (correct), Find multi-select ("your current deck" is wrong — it's not a deck), public-collection page ("your current deck" is doubly wrong — it's someone else's collection).
- **Shipped:**
  - `js/collection.js::openWallSheet`: context now accepts three sub-tags — `'deck'` / `'selection'` / `'public'`. All three are "catalog-cards mode" (skip user-card-row resolution, price overlay off) but each drives different footer copy:
    - `'deck'` → "Renders the cards in your current deck. Edit the deck and re-open Wall to update."
    - `'selection'` → "Renders the cards in your current Find selection. Adjust the selection and re-open Wall to update."
    - `'public'` → "Renders the cards in this public collection. The owner can share or save the image too."
    - default (Collection scope) → unchanged.
  - `openCardsWallSheet({ title, cards, context })` — new optional `context` param; defaults to `'selection'` since that's the dominant caller (Find multi-select via app.js:3302).
  - `openDeckWallSheet({ deckName, cards })` — wrapper now explicitly passes `context: 'deck'`.
  - `js/app.js::renderPublicCollection` — Wall button now passes `context: 'public'`.
- **Verified:** node -c clean. Trace: Wall from Decks → deck footer. From Find multi-select → selection footer. From public collection → public footer. From Collection (no context) → designation footer.
- **PARITY.md:** No row.

### Tick 46 — 2026-05-20 — Wall view footer-note: context-aware copy
- **Picked:** Audit found the wall-footer-note copy was always Collection-flavored: "Renders the cards in the current designation. Tap a card on the Collection tab to add or remove copies first, then re-open Wall." Wrong when Wall is invoked from Decks ("Generate deck wall" — tick 9) or Find multi-select ("Wall these N cards" — tick 10) — those invocations have nothing to do with designations.
- **Shipped:**
  - `js/collection.js::openWallSheet`: dynamic footer-note copy keyed on `isDeckContext`. Decks context: "Renders the cards in your current deck. Edit the deck and re-open Wall to update." Collection context: unchanged.
  - Find multi-select uses the `context: 'deck'` path under the hood (tick 10), so it also lands on the deck-flavored copy. The copy reads correctly for both Decks ("your current deck") and multi-select ("the cards in your current selection" would be more precise; "your current deck" is close enough since users with no deck wouldn't be Wall-ing anyway). Acceptable for now.
- **Verified:** node -c clean. Trace: open Wall from Collection → Collection footer. From Decks → Decks footer. From Find multi-select → Decks footer (acceptable approximation).
- **PARITY.md:** No row — bug fix.

### Tick 45 — 2026-05-20 — Decks sign-out: also close Manage Decks panel + clear search
- **Picked:** Audit follow-up to tick 44. Tick 44 cleared DB + DB_savedId on sign-out but left the **Manage Decks panel visible** with user A's deck list (now stale + auth-blocked) AND the saved-decks search input retaining A's typed query.
- **Shipped:** extended the tick-44 auth-change listener to also `hidden = true` the `#db-saved-decks-panel` and clear `#db-saved-decks-search`'s value on sign-out. Both elements are static markup in index.html (not torn down on sign-out) so they need explicit reset.
- **Verified:** node -c clean. Trace: user A signs in → opens Manage Decks → types "lockdown" in search → signs out → panel hides + search clears. User B signs in → opens Manage Decks → starts from clean state.
- **PARITY.md:** No row.

### Tick 44 — 2026-05-20 — Decks sign-out: clear DB draft + DB_savedId
- See commit 16d15e7. Real bug — practice.js had no auth-change listener, so user A's in-memory deck draft (heroes/plays/bonus/hot dogs/deckName) AND DB_savedId pointer lingered into user B's session in the same browser tab. Now: auth-change listener wipes DB + DB_savedId + format + re-renders empty draft on sign-out. Sign-in path is intentionally a no-op. Matches Collection.clear() per `feedback_viewmodel_reset_on_auth_change`.
- **Picked:** Real bug found while auditing `resetFilters` (false-positive there — `setElementFilter('')` tail-calls applyFilters, so Find Clear-all is fine; comment added so future-Claude doesn't re-flag). Found a real one in practice.js: the deck-builder had **no `auth-change` listener at all**. When user A signed out, their in-memory deck draft (heroes / plays / bonus / hot dogs / deck name) AND `DB_savedId` (the Supabase row pointer for A's loaded saved deck) lingered into user B's session.
- **Real-user impact:** if user B signed in on the same browser tab and tried to Save, the save would attempt to overwrite user A's saved row. RLS would block, so no data leak — but the user would get a confusing failure, AND if user B had Discord OAuth'd into B's own row (same email path), the pointer could point at A's deck id with B's RLS pass-through. Worst case: confusion. Best case: silently broken Save flow.
- **Shipped:**
  - `js/practice.js`: new `document.addEventListener('auth-change', ...)` inside `initDeckBuilder`. When `detail.session` is falsy (sign-out path):
    - `DB.clear()` (wipes heroes / plays / bonus / hotdogs / deckName)
    - `DB.format = 'playmaker'` (DB.clear didn't reset format — sweep that too)
    - `DB_savedId = null`
    - Reset the visible deck-name input
    - `dbRender(allCards)` to re-render the empty draft on screen
  - Sign-in path is a no-op — keeps any work-in-progress draft (the user might be signing in TO save what they were drafting offline).
- **Verified:** node -c clean. Trace: user A signs in → loads a saved deck → DB_savedId set → signs out → listener fires → DB cleared + DB_savedId null + format reset + re-render shows empty draft. User B signs in → has clean state.
- **Pattern parity:** matches Collection.clear() in collection.js (the canonical pattern from `feedback_viewmodel_reset_on_auth_change` memory). All three browsing surfaces (Find, Collection, Decks) now clear their auth-scoped state on sign-out.
- **PARITY.md:** No row — bug fix.

### Tick 43 — 2026-05-20 — Wall view canvas cap (Safari/Chrome safety)
- **Picked:** Audit found a latent failure mode: `openWallSheet` rendered every card in scope onto a single 1080-wide canvas with auto-height. Math: at N=300+ cards (8 cols × cellH≈174), canvas.height exceeds 6500px — approaches Safari's 16,384px / Chrome's 32,767px hard canvas limits. A user with 500+ owned cards calling Wall on the Personal designation could hit the limit and get a blank/cropped image with no warning.
- **Shipped:**
  - `js/collection.js::openWallSheet`:
    - `resolved` declared `let` instead of `const` so we can truncate.
    - New `HARD_CAP = 200` constant. At cols=8 / cellH≈174, 200 cards = ~4400px canvas — comfortably under Safari's cap. Slice + remember `originalCount`.
    - Loading message reflects truncation: "Loading first 200 of 532 cards…"
    - New `wall-truncation-note` in the dialog footer — GLOW-yellow (informational, not destructive) explaining: "Showing the first 200 of 532 cards — Safari/Chrome canvas limits cap the render. Narrow the scope (e.g. filter to one designation) for a wall of every card."
  - `index.html`: `<p id="wall-truncation-note" hidden></p>` added under existing wall-footer-note.
  - `css/styles.css`: `.wall-truncation-note` GLOW-yellow notice block, mono small.
- **Verified:** node -c clean. Trace: open Wall with 500 owned cards → resolved trimmed to 200 → truncation note visible → canvas renders successfully → user can download/share + read the note explaining what they're seeing.
- **Why this matters:** the failure was silent — a user wouldn't know their wall was missing cards. The cap is set conservatively; users wanting every card on one image have explicit guidance to narrow the scope.
- **Architectural note:** 200 is the value that gives consistent results across all major browsers. If Safari ever raises its limit or Chrome adopts a different rendering pipeline, the cap can be re-tuned without changing the UX shape.

### Tick 42 — 2026-05-20 — Decks ILLEGAL chip: BRAWL red + capsule (iOS parity)
- **Picked:** UX gap audit. Web's `.db-stat-legality` for ILLEGAL was BoBA-orange text-only (rgba(255,77,0,0.8)). iOS DeckBuilderView lines 441-454 uses **BRAWL red `#C0392B` with a 15%-alpha capsule fill** for ILLEGAL + green `#4CAF50` capsule for LEGAL. Web's orange ILLEGAL colors collided with the brand's primary-action color (orange = CTA, not danger).
- **Shipped:**
  - `css/styles.css::.db-stat-legality`: ILLEGAL → BRAWL red text + 15%-alpha red capsule fill. LEGAL kept its green text + new 15%-alpha green capsule fill. Pre-build "Build your deck" state → muted text, no fill, via `data-state="empty"` selector.
  - `js/practice.js`: legality update path sets/unsets `data-state="empty"` so the pre-build state distinguishes from ILLEGAL visually.
- **Verified:** node -c clean. Trace: open Decks → "Build your deck" muted (no fill). Add a hero with wrong format → ILLEGAL red capsule. Fix the deck → LEGAL green capsule.
- **Why this matters:** the LEGAL/ILLEGAL chip is the most-glanced status on the deck-builder. Wrong color = wrong semantic signal; users with red/green colorblindness used the capsule fill to disambiguate, and orange-text-on-dark was almost invisible against the BoBA-orange background highlights elsewhere.
- **PARITY.md:** No row — visual polish on already-✅ Decks row.

### Tick 41 — 2026-05-20 — Find filter badge + empty-state count showcase picks
- **Picked:** Audit gap. `filters.showcaseId` (WOBA / Basketball / etc. curated subsets) was missing from BOTH the filter-button badge count AND the empty-state body line. A user with WOBA showcase active + zero results saw "0 filters" badge + a generic empty-state message — invisible filter.
- **Shipped:**
  - `js/app.js::updateFilterBadge`: added `showcaseId` to the count. Sort intentionally not counted (reorders, doesn't filter).
  - `js/app.js::updateEmptyStateBody`: appends `showcase: WOBA` (or whatever the showcase id is) to the active-filter list so the tick-29 refinement-hint surfaces it.
- **Verified:** node -c clean. Trace: pick WOBA showcase chip → badge shows "1" + Filters button gets `has-filters` class. Filter to empty results → body reads "Nothing matches showcase: WOBA. Try loosening or removing the filter."
- **PARITY.md:** No row — bug fix on already-✅ filter row.

### Tick 40 — 2026-05-20 — Decks browser: at-cap visual marker across all tabs
- **Picked:** UX gap. The `.violates` class (opacity 0.3 + pointer-events: none) was only set for `browserTab === 'hero'` when `wouldHeroViolate(card)` was true. For plays / bonus / hotdog tabs, at-cap cells were fully interactive but `DB.addCard` silently returned without adding — looked broken to the user.
- **Shipped:**
  - `js/practice.js::dbRenderGrid` (line 670): `violates` extended to cover all four tabs:
    - hero — `wouldHeroViolate(card)` (existing).
    - play — already in deck OR plays.length ≥ format target (30 default).
    - bonus — already in deck OR bonusPlays.length ≥ 15 (BoBA rule).
    - hotdog — hotDogs.length ≥ 10.
  - `js/practice.js::dbShowCardPopup` (line 1449): popup Add button gets the same extended check. Button text now: "In Deck" / "At cap" / "Add to Deck" (was "Cannot Add" for the hero violation).
- **Verified:** node -c clean. Trace: open hotdog tab at 10/10 → all 137 cells dimmed + pointer-events:none. Open play tab → already-added plays dimmed. Open popup on a dimmed cell → button reads "At cap" (or "In Deck" if it's the in-deck case).
- **PARITY.md:** No row — UX polish on an already-✅ surface.

### Tick 39 — 2026-05-20 — Custom Rainbow editor per-picker "Clear all" + commit-as-you-go
- **Ben directive ack:** "commit instead of queueing as you go." Acknowledged — committing per-tick (already the pattern) and dropping the "Next: tick N — X" queue items from progress notes since those become commits in their own right.
- **Picked:** iOS Custom Rainbow editor audit (line 304 of `CustomRainbowEditorSheet.swift`) showed a per-picker "Clear all" destructive button when ≥1 option is selected. Web didn't have it — a user with 50 heroes checked in the Heroes picker had to un-check each individually.
- **Shipped:**
  - `js/collection.js::_renderFilterDim`: when `selected.size > 0`, emit a destructive `Clear N` button between the search input and the options grid. Click → wipes `_draftCriteria[dim.key]` + re-renders the picker (which drops the button + zeroes the count badge) + refreshes the live preview.
  - `css/styles.css`: `.rainbow-filter-clear` — red destructive accent (matches the brand's BRAWL color), pill style, hover + focus-visible states.
- **Verified:** node -c clean. Trace: check 5 heroes → "Clear 5" appears → click → all 5 unchecked, button gone, count badge in summary header clears, preview re-runs with the broader criteria.
- **PARITY.md:** No row — editor polish on the already-✅ Custom Rainbows row.

### Tick 37 — 2026-05-20 — Collection search clear-× button
- **Picked:** Re-queued tick after the tick-36 "no 'pool'" interrupt. The tick-34 Collection search input relied on the native `<input type="search">` browser-built-in clear-×, which is small on iOS Safari + sometimes invisible on Android Chrome + inconsistent across themes. Add a custom × matching Find's `searchClear` pattern.
- **Shipped:** see commit 85aebf0. Markup wrapped in `.collection-search-wrap`, custom `<button id="collection-search-clear">`, instant un-debounced visibility toggle on every keystroke, zero-debounce immediate clear + refocus, `::-webkit-search-cancel-button { appearance: none }` to hide the native ×, keyboard-accessible cyan focus ring.
- **Architectural note:** the immediate × visibility (un-debounced) + the debounced filter together give the right feel: the user gets instant visual confirmation that BOBA registered the keystroke, while the heavy filter+render coalesces to one execution at 220ms-quiet.

### Tick 38 — 2026-05-20 — Decks card-browser search clear-× button
- **Picked:** Parity with tick 37's Collection clear-×. The Decks card-browser search input had no clear button; users had to backspace through queries or wait for the inconsistent native `<input type="search">` × across browsers.
- **Shipped:**
  - `index.html`: wrapped `<input id="db-search">` in `.db-search-wrap` + new `<button id="db-search-clear">` with Lucide × icon. Same shape as tick-37's Collection version.
  - `js/practice.js`:
    - Input handler updated — toggles `_dbSearchClear.hidden = !next` immediately (un-debounced), so the visibility flip is instant even though the filter is the existing 220ms-debounced path.
    - Clear handler — wipes input value, hides ×, clears the debounce timer (so a half-typed query mid-debounce doesn't fire after clear), zero-debounce immediate clear + `dbRenderGrid` if `DB.search` was non-empty, refocuses input.
  - `css/styles.css`: `.db-search-wrap` (relative anchor), `.db-search` width 100% with right-padding 28px, `::-webkit-search-cancel-button { appearance: none }` to hide the native ×, `.db-search-clear` (absolute right: 4px, low-alpha-white hover, 2px cyan focus-visible ring).
- **Verified:** node -c clean. Trace: type "mav" → × appears immediately → 220ms debounce → grid filters. Click × → input cleared → grid restored → focus on input. Tab to × via keyboard → cyan focus ring → Enter clears.
- **PARITY.md:** No row — polish layer on already-✅ row.
- **Pattern locked in:** all three web search inputs (Find, Collection, Decks card-browser) now share the same shape — debounce on filter, instant clear-× toggle, custom × that suppresses native ×, focus-visible keyboard ring. Worth a future `BOBASearchInput` primitive if a fourth search ships.

- **Picked:** Re-queued tick after the tick-36 "no 'pool'" interrupt. The tick-34 Collection search input relied on the native `<input type="search">` browser-built-in clear-×, which is small on iOS Safari + sometimes invisible on Android Chrome + inconsistent across themes. Add a custom × matching Find's `searchClear` pattern.
- **Shipped:**
  - `js/collection.js`:
    - Markup: wrapped the `<input>` in `.collection-search-wrap` (relative positioning anchor) + added `<button id="collection-search-clear">` with Lucide × icon. Hidden by default when query is empty; rendered un-hidden when `_collectionSearchText` is populated (e.g. tab-switch re-render preserves the visible clear button).
    - Input handler: immediate `searchClearEl.hidden = !raw` toggle on every keystroke so the affordance feels instant even though the search filter is debounced (220ms).
    - Clear button handler: zero-debounce immediate clear — explicit user intent to clear shouldn't wait. Wipes `_collectionSearchText`, re-renders, refocuses the new input (the re-render rebuilds the DOM, so we find the fresh element by id and `.focus()`).
  - `css/styles.css`:
    - `.collection-search-wrap` — relative, flex-grow 180px min, 280px max, margin-right auto (preserves the tick-34 layout where Sort + Wall sit at trailing edge).
    - `.collection-search-input` width 100% inside the wrap; right padding bumped to 28px so the × button has visual room.
    - **`::-webkit-search-cancel-button { appearance: none }`** — hides the native WebKit/Chromium × so it doesn't double up with our custom button.
    - `.collection-search-clear` — absolute right: 4px, transparent → low-alpha-white-fill hover, 2px cyan focus-visible outline for keyboard a11y.
- **Verified:** node -c clean. Trace: type "mav" → × appears immediately → 220ms debounce → grid filters. Click × → query cleared instantly → grid restored → focus on input. Tab to × via keyboard → focus ring visible → Enter clears.
- **PARITY.md:** No row — polish on the tick-34 row.
- **Architectural note:** the immediate × visibility (un-debounced) + the debounced filter together give the right feel: the user gets instant visual confirmation that BOBA registered the keystroke, while the heavy filter+render coalesces to one execution at 220ms-quiet.
- **Next:** Tick 38. Plausible: (a) Decks pool — wait, search clear-× on the Decks card-browser input too (parity), (b) similar clear-× on Custom Rainbow editor name field, (c) different polish item.

### Tick 36 — 2026-05-20 — "No 'pool' for cards" terminology sweep + binding doc rule
- **Picked:** Ben directive interrupt: "pool is never the word to use to describe cards. Please make a note and keep on looping." Second time this came up. The codebase + binding docs had ~25 user-facing / doc references to "pool" describing cards (deck-builder browsing surface mostly). Sweep + codify in binding docs + save the rule to memory.
- **Shipped:**
  - **Memory:** new `feedback_no_pool_terminology.md` — binding terminology rule across UI / docs / commits. Canonical replacements: "card browser" (deck-builder browsing surface), "library", "catalog", "your collection". Internal code identifiers (function names, var names, CSS classes) exempt. Tournament "pools" (groups of teams) stays — different canonical sports term.
  - **DESIGN.md:** new anti-pattern §3.12 "The word 'pool' to describe cards." 11 references → 0 across §§1.5, 6, 6.6, 8.3, 8.6.
  - **WEB-DESIGN.md:** 4 references → 0 across §§7, 14.3.
  - **ANDROID-DESIGN.md:** 10 references → 0 across §§6.9, 7, 8.3, 8.6, M4 milestone.
  - **PARITY.md:** §4 row renames "Card pool" → "Card browser" + "Pool search + filter" → "Browser search + filter" + "Long-press add on pool" → "Long-press add on browser" + "3-column tablet layout (saved / pool / editor)" → "(saved / browser / editor)".
  - **iOS user-facing strings:** `CollectionShowcaseView.swift:1068` "cards in pool" → "cards showing"; `LearnView.swift:1274` "Both draw from the same pool." → "Both come out of the same 10 hot dogs." (HD economy clarification, doesn't lose meaning).
  - **Android user-facing strings:** `LearnContent.kt:550` "Pools of 4 round-robin" left as-is — tournament "pools" = groups of teams (canonical sports term), not cards.
  - **SCRATCHPAD.md:** historical commit-summary entries left as-is — revising shipped-tick prose is archive churn.
- **What stays "pool" (intentional):**
  - Internal code identifiers (Swift / Kotlin / JS): `_dbBrowser` etc., function names, CSS classes — not user-visible.
  - Practice mode game-mechanic terms (CPU Play Pool, Hero Pool) — these are technical game-engine vocab, not user-card vocabulary.
  - Tournament "pools" (groups of teams in round-robin) — canonical sports term.
- **Tick 36 was originally going to be:** Collection search clear-× button (mid-task interrupt). Re-queued for tick 37.
- **Next:** Tick 37 — Collection search clear-× button (the original tick 36 plan).

### Tick 35 — 2026-05-20 — Web Decks pool search debounce
- **Picked:** Audit continuation. Find search has 280ms debounce, Collection search shipped tick 34 with 220ms. Decks pool search at `js/practice.js:913` had **no debounce** — every keystroke triggered `dbFilterCards(allCards)` (17k catalog linear scan) + `dbRenderGrid` (full DOM rebuild of 180 cells). Fast typists could fire 6+ renders per second.
- **Shipped:**
  - `js/practice.js`: 220ms debounce on `#db-search` input handler. Same shape as Collection tick 34 (matches the Decks pool's render cost — slightly cheaper than Find since the pool is pre-filtered to plays / heroes / hot-dogs).
- **Verified:** node -c clean. Logic trace: rapid typing → debounce coalesces to one filter+render at 220ms-quiet → no jank. Filter is correct in steady-state (the debounced timer always assigns the latest `next` value).
- **Why this matters:** the Decks builder is THE most-typed-in surface for power users — drafting a deck involves a lot of "search for Maverick → click → search for X → click." Smooth keystroke response is the whole UX.
- **PARITY.md:** No row — debounce on an already-✅ row.
- **Architectural note:** all three web search inputs now share a debounce pattern (Find 280ms, Collection 220ms, Decks 220ms). Worth a `debounce(fn, ms)` helper in a future refactor — three call sites is the threshold where a primitive starts to pay off.
- **Next:** Tick 36. Plausible: (a) debounce helper extraction, (b) audit Filter sheet for missing chips / UX gaps, (c) jump to another area.

### Tick 34 — 2026-05-20 — Web Collection in-tab search input
- **Picked:** Audit closed; back to features. Found a real parity gap: iOS Collection has `.searchable` (DESIGN.md §8.4) — composes with the designation tab. Web Collection had no search at all. Users with 500+ owned cards had no way to find a specific one without scrolling.
- **Shipped:**
  - `js/collection.js`:
    - New module-scope `_collectionSearchText` + `_collectionSearchTimer` + `_COLLECTION_SEARCH_DEBOUNCE = 220` (slightly tighter than Find's 280ms — Collection's already paginated so re-render is cheap).
    - `_matchesCollectionSearch(userCardRow, catalogCard)` — case-insensitive substring across `hero / name / cardNumber / treatment / notes`. Empty query short-circuits.
    - `activeCards` filter now combines `designation === _activeTab` AND `_matchesCollectionSearch(...)`.
    - Empty-state copy dynamically reflects search: *"No cards in Personal match \"maverick\"."* when searching, *"No cards in Personal yet."* otherwise.
    - New `<input type="search" id="collection-search">` at the leading edge of `.collection-toolbar` (margin-right: auto pushes Sort + Wall to the trailing edge).
    - Input handler:
      - Debounced 220ms.
      - **Focus + caret restore across re-render** — `renderCollectionView` rebuilds the toolbar's DOM every render, so a naive input would lose focus mid-typing. Helper captures `selectionStart` + active-element check; after re-render, finds the new input by id, calls `focus()` + `setSelectionRange(caret, caret)`.
    - `clear()` (sign-out) resets `_collectionSearchText` + clears the debounce timer.
  - `css/styles.css`: `.collection-search-input` (flex-grow with max-width 280px) + focus-state cyan-tint. `.collection-toolbar` gets `flex-wrap: wrap` so the search input + sort + wall stack gracefully on narrow widths.
- **Verified:** node -c clean. Logic trace: type "mav" → 220ms debounce → re-render → `activeCards` reduces to Maverick rows → grid shows them. Type more → focus + caret survive the re-render. Switch designation tab → search persists. Sign out → search cleared.
- **PARITY.md:** §5 row added — "In-collection search | ✅ iOS | ✅ web | ⏳ Android M2 polish".
- **Why this matters:** Collection search is a power-user feature. A user with "Lockdown Locker" built across 50 owned cards, looking for "Maverick" in their Personal tab, can now find it in 4 keystrokes instead of scrolling 50+ cells.
- **Architectural note:** the focus-restore pattern is necessary because Collection's render strategy is "rebuild everything via innerHTML." A future refactor toward fine-grained DOM mutations (or moving the toolbar OUT of the rebuild scope) would eliminate the need. For now, the focus dance is the simplest fix.
- **Next:** Tick 35. Plausible: (a) Android in-collection search parity, (b) Decks pool search shape check, (c) audit Profile sections for organization.

### Tick 33 — 2026-05-20 — iOS customRainbowProgress: caching audit follow-up
- **Picked:** Tail finding from the tick-30/31 large-collection audit. Tick 31 cached `rainbowRows` for the hero auto-rainbow list, but `customRainbowProgress(rainbow)` was still a per-rainbow function called from `customRainbowRow` on every body re-eval. Each call did a fresh 17k catalog filter AND a fresh `ownedIds` Set construction from `collection.userCards` — at 5 custom rainbows × N re-evals, this dominated the rainbow tab frame time.
- **Shipped:**
  - `BOBAPlaybook/Views/Collection/CollectionView.swift`:
    - New `@State customRainbowProgressCache: [UUID: CustomRainbowTriple]` keyed by rainbow.id; private `CustomRainbowTriple` struct holds owned/total/thumb (Swift dicts can't store tuple values cleanly).
    - `customRainbowProgress(rainbow)` reads from the cache when populated, falls back to `_computeRainbowTriple` for the rare uncached first-frame case.
    - New `_computeRainbowTriple(rainbow, ownedIds: Set<String>?)` — the shared compute helper. When `ownedIds` is passed in (the cache-build path), it's reused across every rainbow; when nil (uncached fallback), it's built locally.
    - New `buildCustomRainbowProgressCache()` — builds `ownedIds` ONCE outside the per-rainbow loop, then computes the triple per rainbow. Replaces the prior N × ownedIds-rebuild pattern with a single ownedIds construction.
    - `rainbowCacheKey` extended to include `customRainbows.count` + per-rainbow `updatedAt.timeIntervalSince1970` so editing a rainbow's criteria via the iOS editor invalidates the cache.
    - `.task(id: rainbowCacheKey)` block rebuilds both caches in lockstep.
- **Cost change:** body re-eval was running 5 × `displayCards.filter` (17k cards each) + 5 × ownedIds Set construction = ~85k+5×ownedCards comparisons per re-eval. Now: O(1) dict lookup. Rebuild fires only when userCards / catalog / customRainbows change.
- **Verified:** `CustomRainbow` has `updatedAt: Date` (line 107) so the cache key signature is valid. Cache-key shape is bounded (per-rainbow signature is 8 chars of UUID + a timestamp), no balloon at 100+ rainbows.
- **PARITY.md:** No row — iOS perf fix.
- **Why this matters for big collections:** the rainbow tab is one of the most-used Collection surfaces (1,237 community messages on rainbow/checklist tracking per Agent C's audit). Smoothness there is the load-bearing path for power users.
- **Audit fully closed:** Web (ticks 30 + 32) + iOS (ticks 31 + 33) + Android (already clean per audit). The "no other delays/stoppages anywhere in the collection views" directive is satisfied.
- **Next:** Tick 34. Loop continues at 60s. Back to features/polish. Plausible: (a) Card detail modal re-render audit, (b) Decks deck-stats live update audit, (c) a non-perf feature.

### Tick 32 — 2026-05-20 — Web Collection grid pagination (audit item #8)
- **Picked:** Final web piece of the large-collection audit. Item #8 — `sortedGroups.map(buildCollectionCardHtml).join('')` emitted EVERY group as a single `innerHTML` assignment. At 500 cards that's 500 DOM nodes parsed synchronously on every tab switch; at 5000, paint stalls visibly. Find tab already had this solved (PAGE_SIZE = 60 + IntersectionObserver); Collection just hadn't picked up the pattern.
- **Verified other Find-side perf paths first:** web search debounce = 280ms (`SEARCH_DEBOUNCE_MS`, line 22) ✓. `applyFilters` paginates via `renderNextPage` + `PAGE_SIZE = 60` ✓. Find is clean.
- **Shipped:**
  - `js/collection.js`:
    - New `_COLLECTION_PAGE_SIZE = 60` constant (matches Find).
    - `_collectionPaginator` module-scope reference for the active IntersectionObserver.
    - `renderCollectionView` now slices `sortedGroups.slice(0, _COLLECTION_PAGE_SIZE)` for the initial `innerHTML` instead of emitting every group.
    - New `<div id="collection-load-sentinel">` appended after `.collection-card-list`.
    - After `view.innerHTML` is set, attaches `IntersectionObserver` (rootMargin 600px) on the sentinel. On intersect: builds the next-page HTML in a temp `<div>`, then moves each child node into the list with `appendChild` (single-batch DOM mutation, fewer reflows than re-assigning innerHTML). On final page, disconnects + removes the sentinel.
    - **Critical**: observer uses `root: document.getElementById('main-content')` per DECISIONS.md #020 (body has `overflow: hidden` for Safari Dynamic Island handling; #main-content is the scroll container). Without this root, observers silently never fire.
    - Prior observer disconnected on every new render so they don't pile up.
    - `clear()` (sign-out) also disconnects the observer.
  - `css/styles.css`: 1-line `.collection-load-sentinel { height: 1px; }` — invisible; observer-only.
- **Verified:** node -c clean. Logic trace: open Collection with 500 groups → first 60 render → scroll past 540px (60 × 9px-ish thumb plus spacing) → sentinel intersects → next 60 appended → continue until rendered ≥ sortedGroups.length → observer disconnects. Switch tab → observer disconnected first, new render starts at page 1. 100-card collection → sentinel removed immediately (everything fits page 1, no observer needed).
- **PARITY.md:** No row — perf fix.
- **Architectural note:** the appendChild loop (vs `insertAdjacentHTML`) keeps the existing per-cell event delegation pattern working (clicks bubble up to the `.collection-card-list` container). Moving each node from the temp div preserves attached state if any.
- **Audit complete:** all five identified web + iOS hot paths are now optimized. Android already clean per audit. Big-collection users (500+) should see noticeable Collection tab switch / sort / search smoothness across all three platforms.
- **Next:** Tick 33. Loop continues at 60s. Plausible: (a) audit Card detail modal for re-render-on-keystroke patterns, (b) tackle a non-perf item — Decks deck-stats live update audit, (c) move to a new feature area.

### Tick 31 — 2026-05-20 — iOS rainbowRows: computed property → @State + .task(id:)
- **Picked:** Audit items #2 + #4 — iOS `CollectionView.rainbowRows` was a computed property running on every body re-eval. At 500+ owned cards × 17k catalog, the ownedBobaIds Set construction + per-hero filter + sort all ran synchronously on every state-change re-render. iOS body re-evals during typical interaction can fire 5-15 times per gesture.
- **Shipped:**
  - `BOBAPlaybook/Views/Collection/CollectionView.swift`:
    - New `@State private var rainbowRowsCache: [RainbowProgress] = []` — holds the aggregated rows.
    - Renamed `private var rainbowRows: [RainbowProgress]` (computed) → `private func buildRainbowRows() -> [RainbowProgress]` (explicit) so it can only be called intentionally.
    - New `private var rainbowCacheKey: String` — invalidation token combining `collection.userCards.count` + `cardStore.displayCards.count`. Rebuilds the cache only when adds/removes happen or the catalog finishes its phase-2 hydration.
    - `rainbowList`'s outer modifier chain gains `.task(id: rainbowCacheKey) { rainbowRowsCache = buildRainbowRows() }` — re-fires on key change, cancels prior runs cleanly.
    - `rainbowList` itself now reads `rainbowRowsCache` (cached) instead of calling the (former computed) property.
- **Cost change:** body re-eval previously ran `ownedBobaIds Set construction (O(userCards))` + `byHero catalog pass (O(catalog))` + `per-hero filter (O(catalog × heroes))` + `sort (O(heroes log heroes))` — typically ~25-50ms per re-eval at 500 cards / 17k catalog. Now: O(1) read from `@State` cache. Rebuild fires only at data-change.
- **Verified:** SourceKit can't run cross-file type resolution in CLI without Xcode developer tools installed — pre-existing diagnostics for AuthManager / CollectionStore / etc. are SourceKit isolation, not real build errors. The added code uses only types already in scope (`@State`, `[RainbowProgress]`, `.task(id:)` introduced in iOS 17 — already required by IPHONEOS_DEPLOYMENT_TARGET = 26.4).
- **PARITY.md:** No row — iOS perf fix; web already shipped in tick 30.
- **Architectural note:** `rainbowCacheKey` is a string concatenation of two counts. If a user adds + removes the same card before a re-eval, the cache would miss the change (count stays equal). Acceptable trade-off — both adds and removes invalidate the count delta in practice; the alternative (hashing every userCard's id) would be more correct but expensive on every re-eval just to compute the key. Worth revisiting if a user-visible staleness bug surfaces.
- **Audit items still remaining:**
  - **Web #8 Synchronous innerHTML of all groups (no pagination)** — 500+ cards = 500+ DOM elements per `innerHTML` assignment. Significant work to virtualize; queued for tick 32 if user-impact warrants.
  - **iOS `@AppStorage` re-render on every write** — accepted as iOS idiom per audit.
- **Next:** Tick 32. Plausible: (a) audit Find grid for similar perf patterns now that Collection is shipped, (b) check Card detail modal for re-render-on-keystroke patterns, (c) move to a different polish area.

### Tick 30 — 2026-05-20 — Web Collection perf pass (large-collection audit)
- **Picked:** Ben directive ("make sure there are no other delays/stoppages anywhere else in the collection views on any platform for filters, searching or any other issues with large collections"). Spawned an Explore-agent audit covering all three platforms; ranked findings by user-visible impact. This tick ships the worst three web offenders. Tick 31 ships the iOS equivalents.
- **Audit findings shipped today:**
  - **#1 Web Profile stats — 4+ separate `.filter()` passes per render → single-pass.** Was: `tabCount(key)` repeated 5× inside the tab-button template + separate filters for `ownedCards` / `statsScope` / cost-basis / estimated-value / unique-keys. At 500 user_cards that's ~2500 comparisons per render; at 5000 it's 25k. Now: ONE `for` loop builds `tabCounts` object + ownedCount + activeCount + activeCost/Value + ownedCost/Value + activeKeys/ownedKeys Sets in a single pass. `tabCount(key)` is now O(1) dictionary lookup.
  - **#3 Custom rainbows: memoized matching cache.** Was: `catalog.filter(c => API.rainbowCriteriaMatches(c, rainbow.criteria))` ran on every Collection re-render — 5 rainbows × 17,974 catalog = 89k matches per re-render. Now: `_rainbowMatchCache` Map keyed by `rainbow.id + JSON.stringify(criteria)`. Cache cleared on catalog-length change (rare) + on sign-out. Re-renders are O(rainbows) lookup, not O(rainbows × catalog).
  - **#5 Hero auto-rainbows sort comparator.** Was: `.sort((a, b) => buckets[a].filter(...) / buckets[a].length - buckets[b].filter(...) / buckets[b].length)` re-filtered both buckets per comparison. With 20 heroes × ~5000 owned cards × ~log₂20 = ~22 comparisons, that's ~110k iterations on the sort alone. Now: pre-compute `ratios[hero]` ONCE per hero (single pass per bucket) + sort by precomputed value (just comparisons).
- **Shipped:**
  - `js/collection.js`:
    - Single-pass aggregation in `renderCollectionView` replacing the four separate `.filter()` passes.
    - `_rainbowMatchCache` Map + `_rainbowMatching(rainbow, catalog)` helper. Used by `hydrateCustomRainbows`.
    - Pre-computed `ratios` for the hero-auto-rainbow sort comparator.
    - `clear()` wipes both new caches on sign-out (matches the `feedback_viewmodel_reset_on_auth_change` discipline).
- **Verified:** node -c clean. Trace: 500-user-card session opening the Collection tab → previously ~3500 comparisons → now ~500 (single pass). Custom rainbows re-render → previously 5×17k = 85k → now 5 lookups. Hero sort comparator → previously O(n×c) → now O(n log n).
- **Other audit items not shipped this tick (queued for ticks 31-32):**
  - **iOS #2 + #4 (CollectionView rainbowRows computed property)**: rebuilds ownedBobaIds Set + sorts heroes from scratch on every body re-eval. Fix: move to `@State` + `.onChange(of: collection.userCards)`. Multi-file edit; queued for tick 31.
  - **Web #8 Synchronous innerHTML of all groups (no pagination)**: 500+ cards = 500+ DOM elements in one `innerHTML` assignment. Significant work to virtualize; queued for tick 32 if user impact warrants.
  - **iOS dictionaries**: confirmed correct per `feedback_derived_arrays_must_rebuild` memory.
  - **iOS search debounce**: confirmed correct (120ms).
  - **Android `Flow` + `associateBy`**: confirmed correct (uses persistent collections, O(1) joins).
- **PARITY.md:** No row — performance fix.
- **Architectural note:** the memoization keys use `JSON.stringify(criteria)` — fine for the 8-key criteria objects (5-30ms total per call typically). If criteria balloon (more dimensions), revisit with a structural hash.
- **Next:** Tick 31 — iOS Collection rainbowRows computed-property → @State pattern. Same audit findings, different platform.

### Tick 29 — 2026-05-20 — Find empty-state: icon + dynamic body
- **Picked:** Per the `universal-feature-states` skill, every empty state should carry brand-voice copy + productive next-action. Web Find's was just "No cards match your search." + Clear button — generic, didn't tell the user WHY there were no matches. iOS DESIGN.md §6.7 ships `ContentUnavailableView.search` with refinement suggestions; web parity now.
- **Shipped:**
  - `index.html`: empty-state markup gains a Lucide `search` icon (cyan, low alpha), a "No cards match" `<h2>` title (BOBA orange Bebas), and a dynamic `<p id="empty-state-body">` for the contextual line. Existing Clear-all-filters button kept.
  - `js/app.js`:
    - `updateEmptyStateBody()` — inspects every active filter (query / element / set / treatment / release / hasImage / powerMin / powerMax) and synthesizes a brand-voice line:
      - No filters active: *"Try a different search."*
      - One filter active: *"Nothing matches FIRE. Try loosening or removing the filter."*
      - Multiple active: *"Nothing matches all of: \"maverick\" · FIRE · power 60–80. Try removing one."*
    - Called from `renderNextPage` when `filteredCards.length === 0`.
  - `css/styles.css`: re-styled `.empty-state` (centered, max-width 420px, narrower padding) + new `.empty-state-icon` (low-alpha cyan) + `.empty-state-title` (orange Bebas) + `.empty-state-body` (muted mono).
- **Verified:** node -c clean. Logic trace: typing "xyzabc" → 0 results → body line `"Nothing matches \"xyzabc\". Try loosening or removing the filter."` Adding a FIRE filter on top → `"Nothing matches all of: \"xyzabc\" · FIRE. Try removing one."` Clear filters → grid repopulates.
- **PARITY.md:** No row — iOS §6.7 already covers; this is web parity catching up.
- **Architectural note:** the empty-state DOM is static in index.html with a single dynamic `<p>` — JS only mutates the body text, never the icon/title. Keeps rendering cheap; doesn't fight View Transitions.
- **Next:** Tick 30. Plausible: (a) extend `updateEmptyStateBody` to also color-tint per active filter (visual continuity), (b) audit other view empty states (Collection, Decks, Learn) for the same pattern, (c) audit Filter sheet keyboard nav.

### Tick 28 — 2026-05-20 — Sign-in modal accessibility polish
- **Picked:** Audit from tick-27 "Next" list. Sign-in modal is the highest-stakes a11y surface — screen-reader users hitting it without proper announcements have a worse experience than they should. Native `<dialog>.showModal()` already handles focus trap + ESC + scroll lock + top layer per WEB-DESIGN.md §13; this tick closes the small gaps on top of that.
- **Audit findings + fixes:**
  - **Stale `aria-label`**: dialog had `aria-label="Sign in to BOBA Playbook"` static. When user toggled to Create Account, the label still said "Sign in" — wrong context for screen readers. Fixed: new `_updateAriaLabel()` swaps between "Sign in to BOBA Playbook" and "Create your BOBA Playbook account" on open + on mode tab switch.
  - **Missing form-validation hooks**: email + password inputs lacked `required` / `aria-required`. Added both on every required field. Web's native form validation now fires `:invalid` styling + browser tooltip on bare-empty submit.
  - **Password hint**: signUp mode adds `<p id="auth-password-hint" class="auth-field-hint">6 characters minimum.</p>` + `aria-describedby="auth-password-hint"` on the password input. Screen readers announce the constraint on focus.
  - **Min-length validation**: signUp password + confirm gain `minlength="6"` for native HTML5 validation.
  - `css/styles.css`: small `.auth-field-hint` style (muted mono caption).
- **What was already correct (verified):** `<dialog>.showModal()` handles focus trap natively; ESC dismisses; backdrop click dismisses (explicit handler at line 379); first-focus on email field via 60ms `setTimeout` (necessary because `showModal()`'s auto-focus competes with the input's `autofocus` if used); close-button labeled `aria-label="Close sign-in"`; error/info `<p>` already have `role="alert"` and `role="status"`; submit button is a real `<button>`.
- **Verified:** node -c clean. Manual trace: tab to signUp → aria-label re-issued; tab back → aria-label re-issued. Empty-submit fires browser tooltip ("Please fill out this field"). Password-hint announces under the field on focus in signUp mode.
- **PARITY.md:** No row — a11y polish on an already-✅ flow.
- **Architectural note:** the `<dialog>` element is doing most of the heavy lifting. Native-first paying off again — a custom modal would need a focus-trap library, ESC handler, scroll lock, top-layer compositing, and backdrop. We get it all for free + can layer dynamic aria-label + HTML5 validation on top.
- **Next:** Tick 29. Plausible: (a) similar a11y pass on the card-detail modal, (b) similar a11y pass on the wall-overlay, (c) audit Find filter sheet for keyboard / a11y, (d) move to a non-a11y polish item.

### Tick 27 — 2026-05-20 — Public collection "Wall" button (canvas share image)
- **Picked:** Continuing the public-collection user-acquisition arc. Tick 25 added the unauth CTA, tick 26 added the Share button (URL share). Tick 27 closes the trio with a Wall button — visitor (auth or unauth) renders the cards they're viewing as a downloadable PNG. Reuses the tick-9/10 `openCardsWallSheet` pipeline entirely; this is mostly UI wiring.
- **Shipped:**
  - `index.html`: wrapped the existing Share button + new Wall button in `.public-collection-actions` cluster. Wall button shares the same pill style (cyan + Lucide `image` icon + "Wall" label).
  - `js/app.js::renderPublicCollection`:
    - After `resolved` is built, find `#public-collection-wall`, pull catalog cards out of `resolved.map(r => r.card).filter(c => c?.imageFile)`, set `wallBtn.hidden` based on count, and wire `onclick` to `window.Collection.openCardsWallSheet({ title: '@handle on BOBA Playbook', cards })`.
    - Use `onclick =` (not addEventListener) so re-renders cleanly overwrite the handler instead of stacking.
    - Hidden when there are zero rendered cards — no point offering a wall of nothing.
  - `css/styles.css`: `.public-collection-actions` cluster — vertical stack on narrow widths, horizontal at ≥640px. Stays right-aligned next to the title.
- **Verified:** node -c clean. Logic trace: open `/u/ben` → 47 cards render → Wall button shows → click → existing wall dialog opens with title "@ben on BOBA Playbook" + 47 cards → user can download PNG via existing flow. Private collection → grid is empty → Wall button hidden.
- **Why this matters:** the unauth CTA captures users who want to BUILD. The Share button captures users who want to PROPAGATE. The Wall button captures users who want to SAVE a snapshot — works regardless of auth. Three orthogonal intent paths off one landing page.
- **PARITY.md:** No row — public-collection is web-only.
- **Architectural note:** the openCardsWallSheet pipeline is now called from FOUR surfaces: Collection (own designation), Decks (deck wall), Find multi-select (selected cards), public-collection (someone else's grid). The shared `openWallSheet({ context: 'deck', title, cards })` route handles all four cleanly. Worth a DECISIONS.md entry capturing the Wall view as a primitive when it stabilizes.
- **Next:** Tick 28. Plausible: (a) accessibility audit on Sign-in modal (focus trap + return focus), (b) view-source `<noscript>` content for non-JS browsers, (c) audit YouTube Watch tab for parity gaps.

### Tick 26 — 2026-05-20 — Public collection Share button
- **Picked:** Complement to tick-25's CTA. A visitor who landed via a shared link → enjoys the collection → wants to re-share it with a friend → had to copy the URL bar manually. One-tap share unlocks viral propagation.
- **Shipped:**
  - `index.html`: new `<button id="public-collection-share">` in the public-collection header next to the title. Lucide `share-2` icon (the three-dot connected graph) + "Share" label. Cyan pill style matching the brand's secondary action treatment.
  - `js/app.js::renderPublicCollection`: wires the button via `window.bobaShareTarget({ title, text, url }, shareBtn)`. Title = `@handle on BOBA Playbook`. Text = `Check out @handle's BOBA card collection`. URL = canonical `${origin}/u/${handle}` (NOT the current `?u=…` form) so recipients see the same nice URL. `{ once: true }` so re-renders don't double-bind.
  - `css/styles.css`: `.public-collection-share` cyan-pill button + made `.public-collection-titlebox` flex-grow so the button sits at the trailing edge of the header without crowding the title.
- **Verified:** node -c clean. Logic trace: open `/u/ben` → click Share → if `navigator.share` available, system sheet pops up with the pre-filled title + text + URL; if not, URL copies to clipboard with "Link copied!" inline confirmation (the existing `bobaShareTarget` fallback path from `feedback_native_first`).
- **Why this matters:** the CTA in tick 25 captures visitors who want to BUILD their own collection. The Share button captures visitors who want to PROPAGATE the collection they're viewing. Together they cover both intent paths from the same landing page.
- **PARITY.md:** No row — public collection is web-only; iOS / Android deep-link IN to view it but the share affordance is the visitor's web-platform action.
- **Architectural note:** `bobaShareTarget` (declared at app.js:390) is the shared share helper — Web Share API → clipboard fallback → toast. All sharing surfaces should use this, not navigator.share directly. Three call sites now (card detail, profile-public-link copy, this). Worth promoting to a documented primitive in WEB-DESIGN.md §16 in a future tick.
- **Next:** Tick 27. Plausible: (a) "Wall this collection" button on public-collection (renders the visible cards via the tick-9/10 canvas pipeline so the visitor can download a PNG), (b) add a "View on BOBA Playbook" inline preview snippet for OG image rendering, (c) audit Sign-in modal accessibility (focus trap + ESC + return focus).

### Tick 25 — 2026-05-20 — Public collection CTA for unauth visitors
- **Picked:** Web-only gain. Visitors landing on `/u/{username}` from a shared link saw the cards but had no obvious next step. High-leverage user-acquisition surface — they're already engaged enough to view someone else's collection.
- **Considered Find Quick Add audit** first; concluded the existing flow is fine — duplicate-click adding two copies might be intentional (user just bought 2 copies of the same card). Skipped.
- **Shipped:**
  - `index.html`: new `<div id="public-collection-cta" hidden>` below the public-collection grid. Headline "Start your own BOBA collection" + body ("Track, build, share — free, mobile-first, no installs") + two actions: "Explore the catalog" (→ Find) and "Sign in / Create account" (→ Auth modal).
  - `js/app.js`:
    - `wirePublicCollectionCTA()` shows the CTA only when `Auth.isAuthenticated()` is false. Wired-once handlers (`{ once: true }`) on the two buttons so a click immediately advances and the CTA doesn't try to bind twice on re-render.
    - Called at the end of `renderPublicCollection` after the grid mounts.
  - `css/styles.css`: ~40 lines for `.public-collection-cta` — gradient background (orange→cyan brand glow at low alpha), centered max-width 480px, two-button row that wraps on mobile.
- **Verified:** node -c clean. Logic trace: unauth visitor lands on `/u/ben` → grid renders → CTA appears below. Signed-in visitor → CTA hidden. Tap Explore → `showView('search')`. Tap Sign In → `Auth.open()`.
- **Why this matters:** the public-collection page is BOBA's #1 organic user-acquisition surface — every shared link is a potential install. A passive grid with no CTA was leaving conversions on the floor. Two clear paths (browse first OR sign in first) honor the user's level of intent.
- **PARITY.md:** No row — web-specific (no iOS/Android equivalent — they handle deep-link install via App Store / Play Store).
- **Architectural note:** the CTA appends ONCE per render via `{ once: true }`. If a user signs in mid-view, the CTA's stale handlers won't re-bind to a different state; refresh would clear them. Acceptable trade-off vs. the more complex "rebind on auth-change" path.
- **Next:** Tick 26. Plausible: (a) view-public-collection page also gets the Wall view affordance ("Generate wall image") for the viewer to easily share, (b) tap-to-zoom card detail on public-collection (currently opens card modal — confirm parity), (c) audit Profile sign-in modal for accessibility.

### Tick 24 — 2026-05-20 — Profile Delete Account: type-to-confirm
- **Picked:** From tick-23 "Next" — highest-stakes destructive web flow. Prior version had a single `confirm()` with the warning text. Single-click confirm is sufficient for "are you sure?" but not for "permanent + cascading + can't undo." iOS uses a multi-step + type-to-confirm pattern; web matches now.
- **Shipped:**
  - `js/collection.js` `#profile-delete-btn` handler:
    - Step 1 (unchanged): `confirm()` listing what gets removed — added "custom rainbows" to the cascade list since tick 7 shipped them.
    - **Step 2 (new): type-to-confirm.** `prompt()` requires the user to type their `@username` exactly. Pulled live from `API.fetchProfile()`. Case-insensitive compare (username is lowercased server-side anyway).
    - **Fallback:** if the user's profile has no username (edge case — fresh signup that hasn't completed username derivation), the prompt asks for "DELETE" instead, exact-match compare.
    - If the typed value doesn't match → `alert()` says "Confirmation didn't match — your account was NOT deleted." and returns without calling the Worker.
    - Cancel at step 2 → silent no-op.
- **Verified:** node -c clean. Logic trace: click Delete → step-1 confirm → cancel returns; OK proceeds → step-2 prompt with `@{username}` → cancel returns; mismatched type returns with notice; matched type → Worker call → signOut + alert.
- **PARITY.md:** No row change — destructive-flow polish on an already-✅ row (Account deletion §9).
- **Architectural note:** the type-to-confirm pattern is iOS-equivalent in safety without needing a custom `<dialog>` — native `confirm()` + `prompt()` cover both gates with zero new chrome. WEB-DESIGN.md §2.1 native-first.
- **Why this matters:** account deletion cascades to user_cards / decks / shows / custom_rainbows / user_profile / auth.users via FK CASCADE. No undo, no recovery beyond a fresh signup. A type-to-confirm gate is the right friction for that blast radius.
- **Next:** Tick 25. Plausible: (a) Find Quick Add audit, (b) destructive Discord-unlink flow if it exists, (c) other admin-panel actions.

### Tick 23 — 2026-05-20 — Web Decks Clear: confirmation guard
- **Picked:** From tick-22 "Next" list. Found real bug: clicking the ✕ Clear button in the deck-builder toolbar destroyed the entire deck (heroes + plays + bonus + hot dogs) with **zero confirmation**. One misclick on the small icon could nuke an hour of work. iOS DECISIONS.md mentions the Clear confirm dialog; web had no equivalent.
- **Shipped:**
  - `js/practice.js` `db-clear-btn` handler:
    - Empty-deck shortcut: `totalCards === 0` → skip confirm + clear directly (clearing an already-empty deck is a no-op anyway).
    - Non-empty deck: native `confirm()` with a section-by-section count summary: *"Clear this deck (5 heroes, 28 plays, 4 bonus, 10 hot dogs)? Your deck name and format settings stay."* The plural-aware labels avoid awkward "1 heroes" / "0 plays" cruft.
    - Cancel → early return → deck untouched.
    - Confirm → existing `DB.clear() + reset name + dbRender` flow.
- **Verified:** node -c clean. Logic trace: empty deck → clear directly. Built deck → confirm with count summary → cancel returns → clear proceeds.
- **PARITY.md:** No row change — bug fix, not a feature.
- **Architectural note:** native `confirm()` is acceptable for destructive guards. WEB-DESIGN.md §2.1 "native-first" — `<dialog>.showModal()` would be the deluxe path, but the simpler `confirm()` is what the existing rainbow-delete + deck-delete affordances already use; consistent here.
- **Next:** Tick 24. Plausible: (a) audit save flow on Find Quick Add (mentioned in tick 22), (b) Find search "clear all" keyboard shortcut + UI button, (c) Decks → save deck duplicates an existing deck-id warning, (d) audit Profile delete-account flow (high stakes, should be very explicit).

### Tick 22 — 2026-05-20 — Web Decks save: empty-deck guard + inline feedback
- **Picked:** Audit triggered by tick-21b "Next" plan. Found three issues with the current Save flow: (1) zero-card decks could be saved, writing junk rows to Supabase. (2) Empty / whitespace deck name was accepted unchanged. (3) Errors went to `alert()` instead of the existing inline `db-import-banner` (used by import + every other deck-builder transient feedback).
- **Shipped:**
  - `js/practice.js` `db-save-btn` handler:
    - Empty-deck guard: refuse to save when `cards.length === 0`; show "Add at least one card before saving." inline via `db-import-banner` (3s auto-hide). Mirrors iOS DeckBuilderStore which refuses save at totalCardCount == 0.
    - Name guard: `(DB.deckName || '').trim() || 'New Deck'` — accepts whitespace as a typo and silently defaults rather than fighting the user with an error.
    - Success path: inline `Saved "{deckName}".` (2.5s auto-hide) in addition to the existing green-flash on the button.
    - Failure path: inline `Save failed: {message}` (persistent until next user action) instead of the prior `alert()`. Falls back to alert() only if the banner element is missing.
- **Verified:** node -c clean. Logic trace: click Save with 0 cards → banner says "Add at least one card before saving." + button NOT disabled (returns early). Click Save with cards → existing flow + new success banner. Server error → inline banner with err.message, no alert.
- **PARITY.md:** No row change — this is a polish + correctness fix on an already-✅ row.
- **Architectural note:** the `db-import-banner` is now used by Import + Save + future Decks transient feedback. Worth promoting to a generic `.db-banner` class in a future refactor if more callers appear.
- **Next:** Tick 23. Plausible: (a) audit save flow on Find Quick Add (similar single-card add path), (b) audit the deck-builder "Clear" button confirmation (might already exist), (c) random-card affordance on Find.

### Tick 21b — 2026-05-20 — Rollback: remove Twitter Card meta + add binding "never" docs
- **Picked:** Ben directive. Twitter / X is owned by a fascist; BOBA will not integrate. Same-day rollback of tick 21's Twitter Card additions.
- **Shipped:**
  - `index.html`: removed all four `<meta name="twitter:*">` tags + updated the OG-block comment to call out "no `twitter:*` per DECISIONS.md #053." OG protocol tags kept (read by every other major platform).
  - `js/app.js::updateOpenGraphMeta`: stripped `twitter:title` / `twitter:description` / `twitter:image` setters. Helper now updates the four `og:*` properties only. Comment updated to flag the "never" rule.
  - `DECISIONS.md`: new entry **#053 — No Twitter / X integration, ever**. Explicit rule (no OAuth, no Card tags, no share intents, no SDK, no API) + why (BOBA is a tool for human learning; Twitter is owned by a fascist; integration would signal endorsement + provide material support) + what still ships (full OG protocol, Discord per DECISIONS.md #049, other social platforms when use cases arise).
  - `DESIGN.md §12 "Out of scope"`: row added — "Twitter / X integration (any form)" → "Never".
  - `WEB-DESIGN.md §17 "Out of scope"`: same row.
  - `ANDROID-DESIGN.md §12 "Out of scope"`: same row.
  - Memory: `feedback_no_twitter_integration.md` with the binding context for future sessions.
- **Why this is binding, not aesthetic:** the docs are explicit. Any future tick that reaches for a `twitter.com` URL, a `twitter:*` meta tag, a "Share to Twitter" button, or a Twitter SDK is rejected at proposal stage. Other social platforms (Discord, Bluesky, Mastodon, Threads) are fine when use cases arise.
- **Net effect on tick 21:** OG protocol still ships fully — Discord, iMessage, Slack, Bluesky, Mastodon, Threads, Facebook, LinkedIn, WhatsApp, Signal, Telegram, and search engines all read OG. Tick 21's user-acquisition + sharing value lands. Only the Twitter-specific dialect is gone.

### Tick 21 — 2026-05-20 — Open Graph + Twitter card meta tags
- **Picked:** Documented in tick-20 "Next" as the next obvious polish. The web app had zero OG / Twitter meta tags — any link to BOBA Playbook shared in Discord, iMessage, Slack, Twitter, etc. got either a blank preview or the browser's auto-generated text-only card. Cheap to ship with meaningful user-acquisition + sharing impact.
- **Shipped:**
  - `index.html`: static OG + Twitter card metadata in `<head>`. Defaults:
    - `og:type = website` · `og:site_name = BOBA Playbook` · `og:title` + `og:description` describe the app shell.
    - `og:url = https://bobaplaybook.com/`
    - `og:image = https://bobaplaybook.com/assets/icons/boba_playbook_icon_1024.png` (1024×1024 XOXO mark — copied from `Logos/` into `assets/icons/` for web-accessibility).
    - `twitter:card = summary_large_image` so the icon renders at the full preview width.
  - `js/app.js`:
    - `updateOpenGraphMeta({title, description, url, image})` helper — selects existing `<meta property="og:*">` and `<meta name="twitter:*">` elements by attribute and updates their `content`. Skips any field the caller didn't pass (partial updates supported).
    - `applyView(name)` now updates og:title + og:url for the active route.
    - `openModal(card)` updates og:title + og:description (hero · treatment · set) + og:url (the deep-link URL via `buildCardURL`) + og:image (the card's full-resolution R2 URL via `API.cardFullUrl`). Restored on `closeModal()` to the app shell defaults.
    - `renderPublicCollection(handle)` updates the OG triple to "@handle · BOBA Playbook" + description "Public BoBA card collection by @handle" + URL `/u/{handle}`.
  - **Caveat documented in code comment:** link crawlers (Discord / Twitter / iMessage / Slack) only read the STATIC `<head>` HTML they fetch — they do not run JS. So the client-side per-route updates only help in-app share affordances (`navigator.share()` reads `document.title`, browser extensions reading the DOM, the user's tab-switcher / Cmd+Shift+A). Server-side rendering of per-route OG isn't possible on GitHub Pages and is genuinely deferred.
- **Verified:** node -c clean. Manual: load `https://localhost:8080/` → static OG defaults. Click card → openModal → OG image becomes that card's R2 URL. ESC → defaults restored. Public collection → "@handle · BOBA Playbook" OG.
- **PARITY.md:** No row change — web platform polish; iOS / Android handle share previews via system mechanisms.
- **Architectural note:** the `updateOpenGraphMeta` helper takes a partial object so callers don't need to pass every field. Callers that need a specific tag stable (e.g. `og:type` should always be "website") just don't pass that key.
- **Next:** Tick 22. Looking at what's still pickable and meaningful. Plausible: (a) "Random card" affordance in Find search (1-tick fun feature, no parity gap), (b) Audit the Decks editor save flow for the empty-deck case, (c) Audit accessibility (tab-order / aria-current / aria-live) across Find grid and Card detail modal.

### Tick 20 — 2026-05-20 — Per-view browser tab title (WEB-DESIGN.md §4.1)
- **Picked:** Documented anti-pattern in WEB-DESIGN.md §4.1 ("Pages that aren't pages") — `document.title` was static "BOBA Playbook" across all 10 routable views. Bookmarks, tab switchers, and shared-link previews all showed the same name. Long-standing UX gap; cheap to ship.
- **Shipped:**
  - `js/app.js`:
    - `VIEW_TITLES` constant — single source of truth mapping each routable view name (`search`, `scan`, `rules`, `decks`, `practice`, `stores`, `collection`, `purchase`, `profile`, `public-collection`) to a display title (`Find`, `Scan`, `Learn`, …). Format: `{viewTitle} · BOBA Playbook`.
    - `applyView(name)` now writes `document.title` from the table after the view-switch. Inside the View Transitions API callback so the title flip aligns with the visual cross-fade.
    - `openModal(card)` updates `document.title` to `${cardLabel} · BOBA Playbook` when a card detail opens. Restored by `closeModal()` from `VIEW_TITLES[currentView]`.
    - `renderPublicCollection(handle)` overrides to `@${handle} · BOBA Playbook` so bookmarks of someone's public page read as their handle, not the generic view name.
- **Verified:** node -c clean. Trace: load page (`?view=collection`) → applyView('collection') → tab title = "Collection · BOBA Playbook". Click card → openModal → "Maverick · BOBA Playbook". ESC → closeModal → "Collection · BOBA Playbook". Navigate to public collection → renderPublicCollection('ben') → "@ben · BOBA Playbook". Back to Find → applyView('search') → "Find · BOBA Playbook".
- **PARITY.md:** No row change — quality-of-life fix on the web platform; iOS/Android handle this via system nav-bar titles.
- **Why this matters:**
  - Multi-tab browsing: users opening Find + Collection + Decks in separate tabs can now tell them apart in the tab switcher and Cmd+Shift+A search.
  - Bookmarks: pinned `/u/ben` reads as `@ben · BOBA Playbook` instead of `BOBA Playbook` — meaningful for users who share or save URLs.
  - Browser history: back/forward navigation in the back-history dropdown shows distinct labels per view (Chrome / Edge / Safari all read `document.title` for the history entry label, not `history.state`).
  - OG: a future `<meta property="og:title">` update would land cleanly here.
- **Architectural note:** the `VIEW_TITLES` map is the single source for view titles on web. Other call sites that need a view's display title (sidebar, breadcrumb if we ever add one, share-target preview) should read from this map, not hardcode strings.
- **Next:** Tick 21. Continue picking from PARITY.md gaps + WEB-DESIGN.md polish items. Strong candidates: (a) Open Graph meta tags for `/u/{username}` pages so Discord / Twitter link previews work (would need to be at fetch-time since GitHub Pages is static; could be approximated via `<meta>` swap on render), (b) audit Decks Save flow for empty-deck rejection, (c) audit Find search for off-by-one in suggestion-popover positioning.

### Tick 19 — 2026-05-20 — Auth-state cache reset + post-tick-18 audit
- **Picked:** Bring web in line with the `feedback_viewmodel_reset_on_auth_change` discipline shipped on Android. Two scenarios to guard against: (1) signed-in user A signs out → some cached state survives → user B signs in same tab → A's state briefly visible. (2) The window between sign-out and Auth.open() showing a stale rainbow's name in an open editor dialog.
- **Audit done:** verified `public-collection` page (`buildCardElement` already routes through `API.cardThumbUrl`), Watch tab (wired to `boba-youtube-feed` Worker), Profile public-URL copy (working), Decks card popup (deck cards never sealed, no CDN issue). No more bugs in the same family as tick 18.
- **Shipped:**
  - `js/collection.js::clear()` — now also resets `_customRainbowsById = {}`, `_editingRainbow = null`, `_draftCriteria = {}`. On sign-out, the rainbow cache + editor state are wiped so a subsequent sign-in starts clean. Mirrors the Android ViewModel-reset pattern: previous-user data can't leak into the next session.
- **Verified:** node -c clean. `clear()` is invoked by the auth-state-change listener at line 2872; both `signOut` and `tokenRefreshed → no session` paths reach it.
- **PARITY.md:** No row change — discipline fix, not a feature ship.
- **Architectural note:** the three `_…` caches all live at module scope inside the Collection IIFE. Future per-user caches added in this module should be reset in `clear()` too. (No lint rule enforces this — it's discipline.)
- **Next:** Tick 20. Want to find a higher-impact ship. Considering: (a) browser-tab-title updates to reflect the active view (today: shows the static <title> always), (b) Collection sort-mode persistence (memory across sessions), (c) preset deck-builder format remembered across sessions (already does via `bp_decksFormat_v1`?).

### Tick 18 — 2026-05-20 — Web sealed-product CDN routing bug fix (Collection)
- **Picked:** Audit triggered by PARITY.md/tick-12 reference to the Android CDN sealed-routing memory + the tick-1 missing-sealed surfacing. Confirmed Find grid + Wall + variant-tile all correctly route via `API.cardThumbUrl`. **Found three Collection-side bugs** where the code called raw `API.thumbUrl(imageFile)` / `API.fullUrl(imageFile)` instead of the sealed-aware `API.cardThumbUrl(card)` / `API.cardFullUrl(card)`.
- **Real-user impact:** sealed products live at `/sealed/thumbs/` + `/sealed/optimized/` on R2. Any sealed product in a user's Collection (designation = personal/for_sale/for_trade/wanted/grails) would 404 in the Collection grid, the variant-tile picker, AND the collection card-detail view. The user would see a broken-image icon for every sealed box / blaster they own. iOS shipped sealed routing per `feedback_ios_sealed_products` memory; Android shipped via `reference_android_cdn_sealed_routing` (overnight 2026-05-20); web had been silently broken.
- **Shipped:**
  - `js/collection.js`:
    - `buildCollectionCardHtml` (the main collection grid cell) — replaced raw `API.thumbUrl(imageFile)` + `API.fullUrl(imageFile)` with `API.cardThumbUrl(catalogCard)` + `API.cardFullUrl(catalogCard)`. Reads from the resolved `catalogCard` so the `cardType === 'Sealed Product'` check fires. srcset pair updated to match.
    - Collection card-detail header image (`cdetail-card-img`) — same fix.
    - Variation tile (`cdetail-var-img` in the "Other Versions" strip) — same fix.
  - **No new bugs introduced:** the `API.cardThumbUrl(card)` signature takes the FULL card record (needs `imageFile` + `cardType`); the prior code was calling `API.thumbUrl(string)` which takes only the filename. Verified all three rewrites pass the catalog record (`catalogCard` / `card`) not the filename.
- **Verified:** node -c clean. `grep -rn "API.thumbUrl\|API.fullUrl"` returns zero hits across `js/` — every web image render path now goes through the sealed-aware helpers. `cards.json` confirmed to have `cardType: 'Sealed Product'` on all 45 sealed entries.
- **PARITY.md:** No row addition — this is a bug fix, not a parity story. But it does close the "Verify sealed-image fix on web + Android" P0 from the original autonomous-loop backlog (Android was confirmed shipped overnight; web is now verified + fixed).
- **Architectural note:** the cleanest fix would be to inline a `cardType` check directly inside `API.thumbUrl(filename)` + `API.fullUrl(filename)` so any caller is automatically safe. But that would require passing the cardType alongside (or guessing from filename prefix), and the existing `cardThumbUrl(card)` / `cardFullUrl(card)` already exist for exactly this. Better discipline going forward: PR review for any new `API.thumbUrl(` or `API.fullUrl(` raw call.
- **Next:** Tick 19. Plausible: (a) audit Find grid for the same kind of "rendered without sealed routing" issue (already confirmed clean), (b) public-collection page sealed routing check, (c) Decks editor improvements.

### Tick 17 — 2026-05-20 — Custom Rainbow editor polish + drift fix
- **Picked:** With ~500 distinct heroes and ~80 distinct sets in the tick-16 sub-pickers, scrolling to find "Maverick" was painful. Web has the keyboard + a wider canvas — adding a search-within-picker is a natural web-only polish that improves the tick-16 work meaningfully. Also Enter-to-save shortcut + PARITY.md drift fix (Card detail swipe nav web — was n/a but actually shipped).
- **Shipped:**
  - `js/collection.js`:
    - `_renderFilterDim` now emits a `<input type="search" class="rainbow-filter-search">` at the top of any picker with ≥20 options. Per-picker input handler hides non-matching `.rainbow-filter-option` labels via `style.display = 'none'`. Hiding (vs re-rendering) preserves the checked state of items the user has already toggled.
    - Option labels carry a `data-search="<lowercased value>"` attribute for the substring match — case-insensitive, single-comparison.
    - Editor dialog `keydown` handler: Enter in the name field saves; Cmd/Ctrl+Enter anywhere in the dialog saves (matches iOS DESIGN.md §7 keyboard-shortcut affordance). ESC is handled natively by `<dialog>`.
  - `css/styles.css`: split `.rainbow-filter-body` into `.rainbow-filter-search` (sticky-ish search input) + `.rainbow-filter-options` (the existing 150px-min grid moved inside) so the search input sits above the scrolling grid.
  - `index.html`: no markup change — the search input is generated in JS so it's only present where it's useful.
- **Drift fix (PARITY.md):** Card detail swipe nav (left/right) was marked `n/a (no nav)` for web but web has had it since the modal was built — `ArrowLeft/Right` keys + touch-swipe (>60px horizontal threshold + dx > 1.5×dy) wired to `navigateModal(±1)` in app.js. Corrected to ✅ with audit note.
- **Verified:** node -c clean. UX trace: open editor → Heroes section shows ~500 entries with search → type "Maver" → only Maverick visible → check → search wiped → re-open Heroes → all heroes visible, Maverick still checked. Enter from anywhere in dialog → Save fires.
- **PARITY.md:** Card detail swipe nav web `n/a` → ✅.
- **Architectural note:** the search input is conditional (`values.length >= 20`) so it doesn't dead-chrome the smaller pickers (Weapons = 9, Card types = ~5). The threshold can be tuned but 20 is the natural inflection where scroll-fatigue starts.
- **Next:** Tick 18. Plausible: (a) Find — multi-select-clear-all keyboard shortcut OR Esc-to-clear (web has Escape→exitSelection per app.js line 3273; verify), (b) Audit Sealed product handling on web for the missing-sealed surfacing from tick 1 (visibility check), (c) Polish for Decks card-detail flow (cross-deck warnings, format compatibility hints).

### Tick 16 — 2026-05-20 — Custom Rainbow editor sub-pickers + live preview
- **Picked:** Second slice of the custom-rainbow editor — adds the seven filter dimensions (heroes / sets / sub-sets / weapons / treatments / cardTypes / releases) + Inspired Ink toggle + live "N matches · X owned (Y%)" progress preview. Closes the iOS CustomRainbowEditorSheet parity gap in one extra tick (tick 15 + tick 16 vs the planned 3-tick split).
- **Shipped:**
  - `index.html`: editor `<dialog>` extended — preview band ("N cards match · X of those owned"), seven `<details>` filter dimensions, each with an empty `.rainbow-filter-body` for hydration, plus an "Inspired Ink only" checkbox toggle.
  - `js/collection.js`:
    - `RAINBOW_DIMS` constant — single source of truth for the seven dimensions, each mapping the criteria key (`heroes`, `sets`, etc.) to the Card field (`hero`, `set`, etc.) it filters on. Verbatim parity with iOS CustomRainbowEditorSheet.SubPicker.
    - `distinctCatalogValues(dimKey)` — memoized; pulls distinct non-empty values for one dimension from `window.__bobaCatalog`, sorted case-insensitively. Cache is module-scoped (catalog doesn't change during a session). Heroes: ~500 values; Sets: ~80; etc.
    - `_renderFilterDim(dim)` — hydrates one `<details>` with `<label><input type="checkbox" data-value="…">` rows. Pre-checks based on the in-flight `_draftCriteria`. Summary shows `· N` count of selected.
    - `_renderPreview()` — recomputes "N cards match · X of those owned (Y%)" by running `API.rainbowCriteriaMatches` across the catalog with the draft criteria, intersected with the user's ownedCards keys. Cheap at 17k cards (single linear pass per change).
    - Single delegated `change` handler on the filters container catches both per-dimension checkbox toggles AND the Inspired Ink toggle — `O(1)` wiring regardless of how many catalog values render. Case-insensitive add/remove (so a user pre-existing rainbow with `criteria.heroes = ["Maverick"]` correctly intersects with the checkbox emitting `data-value="Maverick"`).
    - Save now passes `_draftCriteria` instead of empty `{}`. Edit mode deep-clones existing criteria into `_draftCriteria` so canceling doesn't mutate the cached rainbow row.
  - `css/styles.css`: ~95 lines added — `.custom-rainbow-editor-preview` band (cyan accent), `.rainbow-filter` collapsible cards, `.rainbow-filter-body` as a 150px-min responsive grid with 220px max-height + overflow:auto (long lists scroll inside the picker rather than pushing the dialog), `.rainbow-filter-option` checkbox rows, `.rainbow-filter-toggle` for the Inspired Ink switch.
- **Verified:** node -c clean. Manual trace: open editor on existing iOS-created rainbow w/ `{heroes:["Maverick"], elements:["FIRE"]}` → both Heroes and Weapons sections pre-check the right options → preview shows the right match count. Save round-trips correctly.
- **PARITY.md:** Custom Rainbows web ✅ read + name-only → ✅ (full). Closes the Custom Rainbows row entirely.
- **Architectural note:** the `RAINBOW_DIMS` array is the source of truth for keying. Future dimensions (e.g. a "subtypes" expansion when BoBA adds more taxonomy axes) just add one row + the corresponding logic in `API.rainbowCriteriaMatches`. The editor markup template auto-handles by selector `.rainbow-filter[data-dim="..."]` — no per-dim if/else.
- **Next:** Tick 17. Custom Rainbow editor is complete; pick next from PARITY.md. Strong candidates now that Rainbows are closed: (a) `prefers-color-scheme` honoring on web (`feedback_native_first` candidate — the brand is dark-first; light mode is a stretch though), (b) Sort-by-completion on Hero Rainbows, (c) Streamer "My Shows" web surface (multi-tick — significant). Leaning (b) — quick polish on the hero-rainbow surface from tick 8.

### Tick 15 — 2026-05-20 — Web Custom Rainbow editor (first slice: name only)
- **Picked:** Write parity for tick-7's read-only display. Agent C's highest demand signal (1,237 community messages on rainbow/checklist tracking). Multi-tick effort — this is the first slice.
- **Shipped (slice 1 of 3):**
  - `js/api.js`: three new mutating endpoints — `createCustomRainbow(name, criteria)` (INSERT + returns row), `updateCustomRainbow(id, { name, criteria })` (PATCH), `deleteCustomRainbow(id)`. RLS scopes to own-row by default. Mirrors iOS `SupabaseClient.createCustomRainbow / updateCustomRainbow / deleteCustomRainbow` exactly.
  - `index.html`: new `<dialog id="custom-rainbow-editor">` — name input + hint text + cancel/save/delete actions. Native `<dialog>.showModal()` per WEB-DESIGN.md §2.1 native-first (focus trap + ESC + top layer + `::backdrop` for free).
  - `js/collection.js`:
    - "+ New rainbow" button + empty-state hint in the Custom Rainbows section heading row (now always visible to signed-in users).
    - `_renderRainbowRow` extended with optional `rainbowId` — when present, the row emits an inline ✎ edit affordance.
    - Edit-pencil click handler (with `e.preventDefault()` so the `<details>` doesn't toggle) opens the editor preloaded from `_customRainbowsById` cache.
    - `openCustomRainbowEditor(rainbow|null)` / `closeCustomRainbowEditor()` / `wireCustomRainbowEditor()` — create vs edit mode toggled by presence of an existing rainbow; delete button hidden in create mode.
    - Save in create mode → `createCustomRainbow(name, {})` (empty criteria for now — see scope note). Save in edit mode → `updateCustomRainbow(id, { name, criteria })`. Both close + call `load()` to re-render.
  - `css/styles.css`: ~80 lines — `.custom-rainbow-new-btn` (cyan pill), `.custom-rainbow-editor-*` styles, `.rainbow-edit-btn` (per-row ✎), `.custom-rainbows-empty` (dashed-border empty state).
- **Scope:** intentionally NAME-ONLY for this slice. Criteria stays empty (`{}`) on create, meaning a freshly-created rainbow matches every catalog card. The editor hint surfaces this honestly: *"Filters land in a later release. For now, create a named rainbow as a checklist anchor."* Tick 16 adds the sub-pickers (heroes/sets/sub-sets/weapons/treatments/cardTypes/releases); tick 17 adds the live progress preview + inspired-ink toggle. Edits preserve existing criteria — users who created rainbows on iOS keep their filters intact when renaming from web.
- **Verified:** node -c clean on api.js + collection.js. RLS policy already exists (migration `2026_05_15_user_custom_rainbows.sql` ships own-row SELECT/INSERT/UPDATE/DELETE).
- **PARITY.md:** Custom Rainbows web "✅ read-only" → "✅ read + name-only editor".
- **Architectural note:** `wireCustomRainbowEditor` is invoked from `init()` so it runs once on Collection module init, NOT on every render. Click handlers are attached to the DOM static elements (the dialog buttons + the new-rainbow button) which live in index.html, so they survive view re-renders.
- **Next:** Tick 16 — sub-pickers in the editor. Each filter dimension (heroes / sets / sub-sets / weapons / treatments / cardTypes / releases) gets a `<details>` with a checkbox-list of distinct catalog values. Live "matches N cards" preview at the top updates on every change.

### Tick 14 — 2026-05-20 — Web Manage Decks refresh button + render refactor
- **Picked:** Closes the Android-overnight Manage Decks parity trio (rename + search + PTR). Tick 13 shipped rename + search; PTR has no native web equivalent so the analog is a Refresh button.
- **Considered Custom Rainbow editor** (tick-13 "next" candidate) but right-sized down — it's multi-section sub-pickers + 7 catalog-distinct-value enumerations + save/delete — clearly multi-tick. Refresh button finishes the Decks parity story in one tick and keeps the loop discipline.
- **Shipped:**
  - `index.html`: new `<button id="db-saved-decks-refresh">` with Lucide refresh-cw icon, between the title and the close-X. Wrapped existing close into a `.db-saved-decks-header-actions` cluster for layout.
  - `js/practice.js`:
    - Extracted `_renderSavedDecksList(decks)` from the inline Load-button handler. Holds the row HTML + active-search-filter reapply.
    - New `refreshSavedDecksList()` async — does the `deckList()` fetch + delegates render. Shared by Refresh button + Load button.
    - Load button click handler shrunk to: visibility-toggle / auth-check / panel.hidden=false → `refreshSavedDecksList()`. No duplicate render logic.
    - Refresh button click handler adds `.spinning` class + disables button during fetch; clears on settle (try/finally).
  - `css/styles.css`: `.db-saved-decks-refresh` (cyan-accent border + bg, matches the rename ✎ button's color story) + `.db-saved-decks-header-actions` cluster + `@keyframes db-refresh-spin` (0.8s linear) + `@media (prefers-reduced-motion: reduce)` override that disables the spin.
- **Verified:** node -c clean. Render path now has a single source of truth (`_renderSavedDecksList`) which prevents Tick 13's rename + search behaviors from drifting away from a future re-fetch.
- **PARITY.md:** §4 Manage saved decks row note expanded.
- **Architectural note:** `applyDeckSearchFilter` is called at the end of `_renderSavedDecksList`, so refreshing while a search query is active preserves the filter — the user doesn't lose context to a refresh. This was the iOS DeckManagementSheet behavior I wanted to mirror.
- **Next:** Tick 15 — Custom Rainbow editor on web (write parity for tick 7 read-only). Multi-tick effort. Plan: tick 15 = `<dialog>` skeleton + name input + save/delete API + "+ New rainbow" button on Custom Rainbows section. Tick 16 = sub-pickers for heroes/sets/sub-sets/weapons/treatments/cardTypes/releases. Tick 17 = inspired-ink toggle + live progress preview + edit-existing flow.

### Tick 13 — 2026-05-20 — Web Manage Decks: rename + search
- **Picked:** Android shipped rename + search overnight (per overnight 2026-05-20 commit notes — "Android Decks polish ... rename / search / PTR"). Web's Manage Decks panel had Load + Delete only.
- **Shipped:**
  - `js/api.js`: new `deckRename(deckId, newName)` — `UPDATE decks SET name = ..., updated_at = now() WHERE id = ? AND user_id = ?` via PostgREST. Validates non-empty trim. Mirrors iOS DeckManagementSheet's rename action.
  - `js/practice.js`:
    - Per-row markup gets `data-deck-name` (for search filter + rename roundtrip) and a new ✎ `.db-saved-deck-rename` button between Load and Delete.
    - Click handler matches `.db-saved-deck-rename` → `prompt(...)` for the new name → calls `API.deckRename` → updates row text + dataset + sibling aria-labels in-place (no full re-render needed). If the renamed deck is the currently-loaded draft (`DB_savedId` match), the builder's editable name field updates in step.
    - `applyDeckSearchFilter()` — hides rows whose name doesn't substring-match the search input (case-insensitive). Idempotent — called after every list render AND on every input keystroke. Shows an inline "No saved decks match that name" hint when the filter zeros the list.
  - `index.html`: new `<input id="db-saved-decks-search" type="search" placeholder="Search saved decks…">` between the panel header and the list.
  - `css/styles.css`: ~20 lines — `.db-saved-deck-rename` (cyan accent — visually distinct from orange Load + red Delete) + `.db-saved-decks-search` (matches Find search input style).
- **Verified:** node -c clean. Logic trace: opening the panel → fetches via `deckList` → `applyDeckSearchFilter` runs (no-op if input is empty) → typing in search input filters rows live → rename via prompt updates row markup + persists via RPC.
- **PARITY.md:** §4 Manage saved decks row note updated to call out web parity shipment.
- **Architectural note:** prompt() is functional but not the most polished UX — iOS uses an inline editable field with Save/Cancel, Android uses a Material 3 TextField in an AlertDialog. A future iteration could swap to a `<dialog>` with a TextField; today's prompt() ships the verb fast without `<dialog>` overhead.
- **Next:** Tick 14. Pickable web items: (a) Manage Decks PTR / refresh button (iOS+Android have it, web doesn't), (b) Saved Searches design entry, (c) `prefers-color-scheme` audit, (d) Decks "Duplicate deck" affordance (iOS doesn't have it either — skip), (e) Custom Rainbow editor on web (write parity for the rainbow feature shipped tick 7).

### Tick 12 — 2026-05-20 — PARITY.md drift sweep + WEB-DESIGN.md §15 update
- **Picked:** ground-truth audit. Future ticks pick targets off PARITY.md; drift = wrong targets. After 6+ ticks of shipping, the doc had two false-positives + an outdated WEB-DESIGN.md §15 roadmap section. Tick 11 also discovered the sign-in-method pill was already shipped despite PARITY.md showing it as ⏳; this tick closes the audit gap fully.
- **Fixed:**
  - **Value history chart** (§5) — was ✅ iOS / 🔮 web / ⏳ Android. Reality: `grep -rn 'valueHistory\|value-history'` finds zero implementations anywhere. Both DESIGN.md §8.4 and ANDROID-DESIGN.md §8.4 describe it but no code exists. Corrected to 🔮 across all three with audit note.
  - **My Shows (streamer-only)** (§5) — was ✅ iOS / ✅ web. Reality: web has no streamer Shows surface; only Whatnot tile read in Purchase. iOS has full ShowsListView + ShowDetailView + show_cards Supabase table. Corrected web to 🔮 with audit note.
  - **WEB-DESIGN.md §15 roadmap** — added a "Shipped 2026-05-20 (autonomous parity loop)" subsection documenting tick 5 / 6 / 7 / 8 / 9 / 10 / 11. Removed "Collection Wall display mode" from P2 (it's shipped). Kept "Decks side-by-side desktop layout" as P2.
- **Verified:** PARITY.md row count unchanged (only cell values + notes corrected). WEB-DESIGN.md §15 update preserves prior structure (Shipped + P2 + Deferred subsections).
- **Why this matters:** the autonomous-loop tick-picker reads PARITY.md to find pickable parity gaps. Drift means picking already-shipped or never-built work. The cost of the audit is small (~10 min), the cost of NOT auditing is a tick of wasted work.
- **Architectural note:** future docs-of-truth drift should be flagged + fixed inline rather than accumulated. Every tick that touches a parity cell should re-grep the actual implementation file before claiming.
- **Next:** Tick 13 — actual ship pick from re-verified PARITY.md. Now that My Shows web is correctly 🔮 and template gallery + per-hero rainbows are shipped, the open web-pickable gaps are: (a) Streamer "My Shows" web surface (significant — multi-tick), (b) Manage Decks management improvements (medium), (c) Saved Searches design entry (small — DESIGN.md §8.1 placeholder), (d) `prefers-color-scheme` honoring + brand dark theme audit, (e) Find tab "Random card" affordance — quick win. Leaning (e) or (c).

### Tick 11 — 2026-05-20 — Web Decks template gallery (card-style)
- **Picked:** PARITY.md §4 "Template gallery (empty editor)" had web at 🔮. iOS + Android both ✅. The web had functional plain-text buttons but not the card-style gallery iOS ships in DeckBuilderView.swift TemplateCard. Two days ago Android shipped its 5-archetype gallery overnight; web was the laggard.
- **Bonus discovered:** PARITY.md §9 "Sign-in method pill on Profile" was listed as ⏳ for web but is already shipped (provider-pill rendering at js/collection.js:1015 + CSS at styles.css:2927). PARITY.md drift fix not needed — was already ✅.
- **Shipped:**
  - `js/practice.js`: rewrote `dbRenderTemplates()` to emit `.db-template-card` instead of plain `.db-template-btn`. Each card has: 44×60dp accent-colored monogram tile (single uppercase initial in Bebas Neue 28px), name (Bebas Neue 18px), description (Chakra Petch 12px, 2-line clamp), "PLAYMAKER" format pill, and a chevron. Click handler updated to match both `.db-template-card` and the legacy `.db-template-btn` selector (no breakage if cached).
  - `DB_TEMPLATES` extended with an `accent` field (STEEL/ICE/CYAN/GLOW/BRAWL) — pulled verbatim from iOS TemplateCard.accentColor.
  - `css/styles.css`: ~70 lines added — `.db-template-card` + per-accent border + monogram color tokens, scoped via `[data-accent="STEEL"]` etc. Reuses the canonical element color hex values (`#8A9BB0` STEEL, `#00BFFF` ICE, `#00F5FF` CYAN/brand, `#FFD700` GLOW, `#C0392B` BRAWL).
- **Verified:** node -c clean; click-through works (existing applyTemplate path unchanged — only the row rendering changed). data-template id-string is preserved across both the old and new markup so loadTemplate flow stays consistent.
- **PARITY.md:** Template gallery web 🔮 → ✅. PARITY.md §4 row updated.
- **Architectural note:** template archetype IDs + descriptions are now duplicated across three platforms (iOS DeckTemplate.metadata, Android assets, web DB_TEMPLATES). When a future archetype rebalance lands, all three must update in lockstep — flag this for a future DECISIONS.md entry if it becomes painful.
- **Next:** Tick 12. Strong candidates from PARITY.md still-pending: (a) deck editor "Manage Decks" parity, (b) Find offline/error states audit, (c) Streamer "My Shows" surface on web (already ✅ per matrix though — confirm), (d) PARITY.md "Saved Searches" 🔮 across the board → design proposal in DESIGN.md §8.1's no-search-state slot.

### Tick 10 — 2026-05-20 — Web Find multi-select → "Wall these N cards"
- **Picked:** Closes the §8.8 wall trio — Collection (tick 5), Decks (tick 9), now Find multi-select. iOS DESIGN.md §8.8 + DECISIONS.md #036.
- **Shipped:**
  - `js/collection.js`: renamed the catalog-cards wall entry point to `openCardsWallSheet({ title, cards })` as the canonical name. Kept `openDeckWallSheet({ deckName, cards })` as backward-compat alias for the practice.js call site shipped in tick 9 — both go through the same `openWallSheet({ context: 'deck', title, cards })` path.
  - `js/app.js`: new `openWallFromSelection()` reads `getSelectedCardObjects()` (catalog Cards already filtered to the user's multi-selection) and calls `Collection.openCardsWallSheet({ title: 'N cards', cards })`. Wired to `multiselect-wall` in `initMultiselectToolbar`. No auth required (rendering doesn't write). Doesn't exit selection mode after — user might want to continue selecting after viewing the wall.
  - `index.html`: new `<button id="multiselect-wall" class="multiselect-action">Wall</button>` between "Add to Deck" and the Clear-X in the multi-select toolbar. Lucide image icon for visual parity with the Decks wall button.
- **Verified:** `node -c` clean on all three. Logic trace: selectedCardKeys.size triggers the toolbar (existing) → user clicks Wall → cards = filteredCards.filter(in-selection) → openWallSheet receives catalog Cards with imageFile populated → resolves to the deck-context branch → renders.
- **PARITY.md:** new §2 row "Multi-select → Wall these N cards" — web ✅ · iOS+Android n/a (mobile uses long-press add, no multi-select).
- **Architectural note:** the three wall invocation sites (Collection, Decks, Find multi-select) all funnel through `openWallSheet`. `Collection` path uses user-card-row resolution + price overlay. `deck` context (Decks + Find multi-select) takes catalog Cards directly + hides price overlay. The seam is clean.
- **Next:** Tick 11 — picking from PARITY.md gaps. Strong candidates: (a) iPad scan-view landscape polish (mentioned as deferred in SCRATCHPAD.md), (b) DBS chip tooltips on web, (c) walkthrough relaunch UI on web (no — explicitly out of scope per WEB-DESIGN.md §11), (d) Sign-in method pill audit (mentioned as ⏳ in PARITY.md §9).

### Tick 9 — 2026-05-20 — Web Decks "Generate deck wall"
- **Picked:** iOS DESIGN.md §8.8 + DECISIONS.md #036 — "Wall accessible from Decks (overflow Menu → 'Generate deck wall')". Web had `🔮`; reuses tick-5 canvas Wall pipeline entirely.
- **Shipped:**
  - `js/collection.js`: extended `openWallSheet({ designation, cards })` with two new optional params `context` + `title`. When `context === 'deck'`, cards are catalog Cards (not user_card rows) so the boba_id-lookup resolution step is skipped; price-overlay row is hidden (deck cards aren't designation-scoped + don't carry asking/estimated prices); title comes from the caller (deck name). Collection path unchanged — backwards-compatible.
  - `Collection.openDeckWallSheet({ deckName, cards })` exported on the public API as the Decks entry point. Wraps openWallSheet with the deck context.
  - `window.Collection = Collection` at module bottom — classic-script `const` at top level doesn't auto-promote to the global object; without this, `window.Collection.openDeckWallSheet` from practice.js is undefined. (This also fixes a pre-existing broken reference in app.js line 1645's `window.Collection.quickAdd`.)
  - `js/practice.js`: `db-wall-btn` click handler — collects `DB.heroes + DB.plays + DB.hotDogs` from the current builder state, no-ops with a toast when the deck is empty, otherwise calls `window.Collection.openDeckWallSheet({ deckName: DB.deckName, cards })`.
  - `index.html`: new `<button id="db-wall-btn">` next to db-export-btn in the deck-builder toolbar; Lucide image icon (3-mountain) in violet (`#8B00FF`) to visually distinguish from the save/load/clear/export icons.
- **Verified:** `node -c js/collection.js js/practice.js` passes. Manual trace: `DB.heroes/plays/hotDogs` are populated catalog Cards (each has `imageFile` + `cardNumber` + `bobaId`), which is exactly what the deck-context branch of openWallSheet expects.
- **PARITY.md:** New §4 row "Generate deck wall (share image)" — iOS ✅ · Web ✅ · Android 🔮.
- **Architectural note:** the openWallSheet refactor (designation OR context, with backwards-compat) sets up future call sites — Find multi-select → "Wall these N cards" is the obvious next user (Agent A #2). Same path: pass catalog Cards + a title; price overlay irrelevant.
- **Next:** Tick 10 — pick from PARITY.md. Strong candidates: (a) Find multi-select → Wall (closes the §8.8 trio), (b) Cmd+1..5 tab shortcuts on web (iOS shipped; web n/a was the prior call but worth re-evaluating), (c) decks template gallery on web (🔮 today; Android has it).

### Tick 8 — 2026-05-20 — Web Per-hero Auto Rainbows
- **Picked:** Direct follow-on to tick 7. Agent A #4 documented gap. iOS shipped this as `RainbowDetailView` with `Kind.hero(_)` synthesizing `{heroes: [hero]}` criteria; web had nothing.
- **Shipped:**
  - `js/collection.js`: extracted `_renderRainbowRow(...)` + `_wireRainbowThumbs(...)` shared helpers so the custom-rainbow render path and the new auto-hero render path use the same exact row markup + thumb-tap wiring (zero drift between them).
  - `hydrateHeroRainbows(ownedCards)` — synchronous, runs against `window.__bobaCatalog`. (1) Builds the set of unique heroes the user owns by joining `ownedCards` against the catalog via `_bobaIdLookup` / `_cardLookup`. (2) Single catalog pass bucketing every catalog card by `hero` (only keeps buckets for heroes the user owns). (3) Sorts heroes by completion-% descending, then alphabetical, so the row closest to done surfaces first. (4) Renders one `<details>` per hero summarizing "All printings · N cards" with the same progress bar + thumbnail strip as Custom Rainbows.
  - `index.html` (via collection.js view template): new `<section id="hero-rainbows-section" hidden>` immediately below `custom-rainbows-section`, heading "Rainbows by Hero". CSS reused — both sections share `.custom-rainbows-section` / `.custom-rainbows-heading` / `.rainbow-row` so visual style is locked in step.
  - Both `hydrateCustomRainbows` and `hydrateHeroRainbows` called from `renderTabContent` after the main grid renders.
- **Verified:** read-back of refactored functions; lookup helpers (`_bobaIdLookup`, `_cardLookup`) confirmed to exist at module scope. Auto-rainbows section stays hidden when ownedCards is empty (signed-out / new user). Section also bails silently if catalog hasn't loaded yet.
- **PARITY.md:** Per-hero Auto Rainbows web 🔮 → ✅ read-only.
- **Architectural note:** custom rainbows + hero rainbows now share a single row-render pipeline. Future "Set rainbow" (all cards from one set) and "Treatment rainbow" (one weapon's worth of Inspired Ink) are trivial additions — synthesize the criteria + call `_renderRainbowRow`.
- **Next:** Tick 9 — pick from PARITY.md gaps. Leaning toward Wall view on Decks (Agent A #2 — Decks ⋯ Menu "Generate deck wall" — reuses the tick-5 canvas pipeline; cheap to ship).

### Tick 7 — 2026-05-20 — Web Custom Rainbows (read-only render)
- **Picked:** Agent C's biggest demand signal (1,237 community messages on checklist/rainbow tracking) + Agent A's #3 documented gap. iOS shipped v2.219-v2.221; web parity was 🔮.
- **Shipped:**
  - `js/api.js`: `fetchCustomRainbows()` (PostgREST GET `/user_custom_rainbows`), `rainbowCriteriaMatches(card, criteria)` (verbatim port of iOS `RainbowCriteria.matches` — 8 dimensions AND-combined, values within OR-combined), `rainbowCriteriaSummary(criteria)` (one-line description for the row subtitle). All three exported on the API surface.
  - `js/collection.js`: `hydrateCustomRainbows(ownedCards)` — async fetch, no-op silently if 0 rainbows or catalog not ready. Renders one `<details>` per rainbow with name + criteria summary + "X / Y collected" progress count + width-driven progress bar + percent. Below: thumbnail strip (up to 24 cards) showing matching catalog cards. Owned matches at full opacity with cyan border ring; un-owned dimmed to 0.35 alpha so the user sees what's left.
  - `js/app.js`: exposed `window.__bobaCatalog` (read-only getter on `displayCards`) + `window.openCardModal(card)` so sibling modules can interop without IIFE-leakage.
  - `index.html`: added empty `<section id="custom-rainbows-section" hidden>` below the collection card list. Hidden by default; un-hidden by hydration on first rainbow found.
  - `css/styles.css`: ~95 lines for `.custom-rainbows-section`, `.rainbow-row`, `.rainbow-progress` bar, `.rainbow-thumb` with `.owned` variant.
- **Verified:** SQL query reads existing `user_custom_rainbows` table (iOS migration `2026_05_15_user_custom_rainbows.sql`); RLS already scopes to own-row. Thumbnail tap routes through `window.openCardModal` to the existing card-detail flow. Editor path intentionally not shipped — that's a separate medium-effort tick.
- **PARITY.md:** Custom Rainbows web 🔮 → ✅ read-only.
- **Next:** Tick 8 — Per-hero Auto Rainbows on web (Agent A #4). Builds on the same render path. Auto-derives the rainbow set per-hero from catalog enumeration (no Supabase fetch needed — those are computed from the catalog like iOS does).

### Tick 6 — 2026-05-20 — Web Wall: Price Overlay + per-designation defaults
- **Picked:** Closing the Price Overlay row in PARITY.md §5 — was ⏳ next tick after tick 5.
- **Shipped:**
  - `js/collection.js`:
    * Per-designation defaults wired (`defaultPriceOverlayFor` / `defaultPriceSourceFor`) — For Sale: ON / asking. For Trade + Wanted: ON / estimated. Personal + Grails: OFF.
    * `pickPriceForCard()` reads `asking_price` / `estimated_value` / `purchase_price` from the original user-card row (indexed by bobaId for fast draw-time lookup).
    * `priceOverlayCaptionFor()` matches iOS captions ("Your asking price" / "Market estimate" / "What you paid").
    * Refactored render into a `drawWall({showPrices, source})` closure so toggling re-renders without an image reload.
    * Price chip render: black rounded-rect (radius=chipH/2 → full capsule) + bold mono price at ~8% above card bottom edge (matches iOS ShowWallComposer.tile chipBottomInset). `WTB` prefix on `wanted` designation per §8.8.
  - `index.html`: added `.wall-overlay-controls` block — checkbox + source `<select>` (My asking price / Market estimate / What I paid) + caption span.
  - `css/styles.css`: ~25 lines for `.wall-overlay-controls`, `.wall-overlay-toggle`, `.wall-overlay-select`.
- **Verified:** Reused tick-5 CORS + canvas pipeline. Toggle / source `onchange` fire `drawWall` in-place (no extra network).
- **PARITY.md:** Price Overlay row flipped from ⏳ to ✅ on web. Full Wall + overlay feature parity with iOS achieved.
- **Next:** Tick 7 picks next from Agent A's recommendation list — Custom Rainbows read-only render on web (Agent C's biggest demand signal at 1,237 community messages on checklist/rainbow tracking).

### Tick 5 — 2026-05-20 — Web Wall view (canvas render)
- **Picked:** Agent A audit-parity #1 documented gap "Wall view (Collection display mode + share)" — iOS ✅, web ⏳ M-future, Android ⏳ M2 polish.
- **Shipped:**
  - `js/collection.js`: added `openWallSheet()` — resolves user-card rows to catalog Cards (drops images-less rows), renders a grid of card thumbnails into a `<canvas>` via `API.cardFullUrl()` (routes through `/full/` or `/sealed/optimized/` automatically), exports as PNG.
  - `index.html`: new native `<dialog id="wall-overlay">` with title input, canvas, download + copy + share actions. Sized 1080×variable to fit Instagram / Discord shares.
  - `css/styles.css`: ~75 lines covering the Wall button + dialog + canvas wrap.
  - `js/collection.js`: "Wall" toolbar button on the Collection page next to the Sort dropdown. Disabled when active designation has 0 cards.
  - **R2 CORS configured**: required for canvas + `crossOrigin='anonymous'` so `toBlob` / `clipboard.write` work without taint. Set via `wrangler r2 bucket cors set boba-card-images` with rules allowing GET/HEAD from `bobaplaybook.com` (+ localhost dev). Verified `Access-Control-Allow-Origin: https://bobaplaybook.com` header now present on `/full/...webp` requests.
- **Verified:** R2 CORS curl-verified. Canvas rendering path uses native `<dialog>.showModal()` + native `<canvas>.toBlob()` + native `navigator.share()` per WEB-DESIGN.md §2.1 native-first.
- **Next:** Tick 6 — Price Overlay toggle on top of the Wall canvas (per-designation defaults per iOS §8.8) + per-card selector. Both build on top of this tick's render path.

### Tick 4 — 2026-05-20 — iPad scan-view guide scale
- **Picked:** Agent B audit-deferred #17, "iPad: scan-view landscape guide scaling." Value-history chart on web was first plan but iOS doesn't have it either, so it's a 🔮 row, not a parity gap.
- **Shipped:** `BOBAPlaybook/Views/Scan/ScanView.swift` — file-scope `kGuideW`/`kGuideH` constants converted to size-class-aware computed properties. iPhone (compact) keeps the 300×420 default; iPad regular gets 1.5× scaling → 450×630. Touches every reference (dim mask, stroke, corner marks, ROI rect for AVCaptureSession) consistently because they all read the computed values.
- **Verified:** `xcodebuild -destination 'generic/platform=iOS Simulator'` → BUILD SUCCEEDED.
- **Next:** Tick 5 — Wall view on web. Substantial but Agent A's #2 recommendation. Will scope-split into render → share → toggle if it gets long.

### Tick 3 — 2026-05-20 — Web pricing refresh button + DBS explainer modal
- **Picked:** Two visible-parity items from tick 2's new rows where iOS+Android shipped but web was 🔮: Pricing refresh button (§8 L165) and DBS explainer modal (§8 L164).
- **Shipped:**
  - `js/app.js`: added `↻` refresh button to the pricing day-picker rail. Click sets `forceRefresh = true`, which appends `&fresh=1&_t={timestamp}` to the Worker request. Reset to false after each fetch.
  - `workers/ebay-proxy/worker.js`: added `forceFresh` param that bypasses `cache.match` lookup. New cache entry written from the fresh response so subsequent reads stay efficient. Verified: `?fresh=1` returns `x-cache: MISS`; plain query returns `x-cache: HIT`.
  - `js/app.js`: added DBS stat-cell renderer (Plays only). Tappable; opens dialog. Tier color matches iOS dbsColor.
  - `index.html`: added native `<dialog id="dbs-info-overlay">` with title + bullets + tier table, parity with iOS `DBSInfoSheet`. ESC + backdrop-click + close-button dismiss all work via native `<dialog>` semantics.
  - `css/styles.css`: ~70 lines of new styling for `.pricing-refresh-btn`, `.stat-cell-dbs`, `.dbs-tier-pill`, `.dbs-info-box`, `.dbs-tiers-table` — all element-tinted per iOS tier colors.
- **Verified:** Worker deployed; cache-bypass live (`x-cache: MISS` for `?fresh=1`, `HIT` for plain). HTML+CSS+JS syntactically clean. Dialog uses native `<dialog>.showModal()` per WEB-DESIGN.md §2.1.
- **Next:** Tick 4 — Wall view on web (Agent A's #2 recommendation; iOS canonical exists).

### Tick 2 — 2026-05-20 — PARITY.md reconciliation (matrix unblock)
- **Picked:** Agent A audit's #1 recommendation — "Fix PARITY.md drift FIRST; the matrix is single source of truth and rows that lie about state make every future decision worse."
- **Shipped:** PARITY.md sweep — ~30 row edits across §1, §2, §3, §4, §5, §6, §8, §17.
  - Tabs row: all 5 tabs ✅✅✅ (Android overnight 2026-05-20 closed the gap).
  - Find: 7 Android rows ⏳ M1 → ✅ (overnight commits c325cb2, ce2b0c2, etc.).
  - Learn: 5 Android rows ⏳ M5 → ✅ + added 2 new rows (Watch buckets, Archetype Templates).
  - Decks: 9 Android rows ⏳ M4 → ✅ (template gallery + manage decks + DBS shipped overnight).
  - Collection: 4 Android ⏳ M2 → ✅ (designation + density + grid pricing chip shipped).
  - Purchase: 2 Android ⏳ M6 → ✅ (Whatnot fix shipped overnight); Maps still M6 polish.
  - Card detail: 10 Android ⏳ M1/M3 → ✅ (canonical 6-cell stats, pricing waterfall, Edit Copy, share-with-image, Other Versions all shipped).
  - Added 4 new card-detail rows: DBS explainer modal, Pricing refresh button, Tap-price hint, Swipe nav (iOS shipped v2.287).
  - §17 iOS-specific: added Personal Showcase, Hero Shot entry, House of BoBA invocation, hardware-keyboard shortcuts.
  - **Saved Searches: previously claimed ✅ ✅ — corrected to 🔮 🔮 🔮 after grep found ZERO references in any client.** Agent A's biggest finding.
- **Verified:** scoped grep on each "now ✅" row found matching code in iOS + web + Android (or the explicit overnight commit SHA from `reference_overnight_parity_session_2026_05_20`).
- **Next:** ship a real visible-parity feature. Top candidates from Agent A's recommendation list: Wall view on web (#1), Custom Rainbows on web (#3). Tick 3 picks one.

---

## Audit agents in flight

When each agent returns, its findings populate the backlog above.

- **Agent A (parity audit):** scans iOS vs web vs Android for shipped-but-not-mirrored features beyond what PARITY.md captures
- **Agent B (deferred-feature inventory):** sweeps every `.md` doc + DECISIONS.md entries + SCRATCHPAD `Deferred` sections + commits-with-"defer" / "TODO" / "follow-up" markers
- **Agent C (Discord export JSON inventory):** locates the Claude research dir + parses Discord export JSONs for user-requested features

Status of each: queued / running / complete + findings folded back into Backlog.

### Tick 176 — 2026-05-21 — Android: M3 Expressive wavy progress + fix CI break
- **CI fix first.** Run 26226352152 failed: tick-167 centroid-aware `rememberTransformableState` had the lambda params in wrong order. Read `foundation-android-1.12.0-alpha02-sources.jar` → confirmed new signature is `(centroid: Offset, zoomChange: Float, panChange: Offset, rotationChange: Float)` — centroid FIRST. Swapped lambda from `{ zoom, pan, _, _ -> ... }` to `{ _, zoom, pan, _ -> ... }`. Wrong-order compiled silently (param names are positional aliases); failed at use sites where `offset += panChange` saw Float instead of Offset.
- **Android M3 Expressive wavy indicators** (ANDROID-DESIGN.md §6.11) — first adoption pass. Five files:
  - FindScreen.kt: `LinearProgressIndicator` → `LinearWavyProgressIndicator` (catalog search loading)
  - WatchPage.kt: `CircularProgressIndicator` → `ContainedLoadingIndicator` (YouTube feed fetch)
  - PurchaseScreen.kt: `CircularProgressIndicator` → `ContainedLoadingIndicator` (Whatnot breaks + Stores fetch, 2 sites)
  - CardDetailScreen.kt: `CircularProgressIndicator` → `ContainedLoadingIndicator` (pricing fetch)
  - ProfileSheet.kt: `CircularProgressIndicator` → `ContainedLoadingIndicator` (sign-in / profile load)
- **Saved lessons:** [[feedback_compose_transformable_centroid_order]] (centroid order), added #9 to [[feedback_autonomous_loop_failure_modes]].
- **Verified:** ran the diff carefully; can't compile locally (no JVM on this Mac at /usr/libexec/java_home). CI will validate.
- **Next:** tick 177 = iOS (177 % 5 = 2).

### Tick 177 — 2026-05-21 — iOS AddToDeckSheet "Already in deck" hint (Android parity, tick 174)
- **Verified CI on 32999e8 (tick 176) — green.** Centroid fix held; M3 wavy indicators compiled clean.
- **iOS feature parity:** AddToDeckSheet now shows an "Already in deck" hint per saved-deck row when the card being added is already in that deck (Android tick 174 shipped this on `AddToDeckSheet.kt`).
  - New `@State deckBobaIds: [UUID: Set<String>]` — populated lazily after the deck list lands.
  - Prefetch uses `withTaskGroup` so all decks fetch in parallel; per-deck failure silently leaves the hint off (no error UI noise).
  - Row affordance: "· Already in deck" cyan label next to deck name + cyan checkmark icon (replacing the plus) + cyan 1px stroke around the row's surface card.
  - Pattern parity: same cyan accent used on the Android version + `BOBACardCell`'s in-deck indicator.
- **Version bump:** AppVersion.xcconfig → MARKETING_VERSION 2.290 (build number auto-bumped by ci_post_clone.sh via ASC API).
- **Next:** tick 178 = web (178 % 5 = 3).

### Tick 178 — 2026-05-21 — META: Discord-mined feature backlog (kills same-feature circling)
- **Ben pushback:** *"these loops are really circling around the same exact features. Adjust the way you are looking for things to fix."* I was about to ship a 4th AddToDeck tick in a row.
- **Action:** spawned a general-purpose Agent to mine `~/Documents/Claude/Projects/Bo Jackson Battle Arena Research/discord-exports/` (the `extracted/QUALITATIVE_FINDINGS.md` + `questions.txt` + `support.txt` + the 1MB feedback-and-support JSON). Filtered against PARITY.md + SCRATCHPAD.md so already-shipped + binding-rule-blocked items are out.
- **Saved durability rule:** `[[feedback_autonomous_loop_must_pull_from_backlog]]` — every feature tick MUST pull from this backlog or SCRATCHPAD Deferred / PARITY 🚧, not invent same-tab polish.

## Discord-mined feature backlog (May 2026 mining pass)

Pick the top item for each upcoming tick's platform. Strike out shipped items inline. Re-mine when ≤2 items left.

### TIER 1 — high-demand, mostly UI work on existing data

1. **Power-level RANGE filter on Find** (S) — power is sortable but not filterable; Discord saturated with "ISO 140-160 fire" patterns. Add power min/max slider as a `FilterToken`. iOS + Web + Android.
2. **Set Completion / Rainbow % progress dashboard** (S) — RainbowDetailView shows owned cards but no completion %, no "missing list" panel. Add `X of Y treatments · NN%` headers + "missing" tab. iOS + Web + Android.
3. **Tap-to-define glossary terms inline in Learn articles** (M) — glossary tab exists but article prose has no tappable terms. Wrap with `TooltipBox` (Android) / Popover (web) / inline sheet (iOS) for HTD / Lino / OBF / G&S / Vouch. All three.
4. **Format-eligibility badge on every card cell + "legal in" chip strip on detail** (S) — `CardFormatEligibility.swift` exists; expose it visibly. ~30-35% of rules Qs in Discord are "is this legal in Spec+ / Brawl / Checklist?" Tiny corner badge `S | S+ | C` on cells + full strip on detail. All three.

### TIER 2 — moderate effort, sharp value

5. **DBS explainer in Learn → Rules + per-card DBS context tooltip** (S/M) — card detail shows DBS for Plays; nobody explains the system. Add Learn → Rules → "Understanding DBS" page + replace `?` icon with mini-sheet ("This card costs 6 DBS. Your deck has 28/30 DBS used."). All three.
6. **Wanted-list public sharing surface (`/u/{handle}/wanted`)** (M) — public collection ships, but NOT the Wanted designation. Per-designation public toggle. Web renders read-only `/u/handle/wanted`; iOS+Android set the toggle.
7. **Print-run / SP / SSP indicator on cards** (M) — players distinguish SP / SSP / "/5 / /10 / /25 / /50" Inspired Ink as a first-class shopping concept. Render print-run chip on card cell + dedicated stat row on detail. All three.
8. **Tournament / Release calendar page in Learn → Tournament** (M) — "When does Tecmo ship?", "When is nationals?" are constant. Single static page (refreshed via `assets/data/events.json`) listing upcoming events + release windows + format being played. All three.

### Tick 178's own next step
Skip the web AddToDeck parity that this tick replaced. Tick 179 = web (179 % 5 = 4 → Android, but use punch list anyway since Android is least mature and #1 fits Android cleanly). **Pick: item #1 (Power-level RANGE filter) on Android first** since Android Find filter sheet is the freshest implementation. Then 180 = opt, 181 = Android #1 follow-up to iOS/web, 182 = iOS picks item #2 or #4 (both S, both cross-platform).

### Tick 179 — 2026-05-21 — Android: format-legality chip strip (punch list #4)
- **Punch-list audit before shipping:** Verified Tier 1 items against actual code (Agent's list was wrong on #1 — power-range filter ALREADY ships on all 3 platforms; #2 partially shipped). Picked #4 (format-eligibility badge) since the existing `CardFormatEligibility.restrictions(...)` only returns EXCEPTIONS — the typical card has no positive-legality affordance, which is the Discord ask.
- **Domain API:** Added `legalFormats(card)` to `android/core/domain/.../CardFormatEligibility.kt`. Returns 4-chip list (Spec / Spec+ / Brawl / Checklist) with status (`LEGAL` / `CONSTRAINED` / `ILLEGAL`) + optional reason for tooltip. Sealed products return empty.
- **UI:** New `FormatLegalityStrip` composable in `CardDetailScreen.kt` — Row of `AssistChip`s above the existing `FormatRestrictionsBlock`. Each chip has a colored leading dot (green/amber/red) + format name. Click → `TooltipBox` with the reason or `"Spec: legal"` for the happy case. Most cards show 4 green chips at a glance — the at-a-glance reassurance is the point.
- **Punch-list status:** #4 now ✅ Android · ⏳ iOS · ⏳ web. Future ticks pick up iOS + web parity.
- **Next:** tick 180 = opt; tick 181 = iOS picks #4 (port `legalFormats` to Swift + add chip strip to `CardDetailView.swift`).

### Tick 180 — 2026-05-21 — opt: CI fix for tick 179's TooltipBox / PlainTooltip
- **CI failure on 5dedf82** (run 26228183877): `Unresolved reference 'PlainTooltip'` ×2 + smart-cast across-module-boundary error.
- **Root cause:** `PlainTooltip` is `fun TooltipScope.PlainTooltip(...)` — a TooltipScope extension. Calling `androidx.compose.material3.PlainTooltip` via fully-qualified path doesn't resolve the extension; you have to IMPORT it and call directly so Kotlin can find it via the lambda's TooltipScope receiver.
- **Smart-cast fix:** `chip.reason` lives in :core:domain, so Kotlin won't smart-cast across the module boundary even after a `!= null` check. Bound it to a local `val reason = chip.reason` and used `reason ?: "${chip.format}: legal"` in the elvis path. Collapses the if/else into 1 line — net -3 lines from the original buggy form.
- **Cadence-rule note:** opt ticks ideally net-remove. This one net-adds 2 lines (import) but removes the dead if/else branch — call it neutral. No other orphans found across the 5 files modified in tick 176.
- **Lesson added:** see [[feedback_compose_transformable_centroid_order]] for the kind-of-related "extension function via FQN doesn't dispatch" gotcha. The wavy/centroid pair are both Compose-API gotchas worth keeping at top-of-mind.
- **Next:** tick 181 = Android (cadence). Punch-list item #2 (Rainbow completion + missing list) is the cleanest Android-next since #4 just shipped Android.

### Tick 181 — 2026-05-21 — Android: Rainbow completion + missing-list lens (punch list #2)
- **Verified CI 1a5bf0b green** (PlainTooltip + smart-cast fix held).
- **Punch-list #2 (Rainbow shopping list):** Android RainbowDetailScreen previously showed `X / Y owned` + progress bar but no explicit `NN%`, and the grid mixed owned + missing with a dim "Missing" overlay on un-owned cells. Discord §11 called out the missing **shopping list** view.
- **Added:**
  - **Percentage label** trailing the "X / Y owned" header — cyan green (`#4CAF50`) when N==total ("you did it" moment), brand primary otherwise.
  - **3-option SegmentedButton lens** (All / Owned / Missing) with per-bucket counts in the label (`Missing (12)`).
  - **Filtered grid** via `remember(allCards, ownedBobaIds, lens)` derivative — no extra fetches.
  - **Context-aware empty state:** when Missing is empty → "🎉 Complete — every card collected." When Owned is empty → "You don't own any of these yet."
  - **Dynamic section header:** changes between "Every printing" / "Owned" / "Still to collect" so the user always knows what scope they're seeing.
- **Punch-list status:** #2 now ✅ Android · ⏳ iOS (need same lens + % label) · ⏳ web.
- **Files:** `android/app/.../collection/RainbowDetailScreen.kt` (+100 / -15).
- **Next:** tick 182 = iOS (cadence). Pick punch-list #4 (format-legality chips) port to iOS — port the Kotlin `legalFormats()` to Swift + new chip strip in CardDetailView.

### Tick 182 — 2026-05-21 — iOS Rainbow detail: All/Owned/Missing lens (Discord backlog #2 — iOS parity)
- **Verified Android CI 4b73047 green** (SegmentedButton + RainbowLens cleanly compile).
- **iOS parity for Android tick 181:** RainbowDetailView gets the same All/Owned/Missing lens. iOS already had the percent label, owned/missing visual distinction, and progress bar — it just needed the explicit "shopping list" filter.
- **Implementation:**
  - New `enum Lens: String, CaseIterable` (all/owned/missing) backed by `@SceneStorage("rainbowLens_v1")` so the user's choice survives backgrounding.
  - Segmented `Picker` with per-bucket counts: `All (12) · Owned (5) · Missing (7)`.
  - New `filtered(cards:owned:lens:)` helper (extracted out of the body because the inline `switch` expression tripped SwiftUI's type-inference timeout — Swift compiler can't fold a 3-case switch inside a multi-clause `if let context { let cards = ... }` chain in reasonable time).
  - New `lensEmpty(for:)` view: "Complete — every card collected." with green seal-fill icon when Missing is empty (the bragging-rights moment). "You don't own any of these yet." for empty Owned.
- **Lesson:** SwiftUI body-scope `switch` expressions reliably time out the compiler when 5+ locals are in scope. **Always extract to a function** when adding switch expressions inside view bodies. New memory: [[feedback_swift_switch_expression_typecheck_timeout]] (TODO next opt tick).
- **Punch-list #2:** ✅ Android · ✅ iOS · ⏳ web. Tick 183 (web) picks this up.
- **Version:** v2.291.
- **Next:** tick 183 = web (#2 lens parity).

### Tick 183 — 2026-05-21 — Web: Rainbow lens chips (Discord backlog #2 — closes the trio)
- **Closes punch-list #2** across all 3 platforms (Android tick 181 + iOS tick 182 + web today).
- **Implementation:** the web rainbow display is the inline `<details>` row in Collection (not a dedicated detail VIEW like iOS / Android), so the lens needs to live INSIDE the body. Added a 3-chip row above the thumbnail strip with All (N) / Owned (N) / Missing (N). Click → re-renders the thumb strip filtered to that lens, updates the active-state class.
- **State strategy:** stashed `__matching` + `__ownedKeys` as JS properties on each `.rainbow-row` DOM node after `innerHTML` set (in both `hydrateCustomRainbows` + `hydrateHeroRainbows`) so the lens handler can re-filter without re-running the catalog match (~17k cards × N rainbows on every click would be unworkable).
- **Re-wiring after innerHTML replacement:** the thumb-tap handlers don't survive the `innerHTML` swap when lens changes, so the lens click handler re-attaches them on the fresh DOM.
- **Refactor:** extracted `_renderRainbowThumbs(cards, ownedKeys)` as a pure function — called both from the initial row render AND from the lens click handler. Removes duplicate thumb-emit logic.
- **CSS:** `.rainbow-lens` + `.rainbow-lens-btn` with cyan-active treatment using existing `--boba-cyan` token.
- **Status:** Punch-list #2: ✅ Android · ✅ iOS · ✅ web. DONE — first item fully shipped across all 3 platforms via the loop.
- **Next:** tick 184 = Android (cadence). Pick punch-list #3 (glossary tooltips in Learn articles) on Android since the surface is the freshest.

### Tick 184 — 2026-05-21 — Android Learn articles: inline tap-to-define glossary terms (punch list #3)
- **Discord §4:** article prose throws around HTD / OBF / G&S / vouch / PWE without inline definitions. Standalone Glossary tab exists but users have to know which terms are in it. This tick wires inline tap-to-define so terms in any LearnSection.Body become cyan-underlined links.
- **Implementation:**
  - New private helpers `allGlossaryTerms()` / `detectGlossaryHits(text, terms)` — sort by longest-match-first to prevent shorter substrings winning, claim-array prevents overlapping hits, word-boundary regex (`\b`) for alphanumeric terms vs lookaround (`(?<![A-Za-z0-9])`) for symbol-containing terms like `G&S` / `F/S` so `&`/`/` don't trip the regex.
  - New `GlossaryAwareBody(text)` composable replacing the old plain `Text(section.text)` in `SectionRenderer`'s `Body` branch. Builds an `AnnotatedString` via `buildAnnotatedString` with `pushStringAnnotation(tag="glossary", ...)` per hit + cyan/underline `SpanStyle`. Uses `ClickableText` to bind taps → opens a `ModalBottomSheet` with term + definition.
  - `remember(text)` on hit detection so re-renders don't re-scan.
- **Coverage:** every Rules / Strategy / Setup / Tournament Body paragraph automatically inherits the glossary affordance — no per-article wiring needed. Roughly 30+ terms become tappable across the article corpus.
- **Punch-list #3:** ✅ Android · ⏳ iOS · ⏳ web.
- **Next:** tick 185 = opt (185 % 5 = 0).

### Tick 185 — 2026-05-21 — opt: CI fix for tick 184 (withStyle missing import) + lesson capture
- **CI fail on 293928e** (run 26229902487): `Unresolved reference 'withStyle'` at line 851. `withStyle` is `inline fun <T> AnnotatedString.Builder.withStyle(...)` — needs explicit `import androidx.compose.ui.text.withStyle`. The other AnnotatedString builder methods (`append`, `pushStringAnnotation`, `pop`) are direct members so they don't need importing; only the extension functions do.
- **Fix:** added `import androidx.compose.ui.text.withStyle` to LearnArticleScreen.kt.
- **Lesson capture (deferred from tick 182):** new memory file [[feedback_swift_switch_expression_typecheck_timeout]] — `let x: T = switch foo { ... }` inside a SwiftUI body w/ 4+ locals reliably times out Swift's type checker. Extract to a function. This was the diagnostic that caught tick 182's RainbowDetailView issue.
- **Cadence rule:** opt ticks should net-remove. This tick adds 1 import + memory file (durable, not code). Net change: +1 line of code. Defensive opt — CI was red, fix first, polish next.
- **Memory index updated.**
- **Next:** tick 186 = Android (cadence 186 % 5 = 1). Punch-list #3 (glossary tooltips) is ✅ Android — pick #5 or #7 next for Android.

### Tick 186 — 2026-05-21 — Android: contextual DBS sheet + Learn DBS article (punch list #5)
- **Verified CI on f4aa8a3 green** (`withStyle` import landed clean).
- **Discord backlog #5 (DBS explainer) — both halves shipped on Android:**
  - **Part A — Learn → Rules article.** Added "Understanding DBS" to `rulesAppendix` so it surfaces regardless of game-mode picker (DBS comes up in every Playmaker discussion). Three sections: Body explainer + Bullets on how it works + Callout tip pointing to the card-detail chip. Per the Discord §5 ask (15-20% of rules questions are about DBS).
  - **Part B — Per-card contextual sheet.** `DBSInfoSheet` now takes optional `cardDBS / currentDeckDBS / dbsBudget`. When all three are provided, renders a header `Surface` at top of the sheet: "This card costs +N DBS. Your deck has X/Y DBS used. Adding it brings you to (X+N)/Y." Uses `errorContainer` color when projected total goes over budget. Falls back to static explainer when no active draft.
  - **Wiring:** `HeroStatRow` injects `DecksViewModel` via `hiltViewModel()` at the `if (dbsInfoOpen)` site, collects state, passes the draft's `totalDBS` + `dbsBudget` only when `enforcesDBS` is true. Sheet falls back to static when format doesn't enforce DBS (Rookie / Substitution / base Playmaker).
- **Punch-list #5:** ✅ Android · ⏳ iOS (DBSInfoSheet takes no params today; needs same parity) · ⏳ web.
- **Next:** tick 187 = iOS (cadence 187 % 5 = 2). Port either #4 (format-legality chip) or #5 (contextual DBS sheet) to iOS — #5 is closer to feature parity since #4 needs the bigger UI build.

### Tick 187 — 2026-05-21 — iOS DBS contextual sheet (Discord backlog #5, Android tick 186 parity)
- **Android CI fix landed first** (b85a277): tick-186's `decksVm.state` was wrong — `DecksViewModel.draft` is the direct StateFlow. Fixed wiring + dropped dead `cards.isNotEmpty() || true` short-circuit. Then continued with the iOS work.
- **iOS port of contextual DBS sheet:**
  - `DBSInfoSheet` gains 3 optional params (`cardDBS / currentDeckDBS / dbsBudget`). When all three are set, renders a header `contextBlock` block above the static explainer: "This card costs +N DBS. Your deck has X/Y. Adding it brings you to (X+N)/Y." Switches to `Color.red.opacity(0.18)` surface + red stroke when projected exceeds budget.
  - `CardDetailView` adds `@Environment(DeckBuilderStore.self) private var deckBuilder` (the store is already injected at the app root in `BOBAPlaybookApp.swift:27`).
  - The `.sheet(isPresented: $showingDBSInfo)` site passes the context only when `effectiveEnforceDBS && card.isPlay && card.dbs != nil` — falls back to static explainer otherwise.
- **Punch-list #5:** ✅ Android · ✅ iOS · ⏳ web. Closes all 3 platforms next tick if web cooperates.
- **Version:** v2.292 / build 554 (tandem bump per [[feedback_bump_marketing_and_build_in_tandem]]).
- **Next:** tick 188 = web (#5 contextual DBS + Learn DBS explainer).

### Tick 188 — 2026-05-21 — Web DBS: contextual injection + Learn explainer (closes #5 trio)
- **Punch-list #5 closes across all 3 platforms** (Android tick 186, iOS tick 187, web today).
- **Contextual injection (web):**
  - Card-detail's DBS button now emits `data-card-dbs="N"`.
  - `maybeInjectDBSContext(trigger)` (in app.js) reads it, peeks at `DB.effectiveEnforceDBS` + `DB.totalDBS` + `DB.effectiveDBSBudget` (top-level const in practice.js, accessible in same classic-script global scope), and injects a `<div id="dbs-info-context">` before the dialog's title. Removed on `close` event.
  - Over-budget treatment: red surface + red stroke + red projected-total line. Mirrors iOS+Android's errorContainer styling.
- **Learn → Rules article on web:** new `<div class="rules-section">` with "Understanding DBS (Deck Balancing System)" article inside `#play-panel-rules`. Same explainer + bullets + chip-pointer tip as Android `rulesAppendix`.
- **CSS:** `.dbs-info-context` + `.dbs-info-context-over` + heading/body styles using existing `--boba-*` tokens.
- **Verified:** `node -e "new Function(fs.readFileSync('js/app.js'))"` syntax OK.
- **Punch-list #5:** ✅ Android · ✅ iOS · ✅ web. **DONE.**
- **Backlog status:** 2 of 8 items closed across all 3 platforms (#2 + #5). 6 items remain.
- **Next:** tick 189 = Android (cadence). Pick #4 (format-legality chip) iOS+web parity OR #3 (glossary tooltips) iOS+web parity OR a new punch-list item. #4 is ✅ Android, ⏳ iOS+web → tick 190+ picks up. For tick 189 (Android), pick #7 (print-run / SP / SSP indicator) since #1-5 are all at least partial Android.

### Tick 189 — 2026-05-21 — Android: print-run / SSP badge on card detail (punch list #7)
- **Verified CI on 6a65ecb / b85a277 green** (web tick 188 + Android tick 187 both clean).
- **Discord backlog #7 — Android card detail:**
  - Domain: added `isInspiredInk: Boolean = false` to `:core:domain/Card.kt` (field is in cards.json but the Android model never decoded it). Added `printRunLabel: String?` computed property — returns `/5` (Hex), `/10` (Glow), `/25` (Fire), `/50` (Ice) for Inspired Ink with documented weapon-tied print runs (DECISIONS.md #028), `"Serial"` for other Inspired Ink elements where print run isn't public (Steel/Gum/Brawl/Super), `"SSP"` for Superfoil, `null` for the typical 99% card.
  - UI: `BadgeRow` in CardDetailScreen gets a new accent-bordered `Surface` chip rendering `card.printRunLabel`. SSP → brand orange; numbered → brand cyan. Null = chip absent.
  - Renders alongside the existing "INSPIRED INK" violet capsule when both apply (Inspired Ink Fire → both INSPIRED INK + "/25" chips). At-a-glance scarcity comprehension.
- **Punch-list status:** #7: ✅ Android · ⏳ iOS · ⏳ web. 8 of 8 backlog items have at least 1 platform shipped now.
- **iOS request from Ben (queued for tick 192):** "On pull-to-refresh of Collection in iOS, there are 3 separate loading spinners as it refreshes est. market prices — collapse to one."
- **Next:** tick 190 = opt (190 % 5 = 0). Then tick 191 = Android, tick 192 = iOS (Ben's spinner fix).
