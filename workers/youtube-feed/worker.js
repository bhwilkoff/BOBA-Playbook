/**
 * BOBA Playbook — YouTube Feed Aggregator
 *
 * Refreshes a curated YouTube feed every 4 hours via cron, caches
 * categorized payloads in KV, serves them through a single HTTP
 * endpoint with CORS so the iOS + web Watch tab can drop them
 * straight into a grid.
 *
 * Sources merged in priority order:
 *   1. The 6 known BoBA-focused channels (full uploads list).
 *   2. A free-text search for "Bo Jackson Battle Arena" — catches
 *      community videos from creators outside the priority list.
 *
 * Every video is hydrated through `videos.list` so we have
 * `liveBroadcastContent`, `liveStreamingDetails`, `duration`, and
 * statistics. Items get classified into one of three feeds:
 *
 *   - live    →  currently live OR a recent live-replay
 *   - short   →  ≤ 60s vertical (Shorts)
 *   - regular →  everything else
 *
 * Each feed is sorted (priority channels first when fresh, then by
 * publish date) and stored at its own KV key. The HTTP handler
 * just reads from KV — no API calls per request.
 *
 * Quota math (all in YouTube Data API v3 units):
 *   search.list      = 100  · once per refresh
 *   channels.list    = 1    · 1× per known channel, cached once resolved
 *   playlistItems    = 1    · 1× per known channel
 *   videos.list      = 1    · 1× per 50 ids
 *   ────────────────────────────────────────────────
 *   ≈120 units / refresh  ·  720 / day at 4h cadence
 *
 * Endpoints (all CORS-enabled, GET):
 *   /                 →  { live, short, regular } combined
 *   /?type=live       →  { items, writtenAt, count }
 *   /?type=short      →  { items, writtenAt, count }
 *   /?type=regular    →  { items, writtenAt, count }
 *   /health           →  { ok: true, lastRefresh, feedCounts }
 *
 * Admin endpoints (POST, no auth — protect by Cloudflare Access if
 * needed):
 *   POST /refresh     →  manual cron trigger; queues a refresh
 *                        and returns immediately.
 */

// ════════════════════════════════════════════════════════════════
// MARK: - Config
// ════════════════════════════════════════════════════════════════

// `priority: 0` means the channel's NEW videos pin to the top of
// each feed. No channel currently holds this treatment; it remains
// available as a one-line edit if/when we elevate a community
// reviewer at their explicit invitation.
//
// `priority: 5` means we pull the channel's uploads into the feed
// (so the dedupe attaches a sourceChannel tag if the same video
// also shows up in the search results) but the items sort by date
// alongside community search hits — no artificial elevation.
//
// `priority: 9` (search-sourced) is set inline when we merge search
// results in `refreshFeeds`.
const KNOWN_CHANNELS = [
  { handle: "BoBattleArena",          priority: 5 },
  { handle: "InsideTheVault_Bazooka", priority: 5 },
  { handle: "BattleArenaLeague",      priority: 5 },
  { handle: "blokpax",                priority: 5 },
  { handle: "PullsAndPars",           priority: 5 },
];

const YT_API = "https://www.googleapis.com/youtube/v3";

// Restructured 2026-04-28 from {live, short, regular} to
// {upcoming, vertical, horizontal} after Ben asked for orientation-
// based filtering instead of "Shorts vs everything else." The new
// shape:
//   - upcoming    → scheduled + currently-live broadcasts (sort by
//                   streamTime asc, the actual broadcast time, NOT
//                   the publishedAt that gets stamped when the
//                   creator first set up the YouTube event).
//   - vertical    → previously-recorded vertical content. Includes
//                   Shorts AND any non-Shorts upload with a vertical
//                   thumbnail (some creators post both phone +
//                   desktop versions of the same content).
//   - horizontal  → previously-recorded landscape content.
const FEED_KEYS = {
  upcoming:   "boba_videos:upcoming",
  vertical:   "boba_videos:vertical",
  horizontal: "boba_videos:horizontal",
};

const HANDLE_CACHE_KEY = "boba_videos:channel_handles";
const META_KEY         = "boba_videos:meta";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

