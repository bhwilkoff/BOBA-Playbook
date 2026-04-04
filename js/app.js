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
    powerMin: null,
    powerMax: null,
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
  const powerMinInput  = $('power-min');
  const powerMaxInput  = $('power-max');
  const filterToggleBtn = $('filter-toggle-btn');
  const filterPanel     = $('filter-panel');
  const filterBadge     = $('filter-badge');

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

    // Sort: cards with images first, no-image cards last.
    displayCards.sort((a, b) => {
      const aImg = !!(a.imageFile);
      const bImg = !!(b.imageFile);
      if (aImg !== bImg) return aImg ? -1 : 1;
      return 0;
    });
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

    // Power range filter (applied after number filtering)
    if (filters.powerMin !== null || filters.powerMax !== null) {
      const powerSet = new Set();
      if (resultNums === null) {
        for (const card of displayCards) powerSet.add(String(card.cardNumber));
      } else {
        for (const num of resultNums) powerSet.add(num);
      }
      const filtered = new Set();
      for (const num of powerSet) {
        const variants = cardsByNumber.get(num);
        if (!variants) continue;
        const rep = variants.find(c => c.imageAvailable && c.imageFile) || variants[0];
        const p = Number(rep.power);
        const minOk = filters.powerMin === null || p >= filters.powerMin;
        const maxOk = filters.powerMax === null || p <= filters.powerMax;
        if (minOk && maxOk) filtered.add(num);
      }
      resultNums = filtered;
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
     TREATMENT & SET CLASS HELPERS
  ================================================================ */

  function getTreatmentClass(treatment) {
    if (!treatment) return 'tf-base';
    const t = treatment.toLowerCase();
    if (t.includes('blizzard')) return 'tf-blizzard';
    if (t.includes('superfoil')) return 'tf-superfoil';
    if (t.includes('battlefoil')) return 'tf-battlefoil';
    if (t.includes('inspired ink') || t.includes('inspired-ink')) return 'tf-inspired';
    if (t.includes('inspired')) return 'tf-inspired-m';
    if (t.includes('logofoil')) return 'tf-logofoil';
    if (t.includes('blast')) return 'tf-blast';
    if (t.includes('paper')) return 'tf-paper';
    if (t === 'base' || t === 'standard' || t === '') return 'tf-base';
    return 'tf-special';
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
    searchInput.value = '';
    searchClear.hidden = true;
    setFilter.value = '';
    buildTreatmentFilter('');
    hasImageToggle.setAttribute('aria-pressed', 'false');
    if (powerMinInput) powerMinInput.value = '';
    if (powerMaxInput) powerMaxInput.value = '';
    document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
    document.querySelector('.power-preset[data-min=""]')?.classList.add('active');
    setElementFilter('');
    updateFilterBadge();
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
    updateFilterBadge();
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
    const treatmentClass = getTreatmentClass(card.treatment);
    const el = document.createElement('article');
    el.className = `card-item ${treatmentClass}`;
    el.setAttribute('role', 'listitem');
    el.dataset.element = card.element || 'NONE';
    el.setAttribute('tabindex', '0');
    el.setAttribute('aria-label', `${card.name}, ${card.element || 'No element'}, Power ${card.power}`);

    const imgHtml = card.imageFile
      ? `<img class="card-img" src="${escHtml(API.thumbUrl(card.imageFile))}"
              alt="${escHtml(card.name)}" loading="lazy" decoding="async">`
      : `<div class="card-img-placeholder" aria-hidden="true">
           <span class="placeholder-brand">BOBA PB</span>
           <span class="placeholder-status">Image Pending</span>
         </div>`;

    // Only show treatment ribbon for non-base treatments
    const ribbonHtml = (treatmentClass !== 'tf-base')
      ? `<div class="card-treatment-ribbon" aria-hidden="true">${escHtml(card.treatment)}</div>`
      : '';

    el.innerHTML = `
      <div class="card-img-wrap">
        ${imgHtml}
        ${ribbonHtml}
      </div>
      <div class="card-info">
        <div class="card-number">${escHtml(card.cardNumber)}</div>
        <div class="card-name">${escHtml(card.name)}</div>
        <div class="card-meta">
          <span class="element-badge" data-element="${escHtml(card.element || 'NONE')}">${escHtml(card.element || 'NONE')}</span>
          <span class="card-power" aria-label="Power ${card.power}">P${escHtml(String(card.power))}</span>
        </div>
      </div>
      <div class="card-element-bar" aria-hidden="true"></div>`;

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

  function openModal(card) {
    modalContent.innerHTML = buildModalContent(card);
    modalOverlay.hidden = false;
    document.body.style.overflow = 'hidden';
    modalCloseBtn.focus();
    initZoom();

    // Wire "Add to Collection" button
    modalContent.querySelector('[data-action="add-to-collection"]')
      ?.addEventListener('click', () => Collection.openAddSheet(card));
  }

  function closeModal() {
    cleanupZoom();
    modalOverlay.hidden = true;
    document.body.style.overflow = '';
  }

  function buildModalContent(card) {
    const imgSrc = card.imageAvailable && card.imageFile ? API.fullUrl(card.imageFile) : null;
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

    // All hero/athlete associations for this card
    const variants = cardsByNumber.get(String(card.cardNumber)) || [card];

    let heroSection = '';
    if (variants.length > 1) {
      const heroCards = variants.map(v => `
        <div class="hero-card">
          <div>
            <div class="hero-card-name">${escHtml(v.hero || '—')}</div>
            ${v.athleteInspiration ? `<div class="hero-card-athlete">${escHtml(v.athleteInspiration)}</div>` : ''}
          </div>
        </div>`).join('');
      heroSection = `
        <div class="hero-associations">
          <h3 class="section-label">Hero Associations</h3>
          <p class="hero-association-note">This card works with ${variants.length} heroes — a BOBA game mechanic.</p>
          <div class="hero-cards">${heroCards}</div>
        </div>`;
    }

    // Build stat cells — grid layout
    const statDefs = [
      { label: 'Set',       val: card.set,       full: false },
      { label: 'Sub-Set',   val: card.subSet,     full: false },
      { label: 'Type',      val: card.cardType,   full: false },
      { label: 'Variation', val: card.variation,  full: false },
    ].filter(s => s.val);

    if (variants.length === 1 && card.athleteInspiration) {
      statDefs.push({ label: 'Athlete', val: card.athleteInspiration, full: true });
    }
    if (card.playCost) {
      statDefs.push({ label: 'Play Cost', val: card.playCost, full: false });
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

    // Treatment banner (only for non-base)
    const treatmentBanner = (treatmentClass !== 'tf-base' && card.treatment)
      ? `<span class="treatment-banner ${treatmentClass}">${escHtml(card.treatment)}</span>`
      : '';

    return `
      <div class="modal-layout ${treatmentClass}" data-element="${escHtml(element)}">
        <div class="modal-art">${imgHtml}</div>
        <div class="modal-details">
          <div class="modal-badges">
            <span class="element-badge element-badge-lg"
                  data-element="${escHtml(element)}">${escHtml(element)}</span>
            <span class="set-badge ${setClass}">${escHtml(card.set || 'Unknown')}</span>
            ${treatmentBanner}
          </div>
          <div>
            <h2 class="modal-card-name" id="modal-card-name">${escHtml(card.name)}</h2>
            <div class="modal-card-number"># ${escHtml(card.cardNumber)}</div>
          </div>
          <div class="modal-power-display">
            <span class="power-label-txt">POWER</span>
            <span class="power-number">${escHtml(String(card.power))}</span>
          </div>
          <div class="modal-stats" aria-label="Card stats">
            ${statCells}
          </div>
          ${heroSection}
          <div class="modal-collection-action">
            <button class="btn-collection-add" data-action="add-to-collection">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M12 5v14M5 12h14"/>
              </svg>
              Add to Collection
            </button>
          </div>
          <div class="pricing-section">
            <h3 class="section-label">Pricing Comps</h3>
            <p class="pricing-note">Radish &amp; eBay live pricing — coming in M3.</p>
          </div>
        </div>
      </div>`;
  }

  modalCloseBtn.addEventListener('click', closeModal);
  modalOverlay.addEventListener('click', (e) => { if (e.target === modalOverlay) closeModal(); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !modalOverlay.hidden) closeModal();
  });

  // Fired by collection detail when a variation tile is tapped
  document.addEventListener('open-card-by-number', ({ detail: { cardNumber } }) => {
    const cardSet = cardsByNumber.get(String(cardNumber));
    if (cardSet?.length) openModal(cardSet[0]);
  });

  /* ================================================================
     INITIALIZATION
  ================================================================ */
  async function init() {
    // Init auth + collection modules (must be before first render)
    Auth.init();
    Collection.init();

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
    Collection.setCardLookup(num => cardsByNumber.get(String(num))?.[0]);
    Collection.setVariantLookup((hero, excludeNum) =>
      displayCards.filter(c => c.hero === hero && String(c.cardNumber) !== String(excludeNum))
    );

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
