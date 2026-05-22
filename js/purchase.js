/* Purchase view — Upcoming Breaks (Whatnot feed) + Find a Store link.
 * The Whatnot feed is fetched from the boba-ebay-proxy Worker's
 * /whatnot/upcoming endpoint (Cloudflare Worker scrapes whatnot.com
 * server-side and returns normalized JSON).
 */
(function () {
  'use strict';

  const WHATNOT_QUERY = 'bo Jackson battle arena';
  const CACHE_LIFETIME_MS = 5 * 60 * 1000;
  let cached = null;
  let initialized = false;

  function workerBase() {
    return (window.WorkerConfig && window.WorkerConfig.ebayProxyURL)
        || 'https://boba-ebay-proxy.benwilkoff.workers.dev';
  }

  function escapeHTML(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => (
      {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]
    ));
  }

  async function fetchUpcomingShows({ force = false } = {}) {
    if (!force && cached && (Date.now() - cached.at < CACHE_LIFETIME_MS)) {
      return cached.shows;
    }
    const url = new URL(workerBase());
    url.pathname = '/whatnot/upcoming';
    url.searchParams.set('query', WHATNOT_QUERY);
    // No status param — the Worker defaults to CREATED+PLAYING so live
    // streams appear alongside upcoming ones.
    const resp = await fetch(url.toString(), { method: 'GET' });
    if (!resp.ok) throw new Error(`worker returned ${resp.status}`);
    const data = await resp.json();
    const shows = Array.isArray(data?.shows) ? data.shows : [];
    cached = { at: Date.now(), shows };
    return shows;
  }

  function renderEmpty(host) {
    host.innerHTML = `
      <div class="purchase-shows-empty">
        <div class="purchase-shows-empty-icon">📺</div>
        <div class="purchase-shows-empty-title">No upcoming shows right now</div>
        <div class="purchase-shows-empty-sub">Check back soon — new streams scheduled throughout the week.</div>
      </div>`;
  }

  function renderError(host, message) {
    host.innerHTML = `
      <div class="purchase-shows-error">
        <div class="purchase-shows-empty-icon">⚠️</div>
        <div class="purchase-shows-empty-title">Couldn't load upcoming shows</div>
        <div class="purchase-shows-empty-sub">${escapeHTML(message)}</div>
        <button class="purchase-shows-retry" type="button" id="purchase-shows-retry">Retry</button>
      </div>`;
    document.getElementById('purchase-shows-retry')?.addEventListener('click', () => render({ force: true }));
  }

  // Worker formats `scheduledTimeText` in PT; re-derive from the
  // timestamp fields so the user sees their own local clock time.
  function localTimeText(show) {
    const ms = show.startTimeMs
        || (show.scheduledTimeIso ? Date.parse(show.scheduledTimeIso) : NaN);
    if (!Number.isFinite(ms)) return show.scheduledTimeText || '';
    const d = new Date(ms);
    const now = new Date();
    const sameDay = (a, b) => a.getFullYear() === b.getFullYear()
                           && a.getMonth() === b.getMonth()
                           && a.getDate() === b.getDate();
    const tomorrow = new Date(now); tomorrow.setDate(tomorrow.getDate() + 1);
    const time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    if (sameDay(d, now))      return `Today ${time}`;
    if (sameDay(d, tomorrow)) return `Tomorrow ${time}`;
    const day = d.toLocaleDateString([], { weekday: 'short' });
    return `${day} ${time}`;
  }

  function showCardHTML(show) {
    const href = show.showUrl || `https://www.whatnot.com/live/${show.showId}`;
    const thumb = show.thumbnailUrl || '';
    const host = show.host || '';
    const title = show.title || 'Untitled show';
    const time = localTimeText(show);
    const cat = show.categoryName || '';
    const isLive = !!show.isLive;
    // Tick 408 — Android tick 406 + iOS tick 407 parity. Locale-format
    // the viewer count so 4-digit streams render "1,234 watching"
    // instead of "1234 watching".
    const viewerCountFmt = show.viewerCount > 0 ? show.viewerCount.toLocaleString() : '';
    const viewerLabel = isLive
      ? (show.viewerCount > 0 ? `${viewerCountFmt} watching` : '')
      : (show.viewerCount > 0 ? `${viewerCountFmt} interested` : '');
    const thumbHtml = thumb
      ? `<img class="pshow-thumb" src="${escapeHTML(thumb)}" alt="" loading="lazy" onerror="this.style.display='none'">`
      : '<div class="pshow-thumb pshow-thumb-fallback">📺</div>';
    const livePill = isLive ? '<span class="pshow-live-pill">LIVE</span>' : '';
    return `
      <a class="pshow-card" href="${escapeHTML(href)}" target="_blank" rel="noopener">
        <div class="pshow-thumb-wrap">${thumbHtml}${livePill}</div>
        <div class="pshow-body">
          <div class="pshow-meta">
            ${host ? `<span class="pshow-host">@${escapeHTML(host)}</span>` : ''}
            ${!isLive && time ? `<span class="pshow-time">⏰ ${escapeHTML(time)}</span>` : ''}
          </div>
          <div class="pshow-title">${escapeHTML(title)}</div>
          <div class="pshow-foot">
            ${cat ? `<span class="pshow-cat">${escapeHTML(cat).toUpperCase()}</span>` : ''}
            ${viewerLabel ? `<span class="pshow-viewers">👥 ${escapeHTML(viewerLabel)}</span>` : ''}
          </div>
        </div>
      </a>`;
  }

  async function render({ force = false } = {}) {
    const host = document.getElementById('purchase-shows-list');
    if (!host) return;
    if (!cached) {
      host.innerHTML = `<div class="purchase-shows-loading">Loading upcoming shows…</div>`;
    }
    try {
      const shows = await fetchUpcomingShows({ force });
      if (!shows.length) { renderEmpty(host); return; }
      const live = shows.filter(s => s.isLive);
      const upcoming = shows.filter(s => !s.isLive);
      const parts = [];
      if (live.length)     parts.push(...live.map(showCardHTML));
      if (live.length && upcoming.length) {
        parts.push('<div class="purchase-shows-section-divider">UPCOMING</div>');
      }
      if (upcoming.length) parts.push(...upcoming.map(showCardHTML));
      host.innerHTML = parts.join('');
    } catch (err) {
      renderError(host, err.message || 'Network error');
    }
  }

  // ── Pull-to-refresh ─────────────────────────────────────────────
  // Mobile gesture: when the user is at the top of the Purchase view's
  // scroll container and drags down past the threshold, fire a forced
  // re-fetch so the worker pulls fresh streams.
  const PULL_THRESHOLD = 80;
  let isRefreshing = false;
  let pullStartY = null;
  let pullDistance = 0;

  function scrollContainer() {
    return document.getElementById('main-content') || document.body;
  }

  function setRefreshing(on) {
    isRefreshing = on;
    document.getElementById('purchase-refresh-btn')?.classList.toggle('purchase-refresh-btn--spinning', on);
    const ind = document.getElementById('purchase-pull-indicator');
    if (ind) {
      ind.classList.toggle('purchase-pull-indicator--active', on);
      if (on) ind.querySelector('.purchase-pull-label').textContent = 'Refreshing…';
    }
  }

  async function refresh() {
    if (isRefreshing) return;
    setRefreshing(true);
    try { await render({ force: true }); }
    finally {
      setRefreshing(false);
      // Snap the indicator back after a brief pause.
      const ind = document.getElementById('purchase-pull-indicator');
      if (ind) {
        ind.style.transform = '';
        ind.style.opacity = '';
        ind.querySelector('.purchase-pull-label').textContent = 'Pull to refresh';
      }
    }
  }

  function onTouchStart(e) {
    if (isRefreshing) return;
    if (scrollContainer().scrollTop > 0) { pullStartY = null; return; }
    pullStartY = e.touches?.[0]?.clientY ?? null;
    pullDistance = 0;
  }

  function onTouchMove(e) {
    if (pullStartY == null || isRefreshing) return;
    const y = e.touches?.[0]?.clientY ?? pullStartY;
    pullDistance = Math.max(0, y - pullStartY);
    if (pullDistance > 5) {
      const ind = document.getElementById('purchase-pull-indicator');
      if (!ind) return;
      const dragRatio = Math.min(1, pullDistance / PULL_THRESHOLD);
      ind.style.opacity = String(dragRatio);
      ind.style.transform = `translateY(${Math.min(pullDistance * 0.5, 40)}px)`;
      ind.querySelector('.purchase-pull-label').textContent =
        pullDistance >= PULL_THRESHOLD ? 'Release to refresh' : 'Pull to refresh';
    }
  }

  function onTouchEnd() {
    if (pullStartY == null) return;
    const triggered = pullDistance >= PULL_THRESHOLD;
    pullStartY = null;
    pullDistance = 0;
    const ind = document.getElementById('purchase-pull-indicator');
    if (triggered) {
      refresh();
    } else if (ind) {
      ind.style.transform = '';
      ind.style.opacity = '';
    }
  }

  function init() {
    if (initialized) return;
    initialized = true;
    document.getElementById('purchase-refresh-btn')?.addEventListener('click', refresh);
    const sc = scrollContainer();
    sc.addEventListener('touchstart', onTouchStart, { passive: true });
    sc.addEventListener('touchmove',  onTouchMove,  { passive: true });
    sc.addEventListener('touchend',   onTouchEnd);
    sc.addEventListener('touchcancel', onTouchEnd);
    render();
  }

  // Re-fetch when the Purchase view becomes visible.
  window.PurchaseView = {
    init,
    refresh: () => render({ force: true }),
  };
})();
