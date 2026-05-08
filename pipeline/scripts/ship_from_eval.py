#!/usr/bin/env python3
"""
ship_from_eval.py — local-only ship path for Discord-eval winners.

Takes the output of evaluate_discord.py + a list of bobaIds to EXCLUDE
(everything else gets shipped). Runs the same Stage C plumbing
(WebP generation → R2 head-check → R2 upload → catalog patches → PR)
without touching Supabase or the GH Actions cron.

Mantra: One Image per Card. One ID per Card. R2 head-check is the
last-defense against overwriting existing art. Pre-flight have_art
filter is the primary defense.

USAGE
─────
  python pipeline/scripts/ship_from_eval.py \\
    --eval-dir   pipeline/eval/discord-2026-05-08 \\
    --excludes-file /tmp/excludes.txt \\
    --dry-run

  # If preview looks right, drop --dry-run.
"""

from __future__ import annotations

import argparse, json, os, subprocess, sys, time
from pathlib import Path
from typing import Optional

# Reuse the canonical Stage C helpers — single source of truth for
# filename generation, image tiers, head-check upload, bundle patching.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from stage_c_commit import (   # type: ignore
    safe_filename_for_boba_id,
    generate_image_tiers,
    upload_winner,
    patch_bundle,
    make_r2_client,
    CATALOG_BUNDLES,
    WinningCandidate,
)

from dotenv import load_dotenv
load_dotenv(Path(__file__).resolve().parents[2] / ".env")


SCORE_LO_NEAR = 3.4
SCORE_HI_NEAR = 4.5     # exclusive — AUTO winners come from winners.json


def load_have_art_from_repo(repo_root: Path) -> set[str]:
    """Build have_art directly from cards.json — same logic as Stage C."""
    cards = json.loads((repo_root / "assets" / "data" / "cards.json").read_text())
    out = set()
    for c in cards:
        if c.get("imageAvailable"):
            cn  = (c.get("cardNumber") or "").strip()
            hero = (c.get("hero") or c.get("name") or "").strip()
            tr  = (c.get("treatment") or "").strip()
            va  = (c.get("variation") or "").strip()
            out.add(f"{cn}-{hero}-{tr}-{va}")
    return out


def collect_ship_list(eval_dir: Path, excludes: set[str], have_art: set[str]
                      ) -> list[dict]:
    """Returns the ship list = AUTO winners + near-miss filtered, deduped
    by recognized_boba_id (highest score wins), excluding `excludes`."""
    auto = json.loads((eval_dir / "winners.json").read_text())
    near = []
    with (eval_dir / "output.jsonl").open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            sc, rid = r.get("score"), r.get("recognized_boba_id")
            if sc is None or rid is None:
                continue
            if sc < SCORE_LO_NEAR or sc >= SCORE_HI_NEAR:
                continue
            if rid in have_art:
                continue
            if (r.get("crop") or {}).get("method") != "vision_rect":
                continue
            near.append(r)

    seen: dict[str, dict] = {}
    for r in list(auto) + near:
        bid = r["recognized_boba_id"]
        cur = seen.get(bid)
        if cur is None or (r.get("score") or 0) > (cur.get("score") or 0):
            seen[bid] = r

    final = [r for bid, r in seen.items() if bid not in excludes]
    final.sort(key=lambda r: -(r.get("score") or 0))
    return final


def find_crop_path(eval_dir: Path, r: dict) -> Optional[Path]:
    """Resolve the local tight-crop image. AUTO winners live in crops/
    (named by bobaId); near-miss live in crops-near/ (named by rid)."""
    bid = r["recognized_boba_id"]
    safe_bid = bid  # crops/ uses the bobaId verbatim
    p = eval_dir / "crops" / f"{safe_bid}.jpg"
    if p.is_file():
        return p
    p = eval_dir / "crops-near" / f"{r['id']}.jpg"
    if p.is_file():
        return p
    # Last resort: the cardreckon-emitted absolute path
    cp = (r.get("crop") or {}).get("path") or ""
    if cp and Path(cp).is_file():
        return Path(cp)
    return None


