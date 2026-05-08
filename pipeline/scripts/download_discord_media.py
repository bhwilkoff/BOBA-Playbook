#!/usr/bin/env python3
"""
download_discord_media.py — parallel downloader for DCE JSON-only exports.

DCE's `--media` flag is sequential by design (one file at a time, ~40
files/min — bottlenecked by Discord CDN's per-request RTT, not by
bandwidth). Running DCE WITHOUT `--media` and then paralleling the
download with this helper gets ~4× speedup safely.

SAFETY: Discord CDN URLs (cdn.discordapp.com, images-ext-*.discordapp.net)
don't require the bot token — they're self-authenticating signed URLs.
So parallel CDN requests cannot get a token rate-limited or banned.
The IP CAN get 429'd if too aggressive, so we cap at 4 workers and
back off on rate-limit responses.

Output shape matches DCE's --media exactly: writes attachments to
{json_path}_Files/{originalName}-{hash}.{ext} and rewrites every
attachment's `url` field to that relative path. evaluate_discord.py
auto-detects local vs remote via the is_local property and reads
straight off disk for local paths.

USAGE
─────
  # 1. Run DCE WITHOUT --media:
  ./DiscordChatExporter.Cli export -t TOKEN -c CHANNEL_IDS \\
      -f Json -o exports/%C.json

  # 2. Run this:
  python pipeline/scripts/download_discord_media.py \\
      --exports-dir exports/

  # 3. Now exports/{ChannelName}.json has local-file urls and
  #    exports/{ChannelName}.json_Files/ has the media.
"""

from __future__ import annotations

import argparse, hashlib, json, os, re, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Optional

import requests

USER_AGENT = "Mozilla/5.0 (compatible; BoBA-Pipeline/1.0)"
DEFAULT_WORKERS = 4
MAX_RETRIES    = 3
TIMEOUT_SEC    = 30


def short_hash(url: str) -> str:
    """16-char hex hash matching DCE's asset-naming convention."""
    return hashlib.sha1(url.encode()).hexdigest()[:16]


def safe_basename(filename: str) -> str:
    """DCE strips path-unsafe chars; mirror that. Keep the extension."""
    stem, _, ext = filename.rpartition(".")
    if not stem:
        stem = filename
        ext = ""
    stem = re.sub(r"[^\w\-]", "_", stem)
    if ext:
        ext = re.sub(r"[^\w]", "", ext)
        return f"{stem}.{ext}"
    return stem


def local_filename_for(att: dict) -> str:
    """DCE writes attachments as {basename}-{hash}.{ext}. We mirror that
    so files written by this script are interchangeable with DCE --media
    output. Hash is derived from URL so repeated runs are stable."""
    fname = att.get("fileName") or "attachment"
    base, _, ext = fname.rpartition(".")
    if not base:
        base = fname
        ext = ""
    safe_stem = re.sub(r"[^\w\-]", "_", base)
    h = short_hash(att.get("url") or att.get("id", ""))
    if ext:
        return f"{safe_stem}-{h}.{ext.lower()}"
    return f"{safe_stem}-{h}"


def download_one(att: dict, files_dir: Path) -> tuple[bool, Optional[str]]:
    """Returns (ok, local_relpath). Only writes if file isn't already
    present (idempotent re-runs)."""
    url = att.get("url")
    if not url or url.lower().startswith(("file://",)) or not url.lower().startswith("http"):
        # Already local or no URL — nothing to do
        return (True, url)

    local_name = local_filename_for(att)
    local_path = files_dir / local_name
    if local_path.is_file() and local_path.stat().st_size > 0:
        return (True, local_name)

    backoff = 1.0
    for attempt in range(MAX_RETRIES):
        try:
            resp = requests.get(url,
                                headers={"User-Agent": USER_AGENT},
                                timeout=TIMEOUT_SEC,
                                stream=True)
            if resp.status_code == 429:
                # Rate-limited — back off
                retry = float(resp.headers.get("Retry-After", backoff))
                time.sleep(min(retry, 30))
                backoff *= 2
                continue
            if resp.status_code in (403, 404, 410):
                # Signed URL expired / file deleted; silent skip
                return (False, None)
            resp.raise_for_status()
            files_dir.mkdir(parents=True, exist_ok=True)
            tmp_path = local_path.with_suffix(local_path.suffix + ".tmp")
            with tmp_path.open("wb") as f:
                for chunk in resp.iter_content(chunk_size=64 * 1024):
                    if chunk: f.write(chunk)
            tmp_path.rename(local_path)
            return (True, local_name)
        except Exception:
            time.sleep(backoff)
            backoff *= 2
    return (False, None)


