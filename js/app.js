/**
 * BOBA Playbook — Main Application
 *
 * M1: Search Mode — browse, search, and filter 17,793 BOBA cards.
 *
 * Architecture:
 *  - Single IIFE, plain JS, no framework
 *  - $('id') shorthand for getElementById
 *  - All data loading through API (js/api.js)
 *  - DOM updates use textContent or innerHTML with escHtml()
 *  - Card grid uses pagination (PAGE_SIZE cards at a time) + IntersectionObserver
 *  - Search uses pre-built tokenIndex from search-index.json (prefix matching)
 *  - Filters use byElement / bySet / byTreatment indexes
 *
 * See CLAUDE.md for full conventions.
 */

(function () {
  'use strict';

  /* ================================================================
     CONSTANTS
  ================================================================ */
  const PAGE_SIZE    = 60; // cards rendered per batch
  const SEARCH_DEBOUNCE_MS = 280;

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

  /* ================================================================
     STATE
  ================================================================ */
  let cards         = [];   // full catalog (17,793 items)
  let searchIndex   = null; // { tokenIndex, byElement, bySet, byTreatment, hasImage, ... }
  let categories    = null; // { sets: { ... }, ... }

  let filteredCards = [];   // result of current search + filters
  let displayedCount = 0;   // how many card elements are in the DOM

  const filters = {
    query:     '',
    element:   '',
    set:       '',
    treatment: '',
    hasImage:  false,
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
  const hasImageToggle  = $('has-image-toggle');
  const loadSentinel    = $('load-sentinel');
  const clearFiltersBtn = $('clear-filters-btn');

  const modalOverlay  = $('card-modal-overlay');
  const modalContent  = $('modal-content');
  const modalCloseBtn = $('modal-close-btn');

  const sidebarToggle  = $('sidebar-toggle');
  const sidebar        = $('channels-sidebar');
  const sidebarOverlay = $('sidebar-overlay');

  /* ================================================================
     SIDEBAR (mobile)
  ================================================================ */
  function openSidebar() {
    sidebar.classList.add('open');
    sidebarOverlay.classList.add('visible');
    sidebarToggle.setAttribute('aria-expanded', 'true');
  }
  function closeSidebar() {
    sidebar.classList.remove('open');
    sidebarOverlay.classList.remove('visible');
    sidebarToggle.setAttribute('aria-expanded', 'false');
  }

  sidebarToggle.addEventListener('click', openSidebar);
  sidebarOverlay.addEventListener('click', closeSidebar);

  /* ================================================================
     VIEW SYSTEM
  ================================================================ */
  const viewIds = ['search', 'rules', 'collection', 'profile'];
  const navBtnIds = {
    search:     'nav-search-btn',
    rules:      'nav-rules-btn',
    collection: 'nav-collection-btn',
    profile:    'nav-profile-btn',
  };

  function showView(name, fromHistory = false) {
    viewIds.forEach(id => {
      const el = $(`view-${id}`);
      if (el) el.hidden = id !== name;
    });

    Object.entries(navBtnIds).forEach(([id, btnId]) => {
      const btn = $(btnId);
      if (!btn) return;
      const isActive = id === name;
      btn.classList.toggle('active', isActive);
      btn.setAttribute('aria-current', isActive ? 'page' : 'false');
    });

    closeSidebar();

    if (!fromHistory) {
      const url = name === 'search' ? '?' : `?view=${name}`;
      history.pushState({ view: name }, '', url);
    }
  }

  Object.entries(navBtnIds).forEach(([viewName, btnId]) => {
    const btn = $(btnId);
    if (btn) btn.addEventListener('click', () => showView(viewName));
  });

  window.addEventListener('popstate', (e) => {
    const view = e.state?.view || 'search';
    showView(view, true);
  });

  /* ================================================================
     SEARCH LOGIC
  ================================================================ */

  /**
   * Build the result set for current query + filters.
   * Returns array of card objects.
   */
  function computeResults() {
    let resultSet = null; // null = "all cards"

    // --- Text search ---
    const q = filters.query.trim().toLowerCase();
    if (q) {
      const tokens = q.split(/\s+/).filter(Boolean);
      for (const token of tokens) {
        const tokenMatches = new Set();
        // Prefix match: find all tokenIndex keys that start with this token
        for (const key in searchIndex.tokenIndex) {
          if (key.startsWith(token)) {
            for (const idx of searchIndex.tokenIndex[key]) {
              tokenMatches.add(+idx);
            }
          }
        }
        resultSet = resultSet === null
          ? tokenMatches
          : new Set([...resultSet].filter(i => tokenMatches.has(i)));
      }
      // If query tokens produced no matches, return empty
      if (resultSet !== null && resultSet.size === 0) return [];
    }

    // --- Element filter ---
    if (filters.element) {
      const elSet = new Set((searchIndex.byElement[filters.element] || []).map(Number));
      resultSet = resultSet === null ? elSet : intersect(resultSet, elSet);
    }

    // --- Set filter ---
    if (filters.set) {
      const setSet = new Set((searchIndex.bySet[filters.set] || []).map(Number));
      resultSet = resultSet === null ? setSet : intersect(resultSet, setSet);
    }

    // --- Treatment filter ---
    if (filters.treatment) {
      const txSet = new Set((searchIndex.byTreatment[filters.treatment] || []).map(Number));
      resultSet = resultSet === null ? txSet : intersect(resultSet, txSet);
    }

    // --- Has image filter ---
    if (filters.hasImage) {
      const imgSet = new Set((searchIndex.hasImage || []).map(Number));
      resultSet = resultSet === null ? imgSet : intersect(resultSet, imgSet);
    }

    // All filters cleared — return full catalog
    if (resultSet === null) return cards;

    return [...resultSet].map(i => cards[i]).filter(Boolean);
  }

  function intersect(setA, setB) {
    return new Set([...setA].filter(i => setB.has(i)));
  }

  /* ================================================================
     FILTER UI
  ================================================================ */

  /** Build element filter pills from searchIndex.byElement keys */
  function buildElementFilters() {
    const elements = Object.keys(searchIndex.byElement).sort();

    // "All" pill
    const allPill = makePill('', 'All');
    allPill.classList.add('active');
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
    // Update pill states
    elementFilters.querySelectorAll('.element-pill').forEach(pill => {
      const isActive = pill.dataset.element === element;
      pill.classList.toggle('active', isActive);
      pill.setAttribute('aria-pressed', isActive ? 'true' : 'false');
    });
    applyFilters();
  }

  /** Populate set dropdown from categories.json */
  function buildSetFilter() {
    const sets = Object.keys(categories.sets || {}).sort();
    for (const set of sets) {
      const opt = document.createElement('option');
      opt.value = set;
      const count = categories.sets[set]?.count || '';
      opt.textContent = count ? `${set} (${count.toLocaleString()})` : set;
      setFilter.appendChild(opt);
    }
  }

  /** Populate treatment dropdown — all unique treatments across all sets */
  function buildTreatmentFilter() {
    const all = new Set();
    for (const setData of Object.values(categories.sets || {})) {
      for (const t of setData.treatments || []) all.add(t);
    }
    const sorted = [...all].sort();
    for (const t of sorted) {
      const opt = document.createElement('option');
      opt.value = t;
      opt.textContent = t;
      treatmentFilter.appendChild(opt);
    }
  }

  /** When set changes, narrow treatment options to that set's treatments */
  function updateTreatmentOptions(selectedSet) {
    const currentTreatment = treatmentFilter.value;
    // Clear all except "All Treatments"
    while (treatmentFilter.options.length > 1) treatmentFilter.remove(1);

    const treatments = selectedSet
      ? (categories.sets[selectedSet]?.treatments || []).sort()
      : [...new Set(Object.values(categories.sets || {})
          .flatMap(s => s.treatments || []))].sort();

    for (const t of treatments) {
      const opt = document.createElement('option');
      opt.value = t;
      opt.textContent = t;
      treatmentFilter.appendChild(opt);
    }

    // Restore selection if still valid
    if ([...treatmentFilter.options].some(o => o.value === currentTreatment)) {
      treatmentFilter.value = currentTreatment;
    } else {
      treatmentFilter.value = '';
      filters.treatment = '';
    }
  }

  setFilter.addEventListener('change', () => {
    filters.set = setFilter.value;
    updateTreatmentOptions(filters.set);
    applyFilters();
  });

  treatmentFilter.addEventListener('change', () => {
    filters.treatment = treatmentFilter.value;
    applyFilters();
  });

  hasImageToggle.addEventListener('click', () => {
    filters.hasImage = !filters.hasImage;
    hasImageToggle.setAttribute('aria-pressed', filters.hasImage ? 'true' : 'false');
    applyFilters();
  });

  clearFiltersBtn?.addEventListener('click', resetFilters);

  function resetFilters() {
    filters.query = '';
    filters.element = '';
    filters.set = '';
    filters.treatment = '';
    filters.hasImage = false;

    searchInput.value = '';
    searchClear.hidden = true;
    setFilter.value = '';
    treatmentFilter.value = '';
    updateTreatmentOptions('');
    hasImageToggle.setAttribute('aria-pressed', 'false');
    setElementFilter('');
  }

  /* ================================================================
     CARD GRID RENDERING
  ================================================================ */

  function applyFilters() {
    filteredCards = computeResults();
    displayedCount = 0;
    cardGrid.innerHTML = '';
    renderNextPage();
    updateResultsCount();
  }

  function renderNextPage() {
    const end = Math.min(displayedCount + PAGE_SIZE, filteredCards.length);
    const fragment = document.createDocumentFragment();

    for (let i = displayedCount; i < end; i++) {
      fragment.appendChild(buildCardElement(filteredCards[i]));
    }

    cardGrid.appendChild(fragment);
    displayedCount = end;

    const isEmpty = filteredCards.length === 0;
    cardGrid.hidden = isEmpty;
    emptyState.hidden = !isEmpty;
  }

  function buildCardElement(card) {
    const el = document.createElement('article');
    el.className = 'card-item';
    el.setAttribute('role', 'listitem');
    el.dataset.element = card.element || 'NONE';
    el.setAttribute('tabindex', '0');
    el.setAttribute('aria-label', `${card.name}, ${card.element || 'No element'}, Power ${card.power}`);

    const imgHtml = card.imageAvailable && card.imageFile
      ? `<img class="card-img" src="${escHtml(API.thumbUrl(card.imageFile))}"
              alt="${escHtml(card.name)}" loading="lazy" decoding="async">`
      : `<div class="card-img-placeholder" data-element="${escHtml(card.element || 'NONE')}"
              aria-hidden="true">${escHtml(card.element || '?')}</div>`;

    el.innerHTML = `
      <div class="card-img-wrap">${imgHtml}</div>
      <div class="card-info">
        <div class="card-number">${escHtml(card.cardNumber)}</div>
        <div class="card-name">${escHtml(card.name)}</div>
        <div class="card-meta">
          <span class="element-badge" data-element="${escHtml(card.element || 'NONE')}"
                aria-label="Element: ${escHtml(card.element || 'None')}">${escHtml(card.element || 'NONE')}</span>
          <span class="card-power" aria-label="Power ${card.power}">P${escHtml(String(card.power))}</span>
        </div>
      </div>`;

    el.addEventListener('click', () => openModal(card));
    el.addEventListener('keydown', e => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openModal(card); }
    });

    return el;
  }

  function updateResultsCount() {
    const total = filteredCards.length;
    const hasActiveFilter = filters.query || filters.element || filters.set || filters.treatment || filters.hasImage;
    if (hasActiveFilter) {
      searchCount.textContent = `${total.toLocaleString()} card${total !== 1 ? 's' : ''}`;
    } else {
      searchCount.textContent = `${total.toLocaleString()} cards`;
    }
  }

  /* ================================================================
     LOAD MORE (IntersectionObserver on sentinel)
  ================================================================ */
  const sentinelObserver = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting && displayedCount < filteredCards.length) {
      renderNextPage();
    }
  }, { rootMargin: '400px' });

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
  function openModal(card) {
    modalContent.innerHTML = buildModalContent(card);
    modalOverlay.hidden = false;
    document.body.style.overflow = 'hidden';
    modalCloseBtn.focus();
  }

  function closeModal() {
    modalOverlay.hidden = true;
    document.body.style.overflow = '';
  }

  function buildModalContent(card) {
    const imgSrc = card.imageAvailable && card.imageFile
      ? API.fullUrl(card.imageFile) : null;

    const imgHtml = imgSrc
      ? `<img class="modal-card-img" src="${escHtml(imgSrc)}" alt="${escHtml(card.name)}" loading="lazy">`
      : `<div class="modal-img-placeholder" data-element="${escHtml(card.element || 'NONE')}"
              aria-hidden="true">${escHtml(card.element || '?')}</div>`;

    const statsRows = [
      ['Set',          card.set],
      ['Sub-Set',      card.subSet],
      ['Treatment',    card.treatment],
      ['Variation',    card.variation],
      ['Type',         card.cardType],
      card.playCost   ? ['Play Cost',  card.playCost]   : null,
      card.playAbility ? ['Ability', `<span class="play-ability-text">${escHtml(card.playAbility)}</span>`] : null,
      card.athleteInspiration ? ['Athlete', card.athleteInspiration] : null,
    ]
    .filter(Boolean)
    .map(([label, val]) =>
      `<tr>
        <th>${escHtml(label)}</th>
        <td>${label === 'Ability' ? val : escHtml(val ?? '—')}</td>
       </tr>`
    ).join('');

    return `
      <div class="modal-layout">
        <div class="modal-art">${imgHtml}</div>
        <div class="modal-details">
          <div class="modal-badges">
            <span class="element-badge element-badge-lg"
                  data-element="${escHtml(card.element || 'NONE')}">${escHtml(card.element || 'NONE')}</span>
            ${card.isInspiredInk ? '<span class="inspired-ink-badge">Inspired Ink</span>' : ''}
          </div>
          <div>
            <h2 class="modal-card-name" id="modal-card-name">${escHtml(card.name)}</h2>
            <div class="modal-card-number">${escHtml(card.cardNumber)}</div>
          </div>
          <div class="modal-power">P<span>${escHtml(String(card.power))}</span></div>
          <table class="stats-table" aria-label="Card stats">
            <tbody>${statsRows}</tbody>
          </table>
          <div class="pricing-section">
            <h3 class="pricing-title">Pricing Comps</h3>
            <p class="pricing-note">Radish &amp; eBay live pricing — coming soon.</p>
          </div>
        </div>
      </div>`;
  }

  modalCloseBtn.addEventListener('click', closeModal);
  modalOverlay.addEventListener('click', (e) => {
    if (e.target === modalOverlay) closeModal();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !modalOverlay.hidden) closeModal();
  });

  /* ================================================================
     INITIALIZATION
  ================================================================ */
  async function init() {
    // URL routing
    const params = new URLSearchParams(window.location.search);
    const urlView = params.get('view');
    if (urlView && viewIds.includes(urlView)) {
      showView(urlView, true);
    } else {
      showView('search', true);
    }

    // Load card catalog
    try {
      [cards, searchIndex, categories] = await Promise.all([
        API.loadCards(),
        API.loadSearchIndex(),
        API.loadCategories(),
      ]);
    } catch (err) {
      loadingState.innerHTML = `<p style="color:#FF4D00">Failed to load card catalog. Please refresh.</p>`;
      console.error('Catalog load error:', err);
      return;
    }

    loadingState.hidden = true;

    // Build filter controls
    buildElementFilters();
    buildSetFilter();
    buildTreatmentFilter();

    // Initial render — all cards
    filteredCards = cards;
    renderNextPage();
    updateResultsCount();
    cardGrid.hidden = false;
  }

  init();
})();
