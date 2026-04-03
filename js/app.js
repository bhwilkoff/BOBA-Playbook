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

  /* ================================================================
     STATE
  ================================================================ */
  let cards         = [];         // raw catalog (may have multi-hero dupes)
  let searchIndex   = null;
  let categories    = null;

  // Built after load:
  let cardsByNumber = new Map();  // cardNumber (string) → Card[] (all hero associations)
  let displayCards  = [];         // one Card per unique cardNumber (for the grid)

  let filteredCards  = [];
  let displayedCount = 0;

  const filters = {
    query:    '',
    element:  '',
    set:      '',
    treatment:'',
    hasImage: false,
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
  sidebarToggle.addEventListener('click', () => {
    sidebar.classList.add('open');
    sidebarOverlay.classList.add('visible');
    sidebarToggle.setAttribute('aria-expanded', 'true');
  });

  function closeSidebar() {
    sidebar.classList.remove('open');
    sidebarOverlay.classList.remove('visible');
    sidebarToggle.setAttribute('aria-expanded', 'false');
  }
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
      const active = id === name;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-current', active ? 'page' : 'false');
    });
    closeSidebar();
    if (!fromHistory) {
      history.pushState({ view: name }, '', name === 'search' ? '?' : `?view=${name}`);
    }
  }

  Object.entries(navBtnIds).forEach(([view, btnId]) => {
    const btn = $(btnId);
    if (btn) btn.addEventListener('click', () => showView(view));
  });

  window.addEventListener('popstate', (e) => {
    showView(e.state?.view || 'search', true);
  });

  /* ================================================================
     DATA PREPARATION
     Build lookup structures after cards.json loads.
  ================================================================ */

  function prepareData() {
    // Build cardsByNumber: string cardNumber → all Card variants (hero associations)
    for (const card of cards) {
      const num = String(card.cardNumber);
      if (!cardsByNumber.has(num)) cardsByNumber.set(num, []);
      cardsByNumber.get(num).push(card);
    }

    // Build displayCards: one entry per cardNumber.
    // Prefer the variant that has an image available.
    for (const variants of cardsByNumber.values()) {
      const representative = variants.find(c => c.imageAvailable && c.imageFile) || variants[0];
      displayCards.push(representative);
    }
  }

  /* ================================================================
     SEARCH LOGIC
     search-index values are card NUMBERS (strings), not array positions.
  ================================================================ */

  function computeResults() {
    let resultNums = null; // null = "all cards"

    // Text search
    const q = filters.query.trim().toLowerCase();
    if (q) {
      const tokens = q.split(/\s+/).filter(Boolean);
      for (const token of tokens) {
        const matches = new Set();
        for (const key in searchIndex.tokenIndex) {
          if (key.startsWith(token)) {
            for (const cardNum of searchIndex.tokenIndex[key]) {
              matches.add(String(cardNum));
            }
          }
        }
        resultNums = resultNums === null ? matches : intersect(resultNums, matches);
      }
      if (resultNums !== null && resultNums.size === 0) return [];
    }

    // Element filter
    if (filters.element) {
      const s = new Set((searchIndex.byElement[filters.element] || []).map(String));
      resultNums = resultNums === null ? s : intersect(resultNums, s);
    }

    // Set filter
    if (filters.set) {
      const s = new Set((searchIndex.bySet[filters.set] || []).map(String));
      resultNums = resultNums === null ? s : intersect(resultNums, s);
    }

    // Treatment filter
    if (filters.treatment) {
      const s = new Set((searchIndex.byTreatment[filters.treatment] || []).map(String));
      resultNums = resultNums === null ? s : intersect(resultNums, s);
    }

    // Has image filter
    if (filters.hasImage) {
      const s = new Set((searchIndex.hasImage || []).map(String));
      resultNums = resultNums === null ? s : intersect(resultNums, s);
    }

    if (resultNums === null) return displayCards;

    // Map card numbers → display cards
    const results = [];
    for (const num of resultNums) {
      const card = cardsByNumber.get(num)?.[0]; // representative card
      if (card) {
        const rep = cardsByNumber.get(num).find(c => c.imageAvailable && c.imageFile) || card;
        results.push(rep);
      }
    }
    return results;
  }

  function intersect(a, b) {
    return new Set([...a].filter(x => b.has(x)));
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
      opt.textContent = t;
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

  hasImageToggle.addEventListener('click', () => {
    filters.hasImage = !filters.hasImage;
    hasImageToggle.setAttribute('aria-pressed', String(filters.hasImage));
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
    buildTreatmentFilter('');
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
          <span class="element-badge" data-element="${escHtml(card.element || 'NONE')}">${escHtml(card.element || 'NONE')}</span>
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
    searchCount.textContent = `${filteredCards.length.toLocaleString()} cards`;
  }

  /* ================================================================
     LOAD MORE — IntersectionObserver on sentinel
  ================================================================ */
  const sentinelObserver = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting && displayedCount < filteredCards.length) {
      renderNextPage();
    }
  }, { rootMargin: '300px' });

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
    const imgSrc = card.imageAvailable && card.imageFile ? API.fullUrl(card.imageFile) : null;

    const imgHtml = imgSrc
      ? `<img class="modal-card-img" src="${escHtml(imgSrc)}" alt="${escHtml(card.name)}" loading="lazy">`
      : `<div class="modal-img-placeholder" data-element="${escHtml(card.element || 'NONE')}"
              aria-hidden="true">${escHtml(card.element || '?')}</div>`;

    // All hero/athlete associations for this card
    const variants = cardsByNumber.get(String(card.cardNumber)) || [card];

    let heroSection = '';
    if (variants.length > 1) {
      const rows = variants.map(v =>
        `<tr>
          <td>${escHtml(v.hero)}</td>
          <td>${escHtml(v.athleteInspiration || '—')}</td>
         </tr>`
      ).join('');
      heroSection = `
        <div class="hero-associations">
          <h3 class="section-label">Hero Associations</h3>
          <table class="stats-table">
            <thead><tr><th>Hero</th><th>Athlete Inspiration</th></tr></thead>
            <tbody>${rows}</tbody>
          </table>
        </div>`;
    }

    const statsRows = [
      ['Set',         card.set],
      ['Sub-Set',     card.subSet],
      ['Treatment',   card.treatment],
      ['Variation',   card.variation],
      ['Type',        card.cardType],
      card.playCost   ? ['Play Cost', card.playCost]   : null,
      card.playAbility ? ['Ability', `<span class="play-ability-text">${escHtml(card.playAbility)}</span>`] : null,
      variants.length === 1 && card.athleteInspiration ? ['Athlete', card.athleteInspiration] : null,
    ]
    .filter(Boolean)
    .map(([label, val]) =>
      `<tr><th>${escHtml(label)}</th><td>${label === 'Ability' ? val : escHtml(val ?? '—')}</td></tr>`
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
          ${heroSection}
          <div class="pricing-section">
            <h3 class="pricing-title">Pricing Comps</h3>
            <p class="pricing-note">Radish &amp; eBay live pricing — coming soon.</p>
          </div>
        </div>
      </div>`;
  }

  modalCloseBtn.addEventListener('click', closeModal);
  modalOverlay.addEventListener('click', (e) => { if (e.target === modalOverlay) closeModal(); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !modalOverlay.hidden) closeModal();
  });

  /* ================================================================
     INITIALIZATION
  ================================================================ */
  async function init() {
    const params = new URLSearchParams(window.location.search);
    const urlView = params.get('view');
    showView(viewIds.includes(urlView) ? urlView : 'search', true);

    try {
      [cards, searchIndex, categories] = await Promise.all([
        API.loadCards(),
        API.loadSearchIndex(),
        API.loadCategories(),
      ]);
    } catch (err) {
      loadingState.innerHTML = `<p style="color:var(--boba-orange);font-family:var(--font-mono)">
        Failed to load card catalog. Please refresh the page.</p>`;
      console.error('Catalog load error:', err);
      return;
    }

    prepareData();

    loadingState.hidden = true;
    buildElementFilters();
    buildSetFilter();
    buildTreatmentFilter('');

    filteredCards = displayCards;
    renderNextPage();
    updateResultsCount();
  }

  init();
})();