// Stale-upcoming grace period — any "upcoming" event whose
// scheduledStartTime is more than this many hours in the past with
// no actualStartTime stamped gets reclassified as a recorded upload
// (almost always an abandoned placeholder YouTube doesn't auto-
// clean). 24h covers broadcasts that drift slightly past their
// scheduled start without YouTube updating actualStartTime yet.
const STALE_UPCOMING_HOURS = 24;

// ════════════════════════════════════════════════════════════════
// MARK: - HTTP entry
// ════════════════════════════════════════════════════════════════

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/health") {
      const meta = (await env.YT_KV.get(META_KEY, "json")) || {};
      const counts = {};
      for (const [name, key] of Object.entries(FEED_KEYS)) {
        const blob = await env.YT_KV.get(key, "json");
        counts[name] = blob?.count ?? 0;
      }
      return jsonOk({ ok: true, ...meta, feedCounts: counts });
    }

    if (path === "/refresh") {
      if (request.method !== "POST") {
        return jsonErr("POST required", 405);
      }
      ctx.waitUntil(refreshFeeds(env).catch(err => {
        console.error("manual refresh failed:", err);
      }));
      return jsonOk({ status: "refreshing" });
    }

    // Default: serve feeds from KV.
    const type = (url.searchParams.get("type") || "all").toLowerCase();

    if (type === "all") {
      const [upcoming, vertical, horizontal, meta] = await Promise.all([
        env.YT_KV.get(FEED_KEYS.upcoming,   "json"),
        env.YT_KV.get(FEED_KEYS.vertical,   "json"),
        env.YT_KV.get(FEED_KEYS.horizontal, "json"),
        env.YT_KV.get(META_KEY, "json"),
      ]);
      return jsonOk({
        upcoming:   upcoming?.items   || [],
        vertical:   vertical?.items   || [],
        horizontal: horizontal?.items || [],
        writtenAt:  meta?.lastRefresh || null,
      });
    }

    const feedKey = FEED_KEYS[type];
    if (!feedKey) return jsonErr(`unknown type: ${type}`, 400);
    const blob = await env.YT_KV.get(feedKey, "json");
    return jsonOk({
      items:     blob?.items     || [],
      writtenAt: blob?.writtenAt || null,
      count:     blob?.count     ?? 0,
    });
  },

  async scheduled(event, env, ctx) {
    ctx.waitUntil(refreshFeeds(env).catch(err => {
      console.error("scheduled refresh failed:", err);
    }));
  },
};

function jsonOk(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}
function jsonErr(message, status) {
  return jsonOk({ error: message }, status);
}

// ════════════════════════════════════════════════════════════════
// MARK: - Refresh pipeline
// ════════════════════════════════════════════════════════════════

