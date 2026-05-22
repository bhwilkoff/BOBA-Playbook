# Good morning! Overnight loop summary

> Updated by the autonomous /loop. Skim top-down. Things you need to do are at the bottom.

## Loop config
- Started: 2026-05-21 (post-compaction)
- Cadence: every 60s via CronCreate `* * * * *` (session-only — dies if Claude exits)
- Sentinel: `<<autonomous-loop>>`
- Platform cadence: tick%5 → 0=opt, 1+4=Android, 2=iOS, 3=web
- Resuming tick numbering at **202** (last session ended at 201)

## Standing priorities (from your message)
1. **Parity across all 3 platforms** — Web should be ~full-featured (modulo 3D); iOS flagship; Android first-class mobile
2. **New features** — sourced from Discord exports (research/), official BoBA blog archive (docs/blog-digest.md), and proactive web research on TCG-collecting apps + BoBA content. Every 5th tick must include research, not just first-tick research.
3. **Code optimization** — every tick%5==0 lowers complexity / removes cruft / cuts file size. PR diff should net-remove lines.

## What shipped overnight

<!-- Each tick appends a one-line summary here. Most recent on top. -->
- **tick 252 (iOS)** — Upcoming Events section gains the Last-refreshed stamp inline w/ header (770bae4). Closes Android tick 219 + web tick 218 events-stamp parity. v2.305/567.
- **tick 251 (Android — content)** — Power Curve content enriched in Learn → Strategy (dfabf4d). 3 tier-band bullets + 3 positioning-tip bullets ported from iOS PowerCurveSection. Closes the Android-iOS content-depth gap for strategy beginners.
- **tick 250 (opt → parity)** — iOS GlossaryView gains 4 Set Ascension terms (Set Ascension / Modern / Hall of Fame / AlphaTrilogy) — was inconsistency with the inline tap-to-define helper that already had them since tick 242 (e678236). Milestone tick — closes web tick 228 + Android tick 229 to 3-platform glossary parity.
- **tick 249 (Android)** — Haptic feedback on long-press → Quick Add / pool add (f46c1b0). iOS parity (UIImpactFeedbackGenerator); previously the long-press action fired silently.
- **tick 248 (web)** — Recent BoBA news gains relative dates + Last-refreshed stamp (6efcd30). **Closes the relative-dates + freshness-stamp trio** (Android 244+246, iOS 247, web today).
- **tick 247 (iOS)** — Recent BoBA news gains relative-format dates + Last-refreshed stamp inline w/ section header (2390e33). Closes Android tick 244+246 parity. v2.304/566. Web port queued.
- **tick 246 (Android)** — Recent BoBA news rows render relative-format dates ("today" / "3d ago" / "2w ago" / raw ISO for >5wk) (3c4d95b). iOS port queued.
- **tick 245 (opt)** — Drop unused "Audit-driven items" backlog placeholder (5d0d4ac). Net -4 lines.
- **tick 244 (Android)** — "Last refreshed" stamp above Recent BoBA news section (f4de13f). Mirrors the events freshness stamp from tick 219. iOS + web ports queued.
- **tick 243 (3-platform BUGFIX)** — Blog-feed loaders on iOS / Android / web were all decoding as a bare array but the file is `{posts:[...]}` (938e5f0). All 3 platforms' "Recent BoBA news" sections were silently rendering empty. Caught by Python sanity-check. Fixed by adding bundle wrappers.
- **tick 242 (iOS)** — boba_inlineGlossary +5 terms (Set Ascension / Modern / Hall of Fame / AlphaTrilogy / Checklist) so they're tappable in Tournament + Collect prose (84792dc). v2.303/565.
- **tick 241 (Android)** — CollectionCardDetail renders condition + slab pills (PSA 10 / BGS 9.5 / etc.) in orange brand color (74d6119). Closes the user-facing half of tick 239's grading-feature data path.
- **tick 240 (opt)** — Trim SCRATCHPAD historical sections that duplicated AUTONOMOUS_PROGRESS + git history (8aa4d7a). -51 lines. Memory refs preserved as a single archive paragraph.
- **tick 239 (Android)** — Stop dropping grade + gradingCompany on the UserCardRow→UserCard domain boundary (f120e43). Data layer was silently losing slab info; research-mined gap from TCG-collector apps. Surface render queued for next tick.
- **tick 238 (web — NEW FEATURE)** — Recent BoBA News section in Learn → Tournament (dc6232d). **Closes the news-feed trio** (Android 236, iOS 237, web today). refresh-blog.yml now mirrors to all 3 platforms in one daily commit. Orange-tinted card rows; tap opens post in new tab; 2-line CSS clamp.
- **tick 237 (iOS — NEW FEATURE)** — Recent BoBA News section in Learn → Tournament (15ef4d3). Mirrors Android tick 236. refresh-blog.yml workflow now mirrors to iOS + Android bundles in same daily commit. v2.302/564. Web port queued.
- **tick 236 (Android — NEW FEATURE)** — "Recent BoBA news" section in Learn → Tournament sourced from docs/blog-feed.json (3387b18). 5 most-recent posts; tap → in-app Custom Tab. Daily-refreshed via existing cron. iOS + web ports queued.
- **tick 235 (opt)** — Migrate GlossaryAwareBody from deprecated ClickableText → Text + LinkAnnotation.Clickable (69776f0). **Zero Compose deprecation warnings remain on Android.** Captured-term closure pattern documented.
- **tick 234 (3-platform — content)** — Tecmo Bowl release event description enriched w/ grail-card details mined from 2026-03-16 blog post (Touchdown Bo Jackson 1/1 + /34 Black Variation; $100k livestream bounty) (9c8a5e7). All 3 platforms read events.json so iOS + Android + web Tournament tabs all show the richer text.
- **tick 233 (web — content)** — Checklist Format explainer + glossary term (d9ddede). **Closes the Checklist Format trio** (Android 231, iOS 232, web today). New row in TOURNAMENT FORMATS table + dedicated section below + glossary entry.
- **tick 232 (iOS — content)** — Checklist Format explainer + glossary term (c912e1c). Mirrors Android tick 231. ChecklistFormatSection in TournamentView w/ 5-bullet list + GLOW "When Checklist fires" callout. v2.301/563. Web port queued.
- **tick 231 (Android — content)** — Checklist Format explainer in Learn → Tournament + Checklist glossary term (8875b81). Discord-mined from 2026-03-27 blog post; closes real content gap (chip strip referenced Checklist but no Learn article explained it). iOS + web ports queued.
- **tick 230 (opt)** — Migrate Glossary clipboard off deprecated `LocalClipboardManager`/`ClipboardManager` → platform `android.content.ClipboardManager` (bda50f4). 2 deprecation warnings squashed; 1 remains (ClickableText, bigger refactor).
- **tick 229 (Android)** — Mirrors tick 228: same 4 Set Ascension glossary terms added to LearnCorpus.glossaryGame (b49abbd). Inherits GlossaryAwareBody inline tap-to-define automatically.
- **tick 228 (web — content)** — Glossary gains 4 Set Ascension terms (Set Ascension / Modern / Hall of Fame / AlphaTrilogy) (2991892). Picked up automatically by inline-glossary wireInlineGlossary() pass so they're tappable in prose.
- **tick 227 (iOS — content)** — Understanding-DBS Learn appendix section (b73c143). Closes Android tick 186 / web tick 188 trio. RulesView appendix gains GlossaryAware explainer + 5-row RuleCard + Quick-tip callout (cyan) + April-2026 rebalance callout (orange). v2.300/562.
- **tick 226 (Android)** — FormatLegalityStrip tooltip migrated to non-deprecated TooltipPositionProvider(TooltipAnchorPosition.Above) API (1907862). Squashed 1 warning.
- **tick 225 (opt)** — Trim AUTONOMOUS_PROGRESS + SCRATCHPAD backlog of shipped items (Web Wall, Custom Rainbows, Android Whatnot/Maps; Android M6 ✅, M7 split into shipped/pending). Net -12 lines. Backlog now reflects reality (6065b9f).
- **tick 224 (Android)** — ScanReviewSheet gains 36×50 card thumbnails (c00e8f1). iOS ScanQueueView parity — faster card recognition than text-only rows.
- **tick 223 (web)** — Google provider pill on Profile (31c7719). Closes parity with Android tick 206 — all 3 brand colors (Google #4285F4 / Discord / Apple) now rendered.
- **tick 222 (iOS)** — GlossaryAwareText expanded to 3 more high-value prose surfaces (Tournament DBS callout, GameModesSection descriptions, PlaymakerScenario Hot-Dog sidebar) (c0257b8). v2.299/561.
- **tick 221 (Android)** — DeckSummaryBar gains format-name pill (6e81590). Closes parity gap with iOS DeckSummaryPill — user sees active format without opening editor.
- **tick 220 (opt)** — Drop tracked .pyc + gitignore __pycache__/*.pyc/*.pyo (47f1cd0). Removes 1 binary; prevents future Python bytecode leakage into commits.
- **tick 219 (Android)** — Tournament events list gains "Last refreshed N" stamp (92fd3c9). EventsBundle now exposes lastUpdated; mirrors web tick 218.
- **tick 218 (web)** — Tournament events list gains "Last refreshed N ago" stamp from bundle.lastUpdated (d60d2ad). Daily-cron freshness now visible.
- **tick 217 (iOS)** — Inline glossary tap-to-define on RuleCard body (91b6b8b). **Closes Discord backlog #3 trio** (Android 186, web 208, iOS today). AttributedString-based; tap cyan term → NavigationStack sheet w/ definition. v2.298/560.
- **tick 216 (Android)** — Rainbow progress upgraded to M3 Expressive `LinearWavyProgressIndicator` (7427050). First M3 Expressive API ship on Android; collection-completion now feels alive. Differentiates from iOS flat bar.
- **tick 215 (opt)** — Squash 4 compile warnings: dead Elvis on Card.set (non-null); Json hoisted to companion (perf win on cache miss); 2 unnecessary safe-calls on appSnackbar; stale capture-screens comment fixed (15ed095). Build still green.
- **tick 214 (Android)** — BOBAEmptyState gains secondary-action support; Purchase "No breaks" empty state now offers "Browse Whatnot" Custom Tab as alternative path (9e240fb). Closes dead-end when Worker offline.
- **tick 213 (web — content)** — Set Ascension section in Learn → Collect (5b89004). Closes the Set Ascension trio (Android 209, iOS 212, web today). 3 variation-card tiers + Alpha Battlefoils bridge callout.
- **tick 212 (iOS — content)** — Set Ascension section in Learn → Collect (80e0683). Mirrors Android tick 209. 3 tiers w/ era pills + Alpha Battlefoils bridge callout in ICE color. Web port queued. v2.297/559.
- **tick 211 (Android)** — Discord link-state aware Profile row (33c8652). Renders Discord-avatar + CheckCircle in brand #5865F2 when linked; "Link" button only when not linked. Closes the "Link button always shown even when linked" polish gap.
- **tick 210 (opt)** — SCRATCHPAD trim: 7 shipped "Deferred iPad" items, 4 strikethrough "Active / Next-Up" + 1 trailing TRADE-DESIGN note + 6-step Ben-action punch list collapsed to a WAKE_UP pointer (12a47a8). Net -28 lines.
- **tick 209 (Android — content mining)** — Set Ascension Learn article (Modern / Hall of Fame / AlphaTrilogy) sourced from 2026-02-10 blog post (0361e04). Filled real gap: catalog ships Hall of Fame + AlphaTrilogy cards but no article explained format evolution. iOS + web ports queued.
- **tick 208 (web)** — Inline glossary tap-to-define on Learn article prose (77dde05). Wraps term occurrences in Rules/Strategy/Collecting/Tournament panels w/ dotted-cyan underline. Closes Discord backlog #3: 2 of 3 (Android ✅ tick 186, web ✅ today, iOS still pending).
- **tick 207 (iOS)** — Format-legality chip strip on card detail (a644ae3). Closes Discord backlog #4 across all 3 platforms (Android tick 179, web tick 203, iOS today). v2.296/558. Hero power gates Spec/Brawl/Spec+; .help() surfaces reason.
- **tick 206 (Android)** — Provider-specific sign-in method pill (iOS parity, 81aa4b4). ProviderPill: Google #4285F4 · Discord #5865F2 · Apple black · email unmarked-default. Closes PARITY row "Sign-in method pill" ✅ all 3.
- **tick 205 (opt)** — drop dead mockup assets (6.2 MB / 5 PNGs / 5 HTML templates / 3 unused fragments) + PARITY M7 + scan audit (12 row corrections). Net -810 lines (ab97885).
- **tick 204 (Android — content)** — April 2026 DBS rebalance callout in Understanding-DBS Learn article. Android + web (b38c734). Mined from 2026-04-27 blog post. iOS skipped (no Learn article exists for DBS yet; DeckBuilder tap-target covers it).
- **tick 203 (web)** — Discord backlog #4 (format-legality chip strip) web parity (12daa6c). Closes 2 of 3 (Android ✅, web ✅, iOS pending). Hero power gates Spec/Brawl/Spec+; chip leading dot = green/amber/red; native title=tooltip.
- **tick 202** (land pre-compaction work, 3 commits to main): `3-platform: events overhaul + glossary long-press + daily blog cron` (ad08b87) · `Android: beta-prep — Maps SDK + card-detail swipe + scan queue + release signing + CI` (54d2124) · `docs+tools: Play Console asset pipeline + doc trim + WAKE_UP scaffolding` (8609274). CI in progress.

## Things you (Ben) need to do

<!-- Anything that needs human action lands here. -->

### Still queued from before the loop started
1. **Manual-upload `app-release.aab`** (32 MB at `android/app/build/outputs/bundle/release/app-release.aab`) → Play Console → Internal Testing → Create new release.
2. **Walk through Play Console required forms** using `android/distribution/play-console-listing.md`.
3. **Upload icon + feature graphic + 5 screenshots** from `tools/play-assets/out/`.
4. **Re-capture screenshots 2–5** by booting the Pixel 9 Pro AVD from Android Studio's Device Manager + running `bash tools/play-assets/capture-screens.sh`.
5. **Add internal-testing emails**, share opt-in URL.
6. **Promote to Open Testing** track when ready.

## How to stop the loop

```sh
# In Claude Code:
/cron list
/cron delete <id>
```

Or just exit Claude — session-only cron dies automatically.
