#!/usr/bin/env python3
"""
calibrate_estimator.py — analyze pricing-audit-history.json and recommend
multiplier / threshold tunes to address persistent drift.

Does NOT apply changes. Outputs a human-readable report to stdout +
machine-readable recommendations to `assets/data/pricing-calibration-
recommendations.json`. The GH Action commits both alongside the rebuilt
artifact; Ben reviews recommendations periodically and tunes
`build_price_estimates.py` constants by hand.

WHY RECOMMEND-ONLY
------------------
Two reasons. (1) Calibration that auto-applies multipliers turns into a
feedback loop the moment tracker data shifts — a single noisy day could
double the multipliers, then the next day's audit shows new tier
violations, recommending another bump, etc. Human-in-the-loop breaks
the loop. (2) The right multiplier depends on canonical rarity
semantics that the script can't infer — e.g., should HEX/GUM premium
match SUPER's growth pattern, or stay capped because they're "rare" not
"one-of-one"? That's a judgement call (DECISIONS.md #063 amend 2).

RECOMMENDATION CATEGORIES
-------------------------
1. TIER ORDERING — if a higher-tier weapon median falls below a lower-
   tier weapon median for 7+ consecutive days, recommend bumping the
   higher tier's PREMIUM multipliers (or lowering the lower tier's).
2. COVERAGE — if a tier-N weapon's coverage stays below 80% for 14+
   days with no upward trend, recommend either (a) widening the strict-
   gate fallback (e.g., add weapon-extrapolated for GLOW tier 3) or
   (b) accepting the gap as honest (no tracker data → no estimate).
3. PERSISTENT-AUDIT PATTERN — if suspect-low / outliers / etc. stays
   elevated for 14+ days on the same treatment / weapon, surface for
   manual investigation.
4. PATH SHIFT — if direct_comp basis count is growing and extrapolated
   counts are shrinking, that's the GOOD direction (real data accruing).
   Reported as a positive trend, no action needed.

USAGE
-----
    python3 scripts/calibrate_estimator.py
        # print report + write recommendations JSON

    python3 scripts/calibrate_estimator.py --window-days 7
        # change trend window (default 14)

    python3 scripts/calibrate_estimator.py --quiet
        # only write JSON, no stdout (CI use)
"""

import argparse
import datetime
import json
import os
import statistics
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HISTORY = os.path.join(REPO, "assets", "data", "pricing-audit-history.json")
OUT = os.path.join(REPO, "assets", "data", "pricing-calibration-recommendations.json")


# Canonical tier ordering: higher tier should have higher median.
WEAPON_TIERS = {
    "SUPER": 5, "HEX": 4, "GUM": 4, "GLOW": 3,
    "FIRE": 2, "ICE": 2, "STEEL": 1, "BRAWL": 1,
}


def trend(values):
    """Slope of a simple linear regression over indices 0..N-1.
    Positive = upward, negative = downward. Used to detect "no
    upward trend" on coverage."""
    n = len(values)
    if n < 2:
        return 0.0
    xs = list(range(n))
    mx = sum(xs) / n
    my = sum(values) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, values))
    den = sum((x - mx) ** 2 for x in xs)
    return num / den if den else 0.0


