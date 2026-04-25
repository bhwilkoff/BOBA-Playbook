#!/usr/bin/env python3
"""
sync_play_effects_costs.py — Sync `cost` in play-effects.json to
match `playCost` from display-cards.json (the authoritative
catalog from actual card images). The engine reads `card.playCost`
for cost gating, not the JSON entry's `cost` — but the mismatch
shows up in the auditor and is worth fixing for cleanliness.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PE_PATH_IOS = ROOT / "BOBAPlaybook" / "play-effects.json"
PE_PATH_WEB = ROOT / "assets" / "data" / "play-effects.json"
CATALOG_PATH = ROOT / "BOBAPlaybook" / "display-cards.json"


def main() -> int:
    cards = json.loads(CATALOG_PATH.read_text())
    by_name: dict[str, int] = {}
    for c in cards:
        if c.get("cardType") == "Play" and isinstance(c.get("playCost"), int):
            by_name[c["name"]] = c["playCost"]

    raw = json.loads(PE_PATH_IOS.read_text())
    entries = raw.get("entries") or raw

    updated = 0
    for name, entry in entries.items():
        catalog_cost = by_name.get(name)
        if catalog_cost is None:
            continue
        if isinstance(entry.get("cost"), int) and entry["cost"] != catalog_cost:
            entry["cost"] = catalog_cost
            updated += 1

    # Write back to both copies
    out_str = json.dumps(raw, indent=2, ensure_ascii=False) + "\n"
    PE_PATH_IOS.write_text(out_str)
    PE_PATH_WEB.write_text(out_str)
    print(f"✅ Synced {updated} cost(s) to match catalog. Both files updated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
