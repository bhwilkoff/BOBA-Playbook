#!/usr/bin/env python3
"""
track_audit_history.py — append a daily summary row to the pricing audit
history file. Reads the current `price-estimates.json` + `price-estimates-
audit.json` (produced by `build_price_estimates.py` + `audit_estimator.py`)
and writes a compact, diffable snapshot to `assets/data/pricing-audit-
history.json`.

Why: the audit framework (DECISIONS.md #063 amend 2, #064) catches
patterns at a point in time. The HISTORY is what lets us detect DRIFT
over time — coverage shrinking, tier ordering re-inverting, outlier-rich
clusters reappearing after a tracker-data shift — and feeds the
calibration loop (`scripts/calibrate_estimator.py`). One-row-per-day
keeps it human-readable + git-diff-friendly.

Idempotent: if a row for today already exists, REPLACE it (re-runs of
the daily workflow produce one row, not many).

USAGE
-----
    python3 scripts/track_audit_history.py            # append today's row
    python3 scripts/track_audit_history.py --print    # also pretty-print summary
"""

import argparse
import datetime
import json
import os
import re
import statistics
import sys
from collections import defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "assets", "data", "cards.json")
ESTIMATES = os.path.join(REPO, "assets", "data", "price-estimates.json")
AUDIT = os.path.join(REPO, "assets", "data", "price-estimates-audit.json")
BUILD_SCRIPT = os.path.join(REPO, "scripts", "build_price_estimates.py")
APP_VERSION = os.path.join(REPO, "AppVersion.xcconfig")
HISTORY = os.path.join(REPO, "assets", "data", "pricing-audit-history.json")


def extract_config_snapshot():
    """Pull the tuning constants out of build_price_estimates.py so the
    history row captures what config produced these numbers. Saves a
    round-trip on the calibration step (it can compare today's
    multipliers to history without re-running build)."""
    text = open(BUILD_SCRIPT).read()
    config = {}
    keys = [
        "SOLD_HAIRCUT", "MIN_CARDS", "MIN_SIM", "MAX_SIM_GAP", "MAX_COMPS",
        "CONF_AVG_SIM_MED", "CONF_HIGH", "SEALED_MIN_PRICE",
        "SUPER_PREMIUM_LOW", "SUPER_PREMIUM_MID", "SUPER_PREMIUM_HIGH",
        "WEAPON_TIER4_PREMIUM_LOW", "WEAPON_TIER4_PREMIUM_MID",
        "WEAPON_TIER4_PREMIUM_HIGH",
    ]
    for k in keys:
        m = re.search(rf"^{k}\s*=\s*([\d.]+)", text, re.MULTILINE)
        if m:
            v = m.group(1)
            config[k] = float(v) if "." in v else int(v)
    return config


def extract_app_version():
    """Read MARKETING_VERSION from AppVersion.xcconfig — this is the
    'build version' tag attached to the daily row, so we can correlate
    audit drift with shipped versions."""
    try:
        text = open(APP_VERSION).read()
        m = re.search(r"MARKETING_VERSION\s*=\s*([\d.]+)", text)
        return m.group(1) if m else None
    except Exception:
        return None


def compute_weapon_medians(cards, estimates):
    """Median estimate per weapon (matches audit #1 exactly so history
    rows are comparable to the audit's printed table). Excludes weapons
    with fewer than 5 estimates (small-sample noise)."""
    by_weapon = defaultdict(list)
    for c in cards:
        bid = c.get("bobaId")
        if bid not in estimates:
            continue
        w = c.get("element") or "NONE"
        mid = estimates[bid].get("mid", 0)
        if mid > 0:
            by_weapon[w].append(mid)
    out = {}
    for w, mids in by_weapon.items():
        if len(mids) >= 5:
            out[w] = round(statistics.median(mids), 2)
    return out


def compute_printrun_medians(cards, estimates):
    """Median estimate per printRun bucket (matches audit #2)."""
    by_pr = defaultdict(list)
    for c in cards:
        bid = c.get("bobaId")
        if bid not in estimates:
            continue
        pr = c.get("printRun")
        if pr is None:
            continue
        mid = estimates[bid].get("mid", 0)
        if mid > 0:
            by_pr[pr].append(mid)
    out = {}
    for pr, mids in by_pr.items():
        if len(mids) >= 5:
            out[f"/{pr}"] = round(statistics.median(mids), 2)
    return out


def compute_basis_breakdown(estimates):
    """Count estimates by which fallback path produced them. Useful for
    tracking: as tracker data accrues, rarity-extrapolated and weapon-
    extrapolated counts should SHRINK and direct-comp should GROW."""
    counts = {
        "direct_comp": 0,
        "wide_gap_fallback": 0,
        "weapon_extrapolated_tier4": 0,
        "rarity_extrapolated_super": 0,
        "sealed_direct": 0,
        "other": 0,
    }
    for e in estimates.values():
        basis = (e.get("basis") or "").lower()
        if "wide-gap fallback" in basis:
            counts["wide_gap_fallback"] += 1
        elif "cross-weapon" in basis:
            counts["weapon_extrapolated_tier4"] += 1
        elif "no super tracker" in basis or "rarity-extrapolated" in basis and "treatment comps" in basis:
            counts["rarity_extrapolated_super"] += 1
        elif "sealed product" in basis:
            counts["sealed_direct"] += 1
        elif "closest comparable cards" in basis:
            counts["direct_comp"] += 1
        else:
            counts["other"] += 1
    return counts


