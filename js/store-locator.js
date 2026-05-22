/**
 * Store Locator — Find a Store view (web)
 *
 * Loads the authorized-retailer list from assets/data/stores.json via
 * API.loadStores() (manifest-sha256 refresh handled there), renders a
 * Leaflet map + filterable list, and wires native-Maps deeplinks on
 * each store.
 *
 * Leaflet lives on the global `L` — loaded from the SRI-pinned
 * <script> tag in index.html head.
 */
(function () {
  'use strict';

  // Keep mirrored with Models/StoreLocation.swift::bigBoxKeywords. Big
  // national chains are hidden by default so independent hobby shops
  // show up first — they're the ones actually championing BOBA.
  const BIG_BOX_KEYWORDS = [
    "dick's sporting", "dicks sporting", "dsg ", "dsg house of sport",
    "dick's house of sport", "dick's sporting goods combo store",
    "target",
    "walmart", "wal-mart",
    "costco",
    "meijer",
    "fred meyer",
    "scheels",
    "academy sports",
    "gamestop",
    "five below",
    "best buy",
    "barnes & noble", "barnes and noble",
    "books-a-million", "books a million",
    "hobby lobby",
    "kohl's", "kohls",
  ];
  function isBigBox(store) {
    const n = (store?.name || '').toLowerCase();
    return BIG_BOX_KEYWORDS.some(k => n.includes(k));
  }

  // Inline BOBA mark for Leaflet divIcon. 2×2 XOXO in white on the
  // orange disc, mirrors the iOS `BOBAPinMarker`. Kept as a template
  // string so markers can be constructed without a DOM round-trip.
  const BOBA_PIN_HTML = `
    <div class="store-boba-pin-inner">
      <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <line x1="5" y1="5" x2="9.5" y2="9.5" stroke="#fff" stroke-width="2" stroke-linecap="round"/>
        <line x1="9.5" y1="5" x2="5" y2="9.5" stroke="#fff" stroke-width="2" stroke-linecap="round"/>
        <circle cx="17" cy="7.25" r="2.5" fill="none" stroke="#fff" stroke-width="2"/>
        <circle cx="7" cy="16.75" r="2.5" fill="none" stroke="#fff" stroke-width="2"/>
        <line x1="14.5" y1="14.5" x2="19" y2="19" stroke="#fff" stroke-width="2" stroke-linecap="round"/>
        <line x1="19" y1="14.5" x2="14.5" y2="19" stroke="#fff" stroke-width="2" stroke-linecap="round"/>
      </svg>
    </div>`;
  function bobaMarkerIcon() {
    return L.divIcon({
      className: 'store-boba-pin',
      html: BOBA_PIN_HTML,
      iconSize: [28, 28],
      iconAnchor: [14, 14],
    });
  }

  const state = {
    initialised:    false,
    stores:         [],
    filtered:       [],
    manifest:       null,
    searchText:     '',
    /// Set when the user typed a 5-digit US ZIP and we successfully
    /// geocoded it. We treat ZIP entries as a proximity origin
    /// (recenter map, sort by distance) instead of a substring match —
    /// the dataset's postCodes are ZIP+4 so literal substring matches
    /// almost always miss, which is what made the search feel broken.
    zipCoord:       null,
    zipLabel:       '',
    selectedState:  '',
    includeBigBox:  false,
    userCoord:      null,
    map:            null,
    markerLayer:    null,
    userMarker:     null,
  };

  const ZIP_RE = /^\d{5}$/;
  const zipCache = new Map();
  /// Free, CORS-enabled ZIP→lat/lng lookup. No auth, no signup, public
  /// data. We cache responses in-memory for the session.
  async function geocodeZip(zip) {
    if (zipCache.has(zip)) return zipCache.get(zip);
    const resp = await fetch(`https://api.zippopotam.us/us/${zip}`);
    if (!resp.ok) throw new Error(`ZIP ${zip} not found`);
    const data = await resp.json();
    const place = data?.places?.[0];
    if (!place) throw new Error(`ZIP ${zip} not found`);
    const coord = {
      lat: parseFloat(place.latitude),
      lng: parseFloat(place.longitude),
      label: `${place['place name']}, ${place['state abbreviation']}`,
    };
    zipCache.set(zip, coord);
    return coord;
  }

  const $ = (id) => document.getElementById(id);

  async function init() {
    if (state.initialised) {
      // View re-opened — just re-apply filters in case the list changed.
      applyFilter();
      return;
    }
    state.initialised = true;

    wireControls();

    try {
      const { stores, manifest } = await API.loadStores();
      state.stores   = Array.isArray(stores) ? stores : [];
      state.manifest = manifest;
      populateStateFilter();
      applyFilter();
      buildMap();
      renderSummary();
    } catch (err) {
      renderError(err?.message || 'Could not load store list.');
    }
  }

  /* -----------------------------------------------------------------
     Controls
  ----------------------------------------------------------------- */
  function wireControls() {
    const search = $('store-search-input');
    const stateSelect = $('store-state-filter');
    const nearMe = $('store-near-me');
    const bigBox = $('store-include-bigbox');

    bigBox?.addEventListener('change', (e) => {
      state.includeBigBox = !!e.target.checked;
      const label = document.querySelector('label[for="store-include-bigbox"] .store-bigbox-label');
      if (label) label.textContent = state.includeBigBox ? 'Big box included' : 'Include big box';
      applyFilter();
    });

    let debounceTimer;
    search?.addEventListener('input', (e) => {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(async () => {
        const raw = e.target.value.trim();
        state.searchText = raw.toLowerCase();
        if (ZIP_RE.test(raw)) {
          try {
            const coord = await geocodeZip(raw);
            state.zipCoord = { lat: coord.lat, lng: coord.lng };
            state.zipLabel = coord.label;
            if (state.map) {
              state.map.setView([coord.lat, coord.lng], 10);
            }
          } catch (_) {
            state.zipCoord = null;
            state.zipLabel = '';
          }
        } else {
          state.zipCoord = null;
          state.zipLabel = '';
        }
        applyFilter();
      }, 200);
    });

    stateSelect?.addEventListener('change', (e) => {
      state.selectedState = e.target.value;
      applyFilter();
    });

    nearMe?.addEventListener('click', () => {
      if (!navigator.geolocation) {
        alert("Your browser doesn't support location services.");
        return;
      }
      nearMe.classList.add('loading');
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          nearMe.classList.remove('loading');
          nearMe.classList.add('active');
          state.userCoord = { lat: pos.coords.latitude, lng: pos.coords.longitude };
          applyFilter();
          if (state.map) {
            state.map.setView([state.userCoord.lat, state.userCoord.lng], 10);
            drawUserMarker();
          }
        },
        () => {
          nearMe.classList.remove('loading');
          alert('Location access denied — try filtering by state or city instead.');
        },
        { enableHighAccuracy: false, timeout: 10000, maximumAge: 60 * 60 * 1000 }
      );
    });
  }

  function populateStateFilter() {
    const select = $('store-state-filter');
    if (!select) return;
    const states = [...new Set(state.stores.map(s => s.address?.stateShort).filter(Boolean))].sort();
    // Keep the "All States" default, add the rest
    for (const code of states) {
      const opt = document.createElement('option');
      opt.value = code;
      opt.textContent = code;
      select.appendChild(opt);
    }
  }

  /* -----------------------------------------------------------------
     Filtering
  ----------------------------------------------------------------- */
  /// Count of big-box stores that WOULD match the current search if
  /// the user enabled "Include big box". Used by the empty-state hint.
  function countBigBoxMatches() {
    const q = state.searchText;
    const origin = state.zipCoord || state.userCoord;
    return state.stores.filter(s => {
      if (!isBigBox(s)) return false;
      if (state.selectedState && s.address?.stateShort !== state.selectedState) return false;
      if (state.zipCoord && origin) {
        return milesBetween(s.location, origin) <= 50;
      }
      if (!q) return true;
      const a = s.address || {};
      return (s.name || '').toLowerCase().includes(q)
          || (a.city || '').toLowerCase().includes(q)
          || (a.street || '').toLowerCase().includes(q)
          || (a.postCode || '').toLowerCase().includes(q);
    }).length;
  }

  function applyFilter() {
    const q = state.searchText;
    const isZipQuery = !!state.zipCoord;
    let rows = state.stores.filter((s) => {
      if (!state.includeBigBox && isBigBox(s)) return false;
      if (state.selectedState && s.address?.stateShort !== state.selectedState) return false;
      // ZIP query: skip the substring filter — proximity sort below
      // handles relevance. Substring matching against ZIP+4 postcodes
      // is what made entering "97203" return zero hits.
      if (isZipQuery || !q) return true;
      const a = s.address || {};
      return (s.name || '').toLowerCase().includes(q)
          || (a.city || '').toLowerCase().includes(q)
          || (a.street || '').toLowerCase().includes(q)
          || (a.postCode || '').toLowerCase().includes(q);
    });

    const origin = state.zipCoord || state.userCoord;
    if (origin) {
      rows.sort((a, b) =>
        distance(a.location, origin) - distance(b.location, origin)
      );
      // For ZIP queries, only show stores within ~50mi of the ZIP so
      // the list is genuinely "near here" rather than the full catalog
      // sorted by distance.
      if (isZipQuery) {
        rows = rows.filter(s => milesBetween(s.location, origin) <= 50);
      }
    } else {
      rows.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
    }

    state.filtered = rows;
    renderList();
    renderMarkers();
    renderSummary();
  }

  function distance(a, b) {
    if (!a || !b) return Infinity;
    const dLat = a.lat - b.lat;
    const dLng = a.lng - b.lng;
    return dLat * dLat + dLng * dLng;  // squared — sort-order-equivalent, much cheaper than full Haversine
  }

  function milesBetween(a, b) {
    if (!a || !b) return null;
    const toRad = (d) => (d * Math.PI) / 180;
    const R = 3958.8;
    const dLat = toRad(b.lat - a.lat);
    const dLng = toRad(b.lng - a.lng);
    const lat1 = toRad(a.lat);
    const lat2 = toRad(b.lat);
    const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(h));
  }

  /* -----------------------------------------------------------------
     Rendering
  ----------------------------------------------------------------- */
  function renderSummary() {
    const el = $('store-summary');
    if (!el) return;
    if (!state.stores.length) {
      el.textContent = '';
      return;
    }
    const total   = state.stores.length.toLocaleString();
    const showing = state.filtered.length.toLocaleString();
    // Tick 428 — relative-format the "Updated" stamp ("today" / "5d ago")
    // matching the events + blog freshness stamps (Android tick 419,
    // iOS tick 252+419, web app.js ticks 218+248). Falls back to the
    // ISO date for older scrapes (>5wk).
    const rawUpdated = (state.manifest?.scraped_at || '').slice(0, 10);
    const updated = rawUpdated
      ? ((window.bobaRelativeDate?.(rawUpdated)) || rawUpdated)
      : '';
    const hidden  = state.stores.filter(isBigBox).length;

    let line;
    if (state.zipCoord) {
      const where = state.zipLabel || `ZIP ${state.searchText}`;
      line = `${showing} ${state.includeBigBox ? 'retailers' : 'independents'} within 50 mi of ${where}`;
    } else if (!state.includeBigBox) {
      line = `${showing} independent retailers${hidden ? `  ·  ${hidden.toLocaleString()} big box hidden` : ''}`;
    } else {
      line = `${showing} of ${total} authorized retailers`;
    }
    el.textContent = line + (updated ? `  ·  Updated ${updated}` : '');
  }

  function renderList() {
    const el = $('store-list');
    if (!el) return;
    if (!state.filtered.length) {
      // If big-box is hidden and there ARE big-box matches in the
      // current query, surface that — without the hint a search like
      // "97203" returns empty even though there's a Target two blocks
      // away, which is what made the search feel broken.
      const wouldMatchBigBox = state.includeBigBox ? 0 : countBigBoxMatches();
      const bigBoxHint = wouldMatchBigBox > 0
        ? `<p class="store-empty-hint">${wouldMatchBigBox} big-box stores nearby — toggle “Include big box” above to show them.</p>`
        : '';
      el.innerHTML = `
        <div class="store-empty">
          <p>No independent shops match your search.</p>
          ${bigBoxHint}
          <button type="button" id="store-clear-filters" class="store-clear-btn">Clear filters</button>
        </div>`;
      $('store-clear-filters')?.addEventListener('click', () => {
        state.searchText = '';
        state.selectedState = '';
        state.zipCoord = null;
        state.zipLabel = '';
        const s = $('store-search-input'); if (s) s.value = '';
        const ss = $('store-state-filter'); if (ss) ss.value = '';
        applyFilter();
      });
      return;
    }

    // Cap rendered rows for perf — scrolling to the 2,155th store is
    // unnecessary; the user will filter before browsing a long list.
    const MAX_ROWS = 200;
    const rows = state.filtered.slice(0, MAX_ROWS);
    const extra = state.filtered.length - rows.length;

    el.innerHTML = rows.map((s, i) => rowHTML(s, i)).join('') +
      (extra > 0
        ? `<div class="store-more">+${extra.toLocaleString()} more — refine your search to see them.</div>`
        : '');

    el.querySelectorAll('[data-store-idx]').forEach((node) => {
      node.addEventListener('click', () => {
        const idx = Number(node.getAttribute('data-store-idx'));
        const s = state.filtered[idx];
        if (s) openDetail(s);
      });
    });
  }

  function rowHTML(s, idx) {
    const a = s.address || {};
    const city = a.city || '';
    const st   = a.stateShort || '';
    const line = city && st ? `${escapeHTML(city)}, ${escapeHTML(st)}` : escapeHTML(a.full || '');
    const distLabel = state.userCoord
      ? (() => {
          const miles = milesBetween(state.userCoord, s.location);
          if (miles == null) return '';
          return miles < 10 ? `${miles.toFixed(1)} mi` : `${Math.round(miles)} mi`;
        })()
      : '';
    return `
      <button type="button" class="store-row" data-store-idx="${idx}">
        <div class="store-row-pin">${BOBA_PIN_HTML}</div>
        <div class="store-row-body">
          <div class="store-row-name">${escapeHTML(s.name || '')}</div>
          <div class="store-row-meta">${line}</div>
          ${a.street ? `<div class="store-row-street">${escapeHTML(a.street)}</div>` : ''}
        </div>
        ${distLabel ? `<div class="store-row-dist">${distLabel}</div>` : ''}
      </button>
    `;
  }

  function renderError(msg) {
    const el = $('store-list');
    if (!el) return;
    el.innerHTML = `
      <div class="store-error">
        <p>Couldn't load the store list.</p>
        <p class="store-error-detail">${escapeHTML(msg)}</p>
        <button type="button" id="store-retry" class="store-clear-btn">Try again</button>
      </div>`;
    $('store-retry')?.addEventListener('click', () => {
      state.initialised = false;
      init();
    });
  }

  /* -----------------------------------------------------------------
     Map
  ----------------------------------------------------------------- */
  function buildMap() {
    if (typeof L === 'undefined') return;
    if (state.map) return;
    const container = $('store-map');
    if (!container) return;

    state.map = L.map(container, { zoomControl: true, attributionControl: true })
      .setView([39.8283, -98.5795], 4);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 18,
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(state.map);

    state.markerLayer = L.layerGroup().addTo(state.map);
    renderMarkers();
  }

  function renderMarkers() {
    if (!state.markerLayer) return;
    state.markerLayer.clearLayers();
    // Cap markers for perf on mobile — 500 is plenty and the filtered list
    // already narrows most real-world use.
    const MAX_MARKERS = 500;
    state.filtered.slice(0, MAX_MARKERS).forEach((s) => {
      const m = L.marker([s.location.lat, s.location.lng], { icon: bobaMarkerIcon() });
      m.bindTooltip(s.name || 'Store', { direction: 'top' });
      m.on('click', () => openDetail(s));
      m.addTo(state.markerLayer);
    });
  }

  function drawUserMarker() {
    if (!state.map || !state.userCoord) return;
    if (state.userMarker) state.map.removeLayer(state.userMarker);
    state.userMarker = L.circleMarker([state.userCoord.lat, state.userCoord.lng], {
      radius: 7,
      weight: 3,
      color: '#ffffff',
      fillColor: '#00F5FF',
      fillOpacity: 1,
    }).bindTooltip('You are here', { direction: 'top' }).addTo(state.map);
  }

  /* -----------------------------------------------------------------
     Detail
  ----------------------------------------------------------------- */
  function openDetail(s) {
    const existing = document.getElementById('store-detail-overlay');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'store-detail-overlay';
    overlay.className = 'modal-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', s.name || 'Store');

    const a = s.address || {};
    const city = a.city || '';
    const st   = a.stateShort || '';
    const fullAddr = a.full || [a.street, city, st, a.postCode].filter(Boolean).join(', ');
    const appleURL = appleMapsURL(s);
    const googleURL = googleMapsURL(s);

    const phoneHTML = s.phone
      ? `<a class="store-detail-link" href="tel:${encodeURIComponent(s.phone.replace(/[^\d+]/g, ''))}">
           <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="16" height="16" aria-hidden="true">
             <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.37 1.9.72 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.35 1.85.59 2.81.72A2 2 0 0 1 22 16.92z"/>
           </svg>${escapeHTML(s.phone)}</a>`
      : '';
    const webHTML = s.website
      ? `<a class="store-detail-link" href="${normaliseURL(s.website)}" target="_blank" rel="noopener">
           <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="16" height="16" aria-hidden="true">
             <circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 0 20M12 2a15.3 15.3 0 0 0 0 20"/>
           </svg>${escapeHTML(s.website)}</a>`
      : '';

    overlay.innerHTML = `
      <div class="store-detail">
        <button type="button" class="store-detail-close" aria-label="Close">×</button>
        <h2 class="store-detail-name">${escapeHTML(s.name || 'Store')}</h2>
        <p class="store-detail-loc">${escapeHTML(city)}${st ? `, ${escapeHTML(st)}` : ''}</p>
        <a class="store-detail-address" href="${appleURL}" target="_blank" rel="noopener">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="18" height="18" aria-hidden="true">
            <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/>
          </svg>
          <span>${escapeHTML(fullAddr)}</span>
        </a>
        ${phoneHTML}
        ${webHTML}
        <div class="store-detail-actions">
          <a class="store-btn primary" href="${appleURL}" target="_blank" rel="noopener">Open in Apple Maps</a>
          <a class="store-btn secondary" href="${googleURL}" target="_blank" rel="noopener">Open in Google Maps</a>
        </div>
        ${s.modifiedAt ? `<p class="store-detail-verified">Last verified ${s.modifiedAt.slice(0, 10)}</p>` : ''}
      </div>`;
    document.body.appendChild(overlay);

    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) overlay.remove();
    });
    overlay.querySelector('.store-detail-close')?.addEventListener('click', () => overlay.remove());
    document.addEventListener('keydown', function escClose(ev) {
      if (ev.key === 'Escape') {
        overlay.remove();
        document.removeEventListener('keydown', escClose);
      }
    });
  }

  /* -----------------------------------------------------------------
     URLs
  ----------------------------------------------------------------- */
  function appleMapsURL(s) {
    const ll = `${s.location.lat},${s.location.lng}`;
    const q  = s.name ? `&q=${encodeURIComponent(s.name)}` : '';
    return `https://maps.apple.com/?ll=${ll}${q}`;
  }

  function googleMapsURL(s) {
    if (s.placeId) return `https://www.google.com/maps/place/?q=place_id:${encodeURIComponent(s.placeId)}`;
    return `https://www.google.com/maps/search/?api=1&query=${s.location.lat},${s.location.lng}`;
  }

  function normaliseURL(u) {
    if (!u) return '#';
    return /^https?:\/\//i.test(u) ? u : `https://${u}`;
  }

  function escapeHTML(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }

  window.BOBAStoreLocator = { init };
})();