async function refreshFeeds(env) {
  const apiKey = env.YOUTUBE_API_KEY;
  if (!apiKey) throw new Error("YOUTUBE_API_KEY secret not set");

  const startedAt = new Date().toISOString();

  // 1. Resolve YouTube channel ids for the @handles we care about.
  //    Cached in KV after the first call — handles don't change.
  const channels = await resolveChannelHandles(env, apiKey);

  // 2. Fetch in parallel: per-channel uploads + the global search query.
  const channelFetches = channels.map(c =>
    fetchChannelUploads(apiKey, c).then(items =>
      items.map(it => ({ ...it, priority: c.priority, sourceChannel: c.handle }))
    )
  );
  const searchFetch = fetchSearchResults(apiKey, env.SEARCH_QUERY || "Bo Jackson Battle Arena")
    .then(items => items.map(it => ({ ...it, priority: 9, sourceChannel: null })));

  const fetched = await Promise.all([searchFetch, ...channelFetches]);

  // 3. Dedupe by videoId. When the same video appears in multiple
  //    sources (search + channel), keep the lowest priority value
  //    so channel-sourced wins over search-sourced.
  const byId = new Map();
  for (const list of fetched) {
    for (const item of list) {
      const existing = byId.get(item.videoId);
      if (!existing || item.priority < existing.priority) {
        byId.set(item.videoId, item);
      }
    }
  }
  const allIds = [...byId.keys()];

  // 4. Hydrate every video with full details — duration,
  //    liveBroadcastContent, liveStreamingDetails, statistics.
  const detailsById = await fetchVideoDetails(apiKey, allIds);

  // 5. Categorize + sort.
  const upcoming   = [];
  const vertical   = [];
  const horizontal = [];

  for (const id of allIds) {
    const base    = byId.get(id);
    const details = detailsById.get(id);
    if (!details) continue;
    const item = mergeItem(base, details);
    const cat  = categorize(item);
    if      (cat === "upcoming")   upcoming.push(item);
    else if (cat === "vertical")   vertical.push(item);
    else                           horizontal.push(item);
  }

  // Upcoming/live: chronological by stream start (soonest live → next
  // scheduled → recent replays).
  upcoming.sort(sortByStreamTime);

  // Recorded feeds: pin only the TOP-3 most-recent priority-0 videos
  // to the top of the feed; everything else sorts by publishedAt
  // desc. Cap of 3 prevents any single channel from dominating the
  // top of the view even when they're posting at a high cadence.
  pinTopPriorityItems(vertical,   3);
  pinTopPriorityItems(horizontal, 3);
  vertical.sort(sortByPinnedAndDate);
  horizontal.sort(sortByPinnedAndDate);

  // 6. Cap each feed and write to KV.
  const cap = parseInt(env.MAX_ITEMS_PER_FEED || "120", 10);
  const writtenAt = new Date().toISOString();
  const pack = (items) => ({
    items: items.slice(0, cap),
    writtenAt,
    count: Math.min(items.length, cap),
  });

  await Promise.all([
    env.YT_KV.put(FEED_KEYS.upcoming,   JSON.stringify(pack(upcoming))),
    env.YT_KV.put(FEED_KEYS.vertical,   JSON.stringify(pack(vertical))),
    env.YT_KV.put(FEED_KEYS.horizontal, JSON.stringify(pack(horizontal))),
    env.YT_KV.put(META_KEY, JSON.stringify({
      lastRefresh: writtenAt,
      lastStartedAt: startedAt,
      durationMs: Date.now() - new Date(startedAt).getTime(),
      seenVideoCount: allIds.length,
      categorized: {
        upcoming:   upcoming.length,
        vertical:   vertical.length,
        horizontal: horizontal.length,
      },
    })),
  ]);
}

// ════════════════════════════════════════════════════════════════
// MARK: - Channel handle → id resolution (cached)
// ════════════════════════════════════════════════════════════════

async function resolveChannelHandles(env, apiKey) {
  const cached = await env.YT_KV.get(HANDLE_CACHE_KEY, "json");
  // Cache hit only if it's complete for the current handle list.
  if (cached && KNOWN_CHANNELS.every(c => cached[c.handle])) {
    return KNOWN_CHANNELS.map(c => ({
      handle:   c.handle,
      priority: c.priority,
      ...cached[c.handle], // {channelId, uploadsPlaylistId, title}
    }));
  }

  // Cache miss — resolve every handle. Uses 1 quota unit per handle.
  const resolved = {};
  for (const c of KNOWN_CHANNELS) {
    const params = new URLSearchParams({
      part:      "id,snippet,contentDetails",
      forHandle: "@" + c.handle,
      key:       apiKey,
    });
    const r = await fetch(`${YT_API}/channels?${params}`);
    if (!r.ok) {
      console.error(`channel resolve failed (${c.handle}):`, await r.text());
      continue;
    }
    const j = await r.json();
    const ch = j.items?.[0];
    if (!ch) {
      console.warn(`channel handle not found: @${c.handle}`);
      continue;
    }
    resolved[c.handle] = {
      channelId:          ch.id,
      uploadsPlaylistId:  ch.contentDetails?.relatedPlaylists?.uploads,
      title:              ch.snippet?.title,
      thumbnail:          ch.snippet?.thumbnails?.default?.url,
    };
  }

  await env.YT_KV.put(HANDLE_CACHE_KEY, JSON.stringify(resolved));

  return KNOWN_CHANNELS
    .filter(c => resolved[c.handle])
    .map(c => ({ handle: c.handle, priority: c.priority, ...resolved[c.handle] }));
}

