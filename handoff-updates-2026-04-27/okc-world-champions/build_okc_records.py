#!/usr/bin/env python3
"""
Build cards-add.json for the OKC Thunder "World Champion Debut" set
from BoBA's published checklist CSV.

Strategy (mirrors the established LA-/PHI- World Champions records):
  - cardType:   Hero | Play | HotDog
  - set:        "World Champions"
  - subSet:     "2025 - OKC Thunder"
  - variation:  "World Champion Debut" (or "Champions Alt Variation" for OKC-31..36)
  - treatment:  taken from CSV ("Battlefoil" / "Plays" / "Hot Dog")
  - element:    Super→ALT, Hex→HEX, Glow→GLOW, Fire→FIRE, Ice→ICE, Steel→STEEL, "" for non-heroes
  - power:      from CSV
  - playCost:   from CSV (Heroes & Hot Dogs = 0)
  - playAbility: from CSV (Plays only)
  - dbs:        for renamed-reprint Plays, INHERIT from the base play's DBS in
                the 2026-04-27 patch (notation column tells us which base play)
  - imageFile:  null on author (image sourcing follows in a later pass)
  - bobaId:     scripts/boba_id.py formula = "{cardNumber}-{hero or name}-{treatment}-{variation}"
  - searchTokens: derived from name + hero + set tokens + cardNumber

Output:    cards-add.json  (54 records, ready to merge into cards.json)
"""
import csv
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CSV_FILE = HERE / "boba-checklist-2026-04-28.csv"
DBS_PATCH = HERE.parent / "bobaleagues-recon" / "dbs-update-2026-04-27.json"
OUT = HERE / "cards-add.json"

# Build a lookup of base plays by their (lowercased) name → record from the
# 2026-04-27 DBS patch, so we can inherit DBS for renamed-reprint plays.
def load_dbs_lookup() -> dict[str, dict]:
    if not DBS_PATCH.exists():
        return {}
    data = json.loads(DBS_PATCH.read_text())
    out = {}
    for r in data["rows"]:
        key = r["name"].lower().strip()
        # Prefer the U/A/G base printing over HTD reprint for inheritance.
        if key not in out or r["release"] != "HTD":
            out[key] = r
    return out


def dbs_tier(dbs: int | None) -> str | None:
    if dbs is None:
        return None
    if dbs <= 15:
        return "Low"
    if dbs <= 30:
        return "Medium"
    return "High"


def search_tokens(*fields: str) -> list[str]:
    """Tokenize all source fields, lowercase, dedupe, sort."""
    seen = set()
    out = []
    for f in fields:
        if not f:
            continue
        for tok in re.split(r"[\s\-_/(),.]+", f.lower()):
            tok = tok.strip()
            if tok and tok not in seen:
                seen.add(tok)
                out.append(tok)
    return sorted(out)


def athlete_tokens(athlete: str | None) -> list[str]:
    if not athlete or athlete == "N/A":
        return []
    return [t for t in re.split(r"[\s\-]+", athlete.lower()) if t]


def boba_id(card_number: str, name: str, treatment: str, variation: str) -> str:
    # CLAUDE.md formula, with empty fields preserved as trailing dashes.
    return f"{card_number}-{name}-{treatment}-{variation}"


def image_filename_stem(card_number: str, name: str, treatment: str, variation: str) -> str:
    # Mirror existing LA/PHI naming: spaces → underscores; .webp suffix.
    pieces = [card_number, name, treatment, variation]
    return "-".join(p.replace(" ", "_") for p in pieces) + ".webp"


WEAPON_TO_ELEMENT = {
    "Super": "ALT",
    "Hex":   "HEX",
    "Glow":  "GLOW",
    "Fire":  "FIRE",
    "Ice":   "ICE",
    "Steel": "STEEL",
    # Champions Alt Variation rows use uppercase already
    "ALT":   "ALT",
    "HEX":   "HEX",
    "GLOW":  "GLOW",
    "FIRE":  "FIRE",
    "ICE":   "ICE",
    "STEEL": "STEEL",
    "":      "",
}


def parse_notation_for_base_play(notation: str) -> str | None:
    """Notation column is e.g.  '"Mutually Assured Dogstruction" for official play'.
    Return just the base play name if parseable."""
    if not notation:
        return None
    m = re.search(r'"([^"]+)"', notation)
    if m:
        return m.group(1).strip()
    return None


