#!/usr/bin/env python3
"""
apply_handoff_batch.py — generalized handoff applier.

Applies a multi-prefix Cowork handoff batch (e.g. handoff-updates-2026-04-21/)
containing a BATCH_SUMMARY.json + one subdirectory per prefix. Each prefix
directory has:
  - {prefix}_cards_proposed.json  (required — record list)
  - {prefix}_image_claim_map.json (optional — BV images ready to claim)
  - {prefix}_missing_images_patch.json (optional — metadata for eBay sourcer)
  - COWORK_*.md (handoff doc)

Merges all prefixes' records into the master cards.json in one pass, stages
BV images across every prefix, optimizes them, regenerates bundles via
reconcile_all.py, and syncs to the BOBA-Playbook repo.

Run from the BOBA-Playbook repo root:
    python3 scripts/apply_handoff_batch.py \\
        /Users/bhwilkoff/…/Bo\\ Jackson\\ Battle\\ Arena\\ Research/handoff-updates-2026-04-21

Supersedes apply_cyber_handoff.py (kept in git history as a worked example).
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# ─── Paths ──────────────────────────────────────────────────────────
APP_REPO     = Path(__file__).resolve().parent.parent
RESEARCH     = Path("/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research")

R_DATA       = RESEARCH / "unified-cards" / "data"
R_IMAGES     = RESEARCH / "unified-cards" / "images"
R_OPT        = RESEARCH / "unified-cards" / "images-optimized"
R_THUMBS     = RESEARCH / "unified-cards" / "thumbs"
R_BV_IMAGES  = RESEARCH / "source-images" / "images"
R_CARDS      = R_DATA / "cards.json"

APP_DATA     = APP_REPO / "assets" / "data"
APP_IOS      = APP_REPO / "BOBAPlaybook"

# ─── Catalog schema ─────────────────────────────────────────────────
CATALOG_FIELDS = {
    "cardNumber", "bobaId", "bvId", "name", "hero", "cardType", "set", "subSet",
    "variation", "treatment", "element", "power", "playCost", "playAbility",
    "isBonusPlay", "isHTD", "dbs", "dbsTier", "athleteInspiration", "isInspiredInk",
    "imageFile", "imageSource", "imageAvailable", "searchTokens",
}

# Mirrors reconcile_all.py::_build_search_tokens.
def build_search_tokens(*fields) -> list[str]:
    tokens: set[str] = set()
    for field in fields:
        if not field: continue
        words = re.split(r'[\s\-_/]+', str(field).lower())
        tokens.update(w for w in words if len(w) > 1)
    return sorted(tokens)

# Mirrors reconcile_all.py::_sort_key.
def sort_key(card_num: str):
    m = re.match(r'^([A-Za-z\-]*)(\d*)', card_num or "")
    prefix = m.group(1).upper() if m else ""
    num = int(m.group(2)) if (m and m.group(2)) else 0
    return (prefix, num, card_num)

# ─── Load + normalize a single prefix's proposed records ────────────
def load_prefix_records(prefix_dir: Path, prefix_lower: str) -> list[dict]:
    p = prefix_dir / f"{prefix_lower}_cards_proposed.json"
    if not p.exists():
        raise FileNotFoundError(f"missing {p}")
    raw = json.loads(p.read_text())
    out = []
    for r in raw:
        # Fill derivable fields
        if not r.get("searchTokens"):
            r["searchTokens"] = build_search_tokens(
                r.get("cardNumber"), r.get("hero"), r.get("element"),
                r.get("treatment"), r.get("variation"), r.get("set"),
                r.get("subSet"), r.get("athleteInspiration"),
            )
        r.setdefault("bvId", None)
        # Strip non-catalog fields (radishUrl, sourceNote, etc.)
        out.append({k: v for k, v in r.items() if k in CATALOG_FIELDS})
    return out

# ─── Merge all prefixes into cards.json in one pass ─────────────────
def merge_all(batch_dir: Path, prefixes: list[str]) -> tuple[int, int, dict]:
    cards = json.loads(R_CARDS.read_text())
    existing = {c.get("bobaId") for c in cards}
    total_added = 0
    per_prefix: dict[str, int] = {}
    for prefix in prefixes:
        prefix_dir = batch_dir / prefix
        records = load_prefix_records(prefix_dir, prefix)
        added = 0
        for r in records:
            if r["bobaId"] in existing: continue
            cards.append(r)
            existing.add(r["bobaId"])
            added += 1
            total_added += 1
        per_prefix[prefix] = added
        print(f"  {prefix.upper():>6}: +{added} / {len(records)}")
    cards.sort(key=lambda c: sort_key(c.get("cardNumber", "")))
    R_CARDS.write_text(json.dumps(cards, indent=2, ensure_ascii=False))
    return total_added, len(cards), per_prefix

# ─── Stage BV images across every prefix that has a claim map ───────
def stage_all_images(batch_dir: Path, prefixes: list[str]) -> list[Path]:
    staged: list[Path] = []
    missing: list[str] = []
    for prefix in prefixes:
        cm = batch_dir / prefix / f"{prefix}_image_claim_map.json"
        if not cm.exists(): continue
        claims = json.loads(cm.read_text())
        for row in claims:
            src = R_BV_IMAGES / row["bv_disk_file"]
            dst = R_IMAGES / row["target_imageFile"]
            if not src.exists():
                missing.append(f"{prefix}/{row['bv_disk_file']}")
                continue
            if not dst.exists():
                shutil.copy2(src, dst)
            staged.append(dst)
    if missing:
        print(f"  ⚠  {len(missing)} BV source files missing: {missing[:5]}...")
    return staged

# ─── Optimize only the new image files ──────────────────────────────
def optimize(staged: list[Path]):
    if not staged:
        print("  (no new images to optimize)")
        return
    from PIL import Image as PILImage
    OPT_QUALITY, OPT_MAX_SIDE = 75, 1200
    THUMB_WIDTH, THUMB_QUALITY = 200, 60

    def process(src: Path):
        stem = src.stem
        opt_dst = R_OPT    / f"{stem}.webp"
        thm_dst = R_THUMBS / f"{stem}.webp"
        if opt_dst.exists() and thm_dst.exists():
            return "skip"
        try:
            img = PILImage.open(src).convert("RGB")
            w, h = img.size
            if not opt_dst.exists():
                scale = min(1.0, OPT_MAX_SIDE / max(w, h))
                opt = img.resize((int(w*scale), int(h*scale)), PILImage.LANCZOS) if scale < 1 else img
                opt.save(opt_dst, "WEBP", quality=OPT_QUALITY)
            if not thm_dst.exists():
                new_h = max(1, int(h * THUMB_WIDTH / w))
                img.resize((THUMB_WIDTH, new_h), PILImage.LANCZOS).save(thm_dst, "WEBP", quality=THUMB_QUALITY)
            return "ok"
        except Exception as e:
            return f"error:{e}"

    ok = skip = err = 0
    with ThreadPoolExecutor(max_workers=6) as ex:
        for fut in as_completed({ex.submit(process, f): f for f in staged}):
            r = fut.result()
            if r == "ok": ok += 1
            elif r == "skip": skip += 1
            else: err += 1
    print(f"  Optimized: {ok}   Skipped: {skip}   Errors: {err}")

# ─── Regenerate downstream bundles in research ──────────────────────
def regen_research_bundles():
    for step in (5, 6, 8, 9):
        print(f"  reconcile_all.py --step {step}")
        res = subprocess.run(
            [sys.executable, "reconcile_all.py", "--step", str(step)],
            cwd=RESEARCH, capture_output=True, text=True,
        )
        if res.returncode != 0:
            print(res.stdout); print(res.stderr, file=sys.stderr)
            raise RuntimeError(f"reconcile_all.py --step {step} failed")
        tail = [l for l in res.stdout.splitlines() if l.strip()][-4:]
        for l in tail: print(f"    {l}")

# ─── Sync bundles into the BOBA-Playbook repo ───────────────────────
def sync_to_app_repo() -> dict:
    sync = {
        "cards.json":         (R_DATA / "cards.json",         APP_DATA / "cards.json"),
        "cards-slim.json":    (R_DATA / "cards-slim.json",    APP_DATA / "cards-slim.json"),
        "categories.json":    (R_DATA / "categories.json",    APP_DATA / "categories.json"),
        "search-index.json":  (R_DATA / "search-index.json",  APP_DATA / "search-index.json"),
        "missing-cards.json": (R_DATA / "missing-cards.json", APP_DATA / "missing-cards.json"),
    }
    out = {}
    for name, (src, dst) in sync.items():
        if not src.exists():
            print(f"  ⚠ {name}: source missing, skipped"); continue
        shutil.copy2(src, dst)
        out[name] = dst.stat().st_size
    return out

def build_ios_bundles() -> dict:
    cards = json.loads((APP_DATA / "cards.json").read_text())
    # Include every cardType — sealed products are part of the catalog
    # and the app is expected to render them alongside heroes/plays/
    # hot dogs. (Earlier versions of the pipeline dropped Sealed Product
    # from the iOS bundle; that was reversed 2026-04-22 after the Find
    # tab's card-purpose filter surfaced them as missing.)
    display = cards
    head = display[:500]
    d_path = APP_IOS / "display-cards.json"
    h_path = APP_IOS / "cards-head.json"
    d_path.write_text(json.dumps(display, separators=(", ", ": "), ensure_ascii=False))
    h_path.write_text(json.dumps(head,    separators=(", ", ": "), ensure_ascii=False))
    return {
        "display-cards.json": (len(display), d_path.stat().st_size),
        "cards-head.json":    (len(head),    h_path.stat().st_size),
    }

# ─── Main ───────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Apply a multi-prefix handoff batch.")
    ap.add_argument("batch_dir", type=Path,
                    help="Batch directory containing BATCH_SUMMARY.json + per-prefix subdirs")
    args = ap.parse_args()

    batch_dir: Path = args.batch_dir
    if not batch_dir.is_absolute():
        batch_dir = (Path.cwd() / batch_dir).resolve()

    summary = json.loads((batch_dir / "BATCH_SUMMARY.json").read_text())
    prefixes = [p["prefix"].lower() for p in summary["prefixes"]]
    print(f"== Handoff batch: {batch_dir.name} ==")
    print(f"   {len(prefixes)} prefixes: {', '.join(prefixes)}")
    print(f"   Expected: +{summary['total_new_records']} records, {summary['total_images_ready']} BV images")

    print("\n[1/5] Merging records into research cards.json")
    added, total, _ = merge_all(batch_dir, prefixes)
    print(f"  Added {added} records; catalog now {total}")

    print("\n[2/5] Staging BV images")
    staged = stage_all_images(batch_dir, prefixes)
    print(f"  Staged {len(staged)} image files")

    print("\n[3/5] Optimizing new images → images-optimized/ + thumbs/")
    optimize(staged)

    print("\n[4/5] Regenerating bundles via reconcile_all.py")
    regen_research_bundles()

    print("\n[5/5] Syncing bundles to BOBA-Playbook repo")
    synced = sync_to_app_repo()
    for name, size in synced.items():
        print(f"  {name}: {size:,} bytes")
    ios = build_ios_bundles()
    for name, (count, size) in ios.items():
        print(f"  {name}: {count:,} cards, {size:,} bytes")

    print("\n✓ Done.")

if __name__ == "__main__":
    main()
