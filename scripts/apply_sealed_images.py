#!/usr/bin/env python3
"""apply_sealed_images.py — wire R2 sealed images into the catalog.

Sealed product images live on R2 at the SLUGGED bobaId:
    sealed/optimized/{slug_for_file(bobaId)}.webp
    sealed/thumbs/{slug_for_file(bobaId)}.webp

The catalog ships `imageFile: null` on every Sealed Product row, which
is why the iOS / web / Android UI shows no art. This script walks the
catalog, computes the expected slug for each Sealed Product, verifies
the matching R2 object exists, and writes `imageFile: {slug}.webp` +
`imageSource: "R2_SEALED"` + `imageAvailable: true` on the matching
rows across every catalog bundle.

The R2 inventory check happens via the public CDN — no auth required.
Cache is in-process; a card with no matching R2 object is left
untouched (the user-facing UI's nil-imageFile branch still renders the
sealed placeholder).
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CDN_BASE = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev"

BUNDLES = [
    REPO / "assets" / "data" / "cards.json",
    REPO / "assets" / "data" / "cards-head.json",
    REPO / "assets" / "data" / "display-cards.json",
    # cards-slim.json is the source the Android Gradle syncSharedAssets
    # task copies into android/app/src/main/assets/data/cards.json. If
    # we don't backfill sealed imageFiles here too, the next Android
    # build overwrites the updated bundle with a slim file that still
    # has every sealed row's imageFile=null — exactly the bug Ben hit
    # 2026-05-22 ("no sealed product support within the android app").
    REPO / "assets" / "data" / "cards-slim.json",
    REPO / "BOBAPlaybook" / "cards-head.json",
    REPO / "BOBAPlaybook" / "display-cards.json",
    REPO / "android" / "app" / "src" / "main" / "assets" / "data" / "cards.json",
    REPO / "android" / "app" / "src" / "main" / "assets" / "data" / "cards-head.json",
]


def slug_for_file(bid: str) -> str:
    """Match scripts/boba_id.py::slug_for_file exactly. Replace every
    non-alphanumeric (except `-`) with `_`, then collapse repeats and
    trim leading/trailing underscores. Verified to match the actual
    R2 keys via rclone listing."""
    s = re.sub(r"[^A-Za-z0-9\-]+", "_", bid or "")
    s = re.sub(r"_+", "_", s)
    return s.strip("_")


def list_sealed_objects() -> set[str]:
    """Enumerate the R2 sealed/optimized/ prefix. Returns the set of
    bare filenames present (e.g. {'SEALED-alpha-blaster-box-...webp', ...}).

    The R2 public hostname doesn't expose ListBucket directly. We rely
    on rclone (configured remote `r2:`) when available; falls back to
    probing each candidate via HEAD when not. This script is meant to
    run on a machine with rclone configured (the same setup the
    catalog pipeline uses, see ARCHIVE.md 2026-04-13 entries).
    """
    import subprocess
    try:
        proc = subprocess.run(
            ["rclone", "lsf", "r2:boba-card-images/sealed/optimized"],
            capture_output=True, text=True, timeout=60, check=True,
        )
        return set(line.strip() for line in proc.stdout.splitlines() if line.strip())
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        print(f"WARN: rclone unavailable ({e}); falling back to HEAD probing.", file=sys.stderr)
        return set()


def head_exists(url: str) -> bool:
    try:
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=4) as r:
            return r.status == 200
    except Exception:
        return False


def apply_to(path: Path, available: set[str]) -> dict:
    if not path.exists():
        return {"path": str(path), "missing": True}
    cards = json.loads(path.read_text())
    if not isinstance(cards, list):
        return {"path": str(path), "skipped_non_list": True}

    matched = unmatched = changed = 0
    for c in cards:
        if c.get("cardType") != "Sealed Product":
            continue
        bid = c.get("bobaId") or ""
        slug = slug_for_file(bid)
        candidate = f"{slug}.webp"
        # Allow either rclone-derived set OR live HEAD probe.
        is_present = (
            candidate in available
            if available
            else head_exists(f"{CDN_BASE}/sealed/optimized/{candidate}")
        )
        if is_present:
            matched += 1
            if c.get("imageFile") != candidate or c.get("imageAvailable") != True:
                c["imageFile"] = candidate
                c["imageSource"] = "R2_SEALED"
                c["imageAvailable"] = True
                changed += 1
        else:
            unmatched += 1

    path.write_text(json.dumps(cards, indent=2, ensure_ascii=False) + "\n")
    return {
        "path": str(path.relative_to(REPO)),
        "sealed_total": matched + unmatched,
        "with_r2_image": matched,
        "still_missing": unmatched,
        "changed": changed,
    }


def main() -> int:
    available = list_sealed_objects()
    if available:
        print(f"R2 sealed/optimized has {len(available)} object(s).")
    else:
        print("R2 listing unavailable; will HEAD-probe each candidate (slower).")

    for path in BUNDLES:
        stats = apply_to(path, available)
        if stats.get("missing"):
            print(f"  SKIP  {path.relative_to(REPO)} — file missing")
            continue
        print(f"  {stats['with_r2_image']:>3}/{stats['sealed_total']:>3} matched · "
              f"changed={stats['changed']:>3} · {stats['path']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
