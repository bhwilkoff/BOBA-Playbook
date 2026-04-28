/* Watch — Learn → Watch panel. Renders three categorized YouTube
 * feeds (Live / Shorts / Videos) hydrated by the boba-youtube-feed
 * Worker, and embeds playback in-app via the YouTube IFrame Player
 * API (just an <iframe src="https://www.youtube.com/embed/{id}">,
 * which is YouTube's officially-sanctioned embed path).
 *
 * Worker source: workers/youtube-feed/. Refresh cadence is server-
 * side (every 4h via cron); the page just GETs the cached payload.
 */
const Watch = (() => {
  'use strict';

  const WORKER_URL =
    (window.WorkerConfig && window.WorkerConfig.youtubeFeedURL)
    || 'https://boba-youtube-feed.benwilkoff.workers.dev';

  const PANELS = {
    live:   () => document.getElementById('watch-panel-live'),
    shorts: () => document.getElementById('watch-panel-shorts'),
    videos: () => document.getElementById('watch-panel-videos'),
  };
  const COUNTS = {
    live:   () => document.getElementById('watch-count-live'),
    shorts: () => document.getElementById('watch-count-shorts'),
    videos: () => document.getElementById('watch-count-videos'),
  };

  let _bundle  = null;
  let _loaded  = false;
  let _loading = false;

  /* ================================================================
     PUBLIC: init — wire the tab pills + player overlay listeners.
     Lazy on first show (LearnView calls Watch.show() when the user
     flips the Read/Watch toggle to Watch).
  ================================================================ */
  function init() {
    document.querySelectorAll('.watch-tab').forEach(btn => {
      btn.addEventListener('click', () => switchTab(btn.dataset.watchTab));
    });
    // Player overlay close — backdrop + button + Escape.
    document.querySelectorAll('[data-watch-close]').forEach(el => {
      el.addEventListener('click', closePlayer);
    });
    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && !document.getElementById('watch-player-overlay').hidden) {
        closePlayer();
      }
    });
  }

  /* ================================================================
     PUBLIC: show — called when the Watch toggle is selected. Loads
     feeds on first invocation; re-uses cached bundle thereafter.
  ================================================================ */
  async function show() {
    if (!_loaded && !_loading) {
      await loadAll();
    }
  }

  async function loadAll() {
    if (_loading) return;
    _loading = true;
    renderLoadingState('live');
    renderLoadingState('shorts');
    renderLoadingState('videos');
    try {
      const resp = await fetch(WORKER_URL + '/');
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      _bundle = await resp.json();
      _loaded = true;
      renderTab('live',   _bundle.live    || []);
      renderTab('shorts', _bundle.short   || []);
      renderTab('videos', _bundle.regular || []);
    } catch (err) {
      console.error('Watch loadAll failed:', err);
      renderErrorState('live',   err.message);
      renderErrorState('shorts', err.message);
      renderErrorState('videos', err.message);
    } finally {
      _loading = false;
    }
  }

  /* ================================================================
     RENDERING
  ================================================================ */
  function renderTab(name, items) {
    const panel = PANELS[name]();
    const count = COUNTS[name]();
    if (count) count.textContent = items.length;
    if (!panel) return;

    if (!items.length) {
      panel.innerHTML = `<div class="watch-empty">${
        name === 'live'   ? 'No live shows right now.' :
        name === 'shorts' ? 'No new Shorts yet.' :
                            'No videos in this feed yet.'
      }<br><span class="watch-empty-sub">Refreshes every 4 hours.</span></div>`;
      return;
    }

    const cardHtml = items.map(v =>
      name === 'live'   ? liveCard(v)   :
      name === 'shorts' ? shortCard(v)  :
                          videoCard(v)
    ).join('');
    panel.innerHTML = `<div class="watch-grid watch-grid-${name}">${cardHtml}</div>`;

    // Wire taps.
    panel.querySelectorAll('[data-video-id]').forEach(el => {
      el.addEventListener('click', () => {
        const v = items.find(x => x.videoId === el.dataset.videoId);
        if (v) openPlayer(v);
      });
    });
  }

  function renderLoadingState(name) {
    const panel = PANELS[name]();
    if (panel) panel.innerHTML = `<div class="watch-loading">Loading…</div>`;
  }

  function renderErrorState(name, message) {
    const panel = PANELS[name]();
    if (panel) {
      panel.innerHTML = `<div class="watch-error">
        <strong>Couldn't load videos.</strong>
        <span class="watch-error-detail">${esc(message)}</span>
        <button class="btn-ghost-sm watch-retry">Try Again</button>
      </div>`;
      panel.querySelector('.watch-retry')?.addEventListener('click', () => loadAll());
    }
  }

  /* ================================================================
     CARD HTML — one per category to honor the underlying media's
     natural aspect ratio (16:9 for live + regular, 9:16 for Shorts).
  ================================================================ */
  function liveCard(v) {
    const isLive = v.liveBroadcastContent === 'live';
    return `
      <article class="watch-card watch-card-live" data-video-id="${esc(v.videoId)}" tabindex="0">
        <div class="watch-thumb watch-thumb-16x9">
          ${thumbImg(v)}
          <span class="watch-badge ${isLive ? 'watch-badge-live' : 'watch-badge-replay'}">
            ${isLive ? 'LIVE NOW' : 'LIVE REPLAY'}
          </span>
          ${durationBadge(v)}
        </div>
        <h4 class="watch-card-title">${esc(v.title)}</h4>
        ${cardSubtitle(v)}
      </article>`;
  }

  function shortCard(v) {
    return `
      <article class="watch-card watch-card-short" data-video-id="${esc(v.videoId)}" tabindex="0">
        <div class="watch-thumb watch-thumb-9x16">
          ${thumbImg(v)}
          ${durationBadge(v)}
        </div>
        <h4 class="watch-card-title watch-card-title-short">${esc(v.title)}</h4>
        ${cardSubtitle(v, true)}
      </article>`;
  }

  function videoCard(v) {
    return `
      <article class="watch-card watch-card-video" data-video-id="${esc(v.videoId)}" tabindex="0">
        <div class="watch-thumb watch-thumb-16x9">
          ${thumbImg(v)}
          ${durationBadge(v)}
        </div>
        <h4 class="watch-card-title">${esc(v.title)}</h4>
        ${cardSubtitle(v)}
      </article>`;
  }

  function thumbImg(v) {
    if (v.thumbnail) {
      return `<img loading="lazy" src="${esc(v.thumbnail)}" alt="">`;
    }
    return `<div class="watch-thumb-placeholder">▶</div>`;
  }

  function durationBadge(v) {
    if (!v.durationSec) return '';
    return `<span class="watch-duration">${esc(formatDuration(v.durationSec))}</span>`;
  }

  function cardSubtitle(v, compact = false) {
    const parts = [];
    if (v.priority === 0) parts.push(`<span class="watch-pin">★</span>`);
    if (v.channelTitle)   parts.push(`<span class="watch-channel">${esc(v.channelTitle)}</span>`);
    const rel = relativeDate(v.publishedAt);
    if (rel)              parts.push(`<span class="watch-meta">${rel}</span>`);
    if (v.viewCount)      parts.push(`<span class="watch-meta">${formatViews(v.viewCount)} views</span>`);
    return `<div class="watch-card-meta${compact ? ' watch-card-meta-compact' : ''}">${parts.join(' · ')}</div>`;
  }

  /* ================================================================
     PLAYER OVERLAY
  ================================================================ */
  function openPlayer(v) {
    const overlay = document.getElementById('watch-player-overlay');
    const iframe  = document.getElementById('watch-player-iframe');
    const title   = document.getElementById('watch-player-title');
    const channel = document.getElementById('watch-player-channel');

    iframe.src = `https://www.youtube.com/embed/${encodeURIComponent(v.videoId)}?autoplay=1&playsinline=1&modestbranding=1&rel=0`;
    title.textContent   = v.title || '';
    channel.textContent = v.channelTitle || '';
    overlay.hidden = false;
    document.body.classList.add('watch-player-open');
  }

  function closePlayer() {
    const overlay = document.getElementById('watch-player-overlay');
    const iframe  = document.getElementById('watch-player-iframe');
    iframe.src = ''; // stop playback by clearing src
    overlay.hidden = true;
    document.body.classList.remove('watch-player-open');
  }

  /* ================================================================
     TAB SWITCHING
  ================================================================ */
  function switchTab(name) {
    document.querySelectorAll('.watch-tab').forEach(btn => {
      const active = btn.dataset.watchTab === name;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-selected', String(active));
    });
    Object.entries(PANELS).forEach(([n, getter]) => {
      const panel = getter();
      if (panel) panel.hidden = (n !== name);
    });
  }

  /* ================================================================
     UTIL
  ================================================================ */
  function esc(s) {
    return String(s ?? '')
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
      .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }

  function formatDuration(sec) {
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h) return `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
    return `${m}:${String(s).padStart(2,'0')}`;
  }

  function formatViews(n) {
    if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
    if (n >= 1_000)     return (n / 1_000).toFixed(1) + 'K';
    return String(n);
  }

  function relativeDate(iso) {
    if (!iso) return null;
    const d = new Date(iso);
    if (isNaN(d.getTime())) return null;
    const now  = new Date();
    const dDay = new Date(d.getFullYear(),   d.getMonth(),   d.getDate());
    const nDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const diff = Math.round((nDay - dDay) / 86400000);
    if (diff === 0) return 'today';
    if (diff === 1) return 'yesterday';
    if (diff < 7)   return `${diff}d ago`;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    if (d.getFullYear() === now.getFullYear()) {
      return `${months[d.getMonth()]} ${d.getDate()}`;
    }
    return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
  }

  return { init, show, loadAll };
})();

window.Watch = Watch;
document.addEventListener('DOMContentLoaded', () => Watch.init());
