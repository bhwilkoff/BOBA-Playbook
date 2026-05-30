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
                │  DAILY 06:00 UTC  (.github/workflows/pricing-daily-   │
                │                    refresh.yml)                       │
                │                                                       │
                │  1.  refresh_stale_prices --source ebay --limit 800   │
                │  2.  refresh_stale_prices --source whatnot --limit 400│
                │  3.  crawl_active_listings --limit 400 (new coverage) │
                │  4.  build_price_estimates.py  ──► price-estimates.json│
                │  5.  audit_estimator.py        ──► price-estimates-   │
                │                                    audit.json         │
                │  6.  track_audit_history.py    ──► pricing-audit-     │
                │                                    history.json (1 row)│
                │  7.  check_audit_regressions.py  → FAIL if critical   │
                │  8.  calibrate_estimator.py    ──► pricing-           │
                │                                    calibration-       │
                │                                    recommendations.json│
                │  9.  git commit + push (only if clean)                │
                │  10. open issue if regression detected                │
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

## 3. The daily refresh layer

Runs in **GitHub Actions** (`.github/workflows/pricing-daily-
refresh.yml`) on `ubuntu-latest` (unlimited minutes on public repos).
Total ~15-50 min on weekdays, ~30-80 min on weekend bursts. Triggered
by:

- **Weekdays Mon-Fri 06:00 UTC** (`'0 6 * * 1-5'`) — standard limits
  (800/400/800/1200 for eBay-stale/Whatnot-stale/eBay-crawl/Whatnot-
  crawl). ~1,600 eBay calls + ~1,600 Whatnot.
- **Weekends Sat+Sun 00:30 UTC** (`'30 0 * * 0,6'`) — elevated burst
  limits (1200/800/1800/3000). Fires AT THE START of the UTC day so
  the 5K/day eBay quota is freshest; weekend user traffic is ~50% of
  weekday, leaving more cron headroom. ~3,000 eBay + ~3,800 Whatnot.
  REPLACES the weekday 06:00 UTC run on weekends — they don't both
  fire.
- **`workflow_dispatch`** for manual runs (catch-up, recovery, or
  experimentation with custom limits).

The workflow detects which schedule fired via `github.event.schedule`
and switches the env defaults accordingly. The "Run mode summary"
step at the top of every run prints which mode is active so it's
visible at a glance in the Actions UI.

### Why GH Actions (and only GH Actions)

The whole point of the pipeline is **continuous improvement without
dependence on any single machine being awake**. Ben's Mac sleeps,
travels, restarts, and occasionally drops off Wi-Fi. The estimator
shouldn't pause for any of those.

GitHub Actions runs in GitHub's infrastructure, fires on schedule
regardless of any local machine state, and surfaces failures in a
single UI everyone with repo access can see. Failures open issues
automatically; success commits to main automatically.

The one credential cost — `CLOUDFLARE_API_TOKEN` (D1:Read on
`boba-pricing`) added as a repository secret — is a 5-minute one-time
setup (§7). The wrangler CLI on a fresh ubuntu container can't reuse
a local OAuth cache, so the token is the only way to authenticate
`wrangler d1 execute` in CI. Worth it for permanent removal of "any
laptop must be awake" as a dependency.

### Steps in detail

**1. Refresh stale prices via eBay** — `refresh_stale_prices.py
--source ebay --stale-days 14 --limit 800`. Queries D1 for cards whose
newest tracker observation is >14 days old, oldest first. Refreshes via
the eBay proxy (which re-ingests via push). Quota burn: ~800 calls (vs
5K/day free).

**2. Refresh stale prices via Whatnot** — same shape but `--source
whatnot --stale-days 7 --limit 400`. Zero eBay quota (Whatnot scraping
runs through a separate proxy path without OAuth).

**3a. Stratified crawl for new coverage (eBay)** —
`crawl_active_listings.py --source ebay --limit 800`. Round-robins
across (treatment-family × weapon) buckets so coverage fills evenly.
Cursor file persists across runs so we don't re-walk the same cards
every day.

