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
    url.searchParams.set('status', 'CREATED');
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

  function showCardHTML(show) {
    const href = show.showUrl || `https://www.whatnot.com/live/${show.showId}`;
    const thumb = show.thumbnailUrl || '';
    const host = show.host || '';
    const title = show.title || 'Untitled show';
    const time = show.scheduledTimeText || '';
    const cat = show.categoryName || '';
    const viewers = (typeof show.viewerCount === 'number' && show.viewerCount > 0)
      ? `${show.viewerCount} interested` : '';
    const thumbHtml = thumb
      ? `<img class="pshow-thumb" src="${escapeHTML(thumb)}" alt="" loading="lazy" onerror="this.style.display='none'">`
      : '<div class="pshow-thumb pshow-thumb-fallback">📺</div>';
    return `
      <a class="pshow-card" href="${escapeHTML(href)}" target="_blank" rel="noopener">
        <div class="pshow-thumb-wrap">${thumbHtml}</div>
        <div class="pshow-body">
          <div class="pshow-meta">
            ${host ? `<span class="pshow-host">@${escapeHTML(host)}</span>` : ''}
            ${time ? `<span class="pshow-time">⏰ ${escapeHTML(time)}</span>` : ''}
          </div>
          <div class="pshow-title">${escapeHTML(title)}</div>
          <div class="pshow-foot">
            ${cat ? `<span class="pshow-cat">${escapeHTML(cat).toUpperCase()}</span>` : ''}
            ${viewers ? `<span class="pshow-viewers">👥 ${escapeHTML(viewers)}</span>` : ''}
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
      host.innerHTML = shows.map(showCardHTML).join('');
    } catch (err) {
      renderError(host, err.message || 'Network error');
    }
  }

  function init() {
    if (initialized) return;
    initialized = true;
    document.getElementById('purchase-go-stores')?.addEventListener('click', () => {
      if (typeof window.showView === 'function') window.showView('stores');
    });
    render();
  }

  // Re-fetch when the Purchase view becomes visible.
  window.PurchaseView = {
    init,
    refresh: () => render({ force: true }),
  };
})();
