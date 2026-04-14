/**
 * practice.js — Deck Builder + Practice Battle for BOBA Playbook web app
 *
 * Deck Builder: card browser, deck list, validation, export, starter templates.
 * Practice Battle: 7-battle match simulation with CPU AI, phase state machine.
 *
 * All SVG icons — no emoji.
 * Wired up after displayCards are loaded (called from app.js).
 */

'use strict';

// ════════════════════════════════════════════════════════════════
// § Helpers
// ════════════════════════════════════════════════════════════════

const CDN_BASE = 'https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev';
function thumbUrl(file) { return file ? `${CDN_BASE}/thumbs/${file}` : null; }

function $ (id) { return document.getElementById(id); }

// ════════════════════════════════════════════════════════════════
// § Deck Builder
// ════════════════════════════════════════════════════════════════

const DB = {
  format: 'playmaker',
  browserTab: 'hero',
  search: '',
  heroes: [],
  plays: [],
  bonusPlays: [],
  hotDogs: [],
  deckName: 'New Deck',
  quickAdd: false,       // false = interactive popup mode (default); true = instant add

  // Format rules
  formats: {
    rookie:       { heroTarget: 60, needsHD: false, needsPlays: false, powerCap: null },
    substitution: { heroTarget: 60, needsHD: true,  needsPlays: false, powerCap: null },
    playmaker:    { heroTarget: 60, needsHD: true,  needsPlays: true,  powerCap: null },
    spec:         { heroTarget: 60, needsHD: true,  needsPlays: true,  powerCap: 160  },
    limited:      { heroTarget: 40, needsHD: true,  needsPlays: true,  powerCap: null },
  },

  get currentFormat() { return this.formats[this.format]; },
  get allCards() { return this.heroes.concat(this.plays, this.bonusPlays, this.hotDogs); },

  isInDeck(card) {
    return this.heroes.some(c => c.bobaId === card.bobaId)
        || this.plays.some(c => c.bobaId === card.bobaId)
        || this.bonusPlays.some(c => c.bobaId === card.bobaId)
        || this.hotDogs.some(c => c.bobaId === card.bobaId);
  },

  powerValueCounts() {
    const counts = {};
    for (const c of this.heroes) {
      const p = c.power || 0;
      counts[p] = (counts[p] || 0) + 1;
    }
    return counts;
  },

  heroNameCounts() {
    const counts = {};
    for (const c of this.heroes) {
      const h = c.hero || c.name;
      counts[h] = (counts[h] || 0) + 1;
    }
    return counts;
  },

  wouldHeroViolate(card) {
    if (this.heroes.some(c => c.bobaId === card.bobaId)) return true;
    const pv = this.powerValueCounts();
    if ((pv[card.power] || 0) >= 6) return true;
    if (this.currentFormat.powerCap && card.power > this.currentFormat.powerCap) return true;
    const nc = this.heroNameCounts();
    if ((nc[card.hero || card.name] || 0) >= 6) return true;
    return false;
  },

  addCard(card) {
    const tab = this.browserTab;
    if (tab === 'hero') {
      if (this.wouldHeroViolate(card)) return;
      this.heroes.push(card);
    } else if (tab === 'play') {
      if (this.plays.some(c => c.bobaId === card.bobaId)) return;
      if (this.plays.length < 30) this.plays.push(card);
    } else if (tab === 'bonus') {
      if (this.bonusPlays.some(c => c.bobaId === card.bobaId)) return;
      this.bonusPlays.push(card);
    } else if (tab === 'hotdog') {
      if (this.hotDogs.length < 10) this.hotDogs.push(card);
    }
  },

  removeCard(bobaId, section) {
    if (section === 'hero') {
      const i = this.heroes.findIndex(c => c.bobaId === bobaId);
      if (i !== -1) this.heroes.splice(i, 1);
    } else if (section === 'play') {
      const i = this.plays.findIndex(c => c.bobaId === bobaId);
      if (i !== -1) this.plays.splice(i, 1);
    } else if (section === 'bonus') {
      const i = this.bonusPlays.findIndex(c => c.bobaId === bobaId);
      if (i !== -1) this.bonusPlays.splice(i, 1);
    } else if (section === 'hotdog') {
      const i = this.hotDogs.findIndex(c => c.bobaId === bobaId);
      if (i !== -1) this.hotDogs.splice(i, 1);
    }
  },

  validate() {
    const fmt = this.currentFormat;
    const errors = [];
    const diff = fmt.heroTarget - this.heroes.length;
    if (diff > 0) errors.push(`Need ${diff} more heroes (${this.heroes.length}/${fmt.heroTarget})`);
    if (diff < 0) errors.push(`Too many heroes (${this.heroes.length}/${fmt.heroTarget})`);

    if (fmt.powerCap) {
      const over = this.heroes.filter(c => (c.power || 0) > fmt.powerCap);
      if (over.length) errors.push(`${over.length} hero(es) over power cap ${fmt.powerCap}`);
    }

    const pv = this.powerValueCounts();
    for (const [p, cnt] of Object.entries(pv)) {
      if (cnt > 6) errors.push(`Power ${p}: ${cnt}/6 — remove ${cnt - 6}`);
    }

    // Variation uniqueness
    const seen = new Set();
    for (const c of this.heroes) {
      const key = `${c.hero}|${c.treatment || ''}|${c.element}|${c.power}`;
      if (seen.has(key)) errors.push(`Duplicate: ${c.hero} (${c.treatment || 'Base'}, ${c.element}, ${c.power})`);
      seen.add(key);
    }

    if (fmt.needsPlays) {
      const pd = 30 - this.plays.length;
      if (pd > 0) errors.push(`Need ${pd} more plays (${this.plays.length}/30)`);
      if (pd < 0) errors.push(`Too many plays (${this.plays.length}/30)`);
    }

    if (fmt.needsHD) {
      const hd = 10 - this.hotDogs.length;
      if (hd !== 0) errors.push(`Hot Dogs: ${this.hotDogs.length}/10`);
    }

    return errors;
  },

  exportText() {
    const lines = [`# ${this.deckName} (${this.format})`];
    lines.push('');
    lines.push(`## Heroes (${this.heroes.length})`);
    const sorted = [...this.heroes].sort((a, b) => (b.power || 0) - (a.power || 0));
    for (const c of sorted) {
      lines.push(`${c.hero || c.name} ${c.power} ${c.element} (${c.treatment || 'Base'})`);
    }
    if (this.plays.length) {
      lines.push('');
      lines.push(`## Plays (${this.plays.length}/30)`);
      for (const c of this.plays) lines.push(`${c.name} (${c.playCost ?? 0} HD)`);
    }
    if (this.bonusPlays.length) {
      lines.push('');
      lines.push(`## Bonus Plays (${this.bonusPlays.length})`);
      for (const c of this.bonusPlays) lines.push(`${c.name} (${c.playCost ?? 0} HD)`);
    }
    if (this.hotDogs.length) {
      lines.push('');
      lines.push(`## Hot Dogs (${this.hotDogs.length}/10)`);
      for (const c of this.hotDogs) lines.push(c.name || c.hero);
    }
    return lines.join('\n');
  },

  exportCSV() {
    // CSV format compatible with deck-builder.bobattlearena.com
    // Columns: Slot,Card#,Name,Cost,Ability,DBS
    // Slots 1–30 = regular plays, B1–B15 = bonus plays
    // Card# uses set prefix: A=Alpha Edition, U=Alpha Update, G=Griffey Edition
    // HTD (hot dog) cards: HTD-N format
    function csvCard(num) {
      // cardNumber is already in the right format (A-001, G-002, etc.)
      return `"${(num || '').replace(/"/g, '""')}"`;
    }
    function csvStr(s) { return `"${(s || '').replace(/"/g, '""')}"`; }

    const rows = ['Slot,Card#,Name,Cost,Ability,DBS'];

    this.plays.forEach((c, idx) => {
      const slot = idx + 1;
      const cost = c.playCost != null ? c.playCost : '';
      const dbs  = c.dbs != null ? c.dbs : '';
      rows.push(`${slot},${csvCard(c.cardNumber)},${csvStr(c.name)},${cost},${csvStr(c.description || '')},${dbs}`);
    });

    this.bonusPlays.forEach((c, idx) => {
      const slot = `B${idx + 1}`;
      const cost = c.playCost != null ? c.playCost : '';
      const dbs  = c.dbs != null ? c.dbs : '';
      rows.push(`${slot},${csvCard(c.cardNumber)},${csvStr(c.name)},${cost},${csvStr(c.description || '')},${dbs}`);
    });

    return rows.join('\r\n');
  },

  clear() {
    this.heroes = []; this.plays = []; this.bonusPlays = []; this.hotDogs = [];
    this.deckName = 'New Deck';
  },
};

