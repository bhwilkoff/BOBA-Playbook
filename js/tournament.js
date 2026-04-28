/* Tournament engine — web port of iOS TournamentEngine.
 *
 * Local-only bracket engine. No external sync, no commissioner
 * workflow, no prize logistics. Generates schedules, tracks match
 * results, declares champions. Pairs with js/elo.js for per-match
 * rating updates.
 *
 * Same data shape as the Swift side so a future Supabase table can
 * carry the same JSON. Practice is admin-gated on web today; this
 * module is forward-looking infrastructure.
 */
(function () {
  'use strict';

  const FORMATS = {
    ROUND_ROBIN:    'round-robin',
    SWISS:          'swiss',
    SINGLE_ELIM:    'single-elim',
    SWISS_PLAYOFF:  'swiss-playoff',
    RR_PLAYOFF:     'rr-playoff',
  };

  const REPORT_LEVELS = {
    WINNER_ONLY: 'winner-only',
    GAMES:       'games',
    BATTLES:     'battles',
  };

  // ─── Helpers ────────────────────────────────────────────────────────

  /** Crockford-ish 8-char id; not crypto. */
  function uid() {
    return Math.random().toString(36).slice(2, 6) +
           Math.random().toString(36).slice(2, 6);
  }

  function shuffle(arr) {
    const a = arr.slice();
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  function clone(x) { return JSON.parse(JSON.stringify(x)); }

  // ─── Creation ───────────────────────────────────────────────────────

  function create({
    name,
    mode,
    format,
    deckRules = 'apex',
    maxPlayers = 16,
    reportLevel = REPORT_LEVELS.WINNER_ONLY,
    playoffCut = 8,
  } = {}) {
    return {
      id: uid(),
      name,
      mode,
      format,
      deckRules,
      maxPlayers,
      status: 'setup',
      participants: [],
      rounds: [],
      champion: null,
      createdAt: new Date().toISOString(),
      reportLevel,
      playoffCut,
    };
  }

  function addParticipant(t, participant) {
    if (t.status !== 'setup') return;
    if (t.participants.length >= t.maxPlayers) return;
    if (t.participants.some(p => p.id === participant.id)) return;
    t.participants.push(Object.assign({ status: 'active' }, participant));
  }

  // ─── Schedule generation ────────────────────────────────────────────

  /** Round-robin scheduler — circle method. Pre-schedules every
   *  round so the engine can advance through them without further
   *  pairing decisions. With odd N we inject a sentinel BYE. */
  function roundRobinRounds(active) {
    let roster = active.slice();
    if (roster.length % 2 === 1) {
      roster.push({ id: '__bye__', displayName: 'BYE', type: 'cpu',
                    cpuProfile: null, deckId: '', status: 'active' });
    }
    const n = roster.length;
    const rounds = [];
    let ids = roster.map(r => r.id);
    for (let r = 0; r < n - 1; r++) {
      const matches = [];
      for (let i = 0; i < n / 2; i++) {
        const p1 = ids[i];
        const p2 = ids[n - 1 - i];
        const real1 = p1 !== '__bye__' ? p1 : null;
        const real2 = p2 !== '__bye__' ? p2 : null;
        if (!real1) {
          if (real2) matches.push({
            id: uid(), participant1Id: real2, participant2Id: null,
            status: 'scheduled', winnerId: null,
          });
          continue;
        }
        matches.push({
          id: uid(), participant1Id: real1, participant2Id: real2,
          status: 'scheduled', winnerId: null,
        });
      }
      rounds.push({ index: r, phase: 'group', matches });
      // Rotate everyone except index 0 (standard circle method).
      const last = ids.pop();
      ids.splice(1, 0, last);
    }
    return rounds;
  }

  function swissRoundOne(active) {
    const roster = shuffle(active);
    const matches = [];
    while (roster.length >= 2) {
      const a = roster.shift(), b = roster.shift();
      matches.push({
        id: uid(), participant1Id: a.id, participant2Id: b.id,
        status: 'scheduled', winnerId: null,
      });
    }
    if (roster.length) {
      matches.push({
        id: uid(), participant1Id: roster[0].id, participant2Id: null,
        status: 'scheduled', winnerId: null,
      });
    }
    return { index: 0, phase: 'group', matches };
  }

  /** Single-elim with BYEs for non-power-of-two counts. */
  function singleElimRounds(active, phase = 'playoff') {
    if (!active.length) return [];
    let bracketSize = 1;
    while (bracketSize < active.length) bracketSize *= 2;
    const slots = active.map(p => p.id);
    while (slots.length < bracketSize) slots.push(null);
    const matches = [];
    for (let i = 0; i < slots.length; i += 2) {
      const a = slots[i], b = slots[i + 1];
      if (a && b) matches.push({
        id: uid(), participant1Id: a, participant2Id: b,
        status: 'scheduled', winnerId: null,
      });
      else if (a)  matches.push({
        id: uid(), participant1Id: a, participant2Id: null,
        status: 'scheduled', winnerId: null,
      });
      else if (b)  matches.push({
        id: uid(), participant1Id: b, participant2Id: null,
        status: 'scheduled', winnerId: null,
      });
    }
    return [{ index: 0, phase, matches }];
  }

  function generateSchedule(t) {
    if (t.status !== 'setup' || t.participants.length < 2) return false;
    const active = t.participants.filter(p => p.status === 'active');
    switch (t.format) {
      case FORMATS.ROUND_ROBIN:
      case FORMATS.RR_PLAYOFF:
        t.rounds = roundRobinRounds(active);
        break;
      case FORMATS.SWISS:
      case FORMATS.SWISS_PLAYOFF:
        t.rounds = [swissRoundOne(active)];
        break;
      case FORMATS.SINGLE_ELIM:
        t.rounds = singleElimRounds(active, 'playoff');
        break;
    }
    t.status = 'running';
    return true;
  }

  // ─── Match reporting ────────────────────────────────────────────────

  function locateMatch(t, id) {
    for (let r = 0; r < t.rounds.length; r++) {
      const m = t.rounds[r].matches.findIndex(x => x.id === id);
      if (m >= 0) return { r, m };
    }
    return null;
  }

  /** Winner-only report. Higher granularity (games, battles) is
   *  accepted; engine derives the winner from games-tally if needed.
   *  BYE matches auto-advance the present participant. */
  function reportMatch(t, matchId, { winnerId, games, battles } = {}) {
    const loc = locateMatch(t, matchId);
    if (!loc) return false;
    const match = t.rounds[loc.r].matches[loc.m];
    if (match.participant2Id == null) {
      match.winnerId = match.participant1Id;
      match.status = 'completed';
      return true;
    }
    let resolved = winnerId;
    if (resolved == null && games && games.length) {
      const p1Wins = games.filter(g => g.winnerId === match.participant1Id).length;
      const p2Wins = games.filter(g => g.winnerId === match.participant2Id).length;
      if (p1Wins > p2Wins)      resolved = match.participant1Id;
      else if (p2Wins > p1Wins) resolved = match.participant2Id;
      match.player1Score = p1Wins;
      match.player2Score = p2Wins;
    }
    match.winnerId = resolved || null;
    if (games)   match.games   = games;
    if (battles) match.battles = battles;
    match.status = resolved ? 'completed' : 'in-progress';
    return true;
  }

  function isCurrentRoundComplete(t) {
    const last = t.rounds[t.rounds.length - 1];
    if (!last) return false;
    return last.matches.every(m => m.status === 'completed');
  }

  /** Standings: 1 win = 1, ties = 0.5 each. Returns participant ids
   *  in best-first order. */
  function orderedStandings(t) {
    const score = {};
    for (const r of t.rounds) {
      for (const m of r.matches) {
        if (m.status !== 'completed') continue;
        if (m.winnerId) {
          score[m.winnerId] = (score[m.winnerId] || 0) + 1;
        } else if (m.participant2Id != null) {
          score[m.participant1Id] = (score[m.participant1Id] || 0) + 0.5;
          score[m.participant2Id] = (score[m.participant2Id] || 0) + 0.5;
        }
      }
    }
    return t.participants
      .map(p => p.id)
      .sort((a, b) => (score[b] || 0) - (score[a] || 0));
  }

  function declareChampionByRecord(t) {
    const order = orderedStandings(t);
    if (order.length) t.champion = order[0];
    t.status = 'completed';
  }

  /** Standard Swiss round count: ceil(log2(N)) + 1. */
  function swissTargetRounds(t) {
    const n = t.participants.length;
    if (n <= 2) return 1;
    return Math.ceil(Math.log2(n)) + 1;
  }

  function swissNextRoundOrFinish(t, withPlayoff) {
    const target = swissTargetRounds(t);
    const groupRounds = t.rounds.filter(r => r.phase === 'group').length;
    if (groupRounds < target) {
      const standings = orderedStandings(t);
      const played = new Set();
      for (const r of t.rounds) {
        for (const m of r.matches) {
          if (m.participant2Id != null) {
            played.add(`${m.participant1Id}|${m.participant2Id}`);
            played.add(`${m.participant2Id}|${m.participant1Id}`);
          }
        }
      }
      const queue = standings.slice();
      const matches = [];
      while (queue.length) {
        const a = queue.shift();
        // Prefer un-played pairings; fall back to first remaining.
        let bIdx = queue.findIndex(b => !played.has(`${a}|${b}`));
        if (bIdx === -1) bIdx = queue.length ? 0 : -1;
        if (bIdx >= 0) {
          const b = queue.splice(bIdx, 1)[0];
          matches.push({
            id: uid(), participant1Id: a, participant2Id: b,
            status: 'scheduled', winnerId: null,
          });
        } else {
          matches.push({
            id: uid(), participant1Id: a, participant2Id: null,
            status: 'scheduled', winnerId: null,
          });
        }
      }
      const next = { index: groupRounds, phase: 'group', matches };
      t.rounds.push(next);
      return next;
    }
    if (withPlayoff) return openOrAdvancePlayoff(t);
    declareChampionByRecord(t);
    return null;
  }

  function openOrAdvancePlayoff(t) {
    const hasPlayoff = t.rounds.some(r => r.phase === 'playoff');
    if (!hasPlayoff) {
      const standings = orderedStandings(t);
      const cut = standings.slice(0, t.playoffCut);
      const cutSet = new Set(cut);
      for (const p of t.participants) {
        if (!cutSet.has(p.id)) p.status = 'eliminated';
      }
      const roster = cut.map(id => t.participants.find(p => p.id === id))
                        .filter(Boolean);
      const initial = singleElimRounds(roster, 'playoff');
      t.rounds.push(...initial);
      return initial[0] || null;
    }
    return singleElimAdvance(t);
  }

  function singleElimAdvance(t) {
    const last = t.rounds[t.rounds.length - 1];
    if (!last || last.phase !== 'playoff') return null;
    const winners = last.matches.map(m => m.winnerId).filter(Boolean);
    if (winners.length === 1) {
      t.champion = winners[0];
      t.status = 'completed';
      return null;
    }
    if (winners.length < 2) return null;
    const matches = [];
    for (let i = 0; i < winners.length; i += 2) {
      const a = winners[i];
      const b = i + 1 < winners.length ? winners[i + 1] : null;
      matches.push({
        id: uid(), participant1Id: a, participant2Id: b,
        status: 'scheduled', winnerId: null,
      });
    }
    const next = { index: last.index + 1, phase: 'playoff', matches };
    t.rounds.push(next);
    return next;
  }

  function advance(t) {
    if (t.status !== 'running') return null;
    if (!isCurrentRoundComplete(t)) return null;
    switch (t.format) {
      case FORMATS.ROUND_ROBIN: {
        const next = t.rounds.find(r => r.matches.some(m => m.status !== 'completed'));
        if (next) return next;
        declareChampionByRecord(t);
        return null;
      }
      case FORMATS.RR_PLAYOFF: {
        const groupDone = t.rounds.every(r =>
          r.phase !== 'group' || r.matches.every(m => m.status === 'completed'));
        const noPlayoffYet = !t.rounds.some(r => r.phase === 'playoff');
        if (!groupDone) return null;
        if (noPlayoffYet) return openOrAdvancePlayoff(t);
        return singleElimAdvance(t);
      }
      case FORMATS.SWISS:         return swissNextRoundOrFinish(t, false);
      case FORMATS.SWISS_PLAYOFF: return swissNextRoundOrFinish(t, true);
      case FORMATS.SINGLE_ELIM:   return singleElimAdvance(t);
    }
    return null;
  }

  // ─── Public API ─────────────────────────────────────────────────────

  window.BOBATournament = {
    FORMATS, REPORT_LEVELS,
    create, addParticipant, generateSchedule, reportMatch,
    isCurrentRoundComplete, orderedStandings, advance, clone,
  };
})();
