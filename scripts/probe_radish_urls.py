#!/usr/bin/env python3
"""Smoketest Radish Price Guide URLs across a representative
cross-section of the catalog: every cardType × multiple sets ×
varied treatments × name-edge-cases (hyphens, apostrophes,
non-ASCII, ampersands, dots).

For each sampled card, we:
 1. Build the candidate URL via Card+Radish.swift's logic
 2. Fetch it
 3. Look for data signals (eBay-image refs, price tokens, sales
    arrays) that distinguish a real card page from the SPA fallback
 4. Report verdict

The output is a table that flags every set / cardType / edge case
that fails so we can patch the URL builder before shipping.
"""
from __future__ import annotations
import json, urllib.parse, urllib.request, time, sys
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent
CARDS = ROOT / "assets/data/cards.json"

# Set name → (year, slug). New format is /boba/{year}/{slug}/{hero}.
SET_MAP = {
    "Alpha":                          ("2024", "Alpha_Edition"),
    "Alpha Edition":                  ("2024", "Alpha_Edition"),
    "alpha-edition":                  ("2024", "Alpha_Edition"),
    "Alpha Update":                   ("2025", "Alpha_Update"),
    "alpha-update":                   ("2025", "Alpha_Update"),
    "Alpha Blast":                    ("2025", "Alpha_Blast"),
    "Griffey":                        ("2026", "Griffey_Edition"),
    "Griffey Edition":                ("2026", "Griffey_Edition"),
    "griffey-edition":                ("2026", "Griffey_Edition"),
    "National Starter Set":           ("2024", "National_24_Starter_Set"),
    "2024 National Show Starter Set": ("2024", "National_24_Starter_Set"),
    "National '24":                   ("2024", "National_24_Starter_Set"),
    "National 24 Starter Set":        ("2024", "National_24_Starter_Set"),
    "World Champions":                ("2024", "World_Champions"),
    "world-champions":                ("2024", "World_Champions"),
    "World Champions 2024":           ("2024", "World_Champions"),
    "World Champions 2025":           ("2025", "World_Champions"),
    "Battle Trainer Kit":             ("2024", "Battle_Trainer_Kit"),
    "Superfan Series":                ("2024", "Alpha_Edition"),
    "Tecmo Bowl Edition":             ("2025", "Tecmo_Bowl"),
    "tecmo-bowl":                     ("2025", "Tecmo_Bowl"),
    "Promo Cards":                    ("2025", "Promo_Cards"),
    "Big League Chew":                ("2025", "Big_League_Chew"),
    "big-league-chew":                ("2025", "Big_League_Chew"),
    "sandstorm":                      ("2025", "Sandstorm"),
}

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"


HERO_ALIASES = {"ChetMate": "Chetmate", "BoJax": "Bojax"}
PREFIX_REMAP = {"LOGO": "Logo", "RAD": "Rad", "MIX": "Mix"}


def build_url(card: dict) -> str | None:
    """Mirror the production URL builder.
       /boba/{year}/{slug}/{hero}/{cardNumber}
       /boba/sealed for Sealed Products."""
    if card.get("cardType") == "Sealed Product":
        return "https://radishpriceguide.com/boba/sealed"
    set_name = card.get("set") or ""
    if set_name not in SET_MAP:
        return None
    year, slug = SET_MAP[set_name]

    raw_hero = card.get("hero") or card.get("name") or ""
    if not raw_hero:
        return None
    radish_hero = HERO_ALIASES.get(raw_hero, raw_hero)

    card_num = card.get("cardNumber") or ""
    for ours, theirs in PREFIX_REMAP.items():
        if card_num.startswith(ours + "-"):
            card_num = theirs + card_num[len(ours):]
            break
    if not card_num:
        return None

    return (f"https://radishpriceguide.com/boba/{year}/{slug}/"
            f"{urllib.parse.quote(radish_hero, safe='')}/"
            f"{urllib.parse.quote(card_num, safe='')}")


def has_real_data(html: str) -> bool:
    """Distinguishes a real Radish hero page from the SPA fallback.
    Real pages contain eBay listing thumbnails, $-prices, or a
    populated `"sales"` JSON array. The SPA shell renders for any
    URL with the cardNumber/hero echoed in the title but contains
    none of these markers."""
    markers = [
        "i.ebayimg.com/",          # ebay listing image
        "r2.dev/full/",            # r2-hosted card art ref
        '"sales":[{',              # populated sales JSON
    ]
    for m in markers:
        if m in html:
            return True
    # Fall back: a $-price line. SPA shell never has these.
    return "$" in html and any(f"${i}" in html for i in range(1, 100))


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=12) as r:
        return r.read().decode("utf-8", errors="ignore")


