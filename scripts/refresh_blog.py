#!/usr/bin/env python3
"""
refresh_blog.py — refresh docs/blog-feed.json from the official BoBA
blog (https://bobattlearena.com/blog).

The public blog page renders post titles + slugs + excerpts in plain
HTML (it's a server-side-rendered Next.js / static export). We scrape
the listing page once per run, extract title / url / excerpt for the
latest posts, and write a tiny JSON feed the autonomous /loop mines
for content + feature ideas.

Two sources tried in order:
  1. **Listing scrape** — primary; the /blog page already includes
     title + slug + excerpt for the featured + recent + grid sections.
  2. **WP REST fallback** — promo.bobattlearena.com/wp-json/wp/v2/posts
     returns slug + date + title even when the listing scrape fails.
     Excerpt / content are usually blank there but we at least get the
     post existence + date.

Output: docs/blog-feed.json — committed. The autonomous /loop reads
this file at tick start and surfaces unprocessed posts as candidate
work items (autonomous-loop-cadence skill).

Run:
  python3 scripts/refresh_blog.py             # update docs/blog-feed.json
  python3 scripts/refresh_blog.py --check     # exit 1 if drift
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

BLOG_LISTING = "https://bobattlearena.com/blog/all"
WP_POSTS     = "https://promo.bobattlearena.com/wp-json/wp/v2/posts"
PUBLIC_BASE  = "https://bobattlearena.com/blog"
DEFAULT_PATH = Path("docs/blog-feed.json")
POSTS_PER_RUN = 100  # /blog/all has every post; cap generously
WP_PAGES     = 4     # 4 × 25 = 100 posts max from the WP date enrichment


_TAG_RE = re.compile(r"<[^>]+>")


def strip_html(s: str) -> str:
    if not s:
        return ""
    out = _TAG_RE.sub("", s)
    out = html.unescape(out)
    return " ".join(out.split())


def fetch_listing_html() -> str:
    try:
        req = urllib.request.Request(
            BLOG_LISTING,
            headers={
                "User-Agent": "boba-blog-refresh/1",
                "Accept":     "text/html",
            },
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"WARN: listing fetch failed: {e}", file=sys.stderr)
        return ""


# Each post on /blog is an <a href="/blog/{slug}"> … with an inner
# <h2 ... or <h3 ... title and a <p ... excerpt. The page is SSR'd,
# so a single regex over the body is enough. We capture (slug, title,
# excerpt) — excerpt may be missing on the featured tile.
LISTING_POST_RE = re.compile(
    r'<a href="/blog/(?P<slug>[a-z0-9-]+)"[^>]*>'                        # outer link
    r'.*?<(?:h2|h3)[^>]*>\s*(?P<title>.*?)\s*</(?:h2|h3)>'                # title
    r'(?:.*?<p[^>]*>\s*(?P<excerpt>.*?)\s*</p>)?',                       # optional excerpt
    re.DOTALL,
)


def scrape_listing(htmltext: str) -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for m in LISTING_POST_RE.finditer(htmltext):
        slug = m.group("slug")
        if slug in seen or slug == "all":
            continue
        seen.add(slug)
        title   = strip_html(m.group("title") or "")
        excerpt = strip_html(m.group("excerpt") or "")
        if not title:
            continue
        out.append({
            "id":      slug,
            "title":   title,
            "date":    None,    # filled in from WP fallback if available
            "url":     f"{PUBLIC_BASE}/{slug}",
            "excerpt": excerpt,
        })
        if len(out) >= POSTS_PER_RUN:
            break
    return out


def fetch_wp_dates() -> dict[str, str]:
    """Returns {slug: YYYY-MM-DD} across multiple WP pages. {} on any
    failure — the listing scrape carries the title/excerpt; dates from
    WP just enrich it."""
    out: dict[str, str] = {}
    for page in range(1, WP_PAGES + 1):
        try:
            req = urllib.request.Request(
                f"{WP_POSTS}?per_page=25&page={page}&_fields=date,slug",
                headers={
                    "User-Agent": "boba-blog-refresh/1",
                    "Accept":     "application/json",
                },
            )
            with urllib.request.urlopen(req, timeout=20) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
            print(f"WARN: WP date fetch page {page} failed: {e}", file=sys.stderr)
            break
        if not isinstance(data, list) or not data:
            break
        for p in data:
            slug = p.get("slug")
            if slug:
                out[slug] = (p.get("date") or "").split("T")[0] or ""
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, default=DEFAULT_PATH)
    p.add_argument("--check", action="store_true",
                   help="exit 1 if output would change (no write)")
    args = p.parse_args()

    html_text = fetch_listing_html()
    posts = scrape_listing(html_text) if html_text else []
    dates = fetch_wp_dates()
    for post in posts:
        if not post["date"] and post["id"] in dates:
            post["date"] = dates[post["id"]] or None
    # Sort newest first when we have a date; undated stay where the
    # listing put them (which is roughly newest-first on the live page).
    posts.sort(key=lambda e: (e.get("date") or "0000-00-00"), reverse=True)

    bundle = {
        "version": 1,
        "lastUpdated": dt.date.today().isoformat(),
        "source": PUBLIC_BASE,
        "_refresh": {
            "script":   "scripts/refresh_blog.py",
            "workflow": ".github/workflows/refresh-blog.yml",
            "cadence":  "daily — scrapes title/url/excerpt from the "
                        f"public /blog listing at {BLOG_LISTING}; "
                        "enriches with publication dates from the WP "
                        f"REST endpoint at {WP_POSTS}. The autonomous "
                        "/loop mines this file for unprocessed posts "
                        "to convert into candidate work items.",
        },
        "posts": posts,
    }
    serialized = json.dumps(bundle, indent=2, ensure_ascii=False) + "\n"

    if args.check:
        current = args.output.read_text() if args.output.exists() else ""
        if current == serialized:
            print("No changes.")
            return 0
        print("DRIFT: blog-feed.json would change.")
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(serialized)
    print(f"Wrote {args.output} — {len(posts)} posts (latest: "
          f"{posts[0]['date'] if posts else 'none'}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