**3b. Stratified crawl for new coverage (Whatnot)** —
`crawl_active_listings.py --source whatnot --limit 1200`. Same
stratified pattern, separate cursor. **Zero eBay quota cost** — the
limit can be raised aggressively (the constraint is just Whatnot's
site response time, not a paid API quota). Lower hit rate (~5-10%
of walked cards yield listings, vs ~30-50% on eBay) but every hit
is a per-card comp the closest-comp model uses immediately.

Total eBay budget for daily refresh: **~1,600 calls/day** out of 5K
free-tier (800 stale eBay + 800 new eBay; 400 stale Whatnot + 1,200
new Whatnot cost zero eBay). Combined with live user traffic (~3K),
the daily total stays under **4,600 calls/day = 92% of free tier**.
Headroom is intentionally tight here — the coverage growth math
prioritises filling the catalog over leaving spare quota.

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

**9. Open regression issue + exit non-zero** — if step 7 failed,
the workflow uses `actions/github-script@v7` to file a GitHub issue
with the regression report + audit summary + diagnostic steps.
Labels: `pricing`, `regression`, `automated`. The workflow then exits
non-zero so the run is visibly red in the Actions UI, and the bad
artifact is **NOT** committed (the Worker keeps serving yesterday's
good artifact until the regression is fixed).

**10. Commit + push on clean** — only if regression check passed
AND the artifact actually changed. Commit message includes coverage
delta + flagged count + workflow run link. `[skip ci]` tag prevents
the pages-deploy CI from re-triggering this workflow.

**11. Step summary** — `$GITHUB_STEP_SUMMARY` gets a markdown
summary so each run's UI page shows the key metrics at a glance
without digging into logs.

### Free-tier budget per run

**Weekday daily (Mon-Fri 06:00 UTC)**:

| Resource | Per-run | Daily total | Free-tier limit | Headroom |
|---|---|---|---|---|
| GH Actions minutes | ~25-40 min | ~40 min/day | unlimited (public repo) | ∞ |
| eBay Browse API | ~1,600 cron + ~3K user traffic | ~4,600 | 5,000/day | 8% |
| Whatnot proxy calls | ~1,600 | ~1,600 | rate-limit only | n/a |

**Weekend burst (Sat+Sun 00:30 UTC)**:

| Resource | Per-run | Daily total | Free-tier limit | Headroom |
|---|---|---|---|---|
| GH Actions minutes | ~50-80 min | ~80 min/day | unlimited (public repo) | ∞ |
| eBay Browse API | ~3,000 cron + ~1.5K user traffic | ~4,500 | 5,000/day | 10% |
| Whatnot proxy calls | ~3,800 | ~3,800 | rate-limit only | n/a |

**Weekly total**: ~12K eBay cron calls (5 weekday × 1.6K + 2 weekend
× 3K) + ~22K user traffic = ~34K eBay calls/week, vs 35K free-tier
weekly cap (5K × 7). 4% headroom — the weekend burst pushes the
budget to near-capacity intentionally; that's the point.

**Daily-invariant resources**:

| Resource | Per-run | Daily | Free-tier limit | Headroom |
|---|---|---|---|---|
| Cloudflare D1 reads | ~5 queries | ~5/day | 5M/day | >99.99% |
| Cloudflare Worker requests | ~3,200 (weekday) / ~6,800 (weekend) | per above | 100K/day | 93-97% |
| Storage | ~5MB (artifacts + history) | grows ~50KB/day | n/a | n/a |

---

## 4. Failure modes + diagnostic workflow

When the daily run fails or produces unexpected output:

### Case 1 — GH Actions workflow fails (red X in Actions UI)

Open the most recent run via the Actions tab. The Step Summary at the
top gives the headline. Most-likely failures:

