#!/usr/bin/env python3
"""
Tecmo Bowl Edition release-watcher — run daily up to the 2026-06-18 drop.

The full checklist isn't public yet (as of 2026-06-08). This polls the channels
most likely to surface it first and reports anything NEW since the last run, so
we catch the checklist + base-set art the moment it lands:

  1. Official checklist page  bobattlearena.com/checklists/  → a "tecmo" link/PDF
  2. Promo spoiler media       promo.bobattlearena.com WP REST → new card uploads
  3. eBay singles              boba-ebay-proxy Worker         → first secondary singles
  4. Bazooka Vault frontier    bazookavault.com/cards/{id}    → set loads here at/just
                               before release (OPT-IN: only when BV_COOKIE is set)

State persists in pipeline/data/tecmo/watch_state.json so reruns only flag
deltas. Radish (compliance, #056) is link-only and NOT polled.

BV is the highest-leverage early source but needs Ben's two-cookie session
(see bv_catalog_scraper.py header: _bazooka_vault_session + user_id, the FULL
request Cookie header). It rotates/expires, so it CANNOT run unattended — the
BV check runs only when BV_COOKIE is present in the environment and skips
cleanly otherwise. The other three channels are public and cron-safe.

Usage:  python3 pipeline/scripts/tecmo_release_watch.py            # public channels
        BV_COOKIE='<full cookie header>' python3 .../tecmo_release_watch.py   # + BV
Cron:   wire the public-channel run into a daily GH Actions step; run the BV
        check manually (with a fresh cookie) as June 18 approaches.
"""
from __future__ import annotations
import json, os, re, sys, urllib.request, urllib.parse, urllib.error
from pathlib import Path

# Last-known BV catalog frontier (highest valid /cards/{id}); updated in state.
# Verified 2026-06-14: 17751, entire recent band set='Griffey', no Tecmo yet.
BV_FRONTIER_SEED = 17751
BV_CARD_JSON_RE = re.compile(r'\{"card":\{"id":\d+.*?"subscriptionType":"[^"]*"\}', re.DOTALL)

# Carde.io PLAY catalog (public, no auth) — the only structured BoBA card API that
# can run unattended. Mongo game id for "bo-jackson-battle-arena". Baseline count
# verified 2026-06-14: 2461 cards (Alpha/National Show/World Champions/Sandstorm;
# no Griffey, no Tecmo — the gameplay catalog lags the BV collectible vault).
CARDE_GAME_MONGO_ID = "651f3b0e5f72a5fca3f6fe34"
CARDE_PLAY_SEED = 2461
CARDE_CARDS_URL = (f"https://api.carde.io/api/v1/cards/{CARDE_GAME_MONGO_ID}"
                   "?page=1&limit=200")

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


def check_bv_frontier(prev_frontier: int) -> dict:
    """OPT-IN BV check: only runs when BV_COOKIE is set (rotates/expires, can't
    be unattended). Walks upward from the last-known frontier to find the new
    highest valid /cards/{id}, collecting the set labels of any newly-appeared
    cards and flagging Tecmo. Returns a dict the caller prints + persists.

    BV auth needs BOTH _bazooka_vault_session AND user_id — pass the full request
    Cookie header as BV_COOKIE (see bv_catalog_scraper.py header)."""
    cookie = os.environ.get("BV_COOKIE", "").strip()
    if not cookie:
        return {"ran": False, "reason": "BV_COOKIE not set (skipped)",
                "frontier": prev_frontier}
    if "user_id=" not in cookie:
        return {"ran": False, "reason": "BV_COOKIE missing user_id cookie — BV "
                "needs both; pass the full request Cookie header",
                "frontier": prev_frontier}

    def fetch_card(i: int):
        req = urllib.request.Request(f"https://bazookavault.com/cards/{i}",
                                     headers={"User-Agent": UA, "Cookie": cookie,
                                              "Accept": "text/html,*/*"})
        try:
            with urllib.request.urlopen(req, timeout=25) as r:
                if "/login" in r.geturl():
                    return "auth", None
                m = BV_CARD_JSON_RE.search(r.read().decode("utf-8", "replace"))
                return ("ok", json.loads(m.group(0))["card"]) if m else ("nojson", None)
        except urllib.error.HTTPError as e:
            return f"http{e.code}", None
        except Exception:
            return "err", None

    # Auth sanity on a known-good low ID before trusting "frontier unchanged".
    st0, _ = fetch_card(1)
    if st0 == "auth":
        return {"ran": False, "reason": "BV cookie rejected (redirected to /login) "
                "— grab a fresh one", "frontier": prev_frontier}

    # Walk upward from the frontier; BV IDs are contiguous, allow a small gap.
    new_cards, frontier, gap = [], prev_frontier, 0
    i = prev_frontier + 1
    while gap < 15 and i <= prev_frontier + 1000:
        st, card = fetch_card(i)
        if st == "ok":
            frontier, gap = i, 0
            new_cards.append({"id": i, "set": card.get("set"),
                              "name": card.get("name"),
                              "num": card.get("externalCardNumber")})
        else:
            gap += 1
        i += 1

    tecmo = [c for c in new_cards
             if "tecmo" in ((c.get("set") or "") + (c.get("num") or "")).lower()]
    sets = sorted({c.get("set") or "?" for c in new_cards})
    return {"ran": True, "frontier": frontier, "prev_frontier": prev_frontier,
            "moved": frontier - prev_frontier, "new_count": len(new_cards),
            "new_sets": sets, "tecmo_cards": tecmo}