// Card filters per browser tab
function dbFilterCards(allCards) {
  const q = DB.search.toLowerCase();
  return allCards.filter(card => {
    const name = (card.hero || card.name || '').toLowerCase();
    const num = (card.cardNumber || '').toLowerCase();
    const matches = !q || name.includes(q) || num.includes(q);
    if (!matches) return false;
    if (DB.browserTab === 'hero') return card.cardType === 'Hero' && (card.power || 0) > 0;
    if (DB.browserTab === 'play') return card.cardType === 'Play' && !(card.cardNumber || '').startsWith('BPL') && card.treatment !== 'Bonus Plays';
    if (DB.browserTab === 'bonus') return card.cardType === 'Play' && ((card.cardNumber || '').startsWith('BPL') || card.treatment === 'Bonus Plays');
    if (DB.browserTab === 'hotdog') return card.cardType === 'HotDog' || (card.cardType === 'Hero' && (card.treatment || '').toLowerCase().includes('hot dog'));
    return false;
  });
}

function dbRenderGrid(allCards) {
  const grid = $('db-card-grid');
  if (!grid) return;
  const cards = dbFilterCards(allCards).slice(0, 180);
  grid.innerHTML = cards.map(card => {
    const imgUrl = card.imageFile ? thumbUrl(card.imageFile) : null;
    const inDeck = DB.isInDeck(card);
    const violates = DB.browserTab === 'hero' && DB.wouldHeroViolate(card);
    const label = card.hero || card.name || '';
    const sub = card.cardType === 'Hero'
      ? `${card.element} · ${card.power}`
      : (card.playCost != null ? (card.playCost === 0 ? 'FREE' : `${card.playCost} HD`) : '');
    return `<div class="db-card-cell${inDeck ? ' in-deck' : ''}${violates ? ' violates' : ''}"
                 role="listitem"
                 data-boba-id="${card.bobaId || ''}"
                 title="${label}">
      ${imgUrl
        ? `<img class="db-card-img" src="${imgUrl}" alt="${label}" loading="lazy" onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">`
        : ''
      }
      <div class="db-card-img" style="display:${imgUrl ? 'none' : 'flex'};align-items:center;justify-content:center;font-family:var(--font-display);font-size:1.2rem;color:rgba(255,255,255,0.3)">${label.slice(0,2).toUpperCase()}</div>
      <div class="db-card-label">${label}</div>
      <div class="db-card-sub">${sub}</div>
    </div>`;
  }).join('');
}

function dbRenderDeckList() {
  // Hero section
  const heroList = $('db-heroes-list');
  const heroCount = $('db-hero-count');
  if (heroCount) heroCount.textContent = DB.heroes.length;
  if (heroList) {
    heroList.innerHTML = DB.heroes.sort((a, b) => (b.power || 0) - (a.power || 0)).map(c =>
      `<div class="db-card-row">
        <span class="db-card-row-name">${c.hero || c.name}</span>
        <span class="db-card-row-meta">${c.element} ${c.power}</span>
        <button class="db-card-row-remove" data-remove="${c.bobaId}" data-section="hero" aria-label="Remove ${c.hero || c.name}">&times;</button>
      </div>`
    ).join('');
  }

  // Plays section
  const playList = $('db-plays-list');
  const playCount = $('db-play-count');
  if (playCount) playCount.textContent = DB.plays.length;
  if (playList) {
    playList.innerHTML = DB.plays.map(c =>
      `<div class="db-card-row">
        <span class="db-card-row-name">${c.name}</span>
        <span class="db-card-row-meta">${c.playCost != null ? (c.playCost === 0 ? 'FREE' : `${c.playCost}HD`) : ''}</span>
        <button class="db-card-row-remove" data-remove="${c.bobaId}" data-section="play" aria-label="Remove ${c.name}">&times;</button>
      </div>`
    ).join('');
  }

  // Hot Dogs section
  const hdList = $('db-hotdogs-list');
  const hdCount = $('db-hd-count');
  if (hdCount) hdCount.textContent = DB.hotDogs.length;
  if (hdList) {
    hdList.innerHTML = DB.hotDogs.map(c =>
      `<div class="db-card-row">
        <span class="db-card-row-name">${c.name || c.hero}</span>
        <span class="db-card-row-meta">Hot Dog</span>
        <button class="db-card-row-remove" data-remove="${c.bobaId}" data-section="hotdog" aria-label="Remove">&times;</button>
      </div>`
    ).join('');
  }

  // Stats bar
  const heroTarget = DB.currentFormat.heroTarget;
  const hStat = $('db-stat-heroes');
  const pStat = $('db-stat-plays');
  const hdStat = $('db-stat-hotdogs');
  const lStat = $('db-stat-legal');
  if (hStat) hStat.textContent = `Heroes: ${DB.heroes.length}/${heroTarget}`;
  if (pStat) pStat.style.display = DB.currentFormat.needsPlays ? '' : 'none';
  if (pStat) pStat.textContent = `Plays: ${DB.plays.length}/30`;
  if (hdStat) hdStat.style.display = DB.currentFormat.needsHD ? '' : 'none';
  if (hdStat) hdStat.textContent = `Hot Dogs: ${DB.hotDogs.length}/10`;

  const errors = DB.validate();
  if (lStat) {
    if (DB.heroes.length === 0) {
      lStat.textContent = 'Build your deck';
      lStat.className = 'db-stat db-stat-legality';
    } else if (errors.length === 0) {
      lStat.textContent = 'LEGAL';
      lStat.className = 'db-stat db-stat-legality legal';
    } else {
      lStat.textContent = 'ILLEGAL';
      lStat.className = 'db-stat db-stat-legality';
    }
  }

  // Validation errors — shown as prominent banner above deck layout
  const errEl = $('db-errors');
  if (errEl) {
    if (errors.length === 0 || DB.heroes.length === 0) {
      errEl.hidden = true;
      // Reset to just the title
      const title = errEl.querySelector('.db-errors-title');
      if (title) { errEl.innerHTML = ''; errEl.appendChild(title); }
    } else {
      errEl.hidden = false;
      errEl.innerHTML = `<div class="db-errors-title">Fix to make deck legal:</div>` +
        errors.map(e => `<div class="db-error-item">⚠ ${e}</div>`).join('');
    }
  }
}

// Template metadata + key mapping to template-decks.json
const DB_TEMPLATES = [
  { id: 'fire',  key: 'fire-aggro',          name: 'Fire Aggro',          desc: 'Aggressive tempo — Fire weapon synergies' },
  { id: 'ice',   key: 'ice-control',          name: 'Ice Control',         desc: 'Defensive control — deny and outlast' },
  { id: 'steel', key: 'steel-wall',           name: 'Steel Wall',          desc: 'Durable defense — Steel weapon cards' },
  { id: 'mixed', key: 'mixed-toolbox',        name: 'Mixed Toolbox',       desc: 'Flexible answers for every situation' },
  { id: 'eco',   key: 'economy-attrition',    name: 'Economy / Attrition', desc: 'Starve opponent of Hot Dogs' },
];

// Fetched once at initDeckBuilder time; keyed by template key
let dbTemplateData = null;

function dbRenderTemplates() {
  const el = $('db-templates');
  if (!el) return;
  el.innerHTML = DB_TEMPLATES.map(t =>
    `<button class="db-template-btn" data-template="${t.id}" title="${t.desc}">${t.name}</button>`
  ).join('');
}

function dbRender(allCards) {
  dbRenderGrid(allCards);
  dbRenderDeckList();
}

function initDeckBuilder(allCards) {
  const modal = $('deck-builder-modal');
  if (!modal) return;

  dbRenderTemplates();
  dbRender(allCards);

  // Open / Close
  $('btn-open-deck-builder')?.addEventListener('click', () => {
    modal.hidden = false;
    dbRender(allCards);
  });
  $('btn-close-deck-builder')?.addEventListener('click', () => { modal.hidden = true; });
  modal.addEventListener('click', e => { if (e.target === modal) modal.hidden = true; });

  // Format pills
  modal.querySelectorAll('.db-format-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      modal.querySelectorAll('.db-format-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      DB.format = btn.dataset.format;
      dbRender(allCards);
    });
  });

  // Browser tabs
  modal.querySelectorAll('.db-btab').forEach(btn => {
    btn.addEventListener('click', () => {
      modal.querySelectorAll('.db-btab').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      DB.browserTab = btn.dataset.btype;
      dbRenderGrid(allCards);
    });
  });

  // Search
  $('db-search')?.addEventListener('input', e => {
    DB.search = e.target.value;
    dbRenderGrid(allCards);
  });

  // Quick-add toggle
  $('db-quick-add-toggle')?.addEventListener('click', () => {
    DB.quickAdd = !DB.quickAdd;
    $('db-quick-add-toggle').classList.toggle('active', DB.quickAdd);
  });

  // Card grid tap — interactive (popup) by default; quick-add when toggled
  $('db-card-grid')?.addEventListener('click', e => {
    const cell = e.target.closest('.db-card-cell');
    if (!cell || cell.classList.contains('violates')) return;
    const bobaId = cell.dataset.bobaId;
    const card = allCards.find(c => c.bobaId === bobaId);
    if (!card) return;

    if (DB.quickAdd) {
      // Immediate add
      DB.addCard(card);
      dbRender(allCards);
    } else {
      // Show card detail popup
      dbShowCardPopup(card, allCards);
    }
  });

  // Card popup — add button
  $('db-popup-add')?.addEventListener('click', () => {
    const bobaId = $('db-card-popup')?.dataset.bobaId;
    if (!bobaId) return;
    const card = allCards.find(c => c.bobaId === bobaId);
    if (!card) return;
    DB.addCard(card);
    dbRender(allCards);
    // Close popup immediately after adding
    dbHideCardPopup();
  });

  // Card popup — close
  $('db-popup-close')?.addEventListener('click', dbHideCardPopup);
  $('db-card-popup')?.addEventListener('click', e => {
    if (e.target === $('db-card-popup')) dbHideCardPopup();
  });

  // Deck list remove buttons (event delegation)
  modal.addEventListener('click', e => {
    const btn = e.target.closest('.db-card-row-remove');
    if (!btn) return;
    DB.removeCard(btn.dataset.remove, btn.dataset.section);
    dbRender(allCards);
  });

  // Deck name
  $('db-deck-name')?.addEventListener('input', e => { DB.deckName = e.target.value; });

  // Clear deck
  $('db-clear-btn')?.addEventListener('click', () => {
    DB.clear();
    const nameEl = $('db-deck-name');
    if (nameEl) nameEl.value = 'New Deck';
    dbRender(allCards);
  });

  // Templates — load from pre-computed template-decks.json
  $('db-templates')?.addEventListener('click', e => {
    const btn = e.target.closest('.db-template-btn');
    if (!btn) return;
    const meta = DB_TEMPLATES.find(t => t.id === btn.dataset.template);
    if (!meta) return;

    function applyTemplate(data) {
      const byId = {};
      for (const c of allCards) { if (c.bobaId) byId[c.bobaId] = c; }
      const tpl = data[meta.key];
      if (!tpl) return;
      DB.clear();
      DB.format = 'playmaker';
      modal.querySelectorAll('.db-format-btn').forEach(b => b.classList.toggle('active', b.dataset.format === 'playmaker'));
      DB.deckName = meta.name;
      DB.heroes    = tpl.heroIds.map(id => byId[id]).filter(Boolean);
      DB.plays     = tpl.playIds.map(id => byId[id]).filter(Boolean);
      DB.bonusPlays = (tpl.bonusPlayIds || []).map(id => byId[id]).filter(Boolean);
      DB.hotDogs   = tpl.hotDogIds.map(id => byId[id]).filter(Boolean);
      dbRender(allCards);
    }

    if (dbTemplateData) {
      applyTemplate(dbTemplateData);
    } else {
      fetch('assets/data/template-decks.json')
        .then(r => r.json())
        .then(data => { dbTemplateData = data; applyTemplate(data); })
        .catch(() => {
          // Fallback: random legal deck so the button is never broken
          DB.clear();
          DB.format = 'playmaker';
          DB.deckName = meta.name;
          const heroPool = allCards.filter(c => c.cardType === 'Hero' && (c.power || 0) > 0);
          const pvc = {}, hnc = {};
          for (const h of heroPool.sort(() => Math.random() - 0.5)) {
            if (DB.heroes.length >= 60) break;
            const p = h.power || 0;
            if ((pvc[p] || 0) >= 6) continue;
            const hn = h.hero || h.name;
            if ((hnc[hn] || 0) >= 6) continue;
            DB.heroes.push(h); pvc[p] = (pvc[p] || 0) + 1; hnc[hn] = (hnc[hn] || 0) + 1;
          }
          DB.plays   = allCards.filter(c => c.cardType === 'Play' && !(c.cardNumber || '').startsWith('BPL')).sort(() => Math.random() - 0.5).slice(0, 30);
          DB.hotDogs = allCards.filter(c => c.cardType === 'HotDog').slice(0, 10);
          dbRender(allCards);
        });
    }
  });

  // Export
  $('db-export-btn')?.addEventListener('click', () => {
    const outEl = $('db-export-out');
    if (!outEl) return;
    const textEl = $('db-export-text');
    if (textEl) textEl.value = DB.exportText();
    outEl.hidden = !outEl.hidden;
  });

  $('db-copy-btn')?.addEventListener('click', () => {
    const textEl = $('db-export-text');
    if (!textEl) return;
    navigator.clipboard.writeText(textEl.value).then(() => {
      const btn = $('db-copy-btn');
      if (btn) { btn.textContent = 'Copied!'; setTimeout(() => { btn.textContent = 'Copy Text'; }, 2000); }
    });
  });

  // CSV download — compatible with deck-builder.bobattlearena.com
  $('db-csv-btn')?.addEventListener('click', () => {
    const csv = DB.exportCSV();
    const blob = new Blob([csv], { type: 'text/csv' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href = url;
    a.download = `${DB.deckName.replace(/[^a-z0-9]/gi, '_')}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    const btn = $('db-csv-btn');
    if (btn) { btn.textContent = 'Downloaded!'; setTimeout(() => { btn.textContent = 'Download CSV'; }, 2000); }
  });

  // Save deck
  let DB_savedId = null; // track the Supabase deck id for the current deck

  $('db-save-btn')?.addEventListener('click', async () => {
    const session = await API.authGetSession();
    if (!session) {
      // Prompt sign-in
      Auth?.open?.();
      return;
    }
    const btn = $('db-save-btn');
    if (btn) { btn.disabled = true; }
    try {
      const cards = [
        ...DB.heroes.map(c => ({ bobaId: c.bobaId, cardType: 'hero' })),
        ...DB.plays.map(c => ({ bobaId: c.bobaId, cardType: 'play' })),
        ...DB.bonusPlays.map(c => ({ bobaId: c.bobaId, cardType: 'bonus_play' })),
        ...DB.hotDogs.map(c => ({ bobaId: c.bobaId, cardType: 'hot_dog' })),
      ];
      DB_savedId = await API.deckSave(DB_savedId, DB.deckName, DB.format, cards);
      if (btn) { btn.style.color = '#4CAF50'; setTimeout(() => { btn.style.color = ''; }, 2000); }
    } catch (err) {
      console.error('Deck save failed:', err);
      alert('Could not save deck. Please try again.');
    } finally {
      if (btn) { btn.disabled = false; }
    }
  });

  // Load saved decks
  $('db-load-btn')?.addEventListener('click', async () => {
    const panel = $('db-saved-decks-panel');
    if (!panel) return;
    if (!panel.hidden) { panel.hidden = true; return; }

    const session = await API.authGetSession();
    if (!session) {
      Auth?.open?.();
      return;
    }

    panel.hidden = false;
    const list = $('db-saved-decks-list');
    if (list) list.innerHTML = '<div class="db-saved-decks-empty">Loading…</div>';

    try {
      const decks = await API.deckList();
      if (!decks.length) {
        if (list) list.innerHTML = '<div class="db-saved-decks-empty">No saved decks yet.</div>';
        return;
      }
      if (list) {
        list.innerHTML = decks.map(d => `
          <div class="db-saved-deck-row" data-deck-id="${d.id}">
            <div class="db-saved-deck-info">
              <span class="db-saved-deck-name">${d.name}</span>
              <span class="db-saved-deck-meta">${(d.format || 'playmaker').toUpperCase()} · ${new Date(d.updated_at).toLocaleDateString()}</span>
            </div>
            <div class="db-saved-deck-actions">
              <button class="db-saved-deck-load" data-deck-id="${d.id}" data-deck-name="${d.name}" data-deck-format="${d.format || 'playmaker'}">Load</button>
              <button class="db-saved-deck-delete" data-deck-id="${d.id}" aria-label="Delete ${d.name}">✕</button>
            </div>
          </div>
        `).join('');
      }
    } catch (err) {
      console.error('Deck list failed:', err);
      if (list) list.innerHTML = '<div class="db-saved-decks-empty">Could not load decks.</div>';
    }
  });

  // Load a specific saved deck
  $('db-saved-decks-list')?.addEventListener('click', async e => {
    const loadBtn = e.target.closest('.db-saved-deck-load');
    const delBtn  = e.target.closest('.db-saved-deck-delete');

    if (loadBtn) {
      const deckId = loadBtn.dataset.deckId;
      const deckName = loadBtn.dataset.deckName;
      const deckFormat = loadBtn.dataset.deckFormat;
      try {
        const rows = await API.deckLoad(deckId);
        DB.clear();
        DB.deckName = deckName;
        DB.format   = deckFormat;
        const nameEl = $('db-deck-name');
        if (nameEl) nameEl.value = deckName;
        // Set format button
        document.querySelectorAll('#deck-builder-modal .db-format-btn').forEach(b => {
          b.classList.toggle('active', b.dataset.format === deckFormat);
        });
        const byBobaId = {};
        for (const c of allCards) { if (c.bobaId) byBobaId[c.bobaId] = c; }
        for (const row of rows) {
          const card = byBobaId[row.boba_id];
          if (!card) continue;
          if (row.card_type === 'hero')       DB.heroes.push(card);
          else if (row.card_type === 'play')  DB.plays.push(card);
          else if (row.card_type === 'bonus_play') DB.bonusPlays.push(card);
          else if (row.card_type === 'hot_dog')    DB.hotDogs.push(card);
        }
        DB_savedId = deckId;
        dbRender(allCards);
        $('db-saved-decks-panel').hidden = true;
      } catch (err) {
        console.error('Deck load failed:', err);
        alert('Could not load deck.');
      }
    }

    if (delBtn) {
      const deckId = delBtn.dataset.deckId;
      if (!confirm('Delete this deck?')) return;
      try {
        await API.deckDelete(deckId);
        delBtn.closest('.db-saved-deck-row')?.remove();
        if (DB_savedId === deckId) DB_savedId = null;
        const list = $('db-saved-decks-list');
        if (list && !list.querySelector('.db-saved-deck-row')) {
          list.innerHTML = '<div class="db-saved-decks-empty">No saved decks yet.</div>';
        }
      } catch (err) {
        console.error('Deck delete failed:', err);
        alert('Could not delete deck.');
      }
    }
  });
}

