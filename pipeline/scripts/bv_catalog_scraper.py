#!/usr/bin/env python3
"""
Bazooka Vault catalog scraper — cookie-auth, Turnstile-proof.

Refresh of the original research-repo `scrape_bazookasvault.py`. BV's card pages
(`/cards/{id}`) embed a JSON blob with imageUrl + full metadata; the images
themselves are on the public CDN `images.bazookavault.com` (no auth to download).

WHY THIS VERSION: BV now shows a Cloudflare **Turnstile** widget on /login, so an
automated email/password form-POST may be rejected server-side. The reliable path
is **session-cookie auth**: log into BV in your browser (you solve Turnstile once),
copy the `_bazooka_vault_session` cookie, and hand it to this script. We never
automate Turnstile and we use your real session.

The OTHER historical method — listing the public GCS bucket `cardeio-images`
(`rescan_gcs_bucket.py`) — is DEAD for new sets: that bucket's BoBA slice stops
~mid-2025 (no 2026 Griffey, no Tecmo). New art is on the Cloudflare-fronted
`images.bazookavault.com` image API, which is not bucket-listable. So cookie-auth
crawl is the way in for Tecmo Bowl.

GET YOUR COOKIE:
  1. Log into bazookavault.com in a browser.
  2. DevTools → Application/Storage → Cookies → copy the value of `_bazooka_vault_session`.
  3. export BV_COOKIE='<that value>'        # value only, or the full "name=value" string

USAGE:
  # See current catalog size + set breakdown around the new-set ID range
  BV_COOKIE=... python3 pipeline/scripts/bv_catalog_scraper.py probe --start 17000 --end 40000

  # Scan an ID range, keep only rows whose set matches --set, write CSV
  BV_COOKIE=... python3 pipeline/scripts/bv_catalog_scraper.py scan --start 17000 --end 40000 --set "Tecmo"

  # Download the matched cards' art from the public CDN (no auth needed)
  python3 pipeline/scripts/bv_catalog_scraper.py download

OUTPUT (pipeline/data/tecmo/):
  bv_tecmo_scan.csv            — card metadata + imageUrl (bv_scan_results schema)
  bv_art/<filename>.webp       — downloaded card art (gitignored per #011)
"""
from __future__ import annotations
import argparse, csv, json, os, re, sys, time, urllib.request, urllib.error
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

BASE = "https://bazookavault.com"
OUT = Path(__file__).resolve().parents[1] / "data" / "tecmo"
ART = OUT / "bv_art"
CSV_PATH = OUT / "bv_tecmo_scan.csv"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
SCAN_DELAY = 0.45
FIELDS = ["bv_id", "external_card_number", "internal_card_number", "name", "type",
          "set", "sub_set", "variations", "element", "power", "cost",
          "image_url", "is_placeholder", "filename", "download_status", "error"]
PLACEHOLDER = ("hero_back-", "card_back", "Temporary_", "temporary_", "/placeholder")
_JSON_RE = re.compile(r'\{"card":\{"id":\d+.*?"subscriptionType":"[^"]*"\}', re.DOTALL)
_UNSAFE = re.compile(r"[^\w\-.]")


def cookie_header() -> str:
    c = os.environ.get("BV_COOKIE", "").strip()
    if not c:
        sys.exit("Set BV_COOKIE (the _bazooka_vault_session value). See file header.")
    return c if "=" in c else f"_bazooka_vault_session={c}"


def get(url: str, cookie: str | None) -> tuple[int, str, str]:
    headers = {"User-Agent": UA, "Accept": "text/html,*/*"}
    if cookie:
        headers["Cookie"] = cookie
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace"), r.geturl()
    except urllib.error.HTTPError as e:
        return e.code, "", url


def extract(html: str) -> dict | None:
    m = _JSON_RE.search(html)
    if not m:
        return None
    try:
        return json.loads(m.group(0)).get("card")
    except json.JSONDecodeError:
        return None


def is_placeholder(u: str) -> bool:
    return (not u) or any(p in u for p in PLACEHOLDER)


def safe(s) -> str:
    return _UNSAFE.sub("_", str(s or "")).strip("_") or "x"


def filename(card: dict) -> str:
    ext = ".jpg" if card.get("imageUrl", "").endswith(".jpg") else \
          ".png" if card.get("imageUrl", "").endswith(".png") else ".webp"
    parts = [safe(card.get("externalCardNumber", "")), safe(card.get("name", ""))]
    if (el := safe(card.get("element") or "")) != "x":
        parts.append(el)
    if card.get("power"):
        parts.append(f"P{card['power']}")
    return "_".join(parts) + ext


