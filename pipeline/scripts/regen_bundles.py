#!/usr/bin/env python3
"""
regen_bundles.py — propagate master assets/data/cards.json into every
downstream bundle the apps actually consume.

Bundles regenerated:
  - assets/data/cards-head.json         (web, first 506 cards)
  - BOBAPlaybook/display-cards.json     (iOS, full)
  - BOBAPlaybook/cards-head.json        (iOS, first 506 cards)
  - android/app/src/main/assets/data/cards.json   (Android, subset)

Each bundle has its own key-set (Android drops radishUrl /
rookieInspired / searchTokens; web-head drops rookieInspired /
searchTokens) and its own card-set (Android omits some HotDog +
Play cards; head bundles trim to first 506 of master order). This
script PRESERVES those per-bundle conventions by reading the
existing bundle to learn its key-set + bobaId-set, then projecting
the corresponding master values through that filter.

Run after apply_audit_patch.py modifies cards.json:
    python3 pipeline/scripts/regen_bundles.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
MASTER = REPO / "assets" / "data" / "cards.json"

# (path, head_limit). head_limit=None means use original card-set.
BUNDLES = [
    {
        "path": REPO / "assets" / "data" / "cards-head.json",
        "label": "web-head",
        "head_limit": 506,
        "subset_by_bobaId": False,
    },
    {
        "path": REPO / "BOBAPlaybook" / "display-cards.json",
        "label": "iOS-display",
        "head_limit": None,
        "subset_by_bobaId": False,
    },
    {
        "path": REPO / "BOBAPlaybook" / "cards-head.json",
        "label": "iOS-head",
        "head_limit": 506,
        "subset_by_bobaId": False,
    },
    {
        "path": REPO / "android" / "app" / "src" / "main" / "assets" / "data" / "cards.json",
        "label": "Android",
        "head_limit": None,
        "subset_by_bobaId": True,  # Android omits some cards; preserve
    },
    {
        # Android phase-1 fast-load bundle (first 506 cards). Was
        # missing from this list pre-2026-05-25 and silently drifted
        # off — caused Ben's "Collection shows no cards on Android"
        # report when its bobaIds went stale relative to Supabase.
        "path": REPO / "android" / "app" / "src" / "main" / "assets" / "data" / "cards-head.json",
        "label": "Android-head",
        "head_limit": 506,
        "subset_by_bobaId": False,
    },
]


def main() -> int:
    if not MASTER.exists():
        print(f"FATAL: {MASTER} not found", file=sys.stderr)
        return 1
    with open(MASTER) as f:
        master = json.load(f)
    print(f"[regen] master loaded: {len(master)} cards", flush=True)

    for b in BUNDLES:
        path = b["path"]
        if not path.exists():
            print(f"[regen] {b['label']:<14} SKIP — bundle not present at {path}")
            continue
        with open(path) as f:
            existing = json.load(f)
        if isinstance(existing, dict) and "cards" in existing:
            existing_cards = existing["cards"]
            wrap_in_dict = True
        else:
            existing_cards = existing
            wrap_in_dict = False
        if not existing_cards:
            print(f"[regen] {b['label']:<14} SKIP — empty bundle")
            continue
        # Learn the key-set from the first card. All cards in a bundle
        # share the same key-set per existing convention.
        bundle_keys = list(existing_cards[0].keys())
        bundle_keys_set = set(bundle_keys)

        # NEW FIELD: printRun. If master has it but the bundle's first
        # card doesn't, ADD it to the bundle (the field is new).
        if "printRun" in master[0].keys() or any(c.get("printRun") is not None for c in master):
            if "printRun" not in bundle_keys_set:
                bundle_keys.append("printRun")
                bundle_keys_set.add("printRun")

        # NEW FIELD: searchAliases — per-card alternate-name aliases for
        # search (e.g. ["Skeeball"] on Skeee cards so users typing the
        # printed-on-card name still find them). Add to every bundle
        # except Android's stripped subset (Android already drops the
        # related searchTokens field).
        if any(c.get("searchAliases") for c in master):
            if "searchAliases" not in bundle_keys_set and b["label"] != "Android":
                bundle_keys.append("searchAliases")
                bundle_keys_set.add("searchAliases")
            # Android still gets it — Android-side haystackWords reads it
            # at search time (Android doesn't use a prebuilt index).
            if "searchAliases" not in bundle_keys_set and b["label"] == "Android":
                bundle_keys.append("searchAliases")
                bundle_keys_set.add("searchAliases")

        # OLD FIELD: printedSerial. Drop from any bundle that has it.
        if "printedSerial" in bundle_keys_set:
            bundle_keys = [k for k in bundle_keys if k != "printedSerial"]
            bundle_keys_set.discard("printedSerial")

        # Project ALL master cards through this bundle's key-set.
        # Previously Android dropped 77 cards (HotDog Griffey Edition +
        # Alpha Blast subsets) from a stale sync — this regen heals
        # that gap. Bundle-specific card EXCLUSION isn't a current
        # design rule; if any subset filter is needed in the future,
        # add it explicitly here per platform.
        master_iter = master if b["head_limit"] is None else master[:b["head_limit"]]
        regenerated = [{k: c.get(k) for k in bundle_keys} for c in master_iter]

        out_data = {"cards": regenerated} if wrap_in_dict else regenerated
        # Match existing serialization style (preserve ascii-escape choice
        # by reading the first ~200 bytes of the existing file).
        with open(path, "rb") as f:
            sample = f.read(2000)
        # ensure_ascii heuristic: if the bundle was written with non-ASCII
        # chars literal (e.g. é), use ensure_ascii=False. If it used
        # é escapes, use ensure_ascii=True.
        ensure_ascii = b"\\u00" in sample
        payload = json.dumps(out_data, indent=2, ensure_ascii=ensure_ascii)
        if not payload.endswith("\n"):
            payload += "\n"
        path.write_text(payload)
        old_n = len(existing_cards)
        new_n = len(regenerated)
        delta_str = "" if old_n == new_n else f" (was {old_n})"
        print(f"[regen] {b['label']:<14} OK — {new_n} cards{delta_str}, "
              f"{len(bundle_keys)} keys, ensure_ascii={ensure_ascii}")

    print(f"\n[regen] done. Review changes via `git diff`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
