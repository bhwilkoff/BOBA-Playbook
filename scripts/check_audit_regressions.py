#!/usr/bin/env python3
"""
check_audit_regressions.py — gate the daily artifact rebuild on
regression checks against yesterday's audit history.

Reads `assets/data/pricing-audit-history.json` (produced by
`track_audit_history.py`). Compares today's row to the previous row and
exits non-zero when a CRITICAL regression is detected. Used as a CI gate
in `.github/workflows/pricing-daily-refresh.yml` — the workflow runs:

    build → audit → track → CHECK → commit-if-clean

so a bad artifact never ships.

WHY THIS EXISTS
---------------
The audit framework (DECISIONS.md #063 amend 2, #064) catches patterns
at a point in time. Catching a *new* pattern after a daily rebuild is
the regression — what was healthy yesterday is broken today. Without
this check the bad artifact would silently land on bobaplaybook.com and
the Worker's 10-min memo + edge cache would propagate it cross-platform
within 20 min. The check is the seatbelt.

REGRESSION RULES (any ONE trips a critical fail)
------------------------------------------------
- two_plus_flagged grows from 0 → ≥1
  (cards flagged by 2+ audits = highest-confidence wrong estimates;
   we drove this to 0 in #064 and want a hard gate to keep it there)
- missing_in_covered_clusters grows from 0 → ≥1
  (the wide-gap fallback should keep this at 0; reappearance =
   regression in fallback logic)
- outlier_rich_clusters grows from 0 → ≥1
  (cluster-level systematic bug; same shape as the pre-#064 IIMBF
   $1.84 disaster)
- coverage.pct drops by >5 percentage points day-over-day
  (sudden coverage collapse = a strict-gate misfiring or D1 going
   offline)

WARNING RULES (logged but don't fail)
-------------------------------------
- suspect_low grows by >50% AND >10 absolute
- suspect_high grows by >50% AND >10 absolute
- weapon_tier_violations grows by >3
- printrun_violations grows by >2
- any weapon_median moves by >50% day-over-day

USAGE
-----
    python3 scripts/check_audit_regressions.py
        # exits 0 if clean, 1 if critical regression detected
        # always prints a report to stderr

    python3 scripts/check_audit_regressions.py --strict
        # also exits 1 on warnings (use only in CI when needed)
"""

import argparse
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HISTORY = os.path.join(REPO, "assets", "data", "pricing-audit-history.json")


CRITICAL_RULES = [
    # (path, threshold, comparison, message)
    #
    # 'growth-or-cross-zero' fires both (a) when the count crosses 0 →
    # ≥1 (a clean baseline became dirty) AND (b) when an already-dirty
    # baseline grows further (prev=1 → now=2 etc.). Earlier shape
    # (`absolute-gt-or-equal` with prev=0 precondition) silently
    # allowed degradation once a single anomaly slipped through —
    # caught by Ben after the BLBF-255 anomaly landed in today's row.
    ("audit_counts.two_plus_flagged", 1, "growth-or-cross-zero",
     "Cards flagged by 2+ audits grew (was {prev}, now {now}). "
     "Highest-confidence wrong estimates — investigate before shipping."),
    ("audit_counts.missing_in_covered_clusters", 1, "growth-or-cross-zero",
     "Missing-in-covered-cluster grew (was {prev}, now {now}). "
     "Wide-gap fallback (#064) regression."),
    ("audit_counts.outlier_rich_clusters", 1, "growth-or-cross-zero",
     "Outlier-rich clusters grew (was {prev}, now {now}). "
     "Cluster-level systematic bug — same shape as pre-#064 IIMBF."),
]

WARNING_RULES = [
    ("audit_counts.suspect_low", 10, "absolute-and-pct50",
     "suspect-low grew from {prev} to {now} (>50%, >10 abs)."),
    ("audit_counts.suspect_high", 10, "absolute-and-pct50",
     "suspect-high grew from {prev} to {now} (>50%, >10 abs)."),
    ("audit_counts.weapon_tier_violations", 3, "delta-gt",
     "weapon-tier ordering violations grew from {prev} to {now} (+{delta})."),
    ("audit_counts.printrun_violations", 2, "delta-gt",
     "printrun ordering violations grew from {prev} to {now} (+{delta})."),
]


def get_nested(d, path):
    cur = d
    for k in path.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
    return cur


