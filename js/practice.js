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

  // Card grid tap — add
  $('db-card-grid')?.addEventListener('click', e => {
    const cell = e.target.closest('.db-card-cell');
    if (!cell || cell.classList.contains('violates')) return;
    const bobaId = cell.dataset.bobaId;
    const card = allCards.find(c => c.bobaId === bobaId);
    if (!card) return;
    DB.addCard(card);
    dbRender(allCards);
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
      if (btn) { btn.textContent = 'Copied!'; setTimeout(() => { btn.textContent = 'Copy to Clipboard'; }, 2000); }
    });
  });
}

// ════════════════════════════════════════════════════════════════
// § Practice Battle
// ════════════════════════════════════════════════════════════════

const PM = {
  mode: 'playmaker',
  playerDeck: 'random',
  battles: [],
  currentBattle: 0,
  phase: 'reveal',          // reveal | sub | play | resolution | cleanup | over
  playerScore: 0,
  cpuScore: 0,
  playerHD: 10,
  cpuHD: 10,
  cpuPlays: 30,
  playerSubstituted: false,
  cpuSubstituted: false,
  playerPassedPlays: false,
  cpuPassedPlays: false,
  matchOver: false,
  matchWinner: null,        // 'player' | 'cpu' | null (tie)
  allCards: [],

  get slot() { return this.battles[this.currentBattle] || null; },

  startMatch(allCards) {
    this.allCards = allCards;
    this.matchOver = false;
    this.matchWinner = null;
    this.playerScore = 0;
    this.cpuScore = 0;
    this.playerHD = 10;
    this.cpuHD = 10;
    this.cpuPlays = 30;
    this.currentBattle = 0;
    this.phase = 'reveal';

    const heroes = allCards.filter(c => c.cardType === 'Hero' && (c.power || 0) > 0);
    // Prioritize cards that have images for a better visual experience
    const heroesWithImg = heroes.filter(c => c.imageFile);
    const heroesNoImg   = heroes.filter(c => !c.imageFile);
    const playerPool = [...shuffle([...heroesWithImg]), ...shuffle([...heroesNoImg])];
    const cpuPool    = [...shuffle([...heroesWithImg]), ...shuffle([...heroesNoImg])];
    const playerHeroes = playerPool.slice(0, 7);
    const cpuHeroes    = cpuPool.slice(0, 7);

    this.battles = [];
    for (let i = 0; i < 7; i++) {
      this.battles.push({
        id: i,
        playerCard: playerHeroes[i] || null,
        cpuCard: cpuHeroes[i] || null,
        playerPlays: [],
        cpuPlays: [],
        result: null,
        revealed: false,
      });
    }
    this.battles[0].active = true;
  },

  advance() {
    if (this.matchOver) return;
    switch (this.phase) {
      case 'reveal':
        this.battles[this.currentBattle].revealed = true;
        if (this.mode === 'rookie') {
          this.resolve();
        } else {
          this.phase = 'sub';
          this.playerSubstituted = false;
          this.cpuSubstituted = false;
          this.cpuSub();
        }
        break;
      case 'sub':
        if (this.mode === 'playmaker') {
          this.phase = 'play';
          this.playerPassedPlays = false;
          this.cpuPassedPlays = false;
        } else {
          this.resolve();
        }
        break;
      case 'play':
        this.resolve();
        break;
      case 'resolution':
        this.phase = 'cleanup';
        break;
      case 'cleanup':
        this.nextBattle();
        break;
    }
  },

  cpuSub() {
    if (this.mode === 'rookie' || this.cpuSubstituted) return;
    this.cpuSubstituted = true;
    // Easy AI: 50% chance to "substitute" conceptually (no bench to swap in web version)
  },

  resolve() {
    const slot = this.battles[this.currentBattle];
    const pp = (slot.playerCard?.power || 0);
    const cp = (slot.cpuCard?.power || 0);
    if (pp > cp) { slot.result = 'win';  this.playerScore++; }
    else if (cp > pp) { slot.result = 'lose'; this.cpuScore++; }
    else {
      const playerSuper = slot.playerCard?.element === 'SUPER';
      const cpuSuper    = slot.cpuCard?.element === 'SUPER';
      if (playerSuper && !cpuSuper) { slot.result = 'win'; this.playerScore++; }
      else if (cpuSuper && !playerSuper) { slot.result = 'lose'; this.cpuScore++; }
      else { slot.result = 'tie'; }
    }
    this.phase = 'resolution';
    this.checkOver();
  },

  checkOver() {
    if (this.playerScore >= 4) { this.matchOver = true; this.matchWinner = 'player'; this.phase = 'over'; }
    else if (this.cpuScore >= 4) { this.matchOver = true; this.matchWinner = 'cpu'; this.phase = 'over'; }
  },

  nextBattle() {
    this.battles[this.currentBattle].active = false;
    const next = this.currentBattle + 1;
    if (next >= 7 || this.matchOver) {
      this.matchOver = true;
      if (this.playerScore > this.cpuScore) this.matchWinner = 'player';
      else if (this.cpuScore > this.playerScore) this.matchWinner = 'cpu';
      this.phase = 'over';
      return;
    }
    this.currentBattle = next;
    this.battles[this.currentBattle].active = true;
    this.playerSubstituted = false;
    this.cpuSubstituted = false;
    this.playerPassedPlays = false;
    this.cpuPassedPlays = false;
    this.phase = 'reveal';
  },
};