// ── Card popup helpers ───────────────────────────────────────────

const CDN_FULL = 'https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev';
function fullUrl(file) { return file ? `${CDN_FULL}/full/${file}` : null; }

function dbShowCardPopup(card, allCards) {
  const popup  = $('db-card-popup');
  if (!popup) return;
  popup.dataset.bobaId = card.bobaId || '';

  // Image
  const imgEl = $('db-popup-img');
  const phEl  = $('db-popup-placeholder');
  const fullSrc = card.imageFile ? fullUrl(card.imageFile) : null;
  if (fullSrc && imgEl) {
    imgEl.src = fullSrc;
    imgEl.alt = card.hero || card.name || '';
    imgEl.hidden = false;
    imgEl.onerror = () => { imgEl.hidden = true; if (phEl) { phEl.textContent = (card.hero || card.name || '??').substring(0, 2).toUpperCase(); phEl.hidden = false; } };
    if (phEl) phEl.hidden = true;
  } else {
    if (imgEl) imgEl.hidden = true;
    if (phEl)  { phEl.textContent = (card.hero || card.name || '??').substring(0, 2).toUpperCase(); phEl.hidden = false; }
  }

  // Name
  const nameEl = $('db-popup-name');
  if (nameEl) nameEl.textContent = card.hero || card.name || '';

  // Meta
  const metaEl = $('db-popup-meta');
  if (metaEl) {
    const parts = [];
    if (card.cardNumber)  parts.push(card.cardNumber);
    if (card.element)     parts.push(card.element);
    if (card.power != null && card.cardType === 'Hero') parts.push(`PWR ${card.power}`);
    if (card.playCost != null) parts.push(card.playCost === 0 ? 'FREE' : `${card.playCost} HD`);
    if (card.treatment)   parts.push(card.treatment);
    if (card.variation)   parts.push(card.variation);
    metaEl.textContent = parts.join(' · ');
  }

  // Description
  const descEl = $('db-popup-desc');
  if (descEl) descEl.textContent = card.description || '';

  // Add button state
  const addBtn = $('db-popup-add');
  if (addBtn) {
    const inDeck  = DB.isInDeck(card);
    const violates = DB.browserTab === 'hero' && DB.wouldHeroViolate(card);
    addBtn.disabled   = inDeck || violates;
    addBtn.textContent = inDeck ? 'In Deck' : violates ? 'Cannot Add' : 'Add to Deck';
  }

  popup.hidden = false;
}

