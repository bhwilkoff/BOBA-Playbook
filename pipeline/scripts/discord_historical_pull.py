#!/usr/bin/env python3
"""
discord_historical_pull.py — walk back N months of BoBA Discord history,
exporting + evaluating one month at a time, deleting media between
months so peak local disk usage is bounded to a single month's photos
(~1-7 GB).

For each month:
  1. DCE export with --after / --before / --media → exports/<YYYY-MM>/
  2. evaluate_discord.py → eval/<YYYY-MM>/
  3. Delete eval/<YYYY-MM>/output.jsonl + the *_Files dirs (the
     review.html still works because the tight-crop copies stay)
  4. Append AUTO winners + near-miss candidates to running tallies
  5. Mark month complete with a marker file (idempotent re-runs)

After all months:
  - Combine across months, dedupe by recognized_boba_id (highest-scored wins)
  - Strict-AUTO list → ready for ship_from_eval.py
  - Near-miss list → combined HTML for one big manual review pass

CONFIG
──────
Token: DISCORD_TOKEN env var, OR macOS keychain
       (`security add-generic-password -a $USER -s boba-discord-token -w "..."`)

USAGE
─────
  python pipeline/scripts/discord_historical_pull.py \\
    --start-month 2024-05 --end-month 2026-04

  # Idempotent re-run (skips completed months):
  python pipeline/scripts/discord_historical_pull.py \\
    --start-month 2024-05 --end-month 2026-04

  # When done, review the combined output:
  open pipeline/eval/discord-history/historical_review.html
  python pipeline/scripts/ship_from_eval.py \\
    --eval-dir pipeline/eval/discord-history \\
    --excludes-file /tmp/historical-excludes.txt
"""

from __future__ import annotations

import argparse, calendar, json, os, shutil, subprocess, sys, time
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

DEFAULT_DCE_BIN = Path("/Users/bhwilkoff/Downloads/DiscordChatExporter.Cli.osx-arm64/DiscordChatExporter.Cli")
DEFAULT_EXPORTS_BASE = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research/discord-history-exports")
DEFAULT_EVAL_BASE = REPO_ROOT / "pipeline/eval/discord-history"

# Same channels used in the Apr 22 + May 8 exports
CHANNEL_IDS = [
    "1305710603440095255",   # general-chat-here
    "1448759509076934778",   # feedback-and-support
    "1306146115757936650",   # trade-room
]


def get_token() -> str:
    """Discord auth token. Tries DISCORD_TOKEN env first; falls back to
    macOS Keychain via `security find-generic-password -s boba-discord-token`.
    Stored in keychain via:
        security add-generic-password -a $USER -s boba-discord-token -w "<token>"
    """
    if os.environ.get("DISCORD_TOKEN"):
        return os.environ["DISCORD_TOKEN"].strip()
    try:
        proc = subprocess.run(
            ["security", "find-generic-password", "-a", os.environ.get("USER", ""),
             "-s", "boba-discord-token", "-w"],
            check=True, capture_output=True, text=True,
        )
        return proc.stdout.strip()
    except subprocess.CalledProcessError:
        sys.exit(
            "!! No Discord token. Set DISCORD_TOKEN env var, or store in keychain:\n"
            "   security add-generic-password -a $USER -s boba-discord-token -w \"<token>\""
        )


def month_iter(start_ym: str, end_ym: str):
    """Yield (year, month, after_iso, before_iso) for each month in
    [start_ym, end_ym] inclusive. ISO bounds are first-of-month dates so
    DCE's --after/--before treat them as midnight UTC."""
    sy, sm = map(int, start_ym.split("-"))
    ey, em = map(int, end_ym.split("-"))
    y, m = sy, sm
    while (y, m) <= (ey, em):
        after  = f"{y:04d}-{m:02d}-01"
        # before = first of next month
        ny, nm = (y, m + 1) if m < 12 else (y + 1, 1)
        before = f"{ny:04d}-{nm:02d}-01"
        yield y, m, after, before
        y, m = ny, nm


def run(*cmd, cwd=None, capture=False) -> subprocess.CompletedProcess:
    """Lightweight wrapper that doesn't tee output unless capture=True."""
    return subprocess.run(cmd, cwd=cwd,
                          capture_output=capture, text=True, check=False)