def check_rule(prev_row, curr_row, path, threshold, mode, msg_tmpl):
    prev = get_nested(prev_row, path)
    now = get_nested(curr_row, path)
    if now is None or prev is None:
        return None
    delta = now - prev
    if mode == "absolute-gt-or-equal":
        # Trip when value crosses 0 → positive (regression from clean state).
        if prev == 0 and now >= threshold:
            return msg_tmpl.format(prev=prev, now=now, delta=delta)
    elif mode == "growth-or-cross-zero":
        # Fires on both (a) clean→dirty AND (b) any further growth.
        # The first guards the regression-free baseline; the second
        # guards against silent degradation after one anomaly slipped
        # through (the BLBF-255 trap that motivated this rule).
        if (prev == 0 and now >= threshold) or (now > prev and now > 0):
            return msg_tmpl.format(prev=prev, now=now, delta=delta)
    elif mode == "delta-gt":
        if delta > threshold:
            return msg_tmpl.format(prev=prev, now=now, delta=delta)
    elif mode == "absolute-and-pct50":
        if delta >= threshold and prev > 0 and (delta / prev) > 0.5:
            return msg_tmpl.format(prev=prev, now=now, delta=delta)
        # also trip when prev == 0 and now > threshold
        if prev == 0 and now >= threshold:
            return msg_tmpl.format(prev=prev, now=now, delta=delta)
    return None


def check_coverage_drop(prev_row, curr_row):
    """Critical: coverage drops by >5 percentage points day-over-day."""
    prev = (prev_row.get("coverage") or {}).get("pct")
    now = (curr_row.get("coverage") or {}).get("pct")
    if prev is None or now is None:
        return None
    if (prev - now) > 0.05:
        return (f"Coverage dropped from {prev:.1%} to {now:.1%} "
                f"(−{(prev-now)*100:.1f}pp). Possible strict-gate misfire "
                f"or D1 outage.")
    return None


def check_weapon_median_swings(prev_row, curr_row):
    """Warning: any weapon median moves by >50%."""
    prev_meds = prev_row.get("weapon_medians") or {}
    curr_meds = curr_row.get("weapon_medians") or {}
    warnings = []
    for w in set(prev_meds) & set(curr_meds):
        p, c = prev_meds[w], curr_meds[w]
        if p > 0 and abs(c - p) / p > 0.5:
            direction = "up" if c > p else "down"
            warnings.append(
                f"{w} median moved {direction} {abs(c-p)/p*100:.0f}% "
                f"(${p:.2f} → ${c:.2f})"
            )
    return warnings


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 on warnings as well as critical regressions")
    args = ap.parse_args()

    if not os.path.exists(HISTORY):
        print("No history file yet — first run, nothing to compare.", file=sys.stderr)
        return 0

    history = json.load(open(HISTORY))
    rows = history.get("rows") or []
    if len(rows) < 2:
        print(f"Only {len(rows)} row(s) — no previous run to compare.", file=sys.stderr)
        return 0

    prev_row, curr_row = rows[-2], rows[-1]
    print(f"Comparing {curr_row.get('date')} (now) vs {prev_row.get('date')} (prev)",
          file=sys.stderr)
    print(f"  coverage: {prev_row.get('coverage', {}).get('pct'):.1%} → "
          f"{curr_row.get('coverage', {}).get('pct'):.1%}", file=sys.stderr)

    # Critical checks
    criticals = []
    for path, threshold, mode, msg in CRITICAL_RULES:
        result = check_rule(prev_row, curr_row, path, threshold, mode, msg)
        if result:
            criticals.append(result)
    cov_drop = check_coverage_drop(prev_row, curr_row)
    if cov_drop:
        criticals.append(cov_drop)

    # Warnings
    warnings = []
    for path, threshold, mode, msg in WARNING_RULES:
        result = check_rule(prev_row, curr_row, path, threshold, mode, msg)
        if result:
            warnings.append(result)
    warnings.extend(check_weapon_median_swings(prev_row, curr_row))

    if criticals:
        print("\n❌ CRITICAL REGRESSIONS — DO NOT SHIP", file=sys.stderr)
        for m in criticals:
            print(f"  - {m}", file=sys.stderr)
    if warnings:
        print("\n⚠️ WARNINGS", file=sys.stderr)
        for m in warnings:
            print(f"  - {m}", file=sys.stderr)
    if not criticals and not warnings:
        print("✓ no regressions detected", file=sys.stderr)

    if criticals:
        return 1
    if warnings and args.strict:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
