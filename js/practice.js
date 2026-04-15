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
    rookie:       { heroTarget: 60, playsTarget: 30, needsHD: false, needsPlays: false, powerCap: null,  totalPowerCap: null  },
    substitution: { heroTarget: 60, playsTarget: 30, needsHD: true,  needsPlays: false, powerCap: null,  totalPowerCap: null  },
    playmaker:    { heroTarget: 60, playsTarget: 30, needsHD: true,  needsPlays: true,  powerCap: null,  totalPowerCap: null  },
    spec:         { heroTarget: 60, playsTarget: 30, needsHD: true,  needsPlays: true,  powerCap: 160,   totalPowerCap: null  },
    elite:        { heroTarget: 60, playsTarget: 30, needsHD: true,  needsPlays: true,  powerCap: null,  totalPowerCap: 8250  },
    sealed:       { heroTarget: 40, playsTarget: 20, needsHD: true,  needsPlays: true,  powerCap: null,  totalPowerCap: null  },
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
      if (this.plays.length < (this.currentFormat.playsTarget || 30)) this.plays.push(card);
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
      const pt = fmt.playsTarget || 30;
      const pd = pt - this.plays.length;
      if (pd > 0) errors.push(`Need ${pd} more plays (${this.plays.length}/${pt})`);
      if (pd < 0) errors.push(`Too many plays (${this.plays.length}/${pt})`);
    }

    if (fmt.totalPowerCap) {
      const total = this.heroes.reduce((s, c) => s + (c.power || 0), 0);
      if (total > fmt.totalPowerCap) errors.push(`Total power ${total} exceeds ${fmt.totalPowerCap} cap`);
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
      lines.push(`## Plays (${this.plays.length}/${this.currentFormat.playsTarget || 30})`);
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
  if (pStat) pStat.textContent = `Plays: ${DB.plays.length}/${DB.currentFormat.playsTarget || 30}`;
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
  const view = $('view-decks');
  if (!view) return;

  dbRenderTemplates();
  dbRender(allCards);

  // Format pills
  view.querySelectorAll('.db-format-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      view.querySelectorAll('.db-format-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      DB.format = btn.dataset.format;
      dbRender(allCards);
    });
  });

  // Browser tabs
  view.querySelectorAll('.db-btab').forEach(btn => {
    btn.addEventListener('click', () => {
      view.querySelectorAll('.db-btab').forEach(b => b.classList.remove('active'));
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
  view.addEventListener('click', e => {
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
      view.querySelectorAll('.db-format-btn').forEach(b => b.classList.toggle('active', b.dataset.format === 'playmaker'));
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
        document.querySelectorAll('#view-decks .db-format-btn').forEach(b => {
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
  if (/(?:return|recover|gain|take back|retrieve)\b/.test(text)) return 1;
  return 0;
}

// ── Play card effects engine (ported from iOS PracticeStore) ──────
// Returns { playerDelta, cpuDelta } power changes
function pmResolveEffect(card, playerCard, cpuCard) {
  const ability = card.playAbility || '';
  if (!ability) return pmFallbackEffect(card.playCost || 0);

  // Numeric-only abilities (shorthand like "75", "100")
  const numVal = parseInt(ability.trim());
  if (!isNaN(numVal) && numVal > 0 && /^\d+$/.test(ability.trim())) return { playerDelta: numVal, cpuDelta: 0 };

  const text = ability.toLowerCase();

  // Power swap / set effects
  if (text.includes('swap your hero\'s current power with your opponent') || text.includes('swap current power with your opponent')) {
    const myPow = playerCard?.power || 0, theirPow = cpuCard?.power || 0;
    return { playerDelta: theirPow - myPow, cpuDelta: myPow - theirPow };
  }
  if (text.includes('set your hero\'s power to 5 higher') || text.includes('set your hero\'s power to the same')) {
    const theirPow = cpuCard?.power || 0, myPow = playerCard?.power || 0;
    const target = text.includes('5 higher') ? theirPow + 5 : theirPow;
    return { playerDelta: target - myPow, cpuDelta: 0 };
  }
  if (text.includes('same power as your opponent') || text.includes('same as your opponent')) {
    return { playerDelta: (cpuCard?.power || 0) - (playerCard?.power || 0), cpuDelta: 0 };
  }
  if (text.includes('power is doubled')) return { playerDelta: playerCard?.power || 0, cpuDelta: 0 };

  // Cancel effects
  if (text.includes('cancel every play your opponent') || text.includes('cancel all plays')) return { playerDelta: 0, cpuDelta: 0 };

  // Steal effects
  if (text.includes('steal')) {
    let m = text.match(/steal -(\d+).*\+(\d+)/);
    if (m) return { playerDelta: parseInt(m[2]) || 5, cpuDelta: -(parseInt(m[1]) || 5) };
    return { playerDelta: 5, cpuDelta: -5 };
  }

  // Coin flip
  if (text.includes('flip a coin')) return pmResolveCoinFlip(text, playerCard);

  // Dice roll
  if (text.includes('roll a di') || text.includes('roll a die')) return pmResolveDiceRoll(text, playerCard, cpuCard);

  // Simple "+N" to your hero
  let m = text.match(/(?:your|this|give your|the) (?:hero|current hero|hero's power|active hero).*?(?:gets?|gains?|in the active battle.*?gets) \+(\d+)/);
  if (m) {
    const bonus = parseInt(m[1]) || 0;
    const wm = text.match(/if your hero has (?:a |an )?(\w+) weapon/);
    if (wm && playerCard?.element !== wm[1].toUpperCase()) return { playerDelta: 0, cpuDelta: 0 };
    return { playerDelta: bonus, cpuDelta: 0 };
  }

  // "All your heroes get +N"
  m = text.match(/all your heroes get \+(\d+)/);
  if (m) return { playerDelta: parseInt(m[1]) || 10, cpuDelta: 0 };
  m = text.match(/all your opponent's heroes get -(\d+)/);
  if (m) return { playerDelta: 0, cpuDelta: -(parseInt(m[1]) || 10) };

  // Opponent power reduction patterns
  m = text.match(/opponent's hero(?:'s power)?.*?(?:gets?|loses?) -(\d+)/);
  if (m) return { playerDelta: 0, cpuDelta: -(parseInt(m[1]) || 0) };
  m = text.match(/lower.*?opponent.*?-(\d+)/);
  if (m) return { playerDelta: 0, cpuDelta: -(parseInt(m[1]) || 0) };
  m = text.match(/their hero gets -(\d+)/);
  if (m) return { playerDelta: 0, cpuDelta: -(parseInt(m[1]) || 0) };
  if (text.includes('opponent')) {
    m = text.match(/give it -(\d+)/);
    if (m) return { playerDelta: 0, cpuDelta: -(parseInt(m[1]) || 0) };
  }

  // Weapon-conditional boost
  m = text.match(/if your hero has (?:a |an )?(\w+) weapon.*?\+(\d+)/);
  if (m) return playerCard?.element === m[1].toUpperCase() ? { playerDelta: parseInt(m[2]) || 0, cpuDelta: 0 } : { playerDelta: 0, cpuDelta: 0 };
  m = text.match(/all heroes with (\w+) weapons get \+(\d+)/);
  if (m) return playerCard?.element === m[1].toUpperCase() ? { playerDelta: parseInt(m[2]) || 10, cpuDelta: 0 } : { playerDelta: 0, cpuDelta: 0 };
  m = text.match(/opponent's hero has (?:a |an )?(\w+) weapon.*?-(\d+)/);
  if (m) return cpuCard?.element === m[1].toUpperCase() ? { playerDelta: 0, cpuDelta: -(parseInt(m[2]) || 15) } : { playerDelta: 0, cpuDelta: 0 };

  // Weapon type matching
  if (text.includes('different weapon type') && text.includes('opponent')) {
    const same = playerCard?.element === cpuCard?.element;
    m = text.match(/\+(\d+)/);
    if (m) { const b = parseInt(m[1]) || 10; return same ? { playerDelta: 0, cpuDelta: 0 } : { playerDelta: b, cpuDelta: 0 }; }
  }

  // Defensive / protection
  if (text.includes("can't drop below") || text.includes("can't lose any more power")) {
    const wm = text.match(/(\w+) weapon/);
    if (wm && playerCard?.element === wm[1].toUpperCase()) return { playerDelta: 15, cpuDelta: 0 };
    return { playerDelta: 0, cpuDelta: 0 };
  }
  if (text.includes("can't have its power reduced") || text.includes("can't be affected")) return { playerDelta: 10, cpuDelta: 0 };

  // Conditional bonuses
  if (text.includes('if this battle is tied')) { m = text.match(/\+(\d+)/); if (m) return { playerDelta: parseInt(m[1]) || 1, cpuDelta: 0 }; }
  if (text.includes('lost the previous') || text.includes('lost the first') || text.includes('lost the 2 previous')) { m = text.match(/\+(\d+)/); if (m) return { playerDelta: parseInt(m[1]) || 15, cpuDelta: 0 }; }
  if (text.includes('won the first battle') || text.includes('won the last battle') || text.includes('won 2 battles') || text.includes('won at least')) { m = text.match(/\+(\d+)/); if (m) return { playerDelta: parseInt(m[1]) || 10, cpuDelta: 0 }; }
  if (text.includes('if you substituted this battle')) { m = text.match(/\+(\d+)/); if (m) return { playerDelta: parseInt(m[1]) || 10, cpuDelta: 0 }; }

  // Hot dog conditional
  if (text.includes('hot dog') && text.includes('left')) { m = text.match(/\+(\d+)/); if (m) return { playerDelta: parseInt(m[1]) || 10, cpuDelta: 0 }; }

  // Draw effects with power component
  if (text.includes('draw') && text.includes('play')) {
    m = text.match(/\+(\d+)/);
    if (m && (text.includes('your hero gets') || text.includes('hero gains'))) return { playerDelta: parseInt(m[1]) || 0, cpuDelta: 0 };
    return { playerDelta: 0, cpuDelta: 0 };
  }

  // Discard-based power
  if (text.includes('discard')) {
    m = text.match(/opponent's hero gets -(\d+)/);
    if (m) return { playerDelta: 0, cpuDelta: -(parseInt(m[1]) || 20) };
    m = text.match(/\+(\d+).*every card discarded/);
    if (m) return { playerDelta: (parseInt(m[1]) || 5) * 3, cpuDelta: 0 };
    m = text.match(/your hero gets \+(\d+)/);
    if (m) return { playerDelta: parseInt(m[1]) || 10, cpuDelta: 0 };
    return { playerDelta: 0, cpuDelta: 0 };
  }

  // For the rest of the game
  if (text.includes('for the rest of the game')) {
    m = text.match(/\+(\d+)/);
    if (m) return { playerDelta: parseInt(m[1]) || 5, cpuDelta: 0 };
    m = text.match(/-(\d+)/);
    if (m) return { playerDelta: 0, cpuDelta: -(parseInt(m[1]) || 5) };
    return { playerDelta: 5, cpuDelta: 0 };
  }

  // Hot dog economy (no power change)
  if (text.includes('recover') && text.includes('hot dog')) return { playerDelta: 0, cpuDelta: 0 };
  if (text.includes('hot dog')) return { playerDelta: 0, cpuDelta: 0 };
  if (text.includes('honors')) return { playerDelta: 0, cpuDelta: 0 };
  if (text.includes('look at') || text.includes('reveal the top')) return { playerDelta: 0, cpuDelta: 0 };

  // Last resort: find any +N or -N
  m = text.match(/\+(\d+)/);
  if (m) return { playerDelta: parseInt(m[1]) || 0, cpuDelta: 0 };
  m = text.match(/-(\d+)/);
  if (m) return text.includes('opponent') ? { playerDelta: 0, cpuDelta: -(parseInt(m[1]) || 0) } : { playerDelta: -(parseInt(m[1]) || 0), cpuDelta: 0 };

  return pmFallbackEffect(card.playCost || 0);
}

function pmFallbackEffect(cost) { return { playerDelta: cost * 6 + 5, cpuDelta: 0 }; }

function pmResolveCoinFlip(text, playerCard) {
  let flipCount = 1;
  const fcm = text.match(/flip a coin (\d+) times/);
  if (fcm) flipCount = parseInt(fcm[1]) || 1;
  let pd = 0, cd = 0;
  for (let i = 0; i < flipCount; i++) {
    const heads = Math.random() < 0.5;
    if (heads) {
      let m = text.match(/heads.*?\+(\d+)/); if (m) pd += parseInt(m[1]) || 0;
      m = text.match(/heads.*?opponent.*?-(\d+)/); if (m) cd -= parseInt(m[1]) || 0;
      if (pd === 0 && cd === 0) { m = text.match(/heads.*?hero gets \+(\d+)/); if (m) pd += parseInt(m[1]) || 0; }
    } else {
      let m = text.match(/tails.*?\+(\d+)/); if (m) pd += parseInt(m[1]) || 0;
      m = text.match(/tails.*?opponent.*?-(\d+)/); if (m) cd -= parseInt(m[1]) || 0;
      m = text.match(/tails.*?(?:your hero|hero) (?:gets|loses) -(\d+)/); if (m) pd -= parseInt(m[1]) || 0;
    }
  }
  if (text.includes('power is doubled') && flipCount > 0) {
    const allHeads = Array.from({length: flipCount}, () => Math.random() < 0.5).every(Boolean);
    return allHeads ? { playerDelta: playerCard?.power || 0, cpuDelta: 0 } : { playerDelta: 0, cpuDelta: 0 };
  }
  if (pd === 0 && cd === 0) return Math.random() < 0.5 ? { playerDelta: 10, cpuDelta: 0 } : { playerDelta: 0, cpuDelta: 0 };
  return { playerDelta: pd, cpuDelta: cd };
}

function pmResolveDiceRoll(text, playerCard, cpuCard) {
  const roll = Math.floor(Math.random() * 6) + 1;
  if (text.includes('+5x the number') || text.includes('+5x') || text.includes('5x the number')) return { playerDelta: 5 * roll, cpuDelta: 0 };
  if (text.includes('-5x the number') || (text.includes('opponent') && text.includes('5x'))) return { playerDelta: 0, cpuDelta: -5 * roll };
  if (text.includes('two times') && text.includes('add up to 7')) { const r2 = Math.floor(Math.random() * 6) + 1; return (roll + r2 === 7) ? { playerDelta: 100, cpuDelta: 0 } : { playerDelta: 0, cpuDelta: 0 }; }
  if (text.includes('drops to 0') || text.includes('goes to 0')) {
    let m = text.match(/\+(\d+)/); const bonus = m ? parseInt(m[1]) || 25 : 25;
    if (text.includes('1 or 6')) return (roll === 1 || roll === 6) ? { playerDelta: -(playerCard?.power || 999), cpuDelta: 0 } : { playerDelta: bonus, cpuDelta: 0 };
    if (text.includes('lands on a 1') || text.includes('lands on 1')) return roll === 1 ? { playerDelta: -(playerCard?.power || 999), cpuDelta: 0 } : { playerDelta: bonus, cpuDelta: 0 };
  }
  let m = text.match(/lands on (\d+) or (\d+).*?\+(\d+)/);
  if (m) {
    if (roll === parseInt(m[1]) || roll === parseInt(m[2])) return { playerDelta: parseInt(m[3]) || 40, cpuDelta: 0 };
    const fb = text.match(/if not.*?\+(\d+)/);
    return { playerDelta: fb ? parseInt(fb[1]) || 5 : 5, cpuDelta: 0 };
  }
  if (text.includes('3-6') || text.includes('4-6')) {
    m = text.match(/\+(\d+)/); const bonus = m ? parseInt(m[1]) || 25 : 25;
    const threshold = text.includes('4-6') ? 4 : 3;
    if (roll >= threshold) return { playerDelta: bonus, cpuDelta: 0 };
    m = text.match(/-(\d+)/); return m ? { playerDelta: -(parseInt(m[1]) || 0), cpuDelta: 0 } : { playerDelta: 0, cpuDelta: 0 };
  }
  if (text.includes('5 or 6')) { m = text.match(/\+(\d+)/); return roll >= 5 ? { playerDelta: parseInt(m?.[1]) || 50, cpuDelta: 0 } : { playerDelta: 0, cpuDelta: 0 }; }
  if (text.includes('3 times') && text.includes('roll a 6')) { const rolls = [1,2,3].map(() => Math.floor(Math.random()*6)+1); return rolls.includes(6) ? { playerDelta: 30, cpuDelta: 0 } : { playerDelta: 0, cpuDelta: 0 }; }
  if (text.includes('roll again')) {
    let total = 0, r = roll;
    while (r >= 4) { m = text.match(/-(\d+)/); total -= m ? parseInt(m[1]) || 15 : 15; r = Math.floor(Math.random()*6)+1; }
    return { playerDelta: 0, cpuDelta: total };
  }
  if (text.includes('swap current power') && roll === 6) {
    const myP = playerCard?.power || 0, thP = cpuCard?.power || 0;
    return { playerDelta: thP - myP, cpuDelta: myP - thP };
  }
  if (text.includes('both players roll')) {
    const cpuRoll = Math.floor(Math.random()*6)+1;
    m = text.match(/\+(\d+)/); const bonus = m ? parseInt(m[1]) || 25 : 25;
    if (roll > cpuRoll) return { playerDelta: bonus, cpuDelta: 0 };
    return { playerDelta: 0, cpuDelta: 0 };
  }
  m = text.match(/\+(\d+)/);
  if (m) return { playerDelta: parseInt(m[1]) || 10, cpuDelta: 0 };
  return { playerDelta: 10, cpuDelta: 0 };
}

function pmEffectDescription(card) {
  const ability = card.playAbility || '';
  if (!ability) return `+${(card.playCost || 0) * 6 + 5} Power`;
  return ability;
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
  playerPlayHand: [],        // current play cards in hand (4 starting, draw 1/battle)
  playerPlayDeck: [],        // remaining plays
  playerDiscard: [],         // discarded plays
  playerHeroDeckCount: 0,   // remaining heroes (for display)
  playerSubstituted: false,
  playerPassedPlays: false,

  // CPU resources
  cpuHD: 10,
  cpuBench: [],
  cpuPlayCount: 30,
  cpuPlayPool: [],             // actual play cards for CPU
  cpuSubstituted: false,
  cpuPassedPlays: false,

  selectedBenchIdx: null,    // which bench card is tapped for sub
  allCards: [],
  _initialized: false,       // event listeners attached once

  startMatch(allCards) {
    this.allCards = allCards;
    Object.assign(this, {
      matchOver: false, matchWinner: null, playerScore: 0, cpuScore: 0,
      honors: 'player', currentBattle: 0,
      // Per rules: Sub phase comes BEFORE reveal for non-rookie modes
      phase: this.mode === 'rookie' ? 'reveal' : 'sub',
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

    // 7 battle slots per side + 4 bench cards per side = 11 each (per rules §4.2.1, §4.3.1)
    const playerCards = heroPool.slice(0, 11);
    const cpuCards    = heroPool.slice(11, 22);

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

    // Bench = remaining 4 hero cards (indices 7-10, per rules §4.2.1)
    this.playerBench = [...playerCards.slice(7)];
    this.cpuBench    = [...cpuCards.slice(7)];

    // Build play hand from play cards
    const plays = allCards.filter(c => c.cardType === 'Play');
    const shuffledPlays = shuffle([...plays]);
    this.playerPlayHand = shuffledPlays.slice(0, 4); // 4 starting hand per rules §4.3.1
    this.playerPlayDeck = shuffledPlays.slice(4, 30); // 30-card playbook: 4 in hand + 26 in deck
    this.playerDiscard  = [];
    this.playerHeroDeckCount = 49; // 60-card hero deck minus 11 dealt (7 battles + 4 bench)

    // CPU gets its own 30-card play pool (separate shuffle)
    const cpuPlays = shuffle([...plays]);
    this.cpuPlayPool = cpuPlays.slice(0, 30);
    this.cpuPlayQueue = [];
  },

  advance() {
    if (this.matchOver) return;
    const b = this.battles[this.currentBattle];

    switch (this.phase) {
      case 'sub':
        // Per rules (§4.2.2, §4.3.2): Sub happens BEFORE reveal
        // CPU makes blind sub decision (can't see player's card)
        { const didSub = this.cpuDoSub();
          this.phase = 'reveal';
          // Show CPU sub callout after DOM update (deferred so pmUpdateAll runs first)
          if (didSub) setTimeout(() => pmShowCpuSubCallout(true), 50);
        }
        break;

      case 'reveal':
        if (!b.revealed) {
          // Step 1: flip cards face-up so player can see the matchup
          b.revealed = true;
          if (this.mode === 'rookie' || this.mode === 'substitution') {
            this.resolve();
          }
          // In playmaker, stay in reveal phase — user presses again to enter play
        } else {
          // Step 2: cards already revealed, enter play phase
          this.phase = 'play';
          this.playerPassedPlays = false;
          this.cpuPassedPlays = false;
          // CPU plays AFTER reveal, not simultaneously
          this.cpuDoPlay();
          // Show CPU plays as overlay after DOM update
          if (this.cpuPlayQueue.length > 0) {
            setTimeout(() => pmShowCpuPlayQueue(), 50);
          }
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
    // Per rules: original hero goes to discard, not back to bench
    this.battles[this.currentBattle].playerCard = benchCard;
    this.playerBench.splice(benchIdx, 1); // remove from bench
    this.playerHD -= 2;
    // Draw a new hero from hero deck to refill bench (per rules §Glossary "Substitute")
    if (this.playerHeroDeckCount > 0) {
      // In practice mode we don't have full hero deck objects for CPU;
      // for player, add a placeholder draw from remaining pool
      this.playerHeroDeckCount--;
    }
    this.playerSubstituted = true;
    this.selectedBenchIdx = null;
    // Auto-advance to reveal phase after substituting (matches iOS)
    this.advance();
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
      // Use full effects engine instead of simple formula
      const effect = pmResolveEffect(card, b.playerCard, b.cpuCard);
      b.playerEffectPower = (b.playerEffectPower || 0) + (effect.playerDelta || 0);
      b.cpuEffectPower = (b.cpuEffectPower || 0) + (effect.cpuDelta || 0);
    }
    if (b) b.playerPlaysPlayed.push(card);
    this.playerPlayHand.splice(handIdx, 1);
    this.playerDiscard.push(card);
    return true;
  },

  cpuDoSub() {
    if (this.cpuSubstituted || this.cpuBench.length === 0 || this.cpuHD < 2) {
      this.cpuSubstituted = true; return false;
    }
    const b = this.battles[this.currentBattle];
    const cpuPow = (b.cpuCard?.power || 0);

    // Find best bench card
    const bestIdx = this.cpuBench.reduce((bi, c, i) =>
      (c?.power || 0) > (this.cpuBench[bi]?.power || 0) ? i : bi, 0);
    const bestCard = this.cpuBench[bestIdx];
    const bestPow  = bestCard?.power || 0;

    // Per rules (§4.2.2): Subs happen BEFORE reveal — CPU can't see player's card.
    // Blind decision: sub if current hero is weak (<120) and bench is better,
    // or bench has a 30+ power upgrade
    const weakHero = cpuPow < 120 && bestPow > cpuPow;
    const opportunisticSub = bestPow - cpuPow >= 30;

    if (weakHero || opportunisticSub) {
      // Per rules: original hero goes to discard, bench card replaces it
      this.battles[this.currentBattle].cpuCard = bestCard;
      this.cpuBench.splice(bestIdx, 1); // remove from bench (original hero discarded)
      this.cpuHD -= 2;
      this.cpuSubstituted = true;
      return true;
    }
    this.cpuSubstituted = true;
    return false;
  },

  // CPU play cards queue — filled by cpuDoPlay, shown as overlay one by one
  cpuPlayQueue: [],

  cpuDoPlay() {
    if (this.cpuPassedPlays) return;
    const b = this.battles[this.currentBattle];
    this.cpuPlayQueue = [];

    // CPU plays 0-2 cards based on situation
    const losing = (b.cpuCard?.power || 0) + (b.cpuEffectPower || 0) < (b.playerCard?.power || 0) + (b.playerEffectPower || 0);
    const numPlays = losing ? (Math.random() < 0.6 ? 2 : 1) : (Math.random() < 0.4 ? 1 : 0);

    for (let i = 0; i < numPlays; i++) {
      if (this.cpuHD < 1 || this.cpuPlayCount <= 0 || this.cpuPlayPool.length === 0) break;
      // Pick an affordable card from CPU's play pool
      const affordable = this.cpuPlayPool.filter(c => (c.playCost || 0) <= this.cpuHD);
      if (affordable.length === 0) break;
      const card = affordable[Math.floor(Math.random() * affordable.length)];
      const cost = card.playCost || 0;

      this.cpuHD -= cost;
      this.cpuPlayCount--;
      // Remove from pool
      const poolIdx = this.cpuPlayPool.indexOf(card);
      if (poolIdx >= 0) this.cpuPlayPool.splice(poolIdx, 1);

      // Apply effect
      const hdRecovery = pmDetectHDRecovery(card);
      if (hdRecovery > 0) {
        this.cpuHD = Math.min(10, this.cpuHD + hdRecovery);
        this.cpuPlayQueue.push({ card, cost, effect: { playerDelta: 0, cpuDelta: 0 }, hdRecovery });
      } else {
        // For CPU, swap perspective: CPU is the "player" from the resolver's POV
        const effect = pmResolveEffect(card, b.cpuCard, b.playerCard);
        b.cpuEffectPower = (b.cpuEffectPower || 0) + (effect.playerDelta || 0);
        b.playerEffectPower = (b.playerEffectPower || 0) + (effect.cpuDelta || 0);
        this.cpuPlayQueue.push({ card, cost, effect });
      }
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
      // Tie — SUPER weapon wins ONLY in Playmaker mode (§4.3.2 Super Tie Breaker)
      // Rookie/Substitution: tied power = draw, no trophy (§4.1.2, §4.2.2)
      if (this.mode === 'playmaker') {
        const pSuper = b.playerCard?.element === 'SUPER';
        const cSuper = b.cpuCard?.element    === 'SUPER';
        if (pSuper && !cSuper) {
          b.result = 'win';  this.playerScore++; this.honors = 'player';
        } else if (cSuper && !pSuper) {
          b.result = 'lose'; this.cpuScore++;    this.honors = 'cpu';
        } else {
          b.result = 'tie';
        }
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
    // Per rules: Sub phase comes before reveal for non-rookie
    this.phase = this.mode === 'rookie' ? 'reveal' : 'sub';
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
  const hdIcon  = `<svg class="pm-icon" style="color:#4CAF50"><use href="#icon-hotdog"/></svg>`;

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
        <svg class="pm-icon" viewBox="0 0 24 24" fill="none" stroke="rgba(192,57,43,0.9)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <polyline points="14.5 17.5 3 6 3 3 6 3 17.5 14.5"/>
          <line x1="13" x2="19" y1="19" y2="13"/>
          <line x1="16" x2="20" y1="16" y2="20"/>
          <line x1="19" x2="21" y1="21" y2="19"/>
          <polyline points="14.5 6.5 18 3 21 3 21 6 17.5 9.5"/>
          <line x1="5" x2="9" y1="14" y2="18"/>
          <line x1="7" x2="4" y1="17" y2="20"/>
          <line x1="3" x2="5" y1="19" y2="21"/>
        </svg>
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

  <!-- CPU play overlay — shows CPU plays one by one -->
  <div class="pm-cpu-overlay" id="pm-cpu-overlay" hidden>
    <div class="pm-cpu-overlay-inner">
      <div class="pm-cpu-overlay-label">CPU PLAYS</div>
      <div class="pm-cpu-overlay-card" id="pm-cpu-overlay-card"></div>
      <button class="pm-cpu-overlay-dismiss" id="pm-cpu-overlay-dismiss">OK</button>
    </div>
  </div>

  <!-- CPU sub callout -->
  <div class="pm-cpu-sub-callout" id="pm-cpu-sub-callout" hidden>
    <div class="pm-cpu-sub-inner">
      <span class="pm-cpu-sub-icon">⚡</span>
      <span class="pm-cpu-sub-text">CPU SUBSTITUTED</span>
    </div>
  </div>

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
    sub: 'SUBSTITUTION', reveal: 'REVEAL', play: 'PLAY WINDOW',
    resolution: 'RESOLUTION', cleanup: 'CLEANUP', over: 'MATCH OVER',
  };
  // Dynamic button labels — reveal has two states like iOS
  const b = PM.battles[PM.currentBattle];
  const revealLabel = (b && b.revealed) ? 'PLAY PHASE →' : 'REVEAL →';
  const btnLabels = {
    sub: 'SKIP SUBS →', reveal: revealLabel, play: 'END TURN →',
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
      setTimeout(() => banner.classList.remove('visible'), 2000);
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
    // Card back: double-border design (classic TCG pattern, no crossing lines)
    slot.innerHTML = `<svg width="22" height="30" viewBox="0 0 20 28" fill="none" aria-hidden="true">
      <rect x="1" y="1" width="18" height="26" rx="3" fill="rgba(192,57,43,0.12)" stroke="rgba(192,57,43,0.5)" stroke-width="1.5"/>
      <rect x="3.5" y="3.5" width="13" height="21" rx="1.5" stroke="rgba(192,57,43,0.28)" stroke-width="0.9"/>
      <circle cx="10" cy="14" r="3.5" stroke="rgba(192,57,43,0.25)" stroke-width="0.9"/>
    </svg>`;
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
  // Auto-save match state
  if (!PM.matchOver) pmSaveMatch();
  else pmClearSavedMatch();
}

// ── Init (event listeners attached once per session) ────────────

function pmExitPlaymat() {
  const view  = $('view-practice');
  const setup = $('practice-setup');
  const mat   = $('practice-playmat');
  if (view)  view.classList.remove('playmat-mode');
  if (setup) setup.hidden = false;
  if (mat)   mat.hidden = true;
  // Update resume button visibility
  const resumeBtn = $('btn-resume-practice');
  if (resumeBtn) resumeBtn.hidden = !pmLoadMatch();
}

// Show a popup for a play card so the user can read the effect before deciding to play
function pmShowPlayCardPopup(handIdx) {
  const card = PM.playerPlayHand[handIdx];
  if (!card) return;

  // Remove any existing popup
  document.getElementById('pm-play-popup')?.remove();

  const cost       = card.playCost || 0;
  const canAfford  = PM.playerHD >= cost;
  const imgUrl     = card.imageFile ? fullUrl(card.imageFile) : null;
  const ability    = card.playAbility || card.description || '—';
  const costLabel  = cost === 0 ? 'FREE' : `${cost} Hot Dog${cost !== 1 ? 's' : ''}`;
  const affordClass = canAfford ? 'pm-play-popup-play' : 'pm-play-popup-play cannot-afford';
  const element    = card.element || '';

  const popup = document.createElement('div');
  popup.id = 'pm-play-popup';
  popup.className = 'pm-play-popup';
  popup.innerHTML = `
    <div class="pm-play-popup-inner">
      ${imgUrl ? `<div class="pm-play-popup-img-wrap"><img class="pm-play-popup-img" src="${imgUrl}" alt="${card.name||''}" onerror="this.parentElement.style.display='none'"></div>` : ''}
      <div class="pm-play-popup-body">
        <div class="pm-play-popup-header">
          <div class="pm-play-popup-name">${card.name || ''}</div>
          ${element ? `<div class="pm-play-popup-element" data-element="${element}">${element}</div>` : ''}
        </div>
        <div class="pm-play-popup-cost-row">
          <span class="pm-play-popup-cost-pill${!canAfford ? ' cannot-afford' : ''}">${costLabel}</span>
          ${!canAfford ? `<span class="pm-play-popup-afford-warn">Not enough Hot Dogs</span>` : ''}
        </div>
        <div class="pm-play-popup-divider"></div>
        <div class="pm-play-popup-effect-label">EFFECT</div>
        <div class="pm-play-popup-effect">${ability}</div>
        <div class="pm-play-popup-actions">
          <button class="pm-play-popup-cancel">Cancel</button>
          <button class="${affordClass}"${!canAfford ? ' disabled' : ''}>
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

// ── Match persistence (localStorage) ────────────────────────────
const PM_SAVE_KEY = 'boba_practice_match';

function pmSaveMatch() {
  try {
    const snap = {
      mode: PM.mode, phase: PM.phase, currentBattle: PM.currentBattle,
      playerScore: PM.playerScore, cpuScore: PM.cpuScore, honors: PM.honors,
      matchOver: PM.matchOver, matchWinner: PM.matchWinner,
      playerHD: PM.playerHD, cpuHD: PM.cpuHD, cpuPlayCount: PM.cpuPlayCount,
      playerSubstituted: PM.playerSubstituted, cpuSubstituted: PM.cpuSubstituted,
      playerPassedPlays: PM.playerPassedPlays, cpuPassedPlays: PM.cpuPassedPlays,
      playerHeroDeckCount: PM.playerHeroDeckCount,
      // Serialize card arrays by bobaId for compact storage
      battles: PM.battles.map(b => ({
        id: b.id, result: b.result, revealed: b.revealed,
        playerEffectPower: b.playerEffectPower, cpuEffectPower: b.cpuEffectPower,
        playerCardId: b.playerCard?.bobaId || null,
        cpuCardId: b.cpuCard?.bobaId || null,
        playerPlaysPlayed: (b.playerPlaysPlayed || []).map(c => c.bobaId || c.name),
      })),
      playerBenchIds: PM.playerBench.map(c => c?.bobaId),
      cpuBenchIds: PM.cpuBench.map(c => c?.bobaId),
      playerPlayHandIds: PM.playerPlayHand.map(c => c?.bobaId),
      playerPlayDeckIds: PM.playerPlayDeck.map(c => c?.bobaId),
      playerDiscardIds: PM.playerDiscard.map(c => c?.bobaId),
      cpuPlayPoolIds: PM.cpuPlayPool.map(c => c?.bobaId),
      savedAt: Date.now(),
    };
    localStorage.setItem(PM_SAVE_KEY, JSON.stringify(snap));
  } catch (e) { /* ignore storage errors */ }
}

function pmLoadMatch() {
  try {
    const raw = localStorage.getItem(PM_SAVE_KEY);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch (e) { return null; }
}

function pmClearSavedMatch() {
  localStorage.removeItem(PM_SAVE_KEY);
}

function pmRestoreMatch(snap, allCards) {
  if (!snap || !allCards || !allCards.length) return false;
  // Build lookup by bobaId
  const byId = {};
  allCards.forEach(c => { if (c.bobaId) byId[c.bobaId] = c; });
  const findCard = id => id ? (byId[id] || null) : null;

  PM.allCards = allCards;
  PM.mode = snap.mode || 'playmaker';
  PM.phase = snap.phase || 'reveal';
  PM.currentBattle = snap.currentBattle || 0;
  PM.playerScore = snap.playerScore || 0;
  PM.cpuScore = snap.cpuScore || 0;
  PM.honors = snap.honors || 'player';
  PM.matchOver = snap.matchOver || false;
  PM.matchWinner = snap.matchWinner || null;
  PM.playerHD = snap.playerHD ?? 10;
  PM.cpuHD = snap.cpuHD ?? 10;
  PM.cpuPlayCount = snap.cpuPlayCount ?? 30;
  PM.playerSubstituted = snap.playerSubstituted || false;
  PM.cpuSubstituted = snap.cpuSubstituted || false;
  PM.playerPassedPlays = snap.playerPassedPlays || false;
  PM.cpuPassedPlays = snap.cpuPassedPlays || false;
  PM.playerHeroDeckCount = snap.playerHeroDeckCount || 0;
  PM.selectedBenchIdx = null;
  PM.cpuPlayQueue = [];

  PM.battles = (snap.battles || []).map(sb => ({
    id: sb.id, result: sb.result, revealed: sb.revealed,
    playerEffectPower: sb.playerEffectPower || 0,
    cpuEffectPower: sb.cpuEffectPower || 0,
    playerCard: findCard(sb.playerCardId),
    cpuCard: findCard(sb.cpuCardId),
    playerPlaysPlayed: (sb.playerPlaysPlayed || []).map(id => findCard(id)).filter(Boolean),
  }));

  PM.playerBench = (snap.playerBenchIds || []).map(findCard).filter(Boolean);
  PM.cpuBench = (snap.cpuBenchIds || []).map(findCard).filter(Boolean);
  PM.playerPlayHand = (snap.playerPlayHandIds || []).map(findCard).filter(Boolean);
  PM.playerPlayDeck = (snap.playerPlayDeckIds || []).map(findCard).filter(Boolean);
  PM.playerDiscard = (snap.playerDiscardIds || []).map(findCard).filter(Boolean);
  PM.cpuPlayPool = (snap.cpuPlayPoolIds || []).map(findCard).filter(Boolean);

  return true;
}

// Show CPU play cards one by one as dismissible overlays
function pmShowCpuPlayQueue() {
  if (!PM.cpuPlayQueue || PM.cpuPlayQueue.length === 0) return;
  const overlay = $('pm-cpu-overlay');
  if (!overlay) return;

  let queueIdx = 0;

  function showNext() {
    if (queueIdx >= PM.cpuPlayQueue.length) {
      overlay.hidden = true;
      pmUpdateAll();
      return;
    }
    const entry = PM.cpuPlayQueue[queueIdx];
    const card = entry.card;
    const cost = entry.cost;
    const effect = entry.effect;
    const imgUrl = card.imageFile ? fullUrl(card.imageFile) : null;
    const ability = card.playAbility || '';
    const costLabel = cost === 0 ? 'FREE' : `${cost} HD`;

    let deltasHtml = '';
    if (effect.playerDelta > 0) deltasHtml += `<span class="pm-cpu-card-delta-opp">CPU +${effect.playerDelta}</span>`;
    if (effect.playerDelta < 0) deltasHtml += `<span class="pm-cpu-card-delta-opp">CPU ${effect.playerDelta}</span>`;
    if (effect.cpuDelta < 0) deltasHtml += `<span class="pm-cpu-card-delta-you">YOU ${effect.cpuDelta}</span>`;
    if (effect.cpuDelta > 0) deltasHtml += `<span class="pm-cpu-card-delta-you">YOU +${effect.cpuDelta}</span>`;
    if (entry.hdRecovery > 0) deltasHtml += `<span class="pm-cpu-card-delta-opp">CPU +${entry.hdRecovery} HD</span>`;

    const cardEl = $('pm-cpu-overlay-card');
    if (cardEl) {
      cardEl.innerHTML = `
        ${imgUrl ? `<img class="pm-cpu-card-img" src="${imgUrl}" alt="${card.name||''}" onerror="this.style.display='none'">` : ''}
        <div class="pm-cpu-card-name">${card.name || 'Play Card'}</div>
        <div class="pm-cpu-card-cost">${costLabel}</div>
        ${ability ? `<div class="pm-cpu-card-effect">${ability}</div>` : ''}
        <div class="pm-cpu-card-deltas">${deltasHtml}</div>`;
    }

    overlay.hidden = false;
    queueIdx++;
  }

  const dismissBtn = $('pm-cpu-overlay-dismiss');
  // Remove old listener by replacing node
  if (dismissBtn) {
    const newBtn = dismissBtn.cloneNode(true);
    dismissBtn.parentNode.replaceChild(newBtn, dismissBtn);
    newBtn.addEventListener('click', showNext);
  }

  showNext();
}

// Show CPU sub callout (auto-dismiss)
function pmShowCpuSubCallout(didSub) {
  if (!didSub) return;
  const callout = $('pm-cpu-sub-callout');
  if (!callout) return;
  callout.hidden = false;
  // Re-trigger animation
  callout.style.animation = 'none';
  callout.offsetHeight; // force reflow
  callout.style.animation = '';
  setTimeout(() => { callout.hidden = true; }, 2000);
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

  // Substitute button — confirmed sub (auto-advances via playerSub)
  $('pm-btn-sub')?.addEventListener('click', () => {
    if (PM.selectedBenchIdx === null) return;
    if (PM.playerSub(PM.selectedBenchIdx)) pmUpdateAll();
  });

  // CPU overlay dismiss (initial listener — gets replaced dynamically in pmShowCpuPlayQueue)
  $('pm-cpu-overlay-dismiss')?.addEventListener('click', () => {
    const overlay = $('pm-cpu-overlay');
    if (overlay) overlay.hidden = true;
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
  const view = $('view-practice');
  if (!view) return;

  // Show resume button if there's a saved match
  const saved = pmLoadMatch();
  const resumeBtn = $('btn-resume-practice');
  if (resumeBtn) resumeBtn.hidden = !saved;

  // Resume match
  resumeBtn?.addEventListener('click', () => {
    const snap = pmLoadMatch();
    if (!snap) return;

    const mat = $('practice-playmat');
    if (mat && !PM._initialized) {
      mat.innerHTML = pmBuildPlaymatHTML();
      if (typeof lucide !== 'undefined') lucide.createIcons({ nodes: [mat] });
    }

    if (!pmRestoreMatch(snap, allCards)) return;

    const setup = $('practice-setup');
    if (setup) setup.hidden = true;
    if (mat)   mat.hidden = false;
    view.classList.add('playmat-mode');

    pmInitPlaymat();
    pmUpdateAll();
  });

  // Mode radio
  view.querySelectorAll('input[name="practice-mode"]').forEach(radio => {
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
    const checked = view.querySelector('input[name="practice-mode"]:checked');
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
    if (setup) setup.hidden = true;
    if (mat)   mat.hidden = false;
    view.classList.add('playmat-mode');

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