function dbHideCardPopup() {
  const popup = $('db-card-popup');
  if (popup) { popup.hidden = true; popup.dataset.bobaId = ''; }
}

// ════════════════════════════════════════════════════════════════
// § Practice Battle — full interactive playmat (v3 design)
// ════════════════════════════════════════════════════════════════

function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// Detect if a play card recovers hot dogs; returns number to restore (0 = no recovery)
function pmDetectHDRecovery(card) {
  const text = ((card.playAbility || '') + ' ' + (card.description || '')).toLowerCase();
  if (!text.includes('hot dog') && !text.includes('hotdog')) return 0;
  const m = text.match(/(?:return|recover|gain|get|add|take back|retrieve)\s+(\d+|one|two|three)\s+hot\s*dog/i);
  if (m) {
    const vals = { 'one': 1, 'two': 2, 'three': 3 };
    const n = vals[m[1].toLowerCase()] ?? parseInt(m[1]);
    return isNaN(n) ? 1 : n;
  }
  // Fallback: any text about returning/gaining hot dogs
  if (/(?:return|recover|gain|take back|retrieve)\b/.test(text)) return 1;
  return 0;
}

function pmElementColor(el) {
  const map = {
    FIRE: '#FF4D00', ICE: '#00BFFF', HEX: '#8B00FF', STEEL: '#8A9BB0',
    BRAWL: '#C0392B', GLOW: '#FFD700', GUM: '#FF69B4', SUPER: '#FF00FF',
  };
  return map[el] || '#666680';
}

