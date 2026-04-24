#!/usr/bin/env python3
"""
scrape_store_locator.py — pull the official Bo Jackson Battle Arena store
list from bobattlearena.com and normalize it into an app-ready shape.

Background
----------
The store locator page at https://bobattlearena.com/store-locator is an
Astro + Vue SPA whose StoreLocator component fetches everything from
    https://bobattlearena.com/api/stores-cache
as a JSON array of WordPress `store_locator` custom-post entries. The
underlying data lives on `promo.bobattlearena.com` (WordPress + ACF).
Every record carries:
  • name, phone, email, website
  • full formatted address + structured street/city/state/zip/country
  • pre-computed lat/lng (ACF geocoded via Google at edit time)
  • Google Place ID

No auth, no CAPTCHA, public API — the cache endpoint is designed for
the public site to hit it. Scraper is a single GET.

Outputs
-------
store-locator/
  stores-raw-YYYY-MM-DD.json      untouched WordPress payload (archival)
  stores.json                     compact app-ready shape (below)
  stores-summary.md               human-readable stats by region
  manifest.json                   timestamp + counts + checksum

App-ready record shape:
  {
    "id":          9143,
    "name":        "The Hobbies Shop",
    "slug":        "the-hobbies-shop",
    "phone":       "(681)-252-0861",
    "email":       "",
    "website":     "https://www.thehobbiesshop.net/",
    "address": {
      "full":        "305 South West Street, Charles Town, WV 25414, USA",
      "street":      "305 South West Street",
      "city":        "Charles Town",
      "state":       "West Virginia",
      "stateShort":  "WV",
      "postCode":    "25414",
      "country":     "United States",
      "countryShort": "US"
    },
    "location":    { "lat": 39.28617, "lng": -77.86252 },
    "placeId":     "ChIJLc2fVRQBtokR0ZRXDkb1rXo",
    "officialUrl": "https://promo.bobattlearena.com/?store_locator=the-hobbies-shop",
    "modifiedAt":  "2026-04-20T19:10:13Z"
  }

Usage
-----
    python3 scripts/scrape_store_locator.py             # fresh pull
    python3 scripts/scrape_store_locator.py --offline   # re-run normalisation
                                                        # from last raw file
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import sys
import urllib.request
from collections import Counter
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent  # research directory
OUT_DIR = ROOT / "store-locator"
OUT_DIR.mkdir(parents=True, exist_ok=True)

API_URL = "https://bobattlearena.com/api/stores-cache"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36")


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept":     "application/json",
    })
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def latest_raw() -> Path | None:
    candidates = sorted(OUT_DIR.glob("stores-raw-*.json"))
    return candidates[-1] if candidates else None


def _clean(v, *types):
    """Return v if it's one of the allowed types and non-empty-string, else ''."""
    if v is None:
        return ""
    if types and not isinstance(v, types):
        return ""
    if isinstance(v, str):
        return v.strip()
    return v


def _str(v) -> str:
    if v is None:
        return ""
    if isinstance(v, (int, float)):
        # ACF sometimes returns street_number or post_code as int
        return str(v).strip()
    return str(v).strip()


def _iso_gmt(s: str) -> str:
    """Convert WordPress '2026-04-20T19:10:13' (GMT) → '2026-04-20T19:10:13Z'."""
    s = (s or "").strip()
    if not s:
        return ""
    if s.endswith("Z") or "+" in s:
        return s
    return s + "Z"


# US state + Canadian province 2-letter codes, used when parsing fallback
# addresses. Adding extra codes is cheap; the parser only promotes a token
# to `stateShort` when it is exactly in this set.
US_STATES = {
    "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN",
    "IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV",
    "NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN",
    "TX","UT","VT","VA","WA","WV","WI","WY","DC","PR","GU","VI","AS","MP",
}
CA_PROVS = {"AB","BC","MB","NB","NL","NS","ON","PE","QC","SK","NT","NU","YT"}