function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function pmPhaseLabel() {
  const map = { reveal: 'REVEAL', sub: 'SUBSTITUTION', play: 'PLAY WINDOW', resolution: 'RESOLUTION', cleanup: 'CLEANUP', over: 'MATCH OVER' };
  return map[PM.phase] || PM.phase.toUpperCase();
}

function pmNextLabel() {
  const map = { reveal: 'REVEAL', sub: 'DONE SUBS', play: 'DONE PLAYS', resolution: 'NEXT', cleanup: 'NEXT BATTLE', over: 'RESTART' };
  return map[PM.phase] || 'NEXT';
}

function pmRenderPlaymat() {
  const mat = $('practice-playmat');
  if (!mat) return;

  const slot = PM.slot;
  const battleCols = PM.battles.map((b, i) => {
    const pCard = b.playerCard;
    const cCard = b.cpuCard;
    const isActive = i === PM.currentBattle && !PM.matchOver;
    const isPending = b.result === null && !isActive;
    const vsLabel = b.result === 'win' ? 'WIN' : b.result === 'lose' ? 'LOSS' : b.result === 'tie' ? 'TIE' : 'VS';
    const vsClass = b.result === 'win' ? 'win' : b.result === 'lose' ? 'lose' : '';

    function heroSlotHtml(card, revealed, isOpp) {
      if (!card) return `<div class="pm-hero-slot${isOpp ? ' opp' : ''}"><span class="pm-hero-power">—</span></div>`;
      if (isOpp && !revealed) {
        return `<div class="pm-hero-slot opp" title="Facedown">
          <svg width="20" height="28" viewBox="0 0 20 28" fill="none" aria-hidden="true"><rect x="1" y="1" width="18" height="26" rx="3" stroke="rgba(192,57,43,0.5)" stroke-width="1.5"/><line x1="10" y1="4" x2="10" y2="18" stroke="rgba(192,57,43,0.4)" stroke-width="1.2"/><line x1="4" y1="11" x2="16" y2="11" stroke="rgba(192,57,43,0.4)" stroke-width="1.2"/></svg>
        </div>`;
      }
      const img = card.imageFile ? `<img class="pm-hero-img" src="${thumbUrl(card.imageFile)}" alt="${card.hero || card.name}" loading="lazy" onerror="this.style.display='none'">` : '';
      return `<div class="pm-hero-slot${isOpp ? ' opp' : ''}">
        ${img}
        <div class="pm-hero-name">${card.hero || card.name || ''}</div>
        <div class="pm-hero-power">${card.power || 0}</div>
      </div>`;
    }

    return `<div class="pm-battle-col${isActive ? ' active' : ''}${isPending ? ' pending' : ''}" data-battle="${i}">
      <div class="pm-battle-label">B${i + 1}</div>
      ${heroSlotHtml(cCard, b.revealed, true)}
      <div class="pm-vs-bar ${vsClass}">${vsLabel}</div>
      ${heroSlotHtml(pCard, true, false)}
    </div>`;
  }).join('');

  const matchOverHtml = PM.matchOver ? `
    <div class="pm-match-over">
      <div class="pm-result-title ${PM.matchWinner === 'player' ? 'win' : PM.matchWinner === 'cpu' ? 'lose' : 'tie'}">
        ${PM.matchWinner === 'player' ? 'VICTORY!' : PM.matchWinner === 'cpu' ? 'DEFEAT' : 'SUDDEN DEATH'}
      </div>
      <div class="pm-result-score">${PM.playerScore} — ${PM.cpuScore}</div>
      <div class="pm-result-btns">
        <button class="pm-result-btn" id="pm-restart">PLAY AGAIN</button>
        <button class="pm-result-btn secondary" id="pm-exit">EXIT</button>
      </div>
    </div>
  ` : '';

  const hdHtml = PM.mode !== 'rookie'
    ? `<span class="pm-hd-count">HD: ${PM.playerHD}/10</span>` : '';

  mat.innerHTML = `
    <div class="pm-topbar">
      <div class="pm-score">
        <span class="pm-score-player">${PM.playerScore}</span>
        <span style="color:rgba(255,255,255,0.3);font-size:1rem">—</span>
        <span class="pm-score-cpu">${PM.cpuScore}</span>
      </div>
      <div class="pm-phase">${pmPhaseLabel()}</div>
      <button class="pm-exit" id="pm-exit-btn" aria-label="Exit practice">&times;</button>
    </div>
    <div class="pm-battles" style="position:relative">${battleCols}${matchOverHtml}</div>
    <div class="pm-player-zone">
      ${hdHtml}
      <button class="pm-action-btn" id="pm-advance">${pmNextLabel()}</button>
    </div>
  `;

  mat.querySelector('#pm-advance')?.addEventListener('click', () => {
    PM.advance();
    pmRenderPlaymat();
  });
  mat.querySelector('#pm-exit-btn')?.addEventListener('click', () => {
    pmExitPlaymat();
  });
  mat.querySelector('#pm-restart')?.addEventListener('click', () => {
    PM.startMatch(PM.allCards);
    pmRenderPlaymat();
  });
  mat.querySelector('#pm-exit')?.addEventListener('click', () => {
    pmExitPlaymat();
  });
}