// ── PM state object ──────────────────────────────────────────────
const PM = {
  mode: 'playmaker',         // 'rookie' | 'substitution' | 'playmaker'
  battles: [],               // Array[7] of battle objects
  currentBattle: 0,
  phase: 'reveal',           // reveal | sub | play | resolution | cleanup | over
  playerScore: 0,
  cpuScore: 0,
  honors: 'player',          // 'player' | 'cpu'
  matchOver: false,
  matchWinner: null,         // 'player' | 'cpu' | null

  // Player resources
  playerHD: 10,
  playerBench: [],           // hero cards available to substitute in
  playerPlayHand: [],        // current play cards in hand (max 5)
  playerPlayDeck: [],        // remaining plays
  playerDiscard: [],         // discarded plays
  playerHeroDeckCount: 0,   // remaining heroes (for display)
  playerSubstituted: false,
  playerPassedPlays: false,

  // CPU resources
  cpuHD: 10,
  cpuBench: [],
  cpuPlayCount: 30,
  cpuSubstituted: false,
  cpuPassedPlays: false,

  selectedBenchIdx: null,    // which bench card is tapped for sub
  allCards: [],
  _initialized: false,       // event listeners attached once

  startMatch(allCards) {
    this.allCards = allCards;
    Object.assign(this, {
      matchOver: false, matchWinner: null, playerScore: 0, cpuScore: 0,
      honors: 'player', currentBattle: 0, phase: 'reveal',
      playerHD: 10, cpuHD: 10, cpuPlayCount: 30,
      playerSubstituted: false, cpuSubstituted: false,
      playerPassedPlays: false, cpuPassedPlays: false,
      selectedBenchIdx: null,
    });

    // Build hero pool — prioritize cards with images
    const heroes = allCards.filter(c => c.cardType === 'Hero' && (c.power || 0) > 0);
    const withImg = heroes.filter(c => c.imageFile);
    const noImg   = heroes.filter(c => !c.imageFile);
    const heroPool = [...shuffle([...withImg]), ...shuffle([...noImg])];

    // 7 battle slots per side + 6 bench cards per side = 13 each
    const playerCards = heroPool.slice(0, 13);
    const cpuCards    = heroPool.slice(13, 26);

    this.battles = [];
    for (let i = 0; i < 7; i++) {
      this.battles.push({
        id: i,
        playerCard: playerCards[i] || null,
        cpuCard:    cpuCards[i]    || null,
        playerEffectPower: 0,
        cpuEffectPower: 0,
        playerPlaysPlayed: [],
        result: null,
        revealed: false,
      });
    }

    // Bench = remaining 6 hero cards (indices 7-12)
    this.playerBench = [...playerCards.slice(7)];
    this.cpuBench    = [...cpuCards.slice(7)];

    // Build play hand from play cards
    const plays = allCards.filter(c => c.cardType === 'Play');
    const shuffledPlays = shuffle([...plays]);
    this.playerPlayHand = shuffledPlays.slice(0, 5);
    this.playerPlayDeck = shuffledPlays.slice(5, 30); // 30-card playbook: 5 in hand + 25 in deck
    this.playerDiscard  = [];
    this.playerHeroDeckCount = 47; // 60-card hero deck minus 13 dealt (7 battles + 6 bench)
  },

  advance() {
    if (this.matchOver) return;
    const b = this.battles[this.currentBattle];

    switch (this.phase) {
      case 'reveal':
        b.revealed = true;
        if (this.mode === 'rookie') {
          this.resolve();
        } else {
          this.phase = 'sub';
          this.playerSubstituted = false;
          this.cpuSubstituted = false;
          this.selectedBenchIdx = null;
          this.cpuDoSub();
        }
        break;

      case 'sub':
        // Player done with subs — move to play or resolve
        if (this.mode === 'playmaker') {
          this.phase = 'play';
          this.playerPassedPlays = false;
          this.cpuPassedPlays = false;
          // CPU plays a card or two
          this.cpuDoPlay();
        } else {
          this.resolve();
        }
        break;

      case 'play':
        // Player passes on playing more cards
        this.playerPassedPlays = true;
        if (!this.cpuPassedPlays) {
          // CPU gets one more chance to play after player passes
          this.cpuDoPlay();
        }
        if (this.playerPassedPlays && this.cpuPassedPlays) {
          this.resolve();
        }
        break;

      case 'resolution':
        this.phase = 'cleanup';
        break;

      case 'cleanup':
        this.drawPlayCard();
        this.nextBattle();
        break;

      case 'over':
        this.startMatch(this.allCards);
        break;
    }
  },

  playerSub(benchIdx) {
    if (this.phase !== 'sub' || this.playerSubstituted) return false;
    if (this.playerHD < 2) return false;
    if (benchIdx < 0 || benchIdx >= this.playerBench.length) return false;

    const benchCard   = this.playerBench[benchIdx];
    const activeCard  = this.battles[this.currentBattle].playerCard;
    this.battles[this.currentBattle].playerCard = benchCard;
    this.playerBench[benchIdx] = activeCard;
    this.playerHD -= 2;
    this.playerSubstituted = true;
    this.selectedBenchIdx = null;
    return true;
  },

  playerPlayCard(handIdx) {
    if (this.phase !== 'play') return false;
    if (handIdx < 0 || handIdx >= this.playerPlayHand.length) return false;
    const card = this.playerPlayHand[handIdx];
    const cost = card.playCost || 0;
    if (this.playerHD < cost) return false;

    this.playerHD -= cost;
    const hdRecovery = pmDetectHDRecovery(card);
    const b = this.battles[this.currentBattle];
    if (hdRecovery > 0) {
      // Recovery play: restore hot dogs instead of power bonus
      this.playerHD = Math.min(10, this.playerHD + hdRecovery);
    } else if (b) {
      // Tempo/boost play: give power bonus to current battle
      b.playerEffectPower = (b.playerEffectPower || 0) + Math.max(5, cost * 6 + 5);
    }
    if (b) b.playerPlaysPlayed.push(card);
    this.playerPlayHand.splice(handIdx, 1);
    this.playerDiscard.push(card);
    return true;
  },

  cpuDoSub() {
    if (this.cpuSubstituted || this.cpuBench.length === 0 || this.cpuHD < 2) {
      this.cpuSubstituted = true; return;
    }
    const b = this.battles[this.currentBattle];
    const cpuPow    = (b.cpuCard?.power || 0);
    const playerPow = (b.playerCard?.power || 0);

    // Find best bench card
    const bestIdx = this.cpuBench.reduce((bi, c, i) =>
      (c?.power || 0) > (this.cpuBench[bi]?.power || 0) ? i : bi, 0);
    const bestCard = this.cpuBench[bestIdx];
    const bestPow  = bestCard?.power || 0;

    // Sub if:
    //  - Losing by 10+ and bench has a better card (defensive), OR
    //  - Bench card is 30+ stronger (opportunistic upgrade), ~30% chance
    const defensiveSub    = playerPow - cpuPow >= 10 && bestPow > cpuPow;
    const opportunisticSub = bestPow - cpuPow >= 30 && Math.random() < 0.30;

    if (defensiveSub || opportunisticSub) {
      this.battles[this.currentBattle].cpuCard = bestCard;
      this.cpuBench[bestIdx] = b.cpuCard;
      this.cpuHD -= 2;
    }
    this.cpuSubstituted = true;
  },

  cpuDoPlay() {
    if (this.cpuPassedPlays) return;
    const b = this.battles[this.currentBattle];
    const numPlays = Math.random() < 0.4 ? 1 : 0;
    for (let i = 0; i < numPlays; i++) {
      if (this.cpuHD < 1 || this.cpuPlayCount <= 0) break;
      const cost = Math.min(Math.floor(Math.random() * 3) + 1, this.cpuHD);
      this.cpuHD -= cost;
      this.cpuPlayCount--;
      b.cpuEffectPower = (b.cpuEffectPower || 0) + (cost * 6 + 5);
    }
    this.cpuPassedPlays = true;
  },

  resolve() {
    const b = this.battles[this.currentBattle];
    const playerPow = (b.playerCard?.power || 0) + (b.playerEffectPower || 0);
    const cpuPow    = (b.cpuCard?.power    || 0) + (b.cpuEffectPower    || 0);

    if (playerPow > cpuPow) {
      b.result = 'win';  this.playerScore++; this.honors = 'player';
    } else if (cpuPow > playerPow) {
      b.result = 'lose'; this.cpuScore++;    this.honors = 'cpu';
    } else {
      const pSuper = b.playerCard?.element === 'SUPER';
      const cSuper = b.cpuCard?.element    === 'SUPER';
      if (pSuper && !cSuper) {
        b.result = 'win';  this.playerScore++; this.honors = 'player';
      } else if (cSuper && !pSuper) {
        b.result = 'lose'; this.cpuScore++;    this.honors = 'cpu';
      } else {
        b.result = 'tie';
      }
    }
    this.phase = 'resolution';
    this.checkOver();
  },

  checkOver() {
    if (this.playerScore >= 4) { this.matchOver = true; this.matchWinner = 'player'; this.phase = 'over'; }
    else if (this.cpuScore >= 4) { this.matchOver = true; this.matchWinner = 'cpu'; this.phase = 'over'; }
  },

  nextBattle() {
    if (this.matchOver) return;
    const next = this.currentBattle + 1;
    if (next >= 7) {
      this.matchOver = true;
      if (this.playerScore > this.cpuScore) this.matchWinner = 'player';
      else if (this.cpuScore > this.playerScore) this.matchWinner = 'cpu';
      else this.matchWinner = null;
      this.phase = 'over';
      return;
    }
    this.currentBattle = next;
    this.phase = 'reveal';
    this.playerSubstituted = false;
    this.cpuSubstituted = false;
    this.playerPassedPlays = false;
    this.cpuPassedPlays = false;
    this.selectedBenchIdx = null;
  },

  drawPlayCard() {
    if (this.mode !== 'playmaker') return;
    if (this.playerPlayDeck.length === 0 && this.playerDiscard.length > 0) {
      this.playerPlayDeck = shuffle([...this.playerDiscard]);
      this.playerDiscard = [];
    }
    if (this.playerPlayDeck.length > 0) {
      this.playerPlayHand.push(this.playerPlayDeck.shift());
    }
  },
};

