#!/usr/bin/env python3
"""
Tecmo Bowl Edition release-watcher — run daily up to the 2026-06-18 drop.

The full checklist isn't public yet (as of 2026-06-08). This polls the three
channels most likely to surface it first and reports anything NEW since the
last run, so we catch the checklist + base-set art the moment it lands:

  1. Official checklist page  bobattlearena.com/checklists/  → a "tecmo" link/PDF
  2. Promo spoiler media       promo.bobattlearena.com WP REST → new card uploads
  3. eBay singles              boba-ebay-proxy Worker         → first secondary singles

State persists in pipeline/data/tecmo/watch_state.json so reruns only flag
deltas. Bazooka Vault (login+Turnstile) and Radish (compliance, #056) are
intentionally NOT polled here — BV needs Ben's creds; Radish is link-only.

Usage:  python3 pipeline/scripts/tecmo_release_watch.py
Cron:   wire into a daily GH Actions step like the other pipeline watchers.
"""
from __future__ import annotations
import json, re, sys, urllib.request, urllib.parse, urllib.error
from pathlib import Path

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
OUT = Path(__file__).resolve().parents[1] / "data" / "tecmo"
STATE = OUT / "watch_state.json"
EBAY_WORKER = "https://boba-ebay-proxy.benwilkoff.workers.dev/scrape-ebay"


def get(url: str, timeout=25) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def get_json(url: str, timeout=25):
    return json.loads(get(url, timeout))


def check_official_checklist() -> list[str]:
    """Any link on the checklists page mentioning 'tecmo' (page or PDF)."""
    try:
        html = get("https://bobattlearena.com/checklists/")
    except Exception as e:
        return [f"(checklist page fetch failed: {e})"]
    hrefs = re.findall(r'href="([^"]+)"', html)
    return sorted({h for h in hrefs if "tecmo" in h.lower()})


def check_promo_media() -> list[dict]:
    """All promo media uploaded 2026+ (card spoilers land here first)."""
    out, page = [], 1
    while page <= 10:
        url = ("https://promo.bobattlearena.com/wp-json/wp/v2/media"
               f"?per_page=100&page={page}&_fields=id,date,slug,source_url")
        try:
            data = get_json(url)
        except urllib.error.HTTPError:
            break
        except Exception:
            break
        if not data:
            break
        out += [{"id": m["id"], "date": m.get("date"), "url": m.get("source_url")}
                for m in data if (m.get("date") or "") >= "2026-01-01"]
        if len(data) < 100:
            break
        page += 1
    return out


def check_ebay_singles() -> list[str]:
    """eBay listings that look like SINGLES (not sealed boxes/cases/bundles)."""
    q = urllib.parse.quote("Bo Jackson Battle Arena Tecmo Bowl")
    try:
        data = get_json(f"{EBAY_WORKER}?q={q}&limit=50")
    except Exception as e:
        return [f"(ebay worker failed: {e})"]
    items = data.get("items") or data.get("results") or (data if isinstance(data, list) else [])
    sealed = re.compile(r"(hobby box|mega box|double[- ]?mega|case|bundle|sealed|pack|presale|preorder|coming soon)", re.I)
    singles = []
    for it in items:
        t = it.get("title") or it.get("name") or ""
        if t and not sealed.search(t):
            singles.append(t)
    return singles


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    prev = json.loads(STATE.read_text()) if STATE.exists() else {}

    checklist = check_official_checklist()
    promo = check_promo_media()
    singles = check_ebay_singles()

    prev_promo_ids = set(prev.get("promo_ids", []))
    new_promo = [m for m in promo if m["id"] not in prev_promo_ids]
    prev_checklist = set(prev.get("checklist_links", []))
    new_checklist = [c for c in checklist if c not in prev_checklist and not c.startswith("(")]
    prev_singles = set(prev.get("ebay_singles", []))
    new_singles = [s for s in singles if s not in prev_singles and not s.startswith("(")]

    print("=== Tecmo Bowl release watch ===")
    print(f"Official checklist links (tecmo): {len(checklist)}"
          + (f"  ⟵ NEW: {new_checklist}" if new_checklist else ""))
    for c in checklist:
        print("   ·", c)
    print(f"Promo media (2026): {len(promo)}  | NEW since last run: {len(new_promo)}")
    for m in new_promo[:40]:
        print("   + ", m["date"][:10], m["url"])
    print(f"eBay non-sealed (singles?): {len(singles)}  | NEW: {len(new_singles)}")
    for s in new_singles[:40]:
        print("   + ", s[:100])

    if new_checklist:
        print("\n*** ACTION: official Tecmo checklist link appeared — parse + ingest. ***")
    if new_singles:
        print("\n*** ACTION: secondary-market singles appeared — eBay art sourcing now viable. ***")

    STATE.write_text(json.dumps({
        "checklist_links": checklist,
        "promo_ids": [m["id"] for m in promo],
        "ebay_singles": singles,
    }, indent=2))


if __name__ == "__main__":
    main()
