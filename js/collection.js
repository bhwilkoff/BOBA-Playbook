/**
 * Collection — BOBA Playbook
 * Manages user collection state and renders the Collection + Profile views.
 * Must be loaded after api.js and auth.js.
 */
const Collection = (() => {
  'use strict';

  let _cards         = [];
  let _activeTab     = 'personal';
  let _addCard       = null;  // card being added in the add sheet
  let _cardLookup    = null;  // set by app.js after card catalog loads: cardNumber → Card
  let _bobaIdLookup  = null;  // set by app.js after card catalog loads: bobaId → Card
  let _variantLookup = null;  // set by app.js: (hero, excludeBobaId) => Card[]

  // Collection detail overlay state
  let _detailNum   = null;    // card_number currently shown in detail
  let _detailState = 'view';  // 'view' | 'edit'
  let _editEntry   = null;    // user_cards row being edited

  const DESIGNATIONS = [
    { key: 'personal',  label: 'Personal'  },
    { key: 'for_sale',  label: 'For Sale'  },
    { key: 'for_trade', label: 'For Trade' },
    { key: 'wanted',    label: 'Wanted'    },
    { key: 'grails',    label: 'Grails'    },
  ];

  // Paginated render — same pattern as Find's PAGE_SIZE. 60 groups
  // per page keeps the initial paint snappy even at 5000+ user_cards.
  const _COLLECTION_PAGE_SIZE = 60;
  // IntersectionObserver + state for the paginated Collection grid.
  // Re-created on every renderCollectionView pass.
  let _collectionPaginator = null;

  // Collection-tab search text. Parity with iOS DESIGN.md §8.4
  // `.searchable` on Collection. Lower-cased for case-insensitive
  // substring matching against hero / name / cardNumber / treatment.
  // Persisted across designation tab switches; cleared on sign-out
  // (in clear()) so a stale query doesn't leak across users.
  let _collectionSearchText = '';
  let _collectionSearchTimer = null;
  const _COLLECTION_SEARCH_DEBOUNCE = 220;

  /// Does an activeCards row match the current search query? Case-
  /// insensitive substring across hero, name, cardNumber, treatment.
  /// Empty query short-circuits to true.
  function _matchesCollectionSearch(userCardRow, catalogCard) {
    const q = _collectionSearchText;
    if (!q) return true;
    const haystack = [
      catalogCard?.hero,
      catalogCard?.name,
      catalogCard?.cardNumber,
      catalogCard?.treatment,
      userCardRow?.notes,
    ].filter(Boolean).join(' ').toLowerCase();
    return haystack.includes(q);
  }

  /* ================================================================
     DATA
  ================================================================ */

  async function load() {
    try {
      _cards = await API.collectionFetch();
    } catch (e) {
      console.error('Collection load error:', e);
      _cards = [];
    }
    renderCollectionView();
    renderProfileView();
  }

  function clear() {
    _cards = [];
    // Reset per-user caches so a stale previous-user record can't
    // leak into the next session. Mirrors the Android pattern in
    // `feedback_viewmodel_reset_on_auth_change`.
    _customRainbowsById = {};
    _editingRainbow = null;
    _draftCriteria = {};
    _rainbowMatchCache.clear();
    _rainbowMatchCacheCatalogLen = 0;
    _collectionSearchText = '';
    clearTimeout(_collectionSearchTimer);
    _collectionSearchTimer = null;
    if (_collectionPaginator) {
      try { _collectionPaginator.disconnect(); } catch {}
      _collectionPaginator = null;
    }
    renderCollectionView();
    renderProfileView();
  }

  /* ================================================================
     COLLECTION VIEW
  ================================================================ */

  function renderCollectionView() {
    const view = document.getElementById('view-collection');
    if (!view) return;

    if (!Auth.isAuthenticated()) {
      view.innerHTML = `
        <div class="view-inner auth-gate">
          <h2 class="view-heading">My Collection</h2>
          <p class="view-subtitle">Sign in to track your BOBA card collection and portfolio value.</p>
          <button class="btn-primary" id="collection-signin-btn">Sign In / Create Account</button>
        </div>`;
      view.querySelector('#collection-signin-btn')
        ?.addEventListener('click', () => Auth.open());
      return;
    }

    // Single-pass aggregation: counts per designation + cost/value
    // totals for the chosen stats scope. Replaces 4+ separate
    // .filter() passes over _cards on every render — meaningful at
    // 500+ rows, brutal at 5000+. See audit 2026-05-20 tick 30.
    const isOwned = c => c.designation === 'personal'
                      || c.designation === 'for_sale'
                      || c.designation === 'for_trade';
    const tabCounts = Object.create(null);
    let ownedCount = 0;
    let activeCount = 0;
    let activeCost = 0, activeValue = 0;
    let ownedCost  = 0, ownedValue  = 0;
    const activeKeys = new Set();
    const ownedKeys  = new Set();
    for (const c of _cards) {
      tabCounts[c.designation] = (tabCounts[c.designation] || 0) + 1;
      const isActive = c.designation === _activeTab;
      const owned    = isOwned(c);
      if (isActive) {
        activeCount++;
        if (c.purchase_price)  activeCost  += Number(c.purchase_price);
        if (c.estimated_value) activeValue += Number(c.estimated_value);
        activeKeys.add(c.boba_id || c.card_number);
      }
      if (owned) {
        ownedCount++;
        if (c.purchase_price)  ownedCost  += Number(c.purchase_price);
        if (c.estimated_value) ownedValue += Number(c.estimated_value);
        ownedKeys.add(c.boba_id || c.card_number);
      }
    }
    const tabCount = key => tabCounts[key] || 0;
    const ownedCards = _cards.filter(isOwned);  // still need this array for rainbow hydration below
    const totalCostBasis      = _totalsMode === 'filter' ? activeCost  : ownedCost;
    const totalEstimatedValue = _totalsMode === 'filter' ? activeValue : ownedValue;
    const uniqueNums          = (_totalsMode === 'filter' ? activeKeys  : ownedKeys).size;
    const scopeCount          = _totalsMode === 'filter' ? activeCount : ownedCount;
    const isFilter = _totalsMode === 'filter';
    const ownedLabel = isFilter ? 'In Filter' : 'Owned';
    const valueLabel = isFilter ? 'Filter Est. Value' : 'Est. Value';
    const paidLabel  = isFilter ? 'Filter Paid' : 'Total Paid';

    const tabsHtml = DESIGNATIONS.map(d => `
      <button class="desig-tab${_activeTab === d.key ? ' active' : ''}"
              data-tab="${d.key}" role="tab" aria-selected="${_activeTab === d.key}">
        ${esc(d.label)}
        <span class="desig-tab-count">${tabCount(d.key)}</span>
      </button>`).join('');

    // Designation filter + optional search filter (iOS DESIGN.md §8.4
    // `.searchable` parity, web tick 34). Search runs against catalog
    // metadata (hero / name / cardNumber / treatment) + the row's notes.
    const activeCards = _cards.filter(c => {
      if (c.designation !== _activeTab) return false;
      if (!_collectionSearchText) return true;
      const cat = (_bobaIdLookup && c.boba_id)
        ? _bobaIdLookup(c.boba_id)
        : (_cardLookup ? _cardLookup(c.card_number) : null);
      return _matchesCollectionSearch(c, cat);
    });
    // Group by bobaId (or cardNumber for legacy rows) so multiple physical
    // copies render as a single stack with a quantity badge — mirrors the
    // iOS layout and matches the way collectors think about their binders.
    const groupKey = c => c.boba_id || c.card_number;
    const groups = activeCards.reduce((acc, c) => {
      const k = groupKey(c);
      (acc[k] = acc[k] || []).push(c);
      return acc;
    }, {});
    const groupArray = Object.values(groups);
    const sortedGroups = sortCollectionGroups(groupArray);
    // Paginated render — match Find's `PAGE_SIZE` pattern. Big
    // collections (1k+ groups) used to emit every cell synchronously
    // into a single innerHTML, causing visible jank on tab switch.
    // Now: emit first page, observer below appends next page on
    // scroll. Tab switch / sort change re-renders from page 1.
    const initialPage = sortedGroups.slice(0, _COLLECTION_PAGE_SIZE);
    const desigLabel = DESIGNATIONS.find(d => d.key === _activeTab)?.label;
    // Brand-voice empty state with a productive next-action
    // (universal-feature-states skill — empty states must invite action,
    // not just announce absence). Per-designation copy mirrors what the
    // user is most likely to do next. Search-empty branches separately
    // so the CTA is "Clear search," not "Go to Find."
    const isSearchEmpty = sortedGroups.length === 0 && !!_collectionSearchText;
    const emptyCopyByDesig = {
      personal:  { headline: 'No personal cards yet',  body: 'Scan a card or use Quick Add from the Find tab to start your stack.' },
      for_sale:  { headline: 'Nothing for sale yet',   body: 'Mark a card from your Personal stack to start moving it.' },
      for_trade: { headline: 'Nothing for trade yet',  body: 'Flag a card to find a trading partner once trading launches.' },
      wanted:    { headline: 'No wanted cards yet',    body: 'Flag the cards you’re chasing — start with the ones at the top of your list.' },
      grails:    { headline: 'No grails yet',          body: 'Mark the cards you’d cross a state line for.' },
    };
    const emptyCopy = emptyCopyByDesig[_activeTab]
      || { headline: `No cards in ${esc(desigLabel)} yet`, body: '' };
    const emptyHtml = isSearchEmpty
      ? `<div class="collection-empty collection-empty-search">
           <p class="collection-empty-headline">No cards match “${esc(_collectionSearchText)}”</p>
           <p class="collection-empty-body">Try a different search term or clear the box to see every card in ${esc(desigLabel)}.</p>
           <button type="button" class="btn-ghost-sm collection-empty-clear" data-action="clear-collection-search">Clear search</button>
         </div>`
      : `<div class="collection-empty">
           <p class="collection-empty-headline">${esc(emptyCopy.headline)}</p>
           ${emptyCopy.body ? `<p class="collection-empty-body">${esc(emptyCopy.body)}</p>` : ''}
           <button type="button" class="btn-ghost-sm collection-empty-cta" data-action="go-to-find">Browse Find</button>
         </div>`;
    const listHtml = sortedGroups.length === 0
      ? emptyHtml
      : initialPage.map(buildCollectionCardHtml).join('');

    view.innerHTML = `
      <div class="collection-view">
        <div class="collection-header">
          <h2 class="view-heading">My Collection</h2>
          <div class="collection-stats-bar">
            <div class="cstat">
              <!-- Tick 413 — locale-format the counts (iOS tick 412 +
                   Android tick 359 pattern). Serious collectors hit
                   1,000+ cards; "1,234" reads cleaner than "1234". -->
              <span class="cstat-val">${scopeCount.toLocaleString()}</span>
              <span class="cstat-label">${esc(ownedLabel)}</span>
            </div>
            <div class="cstat">
              <span class="cstat-val">${uniqueNums.toLocaleString()}</span>
              <span class="cstat-label">Unique Cards</span>
            </div>
            ${totalCostBasis > 0 ? `
            <div class="cstat">
              <span class="cstat-val">$${totalCostBasis.toFixed(2)}</span>
              <span class="cstat-label">${esc(paidLabel)}</span>
            </div>` : ''}
            ${totalEstimatedValue > 0 ? `
            <div class="cstat">
              <span class="cstat-val">$${totalEstimatedValue.toFixed(2)}</span>
              <span class="cstat-label">${esc(valueLabel)}</span>
            </div>` : ''}
          </div>
          <div class="collection-totals-toggle" role="radiogroup" aria-label="Show totals for">
            <label class="collection-totals-label">Totals:</label>
            <button class="collection-totals-btn${_totalsMode==='collection'?' active':''}"
                    data-totals-mode="collection"
                    role="radio"
                    aria-checked="${_totalsMode==='collection'}">Collection</button>
            <button class="collection-totals-btn${_totalsMode==='filter'?' active':''}"
                    data-totals-mode="filter"
                    role="radio"
                    aria-checked="${_totalsMode==='filter'}">Filter</button>
          </div>
        </div>
        <div class="desig-tabs" role="tablist" aria-label="Collection designations">
          ${tabsHtml}
        </div>
        <div class="collection-toolbar">
          <div class="collection-search-wrap">
            <input type="search" class="collection-search-input" id="collection-search"
                   placeholder="Search your collection…"
                   autocomplete="off" autocorrect="off" spellcheck="false"
                   aria-label="Search this designation"
                   value="${esc(_collectionSearchText)}" />
            <button type="button" class="collection-search-clear" id="collection-search-clear"
                    aria-label="Clear collection search" ${_collectionSearchText ? '' : 'hidden'}>
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor"
                   stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M18 6 6 18M6 6l12 12"/>
              </svg>
            </button>
          </div>
          <label class="collection-sort-label" for="collection-sort">Sort</label>
          <select class="collection-sort-select" id="collection-sort" aria-label="Sort collection">
            <option value="added_desc"${_collectionSort==='added_desc'?' selected':''}>Recently Added</option>
            <option value="added_asc"${_collectionSort==='added_asc'?' selected':''}>Oldest Added</option>
            <option value="price_desc"${_collectionSort==='price_desc'?' selected':''}>Market Value: High → Low</option>
            <option value="price_asc"${_collectionSort==='price_asc'?' selected':''}>Market Value: Low → High</option>
            <option value="paid_desc"${_collectionSort==='paid_desc'?' selected':''}>Paid: High → Low</option>
            <option value="paid_asc"${_collectionSort==='paid_asc'?' selected':''}>Paid: Low → High</option>
            <option value="cost_asc"${_collectionSort==='cost_asc'?' selected':''}>Hot Dog Cost: Low → High</option>
            <option value="cost_desc"${_collectionSort==='cost_desc'?' selected':''}>Hot Dog Cost: High → Low</option>
            <option value="name_asc"${_collectionSort==='name_asc'?' selected':''}>Name A → Z</option>
            <option value="name_desc"${_collectionSort==='name_desc'?' selected':''}>Name Z → A</option>
          </select>
          <!-- Wall view — render the active designation as a single
               shareable image. Parity with iOS CollectionWallSheet
               (DESIGN.md §8.4 + §8.8; DECISIONS.md #036 lifted gate). -->
          <button class="collection-wall-btn" id="collection-wall-btn"
                  type="button" aria-label="Generate wall image"
                  ${sortedGroups.length === 0 ? 'disabled' : ''}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                 width="14" height="14" aria-hidden="true">
              <rect x="3" y="3" width="7" height="7"/>
              <rect x="14" y="3" width="7" height="7"/>
              <rect x="3" y="14" width="7" height="7"/>
              <rect x="14" y="14" width="7" height="7"/>
            </svg>
            Wall
          </button>
        </div>
        <div class="collection-card-list" id="collection-card-list" role="list">
          ${listHtml}
        </div>
        <div class="collection-load-sentinel" id="collection-load-sentinel" aria-hidden="true"></div>
        <!-- CUSTOM RAINBOWS — read-only display of user-defined
             collecting goals stored in user_custom_rainbows. Hydrates
             async on first view-render. iOS shipped v2.219-v2.221;
             web parity ships here (web tick 7). Editor is iOS-only
             today; web users can view + see progress. -->
        <section class="custom-rainbows-section" id="custom-rainbows-section">
          <div class="custom-rainbows-heading-row">
            <h3 class="custom-rainbows-heading">Custom Rainbows</h3>
            <button type="button" class="custom-rainbow-new-btn" id="custom-rainbow-new-btn"
                    aria-label="Create a new custom rainbow" title="New rainbow">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor"
                   stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <line x1="12" y1="5" x2="12" y2="19"/>
                <line x1="5" y1="12" x2="19" y2="12"/>
              </svg>
              <span>New rainbow</span>
            </button>
          </div>
          <div class="custom-rainbows-list" id="custom-rainbows-list"></div>
          <div class="custom-rainbows-empty" id="custom-rainbows-empty" hidden>
            No custom rainbows yet — tap <strong>New rainbow</strong> to set a collecting goal.
          </div>
        </section>
        <!-- HERO AUTO RAINBOWS — one synthesized rainbow per hero
             the user owns at least one card of. Mirrors iOS
             RainbowDetailView Kind.hero(_) pattern: every printing
             of that hero across all sets / treatments is the
             "set to collect." Sorted by completion % descending. -->
        <section class="custom-rainbows-section" id="hero-rainbows-section" hidden>
          <h3 class="custom-rainbows-heading">Rainbows by Hero</h3>
          <div class="custom-rainbows-list" id="hero-rainbows-list"></div>
        </section>
      </div>`;

    view.querySelectorAll('.desig-tab').forEach(tab => {
      tab.addEventListener('click', () => {
        _activeTab = tab.dataset.tab;
        renderCollectionView();
      });
    });

    view.querySelector('#collection-sort')?.addEventListener('change', (e) => {
      setCollectionSort(e.target.value);
    });

    // Search input — debounced re-render matching Find's pattern.
    // Restores focus + caret position after re-render so typing isn't
    // interrupted. Selection range survives via the input's value
    // round-trip + a manual setSelectionRange.
    const searchEl = view.querySelector('#collection-search');
    const searchClearEl = view.querySelector('#collection-search-clear');
    if (searchEl) {
      // Restore focus if the user was typing across a render (e.g.
      // a previous keystroke triggered re-render before the next).
      if (document.activeElement?.id === 'collection-search-prev-focus') {
        searchEl.focus();
      }
      // Toggle the clear-× immediately on every keystroke so the
      // affordance feels instant even though the search filter is
      // debounced. Hidden when the input is empty.
      searchEl.addEventListener('input', (e) => {
        const raw  = e.target.value || '';
        const next = raw.trim().toLowerCase();
        if (searchClearEl) searchClearEl.hidden = !raw;
        clearTimeout(_collectionSearchTimer);
        _collectionSearchTimer = setTimeout(() => {
          if (next === _collectionSearchText) return;
          _collectionSearchText = next;
          // Mark this input as the focus target so the next render
          // restores focus. Doesn't actually change the ID; just a
          // marker the re-render can read.
          const wasActive = document.activeElement === searchEl;
          const caret = searchEl.selectionStart;
          renderCollectionView();
          if (wasActive) {
            const newEl = document.getElementById('collection-search');
            if (newEl) {
              newEl.focus();
              try { newEl.setSelectionRange(caret, caret); } catch {}
            }
          }
        }, _COLLECTION_SEARCH_DEBOUNCE);
      });
      // Clear-× wires immediate clear + re-render (no debounce — the
      // user explicitly asked to clear). Refocuses the input so the
      // user can keep typing without re-tapping.
      searchClearEl?.addEventListener('click', () => {
        searchEl.value = '';
        searchClearEl.hidden = true;
        clearTimeout(_collectionSearchTimer);
        if (_collectionSearchText) {
          _collectionSearchText = '';
          renderCollectionView();
          // After re-render, refocus the new input element by id.
          document.getElementById('collection-search')?.focus();
        } else {
          searchEl.focus();
        }
      });
    }

    view.querySelector('#collection-wall-btn')?.addEventListener('click', () => {
      openWallSheet({
        designation: _activeTab,
        cards: sortedGroups.map(g => g[0]),  // one card per group (representative)
      });
    });

    // Empty-state CTAs (per-designation productive action). Wired only
    // when the empty markup actually rendered. "Browse Find" routes to
    // the Find view; "Clear search" wipes the in-collection search
    // term + re-renders so the unfiltered designation grid surfaces.
    view.querySelector('[data-action="go-to-find"]')?.addEventListener('click', () => {
      if (typeof window.showView === 'function') window.showView('find');
    });
    view.querySelector('[data-action="clear-collection-search"]')?.addEventListener('click', () => {
      _collectionSearchText = '';
      renderCollectionView();
      document.getElementById('collection-search')?.focus();
    });

    // Paginated render: attach IntersectionObserver on the sentinel to
    // append the next page when it scrolls into view. Re-created on
    // every render (so prior observer is GC'd when its sentinel is
    // overwritten). Skips entirely if everything fits in page 1.
    if (_collectionPaginator) {
      try { _collectionPaginator.disconnect(); } catch {}
      _collectionPaginator = null;
    }
    if (sortedGroups.length > _COLLECTION_PAGE_SIZE) {
      const sentinel = view.querySelector('#collection-load-sentinel');
      const listEl   = view.querySelector('#collection-card-list');
      const mainEl   = document.getElementById('main-content');
      if (sentinel && listEl) {
        let rendered = _COLLECTION_PAGE_SIZE;
        _collectionPaginator = new IntersectionObserver((entries) => {
          if (!entries[0].isIntersecting) return;
          const next = Math.min(rendered + _COLLECTION_PAGE_SIZE, sortedGroups.length);
          // Append the next slice as innerHTML — single DOM mutation
          // for the whole batch keeps reflow cost bounded.
          const tmp = document.createElement('div');
          tmp.innerHTML = sortedGroups.slice(rendered, next).map(buildCollectionCardHtml).join('');
          // Move children one-by-one; faster than re-assigning innerHTML.
          while (tmp.firstChild) listEl.appendChild(tmp.firstChild);
          rendered = next;
          if (rendered >= sortedGroups.length) {
            _collectionPaginator?.disconnect();
            _collectionPaginator = null;
            sentinel.remove();
          }
        }, {
          // Body has overflow:hidden; the scrolling container is #main-content
          // (DECISIONS.md #020 + WEB-DESIGN.md note). IntersectionObserver
          // must use this as the root or it never fires.
          root: mainEl,
          rootMargin: '600px 0px',  // start loading well before sentinel enters viewport
        });
        _collectionPaginator.observe(sentinel);
      }
    } else {
      // Everything already in page 1 — remove the (empty) sentinel.
      view.querySelector('#collection-load-sentinel')?.remove();
    }

    // Custom Rainbows — fire async; render only when at least one
    // rainbow comes back. No spinner; the section is hidden by
    // default so an empty fetch is a no-op.
    hydrateCustomRainbows(ownedCards);
    // Per-hero Auto Rainbows — synthesized from owned heroes ×
    // catalog. Always runs; section stays hidden when ownedCards
    // is empty.
    hydrateHeroRainbows(ownedCards);

    view.querySelectorAll('.collection-totals-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        setTotalsMode(btn.dataset.totalsMode);
      });
    });

    // Open detail on card item click (not on delete button)
    view.querySelectorAll('[data-detail-num]').forEach(item => {
      item.addEventListener('click', e => {
        if (e.target.closest('[data-delete-id]')) return;
        openCollectionDetail(item.dataset.detailNum);
      });
      item.addEventListener('keydown', e => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          openCollectionDetail(item.dataset.detailNum);
        }
      });
    });

    view.querySelectorAll('[data-delete-id]').forEach(btn => {
      btn.addEventListener('click', async e => {
        e.stopPropagation();
        const id = btn.dataset.deleteId;
        if (!confirm('Remove this card from your collection?')) return;
        try {
          await API.collectionDelete(id);
          _cards = _cards.filter(c => c.id !== id);
          renderCollectionView();
          renderProfileView();
        } catch (err) {
          alert('Could not remove card: ' + err.message);
        }
      });
    });
  }

  function buildCollectionCardHtml(group) {
    // group is an array of entries that share bobaId + designation.
    const first = group[0];
    const qty   = group.length;
    // Count copies across EVERY designation, not just the active tab,
    // so a coach on the For Sale tab still sees "×3" if they own three
    // total (one for sale + two personal). Without this the badge
    // implies they only have a single copy when the rest are sitting
    // a tab over.
    const groupKeyOf = c => c.boba_id || c.card_number;
    const thisKey = groupKeyOf(first);
    const totalCopiesAllDesignations = _cards.filter(c => groupKeyOf(c) === thisKey).length;
    const designLabel = DESIGNATIONS.find(d => d.key === first.designation)?.label || first.designation;
    // Prefer bobaId lookup for exact card matching; fall back to card_number for legacy rows
    const catalogCard = (_bobaIdLookup && first.boba_id)
      ? _bobaIdLookup(first.boba_id)
      : (_cardLookup ? _cardLookup(first.card_number) : null);
    const cardName    = catalogCard?.name || first.card_number;
    const imageFile   = catalogCard?.imageFile;
    const element     = catalogCard?.element || 'NONE';
    const power       = catalogCard?.power;
    const treatment   = catalogCard?.treatment;

    // Responsive image: srcset auto-upgrades to full-res when the
    // grid renders fewer than ~4 cards across (mobile / "L" density),
    // stays on cheap thumbs in dense layouts. Mirrors iOS's
    // CardImageView size pass-through pattern.
    // CRITICAL: route through API.cardThumbUrl / cardFullUrl so sealed
    // products (cardType === 'Sealed Product') resolve to /sealed/thumbs/
    // and /sealed/optimized/ instead of 404'ing against the regular
    // /thumbs/ and /full/ paths.
    const thumbSrc = catalogCard ? API.cardThumbUrl(catalogCard) : null;
    const fullSrc  = catalogCard ? API.cardFullUrl(catalogCard)  : null;
    const srcsetPair = (thumbSrc && fullSrc)
      ? `${thumbSrc} 200w, ${fullSrc} 1200w`
      : null;
    const imgHtml = thumbSrc
      ? `<img class="ccard-thumb" src="${esc(thumbSrc)}"
              srcset="${esc(srcsetPair)}"
              sizes="auto, (min-width: 1024px) 220px, (min-width: 480px) 33vw, 50vw"
              alt="${esc(cardName)}" loading="lazy" decoding="async">`
      : `<div class="ccard-thumb ccard-thumb-placeholder" data-element="${esc(element)}" aria-hidden="true">
           <span class="placeholder-brand">BOBA<br>PB</span>
         </div>`;

    // Sums + earliest acquired + condition summary across the stack.
    const totalPaid     = group.reduce((s, c) => s + (c.purchase_price ? Number(c.purchase_price) : 0), 0);
    const totalEstimate = group.reduce((s, c) => s + (c.estimated_value ? Number(c.estimated_value) : 0), 0);
    const earliestAdded = group.reduce((min, c) => {
      const ts = c.acquired_at || c.created_at;
      if (!ts) return min;
      return (!min || ts < min) ? ts : min;
    }, null);
    const conditions = Array.from(new Set(group.map(c => c.condition).filter(Boolean)));
    const conditionLabel = conditions.length === 1
      ? conditions[0].replace('_', ' ')
      : conditions.length > 1 ? 'Mixed' : '';

    const valueRow = totalEstimate > 0
      ? `<div class="ccard-price ccard-price-value">$${totalEstimate.toFixed(2)} <span class="ccard-price-tag">VALUE</span>${
          totalPaid > 0 ? `<span class="ccard-price-paid">paid $${totalPaid.toFixed(2)}</span>` : ''
        }</div>`
      : (totalPaid > 0
          ? `<div class="ccard-price">$${totalPaid.toFixed(2)} <span class="ccard-price-tag">PAID</span></div>`
          : '');

    return `
      <div class="collection-card-item" role="listitem" data-element="${esc(element)}"
           data-detail-num="${esc(first.boba_id || first.card_number)}"
           style="cursor:pointer" title="View detail"
           tabindex="0" aria-label="View ${esc(cardName)} detail">
        ${imgHtml}
        <div class="ccard-body">
          <div class="ccard-name-row">
            <span class="ccard-name">${esc(cardName)}</span>
            ${totalCopiesAllDesignations > 1
              ? `<span class="ccard-qty">×${totalCopiesAllDesignations}${
                  totalCopiesAllDesignations !== qty ? ` <span class="ccard-qty-here">(${qty} here)</span>` : ''
                }</span>`
              : ''}
          </div>
          <div class="ccard-stat-strip">
            ${element && element !== 'NONE' ? `<span class="ccard-stat ccard-element" data-element="${esc(element)}">${esc(element)}</span>` : ''}
            ${power ? `<span class="ccard-stat ccard-power">⚡${esc(String(power))}</span>` : ''}
            <span class="ccard-stat ccard-num">#${esc(first.card_number || '—')}</span>
          </div>
          ${treatment ? `<div class="ccard-treatment">${esc(treatment)}</div>` : ''}
          <div class="ccard-badges">
            <span class="desig-badge desig-${esc(first.designation || '')}">${esc(designLabel)}</span>
            ${conditionLabel ? `<span class="ccard-condition">${esc(conditionLabel)}${conditions.length === 1 && group[0].grade ? ` · ${esc(group[0].grade)}` : ''}</span>` : ''}
          </div>
          ${valueRow}
          ${earliestAdded ? `<div class="ccard-added">Added ${esc(formatAddedDate(earliestAdded))}</div>` : ''}
        </div>
        <button class="ccard-delete-btn" data-delete-id="${esc(first.id)}" aria-label="Remove from collection">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
               width="16" height="16" aria-hidden="true">
            <path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>
          </svg>
        </button>
      </div>`;
  }

  /// Short, glanceable acquired-on label. today / yesterday / Nd ago /
  /// Mon DD or Mon DD, YYYY for older entries. Matches the iOS row.
  /* ────────────────────────────────────────────────────────────────
     COLLECTION WALL — canvas render of the active designation as a
     single shareable PNG. Parity with iOS CollectionWallSheet per
     DESIGN.md §8.4 + §8.8. Tick 5 ships canvas-render + download
     + clipboard-copy + Web Share (where available); per-card
     selector + Price Overlay land in a later tick.
  ──────────────────────────────────────────────────────────────── */

  /// Per-designation Price Overlay defaults — DESIGN.md §8.8 + iOS
  /// CollectionWallSheet.defaultPriceOverlay.
  function defaultPriceOverlayFor(designation) {
    return ['for_sale', 'for_trade', 'wanted'].includes(designation);
  }
  function defaultPriceSourceFor(designation) {
    // For Sale: my asking price ("My price") · everything else: market estimate.
    return designation === 'for_sale' ? 'asking' : 'estimated';
  }
  function priceOverlayCaptionFor(designation, source) {
    if (source === 'asking')   return 'Your asking price';
    if (source === 'purchase') return 'What you paid';
    return designation === 'wanted' ? 'Market estimate (WTB)' : 'Market estimate';
  }
  function pickPriceForCard(userCard, source) {
    if (!userCard) return null;
    const val = source === 'asking'   ? userCard.asking_price
              : source === 'purchase' ? userCard.purchase_price
              :                          userCard.estimated_value;
    const n = Number(val);
    return Number.isFinite(n) && n > 0 ? n : null;
  }

  /// Open the Wall dialog. Callers:
  ///   - Collection (default): `{ designation, cards }` where cards
  ///     are user_card rows. Price overlay enabled per designation.
  ///   - Catalog-card callers: `{ context: 'deck'|'selection'|'public', title, cards }`
  ///     where cards are catalog Cards directly. Price overlay disabled.
  ///     `context` sub-tags drive the footer-note copy:
  ///       - 'deck'      → "your current deck" (practice.js Decks Wall)
  ///       - 'selection' → "your current selection" (Find multi-select)
  ///       - 'public'    → "this user's public collection" (public-collection page)
  async function openWallSheet({ designation, cards, context, title }) {
    const overlay = document.getElementById('wall-overlay');
    if (!overlay) return;

    // Any catalog-cards-mode context disables price overlay + skips
    // user-card-row resolution; the sub-tag drives the footer copy.
    const isCatalogContext = context === 'deck' || context === 'selection' || context === 'public';
    const isDeckContext = isCatalogContext;

    const titleInput  = document.getElementById('wall-title-input');
    const canvas      = document.getElementById('wall-canvas');
    const loading     = document.getElementById('wall-loading');
    const loadText    = document.getElementById('wall-loading-text');
    const dlBtn       = document.getElementById('wall-download-btn');
    const cpBtn       = document.getElementById('wall-copy-btn');
    const shBtn       = document.getElementById('wall-share-btn');
    const priceToggle = document.getElementById('wall-price-toggle');
    const priceSource = document.getElementById('wall-price-source');
    const priceCap    = document.getElementById('wall-overlay-caption');
    const priceRow    = priceToggle?.closest('.wall-overlay-controls');

    // Price-overlay controls: defaults from designation (Collection
    // path); disabled entirely for Decks path since deck cards
    // aren't designation-scoped + don't carry asking/estimated.
    if (isDeckContext) {
      priceToggle.checked = false;
      if (priceRow) priceRow.style.display = 'none';
      priceCap.textContent = '';
    } else {
      if (priceRow) priceRow.style.display = '';
      priceToggle.checked = defaultPriceOverlayFor(designation);
      priceSource.value   = defaultPriceSourceFor(designation);
      priceCap.textContent = priceToggle.checked
        ? priceOverlayCaptionFor(designation, priceSource.value)
        : '';
    }

    // Title seed. Decks: passed-in deck name. Collection: derive
    // from designation label.
    if (!titleInput.value || isDeckContext) {
      if (isDeckContext) {
        titleInput.value = title || 'My Deck';
      } else {
        const desigLabel = (DESIGNATIONS.find(d => d.key === designation)?.label) || 'Collection';
        titleInput.value = `My ${desigLabel}`;
      }
    }

    // Collection: keep the original user-card rows around so the
    // price-overlay layer can read asking_price / estimated_value /
    // purchase_price. Indexed by bobaId for fast draw-time lookup.
    // Decks: empty map; price overlay is forced off anyway.
    const userCardByBobaId = {};
    if (!isDeckContext) {
      for (const c of cards) {
        const k = c.boba_id || c.card_number;
        if (k) userCardByBobaId[k] = c;
      }
    }

    // Resolution. Decks: cards are already catalog Cards — pass
    // through, just drop image-less. Collection: lookup catalog
    // Card by boba_id / card_number, drop image-less (would render
    // as placeholders and look broken in a share image).
    let resolved = isDeckContext
      ? cards.filter(c => c && c.imageFile)
      : cards
          .map(c => {
            const cat = (_bobaIdLookup && c.boba_id)
              ? _bobaIdLookup(c.boba_id)
              : (_cardLookup ? _cardLookup(c.card_number) : null);
            return cat;
          })
          .filter(c => c && c.imageFile);

    dlBtn.disabled = true;
    cpBtn.disabled = true;
    shBtn.disabled = true;
    shBtn.hidden = !navigator.share;
    loading.hidden = false;

    overlay.showModal();

    if (resolved.length === 0) {
      loadText.textContent = 'No cards with images to render.';
      return;
    }

    // Cap the rendered card count to keep the canvas height under
    // Safari's 16,384px / Chrome's 32,767px hard limits. At cols=8
    // (max) and cellH≈174, 200 cards → ~4400px canvas; 300+ cards
    // approaches the Safari cap. Cap at 200 + surface the truncation
    // honestly so the user knows what they're seeing.
    const HARD_CAP = 200;
    const originalCount = resolved.length;
    const truncated = originalCount > HARD_CAP;
    if (truncated) resolved = resolved.slice(0, HARD_CAP);
    loadText.textContent = truncated
      ? `Loading first ${HARD_CAP} of ${originalCount} cards…`
      : `Loading ${resolved.length} card${resolved.length === 1 ? '' : 's'}…`;
    // Show the truncation note in the dialog footer so the user
    // knows what they're seeing.
    const truncNote = document.getElementById('wall-truncation-note');
    if (truncNote) {
      if (truncated) {
        truncNote.textContent = `Showing the first ${HARD_CAP} of ${originalCount} cards — Safari/Chrome canvas limits cap the render. Narrow the scope (e.g. filter to one designation) for a wall of every card.`;
        truncNote.hidden = false;
      } else {
        truncNote.hidden = true;
        truncNote.textContent = '';
      }
    }
    // Footer-note copy is context-specific.
    const footerNote = document.getElementById('wall-footer-note');
    if (footerNote) {
      let copy;
      if (context === 'selection') {
        copy = 'Renders the cards in your current Find selection. Adjust the selection and re-open Wall to update.';
      } else if (context === 'public') {
        copy = "Renders the cards in this public collection. The owner can share or save the image too.";
      } else if (context === 'deck') {
        copy = 'Renders the cards in your current deck. Edit the deck and re-open Wall to update.';
      } else {
        copy = 'Renders the cards in the current designation. Tap a card on the Collection tab to add or remove copies first, then re-open Wall.';
      }
      footerNote.textContent = copy;
    }

    // Off-screen render plan. Square canvas, grid of card thumbs
    // computed from total count. 5:7 aspect per card. 1080×1080
    // output is a clean Instagram / Discord-share size.
    const cols = Math.min(Math.max(Math.ceil(Math.sqrt(resolved.length * 1.4)), 3), 8);
    const rows = Math.ceil(resolved.length / cols);
    const PAD = 16;
    const TITLE_H = titleInput.value.trim() ? 80 : 0;
    const cellAspect = 5 / 7;
    // Width drives cell sizing — leave PAD margins + small gutters.
    const cellW = Math.floor((canvas.width - PAD * 2 - (cols - 1) * 8) / cols);
    const cellH = Math.floor(cellW / cellAspect);
    // Resize canvas height to fit content exactly.
    canvas.height = TITLE_H + PAD + rows * cellH + (rows - 1) * 8 + PAD;
    const ctx = canvas.getContext('2d');

    // (Background + title paint moved into drawWall below so toggling
    // the overlay re-renders the whole canvas consistently.)

    // Load every image in parallel. crossOrigin = 'anonymous' so the
    // canvas stays untainted and toBlob / toDataURL work afterward.
    let loaded = 0;
    const loadImage = (card) => new Promise((resolve) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => {
        loaded++;
        loadText.textContent = `Loaded ${loaded}/${resolved.length}…`;
        resolve(img);
      };
      img.onerror = () => { loaded++; resolve(null); };
      img.src = API.cardFullUrl(card) || '';
    });

    const images = await Promise.all(resolved.map(loadImage));

    // Local render function — invoked initially and re-invoked when
    // the user toggles price overlay or changes price source.
    const drawWall = (opts) => {
      const showPrices = opts.showPrices;
      const source = opts.source;
      const wantedPrefix = (designation === 'wanted' && showPrices);

      // Repaint background + title (overlay toggle re-renders the
      // whole canvas, not just an extra layer).
      ctx.fillStyle = '#080810';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      if (TITLE_H > 0) {
        ctx.fillStyle = '#FF4D00';
        ctx.font = '700 36px "Bebas Neue", system-ui, sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(titleInput.value.trim(), canvas.width / 2, TITLE_H / 2 + 16);
      }

      for (let i = 0; i < images.length; i++) {
        const img = images[i];
        const card = resolved[i];
        const col = i % cols;
        const row = Math.floor(i / cols);
        const x = PAD + col * (cellW + 8);
        const y = TITLE_H + PAD + row * (cellH + 8);

        // Rounded-corner clip + draw the card image.
        ctx.save();
        ctx.beginPath();
        const r = Math.min(10, cellW * 0.06);
        ctx.moveTo(x + r, y);
        ctx.arcTo(x + cellW, y,         x + cellW, y + cellH, r);
        ctx.arcTo(x + cellW, y + cellH, x,          y + cellH, r);
        ctx.arcTo(x,          y + cellH, x,          y,          r);
        ctx.arcTo(x,          y,         x + cellW, y,          r);
        ctx.closePath();
        ctx.clip();
        ctx.fillStyle = '#0D0D1A';
        ctx.fillRect(x, y, cellW, cellH);
        if (img) {
          ctx.drawImage(img, x, y, cellW, cellH);
        }
        ctx.restore();

        // Price overlay chip — black rounded-rect with bold mono price.
        // Positioned at ~8% above the bottom edge of the card so it
        // doesn't cover the in-print cardNumber badge / weapon symbol.
        // Matches iOS ShowWallComposer.tile chipBottomInset.
        if (showPrices) {
          const k = card?.bobaId || card?.id || card?.cardNumber;
          const userCard = userCardByBobaId[k];
          const price = pickPriceForCard(userCard, source);
          if (price != null) {
            const fontSize = Math.max(11, Math.floor(cellW * 0.085));
            ctx.font = `700 ${fontSize}px ui-monospace, "Chakra Petch", monospace`;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            const label = (wantedPrefix ? 'WTB ' : '') +
              `$${price.toFixed(price >= 100 ? 0 : 2)}`;
            const padH = Math.max(6, cellW * 0.05);
            const padV = Math.max(3, cellW * 0.025);
            const metrics = ctx.measureText(label);
            const chipW = Math.ceil(metrics.width + padH * 2);
            const chipH = Math.ceil(fontSize + padV * 2);
            const chipX = x + (cellW - chipW) / 2;
            const chipY = y + cellH - (cellH * 0.08) - chipH;
            ctx.fillStyle = 'rgba(0,0,0,0.72)';
            const cr = chipH / 2;
            ctx.beginPath();
            ctx.moveTo(chipX + cr, chipY);
            ctx.arcTo(chipX + chipW, chipY,           chipX + chipW, chipY + chipH, cr);
            ctx.arcTo(chipX + chipW, chipY + chipH,   chipX,          chipY + chipH, cr);
            ctx.arcTo(chipX,          chipY + chipH,   chipX,          chipY,          cr);
            ctx.arcTo(chipX,          chipY,           chipX + chipW, chipY,          cr);
            ctx.closePath();
            ctx.fill();
            ctx.fillStyle = '#ffffff';
            ctx.fillText(label, chipX + chipW / 2, chipY + chipH / 2);
          }
        }
      }
    };

    drawWall({ showPrices: priceToggle.checked, source: priceSource.value });

    // Toggle / source changes re-render in place (no image reload).
    const onOverlayChange = () => {
      priceCap.textContent = priceToggle.checked
        ? priceOverlayCaptionFor(designation, priceSource.value)
        : '';
      drawWall({ showPrices: priceToggle.checked, source: priceSource.value });
    };
    priceToggle.onchange = onOverlayChange;
    priceSource.onchange = onOverlayChange;

    loading.hidden = true;
    dlBtn.disabled = false;
    cpBtn.disabled = false;
    shBtn.disabled = false;

    // Wire actions (clean any prior listeners by cloning).
    const reset = (btn) => {
      const fresh = btn.cloneNode(true);
      btn.replaceWith(fresh);
      return fresh;
    };
    const dl2 = reset(dlBtn);
    const cp2 = reset(cpBtn);
    const sh2 = reset(shBtn);

    dl2.addEventListener('click', () => {
      canvas.toBlob((blob) => {
        if (!blob) return;
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        const safeTitle = (titleInput.value || 'collection-wall').replace(/[^a-z0-9-_]+/gi, '-').toLowerCase();
        a.download = `${safeTitle}.png`;
        a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 4000);
      }, 'image/png');
    });

    cp2.addEventListener('click', async () => {
      try {
        const blob = await new Promise((res) => canvas.toBlob(res, 'image/png'));
        if (!blob) throw new Error('no blob');
        await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
        cp2.textContent = '✓ Copied';
        setTimeout(() => { cp2.textContent = 'Copy Image'; }, 1800);
      } catch {
        cp2.textContent = 'Copy failed';
        setTimeout(() => { cp2.textContent = 'Copy Image'; }, 1800);
      }
    });

    if (navigator.share) {
      sh2.addEventListener('click', async () => {
        try {
          const blob = await new Promise((res) => canvas.toBlob(res, 'image/png'));
          if (!blob) return;
          const file = new File([blob], 'wall.png', { type: 'image/png' });
          if (navigator.canShare?.({ files: [file] })) {
            await navigator.share({ files: [file], title: titleInput.value || 'My Collection' });
          } else {
            await navigator.share({ title: titleInput.value || 'My Collection', url: location.href });
          }
        } catch { /* user cancelled */ }
      });
    }
  }

  // Wall close handler — backdrop click + explicit close button.
  document.getElementById('wall-overlay')?.addEventListener('click', (e) => {
    const ov = document.getElementById('wall-overlay');
    if (e.target.closest('[data-action="close-wall"]') || e.target === ov) {
      ov.close();
    }
  });

  /* ────────────────────────────────────────────────────────────────
     CUSTOM RAINBOWS — read-only display on the Collection page.
     iOS v2.219-v2.221 ships the editor + detail; this is web parity
     (read-only). Each rainbow renders as a row with name + criteria
     summary + progress count + a horizontal scroll of matching
     catalog cards. Owned matches are highlighted; un-owned are
     dimmed so the user sees what they still need.
  ──────────────────────────────────────────────────────────────── */

  /// Shared row-render: emits a <details> for one rainbow (custom or
  /// auto-hero). Used by both hydrateCustomRainbows and
  /// hydrateHeroRainbows. matchingCards is pre-computed by the caller
  /// so the catalog filter only runs once per row.
  ///
  /// `rainbowId` (optional) — when present, the row emits an edit
  /// button that opens the Custom Rainbow editor preloaded with this
  /// row's data. Auto-hero rainbows omit `rainbowId` so they're
  /// uneditable.
  function _renderRainbowRow({ name, summary, matching, ownedKeys, rainbowId }) {
    const ownedMatching   = matching.filter(c => ownedKeys.has(c.bobaId) || ownedKeys.has(c.cardNumber));
    const missingMatching = matching.filter(c => !(ownedKeys.has(c.bobaId) || ownedKeys.has(c.cardNumber)));
    const pct = matching.length === 0 ? 0
      : Math.round((ownedMatching.length / matching.length) * 100);
    const editAffordance = rainbowId
      ? `<button type="button" class="rainbow-edit-btn" data-rainbow-id="${esc(rainbowId)}" aria-label="Edit ${esc(name)}" title="Edit rainbow">✎</button>`
      : '';
    // Tick 183 — Discord backlog #2 (web parity for iOS tick 182 +
    // Android tick 181). Lens chips inside the body let the user
    // narrow the 24-thumb strip to Owned / Missing without leaving
    // Collection. Default is All. Click handler in _wireRainbowThumbs.
    return `
      <details class="rainbow-row">
        <summary>
          <span class="rainbow-name">${esc(name)}</span>
          <span class="rainbow-summary">${esc(summary || 'No criteria')}</span>
          <span class="rainbow-progress">
            <span class="rainbow-progress-count">${ownedMatching.length}/${matching.length}</span>
            <span class="rainbow-progress-bar"><span style="width:${pct}%"></span></span>
            <span class="rainbow-progress-pct">${pct}%</span>
          </span>
          ${editAffordance}
        </summary>
        <div class="rainbow-lens" role="tablist">
          <button type="button" class="rainbow-lens-btn active" data-lens="all"     role="tab">All (${matching.length})</button>
          <button type="button" class="rainbow-lens-btn"        data-lens="owned"   role="tab">Owned (${ownedMatching.length})</button>
          <button type="button" class="rainbow-lens-btn"        data-lens="missing" role="tab">Missing (${missingMatching.length})</button>
        </div>
        <div class="rainbow-thumbs">${_renderRainbowThumbs(matching, ownedKeys)}</div>
      </details>`;
  }

  /// Renders the thumbnail strip body for a rainbow row, lens-aware.
  /// Pure function — emits HTML for the given subset. Called on
  /// initial row render and on every lens click.
  function _renderRainbowThumbs(cards, ownedKeys) {
    if (cards.length === 0) return '<div class="rainbow-empty">No matching cards.</div>';
    const visible = cards.slice(0, 24);
    const thumbs = visible.map(c => {
      const isOwned = ownedKeys.has(c.bobaId) || ownedKeys.has(c.cardNumber);
      const url = API.cardThumbUrl(c) || '';
      return `<button class="rainbow-thumb${isOwned ? ' owned' : ''}"
                      type="button" data-detail-num="${esc(c.cardNumber)}"
                      title="${esc((c.hero || c.name || '') + ' · ' + (c.treatment || ''))}">
                <img src="${esc(url)}" alt="${esc(c.hero || c.name || '')}" loading="lazy" />
              </button>`;
    }).join('');
    const more = cards.length > visible.length
      ? `<div class="rainbow-more">+${cards.length - visible.length} more</div>`
      : '';
    return thumbs + more;
  }

  /// Wires thumbnail-tap → card-detail on a freshly-rendered rainbow list.
  /// Also wires the per-row All/Owned/Missing lens (tick 183).
  function _wireRainbowThumbs(listEl, catalog) {
    listEl.querySelectorAll('[data-detail-num]').forEach(el => {
      el.addEventListener('click', () => {
        const cn = el.dataset.detailNum;
        if (window.openCardModal) {
          const card = catalog.find(c => c.cardNumber === cn);
          if (card) window.openCardModal(card);
        }
      });
    });
    // Lens click handler — event-delegated on each row so each
    // rainbow has its own independent lens state.
    listEl.querySelectorAll('.rainbow-row').forEach(row => {
      row.addEventListener('click', (e) => {
        const btn = e.target.closest('.rainbow-lens-btn');
        if (!btn) return;
        e.preventDefault();
        const lens = btn.dataset.lens;
        // Re-render the row's thumbs in the chosen lens
        const summary = row.querySelector('.rainbow-name')?.textContent || '';
        // Look up the rainbow's catalog match list. Cached on the
        // node when the row was rendered.
        const matching = row.__matching;
        const ownedKeys = row.__ownedKeys;
        if (!matching || !ownedKeys) return;
        const filtered = lens === 'owned'
          ? matching.filter(c => ownedKeys.has(c.bobaId) || ownedKeys.has(c.cardNumber))
          : lens === 'missing'
          ? matching.filter(c => !(ownedKeys.has(c.bobaId) || ownedKeys.has(c.cardNumber)))
          : matching;
        const thumbsEl = row.querySelector('.rainbow-thumbs');
        if (thumbsEl) thumbsEl.innerHTML = _renderRainbowThumbs(filtered, ownedKeys);
        // Update active state
        row.querySelectorAll('.rainbow-lens-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        // Re-wire taps on the freshly-rendered thumbs (the originals
        // are gone with innerHTML replacement).
        thumbsEl?.querySelectorAll('[data-detail-num]').forEach(el => {
          el.addEventListener('click', () => {
            const cn = el.dataset.detailNum;
            if (window.openCardModal) {
              const card = catalog.find(c => c.cardNumber === cn);
              if (card) window.openCardModal(card);
            }
          });
        });
      });
    });
  }

  // Cache of the user's custom rainbows (latest fetch) — keyed by id
  // for fast lookup when the edit button is tapped. Refreshed by
  // hydrateCustomRainbows.
  let _customRainbowsById = {};

  // Memoized "catalog cards matching this rainbow's criteria" cache.
  // Key: rainbow.id + JSON-stringified criteria (so changes to criteria
  // invalidate). Without this, every Collection re-render re-filters
  // 17k catalog × N rainbows on every keystroke. Cleared on clear()
  // (sign-out) + on catalog change (catalogVersion bump).
  const _rainbowMatchCache = new Map();
  let _rainbowMatchCacheCatalogLen = 0;

  function _rainbowMatching(rainbow, catalog) {
    // Invalidate the whole cache if the catalog grew/shrunk (rare —
    // only at first-load progressive hydration).
    if (catalog.length !== _rainbowMatchCacheCatalogLen) {
      _rainbowMatchCache.clear();
      _rainbowMatchCacheCatalogLen = catalog.length;
    }
    const key = `${rainbow.id}|${JSON.stringify(rainbow.criteria || {})}`;
    let cached = _rainbowMatchCache.get(key);
    if (cached) return cached;
    cached = catalog.filter(c => API.rainbowCriteriaMatches(c, rainbow.criteria));
    _rainbowMatchCache.set(key, cached);
    return cached;
  }

  async function hydrateCustomRainbows(ownedCards) {
    const section = document.getElementById('custom-rainbows-section');
    const list    = document.getElementById('custom-rainbows-list');
    const empty   = document.getElementById('custom-rainbows-empty');
    if (!section || !list) return;
    // Only show the "+ New rainbow" affordance to signed-in users —
    // unauthed users can't write, so don't tease the button.
    section.hidden = !Auth.isAuthenticated();
    if (!Auth.isAuthenticated()) return;

    let rainbows;
    try { rainbows = await API.fetchCustomRainbows(); } catch { rainbows = []; }
    _customRainbowsById = {};
    for (const r of rainbows || []) _customRainbowsById[r.id] = r;

    // Empty-state render BEFORE the catalog-readiness check. A user
    // with zero rainbows shouldn't see a bare heading + button when
    // they first sign in (catalog still hydrating) — show the empty
    // hint immediately. The catalog-required match work below is the
    // only path that needs the catalog.
    if (!rainbows || rainbows.length === 0) {
      list.innerHTML = '';
      if (empty) empty.hidden = false;
      return;
    }
    if (empty) empty.hidden = true;

    const catalog = window.__bobaCatalog || [];
    if (catalog.length === 0) return;

    const groupKeyOf = c => c.boba_id || c.card_number;
    const ownedKeys = new Set(ownedCards.map(groupKeyOf));
    // Compute matching arrays once, render rows, then stash matching+
    // ownedKeys on each .rainbow-row so the lens handler in
    // _wireRainbowThumbs can re-filter without recomputing.
    const matchings = rainbows.map(r => _rainbowMatching(r, catalog));
    list.innerHTML = rainbows.map((rainbow, i) => _renderRainbowRow({
      name: rainbow.name,
      summary: API.rainbowCriteriaSummary(rainbow.criteria),
      matching: matchings[i],
      ownedKeys,
      rainbowId: rainbow.id,
    })).join('');
    list.querySelectorAll('.rainbow-row').forEach((row, i) => {
      row.__matching  = matchings[i];
      row.__ownedKeys = ownedKeys;
    });
    _wireRainbowThumbs(list, catalog);
    // Wire edit-pencil clicks to open the editor preloaded.
    list.querySelectorAll('.rainbow-edit-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();         // don't toggle the <details>
        e.stopPropagation();
        const r = _customRainbowsById[btn.dataset.rainbowId];
        if (r) openCustomRainbowEditor(r);
      });
    });
  }

  /// Per-hero Auto Rainbows — one row per unique hero in the user's
  /// owned cards. Each row shows ALL printings of that hero across the
  /// catalog (every set/treatment) as the "set to collect". Mirrors iOS
  /// RainbowDetailView Kind.hero(_) pattern.
  function hydrateHeroRainbows(ownedCards) {
    const section = document.getElementById('hero-rainbows-section');
    const list    = document.getElementById('hero-rainbows-list');
    if (!section || !list) return;

    const catalog = window.__bobaCatalog || [];
    if (catalog.length === 0) return;

    const groupKeyOf = c => c.boba_id || c.card_number;
    const ownedKeys = new Set(ownedCards.map(groupKeyOf));

    // Determine which heroes the user has at least one copy of.
    // Look the user-card row up against the catalog for hero info
    // (user_cards itself doesn't carry hero).
    const ownedHeroes = new Set();
    for (const uc of ownedCards) {
      const cat = (uc.boba_id && _bobaIdLookup)
        ? _bobaIdLookup(uc.boba_id)
        : (_cardLookup ? _cardLookup(uc.card_number) : null);
      const h = cat?.hero;
      if (h && h.trim()) ownedHeroes.add(h);
    }
    if (ownedHeroes.size === 0) return;

    // Build per-hero buckets in one catalog pass (no O(heroes × catalog)).
    const buckets = {};
    for (const c of catalog) {
      if (!c.hero || !ownedHeroes.has(c.hero)) continue;
      (buckets[c.hero] = buckets[c.hero] || []).push(c);
    }

    // Pre-compute completion ratio per hero in a single pass per
    // bucket, then sort by the cached ratio. Without this, the sort
    // comparator filters both buckets on every comparison —
    // ~O(catalog × log heroes) on the comparator versus
    // O(catalog) single-pass + O(heroes log heroes) sort.
    const ratios = {};
    for (const hero of Object.keys(buckets)) {
      const bucket = buckets[hero];
      let owned = 0;
      for (const c of bucket) {
        if (ownedKeys.has(c.bobaId) || ownedKeys.has(c.cardNumber)) owned++;
      }
      ratios[hero] = owned / bucket.length;
    }
    const heroes = Object.keys(buckets).sort((a, b) => {
      if (ratios[a] !== ratios[b]) return ratios[b] - ratios[a];
      return a.localeCompare(b);
    });

    section.hidden = false;
    list.innerHTML = heroes.map(hero => {
      const matching = buckets[hero];
      return _renderRainbowRow({
        name: hero,
        summary: `All printings · ${matching.length} card${matching.length === 1 ? '' : 's'}`,
        matching,
        ownedKeys,
      });
    }).join('');
    // Stash matching+ownedKeys per row so the lens handler can re-filter
    // without recomputing. Tick 183.
    list.querySelectorAll('.rainbow-row').forEach((row, i) => {
      row.__matching  = buckets[heroes[i]];
      row.__ownedKeys = ownedKeys;
    });
    _wireRainbowThumbs(list, catalog);
  }

  function formatAddedDate(iso) {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    const now = new Date();
    const startOfDay = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate());
    const dayDiff = Math.round((startOfDay(now) - startOfDay(d)) / 86400000);
    if (dayDiff === 0) return 'today';
    if (dayDiff === 1) return 'yesterday';
    if (dayDiff > 1 && dayDiff < 7) return `${dayDiff}d ago`;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const sameYear = d.getFullYear() === now.getFullYear();
    return sameYear
      ? `${months[d.getMonth()]} ${d.getDate()}`
      : `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
  }

  /// Collection-only sort. Mirrors CollectionSortOrder in iOS:
  /// added_desc / added_asc / price_desc / price_asc / paid_desc /
  /// paid_asc / name_asc / name_desc.
  let _collectionSort = (typeof localStorage !== 'undefined'
    ? localStorage.getItem('bp_collectionSort_v1')
    : null) || 'added_desc';

  /// Stats-bar mode. 'collection' = whole-collection totals across
  /// owned designations (default; what shipped before v2.272).
  /// 'filter' = totals for the active designation tab only (the
  /// designation is web's primary collection filter axis). iOS
  /// mirrors this via @AppStorage("bp_collectionTotalsMode_v1") in
  /// CollectionView, with additional filter dimensions (weapon,
  /// treatment, etc.) on that platform.
  let _totalsMode = (typeof localStorage !== 'undefined'
    ? localStorage.getItem('bp_collectionTotalsMode_v1')
    : null) || 'collection';

  function sortCollectionGroups(groups) {
    const meta = (group) => {
      const first = group[0];
      const card = (_bobaIdLookup && first.boba_id)
        ? _bobaIdLookup(first.boba_id)
        : (_cardLookup ? _cardLookup(first.card_number) : null);
      const name = (card?.name || first.card_number || '').toLowerCase();
      const added = group.reduce((min, c) => {
        const ts = c.acquired_at || c.created_at || '';
        return (!min || (ts && ts < min)) ? ts : min;
      }, null) || '';
      const value = group.reduce((s, c) => s + (c.estimated_value ? Number(c.estimated_value) : 0), 0);
      const paid  = group.reduce((s, c) => s + (c.purchase_price ? Number(c.purchase_price) : 0), 0);
      // playCost is only set on Play cards; null for Heroes/HotDogs/Sealed.
      const cost  = (card && card.playCost != null) ? Number(card.playCost) : null;
      return { name, added, value, paid, cost };
    };
    const cache = new Map(groups.map(g => [g, meta(g)]));
    const cmp = (a, b, k, dir) => {
      const av = cache.get(a)[k];
      const bv = cache.get(b)[k];
      if (av < bv) return dir;
      if (av > bv) return -dir;
      return cache.get(a).name.localeCompare(cache.get(b).name);
    };
    const list = groups.slice();
    switch (_collectionSort) {
      case 'name_asc':    list.sort((a, b) => cache.get(a).name.localeCompare(cache.get(b).name)); break;
      case 'name_desc':   list.sort((a, b) => cache.get(b).name.localeCompare(cache.get(a).name)); break;
      case 'added_desc':  list.sort((a, b) => cmp(a, b, 'added', -1)); break;
      case 'added_asc':   list.sort((a, b) => cmp(a, b, 'added',  1)); break;
      case 'price_desc':  list.sort((a, b) => cmp(a, b, 'value', -1)); break;
      case 'price_asc':   list.sort((a, b) => cmp(a, b, 'value',  1)); break;
      case 'paid_desc':   list.sort((a, b) => cmp(a, b, 'paid',  -1)); break;
      case 'paid_asc':    list.sort((a, b) => cmp(a, b, 'paid',   1)); break;
      case 'cost_asc':
      case 'cost_desc': {
        // Plays (cost present) before non-Plays so the cost-ordered run stays contiguous.
        const asc = _collectionSort === 'cost_asc';
        list.sort((a, b) => {
          const ac = cache.get(a).cost, bc = cache.get(b).cost;
          const ah = ac != null, bh = bc != null;
          if (ah !== bh) return ah ? -1 : 1;
          const av = ac ?? 0, bv = bc ?? 0;
          if (av !== bv) return asc ? av - bv : bv - av;
          return cache.get(a).name.localeCompare(cache.get(b).name);
        });
        break;
      }
      default:            list.sort((a, b) => cmp(a, b, 'added', -1));
    }
    return list;
  }

  function setCollectionSort(value) {
    _collectionSort = value;
    try { localStorage.setItem('bp_collectionSort_v1', value); } catch (_) { /* noop */ }
    renderCollectionView();
  }

  function setTotalsMode(value) {
    if (value !== 'collection' && value !== 'filter') return;
    _totalsMode = value;
    try { localStorage.setItem('bp_collectionTotalsMode_v1', value); } catch (_) { /* noop */ }
    renderCollectionView();
  }

  /* ================================================================
     PROFILE VIEW
  ================================================================ */

  function renderProfileView() {
    const view = document.getElementById('view-profile');
    if (!view) return;

    if (!Auth.isAuthenticated()) {
      view.innerHTML = `
        <div class="view-inner auth-gate">
          <h2 class="view-heading">Profile</h2>
          <p class="view-subtitle">Sign in to save your collection and sync across devices.</p>
          <button class="btn-primary" id="profile-signin-btn">Sign In / Create Account</button>
        </div>`;
      view.querySelector('#profile-signin-btn')
        ?.addEventListener('click', () => Auth.open());
      return;
    }

    const session = Auth.getSession();
    const email   = session?.user?.email || 'BOBA Player';
    const role    = API.getCachedRole();
    // Sign-in method pill (DESIGN.md §6.5 / iOS provider pill parity).
    // Apple/Discord get rendered as branded pills; email is the
    // unmarked default.
    const provider = session?.user?.app_metadata?.provider;

    // Per-designation card counts and value totals previously rendered
    // here were removed for parity with iOS — those numbers live on the
    // Collection tab's value summary header now, not in Profile.

    view.innerHTML = `
      <div class="profile-page">
        <h2 class="view-heading profile-page-heading">Profile</h2>

        <!-- Account card. Avatar is a button so click-to-edit reads
             as tappable. The actual <img> / silhouette is hydrated by
             wireAvatarEditor() once fetchProfile resolves. -->
        <div class="profile-account-card">
          <button class="profile-avatar profile-avatar-button" id="profile-avatar-btn"
                  type="button" aria-label="Change profile picture">
            <span class="profile-avatar-content" id="profile-avatar-content">
              <svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28" aria-hidden="true">
                <path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-5.33 0-8 2.67-8 4v1h16v-1c0-1.33-2.67-4-8-4z"/>
              </svg>
            </span>
            <span class="profile-avatar-camera" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   stroke-linecap="round" stroke-linejoin="round" width="12" height="12">
                <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
                <circle cx="12" cy="13" r="4"/>
              </svg>
            </span>
          </button>
          <input type="file" id="profile-avatar-file" accept="image/jpeg,image/png,image/webp" hidden>
          <dialog id="profile-avatar-crop-dialog" class="avatar-crop-dialog" aria-label="Crop profile picture">
            <div class="avatar-crop-header">
              <span class="avatar-crop-title">Crop</span>
              <span class="avatar-crop-hint">Drag to position · scroll to zoom</span>
            </div>
            <div class="avatar-crop-stage" id="avatar-crop-stage">
              <canvas id="avatar-crop-canvas" width="280" height="280"></canvas>
              <div class="avatar-crop-mask" aria-hidden="true"></div>
            </div>
            <div class="avatar-crop-actions">
              <button type="button" class="avatar-crop-cancel" id="avatar-crop-cancel">Cancel</button>
              <button type="button" class="avatar-crop-confirm" id="avatar-crop-confirm">Use Photo</button>
            </div>
          </dialog>
          <dialog id="profile-avatar-menu-dialog" class="avatar-menu-dialog" aria-label="Profile picture options">
            <div class="avatar-menu-list">
              <button type="button" class="avatar-menu-row" id="avatar-menu-choose">Choose from Computer</button>
              <button type="button" class="avatar-menu-row" id="avatar-menu-discord" hidden>Use Discord Avatar</button>
              <button type="button" class="avatar-menu-row destructive" id="avatar-menu-remove" hidden>Remove Custom Avatar</button>
              <button type="button" class="avatar-menu-row" id="avatar-menu-cancel">Cancel</button>
            </div>
          </dialog>
          <div class="profile-account-info">
            <div class="profile-account-username" id="profile-username-display">@…</div>
            <div class="profile-account-email">${esc(email)}</div>
            <div class="profile-account-role">
              ${role === 'admin' ? 'Admin' : role === 'moderator' ? 'Moderator' : 'Member'}
              ${role === 'admin' ? '<span class="role-badge admin-badge">ADMIN</span>' :
                role === 'moderator' ? '<span class="role-badge mod-badge">MOD</span>' : ''}
              ${provider === 'apple'   ? '<span class="role-badge provider-pill provider-apple">APPLE</span>' : ''}
              ${provider === 'discord' ? '<span class="role-badge provider-pill provider-discord">DISCORD</span>' : ''}
              ${provider === 'google'  ? '<span class="role-badge provider-pill provider-google">GOOGLE</span>' : ''}
            </div>
          </div>
        </div>

        <!-- Username row (inline edit + debounced banned-words check) -->
        <div class="profile-section">
          <div class="profile-section-label">Username</div>
          <div class="profile-username-row">
            <span class="profile-username-prefix">@</span>
            <input type="text" id="profile-username-input"
                   class="profile-username-input"
                   autocapitalize="none" autocorrect="off" spellcheck="false"
                   maxlength="30"
                   placeholder="username" />
            <span id="profile-username-status" class="profile-username-status"></span>
          </div>
          <p class="profile-username-hint">Lowercase letters, numbers, hyphens, and underscores. 2–30 characters. Used as your public collection URL when sharing is on.</p>
        </div>

        <!-- Collection sharing — global toggle that exposes / hides
             the public read-only collection at bobaplaybook.com/u/{username}.
             Mirrors the iOS Profile toggle (DECISIONS.md #039). -->
        <div class="profile-section" id="profile-sharing-section">
          <div class="profile-section-label">Collection Sharing</div>
          <div class="profile-stat-list">
            <label class="profile-toggle-row" for="profile-public-toggle">
              <span class="profile-toggle-text">
                <span class="profile-toggle-title">Make my collection public</span>
                <span class="profile-toggle-sub">Anyone with your URL can view your owned cards.</span>
              </span>
              <span class="profile-toggle-switch">
                <input type="checkbox" id="profile-public-toggle" />
                <span class="profile-toggle-track"></span>
              </span>
            </label>
            <div class="profile-public-url hidden" id="profile-public-url">
              <span class="profile-public-url-text" id="profile-public-url-text">https://bobaplaybook.com/u/…</span>
              <button class="profile-public-url-copy" id="profile-public-url-copy" type="button"
                      aria-label="Copy public collection link" title="Copy public collection link">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                     stroke-linecap="round" stroke-linejoin="round" width="16" height="16">
                  <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                  <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
                </svg>
              </button>
              <button class="profile-public-url-copy" id="profile-public-url-share" type="button"
                      aria-label="Share public collection link" title="Share public collection link">
                <!-- Lucide: share-2 — matches the public-collection-share icon -->
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                     stroke-linecap="round" stroke-linejoin="round" width="16" height="16">
                  <circle cx="18" cy="5"  r="3"/>
                  <circle cx="6"  cy="12" r="3"/>
                  <circle cx="18" cy="19" r="3"/>
                  <line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/>
                  <line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/>
                </svg>
              </button>
            </div>
          </div>
        </div>

        <!-- Security — Change Password via the native Supabase reset
             email. Wired to API.requestPasswordReset(). -->
        <div class="profile-section">
          <div class="profile-section-label">Security</div>
          <div class="profile-stat-list">
            <button class="profile-action-row" id="profile-change-password-btn">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   stroke-linecap="round" stroke-linejoin="round" width="15" height="15"
                   aria-hidden="true">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
                <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
              </svg>
              <span>Change Password</span>
            </button>
            <p class="profile-change-password-status hidden" id="profile-change-password-status"></p>
          </div>
        </div>

        ${['moderator','admin'].includes(role) ? `
        <!-- Mod/Admin panel links -->
        <div class="profile-section">
          <div class="profile-section-label">Moderation</div>
          <div class="profile-stat-list">
            <button class="profile-mod-row" id="profile-mod-btn">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
              </svg>
              <span>Open Mod Panel</span>
            </button>
            ${role === 'admin' ? `
            <button class="profile-admin-row" id="profile-admin-btn">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <circle cx="12" cy="8" r="4"/><path d="M20 21a8 8 0 1 0-16 0"/>
                <path d="M18 12l2 2 4-4" stroke-width="2.5"/>
              </svg>
              <span>Admin Panel</span>
            </button>` : ''}
          </div>
        </div>` : ''}

        <!-- Role Access — generalized to mod OR streamer.
             Renders for users below the role they're requesting. -->
        <div class="profile-section" id="profile-role-request-section">
          <div class="profile-section-label">Role &amp; Access</div>
          <div class="profile-mod-request-body" id="profile-role-request-body">
            <p class="profile-mod-request-loading">Checking status…</p>
          </div>
        </div>

        <!-- About — Privacy + Terms links + version -->
        <div class="profile-section">
          <div class="profile-section-label">About</div>
          <div class="profile-stat-list">
            <a class="profile-about-row" href="/privacy/" target="_blank" rel="noopener">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
              </svg>
              <span>Privacy Policy</span>
            </a>
            <a class="profile-about-row" href="/terms/" target="_blank" rel="noopener">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
                <polyline points="14 2 14 8 20 8"/>
              </svg>
              <span>Terms of Service</span>
            </a>
            <a class="profile-about-row" href="mailto:ben@bobaplaybook.com?subject=BOBA%20Playbook%20feedback"
               id="profile-feedback-link">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/>
                <polyline points="22,6 12,13 2,6"/>
              </svg>
              <span>Send Feedback</span>
            </a>
            <button class="profile-about-row" type="button" id="profile-feedback-copy-btn"
                    aria-label="Copy feedback email">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
              </svg>
              <span>Copy email address</span>
            </button>
          </div>
        </div>

        <!-- Tick 333 — Keyboard shortcuts cheat sheet. Surfaces the
             shortcuts that ship across views in one place so users
             discover them without trial-and-error or hovering buttons.
             Auto-hides on mobile widths (no keyboard) via CSS. -->
        <div class="profile-section profile-section-shortcuts">
          <div class="profile-section-label">Keyboard shortcuts</div>
          <div class="profile-stat-list profile-shortcuts-list">
            <div class="profile-shortcut-row"><kbd>/</kbd><span>Focus search</span></div>
            <div class="profile-shortcut-row"><kbd>R</kbd><span>Surprise me · pick a random card (Find)</span></div>
            <div class="profile-shortcut-row"><kbd>N</kbd><span>Clear deck draft (Decks)</span></div>
            <div class="profile-shortcut-row"><kbd>⌘</kbd>+<kbd>S</kbd> / <kbd>Ctrl</kbd>+<kbd>S</kbd><span>Save deck (Decks)</span></div>
            <div class="profile-shortcut-row"><kbd>←</kbd> <kbd>→</kbd><span>Prev / next card (Card detail modal)</span></div>
            <div class="profile-shortcut-row"><kbd>Esc</kbd><span>Close modal / dialog</span></div>
          </div>
        </div>

        <!-- Sign out -->
        <div class="profile-section">
          <div class="profile-stat-list">
            <button class="profile-signout-row" id="profile-signout-btn">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>
              </svg>
              <span>Sign Out</span>
            </button>
          </div>
        </div>

        <!-- Delete Account — destructive, with confirm dialog.
             Same deferred-backend approach as iOS (DECISIONS.md #039):
             signs the user out + asks them to email for full deletion
             until the Worker endpoint ships. -->
        <div class="profile-section">
          <div class="profile-stat-list">
            <button class="profile-delete-row" id="profile-delete-btn">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <polyline points="3 6 5 6 21 6"/>
                <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
              </svg>
              <span>Delete Account</span>
            </button>
          </div>
          <p class="profile-delete-hint">Email <a href="mailto:ben@bobaplaybook.com">ben@bobaplaybook.com</a> for immediate deletion.</p>
        </div>
      </div>`;

    view.querySelector('#profile-signout-btn')
      ?.addEventListener('click', async () => {
        if (!confirm('Sign out? Your collection data is saved and will sync back when you sign in again.')) return;
        await Auth.signOut();
      });

    // Tick 293 — pre-fill the Send Feedback mailto body with browser
    // + URL context so Ben can triage faster. iOS v2.314 (tick 286) +
    // Android tick 289 parity. Setting .href at render time means the
    // anchor's default click behavior carries the body through to the
    // OS mail handler.
    const feedbackLink = view.querySelector('#profile-feedback-link');
    if (feedbackLink) {
      const subject = encodeURIComponent('BOBA Playbook feedback');
      const body = encodeURIComponent(
        `\n\n\n---\n` +
        `Page: ${location.href}\n` +
        `Browser: ${navigator.userAgent}`
      );
      feedbackLink.setAttribute(
        'href',
        `mailto:ben@bobaplaybook.com?subject=${subject}&body=${body}`,
      );
    }

    // Tick 168 — copy-email fallback for users without a mailto:
    // handler (some desktop browser configs). Closes parity with
    // iOS tick 167 + Android tick 166's "no email app" graceful
    // fallback. The Send Feedback link still tries the OS mail
    // handler first; this button is the always-works backup.
    view.querySelector('#profile-feedback-copy-btn')
      ?.addEventListener('click', async () => {
        try {
          await navigator.clipboard.writeText('ben@bobaplaybook.com');
          if (typeof window.showToast === 'function') {
            window.showToast('Copied ben@bobaplaybook.com to clipboard');
          }
        } catch (_) {
          if (typeof window.showToast === 'function') {
            window.showToast('Clipboard unavailable — email ben@bobaplaybook.com');
          }
        }
      });

    view.querySelector('#profile-mod-btn')
      ?.addEventListener('click', () => openModSearchPanel());

    view.querySelector('#profile-admin-btn')
      ?.addEventListener('click', () => openAdminPanel());

    // Public collection toggle + URL copy.
    wirePublicCollectionToggle(view);

    // Change Password — triggers the native Supabase reset email.
    wireChangePasswordButton(view);

    // Avatar editor — file picker → canvas crop → upload to R2.
    wireAvatarEditor(view);

    // Delete Account — calls the boba-account-delete Worker which
    // proxies the Supabase admin delete (cascading through every
    // user-data table via FK ON DELETE CASCADE). On success we sign
    // the user out locally so the stale JWT stops getting sent.
    view.querySelector('#profile-delete-btn')
      ?.addEventListener('click', async () => {
        // Two-step destructive confirm — parity with iOS's
        // type-to-confirm pattern for high-stakes destructive
        // actions. Step 1: reads the danger surface. Step 2: requires
        // the user to actually type their username (or DELETE as
        // fallback if no username) so a misclick or hovering pet
        // can't trigger account loss.
        const ok = confirm(
          'Delete your account?\n\n' +
          'This permanently removes your collection, decks, shared ' +
          'links, custom rainbows, and account from BOBA Playbook. ' +
          'This cannot be undone.\n\n' +
          'Continue?'
        );
        if (!ok) return;

        // Look up the user's username for the type-to-confirm prompt.
        // Fall back to literal "DELETE" if their profile has no
        // username (edge case, but possible for fresh accounts).
        let username = null;
        try {
          const profile = await API.fetchProfile();
          username = profile?.username || null;
        } catch { /* offline — fall back to DELETE */ }
        const expected = username || 'DELETE';
        const promptMsg = username
          ? `Type your username (@${username}) to confirm. This action is final.`
          : 'Type DELETE in capital letters to confirm. This action is final.';
        const typed = prompt(promptMsg, '');
        if (typed == null) return;  // user cancelled the type-confirm
        // Case-insensitive compare on username (it's lowercased
        // server-side anyway); exact-match compare on the DELETE
        // fallback so a casual typo doesn't proceed.
        const ok2 = username
          ? typed.trim().toLowerCase() === expected.toLowerCase()
          : typed.trim() === 'DELETE';
        if (!ok2) {
          alert(`Confirmation didn't match — your account was NOT deleted.`);
          return;
        }

        try {
          await API.deleteAccount();
          await Auth.signOut();
          alert('Account deleted. Thanks for trying BOBA Playbook.');
        } catch (e) {
          alert('Could not delete account: ' + (e?.message || e) +
                '\n\nIf this keeps happening, email ben@bobaplaybook.com.');
        }
      });

    // Username inline edit + debounced banned-words check.
    wireUsernameRow(view);

    // Role-request block — handles BOTH moderator AND streamer
    // requests. Uses the new request_role RPC (DECISIONS.md #038).
    renderRoleRequestBlock(view, role);
  }

  /// Mirrors the iOS UsernameRow pattern: derives a default from the
  /// email local-part on first profile open, debounced check_username
  /// on every keystroke, status pill on the right, atomic write via
  /// set_username RPC. Falls back to user-{6-char-hash} when the
  /// derived seed can't escape the banned/reserved gates.
  function wireUsernameRow(view) {
    const input    = view.querySelector('#profile-username-input');
    const display  = view.querySelector('#profile-username-display');
    const status   = view.querySelector('#profile-username-status');
    if (!input || !status || !display) return;

    let currentUsername = null;
    let checkSeq = 0;

    const setStatus = (cls, text) => {
      status.className = 'profile-username-status ' + cls;
      status.textContent = text;
    };

    API.fetchProfile().then(async profile => {
      if (profile?.username) {
        currentUsername = profile.username;
        input.value = profile.username;
        display.textContent = '@' + profile.username;
        setStatus('mine', '✓');
      } else {
        // First-time profile open — auto-derive from email local-part,
        // try numeric suffixes on collision, fall back to user-{hash}.
        const session = Auth.getSession();
        const seed = (session?.user?.email || '').split('@')[0]
          .toLowerCase()
          .replace(/[^a-z0-9_-]/g, '');
        const candidates = seed.length >= 2
          ? [seed, ...Array.from({ length: 98 }, (_, i) => seed + (i + 2))]
          : [];
        for (const candidate of candidates) {
          const trimmed = candidate.slice(0, 30);
          const result = await API.checkUsername(trimmed);
          if (result === 'available') {
            const wrote = await API.setUsername(trimmed);
            if (wrote === 'available') {
              currentUsername = trimmed;
              input.value = trimmed;
              display.textContent = '@' + trimmed;
              setStatus('mine', '✓');
              return;
            }
          }
          if (result === 'invalid_chars' || result === 'too_short') break;
        }
        // Last-ditch: user-{hash}
        const uid = session?.user?.id || '';
        const hash = uid.replace(/[^a-z0-9]/g, '').slice(0, 6);
        if (hash) {
          const fallback = 'user-' + hash;
          const wrote = await API.setUsername(fallback);
          if (wrote === 'available') {
            currentUsername = fallback;
            input.value = fallback;
            display.textContent = '@' + fallback;
            setStatus('mine', '✓');
          }
        }
      }
    }).catch(() => setStatus('error', '✗ Check failed'));

    input.addEventListener('input', () => {
      // Lowercase + strip invalid as the user types
      const raw = input.value;
      const normalized = raw.toLowerCase();
      if (normalized !== raw) {
        const pos = input.selectionStart;
        input.value = normalized;
        input.setSelectionRange(pos, pos);
      }
      const candidate = input.value.trim();
      if (candidate === currentUsername) {
        setStatus('mine', '✓');
        return;
      }
      const seq = ++checkSeq;
      setStatus('checking', '…');
      setTimeout(async () => {
        if (seq !== checkSeq) return;  // superseded
        if (!candidate) { setStatus('idle', ''); return; }
        try {
          const result = await API.checkUsername(candidate);
          if (seq !== checkSeq) return;
          const map = {
            available:     ['ok',    '✓ Available'],
            taken:         ['error', '✗ Already taken'],
            banned:        ['error', '✗ Not allowed'],
            reserved:      ['error', '✗ Reserved'],
            invalid_chars: ['error', '✗ Letters, numbers, _ - only'],
            too_short:     ['error', '✗ At least 2 characters'],
            too_long:      ['error', '✗ 30 characters max'],
          };
          const [cls, text] = map[result] || ['error', '✗ Try a different one'];
          setStatus(cls, text);
          // Auto-commit when validation passes — mirrors iOS pattern.
          if (result === 'available') {
            const wrote = await API.setUsername(candidate);
            if (seq !== checkSeq) return;
            if (wrote === 'available') {
              currentUsername = candidate;
              display.textContent = '@' + candidate;
              setStatus('mine', '✓ Saved');
            } else {
              const [errCls, errText] = map[wrote] || ['error', '✗ Save failed'];
              setStatus(errCls, errText);
            }
          }
        } catch (e) {
          setStatus('error', '✗ Check failed');
        }
      }, 350);
    });
  }

  /// Mirrors iOS Profile's Role & Access section. Generalizes the
  /// old mod-only request to also support streamer (per
  /// DECISIONS.md #038 — request_role RPC takes either role).
  async function renderRoleRequestBlock(view, role) {
    const body = view.querySelector('#profile-role-request-body');
    if (!body) return;

    const isStreamer = role === 'streamer' || role === 'admin';
    const isMod      = role === 'moderator' || role === 'admin';

    let pendingRole = null;
    try {
      const profile = await API.fetchProfile();
      pendingRole = profile?.requested_role || null;
    } catch (_) { /* offline-safe */ }

    const rows = [];
    if (pendingRole) {
      rows.push(`
        <div class="profile-mod-request-pending">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
               width="16" height="16" aria-hidden="true"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
          <div>
            <div class="profile-mod-request-pending-title">${esc(pendingRole.charAt(0).toUpperCase() + pendingRole.slice(1))} request pending</div>
            <div class="profile-mod-request-pending-sub">An admin will review your request soon.</div>
          </div>
        </div>`);
    }
    if (!isStreamer && pendingRole !== 'streamer') {
      rows.push(`
        <button class="profile-mod-request-btn" data-role="streamer">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
               width="15" height="15" aria-hidden="true">
            <rect x="2" y="6" width="14" height="12" rx="2"/><polygon points="22 8 16 12 22 16 22 8"/>
          </svg>
          <span>Request Streamer Access</span>
        </button>`);
    }
    if (!isMod && pendingRole !== 'moderator') {
      rows.push(`
        <button class="profile-mod-request-btn" data-role="moderator">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
               width="15" height="15" aria-hidden="true">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
            <polyline points="9 12 11 14 15 10" stroke-width="2.5"/>
          </svg>
          <span>Request Moderator Access</span>
        </button>`);
    }
    if (rows.length === 1 && pendingRole) {
      // Only the pending banner — nothing actionable. Skip blurb.
      body.innerHTML = rows.join('');
    } else if (!rows.length) {
      body.innerHTML = `<p class="profile-mod-request-blurb">You already have the highest role.</p>`;
    } else {
      const blurb = `<p class="profile-mod-request-blurb">Streamers get the Whatnot Shows feature for live-break prep. Moderators help improve the catalog: upload card images, fix wrong card data, and flag image issues.</p>`;
      body.innerHTML = blurb + rows.join('');
    }

    body.querySelectorAll('.profile-mod-request-btn').forEach(btn => {
      btn.addEventListener('click', () => openRoleRequestModal(view, btn.dataset.role));
    });
  }

  function openRoleRequestModal(view, role) {
    // Per-role copy. The modal shape is identical between mod and
    // streamer; only the title/blurb/feature list changes. Mirrors
    // iOS Profile's RoleRequestSheet (DECISIONS.md #038).
    const copy = role === 'streamer' ? {
      icon: '<rect x="2" y="6" width="14" height="12" rx="2"/><polygon points="22 8 16 12 22 16 22 8"/>',
      title: 'Set up live BOBA breaks',
      lead: 'Streamer access unlocks the Whatnot Shows feature for hosts who run live breaks.',
      featuresLabel: 'WHAT YOU CAN DO AS A STREAMER',
      features: [
        ['Pre-curate breaks', 'Build a Show with the cards you plan to give away or chase during a live break.'],
        ['Track giveaway tally', 'Mark cards as excluded from totals; the running value updates as you go.'],
        ['Generate share images', 'Render a Wall image of your shop\'s hits and post to Whatnot, Discord, or socials.'],
        ['Review before shipping', 'All role promotions are reviewed by an admin — no risk of accidental access.'],
      ],
      fieldHint: 'Tell us about your streaming setup: which platform, how often you go live, what kind of breaks you run.',
    } : {
      icon: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><polyline points="9 12 11 14 15 10" stroke-width="2.5"/>',
      title: 'Help improve the catalog',
      lead: 'Moderator access lets trusted collectors contribute directly to BOBA Playbook\'s card data and images.',
      featuresLabel: 'WHAT YOU CAN DO AS A MOD',
      features: [
        ['Upload card images', 'Submit photos from your own collection, especially for cards still missing art.'],
        ['Fix wrong card data', 'Correct hero names, power values, abilities, or any field that\'s wrong in the app.'],
        ['Flag image issues', 'Request removal or replacement of card images that show the wrong art.'],
        ['Review before shipping', 'All changes go through admin review — no risk of accidental damage.'],
      ],
      fieldHint: 'How long have you collected BOBA? Specific athletes, sets, or treatments you focus on? What\'s motivating you to help?',
    };

    document.getElementById('mod-request-modal')?.remove();
    const modal = document.createElement('div');
    modal.id = 'mod-request-modal';
    modal.className = 'mod-request-modal';
    modal.innerHTML = `
      <div class="mod-request-card" role="dialog" aria-modal="true" aria-labelledby="mod-request-title">
        <div class="mod-request-header">
          <div class="mod-request-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                 width="28" height="28" aria-hidden="true">${copy.icon}</svg>
          </div>
          <h3 id="mod-request-title">${esc(copy.title)}</h3>
          <p>${esc(copy.lead)}</p>
        </div>

        <div class="mod-request-features">
          <div class="mod-request-features-label">${esc(copy.featuresLabel)}</div>
          ${copy.features.map(([t, d]) => `
            <div class="mod-request-feature">
              <strong>${esc(t)}</strong>
              <span>${esc(d)}</span>
            </div>`).join('')}
        </div>

        <label class="mod-request-field">
          <span class="mod-request-field-label">TELL ME A BIT ABOUT YOURSELF</span>
          <span class="mod-request-field-hint">${esc(copy.fieldHint)}</span>
          <textarea id="mod-request-reason" rows="5" placeholder="A short note…"></textarea>
          <span class="mod-request-counter" id="mod-request-counter">0/20 minimum</span>
        </label>

        <div class="mod-request-actions">
          <button class="mod-request-cancel" type="button">Cancel</button>
          <button class="mod-request-submit" type="button" disabled>Submit Request</button>
        </div>
        <p class="mod-request-error hidden" id="mod-request-error"></p>
      </div>`;
    document.body.appendChild(modal);

    const MIN_LEN = 20;
    const textarea = modal.querySelector('#mod-request-reason');
    const counter  = modal.querySelector('#mod-request-counter');
    const submit   = modal.querySelector('.mod-request-submit');
    const err      = modal.querySelector('#mod-request-error');
    const refreshCounter = () => {
      const len = textarea.value.trim().length;
      counter.textContent = `${len}/${MIN_LEN} minimum`;
      counter.classList.toggle('met', len >= MIN_LEN);
      submit.disabled = len < MIN_LEN;
    };
    textarea.addEventListener('input', refreshCounter);
    refreshCounter();

    const close = () => modal.remove();
    modal.querySelector('.mod-request-cancel').addEventListener('click', close);
    modal.addEventListener('click', e => { if (e.target === modal) close(); });

    submit.addEventListener('click', async () => {
      submit.disabled = true;
      submit.textContent = 'Submitting…';
      err.classList.add('hidden');
      try {
        await API.requestRole(role, textarea.value.trim());
        close();
        renderRoleRequestBlock(view, API.getCachedRole());
      } catch (e) {
        err.textContent = e?.message || 'Failed to submit request.';
        err.classList.remove('hidden');
        submit.disabled = false;
        submit.textContent = 'Submit Request';
      }
    });
  }

  /// Public-collection toggle + URL display. Hydrates from
  /// fetchProfile, persists via setPublicCollectionEnabled. URL is
  /// shown only when the toggle is ON; the copy button writes the
  /// current URL to the clipboard with a 2-second confirmation.
  function wirePublicCollectionToggle(view) {
    const toggle   = view.querySelector('#profile-public-toggle');
    const urlBox   = view.querySelector('#profile-public-url');
    const urlText  = view.querySelector('#profile-public-url-text');
    const copyBtn  = view.querySelector('#profile-public-url-copy');
    const shareBtn = view.querySelector('#profile-public-url-share');
    if (!toggle || !urlBox || !urlText || !copyBtn) return;

    const renderUrl = (username) => {
      if (!username) {
        urlBox.classList.add('hidden');
        return;
      }
      urlText.textContent = `https://bobaplaybook.com/u/${username}`;
      urlBox.classList.remove('hidden');
    };

    // Hydrate state from the user_profiles row.
    API.fetchProfile().then(profile => {
      toggle.checked = !!profile?.public_collection_enabled;
      if (toggle.checked) renderUrl(profile?.username);
    }).catch(() => { /* offline — leave toggle in its default state */ });

    toggle.addEventListener('change', async () => {
      const enabled = toggle.checked;
      // Optimistic UI; revert on error.
      try {
        await API.setPublicCollectionEnabled(enabled);
        if (enabled) {
          const profile = await API.fetchProfile();
          renderUrl(profile?.username);
        } else {
          urlBox.classList.add('hidden');
        }
      } catch (e) {
        toggle.checked = !enabled;
        // Tick 163 — was a blocking alert(); same anti-pattern tick
        // 123 / 143 / 158 have been replacing. Non-blocking toast lets
        // the user continue without an OS-modal interrupt.
        if (typeof window.showToast === 'function') {
          window.showToast('Could not update sharing — ' + (e?.message || 'try again'));
        }
      }
    });

    copyBtn.addEventListener('click', async () => {
      const url = urlText.textContent || '';
      if (!url) return;
      try {
        await navigator.clipboard.writeText(url);
        const original = copyBtn.innerHTML;
        copyBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" width="16" height="16"><polyline points="20 6 9 17 4 12"/></svg>';
        setTimeout(() => { copyBtn.innerHTML = original; }, 2000);
      } catch (_) { /* clipboard unavailable — silent */ }
    });

    // Tick 438 — iOS + Android Profile have Copy + Share on the
    // public-URL row; web was Copy-only. Route through the global
    // bobaShareTarget helper (WEB-DESIGN.md §8.2): navigator.share
    // when available, clipboard fallback with copy confirmation.
    if (shareBtn) {
      shareBtn.addEventListener('click', async () => {
        const url = urlText.textContent || '';
        if (!url) return;
        if (typeof window.bobaShareTarget === 'function') {
          await window.bobaShareTarget({
            title: 'My BOBA collection',
            text: 'Check out my BOBA Playbook collection',
            url,
          }, shareBtn);
        } else {
          // bobaShareTarget should always be present, but fall back
          // to clipboard if app.js hasn't loaded yet.
          try { await navigator.clipboard.writeText(url); } catch (_) {}
        }
      });
    }
  }

  /// Change Password — triggers the native Supabase reset email so
  /// the user can pick a new password from a one-time link. Mirrors
  /// the iOS Profile Change Password row.
  function wireChangePasswordButton(view) {
    const btn    = view.querySelector('#profile-change-password-btn');
    const status = view.querySelector('#profile-change-password-status');
    if (!btn || !status) return;

    btn.addEventListener('click', async () => {
      const email = Auth.getSession()?.user?.email;
      if (!email) {
        status.textContent = 'No email on file — sign out and back in to refresh.';
        status.classList.remove('hidden');
        return;
      }
      btn.disabled = true;
      status.classList.remove('hidden');
      status.textContent = 'Sending reset email…';
      try {
        await API.requestPasswordReset(email);
        status.textContent = `Reset link sent to ${email}. Check your inbox.`;
      } catch (e) {
        status.textContent = 'Could not send reset email. ' + (e?.message || '');
      } finally {
        btn.disabled = false;
      }
    });
  }

  /// Profile avatar editor — click the avatar to open the menu
  /// dialog (Choose from Computer / Use Discord / Remove); selecting
  /// a file opens a canvas-based square crop dialog; confirm posts
  /// the cropped JPEG to the avatar Worker and persists the URL via
  /// set_avatar_url RPC. Resolution priority: custom (R2) →
  /// Discord avatar → silhouette.
  function wireAvatarEditor(view) {
    const btn         = view.querySelector('#profile-avatar-btn');
    const content     = view.querySelector('#profile-avatar-content');
    const fileInput   = view.querySelector('#profile-avatar-file');
    const cropDialog  = view.querySelector('#profile-avatar-crop-dialog');
    const cropCanvas  = view.querySelector('#avatar-crop-canvas');
    const cropStage   = view.querySelector('#avatar-crop-stage');
    const cropConfirm = view.querySelector('#avatar-crop-confirm');
    const cropCancel  = view.querySelector('#avatar-crop-cancel');
    const menuDialog  = view.querySelector('#profile-avatar-menu-dialog');
    const menuChoose  = view.querySelector('#avatar-menu-choose');
    const menuDiscord = view.querySelector('#avatar-menu-discord');
    const menuRemove  = view.querySelector('#avatar-menu-remove');
    const menuCancel  = view.querySelector('#avatar-menu-cancel');
    if (!btn || !fileInput || !cropDialog || !menuDialog) return;

    let currentAvatarUrl = null;       // custom (R2) URL, or null
    let currentDiscordAvatarUrl = null;

    /// Render the avatar — img if we have a URL, silhouette otherwise.
    /// Custom always wins over Discord; Discord wins over silhouette.
    const renderAvatar = () => {
      const url = currentAvatarUrl || currentDiscordAvatarUrl;
      if (url) {
        content.innerHTML =
          `<img src="${esc(url)}" alt="" class="profile-avatar-img" referrerpolicy="no-referrer">`;
      } else {
        content.innerHTML =
          `<svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28" aria-hidden="true">` +
            `<path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-5.33 0-8 2.67-8 4v1h16v-1c0-1.33-2.67-4-8-4z"/>` +
          `</svg>`;
      }
      // Show "Use Discord Avatar" only if we have one available.
      menuDiscord.hidden = !currentDiscordAvatarUrl;
      // Show "Remove" only if a custom avatar is set.
      menuRemove.hidden  = !currentAvatarUrl;
    };

    // Hydrate from fetchProfile.
    API.fetchProfile().then(profile => {
      currentAvatarUrl        = profile?.avatar_url        || null;
      currentDiscordAvatarUrl = profile?.discord_avatar_url || null;
      renderAvatar();
    }).catch(() => { /* offline-safe — keep default silhouette */ });

    // Tap avatar → open menu dialog.
    btn.addEventListener('click', () => {
      if (typeof menuDialog.showModal === 'function') menuDialog.showModal();
      else menuDialog.setAttribute('open', '');
    });
    menuCancel.addEventListener('click', () => menuDialog.close());
    menuChoose.addEventListener('click', () => {
      menuDialog.close();
      fileInput.click();
    });
    menuDiscord.addEventListener('click', async () => {
      menuDialog.close();
      try {
        await API.deleteAvatar();
        await API.setAvatarUrl(null);
        currentAvatarUrl = null;
        renderAvatar();
      } catch (e) {
        if (typeof window.showToast === 'function') {
          window.showToast('Could not switch to Discord avatar — ' + (e?.message || 'try again'));
        }
      }
    });
    menuRemove.addEventListener('click', async () => {
      menuDialog.close();
      try {
        await API.deleteAvatar();
        await API.setAvatarUrl(null);
        currentAvatarUrl = null;
        renderAvatar();
      } catch (e) {
        if (typeof window.showToast === 'function') {
          window.showToast('Could not remove custom avatar — ' + (e?.message || 'try again'));
        }
      }
    });

    // File picked → load image → open crop dialog.
    let cropImg = null;
    let cropOffsetX = 0, cropOffsetY = 0;
    let cropScale = 1.0;
    let dragging = false, dragStartX = 0, dragStartY = 0;

    const drawCrop = () => {
      const ctx = cropCanvas.getContext('2d');
      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, cropCanvas.width, cropCanvas.height);
      if (!cropImg) return;
      // Fit-then-cover the cropImg into the canvas at base scale, then
      // apply user scale + offset.
      const cw = cropCanvas.width, ch = cropCanvas.height;
      const aspect = cropImg.naturalWidth / cropImg.naturalHeight;
      let baseW, baseH;
      if (aspect >= 1) { baseH = ch; baseW = ch * aspect; }
      else             { baseW = cw; baseH = cw / aspect; }
      const drawW = baseW * cropScale;
      const drawH = baseH * cropScale;
      const drawX = (cw - drawW) / 2 + cropOffsetX;
      const drawY = (ch - drawH) / 2 + cropOffsetY;
      ctx.drawImage(cropImg, drawX, drawY, drawW, drawH);
    };

    fileInput.addEventListener('change', () => {
      const file = fileInput.files?.[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        const img = new Image();
        img.onload = () => {
          cropImg = img;
          cropOffsetX = 0; cropOffsetY = 0; cropScale = 1.0;
          drawCrop();
          if (typeof cropDialog.showModal === 'function') cropDialog.showModal();
          else cropDialog.setAttribute('open', '');
        };
        img.src = reader.result;
      };
      reader.readAsDataURL(file);
      fileInput.value = '';  // allow re-selecting the same file
    });

    // Drag + wheel-zoom on the canvas.
    cropCanvas.addEventListener('mousedown', (e) => {
      dragging = true;
      dragStartX = e.clientX - cropOffsetX;
      dragStartY = e.clientY - cropOffsetY;
    });
    document.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      cropOffsetX = e.clientX - dragStartX;
      cropOffsetY = e.clientY - dragStartY;
      drawCrop();
    });
    document.addEventListener('mouseup', () => { dragging = false; });
    cropCanvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      const delta = -e.deltaY * 0.002;
      cropScale = Math.max(0.5, Math.min(4.0, cropScale + delta));
      drawCrop();
    }, { passive: false });
    // Touch support (single-finger drag; pinch-zoom uses two-finger
    // distance — rough but works without a library).
    cropCanvas.addEventListener('touchstart', (e) => {
      if (e.touches.length === 1) {
        dragging = true;
        dragStartX = e.touches[0].clientX - cropOffsetX;
        dragStartY = e.touches[0].clientY - cropOffsetY;
      }
    });
    cropCanvas.addEventListener('touchmove', (e) => {
      if (e.touches.length === 1 && dragging) {
        e.preventDefault();
        cropOffsetX = e.touches[0].clientX - dragStartX;
        cropOffsetY = e.touches[0].clientY - dragStartY;
        drawCrop();
      }
    }, { passive: false });
    cropCanvas.addEventListener('touchend', () => { dragging = false; });

    cropCancel.addEventListener('click', () => cropDialog.close());

    cropConfirm.addEventListener('click', async () => {
      // Render to a 512×512 JPEG, circular mask is purely visual —
      // we upload the square crop; the renderer on display sites
      // applies border-radius: 50%.
      const out = document.createElement('canvas');
      out.width = 512; out.height = 512;
      const octx = out.getContext('2d');
      octx.fillStyle = '#000';
      octx.fillRect(0, 0, 512, 512);
      const cw = cropCanvas.width, ch = cropCanvas.height;
      const aspect = cropImg.naturalWidth / cropImg.naturalHeight;
      let baseW, baseH;
      if (aspect >= 1) { baseH = ch; baseW = ch * aspect; }
      else             { baseW = cw; baseH = cw / aspect; }
      const drawW = baseW * cropScale;
      const drawH = baseH * cropScale;
      const drawX = (cw - drawW) / 2 + cropOffsetX;
      const drawY = (ch - drawH) / 2 + cropOffsetY;
      const sf = 512 / cw;
      octx.drawImage(cropImg, drawX * sf, drawY * sf, drawW * sf, drawH * sf);

      cropConfirm.disabled = true;
      cropConfirm.textContent = 'Uploading…';
      try {
        const blob = await new Promise(r => out.toBlob(r, 'image/jpeg', 0.85));
        if (!blob) throw new Error('Could not encode image');
        if (blob.size > 2 * 1024 * 1024) {
          throw new Error('Image too large after crop. Try a smaller source image.');
        }
        const { url, version } = await API.uploadAvatar(blob);
        await API.setAvatarUrl(url);
        currentAvatarUrl = `${url}?v=${version}`;
        renderAvatar();
        cropDialog.close();
        if (typeof window.showToast === 'function') {
          window.showToast('Avatar updated.');
        }
      } catch (e) {
        // Non-blocking toast — was a blocking alert(); inconsistent
        // with the rest of the app's transient-error pattern (tick 54).
        const msg = e?.message || String(e);
        const friendly = /401|expired|signed in/i.test(msg)
          ? 'Sign-in expired. Sign in again and retry.'
          : /network|fetch|failed to/i.test(msg)
          ? 'Network error. Check your connection and retry.'
          : msg;
        if (typeof window.showToast === 'function') {
          window.showToast('Avatar upload failed: ' + friendly);
        } else {
          alert('Could not upload avatar: ' + friendly);
        }
      } finally {
        cropConfirm.disabled = false;
        cropConfirm.textContent = 'Use Photo';
      }
    });
  }

  function openModSearchPanel() {
    const existing = document.getElementById('mod-panel-overlay');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'mod-panel-overlay';
    overlay.className = 'mod-edit-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'Mod Panel');

    overlay.innerHTML = `
      <div class="mod-edit-panel">
        <div class="mod-edit-header">
          <span class="mod-edit-title">Mod Panel</span>
          <button class="mod-edit-close" aria-label="Close">&times;</button>
        </div>
        <div class="mod-edit-body">
          <p class="mod-edit-note">Search for a card to submit info corrections or flag image issues.</p>
          <input class="mod-edit-input" id="mod-panel-search" type="text"
                 placeholder="Card # or hero name…" autocomplete="off">
          <div id="mod-panel-results" class="mod-panel-results"></div>
        </div>
      </div>`;

    document.body.appendChild(overlay);

    overlay.querySelector('.mod-edit-close').addEventListener('click', () => overlay.remove());
    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });

    const searchInput = overlay.querySelector('#mod-panel-search');
    const resultsEl   = overlay.querySelector('#mod-panel-results');

    searchInput.addEventListener('input', async () => {
      const q = searchInput.value.trim().toLowerCase();
      if (!q) { resultsEl.innerHTML = ''; return; }
      try {
        const cards = await API.loadCards();
        const results = cards.filter(c =>
          String(c.cardNumber).toLowerCase().includes(q) ||
          (c.hero ?? '').toLowerCase().includes(q)
        ).slice(0, 15);

        if (!results.length) {
          resultsEl.innerHTML = `<p class="mod-edit-note">No cards found.</p>`;
          return;
        }
        resultsEl.innerHTML = results.map(c => `
          <button class="mod-result-row" data-card-num="${esc(String(c.cardNumber))}">
            <span class="mod-result-hero">${esc(c.hero || c.cardNumber)}</span>
            <span class="mod-result-num">${esc(c.cardNumber)}</span>
          </button>`).join('');

        resultsEl.querySelectorAll('.mod-result-row').forEach(btn => {
          btn.addEventListener('click', () => {
            const num  = btn.dataset.cardNum;
            const card = results.find(c => String(c.cardNumber) === num);
            if (card) {
              overlay.remove();
              // Re-use the existing openModEditPanel from app.js
              if (typeof openModEditPanel === 'function') {
                openModEditPanel(card);
              }
            }
          });
        });
      } catch {}
    });

    searchInput.focus();
  }

  /* ================================================================
     ADMIN PANEL
  ================================================================ */

  async function openAdminPanel() {
    const existing = document.getElementById('admin-panel-overlay');
    if (existing) existing.remove();

    const overlay = document.createElement('div');
    overlay.id = 'admin-panel-overlay';
    overlay.className = 'mod-edit-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'Admin Panel');

    overlay.innerHTML = `
      <div class="mod-edit-panel admin-panel">
        <div class="mod-edit-header">
          <span class="mod-edit-title">Admin Panel</span>
          <button class="mod-edit-close" aria-label="Close">&times;</button>
        </div>
        <div class="mod-edit-body admin-panel-body">
          <div id="admin-metrics" class="admin-metrics-grid">
            <div class="admin-metric-card"><div class="admin-metric-value" id="metric-users">…</div><div class="admin-metric-label">Total Users</div></div>
            <div class="admin-metric-card"><div class="admin-metric-value" id="metric-corrections">…</div><div class="admin-metric-label">Card Corrections</div></div>
            <div class="admin-metric-card"><div class="admin-metric-value" id="metric-images">…</div><div class="admin-metric-label">Image Overrides</div></div>
          </div>
          <div class="admin-section-label">MOD REQUESTS</div>
          <div id="admin-mod-requests-list" class="admin-user-list">
            <div class="admin-loading">Loading mod requests…</div>
          </div>
          <div class="admin-section-label">MISSING ART</div>
          <div id="admin-images-list" class="admin-user-list">
            <div class="admin-loading">Loading…</div>
          </div>
          <div class="admin-section-label">PENDING CORRECTIONS</div>
          <div id="admin-corrections-list" class="admin-user-list">
            <div class="admin-loading">Loading corrections…</div>
          </div>
          <div class="admin-section-label">USERS</div>
          <div id="admin-user-list" class="admin-user-list">
            <div class="admin-loading">Loading users…</div>
          </div>
        </div>
      </div>`;

    document.body.appendChild(overlay);
    overlay.querySelector('.mod-edit-close').addEventListener('click', () => overlay.remove());
    overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });

    // Load data
    await Promise.all([
      loadAdminMetrics(overlay),
      loadAdminModRequests(overlay),
      loadAdminImageOverrides(overlay),
      loadAdminCorrections(overlay),
      loadAdminUsers(overlay),
    ]);
  }

  async function loadAdminModRequests(overlay) {
    const listEl = overlay.querySelector('#admin-mod-requests-list');
    try {
      const requests = await API.adminFetchPendingModRequests();
      if (!requests.length) {
        listEl.innerHTML = `<p class="mod-edit-note">No pending mod requests.</p>`;
        return;
      }
      listEl.innerHTML = requests.map(r => {
        const date = r.requested_at ? new Date(r.requested_at).toLocaleDateString() : '';
        return `
          <div class="admin-correction-row" data-uid="${esc(r.user_id)}">
            <div class="admin-correction-info">
              <div class="admin-correction-card">${esc(r.email || '(no email)')}</div>
              <div class="admin-user-meta">${esc(date)}</div>
              ${r.reason ? `<div class="admin-correction-notes">"${esc(r.reason)}"</div>` : ''}
            </div>
            <div class="admin-correction-actions">
              <button class="admin-approve-btn" data-uid="${esc(r.user_id)}">Approve ✓</button>
              <button class="admin-reject-btn"  data-uid="${esc(r.user_id)}" style="background:rgba(242,63,67,0.15);color:#F23F43;border-color:rgba(242,63,67,0.3)">Deny ✗</button>
            </div>
          </div>`;
      }).join('');

      const wire = (selector, approve) => {
        listEl.querySelectorAll(selector).forEach(btn => {
          btn.addEventListener('click', async () => {
            btn.disabled = true;
            try {
              await API.adminReviewModRequest(btn.dataset.uid, approve);
              btn.closest('.admin-correction-row').remove();
              if (!listEl.querySelector('.admin-correction-row')) {
                listEl.innerHTML = `<p class="mod-edit-note">No pending mod requests.</p>`;
              }
              if (approve) loadAdminUsers(overlay); // promoted user now shows as moderator
            } catch (e) {
              alert('Failed: ' + e.message);
              btn.disabled = false;
            }
          });
        });
      };
      wire('.admin-approve-btn', true);
      wire('.admin-reject-btn',  false);
    } catch (e) {
      listEl.innerHTML = `<p class="mod-edit-note" style="color:var(--boba-orange)">Error: ${esc(e.message)}</p>`;
    }
  }

  async function loadAdminMetrics(overlay) {
    try {
      const [usersResp, correctionsResp, imagesResp] = await Promise.all([
        API.adminFetchCount('user_profiles'),
        API.adminFetchPendingCount('card_corrections'),
        API.adminFetchPendingCount('card_image_overrides'),
      ]);
      overlay.querySelector('#metric-users').textContent       = usersResp;
      overlay.querySelector('#metric-corrections').textContent = correctionsResp;
      overlay.querySelector('#metric-images').textContent      = imagesResp;
    } catch (e) {
      console.warn('[admin] metrics error', e);
    }
  }

  async function loadAdminImageOverrides(overlay) {
    const listEl = overlay.querySelector('#admin-images-list');
    try {
      const overrides = await API.adminFetchPendingImageOverrides();
      if (!overrides.length) {
        listEl.innerHTML = `<p class="mod-edit-note">No missing art — all images accounted for.</p>`;
        return;
      }
      listEl.innerHTML = overrides.map(o => {
        const date = new Date(o.created_at).toLocaleDateString();
        return `
          <div class="admin-correction-row" data-oid="${esc(o.id)}">
            <div class="admin-correction-info">
              <div class="admin-correction-card">${esc(o.card_number)}</div>
              <div class="admin-correction-fields">
                <span class="correction-field">action: <strong>${esc(o.action)}</strong></span>
              </div>
              <div class="admin-user-meta">${date}</div>
            </div>
            <div class="admin-correction-actions">
              <button class="admin-approve-btn" data-oid="${esc(o.id)}">Approve ✓</button>
              <button class="admin-reject-btn" data-oid="${esc(o.id)}" style="background:rgba(242,63,67,0.15);color:#F23F43;border-color:rgba(242,63,67,0.3)">Reject ✗</button>
            </div>
          </div>`;
      }).join('');

      listEl.querySelectorAll('.admin-approve-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          btn.disabled = true;
          try {
            await API.adminApproveImageOverride(btn.dataset.oid);
            // v2.275 — chain to the boba-mod-merge Worker so the
            // approved row's image is pushed to R2 + CF cache purged
            // + applied_image_file set immediately. Failure is non-
            // fatal: the row stays approved and the daily cron will
            // sweep it.
            try {
              await API.applyImageOverride(btn.dataset.oid);
              if (typeof window.refreshAppliedImageOverrides === 'function') {
                await window.refreshAppliedImageOverrides();
              }
            } catch (mergeErr) {
              console.warn('Immediate merge failed (daily cron will sweep):', mergeErr);
            }
            btn.closest('.admin-correction-row').remove();
            if (!listEl.querySelector('.admin-correction-row')) {
              listEl.innerHTML = `<p class="mod-edit-note">No pending image overrides.</p>`;
            }
            loadAdminMetrics(overlay);
          } catch (e) {
            alert('Failed to approve: ' + e.message);
            btn.disabled = false;
          }
        });
      });

      listEl.querySelectorAll('.admin-reject-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          btn.disabled = true;
          try {
            await API.adminRejectImageOverride(btn.dataset.oid);
            btn.closest('.admin-correction-row').remove();
            if (!listEl.querySelector('.admin-correction-row')) {
              listEl.innerHTML = `<p class="mod-edit-note">No pending image overrides.</p>`;
            }
            loadAdminMetrics(overlay);
          } catch (e) {
            alert('Failed to reject: ' + e.message);
            btn.disabled = false;
          }
        });
      });
    } catch (e) {
      listEl.innerHTML = `<p class="mod-edit-note" style="color:var(--boba-orange)">Error: ${esc(e.message)}</p>`;
    }
  }

  async function loadAdminCorrections(overlay) {
    const listEl = overlay.querySelector('#admin-corrections-list');
    try {
      const corrections = await API.adminFetchPendingCorrections();
      if (!corrections.length) {
        listEl.innerHTML = `<p class="mod-edit-note">No pending corrections.</p>`;
        return;
      }
      listEl.innerHTML = corrections.map(c => {
        const fields = Object.entries(c.corrections || {})
          .map(([k, v]) => `<span class="correction-field">${esc(k)}: <strong>${esc(v)}</strong></span>`)
          .join(' · ');
        const date = new Date(c.created_at).toLocaleDateString();
        return `
          <div class="admin-correction-row" data-cid="${esc(c.id)}">
            <div class="admin-correction-info">
              <div class="admin-correction-card">${esc(c.card_number)}</div>
              <div class="admin-correction-fields">${fields}</div>
              ${c.notes ? `<div class="admin-correction-notes">"${esc(c.notes)}"</div>` : ''}
              <div class="admin-user-meta">${date} · ${c.submitted_by.substring(0, 12)}…</div>
            </div>
            <div class="admin-correction-actions">
              <button class="admin-approve-btn" data-cid="${esc(c.id)}">Approve</button>
              <button class="admin-reject-btn" data-cid="${esc(c.id)}">Reject</button>
            </div>
          </div>`;
      }).join('');

      listEl.querySelectorAll('.admin-approve-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          btn.disabled = true;
          try {
            await API.adminApproveCorrection(btn.dataset.cid);
            btn.closest('.admin-correction-row').remove();
            if (!listEl.querySelector('.admin-correction-row')) {
              listEl.innerHTML = `<p class="mod-edit-note">No pending corrections.</p>`;
            }
          } catch (e) {
            alert('Approve failed: ' + e.message);
            btn.disabled = false;
          }
        });
      });

      listEl.querySelectorAll('.admin-reject-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          if (!confirm('Reject this correction?')) return;
          btn.disabled = true;
          try {
            await API.adminRejectCorrection(btn.dataset.cid);
            btn.closest('.admin-correction-row').remove();
            if (!listEl.querySelector('.admin-correction-row')) {
              listEl.innerHTML = `<p class="mod-edit-note">No pending corrections.</p>`;
            }
          } catch (e) {
            alert('Reject failed: ' + e.message);
            btn.disabled = false;
          }
        });
      });
    } catch (e) {
      listEl.innerHTML = `<p class="mod-edit-note" style="color:var(--boba-orange)">Error: ${esc(e.message)}</p>`;
    }
  }

  async function loadAdminUsers(overlay) {
    const listEl = overlay.querySelector('#admin-user-list');
    try {
      const users = await API.adminFetchUsers();
      const currentUserId = Auth.getSession()?.user?.id;

      if (!users.length) {
        listEl.innerHTML = `<p class="mod-edit-note">No users found.</p>`;
        return;
      }

      // Update total users metric from actual results
      const metricEl = overlay.querySelector('#metric-users');
      if (metricEl) metricEl.textContent = users.length;

      listEl.innerHTML = users.map(u => {
        const isMe      = u.user_id === currentUserId;
        const roleClass = u.role === 'admin' ? 'badge-admin' : u.role === 'moderator' ? 'badge-mod' : 'badge-user';
        const joined    = new Date(u.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
        const lastSeen  = u.last_sign_in_at
          ? _relativeTime(new Date(u.last_sign_in_at))
          : 'never';
        const nameHtml  = u.display_name
          ? `<div class="admin-user-name">${esc(u.display_name)}${isMe ? ' <span class="admin-you-badge">YOU</span>' : ''}</div>
             <div class="admin-user-email">${esc(u.email || '')}</div>`
          : `<div class="admin-user-email">${esc(u.email || 'Unknown')}${isMe ? ' <span class="admin-you-badge">YOU</span>' : ''}</div>`;
        const valueStr  = u.total_collection_value > 0
          ? ` · $${Math.round(u.total_collection_value).toLocaleString()} est.`
          : '';
        // Avatar resolver: custom (R2) > Discord > silhouette.
        // Same precedence as Profile / public-collection page.
        const avatarUrl = u.avatar_url || u.discord_avatar_url;
        const avatarHtml = avatarUrl
          ? `<img class="admin-user-avatar-img" src="${esc(avatarUrl)}" alt="" referrerpolicy="no-referrer">`
          : `<svg viewBox="0 0 24 24" fill="currentColor" width="18" height="18"><path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-5.33 0-8 2.67-8 4v1h16v-1c0-1.33-2.67-4-8-4z"/></svg>`;
        // @username + PUBLIC pill — only when set. Mirrors iOS.
        const handleHtml = u.username
          ? `<div class="admin-user-handle">
               <span class="admin-user-handle-name">@${esc(u.username)}</span>
               ${u.public_collection_enabled
                 ? '<span class="admin-public-pill">PUBLIC</span>'
                 : ''}
             </div>`
          : '';
        // Public collection link — only when sharing is on.
        const publicURL = (u.public_collection_enabled && u.username)
          ? `https://bobaplaybook.com/u/${u.username}`
          : null;
        const publicLinkHtml = publicURL
          ? `<div class="admin-user-public-link">
               <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                    stroke-linecap="round" stroke-linejoin="round" width="11" height="11" aria-hidden="true">
                 <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
                 <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
               </svg>
               <a href="${esc(publicURL)}" target="_blank" rel="noopener noreferrer">${esc(publicURL.replace('https://', ''))}</a>
               <button class="admin-user-copy-btn" data-url="${esc(publicURL)}"
                       aria-label="Copy public collection URL" title="Copy URL">
                 <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                      stroke-linecap="round" stroke-linejoin="round" width="11" height="11" aria-hidden="true">
                   <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                   <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
                 </svg>
               </button>
             </div>`
          : '';
        return `
          <div class="admin-user-row" data-uid="${esc(u.user_id)}">
            <div class="admin-user-avatar">${avatarHtml}</div>
            <div class="admin-user-info">
              ${nameHtml}
              ${handleHtml}
              <div class="admin-user-meta">Joined ${joined} · Last seen ${lastSeen}</div>
              <div class="admin-user-collection">${u.collection_count} card${u.collection_count === 1 ? '' : 's'} in collection${valueStr}</div>
              ${publicLinkHtml}
            </div>
            <div class="admin-user-role">
              <span class="admin-role-badge ${roleClass}">${u.role.toUpperCase()}</span>
              ${!isMe ? `<button class="admin-role-btn" data-uid="${esc(u.user_id)}" data-role="${esc(u.role)}">Change</button>` : ''}
            </div>
          </div>`;
      }).join('');

      // Wire copy buttons — uses bobaShareTarget for the same
      // copy-link-with-toast UX as the rest of the app.
      listEl.querySelectorAll('.admin-user-copy-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.preventDefault();
          const url = btn.dataset.url;
          if (!url) return;
          if (typeof window.bobaShareTarget === 'function') {
            window.bobaShareTarget({ title: 'Public Collection', url }, btn);
          } else {
            navigator.clipboard?.writeText(url);
          }
        });
      });

      listEl.querySelectorAll('.admin-role-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          const uid   = btn.dataset.uid;
          const cur   = btn.dataset.role;
          const next  = cur === 'user' ? 'moderator' : cur === 'moderator' ? 'admin' : 'user';
          if (!confirm(`Change role for this user: ${cur} → ${next}?`)) return;
          try {
            await API.adminUpdateRole(uid, next);
            await loadAdminUsers(overlay);
          } catch (e) {
            alert('Role update failed: ' + e.message);
          }
        });
      });
    } catch (e) {
      listEl.innerHTML = `<p class="mod-edit-note" style="color:var(--boba-orange)">Error: ${esc(e.message)}</p>`;
    }
  }

  function _relativeTime(date) {
    const diff = Date.now() - date.getTime();
    const mins  = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days  = Math.floor(diff / 86400000);
    if (mins  <  2)  return 'just now';
    if (mins  < 60)  return `${mins}m ago`;
    if (hours < 24)  return `${hours}h ago`;
    if (days  <  7)  return `${days}d ago`;
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  }

  /* ================================================================
     COLLECTION CARD DETAIL OVERLAY
  ================================================================ */

  function openCollectionDetail(cardNumber) {
    _detailNum   = String(cardNumber);
    _detailState = 'view';
    _editEntry   = null;
    renderCollectionDetail();
    const overlay = document.getElementById('cdetail-overlay');
    overlay.hidden = false;
    document.body.style.overflow = 'hidden';
    overlay.addEventListener('click', _onDetailOverlayClick);
  }

  function _onDetailOverlayClick(e) {
    if (e.target === document.getElementById('cdetail-overlay')) closeCollectionDetail();
  }

  function closeCollectionDetail() {
    const overlay = document.getElementById('cdetail-overlay');
    overlay.hidden = true;
    overlay.removeEventListener('click', _onDetailOverlayClick);
    document.body.style.overflow = '';
    _detailNum   = null;
    _detailState = 'view';
    _editEntry   = null;
  }

  function renderCollectionDetail() {
    const box = document.getElementById('cdetail-box');
    if (!box) return;

    if (_detailState === 'edit' && _editEntry) {
      box.innerHTML = _buildEditFormHtml();
      _wireEditForm();
      return;
    }

    const cardNum     = _detailNum; // may be a bobaId (new) or card_number (legacy)
    // Prefer bobaId lookup for exact card identity; fall back to card_number lookup for legacy
    const catalogCard = (_bobaIdLookup ? _bobaIdLookup(cardNum) : null) ?? (_cardLookup ? _cardLookup(cardNum) : null);
    const cardName    = catalogCard?.name    || cardNum;
    const imageFile   = catalogCard?.imageFile;
    const element     = catalogCard?.element || 'NONE';
    const treatment   = catalogCard?.treatment;
    const power       = catalogCard?.power;
    const hero        = catalogCard?.hero;

    // Match entries by bobaId first; fall back to card_number for legacy nil-bobaId rows
    const myEntries = _cards.filter(c =>
      c.boba_id === cardNum || (c.boba_id == null && c.card_number === cardNum)
    );

    const variations = (hero && _variantLookup)
      ? _variantLookup(hero, cardNum)
      : [];

    // Card header image. Route through API.cardFullUrl so sealed
    // products land on /sealed/optimized/, not /full/.
    const fullSrc = catalogCard ? API.cardFullUrl(catalogCard) : null;
    const imgHtml = fullSrc
      ? `<img class="cdetail-card-img" src="${esc(fullSrc)}"
              alt="${esc(cardName)}" loading="lazy" decoding="async">`
      : `<div class="cdetail-card-img cdetail-card-img-placeholder" data-element="${esc(element)}">
           <span class="placeholder-brand">BOBA PB</span>
           <span class="placeholder-status">Image Pending</span>
         </div>`;

    const tfClass = _getTreatmentClass(treatment);

    const headerHtml = `
      <div class="cdetail-header">
        ${imgHtml}
        <div class="cdetail-card-info">
          <div class="cdetail-card-name">${esc(cardName)}</div>
          <div class="cdetail-card-num">#${esc(catalogCard?.cardNumber || cardNum)}</div>
          <div class="cdetail-badges-row">
            <span class="element-badge" data-element="${esc(element)}">${esc(element)}</span>
            ${treatment ? `<span class="treatment-banner ${esc(tfClass)}">${esc(treatment)}</span>` : ''}
          </div>
          ${power != null ? `<div class="cdetail-card-power">${esc(String(power))} PWR</div>` : ''}
        </div>
      </div>`;

    // My copies
    const copiesHtml = myEntries.length === 0
      ? `<p class="cdetail-empty">No copies found.</p>`
      : myEntries.map(_buildEntryRowHtml).join('');

    // Variations
    const variationsHtml = variations.length === 0 ? '' : `
      <div class="cdetail-section">
        <div class="cdetail-section-title">OTHER VERSIONS (${variations.length})</div>
        <div class="cdetail-variations-scroll">
          ${variations.map(_buildVariationTileHtml).join('')}
        </div>
      </div>`;

    box.innerHTML = `
      <button class="modal-close" id="cdetail-close-btn" aria-label="Close detail">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"
             width="18" height="18" aria-hidden="true">
          <path d="M18 6 6 18M6 6l12 12"/>
        </svg>
      </button>
      <div class="cdetail-inner">
        ${headerHtml}
        <div class="cdetail-section">
          <div class="cdetail-section-hdr">
            <span class="cdetail-section-title">MY COPIES (${myEntries.length})</span>
            ${catalogCard ? `<button class="cdetail-add-btn" id="cdetail-add-btn">+ Add Copy</button>` : ''}
          </div>
          ${copiesHtml}
        </div>
        ${variationsHtml}
      </div>`;

    box.querySelector('#cdetail-close-btn')
      .addEventListener('click', closeCollectionDetail);

    // Add copy button — open add sheet on top; detail stays open underneath
    box.querySelector('#cdetail-add-btn')
      ?.addEventListener('click', () => {
        if (catalogCard) openAddSheet(catalogCard);
      });

    // Edit buttons
    box.querySelectorAll('[data-edit-entry-id]').forEach(btn => {
      btn.addEventListener('click', () => {
        _editEntry   = _cards.find(c => c.id === btn.dataset.editEntryId) || null;
        _detailState = 'edit';
        renderCollectionDetail();
      });
    });

    // Delete buttons — tick 123 replaced the blocking confirm() with
    // an inline Undo toast (3-platform parity: iOS tick 122 banner +
    // Android tick 119 Snackbar+Undo). The Undo toast IS the safety
    // net so the modal-blocking confirm is no longer the right shape.
    box.querySelectorAll('[data-delete-entry-id]').forEach(btn => {
      btn.addEventListener('click', async () => {
        const id = btn.dataset.deleteEntryId;
        // Capture the entry BEFORE delete so Undo can re-add with the
        // full field set (designation / purchase_price / asking_price /
        // condition / notes). Without this, accidental delete drops
        // any per-copy provenance metadata.
        const captured = _cards.find(c => c.id === id);
        if (!captured) return;
        try {
          await API.collectionDelete(id);
          _cards = _cards.filter(c => c.id !== id);
          renderCollectionView();
          renderProfileView();
          const remaining = _cards.filter(c =>
            c.boba_id === cardNum || (c.boba_id == null && c.card_number === cardNum)
          );
          if (remaining.length === 0) closeCollectionDetail();
          else renderCollectionDetail();
          // Undo toast — `showUndoToast` is a script-global from
          // practice.js (tick 118). On Undo we re-add via API.collectionAdd
          // with every captured field so the round-trip is lossless.
          const label = captured.hero || captured.name || 'card';
          if (typeof window.showUndoToast === 'function') {
            window.showUndoToast(`Removed ${label}`, async () => {
              try {
                const saved = await API.collectionAdd({
                  card_number:   captured.card_number,
                  boba_id:       captured.boba_id,
                  hero:          captured.hero,
                  name:          captured.name,
                  element:       captured.element,
                  treatment:     captured.treatment,
                  variation:     captured.variation,
                  designation:   captured.designation,
                  condition:     captured.condition,
                  purchase_price: captured.purchase_price,
                  asking_price:  captured.asking_price,
                  notes:         captured.notes,
                });
                _cards.push(saved);
                renderCollectionView();
                renderProfileView();
                renderCollectionDetail();
              } catch (e) {
                if (typeof window.showToast === 'function') {
                  window.showToast('Undo failed — re-add manually.');
                }
              }
            });
          }
        } catch (err) {
          if (typeof window.showToast === 'function') {
            window.showToast('Could not remove: ' + (err?.message || 'try again'));
          }
        }
      });
    });

    // Variation tile clicks — open card modal on top; detail stays open underneath
    box.querySelectorAll('[data-variant-num]').forEach(tile => {
      tile.addEventListener('click', () => {
        document.dispatchEvent(new CustomEvent('open-card-by-number', { detail: { cardNumber: tile.dataset.variantNum } }));
      });
    });
  }

  function _buildEntryRowHtml(entry) {
    const designLabel = DESIGNATIONS.find(d => d.key === entry.designation)?.label || entry.designation;
    const condText    = entry.condition ? entry.condition.replace('_', ' ') : null;
    return `
      <div class="cdetail-entry">
        <div class="cdetail-entry-main">
          <div class="cdetail-entry-top">
            <span class="desig-badge desig-${esc(entry.designation)}">${esc(designLabel)}</span>
            ${condText ? `<span class="ccard-condition">${esc(condText)}${entry.grade ? ` · ${esc(entry.grade)}` : ''}</span>` : ''}
            ${entry.serial_number ? `<span class="cdetail-serial">${esc(entry.serial_number)}</span>` : ''}
          </div>
          ${entry.purchase_price != null
            ? `<div class="cdetail-entry-price">$${Number(entry.purchase_price).toFixed(2)}<span class="cdetail-entry-price-label"> PAID</span></div>`
            : ''}
          ${entry.notes ? `<div class="cdetail-entry-notes">${esc(entry.notes)}</div>` : ''}
        </div>
        <div class="cdetail-entry-actions">
          <button class="cdetail-entry-btn" data-edit-entry-id="${esc(entry.id)}" aria-label="Edit copy">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                 width="15" height="15" aria-hidden="true">
              <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
              <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
            </svg>
          </button>
          <button class="cdetail-entry-btn cdetail-entry-btn-del" data-delete-entry-id="${esc(entry.id)}" aria-label="Remove copy">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                 width="15" height="15" aria-hidden="true">
              <path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>
            </svg>
          </button>
        </div>
      </div>`;
  }

  function _buildVariationTileHtml(card) {
    const num     = String(card.cardNumber);
    const bid     = String(card.bobaId || num);
    // Match by bobaId first for exact card identity; fall back to card_number for legacy rows
    const owned   = _cards.some(c =>
      ['personal','for_sale','for_trade'].includes(c.designation) &&
      (c.boba_id === bid || (c.boba_id == null && c.card_number === num))
    );
    const wanted  = !owned && _cards.some(c =>
      c.designation === 'wanted' &&
      (c.boba_id === bid || (c.boba_id == null && c.card_number === num))
    );
    const thumbSrc = card.imageFile ? API.cardThumbUrl(card) : null;
    const imgHtml = thumbSrc
      ? `<img class="cdetail-var-img" src="${esc(thumbSrc)}"
              alt="${esc(card.name)}" loading="lazy" decoding="async">`
      : `<div class="cdetail-var-img cdetail-var-img-ph" data-element="${esc(card.element || 'NONE')}"><span>?</span></div>`;
    const badge = owned
      ? `<span class="cdetail-var-own owned">✓</span>`
      : wanted
      ? `<span class="cdetail-var-own wanted">★</span>`
      : '';
    return `
      <button class="cdetail-var-tile" data-variant-num="${esc(num)}">
        <div class="cdetail-var-img-wrap">${imgHtml}${badge}</div>
        <div class="cdetail-var-label">${esc(card.treatment || card.set || '')}</div>
      </button>`;
  }

  function _buildEditFormHtml() {
    const entry    = _editEntry;
    const cardName = (_cardLookup ? _cardLookup(_detailNum)?.name : null) || _detailNum;
    return `
      <button class="modal-close" id="cdetail-close-btn" aria-label="Close">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"
             width="18" height="18" aria-hidden="true">
          <path d="M18 6 6 18M6 6l12 12"/>
        </svg>
      </button>
      <div class="cdetail-inner">
        <div class="cdetail-edit-hdr">
          <button class="cdetail-back-btn" id="cdetail-back-btn" aria-label="Back to detail">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"
                 width="16" height="16" aria-hidden="true">
              <path d="M15 18l-6-6 6-6"/>
            </svg>
          </button>
          <div>
            <div class="cdetail-edit-title">Edit Entry</div>
            <div class="cdetail-edit-subtitle">${esc(cardName)}</div>
          </div>
        </div>
        <form class="add-form" id="cdetail-edit-form" novalidate>
          <div class="form-field">
            <label class="form-label" for="cedit-desig">DESIGNATION</label>
            <select class="form-input form-select" id="cedit-desig">
              ${DESIGNATIONS.map(d =>
                `<option value="${d.key}"${entry.designation === d.key ? ' selected' : ''}>${esc(d.label)}</option>`
              ).join('')}
            </select>
          </div>
          <div class="form-field">
            <label class="form-label" for="cedit-condition">CONDITION</label>
            <select class="form-input form-select" id="cedit-condition">
              <option value="">Select…</option>
              ${['mint','near_mint','excellent','good','poor'].map(v =>
                `<option value="${v}"${entry.condition === v ? ' selected' : ''}>${v.replace('_',' ')}</option>`
              ).join('')}
            </select>
          </div>
          <div class="form-row">
            <div class="form-field">
              <label class="form-label" for="cedit-price">PURCHASE PRICE ($)</label>
              <input class="form-input" type="number" id="cedit-price"
                     placeholder="0.00" min="0" step="0.01"
                     value="${entry.purchase_price != null ? entry.purchase_price : ''}">
            </div>
          </div>
          <div class="form-field">
            <label class="form-label" for="cedit-notes">NOTES</label>
            <input class="form-input" type="text" id="cedit-notes"
                   placeholder="Optional notes…"
                   value="${esc(entry.notes || '')}">
          </div>
          <p class="add-error" id="cedit-error" hidden role="alert"></p>
          <button type="submit" class="btn-primary add-submit-btn" id="cedit-submit">
            Save Changes
          </button>
        </form>
      </div>`;
  }

  function _wireEditForm() {
    const box = document.getElementById('cdetail-box');

    box.querySelector('#cdetail-close-btn')
      .addEventListener('click', closeCollectionDetail);

    box.querySelector('#cdetail-back-btn')
      .addEventListener('click', () => {
        _detailState = 'view';
        _editEntry   = null;
        renderCollectionDetail();
      });

    box.querySelector('#cdetail-edit-form')
      .addEventListener('submit', async e => {
        e.preventDefault();
        const btn = document.getElementById('cedit-submit');
        btn.disabled = true; btn.textContent = 'Saving…';

        const priceVal  = document.getElementById('cedit-price')?.value;

        const fields = {
          designation:    document.getElementById('cedit-desig')?.value    || _editEntry.designation,
          condition:      document.getElementById('cedit-condition')?.value || null,
          purchase_price: priceVal ? Number(priceVal) : null,
          notes:          document.getElementById('cedit-notes')?.value.trim() || null,
        };

        try {
          const captured = _editEntry;  // capture before clearing state below
          const updated = await API.collectionUpdate(_editEntry.id, fields);
          const idx = _cards.findIndex(c => c.id === updated.id);
          if (idx !== -1) _cards[idx] = updated;
          _detailState = 'view';
          _editEntry   = null;
          renderCollectionDetail();
          renderCollectionView();
          renderProfileView();
          // Confirmation toast — closes 3-platform parity with iOS
          // dismiss-as-confirmation + Android tick 151's Snackbar.
          // Without it, web users had no signal the save persisted
          // (the dismissed edit-state could look the same as an
          // un-submitted form if the user lost their place).
          if (typeof window.showToast === 'function') {
            const label = captured?.hero || captured?.name || 'card';
            window.showToast(`Saved edits to ${label}`);
          }
        } catch (err) {
          const errEl = document.getElementById('cedit-error');
          if (errEl) { errEl.textContent = err.message; errEl.hidden = false; }
          btn.disabled = false; btn.textContent = 'Save Changes';
        }
      });
  }

  /* ================================================================
     ADD TO COLLECTION SHEET
  ================================================================ */

  function openAddSheet(card) {
    if (!Auth.isAuthenticated()) { Auth.open(); return; }

    _addCard = card;
    const overlay = document.getElementById('add-collection-overlay');
    const box     = document.getElementById('add-collection-box');

    // Match existing entries by bobaId for exact card identity; fall back to card_number for legacy
    const existing = _cards.filter(c =>
      (card.bobaId && c.boba_id === String(card.bobaId)) ||
      (c.boba_id == null && c.card_number === String(card.cardNumber))
    );
    const existingHtml = existing.length > 0
      ? `<div class="add-existing-notice">
           Already in collection:
           ${existing.map(e => {
             const label = DESIGNATIONS.find(d => d.key === e.designation)?.label || e.designation;
             return `<span class="desig-badge desig-${esc(e.designation)}">${esc(label)}</span>`;
           }).join(' ')}
         </div>`
      : '';

    box.innerHTML = `
      <button class="modal-close" id="add-close-btn" aria-label="Close add to collection">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"
             width="18" height="18" aria-hidden="true">
          <path d="M18 6 6 18M6 6l12 12"/>
        </svg>
      </button>
      <div class="add-sheet-inner">
        <h3 class="add-sheet-title">Add to Collection</h3>
        <div class="add-card-label">
          <span class="add-card-name">${esc(card.name)}</span>
          <span class="add-card-num">#${esc(String(card.cardNumber))}</span>
        </div>
        ${existingHtml}
        <form class="add-form" id="add-form" novalidate>
          <div class="form-field">
            <label class="form-label" for="add-desig">DESIGNATION</label>
            <select class="form-input form-select" id="add-desig">
              <option value="personal">Personal</option>
              <option value="for_sale">For Sale</option>
              <option value="for_trade">For Trade</option>
              <option value="wanted">Wanted</option>
              <option value="grails">Grails</option>
            </select>
          </div>
          <div class="form-field">
            <label class="form-label" for="add-condition">CONDITION</label>
            <select class="form-input form-select" id="add-condition">
              <option value="">Select…</option>
              <option value="mint">Mint</option>
              <option value="near_mint">Near Mint</option>
              <option value="excellent">Excellent</option>
              <option value="good">Good</option>
              <option value="poor">Poor</option>
            </select>
          </div>
          <div class="form-row">
            <div class="form-field">
              <label class="form-label" for="add-price">PURCHASE PRICE ($)</label>
              <input class="form-input" type="number" id="add-price"
                     placeholder="0.00" min="0" step="0.01">
            </div>
          </div>
          <div class="form-field">
            <label class="form-label" for="add-notes">NOTES</label>
            <input class="form-input" type="text" id="add-notes"
                   placeholder="Optional notes…">
          </div>
          <p class="add-error" id="add-error" hidden role="alert"></p>
          <button type="submit" class="btn-primary add-submit-btn" id="add-submit">
            Add to Collection
          </button>
        </form>
      </div>`;

    // Native <dialog> per WEB-DESIGN.md §13.
    if (typeof overlay.showModal === 'function' && !overlay.open) {
      overlay.showModal();
    } else {
      overlay.hidden = false;
      document.body.style.overflow = 'hidden';
    }

    box.querySelector('#add-close-btn').addEventListener('click', closeAddSheet);
    overlay.addEventListener('click', e => { if (e.target === overlay) closeAddSheet(); });
    overlay.addEventListener('cancel', e => {  // ESC dismiss
      e.preventDefault();
      closeAddSheet();
    });
    box.querySelector('#add-form').addEventListener('submit', async e => {
      e.preventDefault();
      await handleAddSubmit();
    });
  }

  function closeAddSheet() {
    const overlay = document.getElementById('add-collection-overlay');
    if (typeof overlay?.close === 'function' && overlay.open) {
      overlay.close();
    } else if (overlay) {
      overlay.hidden = true;
      document.body.style.overflow = '';
    }
    _addCard = null;
  }

  async function handleAddSubmit() {
    if (!_addCard) return;
    const btn = document.getElementById('add-submit');
    btn.disabled = true; btn.textContent = 'Adding…';

    const priceVal  = document.getElementById('add-price')?.value;

    const card = {
      card_number:    String(_addCard.cardNumber),
      boba_id:        _addCard.bobaId ? String(_addCard.bobaId) : undefined,
      designation:    document.getElementById('add-desig')?.value      || 'personal',
      condition:      document.getElementById('add-condition')?.value   || null,
      purchase_price: priceVal ? Number(priceVal) : null,
      notes:          document.getElementById('add-notes')?.value.trim() || null,
    };

    try {
      const saved = await API.collectionAdd(card);
      _cards.push(saved);
      closeAddSheet();
      renderCollectionView();
      renderProfileView();
      // Toast confirmation — parity with iOS tick 102 + Android tick 96.
      // Per-designation label so user sees WHERE the add landed (the
      // sheet defaults to Personal but the user may have switched).
      const desigLabel = (DESIGNATIONS.find(d => d.key === card.designation)?.label) || card.designation;
      if (typeof window.showToast === 'function') {
        window.showToast(`Added to ${desigLabel}`);
      }
      // If collection detail is open for this card, refresh it with the new copy
      const addedId = _addCard.bobaId ? String(_addCard.bobaId) : String(_addCard.cardNumber);
      if (_detailNum === addedId) renderCollectionDetail();
    } catch (err) {
      const errEl = document.getElementById('add-error');
      if (errEl) { errEl.textContent = err.message; errEl.hidden = false; }
      btn.disabled = false; btn.textContent = 'Add to Collection';
    }
  }

  /* ================================================================
     PUBLIC HELPERS — used by app.js card modal
  ================================================================ */

  /* ================================================================
     HELPERS
  ================================================================ */

  // Mirrors getTreatmentClass in app.js — must stay in sync
  function _getTreatmentClass(treatment) {
    if (!treatment) return 'tf-base';
    const t = treatment.toLowerCase();
    if (t.includes('blizzard'))                                  return 'tf-blizzard';
    if (t.includes('superfoil'))                                 return 'tf-superfoil';
    if (t.includes('battlefoil'))                                return 'tf-battlefoil';
    if (t.includes('inspired ink') || t.includes('inspired-ink')) return 'tf-inspired';
    if (t.includes('inspired'))                                  return 'tf-inspired-m';
    if (t.includes('logofoil'))                                  return 'tf-logofoil';
    if (t.includes('blast'))                                     return 'tf-blast';
    if (t.includes('paper'))                                     return 'tf-paper';
    if (t === 'base' || t === 'standard' || t === '')            return 'tf-base';
    return 'tf-special';
  }

  function esc(str) {
    if (str == null) return '';
    const d = document.createElement('div');
    d.textContent = String(str);
    return d.innerHTML;
  }

  /* ================================================================
     INIT
  ================================================================ */

  function init() {
    // React to auth state changes
    document.addEventListener('auth-change', ({ detail: { session } }) => {
      if (session) load();
      else clear();
    });

    // Initial render (signed-out state before Supabase loads)
    renderCollectionView();
    renderProfileView();

    // Wire Custom Rainbow editor (create/edit/delete).
    wireCustomRainbowEditor();
  }

  /* ────────────────────────────────────────────────────────────────
     CUSTOM RAINBOW EDITOR — first slice. Name only; sub-pickers
     land in a later tick. Save / delete via API.createCustomRainbow
     / updateCustomRainbow / deleteCustomRainbow.
  ──────────────────────────────────────────────────────────────── */

  let _editingRainbow = null;   // null = create-new; non-null = edit
  let _draftCriteria  = {};     // edit-form's in-flight criteria

  // The seven catalog filter dimensions + the inspired-ink toggle —
  // verbatim parity with iOS RainbowCriteria's struct shape (the
  // matcher in API.rainbowCriteriaMatches consumes these keys).
  const RAINBOW_DIMS = [
    { key: 'heroes',     label: 'Heroes',     field: 'hero' },
    { key: 'sets',       label: 'Sets',       field: 'set' },
    { key: 'subSets',    label: 'Sub-sets',   field: 'subSet' },
    { key: 'elements',   label: 'Weapons',    field: 'element' },
    { key: 'treatments', label: 'Treatments', field: 'treatment' },
    { key: 'cardTypes',  label: 'Card types', field: 'cardType' },
    { key: 'releases',   label: 'Releases',   field: 'release' },
  ];

  /// Distinct non-empty values for one dimension across the catalog,
  /// sorted case-insensitively. Memoized per dimension since the
  /// catalog doesn't change during a session.
  const _distinctValuesCache = {};
  function distinctCatalogValues(dimKey) {
    if (_distinctValuesCache[dimKey]) return _distinctValuesCache[dimKey];
    const catalog = window.__bobaCatalog || [];
    const field = RAINBOW_DIMS.find(d => d.key === dimKey)?.field;
    if (!field) return [];
    const seen = new Set();
    for (const c of catalog) {
      const v = c?.[field];
      if (typeof v === 'string' && v.trim()) seen.add(v);
    }
    const sorted = [...seen].sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
    _distinctValuesCache[dimKey] = sorted;
    return sorted;
  }

  function _criteriaSelections(criteria, dimKey) {
    const list = criteria?.[dimKey];
    return new Set(Array.isArray(list) ? list.map(v => String(v).toLowerCase()) : []);
  }

  /// Render one filter dimension's checkbox list inside its
  /// `.rainbow-filter-body`. Each option is a `<label><input
  /// type="checkbox">`. Selected count surfaces in the `<summary>`.
  ///
  /// Long lists (Heroes ~500, Sets ~80) get a per-picker search
  /// input at the top — case-insensitive substring filter on the
  /// option labels. Hides non-matching `<label>`s in place; checked
  /// state survives because we only toggle `display`, never re-render.
  function _renderFilterDim(dim) {
    const detailsEl = document.querySelector(`.rainbow-filter[data-dim="${dim.key}"]`);
    if (!detailsEl) return;
    const bodyEl  = detailsEl.querySelector('.rainbow-filter-body');
    const countEl = detailsEl.querySelector('.rainbow-filter-count');
    const values  = distinctCatalogValues(dim.key);
    const selected = _criteriaSelections(_draftCriteria, dim.key);
    // Search input only appears when the list is long enough to
    // benefit from it. Below ~20 entries, all values fit visibly
    // already and a search input is dead chrome.
    const showSearch = values.length >= 20;
    const searchHtml = showSearch
      ? `<input type="search" class="rainbow-filter-search"
                placeholder="Search ${esc(dim.label.toLowerCase())}…"
                aria-label="Search ${esc(dim.label.toLowerCase())}" />`
      : '';
    // Per-picker "Clear all" — appears when at least one option is
    // checked. Matches iOS MultiSelectPicker's destructive button
    // (CustomRainbowEditorSheet.swift line 304). Lets the user reset
    // a noisy filter without un-checking each box individually.
    const clearHtml = selected.size > 0
      ? `<button type="button" class="rainbow-filter-clear" data-clear-dim="${esc(dim.key)}"
                 aria-label="Clear all ${esc(dim.label.toLowerCase())}">Clear ${selected.size}</button>`
      : '';
    const optionsHtml = values.map(v => `
      <label class="rainbow-filter-option" data-search="${esc(v.toLowerCase())}">
        <input type="checkbox" data-value="${esc(v)}" ${selected.has(v.toLowerCase()) ? 'checked' : ''} />
        <span>${esc(v)}</span>
      </label>
    `).join('');
    bodyEl.innerHTML = `${searchHtml}${clearHtml}<div class="rainbow-filter-options">${optionsHtml}</div>`;
    countEl.textContent = selected.size > 0 ? `· ${selected.size}` : '';
    // Wire per-picker search — hides non-matching labels without
    // touching their checked state.
    if (showSearch) {
      const searchEl = bodyEl.querySelector('.rainbow-filter-search');
      const optsEl   = bodyEl.querySelector('.rainbow-filter-options');
      searchEl?.addEventListener('input', () => {
        const q = (searchEl.value || '').trim().toLowerCase();
        optsEl.querySelectorAll('.rainbow-filter-option').forEach(opt => {
          const m = !q || (opt.dataset.search || '').includes(q);
          opt.style.display = m ? '' : 'none';
        });
      });
    }
    // Wire per-picker "Clear all" — wipes the dimension's selections,
    // updates the draft criteria, re-renders the picker (to drop the
    // button + sync the count badge), and refreshes the preview.
    const clearBtn = bodyEl.querySelector('.rainbow-filter-clear');
    clearBtn?.addEventListener('click', () => {
      delete _draftCriteria[dim.key];
      _renderFilterDim(dim);
      _renderPreview();
    });
  }

  /// Recompute "X cards match · Y of those owned (Z%)" from the
  /// current draft criteria. Cheap enough to call on every checkbox
  /// toggle even at 17k cards.
  function _renderPreview() {
    const catalog = window.__bobaCatalog || [];
    const countEl = document.getElementById('custom-rainbow-editor-preview-count');
    const ownedEl = document.getElementById('custom-rainbow-editor-preview-owned');
    if (!countEl || !ownedEl) return;
    if (!catalog.length) {
      countEl.textContent = '… loading catalog';
      ownedEl.textContent = '';
      return;
    }
    const matching = catalog.filter(c => API.rainbowCriteriaMatches(c, _draftCriteria));
    const ownedKeys = new Set(_cards
      .filter(c => ['personal','for_sale','for_trade'].includes(c.designation))
      .map(c => c.boba_id || c.card_number));
    const ownedMatching = matching.filter(c => ownedKeys.has(c.bobaId) || ownedKeys.has(c.cardNumber));
    countEl.textContent = `${matching.length.toLocaleString()} card${matching.length === 1 ? '' : 's'} match`;
    const pct = matching.length === 0 ? 0
      : Math.round((ownedMatching.length / matching.length) * 100);
    ownedEl.textContent = `${ownedMatching.length} of those owned (${pct}%)`;
  }

  function _updateFilterCount(dimKey, delta) {
    const detailsEl = document.querySelector(`.rainbow-filter[data-dim="${dimKey}"]`);
    if (!detailsEl) return;
    const countEl = detailsEl.querySelector('.rainbow-filter-count');
    const list = _draftCriteria[dimKey] || [];
    countEl.textContent = list.length > 0 ? `· ${list.length}` : '';
  }

  function openCustomRainbowEditor(rainbow) {
    const dlg = document.getElementById('custom-rainbow-editor');
    const titleEl = document.getElementById('custom-rainbow-editor-title');
    const nameEl  = document.getElementById('custom-rainbow-editor-name');
    const delBtn  = document.getElementById('custom-rainbow-editor-delete');
    const errEl   = document.getElementById('custom-rainbow-editor-error');
    const inkEl   = document.getElementById('custom-rainbow-editor-inspiredink');
    if (!dlg || !nameEl) return;
    _editingRainbow = rainbow || null;
    // Deep-clone existing criteria so cancelling doesn't mutate the
    // cached rainbow row.
    _draftCriteria = rainbow
      ? JSON.parse(JSON.stringify(rainbow.criteria || {}))
      : {};
    titleEl.textContent = rainbow ? 'Edit Rainbow' : 'New Rainbow';
    nameEl.value = rainbow?.name || '';
    if (inkEl) inkEl.checked = !!_draftCriteria.inspiredInkOnly;
    delBtn.hidden = !rainbow;
    errEl.hidden = true;
    errEl.textContent = '';
    // Hydrate each filter dimension's checkbox list from the catalog.
    RAINBOW_DIMS.forEach(_renderFilterDim);
    _renderPreview();
    if (typeof dlg.showModal === 'function') dlg.showModal();
    setTimeout(() => nameEl.focus(), 50);
  }

  function closeCustomRainbowEditor() {
    const dlg = document.getElementById('custom-rainbow-editor');
    if (dlg?.open) dlg.close();
    _editingRainbow = null;
    _draftCriteria  = {};
  }

  function wireCustomRainbowEditor() {
    document.getElementById('custom-rainbow-new-btn')?.addEventListener('click', () => {
      if (!Auth.isAuthenticated()) { Auth.open(); return; }
      openCustomRainbowEditor(null);
    });
    document.getElementById('custom-rainbow-editor-cancel')
      ?.addEventListener('click', closeCustomRainbowEditor);
    document.querySelector('[data-action="close-rainbow-editor"]')
      ?.addEventListener('click', closeCustomRainbowEditor);

    // Enter in the name field saves; Cmd/Ctrl+Enter anywhere in the
    // dialog saves. ESC is handled natively by <dialog>.
    const dlgEl = document.getElementById('custom-rainbow-editor');
    dlgEl?.addEventListener('keydown', (e) => {
      const isInName = e.target?.id === 'custom-rainbow-editor-name';
      const isPlainEnter = e.key === 'Enter' && !e.shiftKey && !e.metaKey && !e.ctrlKey && isInName;
      const isCmdEnter   = e.key === 'Enter' && (e.metaKey || e.ctrlKey);
      if (isPlainEnter || isCmdEnter) {
        e.preventDefault();
        document.getElementById('custom-rainbow-editor-save')?.click();
      }
    });

    // Delegate checkbox toggle handling to the filters container —
    // keeps the wiring O(1) regardless of how many catalog values
    // the user happens to see.
    const filtersEl = document.getElementById('custom-rainbow-editor-filters');
    filtersEl?.addEventListener('change', (e) => {
      const cb = e.target;
      if (!(cb instanceof HTMLInputElement)) return;
      // Inspired Ink toggle (sibling to the dimension <details>).
      if (cb.id === 'custom-rainbow-editor-inspiredink') {
        if (cb.checked) _draftCriteria.inspiredInkOnly = true;
        else delete _draftCriteria.inspiredInkOnly;
        _renderPreview();
        return;
      }
      // Per-dimension checkbox.
      const detailsEl = cb.closest('.rainbow-filter');
      const dimKey = detailsEl?.dataset?.dim;
      if (!dimKey) return;
      const value = cb.dataset.value;
      if (!value) return;
      const list = Array.isArray(_draftCriteria[dimKey]) ? _draftCriteria[dimKey] : [];
      if (cb.checked) {
        if (!list.some(v => v.toLowerCase() === value.toLowerCase())) list.push(value);
      } else {
        const i = list.findIndex(v => v.toLowerCase() === value.toLowerCase());
        if (i >= 0) list.splice(i, 1);
      }
      if (list.length === 0) delete _draftCriteria[dimKey];
      else _draftCriteria[dimKey] = list;
      _updateFilterCount(dimKey);
      _renderPreview();
    });

    const saveBtn = document.getElementById('custom-rainbow-editor-save');
    saveBtn?.addEventListener('click', async () => {
      const nameEl = document.getElementById('custom-rainbow-editor-name');
      const errEl  = document.getElementById('custom-rainbow-editor-error');
      const name = (nameEl?.value || '').trim();
      if (!name) {
        errEl.textContent = 'Name cannot be empty.';
        errEl.hidden = false;
        return;
      }
      saveBtn.disabled = true;
      try {
        if (_editingRainbow) {
          await API.updateCustomRainbow(_editingRainbow.id, {
            name,
            criteria: _draftCriteria,
          });
        } else {
          await API.createCustomRainbow(name, _draftCriteria);
        }
        closeCustomRainbowEditor();
        // Just re-render the Collection view — `renderCollectionView`
        // calls `hydrateCustomRainbows` which re-fetches the rainbows.
        // Skipping the full `load()` saves a redundant user_cards
        // round-trip (the user_cards array didn't change).
        renderCollectionView();
      } catch (err) {
        errEl.textContent = err?.message || 'Save failed.';
        errEl.hidden = false;
      } finally {
        saveBtn.disabled = false;
      }
    });

    const delBtn = document.getElementById('custom-rainbow-editor-delete');
    delBtn?.addEventListener('click', async () => {
      if (!_editingRainbow) return;
      // Tick 158 — replaces the blocking confirm() with an Undo
      // Snackbar (parity with tick 123 per-copy delete + tick 143
      // Clear-deck + iOS tick 152 banner). Capture the full rainbow
      // (name + criteria) so UNDO can recreate it via the public
      // createCustomRainbow API; Supabase issues a new id on insert
      // but the user-visible data is identical.
      const captured = {
        name: _editingRainbow.name,
        criteria: _editingRainbow.criteria,
      };
      delBtn.disabled = true;
      try {
        await API.deleteCustomRainbow(_editingRainbow.id);
        closeCustomRainbowEditor();
        // Skip the full `load()` round-trip — same reason as save:
        // user_cards didn't change, only the rainbow list did.
        renderCollectionView();
        if (typeof window.showUndoToast === 'function') {
          window.showUndoToast(`Deleted "${captured.name}"`, async () => {
            try {
              await API.createCustomRainbow(captured.name, captured.criteria);
              renderCollectionView();
            } catch (e) {
              if (typeof window.showToast === 'function') {
                window.showToast(`Couldn't restore — ${e?.message || 'try again'}`);
              }
            }
          });
        }
      } catch (err) {
        const errEl = document.getElementById('custom-rainbow-editor-error');
        errEl.textContent = err?.message || 'Delete failed.';
        errEl.hidden = false;
      } finally {
        delBtn.disabled = false;
      }
    });
  }

  /* ================================================================
     PUBLIC API
  ================================================================ */

  /* Quick Add — single-shot add used by the Find view's "Quick Add"
     toggle. Writes a minimal row (card_number + boba_id + personal
     designation) and keeps the in-memory _cards cache consistent so
     the profile + collection views stay in sync without a re-fetch.
     Throws on error; caller surfaces a toast. */
  async function quickAdd(card, designation = 'personal') {
    // Tick 263 — designation-aware quick-add. Find contextMenu shipped
    // tick 262 (iOS) uses .wanted; web's right-click context menu adds
    // the same shortcut. Valid values match the Designation enum:
    // personal · for_sale · for_trade · wanted · grail.
    if (!card) throw new Error('No card');
    const row = {
      card_number: String(card.cardNumber),
      boba_id:     card.bobaId ? String(card.bobaId) : undefined,
      designation: designation,
    };
    const saved = await API.collectionAdd(row);
    _cards.push(saved);
    renderCollectionView();
    renderProfileView();
    return saved;
  }

  /// Open the Wall dialog for an arbitrary catalog-card set. Caller
  /// passes catalog Cards directly (no user-card row resolution) and
  /// a title. Price overlay is disabled (no designation context).
  /// Used by Decks ("Generate deck wall") and Find multi-select
  /// ("Wall these N cards"). Both surfaces are DESIGN.md §8.8.
  function openCardsWallSheet({ title, cards, context }) {
    return openWallSheet({
      // Default to 'selection' since the bulk of callers are Find
      // multi-select. Decks + public-collection pass their own.
      context: context || 'selection',
      title: title,
      cards: cards || [],
    });
  }
  // Backward-compat alias from tick 9 — practice.js calls this name.
  function openDeckWallSheet({ deckName, cards }) {
    return openCardsWallSheet({ title: deckName, cards, context: 'deck' });
  }

  /// Return the user's owned/wanted/etc entries matching a catalog
  /// card. Used by the Find tab card-detail "IN YOUR COLLECTION"
  /// summary (tick 108) — same shape iOS CardDetailView surfaces.
  /// Match prefers bobaId; falls back to cardNumber for legacy rows
  /// that pre-date the bobaId column.
  function entriesForCard(card) {
    if (!card) return [];
    const bobaId = card.bobaId ? String(card.bobaId) : null;
    const num    = card.cardNumber ? String(card.cardNumber) : null;
    return _cards.filter(c =>
      (bobaId && c.boba_id === bobaId) ||
      (!c.boba_id && num && c.card_number === num)
    );
  }

  return {
    init,
    load,
    openAddSheet,
    openCardsWallSheet,
    openDeckWallSheet,
    quickAdd,
    entriesForCard,
    setCardLookup:    fn => { _cardLookup    = fn; },
    setBobaIdLookup:  fn => { _bobaIdLookup  = fn; },
    setVariantLookup: fn => { _variantLookup = fn; },
  };
})();

// Expose for sibling modules (practice.js, app.js) — classic-script
// `const` at top level doesn't auto-promote to the global object, so
// without this `window.Collection.openDeckWallSheet` from practice.js
// would be undefined.
window.Collection = Collection;