function pmExitPlaymat() {
  const setup = $('practice-setup');
  const mat = $('practice-playmat');
  if (setup) setup.hidden = false;
  if (mat) mat.hidden = true;
}

function initPractice(allCards) {
  const modal = $('practice-modal');
  if (!modal) return;

  $('btn-open-practice')?.addEventListener('click', () => {
    modal.hidden = false;
    const setup = $('practice-setup');
    const mat = $('practice-playmat');
    if (setup) setup.hidden = false;
    if (mat) mat.hidden = true;
  });
  $('btn-close-practice')?.addEventListener('click', () => { modal.hidden = true; });
  modal.addEventListener('click', e => { if (e.target === modal) modal.hidden = true; });

  // Mode selection
  modal.querySelectorAll('input[name="practice-mode"]').forEach(radio => {
    radio.addEventListener('change', e => { PM.mode = e.target.value; });
  });

  // Deck choice
  $('practice-player-deck')?.querySelectorAll('.practice-deck-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      $('practice-player-deck').querySelectorAll('.practice-deck-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      PM.playerDeck = btn.dataset.deck;
    });
  });

  // Start
  $('btn-start-practice')?.addEventListener('click', () => {
    const modeEl = modal.querySelector('input[name="practice-mode"]:checked');
    PM.mode = modeEl ? modeEl.value : 'playmaker';
    PM.startMatch(allCards);

    const setup = $('practice-setup');
    const mat = $('practice-playmat');
    if (setup) setup.hidden = true;
    if (mat) { mat.hidden = false; pmRenderPlaymat(); }
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
