# boba-youtube-feed

Cloudflare Worker that aggregates Bo Jackson Battle Arena videos from
YouTube into three categorized feeds (live, short, regular), caches
the result in Workers KV, and serves it to the iOS + web Watch tab.

## Architecture

- **Cron** (`0 */4 * * *`) refreshes feeds every 4 hours.
- **Sources** merged: 6 priority channels' uploads + a free-text
  "Bo Jackson Battle Arena" search.
- **Categorization**: `liveBroadcastContent` → live / live replay /
  Shorts (≤60s + #shorts heuristic) / regular.
- **KV keys**: `boba_videos:{live|short|regular}` and
  `boba_videos:meta` (last refresh stats).
- **Quota cost**: ~120 units per refresh, ~720/day at 4-hour cadence,
  well under the 10k/day free tier.

## First-time deploy

```bash
cd workers/youtube-feed

# 1. Auth Wrangler against your Cloudflare account (already done if
#    you've deployed boba-ebay-proxy from the same machine).
wrangler login

# 2. Create the KV namespace and paste the printed id into
#    wrangler.toml's [[kv_namespaces]] block.
wrangler kv:namespace create YT_KV

# 3. Add the YouTube Data API v3 key as a secret (NEVER commit it).
wrangler secret put YOUTUBE_API_KEY
# (paste the key when prompted)

# 4. Deploy.
wrangler deploy

# 5. Trigger the first refresh manually (cron starts on the next
#    aligned tick, which can be up to 4 hours away).
curl -X POST https://boba-youtube-feed.<your-subdomain>.workers.dev/refresh
```

## Endpoints

```
GET  /              → { live, short, regular, writtenAt }
GET  /?type=live    → { items, writtenAt, count }
GET  /?type=short   → { items, writtenAt, count }
GET  /?type=regular → { items, writtenAt, count }
GET  /health        → { ok, lastRefresh, feedCounts, ... }
POST /refresh       → triggers a fresh fetch + KV write
```

## Item shape

```jsonc
{
  "videoId":      "abc123",
  "title":        "OKC Thunder Champion Box Break!",
  "description":  "...",
  "publishedAt":  "2026-04-28T14:30:00Z",
  "channelId":    "UCxxxxxxxxxxxxxxxxxx",
  "channelTitle": "Radish Dijital",
  "thumbnail":    "https://i.ytimg.com/vi/abc123/maxresdefault.jpg",
  "durationSec":  712,
  "viewCount":    4321,
  "likeCount":    123,
  "commentCount": 17,
  "embeddable":   true,
  "liveBroadcastContent": "none",  // "live" | "upcoming" | "none"
  "liveStreamingDetails": null,    // populated for live + replays
  "priority":     0,               // 0 = pinned channel, 9 = search
  "sourceChannel":"radishdijital", // null when sourced from search
  "url":          "https://www.youtube.com/watch?v=abc123",
  "embedUrl":     "https://www.youtube.com/embed/abc123"
}
```

## Tunables

In `wrangler.toml [vars]`:

- `SEARCH_QUERY` — free-text query (default: `Bo Jackson Battle Arena`).
- `MAX_ITEMS_PER_FEED` — cap each feed (default: 120).
- `PRIORITY_FRESH_DAYS` — within this window, priority channels
  surface first; older priority items fall back to date sort
  (default: 30).

Push changes via `wrangler deploy` (vars-only changes can use
`wrangler vars put <KEY> <VALUE>` for one-off updates).

## Operational notes

- Channel `@handle → channelId` resolution is cached in KV
  (`boba_videos:channel_handles`) after the first refresh — handles
  rarely change. To force re-resolution, delete that key:
  `wrangler kv:key delete --binding=YT_KV boba_videos:channel_handles`.
- The Worker logs to `wrangler tail` if a `videos.list` or
  `playlistItems.list` call returns 4xx/5xx. The most common cause
  is quota exhaustion — quota resets at Pacific midnight.
- Adding/removing channels: edit `KNOWN_CHANNELS` in `worker.js`,
  redeploy, delete `boba_videos:channel_handles` from KV.