- **"Verify Cloudflare credentials"** — `CLOUDFLARE_API_TOKEN`
  secret missing or expired. Recreate at
  [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
  with `D1:Read` on `boba-pricing`. Re-add as a repository secret.
- **"Refresh stale prices via eBay"** — eBay quota exhausted (live
  user traffic + earlier refresh consumed >5K). Step is
  `continue-on-error` so the build still runs with whatever D1 has.
  If persistent, lower `ebay_stale_limit` input.
- **"Build price-estimates.json"** — wrangler D1 query failed.
  Usually transient; re-run via `workflow_dispatch`. If persistent,
  check D1 dashboard for incidents.
- **"Check regressions"** — by design. See Case 2.

(Local launchd notes follow only if you opt into §7's local
alternative; otherwise skip to Case 2.)

### Case 2 — critical regression aborts the commit

A GitHub issue with labels `pricing,regression,automated` was opened
by the workflow. The artifact was rebuilt in CI but NOT committed;
the Worker keeps serving yesterday's good data. Diagnosis:

1. Read the audit summary in the issue body (auto-attached by the
   workflow). For `two_plus_flagged` growth, the "TOP INVESTIGATION
   PRIORITIES" section names the specific cards.
2. Diagnose root cause. Common patterns:
   - **Tracker data shift** (new chase listing landed and contaminated
     a cluster) → wait one more day to see if next snapshot
     stabilises, then re-run the workflow via `gh workflow run
     "pricing · daily refresh + audit"`.
   - **Script regression** (someone tuned `SIM_WEIGHTS` or a strict
     gate threshold) → `git log` on `scripts/build_price_estimates.py`,
     identify the change, fix or revert, push to main. Next cron picks
     it up; or trigger immediately via `gh workflow run`.
   - **New audit pattern** (audit script gained a stricter check) →
     either tune the script's threshold + commit, or accept the new
     floor and let the next cron re-baseline.
3. **All fixes are commit-then-trigger, never run-locally-and-ship.**
   The daily artifact ships only from CI. Local rebuilds during
   investigation are fine for diagnosis but never get force-pushed
   over the CI version — let the next cron (or a manual
   `workflow_dispatch`) produce the corrected artifact.

   The principle: **the cloud is the only source of truth for the
   artifact**. Local rebuilds drift from CI in subtle ways (Whatnot
   proxy response variation, D1 query timing, Python version diffs).
   When a regression happens, fix the SCRIPTS in the repo, push, and
   let CI rebuild. Don't shortcut.

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

### GitHub Actions setup

1. **Create a Cloudflare API token** at
   [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens):
   - Click **Create Token** → **Create Custom Token**
   - Permission: `Account` → `D1` → `Read` (scope to your account)
   - Optional permission: `Account` → `Workers Scripts` → `Read` (for
     future expansion)
   - Account Resources: include only your BOBA Playbook account
   - **Continue to summary** → **Create Token** → copy the value
2. **Add the token as a repository secret**:
   - Repo Settings → Secrets and variables → Actions → New repository
     secret
   - Name: `CLOUDFLARE_API_TOKEN`
   - Value: paste the token from step 1
3. **(Optional) Add account ID** if your CF account has multiple
   sub-accounts: secret name `CLOUDFLARE_ACCOUNT_ID`
4. **Test-fire** via Actions UI → "pricing · daily refresh + audit"
   → "Run workflow" → leave defaults → confirm green
5. **Monitor first 7 days** — verify the cron fires daily at 06:00
   UTC and no false-positive regressions trigger. Recommendations
   file starts emitting at day 14 (`--window-days 14`).
6. **Subscribe to issue notifications** with `pricing,regression`
   labels so you see automated alerts.

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
- [`.github/workflows/pricing-daily-refresh.yml`](./.github/workflows/pricing-daily-refresh.yml)
  — daily cron orchestration

Per-platform pricing rendering binding docs:
[`DESIGN.md`](./DESIGN.md) §8.7 · [`WEB-DESIGN.md`](./WEB-DESIGN.md)
§14.6 · [`ANDROID-DESIGN.md`](./ANDROID-DESIGN.md) §8.7. Locked
vocabulary per [DECISIONS.md #059](./DECISIONS.md).