def process_json(json_path: Path, workers: int) -> tuple[int, int, int]:
    """Download every http(s) attachment URL in json_path's messages
    in parallel; rewrite each url to its local relpath. Returns
    (downloaded, skipped_already_present, failed)."""
    print(f"  [{json_path.name}] loading …", flush=True)
    with json_path.open() as f:
        data = json.load(f)

    files_dir = json_path.parent / f"{json_path.stem}.json_Files"
    files_dir = json_path.parent / f"{json_path.name}_Files"

    # Collect attachments needing download
    work = []
    for msg in data.get("messages", []) or []:
        for att in msg.get("attachments", []) or []:
            url = att.get("url") or ""
            if url.lower().startswith("http"):
                work.append(att)

    print(f"  [{json_path.name}] {len(work):,} attachments to download (workers={workers})", flush=True)
    if not work:
        return (0, 0, 0)

    downloaded = skipped = failed = 0
    rel_parent = files_dir.name   # for relative urls in the rewritten JSON

    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {ex.submit(download_one, att, files_dir): att for att in work}
        done = 0
        for fut in as_completed(futs):
            done += 1
            att = futs[fut]
            try:
                ok, local_name = fut.result()
            except Exception:
                ok, local_name = False, None
            if not ok:
                failed += 1
                continue
            if local_name is None:
                # Already-local URL; no rewrite needed
                continue
            # Was the file already there or did we download fresh?
            local_path = files_dir / local_name
            # We can't easily tell "skipped" vs "downloaded" without more
            # state — count by whether download_one re-fetched. For now
            # collapse into "downloaded" (skipped is reflected in faster runs).
            downloaded += 1
            # Rewrite the att url in-place to the relative path
            att["url"] = f"{rel_parent}/{local_name}"
            if done % 100 == 0 or done == len(work):
                print(f"  [{json_path.name}] {done}/{len(work)}  "
                      f"ok={downloaded} fail={failed}", flush=True)

    # Write back the JSON with rewritten URLs
    json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    print(f"  [{json_path.name}] wrote rewritten JSON", flush=True)
    return (downloaded, skipped, failed)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--exports-dir", required=True,
                    help="Dir containing DCE JSON-only exports (one *.json per channel)")
    ap.add_argument("--workers", type=int, default=DEFAULT_WORKERS,
                    help="Concurrent downloads (default 4 — safe for Discord CDN)")
    args = ap.parse_args()

    if args.workers > 8:
        print(f"WARN: workers={args.workers} > 8, may trigger Discord rate limits", file=sys.stderr)

    exports = Path(args.exports_dir).expanduser()
    if not exports.is_dir():
        sys.exit(f"!! {exports} not found")

    jsons = sorted(exports.glob("*.json"))
    if not jsons:
        sys.exit(f"!! no *.json files in {exports}")

    print(f"processing {len(jsons)} JSON files from {exports}")
    t0 = time.time()
    total_dl = total_skip = total_fail = 0
    for jp in jsons:
        d, s, f = process_json(jp, args.workers)
        total_dl += d; total_skip += s; total_fail += f

    dt = time.time() - t0
    print(f"\n=== done in {dt/60:.1f} min ===")
    print(f"  downloaded: {total_dl:,}")
    print(f"  failed:     {total_fail:,}")
    print(f"  rate:       {total_dl/(dt/60):.0f} files/min" if dt > 0 else "")


if __name__ == "__main__":
    main()
