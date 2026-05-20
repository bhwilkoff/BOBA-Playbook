#!/usr/bin/env python3
"""build_radish_url_map.py — Radish URL → catalog lookup table.

Pulls Radish's sitemap (~4 MB, ~18k canonical card URLs), parses every
5-segment /boba/{year}/{slug}/{hero}/{treatment}/{cardnum} URL, and
writes a JSON lookup table that resolves any catalog
(set, hero, cardNumber) tuple to a canonical Radish URL — including
all the casing / treatment-in-path / cross-year drift we've documented
(DECISIONS.md TODO + RADISH_PARTNERSHIP_CALL.md §8).

Output:
    assets/data/radish-url-map.json
        {
          "lastBuiltAt": "2026-05-20T21:30:00Z",
          "totalUrls":   17963,
          "namespaces":  ["2024/Alpha_Edition", ...],
          "map": {
            "{year}/{slug}/{lower_hero}/{lower_cardnum}": "https://radishpriceguide.com/boba/.../"
            ...
          }
        }

Indexed by lowercase hero + lowercase cardnum so any input casing
(catalog's UPPERCASE prefixes, Radish's Title-case migration, ChetMate
vs Chetmate) resolves to the SAME key. Apply with scripts/apply_radish_urls.py.

Run weekly to catch Radish-side renames / new sets.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SITEMAP_URL = "https://radishpriceguide.com/sitemap.xml"
OUTPUT_PATH = Path(__file__).resolve().parent.parent / "assets" / "data" / "radish-url-map.json"


def fetch_sitemap(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (BOBA Playbook catalog build)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def parse(xml: str) -> dict:
    """Extract canonical URLs and build the lookup table."""
    locs = re.findall(r"<loc>([^<]+)</loc>", xml)

    namespaces: set[tuple[str, str]] = set()
    lookup: dict[str, str] = {}
    skipped_dupe = 0

    for url in locs:
        if "/boba/" not in url:
            continue
        try:
            tail = url.split("/boba/", 1)[1].split("/")
        except (IndexError, ValueError):
            continue
        if len(tail) != 5:
            continue

        year, slug, hero_q, treatment_q, cardnum_q = tail
        # URL-decode each segment (Radish has plenty of %20, %27, etc.)
        try:
            year = urllib.parse.unquote(year)
            slug = urllib.parse.unquote(slug)
            hero = urllib.parse.unquote(hero_q)
            _treatment = urllib.parse.unquote(treatment_q)   # currently unused; kept in URL
            cardnum = urllib.parse.unquote(cardnum_q)
        except UnicodeDecodeError:
            continue

        namespaces.add((year, slug))
        key = f"{year}/{slug}/{hero.lower()}/{cardnum.lower()}"
        if key in lookup and lookup[key] != url:
            # Same hero+cardnum can have multiple TREATMENT pages on Radish
            # (e.g. Maverick FT-1 First Edition vs Maverick FT-1 Battlefoil).
            # Keep the first one we see; downstream is best-effort, and the
            # 4-segment / hero-page URL we'd fall back to is still fine.
            skipped_dupe += 1
            continue
        lookup[key] = url

    out = {
        "lastBuiltAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "source": SITEMAP_URL,
        "totalUrls": len(lookup),
        "totalDuplicateKeysSkipped": skipped_dupe,
        "namespaces": sorted(f"{y}/{s}" for y, s in namespaces),
        "map": lookup,
    }
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sitemap", default=SITEMAP_URL, help="Sitemap URL (default: Radish prod)")
    parser.add_argument("--out", type=Path, default=OUTPUT_PATH, help="Output JSON path")
    parser.add_argument("--input-file", type=Path, help="Read sitemap from local file instead of HTTP fetch")
    args = parser.parse_args()

    if args.input_file:
        print(f"Reading sitemap from {args.input_file}…", flush=True)
        xml = args.input_file.read_text()
    else:
        print(f"Fetching {args.sitemap}…", flush=True)
        try:
            xml = fetch_sitemap(args.sitemap)
        except Exception as e:
            print(f"FATAL: sitemap fetch failed: {e}", file=sys.stderr)
            return 2

    print(f"Parsing {len(xml):,} bytes…", flush=True)
    data = parse(xml)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(data, indent=2, sort_keys=False) + "\n")
    size = args.out.stat().st_size

    print(f"Wrote {args.out} ({size:,} bytes)")
    print(f"  URLs:           {data['totalUrls']:,}")
    print(f"  Duplicate keys: {data['totalDuplicateKeysSkipped']}")
    print(f"  Namespaces:     {len(data['namespaces'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