US_STATE_NAME_TO_SHORT = {
    "alabama":"AL","alaska":"AK","arizona":"AZ","arkansas":"AR","california":"CA",
    "colorado":"CO","connecticut":"CT","delaware":"DE","florida":"FL","georgia":"GA",
    "hawaii":"HI","idaho":"ID","illinois":"IL","indiana":"IN","iowa":"IA","kansas":"KS",
    "kentucky":"KY","louisiana":"LA","maine":"ME","maryland":"MD","massachusetts":"MA",
    "michigan":"MI","minnesota":"MN","mississippi":"MS","missouri":"MO","montana":"MT",
    "nebraska":"NE","nevada":"NV","new hampshire":"NH","new jersey":"NJ","new mexico":"NM",
    "new york":"NY","north carolina":"NC","north dakota":"ND","ohio":"OH","oklahoma":"OK",
    "oregon":"OR","pennsylvania":"PA","rhode island":"RI","south carolina":"SC",
    "south dakota":"SD","tennessee":"TN","texas":"TX","utah":"UT","vermont":"VT",
    "virginia":"VA","washington":"WA","west virginia":"WV","wisconsin":"WI","wyoming":"WY",
    "district of columbia":"DC","puerto rico":"PR",
}


def parse_full_address(full: str) -> dict:
    """Fallback parser for the formatted address string when the structured
    ACF fields come back empty. Handles the two formats seen in the wild:
        '895 S State Rd 135, Greenwood, IN, 46143-9413'
        '923 S 3rd St, Ironton, OH 45638, USA'
        '305 South West Street, Charles Town, WV 25414, USA'
    Returns a dict with whatever fields we can confidently extract.
    """
    import re
    out = {"street": "", "city": "", "stateShort": "", "state": "",
           "postCode": "", "country": "", "countryShort": ""}
    if not full:
        return out

    parts = [p.strip() for p in full.split(",") if p.strip()]
    if not parts:
        return out

    # Trailing 'USA' / 'United States' → peel off
    tail = parts[-1]
    tail_upper = tail.upper()
    if tail_upper in ("USA", "US", "UNITED STATES", "UNITED STATES OF AMERICA"):
        out["country"] = "United States"
        out["countryShort"] = "US"
        parts.pop()
    elif tail_upper in ("CANADA", "CA"):
        out["country"] = "Canada"
        out["countryShort"] = "CA"
        parts.pop()
    # (more country handlers can slot in here as needed)

    if not parts:
        return out

    # Examine the last remaining part — this is either "ST ZIP", "ST", "ZIP",
    # or a bare postcode depending on format.
    last = parts[-1]
    # ST ZIP (zip optional 4-extension)
    m = re.match(r"^([A-Z]{2})\s+(\d{5}(?:-\d{4})?)$", last)
    if m and m.group(1) in US_STATES:
        out["stateShort"] = m.group(1)
        out["postCode"] = m.group(2)
        parts.pop()
    elif last.upper() in US_STATES or last.upper() in CA_PROVS:
        out["stateShort"] = last.upper()
        parts.pop()
    elif re.match(r"^\d{5}(?:-\d{4})?$", last):
        out["postCode"] = last
        parts.pop()
        # Next-to-last might still be the state
        if parts:
            prev = parts[-1].upper()
            if prev in US_STATES or prev in CA_PROVS:
                out["stateShort"] = prev
                parts.pop()

    # Remaining: street, city (and possibly more granular "street" commas).
    # The last remaining part is the city; everything before it is street.
    if parts:
        out["city"] = parts.pop()
    if parts:
        out["street"] = ", ".join(parts)

    # Promote countryShort to US if we derived a US state but no explicit country
    if not out["countryShort"] and out["stateShort"] in US_STATES:
        out["country"] = "United States"
        out["countryShort"] = "US"
    if not out["countryShort"] and out["stateShort"] in CA_PROVS:
        out["country"] = "Canada"
        out["countryShort"] = "CA"

    return out


def _spelled_state_to_short(spelled: str) -> str:
    return US_STATE_NAME_TO_SHORT.get((spelled or "").strip().lower(), "")