def dce_export(token: str, dce_bin: Path, out_dir: Path,
               after: str, before: str, log_path: Path) -> bool:
    """Export the three channels for [after, before) into out_dir.

    Two-phase pattern (much faster than DCE's --media):
      1. Run DCE WITHOUT --media to get JSONs (rate-limited only by API,
         not by per-attachment CDN throttling — completes in seconds).
      2. Run download_discord_media.py with 4 parallel workers — Discord
         CDN doesn't authenticate by token, so parallel CDN requests
         can't get the token banned. ~4× faster than DCE --media.

    Returns True on success."""
    out_dir.mkdir(parents=True, exist_ok=True)
    template = str(out_dir / "%C.json")

    # Phase 1: DCE JSON-only — channels SEQUENTIAL (--parallel 1).
    # DO NOT bump this up. DCE's --parallel runs N channels in parallel,
    # each hammering Discord's API with the user's token at full rate.
    # 3 parallel channels triggered a token-level rate limit on
    # 2026-05-08 that blocked Ben's desktop Discord too. CDN media
    # parallelism is fine (downloader uses signed URLs, no token); but
    # API-side parallelism is account-banning territory. Sequential
    # channels still finish in seconds because the API call is just
    # paginating message metadata, not media.
    cmd = [str(dce_bin), "export",
           "-t", token,
           "-c", *CHANNEL_IDS,
           "-f", "Json",
           "--after", after,
           "--before", before,
           "-o", template]
    with log_path.open("a") as logf:
        logf.write(f"\n=== DCE export {after} → {before} (JSON-only, parallel=3) ===\n")
        logf.flush()
        p1 = subprocess.run(cmd, stdout=logf, stderr=subprocess.STDOUT, text=True)
    if p1.returncode != 0:
        return False

    # Phase 2: parallel media downloader
    dl_cmd = ["python3",
              str(REPO_ROOT / "pipeline/scripts/download_discord_media.py"),
              "--exports-dir", str(out_dir),
              "--workers", "4"]
    with log_path.open("a") as logf:
        logf.write(f"\n=== parallel media download (workers=4) ===\n")
        logf.flush()
        p2 = subprocess.run(dl_cmd, stdout=logf, stderr=subprocess.STDOUT, text=True)
    return p2.returncode == 0


def cleanup_media(exports_dir: Path):
    """Delete every *_Files/ subdir inside exports_dir. Keeps the JSONs
    for retroactive eval if ever needed."""
    freed = 0
    for sub in exports_dir.glob("*_Files"):
        if sub.is_dir():
            try:
                size = sum(p.stat().st_size for p in sub.rglob("*") if p.is_file())
                shutil.rmtree(sub)
                freed += size
            except Exception as e:
                print(f"  ! cleanup failed for {sub}: {e}")
    return freed


def evaluate_month(exports_dir: Path, eval_dir: Path) -> dict:
    """Run evaluate_discord.py against exports_dir. Returns the parsed
    report.txt summary as a dict."""
    eval_dir.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        ["python3", str(REPO_ROOT / "pipeline/scripts/evaluate_discord.py"),
         "--exports-dir", str(exports_dir),
         "--output-dir",  str(eval_dir)],
        capture_output=True, text=True,
    )
    summary = {
        "exit_code": proc.returncode,
        "stdout_tail": proc.stdout[-2000:] if proc.stdout else "",
        "stderr_tail": proc.stderr[-2000:] if proc.stderr else "",
    }
    return summary


def trim_eval_artifacts(eval_dir: Path):
    """Delete the heavy intermediate files we no longer need after the
    month's run is recorded. Keep crops/, crops-near/, winners.json,
    winners.csv, report.txt — drop input/output JSONLs (5–10 MB each)."""
    for name in ("input.jsonl", "output.jsonl"):
        p = eval_dir / name
        if p.is_file():
            try:
                p.unlink()
            except Exception:
                pass


# ─── Combine across months ────────────────────────────────────────────────

SCORE_LO_NEAR = 3.4
SCORE_HI_NEAR = 4.5


def load_have_art() -> set[str]:
    cards = json.loads((REPO_ROOT / "assets/data/cards.json").read_text())
    out = set()
    for c in cards:
        if c.get("imageAvailable"):
            cn   = (c.get("cardNumber") or "").strip()
            hero = (c.get("hero") or c.get("name") or "").strip()
            tr   = (c.get("treatment") or "").strip()
            va   = (c.get("variation") or "").strip()
            out.add(f"{cn}-{hero}-{tr}-{va}")
    return out


