#!/usr/bin/env python3
"""
migrate_v2_bobaid_references.py — replace v2 (4-field) bobaId strings
with v3 (5-field) bobaIds in derived data files that reference cards
by bobaId.

CONTEXT
-------
The v3 migration (DECISIONS.md #057, commit 4b29b64) updated the
master + 5 catalog bundles. But the following files reference cards
BY bobaId and were missed:
  - assets/data/categories.json (web filter category members)
  - assets/data/search-index.json (web search index)
  - android/app/src/main/assets/data/categories.json (Android)
  - android/app/src/main/assets/TemplateDeck.json (iOS + Android)
  - BOBAPlaybook/TemplateDeck.json (iOS)

WHAT THIS DOES
--------------
1. Loads master cards.json. For each card with v3 bobaId, also
   computes its v2 bobaId. Builds a v2 → list-of-v3 map.
2. For each target file, walks the JSON and rewrites every string
   that looks like a v2 bobaId to its v3 equivalent.
3. Logs ambiguous v2 → multiple v3 cases (deterministically picks
   the alphabetically-first match and warns).
4. Logs v2 strings that don't map to any v3 card (probably typos
   or stale references — left as-is).

USAGE
-----
    python3 pipeline/scripts/migrate_v2_bobaid_references.py

Run idempotently; already-v3 strings (5-dash structure) are skipped.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
MASTER = REPO / "assets/data/cards.json"
TARGETS = [
    REPO / "assets/data/categories.json",
    REPO / "assets/data/search-index.json",
    REPO / "android/app/src/main/assets/data/categories.json",
    REPO / "android/app/src/main/assets/TemplateDeck.json",
    REPO / "BOBAPlaybook/TemplateDeck.json",
]


def boba_id_v2(card: dict) -> str:
    cn = str(card.get("cardNumber") or "").strip()
    hero = str(card.get("hero") or card.get("name") or "").strip()
    treat = str(card.get("treatment") or "").strip()
    var = str(card.get("variation") or "").strip()
    return f"{cn}-{hero}-{treat}-{var}"


def build_map(cards: list[dict]) -> dict[str, list[str]]:
    """v2_id → [v3_id, ...] (list-valued for ambiguity reporting)."""
    out: dict[str, list[str]] = {}
    for c in cards:
        v3 = c.get("bobaId")
        if not v3:
            continue
        v2 = boba_id_v2(c)
        out.setdefault(v2, []).append(v3)
    return out


def remap_string(s: str, v2_to_v3: dict[str, list[str]], stats: dict) -> str:
    """If `s` is a v2 bobaId we can map to a unique v3, return v3.
    Otherwise return `s` unchanged (and increment counters)."""
    # Quick reject: strings that don't roughly look like a bobaId
    if "-" not in s:
        return s
    # A v3 bobaId has more dashes than v2; if `s` already in v2_to_v3
    # values, treat as v3 and skip.
    # Simple shape: a bobaId has at least 3 internal dashes.
    if s.count("-") < 3:
        return s
    matches = v2_to_v3.get(s)
    if not matches:
        stats["unmapped"].add(s)
        return s
    if len(matches) > 1:
        # Ambiguous — pick alphabetically first deterministically + log.
        chosen = sorted(matches)[0]
        stats["ambiguous"].setdefault(s, sorted(matches))
        return chosen
    # Unique map.
    stats["mapped"] += 1
    return matches[0]


def walk_and_remap(obj, v2_to_v3, stats):
    """Recursively walk a JSON-loaded structure; rewrite strings that
    match v2 bobaIds. Returns the rewritten structure."""
    if isinstance(obj, str):
        return remap_string(obj, v2_to_v3, stats)
    if isinstance(obj, list):
        return [walk_and_remap(x, v2_to_v3, stats) for x in obj]
    if isinstance(obj, dict):
        # Both keys and values may carry bobaIds.
        new = {}
        for k, v in obj.items():
            new_k = remap_string(k, v2_to_v3, stats) if isinstance(k, str) else k
            new[new_k] = walk_and_remap(v, v2_to_v3, stats)
        return new
    return obj


def main() -> int:
    print(f"[migrate] master: {MASTER}")
    cards = json.loads(MASTER.read_text())
    v2_to_v3 = build_map(cards)
    print(f"[migrate] mapping built: {len(v2_to_v3)} unique v2 bobaIds")
    n_amb = sum(1 for v in v2_to_v3.values() if len(v) > 1)
    if n_amb:
        print(f"[migrate]   of which ambiguous (>1 v3 match): {n_amb}")

    total_rewritten = 0
    for target in TARGETS:
        if not target.exists():
            print(f"[migrate] SKIP (missing): {target}")
            continue
        print(f"\n[migrate] {target}")
        stats = {"mapped": 0, "unmapped": set(), "ambiguous": {}}
        data = json.loads(target.read_text())
        new_data = walk_and_remap(data, v2_to_v3, stats)

        # Preserve original formatting style (indent + ascii) per file.
        # categories.json + search-index.json are compact; TemplateDeck
        # is pretty-printed. Detect by sampling first 200 chars.
        sample = target.read_text()[:400]
        if "\n  " in sample:  # indented
            out = json.dumps(new_data, indent=2, ensure_ascii=False)
        else:  # compact
            out = json.dumps(new_data, separators=(",", ":"), ensure_ascii=False)
        target.write_text(out + ("\n" if sample.endswith("\n") else ""))

        print(f"           mapped: {stats['mapped']} v2→v3")
        if stats["ambiguous"]:
            print(f"           ambiguous (picked first deterministically): {len(stats['ambiguous'])}")
            for v2, picks in list(stats["ambiguous"].items())[:5]:
                print(f"             {v2!r}")
                for p in picks:
                    print(f"               → {p}")
            if len(stats["ambiguous"]) > 5:
                print(f"             … and {len(stats['ambiguous'])-5} more")
        if stats["unmapped"]:
            # Filter out strings that don't look like bobaIds at all
            # (any string with 3+ dashes can trigger a check). Only
            # report ones that contain a likely cardNumber prefix.
            likely_bobaids = {x for x in stats["unmapped"] if x.split("-")[0][:1].isalnum() and len(x.split("-")) >= 4 and len(x) < 200}
            if likely_bobaids:
                print(f"           unmapped bobaId-shaped strings: {len(likely_bobaids)} (left as-is — stale or typo)")
                for x in list(likely_bobaids)[:5]:
                    print(f"             {x!r}")
                if len(likely_bobaids) > 5:
                    print(f"             … and {len(likely_bobaids)-5} more")
        total_rewritten += stats["mapped"]

    print(f"\n[migrate] DONE. Total v2 → v3 rewrites: {total_rewritten}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