// ════════════════════════════════════════════════════════════════
// MARK: - Per-channel uploads
// ════════════════════════════════════════════════════════════════

async function fetchChannelUploads(apiKey, channel) {
  if (!channel.uploadsPlaylistId) return [];
  const params = new URLSearchParams({
    part:       "snippet,contentDetails",
    playlistId: channel.uploadsPlaylistId,
    maxResults: "50",
    key:        apiKey,
  });
  const r = await fetch(`${YT_API}/playlistItems?${params}`);
  if (!r.ok) {
    console.error(`uploads fetch failed (${channel.handle}):`, await r.text());
    return [];
  }
  const j = await r.json();
  return (j.items || []).map(it => ({
    videoId:     it.contentDetails?.videoId,
    publishedAt: it.contentDetails?.videoPublishedAt || it.snippet?.publishedAt,
    title:       it.snippet?.title,
    description: it.snippet?.description,
    channelId:   it.snippet?.channelId,
    channelTitle:it.snippet?.channelTitle,
    thumbnails:  it.snippet?.thumbnails,
  })).filter(x => x.videoId);
}

// ════════════════════════════════════════════════════════════════
// MARK: - Search query (BoBA community wide)
// ════════════════════════════════════════════════════════════════

async function fetchSearchResults(apiKey, query) {
  const params = new URLSearchParams({
    part:       "snippet",
    q:          query,
    type:       "video",
    order:      "date",
    maxResults: "50",
    key:        apiKey,
  });
  const r = await fetch(`${YT_API}/search?${params}`);
  if (!r.ok) {
    console.error("search failed:", await r.text());
    return [];
  }
  const j = await r.json();
  return (j.items || []).map(it => ({
    videoId:      it.id?.videoId,
    publishedAt:  it.snippet?.publishedAt,
    title:        it.snippet?.title,
    description:  it.snippet?.description,
    channelId:    it.snippet?.channelId,
    channelTitle: it.snippet?.channelTitle,
    thumbnails:   it.snippet?.thumbnails,
  })).filter(x => x.videoId);
}

// ════════════════════════════════════════════════════════════════
// MARK: - Hydrate with details
// ════════════════════════════════════════════════════════════════

async function fetchVideoDetails(apiKey, videoIds) {
  const out = new Map();
  // videos.list accepts up to 50 ids per call, 1 quota unit each.
  for (let i = 0; i < videoIds.length; i += 50) {
    const slice = videoIds.slice(i, i + 50);
    const params = new URLSearchParams({
      part: "snippet,contentDetails,liveStreamingDetails,statistics,status",
      id:   slice.join(","),
      key:  apiKey,
    });
    const r = await fetch(`${YT_API}/videos?${params}`);
    if (!r.ok) {
      console.error("videos fetch failed:", await r.text());
      continue;
    }
    const j = await r.json();
    for (const it of (j.items || [])) {
      out.set(it.id, {
        durationISO:           it.contentDetails?.duration,
        liveBroadcastContent:  it.snippet?.liveBroadcastContent,
        liveStreamingDetails:  it.liveStreamingDetails || null,
        viewCount:             toInt(it.statistics?.viewCount),
        likeCount:             toInt(it.statistics?.likeCount),
        commentCount:          toInt(it.statistics?.commentCount),
        privacyStatus:         it.status?.privacyStatus,
        embeddable:            it.status?.embeddable !== false,
        title:                 it.snippet?.title,
        description:           it.snippet?.description,
        channelId:             it.snippet?.channelId,
        channelTitle:          it.snippet?.channelTitle,
        thumbnails:            it.snippet?.thumbnails,
      });
    }
  }
  return out;
}

function toInt(v) { return v == null ? null : parseInt(v, 10); }

// ════════════════════════════════════════════════════════════════
// MARK: - Merge + categorize
// ════════════════════════════════════════════════════════════════