// ── DOM helpers ──────────────────────────────────────────────────

function pmBuildPlaymatHTML() {
  const cols = Array.from({length: 7}, (_, i) => `
    <div class="pm-bc pending" data-battle="${i}">
      <span class="pm-bc-number">B${i + 1}</span>
      <div class="pm-bc-opp"></div>
      <div class="pm-bc-vs"><span>·</span></div>
      <div class="pm-bc-player"></div>
    </div>`).join('');

  const scorePips = Array.from({length: 7}, (_, i) =>
    `<div class="pm-score-pip" data-pip="${i}">${i + 1}</div>`).join('');

  const hdPips = Array.from({length: 10}, (_, i) =>
    `<div class="pm-hd-pip available" data-pip="${i}"></div>`).join('');

  const xoxoSvg = `<svg class="pm-icon pm-icon-lg" style="color:#FF4D00"><use href="#icon-xoxo"/></svg>`;
  const hdIcon  = `<svg class="pm-icon"><use href="#icon-hotdog"/></svg>`;

  return `
  <!-- TOP BAR -->
  <div class="pm-top-bar">
    <div class="pm-mode-tabs">
      <button class="pm-mode-tab" data-mode="rookie">Rookie</button>
      <button class="pm-mode-tab" data-mode="substitution">Sub</button>
      <button class="pm-mode-tab active" data-mode="playmaker">Playmaker</button>
    </div>
    <div class="pm-scoreboard">
      <span class="pm-score-label">Battle</span>
      <div class="pm-score-pips">${scorePips}</div>
      <div class="pm-score-totals">
        <span class="pm-score-you" id="pm-score-you">0</span>
        <span class="pm-score-dash">—</span>
        <span class="pm-score-opp-val" id="pm-score-opp">0</span>
      </div>
    </div>
    <div class="pm-top-logo">${xoxoSvg}</div>
    <div class="pm-phase-area">
      <div class="pm-phase-indicator" id="pm-phase-label"><i data-lucide="eye" class="pm-icon pm-phase-icon" id="pm-phase-icon"></i>REVEAL</div>
      <div class="pm-honors-badge" id="pm-honors"><i data-lucide="star" class="pm-icon pm-icon-sm" style="color:#FFD700"></i> YOU HAVE HONORS</div>
    </div>
    <button class="pm-top-exit" id="pm-exit-btn" aria-label="Exit practice"><i data-lucide="x" class="pm-icon"></i></button>
  </div>

  <!-- PLAY AREA -->
  <div class="pm-play-area">
    <div class="pm-opponent-zone">
      <span class="pm-opp-section-label">OPP</span>
      <div class="pm-opp-bench-area">
        <span class="pm-opp-sub-label">Bench</span>
        <div id="pm-opp-bench" style="display:flex;gap:3px"></div>
      </div>
      <div class="pm-opp-plays-area">
        <span class="pm-opp-sub-label">Plays</span>
        <div class="pm-resource-chip">
          <span class="pm-rc-val" id="pm-opp-plays-val">30</span>
          <span class="pm-rc-label">left</span>
        </div>
      </div>
      <div class="pm-opp-resources">
        <div class="pm-resource-chip">
          ${hdIcon}
          <span class="pm-rc-val" id="pm-opp-hd">10</span>
          <span class="pm-rc-label">HD</span>
        </div>
      </div>
    </div>
    <div class="pm-arena-zone">${cols}</div>
  </div>

  <!-- PLAYER ZONE -->
  <div class="pm-player-zone">
    <div class="pm-deck-stack">
      <div class="pm-deck-icon pm-hero-deck-icon">
        <i data-lucide="swords" class="pm-icon" style="color:rgba(192,57,43,0.9)"></i>
        <span class="pm-di-count" id="pm-hero-deck-count">—</span>
      </div>
      <span class="pm-deck-label">Heroes</span>
    </div>
    <div class="pm-deck-stack pm-play-deck-stack">
      <div class="pm-deck-icon pm-play-deck-icon">
        <svg class="pm-icon" style="color:#8B00FF"><use href="#icon-xoxo"/></svg>
        <span class="pm-di-count" id="pm-play-deck-count">—</span>
      </div>
      <span class="pm-deck-label">Plays</span>
    </div>
    <div class="pm-deck-stack pm-hd-deck-stack">
      <div class="pm-deck-icon pm-hd-deck-icon">${hdIcon}<span class="pm-di-count">10</span></div>
      <span class="pm-deck-label">Hot Dogs</span>
    </div>
    <div class="pm-zone-divider"></div>
    <div class="pm-bench-area">
      <span class="pm-bench-label">Bench — Tap to Sub</span>
      <div class="pm-bench-cards" id="pm-bench-cards"></div>
    </div>
    <div class="pm-zone-divider pm-divider-bench"></div>
    <div class="pm-hand-area">
      <span class="pm-hand-label">Plays — Tap to Play</span>
      <div class="pm-hand-cards" id="pm-hand-cards"></div>
    </div>
    <div class="pm-zone-divider pm-divider-hand"></div>
    <div class="pm-hd-area">
      <span class="pm-hd-label">${hdIcon} <span class="pm-hd-count-display" id="pm-hd-count">10</span>/10</span>
      <div class="pm-hd-pips" id="pm-hd-pips">${hdPips}</div>
    </div>
    <div class="pm-zone-divider"></div>
    <div class="pm-action-area">
      <button class="pm-btn-sub" id="pm-btn-sub" disabled>SUB<br><span style="font-size:0.35rem;opacity:0.7">2 HD</span></button>
      <button class="pm-btn-done" id="pm-btn-done">REVEAL →</button>
    </div>
    <div class="pm-zone-divider"></div>
    <div class="pm-discard-stack">
      <div class="pm-deck-icon" style="border-style:dashed;background:transparent;opacity:0.4">
        <i data-lucide="rotate-ccw" class="pm-icon" style="opacity:0.6"></i>
        <span class="pm-di-count" id="pm-discard-count">0</span>
      </div>
      <span class="pm-deck-label">Discard</span>
    </div>
  </div>

  <!-- Phase transition banner -->
  <div class="pm-phase-banner" id="pm-phase-banner"></div>

  <!-- Match over overlay -->
  <div class="pm-match-over-overlay" id="pm-match-over" hidden>
    <div class="pm-result-title" id="pm-result-title">VICTORY!</div>
    <div class="pm-result-score" id="pm-result-score">0 — 0</div>
    <div class="pm-result-btns">
      <button class="pm-result-btn" id="pm-restart">PLAY AGAIN</button>
      <button class="pm-result-btn secondary" id="pm-exit-match">EXIT</button>
    </div>
  </div>`;
}

// ── Update functions (target DOM directly — no full re-render) ───

function pmSetRootClass() {
  const root = $('practice-playmat');
  if (!root) return;
  root.className = root.className.replace(/\b(?:mode|phase)-\S+/g, '').trim();
  root.classList.add('pm-root', `mode-${PM.mode}`, `phase-${PM.phase}`);

  // Update mode tabs
  root.querySelectorAll('.pm-mode-tab').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.mode === PM.mode);
  });

  // Phase label
  const phaseNames = {
    reveal: 'REVEAL', sub: 'SUB WINDOW', play: 'PLAY WINDOW',
    resolution: 'RESOLUTION', cleanup: 'CLEANUP', over: 'MATCH OVER',
  };
  const btnLabels = {
    reveal: 'REVEAL CARDS →', sub: 'DONE WITH SUBS →', play: 'DONE PLAYING →',
    resolution: 'NEXT →', cleanup: 'NEXT BATTLE →', over: 'PLAY AGAIN',
  };

  const phaseIcons = {
    reveal: 'eye', sub: 'zap', play: 'layers',
    resolution: 'scale', cleanup: 'rotate-cw', over: 'trophy',
  };

  const phaseEl = $('pm-phase-label');
  if (phaseEl) {
    const iconName = phaseIcons[PM.phase] || 'eye';
    phaseEl.innerHTML = `<i data-lucide="${iconName}" class="pm-icon pm-phase-icon"></i>${phaseNames[PM.phase] || PM.phase.toUpperCase()}`;
    if (typeof lucide !== 'undefined') lucide.createIcons({ nodes: [phaseEl] });
  }

  const doneBtn = $('pm-btn-done');
  if (doneBtn) doneBtn.textContent = btnLabels[PM.phase] || 'NEXT →';

  // Honors
  const honorsEl = $('pm-honors');
  if (honorsEl) {
    const who = PM.honors === 'player' ? 'YOU HAVE HONORS' : 'CPU HAS HONORS';
    honorsEl.innerHTML = `<i data-lucide="star" class="pm-icon pm-icon-sm" style="color:#FFD700"></i> ${who}`;
    if (typeof lucide !== 'undefined') lucide.createIcons({ nodes: [honorsEl] });
  }

  // Phase banner
  if (PM.phase !== 'over') {
    const banner = $('pm-phase-banner');
    if (banner) {
      banner.textContent = phaseNames[PM.phase] || PM.phase.toUpperCase();
      banner.classList.add('visible');
      setTimeout(() => banner.classList.remove('visible'), 900);
    }
  }
}

