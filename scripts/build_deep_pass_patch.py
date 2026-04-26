#!/usr/bin/env python3
"""Strict aggregator for the deep OCR pass.

Multi-pass OCR is noisy on stylized BoBA art — the same card can
produce a 5-way vote across powers (Switchblade printed 130 produced
votes [110:5, 130:2, 151:5, 181:2, 81:2] across 30+ preprocessing
variants). Naive majority vote produces false positives.

Conservative rules for auto-patching:

  1. Apply LEADING-DIGIT-DROP filter to the vote tally — if power N
     and 1N both got votes, treat N's votes as drops of 1N and add
     them to 1N's tally (the digit-drop bug doesn't reflect a real
     reading; it's the same observation with a missing leading 1).

  2. Compute "consensus power" = the value with the most votes after
     the drop filter.

  3. Auto-patch only when ALL of:
       - consensus has ≥ 70% of total post-filter votes
       - consensus differs from the row's catalog power
       - |consensus - catalog| ≤ 25 (small canonical step)
       - votes ≥ 4 (need enough evidence)

Anything else → manual review queue.

Usage:
  python3 scripts/build_deep_pass_patch.py \
    --deep /tmp/deep-pass-full.json \
    --out-dir handoff-updates-2026-04-26/deep-pass
"""

from __future__ import annotations