def build_row():
    """Build the full daily-history row dict."""
    today = datetime.date.today().isoformat()
    cards = json.load(open(CATALOG))
    est_doc = json.load(open(ESTIMATES))
    estimates = est_doc.get("estimates", {})
    audit = json.load(open(AUDIT))

    wpn_ord = audit.get("weapon_tier_ordering") or {}
    pr_ord = audit.get("print_run_ordering") or {}

    weapon_violations = len(wpn_ord.get("violations") or [])
    printrun_violations = len(pr_ord.get("violations") or [])

    coverage_rows = audit.get("coverage_by_weapon") or []
    # coverage_pct is in PERCENT (e.g. 65.7), not ratio; tier is None for
    # ALT/CYBER/NONE which we exclude (not in the rarity model's ordinal
    # ladder, so coverage isn't comparable).
    low_coverage = [
        r["weapon"] for r in coverage_rows
        if r.get("tier") is not None
        and r.get("coverage_pct", 100.0) < 80.0
    ]

    row = {
        "date": today,
        "generatedAt": est_doc.get("generatedAt"),
        "buildVersion": extract_app_version(),
        "coverage": {
            "total": len(cards),
            "estimated": len(estimates),
            "pct": round(len(estimates) / max(1, len(cards)), 4),
        },
        "audit_counts": {
            "weapon_tier_violations": weapon_violations,
            "printrun_violations": printrun_violations,
            "hero_ladder_inversions": len(audit.get("same_hero_rarity_inversions") or []),
            "low_coverage_weapons": low_coverage,
            "suspect_low": len(audit.get("suspect_low") or []),
            "suspect_high": len(audit.get("suspect_high") or []),
            "missing_in_covered_clusters": len(audit.get("missing_in_covered_clusters") or []),
            "cluster_outliers": len(audit.get("cluster_outliers") or []),
            "outlier_rich_clusters": len(audit.get("outlier_rich_clusters") or []),
            "two_plus_flagged": len(audit.get("top_priorities") or []),
        },
        "weapon_medians": compute_weapon_medians(cards, estimates),
        "printrun_medians": compute_printrun_medians(cards, estimates),
        "basis_breakdown": compute_basis_breakdown(estimates),
        "config_snapshot": extract_config_snapshot(),
    }
    return row


def load_history():
    fresh = {"_doc": "Daily pricing-audit history. One row per day. "
                     "Append-only except for same-day re-runs which "
                     "REPLACE the latest row. Feed for "
                     "scripts/calibrate_estimator.py.",
             "rows": []}
    if not os.path.exists(HISTORY):
        return fresh
    try:
        return json.load(open(HISTORY))
    except (json.JSONDecodeError, ValueError) as e:
        # Defensive: if the file is corrupt for ANY reason (rebase
        # conflict markers, disk hiccup, half-written interrupted
        # run), don't crash the cron. Log a warning, start fresh.
        # The previous row is lost but the next row carries the same
        # info shape — calibration just loses one day of trend.
        # Better than the alternative of failing every cron until
        # someone manually fixes the file (the exact failure mode
        # that broke 2026-05-30 run 26678971378).
        print(f"⚠ history file at {HISTORY} is corrupt ({e}); starting fresh. "
              f"The corrupt file will be overwritten by this run.",
              file=sys.stderr)
        return fresh


def append_row(history, row, keep_days=180):
    """Append today's row, REPLACING any existing same-date row. Trim
    rows older than `keep_days` so the file stays small + diff-friendly
    even after years of runs. (180 days = ~6 months of trend data — far
    more than enough for the calibration window.)"""
    rows = [r for r in history.get("rows", []) if r.get("date") != row["date"]]
    rows.append(row)
    rows.sort(key=lambda r: r.get("date") or "")
    cutoff = (datetime.date.today() - datetime.timedelta(days=keep_days)).isoformat()
    rows = [r for r in rows if (r.get("date") or "") >= cutoff]
    history["rows"] = rows
    return history


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--print", action="store_true",
                    help="pretty-print the new row to stdout before writing")
    ap.add_argument("--keep-days", type=int, default=180,
                    help="trim rows older than this (default 180)")
    args = ap.parse_args()

    row = build_row()
    history = load_history()
    history = append_row(history, row, keep_days=args.keep_days)

    if args.print:
        print(json.dumps(row, indent=2))
        print()
        print(f"History size: {len(history['rows'])} rows "
              f"(from {history['rows'][0]['date']} to {history['rows'][-1]['date']})")

    with open(HISTORY, "w") as f:
        json.dump(history, f, indent=2)
        f.write("\n")
    print(f"Wrote {HISTORY} — {len(history['rows'])} rows", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