def analyze_tier_ordering(rows, window_days):
    """Check if higher-tier weapons have been BELOW lower-tier weapons
    for `window_days` consecutive recent rows. If so, recommend a
    PREMIUM bump on the higher tier."""
    recs = []
    if len(rows) < window_days:
        return recs
    recent = rows[-window_days:]
    # For each tier pair (higher, lower), check if higher median <
    # lower median on EVERY recent row.
    for higher_w, higher_tier in WEAPON_TIERS.items():
        for lower_w, lower_tier in WEAPON_TIERS.items():
            if higher_tier <= lower_tier:
                continue
            violations = 0
            for row in recent:
                med = row.get("weapon_medians") or {}
                h, l = med.get(higher_w), med.get(lower_w)
                if h is None or l is None:
                    continue
                if h < l:
                    violations += 1
            if violations == len([
                r for r in recent
                if (r.get("weapon_medians") or {}).get(higher_w) is not None
                and (r.get("weapon_medians") or {}).get(lower_w) is not None
            ]) and violations >= window_days:
                # Persistent inversion. Recommend bumping the higher
                # tier's premium.
                med_h = (recent[-1].get("weapon_medians") or {}).get(higher_w)
                med_l = (recent[-1].get("weapon_medians") or {}).get(lower_w)
                ratio = med_l / med_h if med_h else 0
                recs.append({
                    "category": "tier_ordering_inversion",
                    "severity": "high",
                    "weapon_higher": higher_w,
                    "weapon_lower": lower_w,
                    "tier_higher": higher_tier,
                    "tier_lower": lower_tier,
                    "current_median_higher": med_h,
                    "current_median_lower": med_l,
                    "ratio": round(ratio, 2),
                    "recommendation": (
                        f"{higher_w} median (${med_h}) below {lower_w} "
                        f"median (${med_l}) for {window_days}+ days. "
                        + (f"Consider bumping SUPER_PREMIUM_MID by "
                           f"~{int((ratio - 1) * 100)}% (currently in "
                           f"build_price_estimates.py)."
                           if higher_w == "SUPER" else
                           f"Consider bumping WEAPON_TIER4_PREMIUM_MID "
                           f"by ~{int((ratio - 1) * 100)}%."
                           if higher_w in ("HEX", "GUM") else
                           "Consider extending strict-weapon to this "
                           "tier or adding a weapon-extrapolated "
                           "fallback (mirrors the tier-4 pattern in "
                           "DECISIONS.md #064 amend).")
                    ),
                })
    return recs


def analyze_coverage(rows, window_days):
    """Flag weapons whose coverage has been below 80% for `window_days`
    with no upward trend."""
    recs = []
    if len(rows) < window_days:
        return recs
    recent = rows[-window_days:]
    for w in WEAPON_TIERS:
        # Find this weapon's coverage in each row.
        covs = []
        for row in recent:
            for r in row.get("audit_counts", {}).get("low_coverage_weapons") or []:
                if r == w:
                    covs.append(0.0)  # below-80 marker
        # Persistent below-80 marker = w in low_coverage_weapons every day.
        days_below = sum(
            1 for row in recent
            if w in (row.get("audit_counts", {}).get("low_coverage_weapons") or [])
        )
        if days_below >= window_days:
            recs.append({
                "category": "persistent_low_coverage",
                "severity": "medium",
                "weapon": w,
                "tier": WEAPON_TIERS[w],
                "days_below_80": days_below,
                "recommendation": (
                    f"{w} (tier {WEAPON_TIERS[w]}) coverage <80% for "
                    f"{days_below}/{window_days} days. Either tracker "
                    f"data isn't accruing for this weapon (run "
                    f"`scripts/crawl_active_listings.py --treatments` "
                    f"with treatments where {w} appears; or "
                    f"`scripts/refresh_stale_prices.py --source whatnot`) "
                    f"OR the strict-gate is too aggressive for this "
                    f"weapon's market (consider widening fallback)."
                ),
            })
    return recs


def analyze_persistent_audit_patterns(rows, window_days):
    """Flag audit metrics that have been elevated for `window_days`."""
    recs = []
    if len(rows) < window_days:
        return recs
    recent = rows[-window_days:]
    # suspect_low > 20 every day
    sl_values = [r.get("audit_counts", {}).get("suspect_low", 0) for r in recent]
    if all(v > 20 for v in sl_values):
        recs.append({
            "category": "persistent_suspect_low",
            "severity": "medium",
            "values": sl_values,
            "recommendation": (
                f"suspect_low >20 every day for {window_days} days "
                f"(values: {sl_values}). Either the floor thresholds "
                f"in audit_estimator.py audit #5 are too generous, OR "
                f"a real tier-leak bug persists. Investigate the most "
                f"common flagged treatment+weapon."
            ),
        })
    # outlier_rich_clusters > 0 for any day
    or_values = [r.get("audit_counts", {}).get("outlier_rich_clusters", 0) for r in recent]
    if max(or_values) > 0:
        recs.append({
            "category": "outlier_rich_cluster_reappearance",
            "severity": "high",
            "values": or_values,
            "recommendation": (
                f"outlier_rich_clusters fired at least once in last "
                f"{window_days} days (max: {max(or_values)}). Cluster-"
                f"level bug — check audit JSON `outlier_rich_clusters` "
                f"field for the offending (treatment × weapon × set)."
            ),
        })
    return recs


