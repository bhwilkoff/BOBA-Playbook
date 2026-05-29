#!/usr/bin/env python3
"""scripts/audit_estimator.py — systematic estimator audits.

Replaces Ben's manual "I notice card X is off" reports. Run after every
`build_price_estimates.py` to surface what should be investigated next.
Each audit checks a specific failure mode we've actually seen — designed
so cards that get flagged by MULTIPLE audits are the top priorities.

Outputs:
- Stdout report grouped by audit
- assets/data/price-estimates-audit.json — machine-readable summary the
  next session can diff against to see what changed after a tuning pass

Audits implemented (each captures a real failure mode this codebase has
hit, with the commit + memory that documents the lesson):

  1. Weapon-tier ordering — SUPER > HEX/GUM > GLOW > FIRE/ICE > BRAWL/STEEL
     median. Inversions = the rarity model isn't reaching the output.
     (Origin: Ben's 2026-05-29 audit — 444/454 SUPER at $4. DECISIONS.md #063.)
  ...
  8. Suspect-HIGH estimates — mirror of #5. Catches cross-treatment
     leakage UPWARD where a cheap Base Set common got chase-tier
     pricing. (Origin: paired with #5 as the symmetric check.)
  9. Outlier-rich clusters — clusters where >25% of members are >3σ
     outliers. Catches SYSTEMATIC bugs across an entire cluster.
     (Origin: pre-#064 the entire IIMBF cluster was flat $1.84 because
     the synth pool was cross-treatment poisoned — per-card outliers
     wouldn't catch this since they were all uniformly low.)

  2. Print-run ordering — /5 > /10 > /25 > /50 medians. Inversions = the
     printRun_match=10 weight isn't winning where it should.

  3. Same-hero rarity ladder — within each hero, treatments should follow
     tier ordering (Inspired Ink Superfoil > Inspired Ink > Battlefoil >
     Base). Inversions = comp pool is leaking across tiers.

  4. Coverage by weapon — % of cards per weapon that have an estimate.
     Low coverage on a rarity class = systematic skip (Super was 0% before
     the hedged-range fix, then 47%, then 99.8% after the fallback fix).

  5. Suspect-low estimates — high-rarity cards estimated under a floor.
     /5 or /1 cards under $20 = floor breach (the original Super-at-$4 bug
     was this audit, applied retroactively).

  6. Missing estimates in well-covered clusters — cards skipped when
     ≥80% of their cluster (treatment × weapon × set) has estimates.
     Surfaces single-card outliers like Palmer SFA-24 was before the
     virtualized-printRun fix (DECISIONS.md #063 amendment).

  7. Within-cluster z-score outliers — cards >3σ from same-cluster median.
     Catches single-card bugs even when the cluster average looks fine.

Run with no args: audits the current artifact.
Run with --rebuild: rebuilds artifact first, then audits.
"""

from __future__ import annotations

import json
import statistics
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CARDS_PATH = REPO / "assets" / "data" / "cards.json"
EST_PATH   = REPO / "assets" / "data" / "price-estimates.json"
RM_PATH    = REPO / "assets" / "data" / "rarity-model.json"
OUT_PATH   = REPO / "assets" / "data" / "price-estimates-audit.json"