def gather_combined(eval_base: Path) -> tuple[list[dict], list[dict]]:
    """Walk every per-month subdir under eval_base, pull out AUTO winners
    (winners.json) and re-derive near-miss candidates from each month's
    output.jsonl IF it still exists (untrimmed) — otherwise rely on the
    per-month crops-near/ + a sidecar near_miss.json we'll write below.

    Returns (auto, near) — each a list of result dicts already deduped
    by recognized_boba_id (highest score wins) and filtered against
    the current cards.json have_art set."""
    have_art = load_have_art()

    auto_by_bid: dict[str, dict] = {}
    near_by_bid: dict[str, dict] = {}

    for sub in sorted(eval_base.iterdir()):
        if not sub.is_dir():
            continue
        # AUTO winners
        wf = sub / "winners.json"
        if wf.is_file():
            try:
                for w in json.loads(wf.read_text()):
                    w["_month"] = sub.name
                    bid = w.get("recognized_boba_id")
                    if not bid or bid in have_art:
                        continue
                    cur = auto_by_bid.get(bid)
                    if cur is None or (w.get("score") or 0) > (cur.get("score") or 0):
                        auto_by_bid[bid] = w
            except Exception as e:
                print(f"  ! parse {wf}: {e}")

        # Near-miss — read from the sidecar near_miss.jsonl (we write
        # this each month before trimming output.jsonl)
        nf = sub / "near_miss.jsonl"
        if nf.is_file():
            try:
                for line in nf.read_text().splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    r = json.loads(line)
                    r["_month"] = sub.name
                    bid = r.get("recognized_boba_id")
                    if not bid or bid in have_art:
                        continue
                    cur = near_by_bid.get(bid)
                    if cur is None or (r.get("score") or 0) > (cur.get("score") or 0):
                        near_by_bid[bid] = r
            except Exception as e:
                print(f"  ! parse {nf}: {e}")

    auto = sorted(auto_by_bid.values(), key=lambda r: -(r.get("score") or 0))
    near = sorted(near_by_bid.values(), key=lambda r: -(r.get("score") or 0))
    return auto, near


def write_near_miss_sidecar(eval_dir: Path) -> int:
    """Read output.jsonl, extract near-miss-band candidates passing
    vision_rect filter, write them to near_miss.jsonl. Done before
    output.jsonl gets trimmed, so the combined gather can find them."""
    out = eval_dir / "output.jsonl"
    sidecar = eval_dir / "near_miss.jsonl"
    if not out.is_file():
        return 0
    n = 0
    with out.open() as fin, sidecar.open("w") as fout:
        for line in fin:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            sc = r.get("score")
            if sc is None or sc < SCORE_LO_NEAR or sc >= SCORE_HI_NEAR:
                continue
            if (r.get("crop") or {}).get("method") != "vision_rect":
                continue
            if r.get("recognized_boba_id") is None:
                continue
            fout.write(line + "\n")
            n += 1
    return n


def consolidate_crops(eval_base: Path, target_dir: Path,
                      auto: list[dict], near: list[dict]):
    """Copy every winning tight crop into one consolidated dir for the
    final review HTML / ship step."""
    target_dir.mkdir(parents=True, exist_ok=True)
    for r in auto + near:
        bid = r["recognized_boba_id"]
        # AUTO winners' crops live in <month>/crops/{bobaId}.jpg
        # Near-miss crops live in <month>/crops-near/{rid}.jpg
        month = r.get("_month", "")
        candidates = []
        if (eval_base / month / "crops").is_dir():
            candidates.append(eval_base / month / "crops" / f"{bid}.jpg")
        if r.get("id"):
            candidates.append(eval_base / month / "crops-near" / f"{r['id']}.jpg")
        # Whatever the cardreckon-emitted absolute path was
        cp = (r.get("crop") or {}).get("path") or ""
        if cp:
            candidates.append(Path(cp))
        for src in candidates:
            if src.is_file():
                ext = src.suffix or ".jpg"
                # AUTO winner: name by bobaId (matches what ship_from_eval expects)
                # Near-miss: name by rid (matches what ship_from_eval expects)
                if r in auto:
                    dst = target_dir / "crops" / f"{bid}{ext}"
                else:
                    dst = target_dir / "crops-near" / f"{r['id']}{ext}"
                dst.parent.mkdir(parents=True, exist_ok=True)
                try:
                    shutil.copy(src, dst)
                except Exception:
                    pass
                break