def normalise(record: dict) -> dict | None:
    """Transform one WP record into the app-ready shape. Returns None if the
    record is missing essentials (no name OR no lat/lng)."""
    acf = record.get("acf") or {}
    addr = acf.get("address") or {}

    # Essentials: a name and geo coordinates. Skip anything missing either.
    name = _str(acf.get("name")) or _str((record.get("title") or {}).get("rendered"))
    lat  = addr.get("lat")
    lng  = addr.get("lng")
    if not name or lat is None or lng is None:
        return None

    try:
        lat = float(lat)
        lng = float(lng)
    except (TypeError, ValueError):
        return None

    # ACF sometimes populates the structured fields, sometimes leaves them
    # empty and only supplies the formatted `address` string. Build the
    # record from whichever is richer, preferring structured when present.
    full = _str(addr.get("address"))
    fallback = parse_full_address(full) if full else {
        "street": "", "city": "", "stateShort": "", "state": "",
        "postCode": "", "country": "", "countryShort": "",
    }

    structured_street = " ".join(filter(None, [
        _str(addr.get("street_number")),
        _str(addr.get("street_name")),
    ])).strip()

    state_long  = _str(addr.get("state"))
    state_short = _str(addr.get("state_short")) or fallback["stateShort"]
    # If ACF gave us a full state name but no short, derive it
    if not state_short and state_long:
        state_short = _spelled_state_to_short(state_long)
    # Reverse: derive spelled name from code if we only have the code
    if state_short and not state_long and state_short in US_STATES:
        for nm, sh in US_STATE_NAME_TO_SHORT.items():
            if sh == state_short:
                state_long = nm.title()
                break

    country_long  = _str(addr.get("country"))  or fallback["country"]
    country_short = _str(addr.get("country_short")) or fallback["countryShort"]

    return {
        "id":          record.get("id"),
        "name":        name,
        "slug":        _str(record.get("slug")),
        "phone":       _str(acf.get("phone")),
        "email":       _str(acf.get("email")),
        "website":     _str(acf.get("website")),
        "address": {
            "full":         full,
            "street":       structured_street or fallback["street"],
            "city":         _str(addr.get("city"))      or fallback["city"],
            "state":        state_long,
            "stateShort":   state_short,
            "postCode":     _str(addr.get("post_code")) or fallback["postCode"],
            "country":      country_long,
            "countryShort": country_short,
        },
        "location":    {"lat": round(lat, 6), "lng": round(lng, 6)},
        "placeId":     _str(addr.get("place_id")),
        "officialUrl": _str(record.get("link")),
        "modifiedAt":  _iso_gmt(_str(record.get("modified_gmt"))),
    }