function mergeItem(base, details) {
  const durationSec = parseISODurationSec(details.durationISO);
  const thumb = pickThumbnail(details.thumbnails, base.thumbnails);

  // Stream-time semantics: the user wants the actual broadcast start,
  // NOT the publishedAt timestamp YouTube stamps when the creator
  // first creates the event placeholder. Pick scheduledStartTime for
  // upcoming streams, actualStartTime for currently-live or already-
  // started streams. Falls back to publishedAt for non-live videos.
  const lsd = details.liveStreamingDetails || {};
  const streamTime =
    lsd.actualStartTime    ||
    lsd.scheduledStartTime ||
    null;

  return {
    videoId:     base.videoId,
    title:       details.title       || base.title,
    description: details.description || base.description,
    publishedAt: base.publishedAt,
    streamTime,
    scheduledStartTime: lsd.scheduledStartTime || null,
    actualStartTime:    lsd.actualStartTime    || null,
    actualEndTime:      lsd.actualEndTime      || null,
    channelId:    details.channelId    || base.channelId,
    channelTitle: details.channelTitle || base.channelTitle,
    thumbnail:    thumb.url,
    thumbnailWidth:  thumb.width  || null,
    thumbnailHeight: thumb.height || null,
    isVertical:   isVerticalVideo(thumb, durationSec, details.title, details.description),
    durationSec,
    viewCount:    details.viewCount,
    likeCount:    details.likeCount,
    commentCount: details.commentCount,
    embeddable:   details.embeddable,
    liveBroadcastContent: details.liveBroadcastContent,
    liveStreamingDetails: details.liveStreamingDetails,
    priority:      base.priority,
    pinned:        false,  // set later by pinTopPriorityItems
    sourceChannel: base.sourceChannel,
    url:          `https://www.youtube.com/watch?v=${base.videoId}`,
    embedUrl:     `https://www.youtube.com/embed/${base.videoId}`,
  };
}

/// Pick the highest-resolution thumbnail available, returning both
/// the URL and its dimensions so downstream code can detect the
/// source video's orientation. Each YouTube thumbnail object is
/// `{url, width, height}`.
function pickThumbnail(detailsThumbs, baseThumbs) {
  const order = ["maxres", "standard", "high", "medium", "default"];
  for (const key of order) {
    if (detailsThumbs?.[key]) return detailsThumbs[key];
  }
  for (const key of order) {
    if (baseThumbs?.[key]) return baseThumbs[key];
  }
  return { url: null, width: null, height: null };
}

/// True when a recorded video is vertically oriented. The YouTube
/// Data API doesn't surface source video dimensions — `maxres`
/// thumbnails come back as 16:9 (1280×720) for both vertical and
/// horizontal source uploads — so we have to lean on creator-side
/// signals that telegraph orientation:
///
///   1. The 📱 emoji in the title — some creators mark phone-edition
///      cuts of their show this way (e.g. "9 Minute Edition 📱").
///   2. Explicit "phone" / "mobile" / "vertical" / "portrait"
///      keywords in the title or description.
///   3. The #shorts hashtag, which by definition implies vertical.
///   4. Duration ≤ 65s — virtually every YouTube upload that short
///      is a Short these days, regardless of explicit tagging.
///   5. A vertical thumbnail (height > width). Currently rare in
///      practice because YouTube re-encodes everything to 16:9
///      thumbs, but kept as a forward-looking signal for the day
///      that changes (or for a creator who supplies a native
///      vertical thumb).
function isVerticalVideo(thumb, durationSec, title, description) {
  if (thumb?.width && thumb?.height && thumb.height > thumb.width) {
    return true;
  }
  const titleStr = title || "";
  if (titleStr.includes("📱")) return true;

  const text = `${titleStr} ${description || ""}`.toLowerCase();
  const verticalMarkers = [
    "#shorts", "#short",
    "phone edition", "phone version",
    "mobile edition", "mobile version",
    "vertical edition", "vertical version",
    "portrait edition", "portrait version",
  ];
  for (const marker of verticalMarkers) {
    if (text.includes(marker)) return true;
  }

  if (durationSec != null && durationSec > 0 && durationSec <= 65) return true;
  return false;
}