def main() -> int:
    if "--rebuild" in sys.argv:
        print("Rebuilding price-estimates.json first…")
        subprocess.run([sys.executable, str(REPO / "scripts" / "build_price_estimates.py")],
                       check=True)
        print()

    cards = json.loads(CARDS_PATH.read_text())
    est   = json.loads(EST_PATH.read_text()).get("estimates", {})
    rm    = json.loads(RM_PATH.read_text())

    cards_by_bid = {c.get("bobaId"): c for c in cards if c.get("bobaId")}
    print(f"Catalog:   {len(cards):>6} cards")
    print(f"Estimated: {len(est):>6} cards ({100 * len(est) // len(cards)}% coverage)")
    print(f"Rarity model: {len(rm.get('weaponTier', {}))} weapon tiers, "
          f"{len(rm.get('treatments', {}))} treatments")
    print()

    report = {}
    flagged_bids = defaultdict(set)  # bobaId -> set of audit names

    def flag(audit: str, bid: str) -> None:
        flagged_bids[bid].add(audit)

    # ── 1. Weapon-tier ordering ─────────────────────────────────────
    print("── 1. WEAPON-TIER ORDERING ─" + "─" * 47)
    weapon_mids: dict[str, list[float]] = defaultdict(list)
    for c in cards:
        e = est.get(c.get("bobaId") or "")
        if not e:
            continue
        mid = e.get("mid", 0)
        if mid <= 0:
            continue
        if w := c.get("element"):
            weapon_mids[w].append(mid)

    ordinals = {w: t["ordinal"] for w, t in rm.get("weaponTier", {}).items()}
    ordered = sorted(weapon_mids, key=lambda w: -ordinals.get(w, 0))
    weapon_summary = []
    for w in ordered:
        med = statistics.median(weapon_mids[w])
        weapon_summary.append({"weapon": w, "tier": ordinals.get(w), "n": len(weapon_mids[w]), "median": round(med, 2)})
        print(f"  {w:>5} (tier {ordinals.get(w, '?'):>1}): n={len(weapon_mids[w]):>5}  median=${med:>8.2f}")
    violations = []
    for a in weapon_mids:
        for b in weapon_mids:
            if ordinals.get(a, 0) > ordinals.get(b, 0):
                ma = statistics.median(weapon_mids[a])
                mb = statistics.median(weapon_mids[b])
                if ma < mb:
                    violations.append({"higher_tier": a, "lower_tier": b,
                                       "higher_median": round(ma, 2),
                                       "lower_median": round(mb, 2)})
    if violations:
        print(f"  ⚠ {len(violations)} ordering violations:")
        for v in violations[:5]:
            print(f"    {v['higher_tier']} (med ${v['higher_median']}) < "
                  f"{v['lower_tier']} (med ${v['lower_median']}) — should be >")
    else:
        print("  ✓ no violations")
    report["weapon_tier_ordering"] = {"summary": weapon_summary, "violations": violations}
    print()

    # ── 2. Print-run ordering ───────────────────────────────────────
    print("── 2. PRINT-RUN ORDERING ─" + "─" * 49)
    pr_mids: dict[int, list[float]] = defaultdict(list)
    for c in cards:
        e = est.get(c.get("bobaId") or "")
        if not e:
            continue
        mid = e.get("mid", 0)
        if mid <= 0:
            continue
        pr = c.get("printRun")
        if pr is not None:
            pr_mids[pr].append(mid)
    pr_summary = []
    for pr in sorted(pr_mids):
        med = statistics.median(pr_mids[pr])
        pr_summary.append({"printRun": pr, "n": len(pr_mids[pr]), "median": round(med, 2)})
        print(f"  /{pr:<2}: n={len(pr_mids[pr]):>5}  median=${med:>8.2f}")
    pr_violations = []
    prs = sorted(pr_mids.keys())
    for i in range(len(prs) - 1):
        a, b = prs[i], prs[i + 1]
        ma = statistics.median(pr_mids[a])
        mb = statistics.median(pr_mids[b])
        if ma < mb:
            pr_violations.append({"lower_pr": a, "higher_pr": b,
                                  "lower_median": round(ma, 2),
                                  "higher_median": round(mb, 2)})
            print(f"  ⚠ /{a} (med ${ma:.2f}) < /{b} (med ${mb:.2f}) — should be >")
    if not pr_violations:
        print("  ✓ no violations")
    report["print_run_ordering"] = {"summary": pr_summary, "violations": pr_violations}
    print()

    # ── 3. Same-hero rarity ladder ──────────────────────────────────
    print("── 3. SAME-HERO RARITY LADDER ─" + "─" * 44)

    def treatment_tier(t):
        tl = (t or "").lower()
        if "inspired ink superfoil" in tl: return 6
        if "superfoil" in tl: return 5
        if "inspired ink" in tl: return 4
        if "kanji" in tl: return 4
        if "blizzard" in tl: return 3
        if "battlefoil" in tl or "logofoil" in tl: return 2
        if "blast" in tl or "paper" in tl: return 1
        return 0

    hero_treats: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    for c in cards:
        e = est.get(c.get("bobaId") or "")
        if not e:
            continue
        mid = e.get("mid", 0)
        if mid <= 0:
            continue
        if (h := c.get("hero")) and (t := c.get("treatment")):
            hero_treats[h][t].append(mid)

    inversions = []
    for hero, treats in hero_treats.items():
        if len(treats) < 2:
            continue
        tier_meds = sorted([(treatment_tier(t), t, statistics.median(ms))
                            for t, ms in treats.items()])
        for i in range(len(tier_meds) - 1):
            ta, na, ma = tier_meds[i]
            tb, nb, mb = tier_meds[i + 1]
            if ta < tb and ma > mb * 1.5:  # lower tier shouldn't be 1.5× higher tier
                inversions.append({"hero": hero, "lower_tier": na, "higher_tier": nb,
                                   "lower_median": round(ma, 2),
                                   "higher_median": round(mb, 2)})
    if inversions:
        print(f"  ⚠ {len(inversions)} hero-tier inversions (lower-tier > 1.5× higher-tier)")
        for v in inversions[:10]:
            print(f"    {v['hero']}: '{v['lower_tier']}' ${v['lower_median']} > "
                  f"'{v['higher_tier']}' ${v['higher_median']}")
    else:
        print("  ✓ no inversions (>1.5× threshold)")
    report["same_hero_rarity_inversions"] = inversions[:50]
    print()

    # ── 4. Coverage by weapon ───────────────────────────────────────
    print("── 4. COVERAGE BY WEAPON ─" + "─" * 49)
    coverage = []
    for w in sorted(set(c.get("element") for c in cards if c.get("element")),
                    key=lambda w: -ordinals.get(w, 0)):
        in_cat = [c for c in cards if c.get("element") == w]
        with_est = sum(1 for c in in_cat if est.get(c.get("bobaId") or ""))
        pct = 100 * with_est / len(in_cat) if in_cat else 0
        coverage.append({"weapon": w, "tier": ordinals.get(w), "in_catalog": len(in_cat),
                         "with_estimate": with_est, "coverage_pct": round(pct, 1)})
        warn = " ⚠" if pct < 80 else ""
        print(f"  {w:>5} (tier {ordinals.get(w, '?'):>1}): {with_est:>5} / {len(in_cat):>5} "
              f"({pct:>5.1f}%){warn}")
    report["coverage_by_weapon"] = coverage
    print()

    # ── 5. Suspect-low estimates ────────────────────────────────────
    print("── 5. SUSPECT-LOW ESTIMATES ─" + "─" * 46)
    print("  high-rarity cards under floor — likely tier-leak bugs")
    floors = {"SUPER": 30, "HEX": 15, "GUM": 15, "GLOW": 10}
    pr_floors = {1: 30, 5: 25, 10: 15, 25: 10, 50: 8}
    suspects = []
    for c in cards:
        e = est.get(c.get("bobaId") or "")
        if not e:
            continue
        mid = e.get("mid", 0)
        if mid <= 0:
            continue
        w = c.get("element")
        pr = c.get("printRun")
        treatment = (c.get("treatment") or "").lower()
        floor = floors.get(w, 0)
        if pr in pr_floors:
            floor = max(floor, pr_floors[pr])
        if "inspired ink" in treatment:
            floor = max(floor, 20)
        if floor and mid < floor:
            suspects.append({"bobaId": c.get("bobaId"), "mid": mid, "floor": floor,
                             "weapon": w, "printRun": pr, "treatment": c.get("treatment")})
            flag("suspect_low", c.get("bobaId"))
    suspects.sort(key=lambda s: s["mid"])
    print(f"  {len(suspects)} suspect-low estimates")
    for s in suspects[:10]:
        print(f"    ${s['mid']:>7.2f} (floor ${s['floor']})  pr={s['printRun']!r:<5} "
              f"w={s['weapon']!r:<7} t={s['treatment']!r}")
        print(f"      {s['bobaId']}")
    report["suspect_low"] = suspects[:200]
    print()

    # ── 6. Missing in well-covered clusters ─────────────────────────
    print("── 6. MISSING ESTIMATES IN ≥80%-COVERED CLUSTERS ─" + "─" * 25)
    clusters: dict[tuple, list[dict]] = defaultdict(list)
    for c in cards:
        clusters[(c.get("treatment"), c.get("element"), c.get("set"))].append(c)
    missing = []
    for key, group in clusters.items():
        if len(group) < 5:
            continue
        with_est = [c for c in group if est.get(c.get("bobaId") or "")]
        if not with_est:
            continue
        coverage_pct = len(with_est) / len(group)
        if coverage_pct >= 0.8:
            for c in group:
                if not est.get(c.get("bobaId") or ""):
                    missing.append({"coverage": round(coverage_pct, 2),
                                    "cluster": list(key),
                                    "bobaId": c.get("bobaId")})
                    flag("missing_in_covered_cluster", c.get("bobaId"))
    missing.sort(key=lambda m: -m["coverage"])
    print(f"  {len(missing)} cards skipped despite ≥80% cluster coverage")
    for m in missing[:15]:
        print(f"    coverage={m['coverage']:.0%}  cluster={m['cluster']}")
        print(f"      {m['bobaId']}")
    report["missing_in_covered_clusters"] = missing[:200]
    print()

    # ── 7. Within-cluster z-score outliers ──────────────────────────
    print("── 7. WITHIN-CLUSTER OUTLIERS (>3σ FROM CLUSTER MEDIAN) ─" + "─" * 17)
    outliers = []
    for key, group in clusters.items():
        mids = [est[c["bobaId"]]["mid"] for c in group
                if est.get(c.get("bobaId") or "") and est[c["bobaId"]].get("mid", 0) > 0]
        if len(mids) < 5:
            continue
        med = statistics.median(mids)
        sd = statistics.stdev(mids) if len(mids) > 1 else 0
        if sd == 0:
            continue
        for c in group:
            e = est.get(c.get("bobaId") or "")
            if not e:
                continue
            mid = e.get("mid", 0)
            if mid <= 0:
                continue
            z = abs(mid - med) / sd
            if z > 3:
                outliers.append({"z": round(z, 2), "mid": mid, "cluster_median": round(med, 2),
                                 "cluster": list(key), "bobaId": c.get("bobaId")})
                flag("cluster_outlier", c.get("bobaId"))
    outliers.sort(key=lambda o: -o["z"])
    print(f"  {len(outliers)} outliers (>3σ from same-cluster median)")
    for o in outliers[:10]:
        print(f"    ${o['mid']:>8.2f}  (cluster med ${o['cluster_median']}, z={o['z']:.1f})")
        print(f"      {o['bobaId']}")
    report["cluster_outliers"] = outliers[:200]
    print()

    # ── 8. Suspect-HIGH estimates ───────────────────────────────────
    # Mirror of #5 — low-rarity cards priced as if chase. Catches the
    # opposite failure mode: cross-treatment leakage UPWARD where a
    # cheap Base Set common gets a chase-tier estimate because a
    # cross-treatment peer (Inspired Ink chase $300+) dominated its
    # comp pool. The strict-treatment gate (#064) prevents most of
    # these going forward but pre-fix runs (or future scoring tweaks)
    # may re-introduce the pattern — this audit surfaces it.
    print("── 8. SUSPECT-HIGH ESTIMATES ─" + "─" * 45)
    print("  low-rarity cards above ceiling — likely cross-treatment leakage upward")
    # Tight ceilings only for cards that genuinely shouldn't be expensive:
    #   Base Set commons    → $50 across all weapons (cheapest treatment)
    #   tier-1 non-Base BRAWL/STEEL (Battlefoils etc.) → $300 (common tier;
    #     above this likely chase-leakage from cross-treatment match)
    # Tier-2+ weapons / tier-2+ treatments have no ceiling here — they have
    # legitimate chase pricing.
    suspects_high = []
    for c in cards:
        e = est.get(c.get("bobaId") or "")
        if not e:
            continue
        mid = e.get("mid", 0)
        if mid <= 0:
            continue
        w = c.get("element")
        treatment = c.get("treatment") or ""
        treatment_t = treatment_tier(treatment)
        if treatment == "Base Set":
            ceiling = 50
        elif (treatment_t == 1) and w in ("STEEL", "BRAWL"):
            ceiling = 300
        else:
            ceiling = 0
        if ceiling and mid > ceiling:
            suspects_high.append({"bobaId": c.get("bobaId"), "mid": mid,
                                  "ceiling": ceiling, "weapon": w,
                                  "treatment": treatment})
            flag("suspect_high", c.get("bobaId"))
    suspects_high.sort(key=lambda s: -s["mid"])
    print(f"  {len(suspects_high)} suspect-high estimates")
    for s in suspects_high[:10]:
        print(f"    ${s['mid']:>8.2f} (ceiling ${s['ceiling']})  "
              f"w={s['weapon']!r:<7} t={s['treatment']!r}")
        print(f"      {s['bobaId']}")
    report["suspect_high"] = suspects_high[:200]
    print()

    # ── 9. Outlier-rich clusters ────────────────────────────────────
    # Cluster-level pattern detection — better than per-card outliers
    # (#7) for catching SYSTEMATIC bugs. When >25% of a cluster's
    # cards are >3σ outliers from the cluster's own median, the
    # cluster median itself is probably wrong (the cluster is split
    # across two real markets that the estimator is averaging).
    # Pre-#064 the entire IIMBF cluster fit this — every estimate at
    # $1.84 because the synth pool was cross-treatment poisoned.
    print("── 9. OUTLIER-RICH CLUSTERS (>25% of members are >3σ outliers) ─" + "─" * 9)
    rich_clusters = []
    for key, group in clusters.items():
        mids = [est[c["bobaId"]]["mid"] for c in group
                if est.get(c.get("bobaId") or "") and est[c["bobaId"]].get("mid", 0) > 0]
        if len(mids) < 10:
            continue
        med = statistics.median(mids)
        sd = statistics.stdev(mids)
        if sd == 0:
            continue
        n_outliers = sum(1 for m in mids if abs(m - med) / sd > 3)
        ratio = n_outliers / len(mids)
        if ratio > 0.25:
            rich_clusters.append({
                "cluster": list(key),
                "n": len(mids),
                "median": round(med, 2),
                "outlier_pct": round(ratio * 100, 1),
                "n_outliers": n_outliers,
            })
            # Flag every card in the cluster (cluster-level bug)
            for c in group:
                if est.get(c.get("bobaId") or ""):
                    flag("outlier_rich_cluster", c.get("bobaId"))
    rich_clusters.sort(key=lambda r: -r["outlier_pct"])
    print(f"  {len(rich_clusters)} outlier-rich clusters")
    for r in rich_clusters[:10]:
        print(f"    {r['outlier_pct']:>5.1f}% outliers  n={r['n']:<4}  "
              f"median=${r['median']:<8}  {r['cluster']}")
    report["outlier_rich_clusters"] = rich_clusters[:50]
    print()

    # ── Cross-audit priority list ───────────────────────────────────
    print("── TOP INVESTIGATION PRIORITIES (FLAGGED BY MULTIPLE AUDITS) ─" + "─" * 11)
    multi = [(len(audits), bid, sorted(audits)) for bid, audits in flagged_bids.items()
             if len(audits) > 1]
    multi.sort(reverse=True)
    print(f"  {len(multi)} cards flagged by 2+ audits")
    for n, bid, audits in multi[:20]:
        e = est.get(bid, {})
        print(f"    [{n} flags: {', '.join(audits)}]  ${e.get('mid', 0):.2f}  {bid}")
    report["top_priorities"] = [
        {"flags_count": n, "audits": audits, "bobaId": bid,
         "mid": est.get(bid, {}).get("mid")}
        for n, bid, audits in multi[:100]
    ]
    print()

    OUT_PATH.write_text(json.dumps(report, indent=2))
    print(f"Wrote machine-readable report to {OUT_PATH.relative_to(REPO)}")
    print()
    print("Cards flagged by 2+ audits are the highest-priority investigations.")
    print("After fixing the underlying bug + rebuilding the artifact, re-run")
    print("this audit and compare against the previous report to verify the")
    print("fix didn't introduce regressions elsewhere.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
