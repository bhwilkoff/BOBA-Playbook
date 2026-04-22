/**
 * BOBA Playbook — Main Application
 *
 * M1: Search Mode — browse, search, and filter BOBA cards.
 *
 * Data model note: cards.json has multiple rows per physical card when a card
 * has multiple hero associations (same cardNumber, different hero/athleteInspiration).
 * The grid shows one entry per unique cardNumber. The detail modal shows all
 * hero associations for that card.
 *
 * Search-index note: tokenIndex / byElement / bySet etc. store CARD NUMBERS
 * (strings like "1", "BF-208") as values — NOT array positions.
 */

(function () {
  'use strict';

  /* ================================================================
     CONSTANTS
  ================================================================ */
  const PAGE_SIZE           = 60;
  const SEARCH_DEBOUNCE_MS  = 280;

  /* ================================================================
     HELPERS
  ================================================================ */
  const $ = (id) => document.getElementById(id);

  function escHtml(str) {
    if (str == null) return '';
    const d = document.createElement('div');
    d.textContent = String(str);
    return d.innerHTML;
  }

  function relativeDate(iso) {
    if (!iso) return '';
    const date = new Date(iso);
    if (isNaN(date)) return '';
    const days = Math.floor((Date.now() - date.getTime()) / 86400000);
    if (days < 0)  return '';
    if (days === 0) return 'today';
    if (days < 7)  return `${days}d ago`;
    const weeks = Math.floor(days / 7);
    if (weeks < 5) return `${weeks}w ago`;
    return `${Math.floor(days / 30)}mo ago`;
  }

  /* ================================================================
     STATE
  ================================================================ */
  let cards         = [];         // raw catalog (may have multi-hero dupes)
  let searchIndex   = null;
  let categories    = null;
  let aliasIndex    = {};         // lowercase slang → [canonical, ...] (community shorthand)

  // Built after load:
  let cardsByNumber = new Map();  // cardNumber (string) → Card[] (all hero associations)
  let cardsByBobaId = new Map();  // bobaId (string) → Card — exact card identity
  let displayCards  = [];         // one Card per unique cardNumber (for the grid)

  let filteredCards  = [];
  let displayedCount = 0;

  const filters = {
    query:    '',
    element:  '',
    set:      '',
    treatment:'',
    hasImage: false,
    powerMin: null,
    powerMax: null,
    sortBy:   'default',
  };

  /* ================================================================
     DOM REFS
  ================================================================ */
  const loadingState    = $('loading-state');
  const cardGrid        = $('card-grid');
  const emptyState      = $('empty-state');
  const searchInput     = $('search-input');
  const searchClear     = $('search-clear');
  const searchCount     = $('search-count');
  const elementFilters  = $('element-filters');
  const setFilter       = $('set-filter');
  const treatmentFilter = $('treatment-filter');
  const hasImageCheckbox = document.getElementById('has-image-checkbox');
  const loadSentinel    = $('load-sentinel');
  const clearFiltersBtn = $('clear-filters-btn');
  const powerMinInput  = $('power-min');
  const powerMaxInput  = $('power-max');
  const filterToggleBtn = $('filter-toggle-btn');
  const filterPanel     = $('filter-panel');
  const filterBadge     = $('filter-badge');
  const sortBySelect    = $('sort-select');

  const modalOverlay  = $('card-modal-overlay');
  const modalContent  = $('modal-content');
  const modalCloseBtn = $('modal-close-btn');
  const modalNavPrev  = $('modal-nav-prev');
  const modalNavNext  = $('modal-nav-next');

  // Index into filteredCards for the currently open modal (-1 = no modal or card not in list)
  let currentModalIndex = -1;

  const sidebarToggle  = $('sidebar-toggle');
  const sidebar        = $('channels-sidebar');
  const sidebarOverlay = $('sidebar-overlay');

  /* ================================================================
     SIDEBAR (mobile)
  ================================================================ */
  sidebarToggle.addEventListener('click', () => {
    if (sidebar.classList.contains('open')) {
      closeSidebar();
    } else {
      sidebar.classList.add('open');
      sidebarOverlay.classList.add('visible');
      sidebarToggle.setAttribute('aria-expanded', 'true');
    }
  });

  function closeSidebar() {
    sidebar.classList.remove('open');
    sidebarOverlay.classList.remove('visible');
    sidebarToggle.setAttribute('aria-expanded', 'false');
    // Remove focus from the button so :focus-visible ring clears after close
    sidebarToggle.blur();
  }
  sidebarOverlay.addEventListener('click', closeSidebar);

  /* ================================================================
     FILTER PANEL TOGGLE (mobile)
  ================================================================ */
  filterToggleBtn?.addEventListener('click', () => {
    const open = filterPanel.classList.toggle('open');
    filterToggleBtn.setAttribute('aria-expanded', String(open));
    filterPanel.setAttribute('aria-hidden', String(!open));
  });

  function updateFilterBadge() {
    let count = 0;
    if (filters.element)                                count++;
    if (filters.set)                                    count++;
    if (filters.treatment)                              count++;
    if (filters.powerMin !== null || filters.powerMax !== null) count++;
    if (filters.hasImage)                               count++;
    if (filterBadge) {
      filterBadge.textContent = String(count);
      filterBadge.hidden = count === 0;
    }
    filterToggleBtn?.classList.toggle('has-filters', count > 0);
  }

  /* ================================================================
     VIEW SYSTEM
  ================================================================ */
  const viewIds = ['search', 'scan', 'rules', 'decks', 'practice', 'collection', 'profile'];
  const navBtnIds = {
    search:        'nav-search-btn',
    scan:          'nav-scan-btn',
    rules:         'nav-rules-btn',
    decks:         'nav-decks-btn',
    practice:      'nav-practice-btn',
    collection:    'nav-collection-btn',
    profile:       'nav-profile-btn',
  };

  // Tracks the active view for URL building (card URLs embed the view).
  let currentView = 'search';

  /* ----------------------------------------------------------------
     URL BUILDING
     Scheme:
       ?                                   search, no filters
       ?q=lebron&element=FIRE              search + filters
       ?set=Alpha&treatment=Battlefoil     filter-only
       ?view=collection                    non-search views
       ?card=CBF-656&hero=BoJax            card open (search view, no filters)
       ?q=lebron&card=1&hero=LeBoss        card open on top of a search
       ?view=collection&card=1&hero=LeBoss card open from collection view
  ---------------------------------------------------------------- */

  // Serialize current filter state to a URLSearchParams (no card).
  function buildSearchParams() {
    const p = new URLSearchParams();
    if (currentView !== 'search')          p.set('view', currentView);
    if (filters.query)                     p.set('q', filters.query);
    if (filters.element)                   p.set('element', filters.element);
    if (filters.set)                       p.set('set', filters.set);
    if (filters.treatment)                 p.set('treatment', filters.treatment);
    if (filters.hasImage)                  p.set('has_image', '1');
    if (filters.powerMin != null)          p.set('power_min', String(filters.powerMin));
    if (filters.powerMax != null)          p.set('power_max', String(filters.powerMax));
    if (filters.sortBy && filters.sortBy !== 'default') p.set('sort', filters.sortBy);
    return p;
  }

  function buildSearchURL() {
    const str = buildSearchParams().toString();
    return str ? `?${str}` : '?';
  }

  // Card URL: filter state + card identifier (cardNumber + hero + treatment).
  function buildCardURL(card) {
    const p = buildSearchParams();
    p.set('card', String(card.cardNumber));
    if (card.hero) p.set('hero', card.hero);
    if (card.treatment) p.set('treatment', card.treatment);
    return `?${p.toString()}`;
  }

  // Apply URL params to filter state + sync all UI controls.
  // Call applyFilters(true) after this to re-render without a second URL write.
  function applyURLParams(params) {
    filters.query     = params.get('q') || '';
    filters.element   = params.get('element') || '';
    filters.set       = params.get('set') || '';
    filters.treatment = params.get('treatment') || '';
    filters.hasImage  = params.get('has_image') === '1';
    filters.powerMin  = params.has('power_min') ? Number(params.get('power_min')) : null;
    filters.powerMax  = params.has('power_max') ? Number(params.get('power_max')) : null;
    filters.sortBy    = params.get('sort') || 'default';
    if (sortBySelect) sortBySelect.value = filters.sortBy;

    // Sync UI — only update elements that exist (catalog may not be loaded yet).
    if (searchInput)   searchInput.value = filters.query;
    if (searchClear)   searchClear.hidden = !filters.query;

    elementFilters?.querySelectorAll('.element-pill').forEach(pill => {
      const active = pill.dataset.element === filters.element;
      pill.classList.toggle('active', active);
      pill.setAttribute('aria-pressed', active ? 'true' : 'false');
    });

    if (setFilter) setFilter.value = filters.set;
    buildTreatmentFilter(filters.set);
    if (treatmentFilter) treatmentFilter.value = filters.treatment;

    if (hasImageCheckbox) hasImageCheckbox.checked = filters.hasImage;

    if (powerMinInput) powerMinInput.value = filters.powerMin ?? '';
    if (powerMaxInput) powerMaxInput.value = filters.powerMax ?? '';

    document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
    if (filters.powerMin == null && filters.powerMax == null) {
      document.querySelector('.power-preset[data-min=""]')?.classList.add('active');
    } else {
      document.querySelectorAll('.power-preset').forEach(b => {
        const pmin = b.dataset.min !== '' ? Number(b.dataset.min) : null;
        const pmax = b.dataset.max !== '' ? Number(b.dataset.max) : null;
        if (pmin === filters.powerMin && pmax === filters.powerMax) b.classList.add('active');
      });
    }
  }

  // Resolve a card from URL params (card + hero + treatment).
  function cardFromURLParams(params) {
    const num       = params.get('card');
    const hero      = params.get('hero');
    const treatment = params.get('treatment');
    if (!num || !displayCards.length) return null;
    const numStr = String(num);
    if (hero && treatment) {
      return displayCards.find(c => String(c.cardNumber) === numStr && c.hero === hero && c.treatment === treatment)
          ?? displayCards.find(c => String(c.cardNumber) === numStr && c.hero === hero)
          ?? displayCards.find(c => String(c.cardNumber) === numStr);
    }
    if (hero) {
      return displayCards.find(c => String(c.cardNumber) === numStr && c.hero === hero)
          ?? displayCards.find(c => String(c.cardNumber) === numStr);
    }
    const set = cardsByNumber?.get(numStr.toUpperCase()) || cardsByNumber?.get(numStr);
    return set?.[0] ?? displayCards.find(c => String(c.cardNumber) === numStr);
  }

  function showView(name, fromHistory = false) {
    currentView = name;
    viewIds.forEach(id => {
      const el = $(`view-${id}`);
      if (el) el.hidden = id !== name;
    });
    Object.entries(navBtnIds).forEach(([id, btnId]) => {
      const btn = $(btnId);
      if (!btn) return;
      const active = id === name;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-current', active ? 'page' : 'false');
    });
    closeSidebar();
    if (name === 'scan') {
      initScanView();
    } else {
      teardownScan();
    }
    if (name === 'rules' || name === 'decks' || name === 'practice') {
      initPlayView();
    }

    if (!fromHistory) {
      history.pushState({ view: name }, '', buildSearchURL());
    }
  }

  Object.entries(navBtnIds).forEach(([view, btnId]) => {
    const btn = $(btnId);
    if (btn) btn.addEventListener('click', () => showView(view));
  });

  window.addEventListener('popstate', () => {
    const params = new URLSearchParams(window.location.search);
    const urlView = params.get('view') || 'search';

    // Always restore filter state from URL on any navigation.
    if (displayCards.length) {
      applyURLParams(params);
      applyFilters(true); // skipURLSync — URL is already the target
    }

    if (params.has('card')) {
      // Restore card modal — find by cardNumber + hero.
      if (urlView !== currentView) currentView = urlView;
      const card = cardFromURLParams(params);
      if (card) openModal(card, -1, true);
    } else {
      // No card — close modal if open and show the correct view.
      if (!modalOverlay.hidden) {
        cleanupZoom();
        modalOverlay.hidden = true;
        modalNavPrev.hidden = true;
        modalNavNext.hidden = true;
        currentModalIndex = -1;
        document.body.style.overflow = '';
      }
      showView(urlView, true);
    }
  });

  /* ================================================================
     PLAY VIEW
  ================================================================ */
  let playViewInitialized = false;

  function initPlayView() {
    if (playViewInitialized) return;
    playViewInitialized = true;

    // Top-level tab pills: Rules ↔ Strategy
    const tabs   = document.querySelectorAll('.play-tab');
    const panels = document.querySelectorAll('.play-panel');

    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        const target = tab.dataset.tab;
        tabs.forEach(t => {
          t.classList.toggle('active', t.dataset.tab === target);
          t.setAttribute('aria-selected', String(t.dataset.tab === target));
        });
        panels.forEach(p => {
          p.hidden = p.id !== `play-panel-${target}`;
        });
      });
    });

    // Mode switching — syncs rules-mode-btn tabs and rules-content visibility.
    const modeBtns    = document.querySelectorAll('.rules-mode-btn');
    const modeContent = document.querySelectorAll('.rules-content');

    function applyMode(mode) {
      modeBtns.forEach(b => b.classList.toggle('active', b.dataset.mode === mode));
      modeContent.forEach(el => {
        el.hidden = el.id !== `rules-${mode}`;
      });
    }

    applyMode('rookie');

    modeBtns.forEach(btn => {
      btn.addEventListener('click', () => applyMode(btn.dataset.mode));
    });

    // Browse panel — navigate to Search with pre-applied filters
    function browseToSearch(type, value) {
      resetFilters();
      if (type === 'element') {
        setElementFilter(value);
      } else if (type === 'query' && value) {
        searchInput.value = value;
        filters.query = value;
        searchClear.hidden = false;
      }
      showView('search');
      applyFilters();
    }

    // Attach to collection cards (top-level .browse-collection-card with button-like behavior)
    document.querySelectorAll('[data-browse-type]').forEach(el => {
      el.addEventListener('click', e => {
        // Allow child buttons to fire independently; skip if click was on a child chip
        if (e.target.closest('.browse-hero-chip') || e.target.closest('.browse-search-btn')) return;
        const type  = el.dataset.browseType;
        const value = el.dataset.browseValue || '';
        if (type !== 'woba') browseToSearch(type, value);
      });
    });

    // Explicit Browse buttons (arrows)
    document.querySelectorAll('.browse-search-btn').forEach(btn => {
      btn.addEventListener('click', e => {
        e.stopPropagation();
        const type  = btn.dataset.browseType  || btn.closest('[data-browse-type]')?.dataset.browseType  || 'query';
        const value = btn.dataset.browseValue || btn.closest('[data-browse-type]')?.dataset.browseValue || '';
        browseToSearch(type, value);
      });
    });

    // WOBA hero chips
    document.querySelectorAll('.browse-hero-chip').forEach(chip => {
      chip.addEventListener('click', e => {
        e.stopPropagation();
        browseToSearch('query', chip.dataset.browseValue);
      });
    });

    // Play view launch buttons → navigate to full views
    document.getElementById('btn-go-deck-builder')?.addEventListener('click', () => showView('decks'));
    document.getElementById('btn-go-practice')?.addEventListener('click', () => showView('practice'));
  }

  /* ================================================================
     SCAN VIEW
  ================================================================ */
  const WORKER_URL = 'https://boba-ebay-proxy.benwilkoff.workers.dev';
  let scanStream      = null;
  let _scanQRInterval = null;  // regenerate QR every 30s to track refresh token rotation

  function initScanView() {
    const container = $('scan-container');
    if (!container || container.dataset.initialized === '1') return;
    container.dataset.initialized = '1';

    if (!navigator.mediaDevices?.getUserMedia) {
      renderScanUnavailable(container);
      return;
    }
    renderScanCamera(container);
  }

  function teardownScan() {
    if (_scanQRInterval) {
      clearInterval(_scanQRInterval);
      _scanQRInterval = null;
    }
    if (scanStream) {
      scanStream.getTracks().forEach(t => t.stop());
      scanStream = null;
    }
    const container = $('scan-container');
    if (container) {
      container.innerHTML = '';
      delete container.dataset.initialized;
    }
  }

  async function renderScanCamera(container) {
    const isDesktop = window.innerWidth >= 1024;

    container.innerHTML = `
      <div class="scan-wrap">
        <div class="scan-camera-area">
          <div class="scan-video-wrap">
            <video id="scan-video" class="scan-video" autoplay playsinline muted></video>
            <div class="scan-guide-frame" aria-hidden="true"></div>
          </div>
          <p class="scan-status" id="scan-status" aria-live="polite">Starting camera…</p>
          <button class="scan-capture-btn" id="scan-capture-btn" disabled>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"
                 width="20" height="20" aria-hidden="true">
              <circle cx="12" cy="12" r="9"/>
              <circle cx="12" cy="12" r="4" fill="currentColor" stroke="none"/>
            </svg>
            Capture Card
          </button>
          <canvas id="scan-canvas" style="display:none"></canvas>
          <div class="scan-result" id="scan-result" hidden></div>
        </div>
        ${isDesktop ? `
          <div class="scan-desktop-aside">
            <p class="scan-aside-label">Scan on your phone:</p>
            <div id="scan-qr-container" class="scan-qr-img" style="width:220px;height:220px;display:flex;align-items:center;justify-content:center;">
              <span style="font-size:0.75rem;color:var(--boba-text-muted)">Loading…</span>
            </div>
          </div>
        ` : ''}
      </div>
    `;

    startCamera();
    $('scan-capture-btn').addEventListener('click', handleCapture);

    if (isDesktop) {
      generateScanQR().catch(() => {});
      // Regenerate every 30 s — Supabase rotates the refresh token on each
      // auto-refresh cycle (~1 hr), so the QR must stay current.
      _scanQRInterval = setInterval(() => generateScanQR().catch(() => {}), 30_000);
    }
  }

  async function generateScanQR() {
    const qrContainer = $('scan-qr-container');
    const note        = $('scan-qr-note');
    if (!qrContainer) return;

    // Build the QR target URL.
    // If the user is signed in, embed their current refresh token so the
    // scanned device gets authenticated automatically (?view=scan&rt=TOKEN).
    // The refresh token is short (~60 chars) — well within QR capacity at L level.
    // We regenerate every 30 s because Supabase rotates the refresh token on
    // each auto-refresh cycle; the QR must always carry the current token.
    // If the user isn't signed in, the QR still opens the scanner but they'll
    // need to sign in manually on their phone.
    const base    = window.location.origin + window.location.pathname;
    const session = Auth.getSession();
    const rt      = session?.refresh_token;
    const scanUrl = rt
      ? `${base}?view=scan&rt=${encodeURIComponent(rt)}`
      : `${base}?view=scan`;

    // Lazy-load qrcodejs — has a proper browser bundle unlike the 'qrcode' npm package
    if (!window.QRCode) {
      await new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = 'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js';
        s.onload = resolve;
        s.onerror = reject;
        document.head.appendChild(s);
      });
    }

    // qrcodejs takes a container div and creates the canvas inside it
    qrContainer.innerHTML = '';
    new window.QRCode(qrContainer, {
      text:           scanUrl,
      width:          220,
      height:         220,
      colorDark:      '#00F5FF',
      colorLight:     '#0D0D1A',
      correctLevel:   window.QRCode.CorrectLevel.L,
    });

    if (note) {
      note.textContent = rt
        ? 'Scan with any phone — you\'ll be signed in automatically.'
        : 'Scan with any phone. Sign in on desktop first to carry over your session.';
    }
  }

  async function startCamera() {
    const statusEl = $('scan-status');
    const captureBtn = $('scan-capture-btn');
    try {
      scanStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } }
      });
      const video = $('scan-video');
      video.srcObject = scanStream;
      await video.play();
      captureBtn.disabled = false;
      statusEl.textContent = 'Position card so the number is clearly visible, then tap Capture.';
    } catch {
      captureBtn.hidden = true;
      statusEl.textContent = 'Camera access denied. Enable camera permissions and refresh.';
    }
  }

  async function handleCapture() {
    const captureBtn  = $('scan-capture-btn');
    const statusEl    = $('scan-status');
    const resultEl    = $('scan-result');
    const video       = $('scan-video');
    const canvas      = $('scan-canvas');

    captureBtn.disabled = true;
    resultEl.hidden = true;

    if (!video.videoWidth) {
      statusEl.textContent = 'Camera not ready yet. Please wait a moment and try again.';
      captureBtn.disabled = false;
      return;
    }

    statusEl.textContent = 'Scanning…';

    // Resize frame to max 400px wide before encoding (keeps payload small for AI)
    const maxW = 640;
    const vw = video.videoWidth  || maxW;
    const vh = video.videoHeight || 480;
    const scale = Math.min(1, maxW / vw);
    canvas.width  = Math.round(vw * scale);
    canvas.height = Math.round(vh * scale);
    canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
    const base64 = canvas.toDataURL('image/jpeg', 0.85).split(',')[1];

    try {
      const res  = await fetch(`${WORKER_URL}/ocr`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image: base64 })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      const { cardNumber, rawText } = data;

      console.log('[scan] rawText:', rawText);
      console.log('[scan] cardNumber:', cardNumber);

      // Primary: card number match — exact, no ambiguity
      const numberMatches = cardNumber
        ? (cardsByNumber.get(String(cardNumber).toUpperCase()) ?? [])
        : [];

      // Fallback: hero + power + element scoring, returns ranked candidates
      const textCandidates = (!numberMatches.length && rawText)
        ? findCardsByOCRText(rawText)
        : [];

      const candidates = numberMatches.length ? numberMatches : textCandidates;

      if (candidates.length === 1) {
        showScanMatch(resultEl, candidates[0]);
        statusEl.textContent = `Found: ${candidates[0].name}`;
      } else if (candidates.length > 1) {
        showScanCandidates(resultEl, candidates);
        statusEl.textContent = `${candidates.length} possible matches — select the right card.`;
      } else if (cardNumber) {
        statusEl.textContent = `Detected #${cardNumber} — not in catalog.`;
        showScanRetry(resultEl);
      } else {
        statusEl.textContent = 'No card detected. Ensure good lighting and try again.';
        showScanRetry(resultEl);
      }
    } catch (err) {
      statusEl.textContent = `Scan failed: ${err.message}`;
      showScanRetry(resultEl);
      console.error('OCR error:', err);
    }

    captureBtn.disabled = false;
  }

  // Multi-facet OCR matching — mirrors iOS secondary path but returns ALL ranked candidates.
  // Scores each card by how many facets agree with the transcribed text.
  // Caller shows a picker when > 1 result.
  const OCR_ELEMENTS = ['FIRE','ICE','HEX','STEEL','BRAWL','GLOW','GUM','SUPER'];
  // Words in OCR text that hint at a set name
  const OCR_SET_HINTS = [
    { words: ['griffey'],               sets: ['Griffey Edition'] },
    { words: ['alpha blast'],           sets: ['Alpha Blast'] },
    { words: ['alpha update'],          sets: ['Alpha Update'] },
    { words: ['alpha'],                 sets: ['Alpha Edition', 'Alpha Blast', 'Alpha Update'] },
    { words: ['world champion'],        sets: ['World Champions'] },
    { words: ['big league'],            sets: ['Big League Chew'] },
    { words: ['national'],              sets: ['National Starter Set'] },
    { words: ['battle trainer'],        sets: ['Battle Trainer Kit'] },
  ];

  function findCardsByOCRText(rawText) {
    const text    = rawText.toLowerCase();
    const textUp  = rawText.toUpperCase();

    // 2–3 digit integers (powers run ~60–200)
    const nums = new Set(
      [...text.matchAll(/\b(\d{2,3})\b/g)].map(m => parseInt(m[1]))
    );
    if (nums.size === 0) return [];

    // Which elements appear in the OCR text?
    const seenElements = new Set(OCR_ELEMENTS.filter(el => textUp.includes(el)));

    // Which sets are hinted?
    const hintedSets = new Set();
    for (const hint of OCR_SET_HINTS) {
      if (hint.words.some(w => text.includes(w))) hint.sets.forEach(s => hintedSets.add(s));
    }

    const scored = [];
    for (const card of displayCards) {
      if (!card.hero || card.power == null) continue;

      const heroWords = card.hero.toLowerCase().split(/\s+/).filter(w => w.length > 2);
      if (!heroWords.length) continue;
      if (!heroWords.every(w => text.includes(w))) continue;  // hero must match
      if (!nums.has(card.power)) continue;                     // power must match

      // Score additional facets — more agreement = higher confidence
      let score = 0;
      if (seenElements.size > 0) {
        if (seenElements.has(card.element))  score += 3;  // element confirmed
        else                                  score -= 1;  // different element mentioned
      }
      if (hintedSets.size > 0) {
        if (hintedSets.has(card.set))  score += 2;
        else                            score -= 1;
      }
      if (card.imageFile) score += 1;  // prefer cards with images for visual confirmation

      scored.push({ card, score });
    }

    if (!scored.length) return [];
    scored.sort((a, b) => b.score - a.score);

    // Cap at 12 to keep the picker usable
    return scored.slice(0, 12).map(s => s.card);
  }

  function showScanCandidates(container, candidates) {
    container.innerHTML = `
      <div class="scan-candidates">
        <p class="scan-candidates-label">Select the card you scanned:</p>
        <div class="scan-candidates-list">
          ${candidates.map((card, i) => {
            const imgSrc  = API.cardThumbUrl(card);
            const element = card.element || 'NONE';
            const meta    = [card.set, card.treatment].filter(Boolean).join(' · ');
            return `
              <button class="scan-candidate-item" data-index="${i}"
                      aria-label="${escHtml(card.name)}, ${element}, power ${card.power}">
                ${imgSrc
                  ? `<img class="scan-candidate-img" src="${escHtml(imgSrc)}" alt="" loading="lazy">`
                  : `<div class="scan-candidate-img scan-candidate-placeholder"></div>`}
                <div class="scan-candidate-info">
                  <div class="scan-candidate-name">${escHtml(card.name)}</div>
                  <div class="scan-candidate-meta">
                    <span class="element-badge" data-element="${escHtml(element)}">${escHtml(element)}</span>
                    <span class="scan-candidate-power">${card.power}</span>
                    ${meta ? `<span class="scan-candidate-set">${escHtml(meta)}</span>` : ''}
                  </div>
                  <div class="scan-candidate-number">#${escHtml(card.cardNumber)}</div>
                </div>
              </button>`;
          }).join('')}
        </div>
        <button class="btn-ghost-sm scan-again-btn" style="margin-top:.75rem">Scan Again</button>
      </div>`;
    container.hidden = false;
    candidates.forEach((card, i) => {
      container.querySelectorAll('.scan-candidate-item')[i]
        .addEventListener('click', () => {
          showScanMatch(container, card);
          $('scan-status').textContent = `Found: ${card.name}`;
        });
    });
    container.querySelector('.scan-again-btn').addEventListener('click', resetScan);
  }

  function showScanMatch(container, card) {
    const imgSrc  = API.cardThumbUrl(card);
    const element = card.element || 'NONE';
    container.innerHTML = `
      <div class="scan-result-card">
        ${imgSrc ? `<img class="scan-result-img" src="${escHtml(imgSrc)}" alt="${escHtml(card.name)}">` : ''}
        <div class="scan-result-info">
          <span class="element-badge" data-element="${escHtml(element)}">${escHtml(element)}</span>
          <div class="scan-result-name">${escHtml(card.name)}</div>
          <div class="scan-result-num">#${escHtml(card.cardNumber)}</div>
          <div class="scan-result-actions">
            <button class="btn-primary scan-view-btn">View Card</button>
            <button class="btn-ghost-sm scan-again-btn">Scan Again</button>
          </div>
        </div>
      </div>
    `;
    container.hidden = false;
    container.querySelector('.scan-view-btn').addEventListener('click', () => openModal(card));
    container.querySelector('.scan-again-btn').addEventListener('click', resetScan);
  }

  function showScanRetry(container) {
    container.innerHTML = `<button class="btn-ghost-sm scan-again-btn">Try Again</button>`;
    container.hidden = false;
    container.querySelector('.scan-again-btn').addEventListener('click', resetScan);
  }

  function resetScan() {
    const resultEl = $('scan-result');
    if (resultEl) resultEl.hidden = true;
    const statusEl = $('scan-status');
    if (statusEl) statusEl.textContent = 'Position card so the number is clearly visible, then tap Capture.';
  }

  function renderScanUnavailable(container) {
    const scanUrl = window.location.origin + window.location.pathname + '?view=scan';
    const qrSrc   = `https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(scanUrl)}&color=00F5FF&bgcolor=0D0D1A&qzone=1`;
    container.innerHTML = `
      <div class="view-inner">
        <h2 class="view-heading">Scan</h2>
        <p class="placeholder-text">Camera scanning isn't available in this browser.</p>
        <p class="placeholder-text">For instant on-device scanning, use the <strong>BOBA Playbook iOS app</strong>.</p>
        <div class="scan-qr-block">
          <p class="scan-aside-label">Open on your phone:</p>
          <img class="scan-qr-img" src="${escHtml(qrSrc)}" alt="QR code" width="180" height="180">
        </div>
      </div>
    `;
  }

  /* ================================================================
     DATA PREPARATION
     Build lookup structures after cards.json loads.
  ================================================================ */

  // Null out imageFile for any card whose number is in the removals set.
  // This propagates automatically to all renderers since they check card.imageFile.
  function applyImageRemovals(removedSet) {
    if (!removedSet.size) return;
    for (const card of cards) {
      if (removedSet.has(String(card.cardNumber))) {
        card.imageFile = null;
      }
    }
  }

  function prepareData() {
    // Build cardsByNumber: string cardNumber → all Card variants (hero associations)
    // Kept for the modal "hero variants" panel — not used to collapse displayCards.
    for (const card of cards) {
      const num = String(card.cardNumber);
      if (!cardsByNumber.has(num)) cardsByNumber.set(num, []);
      cardsByNumber.get(num).push(card);
    }

    // Build cardsByBobaId: bobaId → Card — used for exact card matching in Collection
    cardsByBobaId.clear();
    for (const card of cards) {
      if (card.bobaId) cardsByBobaId.set(String(card.bobaId), card);
    }

    // Every card is distinct (different imageFile per hero association).
    // Show all cards; sort with images first.
    displayCards.push(...cards);
    displayCards.sort((a, b) => {
      const aImg = !!(a.imageFile);
      const bImg = !!(b.imageFile);
      if (aImg !== bImg) return aImg ? -1 : 1;
      return 0;
    });

    // Wire up Deck Builder + Practice once cards are loaded
    if (typeof window.initPlayTools === 'function') {
      window.initPlayTools(displayCards);
    }
  }

  /* ================================================================
     SEARCH LOGIC
     search-index values are bobaId strings — one bobaId = one card.
  ================================================================ */

  function computeResults() {
    let resultIds = null; // null = "all cards"; Set of bobaId strings when filtered

    // Text search
    // Normalize dashes to spaces so card numbers like "CBF-656" tokenize correctly.
    const q = filters.query.trim().toLowerCase().replace(/-/g, ' ');
    if (q) {
      const tokens = q.split(/\s+/).filter(Boolean);
      for (const token of tokens) {
        // Expand community aliases: if the user typed a known slang
        // ("bojax", "obf", "lino", "blizzy"), we also match the
        // canonical-form prefixes so they land real results.
        const expansions = [token, ...((aliasIndex[token] || []).map(s => s.toLowerCase()))];

        // Collect tokenIndex prefix matches — values are now bobaIds
        const matches = new Set();
        for (const key in searchIndex.tokenIndex) {
          if (expansions.some(exp => key.startsWith(exp))) {
            for (const id of searchIndex.tokenIndex[key]) {
              matches.add(String(id));
            }
          }
        }

        // Hero-name detection: if this token primarily resolves to hero names
        // (byHero prefix matches cover ≥60% of tokenIndex matches), restrict
        // results to those hero cards. byHero now maps hero→[bobaIds] so each
        // id resolves to exactly the right card — no post-filter needed.
        if (token.length >= 3 && matches.size > 0) {
          const matchingHeroes = [];
          const heroIdSet = new Set();
          for (const hero of Object.keys(searchIndex.byHero)) {
            if (hero.toLowerCase().startsWith(token)) {
              matchingHeroes.push(hero);
              for (const id of searchIndex.byHero[hero]) {
                heroIdSet.add(String(id));
              }
            }
          }
          if (matchingHeroes.length > 0 && heroIdSet.size >= matches.size * 0.6) {
            resultIds = resultIds === null ? heroIdSet : intersect(resultIds, heroIdSet);
            continue;
          }
        }

        resultIds = resultIds === null ? matches : intersect(resultIds, matches);
      }
      if (resultIds !== null && resultIds.size === 0) return [];
    }

    // Element filter
    if (filters.element) {
      const s = new Set((searchIndex.byElement[filters.element] || []).map(String));
      resultIds = resultIds === null ? s : intersect(resultIds, s);
    }

    // Set filter
    if (filters.set) {
      const s = new Set((searchIndex.bySet[filters.set] || []).map(String));
      resultIds = resultIds === null ? s : intersect(resultIds, s);
    }

    // Treatment filter
    if (filters.treatment) {
      const s = new Set((searchIndex.byTreatment[filters.treatment] || []).map(String));
      resultIds = resultIds === null ? s : intersect(resultIds, s);
    }

    // Has image filter
    if (filters.hasImage) {
      const s = new Set((searchIndex.hasImage || []).map(String));
      resultIds = resultIds === null ? s : intersect(resultIds, s);
    }

    if (resultIds === null) {
      // No search/filter applied — apply power filter directly against all cards if needed
      if (filters.powerMin !== null || filters.powerMax !== null) {
        return displayCards.filter(card => {
          const p = Number(card.power);
          const minOk = filters.powerMin === null || p >= filters.powerMin;
          const maxOk = filters.powerMax === null || p <= filters.powerMax;
          return minOk && maxOk;
        });
      }
      return displayCards;
    }

    // Expand bobaIds → individual cards. Each bobaId maps to exactly one card
    // so no hero-variant filtering is needed — search contamination is impossible.
    const results = [];
    for (const id of resultIds) {
      const card = cardsByBobaId.get(id);
      if (card) results.push(card);
    }

    // Power range filter applied per-card (cards sharing a number can have different power)
    if (filters.powerMin !== null || filters.powerMax !== null) {
      return results.filter(card => {
        const p = Number(card.power);
        const minOk = filters.powerMin === null || p >= filters.powerMin;
        const maxOk = filters.powerMax === null || p <= filters.powerMax;
        return minOk && maxOk;
      });
    }

    return results;
  }

  function intersect(a, b) {
    return new Set([...a].filter(x => b.has(x)));
  }

  /* ================================================================
     SORT
  ================================================================ */

  function sortCards(arr) {
    const heroName = c => (c.hero || c.name || '').toLowerCase();
    const isSealed = c => c.cardType === 'Sealed Product';

    return [...arr].sort((a, b) => {
      // Sealed products always last, regardless of sort mode.
      const sealedDiff = Number(isSealed(a)) - Number(isSealed(b));
      if (sealedDiff) return sealedDiff;

      // Cards with images always before image-pending, regardless of sort.
      const aImg = !!a.imageFile, bImg = !!b.imageFile;
      if (aImg !== bImg) return aImg ? -1 : 1;

      switch (filters.sortBy) {
        case 'name-asc':
          return heroName(a).localeCompare(heroName(b));
        case 'name-desc':
          return heroName(b).localeCompare(heroName(a));
        case 'power-desc': {
          const d = Number(b.power) - Number(a.power);
          return d || heroName(a).localeCompare(heroName(b));
        }
        case 'power-asc': {
          const d = Number(a.power) - Number(b.power);
          return d || heroName(a).localeCompare(heroName(b));
        }
        case 'number-asc':
          return String(a.cardNumber).localeCompare(String(b.cardNumber), undefined, { numeric: true });
        case 'number-desc':
          return String(b.cardNumber).localeCompare(String(a.cardNumber), undefined, { numeric: true });
        case 'variation':
          return (a.variation || '').localeCompare(b.variation || '') ||
                 heroName(a).localeCompare(heroName(b));
        default:
          // Default: card number ascending.
          return String(a.cardNumber).localeCompare(String(b.cardNumber), undefined, { numeric: true });
      }
    });
  }

  /* ================================================================
     TREATMENT & SET CLASS HELPERS
  ================================================================ */

  function getTreatmentClass(treatment) {
    if (!treatment) return 'tf-base';
    const t = treatment.toLowerCase();
    if (t.includes('blizzard')) return 'tf-blizzard';
    if (t.includes('superfoil')) return 'tf-superfoil';
    if (t.includes('colosseum')) return 'tf-colosseum';
    if (t.includes('battlefoil')) return 'tf-battlefoil';
    if (t.includes('inspired ink') || t.includes('inspired-ink')) return 'tf-inspired';
    if (t.includes('inspired')) return 'tf-inspired-m';
    if (t.includes('logofoil')) return 'tf-logofoil';
    if (t.includes('blast')) return 'tf-blast';
    if (t.includes('paper')) return 'tf-paper';
    if (t === 'base' || t === 'standard' || t === '') return 'tf-base';
    return 'tf-special';
  }

  // Returns a shortened display label for treatments that are too long for ribbons/filters.
  // The raw treatment value is always used for data lookups and filter keys.
  // For non-Hero cards whose name/hero contains non-ASCII (e.g. Japanese Kaiju Dog),
  // fall back to the variation field which holds the readable English name.
  function cardDisplayName(card) {
    const raw = card.name || '';
    if (card.cardType !== 'Hero' && /[^\x00-\x7F]/.test(raw) && card.variation && !/[^\x00-\x7F]/.test(card.variation)) {
      return card.variation;
    }
    return raw;
  }

  function displayTreatment(treatment) {
    if (!treatment) return treatment;
    const t = treatment.toLowerCase();
    if (t.includes('colosseum')) return 'Colosseum';
    if (t.includes('grandma') || t.includes('linoleum')) return 'Linoleum';
    return treatment;
  }

  function getSetClass(set) {
    if (!set) return 'set-other';
    const s = set.toLowerCase();
    if (s.includes('alpha')) return 'set-alpha';
    if (s.includes('griffey')) return 'set-griffey';
    if (s.includes('world champions') || s.includes('champions')) return 'set-champions';
    if (s.includes('starter')) return 'set-starter';
    return 'set-other';
  }

  /* ================================================================
     FILTER UI
  ================================================================ */

  function buildElementFilters() {
    const elements = Object.keys(searchIndex.byElement).sort();

    const allPill = makePill('', 'All');
    allPill.classList.add('active');
    allPill.setAttribute('aria-pressed', 'true');
    allPill.addEventListener('click', () => setElementFilter(''));
    elementFilters.appendChild(allPill);

    for (const el of elements) {
      const pill = makePill(el, el);
      pill.addEventListener('click', () => setElementFilter(el));
      elementFilters.appendChild(pill);
    }
  }

  function makePill(element, label) {
    const btn = document.createElement('button');
    btn.className = 'element-pill';
    btn.dataset.element = element;
    btn.setAttribute('aria-pressed', 'false');
    const dot = document.createElement('span');
    dot.className = 'element-pill-dot';
    btn.appendChild(dot);
    btn.appendChild(document.createTextNode(label));
    return btn;
  }

  function setElementFilter(element) {
    filters.element = element;
    elementFilters.querySelectorAll('.element-pill').forEach(pill => {
      const active = pill.dataset.element === element;
      pill.classList.toggle('active', active);
      pill.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
    applyFilters();
  }

  function buildSetFilter() {
    const sets = Object.keys(categories.sets || {}).sort();
    for (const set of sets) {
      const opt = document.createElement('option');
      opt.value = set;
      const count = categories.sets[set]?.count;
      opt.textContent = count ? `${set} (${count.toLocaleString()})` : set;
      setFilter.appendChild(opt);
    }
  }

  function buildTreatmentFilter(selectedSet) {
    while (treatmentFilter.options.length > 1) treatmentFilter.remove(1);
    const all = selectedSet
      ? (categories.sets[selectedSet]?.treatments || []).sort()
      : [...new Set(Object.values(categories.sets || {}).flatMap(s => s.treatments || []))].sort();
    for (const t of all) {
      const opt = document.createElement('option');
      opt.value = t;
      opt.textContent = displayTreatment(t);
      treatmentFilter.appendChild(opt);
    }
  }

  setFilter.addEventListener('change', () => {
    filters.set = setFilter.value;
    const prev = treatmentFilter.value;
    buildTreatmentFilter(filters.set);
    // Restore treatment selection if still valid in new set
    if ([...treatmentFilter.options].some(o => o.value === prev)) {
      treatmentFilter.value = prev;
      filters.treatment = prev;
    } else {
      filters.treatment = '';
    }
    applyFilters();
  });

  treatmentFilter.addEventListener('change', () => {
    filters.treatment = treatmentFilter.value;
    applyFilters();
  });

  hasImageCheckbox?.addEventListener('change', () => {
    filters.hasImage = hasImageCheckbox.checked;
    applyFilters();
  });

  // Power range inputs
  let powerTimer = null;
  function onPowerInput() {
    clearTimeout(powerTimer);
    powerTimer = setTimeout(() => {
      const minVal = powerMinInput?.value.trim();
      const maxVal = powerMaxInput?.value.trim();
      filters.powerMin = minVal !== '' ? Number(minVal) : null;
      filters.powerMax = maxVal !== '' ? Number(maxVal) : null;
      // Clear active state on presets when manual input is used
      document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
      if (filters.powerMin === null && filters.powerMax === null) {
        document.querySelector('.power-preset[data-min=""]')?.classList.add('active');
      }
      applyFilters();
    }, 300);
  }
  powerMinInput?.addEventListener('input', onPowerInput);
  powerMaxInput?.addEventListener('input', onPowerInput);

  // Power preset buttons
  document.querySelectorAll('.power-preset').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const minVal = btn.dataset.min;
      const maxVal = btn.dataset.max;
      filters.powerMin = minVal !== '' ? Number(minVal) : null;
      filters.powerMax = maxVal !== '' ? Number(maxVal) : null;
      if (powerMinInput) powerMinInput.value = minVal;
      if (powerMaxInput) powerMaxInput.value = maxVal;
      applyFilters();
    });
  });

  clearFiltersBtn?.addEventListener('click', resetFilters);

  function resetFilters() {
    filters.query = '';
    filters.element = '';
    filters.set = '';
    filters.treatment = '';
    filters.hasImage = false;
    filters.powerMin = null;
    filters.powerMax = null;
    filters.sortBy = 'default';
    searchInput.value = '';
    searchClear.hidden = true;
    setFilter.value = '';
    buildTreatmentFilter('');
    if (hasImageCheckbox) hasImageCheckbox.checked = false;
    if (powerMinInput) powerMinInput.value = '';
    if (powerMaxInput) powerMaxInput.value = '';
    if (sortBySelect) sortBySelect.value = 'default';
    document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
    document.querySelector('.power-preset[data-min=""]')?.classList.add('active');
    setElementFilter('');
    updateFilterBadge();
  }

  sortBySelect?.addEventListener('change', () => {
    filters.sortBy = sortBySelect.value;
    applyFilters();
  });

  /* ================================================================
     CARD GRID RENDERING
  ================================================================ */

  // skipURLSync: true when called from popstate/init — URL is already correct.
  function applyFilters(skipURLSync = false) {
    filteredCards = sortCards(computeResults());
    displayedCount = 0;
    cardGrid.innerHTML = '';
    renderNextPage();
    updateResultsCount();
    updateFilterBadge();
    // Reflect filter state in URL so searches are bookmarkable/shareable.
    // Use replaceState (not push) so filter typing doesn't flood browser history.
    if (!skipURLSync && modalOverlay.hidden) {
      history.replaceState({ view: currentView }, '', buildSearchURL());
    }
  }

  function renderNextPage() {
    const end = Math.min(displayedCount + PAGE_SIZE, filteredCards.length);
    const fragment = document.createDocumentFragment();
    for (let i = displayedCount; i < end; i++) {
      fragment.appendChild(buildCardElement(filteredCards[i], i));
    }
    cardGrid.appendChild(fragment);
    displayedCount = end;

    const isEmpty = filteredCards.length === 0;
    cardGrid.hidden = isEmpty;
    emptyState.hidden = !isEmpty;
  }

  function buildCardElement(card, index) {
    const treatmentClass = getTreatmentClass(card.treatment);
    const el = document.createElement('article');
    el.className = `card-item ${treatmentClass}`;
    el.setAttribute('role', 'listitem');
    el.dataset.element = card.element || 'NONE';
    el.setAttribute('tabindex', '0');
    el.setAttribute('aria-label', `${card.name}, ${card.element || 'No element'}, Power ${card.power}`);

    const thumbSrc = API.cardThumbUrl(card);
    const imgHtml = thumbSrc
      ? `<img class="card-img" src="${escHtml(thumbSrc)}"
              alt="${escHtml(card.name)}" loading="lazy" decoding="async">`
      : `<div class="card-img-placeholder" aria-hidden="true">
           <span class="placeholder-brand">BOBA PB</span>
           <span class="placeholder-status">Image Pending</span>
         </div>`;

    // Only show treatment ribbon for non-base treatments
    const ribbonHtml = (treatmentClass !== 'tf-base')
      ? `<div class="card-treatment-ribbon" aria-hidden="true">${escHtml(displayTreatment(card.treatment))}</div>`
      : '';

    el.innerHTML = `
      <div class="card-img-wrap">
        ${imgHtml}
        ${ribbonHtml}
      </div>
      <div class="card-info">
        <div class="card-number">${escHtml(card.cardType === 'Sealed Product' ? card.set : card.cardNumber)}</div>
        <div class="card-name">${escHtml(cardDisplayName(card))}</div>
        <div class="card-meta">
          ${card.cardType === 'Sealed Product'
            ? `<span class="element-badge" data-element="SEALED">${escHtml(card.productType ? card.productType.replace(/-/g, ' ').toUpperCase() : 'SEALED')}</span>
               ${card.msrp ? `<span class="card-power">$${card.msrp.toFixed(2)}</span>` : ''}`
            : card.cardType === 'Play'
            ? `<span class="card-type-badge ${card.isBonusPlay ? 'bonus-badge' : 'play-badge'}">${card.isBonusPlay ? 'BONUS' : 'PLAY'}</span>
               <span class="play-cost${card.playCost === 0 ? ' free' : ''}">${card.playCost === 0 ? 'FREE' : (card.playCost + ' HD')}</span>`
            : card.cardType === 'HotDog'
            ? `<span class="card-type-badge hotdog-badge">HOT DOG</span>`
            : `<span class="element-badge" data-element="${escHtml(card.element || 'NONE')}">${escHtml(card.element || 'NONE')}</span>
               <span class="card-power" aria-label="Power ${card.power}">P${escHtml(String(card.power))}</span>`
          }
        </div>
      </div>
      <div class="card-element-bar" aria-hidden="true"></div>`;

    el.addEventListener('click', () => openModal(card, index));
    el.addEventListener('keydown', e => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openModal(card, index); }
    });
    return el;
  }

  function updateResultsCount() {
    searchCount.textContent = `${filteredCards.length.toLocaleString()} cards`;
  }

  /* ================================================================
     LOAD MORE — IntersectionObserver on sentinel
  ================================================================ */
  // root: main-content because main is the scroll container (body does not scroll)
  const sentinelObserver = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting && displayedCount < filteredCards.length) {
      renderNextPage();
    }
  }, { root: document.getElementById('main-content'), rootMargin: '300px' });

  sentinelObserver.observe(loadSentinel);

  /* ================================================================
     SEARCH INPUT
  ================================================================ */
  let searchTimer = null;

  searchInput.addEventListener('input', () => {
    const val = searchInput.value;
    searchClear.hidden = !val;
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      filters.query = val;
      applyFilters();
    }, SEARCH_DEBOUNCE_MS);
  });

  searchClear.addEventListener('click', () => {
    searchInput.value = '';
    searchClear.hidden = true;
    filters.query = '';
    searchInput.focus();
    applyFilters();
  });

  /* ================================================================
     CARD DETAIL MODAL
  ================================================================ */

  /* ---- Zoom / Pan ---- */
  let _zoomAbort = null;

  function initZoom() {
    if (_zoomAbort) _zoomAbort.abort();
    _zoomAbort = new AbortController();
    const sig = _zoomAbort.signal;

    const artEl  = modalContent.querySelector('.modal-art');
    const imgEl  = modalContent.querySelector('.modal-card-img') ||
                   modalContent.querySelector('.modal-img-placeholder');
    if (!artEl || !imgEl) return;

    let scale = 1, tx = 0, ty = 0;
    let pinchDist = 0;
    let dragging  = false, dStartX = 0, dStartY = 0, dStartTx = 0, dStartTy = 0;
    let lastTap   = 0;

    function apply(animated) {
      imgEl.style.transition = animated ? 'transform 0.22s ease' : 'none';
      imgEl.style.transform  = `translate(${tx}px,${ty}px) scale(${scale})`;
      artEl.classList.toggle('zoomed',   scale > 1);
      artEl.classList.toggle('can-pan',  scale > 1 && !dragging);
      artEl.classList.toggle('dragging', dragging);
    }

    function clamp() {
      if (scale <= 1) { tx = 0; ty = 0; return; }
      const mx = artEl.clientWidth  * (scale - 1) / 2;
      const my = artEl.clientHeight * (scale - 1) / 2;
      tx = Math.max(-mx, Math.min(mx, tx));
      ty = Math.max(-my, Math.min(my, ty));
    }

    /* Touch — pinch + drag */
    imgEl.addEventListener('touchstart', (e) => {
      if (e.touches.length === 2) {
        e.preventDefault();
        pinchDist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY);
      } else if (e.touches.length === 1 && scale > 1) {
        dragging = true;
        dStartX = e.touches[0].clientX; dStartY = e.touches[0].clientY;
        dStartTx = tx; dStartTy = ty;
        apply(false);
      }
    }, { passive: false, signal: sig });

    imgEl.addEventListener('touchmove', (e) => {
      if (e.touches.length === 2) {
        e.preventDefault();
        const d = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY);
        scale = Math.max(1, Math.min(6, scale * d / pinchDist));
        pinchDist = d;
        clamp(); apply(false);
      } else if (dragging && e.touches.length === 1) {
        e.preventDefault();
        tx = dStartTx + e.touches[0].clientX - dStartX;
        ty = dStartTy + e.touches[0].clientY - dStartY;
        clamp(); apply(false);
      }
    }, { passive: false, signal: sig });

    imgEl.addEventListener('touchend', (e) => {
      dragging = false;
      if (scale < 1.08) { scale = 1; tx = 0; ty = 0; }
      // Double-tap to toggle zoom
      const now = Date.now();
      if (now - lastTap < 280 && e.changedTouches.length === 1) {
        scale = scale > 1 ? 1 : 2.5;
        tx = 0; ty = 0;
      }
      lastTap = now;
      clamp(); apply(true);
    }, { signal: sig });

    /* Wheel zoom (desktop) */
    artEl.addEventListener('wheel', (e) => {
      e.preventDefault();
      scale = Math.max(1, Math.min(6, scale * (e.deltaY < 0 ? 1.12 : 0.88)));
      if (scale === 1) { tx = 0; ty = 0; }
      clamp(); apply(false);
    }, { passive: false, signal: sig });

    /* Mouse drag (desktop) */
    artEl.addEventListener('mousedown', (e) => {
      if (scale <= 1) return;
      dragging = true;
      dStartX = e.clientX; dStartY = e.clientY;
      dStartTx = tx; dStartTy = ty;
      e.preventDefault();
      apply(false);
    }, { signal: sig });

    document.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      tx = dStartTx + e.clientX - dStartX;
      ty = dStartTy + e.clientY - dStartY;
      clamp(); apply(false);
    }, { signal: sig });

    document.addEventListener('mouseup', () => {
      if (!dragging) return;
      dragging = false; apply(false);
    }, { signal: sig });

    /* Double-click to toggle zoom (desktop) */
    let clickTimer = null;
    artEl.addEventListener('click', (e) => {
      // Only count as double-click if not a drag
      if (Math.abs(e.clientX - dStartX) > 4 || Math.abs(e.clientY - dStartY) > 4) return;
      if (clickTimer) {
        clearTimeout(clickTimer);
        clickTimer = null;
        scale = scale > 1 ? 1 : 2.5;
        tx = 0; ty = 0;
        clamp(); apply(true);
      } else {
        clickTimer = setTimeout(() => { clickTimer = null; }, 280);
      }
    }, { signal: sig });
  }

  function cleanupZoom() {
    if (_zoomAbort) { _zoomAbort.abort(); _zoomAbort = null; }
  }

  function openModal(card, index = -1, fromHistory = false) {
    modalContent.innerHTML = buildModalContent(card);
    modalOverlay.hidden = false;
    document.body.style.overflow = 'hidden';
    modalCloseBtn.focus();
    initZoom();

    // Track position in filteredCards for prev/next navigation
    currentModalIndex = index >= 0 ? index : filteredCards.findIndex(c => c.cardNumber === card.cardNumber && c.hero === card.hero);
    modalNavPrev.hidden = currentModalIndex <= 0;
    modalNavNext.hidden = currentModalIndex < 0 || currentModalIndex >= filteredCards.length - 1;

    // Push URL state so back/forward navigate between viewed cards.
    // fromHistory = true when called from popstate — URL is already correct.
    if (!fromHistory) {
      history.pushState(
        { view: currentView, card: card.cardNumber, hero: card.hero },
        '',
        buildCardURL(card)
      );
    }

    // Wire "Add to Collection" button
    modalContent.querySelector('[data-action="add-to-collection"]')
      ?.addEventListener('click', () => Collection.openAddSheet(card));

    // Wire "Share" button — URL is already correct in the address bar.
    modalContent.querySelector('[data-action="share-card"]')
      ?.addEventListener('click', (e) => {
        const url = window.location.href;
        if (navigator.share) {
          navigator.share({ title: card.name, text: `${card.name} — BOBA Playbook`, url });
        } else {
          navigator.clipboard.writeText(url).then(() => {
            const btn = e.currentTarget;
            const original = btn.innerHTML;
            btn.textContent = 'Link copied!';
            setTimeout(() => { btn.innerHTML = original; }, 2000);
          });
        }
      });

    // Wire "Mod: Edit Card Info" button
    modalContent.querySelector('[data-action="mod-edit"]')
      ?.addEventListener('click', () => openModEditPanel(card));

    // Wire "Other Versions" tile clicks
    modalContent.querySelectorAll('[data-version-card]').forEach(tile => {
      tile.addEventListener('click', () => {
        const num = tile.dataset.versionCard;
        const vCard = displayCards.find(c => String(c.cardNumber) === num && c.hero === card.hero)
          ?? displayCards.find(c => String(c.cardNumber) === num);
        if (vCard) openModal(vCard);
      });
    });

    // Load live pricing (skip for sealed products — they have their own links)
    if (card.cardType !== 'Sealed Product') loadPricing(card);
  }

  /* ================================================================
     PRICING
  ================================================================ */
  // Set name → Radish slug (mirrors iOS PricingSection.radishURL setMap)
  // Includes all set name variants found in cards.json (short names, full names, slug forms)
  const SET_SLUG_MAP = {
    // Alpha Edition variants
    'Alpha':                         ['2024', 'Alpha_Edition'],
    'Alpha Edition':                 ['2024', 'Alpha_Edition'],
    'alpha-edition':                 ['2024', 'Alpha_Edition'],
    // Alpha Update variants
    'Alpha Update':                  ['2025', 'Alpha_Update'],
    'alpha-update':                  ['2025', 'Alpha_Update'],
    'Alpha Blast':                   ['2025', 'Alpha_Blast'],
    // Griffey Edition variants
    'Griffey':                       ['2026', 'Griffey_Edition'],
    'Griffey Edition':               ['2026', 'Griffey_Edition'],
    'griffey-edition':               ['2026', 'Griffey_Edition'],
    // National Starter Set variants
    'National Starter Set':          ['2024', 'National_24_Starter_Set'],
    '2024 National Show Starter Set': ['2024', 'National_24_Starter_Set'],
    "National '24":                  ['2024', 'National_24_Starter_Set'],
    'National 24 Starter Set':       ['2024', 'National_24_Starter_Set'],
    // World Champions variants
    'World Champions':               ['2024', 'World_Champions'],
    'world-champions':               ['2024', 'World_Champions'],
    'World Champions 2024':          ['2024', 'World_Champions'],
    'World Champions 2025':          ['2025', 'World_Champions'],
    // Other sets
    'Battle Trainer Kit':            ['2024', 'Battle_Trainer_Kit'],
    'Superfan Series':               ['2024', 'Alpha_Edition'],
    'Tecmo Bowl Edition':            ['2025', 'Tecmo_Bowl'],
    'tecmo-bowl':                    ['2025', 'Tecmo_Bowl'],
    'Promo Cards':                   ['2025', 'Promo_Cards'],
    'Big League Chew':               ['2025', 'Big_League_Chew'],
    'big-league-chew':               ['2025', 'Big_League_Chew'],
    'sandstorm':                     ['2025', 'Sandstorm'],
  };

  function buildEbayUrl(card) {
    // "bo jackson battle arena {hero} {cardNumber}" — card number encodes treatment
    // (e.g. "RAD-352"), which is more reliable than full treatment names that
    // sellers rarely write out. Mirrors iOS PricingSection and worker query formula.
    const query  = ['bo jackson battle arena', card.hero, card.cardNumber]
      .filter(Boolean).join(' ');
    const params = new URLSearchParams({
      _nkw: query, LH_Sold: '1', LH_Complete: '1',
      _sacat: '0', _from: 'R40', _trksid: 'm570.l1313', _osacat: '0',
    });
    return `https://www.ebay.com/sch/i.html?${params}`;
  }

  function buildRadishUrl(card) {
    if (card.radishUrl) return card.radishUrl;
    // Programmatic fallback — mirrors iOS PricingSection.radishURL
    const prefixRemap = { LOGO: 'Logo', RAD: 'Rad', MIX: 'Mix' };
    let cardNum = card.cardNumber || '';
    for (const [ours, theirs] of Object.entries(prefixRemap)) {
      if (cardNum.startsWith(ours + '-')) {
        cardNum = theirs + cardNum.slice(ours.length);
        break;
      }
    }
    const [year, slug] = SET_SLUG_MAP[card.set] || ['2024', 'Alpha_Edition'];
    const hero = encodeURIComponent(card.hero || '');
    const num  = encodeURIComponent(cardNum);
    return `https://radishpriceguide.com/boba/${year}/${slug}/${hero}/${num}`;
  }

  function loadPricing(card) {
    const section = $('modal-pricing');
    if (!section) return;

    const ebayUrl   = buildEbayUrl(card);
    const radishUrl = buildRadishUrl(card);
    let days = 30;

    async function fetchAndRender() {
      section.innerHTML = `
        <div class="pricing-header">
          <h3 class="section-label">Pricing</h3>
          <div class="pricing-day-picker" role="group" aria-label="Time range">
            <button class="day-btn${days === 7  ? ' active' : ''}" data-days="7">7d</button>
            <button class="day-btn${days === 30 ? ' active' : ''}" data-days="30">30d</button>
            <button class="day-btn${days === 90 ? ' active' : ''}" data-days="90">90d</button>
          </div>
        </div>
        <div class="pricing-body">
          <div class="pricing-loading">
            <div class="loading-spinner-sm" aria-hidden="true"></div>
            <span>Loading…</span>
          </div>
        </div>
        <div class="pricing-links">
          <a href="${escHtml(ebayUrl)}" target="_blank" rel="noopener" class="btn-pricing-ebay">eBay Sales</a>
          <a href="${escHtml(radishUrl)}" target="_blank" rel="noopener" class="btn-pricing-radish">Radish</a>
        </div>
      `;
      section.querySelectorAll('.day-btn').forEach(btn => {
        btn.addEventListener('click', () => { days = parseInt(btn.dataset.days); fetchAndRender(); });
      });

      try {
        const params = new URLSearchParams({
          cardNumber: card.cardNumber,
          hero:    card.hero    || '',
          set:     card.set     || '',
          element: card.element || '',
          days:    String(days),
          ...(card.power    != null ? { power:     String(card.power) }  : {}),
          ...(card.radishUrl       ? { radishUrl:  card.radishUrl }       : {}),
        });
        const res  = await fetch(`${WORKER_URL}?${params}`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        renderPricingData(section, data);
      } catch {
        const body = section.querySelector('.pricing-body');
        if (body) body.innerHTML = '<p class="pricing-error">Pricing unavailable</p>';
      }
    }

    fetchAndRender();
  }

  function renderPricingSection(label, sectionData, isSold) {
    const fmt = n => n > 0 ? `$${n.toFixed(2)}` : '—';
    const { low, average, high, count, items = [] } = sectionData;
    const typeStr = isSold ? 'sold' : 'active listing';

    const itemsHtml = items.length === 0 ? '' : `
      <div class="pricing-items">
        ${items.map(item => {
          const dateStr = isSold && item.date ? relativeDate(item.date) : '';
          return `
            <a href="${escHtml(item.url)}" target="_blank" rel="noopener" class="pricing-item-row">
              <span class="pricing-item-price">${fmt(item.price)}</span>
              <span class="pricing-item-title">${escHtml(item.title)}</span>
              ${dateStr ? `<span class="pricing-item-date">${escHtml(dateStr)}</span>` : '<span class="pricing-item-arrow">↗</span>'}
            </a>`;
        }).join('')}
      </div>`;

    return `
      <div class="pricing-section${isSold ? '' : ' pricing-section-active'}">
        <p class="pricing-items-label">${label}</p>
        <div class="pricing-grid">
          <div class="pricing-stat">
            <span class="pricing-label">LOW</span>
            <span class="pricing-val">${fmt(low)}</span>
          </div>
          <div class="pricing-stat pricing-stat-center">
            <span class="pricing-label">AVG</span>
            <span class="pricing-val pricing-val-avg${isSold ? '' : ' pricing-val-active'}">${fmt(average)}</span>
          </div>
          <div class="pricing-stat">
            <span class="pricing-label">HIGH</span>
            <span class="pricing-val">${fmt(high)}</span>
          </div>
        </div>
        <p class="pricing-sale-count">${count} ${typeStr}${count !== 1 ? 's' : ''}</p>
        ${itemsHtml}
      </div>`;
  }

  function renderPricingData(section, data) {
    const body = section.querySelector('.pricing-body');
    if (!body) return;
    const fmt = n => n > 0 ? `$${n.toFixed(2)}` : '—';

    // New dual-section format
    if (data.sold || data.active) {
      const parts = [];
      if (data.sold)   parts.push(renderPricingSection('RECENT SALES', data.sold, true));
      if (data.active) parts.push(renderPricingSection('BUY NOW', data.active, false));
      body.innerHTML = parts.join('');
      return;
    }

    // Legacy format (old cached responses / old Worker versions)
    const { low, average, high, count, priceType, items = [] } = data;
    if (!count) {
      body.innerHTML = '<p class="pricing-none">No eBay listings found.</p>';
      return;
    }
    const isSold  = priceType === 'sold';
    const typeStr = isSold ? 'sold' : 'active listing';

    const itemsHtml = items.length === 0 ? '' : `
      <div class="pricing-items">
        ${items.map(item => {
          const dateStr = isSold && item.date ? relativeDate(item.date) : '';
          return `
            <a href="${escHtml(item.url)}" target="_blank" rel="noopener" class="pricing-item-row">
              <span class="pricing-item-price">${fmt(item.price)}</span>
              <span class="pricing-item-title">${escHtml(item.title)}</span>
              ${dateStr ? `<span class="pricing-item-date">${escHtml(dateStr)}</span>` : '<span class="pricing-item-arrow">↗</span>'}
            </a>`;
        }).join('')}
      </div>`;

    body.innerHTML = `
      <div class="pricing-grid">
        <div class="pricing-stat">
          <span class="pricing-label">LOW</span>
          <span class="pricing-val">${fmt(low)}</span>
        </div>
        <div class="pricing-stat pricing-stat-center">
          <span class="pricing-label">AVG</span>
          <span class="pricing-val pricing-val-avg">${fmt(average)}</span>
        </div>
        <div class="pricing-stat">
          <span class="pricing-label">HIGH</span>
          <span class="pricing-val">${fmt(high)}</span>
        </div>
      </div>
      <p class="pricing-sale-count">${count} ${typeStr}${count !== 1 ? 's' : ''}</p>
      ${itemsHtml}
    `;
  }

  function closeModal() {
    cleanupZoom();
    modalOverlay.hidden = true;
    // Nav buttons are position: fixed (not children of the overlay), so hiding
    // the overlay doesn't hide them — must do it explicitly.
    modalNavPrev.hidden = true;
    modalNavNext.hidden = true;
    currentModalIndex = -1;
    document.body.style.overflow = '';
    // Replace URL with the current search/filter state (no card param) so the
    // address bar stays accurate and forward doesn't re-open the closed card.
    history.replaceState({ view: currentView }, '', buildSearchURL());
  }

  function buildVersionsSection(card) {
    // Skip for sealed products and for cards without a hero
    if (card.cardType === 'Sealed Product' || !card.hero) return '';

    const versions = displayCards.filter(c =>
      c.hero === card.hero &&
      String(c.cardNumber) !== String(card.cardNumber) &&
      c.cardType !== 'Sealed Product'
    );
    if (versions.length === 0) return '';

    const tilesHtml = versions.map(v => {
      const thumbSrc = v.imageFile ? API.cardThumbUrl(v) : null;
      const label = escHtml(v.treatment || v.set || v.cardNumber);
      const thumb = thumbSrc
        ? `<img class="version-thumb" src="${escHtml(thumbSrc)}" alt="${escHtml(v.name)}" loading="lazy">`
        : `<div class="version-thumb-placeholder" aria-hidden="true">NO IMG</div>`;
      return `
        <button class="version-tile" data-version-card="${escHtml(String(v.cardNumber))}"
                aria-label="${escHtml(v.name)} — ${label}">
          ${thumb}
          <span class="version-label">${label}</span>
        </button>`;
    }).join('');

    return `
      <div class="other-versions">
        <p class="other-versions-label">Other Versions (${versions.length})</p>
        <div class="versions-scroll">${tilesHtml}</div>
      </div>`;
  }

  function getCardRarity(card) {
    const t = (card.treatment || '').toLowerCase();
    if (t.includes('kanji'))      return { label: 'Kanjifoil',    tier: 5 };
    if (t.includes('superfoil') || card.isInspiredInk) return { label: card.isInspiredInk ? 'Inspired Ink' : 'Superfoil', tier: 4 };
    if (t.includes('blizzard'))   return { label: 'Blizzard',     tier: 3 };
    if (t.includes('battlefoil') || t.includes('logofoil')) return { label: t.includes('logofoil') ? 'Logofoil' : 'Battlefoil', tier: 2 };
    if (t.includes('blast') || t.includes('paper')) return { label: t.includes('blast') ? 'Blast' : 'Paper', tier: 1 };
    return { label: 'Base Set', tier: 0 };
  }

  function buildModalContent(card) {
    const imgSrc = card.imageFile ? API.cardFullUrl(card) : null;
    const treatmentClass = getTreatmentClass(card.treatment);
    const setClass = getSetClass(card.set);
    const element = card.element || 'NONE';

    const imgHtml = imgSrc
      ? `<img class="modal-card-img" src="${escHtml(imgSrc)}" alt="${escHtml(card.name)}" loading="eager">`
      : `<div class="modal-img-placeholder" aria-hidden="true">
           <span class="placeholder-brand">BOBA PB</span>
           <span class="placeholder-card-num">${escHtml(card.cardNumber)}</span>
           <span class="placeholder-status">Image Pending</span>
         </div>`;

    // Build stat cells — grid layout
    const isHero    = card.cardType === 'Hero';
    const isPlay    = card.cardType === 'Play';
    const isHotDog  = card.cardType === 'HotDog';
    const statDefs = [
      // Element only meaningful for Hero cards
      isHero ? { label: 'Element', val: card.element && card.element !== 'NONE' ? card.element : null, full: false } : null,
      isPlay ? { label: 'Cost',    val: card.playCost === 0 ? 'FREE' : `${card.playCost} Hot Dog${card.playCost !== 1 ? 's' : ''}`, full: false } : null,
      { label: 'Set',       val: card.set,       full: false },
      { label: 'Sub-Set',   val: card.subSet,     full: false },
      { label: 'Type',      val: card.cardType,   full: false },
      { label: 'Variation', val: card.variation,  full: false },
    ].filter(s => s?.val);
    if (card.cardType !== 'Sealed Product') {
      statDefs.push({ label: 'Rarity', val: getCardRarity(card).label, full: false });
    }

    let statCells = statDefs.map(s =>
      `<div class="stat-cell${s.full ? ' full' : ''}">
         <div class="stat-label-sm">${escHtml(s.label)}</div>
         <div class="stat-val">${escHtml(s.val ?? '—')}</div>
       </div>`
    ).join('');

    if (card.playAbility) {
      statCells += `
        <div class="stat-cell full">
          <div class="stat-label-sm">Ability</div>
          <div class="stat-val ability">${escHtml(card.playAbility)}</div>
        </div>`;
    }

    // Sealed product modal — distinct layout
    if (card.cardType === 'Sealed Product') {
      const highlightsHtml = (card.highlights || []).map(h =>
        `<li class="sealed-highlight">${escHtml(h)}</li>`
      ).join('');
      const ebayUrl = card.ebaySearchQuery
        ? `https://www.ebay.com/sch/i.html?_nkw=${encodeURIComponent(card.ebaySearchQuery)}&LH_Complete=1&LH_Sold=1&_sacat=0`
        : null;
      const productTypeLabel = card.productType
        ? card.productType.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
        : 'Sealed Product';

      return `
        <div class="modal-layout tf-sealed" data-element="SEALED">
          <div class="modal-art">${imgHtml}</div>
          <div class="modal-details">
            <div class="modal-badges">
              <span class="element-badge element-badge-lg" data-element="SEALED">SEALED</span>
              <span class="set-badge">${escHtml(card.set || 'Unknown')}</span>
            </div>
            <div>
              <h2 class="modal-card-name" id="modal-card-name">${escHtml(card.name)}</h2>
              <div class="modal-card-number">${escHtml(productTypeLabel)}</div>
            </div>
            <div class="modal-stats" aria-label="Product stats">
              ${card.packsPerBox ? `<div class="stat-cell"><div class="stat-label-sm">Packs / Box</div><div class="stat-val">${card.packsPerBox}</div></div>` : ''}
              ${card.cardsPerPack ? `<div class="stat-cell"><div class="stat-label-sm">Cards / Pack</div><div class="stat-val">${card.cardsPerPack}</div></div>` : ''}
              ${card.totalCards ? `<div class="stat-cell"><div class="stat-label-sm">Total Cards</div><div class="stat-val">${card.totalCards}</div></div>` : ''}
              ${card.msrp ? `<div class="stat-cell"><div class="stat-label-sm">MSRP</div><div class="stat-val">$${card.msrp.toFixed(2)}</div></div>` : ''}
              ${card.upc ? `<div class="stat-cell full"><div class="stat-label-sm">UPC</div><div class="stat-val">${escHtml(card.upc)}</div></div>` : ''}
            </div>
            ${highlightsHtml ? `
            <div class="sealed-highlights">
              <h3 class="section-label">What's Inside</h3>
              <ul class="sealed-highlights-list">${highlightsHtml}</ul>
            </div>` : ''}
            <div class="sealed-links">
              ${ebayUrl ? `
              <a href="${escHtml(ebayUrl)}" target="_blank" rel="noopener" class="btn-ebay-sealed">
                <svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14" aria-hidden="true">
                  <path d="M7 18c-1.1 0-1.99.9-1.99 2S5.9 22 7 22s2-.9 2-2-.9-2-2-2zm10 0c-1.1 0-1.99.9-1.99 2S15.9 22 17 22s2-.9 2-2-.9-2-2-2zm-9.4-5h9.1c.75 0 1.41-.41 1.75-1.03L21 7H5.21l-.94-2H1v2h2l3.6 8.59L5.25 17c-.16.28-.25.61-.25.95C5 19.1 5.9 20 7 20h12v-2H7.42c-.14 0-.25-.11-.25-.25l.03-.12.9-1.63z"/>
                </svg>
                eBay Sales
              </a>` : ''}
              ${card.radishUrl ? `
              <a href="${escHtml(card.radishUrl)}" target="_blank" rel="noopener" class="btn-radish-sealed">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                     width="14" height="14" aria-hidden="true">
                  <polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/>
                  <polyline points="16 7 22 7 22 13"/>
                </svg>
                Radish Guide
              </a>` : ''}
            </div>
            <div class="modal-collection-action">
              <button class="btn-collection-add" data-action="add-to-collection">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                     width="15" height="15" aria-hidden="true">
                  <path d="M12 5v14M5 12h14"/>
                </svg>
                Add to Collection
              </button>
            </div>
          </div>
        </div>`;
    }

    // Treatment banner (only for non-base)
    const treatmentBanner = (treatmentClass !== 'tf-base' && card.treatment)
      ? `<span class="treatment-banner ${treatmentClass}">${escHtml(displayTreatment(card.treatment))}</span>`
      : '';

    // Badges and primary stat display differ by card type
    const modalBadgesHtml = isHero
      ? `<span class="element-badge element-badge-lg" data-element="${escHtml(element)}">${escHtml(element)}</span>
         <span class="set-badge ${setClass}">${escHtml(card.set || 'Unknown')}</span>
         ${treatmentBanner}`
      : isPlay
      ? `<span class="card-type-badge ${card.isBonusPlay ? 'bonus-badge' : 'play-badge'}" style="font-size:0.72rem;padding:4px 10px">${card.isBonusPlay ? 'BONUS PLAY' : 'PLAY CARD'}</span>
         <span class="set-badge ${setClass}">${escHtml(card.set || 'Unknown')}</span>
         ${treatmentBanner}`
      : isHotDog
      ? `<div class="modal-hotdog-header"><svg class="pm-icon" style="color:#7ecb82"><use href="#icon-hotdog"/></svg>HOT DOG CARD</div>
         <span class="set-badge ${setClass}">${escHtml(card.set || 'Unknown')}</span>`
      : `<span class="element-badge element-badge-lg" data-element="${escHtml(element)}">${escHtml(element)}</span>
         <span class="set-badge ${setClass}">${escHtml(card.set || 'Unknown')}</span>
         ${treatmentBanner}`;

    const modalStatHtml = isHero
      ? `<div class="modal-power-display">
           <span class="power-label-txt">POWER</span>
           <span class="power-number">${escHtml(String(card.power))}</span>
         </div>`
      : isPlay
      ? `<div class="modal-cost-display">
           <span class="cost-label-txt">COST</span>
           <span class="cost-number${card.playCost === 0 ? ' free' : ''}">${card.playCost === 0 ? 'FREE' : card.playCost}</span>
           ${card.playCost > 0 ? `<span class="cost-unit">Hot Dog${card.playCost !== 1 ? 's' : ''}</span>` : ''}
         </div>`
      : '';  // HotDog: no cost/power display

    return `
      <div class="modal-layout ${treatmentClass}" data-element="${escHtml(element)}">
        <div class="modal-art">${imgHtml}</div>
        <div class="modal-details">
          <div class="modal-badges">
            ${modalBadgesHtml}
          </div>
          <div>
            <h2 class="modal-card-name" id="modal-card-name">${escHtml(cardDisplayName(card))}</h2>
            <div class="modal-card-number"># ${escHtml(card.cardNumber)}</div>
          </div>
          ${modalStatHtml}
          <div class="modal-stats" aria-label="Card stats">
            ${statCells}
          </div>
          <div class="modal-collection-action">
            <button class="btn-collection-add" data-action="add-to-collection">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M12 5v14M5 12h14"/>
              </svg>
              Add to Collection
            </button>
            <button class="btn-share-card" data-action="share-card"
                    title="Share this card" aria-label="Share card link">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/>
                <polyline points="16 6 12 2 8 6"/>
                <line x1="12" y1="2" x2="12" y2="15"/>
              </svg>
              Share
            </button>
          </div>
          <div class="pricing-section" id="modal-pricing"></div>
          ${buildVersionsSection(card)}
          ${['moderator','admin'].includes(API.getCachedRole()) ? `
          <div class="mod-edit-section">
            <button class="btn-mod-edit" data-action="mod-edit">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="13" height="13" aria-hidden="true">
                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
              </svg>
              Mod: Edit Card Info
            </button>
          </div>` : ''}
        </div>
      </div>`;
  }

  function navigateModal(dir) {
    const next = currentModalIndex + dir;
    if (next < 0 || next >= filteredCards.length) return;
    openModal(filteredCards[next], next);
  }

  modalNavPrev.addEventListener('click', () => navigateModal(-1));
  modalNavNext.addEventListener('click', () => navigateModal(+1));

  modalCloseBtn.addEventListener('click', closeModal);
  modalOverlay.addEventListener('click', (e) => { if (e.target === modalOverlay) closeModal(); });
  document.addEventListener('keydown', (e) => {
    if (modalOverlay.hidden) return;
    if (e.key === 'Escape') { closeModal(); return; }
    if (e.key === 'ArrowLeft')  { navigateModal(-1); return; }
    if (e.key === 'ArrowRight') { navigateModal(+1); return; }
  });

  // Touch swipe navigation inside the modal
  let _touchStartX = 0, _touchStartY = 0;
  modalOverlay.addEventListener('touchstart', (e) => {
    _touchStartX = e.touches[0].clientX;
    _touchStartY = e.touches[0].clientY;
  }, { passive: true });
  modalOverlay.addEventListener('touchend', (e) => {
    const dx = e.changedTouches[0].clientX - _touchStartX;
    const dy = e.changedTouches[0].clientY - _touchStartY;
    // Only navigate on clearly horizontal swipes (dx > 60px, more horizontal than vertical)
    if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) {
      navigateModal(dx < 0 ? +1 : -1);
    }
  }, { passive: true });

  // Fired by collection detail when a variation tile is tapped
  document.addEventListener('open-card-by-number', ({ detail: { cardNumber } }) => {
    const cardSet = cardsByNumber.get(String(cardNumber));
    if (cardSet?.length) openModal(cardSet[0]);
  });

  /* ================================================================
     INITIALIZATION
  ================================================================ */
  async function init() {
    // Collection.init() must run before Auth.init() so its auth-change listener
    // is registered before Auth.init()'s eager session restore dispatches the event.
    Collection.init();
    await Auth.init();

    const params = new URLSearchParams(window.location.search);
    const urlView = params.get('view');
    showView(viewIds.includes(urlView) ? urlView : 'search', true);

    try {
      [cards, searchIndex, categories, aliasIndex] = await Promise.all([
        API.loadCards(),
        API.loadSearchIndex(),
        API.loadCategories(),
        API.loadAliasIndex(),
      ]);
    } catch (err) {
      loadingState.innerHTML = `<p style="color:var(--boba-orange);font-family:var(--font-mono)">
        Failed to load card catalog. Please refresh the page.</p>`;
      console.error('Catalog load error:', err);
      return;
    }

    prepareData();
    Collection.setCardLookup(num => cardsByNumber.get(String(num))?.[0]);
    Collection.setBobaIdLookup(id => cardsByBobaId.get(String(id)) ?? null);
    Collection.setVariantLookup((hero, excludeBobaId) =>
      displayCards.filter(c => c.hero === hero && String(c.bobaId) !== String(excludeBobaId))
    );

    // Apply active image removals from Supabase to the in-memory card data.
    // Fire-and-forget: loads in background and re-renders once done so it
    // doesn't delay the initial paint.
    API.loadActiveImageRemovals().then(removed => {
      if (removed.size) {
        applyImageRemovals(removed);
        applyFilters(true); // re-render grid with nulled imageFiles
      }
    });

    loadingState.hidden = true;
    buildElementFilters();
    buildSetFilter();

    // Apply URL params now that filter UI is fully built (element pills, dropdowns,
    // and categories are all available). This is the single source of truth for
    // restoring filter state on load or popstate navigation.
    applyURLParams(params);

    // Initial render respects any URL filter state.
    applyFilters(true); // skipURLSync — URL is already the source of truth

    // Deep-link: ?card=CBF-656&hero=BoJax opens the card modal directly.
    // fromHistory=true → openModal won't push a new state.
    // replaceState normalizes the URL (in case cardNumber casing differs, etc.).
    if (params.has('card')) {
      const card = cardFromURLParams(params);
      if (card) {
        openModal(card, -1, true);
        history.replaceState(
          { view: currentView, card: card.cardNumber, hero: card.hero },
          '',
          buildCardURL(card)
        );
      }
    }
  }

  // ----------------------------------------------------------------
  // Mod card edit panel
  // ----------------------------------------------------------------

  window.openModEditPanel = openModEditPanel;
  function openModEditPanel(card) {
    // Build a simple overlay dialog for info corrections + image upload
    const existing = document.getElementById('mod-edit-overlay');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'mod-edit-overlay';
    overlay.className = 'mod-edit-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'Edit card info');

    overlay.innerHTML = `
      <div class="mod-edit-panel">
        <div class="mod-edit-header">
          <span class="mod-edit-title">Mod: ${escHtml(card.cardNumber)}</span>
          <button class="mod-edit-close" aria-label="Close">&times;</button>
        </div>
        <div class="mod-edit-body">
          <p class="mod-edit-note">${API.getCachedRole() === 'admin' ? 'Admin edits save immediately.' : 'Fields that differ from current data will be submitted as corrections for admin review.'}</p>
          <div class="mod-edit-fields">
            ${modField('hero',        'Hero',        card.hero        ?? '')}
            ${modField('element',     'Element',     card.element     ?? '')}
            ${modField('variation',   'Variation',   card.variation   ?? '')}
            ${modField('treatment',   'Treatment',   card.treatment   ?? '')}
            ${modField('play_ability','Play Ability', card.playAbility ?? '')}
          </div>
          <div class="mod-edit-image-section">
            <label class="mod-edit-label">Image Action</label>
            <select class="mod-edit-select" id="mod-image-action">
              <option value="none">No change</option>
              <option value="replace">Upload replacement image</option>
              <option value="remove">Flag for removal</option>
            </select>
            <div id="mod-image-upload-row" hidden>
              <input type="file" id="mod-image-file" accept="image/*" class="mod-edit-file-input">
            </div>
          </div>
          <div class="mod-edit-notes-section">
            <label class="mod-edit-label" for="mod-notes">Notes (optional)</label>
            <textarea class="mod-edit-textarea" id="mod-notes" rows="3"
                      placeholder="Explain the correction…"></textarea>
          </div>
          <div id="mod-edit-status" class="mod-edit-status" hidden></div>
        </div>
        <div class="mod-edit-footer">
          <button class="btn-ghost-sm" id="mod-cancel-btn">Cancel</button>
          <button class="btn-primary mod-submit-btn" id="mod-submit-btn">${API.getCachedRole() === 'admin' ? 'Save Changes' : 'Submit Correction'}</button>
        </div>
      </div>`;

    document.body.appendChild(overlay);

    // Toggle file input row
    overlay.querySelector('#mod-image-action').addEventListener('change', e => {
      overlay.querySelector('#mod-image-upload-row').hidden = e.target.value !== 'replace';
    });

    overlay.querySelector('.mod-edit-close').addEventListener('click', () => overlay.remove());
    overlay.querySelector('#mod-cancel-btn').addEventListener('click', () => overlay.remove());
    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });

    overlay.querySelector('#mod-submit-btn').addEventListener('click', async () => {
      const submitBtn = overlay.querySelector('#mod-submit-btn');
      const statusEl  = overlay.querySelector('#mod-edit-status');
      submitBtn.disabled = true;
      submitBtn.textContent = 'Submitting…';

      const origValues = {
        hero:         card.hero        ?? '',
        element:      card.element     ?? '',
        variation:    card.variation   ?? '',
        treatment:    card.treatment   ?? '',
        play_ability: card.playAbility ?? '',
      };

      const corrections = {};
      overlay.querySelectorAll('.mod-field-input').forEach(input => {
        const key = input.dataset.field;
        const val = input.value.trim();
        if (val !== origValues[key]) corrections[key] = val;
      });

      const imageAction = overlay.querySelector('#mod-image-action').value;
      const imageFile   = overlay.querySelector('#mod-image-file')?.files?.[0];
      const notes       = overlay.querySelector('#mod-notes').value.trim() || null;

      const isAdmin = API.getCachedRole() === 'admin';
      const correctionStatus = isAdmin ? 'approved' : 'pending';

      try {
        if (Object.keys(corrections).length > 0) {
          await API.submitCardCorrection(card.cardNumber, corrections, notes, correctionStatus, {
            bobaId:    card.bobaId    ?? null,
            hero:      card.hero      ?? null,
            element:   card.element   ?? null,
            power:     card.power     ?? null,
            treatment: card.treatment ?? null,
          });
        }
        if (imageAction !== 'none') {
          let storagePath = null;
          if (imageAction === 'replace' && imageFile) {
            storagePath = await API.uploadModImage(card.cardNumber, imageFile);
          }
          await API.submitImageOverride(card.cardNumber, imageAction, storagePath, correctionStatus, card.bobaId ?? null);
          // Apply the removal immediately to in-memory card objects so the grid
          // reflects the change without a page reload.
          if (imageAction === 'remove') {
            applyImageRemovals(new Set([String(card.cardNumber)]));
          }
        }
        statusEl.hidden = false;
        statusEl.className = 'mod-edit-status success';
        statusEl.textContent = isAdmin ? 'Changes saved.' : 'Correction submitted for review. Thank you!';
        submitBtn.textContent = 'Saved ✓';
        setTimeout(() => overlay.remove(), 2000);
      } catch (err) {
        statusEl.hidden = false;
        statusEl.className = 'mod-edit-status error';
        statusEl.textContent = err.message || 'Submission failed.';
        submitBtn.disabled = false;
        submitBtn.textContent = 'Submit Correction';
      }
    });
  }

  function modField(key, label, currentValue) {
    return `
      <div class="mod-edit-row">
        <label class="mod-edit-label" for="mod-field-${key}">${escHtml(label)}</label>
        <input class="mod-edit-input mod-field-input"
               id="mod-field-${key}"
               data-field="${key}"
               type="text"
               value="${escHtml(currentValue)}">
      </div>`;
  }

  // ----------------------------------------------------------------
  // Discord Trade Room UI
  // ----------------------------------------------------------------

  (function initDiscordUI() {
    const fab        = document.getElementById('discord-fab');
    const badge      = document.getElementById('discord-fab-badge');
    const panel      = document.getElementById('discord-panel');
    const content    = document.getElementById('discord-content');
    const userChip   = document.getElementById('discord-user-chip');
    const closeBtn   = document.getElementById('discord-close-btn');
    const emojiPicker = document.getElementById('discord-emoji-picker');

    if (!fab || !panel || !content) return;

    // ── Emoji data ────────────────────────────────────────────────
    const EMOJI_CATS = [
      { id: 'quick',      icon: '🕐', emoji: ['👍','❤️','🔥','😂','😮','😢','🎉','💯','🙏','👀','💪','✅'] },
      { id: 'smileys',    icon: '😀', emoji: ['😀','😃','😄','😁','😆','😅','🤣','😂','🙂','😊','😍','😘','😎','🥳','😏','😒','😢','😭','😤','😡','🤯','😳','😱','🤗','🤔','😶','🙄','😮','😲','🥱','😴','🤐','🤢','🤮','😷','🤕','🤑','😈','👿','👻','💀'] },
      { id: 'people',     icon: '👋', emoji: ['👋','🤚','✋','👌','✌️','🤞','👈','👉','👆','👇','👍','👎','✊','👏','🙌','🙏','💪','👀','🗣️','👤'] },
      { id: 'animals',    icon: '🐶', emoji: ['🐶','🐱','🐭','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐸','🐵','🐔','🐧','🦅','🦋','🐝','🐢','🦈','🐋','🦓','🐘','🦒','🦁','🐺'] },
      { id: 'food',       icon: '🍕', emoji: ['🍕','🍔','🍟','🌭','🍿','🥗','🍜','🍣','🌮','🌯','🧁','🍰','🎂','🍩','🍪','🍫','🍬','🍭','🍦','☕','🍺','🍻','🥂','🍾'] },
      { id: 'activities', icon: '⚽', emoji: ['⚽','🏀','🏈','⚾','🎾','🏐','🎱','🏓','🥊','🎮','🕹️','🎲','🎯','🎳','🏆','🥇','🥈','🥉','🎖️','🏅'] },
      { id: 'objects',    icon: '💎', emoji: ['💎','💰','💵','💳','🔑','🔒','📱','💻','📷','🎵','🎶','📚','📖','✏️','📝','💡','🔦','💊','🔬','🔭','🪄','🎩','👑','💍'] },
      { id: 'symbols',    icon: '❤️', emoji: ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','💔','💕','💖','✨','⭐','🌟','🔥','💥','❄️','🌈','☀️','🌙','✅','❌','⭕','❗','❓','💯','🔄','⬆️','⬇️','⬅️','➡️'] },
    ];

    let _emojiCatId  = 'quick';
    let _emojiTarget = null; // messageId
    let _replyTo     = null; // {id, authorName}
    let _atBottom    = true;
    let _msgList     = null;

    // ── Render loop ───────────────────────────────────────────────
    Discord.setUpdateCallback(render);

    function render() {
      const state = Discord.getState();

      fab.hidden = true; // temporarily hidden — Discord bot not yet added to server
      const uc = state.unreadCount;
      if (uc > 0) {
        badge.hidden = false;
        badge.textContent = uc > 99 ? '99+' : String(uc);
      } else {
        badge.hidden = true;
      }

      // User chip in header
      if (state.currentUser) {
        const av = Discord.avatarUrl(state.currentUser, 44);
        const dn = Discord.displayName(state.currentUser);
        userChip.hidden = false;
        userChip.innerHTML = av
          ? `<img src="${escHtml(av)}" alt="${escHtml(dn)}"><span>${escHtml(dn)}</span>`
          : `<span>${escHtml(dn)}</span>`;
      } else {
        userChip.hidden = true;
        userChip.innerHTML = '';
      }

      // Content area
      if (!state.isAuthorized) {
        renderConnectView();
      } else if (!state.isMember) {
        renderInviteView();
      } else {
        renderChannelView(state);
      }
    }

    // ── Connect view ───────────────────────────────────────────────
    function renderConnectView() {
      content.innerHTML = `
        <div class="discord-gate">
          <div class="discord-gate-icon"><svg viewBox="0 0 24 24" fill="currentColor" width="52" height="52" style="color:#5865F2"><path d="M20.317 4.492c-1.53-.69-3.17-1.2-4.885-1.49a.075.075 0 0 0-.079.036c-.21.369-.444.85-.608 1.23a18.566 18.566 0 0 0-5.487 0 12.36 12.36 0 0 0-.617-1.23A.077.077 0 0 0 8.562 3c-1.714.29-3.354.8-4.885 1.491a.07.07 0 0 0-.032.027C.533 9.093-.32 13.555.099 17.961a.08.08 0 0 0 .031.055 20.03 20.03 0 0 0 5.993 2.98.078.078 0 0 0 .084-.026c.462-.62.874-1.275 1.226-1.963a.076.076 0 0 0-.041-.106 13.201 13.201 0 0 1-1.872-.878.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.763 8.18 1.763 12.061 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.879.077.077 0 0 0-.041.107c.36.687.772 1.341 1.225 1.962a.077.077 0 0 0 .084.028 19.963 19.963 0 0 0 6.002-2.981.076.076 0 0 0 .032-.054c.5-5.094-.838-9.52-3.549-13.442a.06.06 0 0 0-.031-.028z"/></svg></div>
          <h2>BOBA Trade Room</h2>
          <p>Connect your Discord account to chat<br>with the BOBA community.</p>
          <button class="discord-gate-btn blurple" id="dc-connect-btn">
            <svg viewBox="0 0 24 24" fill="currentColor" width="16" height="16"><path d="M20.317 4.492c-1.53-.69-3.17-1.2-4.885-1.49a.075.075 0 0 0-.079.036c-.21.369-.444.85-.608 1.23a18.566 18.566 0 0 0-5.487 0 12.36 12.36 0 0 0-.617-1.23A.077.077 0 0 0 8.562 3c-1.714.29-3.354.8-4.885 1.491a.07.07 0 0 0-.032.027C.533 9.093-.32 13.555.099 17.961a.08.08 0 0 0 .031.055 20.03 20.03 0 0 0 5.993 2.98.078.078 0 0 0 .084-.026c.462-.62.874-1.275 1.226-1.963a.076.076 0 0 0-.041-.106 13.201 13.201 0 0 1-1.872-.878.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.763 8.18 1.763 12.061 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.879.077.077 0 0 0-.041.107c.36.687.772 1.341 1.225 1.962a.077.077 0 0 0 .084.028 19.963 19.963 0 0 0 6.002-2.981.076.076 0 0 0 .032-.054c.5-5.094-.838-9.52-3.549-13.442a.06.06 0 0 0-.031-.028z"/></svg>
            Connect Discord
          </button>
        </div>`;
      document.getElementById('dc-connect-btn')?.addEventListener('click', async () => {
        await Discord.authorize();
        if (Discord.getState().isMember) {
          await Discord.loadInitialMessages();
          Discord.startPolling();
          Discord.markRead();
        }
      });
    }

    // ── Invite view ───────────────────────────────────────────────
    function renderInviteView() {
      content.innerHTML = `
        <div class="discord-gate">
          <div class="discord-gate-icon">🎮</div>
          <h2>Join the BOBA Discord</h2>
          <p>You need to be a server member to<br>access the trade room.</p>
          <a class="discord-gate-btn green"
             href="https://discord.gg/${Discord.INVITE_CODE}"
             target="_blank" rel="noopener noreferrer">
            ↗ Join Server
          </a>
          <button class="discord-gate-secondary" id="dc-recheck-btn">I've joined — check again</button>
          <button class="discord-gate-disconnect" id="dc-disc-btn">Use a different account</button>
        </div>`;
      document.getElementById('dc-recheck-btn')?.addEventListener('click', async () => {
        await Discord.checkMembership();
        if (Discord.getState().isMember) {
          await Discord.loadInitialMessages();
          Discord.startPolling();
          Discord.markRead();
        }
      });
      document.getElementById('dc-disc-btn')?.addEventListener('click', () => Discord.disconnect());
    }

    // ── Channel view ──────────────────────────────────────────────
    function renderChannelView(state) {
      // Build structure if not already present
      if (!content.querySelector('.discord-msg-list')) {
        content.innerHTML = `
          <div class="discord-msg-list" id="dc-msg-list"></div>
          <div class="discord-reply-indicator" id="dc-reply-indicator" hidden>
            <svg viewBox="0 0 24 24" fill="currentColor" width="12" height="12" style="flex-shrink:0;color:#5865F2"><path d="M9.195 18.44c1.25.714 2.805-.189 2.805-1.629v-2.34c2.032.053 4.036.521 5.58 1.414 1.25.714 2.805-.189 2.805-1.629V8.5c0-1.44-1.555-2.343-2.805-1.629C15.78 7.864 13.887 8.333 12 8.425V6.128c0-1.44-1.555-2.343-2.805-1.629l-7.108 4.062c-1.26.72-1.26 2.536 0 3.256l7.108 4.062z"/></svg>
            Replying to <span class="ri-name" id="dc-reply-name"></span>
            <button class="ri-close" id="dc-reply-cancel">×</button>
          </div>
          <div class="discord-input-bar">
            <textarea class="discord-input" id="dc-input" placeholder="Message #trade-room" rows="1"></textarea>
            <button class="discord-send-btn" id="dc-send-btn" disabled>
              <svg viewBox="0 0 24 24" fill="currentColor" width="18" height="18"><path d="m3.478 2.405-1.142 5.143c-.32 1.44.793 2.73 2.257 2.73l3.405-.001L5.59 21.1c-.334 1.498 1.394 2.576 2.636 1.637L21.368 12.5c1.12-.835 1.003-2.536-.22-3.213L5.104 2.09c-1.27-.697-2.813.237-2.625 1.597l-.001.718z"/></svg>
            </button>
          </div>`;

        _msgList = document.getElementById('dc-msg-list');

        // Input events
        const input   = document.getElementById('dc-input');
        const sendBtn = document.getElementById('dc-send-btn');
        input.addEventListener('input', () => {
          sendBtn.disabled = !input.value.trim();
          sendBtn.classList.toggle('active', !!input.value.trim());
          // Auto-grow
          input.style.height = 'auto';
          input.style.height = Math.min(input.scrollHeight, 120) + 'px';
        });
        input.addEventListener('keydown', e => {
          if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submitMessage(); }
        });
        sendBtn.addEventListener('click', submitMessage);

        // Reply cancel
        document.getElementById('dc-reply-cancel')?.addEventListener('click', () => {
          _replyTo = null;
          document.getElementById('dc-reply-indicator').hidden = true;
        });

        // Scroll tracking
        _msgList.addEventListener('scroll', () => {
          const el = _msgList;
          _atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 60;
        });
      } else {
        _msgList = document.getElementById('dc-msg-list');
      }

      // Render messages
      renderMessages(state.messages, state.hasMore);

      // Scroll to bottom on first load or if already at bottom
      if (_atBottom) {
        requestAnimationFrame(() => {
          if (_msgList) _msgList.scrollTop = _msgList.scrollHeight;
        });
      }
    }

    function renderMessages(messages, hasMore) {
      if (!_msgList) return;
      const prevScrollH = _msgList.scrollHeight;
      const prevScrollT = _msgList.scrollTop;

      _msgList.innerHTML = '';

      // History header
      if (hasMore) {
        const btn = document.createElement('button');
        btn.className = 'discord-load-more';
        btn.textContent = 'Load older messages';
        btn.addEventListener('click', async () => {
          btn.textContent = 'Loading…';
          btn.disabled = true;
          await Discord.loadOlderMessages();
          // Restore scroll position after prepend
          if (_msgList) {
            _msgList.scrollTop = _msgList.scrollHeight - prevScrollH + prevScrollT;
          }
        });
        _msgList.appendChild(btn);
      } else {
        const div = document.createElement('div');
        div.className = 'discord-beginning';
        div.textContent = 'This is the beginning of #trade-room.';
        _msgList.appendChild(div);
      }

      messages.forEach((msg, idx) => {
        const prev    = idx > 0 ? messages[idx - 1] : null;
        const compact = isCompact(msg, prev);
        _msgList.appendChild(buildMessageEl(msg, compact));
      });

      // Bottom anchor
      const anchor = document.createElement('div');
      anchor.id = 'dc-bottom';
      _msgList.appendChild(anchor);
    }

    // ── Message element builder ────────────────────────────────────
    function buildMessageEl(msg, compact) {
      const el    = document.createElement('div');
      el.className = `discord-msg${compact ? ' compact' : ''}`;
      el.dataset.msgId = msg.id;

      const authorName = Discord.displayName(msg.author);
      const avatarUrl  = Discord.avatarUrl(msg.author, 64);
      const colorClass = authorColorClass(msg.author.id);

      let html = '';

      // Avatar column
      if (compact) {
        html += `<div class="discord-msg-avatar-spacer"></div>`;
      } else {
        html += `<div class="discord-msg-avatar">`;
        html += avatarUrl
          ? `<img src="${escHtml(avatarUrl)}" alt="${escHtml(authorName)}" loading="lazy">`
          : `<div class="discord-avatar-fallback ${colorClass}">${escHtml(authorName.charAt(0).toUpperCase())}</div>`;
        html += `</div>`;
      }

      html += `<div class="discord-msg-body">`;

      // Reply bar
      if (msg.type === 19 && msg.referenced_message) {
        const ref = msg.referenced_message;
        const refName = Discord.displayName(ref.author);
        html += `<div class="discord-reply-bar">
          <svg viewBox="0 0 24 24" fill="currentColor" width="10" height="10" style="flex-shrink:0;opacity:0.5"><path d="M9.195 18.44c1.25.714 2.805-.189 2.805-1.629v-2.34c2.032.053 4.036.521 5.58 1.414 1.25.714 2.805-.189 2.805-1.629V8.5c0-1.44-1.555-2.343-2.805-1.629C15.78 7.864 13.887 8.333 12 8.425V6.128c0-1.44-1.555-2.343-2.805-1.629l-7.108 4.062c-1.26.72-1.26 2.536 0 3.256l7.108 4.062z"/></svg>
          <span class="reply-author ${authorColorClass(ref.author.id)}">${escHtml(refName)}</span>
          <span>${escHtml(ref.content ? ref.content.slice(0, 80) : '[attachment]')}</span>
        </div>`;
      }

      // Author + timestamp
      if (!compact) {
        const ts = msg.timestamp ? formatTs(new Date(msg.timestamp)) : '';
        html += `<div class="discord-msg-meta">
          <span class="discord-msg-author ${colorClass}">${escHtml(authorName)}</span>
          <span class="discord-msg-ts">${escHtml(ts)}</span>
        </div>`;
      }

      // Content
      if (msg.content) {
        html += `<div class="discord-msg-content">${renderMarkdown(msg.content)}</div>`;
      }

      // Attachments
      if (Array.isArray(msg.attachments)) {
        msg.attachments.forEach(att => {
          const ct = att.content_type ?? '';
          if (ct.startsWith('image/') || /\.(png|jpg|jpeg|gif|webp)$/i.test(att.filename)) {
            html += `<div class="discord-attachment"><img src="${escHtml(att.proxy_url ?? att.url)}" alt="${escHtml(att.filename)}" loading="lazy"></div>`;
          }
        });
      }

      // Reactions
      if (Array.isArray(msg.reactions) && msg.reactions.length) {
        html += `<div class="discord-reactions">`;
        msg.reactions.forEach(r => {
          const disp  = r.emoji.name ?? r.emoji.id ?? '?';
          const meClass = r.me ? ' me' : '';
          html += `<button class="discord-reaction${meClass}" data-emoji="${escHtml(disp)}">
            <span class="discord-reaction-emoji">${escHtml(disp)}</span>
            <span class="discord-reaction-count">${r.count}</span>
          </button>`;
        });
        html += `<button class="discord-add-reaction" title="Add reaction">☺</button>`;
        html += `</div>`;
      }

      html += `</div>`;
      el.innerHTML = html;

      // Context menu — reply on long-press / right-click
      el.addEventListener('contextmenu', e => {
        e.preventDefault();
        setReply(msg);
      });

      // Reaction click handlers
      el.querySelectorAll('.discord-reaction').forEach(btn => {
        btn.addEventListener('click', () => {
          const emoji = btn.dataset.emoji;
          if (btn.classList.contains('me')) Discord.removeReaction(msg.id, emoji);
          else                               Discord.addReaction(msg.id, emoji);
        });
      });
      el.querySelector('.discord-add-reaction')?.addEventListener('click', e => {
        showEmojiPicker(msg.id, e.currentTarget);
      });

      return el;
    }

    // ── Send ──────────────────────────────────────────────────────
    function submitMessage() {
      const input = document.getElementById('dc-input');
      if (!input) return;
      const text = input.value.trim();
      if (!text) return;
      const replyId = _replyTo?.id ?? null;
      input.value = '';
      input.style.height = 'auto';
      const sendBtn = document.getElementById('dc-send-btn');
      if (sendBtn) { sendBtn.disabled = true; sendBtn.classList.remove('active'); }
      _replyTo = null;
      const ri = document.getElementById('dc-reply-indicator');
      if (ri) ri.hidden = true;
      _atBottom = true;
      Discord.send(text, replyId);
    }

    // ── Reply ─────────────────────────────────────────────────────
    function setReply(msg) {
      _replyTo = { id: msg.id, authorName: Discord.displayName(msg.author) };
      const ri   = document.getElementById('dc-reply-indicator');
      const name = document.getElementById('dc-reply-name');
      if (ri) ri.hidden = false;
      if (name) name.textContent = _replyTo.authorName;
      document.getElementById('dc-input')?.focus();
    }

    // ── Emoji picker ──────────────────────────────────────────────
    function buildEmojiPicker() {
      const cats = document.getElementById('dep-categories');
      const grid = document.getElementById('dep-grid');
      if (!cats || !grid) return;

      // Category tabs
      cats.innerHTML = EMOJI_CATS.map(c =>
        `<button class="dep-cat-btn${c.id === _emojiCatId ? ' active' : ''}" data-cat="${c.id}" title="${c.id}">${c.icon}</button>`
      ).join('');
      cats.querySelectorAll('.dep-cat-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          _emojiCatId = btn.dataset.cat;
          buildEmojiPicker();
        });
      });

      // Search filter
      const search = document.getElementById('dep-search');
      const query  = search?.value.trim() ?? '';
      const pool   = query
        ? EMOJI_CATS.flatMap(c => c.emoji)
        : (EMOJI_CATS.find(c => c.id === _emojiCatId)?.emoji ?? []);

      grid.innerHTML = pool.map(e =>
        `<button class="dep-emoji-btn" data-emoji="${e}">${e}</button>`
      ).join('');
      grid.querySelectorAll('.dep-emoji-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          if (_emojiTarget) Discord.addReaction(_emojiTarget, btn.dataset.emoji);
          hideEmojiPicker();
        });
      });
    }

    function showEmojiPicker(msgId, anchor) {
      _emojiTarget = msgId;
      emojiPicker.hidden = false;
      buildEmojiPicker();

      // Position near the anchor
      const rect = anchor.getBoundingClientRect();
      const ph   = emojiPicker.offsetHeight || 360;
      const pw   = emojiPicker.offsetWidth  || 320;
      let top  = rect.top - ph - 8;
      let left = rect.left - pw / 2;
      if (top < 8) top = rect.bottom + 8;
      left = Math.max(8, Math.min(left, window.innerWidth - pw - 8));
      emojiPicker.style.top  = top + 'px';
      emojiPicker.style.left = left + 'px';

      // Search input
      const search = document.getElementById('dep-search');
      if (search) {
        search.value = '';
        search.oninput = () => buildEmojiPicker();
      }
    }

    function hideEmojiPicker() {
      emojiPicker.hidden = true;
      _emojiTarget = null;
    }

    // Close picker on outside click
    document.addEventListener('click', e => {
      if (!emojiPicker.hidden && !emojiPicker.contains(e.target)) hideEmojiPicker();
    });

    // ── Panel open / close ────────────────────────────────────────
    fab.addEventListener('click', async () => {
      panel.hidden = false;
      Discord.markRead();
      const state = Discord.getState();
      if (state.isAuthorized && state.isMember && state.messages.length === 0) {
        await Discord.loadInitialMessages();
        Discord.startPolling();
        Discord.markRead();
      }
      render();
    });

    closeBtn.addEventListener('click', () => {
      panel.hidden = true;
      Discord.stopPolling();
      Discord.markRead();
      hideEmojiPicker();
    });

    // Close panel on backdrop click
    panel.addEventListener('click', e => {
      if (e.target === panel) {
        panel.hidden = true;
        Discord.stopPolling();
        Discord.markRead();
      }
    });

    // ── Helpers ───────────────────────────────────────────────────
    function authorColorClass(userId) {
      const palette = ['dc-color-0','dc-color-1','dc-color-2','dc-color-3',
                       'dc-color-4','dc-color-5','dc-color-6','dc-color-7','dc-color-8'];
      // Simple hash
      let hash = 0;
      for (let i = 0; i < userId.length; i++) hash = (hash * 31 + userId.charCodeAt(i)) >>> 0;
      return palette[hash % palette.length];
    }

    function isCompact(msg, prev) {
      if (!prev) return false;
      if (msg.author.id !== prev.author.id) return false;
      const d1 = new Date(msg.timestamp);
      const d2 = new Date(prev.timestamp);
      return Math.abs(d1 - d2) < 7 * 60 * 1000;
    }

    function formatTs(date) {
      const now  = new Date();
      const sameDay = date.toDateString() === now.toDateString();
      const yesterday = new Date(now); yesterday.setDate(yesterday.getDate() - 1);
      const wasYesterday = date.toDateString() === yesterday.toDateString();
      const time = date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
      if (sameDay)      return `Today at ${time}`;
      if (wasYesterday) return `Yesterday at ${time}`;
      return date.toLocaleDateString([], { month: '2-digit', day: '2-digit', year: 'numeric' });
    }

    function renderMarkdown(text) {
      let s = escHtml(text);
      s = s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
      s = s.replace(/\*(.+?)\*/g,     '<em>$1</em>');
      s = s.replace(/_(.+?)_/g,       '<em>$1</em>');
      s = s.replace(/~~(.+?)~~/g,     '<del>$1</del>');
      s = s.replace(/`(.+?)`/g,       '<code>$1</code>');
      s = s.replace(/\|\|(.+?)\|\|/g, '▓▓▓');
      return s;
    }

    // Start Discord (restore session if tokens exist)
    Discord.init();
  })();

  init();
})();
