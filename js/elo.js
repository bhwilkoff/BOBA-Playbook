/* Elo rating system — web port of iOS EloEngine.
 *
 * Standard chess-Elo: K=32, 1000 starting rating, ties = 0.5.
 * Per-mode (rookie/sub/playmaker), per-source (practice-ai/pvp),
 * per-era buckets so a Rookie record never bleeds into a Playmaker
 * record. Tier names live-derived from rating using BoBA's weapon
 * vocabulary (Brawl..Super, 200-pt bands).
 *
 * Forward-looking infrastructure — practice is admin-gated on web
 * today; this engine is ready for when it surfaces again. The data
 * model is intentionally a 1:1 mirror of the Swift one so a future
 * cross-platform Supabase table can carry the same shape.
 */
(function () {
  'use strict';

  const K_FACTOR     = 32;
  const STARTING     = 1000;
  const TIE_SCORE    = 0.5;
  const STORAGE_KEY  = 'elo_records_v1';
  const CURRENT_ERA  = 'alpha-2026';

  /** Modes in the Practice surface. */
  const MODES = ['rookie', 'substitution', 'playmaker'];

  /** Score sources we keep separate. */
  const SOURCES = ['practice-ai', 'pvp'];

  /** CPU profile → reference rating. The user's rating moves toward
   *  whichever profile they faced. Sized so beating a Standard CPU
   *  earns the user a small but real climb. */
  const CPU_PROFILES = {
    rookie:   { rating: 800,  label: 'Rookie CPU' },
    standard: { rating: 1000, label: 'Standard CPU' },
    expert:   { rating: 1200, label: 'Expert CPU' },
    champion: { rating: 1500, label: 'Champion CPU' },
    master:   { rating: 1700, label: 'Master CPU' },
  };

  /** Live-derived from rating — never persisted. Tweaking the bands
   *  later doesn't lie about historic state since each EloRecord
   *  recomputes its tier on read. */
  const TIER_BANDS = [
    { name: 'Brawl', floor: 0    },
    { name: 'Steel', floor: 1000 },
    { name: 'Ice',   floor: 1200 },
    { name: 'Fire',  floor: 1400 },
    { name: 'Glow',  floor: 1600 },
    { name: 'Hex',   floor: 1800 },
    { name: 'Gum',   floor: 2000 },
    { name: 'Super', floor: 2200 },
  ];

  function tierFor(rating) {
    let name = TIER_BANDS[0].name;
    for (const b of TIER_BANDS) if (rating >= b.floor) name = b.name;
    return name;
  }

  /** Standard 400-pt logistic. */
  function expectedScore(player, opponent) {
    return 1 / (1 + Math.pow(10, (opponent - player) / 400));
  }

  function emptyRecord(mode, source, era) {
    return {
      mode, source, era,
      rating: STARTING,
      peakRating: STARTING,
      matches: 0, wins: 0, losses: 0, ties: 0,
      history: [],
      updatedAt: new Date().toISOString(),
    };
  }

  /** Mutates `record` in place and returns the signed rating delta.
   *  Outcome is one of 'W' | 'L' | 'T'. */
  function applyMatch(record, opponentRating, outcome, opponentLabel, matchRef) {
    const actual = outcome === 'W' ? 1 : outcome === 'L' ? 0 : TIE_SCORE;
    const expected = expectedScore(record.rating, opponentRating);
    const delta = Math.round(K_FACTOR * (actual - expected));
    record.rating     += delta;
    record.peakRating  = Math.max(record.peakRating, record.rating);
    record.matches    += 1;
    if      (outcome === 'W') record.wins   += 1;
    else if (outcome === 'L') record.losses += 1;
    else                       record.ties   += 1;
    record.history.push({
      at: new Date().toISOString(),
      rating: record.rating,
      delta,
      opponent: opponentLabel || null,
      outcome,
      matchRef: matchRef || null,
    });
    record.updatedAt = new Date().toISOString();
    return delta;
  }

  /** localStorage-backed singleton. Mirrors iOS EloStore. */
  const Store = {
    _records: null,

    _load() {
      if (this._records !== null) return;
      try {
        const raw = localStorage.getItem(STORAGE_KEY);
        this._records = raw ? JSON.parse(raw) : {};
      } catch (_) {
        this._records = {};
      }
    },

    _save() {
      try { localStorage.setItem(STORAGE_KEY, JSON.stringify(this._records)); }
      catch (_) { /* quota / private-mode — non-fatal */ }
    },

    /** Fetch the (mode, source, era) record, materializing an empty
     *  one at the starting rating if absent. */
    record(mode, source = 'practice-ai', era = CURRENT_ERA) {
      this._load();
      const key = `${era}|${source}|${mode}`;
      if (!this._records[key]) this._records[key] = emptyRecord(mode, source, era);
      return this._records[key];
    },

    /** Apply a finished practice match against a CPU profile. Returns
     *  the rating delta so callers can surface "+18 → Brawl 1018". */
    applyPracticeResult(mode, cpuProfileId, outcome, matchRef) {
      const profile = CPU_PROFILES[cpuProfileId] || CPU_PROFILES.standard;
      const rec = this.record(mode);
      const delta = applyMatch(rec, profile.rating, outcome, profile.label, matchRef);
      this._save();
      return delta;
    },

    /** All records for the current era, sorted by mode order. */
    allCurrent() {
      this._load();
      const out = [];
      for (const m of MODES) {
        const key = `${CURRENT_ERA}|practice-ai|${m}`;
        if (this._records[key]) out.push(this._records[key]);
      }
      return out;
    },
  };

  // Expose on window for ad-hoc consumers (practice JS, debug).
  window.BOBAElo = {
    K_FACTOR, STARTING, TIE_SCORE,
    MODES, SOURCES, CPU_PROFILES, TIER_BANDS, CURRENT_ERA,
    tierFor, expectedScore, applyMatch,
    Store,
  };
})();
