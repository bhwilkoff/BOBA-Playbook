#!/usr/bin/env python3
"""
refresh_events.py — refresh assets/data/events.json from live sources.

Two-tier source strategy:
  1. **Official Carde.io events API** — the canonical BoBA-sanctioned
     tournament feed (https://api.carde.io/api/play/events) keyed by
     the BoBA gameId. Filtered to upcoming + future date. Each event
     carries an outbound `url` linking back to play.bobattlearena.com.
  2. **Manually-curated entries** (marked `_curated: true`) are
     PRESERVED across runs — release announcements, in-person events,
     anything Ben adds by hand. They link to the official source URL
     when one exists (blog post / shop page / event page).

Whatnot livestreams were previously merged in under `kind: community`
but were removed 2026-05-21 — they don't belong on the official-events
surface alongside sanctioned tournaments + release announcements. The
Purchase tab still surfaces Whatnot shows via its own dedicated tile
list (`boba-ebay-proxy /whatnot/upcoming`).

Output schema is documented inline in events.json under `_schema`.

Run:
  python3 scripts/refresh_events.py                 # update events.json
  python3 scripts/refresh_events.py --check         # exit 1 if drift
  python3 scripts/refresh_events.py --output PATH   # custom path
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

CARDEIO_EVENTS = "https://api.carde.io/api/play/events"
# Discovered in the play.bobattlearena.com bootstrap config (tick 194).
# This is the BoBA game's stable identifier in Carde.io; if Carde.io
# ever rebrands the BoBA game record, swap this constant.
BOBA_GAME_ID   = "e30530dd-73f7-45be-bfe3-1044edec034a"
DEFAULT_PATH   = Path("assets/data/events.json")


def fetch_cardeio_events() -> list[dict]:
    """Returns the canonical Carde.io events payload (data list).
    Empty list on any failure — refresh shouldn't crash events.json."""
    try:
        # Pull two pages (limit=50 each) — Carde.io paginates and we
        # don't want to miss anything when the upcoming window is busy.
        out: list[dict] = []
        for page in (1, 2):
            req = urllib.request.Request(
                f"{CARDEIO_EVENTS}?limit=50&page={page}",
                headers={
                    "User-Agent": "boba-events-refresh/1",
                    "Accept":     "application/json",
                    "game-id":    BOBA_GAME_ID,
                },
            )
            with urllib.request.urlopen(req, timeout=20) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            page_data = payload.get("data", []) if isinstance(payload, dict) else []
            if not page_data:
                break
            out.extend(page_data)
        return out
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError, KeyError) as e:
        print(f"WARN: Carde.io fetch failed: {e}", file=sys.stderr)
        return []


def cardeio_to_event(ev: dict) -> dict | None:
    """Map a Carde.io event row to events.json shape. Returns None for
    past / non-public / unparseable events. Carde.io marks events as
    upcoming/registration/inProgress/complete via `status`."""
    starts_at = ev.get("startsAt")
    name      = (ev.get("name") or "").strip()
    if not starts_at or not name:
        return None
    status = (ev.get("status") or "").lower()
    if status in ("complete", "completed", "cancelled", "canceled"):
        return None
    if ev.get("public") is False:
        return None
    try:
        sched = dt.datetime.fromisoformat(starts_at.replace("Z", "+00:00"))
    except ValueError:
        return None
    now = dt.datetime.now(dt.timezone.utc)
    # Surface events from now up to 6 months out — past that's noise.
    if sched < now - dt.timedelta(hours=6) or sched > now + dt.timedelta(days=180):
        return None
    addr = ev.get("address") or {}
    location_bits = [b for b in (addr.get("city"), addr.get("state")) if b]
    location = ", ".join(location_bits) if location_bits else None
    activities = ev.get("activities") or []
    format_names = [
        (a.get("name") or "").strip()
        for a in activities if a.get("name")
    ][:4]
    end_iso = None
    if ev.get("endsAt"):
        try:
            end_iso = dt.datetime.fromisoformat(ev["endsAt"].replace("Z", "+00:00")).date().isoformat()
        except ValueError:
            pass
    # Description omits status-machine noise ("Status: published") —
    # the title + url + date + formats already convey everything a
    # reader needs. Carry an optional venue-string into description
    # only when something more than the canned phrase would actually
    # add signal; otherwise leave it absent and let the renderer
    # fall back to formats/location chips.
    out = {
        "id":          f"cardeio-{ev.get('id', starts_at)}",
        "kind":        "tournament",
        "title":       name,
        "date":        sched.date().isoformat(),
        "url":         f"https://play.bobattlearena.com/events/{ev.get('id', '')}",
    }
    if end_iso:        out["endDate"] = end_iso
    if location:       out["location"] = location
    if format_names:   out["formats"]  = format_names
    return out


def load_existing(path: Path) -> dict:
    """Returns the existing events.json dict, or a fresh skeleton."""
    if not path.exists():
        return {"version": 1, "events": []}
    try:
        with path.open() as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {"version": 1, "events": []}


def merge(existing: dict, cardeio_events: list[dict]) -> dict:
    """Preserve curated entries; drop any prior cardeio-* / whatnot-*
    entries and replace with the fresh Carde.io batch. Sort: curated
    first (preserving order), then official tournaments by date asc."""
    events_in = existing.get("events") or []
    curated = [e for e in events_in if isinstance(e, dict) and e.get("_curated") is True]
    sorted_cardeio = sorted(cardeio_events,
                            key=lambda e: (e.get("date") or "", e.get("title") or ""))
    def strip_internal(e: dict) -> dict:
        return {k: v for k, v in e.items() if not k.startswith("_") or k == "_curated"}
    out = dict(existing)
    out["version"]     = existing.get("version", 1)
    out["lastUpdated"] = dt.date.today().isoformat()
    out["events"]      = curated + [strip_internal(e) for e in sorted_cardeio]
    # Preserve _schema + _refresh if present.
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, default=DEFAULT_PATH)
    p.add_argument("--check", action="store_true",
                   help="exit 1 if output would change (no write)")
    args = p.parse_args()

    existing = load_existing(args.output)

    cardeio = fetch_cardeio_events()
    print(f"Fetched {len(cardeio)} Carde.io events; filtering to "
          f"upcoming within 180 days.", file=sys.stderr)
    cardeio_events = [e for e in (cardeio_to_event(ev) for ev in cardeio) if e is not None]
    print(f"  → {len(cardeio_events)} pass filter.", file=sys.stderr)

    merged = merge(existing, cardeio_events)
    serialized = json.dumps(merged, indent=2, ensure_ascii=False) + "\n"

    if args.check:
        current = args.output.read_text() if args.output.exists() else ""
        if current == serialized:
            print("No changes.")
            return 0
        print("DRIFT: events.json would change.")
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(serialized)
    curated_n = sum(1 for e in merged["events"] if e.get("_curated"))
    cardeio_n = sum(1 for e in merged["events"] if str(e.get("id", "")).startswith("cardeio-"))
    print(f"Wrote {args.output} — {curated_n} curated + {cardeio_n} Carde.io "
          f"= {len(merged['events'])} total events.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