def build_record(row: dict, dbs_lookup: dict[str, dict]) -> dict:
    cn = row["Card #"].strip()
    hero_or_name = row["Hero"].strip()
    variation = row["Variation"].strip()
    treatment = row["Treatment"].strip()
    weapon = row["Weapon"].strip()
    notation = row["Notation"].strip()
    power = int(row["Power"]) if row["Power"].strip() else 0
    athlete = row["Athlete Inspiration"].strip()
    play_cost = int(row["Play Cost"]) if row["Play Cost"].strip() else 0
    play_ability = row["Play Ability"].strip() or None

    # Determine cardType from treatment
    if treatment == "Hot Dog":
        card_type = "HotDog"
    elif treatment == "Plays":
        card_type = "Play"
    else:
        card_type = "Hero"

    element = WEAPON_TO_ELEMENT.get(weapon, "")

    # Inherit DBS for renamed-reprint Plays from the underlying base play.
    dbs_val: int | None = None
    base_play_name: str | None = None
    if card_type == "Play":
        base_play_name = parse_notation_for_base_play(notation)
        if base_play_name:
            base = dbs_lookup.get(base_play_name.lower())
            if base:
                dbs_val = base["dbs"]

    # Search tokens — include athlete name pieces + variation/set tokens
    search_t = search_tokens(
        cn,                         # OKC-1
        hero_or_name,
        variation,
        treatment,
        weapon,
        "World Champions",
        "OKC",
        "Thunder",
        "2025",
        *athlete_tokens(athlete),
    )

    bid = boba_id(cn, hero_or_name, treatment, variation)
    img_stem = image_filename_stem(cn, hero_or_name, treatment, variation)

    rec = {
        "cardNumber": cn,
        "bobaId": bid,
        "bvId": None,
        "name": hero_or_name,
        "hero": hero_or_name,
        "cardType": card_type,
        "set": "World Champions",
        "subSet": "2025 - OKC Thunder",
        "variation": variation,
        "treatment": treatment,
        "element": element,
        "power": power,
        "playCost": play_cost,
        "playAbility": play_ability,
        "isBonusPlay": False,
        "isHTD": False,
        "dbs": dbs_val,
        "dbsTier": dbs_tier(dbs_val),
        "athleteInspiration": athlete if athlete else "N/A",
        "isInspiredInk": False,
        "imageFile": None,
        "imageSource": None,
        "imageAvailable": False,
        "searchTokens": search_t,
        "rookieInspired": False,
        "release": "World Champions",
        # Author note for downstream debugging — strip in production if desired.
        "_authorNote": (
            f"Auto-built from boba-checklist-2026-04-28.csv. "
            f"Image stem (when sourced): {img_stem}. "
            + (f"DBS inherited from base play \"{base_play_name}\" via 2026-04-27 patch."
               if base_play_name else "")
        ),
    }
    return rec


def main():
    if not CSV_FILE.exists():
        sys.exit(f"CSV not found at {CSV_FILE}")
    dbs_lookup = load_dbs_lookup()
    rows: list[dict] = []
    with CSV_FILE.open() as f:
        reader = csv.DictReader(f)
        for r in reader:
            if not r.get("Card #"):
                continue
            rows.append(build_record(r, dbs_lookup))

    # Sanity counters
    by_type: dict[str, int] = {}
    by_element: dict[str, int] = {}
    play_dbs_inherited = 0
    play_dbs_missing = []
    for r in rows:
        by_type[r["cardType"]] = by_type.get(r["cardType"], 0) + 1
        if r["cardType"] == "Hero":
            by_element[r["element"]] = by_element.get(r["element"], 0) + 1
        if r["cardType"] == "Play":
            if r["dbs"] is not None:
                play_dbs_inherited += 1
            else:
                play_dbs_missing.append(r["cardNumber"])

    bobaIds = [r["bobaId"] for r in rows]
    if len(set(bobaIds)) != len(bobaIds):
        # Hot Dog Stormchaser ×7 share name but cardNumber differs, so bobaIds
        # remain unique because the formula includes cardNumber.
        sys.exit("ERROR: duplicate bobaIds — check Hot Dog generation")

    payload = {
        "source_csv": "boba-checklist-2026-04-28.csv",
        "set": "World Champions",
        "subSet": "2025 - OKC Thunder",
        "captured_at": "2026-04-27",
        "total_rows": len(rows),
        "by_type": by_type,
        "by_element": by_element,
        "play_dbs_inherited_count": play_dbs_inherited,
        "play_dbs_missing": play_dbs_missing,
        "rows": rows,
    }
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    print(f"Wrote {len(rows)} rows to {OUT}")
    print(f"By type: {by_type}")
    print(f"By element (heroes): {by_element}")
    print(f"Play DBS inherited from 2026-04-27 patch: {play_dbs_inherited}/{by_type.get('Play', 0)}")
    if play_dbs_missing:
        print(f"  Plays without inherited DBS: {play_dbs_missing}")


if __name__ == "__main__":
    main()
