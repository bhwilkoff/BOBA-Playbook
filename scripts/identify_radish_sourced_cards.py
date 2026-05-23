#!/usr/bin/env python3
"""
identify_radish_sourced_cards.py — emit the backfill queue for cards
whose canonical image was originally sourced from Radish.

Context: per RADISH_REMOVAL_LOOP.md, the existing R2 image bytes for
the 8,386 RADISH-sourced cards stay on disk (they're our property per
DECISIONS.md #008 + the walk-away analysis §8.1). What we're stopping
is FUTURE Radish sourcing: pipeline/scripts/stage_a_scrape_radish.py +
scripts/build_radish_url_map.py + scripts/apply_radish_urls.py +
scripts/probe_radish_urls.py were deleted in the same loop. To honor
the email's spirit of "stop using Radish-sourced catalog images," we
backfill those 8,386 cards from non-Radish sources (Bazooka Vault
expansion, eBay-image-sourcer, community submissions) and flip the
imageSource field as each card is resourced.

Output:
  - assets/data/radish_backfill_queue.json — bobaId + cardNumber + hero
    + set + treatment per card, in stable id order. Consumable by
    pipeline/scripts/stage_a_scrape_bv.py (which already operates on
    a queue input) and by the future eBay image sourcer.

How to use:
  1. Run this script — generates the queue JSON.
  2. Feed the queue into stage_a_scrape_bv.py (BV CSV has 4× headroom
     per walk-away §8.1, so expect a 70-85% hit rate from BV alone).
  3. For BV misses, run eBay-image-sourcer (to be built per Phase 7+
     of the removal loop).
  4. For remaining gaps, leave attributed to RADISH until the community
     submission flow surfaces a replacement — bytes still serve from R2
     (CLAUDE.md "one card, one image" mantra preserved).
  5. As each card is re-sourced, the merge step updates imageSource on
     the cards.json row to the new provenance (BV / EBAY / mod_upload).

Re-run after a successful backfill batch to see remaining count.

CRITICAL: this script does NOT run any Radish lookups or touch
radishpriceguide.com. It only reads our own cards.json. Per the email,
all automation against Radish is prohibited.
"""

import json
from pathlib import Path

import argparse

REPO_ROOT = Path(__file__).resolve().parent.parent
CARDS_JSON = REPO_ROOT / "assets" / "data" / "cards.json"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", default="RADISH",
                    help="Catalog imageSource value to filter on (RADISH, inherited, etc.)")
    ap.add_argument("--output", default=None,
                    help="Output path (defaults to assets/data/{source}_backfill_queue.json)")
    args = ap.parse_args()

    output_path = (Path(args.output).resolve() if args.output
                   else REPO_ROOT / "assets" / "data" / f"{args.source.lower()}_backfill_queue.json")

    cards = json.loads(CARDS_JSON.read_text())
    filtered = [
        {
            "bobaId": c.get("bobaId"),
            "cardNumber": c.get("cardNumber"),
            "hero": c.get("hero"),
            "name": c.get("name"),
            "set": c.get("set"),
            "subSet": c.get("subSet"),
            "treatment": c.get("treatment"),
            "variation": c.get("variation"),
            "imageFile": c.get("imageFile"),
        }
        for c in cards
        if c.get("imageSource") == args.source
    ]
    filtered.sort(key=lambda r: r["bobaId"] or "")

    output_path.write_text(json.dumps(filtered, indent=2))
    print(f"Wrote {len(filtered):,} cards (imageSource={args.source}) to {output_path.relative_to(REPO_ROOT)}")
    print("Next: feed into pipeline/scripts/stage_a_scrape_bv.py and the eBay image sourcer.")


if __name__ == "__main__":
    main()