import argparse
import base64
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESEARCH = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"
)
THUMBS = RESEARCH / "unified-cards/thumbs"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--deep", required=True, type=Path)
    ap.add_argument("--out-dir", required=True, type=Path)
    ap.add_argument("--catalog", type=Path,
                    default=ROOT / "BOBAPlaybook/display-cards.json")
    ap.add_argument("--min-share",  type=float, default=0.70)
    ap.add_argument("--max-delta",  type=int,   default=25)
    ap.add_argument("--min-votes",  type=int,   default=4)
    args = ap.parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    deep = json.loads(args.deep.read_text())
    catalog = json.loads(args.catalog.read_text())
    by_bid = {c["bobaId"]: c for c in catalog if c.get("bobaId")}

    auto_patch = []   # confident enough to patch
    review = []       # manual review needed
    confirmed_ok = [] # deep OCR consensus matches catalog

    for r in deep["results"]:
        bid = r["bobaId"]
        c = by_bid.get(bid)
        if c is None:
            continue
        cat_p = c.get("power")
        votes = {int(k): v for k, v in r.get("votes", {}).items()}
        if not votes:
            review.append({"bobaId": bid, "reason": "no_votes",
                           "catalogPower": cat_p,
                           "candidates": r.get("allCandidates", [])})
            continue

        # Leading-digit-drop merge: any 2-digit value N whose 100+N is
        # also in the votes is treated as a partial read of 100+N.
        # Move N's vote count onto 100+N.
        merged = dict(votes)
        for v in list(merged.keys()):
            if 55 <= v <= 99 and (100 + v) in merged:
                merged[100 + v] += merged.pop(v, 0)

        total = sum(merged.values())
        if total < args.min_votes:
            review.append({"bobaId": bid, "reason": "insufficient_votes",
                           "catalogPower": cat_p, "votes": votes,
                           "candidates": r.get("allCandidates", [])})
            continue
        # Top consensus
        top_p, top_v = max(merged.items(), key=lambda kv: kv[1])
        share = top_v / total
        if share < args.min_share:
            review.append({"bobaId": bid, "reason": "consensus_too_weak",
                           "catalogPower": cat_p, "votes": votes,
                           "consensus": top_p, "share": round(share, 3),
                           "candidates": r.get("allCandidates", [])})
            continue
        if top_p == cat_p:
            confirmed_ok.append({"bobaId": bid, "power": cat_p,
                                  "consensus": top_p, "share": round(share, 3)})
            continue
        delta = abs(top_p - cat_p)
        if delta > args.max_delta:
            review.append({"bobaId": bid, "reason": "delta_too_large",
                           "catalogPower": cat_p, "votes": votes,
                           "consensus": top_p, "delta": delta,
                           "candidates": r.get("allCandidates", [])})
            continue
        auto_patch.append({
            "old_bobaId": bid,
            "changes": {"power": top_p},
            "reason": (f"Deep-pass consensus {top_p} (catalog had {cat_p}); "
                       f"share {share:.0%}, votes {merged}"),
        })

    print(f"Auto-patch (strict consensus): {len(auto_patch)}")
    print(f"Confirmed catalog already correct: {len(confirmed_ok)}")
    print(f"Manual review needed:              {len(review)}")

    # Patch JSON
    (args.out_dir / "patch.json").write_text(json.dumps(
        {"modify": auto_patch, "stats": {
            "total_inspected": len(deep["results"]),
            "auto_patched": len(auto_patch),
            "confirmed_ok": len(confirmed_ok),
            "manual_review": len(review),
            "min_share": args.min_share,
            "max_delta": args.max_delta,
            "min_votes": args.min_votes,
        }},
        indent=2, ensure_ascii=False,
    ))
    print(f"Wrote {args.out_dir / 'patch.json'}")

    (args.out_dir / "confirmed_ok.json").write_text(json.dumps(
        confirmed_ok, indent=2, ensure_ascii=False,
    ))
    (args.out_dir / "manual_review.json").write_text(json.dumps(
        review, indent=2, ensure_ascii=False,
    ))
    print(f"Wrote manual_review.json ({len(review)} rows)")

    # Build a tiny HTML viewer that embeds each manual-review row's
    # thumbnail inline (data: URI) so the operator can scroll and decide
    # without needing R2 access. One file, scrollable, no external deps.
    rows = []
    rows.append(
        "<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<title>BoBA manual review queue</title>"
        "<style>body{font-family:system-ui;background:#080810;color:#eee;"
        "margin:0;padding:24px;}h1{margin:0 0 16px}h2{margin:32px 0 8px;"
        "font-size:14px;color:#FF4D00;text-transform:uppercase;}"
        ".card{display:flex;gap:24px;padding:16px;margin:8px 0;"
        "background:#0D0D1A;border:1px solid #222;border-radius:8px;}"
        ".card img{width:200px;height:auto;border-radius:6px;}"
        ".meta{flex:1;font-family:'Chakra Petch',monospace;font-size:13px;}"
        ".bid{color:#00F5FF;}"
        ".cat{color:#FFD166;}"
        ".guess{color:#FF4D00;}"
        ".reason{color:#888;font-size:11px;margin-top:8px;}"
        "</style></head><body>"
        f"<h1>Manual Review Queue — {len(review)} rows</h1>"
        "<p>Each row's catalog metadata vs OCR vote breakdown. Compare "
        "against the printed art to decide. No automated changes from "
        "this list — operator's call.</p>"
    )
    # Group by reason for easier walking.
    by_reason: dict = {}
    for r in review:
        by_reason.setdefault(r.get("reason", "?"), []).append(r)
    for reason, group in sorted(by_reason.items(), key=lambda kv: -len(kv[1])):
        rows.append(f"<h2>{reason} — {len(group)} rows</h2>")
        for r in group[:200]:
            bid = r["bobaId"]
            cat = r.get("catalogPower")
            consensus = r.get("consensus")
            share = r.get("share")
            votes = r.get("votes", {})
            cands = r.get("candidates", [])
            c = by_bid.get(bid)
            if c is None: continue
            slug = c.get("imageFile") or ""
            img_path = THUMBS / slug if slug else None
            img_tag = ""
            if img_path and img_path.exists():
                b64 = base64.b64encode(img_path.read_bytes()).decode()
                img_tag = f"<img src='data:image/webp;base64,{b64}'>"
            rows.append(
                "<div class='card'>"
                f"{img_tag}"
                "<div class='meta'>"
                f"<div class='bid'>{bid}</div>"
                f"<div class='cat'>catalog power: {cat}</div>"
                + (f"<div class='guess'>OCR consensus: {consensus} ({share:.0%} share)</div>" if (consensus is not None and share is not None) else "")
                + f"<div>votes: {votes}</div>"
                + f"<div class='reason'>candidates: {cands[:6]}</div>"
                + f"<div class='reason'>reason flagged: {r.get('reason')}</div>"
                "</div></div>"
            )
    rows.append("</body></html>")
    html_path = args.out_dir / "manual_review.html"
    html_path.write_text("\n".join(rows))
    print(f"Wrote {html_path} (open in a browser to scroll through)")


if __name__ == "__main__":
    main()
