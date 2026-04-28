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
    const viewerLabel = isLive
      ? (show.viewerCount > 0 ? `${show.viewerCount} watching` : '')
      : (show.viewerCount > 0 ? `${show.viewerCount} interested` : '');
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

  function init() {
    if (initialized) return;
    initialized = true;
    render();
  }

  // Re-fetch when the Purchase view becomes visible.
  window.PurchaseView = {
    init,
    refresh: () => render({ force: true }),
  };
})();