def write_summary(path: Path, stores: list[dict], raw_count: int):
    by_country = Counter(s["address"]["countryShort"] or "??" for s in stores)
    by_state = Counter(
        f'{s["address"]["stateShort"] or "??"}'
        for s in stores
        if s["address"]["countryShort"] in ("US", "")
    )
    with_phone   = sum(1 for s in stores if s["phone"])
    with_email   = sum(1 for s in stores if s["email"])
    with_website = sum(1 for s in stores if s["website"])

    lines = [
        "# BOBA Store Locator — Snapshot Summary",
        "",
        f"**Scraped:** {_dt.datetime.now().isoformat(timespec='seconds')}",
        f"**Source:** `{API_URL}`",
        f"**Raw records:** {raw_count:,}",
        f"**Normalized stores (have name + lat/lng):** {len(stores):,}",
        f"**Dropped (missing essentials):** {raw_count - len(stores):,}",
        "",
        "## Contact-info coverage",
        "",
        f"- Phone: {with_phone:,} ({with_phone/len(stores)*100:.1f}%)" if stores else "- No stores",
        f"- Email: {with_email:,} ({with_email/len(stores)*100:.1f}%)" if stores else "",
        f"- Website: {with_website:,} ({with_website/len(stores)*100:.1f}%)" if stores else "",
        "",
        "## By country",
        "",
        "| Country | Stores |",
        "|---|---:|",
    ]
    for country, n in by_country.most_common():
        lines.append(f"| {country} | {n:,} |")
    lines += [
        "",
        "## US stores by state (top 25)",
        "",
        "| State | Stores |",
        "|---|---:|",
    ]
    for state, n in by_state.most_common(25):
        lines.append(f"| {state} | {n:,} |")
    lines += [
        "",
        "## Usage notes for the app location feature",
        "",
        "- Every record has pre-geocoded `location.lat` + `location.lng`. No "
        "runtime geocoding needed. Feed straight into MapKit / Leaflet / "
        "Apple Maps / MapLibre annotations.",
        "- `placeId` is a Google Places ID — useful for 'Open in Google Maps' "
        "deeplinks and Google Places detail calls if you ever want hours / "
        "photos.",
        "- `countryShort` = ISO 3166-1 alpha-2; `stateShort` = USPS for US, "
        "province code for CA / AU. Filter + group by these, not by the "
        "spelled-out `country` / `state` fields.",
        "- `modifiedAt` lets you show relative freshness and detect churn "
        "between scrapes.",
        "",
        "## Re-running",
        "",
        "```",
        "python3 scripts/scrape_store_locator.py",
        "```",
        "",
        "No auth, no rate-limits observed. Safe to run nightly from a cron "
        "or a CI scheduled job.",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--offline", action="store_true",
                    help="Re-run normalisation against the most recent "
                         "stores-raw-*.json instead of fetching fresh data.")
    ap.add_argument("--output", default=None,
                    help="Override output directory (default: research/store-locator/)")
    args = ap.parse_args()

    out_dir = Path(args.output) if args.output else OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    today = _dt.date.today().isoformat()
    raw_path = out_dir / f"stores-raw-{today}.json"

    if args.offline:
        raw = latest_raw()
        if raw is None:
            print("❌ No prior stores-raw-*.json found for --offline.", file=sys.stderr)
            sys.exit(2)
        print(f"→ Offline mode — reusing {raw.name}")
        payload = raw.read_bytes()
        raw_path = raw
    else:
        print(f"→ Fetching {API_URL} …", flush=True)
        try:
            payload = fetch(API_URL)
        except Exception as e:
            print(f"❌ Fetch failed: {e}", file=sys.stderr)
            sys.exit(2)
        raw_path.write_bytes(payload)
        print(f"  wrote {raw_path.name}  ({len(payload):,} bytes)")

    try:
        data = json.loads(payload)
    except json.JSONDecodeError as e:
        print(f"❌ JSON decode failed: {e}", file=sys.stderr)
        sys.exit(2)

    if not isinstance(data, list):
        print(f"❌ Expected a JSON array, got {type(data).__name__}", file=sys.stderr)
        sys.exit(2)

    print(f"→ {len(data):,} raw records")
    stores = [s for s in (normalise(r) for r in data) if s]
    stores.sort(key=lambda s: (s["address"]["countryShort"] or "ZZ",
                               s["address"]["stateShort"] or "ZZ",
                               s["address"]["city"] or "",
                               s["name"]))
    print(f"→ {len(stores):,} normalised stores (dropped {len(data) - len(stores)})")

    stores_path = out_dir / "stores.json"
    stores_path.write_text(
        json.dumps(stores, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"  wrote {stores_path.name}  ({stores_path.stat().st_size:,} bytes)")

    summary_path = out_dir / "stores-summary.md"
    write_summary(summary_path, stores, len(data))
    print(f"  wrote {summary_path.name}")

    manifest = {
        "scraped_at":     _dt.datetime.now().isoformat(timespec="seconds"),
        "source":         API_URL,
        "raw_file":       raw_path.name,
        "stores_file":    stores_path.name,
        "raw_count":      len(data),
        "stores_count":   len(stores),
        "stores_sha256":  hashlib.sha256(stores_path.read_bytes()).hexdigest(),
    }
    (out_dir / "stores-manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8",
    )
    print(f"  wrote stores-manifest.json")

    print()
    print(f"✅ Done. {len(stores):,} stores ready at {stores_path}")


if __name__ == "__main__":
    main()
