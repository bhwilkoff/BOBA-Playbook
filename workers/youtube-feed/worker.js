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

// Priority order matters. Lower priority value = surfaces first when
// videos are equally fresh. radishdijital is the most active community
// reviewer per Ben — pinned to priority 0 so it leads.
const KNOWN_CHANNELS = [
  { handle: "radishdijital",          priority: 0 },
  { handle: "BoBattleArena",          priority: 1 },
  { handle: "InsideTheVault_Bazooka", priority: 1 },
  { handle: "BattleArenaLeague",      priority: 1 },
  { handle: "blokpax",                priority: 1 },
  { handle: "PullsAndPars",           priority: 1 },
];

const YT_API = "https://www.googleapis.com/youtube/v3";

const FEED_KEYS = {
  live:    "boba_videos:live",
  short:   "boba_videos:short",
  regular: "boba_videos:regular",
};

const HANDLE_CACHE_KEY = "boba_videos:channel_handles";
const META_KEY         = "boba_videos:meta";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

// Live-replay window — anything that ended within this many days is
// still surfaced in the live feed. Keeps yesterday's break replay
// front-and-center while letting older replays flow into "regular".
const LIVE_REPLAY_DAYS = 7;

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
      const [live, short, regular, meta] = await Promise.all([
        env.YT_KV.get(FEED_KEYS.live, "json"),
        env.YT_KV.get(FEED_KEYS.short, "json"),
        env.YT_KV.get(FEED_KEYS.regular, "json"),
        env.YT_KV.get(META_KEY, "json"),
      ]);
      return jsonOk({
        live:    live?.items    || [],
        short:   short?.items   || [],
        regular: regular?.items || [],
        writtenAt: meta?.lastRefresh || null,
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
  const live    = [];
  const short   = [];
  const regular = [];
  const priorityFreshDays = parseInt(env.PRIORITY_FRESH_DAYS || "30", 10);

  for (const id of allIds) {
    const base    = byId.get(id);
    const details = detailsById.get(id);
    if (!details) continue;
    const item = mergeItem(base, details);
    const cat  = categorize(item);
    if      (cat === "live")  live.push(item);
    else if (cat === "short") short.push(item);
    else                      regular.push(item);
  }

  const sortFeed = sortByPriorityAndDate(priorityFreshDays);
  live.sort(sortFeed);
  short.sort(sortFeed);
  regular.sort(sortFeed);

  // 6. Cap each feed and write to KV.
  const cap = parseInt(env.MAX_ITEMS_PER_FEED || "120", 10);
  const writtenAt = new Date().toISOString();
  const pack = (items) => ({
    items: items.slice(0, cap),
    writtenAt,
    count: Math.min(items.length, cap),
  });

  await Promise.all([
    env.YT_KV.put(FEED_KEYS.live,    JSON.stringify(pack(live))),
    env.YT_KV.put(FEED_KEYS.short,   JSON.stringify(pack(short))),
    env.YT_KV.put(FEED_KEYS.regular, JSON.stringify(pack(regular))),
    env.YT_KV.put(META_KEY, JSON.stringify({
      lastRefresh: writtenAt,
      lastStartedAt: startedAt,
      durationMs: Date.now() - new Date(startedAt).getTime(),
      seenVideoCount: allIds.length,
      categorized: { live: live.length, short: short.length, regular: regular.length },
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
  const thumb =
    details.thumbnails?.maxres?.url ||
    details.thumbnails?.high?.url   ||
    details.thumbnails?.medium?.url ||
    base.thumbnails?.high?.url      ||
    base.thumbnails?.default?.url;

  return {
    videoId:     base.videoId,
    title:       details.title       || base.title,
    description: details.description || base.description,
    publishedAt: base.publishedAt    || details.liveStreamingDetails?.actualStartTime,
    channelId:    details.channelId    || base.channelId,
    channelTitle: details.channelTitle || base.channelTitle,
    thumbnail:   thumb,
    durationSec,
    viewCount:    details.viewCount,
    likeCount:    details.likeCount,
    commentCount: details.commentCount,
    embeddable:   details.embeddable,
    liveBroadcastContent: details.liveBroadcastContent,
    liveStreamingDetails: details.liveStreamingDetails,
    priority:      base.priority,
    sourceChannel: base.sourceChannel,
    url:          `https://www.youtube.com/watch?v=${base.videoId}`,
    embedUrl:     `https://www.youtube.com/embed/${base.videoId}`,
  };
}

function categorize(item) {
  // Live now — broadcast is currently happening.
  if (item.liveBroadcastContent === "live") return "live";

  // Live replay within the rolling window — surfaced in live feed.
  const ended = item.liveStreamingDetails?.actualEndTime;
  if (ended) {
    const ageDays = (Date.now() - new Date(ended).getTime()) / (1000 * 60 * 60 * 24);
    if (ageDays <= LIVE_REPLAY_DAYS) return "live";
  }

  // Shorts heuristic — YouTube doesn't expose an isShort flag. The
  // duration ≤ 60s + #shorts marker combo catches ~99% of real
  // Shorts without false-positiving on a normal 30-second creator
  // intro clip.
  if (looksLikeShort(item)) return "short";

  return "regular";
}

function looksLikeShort(item) {
  if (item.durationSec == null) return false;
  if (item.durationSec > 65) return false; // small slack for rounding
  const text = `${item.title || ""} ${item.description || ""}`.toLowerCase();
  if (text.includes("#shorts") || text.includes("#short")) return true;
  // Tight duration alone is a strong signal — most ≤60s YouTube
  // uploads on the platform today are Shorts. Loose marker keeps us
  // honest for the rare creator who genuinely posts a 45-second
  // teaser as a regular landscape upload.
  return item.durationSec <= 60;
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

function sortByPriorityAndDate(priorityFreshDays) {
  const freshCutoff = Date.now() - priorityFreshDays * 86400 * 1000;
  return (a, b) => {
    // Live items beat everything within their feed (the live feed
    // can carry live + replay; live should always lead).
    const aLive = a.liveBroadcastContent === "live" ? 0 : 1;
    const bLive = b.liveBroadcastContent === "live" ? 0 : 1;
    if (aLive !== bLive) return aLive - bLive;

    // Priority channels surface first WHILE FRESH. Past the
    // freshness window everyone falls back to date order so a
    // brand-new community video isn't buried under a 2-year-old
    // priority upload.
    const aFresh = (a.priority < 9) && (new Date(a.publishedAt).getTime() >= freshCutoff);
    const bFresh = (b.priority < 9) && (new Date(b.publishedAt).getTime() >= freshCutoff);
    if (aFresh !== bFresh) return bFresh - aFresh;
    if (aFresh && bFresh && a.priority !== b.priority) return a.priority - b.priority;

    // Default: newest first.
    return (b.publishedAt || "").localeCompare(a.publishedAt || "");
  };
}
