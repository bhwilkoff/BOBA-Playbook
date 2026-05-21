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
    release:  '',
    hasImage: false,
    powerMin: null,
    powerMax: null,
    sortBy:   'default',
    showcaseId: '',   // curated subset (WOBA / Basketball / etc.), see js/showcases.js
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
  const elementFilters   = $('element-filters');
  const showcaseFilters  = $('showcase-filters');
  const quickAddToggle   = $('quick-add-toggle');

  /// Whether the Find-view "Quick Add" toggle is active. When true,
  /// tapping a grid card adds it to the user's Collection instead of
  /// opening the modal. Gated on auth at the pill visibility layer.
  let quickAddMode = false;
  const setFilter       = $('set-filter');
  const treatmentFilter = $('treatment-filter');
  const releaseFilter   = $('release-filter');
  const hasImageCheckbox = document.getElementById('has-image-checkbox');
  const loadSentinel    = $('load-sentinel');
  const clearFiltersBtn = $('clear-filters-btn');
  const filterClearAllBtn = $('filter-clear-all-btn');
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

  // DBS explainer dialog wiring (parity with iOS DBSInfoSheet).
  // Document-level delegate so EVERY DBS-tagged element opens the
  // explainer — card-detail modal DBS stat cells AND the Decks
  // editor DBS budget chip (tick 148, closing the 3-platform parity
  // loop with iOS tick 147 + Android tick 134).
  const dbsInfoOverlay = $('dbs-info-overlay');
  document.addEventListener('click', (e) => {
    const trigger = e.target.closest('[data-action="open-dbs-info"]');
    if (trigger) {
      e.preventDefault();
      dbsInfoOverlay?.showModal();
    }
  });
  dbsInfoOverlay?.addEventListener('click', (e) => {
    const closeBtn = e.target.closest('[data-action="close-dbs-info"]');
    // Close on click of explicit X OR on backdrop click (target === dialog).
    if (closeBtn || e.target === dbsInfoOverlay) {
      dbsInfoOverlay.close();
    }
  });

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

  /* Desktop sidebar collapse toggle — shrinks the sidebar to icon-only
     width and reclaims the horizontal space for main content. State
     persists across reloads via localStorage. */
  const COLLAPSE_KEY = 'boba.sidebarCollapsed';
  const collapseToggle = $('sidebar-collapse-toggle');
  if (collapseToggle) {
    const initial = localStorage.getItem(COLLAPSE_KEY) === '1';
    if (initial) document.body.classList.add('sidebar-collapsed');
    const syncAria = () => {
      const collapsed = document.body.classList.contains('sidebar-collapsed');
      collapseToggle.setAttribute('aria-expanded', String(!collapsed));
      collapseToggle.setAttribute('aria-label',
        collapsed ? 'Expand navigation' : 'Collapse navigation');
    };
    syncAria();
    collapseToggle.addEventListener('click', () => {
      const collapsed = document.body.classList.toggle('sidebar-collapsed');
      localStorage.setItem(COLLAPSE_KEY, collapsed ? '1' : '0');
      syncAria();
    });
  }

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
    if (filters.release)                                count++;
    if (filters.powerMin !== null || filters.powerMax !== null) count++;
    if (filters.hasImage)                               count++;
    // Showcase pick (WOBA / Basketball / etc.) was missing from the
    // badge count — a user with WOBA active saw "0 filters" while
    // results were clearly narrowed. Sort is intentionally NOT counted
    // (reorders, doesn't filter).
    if (filters.showcaseId)                             count++;
    if (filterBadge) {
      filterBadge.textContent = String(count);
      filterBadge.hidden = count === 0;
    }
    filterToggleBtn?.classList.toggle('has-filters', count > 0);
    renderActiveFilterChips();
  }

  /// Render dismissible chips for every active filter, always-visible
  /// above the (collapsible) filter panel. Without this, users with
  /// the panel closed could only see the badge count + the empty-state
  /// hint (when filter-yields-zero) — they had to open the panel to
  /// see WHAT was filtering. Tick 73.
  function renderActiveFilterChips() {
    const container = document.getElementById('active-filter-chips');
    if (!container) return;
    const chips = [];
    const push = (label, removeFn) => chips.push({ label, removeFn });
    if (filters.element)    push(filters.element,                () => setElementFilter(''));
    if (filters.set)        push(`Set: ${filters.set}`,          () => { setFilter.value = ''; filters.set = ''; buildTreatmentFilter(''); filters.treatment = ''; applyFilters(); });
    if (filters.treatment)  push(`Treatment: ${filters.treatment}`, () => { treatmentFilter.value = ''; filters.treatment = ''; applyFilters(); });
    if (filters.release)    push(`Release: ${filters.release}`,  () => { releaseFilter.value = ''; filters.release = ''; applyFilters(); });
    if (filters.showcaseId) push(`Showcase: ${filters.showcaseId}`, () => setShowcaseFilter(''));
    if (filters.hasImage)   push('Image only',                   () => { filters.hasImage = false; if (hasImageCheckbox) hasImageCheckbox.checked = false; applyFilters(); });
    if (filters.powerMin != null || filters.powerMax != null) {
      const min = filters.powerMin ?? 0;
      const max = filters.powerMax ?? '∞';
      push(`Power ${min}–${max}`, () => {
        filters.powerMin = null;
        filters.powerMax = null;
        if (powerMinInput) powerMinInput.value = '';
        if (powerMaxInput) powerMaxInput.value = '';
        document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
        document.querySelector('.power-preset[data-min=""]')?.classList.add('active');
        applyFilters();
      });
    }
    container.hidden = chips.length === 0;
    container.innerHTML = chips.map((c, i) =>
      `<button type="button" class="active-filter-chip" data-chip-i="${i}" aria-label="Remove filter ${escHtml(c.label)}">
        <span>${escHtml(c.label)}</span>
        <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor"
             stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M18 6 6 18M6 6l12 12"/>
        </svg>
      </button>`
    ).join('');
    container.querySelectorAll('.active-filter-chip').forEach((btn, i) => {
      btn.addEventListener('click', () => chips[i].removeFn(), { once: true });
    });
  }

  /* ================================================================
     VIEW SYSTEM
  ================================================================ */
  const viewIds = ['search', 'scan', 'rules', 'decks', 'practice', 'stores', 'collection', 'purchase', 'profile', 'public-collection'];
  const navBtnIds = {
    search:        'nav-search-btn',
    scan:          'nav-scan-btn',
    rules:         'nav-rules-btn',
    decks:         'nav-decks-btn',
    practice:      'nav-practice-btn',
    stores:        'nav-stores-btn',
    collection:    'nav-collection-btn',
    purchase:      'nav-purchase-btn',
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
    if (filters.release)                   p.set('release', filters.release);
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
    filters.release   = params.get('release') || '';
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
    if (releaseFilter)   releaseFilter.value   = filters.release;

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

  /// Reduced-motion respect — when the user prefers reduced motion,
  /// skip View Transitions so we don't animate against their setting.
  /// Re-evaluated each call so OS preference changes mid-session take
  /// effect immediately.
  function prefersReducedMotion() {
    return typeof window.matchMedia === 'function'
        && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }

  /// Cross-cutting Share verb (WEB-DESIGN.md §8.2) — single helper
  /// every share button calls. Uses the native Web Share API when
  /// available (mobile Safari, Chrome Android), falls back to
  /// clipboard.writeText + on-button toast everywhere else
  /// (Firefox, Chrome desktop). AbortError = user dismissed the
  /// share sheet — silent.
  ///
  /// `payload`: { title, text, url } — same shape as navigator.share.
  /// `triggerEl` (optional): the <button> that triggered the share;
  ///   gets a 2-sec "Link copied!" label after the clipboard fallback
  ///   so the user knows something happened.
  async function shareTarget(payload, triggerEl) {
    const url = payload?.url || window.location.href;
    const args = { ...payload, url };
    if (typeof navigator.share === 'function') {
      try {
        await navigator.share(args);
        return 'shared';
      } catch (e) {
        if (e?.name === 'AbortError') return 'cancelled';
        // Other errors fall through to the copy path so the user
        // still gets something useful (e.g. iOS share sheet refused
        // due to a missing entitlement, etc.).
      }
    }
    try {
      await navigator.clipboard.writeText(url);
      if (triggerEl) {
        const original = triggerEl.innerHTML;
        const originalText = triggerEl.textContent;
        triggerEl.textContent = 'Link copied!';
        setTimeout(() => {
          triggerEl.innerHTML = original;
          if (triggerEl.textContent !== originalText) {
            triggerEl.textContent = originalText;
          }
        }, 2000);
      }
      return 'copied';
    } catch (_) {
      return 'failed';
    }
  }
  // Expose globally so other modules (collection.js, etc.) can call it
  // without re-implementing the feature-detect.
  window.bobaShareTarget = shareTarget;

  /// Native Popover-API menu (WEB-DESIGN.md §2.1 + §13 ADOPT).
  /// Replaces hand-rolled dropdown patterns and blocking
  /// prompt()/alert() pickers. The browser owns dismissal (click
  /// outside / ESC), top-layer rendering, and focus return.
  ///
  /// `opts`:
  ///   anchor:  HTMLElement that triggered the menu (positioning)
  ///   title:   string shown above the items (optional)
  ///   items:   array of { label, sublabel?, onSelect }
  ///
  /// Builds a transient `<div popover="auto">`, appends to body,
  /// shows, and removes it from the DOM when dismissed (the
  /// `toggle` event fires with newState === 'closed'). One menu
  /// per call — no need to manage IDs.
  function showPopoverMenu({ anchor, title, items }) {
    if (!items?.length) return;
    const menu = document.createElement('div');
    menu.className = 'popover-menu';
    menu.setAttribute('popover', 'auto');
    menu.setAttribute('role', 'menu');
    if (title) {
      const t = document.createElement('div');
      t.className = 'popover-menu-title';
      t.textContent = title;
      menu.appendChild(t);
    }
    items.forEach(({ label, sublabel, onSelect }) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'popover-menu-item';
      btn.setAttribute('role', 'menuitem');
      btn.innerHTML = `
        <span class="popover-menu-label">${escHtml(label)}</span>
        ${sublabel ? `<span class="popover-menu-sublabel">${escHtml(sublabel)}</span>` : ''}
      `;
      btn.addEventListener('click', () => {
        menu.hidePopover();
        try { onSelect?.(); } catch (e) { console.error('[popover] onSelect threw', e); }
      });
      menu.appendChild(btn);
    });
    document.body.appendChild(menu);
    // Position near the anchor (best-effort). The Popover API is
    // baseline-supported but CSS Anchor Positioning isn't on
    // Firefox yet (per WEB-DESIGN.md §13 — WAIT verdict). Manual
    // positioning gives us cross-browser today.
    if (anchor) {
      const rect = anchor.getBoundingClientRect();
      menu.style.position = 'fixed';
      menu.style.top  = `${Math.min(rect.bottom + 6, window.innerHeight - 200)}px`;
      menu.style.left = `${Math.max(8, Math.min(rect.left, window.innerWidth - 240))}px`;
    }
    // Cleanup when dismissed (ESC / click outside / item click).
    menu.addEventListener('toggle', (e) => {
      if (e.newState === 'closed') menu.remove();
    });
    if (typeof menu.showPopover === 'function') {
      menu.showPopover();
    } else {
      // Popover API unsupported — fall back to a positioned div that
      // dismisses on next document click.
      menu.style.display = 'block';
      const dismiss = (ev) => {
        if (menu.contains(ev.target)) return;
        menu.remove();
        document.removeEventListener('click', dismiss);
      };
      // Defer so the click that opened the menu doesn't immediately
      // dismiss it.
      setTimeout(() => document.addEventListener('click', dismiss), 0);
    }
  }
  // Expose globally for collection.js / other modules.
  window.bobaShowPopoverMenu = showPopoverMenu;

  function showView(name, fromHistory = false) {
    // Practice is gated to admin only — bounce non-admins back to
    // search if they hit a deep-link or stale history entry.
    if (name === 'practice' && API.getCachedRole?.() !== 'admin') {
      name = 'search';
    }

    // View Transitions API (Baseline 2024) — wraps the DOM swap so
    // the browser cross-fades the old view into the new one. The
    // `view-transition-name` on grid cells + detail surfaces (set
    // contextually on tap; see renderHeroZoomTransition) lets the
    // browser auto-morph paired elements during the same call. Falls
    // back to an instant swap on Firefox <129 / Safari <18 / when
    // prefers-reduced-motion is on. Same-document flavor only — we
    // don't enable cross-document transitions (Firefox holdout).
    if (typeof document.startViewTransition === 'function' && !prefersReducedMotion()) {
      document.startViewTransition(() => applyView(name));
    } else {
      applyView(name);
    }

    if (!fromHistory) {
      history.pushState({ view: name }, '', buildSearchURL());
    }
  }

  /// The actual DOM swap — extracted from showView so it can run
  /// either directly (no-transition path) or inside a
  /// startViewTransition callback. Pure side-effect; do not call
  /// directly from app code, always go through showView.
  /// Update the Open Graph meta tags in <head> to match the current
  /// route. **Note:** link crawlers (Discord, iMessage, Slack, etc.)
  /// read only the STATIC <head> when they crawl a URL — they don't
  /// run JS — so this client-side update only helps in-app share
  /// affordances (Web Share API target string + browser extensions
  /// that re-read the DOM). Server-side rendering would be needed for
  /// crawler-visible per-route OG, which we don't do on GitHub Pages.
  ///
  /// NO twitter:* tags — per DECISIONS.md #053, BOBA never integrates
  /// with Twitter / X. The OG protocol is read by every other major
  /// platform.
  function updateOpenGraphMeta({ title, description, url, image }) {
    const setMeta = (selector, value) => {
      if (value == null) return;
      const el = document.head.querySelector(selector);
      if (el) el.setAttribute('content', value);
    };
    if (title       != null) setMeta('meta[property="og:title"]',       title);
    if (description != null) setMeta('meta[property="og:description"]', description);
    if (url         != null) setMeta('meta[property="og:url"]',         url);
    if (image       != null) setMeta('meta[property="og:image"]',       image);
  }

  // Display-titles for each routable view, used both for the
  // browser-tab `document.title` and for shareable URL previews.
  // Closes WEB-DESIGN.md §4.1 "Pages that aren't pages" anti-pattern.
  const VIEW_TITLES = {
    search:             'Find',
    scan:               'Scan',
    rules:              'Learn',
    decks:              'Decks',
    practice:           'Practice',
    stores:             'Find a Store',
    collection:         'Collection',
    purchase:           'Purchase',
    profile:            'Profile',
    'public-collection': 'Public Collection',
  };

  function applyView(name) {
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
    // Update browser tab title so bookmarks + tab switchers reflect
    // the active view. Card-detail modal updates the title further
    // (see openModal) — we set the per-view fallback here.
    const viewTitle = VIEW_TITLES[name];
    document.title = viewTitle ? `${viewTitle} · BOBA Playbook` : 'BOBA Playbook';
    updateOpenGraphMeta({
      title: viewTitle ? `${viewTitle} · BOBA Playbook` : 'BOBA Playbook',
      url:   `${location.origin}${location.pathname}${location.search}`,
    });
    if (name === 'scan') {
      initScanView();
    } else {
      teardownScan();
    }
    if (name === 'rules' || name === 'decks' || name === 'practice') {
      initPlayView();
    }
    if (name === 'stores' && window.BOBAStoreLocator?.init) {
      window.BOBAStoreLocator.init();
    }
    if (name === 'purchase' && window.PurchaseView?.init) {
      window.PurchaseView.init();
    }
  }

  Object.entries(navBtnIds).forEach(([view, btnId]) => {
    const btn = $(btnId);
    if (btn) btn.addEventListener('click', () => showView(view));
  });

  // Expose showView for ad-hoc calls (purchase.js → "Open the store map" link).
  window.showView = showView;

  // Expose catalog + modal opener for sibling modules (collection.js's
  // Custom Rainbow render, etc.). Read-only access — modules should
  // not mutate displayCards.
  Object.defineProperty(window, '__bobaCatalog', {
    get: () => displayCards,
    configurable: true,
  });
  window.openCardModal = (card) => { if (card) openModal(card, -1); };

  // Admin-only UI visibility. Any element marked [data-admin-only]
  // stays hidden until the cached role is "admin" — practice mode is
  // currently the only consumer.
  function applyRoleVisibility() {
    const isAdmin = API.getCachedRole?.() === 'admin';
    document.querySelectorAll('[data-admin-only]').forEach(el => {
      el.hidden = !isAdmin;
    });
    // If the currently visible view is admin-only and the role flips
    // back to non-admin (sign out), bounce to search.
    if (!isAdmin && currentView === 'practice') showView('search');
  }
  applyRoleVisibility();
  document.addEventListener('auth-change', applyRoleVisibility);

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
      // No card in URL — close modal if open and show the right view.
      // Native <dialog>.open is the source of truth; .hidden is no
      // longer set when using showModal/close.
      const modalOpen = modalOverlay.open ?? !modalOverlay.hidden;
      if (modalOpen) {
        cleanupZoom();
        if (typeof modalOverlay.close === 'function' && modalOverlay.open) {
          modalOverlay.close();
        } else {
          modalOverlay.hidden = true;
          document.body.style.overflow = '';
        }
        modalNavPrev.hidden = true;
        modalNavNext.hidden = true;
        currentModalIndex = -1;
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

    // Read / Watch top-level toggle. Read defaults to visible (active
    // class set in HTML); Watch is hidden until the user flips the
    // pill, at which point we lazy-load the YouTube feed.
    const learnModeBtns   = document.querySelectorAll('.learn-mode-btn');
    const learnModePanels = document.querySelectorAll('.learn-mode-panel');
    learnModeBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        const target = btn.dataset.mode;
        learnModeBtns.forEach(b => {
          b.classList.toggle('active', b.dataset.mode === target);
          b.setAttribute('aria-selected', String(b.dataset.mode === target));
        });
        learnModePanels.forEach(p => {
          p.hidden = p.id !== `learn-panel-${target}`;
        });
        if (target === 'watch' && window.Watch) {
          window.Watch.show();
        }
      });
    });

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

    // Glossary tap-to-copy — 3-platform parity with iOS tick 87 +
    // Android tick 84. Writes "term — definition" to the clipboard,
    // flashes the row with a checkmark for ~1.2s. Event delegation
    // so the handler survives any future re-render of the panel.
    document.addEventListener('click', e => {
      const row = e.target?.closest?.('.glossary-row');
      if (!row || row.classList.contains('copied')) return;
      const term = row.dataset.term || '';
      const def  = row.dataset.def  || '';
      if (!term || !def) return;
      const payload = `${term} — ${def}`;
      navigator.clipboard.writeText(payload).then(() => {
        row.classList.add('copied');
        setTimeout(() => row.classList.remove('copied'), 1200);
      }).catch(() => {
        // Older browsers / file:// origins — silently fall through;
        // user still sees the row but no clipboard write.
      });
    });

    // Glossary share affordance — right-click (desktop) + long-press
    // (touch). Tick 128 — parity with Android tick 126's ACTION_SEND
    // chooser + iOS tick 127's contextMenu ShareLink. Progressive
    // enhancement: no HTML change required; existing rows just gain
    // a new gesture.
    function glossaryShare(row) {
      const term = row?.dataset?.term || '';
      const def  = row?.dataset?.def  || '';
      if (!term || !def) return;
      const payload = `${term} — ${def}`;
      // Web Share API w/ clipboard fallback (existing helper).
      if (typeof window.bobaShareTarget === 'function') {
        window.bobaShareTarget({
          title: `BOBA Glossary: ${term}`,
          text:  payload,
        });
      } else if (navigator.clipboard?.writeText) {
        navigator.clipboard.writeText(payload).then(() => {
          if (window.showToast) window.showToast('Copied — paste to share');
        });
      }
    }
    document.addEventListener('contextmenu', e => {
      const row = e.target?.closest?.('.glossary-row');
      if (!row) return;
      e.preventDefault();  // suppress the browser's right-click menu
      glossaryShare(row);
    });
    // Long-press for touch — 600ms timer, cleared on move/up so a
    // scroll doesn't accidentally trigger share.
    let _glossaryLongPressTimer = null;
    document.addEventListener('touchstart', e => {
      const row = e.target?.closest?.('.glossary-row');
      if (!row) return;
      clearTimeout(_glossaryLongPressTimer);
      _glossaryLongPressTimer = setTimeout(() => {
        glossaryShare(row);
        _glossaryLongPressTimer = null;
      }, 600);
    }, { passive: true });
    const clearLongPress = () => {
      if (_glossaryLongPressTimer) {
        clearTimeout(_glossaryLongPressTimer);
        _glossaryLongPressTimer = null;
      }
    };
    document.addEventListener('touchmove', clearLongPress, { passive: true });
    document.addEventListener('touchend', clearLongPress, { passive: true });
    document.addEventListener('touchcancel', clearLongPress, { passive: true });

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
  // boba-comc-proxy — surfaces COMC.com asking-price listings as a
  // second source on the BUY NOW panel alongside eBay active listings.
  // Soft-fails to "no COMC items" when blocked by Cloudflare Turnstile
  // (current state per 2026-04-29 — see workers/comc-proxy/src/index.ts).
  const COMC_PROXY_URL = 'https://boba-comc-proxy.benwilkoff.workers.dev';
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
    } catch (err) {
      // Surface specific failure modes so the user knows what to fix.
      // Camera API errors come with named exceptions per the spec —
      // generic "denied" is misleading when the actual cause is
      // a busy camera or hardware-missing.
      captureBtn.hidden = true;
      const name = err?.name || '';
      if (name === 'NotAllowedError' || name === 'SecurityError') {
        statusEl.textContent = 'Camera permission denied. Enable camera in your browser settings, then refresh.';
      } else if (name === 'NotFoundError' || name === 'OverconstrainedError') {
        statusEl.textContent = 'No rear-facing camera found. Try the iOS app for full scan support.';
      } else if (name === 'NotReadableError') {
        statusEl.textContent = 'Camera is in use by another app. Close that app and refresh.';
      } else {
        statusEl.textContent = `Couldn't start camera (${name || 'unknown error'}). Try refreshing.`;
      }
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

  // v2.275 — apply runtime image-replacement overrides on top of the
  // catalog. The boba-mod-merge Worker writes the new image to R2
  // (full/ + thumbs/) and sets applied_image_file on the
  // card_image_overrides row. We overwrite card.imageFile in-memory
  // so all renderers (which read card.imageFile + API.cardThumbUrl)
  // pick up the new filename without a cards.json deploy.
  // Precedence: bobaId match > cardNumber match.
  function applyImageOverridesMap(maps) {
    if (!maps) return;
    const { byBobaId, byCardNumber } = maps;
    if (!byBobaId?.size && !byCardNumber?.size) return;
    for (const card of cards) {
      const fromBoba = card.bobaId ? byBobaId.get(String(card.bobaId)) : null;
      const fromCN   = byCardNumber.get(String(card.cardNumber));
      const applied  = fromBoba || fromCN;
      if (applied) card.imageFile = applied;
    }
  }

  // Expose for openModEditPanel + admin-panel approve callbacks so
  // they can refresh the runtime map after a merge without a reload.
  window.refreshAppliedImageOverrides = async function refreshAppliedImageOverrides() {
    try {
      const maps = await API.loadAppliedImageOverrides();
      applyImageOverridesMap(maps);
      if (typeof applyFilters === 'function') applyFilters(true);
    } catch (e) {
      console.warn('refreshAppliedImageOverrides failed:', e);
    }
  };

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

  /// Cards matching a showcase's `match(card)` predicate, reduced to a
  /// Set of bobaIds. Used by both the filter sheet chips and the smart-
  /// search path when a full query resolves to a showcase name.
  function showcaseIdSet(showcase) {
    const ids = new Set();
    if (!showcase) return ids;
    for (const c of displayCards) {
      if (showcase.match(c) && c.bobaId) ids.add(String(c.bobaId));
    }
    return ids;
  }

  function computeResults() {
    let resultIds = null; // null = "all cards"; Set of bobaId strings when filtered

    // Text search
    // Normalize dashes to spaces so card numbers like "CBF-656" tokenize correctly.
    const q = filters.query.trim().toLowerCase().replace(/-/g, ' ');

    // Smart-search showcase shortcut: typing the full showcase name
    // ("WOBA", "Baseball") narrows to the showcase without requiring
    // the filter sheet. Tried BEFORE token matching so a user searching
    // "basketball" doesn't get hero-name partial matches on "Basket".
    const typedShowcase = (window.Showcases && q) ? window.Showcases.matching(q) : null;
    if (typedShowcase) {
      const s = showcaseIdSet(typedShowcase);
      if (s.size === 0) return [];
      resultIds = s;
    } else if (q) {
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

    // Showcase filter (from the filter-sheet chips, distinct from
    // the smart-search shortcut above). Intersects after text search.
    if (filters.showcaseId && window.Showcases) {
      const showcase = window.Showcases.byId(filters.showcaseId);
      const s = showcaseIdSet(showcase);
      if (s.size === 0) return [];
      resultIds = resultIds === null ? s : intersect(resultIds, s);
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

    // Release filter (Alpha / Alpha Update / Griffey / Alpha Blast / etc.)
    if (filters.release) {
      const s = new Set((searchIndex.byRelease[filters.release] || []).map(String));
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
        case 'cost-asc': {
          // Cards without a Hot Dog cost (Heroes/HotDogs/Sealed) sort after Plays.
          const ah = a.playCost != null, bh = b.playCost != null;
          if (ah !== bh) return ah ? -1 : 1;
          const d = Number(a.playCost ?? 0) - Number(b.playCost ?? 0);
          return d || heroName(a).localeCompare(heroName(b));
        }
        case 'cost-desc': {
          const ah = a.playCost != null, bh = b.playCost != null;
          if (ah !== bh) return ah ? -1 : 1;
          const d = Number(b.playCost ?? 0) - Number(a.playCost ?? 0);
          return d || heroName(a).localeCompare(heroName(b));
        }
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

  /* Showcase chips — curated subsets (WOBA + sports today; team / city /
     custom planned). Tap an active chip to clear it, matching the
     Learn > Browse UX. Entries come from js/showcases.js. */
  function buildShowcaseFilters() {
    if (!showcaseFilters || !window.Showcases) return;
    showcaseFilters.innerHTML = '';
    for (const s of window.Showcases.all) {
      const btn = document.createElement('button');
      btn.className = 'showcase-pill';
      btn.dataset.showcaseId = s.id;
      btn.setAttribute('aria-pressed', 'false');
      btn.textContent = s.name;
      btn.addEventListener('click', () => {
        setShowcaseFilter(filters.showcaseId === s.id ? '' : s.id);
      });
      showcaseFilters.appendChild(btn);
    }
  }

  function setShowcaseFilter(id) {
    filters.showcaseId = id;
    showcaseFilters?.querySelectorAll('.showcase-pill').forEach(pill => {
      const active = pill.dataset.showcaseId === id;
      pill.classList.toggle('active', active);
      pill.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
    applyFilters();
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

  function buildReleaseFilter() {
    if (!releaseFilter || !searchIndex?.byRelease) return;
    while (releaseFilter.options.length > 1) releaseFilter.remove(1);
    const releases = Object.keys(searchIndex.byRelease)
      .sort((a, b) => searchIndex.byRelease[b].length - searchIndex.byRelease[a].length);
    for (const rel of releases) {
      const opt = document.createElement('option');
      opt.value = rel;
      opt.textContent = `${rel} (${searchIndex.byRelease[rel].length.toLocaleString()})`;
      releaseFilter.appendChild(opt);
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

  releaseFilter?.addEventListener('change', () => {
    filters.release = releaseFilter.value;
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
  filterClearAllBtn?.addEventListener('click', resetFilters);

  // Quick Add — toggle click, and auth-change listener so the pill
  // disappears on sign-out. Auth module dispatches 'auth-change' with
  // detail.session set when signed in.
  quickAddToggle?.addEventListener('click', () => setQuickAddMode(!quickAddMode));
  document.addEventListener('auth-change', ({ detail }) => {
    updateQuickAddVisibility(!!detail?.session);
    // Sign-out → drop any active multi-select. Selection actions
    // (Add to Collection / Add to Deck / Wall) are all auth-required
    // anyway; leaving "5 selected" in the toolbar after sign-out
    // would be misleading.
    if (!detail?.session && selectionMode) {
      exitSelectionMode();
    }
  });

  /* ================================================================
     QUICK ADD (Find view)
  ================================================================ */

  /// Flip the toggle label + styling. Pure cosmetics — the click
  /// branch in buildCardElement reads quickAddMode directly.
  /// Inline SVGs for both states so the icon stays a glyph (no emoji).
  const QUICK_ADD_EYE_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>';
  const QUICK_ADD_PLUS_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" width="14" height="14"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>';
  function setQuickAddMode(on) {
    quickAddMode = !!on;
    if (!quickAddToggle) return;
    quickAddToggle.setAttribute('aria-pressed', on ? 'true' : 'false');
    quickAddToggle.classList.toggle('active', on);
    const label = quickAddToggle.querySelector('.quick-add-label');
    const icon  = quickAddToggle.querySelector('.quick-add-icon');
    if (label) label.textContent = on ? 'Quick Add' : 'Tap to View';
    if (icon)  icon.innerHTML    = on ? QUICK_ADD_PLUS_SVG : QUICK_ADD_EYE_SVG;
  }

  /// Only authenticated users get the pill — Quick Add writes to
  /// Supabase, so there's nothing useful to do signed out. Bound to
  /// the 'auth-change' event the Auth module dispatches.
  function updateQuickAddVisibility(isSignedIn) {
    if (!quickAddToggle) return;
    quickAddToggle.hidden = !isSignedIn;
    if (!isSignedIn) setQuickAddMode(false);
  }

  /// Single-card add. Toast flashes briefly at the top; errors surface
  /// via the same toast with an error tint.
  async function quickAddCard(card) {
    try {
      await window.Collection.quickAdd(card);
      showQuickAddToast(`Added ${card.name ?? card.hero}`, false);
    } catch (err) {
      showQuickAddToast(err?.message || 'Add failed', true);
    }
  }

  let _quickAddToastTimer = null;
  function showQuickAddToast(text, isError) {
    const existing = document.getElementById('quick-add-toast');
    if (existing) existing.remove();
    if (_quickAddToastTimer) { clearTimeout(_quickAddToastTimer); _quickAddToastTimer = null; }

    const toast = document.createElement('div');
    toast.id = 'quick-add-toast';
    toast.className = `quick-add-toast${isError ? ' quick-add-toast--error' : ''}`;
    toast.textContent = (isError ? '⚠ ' : '✓ ') + text;
    document.body.appendChild(toast);
    _quickAddToastTimer = setTimeout(() => {
      toast.classList.add('quick-add-toast--fadeout');
      setTimeout(() => toast.remove(), 300);
    }, 1500);
  }

  function resetFilters() {
    filters.query = '';
    filters.element = '';
    filters.set = '';
    filters.treatment = '';
    filters.release = '';
    filters.hasImage = false;
    filters.powerMin = null;
    filters.powerMax = null;
    filters.sortBy = 'default';
    filters.showcaseId = '';
    searchInput.value = '';
    searchClear.hidden = true;
    setFilter.value = '';
    buildTreatmentFilter('');
    if (releaseFilter) releaseFilter.value = '';
    // Clear any active showcase chip so the filter sheet matches state.
    showcaseFilters?.querySelectorAll('.showcase-pill').forEach(p => {
      p.classList.remove('active');
      p.setAttribute('aria-pressed', 'false');
    });
    if (hasImageCheckbox) hasImageCheckbox.checked = false;
    if (powerMinInput) powerMinInput.value = '';
    if (powerMaxInput) powerMaxInput.value = '';
    if (sortBySelect) sortBySelect.value = 'default';
    document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
    document.querySelector('.power-preset[data-min=""]')?.classList.add('active');
    // setElementFilter('') already triggers applyFilters() via its tail
    // call — that's where the re-render after a clear-all happens.
    // Don't add another applyFilters() here (double-render).
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
    // Native <dialog>.open replaces the prior .hidden check.
    const modalOpen = modalOverlay.open ?? !modalOverlay.hidden;
    if (!skipURLSync && !modalOpen) {
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
    if (isEmpty) updateEmptyStateBody();
  }

  /// Update the empty-state body line to surface what's actually
  /// filtering so the user knows where to relax. Mirrors the iOS
  /// `ContentUnavailableView.search` "Try removing the Cost filter"
  /// suggestion pattern from DESIGN.md §6.7.
  function updateEmptyStateBody() {
    const bodyEl = document.getElementById('empty-state-body');
    if (!bodyEl) return;
    const active = [];
    if (filters.query)                            active.push(`"${filters.query}"`);
    if (filters.element)                          active.push(filters.element);
    if (filters.set)                              active.push(filters.set);
    if (filters.treatment)                        active.push(filters.treatment);
    if (filters.release)                          active.push(filters.release);
    if (filters.hasImage)                         active.push('image-only');
    if (filters.powerMin != null || filters.powerMax != null) {
      const min = filters.powerMin ?? 0;
      const max = filters.powerMax ?? '∞';
      active.push(`power ${min}–${max}`);
    }
    // Surface showcase pick so the user knows WOBA / Basketball / etc.
    // is narrowing the result set. Was missing from the empty-state
    // body line; pairs with tick-41's badge-count fix.
    if (filters.showcaseId)                       active.push(`showcase: ${filters.showcaseId}`);
    if (active.length === 0) {
      bodyEl.textContent = 'Try a different search.';
    } else if (active.length === 1) {
      bodyEl.textContent = `Nothing matches ${active[0]}. Try loosening or removing the filter.`;
    } else {
      bodyEl.textContent = `Nothing matches all of: ${active.join(' · ')}. Try removing one.`;
    }
  }

  function buildCardElement(card, index) {
    const treatmentClass = getTreatmentClass(card.treatment);
    const el = document.createElement('article');
    el.className = `card-item ${treatmentClass}`;
    el.setAttribute('role', 'listitem');
    el.dataset.element = card.element || 'NONE';
    el.setAttribute('tabindex', '0');
    el.setAttribute('aria-label', `${card.name}, ${card.element || 'No weapon'}, Power ${card.power}`);

    // Responsive image: srcset pairs the 200w thumb with the 1200w
    // full, sizes="auto" tells modern browsers to pick per rendered
    // cell width. So a dense "S" grid stays on cheap thumbs, while
    // "L" / 1-2-across viewports auto-upgrade to full so the art
    // doesn't pixelate. Older browsers without sizes="auto" fall
    // back to the breakpoint heuristic.
    const thumbSrc = API.cardThumbUrl(card);
    const srcset   = API.cardImageSrcset(card);
    const imgHtml = thumbSrc
      ? `<img class="card-img" src="${escHtml(thumbSrc)}"
              ${srcset ? `srcset="${escHtml(srcset)}" sizes="auto, (min-width: 1024px) 220px, (min-width: 480px) 33vw, 50vw"` : ''}
              alt="${escHtml(card.name)}" loading="lazy" decoding="async" draggable="false">`
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

    el.dataset.cardId    = cardKey(card);
    el.dataset.cardIndex = String(index);

    // Click branches:
    //   • selectionMode + shift  → extend range from lastSelectedIndex
    //   • selectionMode (any tap)→ toggle this card's selection
    //   • plain shift-click      → enter selection mode + select this
    //   • quickAddMode           → write user_cards row + toast
    //   • default                → open the card modal
    const tapHandler = (e) => {
      // Suppress the synthetic click that fires after a long-press
      // entered selection mode on this exact card.
      if (el.dataset.suppressNextClick === '1') {
        delete el.dataset.suppressNextClick;
        return;
      }
      if (selectionMode || e?.shiftKey) {
        if (e?.shiftKey && lastSelectedIndex >= 0 && lastSelectedIndex !== index) {
          selectRange(lastSelectedIndex, index);
        } else {
          toggleCardSelection(card, index);
        }
        return;
      }
      if (quickAddMode && window.Collection && typeof window.Collection.quickAdd === 'function') {
        quickAddCard(card);
      } else {
        openModalWithHeroZoom(el, card, index);
      }
    };
    el.addEventListener('click', tapHandler);
    el.addEventListener('keydown', e => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); tapHandler(e); }
    });

    // Long-press → enter selection mode + select this card. 500ms
    // threshold matches iOS long-press feel. Cancelled on pointer
    // move >6px or pointer up before the timer fires.
    let pressTimer = null;
    let pressStart = null;
    const cancelPress = () => { if (pressTimer) { clearTimeout(pressTimer); pressTimer = null; } };
    el.addEventListener('pointerdown', (e) => {
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      pressStart = { x: e.clientX, y: e.clientY };
      cancelPress();
      pressTimer = setTimeout(() => {
        pressTimer = null;
        // Suppress the click that fires when the finger lifts.
        el.dataset.suppressNextClick = '1';
        if (!selectionMode) enterSelectionMode();
        toggleCardSelection(card, index);
      }, 500);
    });
    el.addEventListener('pointermove', (e) => {
      if (!pressStart) return;
      const dx = e.clientX - pressStart.x, dy = e.clientY - pressStart.y;
      if (dx*dx + dy*dy > 36) cancelPress();
    });
    el.addEventListener('pointerup',   cancelPress);
    el.addEventListener('pointercancel', cancelPress);
    el.addEventListener('pointerleave', cancelPress);

    // Reflect existing selection state when this cell is rebuilt
    // (re-render after a search refresh keeps selections intact).
    if (selectedCardKeys.has(cardKey(card))) el.classList.add('card-item--selected');

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

  /// View Transitions hero zoom — when the user taps a grid cell,
  /// pair it with the modal's hero image so the browser morphs the
  /// thumbnail into the full image instead of cross-fading.
  ///
  /// Mechanics: set view-transition-name on the source cell + the
  /// matching name on the modal hero image (after openModal runs)
  /// inside one startViewTransition callback. Browser captures both,
  /// auto-pairs by name, animates between them. Names are cleared
  /// after the transition finishes so the next tap starts fresh —
  /// view-transition-name must be unique in the document at the
  /// time of capture.
  ///
  /// Falls back to a plain openModal if the API isn't available
  /// (Safari < 18) or the user prefers reduced motion.
  function openModalWithHeroZoom(sourceEl, card, index) {
    const supports = typeof document.startViewTransition === 'function'
                  && !prefersReducedMotion()
                  && sourceEl;
    if (!supports) {
      openModal(card, index);
      return;
    }
    const name = `card-hero`;  // shared transition slot — only one card animates at a time
    sourceEl.style.viewTransitionName = name;
    const transition = document.startViewTransition(() => {
      openModal(card, index);
      // Tag the hero image so the browser pairs the morph.
      const heroImg = modalContent.querySelector('.modal-card-img');
      if (heroImg) heroImg.style.viewTransitionName = name;
    });
    // Clear the names after the animation so the next click can pair
    // freshly (view-transition-name must be unique at capture time).
    transition.finished.finally(() => {
      sourceEl.style.viewTransitionName = '';
      const heroImg = modalContent.querySelector('.modal-card-img');
      if (heroImg) heroImg.style.viewTransitionName = '';
    });
  }

  function openModal(card, index = -1, fromHistory = false) {
    modalContent.innerHTML = buildModalContent(card);
    // Native <dialog> — showModal handles focus trap + ESC + scroll
    // lock + top layer. Guard re-entry; calling showModal on an
    // already-open dialog throws. The View Transitions hero zoom
    // (openModalWithHeroZoom) calls openModal inside a startView-
    // Transition callback; both paths land here.
    if (typeof modalOverlay.showModal === 'function' && !modalOverlay.open) {
      modalOverlay.showModal();
    } else if (modalOverlay.tagName !== 'DIALOG') {
      // Legacy fallback if markup isn't <dialog> for some reason.
      modalOverlay.hidden = false;
      document.body.style.overflow = 'hidden';
    }
    modalCloseBtn.focus();
    initZoom();

    // Update browser tab title to reflect the open card. Restored
    // to the view's title in closeModal().
    const cardLabel = card.name || card.hero || card.cardNumber || 'Card';
    document.title = `${cardLabel} · BOBA Playbook`;
    updateOpenGraphMeta({
      title: `${cardLabel} · BOBA Playbook`,
      description: [card.hero, card.treatment, card.set].filter(Boolean).join(' · ') ||
                   'A card from the Bo Jackson Battle Arena trading card game.',
      url: buildCardURL(card),
      image: card.imageFile ? (API.cardFullUrl(card) || undefined) : undefined,
    });

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

    // Wire "Share" button — routes through the canonical
    // shareTarget helper (Web Share API → clipboard fallback).
    modalContent.querySelector('[data-action="share-card"]')
      ?.addEventListener('click', (e) => {
        shareTarget({
          title: card.name,
          text:  `${card.name} — BOBA Playbook`,
          url:   window.location.href,
        }, e.currentTarget);
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
  // Set name → [year, slug]. Radish URLs are
  // /boba/{year}/{slug}/{name} for Heroes / Plays / Hot Dogs and
  // /boba/sealed for Sealed Products. The cardNumber is NOT in
  // the URL — earlier attempts to include it landed on Radish's
  // filter route which renders an empty cardNumber-echo page
  // instead of the hero detail page with sales data.
  const SET_SLUG_MAP = {
    'Alpha':                         ['2024', 'Alpha_Edition'],
    'Alpha Edition':                 ['2024', 'Alpha_Edition'],
    'alpha-edition':                 ['2024', 'Alpha_Edition'],
    'Alpha Update':                  ['2025', 'Alpha_Update'],
    'alpha-update':                  ['2025', 'Alpha_Update'],
    'Alpha Blast':                   ['2025', 'Alpha_Blast'],
    'Griffey':                       ['2026', 'Griffey_Edition'],
    'Griffey Edition':               ['2026', 'Griffey_Edition'],
    'griffey-edition':               ['2026', 'Griffey_Edition'],
    'National Starter Set':          ['2024', 'National_24_Starter_Set'],
    '2024 National Show Starter Set': ['2024', 'National_24_Starter_Set'],
    "National '24":                  ['2024', 'National_24_Starter_Set'],
    'National 24 Starter Set':       ['2024', 'National_24_Starter_Set'],
    'World Champions':               ['2024', 'World_Champions'],
    'world-champions':               ['2024', 'World_Champions'],
    'World Champions 2024':          ['2024', 'World_Champions'],
    'World Champions 2025':          ['2025', 'World_Champions'],
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

  // Radish is case-sensitive and uses different canonical spellings
  // for a handful of heroes than our catalog does. Verified 2026-05-20
  // via 100-card URL sweep:
  //   - "ChetMate" (CamelCase) is correct on Radish (40 cards on
  //     /Alpha_Update/ChetMate). An earlier alias mapped ChetMate to
  //     "Chetmate" which returns a 200 but 0-card alias page. Removed.
  //   - "BoJax" -> "Bojax" is correct (Bojax page has 25 cards, BoJax
  //     is the empty alias).
  const RADISH_HERO_ALIASES = {
    BoJax: 'Bojax',
  };

  function buildRadishUrl(card) {
    if (card.radishUrl) return card.radishUrl;
    // Sealed Products land on Radish's sealed-sales index — no
    // per-product detail page exists.
    if (card.cardType === 'Sealed Product') {
      return 'https://radishpriceguide.com/boba/sealed';
    }
    // Verified URL shape (Ben supplied two working examples):
    //   /boba/2025/Alpha_Blast/Mean-Joe/BL-B18
    //   /boba/2025/World_Champions/Chetmate/OKC-27
    // Programmatic fallback — mirrors iOS Card+Radish.swift.
    const [year, slug] = SET_SLUG_MAP[card.set] || ['2024', 'Alpha_Edition'];
    // cardNumber prefix casing per current Radish (verified 2026-05-20):
    //   LOGO- → Logo-   (Radish uses title-case for Logofoil)
    //   everything else stays UPPERCASE
    // An earlier version of this builder lowercased RAD- and MIX- too
    // ("Rad-", "Mix-") — that 404s on current Radish, sending the
    // pricing pipeline + the "Radish Guide" button into a
    // hero-only-fallback path for ~2,970 catalog cards.
    const prefixRemap = { LOGO: 'Logo' };
    let cardNum = card.cardNumber || '';
    for (const [ours, theirs] of Object.entries(prefixRemap)) {
      if (cardNum.startsWith(ours + '-')) {
        cardNum = theirs + cardNum.slice(ours.length);
        break;
      }
    }
    // Plays + Hot Dogs put their card name in the `hero` field
    // (per One-ID-per-Card), so the same formula works for all
    // three cardTypes.
    const raw = card.hero || card.name || '';
    if (!raw || !cardNum) return null;
    const radishHero = RADISH_HERO_ALIASES[raw] || raw;
    const heroEnc = encodeURIComponent(radishHero);
    const numEnc  = encodeURIComponent(cardNum);
    return `https://radishpriceguide.com/boba/${year}/${slug}/${heroEnc}/${numEnc}`;
  }

  function loadPricing(card) {
    const section = $('modal-pricing');
    if (!section) return;

    const ebayUrl   = buildEbayUrl(card);
    const radishUrl = buildRadishUrl(card);
    let days = 30;
    /// When the user taps Refresh, append `&fresh=1` so the Worker
    /// bumps its cache key (the Worker also looks at this flag). Reset
    /// to false after the request lands so subsequent day-toggle
    /// fetches use the cache normally.
    let forceRefresh = false;

    async function fetchAndRender() {
      section.innerHTML = `
        <div class="pricing-header">
          <h3 class="section-label">Pricing</h3>
          <div class="pricing-day-picker" role="group" aria-label="Time range">
            <button class="day-btn${days === 7  ? ' active' : ''}" data-days="7">7d</button>
            <button class="day-btn${days === 30 ? ' active' : ''}" data-days="30">30d</button>
            <button class="day-btn${days === 90 ? ' active' : ''}" data-days="90">90d</button>
            <button class="day-btn pricing-refresh-btn" aria-label="Refresh pricing"
                    title="Refresh now (bypass Worker cache)"
                    type="button">↻</button>
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
      section.querySelectorAll('.day-btn:not(.pricing-refresh-btn)').forEach(btn => {
        btn.addEventListener('click', () => { days = parseInt(btn.dataset.days); fetchAndRender(); });
      });
      // Refresh — same fetch, but flags the Worker cache to bypass so
      // a fresh eBay/Radish/Worker round-trip happens immediately
      // instead of serving the 6-hour cached response. Parity with the
      // iOS + Android pricing refresh button (PARITY.md §8).
      section.querySelector('.pricing-refresh-btn')?.addEventListener('click', () => {
        forceRefresh = true;
        fetchAndRender();
      });

      try {
        // Build the Radish URL on the client so the Worker can scrape
        // Radish's pre-validated sold data — without this, the Worker
        // only saw radishUrl when the (rare) catalog field was set,
        // which meant most cards silently fell back to an Insights-
        // only path that's scope-gated.
        const radishUrl = buildRadishUrl(card);
        const params = new URLSearchParams({
          cardNumber: card.cardNumber,
          hero:    card.hero    || '',
          set:     card.set     || '',
          element: card.element || '',
          days:    String(days),
          ...(card.power    != null ? { power:     String(card.power) }  : {}),
          ...(card.treatment       ? { treatment: card.treatment }       : {}),
          ...(radishUrl            ? { radishUrl }                        : {}),
          ...(forceRefresh         ? { fresh: '1', _t: String(Date.now()) } : {}),
        });
        forceRefresh = false;
        // Fire eBay-pricing + COMC-listings in parallel. COMC is
        // additive (BUY NOW second source); soft-fails to [] so a
        // failure doesn't block the eBay/Radish pricing render.
        const [res, comcResp] = await Promise.all([
          fetch(`${WORKER_URL}?${params}`),
          fetchComcListings(card.cardNumber),
        ]);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        // Snap the Radish button to whichever URL the Worker
        // actually scraped sales from. The Worker tried the
        // cardNumber-specific page first, fell back to the
        // hero-only page, and reported back which one carried
        // listings. Stronger signal than any client-side probe.
        if (data.radishResolvedUrl) {
          const radishLink = section.querySelector('.btn-pricing-radish');
          if (radishLink) radishLink.href = data.radishResolvedUrl;
        }
        renderPricingData(section, data, { days, comcListings: comcResp });
      } catch {
        const body = section.querySelector('.pricing-body');
        if (body) body.innerHTML = '<p class="pricing-error">Pricing unavailable</p>';
      }
    }

    fetchAndRender();
  }

  /// COMC.com asking-price listings, fetched alongside the eBay /
  /// Radish pricing call. Soft-fails to [] on any error — additive
  /// to the BUY NOW panel, never blocks the eBay render. Returns
  /// the listings array (already cheapest-first from the worker).
  async function fetchComcListings(cardNumber) {
    if (!cardNumber) return [];
    const url = `${COMC_PROXY_URL}/listings?cardNumber=${encodeURIComponent(cardNumber)}`;
    try {
      const r = await fetch(url);
      if (!r.ok) return [];
      const j = await r.json();
      return Array.isArray(j.listings) ? j.listings : [];
    } catch {
      return [];
    }
  }

  /// Element-prefix stripping for the hero string. Some COMC
  /// listings render as "Glow - Showtime"; our catalog stores
  /// the hero plainly. Per handoff open-question #2.
  function stripElementPrefix(hero) {
    if (!hero) return hero;
    const match = hero.match(/^(Glow|Steel|Fire|Ice|Hex|Brawl|Gum|Super) - (.+)$/);
    return match ? match[2] : hero;
  }

  /// Renders the COMC asking-price strip beneath the eBay BUY NOW
  /// bucket. Takes top 3 cheapest. Each row links out to the COMC
  /// listing detail page in a new tab.
  function renderComcStrip(listings) {
    if (!Array.isArray(listings) || listings.length === 0) return '';
    const fmt = n => Number.isFinite(n) && n > 0 ? `$${n.toFixed(2)}` : '—';
    const top = listings.slice(0, 3);
    const rows = top.map(l => {
      const heroDisplay = stripElementPrefix(l.hero || '');
      const condParts = [l.grading, l.condition].filter(Boolean).join(' ');
      const pillSuffix = condParts ? ` · ${escHtml(condParts)}` : '';
      return `
        <a href="${escHtml(l.comc_url)}" target="_blank" rel="noopener" class="pricing-item-row pricing-comc-row">
          <span class="pricing-item-price">${fmt(l.asking_price_usd)}</span>
          <span class="pricing-item-title">
            ${escHtml(l.cardNumber || '')} ${escHtml(heroDisplay)}
            <span class="pricing-comc-pill">COMC asking${pillSuffix}</span>
          </span>
          <span class="pricing-item-arrow">↗</span>
        </a>`;
    }).join('');
    return `
      <div class="pricing-section pricing-section-comc">
        <p class="pricing-items-label pricing-comc-label">COMC ASKING</p>
        <div class="pricing-items">${rows}</div>
      </div>`;
  }

  // Plain-English labels for the match-reason signals the Worker emits
  // in item.matchReasons[]. Used in the "Probable match" tooltip.
  const MATCH_REASON_LABELS = {
    card_number_exact:   'card number',
    card_number_partial: 'partial card number',
    hero:                'hero name',
    power:               'power level',
    power_in_title:      'power in title',
    element:             'weapon type',
    treatment:           'treatment',
    manufacturer:        'BOBA manufacturer tag',
    year:                'release year',
    trusted_seller:      'trusted seller',
    price_in_range:      'typical price range',
  };

  function humanizeMatchReasons(reasons) {
    if (!Array.isArray(reasons) || reasons.length === 0) return 'Likely this card';
    const positive = reasons
      .filter(r => !r.includes('penalty') && !r.includes('outlier') && !r.includes('mismatch'))
      .map(r => MATCH_REASON_LABELS[r])
      .filter(Boolean);
    if (positive.length === 0) return 'Likely this card';
    if (positive.length === 1) return `Matched by ${positive[0]}.`;
    return `Matched by ${positive.slice(0, -1).join(', ')} and ${positive[positive.length - 1]}.`;
  }

  function renderPricingSection(label, sectionData, isSold, opts = {}) {
    const fmt = n => n > 0 ? `$${n.toFixed(2)}` : '—';
    const {
      low, average, high, count, count_probable = 0, items = [],
      stale = false, estimated = false, estimatedSource = null
    } = sectionData;
    const typeStr = isSold ? 'sold' : 'active listing';
    const days    = opts.days ?? 30;

    // Estimated path: no real sales — Market Est. range from
    // comparable cards. Render as "MARKET EST." with the same
    // tri-cell shape (EST. LOW / EST. MID / EST. HIGH) plus a
    // subtitle explaining where the range came from.
    if (isSold && estimated) {
      const sourceCaption = estimatedSource === 'comps'
        ? 'Estimated from comparable cards'
        : estimatedSource === 'own_sales'
          ? 'Estimated from prior sales'
          : 'Estimated value';
      return `
        <div class="pricing-section pricing-section-estimated">
          <p class="pricing-items-label">
            MARKET EST.
            <span class="pricing-est-pill">EST</span>
          </p>
          <div class="pricing-grid">
            <div class="pricing-stat">
              <span class="pricing-label">EST. LOW</span>
              <span class="pricing-val">${fmt(low)}</span>
            </div>
            <div class="pricing-stat pricing-stat-center">
              <span class="pricing-label">EST. MID</span>
              <span class="pricing-val pricing-val-avg">${fmt(average)}</span>
            </div>
            <div class="pricing-stat">
              <span class="pricing-label">EST. HIGH</span>
              <span class="pricing-val">${fmt(high)}</span>
            </div>
          </div>
          <p class="pricing-sale-count">${sourceCaption}</p>
        </div>`;
    }

    const itemsHtml = items.length === 0 ? '' : `
      <div class="pricing-items">
        ${items.map(item => {
          const dateStr    = isSold && item.date ? relativeDate(item.date) : '';
          // Probable-match badge: Worker's enriched matcher reports
          // confidence < 0.70 on some sold listings. Render an amber
          // pill that reveals the match reasons on hover / long-press.
          const isProbable = typeof item.matchConfidence === 'number' && item.matchConfidence < 0.70;
          const tooltip    = isProbable ? humanizeMatchReasons(item.matchReasons) : '';
          const badge      = isProbable
            ? `<span class="sold-item-probable" title="${escHtml(tooltip)}">Probable match</span>`
            : '';
          return `
            <a href="${escHtml(item.url)}" target="_blank" rel="noopener" class="pricing-item-row${isProbable ? ' sold-item--probable' : ''}">
              <span class="pricing-item-price">${fmt(item.price)}</span>
              <span class="pricing-item-title">${escHtml(item.title)}${badge}</span>
              ${dateStr ? `<span class="pricing-item-date">${escHtml(dateStr)}</span>` : '<span class="pricing-item-arrow">↗</span>'}
            </a>`;
        }).join('')}
      </div>`;

    // Stale path: only one sale, older than the requested window.
    // Surface that single sale as the market anchor with a "STALE"
    // pill + "Sale {age} ago · older than {days}d window" caption.
    if (isSold && stale && items.length > 0) {
      const sale = items[0];
      const ageStr = relativeDate(sale.date) || '';
      return `
        <div class="pricing-section pricing-section-stale">
          <p class="pricing-items-label">
            ${label}
            <span class="pricing-stale-pill">STALE</span>
          </p>
          <div class="pricing-grid pricing-grid-single">
            <div class="pricing-stat">
              <span class="pricing-label">LAST SOLD</span>
              <span class="pricing-val">${fmt(sale.price)}</span>
            </div>
          </div>
          <p class="pricing-sale-count">${ageStr ? `Sale ${escHtml(ageStr)} · ` : ''}older than ${days}d window</p>
          ${itemsHtml}
        </div>`;
    }

    // Probable-count footnote — only shown when the Worker reported at
    // least one badge-only match that isn't contributing to the totals.
    const probableNote = (isSold && count_probable > 0)
      ? ` · ${count_probable} probable`
      : '';

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
        <p class="pricing-sale-count">${count} ${typeStr}${count !== 1 ? 's' : ''}${probableNote}</p>
        ${itemsHtml}
      </div>`;
  }

  function renderPricingData(section, data, opts = {}) {
    const body = section.querySelector('.pricing-body');
    if (!body) return;
    const fmt = n => n > 0 ? `$${n.toFixed(2)}` : '—';

    // New dual-section format
    if (data.sold || data.active) {
      const parts = [];
      if (data.sold)   parts.push(renderPricingSection('RECENT SALES', data.sold, true,  opts));
      if (data.active) parts.push(renderPricingSection('BUY NOW',      data.active, false, opts));
      // COMC asking-price strip — additive, only renders when we
      // actually have listings (current state with Cloudflare
      // Turnstile on COMC's side: empty array, nothing renders).
      if (Array.isArray(opts.comcListings) && opts.comcListings.length > 0) {
        parts.push(renderComcStrip(opts.comcListings));
      }
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
    // Native <dialog> close — also restores focus + un-traps + un-locks
    // the page scroll. Guard for the legacy fallback path.
    if (typeof modalOverlay.close === 'function' && modalOverlay.open) {
      modalOverlay.close();
    } else {
      modalOverlay.hidden = true;
      document.body.style.overflow = '';
    }
    // Nav buttons are position: fixed (not children of the overlay), so hiding
    // the overlay doesn't hide them — must do it explicitly.
    modalNavPrev.hidden = true;
    modalNavNext.hidden = true;
    currentModalIndex = -1;
    // Replace URL with the current search/filter state (no card param) so the
    // address bar stays accurate and forward doesn't re-open the closed card.
    history.replaceState({ view: currentView }, '', buildSearchURL());
    // Restore the view's tab title (set by applyView at the last
    // navigation). Bookmarks / tab switchers shouldn't keep showing
    // a stale card name after the modal closes.
    const viewTitle = VIEW_TITLES[currentView];
    document.title = viewTitle ? `${viewTitle} · BOBA Playbook` : 'BOBA Playbook';
    updateOpenGraphMeta({
      title: document.title,
      description: 'The definitive companion app for the Bo Jackson Battle Arena trading card game.',
      url: `${location.origin}${location.pathname}${location.search}`,
      image: `${location.origin}/assets/icons/boba_playbook_icon_1024.png`,
    });
  }

  /// "IN YOUR COLLECTION" summary block — iOS tick 107 + Collection-tab
  /// CollectionCardDetailView parity. Renders nothing when the user
  /// doesn't own this card, when signed out, or when the Collection
  /// module isn't ready yet (first paint before init).
  function buildInYourCollectionBlock(card) {
    if (!card || !window.Collection?.entriesForCard) return '';
    const entries = window.Collection.entriesForCard(card);
    if (!Array.isArray(entries) || entries.length === 0) return '';
    // Group by designation, count. DESIGNATIONS shape — label table
    // lives in collection.js but the keys match the user_cards
    // designation column so we can map here without depending on it.
    const labelByKey = {
      personal:  'Personal',
      for_sale:  'For Sale',
      for_trade: 'For Trade',
      wanted:    'Wanted',
      grails:    'Grails',
    };
    const counts = {};
    for (const e of entries) {
      const k = e.designation || 'personal';
      counts[k] = (counts[k] || 0) + 1;
    }
    const summary = Object.keys(counts)
      .sort()  // stable display order
      .map(k => {
        const label = labelByKey[k] || k;
        return counts[k] > 1 ? `${label} ×${counts[k]}` : label;
      })
      .join(' · ');
    return `<div class="in-collection-block" role="status">
      <div class="in-collection-label">IN YOUR COLLECTION (${entries.length})</div>
      <div class="in-collection-summary">${escHtml(summary)}</div>
    </div>`;
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

    // Build stat cells — canonical 6-cell taxonomy layout per the
    // BoBA-expert spec (2026-04-24). Reading order with the existing
    // 2-col CSS grid is left-to-right then top-to-bottom, so the
    // ordered sequence below renders as:
    //
    //   Card #    │ Type
    //   Treatment │ Weapon
    //   Set       │ Sub-set
    //
    // "Treatment" replaces "Rarity" everywhere outside the rarity-
    // by-weapon-type discussion in the Learn tab. "Weapon" replaces
    // "Element" (community always says weapon). Cost / DBS / Ability
    // for plays render below the canonical 6 so the standard layout
    // stays predictable across card types.
    const isHero    = card.cardType === 'Hero';
    const isPlay    = card.cardType === 'Play';
    const isHotDog  = card.cardType === 'HotDog';
    const isSealed  = card.cardType === 'Sealed Product';

    const treatmentVal = !isSealed
      ? (card.treatment && card.treatment.trim() ? card.treatment : 'Base Set')
      : null;
    const weaponVal = (card.element && card.element !== 'NONE') ? card.element : (isSealed ? null : '—');

    const statDefs = [
      { label: 'Card #',    val: card.cardNumber,                 full: false },
      { label: 'Type',      val: card.cardType,                   full: false },
      !isSealed ? { label: 'Treatment', val: treatmentVal, full: false } : null,
      !isSealed ? { label: 'Weapon',    val: weaponVal,    full: false } : null,
      { label: 'Set',       val: card.set,                        full: false },
      { label: 'Sub-set',   val: card.subSet || (isSealed ? null : '—'), full: false },
      // Play-specific extras render after the canonical 6
      isPlay ? { label: 'Cost', val: card.playCost === 0 ? 'FREE' : `${card.playCost} Hot Dog${card.playCost !== 1 ? 's' : ''}`, full: false } : null,
    ].filter(s => s !== null && s.val !== null && s.val !== undefined);

    let statCells = statDefs.map(s =>
      `<div class="stat-cell${s.full ? ' full' : ''}">
         <div class="stat-label-sm">${escHtml(s.label)}</div>
         <div class="stat-val">${escHtml(s.val ?? '—')}</div>
       </div>`
    ).join('');

    // DBS cell (Plays only) — parity with iOS + Android. Tappable;
    // opens an explainer dialog. Color-tinted by tier matches iOS
    // CardDetailView.dbsColor.
    if (isPlay && card.dbs != null) {
      const tier = (card.dbsTier || '').toLowerCase();
      const tierClass = tier ? `dbs-tier-${tier.replace(/\s+/g, '-')}` : '';
      statCells += `
        <button class="stat-cell stat-cell-dbs ${tierClass}" type="button"
                data-action="open-dbs-info"
                aria-label="What is DBS? Open explainer">
          <div class="stat-label-sm">
            DBS <span class="dbs-help" aria-hidden="true">?</span>
          </div>
          <div class="stat-val">
            ${escHtml(String(card.dbs))}
            ${card.dbsTier ? `<span class="dbs-tier-pill">${escHtml(card.dbsTier.toUpperCase())}</span>` : ''}
          </div>
        </button>`;
    }

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
          ${buildInYourCollectionBlock(card)}
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
  // Click on the dialog itself (the backdrop area outside the inner
  // modal box) closes — same UX as the prior overlay div. The inner
  // .modal box catches its own clicks; e.target === modalOverlay
  // only fires for the backdrop region.
  modalOverlay.addEventListener('click', (e) => { if (e.target === modalOverlay) closeModal(); });
  // Native <dialog> fires a `cancel` event when ESC dismisses it
  // before the close — we listen so cleanup (cleanupZoom, URL state
  // reset) runs the same code path as the close button.
  modalOverlay.addEventListener('cancel', (e) => {
    e.preventDefault();   // Prevent the default close so we can route through closeModal
    closeModal();
  });
  document.addEventListener('keydown', (e) => {
    // Native <dialog>.open replaces the prior .hidden check.
    const modalOpen = modalOverlay.open ?? !modalOverlay.hidden;
    if (!modalOpen) return;
    // ESC handled natively by <dialog> (fires `cancel` event); we
    // only need ArrowLeft/Right for prev/next nav.
    if (e.key === 'ArrowLeft')  { navigateModal(-1); return; }
    if (e.key === 'ArrowRight') { navigateModal(+1); return; }
  });

  // `/` (no modifier) — jump to Find tab + focus the search input.
  // Tick 133 — parity with iOS Cmd+/ (tick 132) + Android `/` (tick
  // 131). Canonical "go to search" idiom (GitHub, YouTube, X all map
  // `/` to focus search). Skip when the user is already typing in an
  // input / textarea / contentEditable / open <dialog> — `/` should
  // type a slash there.
  document.addEventListener('keydown', (e) => {
    if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return;
    const tgt = e.target;
    if (tgt && (tgt.matches?.('input, textarea, [contenteditable="true"]') || tgt.isContentEditable)) return;
    // Don't fire when a modal <dialog> is open — the user is engaged
    // with a focused task, not browsing.
    if (modalOverlay.open) return;
    // Auth dialog / add-sheet / share — same logic.
    if (document.querySelector('dialog[open]')) return;
    e.preventDefault();
    if (typeof window.showView === 'function') window.showView('find');
    // Defer focus by a frame so the showView's view-transition
    // animation doesn't snatch focus away first.
    requestAnimationFrame(() => {
      const input = document.getElementById('search-input');
      input?.focus();
      input?.select?.();
    });
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
     MULTI-SELECT (Find tab — Select pill + shift-click + drag-marquee)
     -----------------------------------------------------------------
     Selection model: a Set of stable card keys + an index pointer for
     shift-range. The selection persists across renderNextPage()
     refreshes by reading selectedCardKeys from buildCardElement.
     Action toolbar exposes "Add to Collection" + "Add to Deck" with
     dropdown pickers for designation / target deck.

     IMPORTANT: web cards.json ships `bobaId` (not `id`). Earlier
     versions of this code used `card.id` which is undefined on
     every card — Set ended up with a phantom `undefined` entry, the
     querySelector for `[data-card-id="undefined"]` only matched the
     first card, and only that card got the cyan ring. Always go
     through cardKey() so bobaId is the single source of identity.
  ================================================================ */
  const cardKey = (c) => c?.bobaId || c?.cardNumber || '';
  let selectedCardKeys  = new Set();
  let selectionMode     = false;
  let lastSelectedIndex = -1;

  function syncSelectModeToggle() {
    const t = document.getElementById('multiselect-toggle');
    if (!t) return;
    t.setAttribute('aria-pressed', selectionMode ? 'true' : 'false');
    t.classList.toggle('active', selectionMode);
  }
  function enterSelectionMode() {
    selectionMode = true;
    document.body.classList.add('selection-mode');
    syncSelectModeToggle();
    syncSelectionToolbar();
  }
  function exitSelectionMode() {
    selectionMode = false;
    document.body.classList.remove('selection-mode');
    selectedCardKeys.clear();
    lastSelectedIndex = -1;
    document.querySelectorAll('.card-item--selected')
      .forEach(el => el.classList.remove('card-item--selected'));
    syncSelectModeToggle();
    syncSelectionToolbar();
  }
  function toggleCardSelection(card, index) {
    if (!card) return;
    const key = cardKey(card);
    if (!key) {
      console.warn('[multi-select] toggle skipped — card has no bobaId/cardNumber', card);
      return;
    }
    const wasSelected = selectedCardKeys.has(key);
    if (wasSelected) selectedCardKeys.delete(key);
    else             selectedCardKeys.add(key);
    lastSelectedIndex = index;
    const el = cardGrid.querySelector(`.card-item[data-card-id="${cssEscape(key)}"]`);
    el?.classList.toggle('card-item--selected', !wasSelected);
    syncSelectionToolbar();
  }
  function selectRange(fromIdx, toIdx) {
    const lo = Math.min(fromIdx, toIdx), hi = Math.max(fromIdx, toIdx);
    if (!selectionMode) enterSelectionMode();
    for (let i = lo; i <= hi && i < filteredCards.length; i++) {
      const c = filteredCards[i];
      const key = cardKey(c);
      if (!key) continue;
      selectedCardKeys.add(key);
      const el = cardGrid.querySelector(`.card-item[data-card-id="${cssEscape(key)}"]`);
      el?.classList.add('card-item--selected');
    }
    lastSelectedIndex = toIdx;
    syncSelectionToolbar();
  }
  function syncSelectionToolbar() {
    const bar = document.getElementById('multiselect-toolbar');
    const num = document.getElementById('multiselect-count-num');
    if (!bar || !num) return;
    const n = selectedCardKeys.size;
    num.textContent = String(n);
    bar.hidden = n === 0;
  }
  // CSS.escape polyfill for older Safari — bobaIds contain spaces and
  // other CSS-meaningful chars when used in attribute selectors.
  const cssEscape = (window.CSS && CSS.escape)
    ? (s) => CSS.escape(s)
    : (s) => String(s).replace(/[^a-zA-Z0-9_-]/g, ch => '\\' + ch);

  /* ----------------------------------------------------------------
     Drag-marquee selection — mouse only. Mousedown ANYWHERE on the
     grid (including on a card) starts tracking; if the pointer moves
     >5px before mouseup, it becomes a drag → build a marquee rect
     and suppress the click that would have fired on the start card.
     A plain click (no drag) falls through to the card's normal tap
     handler. Modifier+click (shift/cmd/ctrl) skips the marquee
     entirely so the existing range-select / multi-toggle paths work.
     Touch devices use long-press instead — vertical scroll wins.
  ---------------------------------------------------------------- */
  function initMarqueeSelection() {
    if (!cardGrid) return;

    cardGrid.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      // Modifier+click → let it through to the card's tap handler.
      if (e.shiftKey || e.metaKey || e.ctrlKey || e.altKey) return;

      const startX = e.clientX, startY = e.clientY;
      const startCard = e.target.closest('.card-item');
      let marquee = null;
      let didDrag = false;

      const onMove = (m) => {
        if (!didDrag) {
          const dx = m.clientX - startX, dy = m.clientY - startY;
          if ((dx*dx + dy*dy) <= 25) return;  // 5px threshold
          didDrag = true;
          // Suppress the click that mousedown→mouseup will fire on
          // the start card so the marquee doesn't double as a tap.
          if (startCard) startCard.dataset.suppressNextClick = '1';
          marquee = document.createElement('div');
          marquee.className = 'marquee-rect';
          document.body.appendChild(marquee);
        }
        const x = m.clientX, y = m.clientY;
        const left = Math.min(startX, x), top = Math.min(startY, y);
        const w = Math.abs(x - startX), h = Math.abs(y - startY);
        marquee.style.left = `${left}px`;
        marquee.style.top  = `${top}px`;
        marquee.style.width  = `${w}px`;
        marquee.style.height = `${h}px`;
        // Once we're dragging, suppress browser text/image selection.
        m.preventDefault();
      };
      const onUp = () => {
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
        if (!didDrag) return;  // plain click — card's handler runs
        const rect = marquee.getBoundingClientRect();
        marquee.remove();
        marquee = null;
        if (rect.width < 4 && rect.height < 4) return;
        if (!selectionMode) enterSelectionMode();
        cardGrid.querySelectorAll('.card-item').forEach(el => {
          const r = el.getBoundingClientRect();
          if (rectsIntersect(rect, r)) {
            const key = el.dataset.cardId;  // already bobaId via cardKey()
            if (key && !selectedCardKeys.has(key)) {
              selectedCardKeys.add(key);
              el.classList.add('card-item--selected');
              const idx = parseInt(el.dataset.cardIndex, 10);
              if (!isNaN(idx)) lastSelectedIndex = idx;
            }
          }
        });
        syncSelectionToolbar();
      };
      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
    });
  }
  function rectsIntersect(a, b) {
    return !(a.right < b.left || a.left > b.right || a.bottom < b.top || a.top > b.bottom);
  }

  /* ----------------------------------------------------------------
     Selection toolbar wiring — Add to Collection (designation menu),
     Add to Deck (deck-list modal), Clear.
  ---------------------------------------------------------------- */
  function initMultiselectToolbar() {
    const addColl = document.getElementById('multiselect-add-collection');
    const addDeck = document.getElementById('multiselect-add-deck');
    const wall    = document.getElementById('multiselect-wall');
    const clear   = document.getElementById('multiselect-clear');
    const toggle  = document.getElementById('multiselect-toggle');
    addColl?.addEventListener('click', openDesignationMenu);
    addDeck?.addEventListener('click', openDeckPicker);
    wall?.addEventListener('click', openWallFromSelection);
    clear?.addEventListener('click', exitSelectionMode);
    // Explicit "Select" pill — for users who don't discover the
    // shift-click / drag-marquee / long-press gestures.
    toggle?.addEventListener('click', () => {
      if (selectionMode) {
        exitSelectionMode();
        toggle.setAttribute('aria-pressed', 'false');
        toggle.classList.remove('active');
      } else {
        enterSelectionMode();
        toggle.setAttribute('aria-pressed', 'true');
        toggle.classList.add('active');
      }
    });
  }
  function getSelectedCardObjects() {
    // Resolve via the canonical bobaId map, NOT by filtering
    // filteredCards. A user may select 5 cards, then type a query
    // that filters the grid down — selectedCardKeys persists, but
    // the prior pattern only returned the survivors of the new
    // filter. Now all selected cards round-trip regardless of the
    // current filter state.
    const out = [];
    for (const key of selectedCardKeys) {
      const card = cardsByBobaId.get(String(key))
                || cardsByNumber.get(String(key))?.[0];
      if (card) out.push(card);
    }
    return out;
  }
  function openDesignationMenu(e) {
    if (!Auth.isAuthenticated()) {
      Auth.open();
      return;
    }
    const cards = getSelectedCardObjects();
    if (!cards.length) return;
    const choices = [
      ['personal',  'Personal'],
      ['for_sale',  'For Sale'],
      ['for_trade', 'For Trade'],
      ['wanted',    'Wanted'],
      ['grails',    'Grails'],
    ];
    showPopoverMenu({
      anchor: e.currentTarget,
      title:  `Add ${cards.length} card${cards.length===1?'':'s'} to…`,
      items:  choices.map(([key, label]) => ({
        label,
        onSelect: () => bulkAddToCollection(cards, key),
      })),
    });
  }
  async function bulkAddToCollection(cards, designation) {
    // Parallelize via Promise.allSettled — previous for-await loop
    // serialized N HTTP round trips, so a 50-card bulk add took
    // 50× longest-RTT. Worst case: 100% concurrent in flight, which
    // Cloudflare + Supabase handle fine at this scale.
    const results = await Promise.allSettled(
      cards.map(card => API.collectionAdd({
        card_number: card.cardNumber,
        boba_id:     cardKey(card),
        hero:        card.hero || null,
        name:        card.name || null,
        element:     card.element || null,
        treatment:   card.treatment || null,
        variation:   card.variation || null,
        designation,
      }))
    );
    const added  = results.filter(r => r.status === 'fulfilled').length;
    const failed = results.length - added;
    // Single-card path quotes the card name so users see WHAT was
    // added; bulk path stays terse. If everything failed, mention the
    // most common cause (sign-out) so the user knows what to fix.
    const dLabel = designation.replace('_', ' ');
    let msg;
    if (added === 0) {
      msg = `Couldn't add — sign in and retry.`;
    } else if (cards.length === 1) {
      const c = cards[0];
      msg = `Added "${c.hero || c.name}" to ${dLabel}`;
    } else {
      msg = `Added ${added} cards to ${dLabel}${failed ? ` · ${failed} failed` : ''}`;
    }
    showToast(msg);
    exitSelectionMode();
  }
  /// Wall the currently-selected catalog cards. No auth required —
  /// rendering doesn't write anywhere. Title defaults to count.
  function openWallFromSelection() {
    const cards = getSelectedCardObjects();
    if (!cards.length) return;
    if (!window.Collection?.openCardsWallSheet) return;
    window.Collection.openCardsWallSheet({
      title: `${cards.length} card${cards.length === 1 ? '' : 's'}`,
      cards,
    });
    // Don't exit selection mode — the user might want to download
    // the wall AND continue selecting / adding to collection. They
    // can hit Clear when done.
  }

  async function openDeckPicker(e) {
    if (!Auth.isAuthenticated()) {
      Auth.open();
      return;
    }
    const cards = getSelectedCardObjects();
    if (!cards.length) return;
    const anchor = e.currentTarget;
    let decks;
    try { decks = await API.deckList(); } catch (err) {
      showToast('Could not load your decks. ' + (err?.message || ''));
      return;
    }
    if (!decks.length) {
      showToast('No saved decks yet. Build one in the Decks tab first.');
      return;
    }
    showPopoverMenu({
      anchor,
      title: `Add ${cards.length} card${cards.length===1?'':'s'} to deck…`,
      items: decks.map(d => ({
        label:    d.name,
        sublabel: d.format,
        onSelect: () => bulkAddToDeck(cards, d),
      })),
    });
  }
  async function bulkAddToDeck(cards, deck) {
    let existing;
    try { existing = await API.deckLoad(deck.id); } catch (e) {
      showToast('Could not load that deck. ' + (e?.message || '')); return;
    }
    const existingIds = new Set(existing.map(r => r.boba_id));
    const merged = existing.map(r => ({ bobaId: r.boba_id, cardType: r.card_type }));
    let added = 0, skipped = 0;
    for (const card of cards) {
      const key = cardKey(card);
      if (!key) { skipped++; continue; }
      if (existingIds.has(key)) { skipped++; continue; }
      const cardType = card.cardType === 'Hero'   ? 'hero'
                     : card.cardType === 'HotDog' ? 'hot_dog'
                     : card.isBonusPlay           ? 'bonus_play'
                     :                              'play';
      merged.push({ bobaId: key, cardType });
      existingIds.add(key);
      added++;
    }
    try {
      await API.deckSave(deck.id, deck.name, deck.format, merged);
      showToast(`Added ${added} card${added===1?'':'s'} to ${deck.name}${skipped?` · ${skipped} duplicate${skipped===1?'':'s'} skipped`:''}`);
      exitSelectionMode();
    } catch (e) {
      showToast('Could not save deck. ' + (e?.message || ''));
    }
  }
  // Reuse the existing toast helper if present, else fall back to alert.
  function showToast(msg) {
    if (typeof window.showQuickAddToast === 'function') return window.showQuickAddToast(msg);
    if (typeof window.toast === 'function') return window.toast(msg);
    // Minimal inline toast — appears bottom-center for 2.5s.
    let t = document.getElementById('app-toast');
    if (!t) {
      t = document.createElement('div');
      t.id = 'app-toast';
      t.className = 'app-toast';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.classList.add('visible');
    clearTimeout(showToast._timer);
    showToast._timer = setTimeout(() => t.classList.remove('visible'), 2500);
  }
  // Expose for sibling modules (collection.js, practice.js). Without
  // this, `window.showToast` was undefined and the tick-68 +
  // tick-104 wirings silently fell through to alert(). Tick 103
  // discovered the missing export.
  window.showToast = showToast;
  // Escape from selection mode via the keyboard.
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && selectionMode) exitSelectionMode();
  });

  /* ================================================================
     PER-TAB GRID DENSITY (parity with iOS @AppStorage column counts)
     localStorage keys match iOS so a user with both platforms
     gets the same density preference where possible. Web only has
     a Find grid today; Decks/Collection picker hooks land when
     those views get rebuilt to use the canonical .card-grid.
  ================================================================ */
  function initGridColsPicker() {
    const KEY = 'bp_findGridDensity_v1';
    const VALID = ['s', 'm', 'l'];
    let density = localStorage.getItem(KEY) || '';  // '' = responsive default
    const picker = document.querySelector('.grid-cols-picker');
    if (!picker) return;
    const apply = () => {
      if (VALID.includes(density)) {
        document.body.dataset.findDensity = density;
      } else {
        delete document.body.dataset.findDensity;
      }
      picker.querySelectorAll('.grid-cols-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.density === density);
      });
    };
    picker.querySelectorAll('.grid-cols-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const next = btn.dataset.density;
        // Click the active one again to return to responsive default.
        density = (density === next) ? '' : next;
        if (density) localStorage.setItem(KEY, density);
        else         localStorage.removeItem(KEY);
        apply();
      });
    });
    apply();
  }

  /* ================================================================
     OFFLINE INDICATOR (DESIGN.md §6.7 / iOS BOBAOfflinePill parity)
     Subtle pill in the mobile header; visible only when
     navigator.onLine is false. Re-fires on online/offline events so
     intermittent connectivity drops surface immediately.
  ================================================================ */
  function syncOfflinePill() {
    const pill = document.getElementById('offline-pill');
    if (!pill) return;
    pill.hidden = navigator.onLine !== false;
  }
  window.addEventListener('online',  syncOfflinePill);
  window.addEventListener('offline', syncOfflinePill);

  /* ================================================================
     INITIALIZATION
  ================================================================ */
  async function init() {
    syncOfflinePill();
    initGridColsPicker();
    initMarqueeSelection();
    initMultiselectToolbar();
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
    // v2.275 — runtime image-replacement overrides (admin uploads
    // and admin-approved mod uploads applied via boba-mod-merge).
    API.loadAppliedImageOverrides().then(maps => {
      if (maps && (maps.byBobaId.size || maps.byCardNumber.size)) {
        applyImageOverridesMap(maps);
        applyFilters(true);
      }
    });

    loadingState.hidden = true;
    buildShowcaseFilters();
    buildElementFilters();
    buildSetFilter();
    buildReleaseFilter();

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
      } else {
        // Broken / outdated deep-link — surface a toast so the user
        // knows the page loaded but the target card couldn't be
        // resolved. Without this, the URL just sat there and the
        // user wondered whether the link worked.
        showToast(`Couldn't find card "${params.get('card')}"`);
        // Strip the bad card param so a refresh doesn't re-trigger
        // the same toast forever.
        const cleaned = new URLSearchParams(params);
        cleaned.delete('card');
        cleaned.delete('hero');
        cleaned.delete('treatment');
        const qs = cleaned.toString();
        history.replaceState(
          { view: currentView },
          '',
          location.pathname + (qs ? '?' + qs : '')
        );
      }
    }

    // Public collection: ?u=ben (or /u/ben → 404 redirect → ?u=ben)
    // mounts the read-only public-collection view.
    if (params.has('u')) {
      const handle = String(params.get('u') || '').toLowerCase();
      showView('public-collection', true);
      renderPublicCollection(handle);
    }
  }

  /* ================================================================
     PUBLIC COLLECTION VIEW
     Read-only render of someone else's collection at /u/{username}.
     No auth required — relies on the get_public_collection RPC,
     which returns empty for nonexistent or private profiles.
  ================================================================ */
  async function renderPublicCollection(handle) {
    const titleEl    = document.getElementById('public-collection-title');
    const subtitleEl = document.getElementById('public-collection-subtitle');
    const avatarEl   = document.getElementById('public-collection-avatar');
    const gridEl     = document.getElementById('public-collection-grid');
    const emptyEl    = document.getElementById('public-collection-empty');
    if (!titleEl || !gridEl) return;

    titleEl.textContent = `@${handle}`;
    subtitleEl.textContent = 'Loading…';
    // Per-handle tab title so a bookmarked /u/ben page reads as
    // "@ben · BOBA Playbook" not the generic "Public Collection".
    document.title = `@${handle} · BOBA Playbook`;

    // Share button — wired once per render via { once: true }. Uses
    // the canonical URL form (/u/{handle}) so the recipient lands
    // on the same page even if the original opener used ?u={handle}.
    const shareBtn = document.getElementById('public-collection-share');
    shareBtn?.addEventListener('click', () => {
      const url = `${location.origin}/u/${handle}`;
      window.bobaShareTarget?.({
        title: `@${handle} on BOBA Playbook`,
        text:  `Check out @${handle}'s BOBA card collection`,
        url,
      }, shareBtn);
    }, { once: true });
    updateOpenGraphMeta({
      title: `@${handle} · BOBA Playbook`,
      description: `Public BoBA card collection by @${handle}.`,
      url: `${location.origin}/u/${handle}`,
    });
    gridEl.innerHTML = '';
    emptyEl.hidden = true;

    // Owner avatar — render from get_public_profile in parallel with
    // the cards fetch so the header doesn't lag the grid.
    if (avatarEl) {
      // Reset to silhouette while we resolve.
      avatarEl.innerHTML =
        '<svg viewBox="0 0 24 24" fill="currentColor" width="32" height="32">' +
          '<path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-5.33 0-8 2.67-8 4v1h16v-1c0-1.33-2.67-4-8-4z"/>' +
        '</svg>';
      API.fetchPublicProfile(handle).then(profile => {
        if (!profile) return;  // private or nonexistent — silhouette stays
        const url = profile.avatar_url || profile.discord_avatar_url;
        if (url) {
          avatarEl.innerHTML =
            `<img src="${escHtml(url)}" alt="" class="public-collection-avatar-img" referrerpolicy="no-referrer">`;
        }
      }).catch(() => { /* offline / RPC error — silhouette stays */ });
    }

    let rows = [];
    try {
      rows = await API.fetchPublicCollection(handle);
    } catch (err) {
      console.error('public collection fetch failed:', err);
      subtitleEl.textContent = 'Failed to load — please refresh.';
      return;
    }

    if (!rows.length) {
      subtitleEl.textContent = '';
      // Distinguish "private / unknown handle" from "public but
      // empty collection". `fetchPublicProfile` returns a row only
      // when the handle exists AND sharing is on — use it to
      // pick the right empty copy. We fetch it twice (also above
      // for the avatar) but the call is cheap + cached server-side.
      try {
        const profile = await API.fetchPublicProfile(handle);
        if (profile) {
          // Profile exists + public — they just haven't added cards.
          emptyEl.innerHTML = `<h2 style="color: var(--boba-orange); margin: 0 0 0.5rem 0;">No cards yet.</h2><p style="margin: 0; color: rgba(255,255,255,0.5);">@${escHtml(handle)} hasn't added any cards to their public collection.</p>`;
        }
      } catch { /* offline — fall through to default copy */ }
      emptyEl.hidden = false;
      return;
    }

    // Resolve each user_card row to a catalog card via boba_id (preferred)
    // or card_number (fallback). Skip rows whose boba_id no longer
    // exists in the catalog.
    const resolved = rows.map(row => {
      const card = (row.boba_id && cardsByBobaId.get(String(row.boba_id)))
                || cardsByNumber.get(String(row.card_number))?.[0];
      return card ? { card, row } : null;
    }).filter(Boolean);

    subtitleEl.textContent = `${resolved.length} card${resolved.length === 1 ? '' : 's'}`;

    // Reuse buildCardElement so the public-collection grid looks
    // identical to the Find search grid (treatment classes, hover,
    // accessibility attrs all inherited).
    const fragment = document.createDocumentFragment();
    resolved.forEach(({ card }, i) => {
      fragment.appendChild(buildCardElement(card, i));
    });
    gridEl.appendChild(fragment);

    // Wall button — visitor renders the resolved catalog cards
    // through the shared canvas Wall pipeline (collection.js
    // openCardsWallSheet). Requires the catalog cards which are
    // local to this render, so wire HERE not at header-mount time.
    const wallBtn = document.getElementById('public-collection-wall');
    if (wallBtn) {
      const cards = resolved.map(r => r.card).filter(c => c?.imageFile);
      wallBtn.hidden = cards.length === 0;
      wallBtn.onclick = () => {
        if (window.Collection?.openCardsWallSheet) {
          window.Collection.openCardsWallSheet({
            title: `@${handle} on BOBA Playbook`,
            cards,
            context: 'public',
          });
        }
      };
    }

    // Unauth visitor CTA — gentle "make your own BOBA collection"
    // pitch below the grid. Hidden for signed-in users (they
    // already have BOBA Playbook). Wired once per render so a
    // visitor signing in mid-view also drops the CTA.
    wirePublicCollectionCTA();
  }

  function wirePublicCollectionCTA() {
    const cta = document.getElementById('public-collection-cta');
    if (!cta) return;
    const signedIn = !!(typeof Auth !== 'undefined' && Auth.isAuthenticated?.());
    cta.hidden = signedIn;
    if (signedIn) return;
    cta.querySelector('#public-collection-cta-explore')
      ?.addEventListener('click', () => showView('search'), { once: true });
    cta.querySelector('#public-collection-cta-signin')
      ?.addEventListener('click', () => Auth.open(), { once: true });
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
          const overrideId = await API.submitImageOverride(
            card.cardNumber, imageAction, storagePath, correctionStatus, card.bobaId ?? null
          );
          // Apply the removal immediately to in-memory card objects so the grid
          // reflects the change without a page reload.
          if (imageAction === 'remove') {
            applyImageRemovals(new Set([String(card.cardNumber)]));
          }
          // v2.275 — admin replace: chain to the boba-mod-merge Worker so
          // the new image lands in R2 + CF cache purges + applied_image_file
          // is set on the row immediately. Then refresh the runtime override
          // map so subsequent renders pick up the new filename.
          if (imageAction === 'replace' && isAdmin && overrideId) {
            try {
              await API.applyImageOverride(overrideId);
              if (typeof window.refreshAppliedImageOverrides === 'function') {
                await window.refreshAppliedImageOverrides();
              }
            } catch (mergeErr) {
              console.warn('Immediate merge failed (daily cron will sweep):', mergeErr);
            }
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