def to_winning_candidate(r: dict, source_path: Path) -> WinningCandidate:
    bid = r["recognized_boba_id"]
    return WinningCandidate(
        candidate_id=r.get("id") or "",
        boba_id=bid,
        score=float(r.get("score") or 0),
        margin=(float(r["margin"]) if r.get("margin") is not None else None),
        crop_image_r2_key="",     # not used — we read from disk
        image_md5="",
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--eval-dir", required=True)
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--excludes-file", default=None,
                    help="Newline-separated bobaIds to skip")
    ap.add_argument("--branch",
                    default=f"pipeline/discord-eval-{time.strftime('%Y%m%d-%H%M%S')}")
    ap.add_argument("--cdn-base",
                    default="https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    eval_dir = Path(args.eval_dir).expanduser()
    repo_root = Path(args.repo_root).resolve()
    if not (repo_root / "assets/data/cards.json").exists():
        sys.exit(f"!! not a BOBA-Playbook checkout: {repo_root}")
    if not eval_dir.is_dir():
        sys.exit(f"!! eval-dir not found: {eval_dir}")

    excludes: set[str] = set()
    if args.excludes_file and Path(args.excludes_file).is_file():
        for line in Path(args.excludes_file).read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                excludes.add(line)
    print(f"excludes:        {len(excludes)}")

    have_art = load_have_art_from_repo(repo_root)
    print(f"have_art:        {len(have_art):,}")

    ship_list = collect_ship_list(eval_dir, excludes, have_art)
    print(f"ship list:       {len(ship_list)}")
    for i, r in enumerate(ship_list, 1):
        print(f"  {i:2d}. score {r['score']:.2f}  {r['recognized_boba_id']}")

    if not ship_list:
        print("\nNothing to ship.")
        return

    # ─── R2 client ──
    r2 = make_r2_client(
        os.environ["R2_ACCOUNT_ID"].strip(),
        os.environ["R2_ACCESS_KEY"].strip(),
        os.environ["R2_SECRET_KEY"].strip(),
    )
    bucket = os.environ.get("R2_BUCKET", "boba-card-images").strip()

    # ─── Build WinningCandidate objects + read crop bytes ──
    winners: list[WinningCandidate] = []
    crops_in_memory: dict[str, bytes] = {}   # boba_id -> source crop bytes
    missing_crops: list[str] = []
    for r in ship_list:
        cp = find_crop_path(eval_dir, r)
        if not cp:
            missing_crops.append(r["recognized_boba_id"])
            continue
        try:
            crops_in_memory[r["recognized_boba_id"]] = cp.read_bytes()
        except Exception as e:
            print(f"  ! crop read failed for {r['recognized_boba_id']}: {e}")
            missing_crops.append(r["recognized_boba_id"])
            continue
        w = to_winning_candidate(r, cp)
        w.image_file   = safe_filename_for_boba_id(w.boba_id)
        w.full_r2_key  = f"full/{w.image_file}"
        w.thumb_r2_key = f"thumbs/{w.image_file}"
        winners.append(w)

    if missing_crops:
        print(f"\n  ! missing tight crops for {len(missing_crops)} bobaIds:")
        for bid in missing_crops:
            print(f"    - {bid}")

    print(f"\nready to ship: {len(winners)} cards")
    if args.dry_run:
        print("DRY RUN — would generate WebP + upload to R2 + patch bundles + PR")
        return

    # ─── Generate + upload tiers ──
    print(f"\n→ generating + uploading {len(winners)} image tiers")
    refused, failures = [], []
    for i, w in enumerate(winners):
        try:
            full_bytes, thumb_bytes = generate_image_tiers(crops_in_memory[w.boba_id])
            status = upload_winner(r2, bucket, w, full_bytes, thumb_bytes, dry_run=False)
            if status == "already_exists":
                refused.append(w.boba_id)
                print(f"  ⊘ refused overwrite: {w.boba_id}")
        except Exception as e:
            failures.append(w.boba_id)
            print(f"  ! upload failed for {w.boba_id}: {e}")
        if (i + 1) % 5 == 0:
            print(f"  [{i+1}/{len(winners)}]")

    winners = [w for w in winners
               if w.boba_id not in refused and w.boba_id not in failures]
    print(f"\nuploaded {len(winners)}; refused {len(refused)}; failed {len(failures)}")
    if not winners:
        print("Nothing to commit.")
        return

    # ─── Patch catalog bundles ──
    print(f"\n→ patching {len(CATALOG_BUNDLES)} catalog bundles")
    updates = {w.boba_id: w.image_file for w in winners}
    for rel in CATALOG_BUNDLES:
        path = repo_root / rel
        n = patch_bundle(path, updates)
        print(f"  {rel}: patched {n}")

    # ─── Commit + PR ──
    def git(*cmd, check=True):
        return subprocess.run(["git", "-C", str(repo_root), *cmd],
                              check=check, capture_output=True, text=True)

    git("checkout", "-b", args.branch)
    git("add", *CATALOG_BUNDLES)
    diff = git("diff", "--cached", "--quiet", check=False)
    if diff.returncode == 0:
        print("no catalog diff — skipping PR")
        return

    title = f"discord-eval: ship {len(winners)} cards (manual sweep)"
    body_lines = [
        f"## Discord export — manual sweep",
        f"",
        f"Source: `{eval_dir.name}` · score band 3.4–4.5 + 1 AUTO winner · "
        f"manually approved (excludes: {len(excludes)} bobaIds).",
        f"",
        f"- Winners merged: **{len(winners)}**",
        f"- R2 prefix: `full/` + `thumbs/` on `boba-card-images`",
        f"- Refused overwrites: {len(refused)}",
        f"- Failures: {len(failures)}",
        f"",
        f"### Cards",
        f"",
        f"Each card shows the bobaId + recognition score + the production-tier "
        f"image at 300px.",
        f"",
        f"---",
        f"",
    ]
    for i, w in enumerate(winners, 1):
        url = f"{args.cdn_base}/full/{w.image_file}"
        margin_str = f", margin {w.margin:.2f}" if w.margin is not None else ""
        body_lines.append(f"### {i}. `{w.boba_id}` — score {w.score:.2f}{margin_str}")
        body_lines.append("")
        body_lines.append(f'<img src="{url}" width="300">')
        body_lines.append("")

    body = "\n".join(body_lines)

    git("commit", "-m", title)
    git("push", "-u", "origin", args.branch)

    pr = subprocess.run(
        ["gh", "pr", "create", "--title", title, "--body", body,
         "--base", "main", "--head", args.branch],
        cwd=str(repo_root), check=True, capture_output=True, text=True,
    )
    print(f"\nPR: {pr.stdout.strip()}")


if __name__ == "__main__":
    main()