function pmUpdateScoreboard() {
  const youEl = $('pm-score-you');
  const oppEl = $('pm-score-opp');
  if (youEl) youEl.textContent = PM.playerScore;
  if (oppEl) oppEl.textContent = PM.cpuScore;

  document.querySelectorAll('#practice-playmat .pm-score-pip').forEach((pip, idx) => {
    pip.className = 'pm-score-pip';
    const b = PM.battles[idx];
    if (!b) return;
    if (b.result === 'win')  pip.classList.add('you-won');
    else if (b.result === 'lose') pip.classList.add('opp-won');
    else if (idx === PM.currentBattle && !PM.matchOver) pip.classList.add('current');
    pip.textContent = idx + 1;
  });
}

function pmRenderBattleSlotContent(slot, card, revealed, isOpp, battle) {
  if (!card) {
    slot.innerHTML = `<span class="pm-bc-power" style="color:rgba(255,255,255,0.2)">—</span>`;
    return;
  }
  if (isOpp && !revealed) {
    slot.innerHTML = `<svg width="22" height="30" viewBox="0 0 20 28" fill="none" aria-hidden="true"><rect x="1" y="1" width="18" height="26" rx="3" stroke="rgba(192,57,43,0.45)" stroke-width="1.5"/><line x1="10" y1="4" x2="10" y2="18" stroke="rgba(192,57,43,0.35)" stroke-width="1.2"/><line x1="4" y1="11" x2="16" y2="11" stroke="rgba(192,57,43,0.35)" stroke-width="1.2"/></svg>`;
    return;
  }
  const eff     = battle ? (isOpp ? (battle.cpuEffectPower||0) : (battle.playerEffectPower||0)) : 0;
  const basePow = card.power || 0;
  const effPow  = basePow + eff;
  const imgUrl  = card.imageFile ? thumbUrl(card.imageFile) : null;
  const imgHtml = imgUrl ? `<img class="pm-slot-img" src="${imgUrl}" alt="${card.hero||card.name}" loading="lazy" onerror="this.style.display='none'">` : '';
  const bonusHtml = eff > 0 ? `<span class="pm-bc-bonus" style="color:${isOpp?'#8B00FF':'#00F5FF'}">+${eff}</span>` : '';
  slot.innerHTML = `${imgHtml}<span class="pm-bc-name">${(card.hero||card.name||'').substring(0,8)}</span><span class="pm-bc-power">${effPow}</span>${bonusHtml}`;
  if (card.element) {
    const bar = document.createElement('div');
    bar.className = 'pm-bc-element';
    bar.style.background = pmElementColor(card.element);
    slot.appendChild(bar);
  }
}

function pmUpdateBattleCols() {
  for (let idx = 0; idx < 7; idx++) {
    const col = document.querySelector(`#practice-playmat .pm-bc[data-battle="${idx}"]`);
    if (!col) continue;
    const b = PM.battles[idx];
    if (!b) continue;

    const isActive  = idx === PM.currentBattle && !PM.matchOver;
    const isDone    = b.result !== null;
    const isPending = !isDone && !isActive;

    col.className = 'pm-bc' +
      (isActive  ? ' active'  : '') +
      (isDone ? (b.result === 'win' ? ' won' : b.result === 'lose' ? ' lost' : ' tied') : '') +
      (isPending ? ' pending' : '');

    // VS bar
    const vsBar = col.querySelector('.pm-bc-vs');
    if (vsBar) {
      vsBar.className = 'pm-bc-vs' + (b.result === 'win' ? ' win' : b.result === 'lose' ? ' lose' : b.result === 'tie' ? ' tied' : '');
      const s = vsBar.querySelector('span');
      if (s) s.textContent = b.result === 'win' ? 'WIN' : b.result === 'lose' ? 'LOSS' : b.result === 'tie' ? 'TIE' : isActive ? 'VS' : '·';
    }

    // Opponent slot
    const oppSlot = col.querySelector('.pm-bc-opp');
    if (oppSlot) pmRenderBattleSlotContent(oppSlot, b.cpuCard, b.revealed || isDone, true, b);

    // Player slot
    const playerSlot = col.querySelector('.pm-bc-player');
    if (playerSlot) pmRenderBattleSlotContent(playerSlot, b.playerCard, true, false, b);
  }
}

function pmUpdateOpponentZone() {
  // Opponent bench count (show card back shapes)
  const oppBench = $('pm-opp-bench');
  if (oppBench) {
    oppBench.innerHTML = PM.cpuBench.map(() =>
      `<div class="pm-opp-card"></div>`
    ).join('');
  }
  const oppHD = $('pm-opp-hd');
  if (oppHD) oppHD.textContent = PM.cpuHD;
  const oppPlays = $('pm-opp-plays-val');
  if (oppPlays) oppPlays.textContent = PM.cpuPlayCount;
}

function pmUpdatePlayerZone() {
  // HD count and pips
  const hdCount = $('pm-hd-count');
  if (hdCount) hdCount.textContent = PM.playerHD;
  const pipsEl = $('pm-hd-pips');
  if (pipsEl) {
    pipsEl.querySelectorAll('.pm-hd-pip').forEach((pip, i) => {
      pip.className = 'pm-hd-pip ' + (i < PM.playerHD ? 'available' : 'spent');
    });
  }

  // Bench cards
  const benchEl = $('pm-bench-cards');
  if (benchEl) {
    benchEl.innerHTML = PM.playerBench.map((card, idx) => {
      if (!card) return '';
      const el    = card.element || '';
      const elCol = pmElementColor(el);
      const isSel = PM.selectedBenchIdx === idx;
      const imgUrl = card.imageFile ? thumbUrl(card.imageFile) : null;
      const imgHtml = imgUrl
        ? `<img class="pm-bc-sub-img" src="${imgUrl}" alt="" loading="lazy" onerror="this.style.display='none'">`
        : `<span class="pm-bc-sub-initials">${(card.hero||card.name||'??').substring(0,2).toUpperCase()}</span>`;
      return `<div class="pm-bench-card${isSel ? ' selected' : ''}" data-bench-idx="${idx}" title="${card.hero||card.name||''} (${el} ${card.power||0})">
        ${imgHtml}
        <div class="pm-bc-sub-overlay">
          <div class="pm-bc-sub-el" style="background:${elCol}"></div>
          <span class="pm-bc-sub-power">${card.power||0}</span>
        </div>
      </div>`;
    }).join('');
  }

  // Play hand — tap to view popup, not immediate play
  const handEl = $('pm-hand-cards');
  if (handEl) {
    handEl.innerHTML = PM.playerPlayHand.map((card, idx) => {
      const cost      = card.playCost || 0;
      const canAfford = PM.playerHD >= cost;
      const name      = (card.name || '').substring(0, 14);
      const imgUrl    = card.imageFile ? thumbUrl(card.imageFile) : null;
      const imgHtml   = imgUrl ? `<img class="pm-pc-img" src="${imgUrl}" alt="" loading="lazy" onerror="this.style.display='none'">` : '';
      return `<div class="pm-play-card${!canAfford ? ' cannot-afford' : ''}" data-hand-idx="${idx}" title="${card.name||''} — tap to view">
        ${imgHtml}
        <div class="pm-pc-header">
          <span class="pm-pc-name">${name}</span>
          <span class="pm-pc-cost">${cost > 0 ? cost + 'HD' : 'FREE'}</span>
        </div>
      </div>`;
    }).join('');
  }

  // Deck counts
  const hdEl  = $('pm-hero-deck-count');
  const plEl  = $('pm-play-deck-count');
  const discEl = $('pm-discard-count');
  if (hdEl)  hdEl.textContent  = PM.playerHeroDeckCount;
  if (plEl)  plEl.textContent  = PM.playerPlayDeck.length;
  if (discEl) discEl.textContent = PM.playerDiscard.length;

  // Sub button — enabled only when a bench card is selected and conditions met
  const subBtn = $('pm-btn-sub');
  if (subBtn) {
    const canSub = PM.phase === 'sub' && !PM.playerSubstituted && PM.playerHD >= 2 && PM.selectedBenchIdx !== null;
    subBtn.disabled = !canSub;
  }
}