def fetch_card(bv_id: int, cookie: str) -> dict:
    status, html, url = get(f"{BASE}/cards/{bv_id}", cookie)
    if status == 404:
        return {"bv_id": bv_id, "error": "not_found"}
    if "/login" in url:
        return {"bv_id": bv_id, "error": "auth_required"}
    if status != 200:
        return {"bv_id": bv_id, "error": f"http_{status}"}
    card = extract(html)
    if not card:
        return {"bv_id": bv_id, "error": "parse_failed"}
    img = card.get("imageUrl", "")
    ph = is_placeholder(img)
    return {
        "bv_id": bv_id, "external_card_number": card.get("externalCardNumber", ""),
        "internal_card_number": card.get("internalCardNumber", ""), "name": card.get("name", ""),
        "type": card.get("type", ""), "set": card.get("set", ""), "sub_set": card.get("subSet", ""),
        "variations": card.get("variations", ""), "element": card.get("element") or "",
        "power": card.get("power") or "", "cost": card.get("cost") or "", "image_url": img,
        "is_placeholder": "1" if ph else "0", "filename": "" if ph else filename(card),
        "download_status": "", "error": "",
    }


def cmd_probe(a):
    cookie = cookie_header()
    # Sanity: confirm the cookie is valid on a known low ID.
    s0 = fetch_card(1, cookie)
    if s0.get("error") == "auth_required":
        sys.exit("Cookie rejected (got redirected to /login). Re-copy a fresh _bazooka_vault_session.")
    print(f"  cookie OK (id 1 → {s0.get('name','?')!r})")
    sets, last_ok, n = Counter(), 0, 0
    for bv_id in range(a.start, a.end + 1, max(1, a.step)):
        r = fetch_card(bv_id, cookie)
        n += 1
        if not r.get("error"):
            last_ok = bv_id
            sets[r["set"] or "?"] += 1
        time.sleep(SCAN_DELAY)
        if n % 50 == 0:
            print(f"  …probed to {bv_id}, last valid id={last_ok}", file=sys.stderr)
    print(f"\n  sampled {n} ids in [{a.start},{a.end}] step {a.step}; highest valid id seen: {last_ok}")
    print("  set histogram (sampled):")
    for s, c in sets.most_common():
        print(f"    {c:4}  {s}")


def cmd_scan(a):
    cookie = cookie_header()
    OUT.mkdir(parents=True, exist_ok=True)
    want = (a.set or "").lower()
    rows, kept = [], 0
    for bv_id in range(a.start, a.end + 1):
        r = fetch_card(bv_id, cookie)
        if not r.get("error") and (not want or want in (r["set"] or "").lower()):
            rows.append(r)
            kept += 1
        if (bv_id - a.start) % 100 == 0:
            print(f"  id {bv_id} | kept {kept}", file=sys.stderr)
        time.sleep(SCAN_DELAY)
    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in FIELDS})
    print(f"\n  wrote {kept} rows → {CSV_PATH}")
    print("  next: python3 pipeline/scripts/bv_catalog_scraper.py download")


def _dl(row: dict) -> str:
    if row.get("is_placeholder") == "1" or not row.get("image_url") or not row.get("filename"):
        return "skipped"
    dest = ART / row["filename"]
    if dest.exists() and dest.stat().st_size > 1000:
        return "exists"
    try:
        req = urllib.request.Request(row["image_url"], headers={"User-Agent": "BOBA-image-archiver/1.0"})
        with urllib.request.urlopen(req, timeout=30) as r:
            dest.write_bytes(r.read())
        return "ok"
    except Exception as e:
        return f"error:{str(e)[:40]}"


def cmd_download(a):
    if not CSV_PATH.exists():
        sys.exit("No bv_tecmo_scan.csv yet — run `scan` first.")
    ART.mkdir(parents=True, exist_ok=True)
    rows = [r for r in csv.DictReader(open(CSV_PATH, newline="", encoding="utf-8"))
            if r.get("is_placeholder") == "0" and r.get("image_url") and r.get("filename")]
    res = Counter()
    with ThreadPoolExecutor(max_workers=10) as ex:
        for fut in as_completed({ex.submit(_dl, r): r for r in rows}):
            res[fut.result().split(":")[0]] += 1
    print(f"  download: {dict(res)} → {ART}")


def main():
    p = argparse.ArgumentParser(description="Bazooka Vault cookie-auth catalog scraper")
    sub = p.add_subparsers(dest="cmd", required=True)
    pr = sub.add_parser("probe", help="sample an ID range → set histogram + highest valid id")
    pr.add_argument("--start", type=int, default=17000); pr.add_argument("--end", type=int, default=40000)
    pr.add_argument("--step", type=int, default=25); pr.set_defaults(fn=cmd_probe)
    sc = sub.add_parser("scan", help="crawl an ID range, keep rows matching --set, write CSV")
    sc.add_argument("--start", type=int, required=True); sc.add_argument("--end", type=int, required=True)
    sc.add_argument("--set", type=str, default="Tecmo"); sc.set_defaults(fn=cmd_scan)
    dl = sub.add_parser("download", help="download matched art from the public CDN"); dl.set_defaults(fn=cmd_download)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
