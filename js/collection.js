/**
 * Collection — BOBA Playbook
 * Manages user collection state and renders the Collection + Profile views.
 * Must be loaded after api.js and auth.js.
 */
const Collection = (() => {
  'use strict';

  let _cards      = [];
  let _activeTab  = 'personal';
  let _addCard    = null; // card being added in the add sheet
  let _cardLookup = null; // set by app.js after card catalog loads

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
    const totalValue = _cards
      .filter(c => c.purchase_price)
      .reduce((sum, c) => sum + Number(c.purchase_price), 0);
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
            ${totalValue > 0 ? `
            <div class="cstat">
              <span class="cstat-val">$${totalValue.toFixed(2)}</span>
              <span class="cstat-label">Cost Basis</span>
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

    view.querySelectorAll('[data-delete-id]').forEach(btn => {
      btn.addEventListener('click', async () => {
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
           <span>?</span>
         </div>`;

    return `
      <div class="collection-card-item" role="listitem" data-element="${esc(element)}">
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

    const session    = Auth.getSession();
    const email      = session?.user?.email || '—';
    const ownedCount = _cards.filter(c => ['personal','for_sale','for_trade'].includes(c.designation)).length;
    const wantedCount = _cards.filter(c => c.designation === 'wanted').length;
    const grailsCount = _cards.filter(c => c.designation === 'grails').length;
    const totalValue  = _cards
      .filter(c => c.purchase_price)
      .reduce((sum, c) => sum + Number(c.purchase_price), 0);

    view.innerHTML = `
      <div class="view-inner profile-view">
        <h2 class="view-heading">Profile</h2>
        <div class="profile-email">${esc(email)}</div>
        <div class="profile-stats">
          <div class="pstat"><span class="pstat-val">${ownedCount}</span><span class="pstat-label">Owned</span></div>
          <div class="pstat"><span class="pstat-val">${wantedCount}</span><span class="pstat-label">Wanted</span></div>
          <div class="pstat"><span class="pstat-val">${grailsCount}</span><span class="pstat-label">Grails</span></div>
          ${totalValue > 0 ? `<div class="pstat"><span class="pstat-val">$${totalValue.toFixed(2)}</span><span class="pstat-label">Cost Basis</span></div>` : ''}
        </div>
        <button class="btn-ghost-sm" id="profile-signout-btn">Sign Out</button>
      </div>`;

    view.querySelector('#profile-signout-btn')
      ?.addEventListener('click', async () => {
        if (!confirm('Sign out?')) return;
        await Auth.signOut();
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
            <div class="form-field">
              <label class="form-label" for="add-serial">SERIAL #</label>
              <input class="form-input" type="text" id="add-serial"
                     placeholder="e.g. 42/100">
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
    const serialVal = document.getElementById('add-serial')?.value.trim();

    const card = {
      card_number:   String(_addCard.cardNumber),
      designation:   document.getElementById('add-desig')?.value      || 'personal',
      condition:     document.getElementById('add-condition')?.value   || null,
      purchase_price: priceVal ? Number(priceVal) : null,
      serial_number:  serialVal || null,
      notes:          document.getElementById('add-notes')?.value.trim() || null,
    };

    try {
      const saved = await API.collectionAdd(card);
      _cards.push(saved);
      closeAddSheet();
      renderCollectionView();
      renderProfileView();
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
    setCardLookup: fn => { _cardLookup = fn; },
  };
})();