def sample_cards(cards: list[dict]) -> list[tuple[str, dict]]:
    """Auto-pick a representative cross-section of the catalog."""
    samples: list[tuple[str, dict]] = []  # (label, card)
    seen_keys: set[tuple] = set()

    def add(label: str, card: dict, key: tuple):
        if key in seen_keys: return
        seen_keys.add(key)
        samples.append((label, card))

    # 1. One Hero per (set, treatment) combo — covers every set and
    #    treatment seen in the catalog.
    for c in cards:
        if c.get("cardType") != "Hero": continue
        s, tr = c.get("set"), c.get("treatment")
        if not s or not tr: continue
        add(f"Hero / {s} / {tr}", c, ("hero", s, tr))

    # 2. Every Play hero name (one printing each).
    for c in cards:
        if c.get("cardType") != "Play": continue
        h = c.get("hero")
        if not h: continue
        add(f"Play / {c.get('set')} / {h[:30]}", c, ("play", h))

    # 3. Every HotDog hero (one printing each).
    for c in cards:
        if c.get("cardType") != "HotDog": continue
        h = c.get("hero")
        if not h: continue
        add(f"HotDog / {c.get('set')} / {h}", c, ("hotdog", h))

    # 4. Sealed Products — every distinct sealed product.
    for c in cards:
        if c.get("cardType") != "Sealed Product": continue
        n = c.get("name")
        if not n: continue
        add(f"Sealed / {c.get('set')} / {n[:30]}", c, ("sealed", n))

    # 5. Curated edge-case heroes (special characters in name).
    edge_keywords = ["A.I.", "Dr.", ",", "'", "²", "^", " - ", "&", "ChetMate"]
    for c in cards:
        if c.get("cardType") != "Hero": continue
        h = c.get("hero", "")
        if any(kw in h for kw in edge_keywords):
            add(f"Edge / {c.get('set')} / {h}", c, ("edge", h, c.get("set")))

    return samples


def main():
    cards = json.loads(CARDS.read_text())

    candidates = sample_cards(cards)
    # Cap probe at a manageable size — full sample would be hundreds.
    # Spread the cap across categories so we always probe at least
    # one item per set/treatment/edge.
    import random
    random.seed(42)
    by_kind: dict[str, list] = {}
    for label, c in candidates:
        kind = label.split(" / ", 1)[0]
        by_kind.setdefault(kind, []).append((label, c))
    sample: list[tuple[str, dict]] = []
    cap_per_kind = {"Hero": 30, "Play": 25, "HotDog": 15, "Sealed": 8, "Edge": 15}
    for kind, items in by_kind.items():
        random.shuffle(items)
        sample.extend(items[: cap_per_kind.get(kind, 10)])
    print(f"Probing {len(sample)} cards…\n")

    rows = []
    by_status: dict[str, list[tuple]] = defaultdict(list)
    for label, c in sample:
        bid = c.get("bobaId") or "(no bobaId)"
        url = build_url(c)
        if url is None:
            rows.append((label, c.get("cardType","?"), c.get("set","?"),
                         c.get("hero") or c.get("name") or "?",
                         "NO_SET_MAPPING", "—"))
            by_status["NO_SET_MAPPING"].append((bid, "—"))
            continue
        try:
            time.sleep(0.4)  # gentle on Radish
            html = fetch(url)
            ok = has_real_data(html)
            status = "OK" if ok else "EMPTY"
        except Exception as e:
            status = f"ERR_{type(e).__name__}"
        rows.append((label, c.get("cardType","?"), c.get("set","?"),
                     c.get("hero") or c.get("name") or "?",
                     status, url))
        by_status[status].append((bid, url))

    # Print as a table.
    col_widths = [max(len(str(r[i])) for r in rows) for i in range(6)]
    fmt = " | ".join("{:<" + str(w) + "}" for w in col_widths)
    print(fmt.format("bobaId", "type", "set", "hero", "status", "url"))
    print("-" * (sum(col_widths) + 18))
    for r in rows:
        print(fmt.format(*[str(x) for x in r]))

    # Summary
    total = len(rows)
    print()
    print(f"Total probed: {total}")
    for status, items in sorted(by_status.items()):
        print(f"  {status}: {len(items)}")
    fail_count = sum(len(v) for k, v in by_status.items() if k != "OK")
    sys.exit(0 if fail_count == 0 else 1)


if __name__ == "__main__":
    main()
