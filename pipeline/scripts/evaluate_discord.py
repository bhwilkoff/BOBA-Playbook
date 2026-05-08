#!/usr/bin/env python3
"""
evaluate_discord.py — LOCAL-ONLY one-shot Discord-export evaluator.

Walks DiscordChatExporter --media dumps, runs the same `cardreckon`
recognition CLI the GH Actions Stage B pipeline uses, and applies the
strict score-only gates (Path 2) from stage_b_recognize.py classify().
Outputs a local report — no R2 upload, no Supabase writes.

Spot-check the report. For winners that look right, ship them through
the existing Stage C path manually (or extend this with a --commit
mode later).

GATES (mirroring stage_b_recognize.py THRESHOLDS):
  - crop.method == 'vision_rect'  (slabs / uncropped fall-throughs out)
  - score >= 4.5
  - margin >= 0.5  (gap to next-different-hero)
  - second_margin >= 0.5  (gap to runner-up of any kind)
  - recognized_boba_id NOT in cards.json have-art set

USAGE
─────
  # 1. Build cardreckon if needed:
  cd pipeline/recognition/CardRecognitionCLI && swift build -c release && cd -

  # 2. Run:
  python pipeline/scripts/evaluate_discord.py \\
      --exports-dir "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research/discord-exports" \\
      --output-dir  pipeline/eval/discord-2026-05-08

  # 3. Open pipeline/eval/discord-2026-05-08/review.html
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[2]

DEFAULT_EXPORTS_DIR = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/"
    "Bo Jackson Battle Arena Research/discord-exports"
)
DEFAULT_CARDREKON   = REPO_ROOT / "pipeline/recognition/CardRecognitionCLI/.build/release/cardreckon"
DEFAULT_CARDS_JSON  = REPO_ROOT / "BOBAPlaybook/display-cards.json"
DEFAULT_FP_BIN      = REPO_ROOT / "BOBAPlaybook/feature-prints.bin"

IMG_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}  # CGImageSourceCreateWithURL handles HEIC natively on macOS
MIN_BYTES = 50_000
MAX_BYTES = 12_000_000

THRESHOLDS = {
    "auto_score":         4.5,
    "auto_margin":        0.5,
    "auto_second_margin": 0.5,
}


# ─── Helpers ──────────────────────────────────────────────────────────────

def short_id(p: Path) -> str:
    """Stable short id derived from the absolute path so re-runs match."""
    return hashlib.md5(str(p).encode()).hexdigest()[:16]


def collect_images(exports_dir: Path) -> list[Path]:
    out: list[Path] = []
    for sub in exports_dir.glob("*_Files"):
        if not sub.is_dir():
            continue
        for f in sub.iterdir():
            if not f.is_file():
                continue
            if f.suffix.lower() not in IMG_EXTENSIONS:
                continue
            try:
                sz = f.stat().st_size
            except OSError:
                continue
            if sz < MIN_BYTES or sz > MAX_BYTES:
                continue
            out.append(f)
    return out


def load_have_art(cards_json: Path) -> set[str]:
    """All bobaIds already shipped (imageAvailable=true)."""
    data = json.loads(cards_json.read_text())
    have: set[str] = set()
    for c in data:
        if c.get("imageAvailable") and c.get("bobaId"):
            have.add(c["bobaId"])
    return have


def hero_of(boba_id: str) -> str:
    """bobaId formula: cardNumber-hero-treatment-variation. Hero is field 2."""
    parts = boba_id.split("-", 3)  # split into 4
    return parts[1] if len(parts) >= 2 else ""


def classify(result: dict, have_art: set[str]) -> tuple[bool, str]:
    """Return (passes_auto, reason) for a recognition result."""
    if result.get("error"):
        return False, f"error: {result['error']}"
    score = result.get("score")
    recognized = result.get("recognized_boba_id")
    if score is None or recognized is None:
        return False, "no recognition"

    crop = result.get("crop") or {}
    crop_method = crop.get("method")
    if crop_method != "vision_rect":
        return False, f"crop_method={crop_method}"

    if score < THRESHOLDS["auto_score"]:
        return False, f"score={score:.2f} < 4.5"

    margin = result.get("margin")
    if margin is not None and margin < THRESHOLDS["auto_margin"]:
        return False, f"margin={margin:.2f} < 0.5"

    top = result.get("top_candidates") or []
    second_margin = None
    if len(top) >= 2:
        second_margin = (top[0].get("score") or 0) - (top[1].get("score") or 0)
    if second_margin is not None and second_margin < THRESHOLDS["auto_second_margin"]:
        return False, f"second_margin={second_margin:.2f} < 0.5"

    if recognized in have_art:
        return False, f"already imaged ({recognized})"

    return True, "AUTO"


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--exports-dir", default=str(DEFAULT_EXPORTS_DIR))
    ap.add_argument("--cardreckon",   default=str(DEFAULT_CARDREKON))
    ap.add_argument("--cards-json",   default=str(DEFAULT_CARDS_JSON))
    ap.add_argument("--feature-prints", default=str(DEFAULT_FP_BIN))
    ap.add_argument("--output-dir",   required=True,
                    help="Where to write the evaluation report")
    ap.add_argument("--limit", type=int, default=None,
                    help="Process at most N images (testing)")
    args = ap.parse_args()

    exports_dir = Path(args.exports_dir).expanduser()
    cardreckon  = Path(args.cardreckon).expanduser()
    cards_json  = Path(args.cards_json).expanduser()
    fp_bin      = Path(args.feature_prints).expanduser()
    out_dir     = Path(args.output_dir).expanduser()

    for p, label in [(exports_dir, "exports"), (cardreckon, "cardreckon"),
                     (cards_json, "cards-json"), (fp_bin, "feature-prints")]:
        if not p.exists():
            print(f"!! {label} not found: {p}", file=sys.stderr)
            sys.exit(2)

    out_dir.mkdir(parents=True, exist_ok=True)
    crops_dir = out_dir / "crops"
    crops_dir.mkdir(exist_ok=True)

    # ─── Collect ──
    print(f"scanning {exports_dir} …")
    imgs = collect_images(exports_dir)
    print(f"  image files (filtered): {len(imgs):,}")
    if args.limit:
        imgs = imgs[:args.limit]
        print(f"  --limit cap:            {len(imgs):,}")

    have_art = load_have_art(cards_json)
    print(f"  cards.json have-art:    {len(have_art):,}")

    # ─── Generate input JSONL for cardreckon ──
    input_path  = out_dir / "input.jsonl"
    output_path = out_dir / "output.jsonl"
    with input_path.open("w") as f:
        for p in imgs:
            f.write(json.dumps({"id": short_id(p), "image_path": str(p.resolve())}) + "\n")
    print(f"  wrote {input_path}")

    # id → source image path for later lookup
    id_to_src = {short_id(p): p for p in imgs}

    # ─── Run cardreckon ──
    print(f"\nrunning cardreckon ({len(imgs):,} images) — this is the slow step")
    t0 = time.time()
    proc = subprocess.run(
        [str(cardreckon),
         "--cards-json",     str(cards_json),
         "--feature-prints", str(fp_bin),
         "--input",          str(input_path),
         "--output",         str(output_path)],
        capture_output=True, text=True,
    )
    dt = time.time() - t0
    print(f"  cardreckon exit={proc.returncode} in {dt/60:.1f} min")
    if proc.stderr.strip():
        # Only show stderr if non-empty (Vision occasionally warns)
        tail = proc.stderr.strip().splitlines()[-10:]
        print(f"  stderr tail:\n    " + "\n    ".join(tail))
    if proc.returncode != 0:
        print(f"!! cardreckon failed; see {output_path} for partial results", file=sys.stderr)
        sys.exit(proc.returncode)

    # ─── Parse + classify ──
    winners:  list[dict] = []
    rejected: list[dict] = []
    seen_recognized: dict[str, dict] = {}   # bobaId → best result for that bobaId

    with output_path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            r["_source"] = str(id_to_src.get(r.get("id"), ""))
            ok, reason = classify(r, have_art)
            r["_classification_reason"] = reason
            if ok:
                # Dedupe: keep the highest-scored hit per recognized_boba_id
                rid = r["recognized_boba_id"]
                cur = seen_recognized.get(rid)
                if cur is None or (r.get("score") or 0) > (cur.get("score") or 0):
                    seen_recognized[rid] = r
            else:
                rejected.append(r)

    winners = list(seen_recognized.values())

    # ─── Copy tight-crops to out_dir/crops/ ──
    print(f"\ncopying winning tight-crops to {crops_dir}")
    for w in winners:
        crop_path = ((w.get("crop") or {}).get("path") or "")
        if crop_path and Path(crop_path).is_file():
            dst = crops_dir / f"{w['recognized_boba_id']}.jpg"
            try:
                shutil.copy(crop_path, dst)
                w["_crop_local"] = str(dst.resolve())
            except Exception as e:
                w["_crop_local"] = ""
                print(f"  ! copy failed for {w['recognized_boba_id']}: {e}")

    # ─── Write reports ──
    winners.sort(key=lambda r: -(r.get("score") or 0))
    rejected.sort(key=lambda r: -(r.get("score") or 0))

    (out_dir / "winners.json").write_text(
        json.dumps(winners, indent=2, ensure_ascii=False))
    with (out_dir / "winners.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["recognized_boba_id", "score", "margin", "second_margin",
                    "source_file", "crop_local"])
        for r in winners:
            top = r.get("top_candidates") or []
            sm = (top[0].get("score") - top[1].get("score")) if len(top) >= 2 else None
            w.writerow([
                r.get("recognized_boba_id"),
                f"{r.get('score', 0):.3f}",
                f"{r.get('margin', 0):.3f}" if r.get("margin") is not None else "",
                f"{sm:.3f}" if sm is not None else "",
                r.get("_source"),
                r.get("_crop_local", ""),
            ])

    with (out_dir / "rejected.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["reason", "score", "recognized_boba_id", "source_file"])
        for r in rejected[:5000]:   # cap for inspection
            w.writerow([
                r.get("_classification_reason"),
                f"{r.get('score', 0):.3f}" if r.get("score") is not None else "",
                r.get("recognized_boba_id") or "",
                r.get("_source"),
            ])

    # HTML gallery
    html = ['<!doctype html><meta charset=utf-8>',
            '<title>Discord eval</title>',
            '<style>',
            'body{background:#0d0d1a;color:#eee;font:14px/1.4 -apple-system,sans-serif;margin:24px}',
            'h1{font:600 22px/1.2 -apple-system,sans-serif;margin:0 0 8px}',
            '.meta{color:#888;margin-bottom:24px;font-size:12px}',
            '.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px}',
            '.card{background:#13131f;border-radius:8px;padding:12px;font-size:11px}',
            '.card img{width:100%;border-radius:4px;margin-bottom:6px;background:#000}',
            '.bobaid{font:600 13px/1.2 -apple-system,sans-serif;color:#00f5ff;word-break:break-word;margin-bottom:4px}',
            '.score{color:#ffb055}',
            '.row{display:flex;gap:6px;margin-top:4px;color:#777}',
            '.src{color:#666;font-size:10px;word-break:break-all;margin-top:6px}',
            '</style>',
            f'<h1>Discord eval — {len(winners)} winners</h1>',
            f'<div class=meta>{exports_dir} · cardreckon {dt/60:.1f}min · gates: score≥4.5, margin≥0.5, second≥0.5, vision_rect, not-already-imaged</div>',
            '<div class=grid>']
    for r in winners:
        crop_rel = ""
        if r.get("_crop_local"):
            crop_rel = os.path.relpath(r["_crop_local"], out_dir)
        html.append('<div class=card>')
        if crop_rel:
            html.append(f'<img src="{crop_rel}" loading=lazy>')
        html.append(f'<div class=bobaid>{r["recognized_boba_id"]}</div>')
        margin = r.get("margin")
        top = r.get("top_candidates") or []
        sm  = (top[0].get("score") - top[1].get("score")) if len(top) >= 2 else None
        html.append(f'<div class=row><span class=score>score {r["score"]:.2f}</span>')
        if margin is not None:
            html.append(f'<span>margin {margin:.2f}</span>')
        if sm is not None:
            html.append(f'<span>2nd {sm:.2f}</span>')
        html.append('</div>')
        html.append(f'<div class=src>{Path(r["_source"]).name}</div>')
        html.append('</div>')
    html.append('</div>')
    (out_dir / "review.html").write_text("\n".join(html))

    # ─── Reason histogram ──
    from collections import Counter
    reason_summary = Counter()
    for r in rejected:
        # Bucket by leading prefix so we don't get one bucket per score
        rsn = r["_classification_reason"]
        for pref in ("error:", "no recognition", "crop_method=", "score=",
                     "margin=", "second_margin=", "already imaged"):
            if rsn.startswith(pref):
                reason_summary[pref.rstrip("=").rstrip(":").strip()] += 1
                break
        else:
            reason_summary[rsn] += 1

    summary = [
        f"=== Discord eval summary ===",
        f"  exports dir       : {exports_dir}",
        f"  images processed  : {len(imgs):,}",
        f"  cardreckon time   : {dt/60:.1f} min",
        f"  AUTO winners      : {len(winners):,}",
        f"  rejected          : {len(rejected):,}",
        f"",
        f"  rejection reasons :",
    ] + [f"    {k:24s} {v:>6,d}" for k, v in reason_summary.most_common()]
    summary_text = "\n".join(summary) + "\n"
    (out_dir / "report.txt").write_text(summary_text)
    print("\n" + summary_text)
    print(f"open {out_dir / 'review.html'}")


if __name__ == "__main__":
    main()
