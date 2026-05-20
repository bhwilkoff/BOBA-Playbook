#!/usr/bin/env python3
"""apply_radish_urls.py — bake canonical Radish URLs into catalog rows.

Reads assets/data/radish-url-map.json (produced by
scripts/build_radish_url_map.py) and writes a canonical `radishUrl`
field on every matching card across every catalog bundle:

    assets/data/cards.json
    assets/data/cards-head.json
    assets/data/display-cards.json
    BOBAPlaybook/cards-head.json
    BOBAPlaybook/display-cards.json
    android/app/src/main/assets/data/cards.json
    android/app/src/main/assets/data/cards-head.json

The lookup key is `{year}/{slug}/{lower(hero)}/{lower(cardnumber)}`
where (year, slug) come from the catalog's `set` field via SET_MAP.
Lowercasing the hero + cardnum normalizes every drift dimension
(RAD vs Rad vs Mix vs MIX vs ChetMate vs Chetmate) automatically.

If no lookup hit, leaves radishUrl null — the iOS/web resolver will
fall back to the existing HEAD-probe candidate list for those cards.

Coverage report at the end tells you how much of the catalog now
has a pre-baked Radish URL.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from collections import Counter

REPO = Path(__file__).resolve().parent.parent
MAP_PATH = REPO / "assets" / "data" / "radish-url-map.json"

BUNDLES = [
    REPO / "assets" / "data" / "cards.json",
    REPO / "assets" / "data" / "cards-head.json",
    REPO / "assets" / "data" / "display-cards.json",
    REPO / "BOBAPlaybook" / "cards-head.json",
    REPO / "BOBAPlaybook" / "display-cards.json",
    REPO / "android" / "app" / "src" / "main" / "assets" / "data" / "cards.json",
    REPO / "android" / "app" / "src" / "main" / "assets" / "data" / "cards-head.json",
]

# Catalog set name → (year, slug) for Radish URL construction. Mirrors
# the SET_MAP in BOBAPlaybook/Models/Card+Radish.swift and js/app.js.
# Heroes can also live across multiple namespaces on Radish — when the
# primary namespace misses, we sweep ALL 13 namespaces from the lookup
# table for the same (hero, cardnum) key.
SET_MAP = {
    "Alpha":                          ("2024", "Alpha_Edition"),
    "Alpha Edition":                  ("2024", "Alpha_Edition"),
    "Alpha Update":                   ("2025", "Alpha_Update"),
    "Alpha Blast":                    ("2025", "Alpha_Blast"),
    "Griffey":                        ("2026", "Griffey_Edition"),
    "Griffey Edition":                ("2026", "Griffey_Edition"),
    "National Starter Set":           ("2024", "National_24_Starter_Set"),
    "2024 National Show Starter Set": ("2024", "National_24_Starter_Set"),
    "National '24":                   ("2024", "National_24_Starter_Set"),
    "National 24 Starter Set":        ("2024", "National_24_Starter_Set"),
    "World Champions":                ("2024", "World_Champions"),
    "World Champions 2024":           ("2024", "World_Champions"),
    "World Champions 2025":           ("2025", "World_Champions"),
    "Battle Trainer Kit":             ("2024", "Battle_Trainer_Kit"),
    "Superfan Series":                ("2024", "Superfan_Series"),
    "Promo Cards":                    ("2025", "Promo_Cards"),
    "Big League Chew":                ("2025", "Big_League_Chew"),
    "Tecmo Bowl Edition":             ("2025", "Tecmo_Bowl"),
}


def build_lookup_helpers(url_map: dict) -> tuple[dict, dict]:
    """Indexes the URL map by key + by (lower_hero, lower_cardnum)
    for cross-namespace fallback."""
    by_full = url_map["map"]
    by_hero_cn: dict[tuple[str, str], list[str]] = {}
    for key, url in by_full.items():
        # key = "year/slug/lowerhero/lowercardnum"
        parts = key.split("/", 3)
        if len(parts) != 4: continue
        year, slug, lhero, lcn = parts
        by_hero_cn.setdefault((lhero, lcn), []).append(f"{year}/{slug}|{url}")
    return by_full, by_hero_cn


def resolve(card: dict, by_full: dict, by_hero_cn: dict) -> str | None:
    """Resolve a single card to its canonical Radish URL. Returns None
    when neither the primary namespace nor any cross-namespace lookup
    finds a hit."""
    set_field = card.get("set", "")
    hero = (card.get("hero") or card.get("name") or "").strip()
    cardnum = card.get("cardNumber", "")
    if not hero or not cardnum: return None
    # Sealed products always link to the sealed-sales index page.
    if card.get("cardType") == "Sealed Product":
        return "https://radishpriceguide.com/boba/sealed"

    primary = SET_MAP.get(set_field)
    lhero = hero.lower()
    lcn = cardnum.lower()

    # Primary namespace lookup.
    if primary:
        y, s = primary
        hit = by_full.get(f"{y}/{s}/{lhero}/{lcn}")
        if hit: return hit

    # Cross-namespace fallback. Same hero+cardnum on a DIFFERENT
    # (year, slug) — catches ChetMate-OKC-2 (catalog says "World
    # Champions" → 2024, Radish hosts at 2025).
    matches = by_hero_cn.get((lhero, lcn), [])
    if matches:
        return matches[0].split("|", 1)[1]
    return None


def apply_to(path: Path, by_full, by_hero_cn) -> dict:
    """Apply the Radish URL bake to one bundle. Returns a stats dict."""
    if not path.exists():
        return {"path": str(path), "missing": True}
    cards = json.loads(path.read_text())
    if not isinstance(cards, list):
        # Some bundles are wrapped in an object — search for the array.
        return {"path": str(path), "skipped_non_list": True}

    set_breakdown = Counter()
    hit = miss = changed = 0
    for c in cards:
        # Track coverage by set for the report.
        s = c.get("set", "")
        url = resolve(c, by_full, by_hero_cn)
        if url:
            hit += 1
            set_breakdown[s] += 1
            if c.get("radishUrl") != url:
                c["radishUrl"] = url
                changed += 1
        else:
            miss += 1

    path.write_text(json.dumps(cards, indent=2, ensure_ascii=False) + "\n")
    return {
        "path": str(path.relative_to(REPO)),
        "total": len(cards),
        "with_radish_url": hit,
        "without_radish_url": miss,
        "changed": changed,
        "coverage_pct": round(hit / len(cards) * 100, 1) if cards else 0,
        "by_set": dict(set_breakdown.most_common()),
    }


def main() -> int:
    if not MAP_PATH.exists():
        print(f"FATAL: {MAP_PATH} doesn't exist. Run scripts/build_radish_url_map.py first.", file=sys.stderr)
        return 2
    url_map = json.loads(MAP_PATH.read_text())
    print(f"Loaded {url_map['totalUrls']:,} canonical Radish URLs (built {url_map['lastBuiltAt']})")
    by_full, by_hero_cn = build_lookup_helpers(url_map)

    for path in BUNDLES:
        stats = apply_to(path, by_full, by_hero_cn)
        if stats.get("missing"):
            print(f"  SKIP  {path.relative_to(REPO)} — file missing")
            continue
        print(f"  {stats['coverage_pct']:5.1f}%  {stats['path']}  "
              f"hit={stats['with_radish_url']:,}  miss={stats['without_radish_url']:,}  "
              f"changed={stats['changed']:,}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
