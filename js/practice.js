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

  // Active preset (matches iOS DeckBuilderStore.activePresetID).
  // Null = building under raw format defaults without a named preset.
  activePresetID: null,

  // User-toggleable rules layered on top of the format's defaults.
  // Mirrors iOS DeckRuleOverrides. Any non-default value here drives the
  // "Custom Rule Set" indicator in the rules sheet.
  ruleOverrides: {
    perHeroNameLimit: null,      // null = unlimited (2026 PDF default). 6 = legacy rule.
    perPowerLimit: null,         // null defers to format.perPowerDefault. Blast uses 3.
    disablePerPowerLimit: false, // sandbox mode
    enforceDBS: null,            // null defers to format.enforcesDBS
    dbsBudgetOverride: null,     // null defers to format.dbsBudget
    bonusPlaysEnabled: true,
    htdPlaysEnabled: true,
  },

  // Format rules per the 2026 BoBA National Events DRAFT PDF. Each entry
  // declares the hero-deck shape + playbook/hotdog needs + DBS behaviour.
  // The `sealed` legacy entry is kept for back-compat with old saved decks.
  formats: {
    rookie:       { heroMin: 60, heroMax: 60, playsTarget: 30, needsHD: false, needsPlays: false, powerCap: null, absMaxPower: null, totalPowerCap: null, specPlusTiers: null, perPowerDefault: 6, bannedCardTypes: [], enforcesDBS: false, dbsBudget: 1000 },
    substitution: { heroMin: 60, heroMax: 60, playsTarget: 30, needsHD: true,  needsPlays: false, powerCap: null, absMaxPower: null, totalPowerCap: null, specPlusTiers: null, perPowerDefault: 6, bannedCardTypes: [], enforcesDBS: false, dbsBudget: 1000 },
    playmaker:    { heroMin: 60, heroMax: 60, playsTarget: 30, needsHD: true,  needsPlays: true,  powerCap: null, absMaxPower: null, totalPowerCap: null, specPlusTiers: null, perPowerDefault: 6, bannedCardTypes: [], enforcesDBS: true,  dbsBudget: 1000 },
    spec:         { heroMin: 60, heroMax: 60, playsTarget: 30, needsHD: true,  needsPlays: true,  powerCap: 160,  absMaxPower: null, totalPowerCap: null, specPlusTiers: null, perPowerDefault: 6, bannedCardTypes: [], enforcesDBS: true,  dbsBudget: 1000 },
    elite:        { heroMin: 60, heroMax: 60, playsTarget: 30, needsHD: true,  needsPlays: true,  powerCap: null, absMaxPower: null, totalPowerCap: 8250, specPlusTiers: null, perPowerDefault: 6, bannedCardTypes: ['Trainer'], enforcesDBS: true, dbsBudget: 1000 },
    specPlus:     { heroMin: 60, heroMax: 70, playsTarget: 30, needsHD: true,  needsPlays: true,  powerCap: 160,  absMaxPower: 200,
                    totalPowerCap: null,
                    specPlusTiers: { 165: 2, 170: 2, 175: 1, 180: 1, 185: 1, 190: 1, 195: 1, 200: 1 },
                    perPowerDefault: 6, bannedCardTypes: [], enforcesDBS: true,  dbsBudget: 1000 },
    sealed:       { heroMin: 40, heroMax: 40, playsTarget: 20, needsHD: true,  needsPlays: true,  powerCap: null, absMaxPower: null, totalPowerCap: null, specPlusTiers: null, perPowerDefault: 6, bannedCardTypes: [], enforcesDBS: false, dbsBudget: 1000 },
  },

  get currentFormat() { return this.formats[this.format]; },
  get allCards() { return this.heroes.concat(this.plays, this.bonusPlays, this.hotDogs); },

  // ── Effective rule getters (merge format defaults with user overrides) ──
  get effectivePerPowerLimit() {
    if (this.ruleOverrides.disablePerPowerLimit) return null;
    return this.ruleOverrides.perPowerLimit ?? this.currentFormat.perPowerDefault;
  },
  get effectiveEnforceDBS() {
    return this.ruleOverrides.enforceDBS ?? this.currentFormat.enforcesDBS;
  },
  get effectiveDBSBudget() {
    return this.ruleOverrides.dbsBudgetOverride ?? this.currentFormat.dbsBudget;
  },

  // ── DBS totals (Play + Bonus Play printings carry card.dbs + card.dbsTier) ──
  get totalDBS() {
    let t = 0;
    for (const c of this.plays)      t += (c.dbs || 0);
    for (const c of this.bonusPlays) t += (c.dbs || 0);
    return t;
  },

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
    const fmt = this.currentFormat;
    // Exact-variation uniqueness (the "one of" rule that survived 2026)
    if (this.heroes.some(c => c.bobaId === card.bobaId)) return true;
    // Banned types (Elite: Trainer)
    if (fmt.bannedCardTypes.includes(card.cardType)) return true;
    const pv = this.powerValueCounts();
    const power = card.power || 0;
    // Per-hero power cap (Spec: 160; SPEC+ if adding into the ≤160 base)
    if (fmt.powerCap && power > fmt.powerCap) {
      if (fmt.specPlusTiers) {
        // SPEC+ tiered overflow slots accept 165-200 with per-power limits.
        const limit = fmt.specPlusTiers[power];
        if (limit == null) return true;
        if ((pv[power] || 0) >= limit) return true;
      } else {
        return true;
      }
    }
    // Absolute ceiling (SPEC+: 200)
    if (fmt.absMaxPower && power > fmt.absMaxPower) return true;
    // Elite: check total-power budget would not be exceeded
    if (fmt.totalPowerCap) {
      const current = this.heroes.reduce((s, c) => s + (c.power || 0), 0);
      if (current + power > fmt.totalPowerCap) return true;
    }
    // Per-power limit (tiered powers already checked above for SPEC+)
    const tieredPowers = fmt.specPlusTiers ? Object.keys(fmt.specPlusTiers).map(Number) : [];
    const perPowerLimit = this.effectivePerPowerLimit;
    if (perPowerLimit != null && !tieredPowers.includes(power)) {
      if ((pv[power] || 0) >= perPowerLimit) return true;
    }
    // Optional 6-per-hero-name rule (retired by default; opt-in via ruleOverrides)
    if (this.ruleOverrides.perHeroNameLimit != null) {
      const nc = this.heroNameCounts();
      if ((nc[card.hero || card.name] || 0) >= this.ruleOverrides.perHeroNameLimit) return true;
    }
    // Hero max
    if (this.heroes.length >= fmt.heroMax) return true;
    return false;
  },

  // ── Preset application (mirrors iOS DeckBuilderStore.applyPreset) ──
  applyPreset(preset) {
    if (!preset) return;
    this.activePresetID = preset.id;
    this.format = preset.format || 'playmaker';
    const o = preset.overrides || {};
    this.ruleOverrides = {
      perHeroNameLimit:    o.perHeroNameLimit    ?? null,
      perPowerLimit:       o.perPowerLimit       ?? null,
      disablePerPowerLimit: o.disablePerPowerLimit ?? false,
      enforceDBS:          o.enforceDBS          ?? null,
      dbsBudgetOverride:   o.dbsBudget           ?? null,
      bonusPlaysEnabled:   o.bonusPlaysEnabled   ?? true,
      htdPlaysEnabled:     o.htdPlaysEnabled     ?? true,
    };
  },
  unlinkFromPreset() { this.activePresetID = null; },
  get activePreset() {
    if (!this.activePresetID || !RULE_PRESETS) return null;
    return [...RULE_PRESETS.presets, ...RULE_PRESETS.casualPresets]
             .find(p => p.id === this.activePresetID) || null;
  },
  get isCustomRuleSet() {
    const preset = this.activePreset;
    if (!preset) {
      // No preset attached — any non-default override means custom.
      const o = this.ruleOverrides;
      return o.perHeroNameLimit != null || o.perPowerLimit != null || o.disablePerPowerLimit
          || o.enforceDBS != null || o.dbsBudgetOverride != null
          || o.bonusPlaysEnabled === false || o.htdPlaysEnabled === false;
    }
    // Preset attached — diff current overrides against preset's baseline.
    const p = preset.overrides || {};
    const o = this.ruleOverrides;
    return (p.perHeroNameLimit ?? null)    !== o.perHeroNameLimit
        || (p.perPowerLimit ?? null)       !== o.perPowerLimit
        || (p.disablePerPowerLimit ?? false) !== o.disablePerPowerLimit
        || (p.enforceDBS ?? null)          !== o.enforceDBS
        || (p.dbsBudget ?? null)           !== o.dbsBudgetOverride
        || (p.bonusPlaysEnabled ?? true)   !== o.bonusPlaysEnabled
        || (p.htdPlaysEnabled ?? true)     !== o.htdPlaysEnabled;
  },

  /// Add a card to the active section. Returns a structured outcome
  /// the caller uses to surface feedback (tick 113 parity with iOS
  /// tick 112). `{ ok: true }` on success; `{ ok: false, reason: ... }`
  /// on silent-skip so the user sees WHY the add no-opped.
  addCard(card) {
    const tab = this.browserTab;
    if (tab === 'hero') {
      if (this.wouldHeroViolate(card)) {
        // Hero violation could be a duplicate, power-cap miss, or
        // format-specific bar. wouldHeroViolate is the source of
        // truth but doesn't disambiguate; "skipped" is honest.
        return { ok: false, reason: this.isInDeck(card) ? 'already in deck' : 'rule violation' };
      }
      this.heroes.push(card);
      return { ok: true };
    } else if (tab === 'play') {
      if (this.plays.some(c => c.bobaId === card.bobaId)) {
        return { ok: false, reason: 'already in deck' };
      }
      if (this.plays.length >= (this.currentFormat.playsTarget || 30)) {
        return { ok: false, reason: `plays full (${this.currentFormat.playsTarget || 30})` };
      }
      this.plays.push(card);
      return { ok: true };
    } else if (tab === 'bonus') {
      if (this.bonusPlays.some(c => c.bobaId === card.bobaId)) {
        return { ok: false, reason: 'already in deck' };
      }
      if (this.bonusPlays.length >= 15) {
        return { ok: false, reason: 'bonus plays full (15)' };
      }
      this.bonusPlays.push(card);
      return { ok: true };
    } else if (tab === 'hotdog') {
      if (this.hotDogs.length >= 10) {
        return { ok: false, reason: 'hot dogs full (10)' };
      }
      this.hotDogs.push(card);
      return { ok: true };
    }
    return { ok: false, reason: 'unknown tab' };
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

    // Hero count: [heroMin, heroMax] (SPEC+ allows 60-70)
    if (this.heroes.length < fmt.heroMin) {
      const d = fmt.heroMin - this.heroes.length;
      errors.push(`Need ${d} more heroes (${this.heroes.length}/${fmt.heroMin})`);
    } else if (this.heroes.length > fmt.heroMax) {
      errors.push(`Too many heroes (${this.heroes.length}/${fmt.heroMax})`);
    }

    // Per-hero power cap
    if (fmt.powerCap) {
      if (fmt.specPlusTiers) {
        // SPEC+: the first 60 heroes (sorted by power asc) must be ≤160.
        const sorted = [...this.heroes].sort((a, b) => (a.power || 0) - (b.power || 0));
        const baseOver = sorted.slice(0, 60).filter(c => (c.power || 0) > fmt.powerCap).length;
        if (baseOver > 0) errors.push(`${baseOver} base hero(es) over SPEC+ power cap ${fmt.powerCap}`);
      } else {
        const over = this.heroes.filter(c => (c.power || 0) > fmt.powerCap);
        if (over.length) errors.push(`${over.length} hero(es) over power cap ${fmt.powerCap}`);
      }
    }

    // Absolute hero power ceiling (SPEC+: 200)
    if (fmt.absMaxPower) {
      const over = this.heroes.filter(c => (c.power || 0) > fmt.absMaxPower).length;
      if (over > 0) errors.push(`${over} hero(es) above ${fmt.absMaxPower} ceiling`);
    }

    // Elite: total-power budget
    if (fmt.totalPowerCap) {
      const total = this.heroes.reduce((s, c) => s + (c.power || 0), 0);
      if (total > fmt.totalPowerCap) {
        errors.push(`Total power ${total}/${fmt.totalPowerCap} — over by ${total - fmt.totalPowerCap}`);
      }
    }

    // SPEC+ tiered per-power limits
    if (fmt.specPlusTiers) {
      const pv = this.powerValueCounts();
      for (const [powerStr, limit] of Object.entries(fmt.specPlusTiers)) {
        const power = Number(powerStr);
        const cnt = pv[power] || 0;
        if (cnt > limit) errors.push(`SPEC+ allows ${limit} at power ${power}; have ${cnt}`);
      }
    }

    // Per-power-value limit (default 6; Blast 3; skip SPEC+ tiered powers)
    const pv = this.powerValueCounts();
    const tieredPowers = fmt.specPlusTiers ? Object.keys(fmt.specPlusTiers).map(Number) : [];
    const perPowerLimit = this.effectivePerPowerLimit;
    if (perPowerLimit != null) {
      for (const [powerStr, cnt] of Object.entries(pv)) {
        const power = Number(powerStr);
        if (tieredPowers.includes(power)) continue;
        if (cnt > perPowerLimit) {
          errors.push(`Power ${power}: ${cnt}/${perPowerLimit} — remove ${cnt - perPowerLimit}`);
        }
      }
    }

    // Exact-variation uniqueness (the "one of" rule)
    const seen = new Set();
    for (const c of this.heroes) {
      const key = `${c.hero}|${c.treatment || ''}|${c.element}|${c.power}`;
      if (seen.has(key)) errors.push(`Duplicate: ${c.hero} (${c.treatment || 'Base'}, ${c.element}, ${c.power})`);
      seen.add(key);
    }

    // Optional 6-per-hero-name rule (retired by default; opt-in via ruleOverrides)
    if (this.ruleOverrides.perHeroNameLimit != null) {
      const limit = this.ruleOverrides.perHeroNameLimit;
      const nc = this.heroNameCounts();
      for (const [hero, cnt] of Object.entries(nc)) {
        if (cnt > limit) errors.push(`${hero}: ${cnt}/${limit} max (optional rule) — remove ${cnt - limit}`);
      }
    }

    // Banned card types (Elite: Trainer)
    if (fmt.bannedCardTypes.length) {
      const banned = this.heroes.filter(c => fmt.bannedCardTypes.includes(c.cardType));
      if (banned.length) errors.push(`${banned.length} banned card(s): ${fmt.bannedCardTypes.join(', ')} not legal`);
    }

    // Plays
    if (fmt.needsPlays) {
      const pt = fmt.playsTarget || 30;
      const pd = pt - this.plays.length;
      if (pd > 0) errors.push(`Need ${pd} more plays (${this.plays.length}/${pt})`);
      if (pd < 0) errors.push(`Too many plays (${this.plays.length}/${pt})`);
      // Bonus-play hard cap: 15 per BoBA rules (handoff §4(a)).
      if (this.bonusPlays.length > 15) {
        errors.push(`Too many bonus plays (${this.bonusPlays.length}/15) — remove ${this.bonusPlays.length - 15}`);
      }
    }

    // DBS budget (Playmaker divisions only)
    if (this.effectiveEnforceDBS && fmt.needsPlays && this.plays.length) {
      const budget = this.effectiveDBSBudget;
      const over = this.totalDBS - budget;
      if (over > 0) errors.push(`Playbook over DBS budget: ${this.totalDBS}/${budget} — reduce by ${over}`);
    }

    // Hot Dogs
    if (fmt.needsHD) {
      const hd = 10 - this.hotDogs.length;
      if (hd !== 0) errors.push(`Hot Dogs: ${this.hotDogs.length}/10`);
    }

    // Preset-driven special rules (weapon/treatment/set/hotDogHero restrictions)
    const preset = this.activePreset;
    if (preset && preset.specialRules) {
      for (const rule of preset.specialRules) {
        if (rule.selfVerify) continue; // shown in UI as informational
        if (rule.kind === 'weaponRestriction') {
          const allowed = new Set(rule.allowed || []);
          const bad = this.heroes.filter(c => !allowed.has(c.element));
          if (bad.length) errors.push(`${bad.length} hero(es) outside allowed weapons: ${[...allowed].join(', ')}`);
        } else if (rule.kind === 'treatmentContains') {
          const token = rule.token || '';
          const scope = rule.scope || 'heroes';
          const pool = scope === 'all' ? this.heroes.concat(this.hotDogs) : this.heroes;
          const bad = pool.filter(c => !((c.treatment || '').includes(token)));
          if (bad.length) errors.push(`${bad.length} card(s) missing '${token}' treatment`);
        } else if (rule.kind === 'hotDogHero') {
          const bad = this.hotDogs.filter(c => c.hero !== rule.name);
          if (bad.length) errors.push(`${bad.length} hot dog(s) not '${rule.name}'`);
        } else if (rule.kind === 'setRestriction') {
          const allowed = new Set(rule.allowed || []);
          const bad = this.allCards.filter(c => !allowed.has(c.set));
          if (bad.length) errors.push(`${bad.length} card(s) outside allowed set(s): ${[...allowed].join(', ')}`);
        } else if (rule.kind === 'overrideHeroCount') {
          const target = rule.value || 0;
          if (this.heroes.length !== target) {
            const d = target - this.heroes.length;
            errors.push(d > 0 ? `Division requires ${target} heroes (need ${d} more)`
                              : `Division requires ${target} heroes (remove ${-d})`);
          }
        }
      }
    }

    return errors;
  },

  // ── Active-rules descriptor list (mirrors iOS `activeRules`). Drives
  // the rule-chip panel in the Deck Rules sheet. ──
  get activeRules() {
    const fmt = this.currentFormat;
    const out = [];
    // Hero count
    if (fmt.heroMin === fmt.heroMax) {
      out.push({ label: `${fmt.heroMin} Heroes`, isOverride: false });
    } else {
      out.push({ label: `${fmt.heroMin}–${fmt.heroMax} Heroes`, isOverride: false });
    }
    // Per-power limit
    const perPowerLimit = this.effectivePerPowerLimit;
    if (perPowerLimit != null) {
      const isOverride = this.ruleOverrides.perPowerLimit != null && this.ruleOverrides.perPowerLimit !== fmt.perPowerDefault;
      out.push({ label: `Max ${perPowerLimit} per power value`, isOverride });
    } else if (this.ruleOverrides.disablePerPowerLimit) {
      out.push({ label: `No per-power limit`, isOverride: true });
    }
    // Power caps
    if (fmt.powerCap) out.push({ label: `Heroes ≤ ${fmt.powerCap} power`, isOverride: false });
    if (fmt.totalPowerCap) out.push({ label: `Total power ≤ ${fmt.totalPowerCap}`, isOverride: false });
    if (fmt.absMaxPower) out.push({ label: `No heroes above ${fmt.absMaxPower} power`, isOverride: false });
    if (fmt.specPlusTiers) out.push({ label: `SPEC+ tiered slots (1×175-200, 2×165/170)`, isOverride: false });
    // Optional 6-per-hero
    if (this.ruleOverrides.perHeroNameLimit != null) {
      out.push({ label: `Max ${this.ruleOverrides.perHeroNameLimit} of same hero (optional)`, isOverride: true });
    }
    // Banned types
    if (fmt.bannedCardTypes.length) {
      out.push({ label: `No ${fmt.bannedCardTypes.join(', ')} cards`, isOverride: false });
    }
    // DBS / bonus / HTD
    if (fmt.needsPlays) {
      if (this.effectiveEnforceDBS) {
        const budgetOverridden = this.ruleOverrides.dbsBudgetOverride != null;
        const enforceOverridden = this.ruleOverrides.enforceDBS === true && !fmt.enforcesDBS;
        out.push({ label: `${this.effectiveDBSBudget} DBS budget`, isOverride: budgetOverridden || enforceOverridden });
      } else if (fmt.enforcesDBS && this.ruleOverrides.enforceDBS === false) {
        out.push({ label: `DBS enforcement OFF`, isOverride: true });
      }
      out.push({ label: this.ruleOverrides.bonusPlaysEnabled ? 'Bonus Plays ON' : 'Bonus Plays OFF',
                 isOverride: !this.ruleOverrides.bonusPlaysEnabled });
      out.push({ label: this.ruleOverrides.htdPlaysEnabled ? 'HTD Plays ON' : 'HTD Plays OFF',
                 isOverride: !this.ruleOverrides.htdPlaysEnabled });
    }
    out.push({ label: `One-of per exact card`, isOverride: false });
    return out;
  },

  // opts.playsOnly === true → omit Heroes + Hot Dogs (for external deck
  // builders that accept only play cards). Default emits the full deck.
  exportText(opts = {}) {
    const playsOnly = opts.playsOnly === true;
    const lines = [`# ${this.deckName} (${this.format})`];
    lines.push('');
    if (!playsOnly) {
      lines.push(`## Heroes (${this.heroes.length})`);
      const sorted = [...this.heroes].sort((a, b) => (b.power || 0) - (a.power || 0));
      for (const c of sorted) {
        lines.push(`${c.hero || c.name} ${c.power} ${c.element} (${c.treatment || 'Base'})`);
      }
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
    if (!playsOnly && this.hotDogs.length) {
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

  // ── Full-deck CSV export per bobaleagues handoff §6 ──────────────
  // Header: id,name,type,release,number,cost,dbs,ability,bonus
  // Carries Heroes + Hot Dogs + Playbook + Bonus Plays in one file
  // (importCSV detects the header automatically and routes here).
  exportCSVv2() {
    function s(x) { return `"${String(x ?? '').replace(/"/g, '""')}"`; }
    const rows = ['id,name,type,release,number,cost,dbs,ability,bonus'];
    function row(c, type) {
      const cost = c.playCost != null ? c.playCost : '';
      const dbs  = c.dbs != null ? c.dbs : '';
      return [
        s(c.bobaId || c.cardNumber),
        s(c.name),
        type,
        s(c.release || c.set || ''),
        s(c.cardNumber),
        cost, dbs,
        s(c.description || c.playAbility || ''),
        String(c.isBonusPlay === true)
      ].join(',');
    }
    for (const h of this.heroes)     rows.push(row(h, 'HERO'));
    for (const h of this.hotDogs)    rows.push(row(h, 'HD'));
    for (const p of this.plays)      rows.push(row(p, 'PL'));
    for (const b of this.bonusPlays) rows.push(row(b, 'BPL'));
    return rows.join('\r\n');
  },

  clear() {
    this.heroes = []; this.plays = []; this.bonusPlays = []; this.hotDogs = [];
    this.deckName = 'New Deck';
  },

  // ── CSV import (Playbook-only, mirrors iOS importDeckCSV) ──────
  // Accepts the same "A - PL-67" set-prefix format produced by
  // exportCSV() + deck-builder.bobattlearena.com. Populates plays +
  // bonusPlays by slot; leaves heroes + hot dogs untouched so the
  // coach keeps whatever they have.
  importCSV(csvText, allCards) {
    // v2 detection — header begins "id,". v2 carries the full deck
    // (Heroes/HotDogs/Plays/BonusPlays); v1 is Playbook-only.
    if (/^id,/i.test(csvText)) return this._importCSVv2(csvText, allCards);
    const SET_BY_PREFIX = {
      'A': 'Alpha Edition',
      'U': 'Alpha Update',
      'G': 'Griffey Edition',
    };
    const lookup = new Map();
    for (const c of allCards) {
      if (c.cardType === 'Play') lookup.set(`${c.set}|${c.cardNumber}`, c);
    }

    const lines = csvText.split(/\r?\n/).filter(Boolean);
    const newPlays = [], newBonus = [], unresolved = [];
    let skippedHeader = false;
    for (const rawLine of lines) {
      if (!skippedHeader && /^slot,/i.test(rawLine)) { skippedHeader = true; continue; }
      skippedHeader = true;
      const fields = this._parseCSVLine(rawLine);
      if (fields.length < 2) continue;
      const slot = (fields[0] || '').trim();
      const cardNumRaw = (fields[1] || '').trim();
      if (!cardNumRaw) continue;
      const m = cardNumRaw.match(/^([A-Z])\s*-\s*(.+)$/);
      if (!m) { unresolved.push(cardNumRaw); continue; }
      const setName = SET_BY_PREFIX[m[1]];
      if (!setName) { unresolved.push(cardNumRaw); continue; }
      const card = lookup.get(`${setName}|${m[2]}`);
      if (!card) { unresolved.push(cardNumRaw); continue; }
      if (/^B/i.test(slot)) newBonus.push(card);
      else                  newPlays.push(card);
    }

    this.plays = newPlays;
    this.bonusPlays = newBonus;
    return { plays: newPlays.length, bonus: newBonus.length, unresolved };
  },

  // Tolerant v2 importer per bobaleagues handoff §6.
  _importCSVv2(csvText, allCards) {
    const lines = csvText.split(/\r?\n/).filter(Boolean);
    if (!lines.length) return { plays: 0, bonus: 0, unresolved: [] };
    const header = this._parseCSVLine(lines[0]).map(h => h.trim().toLowerCase());
    const col = (aliases) => header.findIndex(h => aliases.includes(h));
    const cId      = col(['id','card id','card_id','bobaid']);
    const cName    = col(['name','play name','card name']);
    const cType    = col(['type','card type','card_type']);
    const cRelease = col(['release','set']);
    const cNumber  = col(['number','cardnumber','card#','card #','card_number']);
    const cBonus   = col(['bonus','is_bonus','bonusplay']);
    const byId      = new Map();
    const byRelNum  = new Map();
    const byRelName = new Map();
    const byName    = new Map();
    const byNumber  = new Map();
    for (const c of allCards) {
      if (c.bobaId) byId.set(c.bobaId, c);
      const rel = c.release || c.set || '';
      if (rel) byRelNum.set(`${rel}|${c.cardNumber}`, c);
      if (rel) byRelName.set(`${rel}|${(c.name||'').toLowerCase()}`, c);
      const k = (c.name||'').toLowerCase();
      if (!byName.has(k)) byName.set(k, []);
      byName.get(k).push(c);
      byNumber.set(c.cardNumber, c);
    }
    const newHeroes = [], newHotDogs = [], newPlays = [], newBonus = [], unresolved = [];
    for (const line of lines.slice(1)) {
      const f = this._parseCSVLine(line);
      if (!f.length) continue;
      const at = (i) => (i >= 0 && i < f.length) ? (f[i] || '').trim() : '';
      const id = at(cId), name = at(cName), type = at(cType).toUpperCase();
      const release = at(cRelease), number = at(cNumber);
      const bonus = at(cBonus).toLowerCase() === 'true';
      let card = (id && byId.get(id))
              || (release && number && byRelNum.get(`${release}|${number}`))
              || (release && name && byRelName.get(`${release}|${name.toLowerCase()}`))
              || (name && byName.get(name.toLowerCase())?.[0])
              || (number && byNumber.get(number))
              || null;
      if (!card) { if (id || name) unresolved.push(name || id); continue; }
      switch (type) {
        case 'HERO':              newHeroes.push(card);  break;
        case 'HD': case 'HOTDOG': newHotDogs.push(card); break;
        case 'BPL':               newBonus.push(card);   break;
        case 'PL': case '':       (bonus ? newBonus : newPlays).push(card); break;
        default:                  newPlays.push(card);
      }
    }
    if (newHeroes.length)  this.heroes  = newHeroes;
    if (newHotDogs.length) this.hotDogs = newHotDogs;
    this.plays      = newPlays;
    this.bonusPlays = newBonus;
    return { plays: newPlays.length, bonus: newBonus.length, unresolved };
  },

  // RFC 4180-ish line parser — handles quoted fields + escaped quotes
  _parseCSVLine(line) {
    const out = [];
    let field = '', inQuotes = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (inQuotes) {
        if (c === '"') {
          if (line[i + 1] === '"') { field += '"'; i++; }
          else inQuotes = false;
        } else field += c;
      } else {
        if (c === ',')      { out.push(field); field = ''; }
        else if (c === '"') inQuotes = true;
        else                field += c;
      }
    }
    out.push(field);
    return out;
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
  // Empty-state branch (iOS tick 92 + Android tick 89 parity).
  // Disambiguates search-driven empty vs tab-driven empty so users
  // know whether the issue is their query or the tab they're on.
  if (cards.length === 0) {
    const trimmedQ = (DB.search || '').trim();
    if (trimmedQ) {
      grid.innerHTML = `<div class="db-browser-empty">
        <p class="db-browser-empty-headline">No cards match "${trimmedQ.replace(/[<>&"]/g, c => ({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;'}[c]))}"</p>
        <p class="db-browser-empty-body">Try a different term or clear the search.</p>
        <button type="button" class="btn-ghost-sm" data-action="db-clear-search">Clear search</button>
      </div>`;
      grid.querySelector('[data-action="db-clear-search"]')?.addEventListener('click', () => {
        DB.search = '';
        const input = $('db-search');
        if (input) input.value = '';
        // Hide the inline ✕ button too — its visibility tracks input value.
        const clearBtn = $('db-search-clear');
        if (clearBtn) clearBtn.hidden = true;
        dbRenderGrid(allCards);
      });
    } else {
      grid.innerHTML = `<div class="db-browser-empty">
        <p class="db-browser-empty-headline">No cards in scope</p>
        <p class="db-browser-empty-body">Pick a different tab above (Heroes / Plays / Bonus / Hot Dogs) to see eligible cards.</p>
      </div>`;
    }
    return;
  }
  grid.innerHTML = cards.map(card => {
    const imgUrl = card.imageFile ? thumbUrl(card.imageFile) : null;
    const inDeck = DB.isInDeck(card);
    // Extended at-cap visual marker — was hero-only; now covers plays /
    // bonus / hotdog so the user sees *before tapping* which cells
    // would silently no-op. Mirrors iOS DeckBuilder's disabled tint.
    const violates =
      (DB.browserTab === 'hero'   && DB.wouldHeroViolate(card)) ||
      (DB.browserTab === 'play'   && (inDeck || DB.plays.length    >= (DB.currentFormat.playsTarget || 30))) ||
      (DB.browserTab === 'bonus'  && (inDeck || DB.bonusPlays.length >= 15)) ||
      (DB.browserTab === 'hotdog' && DB.hotDogs.length >= 10);
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
  const fmt = DB.currentFormat;
  const heroTargetLabel = fmt.heroMin === fmt.heroMax ? `${fmt.heroMin}` : `${fmt.heroMin}–${fmt.heroMax}`;
  const hStat = $('db-stat-heroes');
  const pStat = $('db-stat-plays');
  const hdStat = $('db-stat-hotdogs');
  const dbsStat = $('db-stat-dbs');
  const lStat = $('db-stat-legal');
  if (hStat) hStat.textContent = `Heroes: ${DB.heroes.length}/${heroTargetLabel}`;
  if (pStat) pStat.style.display = fmt.needsPlays ? '' : 'none';
  if (pStat) pStat.textContent = `Plays: ${DB.plays.length}/${fmt.playsTarget || 30}`;
  if (hdStat) hdStat.style.display = fmt.needsHD ? '' : 'none';
  if (hdStat) hdStat.textContent = `Hot Dogs: ${DB.hotDogs.length}/10`;
  if (dbsStat) {
    if (DB.effectiveEnforceDBS && fmt.needsPlays) {
      dbsStat.style.display = '';
      const over = DB.totalDBS > DB.effectiveDBSBudget;
      dbsStat.textContent = `DBS: ${DB.totalDBS}/${DB.effectiveDBSBudget}`;
      dbsStat.className = over ? 'db-stat db-stat-dbs over' : 'db-stat db-stat-dbs';
    } else {
      dbsStat.style.display = 'none';
    }
  }

  const errors = DB.validate();
  if (lStat) {
    if (DB.heroes.length === 0) {
      lStat.textContent = 'Build your deck';
      lStat.className = 'db-stat db-stat-legality';
      lStat.setAttribute('data-state', 'empty');
    } else if (errors.length === 0) {
      lStat.textContent = 'LEGAL';
      lStat.className = 'db-stat db-stat-legality legal';
      lStat.removeAttribute('data-state');
    } else {
      lStat.textContent = 'ILLEGAL';
      lStat.className = 'db-stat db-stat-legality';
      lStat.removeAttribute('data-state');
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

// Template metadata + key mapping to template-decks.json. Replaced
// 2026-04-27 per bobaleagues handoff §7 — the new five reflect
// frequency analysis of community top-tier decks under the post-patch
// DBS budget. Old keys (fire-aggro / ice-control / etc.) are gone.
const DB_TEMPLATES = [
  // accent = matches the per-archetype color in iOS TemplateCard.accentColor
  { id: 'lockdown', key: 'lockdown-locker', name: 'Lockdown Locker', desc: 'Steel-anchored disruption — high-DBS lockouts close out mid-game.', accent: 'STEEL' },
  { id: 'frozen',   key: 'frozen-tempo',    name: 'Frozen Tempo',    desc: 'Ice synergy + Substitution control + economy denial.',           accent: 'ICE' },
  { id: 'draw',     key: 'draw-and-adapt',  name: 'Draw and Adapt',  desc: 'Engine-first. Maximum draw and situational answers.',           accent: 'CYAN' },
  { id: 'glow',     key: 'glow-sacrifice',  name: 'Glow Sacrifice',  desc: 'Spec format: discard-fuel + Glow synergy.',                     accent: 'GLOW' },
  { id: 'brawl',    key: 'brawl-beatdown',  name: 'Brawl Beatdown',  desc: 'Aggro tempo. Win the first 3–4 battles.',                       accent: 'BRAWL' },
];

// Fetched once at initDeckBuilder time; keyed by template key
let dbTemplateData = null;

/// Card-style template gallery — parity with iOS DeckBuilderView's
/// TemplateCard (DESIGN.md §8.3 empty-state). Monogram tile colored
/// by archetype + name + description + chevron. Replaces the prior
/// row of plain text buttons.
function dbRenderTemplates() {
  const el = $('db-templates');
  if (!el) return;
  el.innerHTML = DB_TEMPLATES.map(t => {
    const initial = (t.name[0] || '?').toUpperCase();
    return `<button class="db-template-card" data-template="${t.id}" data-accent="${t.accent}" title="${t.desc}" type="button" aria-label="Load ${t.name} template">
      <span class="db-template-mono" aria-hidden="true">${initial}</span>
      <span class="db-template-text">
        <span class="db-template-name">${t.name}</span>
        <span class="db-template-desc">${t.desc}</span>
        <span class="db-template-format">PLAYMAKER</span>
      </span>
      <svg class="db-template-chev" viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <polyline points="9 18 15 12 9 6"/>
      </svg>
    </button>`;
  }).join('');
}

function dbRender(allCards) {
  dbRenderGrid(allCards);
  dbRenderDeckList();
}

/// Hide saved-deck rows whose name doesn't substring-match the
/// search-input value. Case-insensitive. Idempotent — safe to call
/// after every list render to re-apply the user's active filter.
function applyDeckSearchFilter() {
  const input = $('db-saved-decks-search');
  const list  = $('db-saved-decks-list');
  if (!list) return;
  const q = (input?.value || '').trim().toLowerCase();
  let visibleCount = 0;
  list.querySelectorAll('.db-saved-deck-row').forEach(row => {
    const name = (row.dataset.deckName || '').toLowerCase();
    const matches = !q || name.includes(q);
    row.style.display = matches ? '' : 'none';
    if (matches) visibleCount++;
  });
  // If the search yielded zero matches, show an inline empty-state
  // block with a productive "Clear search" button — universal-feature-
  // states skill (empty states must invite action, not just announce
  // absence). Mirrors web tick 78 Collection empty-search branch.
  let hint = list.querySelector('.db-saved-decks-search-empty');
  if (q && visibleCount === 0) {
    if (!hint) {
      hint = document.createElement('div');
      hint.className = 'db-saved-decks-empty db-saved-decks-search-empty';
      hint.innerHTML = `
        <p class="db-saved-decks-empty-headline">No saved decks match "${q.replace(/[<>&"]/g, c => ({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;'}[c]))}"</p>
        <button type="button" class="btn-ghost-sm" data-action="clear-deck-search">Clear search</button>
      `;
      list.appendChild(hint);
      hint.querySelector('[data-action="clear-deck-search"]')?.addEventListener('click', () => {
        if (input) {
          input.value = '';
          input.focus();
          applyDeckSearchFilter();
        }
      });
    }
  } else if (hint) {
    hint.remove();
  }
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
      // Switching format directly unlinks from any attached preset —
      // user is explicitly overriding the preset's format.
      if (DB.activePreset && DB.activePreset.format !== DB.format) {
        DB.unlinkFromPreset();
      }
      dbRender(allCards);
    });
  });

  // Rules button opens the preset + toggles modal
  $('db-rules-btn')?.addEventListener('click', () => dbOpenRulesModal(allCards));
  $('db-rules-close')?.addEventListener('click', () => dbCloseRulesModal());
  $('db-rules-backdrop')?.addEventListener('click', () => dbCloseRulesModal());
  $('db-rules-reset')?.addEventListener('click', () => {
    // Reset to preset baseline if attached, else clear all overrides
    if (DB.activePreset) {
      DB.applyPreset(DB.activePreset);
    } else {
      DB.ruleOverrides = {
        perHeroNameLimit: null, perPowerLimit: null, disablePerPowerLimit: false,
        enforceDBS: null, dbsBudgetOverride: null,
        bonusPlaysEnabled: true, htdPlaysEnabled: true,
      };
    }
    dbRender(allCards);
    dbRenderRulesSheet(allCards);
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

  // Search — debounced so a fast typist doesn't re-filter the 17k
  // catalog on every keystroke. 220ms matches the Collection search
  // debounce; Find uses 280ms.
  let _dbSearchTimer = null;
  const _dbSearchClear = $('db-search-clear');
  $('db-search')?.addEventListener('input', e => {
    const next = e.target.value;
    // Toggle clear-× instantly so the affordance feels snappy even
    // though the filter is debounced (matches Collection tick 37).
    if (_dbSearchClear) _dbSearchClear.hidden = !next;
    clearTimeout(_dbSearchTimer);
    _dbSearchTimer = setTimeout(() => {
      DB.search = next;
      dbRenderGrid(allCards);
    }, 220);
  });
  _dbSearchClear?.addEventListener('click', () => {
    const input = $('db-search');
    if (!input) return;
    input.value = '';
    _dbSearchClear.hidden = true;
    clearTimeout(_dbSearchTimer);
    if (DB.search) {
      DB.search = '';
      dbRenderGrid(allCards);
    }
    input.focus();
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
      // Immediate add — surface the outcome so silent no-ops
      // (already in deck / cap reached) become visible. Parity with
      // iOS tick 112's "X — already in deck" banner.
      const result = DB.addCard(card);
      dbRender(allCards);
      const label = card.hero || card.name || 'card';
      if (window.showToast) {
        window.showToast(result.ok ? `Added ${label}` : `${label} — ${result.reason}`);
      }
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
    const result = DB.addCard(card);
    dbRender(allCards);
    // Close popup immediately after adding
    dbHideCardPopup();
    const label = card.hero || card.name || 'card';
    if (window.showToast) {
      window.showToast(result.ok ? `Added ${label}` : `${label} — ${result.reason}`);
    }
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
    const bobaId = btn.dataset.remove;
    const section = btn.dataset.section;
    // Capture the card BEFORE remove so Undo can re-add it without
    // re-walking the catalog. Tick 118 — Add/Remove banner symmetry
    // + Undo affordance (parity with iOS tick 117 + Android tick 116).
    const removed = allCards.find(c => c.bobaId === bobaId);
    DB.removeCard(bobaId, section);
    dbRender(allCards);
    if (removed) {
      const label = removed.hero || removed.name || 'card';
      showUndoToast(`Removed ${label}`, () => {
        // Re-add via DB.addCard. AddResult discarded — the slot is
        // free again so the add always succeeds.
        // Restore section context first so addCard routes to the right
        // bucket (Heroes / Plays / Bonus / HotDogs).
        const tabBySection = { hero: 'hero', play: 'play', bonus: 'bonus', hotdog: 'hotdog' };
        const prevTab = DB.browserTab;
        DB.browserTab = tabBySection[section] || prevTab;
        DB.addCard(removed);
        DB.browserTab = prevTab;
        dbRender(allCards);
      });
    }
  });

  // Deck name
  $('db-deck-name')?.addEventListener('input', e => { DB.deckName = e.target.value; });

  // Clear deck — tick 143 closes the 3-platform parity loop on
  // Clear-deck Undo (iOS tick 142, Android tick 139). Replaces the
  // blocking confirm() with a Snackbar that surfaces an Undo action
  // within the recovery window. Matches the per-copy delete pattern
  // tick 123 already established for Collection.
  $('db-clear-btn')?.addEventListener('click', () => {
    // Empty deck → clearing is a no-op; bail before touching the DOM.
    const totalCards = DB.heroes.length + DB.plays.length + DB.bonusPlays.length + DB.hotDogs.length;
    if (totalCards === 0) return;
    // Snapshot pre-clear state. Arrays only — DB.clear() preserves
    // format + activePreset + ruleOverrides, so we don't need them.
    const snapshot = {
      heroes:     DB.heroes.slice(),
      plays:      DB.plays.slice(),
      bonusPlays: DB.bonusPlays.slice(),
      hotDogs:    DB.hotDogs.slice(),
      deckName:   DB.deckName,
    };
    DB.clear();
    const nameEl = $('db-deck-name');
    if (nameEl) nameEl.value = 'New Deck';
    dbRender(allCards);
    if (typeof window.showUndoToast === 'function') {
      window.showUndoToast('Draft cleared', () => {
        DB.heroes     = snapshot.heroes;
        DB.plays      = snapshot.plays;
        DB.bonusPlays = snapshot.bonusPlays;
        DB.hotDogs    = snapshot.hotDogs;
        DB.deckName   = snapshot.deckName;
        if (nameEl) nameEl.value = snapshot.deckName;
        dbRender(allCards);
      });
    }
  });

  // Templates — load from pre-computed template-decks.json
  $('db-templates')?.addEventListener('click', e => {
    const btn = e.target.closest('.db-template-card, .db-template-btn');
    if (!btn) return;
    const meta = DB_TEMPLATES.find(t => t.id === btn.dataset.template);
    if (!meta) return;

    function applyTemplate(data) {
      const byId = {};
      for (const c of allCards) { if (c.bobaId) byId[c.bobaId] = c; }
      const tpl = data[meta.key];
      if (!tpl) return;
      // Capture pre-load draft state so the toast can warn the user
      // when their existing draft was silently overwritten. Parity
      // with iOS tick 137 + Android tick 136. Any non-empty section
      // counts.
      const hadDraft = (DB.heroes.length + DB.plays.length + (DB.bonusPlays || []).length + DB.hotDogs.length) > 0;
      // Preserve the user's chosen format — DON'T overwrite to
      // 'playmaker'. Starter decks ship universally-legal cards
      // (heroes ≤160 power, ≤8200 total, ≤1000 DBS) so any format
      // accepts them; the load just trims to the active format's
      // hero max (Limited = 40, others = 60).
      DB.clear();
      DB.deckName = meta.name;
      const fmt = DB.currentFormat;
      const heroMax = fmt.heroMax || fmt.heroMaximum || 60;
      const allHeroes = tpl.heroIds.map(id => byId[id]).filter(Boolean);
      DB.heroes    = allHeroes.slice(0, heroMax);
      DB.plays     = fmt.needsPlays ? tpl.playIds.map(id => byId[id]).filter(Boolean) : [];
      DB.bonusPlays = fmt.needsPlays
                        ? (tpl.bonusPlayIds || []).map(id => byId[id]).filter(Boolean)
                        : [];
      DB.hotDogs   = fmt.needsHD ? tpl.hotDogIds.map(id => byId[id]).filter(Boolean) : [];
      dbRender(allCards);
      if (window.showToast) {
        window.showToast(hadDraft
          ? `Loaded "${meta.name}" — your previous draft was replaced.`
          : `Loaded "${meta.name}"`);
      }
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

  // Export. The "Full deck" toggle (db-export-full, default checked)
  // switches text + CSV between the full BOBA Playbook deck and a
  // Plays-only export for external deck builders that take only plays.
  const dbExportIsFull = () => $('db-export-full')?.checked !== false;
  const dbRenderExportText = () => {
    const textEl = $('db-export-text');
    if (textEl) textEl.value = DB.exportText({ playsOnly: !dbExportIsFull() });
  };
  $('db-export-btn')?.addEventListener('click', () => {
    const outEl = $('db-export-out');
    if (!outEl) return;
    dbRenderExportText();
    outEl.hidden = !outEl.hidden;
  });
  // Re-render the preview text the moment the toggle flips.
  $('db-export-full')?.addEventListener('change', dbRenderExportText);

  // Generate Deck Wall — iOS DESIGN.md §8.8 + DECISIONS.md #036.
  // Pulls Heroes + Plays + Hot Dogs from the current builder state
  // and hands them to the shared canvas Wall renderer. Empty deck
  // shows a brief toast instead of opening an empty canvas.
  $('db-wall-btn')?.addEventListener('click', () => {
    const cards = [...(DB.heroes || []), ...(DB.plays || []), ...(DB.hotDogs || [])];
    if (cards.length === 0) {
      if (window.showToast) window.showToast('Add some cards to your deck first.');
      return;
    }
    if (window.Collection?.openDeckWallSheet) {
      window.Collection.openDeckWallSheet({
        deckName: DB.deckName || 'My Deck',
        cards,
      });
    }
  });

  $('db-copy-btn')?.addEventListener('click', () => {
    const textEl = $('db-export-text');
    if (!textEl) return;
    navigator.clipboard.writeText(textEl.value).then(() => {
      const btn = $('db-copy-btn');
      if (btn) { btn.textContent = 'Copied!'; setTimeout(() => { btn.textContent = 'Copy Text'; }, 2000); }
    });
  });

  // CSV download. Full deck → exportCSVv2 (Heroes + Hot Dogs + Plays +
  // Bonus Plays; importCSV auto-detects the v2 header). Plays-only →
  // exportCSV (the legacy slot format deck-builder.bobattlearena.com accepts).
  $('db-csv-btn')?.addEventListener('click', () => {
    const full = dbExportIsFull();
    const csv = full ? DB.exportCSVv2() : DB.exportCSV();
    const blob = new Blob([csv], { type: 'text/csv' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href = url;
    a.download = `${DB.deckName.replace(/[^a-z0-9]/gi, '_')}${full ? '' : '_plays'}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    const btn = $('db-csv-btn');
    if (btn) { btn.textContent = 'Downloaded!'; setTimeout(() => { btn.textContent = 'Download CSV'; }, 2000); }
  });

  // CSV import — same format as export. Replaces plays + bonusPlays.
  $('db-import-btn')?.addEventListener('click', () => {
    $('db-import-file')?.click();
  });
  $('db-import-file')?.addEventListener('change', (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const banner = $('db-import-banner');
      try {
        const result = DB.importCSV(String(reader.result || ''), allCards);
        let msg = `Imported ${result.plays} plays + ${result.bonus} bonus`;
        if (result.unresolved.length) msg += ` · ${result.unresolved.length} unresolved`;
        if (banner) {
          banner.textContent = msg;
          banner.hidden = false;
          setTimeout(() => { banner.hidden = true; }, 4000);
        }
        dbRender(allCards);
      } catch (err) {
        if (banner) {
          banner.textContent = `Import failed: ${err.message || err}`;
          banner.hidden = false;
        }
      }
      // Reset the file input so selecting the same file again re-triggers change
      e.target.value = '';
    };
    reader.readAsText(file);
  });

  // Save deck
  let DB_savedId = null; // track the Supabase deck id for the current deck

  // Auth-state listener — wipe the in-memory draft + saved-deck pointer
  // when the user signs out. Without this, user A's draft (+ their
  // DB_savedId pointing at one of A's saved decks) lingered into user
  // B's session. iOS handles this via @Observable store invalidation;
  // web matches now. Mirrors the Collection.clear() pattern from
  // feedback_viewmodel_reset_on_auth_change.
  document.addEventListener('auth-change', ({ detail }) => {
    if (detail?.session) return;  // sign-in — keep the user's draft
    DB.clear();
    DB.format = 'playmaker';  // back to default (DB.clear() doesn't reset format)
    DB_savedId = null;
    _writeDeckURL();
    const nameEl = $('db-deck-name');
    if (nameEl) nameEl.value = DB.deckName;
    // Manage Decks panel could be visible with the prior user's list —
    // hide it so the next sign-in starts clean.
    const savedPanel = $('db-saved-decks-panel');
    if (savedPanel) savedPanel.hidden = true;
    // Reset the saved-decks search input so user B doesn't inherit
    // user A's typed query.
    const savedSearch = $('db-saved-decks-search');
    if (savedSearch) savedSearch.value = '';
    // Re-render so the empty draft replaces whatever the prior user
    // had drafted on screen.
    if (allCards) dbRender(allCards);
  });

  // Tick 308 — Cmd/Ctrl+S triggers Save Deck when on the Decks view.
  // Universal save idiom; iOS v2.319 (tick 307) parity. Gated on
  // (a) Decks view active, (b) no input field has focus (otherwise
  // browser handles Cmd+S = "save page"), (c) no <dialog> open.
  document.addEventListener('keydown', (e) => {
    if (e.key !== 's' && e.key !== 'S') return;
    if (!(e.metaKey || e.ctrlKey)) return;
    if (e.shiftKey || e.altKey) return;
    const decksView = document.getElementById('view-decks');
    if (!decksView || decksView.hidden) return;
    const tgt = e.target;
    if (tgt && (tgt.matches?.('input, textarea, [contenteditable="true"]') || tgt.isContentEditable)) return;
    if (document.querySelector('dialog[open]')) return;
    e.preventDefault();
    $('db-save-btn')?.click();
  });

  // Tick 323 — `n` (no modifier) clears the draft = "new deck" idiom.
  // iOS Cmd+N (v2.322) parity. Browser reserves Ctrl/Cmd+N for new
  // window, so we use unmodified `n` gated on no-input-focus to avoid
  // collision with typing the deck name. Fires the existing
  // db-clear-btn click (Snackbar + Undo recovery window already wired).
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'n' && e.key !== 'N') return;
    if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;
    const decksView = document.getElementById('view-decks');
    if (!decksView || decksView.hidden) return;
    const tgt = e.target;
    if (tgt && (tgt.matches?.('input, textarea, [contenteditable="true"]') || tgt.isContentEditable)) return;
    if (document.querySelector('dialog[open]')) return;
    e.preventDefault();
    $('db-clear-btn')?.click();
  });

  $('db-save-btn')?.addEventListener('click', async () => {
    const session = await API.authGetSession();
    if (!session) {
      // Prompt sign-in
      Auth?.open?.();
      return;
    }
    const btn    = $('db-save-btn');
    const banner = $('db-import-banner');  // reuse existing banner for save feedback

    // Guard: empty deck. Saving a deck with zero cards across every
    // section is almost certainly a misclick — fire an inline hint
    // instead of writing a junk row. iOS parity: DeckBuilderStore
    // refuses save when totalCardCount == 0.
    const cards = [
      ...DB.heroes.map(c => ({ bobaId: c.bobaId, cardType: 'hero' })),
      ...DB.plays.map(c => ({ bobaId: c.bobaId, cardType: 'play' })),
      ...DB.bonusPlays.map(c => ({ bobaId: c.bobaId, cardType: 'bonus_play' })),
      ...DB.hotDogs.map(c => ({ bobaId: c.bobaId, cardType: 'hot_dog' })),
    ];
    if (cards.length === 0) {
      if (banner) {
        banner.textContent = 'Add at least one card before saving.';
        banner.hidden = false;
        setTimeout(() => { banner.hidden = true; }, 3000);
      }
      return;
    }

    // Guard: empty/whitespace name. Default the editable name field
    // to "New Deck" rather than fighting the user — but never write
    // an empty `name` to the server.
    const deckName = (DB.deckName || '').trim() || 'New Deck';

    if (btn) { btn.disabled = true; }
    try {
      DB_savedId = await API.deckSave(DB_savedId, deckName, DB.format, cards);
      _writeDeckURL();  // capture the newly-assigned id in the URL
      if (btn) { btn.style.color = '#4CAF50'; setTimeout(() => { btn.style.color = ''; }, 2000); }
      if (banner) {
        banner.textContent = `Saved "${deckName}".`;
        banner.hidden = false;
        setTimeout(() => { banner.hidden = true; }, 2500);
      }
    } catch (err) {
      console.error('Deck save failed:', err);
      if (banner) {
        banner.textContent = `Save failed: ${err?.message || 'try again'}`;
        banner.hidden = false;
      } else {
        alert('Could not save deck. Please try again.');
      }
    } finally {
      if (btn) { btn.disabled = false; }
    }
  });

  // Close saved-decks overlay
  $('db-saved-decks-close')?.addEventListener('click', () => {
    const panel = $('db-saved-decks-panel');
    if (panel) panel.hidden = true;
  });

  // Fetch + render the saved-decks list. Extracted from the Load
  // button's click handler so the Refresh button can call it
  // Extracted load — reusable from both the Manage Decks Load button
  // click handler AND the URL restore path (window.DeckBuilder
  // .applyURLState below). DB_savedId update + URL write happens here
  // so both entry points stay in lockstep.
  async function _loadSavedDeckIntoEditor(deckId, deckName, deckFormat, opts = {}) {
    if (!deckId) return;
    try {
      const rows = await API.deckLoad(deckId);
      DB.clear();
      DB.deckName = deckName || 'Deck';
      DB.format   = deckFormat || DB.format;
      const nameEl = $('db-deck-name');
      if (nameEl) nameEl.value = DB.deckName;
      document.querySelectorAll('#view-decks .db-format-btn').forEach(b => {
        b.classList.toggle('active', b.dataset.format === DB.format);
      });
      const byBobaId = {};
      for (const c of allCards || []) { if (c.bobaId) byBobaId[c.bobaId] = c; }
      for (const row of rows) {
        const card = byBobaId[row.boba_id];
        if (!card) continue;
        if (row.card_type === 'hero')            DB.heroes.push(card);
        else if (row.card_type === 'play')       DB.plays.push(card);
        else if (row.card_type === 'bonus_play') DB.bonusPlays.push(card);
        else if (row.card_type === 'hot_dog')    DB.hotDogs.push(card);
      }
      DB_savedId = deckId;
      if (allCards) dbRender(allCards);
      const panel = $('db-saved-decks-panel');
      if (panel) panel.hidden = true;
      if (!opts.fromHistory) _writeDeckURL();
    } catch (err) {
      console.error('Deck load failed:', err);
      if (!opts.fromHistory) alert('Could not load deck.');
    }
  }

  function _writeDeckURL() {
    if (typeof history === 'undefined') return;
    const url = new URL(window.location.href);
    url.searchParams.set('view', 'decks');
    if (DB_savedId) url.searchParams.set('deck', DB_savedId);
    else url.searchParams.delete('deck');
    try {
      history.replaceState(
        { ...(history.state || {}), view: 'decks' },
        '',
        url.pathname + url.search,
      );
    } catch (_) { /* noop */ }
  }

  // Expose to app.js popstate dispatcher + initial-load. ?view=decks
  // &deck={id} restores the saved deck into the editor.
  window.DeckBuilder = window.DeckBuilder || {};
  window.DeckBuilder.applyURLState = async (params) => {
    const deckId = params.get('deck');
    if (!deckId) return;
    if (DB_savedId === deckId) return;  // already loaded, no-op
    // Need the deck's name + format for the editor header. Fetch the
    // list (cheap; user's saved-deck count is bounded). If the deck
    // isn't in the user's list (signed out / not their deck), no-op.
    try {
      const list = await API.deckList();
      const deck = list.find(d => d.id === deckId);
      if (!deck) return;
      await _loadSavedDeckIntoEditor(deck.id, deck.name, deck.format, { fromHistory: true });
    } catch (e) {
      console.warn('Decks URL restore failed:', e);
    }
  };

  // independently without re-toggling the panel visibility.
  async function refreshSavedDecksList() {
    const list = $('db-saved-decks-list');
    if (!list) return;
    list.innerHTML = '<div class="db-saved-decks-empty">Loading…</div>';
    try {
      const decks = await API.deckList();
      _renderSavedDecksList(decks);
    } catch (err) {
      console.error('Deck list failed:', err);
      list.innerHTML = '<div class="db-saved-decks-empty">Could not load decks.</div>';
    }
  }

  $('db-saved-decks-refresh')?.addEventListener('click', async () => {
    const btn = $('db-saved-decks-refresh');
    if (btn) {
      btn.classList.add('spinning');
      btn.disabled = true;
    }
    try {
      await refreshSavedDecksList();
    } finally {
      if (btn) {
        btn.classList.remove('spinning');
        btn.disabled = false;
      }
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
    await refreshSavedDecksList();
  });

  function _renderSavedDecksList(decks) {
    const list = $('db-saved-decks-list');
    if (!list) return;
    if (!decks || !decks.length) {
      list.innerHTML = '<div class="db-saved-decks-empty">No saved decks yet.</div>';
      return;
    }
    const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c =>
      ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;' }[c]));
    list.innerHTML = decks.map(d => `
      <div class="db-saved-deck-row" data-deck-id="${esc(d.id)}" data-deck-name="${esc(d.name)}">
        <div class="db-saved-deck-info">
          <span class="db-saved-deck-name">${esc(d.name)}</span>
          <span class="db-saved-deck-meta">${esc((d.format || 'playmaker').toUpperCase())} · ${esc(new Date(d.updated_at).toLocaleDateString())}</span>
        </div>
        <div class="db-saved-deck-actions">
          <button class="db-saved-deck-load" data-deck-id="${esc(d.id)}" data-deck-name="${esc(d.name)}" data-deck-format="${esc(d.format || 'playmaker')}">Load</button>
          <button class="db-saved-deck-rename" data-deck-id="${esc(d.id)}" aria-label="Rename ${esc(d.name)}" title="Rename">✎</button>
          <button class="db-saved-deck-delete" data-deck-id="${esc(d.id)}" aria-label="Delete ${esc(d.name)}">✕</button>
        </div>
      </div>
    `).join('');
    // Re-apply the user's active search filter (if any) so a refresh
    // doesn't blow away their typed query.
    applyDeckSearchFilter();
  }

  // Search filter — hides saved-deck rows whose name doesn't match
  // the typed query (case-insensitive substring). Doesn't refetch.
  $('db-saved-decks-search')?.addEventListener('input', applyDeckSearchFilter);

  // Load a specific saved deck
  $('db-saved-decks-list')?.addEventListener('click', async e => {
    const loadBtn    = e.target.closest('.db-saved-deck-load');
    const delBtn     = e.target.closest('.db-saved-deck-delete');
    const renameBtn  = e.target.closest('.db-saved-deck-rename');

    if (renameBtn) {
      const row = renameBtn.closest('.db-saved-deck-row');
      if (!row) return;
      const deckId = renameBtn.dataset.deckId;
      const currentName = row.dataset.deckName || '';
      const next = prompt('Rename deck', currentName);
      if (next == null) return;                          // Cancel
      const trimmed = next.trim();
      if (!trimmed || trimmed === currentName) return;   // No-op
      try {
        await API.deckRename(deckId, trimmed);
        row.dataset.deckName = trimmed;
        const nameEl = row.querySelector('.db-saved-deck-name');
        if (nameEl) nameEl.textContent = trimmed;
        // Update Load + Delete aria/data so a subsequent load/delete
        // uses the new name in feedback strings.
        const loadEl = row.querySelector('.db-saved-deck-load');
        if (loadEl) loadEl.dataset.deckName = trimmed;
        const delEl = row.querySelector('.db-saved-deck-delete');
        if (delEl) delEl.setAttribute('aria-label', `Delete ${trimmed}`);
        renameBtn.setAttribute('aria-label', `Rename ${trimmed}`);
        // If this deck is the currently-loaded draft, keep the
        // builder's editable name field in step too.
        if (DB_savedId === deckId) {
          DB.deckName = trimmed;
          const nameInput = $('db-deck-name');
          if (nameInput) nameInput.value = trimmed;
        }
        applyDeckSearchFilter();
        // Tick 173 — confirm rename + close parity with iOS/Android
        // (Android tick noted earlier surfaces "Renamed to X" via
        // Snackbar; iOS uses DeckManagementSheet's saveMessage
        // pattern). Web had silent success, alert-on-failure.
        if (typeof window.showToast === 'function') {
          window.showToast(`Renamed to "${trimmed}"`);
        }
      } catch (err) {
        console.error('Deck rename failed:', err);
        // Was a blocking alert(); same anti-pattern tick 123 / 143 /
        // 163 systematically replaced. Use the canonical toast helper.
        if (typeof window.showToast === 'function') {
          window.showToast(`Couldn't rename — ${err?.message || 'try again'}`);
        }
      }
      return;
    }

    if (loadBtn) {
      await _loadSavedDeckIntoEditor(
        loadBtn.dataset.deckId,
        loadBtn.dataset.deckName,
        loadBtn.dataset.deckFormat,
      );
    }

    if (delBtn) {
      const deckId = delBtn.dataset.deckId;
      if (!confirm('Delete this deck?')) return;
      try {
        await API.deckDelete(deckId);
        delBtn.closest('.db-saved-deck-row')?.remove();
        if (DB_savedId === deckId) { DB_savedId = null; _writeDeckURL(); }
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

function fullUrl(file) { return file ? `${CDN_BASE}/full/${file}` : null; }

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
    // Mirror dbRenderGrid's extended at-cap check so the popup add
    // button accurately reflects "this would silently fail" across
    // every tab, not just hero.
    const atCap =
      (DB.browserTab === 'hero'   && DB.wouldHeroViolate(card)) ||
      (DB.browserTab === 'play'   && DB.plays.length    >= (DB.currentFormat.playsTarget || 30)) ||
      (DB.browserTab === 'bonus'  && DB.bonusPlays.length >= 15) ||
      (DB.browserTab === 'hotdog' && DB.hotDogs.length >= 10);
    addBtn.disabled   = inDeck || atCap;
    addBtn.textContent = inDeck ? 'In Deck' : atCap ? 'At cap' : 'Add to Deck';
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
/// Inline toast with an Undo action button (Material Snackbar shape).
/// Distinct from the plain `window.showToast` because that helper
/// only accepts text. Auto-dismisses after 3s; tapping Undo within
/// that window fires the callback + dismisses immediately. Tick 118
/// — parity with iOS tick 117's "Removed X" banner + Android tick 116's
/// Snackbar with Undo action.
function showUndoToast(message, onUndo) {
  // Reuse the same #app-toast element the plain showToast uses; just
  // adds a tappable button child. Visibility class + 3s auto-clear
  // handled inline to keep this self-contained.
  let t = document.getElementById('app-toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'app-toast';
    t.className = 'app-toast';
    document.body.appendChild(t);
  }
  t.textContent = '';  // clear any prior message
  const text = document.createElement('span');
  text.textContent = message;
  const action = document.createElement('button');
  action.type = 'button';
  action.className = 'app-toast-action';
  action.textContent = 'Undo';
  action.addEventListener('click', () => {
    onUndo?.();
    t.classList.remove('visible');
  }, { once: true });
  t.append(text, action);
  t.classList.add('visible');
  if (showUndoToast._timer) clearTimeout(showUndoToast._timer);
  showUndoToast._timer = setTimeout(() => t.classList.remove('visible'), 3000);
}
// Expose for sibling modules (collection.js's per-copy delete in
// particular — tick 123). Top-level `function` declarations land on
// the global object in classic scripts, but the explicit assignment
// is defensive: if practice.js is ever wrapped in an IIFE, this
// keeps cross-module access working.
window.showUndoToast = showUndoToast;

// ── Structured effect executor (play-effects.json) ────────────────
// Loads the effect database lazily and exposes pmExecStructured, which
// consumes an entry's `effects[]` and returns {selfDelta, oppDelta,
// selfHDDelta, oppHDDelta, description, handled}. Unknown ops are
// skipped (forward-compat). Cards without a structured entry currently
// fall through with handled=false; callers treat that as "no effect."

let PM_PLAY_EFFECTS = null;
let PM_PLAY_EFFECTS_PROMISE = null;

function pmLoadPlayEffects() {
  if (PM_PLAY_EFFECTS) return Promise.resolve(PM_PLAY_EFFECTS);
  if (PM_PLAY_EFFECTS_PROMISE) return PM_PLAY_EFFECTS_PROMISE;
  PM_PLAY_EFFECTS_PROMISE = fetch('assets/data/play-effects.json')
    .then(r => r.json())
    .then(data => { PM_PLAY_EFFECTS = data && data.entries ? data.entries : {}; return PM_PLAY_EFFECTS; })
    .catch(() => { PM_PLAY_EFFECTS = {}; return PM_PLAY_EFFECTS; });
  return PM_PLAY_EFFECTS_PROMISE;
}

function pmGetPlayEntry(card) {
  if (!PM_PLAY_EFFECTS || !card || !card.name) return null;
  return PM_PLAY_EFFECTS[card.name] || null;
}

// Effective cost after applying and consuming any play_cost_delta mods for this side.
// Single-use ('next_play_self') mods are consumed here; multi-battle ('this_and_next')
// mods expire based on PM.currentBattle.
function pmEffectiveCost(card, side /* 'player' | 'cpu' */) {
  const nominal = card.playCost || 0;
  if (!PM._playCostMods) PM._playCostMods = { player: [], cpu: [] };
  const mods = PM._playCostMods[side] || [];
  const currentBattle = (typeof PM.currentBattle === 'number') ? PM.currentBattle : 0;
  let total = nominal;
  const keep = [];
  for (const m of mods) {
    if (m.scope === 'this_and_next' && currentBattle > (m.installedAt + 1)) continue; // expired
    total += (m.delta || 0);
    if (m.scope === 'next_play_self') continue; // single-use
    keep.push(m);
  }
  PM._playCostMods[side] = keep;
  return Math.max(0, total);
}

// Returns true if this entry contains at least one op the executor doesn't implement yet.
// Used by the UI to surface an "effect not fully simulated" honesty note.
function pmEntryHasUnknownOps(entry) {
  if (!entry) return false;
  const known = new Set([
    // Power / HD
    'power','power_set','power_swap','power_double','power_steal','power_cap_min',
    'power_reset','add_previous_hero_delta','add_top_hero_power_to_self',
    'hd','hd_recover','swap_hd_counts',
    // Plays / hand / discard
    'draw','discard','discard_top','discard_hand_all','shuffle_hand_into_deck',
    'shuffle_from_discard_to_deck','reclaim_used_play','variable_cost_bonus',
    // Randomness
    'coin_flip','dice_roll','compound_roll','dice_roll_again','versus_dice_roll',
    'dice_gate',  // persistent gate — opponent must roll to play (Leave It To Chance)
    // Legality / control
    'protect_self','cancel_opponent_plays','cap_opponent_plays',
    'block_sub','block_plays','block_draw','block_hd_recover',
    'honors_set','substitute_free','force_substitute',
    'play_cost_delta','cancel_persistent','persistent_delta','install_persistent',
    'player_choice','reveal_play_for_conditional_free',
    // Hero manipulation
    'swap_active_with_hand','swap_active_with_discard','swap_active_with_future_hero',
    'replace_active_with_top_hero_deck','replace_next_with_top_hero_deck',
    'replace_all_unrevealed_with_top_hero_deck','replace_active_from_hand',
    'discard_hero','discard_hero_from_hand','discard_revealed_hero',
    'transform_to_hot_dog','mark_future_battle',
    // Reveal / peek / search / copy
    'reveal','reveal_top','reveal_top_hero_deck','peek_and_reorder_top',
    'reveal_top_reorder_or_bottom','peek_opponent_hand','peek_unrevealed_hero',
    'reorder_unrevealed_heroes','shuffle_revealed_back','force_reveal_from_hand',
    'search','copy_last_play','play_revealed_free','play_top_of_playbook_free',
    'discard_revealed','deploy_chosen_revealed','discard_other_revealed',
    'add_chosen_revealed_to_hand_discard_rest','name_and_discard',
    // Choice
    'choice',
    // Specials
    'mirror_power_effects_to_opponent','flip_opponent_debuffs',
    'tax_per_hero_in_hand','transfer_sub_cost','end_battle_by_power',
    'weapon_debuff_or_penalty','note'
  ]);
  let found = false;
  const walk = (s) => {
    if (found || !s || typeof s !== 'object') return;
    if (Array.isArray(s)) { s.forEach(walk); return; }
    if (s.op && !known.has(s.op)) { found = true; return; }
    ['then','else','options','choice','effect','on_match','on_miss',
     'heads','tails','if_match','on_reveal_effects','components',
     'per_hero_cost','fallback'].forEach(k => { if (s[k]) walk(s[k]); });
    if (s.branches) s.branches.forEach(b => { if (b.then) walk(b.then); if (b.effect) walk(b.effect); });
  };
  (entry.effects || []).forEach(walk);
  (entry.persistent || []).forEach(walk);
  return found;
}

// Legality gate: returns true unless the entry declares an unmet `requires` condition.
// Only hard-gated cards (Hot Dog Stock Exchange, etc.) set `requires`; everything else passes.
function pmIsPlayable(card, self /* 'player' | 'cpu' */) {
  const entry = pmGetPlayEntry(card);
  if (!entry || !entry.requires) return true;
  try {
    const ctx = pmMakeExecContext(self);
    return pmEvalCondition(entry.requires, ctx);
  } catch (_) {
    return true; // fail open on any evaluator error — don't block a legal play
  }
}

// Build context. `self` is whichever side played this card.
function pmMakeExecContext(self /* 'player' | 'cpu' */) {
  const opp = self === 'player' ? 'cpu' : 'player';
  const b = PM.battles[PM.currentBattle] || {};
  const selfCard = self === 'player' ? b.playerCard : b.cpuCard;
  const oppCard  = self === 'player' ? b.cpuCard    : b.playerCard;
  const selfHD   = self === 'player' ? PM.playerHD  : PM.cpuHD;
  const oppHD    = self === 'player' ? PM.cpuHD     : PM.playerHD;
  const selfSubstituted = self === 'player' ? PM.playerSubstituted : PM.cpuSubstituted;
  const selfHand = self === 'player' ? PM.playerPlayHand : PM.cpuPlayPool;
  const selfDiscard = self === 'player' ? PM.playerDiscard : [];
  const selfHeroDeck = self === 'player' ? PM.playerHeroDeck : PM.cpuHeroDeck;
  const selfBench = self === 'player' ? PM.playerBench : PM.cpuBench;

  // Battle history (closed battles only)
  let selfWon = 0, selfLost = 0, selfTied = 0;
  for (let i = 0; i < PM.currentBattle; i++) {
    const r = PM.battles[i].result;
    if (!r) continue;
    const won = (self === 'player' && r === 'win') || (self === 'cpu' && r === 'lose');
    const lost = (self === 'player' && r === 'lose') || (self === 'cpu' && r === 'win');
    if (won) selfWon++; else if (lost) selfLost++; else if (r === 'tie') selfTied++;
  }

  // Plays used this battle (by side)
  const playsUsedThisBattle = self === 'player'
    ? (b.playerPlaysPlayed || []).length
    : (b.cpuPlaysPlayed || b.cpuPlaysRan || []).length; // practice.js uses playerPlaysPlayed; CPU tracked differently

  return {
    self, opp, selfCard, oppCard, selfHD, oppHD, selfSubstituted,
    selfHand, selfDiscard, selfHeroDeck, selfBench,
    selfWon, selfLost, selfTied,
    playsUsedThisBattle,
    battleIdx: PM.currentBattle,
    battlesRemaining: 7 - PM.currentBattle,
    honors: PM.honors,
    // B.1 — snapshot in-scope weapon transforms; pmEvalCondition
    // (and any other ctx-driven weapon read) routes through these.
    weaponTransforms: (PM._weaponTransforms || [])
      .filter(t => pmIsScopeActive(t.scope, t.installedAt, PM.currentBattle))
      .map(t => ({ owner: t.owner, target: t.target, to: t.to, from: t.from || null })),
  };
}

// Evaluate a formula or int delta. Returns an integer.
function pmEvalFormula(val, ctx) {
  if (typeof val === 'number') return val | 0;
  if (val == null) return 0;
  if (typeof val === 'object') {
    if ('value' in val) return val.value | 0;
    // B.3 — recognize nested {formula, left, right} for binary
    // operators, plus the {formula: "multiply", factor, metric}
    // shorthand. Also accepts metric being a nested {type, ...}
    // dict instead of a bare string.
    if (val.formula) {
      switch (val.formula) {
        case 'min': return Math.min(pmEvalFormula(val.left, ctx), pmEvalFormula(val.right, ctx)) | 0;
        case 'max': return Math.max(pmEvalFormula(val.left, ctx), pmEvalFormula(val.right, ctx)) | 0;
        case 'add': return (pmEvalFormula(val.left, ctx) + pmEvalFormula(val.right, ctx)) | 0;
        case 'sub': return (pmEvalFormula(val.left, ctx) - pmEvalFormula(val.right, ctx)) | 0;
        case 'multiply':
          if (val.factor != null || val.metric != null) {
            const f = val.factor != null ? val.factor : 1;
            const m = pmEvalMetricAny(val.metric, val, ctx);
            const off = val.offset || 0;
            let r = f * m + off;
            if (val.min != null) r = Math.max(val.min, r);
            if (val.max != null) r = Math.min(val.max, r);
            return r | 0;
          }
          return (pmEvalFormula(val.left, ctx) * pmEvalFormula(val.right, ctx)) | 0;
        default: return 0;
      }
    }
    const factor = val.factor != null ? val.factor : 1;
    const offset = val.offset || 0;
    const m = pmEvalMetricAny(val.metric, val, ctx);
    let result = factor * m + offset;
    if (val.min != null) result = Math.max(val.min, result);
    if (val.max != null) result = Math.min(val.max, result);
    return result | 0;
  }
  return 0;
}

// Accepts metric as a string OR a nested {type, ...} dict.
function pmEvalMetricAny(val, args, ctx) {
  if (typeof val === 'string') return pmEvalMetric(val, args, ctx);
  if (val && typeof val === 'object') return pmEvalMetric(val.type, val, ctx);
  return 0;
}

function pmEvalMetric(metric, args, ctx) {
  if (!metric) return 0;
  const target = (args && args.target) || 'self';
  // Resolve opponent's plays from PM.battles[currentBattle] rather
  // than the previously-hardcoded 0 — formula deltas like
  // Overcommited's "-5 per opp play" silently computed to 0 before.
  const slot = (PM && Array.isArray(PM.battles))
    ? PM.battles[PM.currentBattle]
    : null;
  const oppSide = ctx.self === 'player' ? 'cpu' : 'player';
  const oppPlays = slot
    ? (oppSide === 'player'
        ? (slot.playerPlaysPlayed || [])
        : (slot.cpuPlaysPlayed || []))
    : [];
  const bound = target === 'self' ? ctx : { // minimal opp context
    selfWon: ctx.selfLost, selfLost: ctx.selfWon, selfTied: ctx.selfTied,
    selfCard: ctx.oppCard, selfHD: ctx.oppHD, selfHand: [], selfDiscard: [],
    playsUsedThisBattle: oppPlays.length,
  };
  switch (metric) {
    case 'plays_used_this_battle': return bound.playsUsedThisBattle || 0;
    case 'plays_used_total': return 0; // not tracked
    case 'heroes_used_total': {
      const weapon = args.weapon;
      const battles = (PM && Array.isArray(PM.battles)) ? PM.battles : [];
      // count of revealed heroes for `target` up through current battle
      let n = 0;
      const heroSide = target === 'self' ? ctx.self : ctx.opp;
      const txfm = ctx.weaponTransforms || [];
      for (let i = 0; i <= ctx.battleIdx; i++) {
        const b = battles[i]; if (!b) continue;
        const card = heroSide === 'player' ? b.playerCard : b.cpuCard;
        if (!card) continue;
        if (weapon && pmResolveWeapon(card, heroSide, txfm) !== weapon) continue;
        n++;
      }
      return n;
    }
    case 'heroes_revealed_total': return ctx.battleIdx + 1;
    case 'battles_won': return bound.selfWon || 0;
    case 'battles_lost': return bound.selfLost || 0;
    case 'battles_tied': return bound.selfTied || 0;
    case 'battles_remaining': return ctx.battlesRemaining;
    case 'hd_count': return bound.selfHD || 0;
    case 'hand_count': return (bound.selfHand || []).length;
    case 'discard_count': {
      const kind = args.kind;
      const pile = bound.selfDiscard || [];
      if (!kind) return pile.length;
      if (kind === 'hero') return pile.filter(c => c.cardType === 'Hero').length;
      if (kind === 'play') return pile.filter(c => c.cardType === 'Play').length;
      if (kind === 'hot_dog') return pile.filter(c => c.cardType === 'HotDog').length;
      return pile.length;
    }
    case 'revealed_hero_power':
    case 'current_power':
    case 'starting_power':
      return bound.selfCard?.power || 0;
    case 'drawn_hero_power': {
      const deck = ctx.selfHeroDeck || [];
      return deck[0]?.power || 0;
    }
    case 'drawn_play_cost':
    case 'revealed_play_cost':
      return (bound.selfHand || [])[0]?.playCost || 0;
    case 'chosen_play_cost': {
      // Returns the cost of the play just chosen by an
      // add_chosen_revealed_to_hand_discard_rest op IN THIS execution
      // (Power Pick et al.). Falls back to "max cost in hand" when no
      // chooser ran in this exec call.
      if (typeof ctx._chosenPlayCost === 'number') return ctx._chosenPlayCost;
      const hand = bound.selfHand || [];
      return hand.reduce((m, c) => Math.max(m, c?.playCost || 0), 0);
    }
    case 'discard_pile_heroes': {
      const pile = bound.selfDiscard || [];
      return pile.filter(c => c.cardType === 'Hero').length;
    }
    case 'discard_pile_heroes_weapon_match': {
      const pile = bound.selfDiscard || [];
      const activeSide = target === 'self' ? ctx.self : ctx.opp;
      const txfm = ctx.weaponTransforms || [];
      const activeW = pmResolveWeapon(ctx.selfCard, activeSide, txfm);
      if (!activeW) return 0;
      return pile.filter(c => c.cardType === 'Hero' && pmResolveWeapon(c, activeSide, txfm) === activeW).length;
    }
    case 'discard_pile_count_excluding_hd': {
      const pile = bound.selfDiscard || [];
      return pile.filter(c => c.cardType !== 'HotDog').length;
    }
    case 'distinct_weapons_revealed': {
      const weapons = new Set();
      const txfm = ctx.weaponTransforms || [];
      for (let i = 0; i <= ctx.battleIdx; i++) {
        const b = PM.battles[i]; if (!b) continue;
        const pw = pmResolveWeapon(b.playerCard, 'player', txfm);
        const cw = pmResolveWeapon(b.cpuCard,    'cpu',    txfm);
        if (pw) weapons.add(pw);
        if (cw) weapons.add(cw);
      }
      return weapons.size;
    }
    case 'battles_lost_streak': {
      let streak = 0, i = ctx.battleIdx - 1;
      while (i >= 0) {
        const slot = PM.battles[i]; if (!slot) break;
        const isLost = (ctx.self === 'player' && slot.result === 'lose') || (ctx.self === 'cpu' && slot.result === 'win');
        if (isLost) { streak++; i--; } else break;
      }
      return streak;
    }
    case 'hd_count_before_cost':
      return bound.selfHD || 0;
    case 'hd_discarded_this_battle':
      return Math.max(0, 10 - (bound.selfHD || 0));
    case 'opponent_hd_used_this_battle':
      return Math.max(0, 10 - (ctx.oppHD || 0));
    case 'cards_discarded_by_this_play':
      // Set by discard/discard_hand_all during the same execution pass.
      return ctx._discardedByThisPlay || 0;
    case 'plays_in_hand_before_shuffle':
      return (bound.selfHand || []).length;
    case 'discarded_plays_cost_gte': {
      const pile = bound.selfDiscard || [];
      const minCost = args.min_cost || args.offset || 3;
      return pile.filter(c => c.cardType === 'Play' && (c.playCost || 0) >= minCost).length;
    }
    default: return 0;
  }
}

function pmEvalCondition(cond, ctx) {
  if (!cond) return true;
  const target = cond.target || 'self';
  const selfView = target === 'self';
  const card = selfView ? ctx.selfCard : ctx.oppCard;
  // B.1 — every weapon read routes through pmResolveWeapon so any
  // active persistent_weapon_transform changes what the rules engine
  // evaluates as the hero's weapon. controllerOf returns the side
  // that owns a card so transforms with target:"self"/"opponent"
  // gate correctly.
  const transforms = ctx.weaponTransforms || [];
  const selfSide = ctx.self;
  const oppSide  = ctx.opp;
  const wpn = (c, controller) => pmResolveWeapon(c, controller, transforms);

  switch (cond.type) {
    case 'weapon':
      return card && wpn(card, selfView ? selfSide : oppSide) === cond.weapon;
    case 'weapon_same': {
      if (cond.between === 'self_opp') {
        return wpn(ctx.selfCard, selfSide) === wpn(ctx.oppCard, oppSide);
      }
      return false; // self_prev variants not tracked
    }
    case 'weapon_different': {
      if (cond.between === 'self_opp') {
        return wpn(ctx.selfCard, selfSide) !== wpn(ctx.oppCard, oppSide);
      }
      return false;
    }
    case 'hd_count': {
      const v = selfView ? ctx.selfHD : ctx.oppHD;
      return pmCmp(v, cond.comparison, cond.value);
    }
    case 'hand_count': {
      const v = selfView ? (ctx.selfHand || []).length : 0;
      return pmCmp(v, cond.comparison, cond.value);
    }
    case 'discard_count': {
      const pile = selfView ? (ctx.selfDiscard || []) : [];
      let v;
      if (cond.kind === 'hero') v = pile.filter(c => c.cardType === 'Hero').length;
      else if (cond.kind === 'play') v = pile.filter(c => c.cardType === 'Play').length;
      else if (cond.kind === 'hot_dog') v = pile.filter(c => c.cardType === 'HotDog').length;
      else v = pile.length;
      return pmCmp(v, cond.comparison, cond.value);
    }
    case 'power_threshold': {
      const p = (card?.power || 0);
      return pmCmp(p, cond.comparison, cond.value);
    }
    case 'battle_num':
      return pmCmp(ctx.battleIdx + 1, cond.comparison, cond.value);
    case 'battles_won':
      return pmCmp(selfView ? ctx.selfWon : ctx.selfLost, cond.comparison, cond.value);
    case 'battles_lost':
      return pmCmp(selfView ? ctx.selfLost : ctx.selfWon, cond.comparison, cond.value);
    case 'battle_tied':
      return (ctx.selfCard?.power || 0) + (PM.battles[ctx.battleIdx]?.playerEffectPower || 0) ===
             (ctx.oppCard?.power || 0) + (PM.battles[ctx.battleIdx]?.cpuEffectPower || 0);
    case 'battle_winning': {
      const pp = (ctx.selfCard?.power || 0);
      const cp = (ctx.oppCard?.power || 0);
      return pp > cp;
    }
    case 'battle_losing': {
      const pp = (ctx.selfCard?.power || 0);
      const cp = (ctx.oppCard?.power || 0);
      return pp < cp;
    }
    case 'prev_battle': {
      if (ctx.battleIdx === 0) return false;
      const r = PM.battles[ctx.battleIdx - 1]?.result;
      const wantWon = cond.result === 'won';
      const wantLost = cond.result === 'lost';
      const wantTied = cond.result === 'tied';
      const won = (ctx.self === 'player' && r === 'win') || (ctx.self === 'cpu' && r === 'lose');
      const lost = (ctx.self === 'player' && r === 'lose') || (ctx.self === 'cpu' && r === 'win');
      if (wantWon) return won;
      if (wantLost) return lost;
      if (wantTied) return r === 'tie';
      return false;
    }
    case 'substituted_this_battle':
      return selfView ? ctx.selfSubstituted : false;
    case 'honors':
      return ctx.honors === ctx.self;
    case 'hero_name': {
      const want = cond.equals;
      return (card?.name === want) || (card?.hero === want);
    }
    case 'metric_compare': {
      const l = pmEvalFormula(cond.left, ctx);
      const r = pmEvalFormula(cond.right, ctx);
      return pmCmp(l, cond.comparison, r);
    }
    case 'plays_used': {
      // Honor `scope`. Default "this_battle" matches legacy entries.
      // No Huddle ("If you ran a Play in the previous Battle…") sets
      // scope: "prev_battle" — without that the condition trivially
      // checks THIS battle's count and fires every battle.
      const scope = cond.scope || 'this_battle';
      const target = cond.target || 'self';
      const selfView = target === 'self';
      let count = 0;
      if (scope === 'prev_battle') {
        if (ctx.battleIdx === 0) return false;
        const prev = PM.battles[ctx.battleIdx - 1];
        if (!prev) return false;
        const plays = selfView
          ? (ctx.self === 'player' ? (prev.playerPlaysPlayed || []) : (prev.cpuPlaysPlayed || []))
          : (ctx.self === 'player' ? (prev.cpuPlaysPlayed || []) : (prev.playerPlaysPlayed || []));
        count = plays.length;
      } else {
        count = selfView ? (ctx.playsUsedThisBattle || 0) : 0;
      }
      return pmCmp(count, cond.comparison, cond.value);
    }
    case 'weapon_streak': {
      const length = cond.length || 2;
      const ref = cond.weapon_ref || 'current_hero';
      let refWeapon = null;
      if (ref === 'current_hero') {
        const c = selfView ? ctx.selfCard : ctx.oppCard;
        refWeapon = wpn(c, selfView ? selfSide : oppSide);
      }
      if (!refWeapon) return false;
      const heroSide = selfView ? selfSide : oppSide;
      let matched = 0, i = ctx.battleIdx - 1;
      while (i >= 0 && matched < length) {
        const slot = PM.battles[i]; if (!slot) break;
        const hero = heroSide === 'player' ? slot.playerCard : slot.cpuCard;
        if (wpn(hero, heroSide) === refWeapon) matched++; else break;
        i--;
      }
      return matched >= length;
    }
    case 'previous_two_heroes_share_weapon': {
      if (ctx.battleIdx < 2) return false;
      const b1 = PM.battles[ctx.battleIdx - 1], b2 = PM.battles[ctx.battleIdx - 2];
      const heroSide = selfView ? selfSide : oppSide;
      const h1 = heroSide === 'player' ? b1.playerCard : b1.cpuCard;
      const h2 = heroSide === 'player' ? b2.playerCard : b2.cpuCard;
      const w1 = wpn(h1, heroSide), w2 = wpn(h2, heroSide);
      return !!w1 && w1 === w2;
    }
    case 'previous_and_current_share_weapon': {
      if (ctx.battleIdx < 1) return false;
      const prev = PM.battles[ctx.battleIdx - 1];
      const heroSide = selfView ? selfSide : oppSide;
      const prevHero = heroSide === 'player' ? prev.playerCard : prev.cpuCard;
      const curW = wpn(ctx.selfCard, heroSide);
      const prevW = wpn(prevHero, heroSide);
      return !!curW && curW === prevW;
    }
    case 'opponent_played_weapon_match': {
      const ref = cond.weapon_ref || 'self_current_hero';
      const selfW = wpn(ctx.selfCard, selfSide);
      const refWeapon = ref === 'self_current_hero' ? (selfW || null) : null;
      if (!refWeapon) return false;
      const b = PM.battles[ctx.battleIdx]; if (!b) return false;
      const oppPlays = ctx.self === 'player' ? (b.cpuPlaysPlayed || b.cpuPlaysRan || []) : (b.playerPlaysPlayed || []);
      // Play cards have no transform — element is stable.
      return oppPlays.some(p => p?.element === refWeapon);
    }
    case 'next_hero_power_gt': {
      const side = target === 'opponent' ? ctx.opp : ctx.self;
      const slot = PM.battles[ctx.battleIdx + 1]; if (!slot) return false;
      const c = side === 'player' ? slot.playerCard : slot.cpuCard;
      return (c?.power || 0) > (cond.value || 0);
    }
    case 'next_hero_weapon_equals': {
      const side = target === 'opponent' ? ctx.opp : ctx.self;
      const slot = PM.battles[ctx.battleIdx + 1]; if (!slot) return false;
      const c = side === 'player' ? slot.playerCard : slot.cpuCard;
      if (cond.weapon === 'player_named') return true;
      return wpn(c, side) === cond.weapon;
    }
    case 'hd_count_compare': {
      switch (cond.comparison) {
        case 'opp_gt_self': return ctx.oppHD > ctx.selfHD;
        case 'self_gt_opp': return ctx.selfHD > ctx.oppHD;
        case 'opp_lt_self': return ctx.oppHD < ctx.selfHD;
        case 'self_lt_opp': return ctx.selfHD < ctx.oppHD;
        case 'eq': return ctx.selfHD === ctx.oppHD;
        default: return false;
      }
    }
    case 'hand_count_compare': {
      const sc = (ctx.selfHand || []).length;
      switch (cond.comparison) {
        case 'opp_gt_self': return 0 > sc;
        case 'self_gt_opp': return sc > 0;
        default: return false;
      }
    }
    case 'discarded_hero_weapon_matches_active': {
      const pile = selfView ? (ctx.selfDiscard || []) : [];
      const activeSide = selfView ? selfSide : oppSide;
      const activeW = wpn(ctx.selfCard, activeSide);
      if (!activeW) return false;
      return pile.some(c => c?.cardType === 'Hero' && wpn(c, activeSide) === activeW);
    }
    case 'battle_won_nth': {
      const n = cond.n || 1;
      const slot = PM.battles[n - 1]; if (!slot || !slot.result) return false;
      return (ctx.self === 'player' && slot.result === 'win') || (ctx.self === 'cpu' && slot.result === 'lose');
    }
    case 'battles_won_streak': {
      let streak = 0, i = ctx.battleIdx - 1;
      while (i >= 0) {
        const slot = PM.battles[i]; if (!slot) break;
        const won = (ctx.self === 'player' && slot.result === 'win') || (ctx.self === 'cpu' && slot.result === 'lose');
        if (won) { streak++; i--; } else break;
      }
      return pmCmp(streak, cond.comparison, cond.value);
    }
    case 'battles_lost_first_n': {
      const n = cond.n || 1;
      let lost = 0;
      for (let i = 0; i < Math.min(n, ctx.battleIdx); i++) {
        const slot = PM.battles[i]; if (!slot) break;
        const isLost = (ctx.self === 'player' && slot.result === 'lose') || (ctx.self === 'cpu' && slot.result === 'win');
        if (isLost) lost++;
      }
      return lost >= n;
    }
    case 'all':
      return (cond.of || []).every(c => pmEvalCondition(c, ctx));
    case 'any':
      return (cond.of || []).some(c => pmEvalCondition(c, ctx));
    case 'not':
      return !pmEvalCondition(cond.cond, ctx);
    default:
      return false; // unknown condition fails closed; branch 'else' still runs
  }
}

function pmCmp(v, comparison, target) {
  switch (comparison) {
    case 'gte': return v >= target;
    case 'gt':  return v >  target;
    case 'lte': return v <= target;
    case 'lt':  return v <  target;
    case 'eq':  return v === target;
    case 'neq': return v !== target;
    default:    return false;
  }
}

// Describe a child persistent that's about to be installed via the
// `install_persistent` op. Used to make win/start callouts read like
// real cause-and-effect: "Armed: Your Hero +5 next battle" instead of
// the generic "Installed follow-up effect."
function pmDescribeArmedFollowUp(spec, ownerSide) {
  if (!spec || typeof spec !== 'object') return 'follow-up effect';
  const scope = spec.scope || '';
  let scopeText = '';
  switch (scope) {
    case 'next_battle':    scopeText = ' next battle'; break;
    case 'this_battle':    scopeText = ' this battle'; break;
    case 'this_and_next':  scopeText = ' for two battles'; break;
    case 'next_2_battles': scopeText = ' for the next 2 battles'; break;
    case 'rest_of_game':   scopeText = ' rest of game'; break;
    default: scopeText = scope ? ' (' + scope + ')' : '';
  }
  const eff = spec.effect;
  if (!eff || !eff.op) return 'follow-up' + scopeText;
  const isOpp = eff.target === 'opponent';
  let recipient;
  if (ownerSide === 'player') recipient = isOpp ? 'CPU Hero' : 'Your Hero';
  else                         recipient = isOpp ? 'Your Hero' : 'CPU Hero';
  switch (eff.op) {
    case 'power': {
      const d = (typeof eff.delta === 'number') ? eff.delta : 0;
      const sign = d >= 0 ? '+' : '';
      return recipient + ' ' + sign + d + scopeText;
    }
    case 'hd_recover': {
      const amt = (typeof eff.amount === 'number') ? eff.amount : 0;
      const owner = ownerSide === 'player' ? 'Your' : 'CPU';
      return owner + ' +' + amt + ' HD' + scopeText;
    }
    case 'block_sub':   return 'block substitutions' + scopeText;
    case 'block_plays': return 'block plays' + scopeText;
    default:            return 'follow-up effect' + scopeText;
  }
}

// Execute a single step (op, branch, or choice). Mutates `out`.
function pmExecStep(step, ctx, out) {
  if (!step) return;
  // Branch: { if, then, else }
  if (step.if) {
    const pass = pmEvalCondition(step.if, ctx);
    const branch = pass ? step.then : step.else;
    if (branch) for (const s of branch) pmExecStep(s, ctx, out);
    return;
  }
  // Choice: { choice: [...], options: [...] } — pick option with highest estimated self power
  if (step.choice || step.options) {
    const opts = step.options || step.choice;
    if (!opts || !opts.length) return;
    let best = opts[0], bestScore = -Infinity;
    for (const o of opts) {
      const probe = { selfDelta: 0, oppDelta: 0, selfHDDelta: 0, oppHDDelta: 0, draws: 0, discards: 0, hasEffect: false, unknownOps: [], notifications: [] };
      for (const s of (o.effects || [])) pmExecStep(s, ctx, probe);
      const score = probe.selfDelta - probe.oppDelta + probe.selfHDDelta * 5;
      if (score > bestScore) { best = o; bestScore = score; }
    }
    for (const s of (best.effects || [])) pmExecStep(s, ctx, out);
    if (best.label) out.notifications.push(`Chose: ${best.label}`);
    return;
  }
  const op = step.op;
  if (!op) return;

  switch (op) {
    case 'power': {
      const d = pmEvalFormula(step.delta, ctx);
      if (step.target === 'opponent') out.oppDelta += d;
      else out.selfDelta += d;
      out.hasEffect = true;
      break;
    }
    case 'power_set': {
      const card = step.target === 'opponent' ? ctx.oppCard : ctx.selfCard;
      const current = card?.power || 0;
      let val = 0;
      if (step.source && 'value' in step.source) val = step.source.value;
      else if (step.source) {
        const src = step.source.target === 'opponent' ? ctx.oppCard : ctx.selfCard;
        val = src?.power || 0;
      }
      val += (step.offset || 0);
      const delta = val - current;
      if (step.target === 'opponent') out.oppDelta += delta;
      else out.selfDelta += delta;
      out.hasEffect = true;
      break;
    }
    case 'power_swap': {
      const myP = ctx.selfCard?.power || 0;
      const thP = ctx.oppCard?.power || 0;
      out.selfDelta += thP - myP;
      out.oppDelta  += myP - thP;
      out.hasEffect = true;
      break;
    }
    case 'power_double': {
      const card = step.target === 'opponent' ? ctx.oppCard : ctx.selfCard;
      const bonus = card?.power || 0;
      if (step.target === 'opponent') out.oppDelta += bonus;
      else out.selfDelta += bonus;
      out.hasEffect = true;
      break;
    }
    case 'power_steal': {
      const amt = pmEvalFormula(step.amount, ctx);
      out.selfDelta += amt;
      out.oppDelta  -= amt;
      out.hasEffect = true;
      break;
    }
    case 'power_cap_min': {
      // approximate as small protective bonus
      if (step.target !== 'opponent') out.selfDelta += 0; // pure floor — skip math, but record protection
      out.protectSelf = true;
      out.hasEffect = true;
      break;
    }
    case 'hd': {
      const d = pmEvalFormula(step.delta, ctx);
      if (step.target === 'opponent') out.oppHDDelta += d;
      else out.selfHDDelta += d;
      out.hasEffect = true;
      break;
    }
    case 'hd_recover': {
      // B.9 — `amount: "all"` recovers everything possible (clamped
      // by applyHDRecover at 10).
      const amt = (step.amount === 'all') ? 10 : pmEvalFormula(step.amount, ctx);
      if (step.target === 'opponent') out.oppHDDelta += amt;
      else out.selfHDDelta += amt;
      out.hasEffect = true;
      break;
    }
    case 'draw': {
      const n = pmEvalFormula(step.count, ctx);
      if (step.kind === 'hero') out.heroDraws = (out.heroDraws || 0) + n;
      else out.draws = (out.draws || 0) + n;
      out.hasEffect = true;
      break;
    }
    case 'discard': {
      const n = step.count === 'all' ? 99 : pmEvalFormula(step.count, ctx);
      out.discards = (out.discards || 0) + n;
      // Track for cards_discarded_by_this_play metric
      ctx._discardedByThisPlay = (ctx._discardedByThisPlay || 0) + n;
      out.hasEffect = true;
      break;
    }
    case 'coin_flip': {
      // Mark this exec as having rolled — host fires on_dice_roll
      // afterwards so persistents like Pay The Price fire only when
      // a roll actually happens (not every battle).
      out.firedDiceOrCoin = true;
      const times = step.times || 1;
      const results = []; // true = heads
      for (let i = 0; i < times; i++) results.push(Math.random() < 0.5);
      const heads = results.filter(Boolean).length;
      const tails = times - heads;
      // Simple heads/tails branches
      if (step.heads && heads > 0) for (let i = 0; i < heads; i++) for (const s of step.heads) pmExecStep(s, ctx, out);
      if (step.tails && tails > 0) for (let i = 0; i < tails; i++) for (const s of step.tails) pmExecStep(s, ctx, out);
      // Aggregate branches
      if (step.branches) {
        for (const br of step.branches) {
          const ag = br.aggregate;
          let fire = false, repeats = 1;
          if (ag === 'all_heads') fire = heads === times;
          else if (ag === 'all_tails') fire = tails === times;
          else if (ag === 'at_least_n_heads') fire = heads >= (br.n || step.n || 1);
          else if (ag === 'at_least_n_tails') fire = tails >= (br.n || step.n || 1);
          else if (ag === 'exact_heads') fire = heads === (br.n || step.n || 0);
          else if (ag === 'per_head') { fire = heads > 0; repeats = heads; }
          else if (ag === 'per_tail') { fire = tails > 0; repeats = tails; }
          else if (!ag && br.on) { fire = br.on.includes(heads) || br.on === 'else'; }
          if (fire && br.then) for (let r = 0; r < repeats; r++) for (const s of br.then) pmExecStep(s, ctx, out);
        }
      }
      // Aggregate on the op itself (then/else form)
      if (step.aggregate && (step.then || step.else)) {
        const ag = step.aggregate; let fire = false;
        if (ag === 'all_heads') fire = heads === times;
        else if (ag === 'all_tails') fire = tails === times;
        else if (ag === 'at_least_n_heads') fire = heads >= (step.n || 1);
        else if (ag === 'at_least_n_tails') fire = tails >= (step.n || 1);
        else if (ag === 'exact_heads') fire = heads === (step.n || 0);
        const branch = fire ? step.then : step.else;
        if (branch) for (const s of branch) pmExecStep(s, ctx, out);
      }
      // Visual reveal — emoji + sequence so the user sees WHICH faces
      // came up, not just the aggregate count.
      const faces = results.map(h => h ? 'HEADS' : 'TAILS');
      const glyphs = '🪙'.repeat(results.length);
      out.notifications.push(`${glyphs} ${faces.join(' · ')}`);
      // Surface the per-flip outcomes so the dice/coin reveal overlay
      // can animate the result. Mirrors iOS RevealState.coinFlips.
      out.coinFlips = (out.coinFlips || []).concat(faces);
      out.hasEffect = true;
      break;
    }
    case 'dice_roll': {
      out.firedDiceOrCoin = true;
      const count = step.count || 1;
      const rolls = [];
      for (let i = 0; i < count; i++) rolls.push(Math.floor(Math.random() * 6) + 1);
      const agg = step.aggregate || (count > 1 ? 'sum' : null);
      const sum = rolls.reduce((a, b) => a + b, 0);
      const matchValue = agg === 'sum' ? sum : rolls[0];
      let matched = false;
      let elseFiredAndEmpty = false;
      if (step.branches) {
        let elseBranch = null;
        for (const br of step.branches) {
          if (br.on === 'else') { elseBranch = br; continue; }
          if (Array.isArray(br.on) && br.on.includes(matchValue)) {
            matched = true;
            if (br.then) for (const s of br.then) pmExecStep(s, ctx, out);
          }
        }
        if (!matched && elseBranch && elseBranch.then) {
          if (!elseBranch.then.length) elseFiredAndEmpty = true;
          for (const s of elseBranch.then) pmExecStep(s, ctx, out);
        } else if (!matched) {
          elseFiredAndEmpty = true;
        }
      }
      if (step.on_match || step.on_miss) {
        // player_pick form — CPU / automated pick: pick the face that maximizes power
        const branch = Math.random() < 1 / 6 ? step.on_match : step.on_miss;
        if (branch) for (const s of branch) pmExecStep(s, ctx, out);
      }
      // Visual reveal — die-face glyph per roll so the user sees the
      // actual values, not just the aggregate.
      const dieFaces = ['⚀','⚁','⚂','⚃','⚄','⚅'];
      const pretty = rolls.map(r => (r >= 1 && r <= 6) ? `${dieFaces[r-1]} ${r}` : String(r));
      out.notifications.push(rolls.length > 1
        ? `🎲 ${pretty.join(' · ')} (sum ${sum})`
        : `🎲 ${pretty[0]}`);
      out.diceRolls = (out.diceRolls || []).concat(rolls);
      // Surface a clear "no power added" callout when the roll missed
      // and the else branch was empty/absent. Without this, the user
      // sees the dice glyph and wonders why nothing happened (Fire
      // Roll / Ice Roll / etc. failed-roll case).
      if (elseFiredAndEmpty) {
        out.notifications.push("Roll didn't trigger any effect");
      }
      out.hasEffect = true;
      break;
    }
    case 'protect_self':
      out.protectSelf = true;
      out.hasEffect = true;
      break;
    case 'cancel_opponent_plays': {
      const oppSide = ctx.self === 'player' ? 'cpu' : 'player';
      const scope = step.scope || 'this_battle';
      PM._blocks = PM._blocks || { player: [], cpu: [] };
      PM._blocks[oppSide].push({ kind: 'block_plays', scope, installedAt: PM.currentBattle });
      out.notifications.push(`Opponent can't play any Plays ${scope.replace(/_/g, ' ')}`);
      out.hasEffect = true;
      break;
    }
    case 'cap_opponent_plays': {
      // Soft cap: opponent allowed up to `max` plays this battle.
      // Falls back to a full block when max is missing or 0. Counter
      // is checked + decremented in cpuDoPlay before each play.
      const oppSide = ctx.self === 'player' ? 'cpu' : 'player';
      const scope = step.scope || 'this_battle';
      const maxPlays = (typeof step.max === 'number') ? step.max : 0;
      if (maxPlays <= 0) {
        PM._blocks = PM._blocks || { player: [], cpu: [] };
        PM._blocks[oppSide].push({ kind: 'block_plays', scope, installedAt: PM.currentBattle });
        out.notifications.push(`Opponent can't play any Plays ${scope.replace(/_/g, ' ')}`);
      } else {
        if (oppSide === 'player') PM._playerPlayCapThisBattle = maxPlays;
        else                      PM._cpuPlayCapThisBattle    = maxPlays;
        out.notifications.push(`Opponent capped at ${maxPlays} play${maxPlays === 1 ? '' : 's'} ${scope.replace(/_/g, ' ')}`);
      }
      out.hasEffect = true;
      break;
    }
    case 'block_sub':
    case 'block_draw':
    case 'block_hd_recover':
    case 'block_plays': {
      const scope = step.scope || step.duration || 'this_battle';
      const targetStr = step.target || 'self';
      PM._blocks = PM._blocks || { player: [], cpu: [] };
      // Verb-phrase notification text — the legacy
      // `op.replace('_', ' ')` produced "block plays" which read as
      // broken grammar. Sentence form tells the user what's prevented.
      const phraseFor = {
        block_plays:      'play any Plays this battle',
        block_draw:       'draw new Plays this battle',
        block_sub:        'substitute this battle',
        block_hd_recover: 'recover Hot Dogs',
      };
      const actionPhrase = phraseFor[op] || op.replace(/_/g, ' ');
      if (targetStr === 'both') {
        PM._blocks.player.push({ kind: op, scope, installedAt: PM.currentBattle });
        PM._blocks.cpu.push(   { kind: op, scope, installedAt: PM.currentBattle });
        out.notifications.push(`Neither side can ${actionPhrase}`);
      } else {
        const targetSide = targetStr === 'opponent' ? ctx.opp : ctx.self;
        PM._blocks[targetSide].push({ kind: op, scope, installedAt: PM.currentBattle });
        const who = targetSide === ctx.self ? 'You' : 'Opponent';
        out.notifications.push(`${who} can't ${actionPhrase}`);
      }
      out.hasEffect = true;
      break;
    }
    case 'honors_set': {
      const targetSide = (step.target === 'opponent') ? ctx.opp : ctx.self;
      const scope = step.scope || 'next_battle';
      PM._pendingHonors = { side: targetSide, scope, installedAt: PM.currentBattle };
      out.notifications.push(`Honors → ${targetSide === 'player' ? 'Player' : 'CPU'} (${scope})`);
      out.hasEffect = true;
      break;
    }
    case 'substitute_free': {
      const targetSide = (step.target === 'opponent') ? ctx.opp : ctx.self;
      const scope = step.scope || 'next_battle';
      PM._freeSub = PM._freeSub || {};
      PM._freeSub[targetSide] = { scope, installedAt: PM.currentBattle };
      out.notifications.push(`Free substitute (${scope})`);
      out.hasEffect = true;
      break;
    }
    case 'force_substitute': {
      const targetSide = (step.target === 'opponent') ? ctx.opp : ctx.self;
      const cost = step.cost != null ? step.cost : 2;
      // Force: deduct HD now, swap active with best bench immediately
      if (targetSide === 'player') PM.playerHD = Math.max(0, PM.playerHD - cost);
      else PM.cpuHD = Math.max(0, PM.cpuHD - cost);
      pmIntentSwapActiveWithHand(targetSide);
      out.notifications.push(`Forced substitute (${cost} HD)`);
      out.hasEffect = true;
      break;
    }
    case 'variable_cost_bonus': {
      // Player chooses X extra HDs; self +factor*X. Auto-spend remaining HD up to reasonable cap.
      const factor = step.factor || step.per_hd || 5;
      const available = Math.max(0, ctx.selfHD);
      const spend = Math.min(available, 3); // auto heuristic: spend up to 3
      if (spend > 0) {
        out.selfHDDelta -= spend;
        out.selfDelta += factor * spend;
      }
      out.hasEffect = true;
      break;
    }
    case 'add_previous_hero_delta': {
      if (ctx.battleIdx > 0) {
        const prev = PM.battles[ctx.battleIdx - 1];
        const bonus = ctx.self === 'player' ? (prev.playerEffectPower || 0) : (prev.cpuEffectPower || 0);
        if (step.target === 'opponent') out.oppDelta += bonus;
        else out.selfDelta += bonus;
      }
      out.hasEffect = true;
      break;
    }
    case 'note':
      // Intentionally no mechanical effect
      break;

    // ── Tier A ops (simple state mutations) ────────────────────
    case 'swap_hd_counts': {
      // Swap self and opp HD counts; delta representation keeps runtime clamping correct
      out.selfHDDelta += (ctx.oppHD - ctx.selfHD);
      out.oppHDDelta  += (ctx.selfHD - ctx.oppHD);
      out.hasEffect = true;
      break;
    }
    case 'play_cost_delta': {
      if (!PM._playCostMods) PM._playCostMods = { player: [], cpu: [] };
      const targetSide = (step.target === 'opponent') ? ctx.opp : ctx.self;
      PM._playCostMods[targetSide].push({
        delta: step.delta || 0,
        scope: step.scope || 'next_play_self',
        installedAt: (typeof PM.currentBattle === 'number') ? PM.currentBattle : 0
      });
      out.hasEffect = true;
      break;
    }
    case 'shuffle_hand_into_deck': {
      // Player side only; CPU uses a unified pool with no hand/deck split
      const targets = step.target === 'both' ? ['self','opponent'] : [step.target || 'self'];
      for (const t of targets) {
        const side = t === 'self' ? ctx.self : ctx.opp;
        if (side === 'player' && (step.kind || 'play') === 'play') {
          const n = PM.playerPlayHand.length;
          out.playsInHandBeforeShuffle = n;
          PM.playerPlayDeck.push(...PM.playerPlayHand);
          PM.playerPlayDeck = shuffle(PM.playerPlayDeck);
          PM.playerPlayHand = [];
          if (n > 0) out.notifications.push(`Shuffled ${n} play${n === 1 ? '' : 's'} from your hand back into the Playbook`);
        }
      }
      out.hasEffect = true;
      break;
    }
    case 'shuffle_from_discard_to_deck': {
      // Player side: move N (or all) from discard back into deck. Supports
      // kind: "play" (default), "hero", or "all" (excluding hot_dog).
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      if (side === 'player') {
        const kind = step.kind || 'play';
        let candidates;
        if (kind === 'play') candidates = PM.playerDiscard.filter(c => c.cardType === 'Play');
        else if (kind === 'hero') candidates = PM.playerDiscard.filter(c => c.cardType === 'Hero');
        else if (kind === 'all') {
          const excl = step.exclude_kind;
          candidates = PM.playerDiscard.filter(c => {
            if (excl === 'hot_dog' && c.cardType === 'HotDog') return false;
            return true;
          });
        } else candidates = PM.playerDiscard.slice();
        const n = step.count != null ? step.count : candidates.length;
        const moving = candidates.slice(0, n);
        PM.playerDiscard = PM.playerDiscard.filter(c => !moving.includes(c));
        // Move heroes back to hero deck; plays to play deck
        for (const c of moving) {
          if (c.cardType === 'Hero') PM.playerHeroDeck.push(c);
          else PM.playerPlayDeck.push(c);
        }
        PM.playerPlayDeck = shuffle(PM.playerPlayDeck);
        PM.playerHeroDeck = shuffle(PM.playerHeroDeck);
      }
      out.hasEffect = true;
      break;
    }
    case 'discard_top': {
      // Player side, play kind: pop N from top of playerPlayDeck into discard.
      // Tracks mean cost of discarded plays so the `discarded_plays_cost_gte` metric reads correctly.
      const n = step.count || 1;
      const targets = step.target === 'both' ? ['self','opponent'] : [step.target || 'self'];
      let discardedPlays = [];
      for (const t of targets) {
        const side = t === 'self' ? ctx.self : ctx.opp;
        if (side === 'player' && (step.kind || 'play') === 'play') {
          const dropped = PM.playerPlayDeck.splice(0, n);
          PM.playerDiscard.push(...dropped);
          discardedPlays.push(...dropped);
        }
      }
      out._discardedPlays = (out._discardedPlays || []).concat(discardedPlays);
      ctx._discardedByThisPlay = (ctx._discardedByThisPlay || 0) + discardedPlays.length;
      out.hasEffect = true;
      break;
    }
    case 'discard_hand_all': {
      // B.12 — kind:"hero" filters to heroes-from-hand only.
      // Heroes-in-hand on iOS live alongside plays in the same array;
      // on JS the hand is similarly mixed when heroes get drawn into
      // it, so the same filter applies.
      const kind = step.kind;
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      if (side === 'player') {
        if (kind === 'hero') {
          const heroes = PM.playerPlayHand.filter(c => c.cardType === 'Hero');
          if (heroes.length) {
            ctx._discardedByThisPlay = (ctx._discardedByThisPlay || 0) + heroes.length;
            PM.playerDiscard.push(...heroes);
            PM.playerPlayHand = PM.playerPlayHand.filter(c => c.cardType !== 'Hero');
            out.notifications.push(`Discarded ${heroes.length} hero${heroes.length === 1 ? '' : 'es'} from your hand`);
          }
        } else {
          const n = PM.playerPlayHand.length;
          ctx._discardedByThisPlay = (ctx._discardedByThisPlay || 0) + n;
          PM.playerDiscard.push(...PM.playerPlayHand);
          PM.playerPlayHand = [];
          if (n > 0) out.notifications.push(`Discarded your entire hand (${n} play${n === 1 ? '' : 's'})`);
        }
      } else {
        // CPU side: cpuPlayPool only contains plays in this codepath,
        // so kind:"hero" is a structural no-op there.
        if (kind !== 'hero') {
          const n = PM.cpuPlayPool.length;
          ctx._discardedByThisPlay = (ctx._discardedByThisPlay || 0) + n;
          PM.cpuPlayPool = [];
          if (n > 0) out.notifications.push(`Discarded CPU's entire hand (${n} play${n === 1 ? '' : 's'})`);
        }
      }
      out.hasEffect = true;
      break;
    }
    case 'power_reset': {
      // Reset battle effect power to 0 (printed power is on the card itself)
      const b = PM.battles[PM.currentBattle];
      if (b) {
        const targets = step.target === 'both' ? ['self','opponent'] : [step.target || 'self'];
        for (const t of targets) {
          const side = t === 'self' ? ctx.self : ctx.opp;
          if (side === 'player') {
            out.selfDelta -= (b.playerEffectPower || 0); // undo all prior modifiers for self
          } else {
            out.oppDelta -= (b.cpuEffectPower || 0);
          }
        }
      }
      out.hasEffect = true;
      break;
    }
    case 'add_top_hero_power_to_self': {
      // Peek top of hero deck; add its power to self delta (does not consume the card)
      const deck = ctx.self === 'player' ? PM.playerHeroDeck : PM.cpuHeroDeck;
      const top = deck && deck[0];
      if (top) out.selfDelta += (top.power || 0);
      out.hasEffect = true;
      break;
    }
    case 'reclaim_used_play': {
      // Player side only: pop N cards from discard back into hand
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      if (side === 'player') {
        const n = step.count || 1;
        const reclaimed = PM.playerDiscard.splice(Math.max(0, PM.playerDiscard.length - n), n);
        PM.playerPlayHand.push(...reclaimed);
      }
      out.hasEffect = true;
      break;
    }

    // ── Tier B: Hero manipulation ──────────────────────────────
    case 'swap_active_with_hand': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      pmIntentSwapActiveWithHand(side);
      out.notifications.push(`Swapped active hero with hand`);
      out.hasEffect = true;
      break;
    }
    case 'swap_active_with_discard': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      pmIntentSwapActiveWithDiscard(side, step.weapon_filter || null);
      out.notifications.push(`Swapped active with discard pile${step.weapon_filter ? ` (filter: ${step.weapon_filter})` : ''}`);
      out.hasEffect = true;
      break;
    }
    case 'swap_active_with_future_hero': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      pmIntentSwapActiveWithFuture(side);
      out.notifications.push(`Swapped active with next battle's hero`);
      out.hasEffect = true;
      break;
    }
    case 'replace_active_with_top_hero_deck': {
      const sides = step.target === 'both' ? [ctx.self, ctx.opp] : [step.target === 'opponent' ? ctx.opp : ctx.self];
      for (const s of sides) pmIntentReplaceActiveWithTopDeck(s);
      out.notifications.push(`Replaced active hero from top of deck`);
      out.hasEffect = true;
      break;
    }
    case 'replace_next_with_top_hero_deck': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      pmIntentReplaceNextWithTopDeck(side);
      out.notifications.push(`Replaced next battle's hero from top of deck`);
      out.hasEffect = true;
      break;
    }
    case 'replace_all_unrevealed_with_top_hero_deck': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      pmIntentReplaceAllUnrevealedWithTopDeck(side);
      out.notifications.push(`Replaced all unrevealed heroes from deck`);
      out.hasEffect = true;
      break;
    }
    case 'replace_active_from_hand': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      const msg = pmIntentReplaceActiveFromHand(side);
      if (msg) out.notifications.push(msg);
      out.hasEffect = true;
      break;
    }
    case 'discard_hero': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      const src = step.source || 'active';
      if (src === 'active') pmIntentDiscardActiveHero(side);
      else pmIntentDiscardHeroFromHand(side);
      out.notifications.push(src === 'active' ? `Discarded active hero` : `Discarded hero from hand`);
      out.hasEffect = true;
      break;
    }
    case 'discard_hero_from_hand': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      pmIntentDiscardHeroFromHand(side);
      out.notifications.push(`Discarded hero from hand`);
      out.hasEffect = true;
      break;
    }
    case 'discard_revealed_hero':
    case 'discard_revealed': {
      out.notifications.push(op === 'discard_revealed_hero' ? `Discarded revealed hero` : `Discarded revealed play`);
      out.hasEffect = true;
      break;
    }
    case 'transform_to_hot_dog': {
      const tgt = step.target;
      const side = tgt === 'opponent' ? ctx.opp : ctx.self;
      pmIntentTransformToHotDog(side);
      out.notifications.push(`Active hero transformed → Hot Dog`);
      out.hasEffect = true;
      break;
    }
    case 'mark_future_battle': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      const selector = step.selector || 'random';
      pmIntentMarkFutureBattle(side, step.on_reveal_effects || [], selector);
      out.notifications.push(`Marked a future battle`);
      out.hasEffect = true;
      break;
    }

    // ── Tier B/C: Reveal / peek / search / copy ────────────────
    case 'reveal_top_hero_deck': {
      const count = step.count || 1;
      const sides = step.target === 'both' ? [ctx.self, ctx.opp] : [step.target === 'opponent' ? ctx.opp : ctx.self];
      for (const s of sides) pmIntentPeekHeroDeck(s, count, ctx);
      out.hasEffect = true;
      break;
    }
    case 'peek_unrevealed_hero': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      const sel = step.selector || 'self_next_battle';
      pmIntentPeekUnrevealedHero(side, sel, ctx);
      out.hasEffect = true;
      break;
    }
    case 'reorder_unrevealed_heroes': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      pmIntentReorderUnrevealedHeroes(side);
      out.notifications.push(`Reordered unrevealed heroes`);
      out.hasEffect = true;
      break;
    }
    case 'reveal': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      const kind = step.kind || 'hero';
      const count = step.count || 1;
      if (kind === 'hero') pmIntentRevealTopHeroes(side, count);
      else pmIntentRevealTopPlays(side, count);
      out.hasEffect = true;
      break;
    }
    case 'reveal_top': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      const count = step.count || 1;
      const kind = step.kind || 'play';
      if (kind === 'play') pmIntentRevealTopPlays(side, count);
      else pmIntentPeekHeroDeck(side, count, ctx);
      out.hasEffect = true;
      break;
    }
    case 'peek_and_reorder_top': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      const count = step.count || 3;
      pmIntentRevealTopPlays(side, count);
      out.notifications.push(`Peeked + reordered top ${count} plays`);
      out.hasEffect = true;
      break;
    }
    case 'reveal_top_reorder_or_bottom': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      const count = step.count || 2;
      pmIntentRevealTopPlays(side, count);
      out.notifications.push(`Peeked opponent's top ${count} plays`);
      out.hasEffect = true;
      break;
    }
    case 'shuffle_revealed_back':
      out.notifications.push(`Shuffled revealed plays back into deck`);
      out.hasEffect = true;
      break;
    case 'force_reveal_from_hand': {
      const count = step.count || 1;
      pmIntentPeekOpponentHand(ctx.self, count, 'chooser');
      out.notifications.push(`Forced opponent to reveal ${count} play${count === 1 ? '' : 's'}`);
      out.hasEffect = true;
      break;
    }
    case 'peek_opponent_hand': {
      const count = step.count || 1;
      const mode = step.mode || 'random';
      pmIntentPeekOpponentHand(ctx.self, count, mode);
      out.hasEffect = true;
      break;
    }
    case 'search': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      const action = step.action || 'play_free';
      pmIntentSearchPlaybook(side, step.filter || {}, action, ctx);
      out.notifications.push(`Searched Playbook (${action})`);
      out.hasEffect = true;
      break;
    }
    case 'copy_last_play': {
      const side = step.target === 'opponent' ? ctx.opp : ctx.self;
      pmIntentCopyLastPlay(side, ctx);
      out.notifications.push(`Copied last play`);
      out.hasEffect = true;
      break;
    }
    case 'play_revealed_free':
    case 'play_top_of_playbook_free': {
      // Honor step.target — versus_dice_roll rewrites this to
      // "opponent" when the actor lost the roll, meaning the OTHER
      // side gets the free play.
      const target = step.target || 'self';
      const actorSide = target === 'opponent' ? ctx.opp : ctx.self;
      const fired = pmIntentPlayTopOfPlaybookFree(actorSide, ctx);
      if (fired) {
        const subject = actorSide === 'player' ? 'You' : 'CPU';
        const verb    = actorSide === 'player' ? 'get' : 'gets';
        const cardName = fired.name || 'a card';
        // Natural-English phrasing including the card that fired.
        // "You get a free bonus play: Edge Rush." rather than
        // "You play the top of the Playbook free."
        out.notifications.push(`${subject} ${verb} a free bonus play: ${cardName}`);
      }
      out.hasEffect = true;
      break;
    }
    case 'discard_other_revealed':
      out.notifications.push(`Discarded other revealed cards`);
      out.hasEffect = true;
      break;
    case 'deploy_chosen_revealed':
      out.notifications.push(`Deployed chosen revealed hero`);
      out.hasEffect = true;
      break;
    case 'add_chosen_revealed_to_hand_discard_rest': {
      // Real implementation: auto-pick the best card from the top N
      // of the relevant deck, move it to hand/bench, discard the rest.
      // Sets ctx._chosenPlayCost so downstream conditionals in the
      // same effects[] array read the truthful value via
      // `chosen_play_cost`.
      const kind = step.kind || 'play';
      const cnt = step.count || 3;
      if (kind === 'play' && ctx.self === 'player') {
        const n = Math.min(cnt, PM.playerPlayDeck.length);
        if (n > 0) {
          const topN = PM.playerPlayDeck.splice(0, n);
          let bestIdx = 0;
          for (let i = 1; i < topN.length; i++) {
            if ((topN[i].playCost || 0) > (topN[bestIdx].playCost || 0)) bestIdx = i;
          }
          const chosen = topN[bestIdx];
          PM.playerPlayHand.push(chosen);
          for (let i = 0; i < topN.length; i++) {
            if (i !== bestIdx) PM.playerDiscard.push(topN[i]);
          }
          ctx._chosenPlayCost = chosen.playCost || 0;
          out.notifications.push(`Picked ${chosen.name} (${chosen.playCost || 0} HD) — discarded ${topN.length - 1} other${topN.length - 1 === 1 ? '' : 's'}`);
        }
      } else if (kind === 'hero') {
        const deck = ctx.self === 'player' ? PM.playerHeroDeck : PM.cpuHeroDeck;
        const bench = ctx.self === 'player' ? PM.playerBench : PM.cpuBench;
        const n = Math.min(cnt, deck.length);
        if (n > 0) {
          const topN = deck.splice(0, n);
          let bestIdx = 0;
          for (let i = 1; i < topN.length; i++) {
            if ((topN[i].power || 0) > (topN[bestIdx].power || 0)) bestIdx = i;
          }
          const chosen = topN[bestIdx];
          bench.push(chosen);
          // CPU has no hero discard pile in current state shape; player does.
          if (ctx.self === 'player') {
            PM.playerHeroDiscard = PM.playerHeroDiscard || [];
            for (let i = 0; i < topN.length; i++) {
              if (i !== bestIdx) PM.playerHeroDiscard.push(topN[i]);
            }
          }
          out.notifications.push(`Picked ${chosen.hero || chosen.name} (${chosen.power || 0} pow) → bench`);
        }
      }
      out.hasEffect = true;
      break;
    }
    case 'name_and_discard': {
      // Auto-name: pick the highest-cost play in opponent's hand. If they
      // have it (always true when auto-named from their hand), discard it.
      const target = (step.target === 'opponent') ? ctx.opp : ctx.self;
      const oppHand = target === 'player' ? PM.playerPlayHand : PM.cpuPlayPool;
      if (oppHand.length > 0) {
        let bestIdx = 0;
        for (let i = 1; i < oppHand.length; i++) {
          if ((oppHand[i]?.playCost || 0) > (oppHand[bestIdx]?.playCost || 0)) bestIdx = i;
        }
        const named = oppHand[bestIdx];
        oppHand.splice(bestIdx, 1);
        if (target === 'player') PM.playerDiscard.push(named);
        ctx._discardedByThisPlay = (ctx._discardedByThisPlay || 0) + 1;
        out.notifications.push(`Named ${named.name} — ${target === 'player' ? 'you' : 'opponent'} discarded it`);
      } else {
        out.notifications.push(`Named a card — ${target === 'player' ? 'your' : "opponent's"} hand is empty`);
      }
      out.hasEffect = true;
      break;
    }

    // ── Tier C: Complex specials ───────────────────────────────
    case 'mirror_power_effects_to_opponent': {
      const b = PM.battles[PM.currentBattle];
      if (b) {
        const selfEff = ctx.self === 'player' ? (b.playerEffectPower || 0) : (b.cpuEffectPower || 0);
        out.oppDelta += selfEff;
        out.notifications.push(`Mirrored ${selfEff} power to opponent`);
      }
      out.hasEffect = true;
      break;
    }
    case 'flip_opponent_debuffs': {
      const b = PM.battles[PM.currentBattle];
      if (b) {
        const selfEff = ctx.self === 'player' ? (b.playerEffectPower || 0) : (b.cpuEffectPower || 0);
        if (selfEff < 0) {
          out.selfDelta += (-selfEff * 2);
          out.notifications.push(`Flipped ${selfEff} debuff → +${-selfEff} bonus`);
        }
      }
      out.hasEffect = true;
      break;
    }
    case 'cancel_persistent': {
      // Rules-clarification (handoff §6.D): only rest_of_game effects
      // get cancelled. Scope-limited persistents (next_battle,
      // this_and_next, etc.) survive and continue ticking. Build a
      // two-column "cancelled vs unchanged" notification so the user
      // can audit what just happened.
      const target = step.target || 'opponent';
      const inGroup = (p) => target === 'self' ? p.owner === ctx.self
                          : target === 'opponent' ? p.owner !== ctx.self
                          : true;
      const candidates = (PM._persistents || []).filter(inGroup);
      const victims  = candidates.filter(p => (p.spec && p.spec.scope) === 'rest_of_game');
      const survived = candidates.filter(p => (p.spec && p.spec.scope) !== 'rest_of_game');
      // Rewind any deltas already applied to the CURRENT battle
      const b = PM.battles[PM.currentBattle];
      if (b) {
        for (const v of victims) {
          if (v.appliedAtBattle === PM.currentBattle) {
            b.playerEffectPower = (b.playerEffectPower || 0) - (v.appliedPlayerDelta || 0);
            b.cpuEffectPower    = (b.cpuEffectPower    || 0) - (v.appliedCpuDelta    || 0);
          }
        }
      }
      const victimSet = new Set(victims);
      PM._persistents = (PM._persistents || []).filter(p => !victimSet.has(p));
      // Sweep weapon transforms with rest_of_game scope owned by the
      // targeted side(s) — they're persistents too.
      const weaponVictims = (PM._weaponTransforms || []).filter(t => {
        const sideMatch = target === 'self' ? t.owner === ctx.self
                       : target === 'opponent' ? t.owner !== ctx.self
                       : true;
        return sideMatch && t.scope === 'rest_of_game';
      });
      const wvSet = new Set(weaponVictims);
      PM._weaponTransforms = (PM._weaponTransforms || []).filter(t => !wvSet.has(t));

      // Build the user-facing summary
      const victimLabels = victims
        .map(p => PM._persistentSummaryLabel(p.spec, p.owner))
        .filter(Boolean)
        .concat(weaponVictims.map(t => PM._weaponTransformLabel(t)));
      const survivorLabels = survived
        .map(p => PM._persistentSummaryLabel(p.spec, p.owner))
        .filter(Boolean);

      if (victimLabels.length || survivorLabels.length) {
        const lines = [];
        if (victimLabels.length) {
          lines.push('CANCELLED:\n  • ' + victimLabels.join('\n  • '));
        }
        if (survivorLabels.length) {
          lines.push('UNCHANGED (scope-limited):\n  • ' + survivorLabels.join('\n  • '));
        }
        out.notifications.push(lines.join('\n\n'));
      } else {
        out.notifications.push('Pull The Plug — no rest-of-game effects to cancel.');
      }
      out.hasEffect = true;
      break;
    }
    case 'persistent_delta': {
      // Install persistent with the inner effect — route through PM
      // so weapon_transform specs split into _weaponTransforms.
      PM.installPersistent(ctx.self, step);
      out.hasEffect = true;
      break;
    }
    case 'tax_per_hero_in_hand': {
      const target = step.target === 'opponent' ? ctx.opp : ctx.self;
      const perDelta = (step.per_hero_cost && step.per_hero_cost.delta) || 0;
      const fallbackDiscards = (step.fallback && step.fallback.count) || 0;
      pmIntentTaxPerHeroInHand(target, perDelta, fallbackDiscards);
      out.hasEffect = true;
      break;
    }
    case 'transfer_sub_cost': {
      const target = step.target === 'opponent' ? ctx.opp : ctx.self;
      const amount = step.amount || 2;
      PM._subCostTransfer = PM._subCostTransfer || {};
      PM._subCostTransfer[target] = { payer: ctx.self, amount };
      out.notifications.push(`Paying next sub for ${target === 'player' ? 'player' : 'opponent'}`);
      out.hasEffect = true;
      break;
    }
    case 'end_battle_by_power':
      PM._endBattleImmediately = true;
      out.notifications.push(`Battle ended immediately by current power`);
      out.hasEffect = true;
      break;
    case 'weapon_debuff_or_penalty': {
      // Auto-pick: match opponent's active weapon → apply if_match; else else
      const oppW = pmResolveWeapon(ctx.oppCard, ctx.opp, ctx.weaponTransforms || []);
      if (oppW && step.if_match) {
        pmExecStep(step.if_match, ctx, out);
        out.notifications.push(`Named weapon matched`);
      } else if (step.else) {
        pmExecStep(step.else, ctx, out);
        out.notifications.push(`Named weapon missed — penalty`);
      }
      out.hasEffect = true;
      break;
    }
    case 'compound_roll': {
      const comps = step.components || [];
      let coinHeads = null, dieVal = null;
      for (const c of comps) {
        if (c.op === 'coin_flip') coinHeads = Math.random() < 0.5;
        else if (c.op === 'dice_roll') dieVal = Math.floor(Math.random() * 6) + 1;
      }
      let matched = false;
      for (const br of (step.branches || [])) {
        if (br.match === 'otherwise') continue;
        if (typeof br.match === 'object' && br.match != null) {
          let ok = true;
          if (br.match.coin) {
            const got = coinHeads ? 'heads' : 'tails';
            if (got !== br.match.coin) ok = false;
          }
          if (Array.isArray(br.match.die_range) && dieVal != null) {
            if (!(dieVal >= br.match.die_range[0] && dieVal <= br.match.die_range[1])) ok = false;
          }
          if (ok && br.effect) {
            for (const s of br.effect) pmExecStep(s, ctx, out);
            matched = true;
            out.notifications.push(`Compound roll → branch matched`);
            break;
          }
        }
      }
      if (!matched) {
        for (const br of (step.branches || [])) {
          if (br.match === 'otherwise' && br.effect) {
            for (const s of br.effect) pmExecStep(s, ctx, out);
            out.notifications.push(`Compound roll → otherwise`);
            break;
          }
        }
      }
      out.hasEffect = true;
      break;
    }
    case 'dice_roll_again': {
      const whileMatch = step.while_match || [4,5,6];
      let extra = 0;
      while (extra < 10) {
        const r = Math.floor(Math.random() * 6) + 1;
        if (!whileMatch.includes(r)) break;
        extra++;
      }
      if (extra > 0) out.notifications.push(`Re-rolled ${extra} extra time${extra === 1 ? '' : 's'}`);
      out.hasEffect = true;
      break;
    }
    case 'versus_dice_roll': {
      // Both sides roll a single die; winner runs `winner_effect`.
      // Tie → no-op. Both rolls land in `out.diceRolls` so the dice-
      // reveal overlay can show them side-by-side. When opponent
      // wins, winner_effect's `target: "winner"` rewrites to
      // "opponent" (and "self" → "opponent") so downstream ops fire
      // for the right seat.
      const selfRoll = Math.floor(Math.random() * 6) + 1;
      const oppRoll  = Math.floor(Math.random() * 6) + 1;
      out.diceRolls = (out.diceRolls || []).concat([selfRoll, oppRoll]);
      out.revealMode = 'versus';
      out.revealLabel = 'VERSUS ROLL';
      const tied = selfRoll === oppRoll;
      const selfWins = selfRoll > oppRoll;
      // Notification text is screen-perspective: "you" = the human
      // player, regardless of which side played the card. Without this
      // rewrite, a CPU-played versus card reads "you 6, opponent 3 —
      // YOU WIN" using "you" to mean "CPU's self," which contradicts
      // every other label on screen.
      const isPlayerActor = ctx.self === 'player';
      const youRoll = isPlayerActor ? selfRoll : oppRoll;
      const cpuRoll = isPlayerActor ? oppRoll  : selfRoll;
      const playerWon = isPlayerActor ? selfWins : !selfWins;
      const outcome = tied ? 'TIE — no effect'
                           : (playerWon ? 'YOU win the roll' : 'CPU wins the roll');
      out.notifications.push(`Versus roll: you ${youRoll}, CPU ${cpuRoll} — ${outcome}`);
      if (!tied && Array.isArray(step.winner_effect)) {
        for (const effect of step.winner_effect) {
          const rewritten = Object.assign({}, effect);
          if (selfWins) {
            if (rewritten.target === 'winner') rewritten.target = 'self';
          } else {
            if (rewritten.target === 'winner' || rewritten.target === 'self') {
              rewritten.target = 'opponent';
            }
          }
          pmExecStep(rewritten, ctx, out);
        }
      }
      out.hasEffect = true;
      break;
    }
    case 'install_persistent': {
      // A fired persistent's `effect` can call this to install a
      // CHILD persistent at fire time — used for "next-battle
      // delivery" (e.g. 2017 Cinderellas: parent fires on_battle_win
      // rest_of_game; child is scoped next_battle and delivers +5
      // power on_battle_start).
      if (step.spec && typeof step.spec === 'object') {
        // Carry parent's source name onto child install so trigger
        // callouts read "Make It, Take It (Win)" instead of generic.
        PM._inheritedInstallSource = ctx._sourceCard || PM._inheritedInstallSource || null;
        PM.installPersistent(ctx.self, step.spec);
        PM._inheritedInstallSource = null;
        // Describe what was armed so the win/start callout reads as
        // a real cause-and-effect chain ("Armed: Your Hero +5 next
        // battle") rather than a generic "Installed follow-up effect."
        out.notifications.push('Armed: ' + pmDescribeArmedFollowUp(step.spec, ctx.self));
      }
      out.hasEffect = true;
      break;
    }
    case 'player_choice': {
      // Generic chooser. JSON shape:
      //   { op:'player_choice', prompt, options:[{label, effects}],
      //     cpu_pick: 0 }
      // CPU side auto-picks `cpu_pick`. Player side surfaces a
      // chooser sheet (host renders pmPlayerChoiceSheet).
      const prompt = step.prompt || 'Choose one';
      const options = Array.isArray(step.options) ? step.options : [];
      if (!options.length) {
        out.unknownOps.push('player_choice (no options)');
        break;
      }
      const cpuPick = (typeof step.cpu_pick === 'number') ? step.cpu_pick : 0;
      if (ctx.self === 'cpu') {
        // CPU resolves immediately with the recommended pick.
        const opt = options[Math.max(0, Math.min(cpuPick, options.length - 1))];
        for (const eff of (opt.effects || [])) pmExecStep(eff, ctx, out);
        if (opt.label) out.notifications.push(`CPU chose: ${opt.label}`);
      } else {
        // Player path: queue a chooser intent; host opens the sheet
        // and re-runs the chosen option's effects via the executor.
        out.intents = (out.intents || []);
        out.intents.push({
          kind: 'presentPlayerChoice',
          side: ctx.self,
          prompt,
          options,
          cpuPick,
        });
      }
      out.hasEffect = true;
      break;
    }
    case 'reveal_play_for_conditional_free': {
      // Scare Tactics. Player picks a card from hand; if next CPU
      // play's cost ≥ revealed cost, the revealed card resolves free
      // for the player. CPU side auto-reveals their highest-cost play.
      out.intents = (out.intents || []);
      out.intents.push({ kind: 'revealForConditionalFree', side: ctx.self });
      out.hasEffect = true;
      break;
    }
    case 'dice_gate': {
      // Inert when invoked directly — `dice_gate` lives inside a
      // persistent's `effect` and is consumed by pmCheckPlayGate
      // when the OPPOSING side plays. If we hit it here it just
      // means a malformed entry tried to fire it as a one-shot.
      out.notifications.push('Dice gate set (opponent must roll to play)');
      out.hasEffect = true;
      break;
    }

    default:
      // Unknown op — log once, skip silently
      out.unknownOps.push(op);
      break;
  }
}

// Execute an entry against a context. Returns computed deltas.
function pmExecStructured(entry, ctx) {
  const out = {
    selfDelta: 0, oppDelta: 0, selfHDDelta: 0, oppHDDelta: 0,
    draws: 0, heroDraws: 0, discards: 0,
    protectSelf: false, cancelOpp: false,
    hasEffect: false, unknownOps: [], notifications: []
  };
  if (!entry || !entry.effects) return out;
  for (const step of entry.effects) pmExecStep(step, ctx, out);
  // Flag persistent effects — applied to match state for future battles
  if (entry.persistent && entry.persistent.length) {
    out.hasPersistent = true;
  }
  return out;
}

// ══════════════════════════════════════════════════════════════════
// Intent helpers — mutate PM state for Tier B/C ops
// ══════════════════════════════════════════════════════════════════

// Auto-discard N cards from the given side's playbook hand. Cards
// referencing `discard 2 plays` would otherwise be silent no-ops
// because out.discards is just a counter. Pops from the front (oldest
// drawn) of the hand and pushes onto the discard pile. Player-side
// chooser flow can come later; for now this matches iOS's
// autoDiscardHand intent semantics.
function pmAutoDiscardFromHand(side, count) {
  if (!count || count < 1) return;
  const hand = side === 'player' ? PM.playerPlayHand : PM.cpuPlayPool;
  if (!hand.length) return;
  const n = Math.min(count, hand.length);
  const dropped = hand.splice(0, n);
  if (side === 'player') {
    PM.playerDiscard.push(...dropped);
  }
  // CPU has no public discard pile; cards go to the void per the rules.
  pmEnqueueNotification(`${side === 'player' ? 'You' : 'CPU'} discarded ${n} play${n === 1 ? '' : 's'}`);
}

// Dispatch executor-emitted intents that need host-side handling
// (player_choice, scare reveal, etc.). The web doesn't yet have full
// chooser sheets, so we route each intent to a sane auto-resolution
// (CPU-style auto-pick for the first option) and let the UI evolve.
function pmHandlePlayIntents(intents, ctx, out, sourceCard) {
  for (const intent of intents) {
    if (!intent || !intent.kind) continue;
    if (intent.kind === 'presentPlayerChoice') {
      // Player surfaces the chooser sheet; CPU auto-picked already
      // inside the executor. For player side, queue a deferred
      // chooser; for now, auto-pick the cpuPick option so the play
      // resolves without dropping. (Sheet UI lands in Wave 3.)
      const opts = intent.options || [];
      if (!opts.length) continue;
      const idx = Math.max(0, Math.min(intent.cpuPick || 0, opts.length - 1));
      const opt = opts[idx];
      const childCtx = Object.assign({}, ctx, { _sourceCard: sourceCard?.name || '' });
      for (const eff of (opt.effects || [])) {
        const child = { selfDelta: 0, oppDelta: 0, selfHDDelta: 0, oppHDDelta: 0,
                        draws: 0, discards: 0, hasEffect: false, unknownOps: [], notifications: [] };
        pmExecStep(eff, childCtx, child);
        out.selfDelta += child.selfDelta || 0;
        out.oppDelta  += child.oppDelta  || 0;
        out.selfHDDelta += child.selfHDDelta || 0;
        out.oppHDDelta  += child.oppHDDelta  || 0;
        if (child.notifications && child.notifications.length) {
          out.notifications = (out.notifications || []).concat(child.notifications);
        }
      }
      if (opt.label) {
        out.notifications = (out.notifications || []).concat([
          intent.side === 'player' ? `Auto-chose: ${opt.label}` : `CPU chose: ${opt.label}`
        ]);
      }
    } else if (intent.kind === 'revealForConditionalFree') {
      // Scare Tactics — store revealed card so next opp play can
      // gate on its cost. Player side would normally surface a
      // hand chooser; we auto-pick highest-cost play.
      const hand = intent.side === 'player' ? PM.playerPlayHand : PM.cpuPlayPool;
      if (!hand.length) continue;
      let bestIdx = 0;
      for (let i = 1; i < hand.length; i++) {
        if ((hand[i]?.playCost || 0) > (hand[bestIdx]?.playCost || 0)) bestIdx = i;
      }
      PM._scareReveal = {
        side: intent.side,
        card: hand[bestIdx],
        revealedAt: PM.currentBattle,
      };
      pmEnqueueNotification(`Scare Tactics: ${intent.side === 'player' ? 'You' : 'CPU'} revealed ${hand[bestIdx].name}`);
    }
  }
}

// Scare Tactics — if `actingSide` is playing a card whose cost meets
// the threshold of the OPPOSITE side's revealed card (from a prior
// battle), the revealed card resolves free for the revealer's side.
// Single-shot per match — clears the reveal once it fires.
function pmMaybeFireScareReveal(actingSide, oppPlayCost) {
  const reveal = PM._scareReveal;
  if (!reveal) return;
  // Reveal must have been made on a different battle than the one we're in.
  if (reveal.revealedAt >= PM.currentBattle) return;
  // The reveal owner must be the opposite of the acting side.
  const owner = reveal.side;
  if (owner === actingSide) return;
  const threshold = reveal.card?.playCost || 0;
  if ((oppPlayCost || 0) < threshold) return;
  // Pull the revealed card from the owner's hand and resolve it free
  // for the owner's side.
  const hand = owner === 'player' ? PM.playerPlayHand : PM.cpuPlayPool;
  const idx = hand.indexOf(reveal.card);
  if (idx < 0) {
    PM._scareReveal = null;
    return;
  }
  hand.splice(idx, 1);
  if (owner === 'player') PM.playerDiscard.push(reveal.card);
  pmEnqueueNotification(`✨ Scare Tactics fires — ${reveal.card.name} resolves free for ${owner === 'player' ? 'you' : 'CPU'}`);
  // Run the revealed card's effects with the owner's context.
  const entry = pmGetPlayEntry(reveal.card);
  if (entry && entry.effects && entry.effects.length) {
    const ctx = pmMakeExecContext(owner);
    ctx._sourceCard = reveal.card.name || '';
    const out = pmExecStructured(entry, ctx);
    const b = PM.battles[PM.currentBattle];
    if (b) {
      const playerDelta = owner === 'player' ? out.selfDelta : out.oppDelta;
      const cpuDelta    = owner === 'player' ? out.oppDelta : out.selfDelta;
      b.playerEffectPower = (b.playerEffectPower || 0) + (playerDelta || 0);
      b.cpuEffectPower    = (b.cpuEffectPower    || 0) + (cpuDelta || 0);
    }
    PM.applyHDRecover(owner, out.selfHDDelta);
    PM.applyHDRecover(owner === 'player' ? 'cpu' : 'player', out.oppHDDelta);
  }
  PM._scareReveal = null;
}

// Engine side of Leave It To Chance. Returns null if no in-scope
// dice_gate persistent applies; otherwise returns {roll, passed}.
// Caller (player or CPU play resolution) cancels the play when
// passed===false.
function pmCheckPlayGate(actingSide) {
  const opp = actingSide === 'player' ? 'cpu' : 'player';
  for (const inst of (PM._persistents || [])) {
    if (inst.owner !== opp) continue;
    const trigger = inst.spec && inst.spec.trigger;
    if (trigger !== 'on_opp_play') continue;
    if (!pmIsScopeActive(inst.spec.scope, inst.installedAt, PM.currentBattle, inst.spec)) continue;
    const eff = inst.spec.effect;
    if (!eff || eff.op !== 'dice_gate') continue;
    const passOn = Array.isArray(eff.pass_on) ? eff.pass_on : [2,3,4,5];
    const roll = Math.floor(Math.random() * 6) + 1;
    return { roll, passed: passOn.includes(roll) };
  }
  return null;
}

function pmIntentSwapActiveWithHand(side) {
  const b = PM.battles[PM.currentBattle]; if (!b) return;
  const bench = side === 'player' ? PM.playerBench : PM.cpuBench;
  if (!bench.length) return;
  let bestIdx = 0;
  for (let i = 1; i < bench.length; i++) if ((bench[i]?.power || 0) > (bench[bestIdx]?.power || 0)) bestIdx = i;
  const replacement = bench[bestIdx];
  bench.splice(bestIdx, 1);
  const current = side === 'player' ? b.playerCard : b.cpuCard;
  if (side === 'player') { b.playerCard = replacement; if (current) PM.playerBench.push(current); }
  else                   { b.cpuCard = replacement;    if (current) PM.cpuBench.push(current); }
}

// Distinct from swap — used by cards that pair `discard_hero` + `replace_active_from_hand`
// (e.g. Forced Retreat). The current active slot holds a card just drawn from the hero
// deck by discard_hero's auto-refill; returning it to the top of the deck keeps deck
// integrity. Returns a human-readable notification with the hero names swapped.
function pmIntentReplaceActiveFromHand(side) {
  const b = PM.battles[PM.currentBattle]; if (!b) return null;
  const bench = side === 'player' ? PM.playerBench : PM.cpuBench;
  const deck  = side === 'player' ? PM.playerHeroDeck : PM.cpuHeroDeck;
  if (!bench.length) return `No bench hero to replace with`;
  let bestIdx = 0;
  for (let i = 1; i < bench.length; i++) if ((bench[i]?.power || 0) > (bench[bestIdx]?.power || 0)) bestIdx = i;
  const replacement = bench[bestIdx];
  bench.splice(bestIdx, 1);
  const current = side === 'player' ? b.playerCard : b.cpuCard;
  if (current) deck.unshift(current); // return to top of deck, preserving deck size
  if (side === 'player') b.playerCard = replacement; else b.cpuCard = replacement;
  const who = side === 'player' ? 'Your' : "Opponent's";
  return `${who} active → ${replacement.name} (from bench)`;
}

function pmIntentSwapActiveWithDiscard(side, weaponFilter) {
  if (side !== 'player') return; // CPU has no discard pile in this model
  const pool = PM.playerDiscard.filter(c => c.cardType === 'Hero' && (!weaponFilter || c.element === weaponFilter));
  if (!pool.length) return;
  const best = pool.reduce((a, c) => (c.power || 0) > (a.power || 0) ? c : a, pool[0]);
  const b = PM.battles[PM.currentBattle]; if (!b) return;
  const current = b.playerCard;
  b.playerCard = best;
  PM.playerDiscard = PM.playerDiscard.filter(c => c !== best);
  if (current) PM.playerDiscard.push(current);
}

function pmIntentSwapActiveWithFuture(side) {
  const next = PM.battles[PM.currentBattle + 1]; const cur = PM.battles[PM.currentBattle];
  if (!next || !cur) return;
  if (side === 'player') { const t = cur.playerCard; cur.playerCard = next.playerCard; next.playerCard = t; }
  else                   { const t = cur.cpuCard;    cur.cpuCard    = next.cpuCard;    next.cpuCard    = t; }
}

function pmIntentReplaceActiveWithTopDeck(side) {
  const b = PM.battles[PM.currentBattle]; if (!b) return;
  if (side === 'player') {
    if (!PM.playerHeroDeck.length) return;
    const old = b.playerCard;
    b.playerCard = PM.playerHeroDeck.shift();
    if (old) PM.playerDiscard.push(old);
  } else {
    if (!PM.cpuHeroDeck.length) return;
    b.cpuCard = PM.cpuHeroDeck.shift();
  }
}

function pmIntentReplaceNextWithTopDeck(side) {
  const next = PM.battles[PM.currentBattle + 1]; if (!next) return;
  if (side === 'player' && PM.playerHeroDeck.length) next.playerCard = PM.playerHeroDeck.shift();
  else if (side === 'cpu' && PM.cpuHeroDeck.length)   next.cpuCard = PM.cpuHeroDeck.shift();
}

function pmIntentReplaceAllUnrevealedWithTopDeck(side) {
  for (let i = PM.currentBattle + 1; i < PM.battles.length; i++) {
    if (side === 'player') {
      if (!PM.playerHeroDeck.length) break;
      PM.battles[i].playerCard = PM.playerHeroDeck.shift();
    } else {
      if (!PM.cpuHeroDeck.length) break;
      PM.battles[i].cpuCard = PM.cpuHeroDeck.shift();
    }
  }
}

function pmIntentDiscardActiveHero(side) {
  const b = PM.battles[PM.currentBattle]; if (!b) return;
  if (side === 'player') {
    if (b.playerCard) PM.playerDiscard.push(b.playerCard);
    b.playerCard = PM.playerHeroDeck.length ? PM.playerHeroDeck.shift() : null;
  } else {
    b.cpuCard = PM.cpuHeroDeck.length ? PM.cpuHeroDeck.shift() : null;
  }
}

function pmIntentDiscardHeroFromHand(side) {
  const bench = side === 'player' ? PM.playerBench : PM.cpuBench;
  if (!bench.length) return;
  let worstIdx = 0;
  for (let i = 1; i < bench.length; i++) if ((bench[i]?.power || 0) < (bench[worstIdx]?.power || 0)) worstIdx = i;
  const c = bench.splice(worstIdx, 1)[0];
  if (side === 'player' && c) PM.playerDiscard.push(c);
}

function pmIntentTransformToHotDog(side) {
  const b = PM.battles[PM.currentBattle]; if (!b) return;
  if (side === 'player') {
    b.playerTransformedToHotDog = true;
    const cur = b.playerCard?.power || 0;
    b.playerEffectPower = (b.playerEffectPower || 0) - cur;
  } else {
    b.cpuTransformedToHotDog = true;
    const cur = b.cpuCard?.power || 0;
    b.cpuEffectPower = (b.cpuEffectPower || 0) - cur;
  }
}

function pmIntentMarkFutureBattle(side, onReveal, selector) {
  PM._markedBattles = PM._markedBattles || [];
  const candidates = [];
  for (let i = PM.currentBattle + 1; i < PM.battles.length; i++) {
    if (!PM.battles[i].revealed) candidates.push(i);
  }
  if (!candidates.length) return;
  // Player-pick selector → open chooser modal so the user picks
  // which Hero to mark (Delayed Recovery: "Choose one of your
  // unrevealed Heroes"). Default / opponent / unknown selector
  // falls back to a random pick.
  if (selector === 'unrevealed_hero_player_pick' && side === 'player') {
    pmShowFutureBattlePickModal(side, onReveal, candidates);
    return;
  }
  const target = candidates[Math.floor(Math.random() * candidates.length)];
  PM._markedBattles.push({ side, battleIdx: target, onReveal });
}

function pmShowFutureBattlePickModal(side, onReveal, candidates) {
  document.getElementById('pm-future-pick-overlay')?.remove();
  const overlay = document.createElement('div');
  overlay.id = 'pm-future-pick-overlay';
  overlay.className = 'modal-overlay pm-modal-overlay pm-future-pick-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', 'Choose an unrevealed Hero');

  const rowsHTML = candidates.map(idx => {
    const slot = PM.battles[idx];
    const card = side === 'player' ? slot.playerCard : slot.cpuCard;
    const imgUrl = card && card.imageFile ? thumbUrl(card.imageFile) : null;
    const name = card ? (card.hero || card.name) : 'Unknown hero';
    const power = card && typeof card.power === 'number' ? `${card.power} POW` : '';
    const element = card && card.element ? card.element.toUpperCase() : '';
    return `
      <button class="pm-future-pick-row" data-battle-idx="${idx}" type="button">
        <div class="pm-future-pick-img">
          ${imgUrl ? `<img src="${imgUrl}" alt="${pmEscapeHTML(name)}" onerror="this.style.display='none'">` : ''}
        </div>
        <div class="pm-future-pick-info">
          <div class="pm-future-pick-eyebrow">BATTLE ${idx + 1}</div>
          <div class="pm-future-pick-name">${pmEscapeHTML(name)}</div>
          <div class="pm-future-pick-meta">
            ${power ? `<span class="pm-future-pick-pow">${power}</span>` : ''}
            ${element ? `<span class="pm-future-pick-element">${element}</span>` : ''}
          </div>
        </div>
        <span class="pm-future-pick-chevron">›</span>
      </button>`;
  }).join('');

  overlay.innerHTML = `
    <div class="pm-future-pick-modal">
      <h2>Choose an Unrevealed Hero</h2>
      <p class="pm-future-pick-sub">The card's effect triggers on the chosen Hero's reveal.</p>
      <div class="pm-future-pick-list">${rowsHTML}</div>
      <button class="pm-future-pick-cancel" type="button">Cancel</button>
    </div>`;
  document.body.appendChild(overlay);
  const close = () => overlay.remove();
  overlay.querySelectorAll('.pm-future-pick-row').forEach(btn => {
    btn.addEventListener('click', () => {
      const idx = parseInt(btn.dataset.battleIdx, 10);
      if (!isNaN(idx)) {
        PM._markedBattles = PM._markedBattles || [];
        PM._markedBattles.push({ side, battleIdx: idx, onReveal });
        pmEnqueueNotification(`Marked Battle ${idx + 1} — effect triggers on reveal`);
      }
      close();
    });
  });
  overlay.querySelector('.pm-future-pick-cancel').addEventListener('click', close);
  overlay.addEventListener('click', e => { if (e.target === overlay) close(); });
  document.addEventListener('keydown', function escClose(ev) {
    if (ev.key === 'Escape') { close(); document.removeEventListener('keydown', escClose); }
  });
}

function pmIntentPeekHeroDeck(side, count, ctx) {
  const deck = side === 'player' ? PM.playerHeroDeck : PM.cpuHeroDeck;
  const names = deck.slice(0, count).map(c => c.name).join(', ');
  if (!names) return;
  const who = side === (ctx && ctx.self) ? `Your next hero${count === 1 ? '' : 'es'}` : `Opponent's next hero${count === 1 ? '' : 'es'}`;
  PM._peekCallouts = PM._peekCallouts || [];
  PM._peekCallouts.push(`${who}: ${names}`);
}

function pmIntentPeekUnrevealedHero(side, selector, ctx) {
  const isOppNext = selector === 'opponent_next_battle' || /next/.test(selector);
  const idx = PM.currentBattle + (isOppNext ? 1 : 0);
  const slot = PM.battles[idx]; if (!slot) return;
  const c = side === 'player' ? slot.playerCard : slot.cpuCard;
  if (c) {
    PM._peekCallouts = PM._peekCallouts || [];
    PM._peekCallouts.push(`Peeked unrevealed hero: ${c.name}`);
  }
}

function pmIntentReorderUnrevealedHeroes(side) {
  const slots = [];
  for (let i = PM.currentBattle + 1; i < PM.battles.length; i++) if (!PM.battles[i].revealed) slots.push(i);
  const cards = slots.map(i => side === 'player' ? PM.battles[i].playerCard : PM.battles[i].cpuCard).filter(Boolean);
  cards.sort((a, b) => (b.power || 0) - (a.power || 0));
  slots.forEach((idx, i) => {
    if (i >= cards.length) return;
    if (side === 'player') PM.battles[idx].playerCard = cards[i];
    else                   PM.battles[idx].cpuCard    = cards[i];
  });
}

function pmIntentRevealTopPlays(side, count) {
  const pool = side === 'player' ? PM.playerPlayDeck : PM.cpuPlayPool;
  const names = pool.slice(0, count).map(c => c.name).join(', ');
  if (!names) return;
  PM._peekCallouts = PM._peekCallouts || [];
  PM._peekCallouts.push(`Top plays: ${names}`);
}

function pmIntentRevealTopHeroes(side, count) {
  const pool = side === 'player' ? PM.playerHeroDeck : PM.cpuHeroDeck;
  const names = pool.slice(0, count).map(c => c.name).join(', ');
  if (!names) return;
  PM._peekCallouts = PM._peekCallouts || [];
  PM._peekCallouts.push(`Top heroes: ${names}`);
}

function pmIntentPeekOpponentHand(side, count, mode) {
  const pool = side === 'player' ? PM.cpuPlayPool : PM.playerPlayHand;
  const selected = mode === 'random' ? [...pool].sort(() => Math.random() - 0.5).slice(0, count) : pool.slice(0, count);
  if (!selected.length) return;
  if (side === 'player') {
    // Surface as a dismissible modal with full card visuals — the
    // 2s toast was unreadable for two card names. Pre-Game Spy et al.
    pmShowPeekedHandModal(selected, PM._currentlyResolvingPlayCard || '');
  } else {
    PM._peekCallouts = PM._peekCallouts || [];
    PM._peekCallouts.push(`Opponent's hand: ${selected.map(c => c.name).join(', ')}`);
  }
}

function pmShowPeekedHandModal(cards, sourceCard) {
  // Drop any prior overlay so quick-fire reveals don't stack.
  document.getElementById('pm-peeked-hand-overlay')?.remove();
  const overlay = document.createElement('div');
  overlay.id = 'pm-peeked-hand-overlay';
  overlay.className = 'modal-overlay pm-modal-overlay pm-peeked-hand-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', "Opponent's hand revealed");

  const cardsHTML = cards.map(c => {
    const imgUrl = c.imageFile ? thumbUrl(c.imageFile) : null;
    const cost = (typeof c.playCost === 'number')
      ? (c.playCost === 0 ? 'FREE' : `${c.playCost} HD`)
      : '';
    return `
      <div class="pm-peeked-card">
        <div class="pm-peeked-card-img">
          ${imgUrl
            ? `<img src="${imgUrl}" alt="${pmEscapeHTML(c.name)}" onerror="this.style.display='none'">`
            : ''}
        </div>
        <div class="pm-peeked-card-info">
          <div class="pm-peeked-card-name">${pmEscapeHTML(c.name)}</div>
          ${cost ? `<div class="pm-peeked-card-cost">${cost}</div>` : ''}
          ${c.playAbility ? `<div class="pm-peeked-card-ability">${pmEscapeHTML(c.playAbility)}</div>` : ''}
        </div>
      </div>`;
  }).join('');

  overlay.innerHTML = `
    <div class="pm-peeked-hand-modal">
      ${sourceCard ? `<div class="pm-peeked-source">${pmEscapeHTML(sourceCard.toUpperCase())}</div>` : ''}
      <h2>Opponent's Hand</h2>
      <p class="pm-peeked-sub">${cards.length} play${cards.length === 1 ? '' : 's'} revealed.</p>
      <div class="pm-peeked-cards">${cardsHTML}</div>
      <button class="pm-peeked-done" type="button">Done</button>
    </div>`;
  document.body.appendChild(overlay);
  const close = () => overlay.remove();
  overlay.querySelector('.pm-peeked-done').addEventListener('click', close);
  overlay.addEventListener('click', e => { if (e.target === overlay) close(); });
  document.addEventListener('keydown', function escClose(ev) {
    if (ev.key === 'Escape') { close(); document.removeEventListener('keydown', escClose); }
  });
}

function pmIntentSearchPlaybook(side, filter, action, ctx) {
  if (side !== 'player') return;
  const pool = [...PM.playerPlayDeck, ...PM.playerPlayHand, ...PM.playerDiscard].filter(c => c.cardType === 'Play');
  if (!pool.length) return;
  const best = pool.reduce((a, c) => (c.playCost || 0) > (a.playCost || 0) ? c : a, pool[0]);
  if (action === 'play_free' && best) {
    const entry = pmGetPlayEntry(best);
    if (entry) {
      const inner = pmExecStructured(entry, ctx);
      if (inner.hasEffect) {
        const b = PM.battles[PM.currentBattle];
        if (b) {
          b.playerEffectPower = (b.playerEffectPower || 0) + (inner.selfDelta || 0);
          b.cpuEffectPower    = (b.cpuEffectPower    || 0) + (inner.oppDelta  || 0);
        }
      }
    }
    PM._peekCallouts = PM._peekCallouts || [];
    PM._peekCallouts.push(`Played ${best.name} free (Playbook search)`);
  }
}

function pmIntentCopyLastPlay(side, ctx) {
  let last = null;
  for (let i = PM.currentBattle; i >= 0; i--) {
    const b = PM.battles[i]; if (!b) continue;
    const arr = side === 'player' ? b.playerPlaysPlayed : (b.cpuPlaysPlayed || b.cpuPlaysRan || []);
    if (arr && arr.length) { last = arr[arr.length - 1]; break; }
  }
  if (!last) return;
  const entry = pmGetPlayEntry(last);
  if (!entry) return;
  const inner = pmExecStructured(entry, ctx);
  if (inner.hasEffect) {
    const b = PM.battles[PM.currentBattle];
    if (b) {
      if (side === 'player') {
        b.playerEffectPower = (b.playerEffectPower || 0) + (inner.selfDelta || 0);
        b.cpuEffectPower    = (b.cpuEffectPower    || 0) + (inner.oppDelta  || 0);
      } else {
        b.cpuEffectPower    = (b.cpuEffectPower    || 0) + (inner.selfDelta || 0);
        b.playerEffectPower = (b.playerEffectPower || 0) + (inner.oppDelta  || 0);
      }
    }
  }
}

function pmIntentPlayTopOfPlaybookFree(side, ctx) {
  // Pop from the relevant deck and exec its entry. `side` is the
  // ACTOR — the side that gets to play for free — which may differ
  // from ctx.self when versus_dice_roll rewrote target to "opponent".
  // Returns the card that fired (or null) so the caller can name it
  // in the notification.
  const top = side === 'player'
    ? PM.playerPlayDeck[0]
    : (PM.cpuPlayPool && PM.cpuPlayPool[0]);
  if (!top) return null;
  const entry = pmGetPlayEntry(top);
  if (!entry) return null;
  // Build a context whose `self` matches the actor side so deltas
  // get attributed correctly (selfDelta/oppDelta are relative to
  // ctx.self in pmExecStep). Using the original ctx would credit the
  // wrong side with the inner play's effect.
  const innerCtx = pmMakeExecContext(side);
  const inner = pmExecStructured(entry, innerCtx);
  if (inner.hasEffect) {
    const b = PM.battles[PM.currentBattle];
    if (b) {
      if (side === 'player') {
        b.playerEffectPower = (b.playerEffectPower || 0) + (inner.selfDelta || 0);
        b.cpuEffectPower    = (b.cpuEffectPower    || 0) + (inner.oppDelta  || 0);
      } else {
        b.cpuEffectPower    = (b.cpuEffectPower    || 0) + (inner.selfDelta || 0);
        b.playerEffectPower = (b.playerEffectPower || 0) + (inner.oppDelta  || 0);
      }
    }
  }
  // Move the consumed top card off its source so it isn't replayed.
  if (side === 'player') {
    PM.playerPlayDeck.shift();
    PM.playerDiscard.push(top);
  } else if (PM.cpuPlayPool) {
    PM.cpuPlayPool.shift();
  }
  return top;
}

function pmIntentTaxPerHeroInHand(target, perDelta, fallbackDiscards) {
  const bench = target === 'player' ? PM.playerBench : PM.cpuBench;
  const heroCount = bench.length;
  const totalCost = Math.abs(perDelta) * heroCount;
  const hd = target === 'player' ? PM.playerHD : PM.cpuHD;
  if (hd >= totalCost) {
    if (target === 'player') PM.playerHD = Math.max(0, PM.playerHD - totalCost);
    else PM.cpuHD = Math.max(0, PM.cpuHD - totalCost);
  } else {
    if (target === 'player') {
      const n = Math.min(fallbackDiscards, bench.length);
      for (let i = 0; i < n; i++) PM.playerDiscard.push(bench.pop());
    } else {
      const n = Math.min(fallbackDiscards, bench.length);
      for (let i = 0; i < n; i++) bench.pop();
    }
  }
}

// Returns true if `side` is currently blocked from `kind` action.
function pmIsBlocked(side, kind) {
  const blocks = (PM._blocks && PM._blocks[side]) || [];
  return blocks.some(b => {
    if (b.kind !== kind) return false;
    if (b.scope === 'this_battle') return PM.currentBattle === b.installedAt;
    if (b.scope === 'next_battle') return PM.currentBattle === b.installedAt + 1;
    if (b.scope === 'rest_of_game') return true;
    return PM.currentBattle >= b.installedAt;
  });
}

// Purge expired blocks when moving battles
function pmPurgeExpiredBlocks() {
  if (!PM._blocks) return;
  for (const side of ['player','cpu']) {
    PM._blocks[side] = (PM._blocks[side] || []).filter(b => {
      if (b.scope === 'this_battle') return PM.currentBattle <= b.installedAt;
      if (b.scope === 'next_battle') return PM.currentBattle <= b.installedAt + 1;
      return true;
    });
  }
}


// ══════════════════════════════════════════════════════════════════
// § Format-aware deck construction
// Mirrors iOS PracticeStore.buildRandomHeroDeck/padHeroDeck/
// buildRandomPlaybook. Powers the Random Deck source + Starter Deck
// padding when a stricter format is selected (SPEC / SPEC+ / Limited).
// ══════════════════════════════════════════════════════════════════

function pmFormatPowerCap(format) {
  switch (format) {
    case 'spec':     return 160;
    case 'specPlus': return 200;
    case 'standard':
    case 'limited':
    default:         return null;
  }
}
function pmFormatHeroDeckSize(format) {
  switch (format) {
    case 'limited': return 40;
    default:        return 60;
  }
}
// Build a 60-card (or 40 in limited) hero deck honoring the active
// format's power cap and a realistic power curve: 50% high (≥135),
// 40% mid (100–134), 10% low (55–99). Caps any single power value at
// 6 cards and any hero name at 4 variations. Backfill + relax-cap
// fallback guarantees hitting target.
function pmBuildRandomHeroDeck(pool, format) {
  const cap = pmFormatPowerCap(format);
  const target = pmFormatHeroDeckSize(format);
  const candidates = pool.filter(c =>
       c.cardType === 'Hero'
    && (c.power || 0) >= 55
    && c.imageFile
    && !((c.treatment || '').toLowerCase().includes('hot dog'))
    && (cap == null || (c.power || 0) <= cap)
  );
  if (!candidates.length) return [];

  const highTarget = Math.round(target * 0.50);
  const midTarget  = Math.round(target * 0.90);   // cumulative
  const lowTarget  = target;

  const high = shuffle(candidates.filter(c => (c.power || 0) >= 135));
  const mid  = shuffle(candidates.filter(c => { const p = c.power || 0; return p >= 100 && p < 135; }));
  const low  = shuffle(candidates.filter(c => (c.power || 0) < 100));

  const deck = [];
  const deckIDs = new Set();
  const byPower = new Map();
  const byHero  = new Map();

  function tryAdd(card, perPowerCap = 6, perHeroCap = 4) {
    if (deckIDs.has(card.bobaId)) return false;
    const p = card.power || 0;
    const h = card.hero || '';
    if ((byPower.get(p) || 0) >= perPowerCap) return false;
    if (h && (byHero.get(h) || 0) >= perHeroCap) return false;
    deck.push(card);
    deckIDs.add(card.bobaId);
    byPower.set(p, (byPower.get(p) || 0) + 1);
    if (h) byHero.set(h, (byHero.get(h) || 0) + 1);
    return true;
  }
  function fillFrom(source, targetCount) {
    for (const card of source) { if (deck.length >= targetCount) break; tryAdd(card); }
  }
  fillFrom(high, highTarget);
  fillFrom(mid,  midTarget);
  fillFrom(low,  lowTarget);

  // Backfill + relax-cap so we always hit target.
  const backfill = shuffle([...high, ...mid, ...low]);
  for (const card of backfill) { if (deck.length >= target) break; tryAdd(card); }
  for (const card of backfill) { if (deck.length >= target) break; tryAdd(card, 6, 6); }
  return deck;
}

// Filter an existing hero list to format constraints (drop heroes
// above the cap), then pad up to target from the catalog. Used when
// a saved/template deck is loaded under a stricter format than it
// was designed for.
function pmPadHeroDeck(existing, pool, format) {
  const cap = pmFormatPowerCap(format);
  const target = pmFormatHeroDeckSize(format);
  let deck = existing.filter(c => cap == null || (c.power || 0) <= cap);
  if (deck.length >= target) return deck.slice(0, target);
  const deckIDs = new Set(deck.map(c => c.bobaId));
  const byPower = new Map();
  const byHero  = new Map();
  for (const c of deck) {
    const p = c.power || 0;
    byPower.set(p, (byPower.get(p) || 0) + 1);
    const h = c.hero || '';
    if (h) byHero.set(h, (byHero.get(h) || 0) + 1);
  }
  const candidates = shuffle(pool.filter(c =>
       c.cardType === 'Hero'
    && (c.power || 0) >= 55
    && c.imageFile
    && !deckIDs.has(c.bobaId)
    && (cap == null || (c.power || 0) <= cap)
  ));
  for (const card of candidates) {
    if (deck.length >= target) break;
    const p = card.power || 0;
    const h = card.hero || '';
    if ((byPower.get(p) || 0) >= 6) continue;
    if (h && (byHero.get(h) || 0) >= 4) continue;
    deck.push(card);
    deckIDs.add(card.bobaId);
    byPower.set(p, (byPower.get(p) || 0) + 1);
    if (h) byHero.set(h, (byHero.get(h) || 0) + 1);
  }
  return deck;
}

// 30-card playbook biased toward the deck-composition triad:
// 8 recovery (economy + value) / 8 buffs (tempo+conditional+persistent)
// / 4 utility / 4 denial (disruption) / up to 6 bonus plays.
// Categories pulled from play-effects.json via pmGetPlayEntry.
function pmBuildRandomPlaybook(pool) {
  if (!pool || !pool.length) return [];
  const categoryOf = (c) => {
    const e = pmGetPlayEntry(c);
    return (e && e.category) || 'unknown';
  };
  const regular = pool.filter(c => c.isBonusPlay !== true && c.imageFile);
  const bonus   = shuffle(pool.filter(c => c.isBonusPlay === true && c.imageFile));
  const byRole = { recovery: [], buffs: [], utility: [], denial: [], other: [] };
  for (const c of regular) {
    switch (categoryOf(c)) {
      case 'economy':
      case 'value':         byRole.recovery.push(c); break;
      case 'tempo':
      case 'conditional':
      case 'persistent':    byRole.buffs.push(c);    break;
      case 'utility':       byRole.utility.push(c);  break;
      case 'disruption':    byRole.denial.push(c);   break;
      default:              byRole.other.push(c);
    }
  }
  for (const k of Object.keys(byRole)) byRole[k] = shuffle(byRole[k]);

  // Composition rebalanced 2026-04-27 per the bobaleagues meta
  // analysis (handoff §8) after BoBA's same-day DBS rebalance:
  //   ~2 high-DBS lockout finishers (≥80 DBS post-patch)
  //   ~3 community staples (4/4 top decks: Champion's Lasso,
  //     Dog Gone Inflation, No Huddle)
  //   10 draw/recovery, 6 buffs, 3 utility, 3 denial, 6 bonus.
  const lockouts = regular
    .filter(c => (c.dbs ?? 0) >= 80)
    .sort((a, b) => (b.dbs ?? 0) - (a.dbs ?? 0));
  const stapleNames = new Set([
    "The Champion's Lasso",
    "Dog Gone Inflation",
    "No Huddle",
  ]);
  const staples = regular.filter(c => stapleNames.has(c.name));

  const deck = [];
  const deckIDs = new Set();
  function tryAdd(c) {
    if (!c || deckIDs.has(c.bobaId) || deck.length >= 30) return;
    deck.push(c); deckIDs.add(c.bobaId);
  }
  function draw(key, count) {
    let taken = 0;
    for (const c of byRole[key]) {
      if (taken >= count) break;
      if (deckIDs.has(c.bobaId)) continue;
      tryAdd(c); taken++;
    }
  }

  for (const c of lockouts.slice(0, 2)) tryAdd(c);
  for (const c of staples) tryAdd(c);
  draw('recovery', 10);
  draw('buffs',     6);
  draw('utility',   3);
  draw('denial',    3);
  // Bonus plays — default 6, capped at 15 (BoBA rule limit).
  let bonusTaken = 0;
  for (const c of bonus) {
    if (bonusTaken >= 6 || deck.length >= 30) break;
    if (deckIDs.has(c.bobaId)) continue;
    tryAdd(c); bonusTaken++;
  }
  if (deck.length < 30) {
    for (const c of shuffle(regular)) {
      if (deck.length >= 30) break;
      if (deckIDs.has(c.bobaId)) continue;
      tryAdd(c);
    }
  }
  return shuffle(deck);
}

function pmElementColor(el) {
  const map = {
    FIRE: '#FF4D00', ICE: '#00BFFF', HEX: '#8B00FF', STEEL: '#8A9BB0',
    BRAWL: '#C0392B', GLOW: '#FFD700', GUM: '#FF69B4', SUPER: '#FF00FF',
  };
  return map[el] || '#666680';
}

// ── Foundation helpers (mirror PracticeStore.swift) ────────────────
//
// pmIsScopeActive — canonical scope vocabulary used by every persistent
// reader (block check, weapon transform, trigger fire). Recognizes the
// full set of scopes Cowork's audit calls out: rest_of_game,
// this_battle, next_battle, this_and_next, next_2_battles,
// next_N_battles (with spec.n), battle_1..battle_7, battles_4_7,
// current (legacy alias), prev_battle (always false going forward).
function pmIsScopeActive(scope, installedAt, at, spec) {
  if (!scope) return false;
  switch (scope) {
    case 'rest_of_game':   return true;
    case 'this_battle':    return at === installedAt;
    case 'current':        return at === installedAt; // legacy alias
    case 'next_battle':    return at === installedAt + 1;
    case 'this_and_next':  return at >= installedAt && at <= installedAt + 1;
    case 'next_2_battles': return at > installedAt && at <= installedAt + 2;
    case 'battles_4_7':    return at >= 3 && at <= 6;
    case 'next_N_battles': {
      const n = (spec && Number(spec.n)) || 1;
      return at > installedAt && at <= installedAt + n;
    }
    case 'prev_battle':    return false;
    default:
      if (typeof scope === 'string' && scope.startsWith('battle_')) {
        const n = parseInt(scope.slice('battle_'.length), 10);
        if (!isNaN(n) && n >= 1 && n <= 7) return at === (n - 1);
      }
      return false;
  }
}

// pmResolveWeapon — apply any in-scope weapon_transform to a card from
// the controller's perspective. Mirrors PlayExecContext.weapon(of:as:)
// in iOS. `controller` is the side that OWNS the hero being asked
// about; `transforms` is the snapshot of in-scope transforms passed
// via ctx (or PM._weaponTransforms when called outside a context).
function pmResolveWeapon(card, controller, transforms) {
  if (!card) return '';
  let w = card.element || '';
  if (!Array.isArray(transforms)) return w;
  for (const t of transforms) {
    const target = t.target;
    const to = t.to;
    if (!target || !to) continue;
    let applies;
    switch (target) {
      case 'all_heroes': applies = true; break;
      case 'self':       applies = controller === t.owner; break;
      case 'opponent':   applies = controller !== t.owner; break;
      default:           applies = false;
    }
    if (!applies) continue;
    if (t.from && t.from !== '' && t.from !== w) continue;
    w = to;
  }
  return w;
}

// Lightweight toast — used by trigger firings + HD recover modifier
// surfacing. Defers to pmQueuePhaseBanner once the playmat has rendered;
// silently no-ops if called too early (e.g. during match init).
function pmEnqueueNotification(text, duration) {
  if (typeof pmQueuePhaseBanner !== 'function') return;
  try { pmQueuePhaseBanner(text, duration || 1800); }
  catch (e) { /* ignore — the playmat may not be in the DOM yet */ }
}

// Battles left before a finite-scope effect expires. Null for
// rest_of_game and unrecognized scopes. Mirrors PracticeStore.swift
// battlesRemaining(for:installedAt:at:spec:).
function pmBattlesRemaining(scope, installedAt, at, spec) {
  if (!scope) return null;
  switch (scope) {
    case 'rest_of_game':   return null;
    case 'this_battle':    return at === installedAt ? 1 : 0;
    case 'current':        return at === installedAt ? 1 : 0;
    case 'next_battle':    return at === installedAt + 1 ? 1 : 0;
    case 'this_and_next':  return Math.max(0, (installedAt + 1) - at + 1);
    case 'next_2_battles': return Math.max(0, (installedAt + 2) - at + 1);
    case 'battles_4_7':    return Math.max(0, 6 - at + 1);
    case 'next_N_battles': {
      const n = (spec && Number(spec.n)) || 1;
      return Math.max(0, (installedAt + n) - at + 1);
    }
    default:
      if (typeof scope === 'string' && scope.startsWith('battle_')) {
        const n = parseInt(scope.slice('battle_'.length), 10);
        if (!isNaN(n)) return at === (n - 1) ? 1 : 0;
      }
      return null;
  }
}

// Human-friendly suffix matching scopeDisplayLabel on iOS.
function pmScopeDisplayLabel(scope) {
  if (!scope) return '';
  switch (scope) {
    case 'rest_of_game':   return '(rest of game)';
    case 'this_battle':    return '(this battle)';
    case 'current':        return '(this battle)';
    case 'next_battle':    return '(next battle)';
    case 'this_and_next':  return '(this + next battle)';
    case 'next_2_battles': return '(next 2 battles)';
    case 'battles_4_7':    return '(battles 4–7)';
    case 'next_N_battles': return '(next N battles)';
    default:
      if (typeof scope === 'string' && scope.startsWith('battle_')) {
        const n = parseInt(scope.slice('battle_'.length), 10);
        if (!isNaN(n)) return `(battle ${n})`;
      }
      return '';
  }
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
  playerHeroDeck: [],        // remaining hero cards to draw from for bench refill
  playerPlayHand: [],        // current play cards in hand (4 starting, draw 1/battle)
  playerPlayDeck: [],        // remaining plays
  playerDiscard: [],         // discarded plays
  playerSubstituted: false,
  playerPassedPlays: false,

  // CPU resources
  cpuHD: 10,
  cpuBench: [],
  cpuHeroDeck: [],             // remaining hero cards for CPU bench refill
  cpuPlayCount: 30,
  cpuPlayPool: [],             // actual play cards for CPU
  cpuSubstituted: false,
  cpuPassedPlays: false,

  selectedBenchIdx: null,    // which bench card is tapped for sub
  allCards: [],
  _initialized: false,       // event listeners attached once
  _showPhaseBanner: false,   // flag consumed by pmSetRootClass to queue a banner
  _pendingCpuSub: false,     // flag: CPU sub callout should be queued after phase banner
  _pendingCpuPlays: false,   // flag: CPU play overlays should be queued after phase banner

  // Custom rules layered on top of mode. Mirrors iOS PracticeCustomRules.
  // Engine wires: heroFormat → deck construction. Other knobs persist
  // in state for now; runtime wiring lands as features ship.
  customRules: {
    matchLength: 'bo7',         // 'bo7' | 'bo5' | 'bo3'
    heroFormat:  'standard',    // 'standard' | 'spec' | 'specPlus' | 'limited'
    startingHotDogs: 10,        // 5 | 8 | 10 | 12 | 15
    superBreaksTies: true,
    suddenDeath: true,
  },

  startMatch(allCards, opts = {}) {
    this.allCards = allCards;
    this._lastOpts = opts; // remember for Rematch / Play Again
    pmLoadPlayEffects(); // fire-and-forget — ready by the time cards are played
    this._persistents = []; // installed persistent effects (rest_of_game / next_battle, etc.)
    this._weaponTransforms = []; // B.1 — see installPersistent
    this._nextHonors = null;
    this._nextSubFree = null;
    PM._blocks = { player: [], cpu: [] };
    PM._pendingHonors = null;
    PM._freeSub = {};
    PM._subCostTransfer = {};
    PM._markedBattles = [];
    PM._peekCallouts = [];
    PM._playCostMods = { player: [], cpu: [] };
    PM._endBattleImmediately = false;
    // Roll 1d6 per side for Honors. High roll wins, ties re-roll.
    // Stash the rolls so the setup overlay can replay them visually.
    let playerRoll = 1 + Math.floor(Math.random() * 6);
    let cpuRoll    = 1 + Math.floor(Math.random() * 6);
    while (playerRoll === cpuRoll) {
      playerRoll = 1 + Math.floor(Math.random() * 6);
      cpuRoll    = 1 + Math.floor(Math.random() * 6);
    }
    const startHonors = playerRoll > cpuRoll ? 'player' : 'cpu';
    PM._pendingSetupHonors = { playerRoll, cpuRoll, winner: startHonors };
    Object.assign(this, {
      matchOver: false, matchWinner: null, playerScore: 0, cpuScore: 0,
      honors: startHonors, currentBattle: 0,
      // Per rules: Sub phase comes BEFORE reveal for non-rookie modes
      phase: this.mode === 'rookie' ? 'reveal' : 'sub',
      playerHD: 10, cpuHD: 10, cpuPlayCount: 30,
      playerSubstituted: false, cpuSubstituted: false,
      playerPassedPlays: false, cpuPassedPlays: false,
      selectedBenchIdx: null, _showPhaseBanner: true,
    });
    pmNotifQueue.clear();

    // Active format from custom rules drives hero deck size + power cap.
    // Falls back to standard if customRules hasn't been set.
    const format = (PM.customRules && PM.customRules.heroFormat) || 'standard';
    const allPlays = allCards.filter(c => c.cardType === 'Play');

    // Build each side: format-aware random builder if no provided deck;
    // pad-to-target if a partial deck is provided. Templates and saved
    // decks get cap-violators dropped and gaps refilled from the catalog
    // so a match never starts with a deck that's illegal for the active
    // format.
    const buildSide = (deckCards) => {
      let heroes;
      if (deckCards?.heroes?.length) {
        heroes = pmPadHeroDeck(shuffle([...deckCards.heroes]), allCards, format);
      } else {
        heroes = pmBuildRandomHeroDeck(allCards, format);
      }
      const plays = deckCards?.plays?.length
        ? shuffle([...deckCards.plays]).slice(0, 30)
        : pmBuildRandomPlaybook(allPlays);
      return { heroes, plays };
    };
    const playerSide = buildSide(opts.playerDeck);
    const cpuSide    = buildSide(opts.cpuDeck);

    const playerCards = playerSide.heroes.slice(0, 11);
    const cpuCards    = cpuSide.heroes.slice(0, 11);

    this.battles = [];
    for (let i = 0; i < 7; i++) {
      this.battles.push({
        id: i,
        playerCard: playerCards[i] || null,
        cpuCard:    cpuCards[i]    || null,
        playerEffectPower: 0,
        cpuEffectPower: 0,
        playerPlaysPlayed: [],
        cpuPlaysPlayed: [],
        // Per-side power-contribution log used by the 1v1 view's
        // breakdown panel. Entries are { label, delta, cardRef? } —
        // appended whenever an effect changes effective power, which
        // means the post-resolution panel can show "base + each delta
        // = final" without re-walking effects after the fact.
        playerBreakdown: [],
        cpuBreakdown: [],
        result: null,
        revealed: false,
        playerTransformedToHotDog: false,
        cpuTransformedToHotDog: false,
      });
    }

    this.playerBench = [...playerCards.slice(7)];
    this.cpuBench    = [...cpuCards.slice(7)];
    this.playerHeroDeck = playerSide.heroes.slice(11, 60);
    this.cpuHeroDeck    = cpuSide.heroes.slice(11, 60);

    this.playerPlayHand = playerSide.plays.slice(0, 4);
    this.playerPlayDeck = playerSide.plays.slice(4, 30);
    this.playerDiscard  = [];

    this.cpuPlayPool = cpuSide.plays.slice(0, 30);
    this.cpuPlayQueue = [];

    // Hot Dog deck card capture for the discard inspector. Per
    // Comprehensive Rules Guide §3.1, spent Hot Dogs share the
    // discard zone with heroes + plays. The web engine still tracks
    // HDs as an Int (playerHD), but holding onto the actual cards
    // lets the inspector render them as card rows matching the iOS
    // treatment. Resolved deck → those exact cards. No resolved
    // deck (random) → 10 random catalog Hot Dogs.
    const allHotDogs = allCards.filter(c => c.cardType === 'HotDog' && c.imageFile);
    const captureHotDogs = (resolved) => {
      const fromDeck = (resolved && Array.isArray(resolved.hotDogs))
        ? resolved.hotDogs.slice(0, 10) : [];
      if (fromDeck.length >= 10) return fromDeck;
      const need = 10 - fromDeck.length;
      const fill = [...allHotDogs].sort(() => Math.random() - 0.5).slice(0, need);
      return fromDeck.concat(fill);
    };
    this.playerHotDogDeckCards = captureHotDogs(opts.playerDeck);
    this.cpuHotDogDeckCards    = captureHotDogs(opts.cpuDeck);
  },

  advance() {
    if (this.matchOver) return;
    // In-flight guard. The button handler that calls advance() also
    // calls pmUpdateAll() which may queue CPU overlays / phase
    // banners. The user can fire a second click before any of that
    // settles. With pmNotifQueue.clear() removed from the body of
    // advance(), the queue is now durable across phases — but a
    // double-click during an inflight transition still risks the
    // resolution / cleanup case running before the player has
    // dismissed the CPU plays from the previous phase. Drop the
    // second click on the floor.
    if (this._advanceInFlight) return;
    this._advanceInFlight = true;
    try {
      this._advance();
    } finally {
      this._advanceInFlight = false;
    }
  },

  _advance() {
    const b = this.battles[this.currentBattle];

    // NOTE: We deliberately do NOT clear pmNotifQueue here. The
    // previous version wiped any in-flight CPU plays / phase banners
    // mid-animation, which is the root of the user's "things appear
    // and disappear" / "notifications are out of order" complaints.
    // The queue is FIFO; let it drain naturally as new entries are
    // appended for this phase's events.

    switch (this.phase) {
      case 'sub':
        // Per rules (§4.2.2, §4.3.2): Sub happens BEFORE reveal
        // CPU makes blind sub decision (can't see player's card)
        { const didSub = this.cpuDoSub();
          this.phase = 'reveal';
          this._showPhaseBanner = true;
          this._pendingCpuSub = didSub; // queued after phase banner in pmSetRootClass
        }
        break;

      case 'reveal':
        if (!b.revealed) {
          // Step 1: flip cards face-up so player can see the matchup
          b.revealed = true;
          this.applyContinuousPersistents();
          if (this.mode === 'rookie' || this.mode === 'substitution') {
            this.resolve();
          }
          // In playmaker, stay in reveal phase — user presses again to enter play
        } else {
          // Step 2: cards already revealed, enter play phase
          this.phase = 'play';
          this._showPhaseBanner = true;
          this.playerPassedPlays = false;
          this.cpuPassedPlays = false;
          // Honors rule (§4.3.2): honors player acts first in the play window.
          // CPU honors → CPU plays now, then player. Player honors → player plays first; CPU reacts on END TURN.
          if (this.honors === 'cpu') {
            this.cpuDoPlay();
            this._pendingCpuPlays = this.cpuPlayQueue.length > 0;
          }
        }
        break;

      case 'play':
        // Player passes on playing more cards
        this.playerPassedPlays = true;
        if (!this.cpuPassedPlays) {
          // CPU hadn't played yet (player had honors and went first) — CPU reacts now
          this.cpuDoPlay();
          this._pendingCpuPlays = this.cpuPlayQueue.length > 0;
        }
        if (this.playerPassedPlays && this.cpuPassedPlays) {
          this.resolve();
        }
        break;

      case 'resolution':
        this.phase = 'cleanup';
        this._showPhaseBanner = true;
        // Draw replacement play card on entering cleanup (matches iOS; visible to user before next battle)
        this.drawPlayCard();
        break;

      case 'cleanup':
        this.nextBattle();
        break;

      case 'over':
        this.startMatch(this.allCards, this._lastOpts || {});
        break;
    }
  },

  playerSub(benchIdx) {
    if (this.phase !== 'sub' || this.playerSubstituted) return false;
    if (pmIsBlocked('player', 'block_sub')) return false;
    if (benchIdx < 0 || benchIdx >= this.playerBench.length) return false;

    const freeSub = !!(PM._freeSub && PM._freeSub.player);
    const transfer = PM._subCostTransfer && PM._subCostTransfer.player;
    const cost = freeSub ? 0 : 2;
    if (!transfer && this.playerHD < cost) return false;

    const benchCard = this.playerBench[benchIdx];
    // Per rules: original hero goes to discard pile, not back to bench.
    // Push the displaced active to playerHeroDiscard so cards like
    // Don't Call It a Comeback (swap_active_with_discard) can pull it
    // back. iOS has always tracked this; web was dropping the hero on
    // the floor.
    const displaced = this.battles[this.currentBattle].playerCard;
    if (displaced) {
      PM.playerHeroDiscard = PM.playerHeroDiscard || [];
      PM.playerHeroDiscard.push(displaced);
    }
    this.battles[this.currentBattle].playerCard = benchCard;
    this.playerBench.splice(benchIdx, 1); // remove from bench

    if (transfer && transfer.payer === 'cpu') {
      this.cpuHD = Math.max(0, this.cpuHD - cost);
      delete PM._subCostTransfer.player;
    } else {
      this.playerHD -= cost;
    }
    if (freeSub) delete PM._freeSub.player;

    // Draw a new hero from hero deck to refill bench (per rules §Glossary "Substitute")
    if (this.playerHeroDeck.length > 0) {
      this.playerBench.push(this.playerHeroDeck.shift());
    }
    this.playerSubstituted = true;
    this.selectedBenchIdx = null;
    // Auto-advance to reveal phase after substituting (matches iOS)
    this.advance();
    return true;
  },

  lastEffectResult: null,    // { card, playerDelta, cpuDelta, description } — shown as toast

  playerPlayCard(handIdx) {
    if (this.phase !== 'play') return false;
    if (pmIsBlocked('player', 'block_plays')) return false;
    // Soft cap (Restricted List). When set, the player can't exceed
    // N plays this battle.
    if (PM._playerPlayCapThisBattle != null) {
      const used = (this.battles[this.currentBattle]?.playerPlaysPlayed || []).length;
      if (used >= PM._playerPlayCapThisBattle) return false;
    }
    if (handIdx < 0 || handIdx >= this.playerPlayHand.length) return false;
    const card = this.playerPlayHand[handIdx];
    const cost = pmEffectiveCost(card, 'player');
    if (this.playerHD < cost) return false;
    if (!pmIsPlayable(card, 'player')) return false;

    // Leave It To Chance: opponent's dice_gate persistent forces a roll.
    // Fail → play is cancelled (cost still consumed, card discarded).
    const gate = pmCheckPlayGate('player');
    if (gate && !gate.passed) {
      this.playerHD -= cost;
      this.playerPlayHand.splice(handIdx, 1);
      this.playerDiscard.push(card);
      pmEnqueueNotification(`🎲 ${gate.roll} — ${card.name} cancelled by Leave It To Chance`);
      return true;
    }
    if (gate && gate.passed) {
      pmEnqueueNotification(`🎲 ${gate.roll} — ${card.name} survives the gate`);
    }
    this.playerHD -= cost;
    this.lastEffectResult = null;
    const b = this.battles[this.currentBattle];

    // Structured executor first; fall back to regex resolver if no entry or no mechanical effect
    let effect = { playerDelta: 0, cpuDelta: 0 };
    let hdRecovery = 0;
    let extraNotifs = [];
    let firedDiceOrCoinFlag = false;
    let diceRollsForReveal = [];
    let coinFlipsForReveal = [];
    const entry = pmGetPlayEntry(card);
    let structuredHandled = false;
    const hasEffectsBlock    = entry && Array.isArray(entry.effects) && entry.effects.length > 0;
    const hasPersistentBlock = entry && Array.isArray(entry.persistent) && entry.persistent.length > 0;
    if (entry && (hasEffectsBlock || hasPersistentBlock)) {
      const ctx = pmMakeExecContext('player');
      ctx._sourceCard = card.name || '';
      // Make the source name available to intent handlers that don't
      // get the ctx (e.g. pmIntentPeekOpponentHand needs it for the
      // PeekedHand modal eyebrow).
      PM._currentlyResolvingPlayCard = card.name || '';
      const out = pmExecStructured(entry, ctx);
      firedDiceOrCoinFlag = !!out.firedDiceOrCoin;
      diceRollsForReveal = out.diceRolls || [];
      coinFlipsForReveal = out.coinFlips || [];
      // Mark handled whenever a JSON entry exists with effects OR
      // persistent — even when out.hasEffect is false. Two failure
      // modes the legacy regex resolver causes when this gate is
      // wrong:
      //   1. Condition-gated cards (To Fight Another Day on B1)
      //      correctly evaluate to false → empty out → regex applies
      //      the bonus unconditionally.
      //   2. Persistent-only cards (Overcommited, Lose 1 To Win 2)
      //      have empty effects[] but a real persistent[]. The regex
      //      parses ability text ("next battle, opp gets -5") and
      //      misfires on the CURRENT battle.
      effect.playerDelta = out.selfDelta;
      effect.cpuDelta = out.oppDelta;
      // protect_self mirror: player playing → cpuDelta lands on CPU.
      // If CPU is protected this battle, clamp negative deltas to 0.
      if (PM._cpuProtectedThisBattle && effect.cpuDelta < 0) effect.cpuDelta = 0;
      this.applyHDRecover('player', out.selfHDDelta);
      this.applyHDRecover('cpu',    out.oppHDDelta);
      structuredHandled = true;
      // Queue persistent effects — installPersistent splits
      // weapon_transform specs into the dedicated array.
      if (out.hasPersistent && entry.persistent) {
        for (const p of entry.persistent) this.installPersistent('player', p, { sourceCard: card.name });
      }
      // Auto-discard intent: cards saying "discard N plays" set out.discards.
      // Pop from the top of the player's playbook discard pile (placeholder
      // — chooser flow will land in a follow-on UI pass).
      if (out.discards) pmAutoDiscardFromHand('player', out.discards);
      // Wire `out.draws` (61 catalog cards use op:"draw" — every one
      // was a silent no-op before this consumer was added).
      if (out.draws) for (let i = 0; i < out.draws; i++) this.drawPlayCard();
      if (out.heroDraws) {
        for (let i = 0; i < out.heroDraws && this.playerHeroDeck.length; i++) {
          this.playerBench.push(this.playerHeroDeck.shift());
        }
      }
      // protect_self → opponent's negative deltas to player clamp to 0
      // for the rest of THIS battle (Immunity, Indestructible, etc.).
      if (out.protectSelf) PM._playerProtectedThisBattle = true;
      // Player_choice / scare reveal / install_persistent intents
      if (Array.isArray(out.intents) && out.intents.length) {
        pmHandlePlayIntents(out.intents, ctx, out, card);
      }
      // on_dice_roll persistents (Pay The Price et al.) fire only
      // when this play actually rolled — not every battle.
      if (out.firedDiceOrCoin) {
        this.firePersistentTriggers('on_dice_roll', null);
      }
      // Surface extra notifications from ops (peek, swap, choice label, etc.)
      if (out.notifications && out.notifications.length) {
        extraNotifs = extraNotifs.concat(out.notifications);
      }
    }
    if (!structuredHandled) {
      // Reached only when a Play has no JSON entry. With 100% catalog
      // coverage in play-effects.json, this branch should never fire
      // for a real card. The legacy regex resolver was the source of
      // multiple wrong-battle misfires (Overcommited, Lose 1 To Win 2,
      // etc.) — replaced with a no-op + console warning.
      console.warn('⚠️ Play card has no JSON entry — skipping:', card.name);
    }
    if (hdRecovery > 0) {
      this.playerHD = Math.min(10, this.playerHD + hdRecovery);
    }
    if (b) {
      b.playerEffectPower = (b.playerEffectPower || 0) + (effect.playerDelta || 0);
      b.cpuEffectPower = (b.cpuEffectPower || 0) + (effect.cpuDelta || 0);
      // Log this play's contribution to each side's breakdown so the
      // post-resolution 1v1 panel can render "Base + N + M = final".
      if (effect.playerDelta) {
        b.playerBreakdown = b.playerBreakdown || [];
        b.playerBreakdown.push({ label: card.name, delta: effect.playerDelta, cardRef: card });
      }
      if (effect.cpuDelta) {
        b.cpuBreakdown = b.cpuBreakdown || [];
        b.cpuBreakdown.push({ label: card.name, delta: effect.cpuDelta, cardRef: card });
      }
    }
    // Dice/coin reveal — fire a center-screen overlay when the play
    // rolled dice or flipped coins. The captured locals are populated
    // inside the structured-exec block above; referencing `out` here
    // would be a scope error (it lives only inside that block) and
    // would silently throw mid-play, leaving the popup open and the
    // played card never appended to b.playerPlaysPlayed.
    if (firedDiceOrCoinFlag && (diceRollsForReveal.length || coinFlipsForReveal.length)) {
      pmShowDiceCoinReveal({
        side: 'player',
        sourceLabel: card.name,
        diceRolls: diceRollsForReveal,
        coinFlips: coinFlipsForReveal,
      });
    }
    // Build description for the toast (combines HD recovery + power delta when both apply)
    const ability = (card.playAbility || '').toLowerCase();
    let desc = '';
    if (ability.includes('flip a coin')) {
      const success = (effect.playerDelta > 0 || effect.cpuDelta < 0);
      desc = `Coin flip: ${success ? 'Success!' : 'No effect'}`;
    } else if (ability.includes('roll a di') || ability.includes('roll a die')) {
      desc = 'Dice roll';
    }
    const parts = [];
    if (effect.playerDelta > 0) parts.push(`+${effect.playerDelta} to you`);
    if (effect.playerDelta < 0) parts.push(`${effect.playerDelta} to you`);
    if (effect.cpuDelta < 0) parts.push(`${effect.cpuDelta} to opponent`);
    if (effect.cpuDelta > 0) parts.push(`+${effect.cpuDelta} to opponent`);
    if (hdRecovery > 0) parts.push(`+${hdRecovery} HD`);
    if (parts.length) desc += (desc ? ': ' : '') + parts.join(', ');
    // Append any peek/swap/choice notifications from intents
    if (extraNotifs.length) desc += (desc ? ' · ' : '') + extraNotifs.join(' · ');
    const peeks = PM._peekCallouts || [];
    if (peeks.length) {
      desc += (desc ? ' · ' : '') + peeks.join(' · ');
      PM._peekCallouts = [];
    }
    if (!desc) desc = 'No power change';
    this.lastEffectResult = { card, playerDelta: effect.playerDelta, cpuDelta: effect.cpuDelta, description: desc };
    if (b) b.playerPlaysPlayed.push(card);
    this.playerPlayHand.splice(handIdx, 1);
    this.playerDiscard.push(card);
    return true;
  },

  cpuDoSub() {
    if (this.cpuSubstituted || this.cpuBench.length === 0) {
      this.cpuSubstituted = true; return false;
    }
    if (pmIsBlocked('cpu', 'block_sub')) {
      this.cpuSubstituted = true; return false;
    }
    const freeSub = !!(PM._freeSub && PM._freeSub.cpu);
    const transfer = PM._subCostTransfer && PM._subCostTransfer.cpu;
    const subCost = freeSub ? 0 : 2;
    if (!transfer && this.cpuHD < subCost) {
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
      // Capture the displaced hero so the callout can render it. Per
      // strict BoBA rules the player wouldn't see this; in practice
      // we trade rule fidelity for teaching value (player can read
      // the power swing of the swap).
      const displaced = b.cpuCard;
      // Per rules: original hero goes to discard, bench card replaces it
      this.battles[this.currentBattle].cpuCard = bestCard;
      this.cpuBench.splice(bestIdx, 1); // remove from bench (original hero discarded)
      if (transfer && transfer.payer === 'player') {
        this.playerHD = Math.max(0, this.playerHD - subCost);
        delete PM._subCostTransfer.cpu;
      } else {
        this.cpuHD -= subCost;
      }
      if (freeSub) delete PM._freeSub.cpu;
      // Draw a replacement hero from CPU's deck to refill bench
      if (this.cpuHeroDeck.length > 0) {
        this.cpuBench.push(this.cpuHeroDeck.shift());
      }
      this.cpuSubstituted = true;
      PM._pendingCpuSubDisplaced = displaced || null;
      PM._pendingCpuSubFree = freeSub;
      return true;
    }
    this.cpuSubstituted = true;
    return false;
  },

  // CPU play cards queue — filled by cpuDoPlay, shown as overlay one by one
  cpuPlayQueue: [],

  cpuDoPlay() {
    if (this.cpuPassedPlays) return;
    // Set the passed flag at the TOP, before any work runs. Any re-
    // entry — synchronous or otherwise — bails on the guard above
    // instead of populating cpuPlayQueue twice. The original code
    // set this at the bottom (line ~4641) which left a window where
    // another caller could pass the guard while the first call was
    // still mid-loop.
    this.cpuPassedPlays = true;
    if (pmIsBlocked('cpu', 'block_plays')) {
      return;
    }
    const b = this.battles[this.currentBattle];
    this.cpuPlayQueue = [];

    // Smart pacing — distribute remaining plays across remaining
    // battles instead of dumping early. Mirrors the iOS heuristic
    // in PracticeStore.cpuPreparePlayTurn.
    const battlesPlayed   = this.currentBattle;
    const battlesLeft     = Math.max(1, 7 - battlesPlayed);
    const futureBattles   = Math.max(0, battlesLeft - 1);
    const reserveForLater = futureBattles;
    const availableForNow = Math.max(0, this.cpuPlayCount - reserveForLater);
    const fairShare       = Math.max(1, Math.floor(availableForNow / battlesLeft));
    let numPlays          = Math.min(this.cpuPlayCount, fairShare);

    // Stakes bump — high-stakes battles get one extra play
    const cpuLossesSoFar = this.battles
      .slice(0, this.currentBattle)
      .filter(slot => slot.result === 'win')   // player win == cpu loss
      .length;
    const mustWin = cpuLossesSoFar >= 3 || this.currentBattle >= 6;
    if (mustWin) numPlays = Math.min(this.cpuPlayCount, numPlays + 1);

    // Situational nudge — if currently losing the power race, play
    // one MORE; if comfortably winning, play one LESS.
    const losing = (b.cpuCard?.power || 0) + (b.cpuEffectPower || 0)
                 < (b.playerCard?.power || 0) + (b.playerEffectPower || 0);
    if (losing) numPlays = Math.min(this.cpuPlayCount, numPlays + 1);

    // HD-conservation pullback — preserve fuel for next battle's sub
    if (this.cpuHD <= 2 && numPlays > 1) numPlays -= 1;

    // Floor / ceiling — never more than 4 in one battle, never < 0
    numPlays = Math.max(0, Math.min(numPlays, 4));
    // Restricted List soft cap (cap_opponent_plays.max). When set,
    // CPU's per-battle play count is bounded by it in addition to
    // the engine's natural numPlays.
    if (PM._cpuPlayCapThisBattle != null) {
      numPlays = Math.min(numPlays, PM._cpuPlayCapThisBattle);
    }

    for (let i = 0; i < numPlays; i++) {
      if (this.cpuHD < 1 || this.cpuPlayCount <= 0 || this.cpuPlayPool.length === 0) break;
      // Pick an affordable, legal card from CPU's play pool
      const affordable = this.cpuPlayPool.filter(c =>
        pmEffectiveCost(c, 'cpu') <= this.cpuHD && pmIsPlayable(c, 'cpu'));
      if (affordable.length === 0) break;
      const card = affordable[Math.floor(Math.random() * affordable.length)];
      const cost = pmEffectiveCost(card, 'cpu');

      // Leave It To Chance: player's dice_gate persistent forces a roll.
      // Failed gate cancels the play (cost still consumed).
      const gate = pmCheckPlayGate('cpu');
      if (gate && !gate.passed) {
        this.cpuHD -= cost;
        this.cpuPlayCount--;
        const poolIdx0 = this.cpuPlayPool.indexOf(card);
        if (poolIdx0 >= 0) this.cpuPlayPool.splice(poolIdx0, 1);
        pmEnqueueNotification(`🎲 ${gate.roll} — ${card.name} cancelled by Leave It To Chance`);
        continue;
      }
      if (gate && gate.passed) {
        pmEnqueueNotification(`🎲 ${gate.roll} — ${card.name} survives the gate`);
      }
      // Scare Tactics: if the player pre-revealed last battle and
      // CPU's play meets the cost threshold, fire the revealed
      // card free for the player.
      pmMaybeFireScareReveal('cpu', cost);

      this.cpuHD -= cost;
      this.cpuPlayCount--;
      // Remove from pool
      const poolIdx = this.cpuPlayPool.indexOf(card);
      if (poolIdx >= 0) this.cpuPlayPool.splice(poolIdx, 1);

      // Apply effect — structured executor first, regex fallback
      let effect = { playerDelta: 0, cpuDelta: 0 };
      // Persistent specs the executor produces — held until the
      // user dismisses this card's overlay (see dismiss path).
      let deferredPersistents = [];
      let hdRecovery = 0;
      let structuredHandled = false;
      const entry = pmGetPlayEntry(card);
      const cpuHasEffects    = entry && Array.isArray(entry.effects) && entry.effects.length > 0;
      const cpuHasPersistent = entry && Array.isArray(entry.persistent) && entry.persistent.length > 0;
      if (entry && (cpuHasEffects || cpuHasPersistent)) {
        const ctx = pmMakeExecContext('cpu');
        ctx._sourceCard = card.name || '';
        PM._currentlyResolvingPlayCard = card.name || '';
        const out = pmExecStructured(entry, ctx);
        // Flip perspective back to queue's player/cpu convention
        effect.playerDelta = out.oppDelta;
        effect.cpuDelta = out.selfDelta;
        // protect_self mirror: CPU playing → playerDelta lands on
        // player. Clamp if player is protected this battle.
        if (PM._playerProtectedThisBattle && effect.playerDelta < 0) effect.playerDelta = 0;
        this.applyHDRecover('cpu',    out.selfHDDelta);
        this.applyHDRecover('player', out.oppHDDelta);
        structuredHandled = true;
        // Surface peek/swap/choice notifications from CPU plays
        if (out.notifications && out.notifications.length) {
          PM._peekCallouts = (PM._peekCallouts || []).concat(out.notifications);
        }
        // Defer persistent installs until the user dismisses THIS
        // play's overlay. Without this, when CPU plays cards 1, 2, 3
        // in sequence the active-effects banner would expose card 2's
        // persistent before the user has seen card 2's overlay —
        // spoiling the reveal.
        if (out.hasPersistent && entry.persistent) {
          deferredPersistents = entry.persistent.slice();
        }
        if (out.discards) pmAutoDiscardFromHand('cpu', out.discards);
        // Wire CPU-side draws — cpuPlayCount is the fluid pool budget.
        if (out.draws) this.cpuPlayCount = (this.cpuPlayCount || 0) + out.draws;
        if (out.heroDraws) {
          for (let i = 0; i < out.heroDraws && this.cpuHeroDeck.length; i++) {
            this.cpuBench.push(this.cpuHeroDeck.shift());
          }
        }
        if (out.protectSelf) PM._cpuProtectedThisBattle = true;
        if (Array.isArray(out.intents) && out.intents.length) {
          pmHandlePlayIntents(out.intents, ctx, out, card);
        }
        if (out.firedDiceOrCoin) {
          this.firePersistentTriggers('on_dice_roll', null);
        }
      }
      if (!structuredHandled) {
        // Same dead-code guard as player path; legacy regex resolver
        // removed because every catalog card has a JSON entry.
        console.warn('⚠️ CPU play card has no JSON entry — skipping:', card.name);
      }
      if (hdRecovery > 0) this.cpuHD = Math.min(10, this.cpuHD + hdRecovery);
      b.cpuEffectPower = (b.cpuEffectPower || 0) + (effect.cpuDelta || 0);
      b.playerEffectPower = (b.playerEffectPower || 0) + (effect.playerDelta || 0);
      // Mirror player-side breakdown logging so the 1v1 panel can show
      // CPU's contributions too.
      if (effect.cpuDelta) {
        b.cpuBreakdown = b.cpuBreakdown || [];
        b.cpuBreakdown.push({ label: card.name, delta: effect.cpuDelta, cardRef: card });
      }
      if (effect.playerDelta) {
        b.playerBreakdown = b.playerBreakdown || [];
        b.playerBreakdown.push({ label: card.name, delta: effect.playerDelta, cardRef: card });
      }
      // CPU plays are surfaced via the existing pm-cpu-overlay queue,
      // which shows each card with its effect text. Firing a separate
      // dice/coin reveal during cpuDoPlay() races the queue and pops a
      // full-screen overlay before the user sees what the CPU played.
      // The dice values are already in entry.notifications and the
      // toast pipeline. Skip the synchronous fullscreen reveal for CPU.
      // Track CPU plays on the battle slot (for copy_last_play, metrics, etc.)
      b.cpuPlaysPlayed = b.cpuPlaysPlayed || [];
      b.cpuPlaysPlayed.push(card);
      const notifs = PM._peekCallouts && PM._peekCallouts.length ? PM._peekCallouts.splice(0) : [];
      this.cpuPlayQueue.push({
        card, cost, effect,
        hdRecovery: hdRecovery > 0 ? hdRecovery : undefined,
        notifications: notifs,
        deferredPersistents: deferredPersistents || [],
      });
    }
    // (cpuPassedPlays already set at top — re-entry guard.)
  },

  // Dry-run: compute the pending power delta that installed continuous/battle_start
  // persistents will apply to an unrevealed battle for the given side.
  // Returns 0 for already-revealed battles (their delta is already in effectPower).
  // ── B.1 weapon transform + active-effect surface ────────────────

  // Snapshot of transforms in scope right now (used by ctx & UI).
  _activeWeaponTransforms() {
    return (this._weaponTransforms || []).filter(t =>
      pmIsScopeActive(t.scope, t.installedAt, this.currentBattle)
    );
  },

  effectiveWeapon(card, side) {
    if (!card) return '';
    return pmResolveWeapon(card, side, this._activeWeaponTransforms());
  },

  isWeaponTransformed(card, side) {
    if (!card) return false;
    return this.effectiveWeapon(card, side) !== (card.element || '');
  },

  // Central persistent-install. Splits weapon_transform persistents
  // into PM._weaponTransforms; everything else routes to _persistents.
  // Pushes a banner-friendly summary into PM._activeEffectsLog so the
  // UI can render "what's currently in force" without re-walking
  // everything every frame.
  installPersistent(owner, spec, opts) {
    if (!this._weaponTransforms) this._weaponTransforms = [];
    if (!this._persistents)      this._persistents = [];
    // Source-card attribution. Direct installs pass it via opts;
    // child installs (via install_persistent op) inherit from the
    // parent's source through PM._inheritedInstallSource.
    const sourceCard = (opts && opts.sourceCard)
      || PM._inheritedInstallSource
      || '';
    const eff = spec && spec.effect;
    if (eff && eff.op === 'weapon_transform') {
      const to = eff.to || '';
      if (!to) return;
      const t = {
        owner: owner,
        installedAt: this.currentBattle,
        scope: spec.scope || 'rest_of_game',
        target: eff.target || 'self',
        to: to,
        from: (eff.from && eff.from !== '') ? eff.from : null,
        sourceCard,
      };
      this._weaponTransforms.push(t);
      this._appendActiveEffectsLog({
        owner: owner,
        label: this._weaponTransformLabel(t),
        kind: 'transform',
      });
      return;
    }
    this._persistents.push({ owner, spec, installedAt: this.currentBattle, sourceCard });
    const label = this._persistentSummaryLabel(spec, owner);
    if (label) this._appendActiveEffectsLog({ owner, label, kind: 'persistent' });
  },

  _weaponTransformLabel(t) {
    const scope = pmScopeDisplayLabel(t.scope);
    switch (t.target) {
      case 'all_heroes': return `All Heroes → ${t.to} weapons ${scope}`;
      case 'self':       return t.from
                                ? `Your ${t.from} Heroes → ${t.to} weapons ${scope}`
                                : `Your Heroes → ${t.to} weapons ${scope}`;
      case 'opponent':   return `Opponent's Heroes → ${t.to} weapons ${scope}`;
      default:           return `Weapon transform → ${t.to} ${scope}`;
    }
  },

  _persistentSummaryLabel(spec, owner) {
    const eff = spec && spec.effect;
    if (!eff) return null;
    const op = eff.op || '';
    const scope = pmScopeDisplayLabel(spec.scope || 'this_battle');
    const who = owner === 'player' ? 'You' : 'CPU';
    // Triggered persistents wear a short prefix so multi-branch cards
    // (Win or Weiners installs one for on_battle_win + one for
    // on_battle_loss) read as "if win → draw" / "if loss → recover"
    // instead of two visually-identical pills.
    const trigger = (spec && spec.trigger) || '';
    const prefix = (
      trigger === 'on_battle_win'     ? 'On win: ' :
      trigger === 'on_battle_loss'    ? 'On loss: ' :
      trigger === 'on_plays_resolved' ? 'After plays: ' :
      trigger === 'on_battle_start'   ? 'Battle start: ' :
      trigger === 'on_opp_play'       ? 'On opponent play: ' :
      trigger === 'on_turn_end'       ? 'End of turn: ' :
      ''
    );
    const wrap = body => prefix ? `${prefix}${body}` : body;
    switch (op) {
      case 'modify_hd_recover':
        if (eff.cap != null)   return wrap(`HD recovery capped at ${eff.cap} ${scope}`);
        if (eff.delta != null) return wrap(`HD recovery ${eff.delta > 0 ? '+' : ''}${eff.delta} ${scope}`);
        return wrap(`HD recovery modifier active ${scope}`);
      case 'redirect_hd_recover':
        return wrap(`${who}: redirect HD recovery ${scope}`);
      case 'block_hd_recover': {
        const target = eff.target || 'self';
        if (target === 'both')     return wrap(`Neither side recovers HDs ${scope}`);
        if (target === 'opponent') return wrap(`Opponent can't recover HDs ${scope}`);
        return wrap(`${who} can't recover HDs ${scope}`);
      }
      case 'auto_lose_battle':    return wrap(`Lose any battle with 0 HDs ${scope}`);
      case 'require_dice_roll':   return wrap(`Opponent must roll dice to play ${scope}`);
      case 'allow_hd_overspend':  return wrap(`${who} can overspend HDs by ${eff.max_deficit || 0} ${scope}`);
      case 'power': {
        if (eff.delta != null) {
          const target = eff.target || 'self';
          const recipient = target === 'opponent'
            ? (owner === 'player' ? 'CPU Hero' : 'Your Hero')
            : (owner === 'player' ? 'Your Hero' : 'CPU Hero');
          return wrap(`${recipient} ${eff.delta > 0 ? '+' : ''}${eff.delta} ${scope}`);
        }
        return null;
      }
      case 'hd_recover': {
        const amount = (typeof eff.amount === 'number') ? `${eff.amount} HD`
                     : (eff.amount === 'all') ? 'all HDs' : 'HDs';
        const target = eff.target || 'self';
        const recipient = target === 'opponent'
          ? (owner === 'player' ? 'CPU' : 'You')
          : (owner === 'player' ? 'You' : 'CPU');
        return wrap(`${recipient} recover ${amount} ${scope}`);
      }
      case 'draw': {
        const n = (typeof eff.count === 'number') ? eff.count : 1;
        const kind = eff.kind === 'hero' ? 'Hero' : 'Play';
        return wrap(`${who} draw ${n} ${kind}${n === 1 ? '' : 's'} ${scope}`);
      }
      default:
        // Don't surface unmapped ops as cryptic "you installed
        // some_op_name" pills. Returning null suppresses the pill
        // entirely; the engine still applies the effect, the user
        // just doesn't see a confusing label for it. Better silence
        // than jargon.
        return null;
    }
  },

  // Live banner data — reads BOTH transforms and persistents, filtered
  // to in-scope only. Each entry: {id, owner, label, icon, color,
  // remaining}. `remaining` is the count of battles left for finite
  // scopes; null for rest_of_game.
  activeEffectsForUI() {
    const rows = [];
    let id = 0;
    for (const t of (this._weaponTransforms || [])) {
      if (!pmIsScopeActive(t.scope, t.installedAt, this.currentBattle)) continue;
      rows.push({
        id: ++id, owner: t.owner,
        label: this._weaponTransformLabel(t),
        icon: 'transform', color: '#8B00FF',
        remaining: pmBattlesRemaining(t.scope, t.installedAt, this.currentBattle, null),
        sourceCard: t.sourceCard || '',
      });
    }
    // One pill per active persistent. The previous attempt to dedupe
    // multi-branch cards by (owner, sourceCard, scope) caused the
    // banner to disappear entirely in some cases. Instead we add a
    // trigger prefix to each body in _persistentSummaryLabel, so
    // multi-branch cards (Win or Weiners) read as "if win → draw" vs
    // "if loss → recover 2 HD" — distinct bodies under the same
    // sourceCard eyebrow.
    for (const inst of (this._persistents || [])) {
      const scope = inst.spec && inst.spec.scope;
      if (!pmIsScopeActive(scope, inst.installedAt, this.currentBattle, inst.spec)) continue;
      const label = this._persistentSummaryLabel(inst.spec, inst.owner);
      if (!label) continue;
      rows.push({
        id: ++id, owner: inst.owner, label,
        icon: 'persistent', color: '#00F5FF',
        remaining: pmBattlesRemaining(scope, inst.installedAt, this.currentBattle, inst.spec),
        sourceCard: inst.sourceCard || '',
      });
    }
    return rows;
  },

  _appendActiveEffectsLog(entry) {
    // No-op stub today — banner re-renders from activeEffectsForUI()
    // after every battle update so we don't need a separate log.
    // Keeping the hook so future code can persist a "trigger fired"
    // history surfaced by the post-battle summary.
  },

  // ── B.2 / B.4 / B.9 trigger dispatch ────────────────────────────
  //
  // One entry point for every non-continuous trigger (on_plays_resolved,
  // on_battle_win, on_battle_loss, on_battle_start, on_turn_end). Walks
  // _persistents, runs each matching block's effect, and writes any
  // produced power deltas back into the current slot's effectPower so
  // late-firing boosts can sway the battle they fire in.
  firePersistentTriggers(trigger, winner /* 'player' | 'cpu' | null */) {
    const b = this.battles[this.currentBattle];
    if (!b) return;
    for (const inst of (this._persistents || [])) {
      const persistentTrigger = inst.spec && inst.spec.trigger;
      if (persistentTrigger !== trigger) continue;
      const scope = inst.spec && inst.spec.scope;
      if (!pmIsScopeActive(scope, inst.installedAt, this.currentBattle, inst.spec)) continue;
      if (trigger === 'on_battle_win'  && winner != null && inst.owner !== winner) continue;
      if (trigger === 'on_battle_loss' && winner != null && inst.owner === winner) continue;
      const eff = inst.spec.effect;
      if (!eff) continue;
      const ctx = pmMakeExecContext(inst.owner);
      const out = { selfDelta: 0, oppDelta: 0, selfHDDelta: 0, oppHDDelta: 0,
                    draws: 0, discards: 0, hasEffect: false, unknownOps: [], notifications: [] };
      pmExecStep(eff, ctx, out);
      const playerDelta = inst.owner === 'player' ? (out.selfDelta || 0) : (out.oppDelta || 0);
      const cpuDelta    = inst.owner === 'player' ? (out.oppDelta  || 0) : (out.selfDelta || 0);
      b.playerEffectPower = (b.playerEffectPower || 0) + playerDelta;
      b.cpuEffectPower    = (b.cpuEffectPower    || 0) + cpuDelta;
      // Surface the firing — without a callout the user sees numbers
      // change with no explanation.
      if (playerDelta || cpuDelta || (out.notifications && out.notifications.length)) {
        const recipientDelta = inst.owner === 'player' ? playerDelta : cpuDelta;
        const oppDeltaToOwner = inst.owner === 'player' ? cpuDelta : playerDelta;
        let parts = [];
        if (recipientDelta) {
          parts.push(`${inst.owner === 'player' ? 'Your' : 'CPU'} Hero ${recipientDelta > 0 ? '+' : ''}${recipientDelta}`);
        }
        if (oppDeltaToOwner) {
          parts.push(`${inst.owner === 'player' ? 'CPU' : 'Your'} Hero ${oppDeltaToOwner > 0 ? '+' : ''}${oppDeltaToOwner}`);
        }
        if (out.notifications && out.notifications.length) parts.push(out.notifications.join(', '));
        // Source-card-named prefix: "Make It, Take It (Win)" instead
        // of bare "Win trigger". Falls back to the kind label when no
        // source is recorded (legacy installs).
        const kindLabel = trigger === 'on_battle_win'     ? 'Win'
                        : trigger === 'on_battle_loss'    ? 'Loss'
                        : trigger === 'on_plays_resolved' ? 'End-of-turn'
                        : trigger === 'on_battle_start'   ? 'Battle start'
                        : 'Trigger';
        const prefix = inst.sourceCard
          ? `${inst.sourceCard} (${kindLabel})`
          : `${kindLabel} trigger`;
        pmEnqueueNotification(`${prefix}: ${parts.join(' — ')}`);
      }
    }
  },

  // B.8 Ultimatum Dog — auto_lose_battle persistent fires before normal
  // power compare. Returns the side forced to lose, or null.
  _sideForcedToLoseForZeroHD() {
    for (const inst of (this._persistents || [])) {
      if ((inst.spec && inst.spec.trigger) !== 'on_turn_end') continue;
      const eff = inst.spec.effect;
      if (!eff || eff.op !== 'auto_lose_battle') continue;
      if (!pmIsScopeActive(inst.spec.scope, inst.installedAt, this.currentBattle, inst.spec)) continue;
      const target = eff.target || 'any_with_zero_hd';
      if (target !== 'any_with_zero_hd') continue;
      const playerZero = (this.playerHD || 0) === 0;
      const cpuZero    = (this.cpuHD    || 0) === 0;
      if (playerZero && !cpuZero) return 'player';
      if (cpuZero    && !playerZero) return 'cpu';
      if (playerZero && cpuZero)
        return inst.owner === 'player' ? 'cpu' : 'player';
    }
    return null;
  },

  // ── B.5 HD recover pipeline ─────────────────────────────────────
  applyHDRecover(side, amount) {
    if (!amount) return 0;
    if (amount < 0) {
      if (side === 'player') this.playerHD = Math.max(0, (this.playerHD || 0) + amount);
      else                   this.cpuHD    = Math.max(0, (this.cpuHD    || 0) + amount);
      return amount;
    }
    let actualSide = side;
    let actualAmount = amount;

    // 1. Redirect
    for (const inst of (this._persistents || [])) {
      const eff = inst.spec && inst.spec.effect;
      if (!eff || eff.op !== 'redirect_hd_recover') continue;
      if (!pmIsScopeActive(inst.spec.scope, inst.installedAt, this.currentBattle, inst.spec)) continue;
      const owner = inst.owner;
      const fromStr = eff.from || 'opponent';
      const toStr   = eff.to   || 'self';
      const fromSide = fromStr === 'self' ? owner : (owner === 'player' ? 'cpu' : 'player');
      const toSide   = toStr   === 'self' ? owner : (owner === 'player' ? 'cpu' : 'player');
      if (actualSide === fromSide) actualSide = toSide;
    }

    // 2. Cap + 3. Delta
    for (const inst of (this._persistents || [])) {
      const eff = inst.spec && inst.spec.effect;
      if (!eff || eff.op !== 'modify_hd_recover') continue;
      if (!pmIsScopeActive(inst.spec.scope, inst.installedAt, this.currentBattle, inst.spec)) continue;
      const targetStr = eff.target || 'both';
      let applies;
      switch (targetStr) {
        case 'both': applies = true; break;
        case 'self': applies = actualSide === inst.owner; break;
        default:     applies = actualSide !== inst.owner;
      }
      if (!applies) continue;
      if (eff.cap   != null) actualAmount = Math.min(actualAmount, eff.cap);
      if (eff.delta != null) actualAmount += eff.delta;
    }

    // 4. Block
    if (pmIsBlocked(actualSide, 'block_hd_recover')) {
      pmEnqueueNotification(`${actualSide === 'player' ? 'You' : 'CPU'} blocked from HD recovery`);
      return 0;
    }
    actualAmount = Math.max(0, actualAmount);
    if (actualSide === 'player') this.playerHD = Math.min(10, (this.playerHD || 0) + actualAmount);
    else                          this.cpuHD    = Math.min(10, (this.cpuHD    || 0) + actualAmount);

    if (actualAmount !== amount || actualSide !== side) {
      const from = side === 'player' ? 'You' : 'CPU';
      const to   = actualSide === 'player' ? 'You' : 'CPU';
      pmEnqueueNotification(actualSide !== side
        ? `HD recovery redirected: ${from} → ${to} (+${actualAmount})`
        : `HD recovery: ${to} +${actualAmount} (modified from +${amount})`);
    }
    return actualAmount;
  },

  previewPersistentPower(battleIdx, side /* 'player' | 'cpu' */) {
    const b = this.battles[battleIdx];
    if (!b || b.revealed) return 0;
    let total = 0;
    for (const inst of (this._persistents || [])) {
      const scope = inst.spec && inst.spec.scope;
      const trigger = inst.spec && inst.spec.trigger;
      if (trigger !== 'continuous' && trigger !== 'battle_start') continue;
      const inScope = pmIsScopeActive(scope, inst.installedAt, battleIdx, inst.spec);
      if (!inScope || !inst.spec.effect) continue;
      // Build a context rooted at the owner but pointing at the previewed battle.
      const ctx = pmMakeExecContext(inst.owner);
      ctx.battleIdx = battleIdx;
      ctx.selfCard = inst.owner === 'player' ? b.playerCard : b.cpuCard;
      ctx.oppCard  = inst.owner === 'player' ? b.cpuCard    : b.playerCard;
      const out = { selfDelta: 0, oppDelta: 0, selfHDDelta: 0, oppHDDelta: 0, draws: 0, discards: 0, hasEffect: false, unknownOps: [], notifications: [] };
      pmExecStep(inst.spec.effect, ctx, out);
      if (!out.hasEffect) continue;
      if (inst.owner === side) total += (out.selfDelta || 0);
      else                     total += (out.oppDelta  || 0);
    }
    return total;
  },

  // Apply continuous/battle-scoped persistents (Fire Boost, etc.) at reveal.
  // Only `continuous` trigger with a `power` effect is resolved here —
  // scoped persistents with other triggers are tracked but not yet executed.
  applyContinuousPersistents() {
    if (!this._persistents || !this._persistents.length) return;
    const b = this.battles[this.currentBattle];
    if (!b) return;
    for (const inst of this._persistents) {
      const scope = inst.spec.scope;
      const trigger = inst.spec.trigger;
      // Scope gating
      const inScope = pmIsScopeActive(scope, inst.installedAt, this.currentBattle, inst.spec);
      if (!inScope) continue;
      if (trigger !== 'continuous' && trigger !== 'battle_start') continue;

      const ctx = pmMakeExecContext(inst.owner);
      const eff = inst.spec.effect;
      if (!eff) continue;
      const out = { selfDelta: 0, oppDelta: 0, selfHDDelta: 0, oppHDDelta: 0, draws: 0, discards: 0, hasEffect: false, unknownOps: [], notifications: [] };
      pmExecStep(eff, ctx, out);
      if (!out.hasEffect) continue;
      // Translate self/opp deltas into player/cpu deltas for the slot
      const playerDelta = inst.owner === 'player' ? (out.selfDelta || 0) : (out.oppDelta || 0);
      const cpuDelta    = inst.owner === 'player' ? (out.oppDelta  || 0) : (out.selfDelta || 0);
      b.playerEffectPower = (b.playerEffectPower || 0) + playerDelta;
      b.cpuEffectPower    = (b.cpuEffectPower    || 0) + cpuDelta;
      // Record for cancel_persistent retroactive rewind
      inst.appliedAtBattle = this.currentBattle;
      inst.appliedPlayerDelta = playerDelta;
      inst.appliedCpuDelta = cpuDelta;
    }
  },

  resolve() {
    // B.2 — fire on_plays_resolved persistents BEFORE we decide the
    // winner. Their power deltas land in effectPower so end-of-turn
    // boosts (Steel Resolve, Baby Phoenix) can swing the verdict.
    this.firePersistentTriggers('on_plays_resolved');

    const b = this.battles[this.currentBattle];
    const playerBase = b.playerTransformedToHotDog ? 0 : (b.playerCard?.power || 0);
    const cpuBase    = b.cpuTransformedToHotDog    ? 0 : (b.cpuCard?.power    || 0);
    const playerPow = playerBase + (b.playerEffectPower || 0);
    const cpuPow    = cpuBase    + (b.cpuEffectPower    || 0);

    // B.8 Ultimatum Dog — auto-loss for any side at 0 HDs supersedes
    // power compare entirely.
    const forcedLoser = this._sideForcedToLoseForZeroHD();
    if (forcedLoser) {
      if (forcedLoser === 'player') { b.result = 'lose'; this.cpuScore++;    this.honors = 'cpu'; }
      else                          { b.result = 'win';  this.playerScore++; this.honors = 'player'; }
      this.firePersistentTriggers(b.result === 'win' ? 'on_battle_win' : 'on_battle_loss', b.result === 'win' ? 'player' : 'cpu');
      this.phase = 'resolution';
      this._showPhaseBanner = true;
      this.checkOver();
      return;
    }

    if (playerPow > cpuPow) {
      b.result = 'win';  this.playerScore++; this.honors = 'player';
    } else if (cpuPow > playerPow) {
      b.result = 'lose'; this.cpuScore++;    this.honors = 'cpu';
    } else {
      // Tie — SUPER weapon wins ONLY in Playmaker mode (§4.3.2 Super Tie Breaker)
      // Rookie/Substitution: tied power = draw, no trophy (§4.1.2, §4.2.2)
      if (this.mode === 'playmaker') {
        // Resolve weapon through transform stack so "Only Fire" + a
        // SUPER-printed hero reads as FIRE here.
        const pW = this.effectiveWeapon(b.playerCard, 'player');
        const cW = this.effectiveWeapon(b.cpuCard,    'cpu');
        const pSuper = pW === 'SUPER';
        const cSuper = cW === 'SUPER';
        if (pSuper && !cSuper) {
          b.result = 'win';  this.playerScore++; this.honors = 'player';
          b.superTiebreaker = { winner: 'player', total: playerPow };
          pmEnqueueNotification(`⚡ TIED at ${playerPow} — ${b.playerCard?.hero || b.playerCard?.name || 'Your hero'}'s SUPER weapon breaks the tie (Rules §4.5)`);
        } else if (cSuper && !pSuper) {
          b.result = 'lose'; this.cpuScore++;    this.honors = 'cpu';
          b.superTiebreaker = { winner: 'cpu', total: cpuPow };
          pmEnqueueNotification(`⚡ TIED at ${cpuPow} — ${b.cpuCard?.hero || b.cpuCard?.name || 'CPU hero'}'s SUPER weapon breaks the tie (Rules §4.5)`);
        } else {
          b.result = 'tie';
        }
      } else {
        b.result = 'tie';
      }
    }

    // B.4 — battle-resolution triggers. on_battle_win fires for the
    // winning side's persistents; on_battle_loss for the loser's.
    if (b.result === 'win') {
      this.firePersistentTriggers('on_battle_win',  'player');
      this.firePersistentTriggers('on_battle_loss', 'player');  // fires CPU's loss persistents
    } else if (b.result === 'lose') {
      this.firePersistentTriggers('on_battle_win',  'cpu');
      this.firePersistentTriggers('on_battle_loss', 'cpu');     // fires player's loss persistents
    }

    this.phase = 'resolution';
    this._showPhaseBanner = true;
    this.checkOver();
  },

  checkOver() {
    if (this.playerScore >= 4) { this.matchOver = true; this.matchWinner = 'player'; this.phase = 'over'; }
    else if (this.cpuScore >= 4) { this.matchOver = true; this.matchWinner = 'cpu'; this.phase = 'over'; }
  },

  nextBattle() {
    if (this.matchOver) return;
    const next = this.currentBattle + 1;
    // Sudden Death — Comprehensive Rules Guide §4.4. After 7
    // battles with the score tied, append an 8th battle to break
    // the tie. Final SD result is final (no further extensions).
    if (next >= 7 && this.playerScore === this.cpuScore && this.battles.length < 8) {
      const sdSlot = {
        id: 7,
        playerCard: this.playerHeroDeck.length ? this.playerHeroDeck.shift() : null,
        cpuCard:    this.cpuHeroDeck.length    ? this.cpuHeroDeck.shift()    : null,
        playerEffectPower: 0, cpuEffectPower: 0,
        playerPlaysPlayed: [], cpuPlaysPlayed: [],
        result: null, revealed: false,
        playerTransformedToHotDog: false, cpuTransformedToHotDog: false,
      };
      this.battles.push(sdSlot);
      pmEnqueueNotification('⚡ Sudden Death — one more battle to decide it');
      // Fall through to currentBattle = next (== 7).
    } else if (next >= 8 || (next >= 7 && this.playerScore !== this.cpuScore)) {
      this.matchOver = true;
      if (this.playerScore > this.cpuScore) this.matchWinner = 'player';
      else if (this.cpuScore > this.playerScore) this.matchWinner = 'cpu';
      else this.matchWinner = null;
      this.phase = 'over';
      return;
    }
    this.currentBattle = next;
    // Reset per-battle protect_self flags (Immunity, Indestructible).
    PM._playerProtectedThisBattle = false;
    PM._cpuProtectedThisBattle = false;
    // Reset per-battle play caps (Restricted List et al).
    PM._playerPlayCapThisBattle = null;
    PM._cpuPlayCapThisBattle = null;
    // Apply pending honors_set
    if (PM._pendingHonors) {
      this.honors = PM._pendingHonors.side;
      if (PM._pendingHonors.scope === 'next_battle') PM._pendingHonors = null;
    }
    // Purge expired blocks
    pmPurgeExpiredBlocks();
    // B.9 — fire on_battle_start triggers for any persistent whose
    // scope matches this battle (e.g. Late Game Push reveals its
    // hd_recover at the start of Battle 7).
    this.firePersistentTriggers('on_battle_start');
    // Fire marked_battle on_reveal effects for this battle
    const fires = (PM._markedBattles || []).filter(m => m.battleIdx === this.currentBattle);
    for (const mark of fires) {
      const ctx = pmMakeExecContext(mark.side);
      const out = { selfDelta: 0, oppDelta: 0, selfHDDelta: 0, oppHDDelta: 0, draws: 0, discards: 0, hasEffect: false, unknownOps: [], notifications: [] };
      for (const s of mark.onReveal) pmExecStep(s, ctx, out);
      if (out.hasEffect) {
        const b = PM.battles[this.currentBattle];
        if (b) {
          if (mark.side === 'player') {
            b.playerEffectPower = (b.playerEffectPower || 0) + (out.selfDelta || 0);
            b.cpuEffectPower    = (b.cpuEffectPower    || 0) + (out.oppDelta  || 0);
          } else {
            b.cpuEffectPower    = (b.cpuEffectPower    || 0) + (out.selfDelta || 0);
            b.playerEffectPower = (b.playerEffectPower || 0) + (out.oppDelta  || 0);
          }
        }
        PM._peekCallouts = (PM._peekCallouts || []).concat([`Marked battle triggered`]);
      }
    }
    PM._markedBattles = (PM._markedBattles || []).filter(m => m.battleIdx !== this.currentBattle);

    // Per rules: Sub phase comes before reveal for non-rookie
    this.phase = this.mode === 'rookie' ? 'reveal' : 'sub';
    this._showPhaseBanner = true;
    this.playerSubstituted = false;
    this.cpuSubstituted = false;
    this.playerPassedPlays = false;
    this.cpuPassedPlays = false;
    this.selectedBenchIdx = null;
  },

  drawPlayCard() {
    if (this.mode !== 'playmaker') return;
    if (pmIsBlocked('player', 'block_draw')) return;
    // UX#9 — auto-reshuffle when the playbook deck is empty. Surface
    // a notification so the user sees the reshuffle happen rather
    // than wondering where the new draws came from.
    if (this.playerPlayDeck.length === 0 && this.playerDiscard.length > 0) {
      const count = this.playerDiscard.length;
      this.playerPlayDeck = shuffle([...this.playerDiscard]);
      this.playerDiscard = [];
      pmEnqueueNotification(`Playbook reshuffled · ${count} cards back into deck`);
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
    <button class="pm-top-help" id="pm-help-btn" aria-label="Replay walkthrough" title="Replay walkthrough">?</button>
    <button class="pm-top-exit" id="pm-exit-btn" aria-label="Exit practice"><i data-lucide="x" class="pm-icon"></i></button>
  </div>

  <!-- ACTIVE EFFECTS BANNER -->
  <div class="pm-active-effects" id="pm-active-effects" hidden></div>

  <!-- PLAY AREA -->
  <div class="pm-play-area">
    <div class="pm-opponent-zone">
      <span class="pm-opp-section-label">OPP</span>
      <div class="pm-opp-bench-area">
        <span class="pm-opp-sub-label">Bench</span>
        <div id="pm-opp-bench" style="display:flex;gap:3px"></div>
      </div>
      <button type="button" class="pm-opp-plays-area" id="pm-opp-plays-btn"
              aria-label="Inspect CPU plays used">
        <span class="pm-opp-sub-label">Plays</span>
        <div class="pm-resource-chip">
          <span class="pm-rc-val" id="pm-opp-plays-val">30</span>
          <span class="pm-rc-label">left</span>
        </div>
      </button>
      <div class="pm-opp-resources">
        <div class="pm-resource-chip">
          ${hdIcon}
          <span class="pm-rc-val" id="pm-opp-hd">10</span>
          <span class="pm-rc-label">HD</span>
        </div>
      </div>
    </div>
    <!-- Horizontal arena: 7 battle columns. The active battle column
         expands to ~80vw and renders the iOS ActiveBattleView 1v1
         layout (player left, VS center, CPU right, breakdown panel
         underneath when resolved). Inactive columns stay narrow with
         the BattleColumnView layout (CPU top, VS middle, player
         bottom). Mirrors PracticeView.arenaView. -->
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
    <button class="pm-discard-stack" id="pm-discard-btn" type="button" aria-label="Inspect your discard pile">
      <div class="pm-deck-icon" style="border-style:dashed;background:transparent;opacity:0.4">
        <i data-lucide="rotate-ccw" class="pm-icon" style="opacity:0.6"></i>
        <span class="pm-di-count" id="pm-discard-count">0</span>
      </div>
      <span class="pm-deck-label">Discard</span>
    </button>
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
  // Final-battle action: B7 or once a side has clinched 4 wins.
  // SD case: B7 with tied score → next press extends to B8.
  const clinched   = (PM.playerScore >= 4) || (PM.cpuScore >= 4);
  const isSDTrigger = PM.currentBattle === 6 && PM.playerScore === PM.cpuScore && !clinched;
  const isFinalAction = clinched
    || (PM.currentBattle === 6 && PM.playerScore !== PM.cpuScore)
    || PM.currentBattle >= 7;
  const labelFor = (def) => isSDTrigger ? 'SUDDEN DEATH' : (isFinalAction ? 'FINISH MATCH' : def);
  const resolutionLabel = labelFor('NEXT →');
  const cleanupLabel    = labelFor('NEXT BATTLE →');
  const btnLabels = {
    sub: 'SKIP SUBS →', reveal: revealLabel, play: 'END TURN →',
    resolution: resolutionLabel, cleanup: cleanupLabel, over: 'PLAY AGAIN',
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

  // Follow-up notifications — CPU plays/subs go first so they are seen before the phase banner
  // (especially important for the resolution flow: user should see CPU plays before the RESOLUTION banner).
  if (PM._pendingCpuSub) {
    PM._pendingCpuSub = false;
    pmQueueCpuSub();
  }
  if (PM._pendingCpuPlays) {
    PM._pendingCpuPlays = false;
    pmQueueCpuPlays();
  }
  // Phase banner — queued after any CPU overlays so the banner marks the transition cleanly
  if (PM.phase !== 'over' && PM._showPhaseBanner) {
    PM._showPhaseBanner = false;
    pmQueuePhaseBanner(phaseNames[PM.phase] || PM.phase.toUpperCase(), 2000);
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
    let pendingHtml = '';
    if (battle) {
      const pending = PM.previewPersistentPower(battle.id, 'cpu');
      if (pending !== 0) {
        const color = pending > 0 ? '#C0392B' : '#00F5FF'; // CPU's +N is bad for you
        pendingHtml = `<span class="pm-bc-pending" style="color:${color}">${pending > 0 ? '+' : ''}${pending}</span>`;
      }
    }
    slot.innerHTML = `<svg width="22" height="30" viewBox="0 0 20 28" fill="none" aria-hidden="true">
      <rect x="1" y="1" width="18" height="26" rx="3" fill="rgba(192,57,43,0.12)" stroke="rgba(192,57,43,0.5)" stroke-width="1.5"/>
      <rect x="3.5" y="3.5" width="13" height="21" rx="1.5" stroke="rgba(192,57,43,0.28)" stroke-width="0.9"/>
      <circle cx="10" cy="14" r="3.5" stroke="rgba(192,57,43,0.25)" stroke-width="0.9"/>
    </svg>${pendingHtml}`;
    return;
  }
  const eff     = battle ? (isOpp ? (battle.cpuEffectPower||0) : (battle.playerEffectPower||0)) : 0;
  const basePow = card.power || 0;
  const effPow  = basePow + eff;
  const imgUrl  = card.imageFile ? thumbUrl(card.imageFile) : null;
  const imgHtml = imgUrl ? `<img class="pm-slot-img" src="${imgUrl}" alt="${card.hero||card.name}" loading="lazy" onerror="this.style.display='none'">` : '';
  // Current applied bonus (shows +N or -N)
  let bonusHtml = '';
  if (eff !== 0) {
    const col = eff > 0 ? (isOpp ? '#8B00FF' : '#00F5FF') : '#C0392B';
    bonusHtml = `<span class="pm-bc-bonus" style="color:${col}">${eff > 0 ? '+' : ''}${eff}</span>`;
  }
  // Pending persistent preview (only if this battle isn't yet revealed)
  let pendingHtml = '';
  if (battle && !battle.revealed) {
    const side = isOpp ? 'cpu' : 'player';
    const pending = PM.previewPersistentPower(battle.id, side);
    if (pending !== 0) {
      const col = pending > 0 ? '#00F5FF' : '#C0392B';
      pendingHtml = `<span class="pm-bc-pending" style="color:${col}">${pending > 0 ? '+' : ''}${pending}</span>`;
    }
  }
  slot.innerHTML = `${imgHtml}<span class="pm-bc-name">${(card.hero||card.name||'').substring(0,8)}</span><span class="pm-bc-power">${effPow}</span>${bonusHtml}${pendingHtml}`;
  if (card.element) {
    const bar = document.createElement('div');
    bar.className = 'pm-bc-element';
    bar.style.background = pmElementColor(card.element);
    slot.appendChild(bar);
  }
}

// Detect if the active battle is being decided by SUPER weapon
// tiebreaker per Rules §4.5: Playmaker mode, totals tied, exactly one
// side has SUPER as effective weapon. Returns { winnerName, total }
// when applicable, otherwise null. Mirrors ActiveBattleView.swift:161.
function pmDetectSuperTiebreaker(b) {
  if (PM.mode !== 'playmaker') return null;
  if (!b || b.result == null || b.result === 'tie') return null;
  const playerTotal = (b.playerCard?.power || 0) + (b.playerEffectPower || 0);
  const cpuTotal    = (b.cpuCard?.power    || 0) + (b.cpuEffectPower    || 0);
  if (playerTotal !== cpuTotal) return null;
  const playerWeapon = PM.effectiveWeapon ? PM.effectiveWeapon(b.playerCard, 'player') : (b.playerCard?.element || '');
  const cpuWeapon    = PM.effectiveWeapon ? PM.effectiveWeapon(b.cpuCard,    'cpu')    : (b.cpuCard?.element    || '');
  if ((playerWeapon === 'SUPER') === (cpuWeapon === 'SUPER')) return null;
  const winner = b.result === 'win' ? b.playerCard : b.cpuCard;
  return {
    winnerName: winner?.hero || winner?.name || 'SUPER hero',
    total: playerTotal,
  };
}

// Render the iOS-faithful ActiveBattleView layout into the column for
// the active battle. Wide horizontal layout: player card (left) → VS
// indicator (center) → CPU card (right), with the breakdown panel
// stacked above when the battle has resolved. Uses the full-resolution
// CDN tier — the active card is hundreds of pixels wide and the thumb
// tier visibly pixelates. Mirrors ActiveBattleView.swift:68–136.
function pmRenderActiveBattleColumn(col, b) {
  const isResolved = b.result !== null;
  // Hash the state that actually affects the rendered output. If
  // nothing's changed since the last render we skip the innerHTML
  // rebuild — which on a busy phase transition was reloading the
  // full-res card images several times in a row, causing input lag
  // that read as "clicks delayed and not related to the interface".
  const stateHash = [
    b.playerCard?.bobaId || '',
    b.cpuCard?.bobaId || '',
    b.playerEffectPower || 0,
    b.cpuEffectPower || 0,
    b.revealed ? 1 : 0,
    b.result || '',
    (b.playerBreakdown || []).length,
    (b.cpuBreakdown || []).length,
    PM.mode || '',
  ].join('|');
  // Pulse heroes whose effect power changed since last render. Mirrors
  // iOS ActiveBattleView's .task(id: playerPulseTrigger) / cpuPulseTrigger.
  const lastPlayerEff = col._lastPlayerEff;
  const lastCpuEff    = col._lastCpuEff;
  const playerPulse = lastPlayerEff !== undefined && lastPlayerEff !== (b.playerEffectPower || 0);
  const cpuPulse    = lastCpuEff    !== undefined && lastCpuEff    !== (b.cpuEffectPower    || 0);
  col._lastPlayerEff = (b.playerEffectPower || 0);
  col._lastCpuEff    = (b.cpuEffectPower    || 0);

  if (col._lastStateHash === stateHash && !playerPulse && !cpuPulse) return;
  col._lastStateHash = stateHash;

  const superTie = pmDetectSuperTiebreaker(b);

  col.innerHTML = `
    <div class="pm-bc-active-inner">
      <div class="pm-bc-active-header">BATTLE ${b.id + 1}</div>
      ${isResolved ? pmRenderBreakdownPanel(b) : ''}
      ${superTie ? pmRenderSuperTiebreakerBanner(superTie) : ''}
      <div class="pm-bc-active-row">
        ${pmRenderActiveHero(b.playerCard, true,  b, false, playerPulse)}
        <div class="pm-bc-active-vs ${isResolved ? 'pm-bc-active-vs--' + b.result : ''}">
          ${isResolved
            ? (b.result === 'win' ? 'WIN' : b.result === 'lose' ? 'LOSS' : 'TIE')
            : 'VS'}
        </div>
        ${pmRenderActiveHero(b.cpuCard, false, b, !(b.revealed || isResolved), cpuPulse)}
      </div>
    </div>
  `;

  // Tap-to-review on breakdown rows (post-resolution).
  col.querySelectorAll('.pm-breakdown-row[data-card-name]').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const name = btn.getAttribute('data-card-name');
      const side = btn.getAttribute('data-side');
      const arr = side === 'player'
        ? (b.playerPlaysPlayed || [])
        : (b.cpuPlaysPlayed || b.cpuPlaysRan || []);
      const card = arr.find(c => c.name === name);
      if (card && typeof pmShowPlayReviewSheet === 'function') {
        pmShowPlayReviewSheet(card);
      }
    });
  });
}

function pmRenderActiveHero(card, isPlayer, b, isFaceDown, pulse) {
  const sideClass = isPlayer ? 'pm-active-hero--player' : 'pm-active-hero--cpu';
  const pulseClass = pulse ? ' pm-active-hero--pulse' : '';
  if (!card) {
    return `<div class="pm-active-hero ${sideClass} pm-active-hero--empty"><span>—</span></div>`;
  }
  if (isFaceDown) {
    let pending = 0;
    try { pending = PM.previewPersistentPower(b.id, 'cpu'); } catch (_) {}
    const pendingHtml = pending !== 0
      ? `<span class="pm-active-hero-pending" style="color:${pending > 0 ? '#C0392B' : '#00F5FF'}">${pending > 0 ? '+' : ''}${pending}</span>`
      : '';
    return `
      <div class="pm-active-hero ${sideClass} pm-active-hero--facedown${pulseClass}">
        <div class="pm-active-hero-card pm-active-hero-card-back">
          <svg viewBox="0 0 60 84" aria-hidden="true">
            <rect x="3" y="3" width="54" height="78" rx="6" fill="rgba(192,57,43,0.12)" stroke="rgba(192,57,43,0.65)" stroke-width="2"/>
            <rect x="9" y="9" width="42" height="66" rx="3" stroke="rgba(192,57,43,0.35)" stroke-width="1.2"/>
            <circle cx="30" cy="42" r="10" stroke="rgba(192,57,43,0.32)" stroke-width="1.2"/>
          </svg>
          ${pendingHtml}
        </div>
        <div class="pm-active-hero-name">CPU</div>
      </div>
    `;
  }
  const eff     = isPlayer ? (b.playerEffectPower || 0) : (b.cpuEffectPower || 0);
  const basePow = card.power || 0;
  const effPow  = basePow + eff;
  // Full-res tier for the active battle hero — the card renders large
  // and the 200px thumb visibly pixelates here.
  const imgUrl  = card.imageFile ? fullUrl(card.imageFile) : null;

  // Effective weapon (resolves through the persistent_weapon_transform
  // stack so e.g. "Only Steel" makes the badge read STEEL with a ⟲
  // marker). Mirrors ActiveBattleView.weaponBadge.
  const printed = card.element || '';
  const effectiveWeapon = PM.effectiveWeapon ? PM.effectiveWeapon(card, isPlayer ? 'player' : 'cpu') : printed;
  const isTransformed = !!effectiveWeapon && effectiveWeapon !== printed;
  const weaponText = effectiveWeapon || printed;
  const weaponColor = isTransformed ? '#8B00FF' : (weaponText ? pmElementColor(weaponText) : 'rgba(255,255,255,0.2)');
  const elColor = printed ? pmElementColor(printed) : 'rgba(255,255,255,0.2)';

  const bonusHtml = eff !== 0
    ? `<span class="pm-active-hero-bonus" style="color:${eff > 0 ? '#00F5FF' : '#C0392B'}">${eff > 0 ? '+' : ''}${eff}</span>`
    : '';

  const imgHtml = imgUrl
    ? `<img class="pm-active-hero-img" src="${imgUrl}" alt="${card.hero || card.name}" loading="lazy" onerror="this.style.display='none'">`
    : '';

  // Border color follows effective weapon when transformed so the
  // visual state ("Only Steel" → steel-bordered card) matches iOS.
  const borderColor = isTransformed ? weaponColor : elColor;

  return `
    <div class="pm-active-hero ${sideClass}${pulseClass}">
      <div class="pm-active-hero-card" style="border-color:${borderColor}">
        ${imgHtml}
        <span class="pm-active-hero-power">${effPow}</span>
        ${bonusHtml}
      </div>
      <div class="pm-active-hero-name">${(card.hero || card.name || '').substring(0, 22)}</div>
      ${weaponText ? `<div class="pm-active-hero-weapon" style="background:${weaponColor}1a;border-color:${weaponColor};color:${weaponColor}">${isTransformed ? '↻ ' : ''}${weaponText}</div>` : ''}
    </div>
  `;
}

// Full-width banner shown post-resolution when SUPER weapon decided
// the battle (Rules §4.5). Mirrors ActiveBattleView.swift:176-208.
function pmRenderSuperTiebreakerBanner(info) {
  return `
    <div class="pm-super-tiebreaker-banner">
      <span class="pm-super-tiebreaker-bolt">⚡</span>
      <div class="pm-super-tiebreaker-text">
        <div class="pm-super-tiebreaker-title">SUPER WEAPON BREAKS TIE</div>
        <div class="pm-super-tiebreaker-body">Both heroes tied at ${info.total} power. ${info.winnerName}'s SUPER weapon wins automatically (Rules §4.5).</div>
      </div>
    </div>
  `;
}

// Two-column itemized power-contribution panel rendered after a battle
// resolves. Each row shows the contributing play's name + delta; tapping
// a row opens the play-review sheet. Mirrors the iOS breakdown panel.
function pmRenderBreakdownPanel(b) {
  const playerBase = b.playerCard ? (b.playerCard.power || 0) : 0;
  const cpuBase    = b.cpuCard    ? (b.cpuCard.power    || 0) : 0;
  const playerFinal = playerBase + (b.playerEffectPower || 0);
  const cpuFinal    = cpuBase    + (b.cpuEffectPower    || 0);
  const playerWon = b.result === 'win';
  const cpuWon    = b.result === 'lose';

  return `
    <div class="pm-breakdown-panel">
      ${pmRenderBreakdownColumn('YOU', playerBase, b.playerBreakdown || [], playerFinal, 'player', playerWon)}
      ${pmRenderBreakdownColumn('CPU', cpuBase,    b.cpuBreakdown    || [], cpuFinal,    'cpu',    cpuWon)}
    </div>
  `;
}

function pmRenderBreakdownColumn(label, base, contribs, finalPow, side, isWinner) {
  const rows = contribs.map(c => {
    const delta = c.delta || 0;
    const sign = delta > 0 ? '+' : '';
    const cls  = delta > 0 ? 'pm-breakdown-pos' : 'pm-breakdown-neg';
    return `
      <button type="button" class="pm-breakdown-row" data-card-name="${(c.label || '').replace(/"/g, '&quot;')}" data-side="${side}">
        <span class="pm-breakdown-label">${c.label || '—'}</span>
        <span class="pm-breakdown-delta ${cls}">${sign}${delta}</span>
      </button>
    `;
  }).join('');
  return `
    <div class="pm-breakdown-col ${isWinner ? 'pm-breakdown-col--winner' : ''}">
      <div class="pm-breakdown-header">
        <span class="pm-breakdown-side">${label}</span>
        <span class="pm-breakdown-base">Base ${base}</span>
      </div>
      <div class="pm-breakdown-rows">${rows || '<div class="pm-breakdown-empty">No effects</div>'}</div>
      <div class="pm-breakdown-total">
        <span>Total</span>
        <span class="pm-breakdown-final">${finalPow}</span>
      </div>
    </div>
  `;
}

// Static mini-column DOM for an inactive battle. Re-applied whenever
// a column transitions FROM active back to inactive so the column
// owns the right child structure.
function pmResetMiniColumnDOM(col, idx) {
  col.innerHTML = `
    <span class="pm-bc-number">B${idx + 1}</span>
    <div class="pm-bc-opp"></div>
    <div class="pm-bc-vs"><span>·</span></div>
    <div class="pm-bc-player"></div>
  `;
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
    const wasActive = col.classList.contains('active');

    col.className = 'pm-bc' +
      (isActive  ? ' active'  : '') +
      (isDone ? (b.result === 'win' ? ' won' : b.result === 'lose' ? ' lost' : ' tied') : '') +
      (isPending ? ' pending' : '');

    if (isActive) {
      // Replace the column body with the iOS-faithful 1v1 layout +
      // breakdown panel (post-resolution).
      pmRenderActiveBattleColumn(col, b);
    } else {
      // Restore mini-column DOM if this column was previously active.
      if (wasActive || !col.querySelector('.pm-bc-vs')) {
        pmResetMiniColumnDOM(col, idx);
      }

      // VS bar
      const vsBar = col.querySelector('.pm-bc-vs');
      if (vsBar) {
        vsBar.className = 'pm-bc-vs' + (b.result === 'win' ? ' win' : b.result === 'lose' ? ' lose' : b.result === 'tie' ? ' tied' : '');
        const s = vsBar.querySelector('span');
        if (s) s.textContent = b.result === 'win' ? 'WIN' : b.result === 'lose' ? 'LOSS' : b.result === 'tie' ? 'TIE' : '·';
      }

      // Opponent slot
      const oppSlot = col.querySelector('.pm-bc-opp');
      if (oppSlot) pmRenderBattleSlotContent(oppSlot, b.cpuCard, b.revealed || isDone, true, b);

      // Player slot
      const playerSlot = col.querySelector('.pm-bc-player');
      if (playerSlot) pmRenderBattleSlotContent(playerSlot, b.playerCard, true, false, b);
    }
  }

  // Auto-scroll the active battle into view ONLY when the active
  // battle changes — firing every render kicked off a smooth-scroll
  // animation on every state update, which on touch devices defers
  // the next click and made the UI feel disconnected from input.
  // Mirrors iOS ScrollViewReader.scrollTo(_, anchor:.center) which
  // also only fires on currentBattle change.
  if (pmUpdateBattleCols._lastActive !== PM.currentBattle) {
    pmUpdateBattleCols._lastActive = PM.currentBattle;
    pmScrollActiveIntoView();
  }
}

function pmScrollActiveIntoView() {
  const arena = document.querySelector('#practice-playmat .pm-arena-zone');
  if (!arena) return;
  const active = arena.querySelector('.pm-bc.active');
  if (!active) return;
  active.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
}


// Animated reveal for dice rolls and coin flips. Mirrors iOS
// DiceCoinRevealOverlay — large glyphs spin briefly, settle on the
// real result, then auto-dismiss after ~1.6s (or tap to dismiss
// once settled).
function pmShowDiceCoinReveal({ side, sourceLabel, diceRolls, coinFlips }) {
  // Don't stack multiple reveals — replace any in-flight one.
  document.getElementById('pm-dice-coin-overlay')?.remove();

  const accent = side === 'player' ? '#00F5FF' : '#C77DFF';
  const dieFaces = ['⚀','⚁','⚂','⚃','⚄','⚅'];
  const titleParts = [];
  if (coinFlips.length) titleParts.push(coinFlips.length > 1 ? 'COIN FLIPS' : 'COIN FLIP');
  if (diceRolls.length) titleParts.push(diceRolls.length > 1 ? 'DICE ROLL' : 'DIE ROLL');
  const title = titleParts.join(' + ') || 'ROLL';

  const overlay = document.createElement('div');
  overlay.id = 'pm-dice-coin-overlay';
  overlay.className = 'pm-dice-coin-overlay';
  overlay.setAttribute('role', 'alert');
  overlay.setAttribute('aria-label', title);

  const diceHtml = diceRolls.map(r => {
    const face = (r >= 1 && r <= 6) ? dieFaces[r - 1] : '?';
    return `<div class="pm-dice-coin-die" data-final="${r}" style="color:${accent};border-color:${accent}">
              <span class="pm-dice-coin-glyph">${face}</span>
              <span class="pm-dice-coin-value">${r}</span>
            </div>`;
  }).join('');
  const coinsHtml = coinFlips.map(f => {
    return `<div class="pm-dice-coin-coin" data-final="${f}" style="color:${accent};border-color:${accent}">
              <span class="pm-dice-coin-coin-glyph">🪙</span>
              <span class="pm-dice-coin-coin-label">${f}</span>
            </div>`;
  }).join('');

  overlay.innerHTML = `
    <div class="pm-dice-coin-card">
      ${sourceLabel ? `<div class="pm-dice-coin-source">${pmEscapeHTML(sourceLabel).toUpperCase()}</div>` : ''}
      <div class="pm-dice-coin-title" style="color:${accent}">${title}</div>
      <div class="pm-dice-coin-row">${coinsHtml}${diceHtml}</div>
      <div class="pm-dice-coin-hint">Tap to continue</div>
    </div>
  `;
  document.body.appendChild(overlay);

  // Settled state shows the "Tap to continue" hint, but the overlay is
  // dismissable on tap from the moment it appears — blocking input
  // during the spin caused next-phase / play-card buttons underneath
  // to swallow taps. Auto-dismiss kicks in if the user isn't paying
  // attention.
  const spinDuration = 850;
  const settledTimer = setTimeout(() => {
    overlay.classList.add('pm-dice-coin-overlay--settled');
  }, spinDuration);
  const autoDismiss = setTimeout(() => {
    clearTimeout(settledTimer);
    overlay.remove();
  }, spinDuration + 1400);
  overlay.addEventListener('click', () => {
    clearTimeout(settledTimer);
    clearTimeout(autoDismiss);
    overlay.remove();
  });
}

/// UX#7 — review sheet for a played card. Shared by tap-on-chip
/// from the plays-used row. Mirrors iOS PlayReviewSheet visually.
function pmShowPlayReviewSheet(card) {
  const existing = document.getElementById('pm-play-review-overlay');
  if (existing) existing.remove();
  const overlay = document.createElement('div');
  overlay.id = 'pm-play-review-overlay';
  overlay.className = 'modal-overlay pm-modal-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', `Review play: ${card.name || ''}`);

  const fullBase = (window.BOBA && window.BOBA.fullUrl)
    ? window.BOBA.fullUrl(card.imageFile)
    : (card.imageFile
        ? `https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev/full/${card.imageFile}`
        : '');
  const imgHtml = card.imageFile
    ? `<img class="pm-prs-image" src="${fullBase}" alt="">`
    : '';
  const cost = card.playCost;
  const costHtml = (cost === 0)
    ? `<span class="pm-prs-chip pm-prs-chip--free">FREE</span>`
    : (cost != null ? `<span class="pm-prs-chip">${cost} HD</span>` : '');
  const bonusHtml = card.isBonusPlay
    ? `<span class="pm-prs-chip pm-prs-chip--bonus">★ BONUS</span>` : '';
  const ability = card.playAbility ? pmEscapeHTML(card.playAbility) : 'No effect text on file.';

  overlay.innerHTML = `
    <div class="pm-play-review">
      <div class="pm-prs-header">
        <h2>${pmEscapeHTML(card.name || '')}</h2>
        <button class="pm-prs-close" type="button" aria-label="Close">×</button>
      </div>
      <div class="pm-prs-body">
        ${imgHtml}
        <div class="pm-prs-meta">${costHtml}${bonusHtml}</div>
        <div class="pm-prs-effect-label">EFFECT</div>
        <div class="pm-prs-effect-text">${ability}</div>
      </div>
    </div>`;
  document.body.appendChild(overlay);
  overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
  overlay.querySelector('.pm-prs-close')?.addEventListener('click', () => overlay.remove());
  document.addEventListener('keydown', function escClose(ev) {
    if (ev.key === 'Escape') {
      overlay.remove();
      document.removeEventListener('keydown', escClose);
    }
  });
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
      const safeBenchTitle = pmEscapeHTML(`${card.hero||card.name||''} (${el} ${card.power||0})`);
      return `<div class="pm-bench-card${isSel ? ' selected' : ''}" data-bench-idx="${idx}" title="${safeBenchTitle}">
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
      const nominal   = card.playCost || 0;
      const cost      = pmEffectiveCost(card, 'player');
      const canAfford = PM.playerHD >= cost;
      const modified  = cost !== nominal;
      const isBonus   = cost < nominal;
      const isBonusPlay = card.isBonusPlay === true;
      const name      = (card.name || '').substring(0, 14);
      const imgUrl    = card.imageFile ? thumbUrl(card.imageFile) : null;
      const imgHtml   = imgUrl ? `<img class="pm-pc-img" src="${imgUrl}" alt="" loading="lazy" onerror="this.style.display='none'">` : '';
      // UX#5 — when an active scope shifts the cost, show "3→5" with
      // the original struck through. Color: green if reduced, amber
      // if inflated but affordable, red if unaffordable.
      const costHtml = modified
        ? `<span class="pm-pc-cost pm-pc-cost--${!canAfford ? 'over' : isBonus ? 'discount' : 'inflated'}">
             <s>${nominal}</s>→<strong>${cost > 0 ? cost : 'FREE'}</strong>
           </span>`
        : `<span class="pm-pc-cost">${cost > 0 ? cost + 'HD' : 'FREE'}</span>`;
      // UX#10 — bonus-play distinction. Gold border + ★ BONUS tag.
      const bonusBadge = isBonusPlay
        ? `<span class="pm-pc-bonus-tag">★ BONUS</span>` : '';
      const cardClass = `pm-play-card${!canAfford ? ' cannot-afford' : ''}${isBonusPlay ? ' is-bonus' : ''}`;
      const safeTitle = pmEscapeHTML(`${card.name || ''} — tap to view`);
      const safeName = pmEscapeHTML(name);
      return `<div class="${cardClass}" data-hand-idx="${idx}" title="${safeTitle}">
        ${imgHtml}
        ${bonusBadge}
        <div class="pm-pc-header">
          <span class="pm-pc-name">${safeName}</span>
          ${costHtml}
        </div>
      </div>`;
    }).join('');
  }

  // Deck counts
  const hdEl  = $('pm-hero-deck-count');
  const plEl  = $('pm-play-deck-count');
  const discEl = $('pm-discard-count');
  if (hdEl)  hdEl.textContent  = PM.playerHeroDeck.length;
  if (plEl)  plEl.textContent  = PM.playerPlayDeck.length;
  if (discEl) {
    // Combined discard count per Comprehensive Rules Guide §3.1.
    // Hot Dogs are tracked as a count via playerHD (starts at 10);
    // spent count = 10 - current. Plays and heroes have explicit
    // arrays.
    const heroes = (PM.playerHeroDiscard && PM.playerHeroDiscard.length) || 0;
    const plays  = PM.playerDiscard.length;
    const hotdogs = Math.max(0, 10 - (PM.playerHD || 0));
    discEl.textContent = heroes + plays + hotdogs;
  }

  // Phase-aware secondary action button. Mirrors the iOS bottom
  // toolbar: CHOOSE SUBS in sub phase, CHOOSE PLAYS in play phase,
  // hidden in reveal / resolution / cleanup. Web's bench + plays are
  // always visible so the click just brings the relevant zone into
  // view (visual nudge, not a panel toggle like iOS).
  const subBtn = $('pm-btn-sub');
  if (subBtn) {
    if (PM.phase === 'sub' && PM.mode !== 'rookie') {
      const canSub = !PM.playerSubstituted && PM.playerHD >= 2 && PM.selectedBenchIdx !== null;
      subBtn.innerHTML = `CHOOSE SUBS<br><span style="font-size:0.35rem;opacity:0.7">2 HD</span>`;
      subBtn.disabled = !canSub;
      subBtn.hidden = false;
      subBtn.dataset.phase = 'sub';
    } else if (PM.phase === 'play' && PM.mode === 'playmaker') {
      subBtn.innerHTML = `CHOOSE PLAYS`;
      subBtn.disabled = false;
      subBtn.hidden = false;
      subBtn.dataset.phase = 'play';
    } else {
      subBtn.hidden = true;
      subBtn.dataset.phase = '';
    }
  }
}

function pmUpdateMatchOverlay() {
  const overlay = $('pm-match-over');
  if (!overlay) return;
  if (PM.phase !== 'over') {
    overlay.hidden = true;
    return;
  }
  overlay.hidden = false;

  const verdict =
    PM.matchWinner === 'player' ? { title: 'VICTORY!',     sub: 'You won the match',  cls: 'win' } :
    PM.matchWinner === 'cpu'    ? { title: 'DEFEAT',       sub: 'CPU won the match',  cls: 'lose' } :
                                  { title: 'SUDDEN DEATH', sub: 'The match ended in a tie', cls: 'tie' };

  // Trophy strip — one icon per battle. Mirrors iOS trophyStrip.
  const trophy = (b) => {
    const cls = b.result === 'win' ? 'win' : b.result === 'lose' ? 'lose' : b.result === 'tie' ? 'tie' : 'pending';
    const glyph = b.result === 'win' ? '🏆' : b.result === 'lose' ? '✗' : b.result === 'tie' ? '=' : '○';
    return `
      <div class="pm-trophy pm-trophy--${cls}">
        <div class="pm-trophy-glyph">${glyph}</div>
        <div class="pm-trophy-num">${b.id + 1}</div>
      </div>`;
  };
  const trophyStrip = (PM.battles || []).map(trophy).join('');

  // Per-battle summary — hero + plays for each side. Plays are
  // rendered as tappable chips so the user can open the PlayReviewSheet
  // to see the card's full effect text. Mirrors iOS battleSummaryRow
  // + tap-to-review behavior on each chip.
  const playChips = (cards, side, battleId) => {
    if (!cards || !cards.length) {
      return `<div class="pm-summary-plays pm-summary-plays--empty">(no plays)</div>`;
    }
    return `<div class="pm-summary-plays">${cards.map((c, i) =>
      `<button type="button" class="pm-summary-play-chip" data-battle="${battleId}" data-side="${side}" data-idx="${i}">${pmEscapeHTML(c.name || '')}</button>`
    ).join('')}</div>`;
  };
  const summaryRow = (b) => {
    const verdictText =
      b.result === 'win'  ? 'YOU WON' :
      b.result === 'lose' ? 'CPU WON' :
      b.result === 'tie'  ? 'TIE' : '—';
    const verdictCls =
      b.result === 'win'  ? 'win' :
      b.result === 'lose' ? 'lose' :
      b.result === 'tie'  ? 'tie' : 'muted';
    const playerFinal = (b.playerCard?.power || 0) + (b.playerEffectPower || 0);
    const cpuFinal    = (b.cpuCard?.power    || 0) + (b.cpuEffectPower    || 0);
    const playerHero  = b.playerCard?.hero || b.playerCard?.name || '';
    const cpuHero     = b.cpuCard?.hero    || b.cpuCard?.name    || '';
    return `
      <div class="pm-summary-row">
        <div class="pm-summary-row-head">
          <span class="pm-summary-battle">BATTLE ${b.id + 1}</span>
          <span class="pm-summary-dot">·</span>
          <span class="pm-summary-verdict pm-summary-verdict--${verdictCls}">${verdictText}</span>
          <span class="pm-summary-power">${playerFinal} — ${cpuFinal}</span>
        </div>
        <div class="pm-summary-side">
          <span class="pm-summary-side-label">YOU</span>
          <div class="pm-summary-side-body">
            ${playerHero ? `<div class="pm-summary-hero">${pmEscapeHTML(playerHero)}</div>` : ''}
            ${playChips(b.playerPlaysPlayed, 'player', b.id)}
          </div>
        </div>
        <div class="pm-summary-side">
          <span class="pm-summary-side-label">CPU</span>
          <div class="pm-summary-side-body">
            ${cpuHero ? `<div class="pm-summary-hero">${pmEscapeHTML(cpuHero)}</div>` : ''}
            ${playChips(b.cpuPlaysPlayed || b.cpuPlaysRan, 'cpu', b.id)}
          </div>
        </div>
      </div>`;
  };
  const summary = (PM.battles || []).filter(b => b.result !== null).map(summaryRow).join('');

  overlay.innerHTML = `
    <div class="pm-match-over-card">
      <div class="pm-result-title pm-result-title--${verdict.cls}">${verdict.title}</div>
      <div class="pm-result-sub">${verdict.sub}</div>
      <div class="pm-result-score">${PM.playerScore} — ${PM.cpuScore}</div>
      <div class="pm-trophy-section">
        <div class="pm-trophy-label">BATTLE PROGRESSION</div>
        <div class="pm-trophy-strip">${trophyStrip}</div>
      </div>
      <div class="pm-summary-scroll">${summary}</div>
      <div class="pm-result-btns">
        <button class="pm-result-btn" id="pm-restart">PLAY AGAIN</button>
        <button class="pm-result-btn secondary" id="pm-exit-match">EXIT</button>
      </div>
    </div>
  `;

  // Re-bind buttons since we replaced their nodes — wire into the
  // canonical handlers used at view-init time.
  $('pm-restart')?.addEventListener('click', () => {
    PM.startMatch(PM.allCards, PM._lastOpts || {});
    pmUpdateAll();
  });
  $('pm-exit-match')?.addEventListener('click', () => {
    if (typeof pmExitPlaymat === 'function') pmExitPlaymat();
  });

  // Wire summary play chips to open the PlayReviewSheet. Mirrors iOS
  // — taps open the played card's full effect detail.
  overlay.querySelectorAll('.pm-summary-play-chip').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const battleId = parseInt(btn.dataset.battle, 10);
      const side = btn.dataset.side;
      const idx = parseInt(btn.dataset.idx, 10);
      const b = PM.battles[battleId];
      if (!b) return;
      const arr = side === 'player'
        ? (b.playerPlaysPlayed || [])
        : (b.cpuPlaysPlayed || b.cpuPlaysRan || []);
      const card = arr[idx];
      if (card && typeof pmShowPlayReviewSheet === 'function') {
        pmShowPlayReviewSheet(card);
      }
    });
  });
}

function pmUpdateAll() {
  pmSetRootClass();
  pmUpdateScoreboard();
  pmUpdateBattleCols();
  pmUpdateOpponentZone();
  pmUpdatePlayerZone();
  pmUpdateActiveEffectsBanner();
  pmUpdateMatchOverlay();
  // Auto-save match state
  if (!PM.matchOver) pmSaveMatch();
  else pmClearSavedMatch();
}

/// UX#8 — discard inspector modal. Player side renders the actual list
/// of discarded play Card objects; CPU side reconstructs the per-battle
/// play history from `battles[].cpuPlaysPlayed` since the engine
/// doesn't carry a per-card CPU discard pile.
function pmShowDiscardInspector(side /* 'player' | 'cpu' */) {
  const existing = document.getElementById('pm-discard-overlay');
  if (existing) existing.remove();

  const overlay = document.createElement('div');
  overlay.id = 'pm-discard-overlay';
  overlay.className = 'modal-overlay pm-modal-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', side === 'player' ? 'Your discard pile' : 'CPU plays used');

  const thumbBaseFor = (file) => (window.BOBA && window.BOBA.thumbUrl)
    ? window.BOBA.thumbUrl(file)
    : `https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev/thumbs/${file}`;
  const fullBaseFor = (file) => (window.BOBA && window.BOBA.fullUrl)
    ? window.BOBA.fullUrl(file)
    : `https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev/full/${file}`;

  // Per-row template — wraps the row in a `<details>` so each card
  // can be expanded independently (matches iOS DiscardCardRow).
  // Card-type-aware: Plays show effect text; Heroes show power +
  // weapon + set + athlete; Hot Dogs show variation + a one-line
  // explainer. Replaces the old "no effect on file" boilerplate
  // for non-Play card types.
  let _rowKey = 0;
  const statRow = (label, value) =>
    `<div class="pm-di-stat-row"><span class="pm-di-stat-label">${pmEscapeHTML(label).toUpperCase()}</span><span class="pm-di-stat-value">${pmEscapeHTML(value)}</span></div>`;
  const headerChips = (card) => {
    if (card.cardType === 'Hero') {
      const power = (typeof card.power === 'number')
        ? `<span class="pm-di-row-chip pm-di-row-chip--power">${card.power} PW</span>`
        : '';
      const weapon = card.element
        ? `<span class="pm-di-row-chip pm-di-row-chip--weapon" data-weapon="${pmEscapeHTML(card.element)}">${pmEscapeHTML(card.element)}</span>`
        : '';
      return `${power}${weapon}`;
    }
    if (card.cardType === 'HotDog') {
      return `<span class="pm-di-row-chip pm-di-row-chip--hotdog">HOT DOG</span>`;
    }
    // Default: Play
    const cost = card.playCost;
    const costHtml = (cost === 0)
      ? `<span class="pm-di-row-cost pm-di-row-cost--free">FREE</span>`
      : (cost != null ? `<span class="pm-di-row-cost">${cost} HD</span>` : '');
    const bonusHtml = card.isBonusPlay
      ? `<span class="pm-di-row-bonus">★ BONUS</span>` : '';
    return `${costHtml}${bonusHtml}`;
  };
  const detailBody = (card) => {
    if (card.cardType === 'Hero') {
      const stats = [];
      if (typeof card.power === 'number') stats.push(statRow('Power', String(card.power)));
      stats.push(statRow('Weapon', card.element || '—'));
      stats.push(statRow('Set', card.set || '—'));
      if (card.subSet) stats.push(statRow('Sub-set', card.subSet));
      if (card.treatment) stats.push(statRow('Treatment', card.treatment));
      if (card.athleteInspiration) stats.push(statRow('Inspired by', card.athleteInspiration));
      return `<div class="pm-di-row-effect">
        <div class="pm-di-row-effect-label">HERO</div>
        <div class="pm-di-stat-block">${stats.join('')}</div>
      </div>`;
    }
    if (card.cardType === 'HotDog') {
      const stats = [];
      if (card.variation) stats.push(statRow('Variation', card.variation));
      if (card.set)       stats.push(statRow('Set', card.set));
      if (card.treatment) stats.push(statRow('Treatment', card.treatment));
      return `<div class="pm-di-row-effect">
        <div class="pm-di-row-effect-label" style="color:#4CAF50">HOT DOG · SPENT</div>
        <div class="pm-di-stat-block">${stats.join('')}</div>
        <div class="pm-di-row-effect-text" style="margin-top:6px;font-size:11px;opacity:0.7">Spent for a substitution or play cost. Hot Dogs share the discard zone with heroes and plays.</div>
      </div>`;
    }
    // Default: Play
    const ability = card.playAbility
      ? pmEscapeHTML(card.playAbility)
      : 'No effect text on file.';
    return `<div class="pm-di-row-effect">
      <div class="pm-di-row-effect-label">EFFECT</div>
      <div class="pm-di-row-effect-text">${ability}</div>
    </div>`;
  };
  const displayName = (card) => {
    if (card.cardType === 'Hero' && card.hero) return card.hero;
    return card.name || '';
  };
  const cardRow = (card) => {
    const thumbHtml = card.imageFile
      ? `<img class="pm-di-row-thumb" src="${thumbBaseFor(card.imageFile)}" alt="">`
      : '';
    const fullThumbHtml = card.imageFile
      ? `<img class="pm-di-detail-img" src="${fullBaseFor(card.imageFile)}" alt="">`
      : '';
    const key = `pm-di-row-${++_rowKey}`;
    return `<details class="pm-di-row" id="${key}">
      <summary class="pm-di-row-summary">
        ${thumbHtml}
        <div class="pm-di-row-text">
          <div class="pm-di-row-name">${pmEscapeHTML(displayName(card))}</div>
          <div class="pm-di-row-meta">${headerChips(card)}</div>
        </div>
        <span class="pm-di-row-chev" aria-hidden="true">▾</span>
      </summary>
      <div class="pm-di-row-detail">
        ${fullThumbHtml}
        ${detailBody(card)}
      </div>
    </details>`;
  };

  let body;
  if (side === 'player') {
    // Combined player discard view per Comprehensive Rules Guide
    // §3.1 — heroes, plays, and spent Hot Dogs all share one zone.
    const heroes  = PM.playerHeroDiscard || [];
    const plays   = PM.playerDiscard || [];
    const hdSpent = Math.max(0, 10 - (PM.playerHD || 0));
    const hdCards = (PM.playerHotDogDeckCards || []).slice(0, hdSpent);
    if (!heroes.length && !plays.length && !hdCards.length) {
      body = `<div class="pm-di-empty">No cards in discard yet</div>`;
    } else {
      const sections = [];
      if (heroes.length) {
        sections.push(`<div class="pm-di-header">${heroes.length} HERO${heroes.length === 1 ? '' : 'ES'} · MOST RECENT FIRST</div>`);
        sections.push(heroes.slice().reverse().map(cardRow).join(''));
      }
      if (plays.length) {
        sections.push(`<div class="pm-di-header">${plays.length} PLAY${plays.length === 1 ? '' : 'S'} · MOST RECENT FIRST</div>`);
        sections.push(plays.slice().reverse().map(cardRow).join(''));
      }
      if (hdCards.length) {
        sections.push(`<div class="pm-di-header">${hdCards.length} HOT DOG${hdCards.length === 1 ? '' : 'S'} SPENT</div>`);
        sections.push(hdCards.map(cardRow).join(''));
      }
      body = sections.join('');
    }
  } else {
    const battles = PM.battles || [];
    const total = battles.reduce((acc, b) => acc + (b.cpuPlaysPlayed || b.cpuPlaysRan || []).length, 0);
    if (!total) {
      body = `<div class="pm-di-empty">CPU hasn't played any cards yet</div>`;
    } else {
      body = `<div class="pm-di-header">${total} PLAY${total === 1 ? '' : 'S'} USED · GROUPED BY BATTLE</div>`;
      battles.forEach(b => {
        const plays = b.cpuPlaysPlayed || b.cpuPlaysRan || [];
        if (!plays.length) return;
        body += `<div class="pm-di-battle-label">BATTLE ${b.id + 1}</div>`;
        body += plays.map(cardRow).join('');
      });
    }
  }

  overlay.innerHTML = `
    <div class="pm-discard-inspector">
      <div class="pm-di-titlebar">
        <h2>${side === 'player' ? 'Your Discard Pile' : 'CPU Plays Used'}</h2>
        <button class="pm-di-close" type="button" aria-label="Close">×</button>
      </div>
      <div class="pm-di-body">${body}</div>
    </div>`;
  document.body.appendChild(overlay);
  overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
  overlay.querySelector('.pm-di-close')?.addEventListener('click', () => overlay.remove());
  document.addEventListener('keydown', function escClose(ev) {
    if (ev.key === 'Escape') {
      overlay.remove();
      document.removeEventListener('keydown', escClose);
    }
  });
}

// ─────────────────────────────────────────────────────────────────
// Rules-clarification helpers (§6.A — Recycle / Reload warning)

function pmIsRecyclePlay(card) {
  if (!card) return false;
  const entry = pmGetPlayEntry(card);
  if (!entry || !entry.effects) return false;
  return entry.effects.some(s => s && (s.op === 'shuffle_from_discard_to_deck' || s.op === 'reclaim_used_play'));
}

function pmPlayerHasRestOfGameEffects() {
  const persistents = (PM._persistents || []).some(p =>
    p.owner === 'player' && (p.spec && p.spec.scope) === 'rest_of_game');
  const transforms = (PM._weaponTransforms || []).some(t =>
    t.owner === 'player' && t.scope === 'rest_of_game');
  return persistents || transforms;
}

function pmPlayerRestOfGameEffectSummary() {
  const labels = [];
  for (const p of (PM._persistents || [])) {
    if (p.owner !== 'player') continue;
    if ((p.spec && p.spec.scope) !== 'rest_of_game') continue;
    const lbl = PM._persistentSummaryLabel(p.spec, p.owner);
    if (lbl) labels.push(lbl);
  }
  for (const t of (PM._weaponTransforms || [])) {
    if (t.owner !== 'player' || t.scope !== 'rest_of_game') continue;
    labels.push(PM._weaponTransformLabel(t));
  }
  return labels.join('\n• ');
}

/// Confirm modal for Recycle/Reload. Shows the active rest_of_game
/// effects that will end if the user proceeds. Calls `onConfirm()`
/// when the user accepts; closes silently on cancel.
function pmConfirmRecycle(summary, onConfirm) {
  const existing = document.getElementById('pm-recycle-overlay');
  if (existing) existing.remove();

  const overlay = document.createElement('div');
  overlay.id = 'pm-recycle-overlay';
  overlay.className = 'modal-overlay pm-modal-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', 'Confirm recycle');
  overlay.innerHTML = `
    <div class="pm-recycle-modal">
      <h2>Recycle these plays?</h2>
      <p>Picking plays back up from your discard ends any rest-of-game effects attached to them. Currently active:</p>
      <ul class="pm-recycle-list">
        ${summary.split('\n• ').filter(Boolean).map(line => `<li>${pmEscapeHTML(line)}</li>`).join('')}
      </ul>
      <div class="pm-recycle-actions">
        <button class="pm-recycle-cancel" type="button">Cancel</button>
        <button class="pm-recycle-go" type="button">Recycle</button>
      </div>
    </div>`;
  document.body.appendChild(overlay);
  const close = () => overlay.remove();
  overlay.addEventListener('click', e => { if (e.target === overlay) close(); });
  overlay.querySelector('.pm-recycle-cancel').addEventListener('click', close);
  overlay.querySelector('.pm-recycle-go').addEventListener('click', () => {
    close();
    onConfirm();
  });
  document.addEventListener('keydown', function escClose(ev) {
    if (ev.key === 'Escape') { close(); document.removeEventListener('keydown', escClose); }
  });
}

function pmEscapeHTML(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => (
    {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]
  ));
}

/// Re-render the active-effects pill strip from PM.activeEffectsForUI().
/// Hidden when no effects are in scope.
function pmUpdateActiveEffectsBanner() {
  const el = document.getElementById('pm-active-effects');
  if (!el) return;
  const rows = (typeof PM.activeEffectsForUI === 'function') ? PM.activeEffectsForUI() : [];
  if (!rows.length) { el.hidden = true; el.innerHTML = ''; return; }
  el.hidden = false;
  // Eyebrow + scrollable chip strip — matches the iOS layout so
  // coaches read the band as "active effects" instead of an
  // unstyled rectangle.
  const eyebrow = `
    <div class="pm-active-effects-eyebrow">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"
           stroke-linecap="round" stroke-linejoin="round">
        <path d="M18.6 6.62a5.5 5.5 0 0 0-7.78 0L12 7.83l-1.18-1.18a5.5 5.5 0 0 0-7.78 7.78L12 23.07l8.96-8.64a5.5 5.5 0 0 0-2.36-9.81z"/>
      </svg>
      <span>Active</span>
    </div>`;
  const pillsHTML = rows.map(r => {
    const ownerClass = r.owner === 'player' ? 'pm-effect-pill--you' : 'pm-effect-pill--opp';
    const iconHTML = r.icon === 'transform'
      ? '<svg viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/></svg>'
      : '<svg viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M18.6 6.62a5.5 5.5 0 0 0-7.78 0L12 7.83l-1.18-1.18a5.5 5.5 0 0 0-7.78 7.78L12 23.07l8.96-8.64a5.5 5.5 0 0 0-2.36-9.81z"/></svg>';
    // UX#11 tick-down badge — rendered when remaining > 0.
    const tickHTML = (r.remaining != null && r.remaining > 0)
      ? `<span class="pm-effect-pill-tick">${r.remaining}</span>`
      : '';
    return `<span class="pm-effect-pill ${ownerClass}" style="--effect-color:${r.color}">${iconHTML}<span>${pmEscapeHTML(r.label)}</span>${tickHTML}</span>`;
  }).join('');
  el.innerHTML = `${eyebrow}<div class="pm-active-effects-strip">${pillsHTML}</div>`;
}

// ── Init (event listeners attached once per session) ────────────

function pmExitPlaymat() {
  const view  = $('view-practice');
  const setup = $('practice-setup');
  const mat   = $('practice-playmat');
  if (view)  view.classList.remove('playmat-mode');
  if (setup) setup.hidden = false;
  if (mat)   mat.hidden = true;
  // Body-level flag used by CSS to gate the portrait rotate hint; we
  // only want that overlay while a match is actually running, not on
  // the setup screen.
  document.body.classList.remove('practice-active');
  document.body.classList.remove('practice-rotate-dismissed');
  // Update resume button visibility
  const resumeBtn = $('btn-resume-practice');
  if (resumeBtn) resumeBtn.hidden = !pmLoadMatch();
  // Refresh saved-deck options in case user created new decks since last setup view
  pmPopulateSavedDeckOptions();
}

// Toggle body.practice-active so CSS reveals the portrait rotate hint
// only while the playmat is the active surface. Called from the two
// start paths (fresh start + resume) where setup hides + mat shows.
function pmMarkPlaymatActive() {
  document.body.classList.add('practice-active');
  // Dismiss handler is wired once; reset on every new match so the
  // hint reappears if a user goes back to portrait after dismissing.
  document.body.classList.remove('practice-rotate-dismissed');
  const dismiss = document.getElementById('practice-rotate-dismiss');
  if (dismiss && !dismiss.dataset.wired) {
    dismiss.addEventListener('click', () => {
      document.body.classList.add('practice-rotate-dismissed');
    });
    dismiss.dataset.wired = '1';
  }
}

// Show a popup for a play card so the user can read the effect before deciding to play
function pmShowPlayCardPopup(handIdx) {
  const card = PM.playerPlayHand[handIdx];
  if (!card) return;

  // Remove any existing popup
  document.getElementById('pm-play-popup')?.remove();

  const cost       = pmEffectiveCost(card, 'player');
  const canAfford  = PM.playerHD >= cost;
  const canUse     = pmIsPlayable(card, 'player');
  // Phase / global play-block check — without this, the popup would
  // light up "Play Card" while playerPlayCard() silently rejects the
  // click (wrong phase, Restricted-List cap, block_plays persistent).
  // Mirrors the gates in PracticeStore.playerPlayCard.
  const inPlayPhase = PM.phase === 'play';
  const cap = PM._playerPlayCapThisBattle;
  const used = (PM.battles[PM.currentBattle]?.playerPlaysPlayed || []).length;
  const overCap = cap != null && used >= cap;
  const blocked = pmIsBlocked('player', 'block_plays');
  const phaseWarn =
    !inPlayPhase ? 'Wait for the Play phase' :
    blocked      ? 'Plays are blocked this battle' :
    overCap      ? `Play limit reached (${cap})` :
    '';
  const playable   = canAfford && canUse && inPlayPhase && !blocked && !overCap;
  const imgUrl     = card.imageFile ? fullUrl(card.imageFile) : null;
  const entry     = pmGetPlayEntry(card);
  // play-effects.json is authoritative for ability text (covers cards where
  // cards.json has playAbility=null, e.g. National Starter Set variants).
  const ability    = card.playAbility || entry?.ability || card.description || '—';
  const costLabel  = cost === 0 ? 'FREE' : `${cost} Hot Dog${cost !== 1 ? 's' : ''}`;
  const affordClass = playable ? 'pm-play-popup-play' : 'pm-play-popup-play cannot-afford';
  const element    = card.element || '';
  const partial   = pmEntryHasUnknownOps(entry);

  const popup = document.createElement('div');
  popup.id = 'pm-play-popup';
  popup.className = 'pm-play-popup';
  const safeName = pmEscapeHTML(card.name || '');
  const safeAbility = pmEscapeHTML(ability);
  popup.innerHTML = `
    <div class="pm-play-popup-inner">
      ${imgUrl ? `<div class="pm-play-popup-img-wrap"><img class="pm-play-popup-img" src="${imgUrl}" alt="${safeName}" onerror="this.parentElement.style.display='none'"></div>` : ''}
      <div class="pm-play-popup-body">
        <div class="pm-play-popup-header">
          <div class="pm-play-popup-name">${safeName}</div>
          ${element ? `<div class="pm-play-popup-element" data-element="${element}">${element}</div>` : ''}
        </div>
        <div class="pm-play-popup-cost-row">
          <span class="pm-play-popup-cost-pill${!canAfford ? ' cannot-afford' : ''}">${costLabel}</span>
          ${!canAfford ? `<span class="pm-play-popup-afford-warn">Not enough Hot Dogs</span>` : ''}
          ${canAfford && !canUse ? `<span class="pm-play-popup-afford-warn">Can't be played this Battle</span>` : ''}
          ${canAfford && canUse && phaseWarn ? `<span class="pm-play-popup-afford-warn">${phaseWarn}</span>` : ''}
        </div>
        <div class="pm-play-popup-divider"></div>
        <div class="pm-play-popup-effect-label">EFFECT</div>
        <div class="pm-play-popup-effect">${safeAbility}</div>
        ${partial ? `<div class="pm-play-popup-partial-note">⚠ Some effects not yet simulated</div>` : ''}
        <div class="pm-play-popup-actions">
          <button class="pm-play-popup-cancel">Cancel</button>
          <button class="${affordClass}"${!playable ? ' disabled' : ''}>
            Play Card
          </button>
        </div>
      </div>
    </div>`;

  // Diagnose any silent rejection so the user gets feedback instead
  // of an inert button. Mirrors the gate set in PracticeStore.playerPlayCard.
  const explainRejection = () => {
    if (PM.phase !== 'play')                                   return 'Play phase has ended — wait for the next one.';
    if (pmIsBlocked('player', 'block_plays'))                  return 'Plays are blocked this battle.';
    if (PM._playerPlayCapThisBattle != null) {
      const used = (PM.battles[PM.currentBattle]?.playerPlaysPlayed || []).length;
      if (used >= PM._playerPlayCapThisBattle)                 return `Play limit reached (${PM._playerPlayCapThisBattle} per battle).`;
    }
    const c = PM.playerPlayHand[handIdx];
    if (!c)                                                    return 'Card no longer in hand.';
    const cost = pmEffectiveCost(c, 'player');
    if (PM.playerHD < cost)                                    return `Not enough Hot Dogs (${PM.playerHD} / ${cost}).`;
    if (!pmIsPlayable(c, 'player'))                            return "This card's requirements aren't met.";
    return 'Play rejected.';
  };

  const tryPlay = () => {
    if (PM.playerPlayCard(handIdx)) {
      popup.remove();
      pmUpdateAll();
      if (PM.lastEffectResult) pmShowEffectToast(PM.lastEffectResult);
    } else {
      // Surface why so the click isn't silently swallowed.
      pmEnqueueNotification(explainRejection());
    }
  };

  popup.querySelector('.pm-play-popup-play').addEventListener('click', () => {
    // Rules-clarification (handoff §6.A): warn before Recycle/Reload
    // clear active rest_of_game effects.
    const card = PM.playerPlayHand[handIdx];
    if (pmIsRecyclePlay(card) && pmPlayerHasRestOfGameEffects()) {
      const summary = pmPlayerRestOfGameEffectSummary();
      pmConfirmRecycle(summary, tryPlay);
      return;
    }
    tryPlay();
  });
  popup.querySelector('.pm-play-popup-cancel').addEventListener('click', () => popup.remove());
  popup.addEventListener('click', e => { if (e.target === popup) popup.remove(); });

  const mat = $('practice-playmat');
  if (mat) mat.appendChild(popup);
}

// Inspect-and-substitute popup for bench heroes. Mirrors iOS
// PracticeBenchPanel — always inspectable; the SUB button is enabled
// only during the sub phase when the player has 2 HD and hasn't
// substituted yet this battle.
function pmShowBenchCardPopup(benchIdx) {
  const card = PM.playerBench[benchIdx];
  if (!card) return;
  document.getElementById('pm-play-popup')?.remove();

  const imgUrl = card.imageFile ? fullUrl(card.imageFile) : null;
  const element = card.element || '';
  const power = card.power != null ? card.power : '—';
  const athlete = card.athleteInspiration ? card.athleteInspiration : '';
  const setLine = [card.set, card.subSet, card.treatment].filter(Boolean).join(' · ');

  // The substitute action only makes sense in the sub phase. Outside
  // it, the popup is read-only ("inspect this bench hero") so the
  // "Substitute (2 HD)" button doesn't confuse the user during play.
  const inSubPhase = PM.phase === 'sub';
  const canSub = inSubPhase && !PM.playerSubstituted && PM.playerHD >= 2;
  const subWarn = !canSub && inSubPhase && PM.playerSubstituted
    ? "You've already subbed this Battle"
    : !canSub && inSubPhase && PM.playerHD < 2
      ? "Need 2 Hot Dogs to substitute"
      : '';

  // Action button: in sub phase show the Substitute CTA; otherwise
  // collapse to a single Close button.
  const actionsHtml = inSubPhase
    ? `<button class="pm-play-popup-cancel">Cancel</button>
       <button class="pm-play-popup-play${canSub ? '' : ' cannot-afford'}"${canSub ? '' : ' disabled'}>
         Substitute (2 HD)
       </button>`
    : `<button class="pm-play-popup-cancel" style="flex:1">Close</button>`;

  const popup = document.createElement('div');
  popup.id = 'pm-play-popup';
  popup.className = 'pm-play-popup';
  popup.innerHTML = `
    <div class="pm-play-popup-inner">
      ${imgUrl ? `<div class="pm-play-popup-img-wrap"><img class="pm-play-popup-img" src="${imgUrl}" alt="${card.hero||card.name||''}" onerror="this.parentElement.style.display='none'"></div>` : ''}
      <div class="pm-play-popup-body">
        <div class="pm-play-popup-header">
          <div class="pm-play-popup-name">${card.hero || card.name || ''}</div>
          ${element ? `<div class="pm-play-popup-element" data-element="${element}">${element}</div>` : ''}
        </div>
        <div class="pm-play-popup-cost-row">
          <span class="pm-play-popup-cost-pill">${power} POWER</span>
          ${subWarn ? `<span class="pm-play-popup-afford-warn">${subWarn}</span>` : ''}
        </div>
        <div class="pm-play-popup-divider"></div>
        ${athlete ? `<div class="pm-play-popup-effect-label">INSPIRED BY</div><div class="pm-play-popup-effect">${pmEscapeHTML(athlete)}</div>` : ''}
        ${setLine ? `<div class="pm-play-popup-effect-label" style="margin-top:10px">PRINT</div><div class="pm-play-popup-effect">${pmEscapeHTML(setLine)}</div>` : ''}
        <div class="pm-play-popup-actions">
          ${actionsHtml}
        </div>
      </div>
    </div>`;

  if (inSubPhase) {
    popup.querySelector('.pm-play-popup-play').addEventListener('click', () => {
      if (!canSub) return;
      if (PM.playerSub(benchIdx)) {
        popup.remove();
        pmUpdateAll();
      }
    });
  }
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
      playerHeroDeckIds: PM.playerHeroDeck.map(c => c?.bobaId),
      cpuHeroDeckIds: PM.cpuHeroDeck.map(c => c?.bobaId),
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
      // Captured Hot Dog deck cards for the discard inspector.
      playerHotDogDeckIds: (PM.playerHotDogDeckCards || []).map(c => c?.bobaId),
      cpuHotDogDeckIds:    (PM.cpuHotDogDeckCards    || []).map(c => c?.bobaId),
      // Hero discard pile (displaced by substitutions).
      playerHeroDiscardIds: (PM.playerHeroDiscard || []).map(c => c?.bobaId),
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
  PM.playerHeroDeck = (snap.playerHeroDeckIds || []).map(findCard).filter(Boolean);
  PM.cpuHeroDeck = (snap.cpuHeroDeckIds || []).map(findCard).filter(Boolean);
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
  PM.playerHotDogDeckCards = (snap.playerHotDogDeckIds || []).map(findCard).filter(Boolean);
  PM.cpuHotDogDeckCards    = (snap.cpuHotDogDeckIds    || []).map(findCard).filter(Boolean);
  PM.playerHeroDiscard     = (snap.playerHeroDiscardIds || []).map(findCard).filter(Boolean);
  PM.cpuPlayPool = (snap.cpuPlayPoolIds || []).map(findCard).filter(Boolean);

  return true;
}

// ── Notification queue — serializes banners/overlays so they never overlap ──

const pmNotifQueue = {
  queue: [],
  active: false,
  _timer: null,

  push(entry) {
    this.queue.push(entry);
    if (!this.active) this._next();
  },

  /** Clear all pending notifications and hide the active one */
  clear() {
    this.queue = [];
    if (this._timer) { clearTimeout(this._timer); this._timer = null; }
    this._hideAll();
    this.active = false;
  },

  /** Hide every notification element */
  _hideAll() {
    const banner = $('pm-phase-banner');
    if (banner) { banner.classList.remove('visible'); banner.style.display = 'none'; }
    const overlay = $('pm-cpu-overlay');
    if (overlay) overlay.hidden = true;
    const callout = $('pm-cpu-sub-callout');
    if (callout) callout.hidden = true;
  },

  _next() {
    if (this.queue.length === 0) { this.active = false; return; }
    this.active = true;
    // Hide everything before showing the next notification
    this._hideAll();
    const entry = this.queue.shift();
    entry.show(() => this._next());
  },
};

/** Enqueue a phase banner (auto-dismiss after duration ms) */
function pmQueuePhaseBanner(text, duration) {
  pmNotifQueue.push({
    show(done) {
      const banner = $('pm-phase-banner');
      if (!banner) { done(); return; }
      banner.textContent = text;
      banner.style.display = ''; // restore from _hideAll
      // Force reflow so opacity transition works after display change
      banner.offsetHeight;
      banner.classList.add('visible');
      pmNotifQueue._timer = setTimeout(() => {
        banner.classList.remove('visible');
        // Wait for fade-out transition (300ms) then hide fully before next
        pmNotifQueue._timer = setTimeout(() => {
          banner.style.display = 'none';
          done();
        }, 350);
      }, duration || 2000);
    }
  });
}

/** Enqueue CPU sub callout (auto-dismiss) */
function pmQueueCpuSub() {
  pmNotifQueue.push({
    show(done) {
      const callout = $('pm-cpu-sub-callout');
      if (!callout) { done(); return; }
      // Re-render the callout body with displaced hero info so the
      // player can read what was just swapped. The new (face-down)
      // hero is intentionally NOT shown — sub still happens before
      // reveal, we're just exposing what got dropped.
      const displaced = PM._pendingCpuSubDisplaced;
      const freeSub = PM._pendingCpuSubFree;
      const inner = callout.querySelector('.pm-cpu-sub-inner');
      if (inner) {
        const name = displaced ? (displaced.hero || displaced.name || 'their hero') : 'their hero';
        const powerLabel = displaced && displaced.power != null ? ` (${displaced.power} power)` : '';
        const costLabel = freeSub ? 'for free' : 'for 2 Hot Dogs';
        const thumbBase = (window.BOBA && window.BOBA.thumbUrl)
          ? window.BOBA.thumbUrl(displaced && displaced.imageFile)
          : (displaced && displaced.imageFile
              ? `https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev/thumbs/${displaced.imageFile}`
              : '');
        const imageHtml = displaced && displaced.imageFile
          ? `<img class="pm-cpu-sub-img" src="${thumbBase}" alt="">`
          : '';
        inner.innerHTML = `
          <span class="pm-cpu-sub-icon">⚡</span>
          <div class="pm-cpu-sub-body">
            <div class="pm-cpu-sub-text">CPU SUBSTITUTED</div>
            ${imageHtml}
            <div class="pm-cpu-sub-detail">Subbed out ${name}${powerLabel} ${costLabel}</div>
          </div>`;
      }
      PM._pendingCpuSubDisplaced = null;
      PM._pendingCpuSubFree = false;
      callout.hidden = false;
      callout.style.animation = 'none';
      callout.offsetHeight;
      callout.style.animation = '';
      pmNotifQueue._timer = setTimeout(() => {
        callout.hidden = true;
        done();
      }, 3200);
    }
  });
}

/** Enqueue CPU play cards (one by one, manually dismissed) */
function pmQueueCpuPlays() {
  if (!PM.cpuPlayQueue || PM.cpuPlayQueue.length === 0) return;
  // Each play card is its own queued notification
  PM.cpuPlayQueue.forEach((entry, idx) => {
    pmNotifQueue.push({
      show(done) {
        pmShowSingleCpuPlay(entry, done);
      }
    });
  });
}

/** Show a brief toast with the effect result after playing a card */
function pmShowEffectToast(result) {
  // Route through pmNotifQueue so the toast appears in the correct
  // order relative to CPU play overlays and phase banners that
  // pmSetRootClass enqueues on the same tick. Without the queue, the
  // toast was appending directly to the DOM and could overlap or be
  // overlapped by CPU overlays unpredictably.
  const { card, playerDelta, cpuDelta, description } = result;
  const name = card?.name || 'Play';
  const isPositive = playerDelta > 0 || cpuDelta < 0;
  const color = isPositive ? '#4CAF50' : (playerDelta < 0 || cpuDelta > 0) ? '#C0392B' : '#00F5FF';
  const ability = (card?.playAbility || '').toLowerCase();
  let icon = '✦';
  if (ability.includes('flip a coin')) icon = '🪙';
  else if (ability.includes('roll a di') || ability.includes('roll a die')) icon = '🎲';
  else if (ability.includes('steal')) icon = '⚡';
  else if (ability.includes('swap')) icon = '🔄';

  pmNotifQueue.push({
    show(done) {
      document.getElementById('pm-effect-toast')?.remove();
      const toast = document.createElement('div');
      toast.id = 'pm-effect-toast';
      toast.className = 'pm-effect-toast';
      // Escape dynamic strings — name and description are concatenations
      // of card titles, ability text, and notifications. Even if the
      // catalog is currently clean, raw innerHTML interpolation makes
      // any future angle-bracket or quote content silently break the
      // surrounding markup.
      toast.innerHTML = `
        <span class="pm-effect-toast-icon">${icon}</span>
        <span class="pm-effect-toast-name" style="color:${color}">${pmEscapeHTML(name)}</span>
        <span class="pm-effect-toast-desc">${pmEscapeHTML(description)}</span>`;
      const mat = $('practice-playmat');
      if (mat) mat.appendChild(toast);
      // Force reflow then animate in
      toast.offsetHeight;
      toast.classList.add('visible');
      pmNotifQueue._timer = setTimeout(() => {
        toast.classList.remove('visible');
        pmNotifQueue._timer = setTimeout(() => {
          toast.remove();
          done();
        }, 400);
      }, 1800);
    }
  });
}

// Show a single CPU play card overlay; calls done() when user dismisses
function pmShowSingleCpuPlay(entry, done) {
  const overlay = $('pm-cpu-overlay');
  if (!overlay) { done(); return; }

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

  const notifs = (entry.notifications || []);
  const notifsHtml = notifs.length
    ? `<div class="pm-cpu-card-notifs">${notifs.map(n => `<span>${pmEscapeHTML(n)}</span>`).join('')}</div>`
    : '';

  const safeCardName = pmEscapeHTML(card.name || 'Play Card');
  const safeAbility = pmEscapeHTML(ability);
  const cardEl = $('pm-cpu-overlay-card');
  if (cardEl) {
    cardEl.innerHTML = `
      ${imgUrl ? `<img class="pm-cpu-card-img" src="${imgUrl}" alt="${safeCardName}" onerror="this.style.display='none'">` : ''}
      <div class="pm-cpu-card-name">${safeCardName}</div>
      <div class="pm-cpu-card-cost">${costLabel}</div>
      ${ability ? `<div class="pm-cpu-card-effect">${safeAbility}</div>` : ''}
      <div class="pm-cpu-card-deltas">${deltasHtml}</div>
      ${notifsHtml}`;
  }

  overlay.hidden = false;

  // Single dismiss path — replace the OK button AND wire tap-anywhere
  // on the overlay backdrop. Without the backdrop tap, users who fling
  // clicks at the playmat (expecting to advance the phase) get them
  // silently swallowed by the overlay until they hunt for the OK
  // button.
  const dismiss = () => {
    const deferred = (entry && entry.deferredPersistents) || [];
    for (const p of deferred) {
      PM.installPersistent('cpu', p, { sourceCard: card?.name });
    }
    overlay.hidden = true;
    overlay.removeEventListener('click', backdropClick);
    pmUpdateAll();
    done();
  };
  function backdropClick(e) {
    // Only react when the click is on the overlay scrim itself, not
    // on bubbled events from the inner card or OK button (those have
    // their own handlers / don't need duplicates).
    if (e.target === overlay) dismiss();
  }
  overlay.addEventListener('click', backdropClick);

  const dismissBtn = $('pm-cpu-overlay-dismiss');
  if (dismissBtn) {
    const newBtn = dismissBtn.cloneNode(true);
    dismissBtn.parentNode.replaceChild(newBtn, dismissBtn);
    newBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      dismiss();
    });
  }
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

  // Bench card tap → show detail popup (hero stats + SUB button when
  // the sub phase allows). Tapping is always permitted so coaches can
  // inspect a bench hero even outside the sub window — matches iOS
  // PracticeBenchPanel which always renders the selected card detail.
  $('pm-bench-cards')?.addEventListener('click', e => {
    const cardEl = e.target.closest('.pm-bench-card');
    if (!cardEl) return;
    const idx = parseInt(cardEl.dataset.benchIdx, 10);
    pmShowBenchCardPopup(idx);
  });

  // Phase-aware secondary action button. Mirrors iOS PracticeBottom-
  // Toolbar: in the sub phase it confirms a substitute (when a bench
  // card is selected) or otherwise scrolls the bench area into view;
  // in the play phase it scrolls the plays hand into view as a visual
  // nudge ("here's where to act"). The legacy "auto-confirm sub on
  // tap" path stays so coaches who've selected a bench card can still
  // execute the sub from this button.
  $('pm-btn-sub')?.addEventListener('click', () => {
    const phase = PM.phase;
    if (phase === 'sub') {
      if (PM.selectedBenchIdx !== null && PM.playerSub(PM.selectedBenchIdx)) {
        pmUpdateAll();
      } else {
        $('pm-bench-cards')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      }
    } else if (phase === 'play') {
      $('pm-hand-cards')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
  });

  // CPU overlay dismiss — handled dynamically by pmShowSingleCpuPlay via the queue

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

  // UX#8 — discard inspector triggers (player + CPU)
  $('pm-discard-btn')?.addEventListener('click', () => pmShowDiscardInspector('player'));
  $('pm-opp-plays-btn')?.addEventListener('click', () => pmShowDiscardInspector('cpu'));

  // Mode tabs inside playmat
  document.querySelectorAll('#practice-playmat .pm-mode-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      PM.mode = btn.dataset.mode;
      pmSetRootClass();
    });
  });

  // Exit / restart buttons
  $('pm-exit-btn')?.addEventListener('click', pmExitPlaymat);
  $('pm-help-btn')?.addEventListener('click', pmReplayTutorial);
  $('pm-exit-match')?.addEventListener('click', pmExitPlaymat);
  $('pm-restart')?.addEventListener('click', () => {
    PM.startMatch(PM.allCards, PM._lastOpts || {});
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
    pmMarkPlaymatActive();

    pmInitPlaymat();
    pmUpdateAll();
  });

  // Mode radio
  view.querySelectorAll('input[name="practice-mode"]').forEach(radio => {
    radio.addEventListener('change', e => {
      PM.mode = e.target.value;
      pmUpdateFormatRowVisibility();
    });
  });

  // Tab switching (Game Mode / Your Deck / CPU Deck)
  view.querySelectorAll('.practice-setup-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      const target = btn.dataset.tab;
      view.querySelectorAll('.practice-setup-tab').forEach(b => {
        const isActive = b.dataset.tab === target;
        b.classList.toggle('active', isActive);
        b.setAttribute('aria-selected', isActive ? 'true' : 'false');
      });
      view.querySelectorAll('.practice-setup-pane').forEach(p => {
        const show = p.dataset.pane === target;
        p.hidden = !show;
        p.classList.toggle('active', show);
      });
    });
  });

  // Custom rules disclosure
  const rulesToggle = $('practice-custom-rules-toggle');
  const rulesPane = $('practice-custom-rules');
  if (rulesToggle && rulesPane) {
    rulesToggle.addEventListener('click', () => {
      const expanded = rulesToggle.getAttribute('aria-expanded') === 'true';
      rulesToggle.setAttribute('aria-expanded', expanded ? 'false' : 'true');
      rulesPane.hidden = expanded;
    });
  }

  // Custom-rules segmented pickers (matchLength / startingHotDogs)
  view.querySelectorAll('.practice-segmented').forEach(group => {
    const ruleKey = group.dataset.rule;
    if (!ruleKey) return;
    group.querySelectorAll('.practice-seg').forEach(btn => {
      btn.addEventListener('click', () => {
        group.querySelectorAll('.practice-seg').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        const raw = btn.dataset.value;
        PM.customRules[ruleKey] = (ruleKey === 'startingHotDogs') ? parseInt(raw, 10) : raw;
        pmUpdateCustomRulesBadge();
      });
    });
  });

  // Hero-format select
  const formatSel = $('practice-hero-format');
  if (formatSel) {
    formatSel.addEventListener('change', () => {
      PM.customRules.heroFormat = formatSel.value;
      pmUpdateCustomRulesBadge();
      pmUpdateFormatBanners();
    });
  }
  // Toggles
  $('practice-super-ties')?.addEventListener('change', e => {
    PM.customRules.superBreaksTies = e.target.checked;
    pmUpdateCustomRulesBadge();
  });
  $('practice-sudden-death')?.addEventListener('change', e => {
    PM.customRules.suddenDeath = e.target.checked;
    pmUpdateCustomRulesBadge();
  });

  // Deck-select changes refresh the format-compliance banner
  $('practice-player-select')?.addEventListener('change', pmUpdateFormatBanners);
  $('practice-cpu-select')?.addEventListener('change', pmUpdateFormatBanners);

  // Populate saved-deck optgroups (once, lazily when setup is first shown)
  pmPopulateSavedDeckOptions();

  // Pre-fetch template-decks.json so the format-compliance banner can
  // count cap-violators without a click-time fetch. Background fire.
  if (!dbTemplateData) {
    fetch('assets/data/template-decks.json')
      .then(r => r.json())
      .then(data => { dbTemplateData = data; pmUpdateFormatBanners(); })
      .catch(() => {});
  }

  // Start — single handler, fired by any of the three tab Start buttons
  const startHandler = async () => {
    const checked = view.querySelector('input[name="practice-mode"]:checked');
    PM.mode = checked ? checked.value : 'playmaker';

    const playerSpec = pmParseDeckSpec($('practice-player-select')?.value || 'random');
    const cpuSpec    = pmParseDeckSpec($('practice-cpu-select')?.value    || 'random');

    const startBtns = view.querySelectorAll('.practice-start-btn:not(.practice-resume-btn)');
    startBtns.forEach(b => { b.disabled = true; b.textContent = 'PREPARING…'; });
    let playerDeck = null, cpuDeck = null;
    try {
      [playerDeck, cpuDeck] = await Promise.all([
        pmResolveDeckSpec(playerSpec, allCards),
        pmResolveDeckSpec(cpuSpec, allCards),
      ]);
    } catch (err) {
      console.warn('Deck resolve failed; using random pools.', err);
    } finally {
      startBtns.forEach(b => { b.disabled = false; b.textContent = 'START PRACTICE'; });
    }

    // Build playmat HTML once
    const mat = $('practice-playmat');
    if (mat && !PM._initialized) {
      mat.innerHTML = pmBuildPlaymatHTML();
      if (typeof lucide !== 'undefined') lucide.createIcons({ nodes: [mat] });
    }

    PM.startMatch(allCards, { playerDeck, cpuDeck });

    const setup = $('practice-setup');
    if (setup) setup.hidden = true;
    if (mat)   mat.hidden = false;
    view.classList.add('playmat-mode');
    pmMarkPlaymatActive();

    pmInitPlaymat();
    pmUpdateAll();
    pmShowSetupHonorsRoll();
    pmMaybeShowTutorial();
  };
  $('btn-start-practice')?.addEventListener('click', startHandler);
  $('btn-start-practice-your-deck')?.addEventListener('click', startHandler);
  $('btn-start-practice-cpu-deck')?.addEventListener('click', startHandler);

  // Initial UI sync
  pmUpdateCustomRulesBadge();
  pmUpdateFormatBanners();
  pmUpdateFormatRowVisibility();
}

// Hide the format row outside Playmaker — the deck-format taxonomy
// (Standard / SPEC / SPEC+ / Limited) only applies to full Playmaker
// games. Mirrors iOS PracticeSetupView's conditional row.
function pmUpdateFormatRowVisibility() {
  const row = document.getElementById('practice-format-row');
  if (!row) return;
  row.hidden = (PM.mode !== 'playmaker');
}

// Sync the "N overrides" badge on the disclosure header.
function pmUpdateCustomRulesBadge() {
  const badge = document.getElementById('practice-custom-rules-badge');
  if (!badge) return;
  const c = PM.customRules || {};
  let n = 0;
  if (c.matchLength && c.matchLength !== 'bo7') n++;
  if (c.heroFormat && c.heroFormat !== 'standard') n++;
  if (c.startingHotDogs != null && c.startingHotDogs !== 10) n++;
  if (c.superBreaksTies === false) n++;
  if (c.suddenDeath === false) n++;
  badge.hidden = n === 0;
  badge.textContent = `${n} override${n === 1 ? '' : 's'}`;
}

// Render format-compliance banner under each deck dropdown.
// - Hidden when format is standard.
// - Cyan checkmark when the selected source is fully compliant.
// - Amber warning when a template has heroes above the active cap.
function pmUpdateFormatBanners() {
  const format = (PM.customRules && PM.customRules.heroFormat) || 'standard';
  const cap = pmFormatPowerCap(format);
  const size = pmFormatHeroDeckSize(format);

  function paint(banner, sel) {
    if (!banner) return;
    if (format === 'standard' || PM.mode !== 'playmaker') {
      banner.hidden = true;
      return;
    }
    const value = sel?.value || 'random';
    const spec = pmParseDeckSpec(value);
    // Template + saved decks resolve async, so we can't show a precount
    // of cap-violators here without paying a fetch latency. The format-
    // aware builder + padHeroDeck still filter at startMatch time; this
    // banner just communicates the active format restriction so the user
    // isn't surprised.
    let bad = 0;
    if (spec && spec.kind === 'template' && dbTemplateData) {
      const tpl = dbTemplateData[spec.key];
      if (tpl && Array.isArray(tpl.heroIds)) {
        const cap = pmFormatPowerCap(format);
        if (cap != null && PM.allCards && PM.allCards.length) {
          const byId = {};
          for (const c of PM.allCards) if (c.bobaId) byId[c.bobaId] = c;
          for (const id of tpl.heroIds) {
            const card = byId[id];
            if (card && (card.power || 0) > cap) bad++;
          }
        }
      }
    }
    const labelMap = { spec: 'SPEC · 160 power cap', specPlus: 'SPEC+ · 200 power cap', limited: 'Limited · 40-card deck' };
    const tag = labelMap[format] || format;
    if (bad > 0) {
      banner.className = 'practice-format-banner warning';
      banner.textContent = `${tag} · ${bad} hero${bad === 1 ? '' : 'es'} in this selection will be filtered to fit`;
    } else {
      banner.className = 'practice-format-banner compliant';
      banner.textContent = `${tag} · ${size}-card hero deck · ready to play`;
    }
    banner.hidden = false;
  }
  paint(document.getElementById('practice-player-format-banner'), document.getElementById('practice-player-select'));
  paint(document.getElementById('practice-cpu-format-banner'),    document.getElementById('practice-cpu-select'));
}

/// Setup overlay — animates the honors roll (1d6 per side) before
/// the first battle starts. Mirrors iOS SetupHonorsRollOverlay.
/// Layout is intentionally compact so it fits in iPhone landscape
/// without clipping the bottom of the popup.
function pmShowSetupHonorsRoll() {
  const data = PM._pendingSetupHonors;
  if (!data) return;
  PM._pendingSetupHonors = null;

  const overlay = document.createElement('div');
  overlay.id = 'pm-setup-honors-overlay';
  overlay.className = 'modal-overlay pm-modal-overlay pm-setup-honors-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', 'Roll for honors');

  const dieFaces = ['⚀','⚁','⚂','⚃','⚄','⚅'];
  const renderDie = (val) => `<span class="pm-shr-die" data-final="${val}">${dieFaces[val - 1]}</span>`;

  overlay.innerHTML = `
    <div class="pm-setup-honors">
      <h2 class="pm-shr-title">ROLL FOR HONORS</h2>
      <p class="pm-shr-sub">High roll acts first in Battle 1.</p>
      <div class="pm-shr-grid">
        <div class="pm-shr-col pm-shr-col--you">
          <div class="pm-shr-label">YOU</div>
          ${renderDie(data.playerRoll)}
        </div>
        <div class="pm-shr-col pm-shr-col--cpu">
          <div class="pm-shr-label">CPU</div>
          ${renderDie(data.cpuRoll)}
        </div>
      </div>
      <div class="pm-shr-result" hidden>
        <div class="pm-shr-winner pm-shr-winner--${data.winner}">
          ${data.winner === 'player' ? 'YOU WIN HONORS' : 'CPU WINS HONORS'}
        </div>
        <button class="pm-shr-begin" type="button">BEGIN BATTLE 1</button>
      </div>
    </div>`;
  document.body.appendChild(overlay);

  // Tumble the dice for ~1.0s, then settle on the rolled values.
  const dieEls = overlay.querySelectorAll('.pm-shr-die');
  const SPIN_MS = 1000;
  const FRAME_MS = 60;
  const start = Date.now();
  const interval = setInterval(() => {
    if (Date.now() - start >= SPIN_MS) {
      clearInterval(interval);
      dieEls.forEach(el => {
        const final = parseInt(el.dataset.final, 10);
        el.textContent = dieFaces[final - 1];
        el.classList.add('settled');
      });
      const winnerCol = overlay.querySelector(`.pm-shr-col--${data.winner}`);
      if (winnerCol) winnerCol.classList.add('won');
      const result = overlay.querySelector('.pm-shr-result');
      if (result) result.hidden = false;
      return;
    }
    dieEls.forEach(el => {
      el.textContent = dieFaces[Math.floor(Math.random() * 6)];
    });
  }, FRAME_MS);

  overlay.querySelector('.pm-shr-begin')?.addEventListener('click', () => {
    overlay.remove();
  });
}

// ── First-run tutorial ─────────────────────────────────────────────
// 5 ordered callouts spotlighting real playmat elements. No blur —
// the content behind stays fully visible. A glowing ring traces the
// target element; the tooltip card sits adjacent with an arrow.
// Fires once per browser (localStorage['bp_practiceTutorialSeen_v1']).

const PM_TUTORIAL_STEPS = [
  { key: 'scoreboard',
    title: 'Battle Score',
    message: "Your wins vs. the CPU's. First to 4 Battles wins the match. If it's 3–3 after Battle 7, Sudden Death decides the game.",
    selector: '.pm-scoreboard',
    placement: 'bottom' },
  { key: 'activeBattle',
    title: 'The Active Battle',
    message: "Your Hero faces the CPU's. Higher Power wins this Battle. If Power is tied, a Hero with a Super Weapon wins — otherwise the Battle is a draw (no trophy).",
    selector: '.pm-bc.active',
    placement: 'right' },
  { key: 'bench',
    title: 'Your Bench',
    message: "Before Heroes are revealed, the Honors player may spend 2 Hot Dogs to swap their face-down Hero for one from the Bench. One Sub per Battle.",
    selector: '.pm-bench-area',
    placement: 'top' },
  { key: 'plays',
    title: 'Your Plays',
    message: "After Heroes reveal, the Honors player goes first. Play any number of Plays (paying Hot Dogs) or pass — each player gets one turn to play Plays per Battle.",
    selector: '.pm-hand-area',
    placement: 'top' },
  { key: 'advance',
    title: 'Advance the Battle',
    message: "Each Battle runs: Substitute → Reveal → Play → Resolve. After the Battle, both players draw 1 Play and the winner takes Honors next. Tap here to advance.",
    selector: '#pm-btn-done',
    placement: 'top' }
];

// Mode-aware step list. Mirrors iOS PracticeView.tutorialStepsForMode:
// Rookie skips bench + plays; Substitution keeps bench but skips plays.
function pmTutorialStepsForCurrentMode() {
  const mode = PM.mode || 'playmaker';
  return PM_TUTORIAL_STEPS.filter(step => {
    if (step.key === 'bench') return mode !== 'rookie';
    if (step.key === 'plays') return mode === 'playmaker';
    return true;
  });
}

function pmMaybeShowTutorial() {
  try {
    if (localStorage.getItem('bp_practiceTutorialSeen_v1')) return;
  } catch (_) { /* private mode — show anyway */ }
  pmShowTutorial(0);
}

// Re-fire the tutorial from step 0 regardless of seen state. Used by
// the "?" button in the top bar so coaches can replay the walkthrough.
function pmReplayTutorial() {
  try { localStorage.removeItem('bp_practiceTutorialSeen_v1'); } catch (_) {}
  pmShowTutorial(0);
}

function pmShowTutorial(stepIdx) {
  document.getElementById('pm-tutorial')?.remove();

  const steps = pmTutorialStepsForCurrentMode();
  const step = steps[stepIdx];
  if (!step) return;
  const isLast = stepIdx >= steps.length - 1;
  const total = steps.length;

  const target = document.querySelector(step.selector);
  if (!target) {
    // Target missing — skip gracefully
    if (!isLast) return pmShowTutorial(stepIdx + 1);
    try { localStorage.setItem('bp_practiceTutorialSeen_v1', '1'); } catch (_) {}
    return;
  }

  const overlay = document.createElement('div');
  overlay.id = 'pm-tutorial';
  overlay.className = 'pm-tutorial';

  const dots = steps.map((_, i) =>
    `<span class="pm-tutorial-dot${i === stepIdx ? ' active' : ''}"></span>`
  ).join('');

  overlay.innerHTML = `
    <div class="pm-tutorial-scrim" aria-hidden="true"></div>
    <div class="pm-tutorial-ring" aria-hidden="true"></div>
    <div class="pm-tutorial-card" role="dialog" aria-modal="true" aria-labelledby="pm-tutorial-title">
      <div class="pm-tutorial-arrow" aria-hidden="true"></div>
      <div class="pm-tutorial-head">
        <span class="pm-tutorial-step">STEP ${stepIdx + 1} OF ${total}</span>
        <button class="pm-tutorial-skip" type="button">SKIP</button>
      </div>
      <div class="pm-tutorial-title" id="pm-tutorial-title">${step.title}</div>
      <div class="pm-tutorial-message">${step.message}</div>
      <div class="pm-tutorial-dots">${dots}</div>
      <button class="pm-tutorial-next" type="button">${isLast ? 'GOT IT' : 'NEXT'}</button>
    </div>
  `;
  document.body.appendChild(overlay);

  const ring = overlay.querySelector('.pm-tutorial-ring');
  const card = overlay.querySelector('.pm-tutorial-card');
  const arrow = overlay.querySelector('.pm-tutorial-arrow');

  const place = () => {
    const r = target.getBoundingClientRect();
    const pad = 6;
    // Ring traces the target with padding
    ring.style.top    = (r.top - pad) + 'px';
    ring.style.left   = (r.left - pad) + 'px';
    ring.style.width  = (r.width  + pad * 2) + 'px';
    ring.style.height = (r.height + pad * 2) + 'px';

    // Tooltip placement — adapt when requested side doesn't fit
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const cardW = Math.min(420, vw - 32);
    card.style.width = cardW + 'px';
    const cardRect = card.getBoundingClientRect();
    const cardH = cardRect.height;

    const gap = 18; // distance between ring and card
    const spaceBelow = vh - r.bottom;
    const spaceAbove = r.top;
    const spaceRight = vw - r.right;
    const spaceLeft  = r.left;

    let placement = step.placement;
    // Fallback if requested side doesn't have room
    const needed = cardH + gap + 16;
    if (placement === 'bottom' && spaceBelow < needed && spaceAbove > needed) placement = 'top';
    if (placement === 'top'    && spaceAbove < needed && spaceBelow > needed) placement = 'bottom';
    if (placement === 'right'  && spaceRight < cardW + gap + 16) placement = spaceBelow >= needed ? 'bottom' : 'top';
    if (placement === 'left'   && spaceLeft  < cardW + gap + 16) placement = spaceBelow >= needed ? 'bottom' : 'top';

    let cardTop, cardLeft, arrowTop, arrowLeft, arrowDir;
    if (placement === 'bottom') {
      cardTop  = r.bottom + gap;
      cardLeft = Math.max(16, Math.min(vw - cardW - 16, r.left + r.width / 2 - cardW / 2));
      arrowDir = 'up';
      arrowTop = -7;
      arrowLeft = (r.left + r.width / 2) - cardLeft - 7;
    } else if (placement === 'top') {
      cardTop  = r.top - gap - cardH;
      cardLeft = Math.max(16, Math.min(vw - cardW - 16, r.left + r.width / 2 - cardW / 2));
      arrowDir = 'down';
      arrowTop = cardH - 7;
      arrowLeft = (r.left + r.width / 2) - cardLeft - 7;
    } else if (placement === 'right') {
      cardLeft = r.right + gap;
      cardTop  = Math.max(16, Math.min(vh - cardH - 16, r.top + r.height / 2 - cardH / 2));
      arrowDir = 'left';
      arrowLeft = -7;
      arrowTop = (r.top + r.height / 2) - cardTop - 7;
    } else { // left
      cardLeft = r.left - gap - cardW;
      cardTop  = Math.max(16, Math.min(vh - cardH - 16, r.top + r.height / 2 - cardH / 2));
      arrowDir = 'right';
      arrowLeft = cardW - 7;
      arrowTop = (r.top + r.height / 2) - cardTop - 7;
    }

    // Clamp tooltip inside viewport
    cardTop  = Math.max(12, Math.min(vh - cardH - 12, cardTop));
    cardLeft = Math.max(12, Math.min(vw - cardW - 12, cardLeft));

    card.style.top  = cardTop + 'px';
    card.style.left = cardLeft + 'px';
    card.setAttribute('data-arrow', arrowDir);
    arrow.style.top  = arrowTop + 'px';
    arrow.style.left = arrowLeft + 'px';
  };
  place();

  const close = () => {
    try { localStorage.setItem('bp_practiceTutorialSeen_v1', '1'); } catch (_) {}
    window.removeEventListener('resize', place);
    overlay.remove();
  };
  const advance = () => { isLast ? close() : pmShowTutorial(stepIdx + 1); };

  overlay.querySelector('.pm-tutorial-next').addEventListener('click', advance);
  overlay.querySelector('.pm-tutorial-skip').addEventListener('click', close);
  overlay.querySelector('.pm-tutorial-scrim').addEventListener('click', advance);
  window.addEventListener('resize', place);
  // Re-place on the next frame once layout has settled (handles initial async renders)
  requestAnimationFrame(place);
}

// ── Deck spec parsing / resolution for practice setup ──────────────

function pmParseDeckSpec(value) {
  if (!value || value === 'random') return { kind: 'random' };
  if (value.startsWith('template:')) return { kind: 'template', key: value.slice('template:'.length) };
  if (value.startsWith('saved:'))    return { kind: 'saved',    deckId: value.slice('saved:'.length) };
  return { kind: 'random' };
}

async function pmResolveDeckSpec(spec, allCards) {
  if (!spec || spec.kind === 'random') return null;
  const byId = {};
  for (const c of allCards) if (c.bobaId) byId[c.bobaId] = c;
  const heroes = [], plays = [], hotDogs = [];

  if (spec.kind === 'template') {
    if (!dbTemplateData) {
      try { dbTemplateData = await fetch('assets/data/template-decks.json').then(r => r.json()); }
      catch { return null; }
    }
    const tpl = dbTemplateData[spec.key];
    if (!tpl) return null;
    for (const id of tpl.heroIds || [])      { const c = byId[id]; if (c) heroes.push(c); }
    for (const id of tpl.playIds || [])      { const c = byId[id]; if (c) plays.push(c); }
    for (const id of tpl.bonusPlayIds || []) { const c = byId[id]; if (c) plays.push(c); }
    for (const id of tpl.hotDogIds || [])    { const c = byId[id]; if (c) hotDogs.push(c); }
    return { heroes, plays, hotDogs };
  }

  if (spec.kind === 'saved') {
    try {
      const rows = await API.deckLoad(spec.deckId);
      for (const row of rows) {
        const card = byId[row.boba_id];
        if (!card) continue;
        if (row.card_type === 'hero') heroes.push(card);
        else if (row.card_type === 'play' || row.card_type === 'bonus_play') plays.push(card);
        else if (row.card_type === 'hot_dog') hotDogs.push(card);
      }
      return { heroes, plays, hotDogs };
    } catch (err) {
      console.warn('Saved deck load failed; falling back to random.', err);
      return null;
    }
  }

  return null;
}

async function pmPopulateSavedDeckOptions() {
  const playerGroup = $('practice-player-saved');
  const cpuGroup    = $('practice-cpu-saved');
  if (!playerGroup && !cpuGroup) return;

  let decks = [];
  try {
    const session = await API.authGetSession?.();
    if (!session) {
      // Hide groups when signed out
      if (playerGroup) playerGroup.hidden = true;
      if (cpuGroup)    cpuGroup.hidden    = true;
      return;
    }
    decks = await API.deckList();
  } catch { decks = []; }

  if (!decks.length) {
    if (playerGroup) playerGroup.hidden = true;
    if (cpuGroup)    cpuGroup.hidden    = true;
    return;
  }

  const html = decks.map(d =>
    `<option value="saved:${d.id}">${(d.name || 'Untitled').replace(/</g, '&lt;')}</option>`
  ).join('');
  if (playerGroup) { playerGroup.hidden = false; playerGroup.innerHTML = html; }
  if (cpuGroup)    { cpuGroup.hidden    = false; cpuGroup.innerHTML    = html; }
}

// ════════════════════════════════════════════════════════════════
// § Init — called from app.js after displayCards loaded
// ════════════════════════════════════════════════════════════════

// Catalog of rule presets (2026 Nationals events + casual baselines).
// Loaded lazily from assets/data/rule_presets.json at first access.
let RULE_PRESETS = null;
async function loadRulePresets() {
  if (RULE_PRESETS) return RULE_PRESETS;
  try {
    const resp = await fetch('assets/data/rule_presets.json');
    if (resp.ok) RULE_PRESETS = await resp.json();
  } catch (_) { /* offline — presets remain unavailable, picker shows a stub */ }
  if (!RULE_PRESETS) RULE_PRESETS = { schemaVersion: 0, presets: [], casualPresets: [] };
  return RULE_PRESETS;
}

// ── Deck Rules modal ──────────────────────────────────────────────
async function dbOpenRulesModal(allCards) {
  await loadRulePresets();
  const modal = $('db-rules-modal');
  if (!modal) return;
  modal.hidden = false;
  document.body.classList.add('db-rules-open');
  dbRenderRulesSheet(allCards);
}
function dbCloseRulesModal() {
  const modal = $('db-rules-modal');
  if (!modal) return;
  modal.hidden = true;
  document.body.classList.remove('db-rules-open');
}

function dbRenderRulesSheet(allCards) {
  const body = $('db-rules-body');
  const resetBtn = $('db-rules-reset');
  if (!body) return;

  const nat = RULE_PRESETS?.presets || [];
  const casual = RULE_PRESETS?.casualPresets || [];
  const active = DB.activePreset;
  const isCustom = DB.isCustomRuleSet;
  if (resetBtn) resetBtn.disabled = !isCustom && !DB.activePresetID;

  const activeRuleChip = r => `
    <li class="dbr-rule${r.isOverride ? ' dbr-rule-override' : ''}">
      <span class="dbr-rule-dot"></span>
      <span class="dbr-rule-label">${esc(r.label)}</span>
      ${r.isOverride ? '<span class="dbr-rule-pill">CUSTOM</span>' : ''}
    </li>`;

  const presetCard = p => {
    const selected = DB.activePresetID === p.id;
    const purse = p.divisionPurse ? `<span class="dbr-preset-purse">$${Math.round(p.divisionPurse/1000)}k</span>` : '';
    return `
      <button class="dbr-preset${selected ? ' dbr-preset-selected' : ''}" data-preset-id="${esc(p.id)}">
        <span class="dbr-preset-check">${selected ? '●' : '○'}</span>
        <span class="dbr-preset-body">
          <span class="dbr-preset-title">${esc(p.name)} ${purse}</span>
          <span class="dbr-preset-desc">${esc(p.description || '')}</span>
        </span>
      </button>`;
  };

  const specialRuleRow = r => {
    const label = dbSpecialRuleLabel(r);
    const pill = r.selfVerify ? '<span class="dbr-rule-pill dbr-rule-selfverify">SELF-VERIFY</span>' : '';
    const note = r.note ? `<div class="dbr-rule-note">${esc(r.note)}</div>` : '';
    return `<li class="dbr-special"><span class="dbr-rule-label">${esc(label)}</span>${pill}${note}</li>`;
  };

  const toggle = (id, on, title, desc) => `
    <label class="dbr-toggle">
      <input type="checkbox" id="${id}" ${on ? 'checked' : ''}>
      <span class="dbr-toggle-body">
        <span class="dbr-toggle-title">${esc(title)}</span>
        <span class="dbr-toggle-desc">${esc(desc)}</span>
      </span>
    </label>`;

  const needsPlays = DB.currentFormat.needsPlays;
  const effPerPower = DB.effectivePerPowerLimit;

  body.innerHTML = `
    <div class="dbr-section">
      <div class="dbr-section-label">Rule Set</div>
      <details class="dbr-presets-group" open>
        <summary><strong>2026 Nationals Events</strong> <span>${nat.length} presets from the DRAFT PDF</span></summary>
        <div class="dbr-presets">${nat.map(presetCard).join('')}</div>
      </details>
      <details class="dbr-presets-group">
        <summary><strong>Casual Rule Sets</strong> <span>Home-rules + legacy presets</span></summary>
        <div class="dbr-presets">${casual.map(presetCard).join('')}</div>
      </details>
      ${isCustom ? `
        <div class="dbr-custom-indicator">
          <strong>Custom Rule Set</strong>
          <span>${active ? `Based on "${esc(active.name)}" with your customizations.` : 'Building under format defaults — no preset attached.'}</span>
        </div>` : ''}
    </div>

    <div class="dbr-section">
      <div class="dbr-section-label">${esc(active ? active.name : DB.format)} — Active Rules</div>
      <ul class="dbr-rules-list">${DB.activeRules.map(activeRuleChip).join('')}</ul>
    </div>

    ${active && active.specialRules && active.specialRules.length ? `
      <div class="dbr-section">
        <div class="dbr-section-label">Division-Specific Rules</div>
        <ul class="dbr-rules-list">${active.specialRules.map(specialRuleRow).join('')}</ul>
        <div class="dbr-section-foot">SELF-VERIFY rules can't be machine-checked against the catalog — you confirm compliance yourself.</div>
      </div>` : ''}

    <div class="dbr-section">
      <div class="dbr-section-label">Optional Rule Toggles</div>
      ${toggle('dbr-toggle-hero6', DB.ruleOverrides.perHeroNameLimit === 6,
               'Max 6 of same hero (legacy)',
               'Pre-2026 rule, retired in the Nationals PDF. Useful for casual / teaching play.')}
      <div class="dbr-segmented">
        <label class="dbr-segmented-label">Per-power-value limit</label>
        <div class="dbr-segmented-options">
          <button data-perpower="3"${effPerPower === 3 ? ' class="active"' : ''}>3 (Blast)</button>
          <button data-perpower="6"${effPerPower === 6 ? ' class="active"' : ''}>6 (standard)</button>
        </div>
      </div>
      ${needsPlays ? toggle('dbr-toggle-bonus', DB.ruleOverrides.bonusPlaysEnabled,
               'Bonus Plays enabled',
               'Off in Spec Playmaker / Brawl Playmaker per 2026 PDF; on elsewhere.') : ''}
      ${needsPlays ? toggle('dbr-toggle-htd', DB.ruleOverrides.htdPlaysEnabled,
               'HTD Plays enabled',
               'Off in Spec Playmaker / Brawl Playmaker; N/A in Tecmo Bowl.') : ''}
      ${needsPlays ? toggle('dbr-toggle-dbs', DB.effectiveEnforceDBS,
               'DBS budget enforced',
               '1,000 DBS cap for Playmaker divisions. Flip off for casual builds.') : ''}
    </div>
  `;

  // Wire preset clicks
  body.querySelectorAll('[data-preset-id]').forEach(btn => {
    btn.addEventListener('click', () => {
      const pid = btn.dataset.presetId;
      const preset = [...nat, ...casual].find(p => p.id === pid);
      if (preset) {
        DB.applyPreset(preset);
        // Update the format pills to match
        document.querySelectorAll('#view-decks .db-format-btn').forEach(b => {
          b.classList.toggle('active', b.dataset.format === DB.format);
        });
        dbRender(allCards);
        dbRenderRulesSheet(allCards);
      }
    });
  });

  // Wire toggles
  body.querySelector('#dbr-toggle-hero6')?.addEventListener('change', e => {
    DB.ruleOverrides.perHeroNameLimit = e.target.checked ? 6 : null;
    dbRender(allCards); dbRenderRulesSheet(allCards);
  });
  body.querySelectorAll('[data-perpower]').forEach(b => {
    b.addEventListener('click', () => {
      const n = Number(b.dataset.perpower);
      DB.ruleOverrides.perPowerLimit = (n === DB.currentFormat.perPowerDefault) ? null : n;
      dbRender(allCards); dbRenderRulesSheet(allCards);
    });
  });
  body.querySelector('#dbr-toggle-bonus')?.addEventListener('change', e => {
    DB.ruleOverrides.bonusPlaysEnabled = e.target.checked;
    dbRender(allCards); dbRenderRulesSheet(allCards);
  });
  body.querySelector('#dbr-toggle-htd')?.addEventListener('change', e => {
    DB.ruleOverrides.htdPlaysEnabled = e.target.checked;
    dbRender(allCards); dbRenderRulesSheet(allCards);
  });
  body.querySelector('#dbr-toggle-dbs')?.addEventListener('change', e => {
    DB.ruleOverrides.enforceDBS = e.target.checked;
    dbRender(allCards); dbRenderRulesSheet(allCards);
  });
}

function dbSpecialRuleLabel(r) {
  switch (r.kind) {
    case 'weaponRestriction':    return `Weapons: ${(r.allowed || []).join(', ')}`;
    case 'treatmentContains':    return `${r.scope === 'all' ? 'All cards' : 'Heroes'} must be ${r.token} treatment`;
    case 'hotDogHero':           return `All Hot Dogs must be "${r.name}"`;
    case 'setRestriction':       return `Set: ${(r.allowed || []).join(', ')}`;
    case 'ownershipProof':       return `Ownership: ${r.description || (r.count + ' unique')}`;
    case 'bannedCardType':       return `No ${r.type} cards`;
    case 'overrideHeroCount':    return `Hero count: ${r.value}`;
    case 'overridePerPowerLimit':return `Max ${r.value} per power`;
    default:                     return r.kind;
  }
}

// Minimal HTML-escape helper for rules-sheet text
function esc(s) {
  return String(s || '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
}

function initPlayTools(allCards) {
  loadRulePresets(); // fire-and-forget; presets appear once JSON arrives
  initDeckBuilder(allCards);
  initPractice(allCards);
}

// Export for app.js
if (typeof window !== 'undefined') {
  window.initPlayTools = initPlayTools;
}
