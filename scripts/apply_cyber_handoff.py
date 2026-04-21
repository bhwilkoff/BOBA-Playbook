#!/usr/bin/env python3
"""
apply_cyber_handoff.py — one-shot merge of the 2025 Cyber Promo set.

Applies Cowork's handoff-cyber/ payload:
  1. Merges 28 new Cyber records into the research cards.json (idempotent on bobaId).
  2. Copies 27 BV images into unified-cards/images/ under their target bobaIdSlug names.
  3. Optimizes those 27 files → images-optimized/ + thumbs/ (WebP, matches step 11 of reconcile_all.py).
  4. Delegates bundle regeneration to reconcile_all.py (--step 5, 6, 8, 9).
  5. Copies regenerated bundles from research into the BOBA-Playbook repo.
  6. Builds BOBAPlaybook/display-cards.json (cards.json minus Sealed Product) and
     BOBAPlaybook/cards-head.json (first 500 of display).

Run from the BOBA-Playbook repo root. Requires Pillow (already used by reconcile_all.py).
"""

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
HANDOFF      = RESEARCH / "handoff-cyber"

R_DATA       = RESEARCH / "unified-cards" / "data"
R_IMAGES     = RESEARCH / "unified-cards" / "images"
R_OPT        = RESEARCH / "unified-cards" / "images-optimized"
R_THUMBS     = RESEARCH / "unified-cards" / "thumbs"
R_BV_IMAGES  = RESEARCH / "bazookavault-images" / "images"
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

# Mirrors reconcile_all.py::_build_search_tokens — keep in lockstep.
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

# ─── Step 1: merge records ──────────────────────────────────────────
def load_handoff_records() -> list[dict]:
    raw = json.loads((HANDOFF / "cyber_cards_proposed.json").read_text())
    out = []
    for r in raw:
        # Fill in derivable fields
        if not r.get("searchTokens"):
            r["searchTokens"] = build_search_tokens(
                r.get("cardNumber"), r.get("hero"), r.get("element"),
                r.get("treatment"), r.get("variation"), r.get("set"),
                r.get("subSet"), r.get("athleteInspiration"),
            )
        # bvId is null for hand-authored records (no BazookaVault DB row)
        r.setdefault("bvId", None)
        # Strip non-catalog fields (radishUrl, sourceNote, etc.)
        out.append({k: v for k, v in r.items() if k in CATALOG_FIELDS})
    return out

def merge_records(records: list[dict]) -> tuple[int, int]:
    cards = json.loads(R_CARDS.read_text())
    existing = {c.get("bobaId") for c in cards}
    added = 0
    for r in records:
        if r["bobaId"] in existing:
            continue
        cards.append(r)
        added += 1
    # Re-sort so Cyber cards land in natural order (CYB-* after numeric prefixes).
    cards.sort(key=lambda c: sort_key(c.get("cardNumber", "")))
    R_CARDS.write_text(json.dumps(cards, indent=2, ensure_ascii=False))
    return added, len(cards)

# ─── Step 2: stage images ───────────────────────────────────────────
def stage_images() -> list[Path]:
    claims = json.loads((HANDOFF / "cyber_image_claim_map.json").read_text())
    staged: list[Path] = []
    missing: list[str] = []
    for row in claims:
        src = R_BV_IMAGES / row["bv_disk_file"]
        dst = R_IMAGES / row["target_imageFile"]
        if not src.exists():
            missing.append(row["bv_disk_file"])
            continue
        if not dst.exists():
            shutil.copy2(src, dst)
        staged.append(dst)
    if missing:
        print(f"  ⚠  {len(missing)} BV source files missing: {missing[:5]}...")
    return staged

# ─── Step 3: optimize only the new images ───────────────────────────
def optimize(staged: list[Path]):
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
    return ok, skip, err

# ─── Step 4: regenerate downstream bundles in research ──────────────
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
        # Print only the summary lines (last ~6 lines)
        tail = [l for l in res.stdout.splitlines() if l.strip()][-4:]
        for l in tail: print(f"    {l}")

# ─── Step 5: sync bundles into the BOBA-Playbook repo ───────────────
def sync_to_app_repo() -> dict:
    sync = {
        "cards.json":         (R_DATA / "cards.json",         APP_DATA / "cards.json"),
        "cards-slim.json":    (R_DATA / "cards-slim.json",    APP_DATA / "cards-slim.json"),
        "categories.json":    (R_DATA / "categories.json",    APP_DATA / "categories.json"),
        "search-index.json":  (R_DATA / "search-index.json",  APP_DATA / "search-index.json"),
        "missing-cards.json": (R_DATA / "missing-cards.json", APP_DATA / "missing-cards.json"),
    }
    results = {}
    for name, (src, dst) in sync.items():
        if not src.exists():
            print(f"  ⚠ {name}: source missing, skipped"); continue
        shutil.copy2(src, dst)
        results[name] = dst.stat().st_size
    return results

def build_ios_bundles() -> dict:
    cards = json.loads((APP_DATA / "cards.json").read_text())
    display = [c for c in cards if c.get("cardType") != "Sealed Product"]
    # cards.json is already sorted; display preserves that order
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
    print("== Cyber handoff ==")

    print("\n[1/5] Merging 28 Cyber records into research cards.json")
    records = load_handoff_records()
    added, total = merge_records(records)
    print(f"  Added {added} / {len(records)} (catalog now {total})")

    print("\n[2/5] Staging 27 BV images into unified-cards/images/")
    staged = stage_images()
    print(f"  Staged {len(staged)} files")

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
