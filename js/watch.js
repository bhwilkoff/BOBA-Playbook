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
    upcoming:   () => document.getElementById('watch-panel-upcoming'),
    vertical:   () => document.getElementById('watch-panel-vertical'),
    horizontal: () => document.getElementById('watch-panel-horizontal'),
  };
  const COUNTS = {
    upcoming:   () => document.getElementById('watch-count-upcoming'),
    vertical:   () => document.getElementById('watch-count-vertical'),
    horizontal: () => document.getElementById('watch-count-horizontal'),
  };

  let _bundle  = null;
  let _loaded  = false;
  let _loading = false;

  /* ================================================================
     PUBLIC: init — wire the tab pills, refresh button, pull-to-
     refresh gesture, and player overlay listeners. Lazy on first
     show (LearnView calls Watch.show() when the user flips the
     Read/Watch toggle to Watch).
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
    // Tap the refresh button → force a fresh fetch.
    document.getElementById('watch-refresh-btn')?.addEventListener('click', refresh);
    // Pull-to-refresh on touch devices — listeners attach to the
    // shared scroll container (#main-content) and ignore drags when
    // we're not actually on the Watch panel.
    initPullToRefresh();
  }

  /* ================================================================
     PULL-TO-REFRESH — mirrors the Live-Breaks (Purchase view) flow.
     Listeners live on #main-content (the only scrollable surface
     in our flex-column layout); a guard rejects drags when the
     Watch panel isn't the active panel.
  ================================================================ */
  const PULL_THRESHOLD = 80;
  let _ptrStartY    = null;
  let _ptrDistance  = 0;
  let _ptrRefreshing = false;

  function watchPanelVisible() {
    const panel = document.getElementById('learn-panel-watch');
    return panel && !panel.hidden;
  }

  function scrollContainer() {
    return document.getElementById('main-content') || document.body;
  }

  function setRefreshing(on) {
    _ptrRefreshing = on;
    document.getElementById('watch-refresh-btn')?.classList.toggle('watch-refresh-btn--spinning', on);
    const ind = document.getElementById('watch-pull-indicator');
    if (ind) {
      ind.classList.toggle('watch-pull-indicator--active', on);
      if (on) ind.querySelector('.watch-pull-label').textContent = 'Refreshing…';
    }
  }

  async function refresh() {
    if (_ptrRefreshing || _loading) return;
    setRefreshing(true);
    try { await loadAll(); }
    finally {
      setRefreshing(false);
      const ind = document.getElementById('watch-pull-indicator');
      if (ind) {
        ind.style.transform = '';
        ind.style.opacity = '';
        ind.querySelector('.watch-pull-label').textContent = 'Pull to refresh';
      }
    }
  }

  function onTouchStart(e) {
    if (!watchPanelVisible() || _ptrRefreshing) return;
    if (scrollContainer().scrollTop > 0) { _ptrStartY = null; return; }
    _ptrStartY = e.touches?.[0]?.clientY ?? null;
    _ptrDistance = 0;
  }

  function onTouchMove(e) {
    if (_ptrStartY == null || _ptrRefreshing || !watchPanelVisible()) return;
    const y = e.touches?.[0]?.clientY ?? _ptrStartY;
    _ptrDistance = Math.max(0, y - _ptrStartY);
    if (_ptrDistance > 5) {
      const ind = document.getElementById('watch-pull-indicator');
      if (!ind) return;
      const dragRatio = Math.min(1, _ptrDistance / PULL_THRESHOLD);
      ind.style.opacity = String(dragRatio);
      ind.style.transform = `translateY(${Math.min(_ptrDistance * 0.5, 40)}px)`;
      ind.querySelector('.watch-pull-label').textContent =
        _ptrDistance >= PULL_THRESHOLD ? 'Release to refresh' : 'Pull to refresh';
    }
  }

  function onTouchEnd() {
    if (_ptrStartY == null) return;
    const triggered = _ptrDistance >= PULL_THRESHOLD;
    _ptrStartY = null;
    _ptrDistance = 0;
    const ind = document.getElementById('watch-pull-indicator');
    if (triggered) {
      refresh();
    } else if (ind) {
      ind.style.transform = '';
      ind.style.opacity = '';
    }
  }

  function initPullToRefresh() {
    const sc = scrollContainer();
    sc.addEventListener('touchstart',  onTouchStart, { passive: true });
    sc.addEventListener('touchmove',   onTouchMove,  { passive: true });
    sc.addEventListener('touchend',    onTouchEnd);
    sc.addEventListener('touchcancel', onTouchEnd);
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
    renderLoadingState('upcoming');
    renderLoadingState('vertical');
    renderLoadingState('horizontal');
    try {
      const resp = await fetch(WORKER_URL + '/');
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      _bundle = await resp.json();
      _loaded = true;
      renderTab('upcoming',   _bundle.upcoming   || []);
      renderTab('vertical',   _bundle.vertical   || []);
      renderTab('horizontal', _bundle.horizontal || []);
    } catch (err) {
      console.error('Watch loadAll failed:', err);
      renderErrorState('upcoming',   err.message);
      renderErrorState('vertical',   err.message);
      renderErrorState('horizontal', err.message);
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
        name === 'upcoming' ? 'No upcoming or live shows right now.' :
        name === 'vertical' ? 'No vertical videos yet.' :
                              'No horizontal videos yet.'
      }<br><span class="watch-empty-sub">Refreshes every 4 hours. Pull down to refresh now.</span></div>`;
      return;
    }

    const cardHtml = items.map(v =>
      name === 'upcoming' ? upcomingCard(v)   :
      name === 'vertical' ? verticalCard(v)   :
                            horizontalCard(v)
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
     natural aspect ratio (16:9 for upcoming + horizontal, 9:16 for
     vertical) and to surface stream times on Upcoming Live cards.
  ================================================================ */
  function upcomingCard(v) {
    // Upcoming feed carries live + scheduled streams only (the worker
    // routes replays to vertical/horizontal). Two badge variants:
    // red LIVE NOW for active broadcasts, cyan UPCOMING for the rest.
    const isLive = v.liveBroadcastContent === 'live';
    const badgeClass = isLive ? 'watch-badge-live' : 'watch-badge-upcoming';
    const badgeText  = isLive ? 'LIVE NOW' : 'UPCOMING';
    const when = streamTimeLabel(v);
    return `
      <article class="watch-card watch-card-upcoming" data-video-id="${esc(v.videoId)}" tabindex="0">
        <div class="watch-thumb watch-thumb-16x9">
          ${thumbImg(v)}
          <span class="watch-badge ${badgeClass}">${badgeText}</span>
          ${durationBadge(v)}
        </div>
        <h4 class="watch-card-title">${esc(v.title)}</h4>
        ${when ? `<div class="watch-card-streamtime${isLive ? ' watch-card-streamtime-live' : ''}">
          <span class="watch-card-streamtime-icon" aria-hidden="true">⏱</span> ${esc(when)}
        </div>` : ''}
        ${cardSubtitle(v)}
      </article>`;
  }

  function verticalCard(v) {
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

  function horizontalCard(v) {
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

  /// "Today at 1:00 PM" / "Tomorrow at 1:00 PM" / "Wed at 1:00 PM" /
  /// "Apr 30 at 1:00 PM". Reads streamTime (actualStartTime ||
  /// scheduledStartTime), NOT publishedAt.
  function streamTimeLabel(v) {
    const iso = v.streamTime || v.scheduledStartTime || v.actualStartTime;
    if (!iso) return null;
    const d = new Date(iso);
    if (isNaN(d.getTime())) return null;
    const now  = new Date();
    const dDay = new Date(d.getFullYear(),   d.getMonth(),   d.getDate());
    const nDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const diff = Math.round((dDay - nDay) / 86400000);
    const time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    if (diff ===  0) return `Today at ${time}`;
    if (diff ===  1) return `Tomorrow at ${time}`;
    if (diff === -1) return `Yesterday at ${time}`;
    if (diff > 1 && diff < 7) {
      const dow = d.toLocaleDateString([], { weekday: 'short' });
      return `${dow} at ${time}`;
    }
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    if (d.getFullYear() === now.getFullYear()) {
      return `${months[d.getMonth()]} ${d.getDate()} at ${time}`;
    }
    return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()} at ${time}`;
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
    const desc    = document.getElementById('watch-player-description');

    // youtube-nocookie + enablejsapi + origin/widget_referrer is the
    // post-July-2025 incantation that avoids Error 152/153 in
    // restricted embed contexts. Mirrors the iOS YouTubePlayerView
    // setup so both platforms share the same embed shape.
    const origin = encodeURIComponent(window.location.origin || 'https://bobaplaybook.com');
    iframe.src =
      `https://www.youtube-nocookie.com/embed/${encodeURIComponent(v.videoId)}` +
      `?autoplay=1&playsinline=1&modestbranding=1&rel=0&enablejsapi=1` +
      `&origin=${origin}&widget_referrer=${origin}`;
    title.textContent   = v.title || '';
    channel.textContent = v.channelTitle || '';
    if (desc) {
      // Linkified description — URLs in YouTube descriptions become
      // tappable anchors. innerHTML is safe here because linkifyDesc
      // escapes every non-URL chunk before reassembling the string.
      desc.innerHTML = v.description ? linkifyDesc(v.description) : '';
    }
    overlay.hidden = false;
    document.body.classList.add('watch-player-open');
  }

  /// Convert plain-text URLs to anchor tags while escaping the rest
  /// of the string. Splits on URL matches, escapes the in-between
  /// segments, and wraps each match in `<a target="_blank" rel=...>`
  /// so taps open in a new tab and don't navigate the embed away.
  function linkifyDesc(text) {
    const urlRegex = /\b(https?:\/\/[^\s<>"']+)/g;
    let out = '';
    let lastEnd = 0;
    text.replace(urlRegex, (match, url, offset) => {
      out += esc(text.slice(lastEnd, offset));
      // Strip trailing punctuation that's almost always sentence
      // terminators rather than part of the URL.
      let cleaned = url;
      let trailing = '';
      while (/[.,!?;:)\]]$/.test(cleaned)) {
        trailing = cleaned.slice(-1) + trailing;
        cleaned  = cleaned.slice(0, -1);
      }
      out += `<a href="${esc(cleaned)}" target="_blank" rel="noopener noreferrer">${esc(cleaned)}</a>${esc(trailing)}`;
      lastEnd = offset + match.length;
      return match;
    });
    out += esc(text.slice(lastEnd));
    // Preserve newlines as <br> so the description keeps its
    // multi-paragraph shape.
    return out.replace(/\n/g, '<br>');
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