function pmUpdateMatchOverlay() {
  const overlay = $('pm-match-over');
  if (!overlay) return;
  if (PM.phase === 'over') {
    overlay.hidden = false;
    const title = $('pm-result-title');
    const score = $('pm-result-score');
    if (title) {
      title.className = `pm-result-title ${PM.matchWinner === 'player' ? 'win' : PM.matchWinner === 'cpu' ? 'lose' : 'tie'}`;
      title.textContent = PM.matchWinner === 'player' ? 'VICTORY!' : PM.matchWinner === 'cpu' ? 'DEFEAT' : 'SUDDEN DEATH';
    }
    if (score) score.textContent = `${PM.playerScore} — ${PM.cpuScore}`;
  } else {
    overlay.hidden = true;
  }
}

function pmUpdateAll() {
  pmSetRootClass();
  pmUpdateScoreboard();
  pmUpdateBattleCols();
  pmUpdateOpponentZone();
  pmUpdatePlayerZone();
  pmUpdateMatchOverlay();
}

// ── Init (event listeners attached once per session) ────────────

function pmExitPlaymat() {
  const modal  = $('practice-modal');
  const setup  = $('practice-setup');
  const mat    = $('practice-playmat');
  if (modal) modal.classList.remove('playmat-mode');
  if (setup) setup.hidden = false;
  if (mat)   mat.hidden = true;
  const header = modal?.querySelector('.play-modal-header');
  if (header) header.hidden = false;
}

// Show a popup for a play card so the user can read the effect before deciding to play
function pmShowPlayCardPopup(handIdx) {
  const card = PM.playerPlayHand[handIdx];
  if (!card) return;

  // Remove any existing popup
  document.getElementById('pm-play-popup')?.remove();

  const cost       = card.playCost || 0;
  const canAfford  = PM.playerHD >= cost;
  const imgUrl     = card.imageFile ? thumbUrl(card.imageFile) : null;
  const ability    = card.playAbility || card.description || '—';
  const costLabel  = cost === 0 ? 'FREE' : `${cost} HD`;
  const hdNote     = !canAfford ? ` <span style="color:#C0392B">(not enough HD)</span>` : '';

  const popup = document.createElement('div');
  popup.id = 'pm-play-popup';
  popup.className = 'pm-play-popup';
  popup.innerHTML = `
    <div class="pm-play-popup-inner">
      ${imgUrl ? `<img class="pm-play-popup-img" src="${imgUrl}" alt="${card.name||''}" onerror="this.style.display='none'">` : ''}
      <div class="pm-play-popup-body">
        <div class="pm-play-popup-name">${card.name || ''}</div>
        <div class="pm-play-popup-cost">${costLabel}${hdNote}</div>
        <div class="pm-play-popup-effect">${ability}</div>
        <div class="pm-play-popup-actions">
          <button class="pm-play-popup-cancel">Cancel</button>
          <button class="pm-play-popup-play${!canAfford ? ' cannot-afford' : ''}"${!canAfford ? ' disabled' : ''}>
            Play Card
          </button>
        </div>
      </div>
    </div>`;

  popup.querySelector('.pm-play-popup-play').addEventListener('click', () => {
    if (PM.playerPlayCard(handIdx)) { popup.remove(); pmUpdateAll(); }
  });
  popup.querySelector('.pm-play-popup-cancel').addEventListener('click', () => popup.remove());
  popup.addEventListener('click', e => { if (e.target === popup) popup.remove(); });

  const mat = $('practice-playmat');
  if (mat) mat.appendChild(popup);
}

function pmInitPlaymat() {
  if (PM._initialized) return;
  PM._initialized = true;

  // HD pips — manual tracking (click to spend/recover)
  $('pm-hd-pips')?.addEventListener('click', e => {
    const pip = e.target.closest('.pm-hd-pip');
    if (!pip) return;
    const i = parseInt(pip.dataset.pip);
    // If clicking an available pip, spend down to that index; if spent, recover up to include it
    PM.playerHD = i < PM.playerHD ? i : i + 1;
    PM.playerHD = Math.max(0, Math.min(10, PM.playerHD));
    pmUpdatePlayerZone();
  });

  // Bench card tap → select for substitution
  $('pm-bench-cards')?.addEventListener('click', e => {
    const card = e.target.closest('.pm-bench-card');
    if (!card) return;
    if (PM.phase !== 'sub' || PM.playerSubstituted) return;
    const idx = parseInt(card.dataset.benchIdx);
    PM.selectedBenchIdx = PM.selectedBenchIdx === idx ? null : idx;
    pmUpdatePlayerZone();
  });

  // Substitute button — confirmed sub
  $('pm-btn-sub')?.addEventListener('click', () => {
    if (PM.selectedBenchIdx === null) return;
    if (PM.playerSub(PM.selectedBenchIdx)) pmUpdateAll();
  });

  // Play card click — show detail popup first so user can read effect before playing
  $('pm-hand-cards')?.addEventListener('click', e => {
    const card = e.target.closest('.pm-play-card');
    if (!card) return;
    const idx = parseInt(card.dataset.handIdx);
    pmShowPlayCardPopup(idx);
  });

  // Done / advance button
  $('pm-btn-done')?.addEventListener('click', () => {
    PM.advance();
    pmUpdateAll();
  });

  // Mode tabs inside playmat
  document.querySelectorAll('#practice-playmat .pm-mode-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      PM.mode = btn.dataset.mode;
      pmSetRootClass();
    });
  });

  // Exit / restart buttons
  $('pm-exit-btn')?.addEventListener('click', pmExitPlaymat);
  $('pm-exit-match')?.addEventListener('click', pmExitPlaymat);
  $('pm-restart')?.addEventListener('click', () => {
    PM.startMatch(PM.allCards);
    pmUpdateAll();
  });
}

function initPractice(allCards) {
  const modal = $('practice-modal');
  if (!modal) return;

  $('btn-open-practice')?.addEventListener('click', () => {
    modal.hidden = false;
    $('practice-setup').hidden = false;
    $('practice-playmat').hidden = true;
    modal.classList.remove('playmat-mode');
    const hdr = modal.querySelector('.play-modal-header');
    if (hdr) hdr.hidden = false;
  });
  $('btn-close-practice')?.addEventListener('click', () => { modal.hidden = true; });
  modal.addEventListener('click', e => { if (e.target === modal) modal.hidden = true; });

  // Mode radio
  modal.querySelectorAll('input[name="practice-mode"]').forEach(radio => {
    radio.addEventListener('change', e => { PM.mode = e.target.value; });
  });

  // Deck choice
  $('practice-player-deck')?.querySelectorAll('.practice-deck-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      $('practice-player-deck').querySelectorAll('.practice-deck-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
    });
  });

  // Start
  $('btn-start-practice')?.addEventListener('click', () => {
    const checked = modal.querySelector('input[name="practice-mode"]:checked');
    PM.mode = checked ? checked.value : 'playmaker';

    // Build playmat HTML once
    const mat = $('practice-playmat');
    if (mat && !PM._initialized) {
      mat.innerHTML = pmBuildPlaymatHTML();
      if (typeof lucide !== 'undefined') lucide.createIcons({ nodes: [mat] });
    }

    PM.startMatch(allCards);

    // Switch to playmat view
    const setup = $('practice-setup');
    const hdr   = modal.querySelector('.play-modal-header');
    if (setup) setup.hidden = true;
    if (hdr)   hdr.hidden = true;
    if (mat)   mat.hidden = false;
    modal.classList.add('playmat-mode');

    pmInitPlaymat();
    pmUpdateAll();
  });
}

// ════════════════════════════════════════════════════════════════
// § Init — called from app.js after displayCards loaded
// ════════════════════════════════════════════════════════════════

function initPlayTools(allCards) {
  initDeckBuilder(allCards);
  initPractice(allCards);
}

// Export for app.js
if (typeof window !== 'undefined') {
  window.initPlayTools = initPlayTools;
}
