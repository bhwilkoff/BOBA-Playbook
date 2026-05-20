# Parity audit — 2026-05-20

## Documented gaps (top 15, prioritized)

Sorted by visibility-during-ordinary-use × user impact. Web "M-future" treated as a present gap; Android "⏳ M-N" called out where M0–M7 functional scaffolding has shipped but the listed item isn't actually wired.

| # | Feature | iOS | Web | Android | Where (PARITY.md) | Effort |
|---|---|---|---|---|---|---|
| 1 | Wall view (Collection display mode + share) | ✅ | ⏳ M-future | ⏳ M2 | §5 L109 | medium |
| 2 | Price Overlay in Wall view | ✅ | ⏳ M-future | ⏳ M2 | §5 L110 | low (rides on #1) |
| 3 | Custom Rainbows | ✅ | 🔮 | ⏳ M2 | §5 L106 | medium |
| 4 | Per-hero Auto Rainbows | ✅ | 🔮 | ⏳ M2 | §5 L107 | medium |
| 5 | Value history chart | ✅ | 🔮 | ⏳ M2 | §5 L105 | low |
| 6 | Deck editor sheet w/ zoom (web side-by-side) | ✅ | ⏳ desktop pattern | ⏳ M4 | §4 L83 | medium |
| 7 | Template gallery (empty Decks editor) | ✅ | 🔮 | ⏳ M4 | §4 L91 | low |
| 8 | Multi-select + bulk add on Find | n/a | ✅ | 🔮 | §2 L54 | medium (Android only) |
| 9 | Public collection URL `/u/{username}` | n/a (toggle) | ✅ | ⏳ M7 | §5 L113 | n/a — toggle done; backend ✅ |
| 10 | Personal Showcase (iTunes-style screensaver) | ✅ | 🚫 | 🚫 v1 | §5 L111 | (intentional) — skip |
| 11 | Saved Searches | claimed ✅ | claimed ✅ | ⏳ M1 | §2 L58 | **see undocumented #1** |
| 12 | Sign-in method pill on Profile | ✅ | ✅ | ⏳ M7 | §9 L185 | low |
| 13 | Admin / Mod panel (Android v2) | ✅ | ✅ | 🔮 | §9 L182-184 | high (deferred) |
| 14 | Tap break tile → external Whatnot | ✅ | ✅ | ⏳ M6 | §6 L124 | low |
| 15 | OAuth callback handling on Android | ✅ | ✅ | ⏳ M0 | §10 L197 | low |

Items where Android shows ⏳ M-N (M1–M7) but the May-20 overnight session shipped functional scaffolding — items 6, 7, 8, 12, 13, 14, 15 are likely closer than the matrix shows. PARITY.md needs a sweep against the actual Android state per `reference_android_v1_status` memory.

## Undocumented gaps (top 12)

Code-verified asymmetries that don't appear in PARITY.md.

| # | Feature | Shipped on | Missing on | Where in code | Effort | Notes |
|---|---|---|---|---|---|---|
| 1 | **Saved Searches (Find featured shelf)** — PARITY.md claims ✅ on iOS+web but grep finds zero `Saved`/`savedSearch` references in `BOBAPlaybook/Views/Search/SearchView.swift` or `js/app.js`. Android FindScreen.kt only has Recently Added | **none** (PARITY.md inaccurate) | iOS, web, Android all | iOS: SearchView.swift no match · Web: app.js no match · Android: FindScreen.kt L721 only "Recently added" | medium | Either ship everywhere or fix PARITY.md row §2 L58 |
| 2 | **Personal Showcase entry point (Open Showcase Menu item)** | iOS only — `CollectionView.swift:604-612` | web, Android | iOS `CollectionView.swift` L608 menu item; no equivalent in `js/collection.js` or Android | (out of scope per §15 L257) | But §15 says Hero Shot row applies — Showcase entry not explicitly in PARITY.md §17 iOS-specific table |
| 3 | **Hero Shot fullScreenCover from Collection card detail** | iOS only — `CollectionCardDetailView.swift:23,186-264` | web, Android | iOS only; not listed in PARITY.md §15 or §17 | n/a (3D scope) | Add to §17 iOS-specific table |
| 4 | **House of BoBA easter egg entry** in Profile menu | iOS only — `ProfileView.swift:48,95,170-184` | web (n/a), Android | iOS ProfileView.swift L170-184 "easter eggs" menu | n/a | PARITY.md §15 lists House of BoBA but not the Profile-menu invocation pattern |
| 5 | **Watch view (tournament livestream feed)** | iOS, web, Android | none missing — but **not in PARITY.md** | iOS `WatchView.swift`; web `js/watch.js` + `index.html:1790-1819`; Android `WatchPage.kt` + `WatchViewModel.kt` | n/a | Add row to PARITY.md §3 Learn (Watch is currently under Learn) |
| 6 | **Tournament reference content** (TOURNAMENT FORMATS / MATCH STRUCTURE / PENALTY REFERENCE) | iOS, web | Android (placeholder only) | Web `index.html:1660-1785`; iOS Play views; Android `LearnContent.kt` to verify | low | Add row under §3 Learn or §4 Decks |
| 7 | **Discord Trade Room overlay (mod-gated)** | iOS only — `TradeRoomSheet.swift`, `DiscordMessageRow.swift`, `ReactionPickerView.swift` | web (stub at `js/app.js:3571-3775`), Android | iOS full implementation; web has UI shell but no message-send wiring; Android nothing | gated per DECISIONS.md #025/#049 | Per CLAUDE.md `Remove all Discord-sourcing infrastructure` recent commit b797b5d — confirm intent before lifting gate |
| 8 | **In-app cropping (mod add-card)** | iOS only — pure-UIKit `CardCropView` per v2.218 | web, Android (mod panels deferred) | iOS `ModAddCardSheet.swift` | n/a | Lives with mod panels in §9 L182-184; tied to mod-panel parity |
| 9 | **Per-tab grid density picker (Find / Decks / Collection)** | iOS, web, Android | none missing per memory `feedback_grid_density_per_tab` | iOS `ColumnsPickerRow` in ProfileView.swift L617-624; Android `FindPrefsStore`/`CollectionPrefsStore` per overnight session | n/a | NOT in PARITY.md §5 L103 today shows Collection only; should reflect that Find + Decks also persist density |
| 10 | **DBS explainer ModalBottomSheet on card detail** | iOS, Android (per overnight commit notes) | web | iOS CardDetailView; Android per `df7e799` overnight commit | low | New affordance; add to §8 card-detail |
| 11 | **Pricing refresh button on card detail** | iOS, Android (per `27796a4` overnight) | web | iOS CardDetailView; Android | low | Add to §8 L150 |
| 12 | **Hardware-keyboard shortcuts (Cmd+1..5 / Ctrl+1..5)** | iOS, Android (per overnight session) | web | iOS hidden-Button overlay; Android Ctrl+1..5 | low | Add to §17 iOS-specific or generalize to §1 |

## Recommended ship order (top 5)

1. **Fix PARITY.md drift (undocumented #1, #5, #6, #9, #10, #11, #12)** — the matrix is the single source of truth for parity decisions; rows that lie about state make every future decision worse. Saved Searches is the worst offender (claimed ✅×2, actually nowhere). Audit + reconcile takes ~2 hours and unblocks everything else.

2. **Wall view + Price Overlay on web (documented #1, #2)** — the most-visible Collection sharing affordance; iOS users already use it, web users can't reciprocate when iOS users share `/u/{username}` walls. Single feature unlocks the share-with-friends loop on the most-shared platform.

3. **Custom Rainbows + Per-hero Auto Rainbows on web (documented #3, #4)** — collecting goals are central to the "Own" verb. Web users currently see a degraded Collection experience vs iOS. Backend already exists (`user_custom_rainbows` Supabase table); just needs the web renderer + editor.

4. **Sweep Android M1–M7 deferred-polish items now that scaffolding is in (per `reference_android_v1_status`)** — the matrix shows ⏳ M-N on items that overnight session likely landed (Saved Searches shelf, sign-in method pill, OAuth callback). Cheaper to verify + flip status than to rebuild later. Pair with item #1.

5. **Value history chart on web (documented #5)** — small surface (single chart push destination), high "feels native" payoff, no new backend. Closes the last meaningful Collection gap once Wall + Rainbows ship.
