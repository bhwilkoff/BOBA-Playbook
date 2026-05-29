# BOBA Pricing Automation — End-to-End Self-Improving Loop

> **Binding.** This is the single source of truth for how pricing data
> flows from "user opens a card" through "iOS/Web/Android shows a price"
> with no manual intervention. Companion to
> [`PRICING_PLAYBOOK.md`](./PRICING_PLAYBOOK.md) (provenance-honest
> design principles), [`DECISIONS.md`](./DECISIONS.md) (#058 + #063 +
> #064 + #065 architecture log), and the per-platform binding docs
> ([`DESIGN.md`](./DESIGN.md), [`WEB-DESIGN.md`](./WEB-DESIGN.md),
> [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md) §8.7).
>
> Ratified 2026-05-29 after the post-#064 audit-driven calibration
> loop demonstrated the workflow on real data. Every step in this doc
> stays within free-tier limits across eBay Browse, Cloudflare
> (Workers, D1, KV, Pages), Supabase, and GitHub Actions.

---

## 1. The architecture in one diagram

```
                ┌──────────────────────────────────────────────────────┐
                │  CONTINUOUS  (always running, zero cron)              │
                │                                                       │
   User opens   │  iOS / Web / Android                                  │
   card detail  │      │ HTTP GET /?cardNumber=&hero=&set=…&bobaId=     │
        │       │      ▼                                                │
        │       │  boba-ebay-proxy Worker  ─┐                           │
        │       │      │                    │ ctx.waitUntil(            │
        │       │      │ live response       │   pushIngest(            │
        ▼       │      ▼                    │     listings → tracker D1)│
   PricingSection      Client              │ )                          │
                │                          ▼                            │
                │                  boba-pricing-tracker /ingest         │
                │                          │                            │
                │                          ▼                            │
                │                    D1 boba-pricing                    │
                │      ┌────────────┴────────────────┐                  │
                │      ▼ snapshot                    ▼ vanish-detect    │
                │ listings (active)            sold_events (inferred)   │
                └──────────────────────────────────────────────────────┘
                                       │
                                       │ (data source for daily refresh)
                                       ▼
                ┌──────────────────────────────────────────────────────┐
                │  DAILY 09:00 MT  (local launchd cron on Ben's Mac)    │
                │  — uses existing wrangler OAuth + macOS Keychain      │
                │  — driver: scripts/daily_pricing_refresh.sh           │
                │  — plist:  scripts/com.bobaplaybook.pricing-daily.plist│
                │                                                       │
                │  1.  git pull --rebase --autostash                    │
                │  2.  refresh_stale_prices --source ebay --limit 800   │
                │  3.  refresh_stale_prices --source whatnot --limit 400│
                │  4.  crawl_active_listings --limit 400 (new coverage) │
                │  5.  build_price_estimates.py  ──► price-estimates.json│
                │  6.  audit_estimator.py        ──► price-estimates-   │
                │                                    audit.json         │
                │  7.  track_audit_history.py    ──► pricing-audit-     │
                │                                    history.json (1 row)│
                │  8.  check_audit_regressions.py  → SKIP commit if     │
                │                                    critical regression│
                │  9.  calibrate_estimator.py    ──► pricing-           │
                │                                    calibration-       │
                │                                    recommendations.json│
                │  10. git commit + push (only if clean)                │
                │  11. macOS notification (success or regression)       │
                └──────────────────────────────────────────────────────┘
                                       │
                                       │ (push to main → Pages deploy)
                                       ▼
                ┌──────────────────────────────────────────────────────┐
                │  PROPAGATION  (auto, ~10-20 min)                      │
                │                                                       │
                │  GitHub Pages publishes                               │
                │    https://bobaplaybook.com/assets/data/              │
                │      price-estimates.json                             │
                │                                                       │
                │  boba-price-estimator Worker fetches it via           │
                │    ESTIMATES_ARTIFACT_URL (10-min memo + 10-min       │
                │    edge cache)                                        │
                │                                                       │
                │  iOS / Web / Android call /estimate?bobaId=…          │
                │  → Worker returns rarity_baseline mapped to           │
                │    {low, mid, high, comparableCount,                  │
                │     comparableSources, confidence, method}            │
                │  → identical render across all 3 platforms (DECISIONS │
                │    #059 locked vocabulary)                            │
                └──────────────────────────────────────────────────────┘
```

---

## 2. The continuous data layer (always running, no cron)

### How tracker D1 grows

Every pricing fetch from iOS / Web / Android flows through
`boba-ebay-proxy`. The proxy hits eBay Browse, returns the live response
to the client, and **in `ctx.waitUntil` (so it doesn't block the user
response) POSTs the listings to `boba-pricing-tracker /ingest`**. The
tracker writes them to D1's `listings` table keyed by `boba_id`.

Push model rationale (DECISIONS.md #058): the per-card walk needed for
the "cron-style" approach makes 2 service-binding fetches × 17k cards
= 34k subrequests, which blows Cloudflare's free-plan 50-subrequest-
per-invocation cap. The push model is invocation-per-card, so each
ingest fits trivially under the cap.

### Vanish-inference (sold comps)

On every ingest the tracker compares the new listing snapshot vs the
prior snapshot for that bobaId. Listings that disappear in the new
snapshot are recorded as **"sold @ last-seen price"** in `sold_events`
with a confidence score (`inferred_sold = 1`, `sold_confidence` derived
from how reliably the listing disappeared). This is BOBA's only source
of transacted comps — eBay Marketplace Insights production access is
permanently unavailable (DECISIONS.md #058).

### Community comps (Tier 3)

A separate, smaller stream: signed-in users submit price + sold-date +
platform via `submit_community_comp` RPC (Supabase). Mod-reviewed; once
approved they merge into `/comps` via `get_approved_comps`. Same
provenance pill mechanism, just a different source.

### Total cost of the data layer

| Resource | Limit | Daily usage | Headroom |
|---|---|---|---|
| Cloudflare Workers (free) | 100K req/day across all Workers | ~5-15K (live user traffic + push) | ~85K |
| Cloudflare D1 reads | 5M/day | <100K | ~98% |
| Cloudflare D1 writes | 100K/day | ~5K (one per ingest) | ~95% |
| Supabase rows read | 500K/month | ~50K | ~90% |
| eBay Browse API | 5K/day | ~3K (live user traffic) | ~40% |

Zero cron, zero scheduling, zero failure modes. The data grows the
moment a user opens a card detail.

---

## 3. The daily refresh layer (local launchd cron)

Runs at **09:00 Mountain Time** (configurable in the plist's
`StartCalendarInterval`) on Ben's Mac via launchd. Total run time ~15-25
minutes. Triggered by:

- `launchd` schedule (StartCalendarInterval) — fires daily at 09:00 local
- Manual via `scripts/install_pricing_cron.sh --trigger` (kickstart)
- Direct: `scripts/daily_pricing_refresh.sh [--dry] [--skip-refresh]`

### Why local launchd, not GH Actions

The driver script uses `wrangler d1 execute` to read the tracker D1.
Wrangler authenticates via OAuth that's cached locally
(`~/.config/.wrangler/config/` on macOS) when you run `wrangler login`
once. **A local cron inherits that auth automatically** — no new API
token needed.

GH Actions would run in a fresh ubuntu container with no wrangler
config, requiring a `CLOUDFLARE_API_TOKEN` repository secret. That's
viable (see §6.2 "Cloud failover option") but adds a credential to
manage. Local launchd has zero new credentials — it uses (a) the
wrangler OAuth that's already on the Mac and (b) the macOS Keychain
git credentials already used for daily git push.

**Trade-off**: the Mac needs to be awake at 09:00 local. If asleep,
launchd queues the missed run and fires it on next wake. If the Mac is
off for multiple days (travel), runs queue once; manually trigger via
`scripts/install_pricing_cron.sh --trigger` on return to backfill.

### Steps in detail

**1. Refresh stale prices via eBay** — `refresh_stale_prices.py
--source ebay --stale-days 14 --limit 800`. Queries D1 for cards whose
newest tracker observation is >14 days old, oldest first. Refreshes via
the eBay proxy (which re-ingests via push). Quota burn: ~800 calls (vs
5K/day free).

**2. Refresh stale prices via Whatnot** — same shape but `--source
whatnot --stale-days 7 --limit 400`. Zero eBay quota (Whatnot scraping
runs through a separate proxy path without OAuth).

**3. Stratified crawl for new coverage** — `crawl_active_listings.py
--source ebay --limit 400`. Round-robins across (treatment-family ×
weapon) buckets so coverage fills evenly. Cursor file persists across
runs so we don't re-walk the same cards every day.

Total eBay budget for daily refresh: **~1,200 calls/day** out of 5K
free-tier. Combined with live user traffic (~3K), the daily total stays
under **4,200 calls/day = 84% of free tier**, leaving meaningful
headroom for traffic spikes.

**4. Rebuild estimator artifact** — `build_price_estimates.py` pulls
all D1 listings + sold_events + (optionally Whatnot augmentation) and
produces the closest-comp similarity model output to
`assets/data/price-estimates.json`. Strict-treatment/printrun/weapon
gates apply per DECISIONS.md #064 + amendment.

**5. Run the 9-audit framework** — `audit_estimator.py` writes
`assets/data/price-estimates-audit.json` with the 9 audits' findings +
cross-audit priority list.

**6. Track audit history** — `track_audit_history.py` appends a row
to `assets/data/pricing-audit-history.json` with coverage, audit
counts, weapon/printrun medians, basis breakdown, and the build's
config snapshot. One row per day; same-day re-runs replace the row
(idempotent). Rows older than 180 days trim automatically.

**7. Regression gate** — `check_audit_regressions.py` compares
today's row vs yesterday's. **CRITICAL regressions** (any one fails
the build):
- `two_plus_flagged` grows from 0 → ≥1
- `missing_in_covered_clusters` grows from 0 → ≥1
- `outlier_rich_clusters` grows from 0 → ≥1
- `coverage.pct` drops by >5 percentage points
**WARNING regressions** (logged, don't fail):
- suspect_low / suspect_high grow by >50% AND >10 absolute
- weapon_tier_violations grow by >3
- printrun_violations grow by >2
- any weapon median moves by >50% day-over-day

**8. Calibration recommendations** — `calibrate_estimator.py
--window-days 14` reads history and writes
`assets/data/pricing-calibration-recommendations.json`. Categories:
*tier_ordering_inversion* (persistent rarity-tier inversion), *persistent_low_coverage*,
*persistent_suspect_low*, *outlier_rich_cluster_reappearance*,
*positive_path_shift* (real tracker data accruing — multipliers trigger
less). Recommendation-only, never auto-applied (see §6).

**9. macOS notification on regression** — if step 7 failed, the
script fires `osascript -e 'display notification'` with the regression
headline. The notification appears in Notification Center; sound plays
("Glass"). The script exits non-zero so launchd records the failure,
and the bad artifact is **NOT** committed (the Worker keeps serving
yesterday's good artifact until the regression is fixed).

To inspect after a regression:
```
tail -100 ~/Library/Logs/boba-pricing-daily.err.log
cat /tmp/boba-pricing-regress.log
cat assets/data/price-estimates-audit.json | head -50
```

Resolve, then re-run: `scripts/daily_pricing_refresh.sh --skip-refresh`

**10. Commit + push on clean** — only if regression check passed
AND the artifact actually changed. Commit message includes coverage
delta + flagged count. `[skip ci]` tag prevents the pages-deploy CI
from re-triggering this workflow.

**11. macOS notification on success** — `osascript` displays
"BOBA pricing daily — OK" with the coverage + flagged-count headline
so you can confirm at a glance that the cron fired and committed.

### Free-tier budget for the daily refresh

| Resource | Per-run | Daily total | Free-tier limit | Headroom |
|---|---|---|---|---|
| macOS compute | ~15-25 min CPU-light | ~25 min/day | n/a | ∞ |
| Wrangler / Cloudflare auth | local OAuth (no API token) | n/a | n/a | n/a |
| eBay Browse API | ~1,200 | ~1,200 | 5,000/day | 76% |
| Cloudflare D1 reads | ~5 queries | ~5/day | 5M/day | >99.99% |
| Cloudflare Worker requests | ~1,700 (proxy hits) | ~1,700 | 100K/day | 98% |
| Storage | ~5MB (artifacts + history) | grows ~50KB/day | n/a | n/a |

---

## 4. Failure modes + diagnostic workflow

When the daily run fails or produces unexpected output:

### Case 1 — launchd job fails (notification: "BOBA pricing daily — FAILED")

Open `~/Library/Logs/boba-pricing-daily.err.log` — the last `FATAL:`
line names the step + cause. Most-likely failures:

- **"wrangler not authenticated"** — your wrangler OAuth expired or
  was logged out. Run `npx wrangler whoami`. If it says "not logged
  in", run `npx wrangler login` once from Terminal and re-run the
  job: `scripts/install_pricing_cron.sh --trigger`.
- **"required command 'X' not found in PATH"** — homebrew or python
  moved. The plist exports `/opt/homebrew/bin:...` but if you use a
  different Python install (pyenv, conda), edit the plist's
  `EnvironmentVariables` or the script's `export PATH=` line.
- **"git pull failed"** — usually merge conflict from manual local
  edits. The script uses `--autostash` so simple uncommitted edits
  rebase cleanly; a true merge conflict needs manual `git rebase
  --continue` or `git rebase --abort`.
- **eBay quota** — script is best-effort and continues with whatever
  D1 has. If quota is consistently exhausted, lower `EBAY_STALE_LIMIT`
  by editing the plist's `EnvironmentVariables` or the script.
- **"Check regressions" failed** — by design. See Case 2.

### Case 2 — critical regression aborts the commit

Notification: "BOBA pricing daily — REGRESSION". The artifact was
rebuilt locally but NOT committed; the Worker keeps serving
yesterday's good data. Diagnosis:

1. Run locally to confirm:
   `python3 scripts/audit_estimator.py --rebuild`
2. Inspect the audit JSON for the offending category. For
   `two_plus_flagged` reappearance, the report's "TOP INVESTIGATION
   PRIORITIES" section names the specific cards.
3. Diagnose root cause. Common patterns:
   - **Tracker data shift** (new chase listing landed and contaminated
     a cluster) → wait one more day to see if next snapshot
     stabilises, then re-run workflow.
   - **Script regression** (someone tuned `SIM_WEIGHTS` or a strict
     gate threshold) → `git log` on `scripts/build_price_estimates.py`,
     identify the change, fix or revert.
   - **New audit pattern** (audit script gained a stricter check) →
     either tune the script's threshold or accept the new floor.
4. Force-rebuild + ship the corrected artifact:
   `scripts/daily_pricing_refresh.sh --skip-refresh` (after the fix is
   committed). Skip-refresh avoids burning quota since you already have
   the data; just rebuilds + audits + commits if regression-clean.

### Case 3 — workflow succeeds but estimates look wrong cross-platform

The Worker memo + edge cache (each 10 min) hold the prior artifact for
up to 20 min after a push. Force-refresh via:
- **iOS**: tap the Refresh button in the pricing section (`forceRefresh=true`)
- **Web**: tap the Refresh button (`fresh=1` param)
- **Android**: tap the Refresh button

For a global cache bust (all clients), bump
`workers/price-estimator/wrangler.toml`'s deploy and `wrangler deploy`
— a new Worker version starts with empty memos.

### Case 4 — calibration recommendations look bogus

The script is conservative on purpose (recommend-only). Two things to
verify before acting on a recommendation:
1. **Window adequacy** — `--window-days 14` is the default. A 7-day
   window can be noisy; 30-day is more stable for tier-ordering checks.
2. **Canonical correctness** — recommendations like "bump
   SUPER_PREMIUM_MID by 50%" should be sanity-checked against
   `rarity-model.json`. SUPER is one_of_one; HEX/GUM are secret_rare —
   different premium magnitudes are correct (DECISIONS.md #064 amend).

---

## 5. Future-proofing — how audit changes flow into the loop

Ben's hard requirement: "Any changes that are made during audits will
be folded into the self-improving workflow." This is the design that
delivers it:

### When you add a new audit (e.g., #10)

1. Edit `scripts/audit_estimator.py` — add the audit function in the
   same shape as the existing 9. Write findings to `report["new_check"]`.
2. **No change to `track_audit_history.py`** — it reads the audit JSON
   and only the canonical 9 counts are hard-named in the schema.
   New checks AUTOMATICALLY become available via the
   `audit_counts[...]` dict as long as the audit script writes to
   `report` and the count appears in the audit JSON's top-level.
3. To gate on the new audit in regression checks, add a rule to
   `CRITICAL_RULES` or `WARNING_RULES` in
   `check_audit_regressions.py`. One line per new gate.
4. The calibration script picks up the new metric automatically via
   `audit_counts` field comparison. Targeted recommendations
   (e.g., "if new_check fires for N consecutive days, do X") need an
   explicit rule added to `calibrate_estimator.py`'s
   `analyze_persistent_audit_patterns`.

### When you tune a multiplier

1. Edit the constant in `scripts/build_price_estimates.py`.
2. The next daily run captures the new constant in
   `config_snapshot` of the history row. Future calibration
   recommendations can compare "what we had on day X" vs current.
3. To document the tune, add a brief DECISIONS.md entry (no formal
   architecture change, but the WHY of the tune helps future
   investigation).

### When you add a new strict gate / similarity factor

1. Edit `SIM_WEIGHTS` or add a new strict-gate boolean in
   `build_price_estimates.py`.
2. Extend `config_snapshot` extraction in `track_audit_history.py`
   to include the new constant (one line in the `keys = […]` list).
3. The next daily run captures the new gate; subsequent runs can
   detect drift related to it.

### When you add a new pricing data source (e.g., COMC unblocking, new community endpoint)

1. The data flows through the existing tracker `/ingest` if it can
   be normalised to `(bobaId, price, source)` — no schema change.
2. `build_price_estimates.py` adds the source to the priced-pool
   build step. The closest-comp model treats it as just another
   peer.
3. Audit and calibration are source-agnostic; they operate on
   estimates not on raw data.

The principle: **the audit framework reads from the artifact, history
tracks the audit, calibration tracks the history, regression checks
gate the commit.** Each layer is fed by the one below; new logic at
any layer flows up automatically without rewriting upper layers.

---

## 6. Why recommendation-only calibration

Auto-applying multipliers creates a feedback loop. A single noisy day
could double the multipliers, then the next day's audit shows new
violations, recommending another bump, etc. Three failure modes
specifically:

1. **Tracker data drift** — a fresh chase listing inflates a weapon's
   median for a day. Auto-calibration would lower the multiplier;
   next day after the listing vanishes, the multiplier is too low
   and an entirely different set of cards becomes suspect-low.
2. **Audit-script tweaks** — if someone changes audit #5's floor
   from $30 to $40, suspect-low jumps. Auto-calibration would
   conclude "real bug, bump premium" — wrong response.
3. **Canonical-truth changes** — e.g., a new SUPER variant is
   added with `printRun=null` (catalog data error). Auto-calibration
   would treat the missing data as "less SUPER market presence" and
   lower the multiplier.

Human-in-the-loop breaks all three. The recommendations file is
committed alongside the artifact; Ben reviews periodically (~weekly
in steady state) and applies tunes by hand to
`build_price_estimates.py`. Next daily run captures the new constants
in history; calibration adjusts its baseline.

---

## 7. Setup checklist (one-time, when first enabling)

1. **Verify wrangler auth** — run from Terminal:
   ```
   npx wrangler whoami
   ```
   Should print "logged in with an OAuth Token, associated with the
   email …". If not, run `npx wrangler login` once.
2. **Verify git push works without prompt** — run from Terminal:
   ```
   git push origin main --dry-run
   ```
   Should succeed silently. If it prompts for credentials, configure the
   macOS Keychain credential helper:
   `git config --global credential.helper osxkeychain` and run
   `git push` once interactively to cache.
3. **Install the launchd job**:
   ```
   scripts/install_pricing_cron.sh
   ```
   This symlinks the plist into `~/Library/LaunchAgents/`, bootstraps
   launchd, and enables the job. Idempotent — safe to re-run.
4. **Test-fire once** to verify end-to-end before the scheduled time:
   ```
   scripts/install_pricing_cron.sh --trigger
   ```
   Watch the live log:
   `tail -f ~/Library/Logs/boba-pricing-daily.out.log`
5. **Monitor first 7 days** — verify the cron fires daily at 09:00
   local and no false-positive regressions trigger. Recommendations
   file starts emitting at day 14 (`--window-days 14`).
6. **Allow notifications** — macOS may ask permission the first time
   `osascript` displays a notification. Grant it (System Settings →
   Notifications → Script Editor → Allow Notifications) so you see
   regression alerts.

### Uninstalling

```
scripts/install_pricing_cron.sh --uninstall
```

Removes the launchd job + symlink. The repo files stay intact; you can
re-install later by re-running `scripts/install_pricing_cron.sh`.

### Cloud failover option (optional)

If your Mac is offline for extended travel and the cron queue isn't
acceptable, you can ALSO run the same pipeline in GitHub Actions. The
trade-off is a one-time setup of a `CLOUDFLARE_API_TOKEN` secret (with
`D1:Read` on `boba-pricing`) — the scripts themselves are portable. A
GH Actions workflow file isn't included in the repo today; if you want
one, ask and I'll port `daily_pricing_refresh.sh` to a `.yml`.

---

## 8. References

- [PRICING_PLAYBOOK.md](./PRICING_PLAYBOOK.md) — provenance-honest
  design principles, §6 architecture, §6.7 audit & calibration loop
- [DECISIONS.md](./DECISIONS.md) — #058 (tracker push model),
  #063 (SUPER tier-lock), #064 (strict-treatment / strict-weapon /
  wide-gap fallback), #065 (daily-automation architecture)
- [`scripts/build_price_estimates.py`](./scripts/build_price_estimates.py)
  — the closest-comp model with all strict gates + multipliers
- [`scripts/audit_estimator.py`](./scripts/audit_estimator.py) —
  the 9-audit framework
- [`scripts/track_audit_history.py`](./scripts/track_audit_history.py)
  — one-row-per-day history snapshot
- [`scripts/check_audit_regressions.py`](./scripts/check_audit_regressions.py)
  — CI gate against regressions
- [`scripts/calibrate_estimator.py`](./scripts/calibrate_estimator.py)
  — recommendation engine
- [`scripts/daily_pricing_refresh.sh`](./scripts/daily_pricing_refresh.sh)
  — orchestrator shell script
- [`scripts/com.bobaplaybook.pricing-daily.plist`](./scripts/com.bobaplaybook.pricing-daily.plist)
  — launchd schedule (09:00 local daily)
- [`scripts/install_pricing_cron.sh`](./scripts/install_pricing_cron.sh)
  — one-shot installer

Per-platform pricing rendering binding docs:
[`DESIGN.md`](./DESIGN.md) §8.7 · [`WEB-DESIGN.md`](./WEB-DESIGN.md)
§14.6 · [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md) §8.7. Locked
vocabulary per [DECISIONS.md #059](./DECISIONS.md).
