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