def analyze_path_shifts(rows, window_days):
    """Compare basis_breakdown over time. If extrapolated paths shrink
    and direct_comp grows, that's the good direction — report it."""
    if len(rows) < window_days:
        return []
    recent = rows[-window_days:]
    first = recent[0].get("basis_breakdown") or {}
    last = recent[-1].get("basis_breakdown") or {}
    notes = []
    for path in ("rarity_extrapolated_super", "weapon_extrapolated_tier4",
                 "wide_gap_fallback"):
        f = first.get(path, 0)
        l = last.get(path, 0)
        if f > 0:
            delta_pct = (l - f) / f * 100
            if delta_pct < -10:
                notes.append({
                    "category": "positive_path_shift",
                    "severity": "info",
                    "path": path,
                    "from": f,
                    "to": l,
                    "delta_pct": round(delta_pct, 1),
                    "recommendation": (
                        f"{path} decreased {abs(delta_pct):.0f}% over "
                        f"{window_days} days ({f} → {l}). Real tracker "
                        f"data accruing for this class — multipliers "
                        f"will trigger less. No action needed."
                    ),
                })
            elif delta_pct > 10:
                notes.append({
                    "category": "negative_path_shift",
                    "severity": "low",
                    "path": path,
                    "from": f,
                    "to": l,
                    "delta_pct": round(delta_pct, 1),
                    "recommendation": (
                        f"{path} grew {delta_pct:.0f}% over "
                        f"{window_days} days ({f} → {l}). More cards "
                        f"falling through to extrapolated paths — may "
                        f"indicate tracker D1 lost data (vanish-inference "
                        f"running aggressively) or new catalog cards "
                        f"added without tracker coverage."
                    ),
                })
    return notes


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--window-days", type=int, default=14,
                    help="trend window (default 14)")
    ap.add_argument("--quiet", action="store_true", help="suppress stdout report")
    args = ap.parse_args()

    if not os.path.exists(HISTORY):
        msg = "No history file yet — nothing to calibrate."
        if not args.quiet:
            print(msg)
        return 0
    history = json.load(open(HISTORY))
    rows = history.get("rows") or []
    if len(rows) < args.window_days:
        msg = (f"History has {len(rows)} rows, need {args.window_days} for "
               f"calibration window. Skipping recommendations.")
        if not args.quiet:
            print(msg)
        # Still write an (empty) recommendations file so CI commits something.
        json.dump({
            "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "windowDays": args.window_days,
            "rowsAnalyzed": len(rows),
            "recommendations": [],
            "note": msg,
        }, open(OUT, "w"), indent=2)
        return 0

    recs = []
    recs.extend(analyze_tier_ordering(rows, args.window_days))
    recs.extend(analyze_coverage(rows, args.window_days))
    recs.extend(analyze_persistent_audit_patterns(rows, args.window_days))
    recs.extend(analyze_path_shifts(rows, args.window_days))

    out_doc = {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "windowDays": args.window_days,
        "rowsAnalyzed": len(rows),
        "from": rows[-args.window_days].get("date"),
        "to": rows[-1].get("date"),
        "recommendations": recs,
    }
    with open(OUT, "w") as f:
        json.dump(out_doc, f, indent=2)
        f.write("\n")

    if not args.quiet:
        print(f"Analyzed {args.window_days} days "
              f"({out_doc['from']} → {out_doc['to']})")
        print(f"Found {len(recs)} recommendations:\n")
        if not recs:
            print("  ✓ no calibration changes recommended — estimator is stable")
        else:
            by_sev = {}
            for r in recs:
                by_sev.setdefault(r["severity"], []).append(r)
            for sev in ("high", "medium", "low", "info"):
                items = by_sev.get(sev) or []
                if items:
                    print(f"  {sev.upper()} ({len(items)}):")
                    for r in items:
                        print(f"    [{r['category']}] {r['recommendation']}")
                    print()
        print(f"Wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