function categorize(item) {
  // Live now — currently broadcasting.
  if (item.liveBroadcastContent === "live") return "upcoming";

  // Scheduled to start in the future. Filter out two flavors of
  // zombie placeholder that YouTube doesn't auto-clean:
  //   (a) "upcoming" with no scheduledStartTime at all — almost
  //       always a generic Live Stream placeholder a creator made
  //       months ago and never used. We can't even surface a
  //       "starts at" line for these, so they'd be useless cards.
  //   (b) "upcoming" with a scheduledStartTime more than
  //       STALE_UPCOMING_HOURS in the past — abandoned event.
  // Both fall through to vertical/horizontal so they're not lost
  // entirely (a coach who finds them via search still sees them).
  if (item.liveBroadcastContent === "upcoming") {
    if (!item.scheduledStartTime) {
      return item.isVertical ? "vertical" : "horizontal";
    }
    const sched = new Date(item.scheduledStartTime).getTime();
    if (sched < Date.now() - STALE_UPCOMING_HOURS * 3600 * 1000) {
      return item.isVertical ? "vertical" : "horizontal";
    }
    return "upcoming";
  }

  // Everything else — including ended live broadcasts (replays) —
  // routes into vertical/horizontal based on orientation. Per Ben
  // (2026-04-28): "Upcoming Live" is for current + future only;
  // replays belong in their orientation feed.
  return item.isVertical ? "vertical" : "horizontal";
}

function parseISODurationSec(iso) {
  if (!iso) return null;
  const m = iso.match(/^P(?:([0-9]+)D)?T?(?:([0-9]+)H)?(?:([0-9]+)M)?(?:([0-9]+)S)?$/);
  if (!m) return null;
  const [, d, h, mi, s] = m;
  return ((+d || 0) * 86400) + ((+h || 0) * 3600) + ((+mi || 0) * 60) + (+s || 0);
}

// ════════════════════════════════════════════════════════════════
// MARK: - Sort
// ════════════════════════════════════════════════════════════════

/// Mark the top-N most-recent priority-0 (top-tier) items in a feed
/// with `pinned: true`. Everything else (including older priority-0
/// items) gets `pinned: false`. The sort below uses the flag.
function pinTopPriorityItems(items, capN) {
  const candidates = items
    .filter(v => v.priority === 0)
    .sort((a, b) => (b.publishedAt || "").localeCompare(a.publishedAt || ""))
    .slice(0, capN);
  const pinnedSet = new Set(candidates.map(v => v.videoId));
  for (const v of items) {
    v.pinned = pinnedSet.has(v.videoId);
  }
}

/// Pinned items first (sorted by date desc among themselves), then
/// the rest by date desc. Lets the top-priority channel's most recent
/// uploads anchor each feed without burying everyone else's fresh
/// content beneath the entire priority-channel back-catalog.
function sortByPinnedAndDate(a, b) {
  if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
  return (b.publishedAt || "").localeCompare(a.publishedAt || "");
}

/// Upcoming-live sort: live now first (sorted by actualStartTime so
/// the longest-running stream sits at top), then scheduled streams
/// chronologically (soonest first), then recently-ended replays
/// reverse-chronologically. Tiebreaker: priority → date.
function sortByStreamTime(a, b) {
  const aBucket = streamBucket(a);
  const bBucket = streamBucket(b);
  if (aBucket !== bBucket) return aBucket - bBucket;
  const aTime = streamSortKey(a);
  const bTime = streamSortKey(b);
  // For "upcoming" bucket, ascending (soonest first). For "live" and
  // "replay" buckets, descending (most recent first).
  if (aBucket === 1) return aTime - bTime;
  return bTime - aTime;
}

function streamBucket(item) {
  if (item.liveBroadcastContent === "live") return 0;     // live now
  if (item.liveBroadcastContent === "upcoming") return 1; // scheduled
  return 2;                                                // ended replay
}

function streamSortKey(item) {
  const t =
    item.actualStartTime    ||
    item.scheduledStartTime ||
    item.actualEndTime      ||
    item.publishedAt        ||
    null;
  return t ? new Date(t).getTime() : 0;
}
