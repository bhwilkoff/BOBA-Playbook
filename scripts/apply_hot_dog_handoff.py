#!/usr/bin/env python3
"""Apply Cowork's 2026-04-24 hot-dog alignment handoff to every catalog bundle.

What it does, end to end:

1. Loads the master catalog (`unified-cards/data/cards.json`).
2. Applies `patch.json`:
   - 25 modify entries — update `variation` / `subSet` / `bobaId` on the
     existing 23 Griffey Edition HD records + 2 reclassifications.
   - 59 add entries — new HD records (14 Alpha Update + 30 Alpha Blast +
     15 Griffey Edition).
3. Recomputes `searchTokens` on every touched record (variation/subSet
   changes invalidate the existing tokens; new records ship with
   `searchTokens: null`).
4. Writes the updated catalog back to:
     - upstream `unified-cards/data/cards.json` (master)
     - `assets/data/cards.json` (web)
     - `BOBAPlaybook/display-cards.json` (iOS full)
5. Regenerates `BOBAPlaybook/cards-head.json` (first 500 cards).
6. Regenerates `assets/data/categories.json` (filter dropdown facets).
7. Regenerates `assets/data/search-index.json` (per-token + per-facet
   inverted indexes used by the web app's filter pipeline).
8. Appends the 30 Alpha Blast HD entries from
   `missing-art-additions.json` to `unified-cards/data/missing-cards.json`
   so the existing eBay sourcer picks them up on its next run.
9. Verifies bobaId uniqueness + per-set Hot Dog counts.

Step 8 (Supabase row migration for the 23 changed Griffey HD bobaIds)
is intentionally NOT done by this script — it requires DB credentials
and is a separate operational step. SQL UPDATE pairs are printed at the
end for the operator to run.

Idempotency note: re-running this script after a successful apply will
fail at the modify step because `old_bobaId` lookup will miss (records
have been renamed). That's intentional — it prevents partial-apply
races. Restore from git if you need to re-run.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HANDOFF = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"
    "/handoff-updates-2026-04-24/hot-dog-alignment"
)
RESEARCH = Path(
    "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"
)

MASTER_CARDS = RESEARCH / "unified-cards/data/cards.json"
MASTER_MISSING = RESEARCH / "unified-cards/data/missing-cards.json"
WEB_CARDS = ROOT / "assets/data/cards.json"
WEB_CATEGORIES = ROOT / "assets/data/categories.json"
WEB_INDEX = ROOT / "assets/data/search-index.json"
IOS_DISPLAY = ROOT / "BOBAPlaybook/display-cards.json"
IOS_HEAD = ROOT / "BOBAPlaybook/cards-head.json"

# ─── Search token rebuilder (mirrors reconcile_all.py:_build_search_tokens) ───

def build_search_tokens(*fields) -> list[str]:
    tokens: set[str] = set()
    for field in fields:
        if not field:
            continue
        words = re.split(r"[\s\-_/]+", str(field).lower())
        tokens.update(w for w in words if len(w) > 1)
    return sorted(tokens)


def regen_tokens(card: dict) -> None:
    """Recompute the searchTokens for a card in place. Mirrors the field
    list used in step4 of reconcile_all (cardNumber, hero, element,
    treatment OR variation, variation, set, subSet, athlete)."""
    card["searchTokens"] = build_search_tokens(
        card.get("cardNumber"),
        card.get("hero"),
        card.get("element"),
        card.get("treatment") or card.get("variation"),
        card.get("variation"),
        card.get("set"),
        card.get("subSet"),
        card.get("athleteInspiration"),
    )


# ─── Patch application ───────────────────────────────────────────────────────

def apply_patch(cards: list[dict], patch: dict) -> tuple[int, int]:
    by_old: dict[str, int] = {
        c.get("bobaId") or "": i for i, c in enumerate(cards)
    }
    modified = 0
    for action in patch.get("modify", []):
        old_bid = action["old_bobaId"]
        if old_bid not in by_old:
            raise SystemExit(
                f"modify failed — old_bobaId not found: {old_bid!r}\n"
                "(was the patch already applied? restore from git first)"
            )
        idx = by_old[old_bid]
        cards[idx].update(action["changes"])
        regen_tokens(cards[idx])
        modified += 1
    added = 0
    for new_rec in patch.get("add", []):
        new_rec.pop("_audit_notes", None)
        # New records ship with searchTokens=null; build them now.
        regen_tokens(new_rec)
        cards.append(new_rec)
        added += 1
    return modified, added


# ─── categories.json (port of reconcile_all step8) ───────────────────────────

ELEMENT_RARITY = {
    "BRAWL": "Common", "STEEL": "Common",
    "FIRE": "Rare SP", "ICE": "Rare SP",
    "GLOW": "Ultra Rare", "HEX": "Elite",
    "GUM": "Secret Rare", "SUPER": "Unique 1/1",
}


def build_categories(cards: list[dict]) -> dict:
    sets = defaultdict(lambda: {"count": 0, "subSets": set(), "treatments": set()})
    treatments = defaultdict(lambda: {"count": 0, "elements": set(), "bobaIds": []})
    elements = defaultdict(lambda: {"count": 0, "rarity": ""})
    heroes = defaultdict(lambda: {"count": 0, "bobaIds": [], "athletes": set()})
    card_types: Counter = Counter()
    dbs_tiers: Counter = Counter()
    hd_costs: Counter = Counter()
    play_subtypes: Counter = Counter()

    for c in cards:
        s = c.get("set") or "Unknown"
        t = c.get("treatment") or c.get("variation") or "Unknown"
        e = c.get("element") or ""
        h = c.get("hero") or ""
        ct = c.get("cardType") or "Unknown"
        cn = c.get("cardNumber", "")
        athlete = c.get("athleteInspiration") or ""
        sub = c.get("subSet") or ""

        sets[s]["count"] += 1
        if sub:
            sets[s]["subSets"].add(sub)
        if t:
            sets[s]["treatments"].add(t)

        bid = c.get("bobaId", cn)
        treatments[t]["count"] += 1
        if e:
            treatments[t]["elements"].add(e)
        if bid:
            treatments[t]["bobaIds"].append(bid)
        if e:
            elements[e]["count"] += 1
            elements[e]["rarity"] = ELEMENT_RARITY.get(e, "Unknown")
        if h and ct == "Hero":
            heroes[h]["count"] += 1
            heroes[h]["bobaIds"].append(bid)
            if athlete:
                heroes[h]["athletes"].add(athlete)
        card_types[ct] += 1
        if ct == "Play":
            tier = c.get("dbsTier")
            if tier:
                dbs_tiers[tier] += 1
            hdc = c.get("playCost")
            if isinstance(hdc, int):
                hd_costs[str(hdc)] += 1
            if c.get("isBonusPlay"):
                play_subtypes["BonusPlay"] += 1
            elif c.get("isHTD"):
                play_subtypes["HTD"] += 1
            else:
                play_subtypes["Standard"] += 1

    return {
        "sets": {
            k: {
                "count": v["count"],
                "subSets": sorted(v["subSets"]),
                "treatments": sorted(v["treatments"]),
            }
            for k, v in sorted(sets.items(), key=lambda kv: -kv[1]["count"])
        },
        "treatments": {
            k: {
                "count": v["count"],
                "elements": sorted(v["elements"]),
                "sampleBobaIds": sorted(v["bobaIds"])[:5],
            }
            for k, v in sorted(treatments.items(), key=lambda kv: -kv[1]["count"])
        },
        "elements": {
            k: {"count": v["count"], "rarity": v["rarity"]}
            for k, v in sorted(elements.items(), key=lambda kv: -kv[1]["count"])
        },
        "heroes": {
            k: {
                "count": v["count"],
                "athletes": sorted(v["athletes"]),
                "bobaIds": sorted(v["bobaIds"])[:10],
            }
            for k, v in sorted(heroes.items(), key=lambda kv: kv[0])
        },
        "cardTypes": dict(card_types),
        "dbsTiers": dict(sorted(
            dbs_tiers.items(),
            key=lambda kv: {"Low": 0, "Medium": 1, "High": 2, "Very High": 3}.get(kv[0], 99),
        )),
        "hdCosts": dict(sorted(hd_costs.items(), key=lambda kv: int(kv[0]))),
        "playSubtypes": dict(play_subtypes),
        "totalCards": len(cards),
        "totalWithImages": sum(1 for c in cards if c.get("imageAvailable")),
    }


# ─── search-index.json (port of reconcile_all step9) ─────────────────────────

def power_bucket(p) -> str:
    if p is None:
        return "none"
    p = int(p)
    if p >= 180:
        return "180+"
    if p >= 160:
        return "160-179"
    if p >= 140:
        return "140-159"
    if p >= 120:
        return "120-139"
    if p >= 100:
        return "100-119"
    return "under-100"


def build_search_index(cards: list[dict]) -> dict:
    token_index: dict[str, list[str]] = defaultdict(list)
    by_element: dict[str, list[str]] = defaultdict(list)
    by_set: dict[str, list[str]] = defaultdict(list)
    by_treatment: dict[str, list[str]] = defaultdict(list)
    by_card_type: dict[str, list[str]] = defaultdict(list)
    by_hero: dict[str, list[str]] = defaultdict(list)
    by_power_range: dict[str, list[str]] = defaultdict(list)
    by_dbs_tier: dict[str, list[str]] = defaultdict(list)
    by_hd_cost: dict[str, list[str]] = defaultdict(list)
    by_play_subtype: dict[str, list[str]] = defaultdict(list)
    has_image_index: list[str] = []

    for c in cards:
        bid = c.get("bobaId", "")
        if not bid:
            continue
        for token in c.get("searchTokens") or []:
            token_index[token].append(bid)
        if c.get("element"):
            by_element[c["element"]].append(bid)
        if c.get("set"):
            by_set[c["set"]].append(bid)
        if c.get("treatment") or c.get("variation"):
            by_treatment[c.get("treatment") or c.get("variation")].append(bid)
        if c.get("cardType"):
            by_card_type[c["cardType"]].append(bid)
        if c.get("hero") and c.get("cardType") == "Hero":
            by_hero[c["hero"]].append(bid)
        if c.get("power"):
            by_power_range[power_bucket(c["power"])].append(bid)
        if c.get("cardType") == "Play":
            if c.get("dbsTier"):
                by_dbs_tier[c["dbsTier"]].append(bid)
            hdc = c.get("playCost")
            if isinstance(hdc, int):
                by_hd_cost[str(hdc)].append(bid)
            if c.get("isBonusPlay"):
                by_play_subtype["BonusPlay"].append(bid)
            elif c.get("isHTD"):
                by_play_subtype["HTD"].append(bid)
            else:
                by_play_subtype["Standard"].append(bid)
        if c.get("imageAvailable"):
            has_image_index.append(bid)

    return {
        "tokenIndex": dict(token_index),
        "byElement": dict(by_element),
        "bySet": dict(by_set),
        "byTreatment": dict(by_treatment),
        "byCardType": dict(by_card_type),
        "byHero": dict(by_hero),
        "byPowerRange": dict(by_power_range),
        "byDbsTier": dict(by_dbs_tier),
        "byHdCost": dict(by_hd_cost),
        "byPlaySubtype": dict(by_play_subtype),
        "hasImage": has_image_index,
    }


# ─── Missing-cards append ────────────────────────────────────────────────────

def append_missing_art(additions: list[dict]) -> int:
    if not MASTER_MISSING.exists():
        print(f"  WARN: {MASTER_MISSING} missing, skipping missing-cards append")
        return 0
    missing = json.loads(MASTER_MISSING.read_text())
    missing.setdefault("cards", [])
    existing_ids = {c.get("bobaId") for c in missing["cards"] if c.get("bobaId")}
    appended = 0
    for new in additions:
        if new.get("bobaId") in existing_ids:
            continue
        missing["cards"].append(new)
        appended += 1
    missing.setdefault("summary", {})
    missing["summary"]["missingImages"] = len(missing["cards"])
    # coveragePct + byTreatment will be auto-recomputed on next pipeline run
    MASTER_MISSING.write_text(
        json.dumps(missing, indent=2, ensure_ascii=False)
    )
    return appended


# ─── Verification ────────────────────────────────────────────────────────────

def verify(cards: list[dict]) -> None:
    ids = [c.get("bobaId") for c in cards if c.get("bobaId")]
    dupes = len(ids) - len(set(ids))
    if dupes:
        from collections import Counter as C
        dupe_ids = [k for k, v in C(ids).items() if v > 1]
        raise SystemExit(
            f"  bobaId COLLISION — {dupes} duplicate(s): {dupe_ids[:5]}"
        )
    hd = [c for c in cards if (c.get("treatment") or "").lower() == "hot dog"]
    by_set = Counter(c.get("set") for c in hd)
    print(f"  total cards:          {len(cards):,}")
    print(f"  unique bobaIds:       {len(set(ids)):,}")
    print(f"  Hot Dog records:      {len(hd):,}")
    print(f"  Hot Dogs / set:       {dict(by_set)}")
    expected = {
        "Alpha Update": 30,
        "Alpha Blast": 30,
        "Griffey Edition": 40,
    }
    for s, n in expected.items():
        actual = by_set.get(s, 0)
        ok = "✓" if actual == n else "✗"
        print(f"    {ok} {s}: {actual} (expected {n})")


# ─── Main ────────────────────────────────────────────────────────────────────

def main() -> None:
    print(f"Loading patch: {HANDOFF / 'patch.json'}")
    patch = json.loads((HANDOFF / "patch.json").read_text())
    additions = json.loads(
        (HANDOFF / "missing-art-additions.json").read_text()
    )["cards"]

    print(f"Loading master cards.json: {MASTER_CARDS}")
    cards = json.loads(MASTER_CARDS.read_text())
    print(f"  baseline: {len(cards):,} cards")

    print("Applying patch (modify + add)…")
    modified, added = apply_patch(cards, patch)
    print(f"  modified: {modified}")
    print(f"  added:    {added}")

    print("Verifying…")
    verify(cards)

    # ── Write all bundles ──
    print("\nWriting bundles…")
    # The master uses indent=2 ensure_ascii=False. Match that.
    master_text = json.dumps(cards, indent=2, ensure_ascii=False)
    MASTER_CARDS.write_text(master_text)
    print(f"  wrote {MASTER_CARDS}")
    WEB_CARDS.write_text(master_text)
    print(f"  wrote {WEB_CARDS}")
    # iOS display-cards is fully compact (no whitespace) — verified
    # against the existing file. Saves ~3 MB vs default separators.
    IOS_DISPLAY.write_text(
        json.dumps(cards, ensure_ascii=False, separators=(",", ":"))
    )
    print(f"  wrote {IOS_DISPLAY}")
    # cards-head uses default separators (with spaces) — its size is
    # already trivial (~330 KB) so readability beats compaction.
    IOS_HEAD.write_text(json.dumps(cards[:500], ensure_ascii=False))
    print(f"  wrote {IOS_HEAD}")

    print("\nBuilding categories.json…")
    cats = build_categories(cards)
    cats_text = json.dumps(cats, indent=2, ensure_ascii=False)
    WEB_CATEGORIES.write_text(cats_text)
    print(f"  wrote {WEB_CATEGORIES}")

    print("\nBuilding search-index.json…")
    idx = build_search_index(cards)
    idx_text = json.dumps(idx, indent=2, ensure_ascii=False)
    WEB_INDEX.write_text(idx_text)
    print(f"  wrote {WEB_INDEX} ({len(idx_text):,} bytes)")

    print("\nAppending missing-art entries…")
    n = append_missing_art(additions)
    print(f"  appended {n} entries to {MASTER_MISSING}")

    # ── Print SQL migration commands for the operator ──
    print("\n" + "=" * 62)
    print("  Supabase migration SQL (run separately via dashboard / psql)")
    print("=" * 62)
    pairs = [
        (a["old_bobaId"], a["changes"]["bobaId"])
        for a in patch["modify"]
        if a["changes"].get("bobaId")
    ]
    print(f"-- {len(pairs)} bobaId rename pairs")
    for old, new in pairs:
        old_esc = old.replace("'", "''")
        new_esc = new.replace("'", "''")
        for tbl in ("user_cards", "card_corrections",
                    "card_image_overrides", "deck_cards"):
            print(
                f"UPDATE {tbl} SET boba_id = '{new_esc}' "
                f"WHERE boba_id = '{old_esc}';"
            )
    print("\nDone.")


if __name__ == "__main__":
    main()
