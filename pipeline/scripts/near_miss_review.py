#!/usr/bin/env python3
"""
near_miss_review.py — interactive manual-sweep HTML for evaluate_discord
output. Surfaces candidates that scored 3.4–4.5 (just below the AUTO
gate) AND whose recognized bobaId is NOT in cards.json's have-art set.

Click a card to toggle approved (cyan border). When done, hit
"Copy approved JSON" — paste it into ship_from_eval.py (TODO) or hand
off to whatever ship path you want.

USAGE
─────
  python pipeline/scripts/near_miss_review.py \\
    --eval-dir pipeline/eval/discord-2026-05-08

  open pipeline/eval/discord-2026-05-08/near_miss.html
"""

from __future__ import annotations
import argparse, json, os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CARDS_JSON = REPO_ROOT / "BOBAPlaybook/display-cards.json"

# Score band — anything below 3.4 is too noisy to be worth a manual look;
# at 4.5 we're already in AUTO territory. Treat 4.5 as exclusive upper
# bound so AUTO winners stay out of this list.
SCORE_LO = 3.4
SCORE_HI = 4.5


def load_have_art(cards_json: Path) -> set[str]:
    have = set()
    for c in json.loads(cards_json.read_text()):
        if c.get("imageAvailable") and c.get("bobaId"):
            have.add(c["bobaId"])
    return have


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--eval-dir", required=True,
                    help="Directory written by evaluate_discord.py")
    ap.add_argument("--cards-json", default=str(DEFAULT_CARDS_JSON))
    ap.add_argument("--score-lo", type=float, default=SCORE_LO)
    ap.add_argument("--score-hi", type=float, default=SCORE_HI)
    args = ap.parse_args()

    eval_dir = Path(args.eval_dir).expanduser()
    output_jsonl = eval_dir / "output.jsonl"
    crops_dir = eval_dir / "crops-near"
    crops_dir.mkdir(exist_ok=True)
    if not output_jsonl.is_file():
        raise SystemExit(f"!! {output_jsonl} not found — run evaluate_discord.py first")

    have_art = load_have_art(Path(args.cards_json))
    print(f"have_art: {len(have_art):,}")

    candidates = []
    with output_jsonl.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            score = r.get("score")
            recog = r.get("recognized_boba_id")
            if score is None or recog is None:
                continue
            if score < args.score_lo or score >= args.score_hi:
                continue
            if recog in have_art:
                continue
            crop = r.get("crop") or {}
            if crop.get("method") != "vision_rect":
                continue
            candidates.append(r)

    print(f"near-miss candidates (score {args.score_lo}–{args.score_hi}, no art, vision_rect): {len(candidates):,}")

    # Copy each tight crop into crops-near/ so the HTML can display it
    # via a relative path (works when the eval dir is moved/zipped).
    import shutil
    for r in candidates:
        crop_path = (r.get("crop") or {}).get("path") or ""
        if crop_path and Path(crop_path).is_file():
            dst = crops_dir / f"{r['id']}.jpg"
            try:
                shutil.copy(crop_path, dst)
                r["_crop_local"] = f"crops-near/{r['id']}.jpg"
            except Exception:
                r["_crop_local"] = ""

    candidates.sort(key=lambda r: -(r.get("score") or 0))

    # ── Build HTML ──
    cards_html = []
    for r in candidates:
        rid = r["id"]
        recog = r["recognized_boba_id"]
        score = r.get("score") or 0
        margin = r.get("margin")
        top = r.get("top_candidates") or []
        sm = (top[0]["score"] - top[1]["score"]) if len(top) >= 2 else None
        ocr = r.get("ocr") or {}
        ocr_num = (ocr.get("card_number_hint") or "").strip()
        ocr_hero = (ocr.get("raw_name") or "").strip()
        crop_rel = r.get("_crop_local", "")

        chips = [f'<span class=score>score {score:.2f}</span>']
        if margin is not None:
            chips.append(f'<span>margin {margin:.2f}</span>')
        if sm is not None:
            chips.append(f'<span>2nd {sm:.2f}</span>')

        # Top 3 with already-imaged markers
        top_lines = []
        for c in (top or [])[:3]:
            bid = c.get("boba_id") or ""
            sc  = c.get("score") or 0
            cls = "imaged" if bid in have_art else ("self" if bid == recog else "alt")
            top_lines.append(
                f'<div class="cand {cls}">'
                f'<span class=cscore>{sc:.2f}</span> '
                f'<span class=cbid>{bid}</span>'
                f'</div>'
            )

        ocr_block = ""
        if ocr_num or ocr_hero:
            ocr_block = (f'<div class=ocr>OCR: <code>{ocr_num}</code> · <code>{ocr_hero}</code></div>')

        img_block = (f'<img src="{crop_rel}" loading=lazy>' if crop_rel
                     else '<div class=noimg>(no crop)</div>')

        cards_html.append(
            f'<div class=card data-bid="{recog}" data-rid="{rid}" onclick="toggle(this)">'
            f'{img_block}'
            f'<div class=bobaid>{recog}</div>'
            f'<div class=row>{"".join(chips)}</div>'
            f'{ocr_block}'
            f'<div class=cands>{"".join(top_lines)}</div>'
            f'</div>'
        )

    html = f"""<!doctype html>
<meta charset=utf-8>
<title>Discord near-miss sweep</title>
<style>
body {{ background:#0d0d1a; color:#eee; font:14px/1.4 -apple-system,BlinkMacSystemFont,sans-serif; margin:24px; padding-bottom:80px }}
h1 {{ font:600 22px/1.2 -apple-system,sans-serif; margin:0 0 8px }}
.meta {{ color:#888; font-size:12px; margin-bottom:24px }}
.toolbar {{ position:fixed; bottom:0; left:0; right:0; background:rgba(13,13,26,0.95); backdrop-filter:blur(8px); padding:14px 24px; border-top:1px solid #2a2a3e; display:flex; gap:12px; align-items:center; z-index:10 }}
.toolbar button {{ background:#ff4d00; color:#080810; border:0; padding:8px 16px; border-radius:6px; font:600 13px/1 -apple-system,sans-serif; cursor:pointer }}
.toolbar button.ghost {{ background:transparent; color:#aaa; border:1px solid #444 }}
.counter {{ color:#00f5ff; font:600 14px/1 -apple-system,sans-serif; margin-left:auto }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(280px,1fr)); gap:16px }}
.card {{ background:#13131f; border:2px solid transparent; border-radius:8px; padding:12px; cursor:pointer; transition:border-color .15s, transform .15s }}
.card.approved {{ border-color:#00f5ff; transform:scale(1.01) }}
.card img {{ width:100%; height:auto; aspect-ratio:5/7; object-fit:cover; border-radius:4px; margin-bottom:8px; background:#000; display:block }}
.card .noimg {{ aspect-ratio:5/7; background:#222; border-radius:4px; display:flex; align-items:center; justify-content:center; color:#666; font-size:11px; margin-bottom:8px }}
.bobaid {{ font:600 13px/1.3 -apple-system,sans-serif; color:#fff; word-break:break-word; margin-bottom:6px }}
.row {{ display:flex; gap:8px; font-size:11px; color:#888; margin-bottom:6px; flex-wrap:wrap }}
.row .score {{ color:#ffb055; font-weight:600 }}
.ocr {{ font-size:10px; color:#666; margin-bottom:6px }}
.ocr code {{ background:#1a1a26; padding:1px 4px; border-radius:3px; color:#aaa }}
.cands {{ border-top:1px solid #1f1f2e; padding-top:6px; font-size:10px }}
.cand {{ display:flex; gap:6px; padding:2px 0 }}
.cand .cscore {{ color:#888; min-width:34px }}
.cand .cbid {{ color:#777; word-break:break-word }}
.cand.self .cbid {{ color:#00f5ff }}
.cand.imaged .cbid {{ color:#666; text-decoration:line-through }}
</style>

<h1>Discord near-miss sweep — {len(candidates)} candidates</h1>
<div class=meta>score band {args.score_lo}–{args.score_hi} · vision_rect only · recognized bobaId NOT yet imaged · sorted by score desc · click a card to approve (cyan border)</div>

<div class=grid>
{"".join(cards_html)}
</div>

<div class=toolbar>
  <button onclick="copy()">Copy approved JSON</button>
  <button class=ghost onclick="clearAll()">Clear all</button>
  <button class=ghost onclick="approveAll()">Approve all visible</button>
  <span class=counter id=counter>0 approved</span>
</div>

<script>
const KEY = "discord-near-miss-approved-v1";
function loadSet() {{
  try {{ return new Set(JSON.parse(localStorage.getItem(KEY) || "[]")); }}
  catch (e) {{ return new Set(); }}
}}
function saveSet(s) {{
  localStorage.setItem(KEY, JSON.stringify([...s]));
  document.getElementById("counter").textContent = s.size + " approved";
}}
let approved = loadSet();
function refresh() {{
  document.querySelectorAll(".card").forEach(el => {{
    if (approved.has(el.dataset.rid)) el.classList.add("approved");
    else el.classList.remove("approved");
  }});
  saveSet(approved);
}}
function toggle(el) {{
  const rid = el.dataset.rid;
  if (approved.has(rid)) approved.delete(rid);
  else approved.add(rid);
  refresh();
}}
function clearAll() {{
  if (!confirm("Clear all approvals?")) return;
  approved = new Set();
  refresh();
}}
function approveAll() {{
  document.querySelectorAll(".card").forEach(el => approved.add(el.dataset.rid));
  refresh();
}}
function copy() {{
  const out = [];
  document.querySelectorAll(".card").forEach(el => {{
    if (approved.has(el.dataset.rid)) {{
      out.push({{rid: el.dataset.rid, bobaId: el.dataset.bid}});
    }}
  }});
  const blob = JSON.stringify(out, null, 2);
  navigator.clipboard.writeText(blob).then(() => {{
    alert("Copied " + out.length + " approvals to clipboard.");
  }}).catch(() => {{
    const w = window.open("");
    w.document.body.innerText = blob;
  }});
}}
refresh();
</script>
"""
    out_path = eval_dir / "near_miss.html"
    out_path.write_text(html)
    print(f"\nopen {out_path}")


if __name__ == "__main__":
    main()