def write_combined_outputs(eval_base: Path, auto: list[dict], near: list[dict]):
    """Write the top-level winners.json + output.jsonl + near_miss sidecar
    so ship_from_eval.py can run against eval_base directly."""
    eval_base.mkdir(parents=True, exist_ok=True)
    (eval_base / "winners.json").write_text(json.dumps(auto, indent=2, ensure_ascii=False))
    # Synthesize an output.jsonl that's exactly the combined auto + near
    # so ship_from_eval's collect_ship_list works (it filters that file).
    with (eval_base / "output.jsonl").open("w") as f:
        for r in auto + near:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def write_combined_html(eval_base: Path, auto: list[dict], near: list[dict],
                        per_month_stats: list[dict]):
    """Big review HTML covering all months. Mirrors near_miss_review.py
    but with a month chip per card."""
    have_art = load_have_art()
    rows = []
    for r in auto + near:
        bid = r["recognized_boba_id"]
        score = r.get("score") or 0
        margin = r.get("margin")
        top = r.get("top_candidates") or []
        sm = (top[0]["score"] - top[1]["score"]) if len(top) >= 2 else None
        ocr = r.get("ocr") or {}
        tier = "AUTO" if r in auto else "near"
        crop_rel = (f"crops/{bid}.jpg" if r in auto
                    else f"crops-near/{r['id']}.jpg")
        chips = [f'<span class=score>score {score:.2f}</span>',
                 f'<span class=tier-{tier.lower()}>{tier}</span>',
                 f'<span class=month>{r.get("_month","")}</span>']
        if margin is not None:
            chips.append(f'<span>margin {margin:.2f}</span>')
        if sm is not None:
            chips.append(f'<span>2nd {sm:.2f}</span>')

        top_lines = []
        for c in (top or [])[:3]:
            tbid = c.get("boba_id") or ""
            tsc  = c.get("score") or 0
            cls = "imaged" if tbid in have_art else ("self" if tbid == bid else "alt")
            top_lines.append(
                f'<div class="cand {cls}">'
                f'<span class=cscore>{tsc:.2f}</span> '
                f'<span class=cbid>{tbid}</span></div>')

        ocr_block = ""
        if ocr.get("card_number_hint") or ocr.get("raw_name"):
            ocr_block = (f'<div class=ocr>OCR: <code>{ocr.get("card_number_hint","")}</code> · '
                         f'<code>{ocr.get("raw_name","")}</code></div>')

        rows.append(
            f'<div class="card tier-{tier.lower()}" data-bid="{bid}" '
            f'data-rid="{r.get("id","")}" data-tier="{tier}" onclick="toggle(this)">'
            f'<img src="{crop_rel}" loading=lazy>'
            f'<div class=bobaid>{bid}</div>'
            f'<div class=row>{"".join(chips)}</div>'
            f'{ocr_block}'
            f'<div class=cands>{"".join(top_lines)}</div>'
            f'</div>')

    months_summary = "".join(
        f'<tr><td>{s["month"]}</td><td>{s["images"]:,}</td><td>{s["auto"]}</td><td>{s["near"]}</td></tr>'
        for s in per_month_stats
    )

    html = f"""<!doctype html><meta charset=utf-8>
<title>Discord historical sweep</title>
<style>
body {{ background:#0d0d1a; color:#eee; font:14px/1.4 -apple-system,sans-serif; margin:24px; padding-bottom:80px }}
h1 {{ font:600 22px/1.2 -apple-system,sans-serif; margin:0 0 8px }}
.meta {{ color:#888; font-size:12px; margin-bottom:24px }}
table {{ border-collapse:collapse; margin:8px 0 24px }}
th, td {{ padding:4px 12px; text-align:right; border-bottom:1px solid #222; font:11px/1 -apple-system,sans-serif }}
th {{ color:#666; font-weight:400 }}
td:first-child, th:first-child {{ text-align:left }}
.toolbar {{ position:fixed; bottom:0; left:0; right:0; background:rgba(13,13,26,0.95); backdrop-filter:blur(8px); padding:14px 24px; border-top:1px solid #2a2a3e; display:flex; gap:12px; align-items:center; z-index:10 }}
.toolbar button {{ background:#ff4d00; color:#080810; border:0; padding:8px 16px; border-radius:6px; font:600 13px/1 -apple-system,sans-serif; cursor:pointer }}
.toolbar button.ghost {{ background:transparent; color:#aaa; border:1px solid #444 }}
.counter {{ color:#00f5ff; font:600 14px/1 -apple-system,sans-serif; margin-left:auto }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(280px,1fr)); gap:16px }}
.card {{ background:#13131f; border:2px solid transparent; border-radius:8px; padding:12px; cursor:pointer }}
.card.approved {{ border-color:#00f5ff }}
.card img {{ width:100%; aspect-ratio:5/7; object-fit:cover; border-radius:4px; margin-bottom:8px; background:#000; display:block }}
.bobaid {{ font:600 13px/1.3 -apple-system,sans-serif; color:#fff; word-break:break-word; margin-bottom:6px }}
.row {{ display:flex; gap:8px; font-size:11px; color:#888; margin-bottom:6px; flex-wrap:wrap }}
.row .score {{ color:#ffb055; font-weight:600 }}
.row .tier-auto {{ background:#1a3a1a; color:#7ed957; padding:1px 6px; border-radius:3px }}
.row .tier-near {{ background:#3a2a1a; color:#ffb055; padding:1px 6px; border-radius:3px }}
.row .month {{ color:#666; font-family:ui-monospace,monospace }}
.ocr {{ font-size:10px; color:#666; margin-bottom:6px }}
.ocr code {{ background:#1a1a26; padding:1px 4px; border-radius:3px; color:#aaa }}
.cands {{ border-top:1px solid #1f1f2e; padding-top:6px; font-size:10px }}
.cand {{ display:flex; gap:6px; padding:2px 0 }}
.cand .cscore {{ color:#888; min-width:34px }}
.cand .cbid {{ color:#777; word-break:break-word }}
.cand.self .cbid {{ color:#00f5ff }}
.cand.imaged .cbid {{ color:#666; text-decoration:line-through }}
</style>
<h1>Discord historical sweep — {len(auto)} AUTO + {len(near)} near-miss</h1>
<div class=meta>combined across all months · already-imaged filtered · click to approve · sorted by score desc</div>
<table><thead><tr><th>month</th><th>images</th><th>auto</th><th>near</th></tr></thead>
<tbody>{months_summary}</tbody></table>
<div class=grid>{"".join(rows)}</div>
<div class=toolbar>
  <button onclick="copy()">Copy approved JSON</button>
  <button class=ghost onclick="approveAll()">Approve all visible</button>
  <button class=ghost onclick="approveAllAuto()">Approve AUTO only</button>
  <button class=ghost onclick="clearAll()">Clear all</button>
  <span class=counter id=counter>0 approved</span>
</div>
<script>
const KEY = "discord-historical-approved-v1";
function load() {{ try {{ return new Set(JSON.parse(localStorage.getItem(KEY)||"[]")); }} catch(e) {{ return new Set(); }} }}
function save(s) {{ localStorage.setItem(KEY, JSON.stringify([...s])); document.getElementById("counter").textContent = s.size + " approved"; }}
let approved = load();
function refresh() {{
  document.querySelectorAll(".card").forEach(el => {{
    const k = el.dataset.tier === "AUTO" ? el.dataset.bid : el.dataset.rid;
    el.classList.toggle("approved", approved.has(k));
  }});
  save(approved);
}}
function toggle(el) {{
  const k = el.dataset.tier === "AUTO" ? el.dataset.bid : el.dataset.rid;
  approved.has(k) ? approved.delete(k) : approved.add(k);
  refresh();
}}
function approveAll() {{ document.querySelectorAll(".card").forEach(el => approved.add(el.dataset.tier === "AUTO" ? el.dataset.bid : el.dataset.rid)); refresh(); }}
function approveAllAuto() {{ document.querySelectorAll(".card.tier-auto").forEach(el => approved.add(el.dataset.bid)); refresh(); }}
function clearAll() {{ if (!confirm("Clear?")) return; approved = new Set(); refresh(); }}
function copy() {{
  const out = [];
  document.querySelectorAll(".card").forEach(el => {{
    const k = el.dataset.tier === "AUTO" ? el.dataset.bid : el.dataset.rid;
    if (approved.has(k)) out.push({{tier: el.dataset.tier, bobaId: el.dataset.bid, rid: el.dataset.rid}});
  }});
  navigator.clipboard.writeText(JSON.stringify(out, null, 2))
    .then(() => alert("Copied " + out.length + " approvals."));
}}
refresh();
</script>"""
    (eval_base / "historical_review.html").write_text(html)


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--start-month", required=True, help="YYYY-MM, inclusive")
    ap.add_argument("--end-month",   required=True, help="YYYY-MM, inclusive")
    ap.add_argument("--exports-base", default=str(DEFAULT_EXPORTS_BASE))
    ap.add_argument("--eval-base",    default=str(DEFAULT_EVAL_BASE))
    ap.add_argument("--dce-bin",      default=str(DEFAULT_DCE_BIN))
    ap.add_argument("--skip-existing", action="store_true", default=True,
                    help="Skip months already marked complete (default true)")
    ap.add_argument("--combine-only", action="store_true",
                    help="Skip per-month work; just combine existing eval dirs")
    args = ap.parse_args()

    exports_base = Path(args.exports_base).expanduser()
    eval_base    = Path(args.eval_base).expanduser()
    dce_bin      = Path(args.dce_bin).expanduser()

    exports_base.mkdir(parents=True, exist_ok=True)
    eval_base.mkdir(parents=True, exist_ok=True)
    log_path = eval_base / "historical_pull.log"

    per_month_stats = []
    months = list(month_iter(args.start_month, args.end_month))
    print(f"plan: {len(months)} months from {args.start_month} → {args.end_month}")

    if not args.combine_only:
        token = get_token()

        for y, m, after, before in months:
            tag = f"{y:04d}-{m:02d}"
            month_eval = eval_base / tag
            marker = month_eval / ".complete"
            if args.skip_existing and marker.is_file():
                print(f"\n[{tag}] skip — already complete")
                stats = json.loads(marker.read_text() or "{}")
                per_month_stats.append({"month": tag, **stats})
                continue

            month_exports = exports_base / tag
            print(f"\n[{tag}] DCE export {after} → {before}")
            t0 = time.time()
            ok = dce_export(token, dce_bin, month_exports, after, before, log_path)
            if not ok:
                print(f"  ! DCE failed — see {log_path}")
                continue
            dce_dt = time.time() - t0

            print(f"[{tag}] DCE done in {dce_dt/60:.1f} min — running evaluate")
            month_eval.mkdir(parents=True, exist_ok=True)
            t0 = time.time()
            summary = evaluate_month(month_exports, month_eval)
            ev_dt = time.time() - t0

            # Persist a near-miss sidecar BEFORE we trim output.jsonl
            n_near = write_near_miss_sidecar(month_eval)

            # Read winners count from winners.json
            try:
                wins = json.loads((month_eval / "winners.json").read_text())
                n_auto = len(wins)
            except Exception:
                n_auto = 0

            # Image count from report.txt
            n_imgs = 0
            try:
                txt = (month_eval / "report.txt").read_text()
                for ln in txt.splitlines():
                    if "images processed" in ln:
                        n_imgs = int(ln.split(":")[-1].strip().replace(",", ""))
                        break
            except Exception:
                pass

            stats = {"images": n_imgs, "auto": n_auto, "near": n_near,
                     "dce_minutes": round(dce_dt/60, 1),
                     "eval_minutes": round(ev_dt/60, 1)}
            per_month_stats.append({"month": tag, **stats})
            print(f"[{tag}] images={n_imgs:,}  auto={n_auto}  near={n_near}  "
                  f"(dce {dce_dt/60:.1f}m + eval {ev_dt/60:.1f}m)")

            # Cleanup: media first (the big win), then trim heavy intermediates
            freed = cleanup_media(month_exports)
            print(f"[{tag}] freed {freed/1024/1024/1024:.2f} GB media")
            trim_eval_artifacts(month_eval)

            # Mark complete
            marker.write_text(json.dumps(stats))

    # Combine across months
    print("\n=== combining across months ===")
    auto, near = gather_combined(eval_base)
    print(f"  AUTO winners (deduped, not-imaged): {len(auto)}")
    print(f"  near-miss    (deduped, not-imaged): {len(near)}")

    # Pull per-month stats from marker files if --combine-only
    if args.combine_only:
        per_month_stats = []
        for sub in sorted(eval_base.iterdir()):
            mark = sub / ".complete"
            if mark.is_file():
                try:
                    per_month_stats.append({"month": sub.name, **json.loads(mark.read_text())})
                except Exception:
                    pass

    write_combined_outputs(eval_base, auto, near)
    consolidate_crops(eval_base, eval_base, auto, near)
    write_combined_html(eval_base, auto, near, per_month_stats)

    print(f"\nopen {eval_base / 'historical_review.html'}")
    print(f"\nWhen ready to ship, write your excludes to /tmp/historical-excludes.txt and run:")
    print(f"  python pipeline/scripts/ship_from_eval.py \\")
    print(f"    --eval-dir {eval_base} \\")
    print(f"    --excludes-file /tmp/historical-excludes.txt")


if __name__ == "__main__":
    main()