def check_carde_play_catalog(prev_total: int) -> dict:
    """Poll the public Carde.io PLAY catalog (no auth, cron-safe). Reports the
    total card count + flags any Tecmo-slugged card. A jump past the baseline
    means a new set started loading into the gameplay catalog. This LAGS the BV
    collectible vault, but it's the only structured signal that runs unattended."""
    try:
        data = get_json(CARDE_CARDS_URL, timeout=30)
    except Exception as e:
        return {"ran": False, "reason": f"carde fetch failed: {e}", "total": prev_total}
    total = (data.get("pagination") or {}).get("totalResults", prev_total)
    # First page only carries 200 slugs; a Tecmo card may not be on page 1. The
    # total-count delta is the cheap trigger; on a delta the caller pulls more.
    tecmo_on_pg1 = [c for c in (data.get("data") or [])
                    if "tecmo" in (c.get("slug", "") + c.get("name", "")).lower()]
    return {"ran": True, "total": total, "prev_total": prev_total,
            "grew": total - prev_total, "tecmo_pg1": tecmo_on_pg1}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    prev = json.loads(STATE.read_text()) if STATE.exists() else {}

    checklist = check_official_checklist()
    promo = check_promo_media()
    singles = check_ebay_singles()
    bv = check_bv_frontier(int(prev.get("bv_frontier", BV_FRONTIER_SEED)))
    carde = check_carde_play_catalog(int(prev.get("carde_play_total", CARDE_PLAY_SEED)))

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

    if bv.get("ran"):
        print(f"BV frontier: {bv['frontier']}  | moved +{bv['moved']} since last run"
              f"  | new cards: {bv['new_count']}  sets: {bv.get('new_sets') or '—'}")
        for c in (bv.get("tecmo_cards") or [])[:40]:
            print("   + TECMO ", c["id"], c.get("num"), c.get("name"))
    else:
        print(f"BV frontier: not checked — {bv.get('reason')}")

    if carde.get("ran"):
        print(f"Carde.io play catalog: {carde['total']} cards  | grew +{carde['grew']} "
              f"since last run" + ("  ⟵ TECMO on page 1!" if carde.get("tecmo_pg1") else ""))
    else:
        print(f"Carde.io play catalog: not checked — {carde.get('reason')}")

    if new_checklist:
        print("\n*** ACTION: official Tecmo checklist link appeared — parse + ingest. ***")
    if new_singles:
        print("\n*** ACTION: secondary-market singles appeared — eBay art sourcing now viable. ***")
    if bv.get("tecmo_cards"):
        print(f"\n*** ACTION: BV LOADED {len(bv['tecmo_cards'])}+ TECMO cards — run "
              "bv_catalog_scraper.py scan --set Tecmo then download. ***")
    elif bv.get("ran") and bv.get("moved", 0) > 0:
        print(f"\n*** NOTE: BV frontier moved +{bv['moved']} (sets {bv.get('new_sets')}) "
              "but no Tecmo yet — re-check; the set load may be in progress. ***")
    if carde.get("tecmo_pg1") or (carde.get("ran") and carde.get("grew", 0) > 0):
        print(f"\n*** NOTE: Carde.io play catalog grew +{carde.get('grew', 0)} — a set is "
              "loading into the gameplay catalog; pull all pages + check for Tecmo slugs. ***")

    new_state = {
        "checklist_links": checklist,
        "promo_ids": [m["id"] for m in promo],
        "ebay_singles": singles,
        "bv_frontier": bv.get("frontier", prev.get("bv_frontier", BV_FRONTIER_SEED)),
        "carde_play_total": carde.get("total", prev.get("carde_play_total", CARDE_PLAY_SEED)),
    }
    STATE.write_text(json.dumps(new_state, indent=2))


if __name__ == "__main__":
    main()
