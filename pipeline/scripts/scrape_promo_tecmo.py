#!/usr/bin/env python3
"""
Tecmo Bowl Edition spoiler-art harvester — promo.bobattlearena.com.

BoBA hosts pre-release spoiler card art on a separate WordPress install at
promo.bobattlearena.com. Its WP REST API is OPEN (the main bobattlearena.com
/wp-json is locked), so we can enumerate the FULL media library rather than
guess filenames. The official per-card checklist is NOT yet published
(bobattlearena.com/checklists/ has only the Griffey 2026 Edition + older), so
this captures everything the publisher has revealed so far.

NOT a Bazooka Vault / Radish scraper. BV is login+Turnstile-gated (needs Ben's
creds for a fresh crawl); Radish is compliance-off-limits (DECISIONS.md #056) —
we only ever used it as a read-only "has it surfaced?" signal.

Output:
  pipeline/data/tecmo/promo_media_manifest.json   — every media item
  pipeline/data/tecmo/art/<id>-<slug>.<ext>       — downloaded candidate card art

Usage:
  python3 pipeline/scripts/scrape_promo_tecmo.py            # enumerate + download 2026 candidates
  python3 pipeline/scripts/scrape_promo_tecmo.py --no-download
"""
from __future__ import annotations
import json, re, sys, time, urllib.request, urllib.error
from pathlib import Path

BASE = "https://promo.bobattlearena.com/wp-json/wp/v2/media"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
OUT_DIR = Path(__file__).resolve().parents[1] / "data" / "tecmo"
ART_DIR = OUT_DIR / "art"

# Heuristics for "this looks like a single-card spoiler", tuned to the naming
# seen on the Tecmo posts (heronameselway.png, MarinoHexwsig.png, ltautofinal.png,
# ericdickersonfinal.png, ElwayHex*.png, BoJackson_34.png, Touchdown-Bo-Jackson*).
WEAPONS = ("fire", "ice", "hex", "steel", "brawl", "glow", "gum", "super", "alt", "cyber")
CARDISH = re.compile(
    r"(hex|fire|ice|steel|brawl|glow|gum|super|auto|sig|variation|/34|_34|"
    r"touchdown|hero|alt-?art|8-?bit|inspired|ink|parallel|insert|final)",
    re.I,
)
# Obvious non-cards to skip when choosing what to download.
SKIP = re.compile(r"(logo|banner|teaser|box|case|mega|wrapper|hobby|coming|"
                  r"last-call|intro|landing|favicon|icon|background)", re.I)


def fetch_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r), dict(r.headers)


def enumerate_media() -> list[dict]:
    items, page = [], 1
    while True:
        url = (f"{BASE}?per_page=100&page={page}"
               "&_fields=id,date,slug,title,source_url,alt_text,caption,media_details,mime_type")
        try:
            data, hdrs = fetch_json(url)
        except urllib.error.HTTPError as e:
            if e.code == 400:  # past last page
                break
            raise
        if not data:
            break
        items.extend(data)
        total_pages = int(hdrs.get("X-WP-TotalPages", page))
        print(f"  page {page}/{total_pages}: +{len(data)} (total {len(items)})", file=sys.stderr)
        if page >= total_pages:
            break
        page += 1
        time.sleep(0.3)
    return items


def is_card_candidate(m: dict) -> bool:
    blob = " ".join([
        str(m.get("slug", "")),
        (m.get("title") or {}).get("rendered", "") if isinstance(m.get("title"), dict) else "",
        m.get("source_url", ""),
        m.get("alt_text", "") or "",
    ])
    if SKIP.search(blob):
        return False
    if not (m.get("mime_type", "") or "").startswith("image/"):
        return False
    # Card-ish name OR a portrait-ish aspect ratio (cards are 5:7 ~0.71).
    md = m.get("media_details") or {}
    w, h = md.get("width") or 0, md.get("height") or 0
    portraitish = bool(w and h and 0.6 <= (w / h) <= 0.85)
    return bool(CARDISH.search(blob)) or portraitish


def download(url: str, dest: Path):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        dest.write_bytes(r.read())


def main():
    no_dl = "--no-download" in sys.argv
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ART_DIR.mkdir(parents=True, exist_ok=True)

    print("Enumerating promo.bobattlearena.com media library…", file=sys.stderr)
    media = enumerate_media()

    # Focus on the Tecmo spoiler window: uploads from 2025-08 onward.
    recent = [m for m in media if (m.get("date") or "") >= "2025-08-01"]
    candidates = [m for m in recent if is_card_candidate(m)]

    manifest = {
        "source": "promo.bobattlearena.com WP REST media",
        "total_media": len(media),
        "recent_since_2025_08": len(recent),
        "card_candidates": len(candidates),
        "candidates": [
            {
                "id": m["id"],
                "date": m.get("date"),
                "slug": m.get("slug"),
                "title": (m.get("title") or {}).get("rendered", "") if isinstance(m.get("title"), dict) else "",
                "alt": m.get("alt_text"),
                "source_url": m.get("source_url"),
                "width": (m.get("media_details") or {}).get("width"),
                "height": (m.get("media_details") or {}).get("height"),
            }
            for m in candidates
        ],
    }
    (OUT_DIR / "promo_media_manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"\nTotal media: {len(media)} | since 2025-08: {len(recent)} | "
          f"card candidates: {len(candidates)}", file=sys.stderr)

    if no_dl:
        return
    print(f"Downloading {len(candidates)} candidates → {ART_DIR}", file=sys.stderr)
    ok = 0
    for m in candidates:
        url = m["source_url"]
        ext = url.rsplit(".", 1)[-1].split("?")[0][:4]
        dest = ART_DIR / f"{m['id']}-{m.get('slug','')[:50]}.{ext}"
        try:
            download(url, dest)
            ok += 1
        except Exception as e:
            print(f"  ! {url}: {e}", file=sys.stderr)
        time.sleep(0.2)
    print(f"Downloaded {ok}/{len(candidates)} → {ART_DIR}", file=sys.stderr)


if __name__ == "__main__":
    main()
