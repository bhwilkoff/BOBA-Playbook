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
  let _cardLookup    = null;  // set by app.js after card catalog loads
  let _variantLookup = null;  // set by app.js: (hero, excludeNum) => Card[]

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

    const tabCount   = key => _cards.filter(c => c.designation === key).length;
    const ownedCards = _cards.filter(c => ['personal','for_sale','for_trade'].includes(c.designation));
    const totalCostBasis = ownedCards
      .filter(c => c.purchase_price)
      .reduce((sum, c) => sum + Number(c.purchase_price), 0);
    const totalEstimatedValue = ownedCards
      .filter(c => c.estimated_value)
      .reduce((sum, c) => sum + Number(c.estimated_value), 0);
    const uniqueNums = new Set(_cards.map(c => c.card_number)).size;

    const tabsHtml = DESIGNATIONS.map(d => `
      <button class="desig-tab${_activeTab === d.key ? ' active' : ''}"
              data-tab="${d.key}" role="tab" aria-selected="${_activeTab === d.key}">
        ${esc(d.label)}
        <span class="desig-tab-count">${tabCount(d.key)}</span>
      </button>`).join('');

    const activeCards = _cards.filter(c => c.designation === _activeTab);
    const listHtml = activeCards.length === 0
      ? `<p class="collection-empty">No cards in ${esc(DESIGNATIONS.find(d => d.key === _activeTab)?.label)} yet.</p>`
      : activeCards.map(buildCollectionCardHtml).join('');

    view.innerHTML = `
      <div class="collection-view">
        <div class="collection-header">
          <h2 class="view-heading">My Collection</h2>
          <div class="collection-stats-bar">
            <div class="cstat">
              <span class="cstat-val">${ownedCards.length}</span>
              <span class="cstat-label">Owned</span>
            </div>
            <div class="cstat">
              <span class="cstat-val">${uniqueNums}</span>
              <span class="cstat-label">Unique Cards</span>
            </div>
            ${totalCostBasis > 0 ? `
            <div class="cstat">
              <span class="cstat-val">$${totalCostBasis.toFixed(2)}</span>
              <span class="cstat-label">Total Paid</span>
            </div>` : ''}
            ${totalEstimatedValue > 0 ? `
            <div class="cstat">
              <span class="cstat-val">$${totalEstimatedValue.toFixed(2)}</span>
              <span class="cstat-label">Est. Value</span>
            </div>` : ''}
          </div>
        </div>
        <div class="desig-tabs" role="tablist" aria-label="Collection designations">
          ${tabsHtml}
        </div>
        <div class="collection-card-list" role="list">
          ${listHtml}
        </div>
      </div>`;

    view.querySelectorAll('.desig-tab').forEach(tab => {
      tab.addEventListener('click', () => {
        _activeTab = tab.dataset.tab;
        renderCollectionView();
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

  function buildCollectionCardHtml(entry) {
    const designLabel = DESIGNATIONS.find(d => d.key === entry.designation)?.label || entry.designation;
    const catalogCard = _cardLookup ? _cardLookup(entry.card_number) : null;
    const cardName    = catalogCard?.name || entry.card_number;
    const imageFile   = catalogCard?.imageFile;
    const element     = catalogCard?.element || 'NONE';

    const imgHtml = imageFile
      ? `<img class="ccard-thumb" src="${esc(API.thumbUrl(imageFile))}"
              alt="${esc(cardName)}" loading="lazy" decoding="async">`
      : `<div class="ccard-thumb ccard-thumb-placeholder" data-element="${esc(element)}" aria-hidden="true">
           <span class="placeholder-brand">BOBA<br>PB</span>
         </div>`;

    return `
      <div class="collection-card-item" role="listitem" data-element="${esc(element)}"
           data-detail-num="${esc(entry.card_number)}"
           style="cursor:pointer" title="View detail"
           tabindex="0" aria-label="View ${esc(cardName)} detail">
        ${imgHtml}
        <div class="ccard-body">
          <div class="ccard-name">${esc(cardName)}</div>
          <div class="ccard-num">#${esc(entry.card_number || '—')}</div>
          <div class="ccard-badges">
            <span class="desig-badge desig-${esc(entry.designation || '')}">${esc(designLabel)}</span>
            ${entry.condition ? `<span class="ccard-condition">${esc(entry.condition.replace('_',' '))}${entry.grade ? ` · ${esc(entry.grade)}` : ''}</span>` : ''}
          </div>
          ${entry.purchase_price ? `<div class="ccard-price">$${Number(entry.purchase_price).toFixed(2)}</div>` : ''}
          ${entry.notes ? `<div class="ccard-notes">${esc(entry.notes)}</div>` : ''}
        </div>
        <button class="ccard-delete-btn" data-delete-id="${esc(entry.id)}" aria-label="Remove from collection">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
               width="16" height="16" aria-hidden="true">
            <path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>
          </svg>
        </button>
      </div>`;
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

    // Unique card numbers per designation (mirrors iOS uniqueCardNumbers)
    const uniqueFor = key => new Set(_cards.filter(c => c.designation === key).map(c => c.card_number)).size;
    const personalCount  = uniqueFor('personal');
    const forSaleCount   = uniqueFor('for_sale');
    const forTradeCount  = uniqueFor('for_trade');
    const wantedCount    = uniqueFor('wanted');
    const grailsCount    = uniqueFor('grails');
    const ownedProfileCards = _cards.filter(c => ['personal','for_sale','for_trade'].includes(c.designation));
    const totalValue     = ownedProfileCards
      .filter(c => c.purchase_price)
      .reduce((sum, c) => sum + Number(c.purchase_price), 0);
    const totalValueStr  = totalValue > 0
      ? '$' + totalValue.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
      : '—';
    const estValue = ownedProfileCards
      .filter(c => c.estimated_value)
      .reduce((sum, c) => sum + Number(c.estimated_value), 0);
    const estValueStr = estValue > 0
      ? '$' + estValue.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
      : null;

    // SVG icons matching iOS SF Symbols
    const icons = {
      person:   `<svg viewBox="0 0 24 24" fill="currentColor" width="15" height="15"><path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-5.33 0-8 2.67-8 4v1h16v-1c0-1.33-2.67-4-8-4z"/></svg>`,
      tag:      `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="15" height="15"><path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/><circle cx="7" cy="7" r="1.5" fill="currentColor" stroke="none"/></svg>`,
      trade:    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="15" height="15"><path d="M7 16V4m0 0L3 8m4-4l4 4M17 8v12m0 0l4-4m-4 4l-4-4"/></svg>`,
      star:     `<svg viewBox="0 0 24 24" fill="currentColor" width="15" height="15"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/></svg>`,
      crown:    `<svg viewBox="0 0 24 24" fill="currentColor" width="15" height="15"><path d="M2 20h20v2H2v-2zM4 18l4-8 4 4 4-7 4 11H4z"/></svg>`,
      dollar:   `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="15" height="15"><circle cx="12" cy="12" r="10"/><path d="M12 6v12M15 8.5C15 7.12 13.66 6 12 6h-1c-1.66 0-3 1.12-3 2.5S9.34 11 11 11h2c1.66 0 3 1.12 3 2.5S14.66 17 13 17h-1c-1.66 0-3-1.12-3-2.5"/></svg>`,
      chart:    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="15" height="15"><polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/></svg>`,
    };

    const statRow = (iconKey, label, value, colorClass = '') => `
      <div class="profile-stat-row">
        <span class="profile-stat-icon${colorClass ? ' ' + colorClass : ''}">${icons[iconKey]}</span>
        <span class="profile-stat-label">${esc(label)}</span>
        <span class="profile-stat-value">${esc(String(value))}</span>
      </div>`;

    view.innerHTML = `
      <div class="profile-page">
        <h2 class="view-heading profile-page-heading">Profile</h2>

        <!-- Account card -->
        <div class="profile-account-card">
          <div class="profile-avatar">
            <svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28" aria-hidden="true">
              <path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-5.33 0-8 2.67-8 4v1h16v-1c0-1.33-2.67-4-8-4z"/>
            </svg>
          </div>
          <div class="profile-account-info">
            <div class="profile-account-email">${esc(email)}</div>
            <div class="profile-account-role">
              ${role === 'admin' ? 'Admin' : role === 'moderator' ? 'Moderator' : 'Member'}
              ${role === 'admin' ? '<span class="role-badge admin-badge">ADMIN</span>' :
                role === 'moderator' ? '<span class="role-badge mod-badge">MOD</span>' : ''}
            </div>
          </div>
        </div>

        <!-- Collection stats -->
        <div class="profile-section">
          <div class="profile-section-label">Collection</div>
          <div class="profile-stat-list">
            ${statRow('person', 'Personal',  personalCount,  'icon-cyan')}
            ${statRow('tag',    'For Sale',  forSaleCount,   'icon-orange')}
            ${statRow('trade',  'For Trade', forTradeCount,  'icon-green')}
            ${statRow('star',   'Wanted',    wantedCount,    'icon-violet')}
            ${statRow('crown',  'Grails',    grailsCount,    'icon-gold')}
            <div class="profile-stat-divider"></div>
            ${statRow('dollar', 'Total Paid', totalValueStr, 'icon-cyan')}
            ${estValueStr ? statRow('chart', 'Est. Market Value', estValueStr, 'icon-orange') : ''}
          </div>
        </div>

        <!-- Recalculate collection value -->
        <div class="profile-section">
          <div class="profile-stat-list">
            <button class="profile-action-row" id="profile-recalculate-btn">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M23 4v6h-6"/><path d="M1 20v-6h6"/>
                <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
              </svg>
              <span>Recalculate Collection Value</span>
            </button>
            <p class="profile-recalc-status hidden" id="profile-recalc-status"></p>
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
      </div>`;

    view.querySelector('#profile-signout-btn')
      ?.addEventListener('click', async () => {
        if (!confirm('Sign out? Your collection data is saved and will sync back when you sign in again.')) return;
        await Auth.signOut();
      });

    view.querySelector('#profile-mod-btn')
      ?.addEventListener('click', () => openModSearchPanel());

    view.querySelector('#profile-admin-btn')
      ?.addEventListener('click', () => openAdminPanel());

    view.querySelector('#profile-recalculate-btn')
      ?.addEventListener('click', () => recalculateValues(view));
  }

  const EBAY_WORKER_URL = 'https://boba-ebay-proxy.benwilkoff.workers.dev';

  async function recalculateValues(view) {
    const btn    = view.querySelector('#profile-recalculate-btn');
    const status = view.querySelector('#profile-recalc-status');
    if (!btn || !status) return;

    const ownedCards = _cards.filter(c => ['personal','for_sale','for_trade'].includes(c.designation));
    if (!ownedCards.length) {
      status.textContent = 'No owned cards to price.';
      status.classList.remove('hidden');
      return;
    }

    btn.disabled = true;
    status.classList.remove('hidden');
    status.textContent = `Fetching prices… 0 / ${ownedCards.length}`;

    let updated = 0;
    for (let i = 0; i < ownedCards.length; i++) {
      const entry = ownedCards[i];
      const card  = _cardLookup ? _cardLookup(entry.card_number) : null;
      if (!card) continue;

      try {
        const params = new URLSearchParams({
          cardNumber: card.cardNumber,
          hero:       card.hero       || '',
          set:        card.set        || '',
          element:    card.element    || '',
          days:       '30',
          ...(card.power    ? { power:     String(card.power)    } : {}),
          ...(card.radishUrl ? { radishUrl: card.radishUrl       } : {}),
        });
        const res  = await fetch(`${EBAY_WORKER_URL}?${params}`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        const avg  = data?.average;
        if (avg && avg > 0) {
          await API.collectionUpdate(entry.id, { estimated_value: avg });
          const local = _cards.find(c => c.id === entry.id);
          if (local) local.estimated_value = avg;
          updated++;
        }
      } catch (_) {
        // skip cards that fail pricing — don't abort the whole run
      }

      status.textContent = `Fetching prices… ${i + 1} / ${ownedCards.length}`;
      // Yield to keep the UI responsive
      await new Promise(r => setTimeout(r, 50));
    }

    btn.disabled = false;
    status.textContent = `Done — updated ${updated} of ${ownedCards.length} cards.`;
    renderCollectionView();
    renderProfileView();
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
      loadAdminImageOverrides(overlay),
      loadAdminCorrections(overlay),
      loadAdminUsers(overlay),
    ]);
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
              <button class="admin-approve-btn" data-oid="${esc(o.id)}">Resolved</button>
            </div>
          </div>`;
      }).join('');

      listEl.querySelectorAll('.admin-approve-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          btn.disabled = true;
          try {
            await API.adminResolveImageOverride(Number(btn.dataset.oid));
            btn.closest('.admin-correction-row').remove();
            if (!listEl.querySelector('.admin-correction-row')) {
              listEl.innerHTML = `<p class="mod-edit-note">No missing art — all images accounted for.</p>`;
            }
            // Refresh metrics count
            loadAdminMetrics(overlay);
          } catch (e) {
            alert('Failed to resolve: ' + e.message);
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

      listEl.innerHTML = users.map(u => {
        const isMe = u.user_id === currentUserId;
        const roleClass = u.role === 'admin' ? 'badge-admin' : u.role === 'moderator' ? 'badge-mod' : 'badge-user';
        return `
          <div class="admin-user-row" data-uid="${esc(u.user_id)}">
            <div class="admin-user-info">
              <div class="admin-user-email">${esc(u.email || 'Unknown')}${isMe ? ' <span class="admin-you-badge">YOU</span>' : ''}</div>
              <div class="admin-user-meta">${u.user_id.substring(0, 12)}… · Joined ${new Date(u.created_at).toLocaleDateString()}</div>
            </div>
            <div class="admin-user-role">
              <span class="admin-role-badge ${roleClass}">${u.role.toUpperCase()}</span>
              ${!isMe ? `<button class="admin-role-btn" data-uid="${esc(u.user_id)}" data-role="${esc(u.role)}">Change</button>` : ''}
            </div>
          </div>`;
      }).join('');

      listEl.querySelectorAll('.admin-role-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          const uid  = btn.dataset.uid;
          const cur  = btn.dataset.role;
          const next = cur === 'user' ? 'moderator' : cur === 'moderator' ? 'admin' : 'user';
          const label = `${cur} → ${next}`;
          if (!confirm(`Change role for this user: ${label}?`)) return;
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

    const cardNum     = _detailNum;
    const catalogCard = _cardLookup ? _cardLookup(cardNum) : null;
    const cardName    = catalogCard?.name    || cardNum;
    const imageFile   = catalogCard?.imageFile;
    const element     = catalogCard?.element || 'NONE';
    const treatment   = catalogCard?.treatment;
    const power       = catalogCard?.power;
    const hero        = catalogCard?.hero;

    const myEntries = _cards.filter(c => c.card_number === cardNum);

    const variations = (hero && _variantLookup)
      ? _variantLookup(hero, cardNum)
      : [];

    // Card header image
    const imgHtml = imageFile
      ? `<img class="cdetail-card-img" src="${esc(API.fullUrl(imageFile))}"
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
          <div class="cdetail-card-num">#${esc(cardNum)}</div>
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

    // Delete buttons
    box.querySelectorAll('[data-delete-entry-id]').forEach(btn => {
      btn.addEventListener('click', async () => {
        if (!confirm('Remove this copy from your collection?')) return;
        const id = btn.dataset.deleteEntryId;
        try {
          await API.collectionDelete(id);
          _cards = _cards.filter(c => c.id !== id);
          renderCollectionView();
          renderProfileView();
          const remaining = _cards.filter(c => c.card_number === cardNum);
          if (remaining.length === 0) closeCollectionDetail();
          else renderCollectionDetail();
        } catch (err) {
          alert('Could not remove: ' + err.message);
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
    const owned   = _cards.some(c => c.card_number === num && ['personal','for_sale','for_trade'].includes(c.designation));
    const wanted  = !owned && _cards.some(c => c.card_number === num && c.designation === 'wanted');
    const imgHtml = card.imageFile
      ? `<img class="cdetail-var-img" src="${esc(API.thumbUrl(card.imageFile))}"
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
          const updated = await API.collectionUpdate(_editEntry.id, fields);
          const idx = _cards.findIndex(c => c.id === updated.id);
          if (idx !== -1) _cards[idx] = updated;
          _detailState = 'view';
          _editEntry   = null;
          renderCollectionDetail();
          renderCollectionView();
          renderProfileView();
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

    const existing = _cards.filter(c => c.card_number === String(card.cardNumber));
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

    overlay.hidden = false;
    document.body.style.overflow = 'hidden';

    box.querySelector('#add-close-btn').addEventListener('click', closeAddSheet);
    overlay.addEventListener('click', e => { if (e.target === overlay) closeAddSheet(); });
    box.querySelector('#add-form').addEventListener('submit', async e => {
      e.preventDefault();
      await handleAddSubmit();
    });
  }

  function closeAddSheet() {
    document.getElementById('add-collection-overlay').hidden = true;
    document.body.style.overflow = '';
    _addCard = null;
  }

  async function handleAddSubmit() {
    if (!_addCard) return;
    const btn = document.getElementById('add-submit');
    btn.disabled = true; btn.textContent = 'Adding…';

    const priceVal  = document.getElementById('add-price')?.value;

    const card = {
      card_number:   String(_addCard.cardNumber),
      designation:   document.getElementById('add-desig')?.value      || 'personal',
      condition:     document.getElementById('add-condition')?.value   || null,
      purchase_price: priceVal ? Number(priceVal) : null,
      notes:          document.getElementById('add-notes')?.value.trim() || null,
    };

    try {
      const saved = await API.collectionAdd(card);
      _cards.push(saved);
      closeAddSheet();
      renderCollectionView();
      renderProfileView();
      // If collection detail is open for this card, refresh it with the new copy
      if (_detailNum === String(_addCard.cardNumber)) renderCollectionDetail();
    } catch (err) {
      const errEl = document.getElementById('add-error');
      if (errEl) { errEl.textContent = err.message; errEl.hidden = false; }
      btn.disabled = false; btn.textContent = 'Add to Collection';
    }
  }

  /* ================================================================
     PUBLIC HELPERS — used by app.js card modal
  ================================================================ */

  function isOwned(cardNumber) {
    return _cards.some(c =>
      c.card_number === String(cardNumber) &&
      ['personal','for_sale','for_trade'].includes(c.designation)
    );
  }

  function isWanted(cardNumber) {
    return _cards.some(c =>
      c.card_number === String(cardNumber) && c.designation === 'wanted'
    );
  }

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
  }

  /* ================================================================
     PUBLIC API
  ================================================================ */

  return {
    init,
    load,
    openAddSheet,
    isOwned,
    isWanted,
    setCardLookup:    fn => { _cardLookup    = fn; },
    setVariantLookup: fn => { _variantLookup = fn; },
  };
})();
