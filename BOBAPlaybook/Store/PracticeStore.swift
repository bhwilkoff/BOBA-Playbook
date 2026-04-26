//
//  PracticeStore.swift
//  BOBAPlaybook
//
//  @Observable game state machine for Practice Battle mode.
//  Manages current match, phase progression, CPU AI, and score.
//

import Foundation
import SwiftUI

// ════════════════════════════════════════════════════════════════
// MARK: - Practice Game Mode
// ════════════════════════════════════════════════════════════════

enum PracticeMode: String, CaseIterable, Identifiable, Codable {
    case rookie       = "Rookie"
    case substitution = "Substitution"
    case playmaker    = "Playmaker"
    var id: String { rawValue }

    var showHotDogs: Bool { self != .rookie }
    var showPlays: Bool   { self == .playmaker }
    var showBench: Bool   { self != .rookie }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Battle Phase
// ════════════════════════════════════════════════════════════════

enum BattlePhase: String, CaseIterable, Codable {
    case reveal      = "Reveal"
    case sub         = "Substitution"
    case play        = "Play Window"
    case resolution  = "Resolution"
    case cleanup     = "Cleanup"
    case matchOver   = "Match Over"

    var icon: String {
        switch self {
        case .reveal:     return "eye"
        case .sub:        return "bolt.fill"
        case .play:       return "rectangle.stack"
        case .resolution: return "scalemass"
        case .cleanup:    return "arrow.clockwise"
        case .matchOver:  return "trophy"
        }
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Battle Result
// ════════════════════════════════════════════════════════════════

enum BattleResult: String, Codable {
    case win, lose, tie
}

// ════════════════════════════════════════════════════════════════
// MARK: - Battle Slot
// ════════════════════════════════════════════════════════════════

struct PowerContribution: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let label: String
    let delta: Int
}

struct BattleSlot: Identifiable, Codable {
    let id: Int   // 0-based battle index
    var playerCard: Card?
    var cpuCard: Card?
    var playerPlayedCards: [Card] = []
    var cpuPlayedCards: [Card] = []
    var playerEffectPower: Int = 0   // bonus from played play cards
    var cpuEffectPower: Int = 0
    /// Auto-itemized power breakdown — each entry corresponds to one
    /// modifier (a played card or an in-scope persistent firing) that
    /// contributed to the side's effect power. Drives the Resolution
    /// overlay so coaches can audit the math at a glance and never
    /// hit the "wait, what did that +10 come from?" pain point that
    /// the practice-battle UI handoff calls out at [00:17:08].
    var playerBreakdown: [PowerContribution] = []
    var cpuBreakdown: [PowerContribution] = []
    var playerFinalPower: Int = 0
    var cpuFinalPower: Int = 0
    var result: BattleResult?
    var isActive: Bool = false
    var isRevealed: Bool = false
    var playerTransformedToHotDog: Bool = false   // active hero treated as Power 0 token
    var cpuTransformedToHotDog: Bool = false
}

// ════════════════════════════════════════════════════════════════
// MARK: - PracticeStore
// ════════════════════════════════════════════════════════════════

@Observable
@MainActor
final class PracticeStore {

    // MARK: - Setup State
    var mode: PracticeMode = .rookie
    var playerDeckSource: DeckSource = .random
    var cpuDeckSource: DeckSource = .random

    enum DeckSource {
        case template(DeckTemplate)
        case random
        case saved(UUID)

        static func == (lhs: DeckSource, rhs: DeckSource) -> Bool {
            switch (lhs, rhs) {
            case (.random, .random): return true
            case (.template(let a), .template(let b)): return a.id == b.id
            case (.saved(let a), .saved(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Match State
    var battles: [BattleSlot] = []
    var currentBattle: Int = 0          // 0-indexed
    var phase: BattlePhase = .reveal
    var playerScore: Int = 0
    var cpuScore: Int = 0
    var honors: Honors = .player        // who acts first each phase

    enum Honors: String, Codable { case player, cpu }

    // MARK: - Player Resources
    var playerHeroDeck: [Card] = []     // shuffled, remaining
    var playerBench: [Card] = []        // 4 bench cards per rules (§4.2.1, §4.3.1)
    var playerHeroDiscard: [Card] = []  // displaced heroes go here (subs, swaps, etc.)
    var playerHand: [Card] = []         // play cards in hand (4 starting, draw 1/battle)
    var playerPlayDeck: [Card] = []     // remaining play cards
    var playerPlayDiscard: [Card] = []  // played/discarded play cards
    var playerHotDogs: Int = 10
    var playerHotDogDiscard: Int = 0

    // MARK: - CPU Resources
    var cpuHeroDeck: [Card] = []
    var cpuBench: [Card] = []
    var cpuHeroDiscard: [Card] = []
    var cpuHand: [Card] = []
    var cpuHotDogs: Int = 10
    var cpuPlaysRemaining: Int = 30

    // MARK: - Cached card pool (for Play Again)
    var allCardsPool: [Card] = []

    // MARK: - Phase-level state
    var playerSubstituted: Bool = false
    var cpuSubstituted: Bool = false
    /// `protect_self` flags. When set, opponent's play deltas to this
    /// side's hero clamp to ≥ 0 — Immunity, Indestructible, Showtime's
    /// Elbow Guard. Reset each battle. Persistent triggers from
    /// earlier battles bypass protection (the rule text is "can't be
    /// affected by opponent's PLAYS," not "can't be affected by any
    /// effect ever").
    var playerProtectedThisBattle: Bool = false
    var cpuProtectedThisBattle: Bool = false
    /// Soft cap on opp plays this battle (Restricted List). nil =
    /// uncapped. Counter is checked + decremented in cpuDoPlay /
    /// playerPlayCard before each play. Reset in moveToNextBattle.
    var playerPlayCapThisBattle: Int? = nil
    var cpuPlayCapThisBattle: Int? = nil
    var playerPassedPlays: Bool = false
    var cpuPassedPlays: Bool = false

    // MARK: - CPU Action Log (for UI callouts)
    struct ActionCallout: Identifiable {
        let id = UUID()
        let message: String
        let icon: String      // SF Symbol name
        let color: String     // hex color
        var card: Card? = nil // the play card (for CPU play display)
        var playerDelta: Int = 0
        var cpuDelta: Int = 0
        // Dice / coin results produced by this play's executor. Held
        // here (rather than fired immediately when the executor runs)
        // so the reveal overlay can play AFTER the user has seen the
        // CPU play overlay — i.e., timed to the card that triggered
        // the roll instead of bursting at the start of the play phase.
        var coinFlips: [Bool] = []
        var diceRolls: [Int] = []
        /// Carry-through for executor revealMode/revealLabel so the
        /// host can build a properly-tagged RevealState at dismiss.
        var revealMode: String = "single"
        var revealLabel: String = ""
    }
    var cpuCallouts: [ActionCallout] = []
    var lastEffectCallout: ActionCallout? = nil  // coin flip / dice result

    // MARK: - Setup honors roll
    //
    // Per BoBA setup procedure each player rolls one d6 — high roll
    // wins Honors for Battle 1 (re-roll on tie). Practice surfaces
    // the roll in a dedicated overlay so newcomers see the procedure
    // play out rather than honors being assigned silently.
    struct SetupHonorsRoll: Identifiable {
        let id = UUID()
        let playerRoll: Int       // single d6 face
        let cpuRoll: Int
        let winner: Honors
    }
    var pendingSetupHonors: SetupHonorsRoll? = nil

    // MARK: - Animated dice / coin reveal
    //
    // Populated when a played card rolls dice or flips coins. The
    // PracticeView watches `pendingReveal` and renders a spinning
    // coin / tumbling dice overlay for ~1s before clearing it and
    // letting the rest of the effect cascade (callouts, deltas).
    // `side` tracks who played the card so the overlay can tint
    // correctly (cyan for player, purple for CPU).
    enum RevealKind: String, Codable { case single, versus, summed, gate }
    struct RevealState: Identifiable {
        let id = UUID()
        let side: PlayExecContext.Side
        let coinFlips: [Bool]     // true = HEADS
        let diceRolls: [Int]      // 1…6
        var kind: RevealKind = .single
        /// When set, the overlay shows a contextual label
        /// (e.g. "Leave It To Chance gate", "Luck of the Draw").
        var sourceLabel: String = ""
    }
    var pendingReveal: RevealState? = nil

    // CPU play queue — shown one at a time, user dismisses each
    var cpuPlayQueue: [ActionCallout] = []
    var currentCpuPlay: ActionCallout? = nil

    // CPU sub callout — shown once, user dismisses
    var cpuSubCallout: ActionCallout? = nil

    // MARK: - Match completed?
    var matchOver: Bool = false
    var matchWinner: Honors?

    // MARK: - Persistent effects (play-effects.json `persistent[]`)
    final class PersistentEffect: Codable {
        let owner: PlayExecContext.Side
        let installedAt: Int   // battle index when installed
        /// Spec is [String: Any]; we carry it as JSON Data for Codable.
        let specData: Data
        /// Name of the play card that installed this persistent. Used
        /// to label trigger callouts and breakdown rows ("Baby Phoenix:
        /// +10" instead of bare "End-of-turn: +10"). Empty for child
        /// persistents installed by other persistents (those inherit
        /// the parent's source via the install path).
        var sourceCard: String = ""
        var spec: [String: Any] {
            (try? JSONSerialization.jsonObject(with: specData) as? [String: Any]) ?? [:]
        }
        /// Cumulative delta this persistent has applied to the CURRENT battle.
        /// Used to rewind by `cancel_persistent` without touching past battles.
        var appliedPlayerDelta: Int = 0
        var appliedCpuDelta: Int = 0
        var appliedAtBattle: Int = -1

        init(owner: PlayExecContext.Side, spec: [String: Any], installedAt: Int, sourceCard: String = "") {
            self.owner = owner
            self.installedAt = installedAt
            self.specData = (try? JSONSerialization.data(withJSONObject: spec)) ?? Data("{}".utf8)
            self.sourceCard = sourceCard
        }
    }
    var persistents: [PersistentEffect] = []

    // MARK: - Weapon transforms (B.1 persistent_weapon_transform)
    //
    // Parallel state to `persistents` — when a persistent's effect is a
    // `weapon_transform` op, we record it here instead of (or in addition
    // to) the PersistentEffect list, so every weapon read can consult a
    // simple flat array rather than re-walking the persistent specs.
    //
    // Precedence rule (matches audit §B.1): transforms apply in install
    // order — later installs win on overlapping heroes. Scope respects
    // the shared `isScopeActive` helper so transforms fall off the mat
    // the same way any other persistent does.
    struct WeaponTransform: Codable {
        let owner: PlayExecContext.Side
        let installedAt: Int
        let scope: String
        /// `all_heroes` | `self` | `opponent`
        let target: String
        /// When non-nil, only transforms heroes whose printed element
        /// matches. Absent means "transform everything the target clause
        /// covers, regardless of starting weapon."
        let from: String?
        let to: String
        /// Name of the play card that installed this transform.
        /// Lets the active-effects banner show "Only Steel · Steel
        /// transform" instead of just "Steel transform."
        var sourceCard: String = ""
    }
    var weaponTransforms: [WeaponTransform] = []

    // MARK: - Play-cost modifiers (from play_cost_delta op)
    struct CostMod: Codable {
        var delta: Int
        var scope: String     // "next_play_self" | "this_and_next"
        var installedAt: Int  // battle idx
    }
    var playerCostMods: [CostMod] = []
    var cpuCostMods: [CostMod] = []

    // MARK: - Block flags (from block_sub/plays/draw/hd_recover ops)
    struct BlockEntry: Codable { var kind: String; var scope: String; var installedAt: Int }
    var playerBlocks: [BlockEntry] = []
    var cpuBlocks: [BlockEntry] = []

    // MARK: - Honors / free-sub / sub-cost-transfer queues
    struct ScopedFlag: Codable { var scope: String; var installedAt: Int }
    var playerPendingHonors: ScopedFlag? = nil
    var cpuPendingHonors: ScopedFlag? = nil
    var playerFreeSub: ScopedFlag? = nil
    var cpuFreeSub: ScopedFlag? = nil
    /// When set, the next substitute cost for this side is paid by the OTHER side's HD.
    var playerSubCostTransferFrom: PlayExecContext.Side? = nil
    var cpuSubCostTransferFrom: PlayExecContext.Side? = nil

    // MARK: - Marked future battles (mark_future_battle op)
    /// `onReveal` holds a `[[String: Any]]` of effect steps. We serialize it as
    /// JSON `Data` so `MatchSnapshot` can encode it.
    struct MarkedBattle: Codable {
        var side: PlayExecContext.Side
        var battleIdx: Int
        var onRevealData: Data  // JSONSerialization-encoded [[String: Any]]
        var onReveal: [[String: Any]] {
            (try? JSONSerialization.jsonObject(with: onRevealData) as? [[String: Any]]) ?? []
        }
        init(side: PlayExecContext.Side, battleIdx: Int, onReveal: [[String: Any]]) {
            self.side = side
            self.battleIdx = battleIdx
            self.onRevealData = (try? JSONSerialization.data(withJSONObject: onReveal)) ?? Data("[]".utf8)
        }
    }
    var markedBattles: [MarkedBattle] = []

    // MARK: - Peeked info surfaced to UI
    var peekedCards: [ActionCallout] = []   // queued peek notifications
    var pendingPlayerNotes: [String] = []   // notes from last player play; folded into callout
    var cpuLastPlayNotes: [String] = []     // notes from most recent CPU play (consumed by play queue builder)

    /// Returns true if `side` has an active block of `kind` in scope right now.
    func isBlocked(_ side: PlayExecContext.Side, kind: String) -> Bool {
        let blocks = side == .player ? playerBlocks : cpuBlocks
        for b in blocks where b.kind == kind {
            if Self.isScopeActive(b.scope, installedAt: b.installedAt, at: currentBattle) { return true }
        }
        return false
    }

    private func purgeExpiredBlocks() {
        playerBlocks.removeAll { !Self.isScopeActive($0.scope, installedAt: $0.installedAt, at: currentBattle)
                                  && !Self.isScopeStillValidForFutureBattles($0.scope, installedAt: $0.installedAt, now: currentBattle) }
        cpuBlocks.removeAll    { !Self.isScopeActive($0.scope, installedAt: $0.installedAt, at: currentBattle)
                                  && !Self.isScopeStillValidForFutureBattles($0.scope, installedAt: $0.installedAt, now: currentBattle) }
    }

    // MARK: - Scope interpreter (shared by all persistent / block readers)
    //
    // Canonical vocabulary (matches Cowork's 2026-04-24 audit):
    //   rest_of_game            — always true
    //   this_battle             — battleIdx == installedAt
    //   next_battle             — battleIdx == installedAt + 1
    //   this_and_next           — battleIdx ∈ [installedAt, installedAt+1]
    //   next_2_battles          — battleIdx ∈ (installedAt, installedAt+2]
    //   next_N_battles  (any N) — battleIdx ∈ (installedAt, installedAt+N]  (N from spec["n"])
    //   battle_1 … battle_7     — battleIdx == (N − 1)
    //   battles_4_7             — battleIdx ∈ [3, 6]
    //   until_opp_wins          — rest_of_game minus any battle after the opponent
    //                             wins one (caller passes the actual flag; default true)
    //   current                 — alias for this_battle (legacy, should be fixed
    //                             in JSON by now but kept for safety)
    //   prev_battle             — retrospective scope, never active as a forward
    //                             effect; returns false so broken data stays silent
    //                             rather than silently-wrong.
    //
    /// Resolves any in-scope `dice_gate` persistent owned by the
    /// opponent of `actingSide`. Returns nil when no gate applies;
    /// returns (roll, passed) when one does. Implements the engine
    /// side of Leave It To Chance — opponent rolls, dice is shown,
    /// and the play either continues (passed) or is cancelled.
    struct PlayGateOutcome { let roll: Int; let passed: Bool }
    func checkPlayGate(actingSide: PlayExecContext.Side) -> PlayGateOutcome? {
        let opp: PlayExecContext.Side = actingSide == .player ? .cpu : .player
        for inst in persistents {
            guard inst.owner == opp else { continue }
            guard (inst.spec["trigger"] as? String) == "on_opp_play" else { continue }
            guard Self.isScopeActive(
                inst.spec["scope"] as? String,
                installedAt: inst.installedAt,
                at: currentBattle,
                spec: inst.spec
            ) else { continue }
            guard let effect = inst.spec["effect"] as? [String: Any],
                  (effect["op"] as? String) == "dice_gate"
            else { continue }
            let pass = (effect["pass_on"] as? [Int]) ?? [2, 3, 4, 5]
            let roll = Int.random(in: 1...6)
            return PlayGateOutcome(roll: roll, passed: pass.contains(roll))
        }
        return nil
    }

    // Unknown scopes return false — that's a "silent no-op" safety net for any
    // new scope authored in the JSON before the host learns to read it.
    static func isScopeActive(
        _ scope: String?,
        installedAt: Int,
        at battleIdx: Int,
        spec: [String: Any]? = nil
    ) -> Bool {
        guard let scope else { return false }
        switch scope {
        case "rest_of_game":   return true
        case "this_battle":    return battleIdx == installedAt
        case "current":        return battleIdx == installedAt            // legacy alias
        case "next_battle":    return battleIdx == installedAt + 1
        case "this_and_next":  return battleIdx >= installedAt && battleIdx <= installedAt + 1
        case "next_2_battles": return battleIdx > installedAt && battleIdx <= installedAt + 2
        case "battles_4_7":    return battleIdx >= 3 && battleIdx <= 6
        case "next_N_battles":
            let n = (spec?["n"] as? Int) ?? 1
            return battleIdx > installedAt && battleIdx <= installedAt + n
        case "prev_battle":    return false   // never active going forward
        default:
            // battle_1 … battle_7 literal
            if scope.hasPrefix("battle_"),
               let n = Int(scope.dropFirst("battle_".count)),
               n >= 1, n <= 7 {
                return battleIdx == (n - 1)
            }
            return false
        }
    }

    /// Block-reaper predicate. Returns true when a block should be KEPT even
    /// though it isn't active this battle — e.g. `rest_of_game` blocks always
    /// stay; `next_battle` stays until currentBattle passes installedAt+1.
    /// Used only by `purgeExpiredBlocks`.
    static func isScopeStillValidForFutureBattles(
        _ scope: String?,
        installedAt: Int,
        now: Int
    ) -> Bool {
        guard let scope else { return false }
        switch scope {
        case "rest_of_game":   return true
        case "this_battle":    return now <= installedAt
        case "current":        return now <= installedAt
        case "next_battle":    return now <= installedAt + 1
        case "this_and_next":  return now <= installedAt + 1
        case "next_2_battles": return now <= installedAt + 2
        case "battles_4_7":    return now <= 6
        default:
            if scope.hasPrefix("battle_"),
               let n = Int(scope.dropFirst("battle_".count)) {
                return now <= (n - 1)
            }
            return false
        }
    }

    /// Effective play cost for `card` on `side`. Pass `consume: true` only when
    /// actually playing the card — consumption removes single-use mods. Callers
    /// that just want to display or evaluate affordability should leave it false.
    func effectiveCost(for card: Card, side: PlayExecContext.Side, consume: Bool = false) -> Int {
        let nominal = card.playCost ?? 0
        let mods = side == .player ? playerCostMods : cpuCostMods
        var total = nominal
        var keep: [CostMod] = []
        for m in mods {
            if m.scope == "this_and_next" && currentBattle > m.installedAt + 1 { continue }
            total += m.delta
            if m.scope == "next_play_self" { continue }  // single-use
            keep.append(m)
        }
        if consume {
            if side == .player { playerCostMods = keep } else { cpuCostMods = keep }
        }
        return max(0, total)
    }

    /// Apply all intents (cost mods + hand/deck/discard mutations + Tier B/C effects)
    /// left on the PlayExecOut by the structured executor. Returns the list of
    /// notification strings collected from intents (for UI surfacing).
    @discardableResult
    fileprivate func applyIntents(_ out: PlayExecOut, actingSide: PlayExecContext.Side) -> [String] {
        var collected: [String] = []
        // Tier A: cost mods
        for inst in out.costModInstalls {
            let cm = CostMod(delta: inst.delta, scope: inst.scope, installedAt: currentBattle)
            if inst.target == .player { playerCostMods.append(cm) } else { cpuCostMods.append(cm) }
        }
        // Tier A: player-only hand/deck/discard manipulations
        if out.shuffleHandIntoDeck && actingSide == .player {
            playerPlayDeck.append(contentsOf: playerHand)
            playerHand = []
            playerPlayDeck.shuffle()
        }
        // protect_self → opponent's play deltas to this side clamp
        // to ≥ 0 for the rest of THIS battle. Reset in moveToNextBattle.
        if out.protectSelf {
            if actingSide == .player {
                playerProtectedThisBattle = true
            } else {
                cpuProtectedThisBattle = true
            }
        }
        if out.shuffleDiscardToDeckCount != 0 && actingSide == .player {
            let n = out.shuffleDiscardToDeckCount < 0
                ? playerPlayDiscard.count
                : min(out.shuffleDiscardToDeckCount, playerPlayDiscard.count)
            if n > 0 {
                let moved = Array(playerPlayDiscard.prefix(n))
                playerPlayDiscard.removeFirst(n)
                // Route heroes back to hero deck; plays to play deck
                for c in moved {
                    if c.cardType == "Hero" { playerHeroDeck.append(c) }
                    else { playerPlayDeck.append(c) }
                }
                playerPlayDeck.shuffle()
                playerHeroDeck.shuffle()
            }
        }
        if out.discardTopCount > 0 && actingSide == .player {
            let n = min(out.discardTopCount, playerPlayDeck.count)
            if n > 0 {
                let dropped = Array(playerPlayDeck.prefix(n))
                playerPlayDeck.removeFirst(n)
                playerPlayDiscard.append(contentsOf: dropped)
            }
        }
        // Wire `out.draws` (61 catalog cards use op:"draw" — every
        // one was a silent no-op before this consumer was added). For
        // CPU side the cpuHand pool is fluid and not mediated by a
        // separate deck, so we approximate by bumping cpuPlaysRemaining.
        if out.draws > 0 {
            if actingSide == .player {
                for _ in 0..<out.draws { drawPlayCard() }
            } else {
                cpuPlaysRemaining += out.draws
            }
        }
        // Wire `out.heroDraws` — draws from the side's hero deck to
        // bench. Power Pick and similar use this when bench refills
        // are part of the effect.
        if out.heroDraws > 0 {
            if actingSide == .player {
                for _ in 0..<out.heroDraws {
                    guard !playerHeroDeck.isEmpty else { break }
                    playerBench.append(playerHeroDeck.removeFirst())
                }
            } else {
                for _ in 0..<out.heroDraws {
                    guard !cpuHeroDeck.isEmpty else { break }
                    cpuBench.append(cpuHeroDeck.removeFirst())
                }
            }
        }
        if out.discardHandAll && actingSide == .player {
            // B.12 — kind: "hero" filters to heroes-from-hand only.
            // Heroes-in-hand currently live in playerHand alongside
            // plays — strip and discard those, leaving plays untouched.
            switch out.discardHandAllKind {
            case "hero":
                let heroes = playerHand.filter { $0.cardType == "Hero" }
                if !heroes.isEmpty {
                    playerPlayDiscard.append(contentsOf: heroes)
                    playerHand.removeAll { $0.cardType == "Hero" }
                }
            default:
                playerPlayDiscard.append(contentsOf: playerHand)
                playerHand = []
            }
        }
        if out.reclaimUsedPlayCount > 0 && actingSide == .player {
            let n = min(out.reclaimUsedPlayCount, playerPlayDiscard.count)
            if n > 0 {
                let reclaimed = Array(playerPlayDiscard.suffix(n))
                playerPlayDiscard.removeLast(n)
                playerHand.append(contentsOf: reclaimed)
            }
        }

        // Tier B/C: handle each explicit intent
        var intentCallouts: [ActionCallout] = []
        for intent in out.intents {
            applyIntent(intent, actingSide: actingSide, notifyInto: &intentCallouts)
        }
        for c in intentCallouts { collected.append(c.message) }

        // Surface notifications
        for msg in out.notifications { collected.append(msg) }
        return collected
    }

    /// Handle a single PlayIntent. Mutates store state and may append callouts.
    private func applyIntent(_ intent: PlayIntent, actingSide: PlayExecContext.Side, notifyInto callouts: inout [ActionCallout]) {
        switch intent {
        case .notify(let msg):
            callouts.append(ActionCallout(message: msg, icon: "sparkles", color: "00F5FF"))

        case .peekHeroDeck(let side, let count):
            let deck = side == .player ? playerHeroDeck : cpuHeroDeck
            let names = deck.prefix(count).map { $0.name }.joined(separator: ", ")
            if !names.isEmpty {
                let who = (side == actingSide) ? "Your next hero\(count == 1 ? "" : "es")" : "Opponent's next hero\(count == 1 ? "" : "es")"
                callouts.append(ActionCallout(
                    message: "\(who): \(names)",
                    icon: "eye",
                    color: "00F5FF"
                ))
            }

        case .swapActiveWithHand(let side):
            // Find strongest hero in the side's bench (closest proxy to "hero hand")
            var bench = side == .player ? playerBench : cpuBench
            guard !bench.isEmpty, battles.indices.contains(currentBattle) else { break }
            let bestIdx = bench.indices.max(by: { (bench[$0].power ?? 0) < (bench[$1].power ?? 0) })!
            let replacement = bench[bestIdx]
            bench.remove(at: bestIdx)
            let current: Card?
            if side == .player {
                current = battles[currentBattle].playerCard
                battles[currentBattle].playerCard = replacement
                if let current = current { bench.append(current) }
                playerBench = bench
            } else {
                current = battles[currentBattle].cpuCard
                battles[currentBattle].cpuCard = replacement
                if let current = current { bench.append(current) }
                cpuBench = bench
            }
            callouts.append(ActionCallout(
                message: "Swapped active hero → \(replacement.name)",
                icon: "arrow.triangle.2.circlepath",
                color: "8B00FF"
            ))

        case .swapActiveWithDiscard(let side, let weaponFilter):
            guard battles.indices.contains(currentBattle) else { break }
            // Heroes live in playerHeroDiscard / cpuHeroDiscard now;
            // play cards live in playerPlayDiscard. Don't Call It a
            // Comeback specifically pulls from the HERO pile.
            let pool: [Card]
            if side == .player {
                pool = playerHeroDiscard.filter {
                    $0.cardType == "Hero" && (weaponFilter == nil || $0.element == weaponFilter)
                }
            } else {
                pool = cpuHeroDiscard.filter {
                    $0.cardType == "Hero" && (weaponFilter == nil || $0.element == weaponFilter)
                }
            }
            guard !pool.isEmpty else {
                callouts.append(ActionCallout(
                    message: "No heroes in \(side == .player ? "your" : "CPU") discard pile",
                    icon: "questionmark.circle", color: "666680"
                ))
                break
            }
            // Player side: open a chooser sheet so the user picks
            // which hero to bring back. CPU auto-picks highest power.
            if side == .player {
                pendingHeroDiscardChoice = HeroDiscardChoice(
                    side: .player, weaponFilter: weaponFilter, pool: pool
                )
            } else {
                if let best = pool.max(by: { ($0.power ?? 0) < ($1.power ?? 0) }) {
                    let current = battles[currentBattle].cpuCard
                    battles[currentBattle].cpuCard = best
                    cpuHeroDiscard.removeAll { $0.id == best.id }
                    if let current = current { cpuHeroDiscard.append(current) }
                    callouts.append(ActionCallout(
                        message: "CPU swapped active → \(best.hero.isEmpty ? best.name : best.hero) (from discard)",
                        icon: "arrow.counterclockwise",
                        color: "8B00FF"
                    ))
                }
            }

        case .swapActiveWithFutureHero(let side):
            let nextIdx = currentBattle + 1
            guard battles.indices.contains(currentBattle),
                  battles.indices.contains(nextIdx) else { break }
            if side == .player {
                let a = battles[currentBattle].playerCard
                let b = battles[nextIdx].playerCard
                battles[currentBattle].playerCard = b
                battles[nextIdx].playerCard = a
            } else {
                let a = battles[currentBattle].cpuCard
                let b = battles[nextIdx].cpuCard
                battles[currentBattle].cpuCard = b
                battles[nextIdx].cpuCard = a
            }
            callouts.append(ActionCallout(
                message: "Swapped active with next battle's hero",
                icon: "arrow.left.arrow.right",
                color: "8B00FF"
            ))

        case .replaceActiveWithTopDeck(let side):
            guard battles.indices.contains(currentBattle) else { break }
            if side == .player {
                guard !playerHeroDeck.isEmpty else { break }
                let old = battles[currentBattle].playerCard
                battles[currentBattle].playerCard = playerHeroDeck.removeFirst()
                if let old = old { playerPlayDiscard.append(old) }
            } else {
                guard !cpuHeroDeck.isEmpty else { break }
                battles[currentBattle].cpuCard = cpuHeroDeck.removeFirst()
            }
            callouts.append(ActionCallout(
                message: "Replaced active hero from top of deck",
                icon: "rectangle.stack.fill.badge.person.crop",
                color: "8B00FF"
            ))

        case .replaceNextWithTopDeck(let side):
            let nextIdx = currentBattle + 1
            guard battles.indices.contains(nextIdx) else { break }
            if side == .player, !playerHeroDeck.isEmpty {
                battles[nextIdx].playerCard = playerHeroDeck.removeFirst()
            } else if side == .cpu, !cpuHeroDeck.isEmpty {
                battles[nextIdx].cpuCard = cpuHeroDeck.removeFirst()
            }

        case .replaceAllUnrevealedWithTopDeck(let side):
            let start = currentBattle + 1
            for i in start..<battles.count {
                if side == .player {
                    guard !playerHeroDeck.isEmpty else { break }
                    battles[i].playerCard = playerHeroDeck.removeFirst()
                } else {
                    guard !cpuHeroDeck.isEmpty else { break }
                    battles[i].cpuCard = cpuHeroDeck.removeFirst()
                }
            }

        case .replaceActiveFromHand(let side):
            // Used by cards that pair `discard_hero` + `replace_active_from_hand`
            // (e.g. Forced Retreat). Current active holds a card just drawn from
            // the hero deck by discard_hero's auto-refill; return it to the top
            // of the deck so deck size stays intact.
            guard battles.indices.contains(currentBattle) else { break }
            var bench = side == .player ? playerBench : cpuBench
            guard !bench.isEmpty else { break }
            let bestIdx = bench.indices.max(by: { (bench[$0].power ?? 0) < (bench[$1].power ?? 0) })!
            let replacement = bench[bestIdx]
            bench.remove(at: bestIdx)
            if side == .player {
                if let current = battles[currentBattle].playerCard { playerHeroDeck.insert(current, at: 0) }
                battles[currentBattle].playerCard = replacement
                playerBench = bench
            } else {
                if let current = battles[currentBattle].cpuCard { cpuHeroDeck.insert(current, at: 0) }
                battles[currentBattle].cpuCard = replacement
                cpuBench = bench
            }
            let who = side == .player ? "Your" : "Opponent's"
            callouts.append(ActionCallout(
                message: "\(who) active → \(replacement.name) (from bench)",
                icon: "arrow.triangle.swap",
                color: "00F5FF",
                card: replacement
            ))

        case .discardActiveHero(let side):
            guard battles.indices.contains(currentBattle) else { break }
            if side == .player {
                if let c = battles[currentBattle].playerCard { playerPlayDiscard.append(c) }
                // Replace with top of deck if available
                battles[currentBattle].playerCard = playerHeroDeck.isEmpty ? nil : playerHeroDeck.removeFirst()
            } else {
                battles[currentBattle].cpuCard = cpuHeroDeck.isEmpty ? nil : cpuHeroDeck.removeFirst()
            }

        case .discardHeroFromHand(let side):
            // "Hand" is bench for heroes
            if side == .player {
                if let idx = playerBench.indices.min(by: { (playerBench[$0].power ?? 0) < (playerBench[$1].power ?? 0) }) {
                    let c = playerBench.remove(at: idx)
                    playerPlayDiscard.append(c)
                }
            } else if !cpuBench.isEmpty {
                cpuBench.remove(at: 0)
            }

        case .discardRevealedHero, .discardRevealedPlay:
            break // visual only; no concrete state mutation

        case .transformActiveToHotDog(let side):
            guard battles.indices.contains(currentBattle) else { break }
            if side == .player {
                battles[currentBattle].playerTransformedToHotDog = true
                let cur = battles[currentBattle].playerCard?.power ?? 0
                battles[currentBattle].playerEffectPower -= cur
            } else {
                battles[currentBattle].cpuTransformedToHotDog = true
                let cur = battles[currentBattle].cpuCard?.power ?? 0
                battles[currentBattle].cpuEffectPower -= cur
            }

        case .capOpponentPlays(let side, _, let max):
            // Restricted List: soft cap that decrements per play.
            // Only this_battle scope is honored for now (the only
            // scope the catalog uses). next_battle would need a
            // pending-cap mechanism similar to honors install.
            if side == .player {
                playerPlayCapThisBattle = max
            } else {
                cpuPlayCapThisBattle = max
            }
            callouts.append(ActionCallout(
                message: "\(side == .player ? "You" : "CPU") capped at \(max) play\(max == 1 ? "" : "s") this battle",
                icon: "lock.fill", color: "FFD166"
            ))

        case .markFutureBattle(let side, let onReveal, let selector):
            // Player-pick selector → open a chooser sheet so the
            // coach selects which unrevealed Hero to mark (Delayed
            // Recovery's intent). Unknown / random selector → fall
            // back to a random pick.
            let unrevealed = (currentBattle + 1..<battles.count).filter { !battles[$0].isRevealed }
            guard !unrevealed.isEmpty else { break }
            if selector == "unrevealed_hero_player_pick" && side == .player {
                pendingFutureBattlePick = FutureBattlePick(
                    side: side,
                    onReveal: onReveal,
                    candidateBattleIndices: unrevealed
                )
            } else {
                guard let target = unrevealed.randomElement() else { break }
                markedBattles.append(MarkedBattle(side: side, battleIdx: target, onReveal: onReveal))
                callouts.append(ActionCallout(
                    message: "Marked Battle \(target + 1) — effect triggers on reveal",
                    icon: "flag.fill",
                    color: "FFD166"
                ))
            }

        case .forceSubstitute(let target, let cost):
            // Force `target` to sub on their next sub phase. Charge cost from target.
            if target == .player {
                playerHotDogs = max(0, playerHotDogs - cost)
            } else {
                cpuHotDogs = max(0, cpuHotDogs - cost)
            }
            // Swap target's active with best bench immediately (forced)
            applyIntent(.swapActiveWithHand(side: target), actingSide: actingSide, notifyInto: &callouts)

        case .mirrorPowerEffects:
            break // already applied as delta inline in executor

        case .flipOpponentDebuffs:
            break // already applied inline

        case .cancelPersistents(let target):
            // Rules-clarification (handoff §6.D): Pull The Plug only
            // cancels `rest_of_game` effects. Scope-limited effects
            // (next_battle, this_and_next, etc.) survive and continue
            // to tick down. We split persistents accordingly so the
            // post-fire callout can show the user exactly what was
            // hit and what stuck around.
            let inTargetGroup: (PersistentEffect) -> Bool = { p in
                switch target {
                case "self":     return p.owner == actingSide
                case "opponent": return p.owner != actingSide
                default:         return true
                }
            }
            let candidates = persistents.filter(inTargetGroup)
            let victims  = candidates.filter { ($0.spec["scope"] as? String) == "rest_of_game" }
            let survived = candidates.filter { ($0.spec["scope"] as? String) != "rest_of_game" }
            // Rewind their deltas that already hit the CURRENT battle
            if battles.indices.contains(currentBattle) {
                var slot = battles[currentBattle]
                for p in victims where p.appliedAtBattle == currentBattle {
                    slot.playerEffectPower -= p.appliedPlayerDelta
                    slot.cpuEffectPower    -= p.appliedCpuDelta
                }
                battles[currentBattle] = slot
            }
            // Remove ONLY the rest_of_game victims; survivors stay in
            // place to keep ticking down on their own schedule.
            let victimIds = Set(victims.map { ObjectIdentifier($0) })
            persistents.removeAll { victimIds.contains(ObjectIdentifier($0)) }
            // Also clean weapon transforms with rest_of_game scope
            // owned by the targeted side(s) — they're effectively
            // persistents too.
            let weaponVictims = weaponTransforms.filter { t in
                let sideMatch: Bool = {
                    switch target {
                    case "self":     return t.owner == actingSide
                    case "opponent": return t.owner != actingSide
                    default:         return true
                    }
                }()
                return sideMatch && t.scope == "rest_of_game"
            }
            weaponTransforms.removeAll { t in
                weaponVictims.contains(where: { $0.installedAt == t.installedAt && $0.to == t.to && $0.target == t.target })
            }
            // Build the user-facing summary — names of cancelled +
            // names of survived. Strict labels per the audit's "two-
            // column list" call-out (§6.D).
            let victimLabels: [String] = victims.compactMap { p in
                persistentSummaryLabel(spec: p.spec, owner: p.owner)
            } + weaponVictims.map { weaponTransformLabel(target: $0.target, from: $0.from, to: $0.to, scope: $0.scope) }
            let survivorLabels: [String] = survived.compactMap { p in
                persistentSummaryLabel(spec: p.spec, owner: p.owner)
            }
            if !victimLabels.isEmpty || !survivorLabels.isEmpty {
                var lines: [String] = []
                if !victimLabels.isEmpty {
                    lines.append("CANCELLED:\n  • " + victimLabels.joined(separator: "\n  • "))
                }
                if !survivorLabels.isEmpty {
                    lines.append("UNCHANGED (scope-limited):\n  • " + survivorLabels.joined(separator: "\n  • "))
                }
                callouts.append(ActionCallout(
                    message: lines.joined(separator: "\n\n"),
                    icon: "bolt.slash.fill",
                    color: "FF4D00"
                ))
            } else {
                callouts.append(ActionCallout(
                    message: "Pull The Plug — no rest-of-game effects to cancel.",
                    icon: "bolt.slash.fill",
                    color: "FF4D00"
                ))
            }

        case .peekOpponentHand(let side, let count, let mode):
            let pool: [Card] = side == .player ? cpuHand : playerHand
            let selected: [Card]
            if mode == "random" {
                selected = Array(pool.shuffled().prefix(count))
            } else {
                selected = Array(pool.prefix(count))
            }
            if !selected.isEmpty {
                if side == .player {
                    // Surface the actual cards in a dismissible sheet
                    // (Pre-Game Spy et al.). The 2s toast was too
                    // fleeting — coaches couldn't read more than one
                    // card name before it vanished.
                    pendingPeekedHand = PeekedHandReveal(
                        cards: selected,
                        sourceCard: lastResolvingPlayCard
                    )
                } else {
                    // CPU peeking the player's hand — keep the toast
                    // since there's no UI surface to dismiss for CPU.
                    let names = selected.map { $0.name }.joined(separator: ", ")
                    callouts.append(ActionCallout(
                        message: "Opponent's hand: \(names)",
                        icon: "eye",
                        color: "00F5FF"
                    ))
                }
            }

        case .searchPlaybook(let side, _, let action):
            // Play the best card available from the acting side's deck+hand+discard FREE
            guard side == .player else { break }
            let pool = playerPlayDeck + playerHand + playerPlayDiscard
            guard let best = pool
                .filter({ $0.cardType == "Play" })
                .max(by: { ($0.playCost ?? 0) < ($1.playCost ?? 0) }) else { break }
            if action == "play_free" {
                // Execute the found play card without cost
                if let entry = PlayEffects.entry(for: best.name) {
                    let ctx = makeExecContext(self_: side)
                    let innerOut = PlayEffectExecutor.run(entry: entry, ctx: ctx)
                    if innerOut.hasEffect, battles.indices.contains(currentBattle) {
                        if side == .player {
                            battles[currentBattle].playerEffectPower += innerOut.selfDelta
                            battles[currentBattle].cpuEffectPower += innerOut.oppDelta
                        } else {
                            battles[currentBattle].cpuEffectPower += innerOut.selfDelta
                            battles[currentBattle].playerEffectPower += innerOut.oppDelta
                        }
                    }
                }
                callouts.append(ActionCallout(
                    message: "Played \(best.name) free (Playbook search)",
                    icon: "magnifyingglass",
                    color: "00F5FF"
                ))
            }

        case .copyLastPlay(let side):
            // Find last play cast by this side in this or a previous battle
            var lastPlay: Card? = nil
            for i in stride(from: currentBattle, through: 0, by: -1) where battles.indices.contains(i) {
                let plays = side == .player ? battles[i].playerPlayedCards : battles[i].cpuPlayedCards
                if let p = plays.last { lastPlay = p; break }
            }
            guard let last = lastPlay else { break }
            if let entry = PlayEffects.entry(for: last.name) {
                let ctx = makeExecContext(self_: side)
                let innerOut = PlayEffectExecutor.run(entry: entry, ctx: ctx)
                if innerOut.hasEffect, battles.indices.contains(currentBattle) {
                    if side == .player {
                        battles[currentBattle].playerEffectPower += innerOut.selfDelta
                        battles[currentBattle].cpuEffectPower += innerOut.oppDelta
                    } else {
                        battles[currentBattle].cpuEffectPower += innerOut.selfDelta
                        battles[currentBattle].playerEffectPower += innerOut.oppDelta
                    }
                }
            }
            callouts.append(ActionCallout(
                message: "Copied \(last.name)",
                icon: "doc.on.doc.fill",
                color: "00F5FF"
            ))

        case .taxPerHeroInHand(let target, let perHDCost, let fallbackDiscards):
            let bench = target == .player ? playerBench : cpuBench
            let heroCount = bench.count
            let totalCost = abs(perHDCost) * heroCount
            let targetHD = target == .player ? playerHotDogs : cpuHotDogs
            if targetHD >= totalCost {
                if target == .player { playerHotDogs -= totalCost } else { cpuHotDogs -= totalCost }
                callouts.append(ActionCallout(
                    message: "Tax: -\(totalCost) HD (\(heroCount) heroes × \(abs(perHDCost)))",
                    icon: "dollarsign.circle.fill",
                    color: "FF4D00"
                ))
            } else {
                // Fallback: discard heroes
                if target == .player {
                    let n = min(fallbackDiscards, playerBench.count)
                    for _ in 0..<n { playerPlayDiscard.append(playerBench.removeLast()) }
                } else if target == .cpu {
                    let n = min(fallbackDiscards, cpuBench.count)
                    for _ in 0..<n { cpuBench.removeLast() }
                }
            }

        case .transferSubCost(let target, _):
            // Next time `target` subs, opponent's HD pays. Record flag.
            if target == .player { playerSubCostTransferFrom = actingSide == .cpu ? .cpu : .cpu }
            else { cpuSubCostTransferFrom = actingSide == .player ? .player : .player }

        case .playRevealedFree, .playTopOfPlaybookFree:
            // For free plays of revealed cards: simulate by drawing + playing best-from-deck
            // as a zero-cost effect. Implemented as a simplified draw + best-of-1-power-delta.
            guard actingSide == .player else { break }
            let pool = playerPlayDeck.prefix(1)
            if let card = pool.first, let entry = PlayEffects.entry(for: card.name) {
                let ctx = makeExecContext(self_: actingSide)
                let innerOut = PlayEffectExecutor.run(entry: entry, ctx: ctx)
                if innerOut.hasEffect, battles.indices.contains(currentBattle) {
                    battles[currentBattle].playerEffectPower += innerOut.selfDelta
                    battles[currentBattle].cpuEffectPower += innerOut.oppDelta
                }
            }

        case .peekUnrevealedHero(let side, let selector):
            let deck = side == .player ? playerHeroDeck : cpuHeroDeck
            let targetIdx = (selector == "opponent_next_battle" || selector.contains("next")) ? currentBattle + 1 : currentBattle
            var name: String? = nil
            if battles.indices.contains(targetIdx) {
                name = side == .player ? battles[targetIdx].playerCard?.name : battles[targetIdx].cpuCard?.name
            }
            if name == nil { name = deck.first?.name }
            if let name = name {
                callouts.append(ActionCallout(
                    message: "Peeked unrevealed hero: \(name)",
                    icon: "eye",
                    color: "00F5FF"
                ))
            }

        case .reorderUnrevealedHeroes(let side):
            // Re-sort unrevealed hero slots by power desc for side
            let slots = (currentBattle + 1..<battles.count).filter { !battles[$0].isRevealed }
            var cards: [Card] = slots.compactMap { side == .player ? battles[$0].playerCard : battles[$0].cpuCard }
            cards.sort { ($0.power ?? 0) > ($1.power ?? 0) }
            for (i, idx) in slots.enumerated() {
                guard i < cards.count else { break }
                if side == .player { battles[idx].playerCard = cards[i] } else { battles[idx].cpuCard = cards[i] }
            }

        case .revealTopPlays(let side, let count, _):
            let pool = side == .player ? playerPlayDeck : []
            let names = pool.prefix(count).map { $0.name }.joined(separator: ", ")
            if !names.isEmpty {
                callouts.append(ActionCallout(
                    message: "Top plays: \(names)",
                    icon: "eye",
                    color: "00F5FF"
                ))
            }

        case .revealTopHeroes(let side, let count, _):
            let pool = side == .player ? playerHeroDeck : cpuHeroDeck
            let names = pool.prefix(count).map { $0.name }.joined(separator: ", ")
            if !names.isEmpty {
                callouts.append(ActionCallout(
                    message: "Top heroes: \(names)",
                    icon: "eye",
                    color: "00F5FF"
                ))
            }

        case .installPersistent(let owner, let spec):
            // Child installs (from `install_persistent` op fired
            // inside another persistent) inherit the parent's source
            // card name via `_inheritedInstallSource`. Set by the
            // firing path; cleared after applyIntents returns.
            installPersistent(owner: owner, spec: spec, sourceCard: _inheritedInstallSource)

        case .installBlock(let side, let kind, let scope):
            let entry = BlockEntry(kind: kind, scope: scope, installedAt: currentBattle)
            if side == .player { playerBlocks.append(entry) } else { cpuBlocks.append(entry) }

        case .installHonors(let side, let scope):
            let flag = ScopedFlag(scope: scope, installedAt: currentBattle)
            if side == .player { playerPendingHonors = flag } else { cpuPendingHonors = flag }

        case .installSubstituteFree(let side, let scope):
            let flag = ScopedFlag(scope: scope, installedAt: currentBattle)
            if side == .player { playerFreeSub = flag } else { cpuFreeSub = flag }

        case .nameAndDiscard(let target):
            // Auto-name: pick the highest-cost play in target's hand and discard it.
            if target == .player {
                guard !playerHand.isEmpty else {
                    callouts.append(ActionCallout(message: "Named a card — your hand is empty", icon: "questionmark.circle", color: "666680"))
                    break
                }
                let bestIdx = playerHand.indices.max(by: { (playerHand[$0].playCost ?? 0) < (playerHand[$1].playCost ?? 0) })!
                let named = playerHand.remove(at: bestIdx)
                playerPlayDiscard.append(named)
                callouts.append(ActionCallout(
                    message: "Named \(named.name) — you discarded it",
                    icon: "exclamationmark.triangle.fill",
                    color: "FF4D00"
                ))
            } else {
                guard !cpuHand.isEmpty else {
                    callouts.append(ActionCallout(message: "Named a card — opponent's hand is empty", icon: "questionmark.circle", color: "666680"))
                    break
                }
                let bestIdx = cpuHand.indices.max(by: { (cpuHand[$0].playCost ?? 0) < (cpuHand[$1].playCost ?? 0) })!
                let named = cpuHand.remove(at: bestIdx)
                callouts.append(ActionCallout(
                    message: "Named \(named.name) — opponent discarded it",
                    icon: "exclamationmark.triangle.fill",
                    color: "FF4D00"
                ))
            }

        case .endBattleByPower:
            // Trigger resolution immediately (best-effort — caller will still need to advance phase)
            phase = .resolution
            resolveCurrentBattle()

        case .chooseHandDiscard(let side, let count):
            // Player side: surface the chooser sheet via observable
            // state. CPU side: auto-pick the lowest-cost plays so
            // the card's downstream effects still apply mechanically.
            if side == .player {
                pendingHandDiscard = HandDiscardChoice(
                    count: min(count, playerHand.count)
                )
            } else {
                autoDiscardCpuHand(count: count, into: &callouts)
            }

        case .revealForConditionalFree(let side):
            // Scare Tactics — player picks a play to "reveal" from
            // their hand. CPU side just picks the highest-cost play
            // (gives the best chance of a free use next battle).
            if side == .player {
                guard !playerHand.isEmpty else { break }
                pendingScareReveal = ScareTacticsState(
                    pool: playerHand
                )
            } else {
                guard let pick = cpuHand.max(by: { ($0.playCost ?? 0) < ($1.playCost ?? 0) }) else { break }
                cpuRevealedScarePlay = pick
                callouts.append(ActionCallout(
                    message: "CPU revealed a play for Scare Tactics",
                    icon: "eye", color: "C77DFF"
                ))
            }

        case .presentPlayerChoice(let side, let prompt, let options, let cpuPick):
            // CPU side auto-picks. Player side queues a chooser
            // sheet via observable state. The chosen option's
            // `effects` are run through the executor at confirm.
            if side == .cpu {
                let pick = max(0, min(cpuPick, options.count - 1))
                runChoiceEffects(options[pick].effects, actingSide: .cpu, into: &callouts)
            } else {
                pendingPlayerChoice = PlayerChoiceState(
                    prompt: prompt,
                    options: options.enumerated().map { idx, opt in
                        PlayerChoiceState.Option(id: idx, label: opt.label, effects: opt.effects)
                    }
                )
            }

        case .autoDiscardHand(let side, let count):
            // Forced discard with no chooser — host picks the
            // lowest-cost plays as a sensible default. Used by cards
            // like Hungry Demands targeting the opponent, or any
            // discard op without `mode: "choice"`.
            if side == .player {
                let n = min(count, playerHand.count)
                let toDiscard = Array(playerHand.sorted { ($0.playCost ?? 0) < ($1.playCost ?? 0) }.prefix(n))
                for c in toDiscard {
                    if let idx = playerHand.firstIndex(of: c) {
                        playerHand.remove(at: idx)
                        playerPlayDiscard.append(c)
                    }
                }
                if n > 0 {
                    callouts.append(ActionCallout(
                        message: "Discarded \(n) play\(n == 1 ? "" : "s") from hand",
                        icon: "trash", color: "C0392B"
                    ))
                }
            } else {
                autoDiscardCpuHand(count: count, into: &callouts)
            }

        case .chooseTopAndKeepBest(let side, let kind, let count):
            // Real "reveal top N, keep best 1, discard rest" handler.
            // Auto-picks the best card since the chooser sheet for
            // top-of-deck picks isn't built. For plays: best = highest
            // cost; for heroes: best = highest power. CPU side has no
            // separate playbook deck, so it auto-picks from the hand
            // pool instead of moving cards anywhere.
            if kind == "play" {
                if side == .player {
                    let n = min(count, playerPlayDeck.count)
                    guard n > 0 else { break }
                    let topN = Array(playerPlayDeck.prefix(n))
                    playerPlayDeck.removeFirst(n)
                    let bestIdx = topN.enumerated().max(by: { ($0.element.playCost ?? 0) < ($1.element.playCost ?? 0) })?.offset ?? 0
                    let chosen = topN[bestIdx]
                    playerHand.append(chosen)
                    for (i, c) in topN.enumerated() where i != bestIdx {
                        playerPlayDiscard.append(c)
                    }
                    let costLabel = chosen.playCost.map { "\($0) HD" } ?? "?"
                    callouts.append(ActionCallout(
                        message: "Picked \(chosen.name) (\(costLabel)) — discarded \(n - 1) other\(n - 1 == 1 ? "" : "s")",
                        icon: "hand.tap", color: "00F5FF"
                    ))
                } else {
                    // CPU has no separate play deck — no-op visually,
                    // chosenPlayCost was already predicted at exec time
                    // from selfPlayDeck (which is empty for CPU, so
                    // CPU-side conditional reads default 0).
                    callouts.append(ActionCallout(
                        message: "CPU picked best play (no deck mutation)",
                        icon: "hand.tap", color: "8B00FF"
                    ))
                }
            } else if kind == "hero" {
                if side == .player {
                    let n = min(count, playerHeroDeck.count)
                    guard n > 0 else { break }
                    let topN = Array(playerHeroDeck.prefix(n))
                    playerHeroDeck.removeFirst(n)
                    let bestIdx = topN.enumerated().max(by: { ($0.element.power ?? 0) < ($1.element.power ?? 0) })?.offset ?? 0
                    let chosen = topN[bestIdx]
                    playerBench.append(chosen)
                    for (i, c) in topN.enumerated() where i != bestIdx {
                        playerHeroDiscard.append(c)
                    }
                    let powLabel = chosen.power.map { "\($0) pow" } ?? "?"
                    callouts.append(ActionCallout(
                        message: "Picked \(chosen.hero.isEmpty ? chosen.name : chosen.hero) (\(powLabel)) → bench",
                        icon: "hand.tap", color: "00F5FF"
                    ))
                } else if !cpuHeroDeck.isEmpty {
                    let n = min(count, cpuHeroDeck.count)
                    let topN = Array(cpuHeroDeck.prefix(n))
                    cpuHeroDeck.removeFirst(n)
                    let bestIdx = topN.enumerated().max(by: { ($0.element.power ?? 0) < ($1.element.power ?? 0) })?.offset ?? 0
                    let chosen = topN[bestIdx]
                    cpuBench.append(chosen)
                    for (i, c) in topN.enumerated() where i != bestIdx {
                        cpuHeroDiscard.append(c)
                    }
                    callouts.append(ActionCallout(
                        message: "CPU picked \(chosen.hero.isEmpty ? chosen.name : chosen.hero) → bench",
                        icon: "hand.tap", color: "8B00FF"
                    ))
                }
            }
        }
    }

    /// Shared CPU-hand auto-discard helper used by both intent
    /// branches above.
    private func autoDiscardCpuHand(count: Int, into callouts: inout [ActionCallout]) {
        let n = min(count, cpuHand.count)
        let toDiscard = Array(cpuHand.sorted { ($0.playCost ?? 0) < ($1.playCost ?? 0) }.prefix(n))
        for c in toDiscard {
            if let idx = cpuHand.firstIndex(of: c) {
                cpuHand.remove(at: idx)
            }
        }
        if n > 0 {
            callouts.append(ActionCallout(
                message: "CPU discarded \(n) play\(n == 1 ? "" : "s")",
                icon: "trash", color: "C0392B"
            ))
        }
    }

    // MARK: - Hand-discard chooser
    //
    // Damage on Discard, Trash Bandit, etc. ask the player to pick
    // N plays to throw away. `pendingHandDiscard` is set by the
    // executor's `chooseHandDiscard` intent; the practice view
    // presents a sheet bound to it.
    struct HandDiscardChoice: Identifiable {
        let id = UUID()
        let count: Int
    }
    var pendingHandDiscard: HandDiscardChoice? = nil

    /// Pre-Game Spy / peek_opponent_hand reveal. The card "shows"
    /// you N opponent plays — previously a 2-second toast, now a
    /// dismissible sheet so coaches actually see the cards.
    struct PeekedHandReveal: Identifiable {
        let id = UUID()
        let cards: [Card]
        /// Source card name for the sheet eyebrow ("PRE-GAME SPY").
        let sourceCard: String
    }
    var pendingPeekedHand: PeekedHandReveal? = nil

    func dismissPeekedHand() { pendingPeekedHand = nil }

    /// Delayed Recovery and other "choose one of your unrevealed
    /// Heroes" cards. Pop the chooser sheet, list the candidate
    /// battles' heroes, register the marked battle on confirm.
    struct FutureBattlePick: Identifiable {
        let id = UUID()
        let side: PlayExecContext.Side
        let onReveal: [[String: Any]]
        let candidateBattleIndices: [Int]
    }
    var pendingFutureBattlePick: FutureBattlePick? = nil

    func confirmFutureBattlePick(battleIdx: Int) {
        guard let pick = pendingFutureBattlePick,
              pick.candidateBattleIndices.contains(battleIdx) else {
            pendingFutureBattlePick = nil
            return
        }
        markedBattles.append(MarkedBattle(side: pick.side, battleIdx: battleIdx, onReveal: pick.onReveal))
        cpuCallouts.append(ActionCallout(
            message: "Marked Battle \(battleIdx + 1) — effect triggers on reveal",
            icon: "flag.fill",
            color: "FFD166"
        ))
        pendingFutureBattlePick = nil
    }

    func cancelFutureBattlePick() { pendingFutureBattlePick = nil }

    /// Name of the play card the engine is currently resolving. Set
    /// by the player/CPU play paths immediately before invoking
    /// applyIntents, cleared after. Used by peek/reveal sheets to
    /// label themselves with the source card name.
    private var lastResolvingPlayCard: String = ""

    /// Called by the chooser sheet when the user confirms their
    /// selection. Removes the chosen cards from hand into discard.
    func confirmHandDiscard(_ cards: [Card]) {
        for c in cards {
            if let idx = playerHand.firstIndex(of: c) {
                playerHand.remove(at: idx)
                playerPlayDiscard.append(c)
            }
        }
        pendingHandDiscard = nil
    }

    func cancelHandDiscard() {
        pendingHandDiscard = nil
    }

    // MARK: - Hero-discard chooser
    //
    // Don't Call It a Comeback (and other future swap-with-discard
    // plays) pull a hero from the displaced-hero pile back into the
    // active slot. Player picks one; CPU auto-selects.
    struct HeroDiscardChoice: Identifiable {
        let id = UUID()
        let side: PlayExecContext.Side
        let weaponFilter: String?
        let pool: [Card]
    }
    var pendingHeroDiscardChoice: HeroDiscardChoice? = nil

    /// Transient: source-card name to thread through the install
    /// pipeline when `installPersistent` is reached via the intent
    /// path (i.e. fired by another persistent's `install_persistent`
    /// op). Set by `firePersistentTriggers` before calling
    /// `applyIntents`, cleared after. Empty string disables.
    private var _inheritedInstallSource: String = ""

    // MARK: - Player choice (player_choice op)
    //
    // Generic chooser surface. When the executor emits a
    // `presentPlayerChoice` intent for the player side, we stash a
    // PlayerChoiceState here; the practice view watches for it and
    // presents PlayerChoiceSheet. On confirm, the chosen option's
    // effects are run through the executor as if they were inline.
    struct PlayerChoiceState: Identifiable {
        let id = UUID()
        let prompt: String
        let options: [Option]
        struct Option: Identifiable {
            let id: Int
            let label: String
            let effects: [[String: Any]]
        }
    }
    var pendingPlayerChoice: PlayerChoiceState? = nil

    // MARK: - Scare Tactics
    //
    // Player picks a play from their hand to "reveal." The card
    // stays in hand. Next battle, if the OPPONENT plays a card
    // whose cost ≥ the revealed card's cost, the player gets to
    // run the revealed card free. After that, the reveal clears.
    struct ScareTacticsState: Identifiable {
        let id = UUID()
        let pool: [Card]
    }
    var pendingScareReveal: ScareTacticsState? = nil
    /// Per-side: the play card revealed for Scare Tactics, kept
    /// until next battle resolves or the trigger fires.
    var playerRevealedScarePlay: Card? = nil
    var cpuRevealedScarePlay: Card? = nil
    /// The battle index at which Scare Tactics was activated (the
    /// reveal becomes eligible to fire in `installedAt + 1`).
    var playerScareRevealedAt: Int = -1

    // MARK: - Hero pulse (power-change visual feedback)
    //
    // Bumped each time a side's effect power changes — the hero
    // card on that side pulses (scale + glow) once per increment
    // so coaches see WHICH hero just got hit instead of having to
    // re-read the breakdown.
    var playerHeroPulse: Int = 0
    var cpuHeroPulse: Int = 0
    private func pulse(_ side: PlayExecContext.Side) {
        if side == .player { playerHeroPulse &+= 1 }
        else               { cpuHeroPulse &+= 1 }
    }

    func confirmScareReveal(_ card: Card) {
        playerRevealedScarePlay = card
        playerScareRevealedAt = currentBattle
        pendingScareReveal = nil
        cpuCallouts.append(ActionCallout(
            message: "Revealed \(card.name) — free next battle if CPU plays cost ≥ \(card.playCost ?? 0)",
            icon: "eye", color: "00F5FF",
            card: card
        ))
    }

    func cancelScareReveal() {
        pendingScareReveal = nil
    }

    /// Called from the CPU play path each time the CPU resolves
    /// a play. If the player has a revealed Scare Tactics card,
    /// we're in the eligibility window (install battle + 1), and
    /// the CPU's play cost meets or exceeds the revealed card's
    /// cost, the revealed play fires for free.
    private func maybeFireScareReveal(cpuPlayCost: Int) {
        guard let revealed = playerRevealedScarePlay else { return }
        guard currentBattle == playerScareRevealedAt + 1 else { return }
        let threshold = revealed.playCost ?? 0
        guard cpuPlayCost >= threshold else { return }
        guard let idx = playerHand.firstIndex(where: { $0.id == revealed.id }) else {
            // Card was discarded or otherwise gone — clear reveal.
            playerRevealedScarePlay = nil
            return
        }
        playerHand.remove(at: idx)
        battles[currentBattle].playerPlayedCards.append(revealed)
        playerPlayDiscard.append(revealed)
        // Run the revealed play's executor for free
        if let entry = PlayEffects.entry(for: revealed.name),
           let effects = entry["effects"] as? [[String: Any]], !effects.isEmpty {
            let ctx = makeExecContext(self_: .player)
            let out = PlayEffectExecutor.run(entry: entry, ctx: ctx)
            battles[currentBattle].playerEffectPower += out.selfDelta
            battles[currentBattle].cpuEffectPower    += out.oppDelta
            applyHDRecover(side: .player, amount: out.selfHDDelta)
            applyHDRecover(side: .cpu,    amount: out.oppHDDelta)
            if out.selfDelta != 0 {
                battles[currentBattle].playerBreakdown.append(
                    .init(label: "\(revealed.name) (Scare Tactics free)", delta: out.selfDelta))
            }
            if out.oppDelta != 0 {
                battles[currentBattle].cpuBreakdown.append(
                    .init(label: "\(revealed.name) (Scare Tactics free)", delta: out.oppDelta))
            }
        }
        cpuCallouts.append(ActionCallout(
            message: "Scare Tactics fired — \(revealed.name) ran free (CPU's cost \(cpuPlayCost) ≥ \(threshold))",
            icon: "wand.and.stars", color: "FFD700",
            card: revealed
        ))
        playerRevealedScarePlay = nil
    }

    /// Called by the chooser sheet when the user picks an option.
    /// Runs the option's effects through the player-side executor
    /// and applies the resulting deltas/intents.
    func confirmPlayerChoice(option: PlayerChoiceState.Option) {
        var followups: [ActionCallout] = []
        runChoiceEffects(option.effects, actingSide: .player, into: &followups)
        cpuCallouts.append(contentsOf: followups)
        pendingPlayerChoice = nil
    }

    func cancelPlayerChoice() {
        pendingPlayerChoice = nil
    }

    /// Runs a list of executor steps (the chosen option's effects)
    /// as if they were inline at the originating play card. Used by
    /// both the player confirm path and the CPU auto-pick path.
    private func runChoiceEffects(_ effects: [[String: Any]],
                                  actingSide: PlayExecContext.Side,
                                  into callouts: inout [ActionCallout]) {
        let ctx = makeExecContext(self_: actingSide)
        var out = PlayExecOut()
        for step in effects {
            PlayEffectExecutor.execStep(step, ctx: ctx, out: &out)
        }
        // Power deltas — feed back into the current battle slot
        // so a chosen +20 actually changes hero power.
        if battles.indices.contains(currentBattle) {
            if actingSide == .player {
                battles[currentBattle].playerEffectPower += out.selfDelta
                battles[currentBattle].cpuEffectPower    += out.oppDelta
                if out.selfDelta != 0 {
                    battles[currentBattle].playerBreakdown.append(.init(label: "Choice", delta: out.selfDelta))
                }
                if out.oppDelta != 0 {
                    battles[currentBattle].cpuBreakdown.append(.init(label: "Choice", delta: out.oppDelta))
                }
            } else {
                battles[currentBattle].cpuEffectPower    += out.selfDelta
                battles[currentBattle].playerEffectPower += out.oppDelta
            }
        }
        applyHDRecover(side: actingSide, amount: out.selfHDDelta)
        applyHDRecover(side: actingSide == .player ? .cpu : .player, amount: out.oppHDDelta)
        // Apply nested intents (could include further choices,
        // installs, discards, etc.).
        for intent in out.intents {
            applyIntent(intent, actingSide: actingSide, notifyInto: &callouts)
        }
        for msg in out.notifications {
            callouts.append(ActionCallout(message: msg, icon: "sparkles", color: "00F5FF"))
        }
    }

    /// Map executor's `out.revealMode` string into the typed
    /// RevealState.RevealKind. Defaults to .single for unknown
    /// values so future modes silently fall back to a sane render.
    private func revealKindFromMode(_ mode: String) -> RevealKind {
        switch mode {
        case "versus": return .versus
        case "summed": return .summed
        case "gate":   return .gate
        default:       return .single
        }
    }

    func confirmHeroDiscardSwap(_ chosen: Card) {
        guard battles.indices.contains(currentBattle) else { return }
        let current = battles[currentBattle].playerCard
        battles[currentBattle].playerCard = chosen
        playerHeroDiscard.removeAll { $0.id == chosen.id }
        if let current = current { playerHeroDiscard.append(current) }
        pendingHeroDiscardChoice = nil
    }

    func cancelHeroDiscardSwap() {
        pendingHeroDiscardChoice = nil
    }

    // MARK: - Computed

    var currentSlot: BattleSlot? {
        battles.indices.contains(currentBattle) ? battles[currentBattle] : nil
    }

    var playerHeroForCurrentBattle: Card? { currentSlot?.playerCard }
    var cpuHeroForCurrentBattle: Card? { currentSlot?.cpuCard }

    // MARK: - Setup / Start

    /// Resolved deck payload used when a side is set to a template or saved deck.
    struct ResolvedDeck {
        var heroes: [Card] = []
        var plays: [Card] = []
        var hotDogs: [Card] = []
    }

    /// Optional pre-resolved decks for each side. Views can pass these before calling
    /// `startMatch` (e.g. PracticeSetupView fetches saved decks from Supabase).
    var playerResolvedDeck: ResolvedDeck?
    var cpuResolvedDeck: ResolvedDeck?

    /// Custom-rules selection from the Game Mode tab. Drives
    /// format-aware random deck construction (power caps, deck
    /// size) and template padding/filtering. Defaults to the
    /// standard rules so existing call sites keep working.
    var customRules: PracticeCustomRules = PracticeCustomRules()

    /// Resolve a DeckSource to card arrays against the given catalog. Templates are loaded
    /// synchronously from the bundled JSON; .random and .saved return nil here — saved decks
    /// must be resolved asynchronously by the caller.
    static func resolveTemplateDeck(_ source: DeckSource, catalog: [Card]) -> ResolvedDeck? {
        guard case .template(let template) = source else { return nil }
        var byId: [String: Card] = [:]
        for c in catalog { byId[c.id] = c }
        var r = ResolvedDeck()
        for id in template.heroIds      { if let c = byId[id] { r.heroes.append(c) } }
        for id in template.playIds      { if let c = byId[id] { r.plays.append(c) } }
        for id in template.bonusPlayIds { if let c = byId[id] { r.plays.append(c) } }
        for id in template.hotDogIds    { if let c = byId[id] { r.hotDogs.append(c) } }
        return r
    }

    // ════════════════════════════════════════════════════════════
    // MARK: - Random deck builders (realistic-feel)
    // ════════════════════════════════════════════════════════════
    //
    // The original `randomHeroPool.shuffled().prefix(60)` produced
    // decks dominated by the long tail of low-power heroes (55-90).
    // Per the practice-battle UI handoff §11 ("Deck composition
    // triad" + "Bonus play ceiling" + "Substitution positioning")
    // and §10 (Spec/Limited/SPEC+ formats), a plausible competitive
    // deck has a defined power curve, balanced play categories,
    // and at most 6 bonus plays.
    //
    // These builders aim for that profile.

    /// Power cap for a given format — heroes above this value are
    /// not allowed. Returns nil for "no cap" formats.
    static func powerCap(for format: PracticeCustomRules.HeroFormat) -> Int? {
        switch format {
        case .standard: return nil
        case .spec:     return 160
        case .specPlus: return 200
        case .limited:  return nil
        }
    }

    /// Target hero deck size for a given format. The practice
    /// match only deals 11 heroes (7 battles + 4 bench) per side
    /// regardless, but the rest sit in the hero deck for
    /// `draw kind:hero` effects.
    static func heroDeckSize(for format: PracticeCustomRules.HeroFormat) -> Int {
        switch format {
        case .standard: return 60
        case .spec:     return 60
        case .specPlus: return 60   // simplification — full SPEC+ caps at 70
        case .limited:  return 40
        }
    }

    /// Builds a hero deck honoring format constraints:
    /// - Standard: 60 heroes, no power cap
    /// - SPEC: 60 heroes, max 160 power
    /// - SPEC+: 60 heroes, max 200 power
    /// - Limited: 40 heroes, no power cap
    /// All formats: realistic power-curve distribution + the
    /// 6-per-power-value rule + max 4 variations of one hero name.
    static func buildRandomHeroDeck(pool: [Card], format: PracticeCustomRules.HeroFormat = .standard) -> [Card] {
        let cap = powerCap(for: format)
        let target = heroDeckSize(for: format)
        let candidates = pool.filter {
            $0.cardType == "Hero"
            && ($0.power ?? 0) >= 55
            && !($0.imageFile ?? "").isEmpty
            && !((($0.treatment ?? "").lowercased()).contains("hot dog"))
            && (cap == nil || ($0.power ?? 0) <= (cap ?? Int.max))
        }
        guard !candidates.isEmpty else { return [] }

        // Tier targets scale with deck size: the high/mid/low
        // ratio (50/40/10) is the same regardless of format, so a
        // 40-card Limited deck still feels like a representative
        // mix.
        let highTarget = Int((Double(target) * 0.50).rounded())
        let midTarget  = Int((Double(target) * 0.90).rounded())   // cumulative
        let lowTarget  = target

        // The "high" cutoff stays at 135 even when the cap forces
        // most cards lower (SPEC etc.) — the tier system gracefully
        // degrades when the pool's max is below 135.
        let high = candidates.filter { ($0.power ?? 0) >= 135 }.shuffled()
        let mid  = candidates.filter { let p = $0.power ?? 0; return p >= 100 && p < 135 }.shuffled()
        let low  = candidates.filter { ($0.power ?? 0) < 100 }.shuffled()

        var deck: [Card] = []
        var deckIDs: Set<String> = []
        var byPower: [Int: Int] = [:]
        var byHero:  [String: Int] = [:]

        @discardableResult
        func tryAdd(_ card: Card, perPowerCap: Int = 6, perHeroCap: Int = 4) -> Bool {
            if deckIDs.contains(card.id) { return false }
            let p = card.power ?? 0
            let h = card.hero
            if (byPower[p] ?? 0) >= perPowerCap { return false }
            if !h.isEmpty, (byHero[h] ?? 0) >= perHeroCap { return false }
            deck.append(card)
            deckIDs.insert(card.id)
            byPower[p, default: 0] += 1
            if !h.isEmpty { byHero[h, default: 0] += 1 }
            return true
        }
        func fillFrom(_ source: [Card], targetCount: Int) {
            for card in source where deck.count < targetCount {
                tryAdd(card)
            }
        }

        fillFrom(high, targetCount: highTarget)
        fillFrom(mid,  targetCount: midTarget)
        fillFrom(low,  targetCount: lowTarget)

        // Backfill / relax-cap fallback so we always hit `target`.
        let backfill = (high + mid + low).shuffled()
        for card in backfill where deck.count < target { tryAdd(card) }
        for card in backfill where deck.count < target { tryAdd(card, perHeroCap: 6) }
        return deck
    }

    /// Filters an existing hero list to format constraints (drops
    /// any hero above the format's power cap), then pads up to the
    /// format's target size from `pool`. Used when a template or
    /// saved deck is loaded under a stricter format than it was
    /// designed for — incompatible heroes get silently filtered
    /// and the gap is filled with format-compliant picks.
    static func padHeroDeck(_ existing: [Card], pool: [Card], format: PracticeCustomRules.HeroFormat = .standard) -> [Card] {
        let cap = powerCap(for: format)
        let target = heroDeckSize(for: format)
        // Drop heroes that violate the format's power cap.
        var deck = existing.filter { cap == nil || ($0.power ?? 0) <= (cap ?? Int.max) }
        guard deck.count < target else { return Array(deck.prefix(target)) }
        var deckIDs: Set<String> = Set(deck.map(\.id))
        var byPower: [Int: Int] = [:]
        var byHero:  [String: Int] = [:]
        for c in deck {
            byPower[c.power ?? 0, default: 0] += 1
            if !c.hero.isEmpty { byHero[c.hero, default: 0] += 1 }
        }
        let candidates = pool.filter {
            $0.cardType == "Hero"
            && ($0.power ?? 0) >= 55
            && !($0.imageFile ?? "").isEmpty
            && !deckIDs.contains($0.id)
            && (cap == nil || ($0.power ?? 0) <= (cap ?? Int.max))
        }.shuffled()
        for card in candidates where deck.count < target {
            let p = card.power ?? 0
            if (byPower[p] ?? 0) >= 6 { continue }
            if !card.hero.isEmpty, (byHero[card.hero] ?? 0) >= 4 { continue }
            deck.append(card)
            deckIDs.insert(card.id)
            byPower[p, default: 0] += 1
            if !card.hero.isEmpty { byHero[card.hero, default: 0] += 1 }
        }
        return deck
    }

    /// Counts how many heroes in `existing` violate the format's
    /// power cap. Drives the "N heroes filtered to fit SPEC" badge
    /// in the deck tab.
    static func incompatibleHeroCount(_ existing: [Card], format: PracticeCustomRules.HeroFormat) -> Int {
        guard let cap = powerCap(for: format) else { return 0 }
        return existing.filter { ($0.power ?? 0) > cap }.count
    }

    /// Builds a 30-card playbook biased toward the deck-composition
    /// triad — HD recovery, card draw, buff plays — with the
    /// 6-bonus-play ceiling enforced. Categories are looked up
    /// from play-effects.json via `PlayEffects.entry(for:)`.
    /// Falls back to a clean shuffle if the categorized pool is
    /// thin in any bucket.
    static func buildRandomPlaybook(pool: [Card]) -> [Card] {
        guard !pool.isEmpty else { return [] }
        PlayEffects.loadIfNeeded()

        // Resolve each card's play-effects category. Cards with no
        // entry (very rare — auditor catches these) get "unknown."
        func categoryOf(_ c: Card) -> String {
            (PlayEffects.entry(for: c.name)?["category"] as? String) ?? "unknown"
        }

        // Bucket by triad role:
        //   recovery: economy + value (HD recovery, card draw)
        //   buffs:    tempo + conditional + persistent (power swings)
        //   utility:  utility (search / swap / reorder)
        //   denial:   disruption (debuffs, blocks, force-discards)
        // Bonus plays are handled separately under the 6-card cap.
        let regular = pool.filter { $0.isBonusPlay != true }
        let bonus   = pool.filter { $0.isBonusPlay == true }.shuffled()

        var byRole: [String: [Card]] = [:]
        for c in regular {
            switch categoryOf(c) {
            case "economy", "value":             byRole["recovery", default: []].append(c)
            case "tempo", "conditional", "persistent":
                                                 byRole["buffs",    default: []].append(c)
            case "utility":                      byRole["utility",  default: []].append(c)
            case "disruption":                   byRole["denial",   default: []].append(c)
            default:                             byRole["other",    default: []].append(c)
            }
        }
        // Shuffle each bucket
        for k in byRole.keys { byRole[k] = byRole[k]?.shuffled() }

        // Target: 8 recovery, 8 buffs, 4 utility, 4 denial,
        // up to 6 bonus = 30 total. Adjust if any bucket is thin.
        var deck: [Card] = []
        var deckIDs: Set<String> = []
        func draw(_ key: String, _ count: Int) {
            var taken = 0
            for c in byRole[key] ?? [] where taken < count {
                if !deckIDs.contains(c.id) {
                    deck.append(c); deckIDs.insert(c.id); taken += 1
                }
            }
        }
        draw("recovery", 8)
        draw("buffs",    8)
        draw("utility",  4)
        draw("denial",   4)
        // Bonus plays — capped at 6 per handoff guidance ("Never
        // more than 6 bonus plays — too many cards dilutes your
        // Playbook.").
        var bonusTaken = 0
        for c in bonus where bonusTaken < 6 && deck.count < 30 {
            if !deckIDs.contains(c.id) {
                deck.append(c); deckIDs.insert(c.id); bonusTaken += 1
            }
        }
        // Backfill any shortage from any role (still excludes
        // duplicate IDs).
        if deck.count < 30 {
            let backfill = regular.shuffled()
            for c in backfill where deck.count < 30 {
                if !deckIDs.contains(c.id) {
                    deck.append(c); deckIDs.insert(c.id)
                }
            }
        }
        return deck.shuffled()
    }

    func startMatch(allCards: [Card]) {
        Self.deleteSavedMatch()
        PlayEffects.loadIfNeeded()
        persistents = []
        weaponTransforms = []
        playerCostMods = []
        cpuCostMods = []
        playerBlocks = []
        cpuBlocks = []
        playerPendingHonors = nil
        cpuPendingHonors = nil
        playerFreeSub = nil
        cpuFreeSub = nil
        playerSubCostTransferFrom = nil
        cpuSubCostTransferFrom = nil
        markedBattles = []
        pendingPlayerNotes = []
        cpuLastPlayNotes = []
        peekedCards = []
        if !allCards.isEmpty { allCardsPool = allCards }
        let pool = allCardsPool

        // Auto-resolve templates (synchronous) if not already resolved; saved decks must be
        // pre-resolved by the view since Supabase fetch is async.
        if playerResolvedDeck == nil, case .template = playerDeckSource {
            playerResolvedDeck = Self.resolveTemplateDeck(playerDeckSource, catalog: pool)
        }
        if cpuResolvedDeck == nil, case .template = cpuDeckSource {
            cpuResolvedDeck = Self.resolveTemplateDeck(cpuDeckSource, catalog: pool)
        }

        // Random pools — used when a side is set to .random AND for
        // padding any incomplete saved/template deck. Built lazily
        // per side so each random side gets a fresh draw + the two
        // sides aren't mirror images of each other.
        let allPlays = pool.filter { $0.cardType == "Play" && !($0.imageFile ?? "").isEmpty }

        let format = customRules.heroFormat
        func buildSide(resolved: ResolvedDeck?) -> (heroes: [Card], plays: [Card]) {
            // Heroes: build a realistic, FORMAT-COMPLIANT mix.
            // Spec/SPEC+ enforce a power cap; Limited targets a 40-
            // card deck. Templates/saved decks are filtered to drop
            // any cap violations and padded back to target size
            // from the catalog so a deck always lands legal for the
            // active format.
            let sideHeroes: [Card]
            if let resolved, !resolved.heroes.isEmpty {
                sideHeroes = Self.padHeroDeck(resolved.heroes.shuffled(), pool: pool, format: format)
            } else {
                sideHeroes = Self.buildRandomHeroDeck(pool: pool, format: format)
            }
            // Plays: balanced 30-card playbook with the deck-
            // composition triad (HD recovery / draw plays / buff
            // plays) and the 6-bonus-play ceiling per handoff
            // guidance. Falls back to a clean shuffle when the
            // composition pass can't fill all slots.
            let sidePlays: [Card]
            if let resolved, !resolved.plays.isEmpty {
                sidePlays = resolved.plays.shuffled()
            } else {
                sidePlays = Self.buildRandomPlaybook(pool: allPlays)
            }
            return (sideHeroes, sidePlays)
        }

        let playerSide = buildSide(resolved: playerResolvedDeck)
        let cpuSide    = buildSide(resolved: cpuResolvedDeck)

        let playerPool = Array(playerSide.heroes.prefix(11))
        let cpuPool    = Array(cpuSide.heroes.prefix(11))

        // Set up battles
        battles = (0..<7).map { i in
            var slot = BattleSlot(id: i)
            slot.playerCard = i < playerPool.count ? playerPool[i] : nil
            slot.cpuCard    = i < cpuPool.count    ? cpuPool[i]    : nil
            return slot
        }

        // Bench (4 cards per rules)
        playerBench = mode.showBench ? Array(playerPool.dropFirst(7)) : []
        cpuBench    = mode.showBench ? Array(cpuPool.dropFirst(7))    : []

        // Remaining hero deck — simulate 60-card deck (60 - 11 dealt = 49 remaining)
        playerHeroDeck = Array(playerSide.heroes.dropFirst(11).prefix(49))
        cpuHeroDeck    = Array(cpuSide.heroes.dropFirst(11).prefix(49))

        // Play cards (4 starting hand per rules — §4.3.1 "Each Player draws four Plays")
        if mode.showPlays {
            playerHand       = Array(playerSide.plays.prefix(4))
            playerPlayDeck   = Array(playerSide.plays.dropFirst(4))
            playerPlayDiscard = []
            cpuHand          = Array(cpuSide.plays.prefix(4))
        } else {
            playerHand = []; playerPlayDeck = []; playerPlayDiscard = []
            cpuHand = []
        }

        // Reset scores and state
        playerScore = 0; cpuScore = 0
        playerHotDogs = 10; cpuHotDogs = 10
        cpuPlaysRemaining = 30
        // Clear every overlay/callout slot so a previous match's
        // modal state can't leak into the new one. Without this,
        // a `pendingReveal` from a prior CPU dice roll could leave
        // an invisible-tap-blocking layer over the playmat that
        // would prevent the user from interacting with the bench.
        pendingReveal = nil
        currentCpuPlay = nil
        cpuPlayQueue = []
        cpuCallouts = []
        cpuSubCallout = nil
        lastEffectCallout = nil
        peekedCards = []
        pendingRecycleCard = nil
        pendingRecycleVictimSummary = ""
        pendingHandDiscard = nil
        pendingHeroDiscardChoice = nil
        pendingPlayerChoice = nil
        pendingScareReveal = nil
        playerRevealedScarePlay = nil
        cpuRevealedScarePlay = nil
        playerScareRevealedAt = -1
        playerHeroDiscard = []
        cpuHeroDiscard = []
        // Roll 1d6 per side for Honors. High roll wins, ties re-roll.
        // Surfaces via `pendingSetupHonors` so the UI can play a
        // dedicated overlay before the first battle starts.
        var playerRoll = Int.random(in: 1...6)
        var cpuRoll    = Int.random(in: 1...6)
        while playerRoll == cpuRoll {
            playerRoll = Int.random(in: 1...6)
            cpuRoll    = Int.random(in: 1...6)
        }
        let winner: Honors = playerRoll > cpuRoll ? .player : .cpu
        honors = winner
        pendingSetupHonors = SetupHonorsRoll(
            playerRoll: playerRoll, cpuRoll: cpuRoll, winner: winner
        )
        currentBattle = 0
        // Per rules: Sub phase comes BEFORE reveal (§4.2.2, §4.3.2)
        // Rookie has no sub phase, starts at reveal
        phase = mode == .rookie ? .reveal : .sub
        matchOver = false
        matchWinner = nil
        playerSubstituted = false; cpuSubstituted = false
        playerPassedPlays = false; cpuPassedPlays = false

        battles[0].isActive = true
    }

    // MARK: - Phase Advance

    func advancePhase() {
        guard !matchOver else { return }
        cpuCallouts = []
        lastEffectCallout = nil
        cpuSubCallout = nil

        // Apply any remaining queued CPU play effects before advancing
        if let play = currentCpuPlay {
            battles[currentBattle].cpuEffectPower += play.cpuDelta
            battles[currentBattle].playerEffectPower += play.playerDelta
        }
        for play in cpuPlayQueue {
            battles[currentBattle].cpuEffectPower += play.cpuDelta
            battles[currentBattle].playerEffectPower += play.playerDelta
        }
        currentCpuPlay = nil
        cpuPlayQueue = []

        switch phase {
        case .sub:
            // Per rules (§4.2.2, §4.3.2): Substitution happens BEFORE reveal
            // CPU makes blind sub decision (can't see player's card)
            if !cpuSubstituted { cpuTakeSubstitutionTurn() }
            // Advance to reveal phase — cards not yet flipped
            phase = .reveal

        case .reveal:
            if !battles[currentBattle].isRevealed {
                // First press: flip both cards face-up
                battles[currentBattle].isRevealed = true
                applyContinuousPersistents()
                // Stay in reveal phase so user can see the cards before plays begin
                if mode == .rookie || mode == .substitution {
                    // Rookie/Substitution: no play phase, resolve immediately
                    resolveCurrentBattle()
                    if !matchOver { phase = .resolution }
                }
                // Playmaker: stay in .reveal — user presses again to enter play phase
            } else {
                // Second press (Playmaker only): cards already revealed, move to play phase
                // Per Comprehensive Rules Guide §4.3.2: honors player plays first.
                // Each player has only ONE opportunity per battle to run Plays.
                phase = .play
                playerPassedPlays = false
                cpuPassedPlays = false
                if honors == .cpu {
                    // CPU has honors — CPU plays first, then player reacts.
                    cpuPreparePlayTurn()
                }
                // Player has honors — wait for player to play or press END TURN.
            }

        case .play:
            phase = .resolution
            resolveCurrentBattle()

        case .resolution:
            // Chain cleanup (draw play cards) and the next-battle move
            // into one button press. The intermediate .cleanup pause
            // was purely a second tap with no additional information —
            // coaches already saw the resolution on the previous screen.
            drawPlayCard()
            cpuDrawPlayCard()
            moveToNextBattle()

        case .cleanup:
            // Kept for backwards compatibility with saved drafts that
            // may have been persisted mid-cleanup. Normal flow skips
            // straight through from .resolution to next battle.
            moveToNextBattle()

        case .matchOver:
            break
        }

        // Auto-save after each phase transition (but not if the match just ended)
        if matchOver {
            Self.deleteSavedMatch()
        } else {
            saveMatch()
        }
    }

    /// Dismiss current CPU play callout and show next in queue
    func dismissCpuPlay() {
        if let play = currentCpuPlay {
            // Apply the effect now as user sees it
            battles[currentBattle].cpuEffectPower += play.cpuDelta
            battles[currentBattle].playerEffectPower += play.playerDelta
            if play.cpuDelta != 0    { pulse(.cpu) }
            if play.playerDelta != 0 { pulse(.player) }
            // UX#3 — log itemized contributions. Use the callout's
            // card name when available; otherwise fall back to the
            // callout message ("CPU plays Combo Deal").
            let label = play.card?.name ?? play.message
            // Always log the CPU's played card so the breakdown
            // panel surfaces it as a tappable row, even when its
            // power delta is zero (Forced Substitution, blocks, etc.).
            battles[currentBattle].cpuBreakdown.append(
                .init(label: label, delta: play.cpuDelta))
            if play.playerDelta != 0 {
                battles[currentBattle].playerBreakdown.append(
                    .init(label: "\(label) (CPU played)", delta: play.playerDelta))
            }
            // Now that the user has acknowledged THIS specific CPU
            // play, surface its dice/coin reveal (if any). This is
            // the timing fix — previously every CPU roll fired during
            // the executor sweep at start-of-phase, before any of
            // the play overlays appeared.
            if !play.coinFlips.isEmpty || !play.diceRolls.isEmpty {
                pendingReveal = RevealState(
                    side: .cpu,
                    coinFlips: play.coinFlips,
                    diceRolls: play.diceRolls,
                    kind: revealKindFromMode(play.revealMode),
                    sourceLabel: play.revealLabel.isEmpty
                        ? (play.card?.name ?? "")
                        : play.revealLabel
                )
            }
        }
        if cpuPlayQueue.isEmpty {
            currentCpuPlay = nil
            cpuPassedPlays = true
            // If the player has already passed, both sides are done with the
            // play phase — resolve automatically. Without this, a player who
            // had honors would have to press END TURN a second time after
            // watching the CPU play out its cards.
            if playerPassedPlays && phase == .play {
                phase = .resolution
                resolveCurrentBattle()
                if matchOver { Self.deleteSavedMatch() } else { saveMatch() }
            }
        } else {
            currentCpuPlay = cpuPlayQueue.removeFirst()
        }
    }

    /// Dismiss CPU sub callout
    func dismissCpuSub() {
        cpuSubCallout = nil
    }

    /// Trigger CPU substitution decision (called when player starts sub phase interaction)
    func triggerCpuSub() {
        guard !cpuSubstituted else { return }
        cpuTakeSubstitutionTurn()
    }

    // MARK: - Substitution (Player)

    func playerSubstitute(benchIndex: Int) {
        guard phase == .sub,
              !playerSubstituted,
              !isBlocked(.player, kind: "block_sub"),
              benchIndex < playerBench.count else { return }

        // Sub cost is free if a free-sub flag is active or cost is being transferred to CPU
        let freeSub = playerFreeSub != nil
        let transferFrom = playerSubCostTransferFrom
        let cost = freeSub ? 0 : 2
        guard playerHotDogs >= cost || transferFrom != nil else { return }

        // Capture the displaced hero so it lands in the discard pile —
        // makes Don't Call It a Comeback / hero-discard inspector
        // possible. Per rules the swapped-out hero is discarded, not
        // returned to the bench.
        if let displaced = battles[currentBattle].playerCard {
            playerHeroDiscard.append(displaced)
        }
        battles[currentBattle].playerCard = playerBench[benchIndex]
        // Original hero goes to discard (removed from bench)
        playerBench.remove(at: benchIndex)

        if transferFrom == .cpu {
            cpuHotDogs = max(0, cpuHotDogs - cost)
            playerSubCostTransferFrom = nil
        } else {
            playerHotDogs -= cost
            playerHotDogDiscard += cost
        }
        if freeSub { playerFreeSub = nil }

        // Draw a new hero from hero deck to replace the bench slot
        // (per Comprehensive Rules Guide §4.2.2 / Glossary "Substitute").
        if let drawn = playerHeroDeck.first {
            playerHeroDeck.removeFirst()
            playerBench.append(drawn)
        } else {
            // Deck-empty case is exceptional in a normal 60-card match
            // but possible in Limited or after enough hero-draining
            // play cards. Surface a callout (via the shared callout
            // queue) so the user understands why the bench is shorter.
            cpuCallouts.append(ActionCallout(
                message: "Hero deck empty — bench can't refill",
                icon: "exclamationmark.triangle.fill",
                color: "FFD166"
            ))
        }

        playerSubstituted = true

        // Substitution completes the sub phase — advance automatically
        advancePhase()
    }

    // MARK: - Play Card (Player)

    /// Card the player tapped Play on but hasn't confirmed yet — non-nil
    /// while the Recycle warning is up. View binds an alert to this so
    /// the play happens only after explicit confirmation.
    var pendingRecycleCard: Card? = nil

    /// Friendly summary of rest_of_game effects (per-side) the user is
    /// about to risk losing. Cached when the warning fires so the alert
    /// can show the list without re-walking persistents.
    var pendingRecycleVictimSummary: String = ""

    func playerPlayCard(_ card: Card) {
        guard phase == .play, playerHand.contains(card) else { return }
        guard !isBlocked(.player, kind: "block_plays") else { return }
        // Soft cap (Restricted List et al). When set, the player can't
        // exceed N plays this battle.
        if let cap = playerPlayCapThisBattle,
           battles[currentBattle].playerPlayedCards.count >= cap {
            return
        }
        guard effectiveCost(for: card, side: .player) <= playerHotDogs else { return }
        guard PlayEffects.isPlayable(name: card.name, ctx: makeExecContext(self_: .player)) else { return }

        // Rules-clarification (handoff §6.A): Recycle / Reload pull
        // plays from the discard back into the playbook/hand. Per the
        // physical-game ruling, rest-of-game effects attached to those
        // plays end. Surface a confirm alert when the user is about to
        // play a recycler AND has rest-of-game effects in force.
        if pendingRecycleCard == nil, isRecyclePlay(card), playerHasRestOfGameEffects() {
            pendingRecycleVictimSummary = playerRestOfGameEffectSummary()
            pendingRecycleCard = card
            return
        }
        let cost = effectiveCost(for: card, side: .player, consume: true)

        lastEffectCallout = nil
        playerHand.removeFirst(where: { $0 == card })
        battles[currentBattle].playerPlayedCards.append(card)

        // Leave It To Chance gate — opponent's persistent forces a
        // dice roll AFTER cost is paid; on a miss the play's effects
        // are cancelled but the HD remains spent (per ability text).
        if let gate = checkPlayGate(actingSide: .player) {
            pendingReveal = RevealState(
                side: .player,
                coinFlips: [],
                diceRolls: [gate.roll],
                kind: .gate,
                sourceLabel: "Leave It To Chance"
            )
            // Surface the *card* in the callout — effectCalloutBanner
            // renders the cancelled play's image with a red ✕ stamp
            // so the user sees exactly which card got killed.
            lastEffectCallout = ActionCallout(
                message: gate.passed
                    ? "🎲 \(gate.roll) — \(card.name) plays through Leave It To Chance"
                    : "🎲 \(gate.roll) — \(card.name) cancelled by Leave It To Chance",
                icon: "dice.fill",
                color: gate.passed ? "4CAF50" : "C0392B",
                card: card
            )
            scheduleEffectDismiss()
            if !gate.passed {
                playerPlayDiscard.append(card)
                saveMatch()
                return
            }
        }

        let ability = (card.playAbility ?? "").lowercased()

        // Structured executor first; fall back to regex resolver if no entry or no mechanical effect
        var playerDelta = 0
        var cpuDelta = 0
        var structuredHandled = false
        let entryForPlayer = PlayEffects.entry(for: card.name)
        let hasPersistentBlock = (entryForPlayer?["persistent"] as? [[String: Any]])?.isEmpty == false
        let hasEffectsBlock    = (entryForPlayer?["effects"]    as? [[String: Any]])?.isEmpty == false
        if let entry = entryForPlayer, hasEffectsBlock || hasPersistentBlock {
            let ctx = makeExecContext(self_: .player)
            let out = PlayEffectExecutor.run(entry: entry, ctx: ctx)
            // Mark the card as structured-handled IF it has a JSON entry,
            // regardless of whether `out.hasEffect` is true. Two failure
            // modes the legacy regex resolver causes when this gate is
            // wrong:
            //   1. Condition-gated cards (To Fight Another Day, Turn
            //      the Tide, Comeback Time) correctly evaluate to
            //      false on Battle 1 → empty out → regex applies the
            //      bonus unconditionally.
            //   2. Persistent-only cards (Overcommited, Lose 1 To Win
            //      2 (Hopefully), etc.) have empty `effects` but a
            //      real `persistent` block. The regex parses the
            //      ability text ("Next battle, opponent gets -5") and
            //      misfires on the CURRENT battle.
            // Gate now triggers on EITHER effects[] or persistent[].
            structuredHandled = true
            playerDelta = out.selfDelta
            cpuDelta = out.oppDelta
            // protect_self: clamp opponent's negative-to-self delta.
            // Player playing → cpuDelta is delivered to CPU; if CPU
            // is protected this battle, clamp it.
            if cpuProtectedThisBattle, cpuDelta < 0 { cpuDelta = 0 }
            applyHDRecover(side: .player, amount: out.selfHDDelta)
            applyHDRecover(side: .cpu,    amount: out.oppHDDelta)
            if !out.coinFlips.isEmpty || !out.diceRolls.isEmpty {
                pendingReveal = RevealState(
                    side: .player,
                    coinFlips: out.coinFlips,
                    diceRolls: out.diceRolls,
                    kind: revealKindFromMode(out.revealMode),
                    sourceLabel: out.revealLabel.isEmpty ? card.name : out.revealLabel
                )
            }
            if out.hasPersistent, let persistent = entry["persistent"] as? [[String: Any]] {
                let ctxForCheck = makeExecContext(self_: .player)
                for p in persistent {
                    if let ifCond = p["if"] as? [String: Any] {
                        guard PlayEffectExecutor.evalCondition(ifCond, ctx: ctxForCheck) else { continue }
                    }
                    installPersistent(owner: .player, spec: p, sourceCard: card.name)
                }
            }
            lastResolvingPlayCard = card.name
            let notes = applyIntents(out, actingSide: .player)
            lastResolvingPlayCard = ""
            if !notes.isEmpty {
                pendingPlayerNotes = notes
            }
        }
        if !structuredHandled {
            // Reached only when a Play has no JSON entry — every card
            // in play-effects.json now has at least an effects[] or
            // persistent[] block, so this branch should never run for
            // catalog cards. The auditor's `catalog` check + the new
            // `unknown_trigger` check + 0-error gate keep the JSON
            // honest. If you see this in the console, an unmapped
            // play card slipped into the deck — surface a no-op
            // instead of falling back to the legacy regex resolver
            // (which was the source of multiple wrong-battle misfires
            // — Overcommited, Lose 1 To Win 2, etc.).
            print("⚠️ Play card has no JSON entry — skipping: \(card.name)")
        }

        battles[currentBattle].playerEffectPower += playerDelta
        battles[currentBattle].cpuEffectPower += cpuDelta
        if playerDelta != 0 { pulse(.player) }
        if cpuDelta != 0    { pulse(.cpu) }
        // UX#3 — record per-modifier breakdown so the Resolution
        // overlay can itemize the math instead of showing a single
        // +N total. Every played card gets a line item (even when
        // its power delta is 0) so coaches can review which cards
        // actually fired and tap through to their effect text.
        battles[currentBattle].playerBreakdown.append(
            .init(label: card.name, delta: playerDelta))
        if cpuDelta != 0 {
            battles[currentBattle].cpuBreakdown.append(
                .init(label: "\(card.name) (you played)", delta: cpuDelta))
        }

        // Handle shuffle/draw effects (legacy — still useful for cards where structured
        // path didn't produce draws)
        if !structuredHandled { resolveDrawEffects(ability: ability) }

        // Set effect callout for coin flips / dice rolls (auto-dismiss after delay)
        if ability.contains("flip a coin") {
            let result = playerDelta > 0 || cpuDelta < 0 ? "Success!" : "No effect"
            lastEffectCallout = ActionCallout(message: "Coin flip: \(result) (\(playerDelta > 0 ? "+\(playerDelta)" : "\(cpuDelta)"))", icon: "circle.fill", color: playerDelta > 0 ? "4CAF50" : "C0392B")
            scheduleEffectDismiss()
        } else if ability.contains("roll a di") {
            lastEffectCallout = ActionCallout(message: "Dice roll: \(playerDelta > 0 ? "+\(playerDelta)" : "\(cpuDelta)") Power", icon: "dice.fill", color: playerDelta > 0 ? "4CAF50" : "C0392B")
            scheduleEffectDismiss()
        } else if playerDelta != 0 || cpuDelta != 0 || !pendingPlayerNotes.isEmpty {
            // Show power change callout for all effects (and fold in intent notifications)
            var parts: [String] = []
            if playerDelta > 0 { parts.append("+\(playerDelta) to you") }
            if playerDelta < 0 { parts.append("\(playerDelta) to you") }
            if cpuDelta < 0 { parts.append("\(cpuDelta) to opponent") }
            if cpuDelta > 0 { parts.append("+\(cpuDelta) to opponent") }
            var msg = "\(card.name)"
            if !parts.isEmpty { msg += ": " + parts.joined(separator: ", ") }
            if !pendingPlayerNotes.isEmpty {
                msg += " · " + pendingPlayerNotes.joined(separator: " · ")
            }
            lastEffectCallout = ActionCallout(
                message: msg,
                icon: "sparkles",
                color: playerDelta > 0 ? "00F5FF" : "FF4D00"
            )
            scheduleEffectDismiss()
        }
        pendingPlayerNotes = []

        playerHotDogs -= cost
        playerPlayDiscard.append(card)
    }

    /// Handle play card effects that draw/shuffle cards
    private func resolveDrawEffects(ability: String) {
        // "Draw N Plays" / "draw N Play"
        if let match = ability.firstMatch(of: /draw (\d+) play/) {
            let count = Int(match.1) ?? 1
            for _ in 0..<count { drawPlayCard() }
        } else if ability.contains("draw a play") || ability.contains("draw 1 play") {
            drawPlayCard()
        }

        // "Shuffle all Plays in your hand back into your Playbook and draw 4 new Plays"
        // "Shuffle all your Plays in your hand back into your Playbook, then draw 4 new Plays"
        if ability.contains("shuffle") && ability.contains("play") && ability.contains("draw") {
            if ability.contains("back into your playbook") || ability.contains("back into their playbook") {
                // Return hand to deck and draw fresh
                playerPlayDeck.append(contentsOf: playerHand)
                playerHand = []
                playerPlayDeck.shuffle()
                // Draw 4 new plays (or whatever number is specified)
                let drawCount: Int
                if let match = ability.firstMatch(of: /draw (\d+)/) {
                    drawCount = Int(match.1) ?? 4
                } else {
                    drawCount = 4
                }
                for _ in 0..<drawCount { drawPlayCard() }
            }
        }

        // "Shuffle all Plays used in previous Battles back into your Playbook. Draw 2 Plays."
        if ability.contains("shuffle all plays used in previous") {
            playerPlayDeck.append(contentsOf: playerPlayDiscard)
            playerPlayDiscard = []
            playerPlayDeck.shuffle()
            if let match = ability.firstMatch(of: /draw (\d+)/) {
                let count = Int(match.1) ?? 2
                for _ in 0..<count { drawPlayCard() }
            }
        }

        // "Both Players Discard all the Plays in their hands and Draw 3 new Plays"
        if ability.contains("discard all") && ability.contains("plays in their hands") && ability.contains("draw 3") {
            playerPlayDiscard.append(contentsOf: playerHand)
            playerHand = []
            for _ in 0..<3 { drawPlayCard() }
        }

        // "Draw a Hero from your Hero Deck"
        if ability.contains("draw a hero") || ability.contains("draw 1 hero") {
            if let hero = playerHeroDeck.first {
                playerHeroDeck.removeFirst()
                playerBench.append(hero)
            }
        }

        // "Recover N Hot Dog(s)"
        if let match = ability.firstMatch(of: /recover (\d+) hot dog/) {
            let count = Int(match.1) ?? 1
            let recovered = min(count, playerHotDogDiscard)
            playerHotDogs += recovered
            playerHotDogDiscard -= recovered
        }
    }

    /// Auto-dismiss effect callout after a short delay
    private func scheduleEffectDismiss() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                lastEffectCallout = nil
            }
        }
    }

    func playerPassPlays() {
        guard phase == .play else { return }
        playerPassedPlays = true
        // If CPU hasn't had their turn yet (e.g., player had honors and is now
        // passing), CPU takes their turn now. Per rules §4.3.2, each player
        // has only one opportunity per battle to run Plays.
        if !cpuPassedPlays {
            cpuPreparePlayTurn()
        }
        if cpuPassedPlays {
            phase = .resolution
            resolveCurrentBattle()
            if matchOver { Self.deleteSavedMatch() } else { saveMatch() }
        }
    }

    // MARK: - CPU AI

    private func cpuTakeSubstitutionTurn() {
        cpuSubCallout = nil
        guard mode.showBench, !cpuSubstituted, !isBlocked(.cpu, kind: "block_sub"),
              !cpuBench.isEmpty else {
            cpuSubstituted = true; return
        }
        let freeSub = cpuFreeSub != nil
        let transferFrom = cpuSubCostTransferFrom
        let effectiveCost = freeSub ? 0 : 2
        guard cpuHotDogs >= effectiveCost || transferFrom != nil else {
            cpuSubstituted = true; return
        }
        let currentPower = battles[currentBattle].cpuCard?.power ?? 0

        // Find best bench card
        guard let bestIdx = cpuBench.indices.max(by: { (cpuBench[$0].power ?? 0) < (cpuBench[$1].power ?? 0) }) else {
            cpuSubstituted = true; return
        }
        let bestBenchPower = cpuBench[bestIdx].power ?? 0

        // Per rules (§4.2.2): Subs happen BEFORE reveal — CPU can't see player's card.
        // Blind decision: sub if bench has a significantly stronger hero (30+ power upgrade)
        // or if current hero is below average power (< 120) and bench has better
        let weakHero = currentPower < 120 && bestBenchPower > currentPower
        let bigUpgrade = bestBenchPower >= currentPower + 30

        if weakHero || bigUpgrade {
            let best = cpuBench[bestIdx]
            // Capture the hero being subbed OUT before we overwrite
            // it on the slot — we surface this in the callout so the
            // player can see what power level the CPU is dropping
            // and make a more informed read on whether to counter-sub
            // themselves. (Strict BoBA rules would hide this; for
            // practice we trade fidelity for teaching value.)
            let displaced = battles[currentBattle].cpuCard
            if let d = displaced { cpuHeroDiscard.append(d) }
            cpuBench.remove(at: bestIdx)
            battles[currentBattle].cpuCard = best
            // Per Comprehensive Rules Guide §4.2.2 / Glossary
            // "Substitute": after substituting, the side draws 1
            // Hero from their Hero Deck to refill the Hero Hand.
            // Was missing on iOS — CPU's bench permanently shrank
            // every sub. Web `cpuDoSub` always had this; restoring
            // platform parity here.
            if !cpuHeroDeck.isEmpty {
                cpuBench.append(cpuHeroDeck.removeFirst())
            }
            if transferFrom == .player {
                playerHotDogs = max(0, playerHotDogs - effectiveCost)
                cpuSubCostTransferFrom = nil
            } else {
                cpuHotDogs -= effectiveCost
            }
            if freeSub { cpuFreeSub = nil }

            // Sub happens before reveal — don't show the NEW hero
            // (still face-down). DO show the displaced one so the
            // player can read the swing.
            let displacedLabel: String = {
                guard let d = displaced else { return "their hero" }
                let nm = d.hero.isEmpty ? d.name : d.hero
                let pw = d.power.map { " (\($0) power)" } ?? ""
                return "\(nm)\(pw)"
            }()
            let costLine = freeSub ? "for free" : "for 2 Hot Dogs"
            let pendingCallout = ActionCallout(
                message: "CPU subbed out \(displacedLabel) \(costLine)",
                icon: "arrow.triangle.2.circlepath",
                color: "FF4D00",
                card: displaced
            )
            // Delay showing callout so it appears after the phase banner clears (~2.5s)
            // Only show if still in reveal phase and cards haven't been flipped yet
            let battleIdx = currentBattle
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                guard phase == .reveal, !battles[battleIdx].isRevealed else { return }
                cpuSubCallout = pendingCallout
            }
        }
        cpuSubstituted = true
    }

    /// Prepare CPU plays as a queue — effects applied one at a time as user dismisses each
    private func cpuPreparePlayTurn() {
        cpuPlayQueue = []
        currentCpuPlay = nil
        guard mode == .playmaker else {
            cpuPassedPlays = true; return
        }
        guard !isBlocked(.cpu, kind: "block_plays") else {
            cpuPassedPlays = true; return
        }

        var cardsPlayed = 0
        // Smart pacing — distribute the CPU's remaining plays across
        // the remaining battles instead of dumping them in early
        // rounds. Without this the CPU often emptied its playbook by
        // battle 3 and had nothing to answer with in battles 5–7.
        //
        // Heuristic per battle:
        // 1. Reserve at least 1 play per future battle (so even at
        //    battle 7 there's still ammo).
        // 2. Spend a fair share of what's left after the reservation.
        // 3. Push 1 extra play if this is a high-stakes battle
        //    (battle 7, or any battle where the CPU is one win away
        //    from losing the match).
        // 4. Pull back 1 play if HD reserves are critically low.
        let battlesPlayed   = currentBattle
        let battlesLeft     = max(1, 7 - battlesPlayed)        // includes current
        let futureBattles   = max(0, battlesLeft - 1)
        let reserveForLater = futureBattles                    // 1 play per future battle
        let availableForNow = max(0, cpuPlaysRemaining - reserveForLater)
        let fairShare       = max(1, availableForNow / battlesLeft)
        var maxPlays        = min(cpuPlaysRemaining, fairShare)
        // Stakes bump — if losing the match is one battle away OR
        // we're in the final battle, allow one more play.
        let cpuLosses = battles.prefix(currentBattle).filter { $0.result == .win }.count // player wins == cpu loss
        let mustWin   = cpuLosses >= 3 || currentBattle >= 6   // battle 7 (idx 6) or 3 losses already
        if mustWin { maxPlays = min(cpuPlaysRemaining, maxPlays + 1) }
        // HD-conservation pullback — if HD ≤ 2, drop the count by one
        // so the CPU still has fuel for substitutions next battle.
        if cpuHotDogs <= 2 && maxPlays > 1 { maxPlays -= 1 }
        // Floor / ceiling — never play more than 4 in a single battle
        // (avoids the dump-everything-on-turn-1 problem) and never
        // less than 0 (passing is fine).
        maxPlays = max(0, min(maxPlays, 4))

        var tempHotDogs = cpuHotDogs

        let cpuCtx = makeExecContext(self_: .cpu)
        // Restricted List soft cap (cap_opponent_plays.max). When set,
        // CPU's per-battle play count is bounded by it in addition to
        // the engine's natural maxPlays.
        if let cap = cpuPlayCapThisBattle {
            maxPlays = min(maxPlays, cap)
        }
        while cardsPlayed < maxPlays && cpuPlaysRemaining > 0 {
            let affordable = cpuHand.filter {
                effectiveCost(for: $0, side: .cpu) <= tempHotDogs &&
                PlayEffects.isPlayable(name: $0.name, ctx: cpuCtx)
            }
            guard let card = affordable.min(by: { effectiveCost(for: $0, side: .cpu) < effectiveCost(for: $1, side: .cpu) }) else { break }

            cpuHand.removeFirst(where: { $0 == card })
            battles[currentBattle].cpuPlayedCards.append(card)
            let cost = effectiveCost(for: card, side: .cpu, consume: true)

            // Leave It To Chance gate — same as the player path,
            // but here the GATE's owner is the player and the gated
            // actor is the CPU. On a miss the play's effects are
            // silently dropped (HD remains spent).
            if let gate = checkPlayGate(actingSide: .cpu) {
                tempHotDogs -= cost
                cpuHotDogs -= cost
                cpuPlaysRemaining -= 1
                cardsPlayed += 1
                cpuPlayQueue.append(ActionCallout(
                    message: gate.passed
                        ? "CPU rolled \(gate.roll) — \(card.name) plays through"
                        : "CPU rolled \(gate.roll) — \(card.name) cancelled by your Leave It To Chance",
                    icon: "dice.fill",
                    color: gate.passed ? "8B00FF" : "4CAF50",
                    card: card,
                    diceRolls: [gate.roll]
                ))
                if !gate.passed { continue }
            }

            // Structured executor first (CPU perspective); fall back to regex resolver
            var cpuDelta = 0
            var playerDelta = 0
            var structuredHandled = false
            // Per-card reveal data — captured here so the dice/coin
            // animation can play AFTER the user dismisses this card's
            // overlay, instead of bursting at start-of-phase.
            var capturedCoinFlips: [Bool] = []
            var capturedDiceRolls: [Int] = []
            var capturedRevealMode = "single"
            var capturedRevealLabel = ""
            let entryForCpu = PlayEffects.entry(for: card.name)
            let cpuHasPersistent = (entryForCpu?["persistent"] as? [[String: Any]])?.isEmpty == false
            let cpuHasEffects    = (entryForCpu?["effects"]    as? [[String: Any]])?.isEmpty == false
            if let entry = entryForCpu, cpuHasEffects || cpuHasPersistent {
                let ctx = makeExecContext(self_: .cpu)
                let out = PlayEffectExecutor.run(entry: entry, ctx: ctx)
                // Mark structured-handled regardless of out.hasEffect
                // — same reasoning as the player-side path. Gate must
                // also fire for persistent-only cards (no effects[])
                // or the regex resolver misfires on the current battle.
                structuredHandled = true
                cpuDelta = out.selfDelta
                playerDelta = out.oppDelta
                // protect_self mirror: CPU playing → playerDelta lands
                // on player; if player is protected this battle, clamp.
                if playerProtectedThisBattle, playerDelta < 0 { playerDelta = 0 }
                applyHDRecover(side: .cpu,    amount: out.selfHDDelta)
                applyHDRecover(side: .player, amount: out.oppHDDelta)
                capturedCoinFlips = out.coinFlips
                capturedDiceRolls = out.diceRolls
                capturedRevealMode = out.revealMode
                capturedRevealLabel = out.revealLabel
                if out.hasPersistent, let persistent = entry["persistent"] as? [[String: Any]] {
                    let ctxForCheck = makeExecContext(self_: .cpu)
                    for p in persistent {
                        if let ifCond = p["if"] as? [String: Any] {
                            guard PlayEffectExecutor.evalCondition(ifCond, ctx: ctxForCheck) else { continue }
                        }
                        installPersistent(owner: .cpu, spec: p, sourceCard: card.name)
                    }
                }
                lastResolvingPlayCard = card.name
                let notes = applyIntents(out, actingSide: .cpu)
                lastResolvingPlayCard = ""
                cpuLastPlayNotes = notes
            }
            if !structuredHandled {
                // Same dead-code guard as player path. CPU shouldn't
                // be drawing unmapped cards either; log + no-op.
                print("⚠️ CPU play card has no JSON entry — skipping: \(card.name)")
            }

            tempHotDogs -= cost
            cpuHotDogs -= cost
            cpuPlaysRemaining -= 1
            cardsPlayed += 1

            let desc = Self.effectDescription(for: card)
            let notes = cpuLastPlayNotes
            cpuLastPlayNotes = []
            let notesSuffix = notes.isEmpty ? "" : " · " + notes.joined(separator: " · ")
            cpuPlayQueue.append(ActionCallout(
                message: "CPU played \(card.name) (\(cost) HD) — \(desc)\(notesSuffix)",
                icon: "rectangle.stack",
                color: "8B00FF",
                card: card,
                playerDelta: playerDelta,
                cpuDelta: cpuDelta,
                coinFlips: capturedCoinFlips,
                diceRolls: capturedDiceRolls,
                revealMode: capturedRevealMode,
                revealLabel: capturedRevealLabel
            ))
            // Scare Tactics — fire the player's revealed play free
            // when the CPU's play cost meets the threshold. Runs
            // immediately so the breakdown shows the contribution
            // before the user dismisses the CPU's overlay.
            maybeFireScareReveal(cpuPlayCost: cost)
        }

        if cpuPlayQueue.isEmpty {
            cpuPassedPlays = true
        } else {
            // Show first play immediately
            currentCpuPlay = cpuPlayQueue.removeFirst()
        }
    }

    // MARK: - Recycle-warning helpers (§6.A rules clarification)

    /// True when the play has any op that pulls cards back from the
    /// discard pile into the active deck/hand. Recycle, Reload, and
    /// Return from the Depths all qualify.
    private func isRecyclePlay(_ card: Card) -> Bool {
        guard let entry = PlayEffects.entry(for: card.name),
              let effects = entry["effects"] as? [[String: Any]] else { return false }
        return effects.contains { step in
            let op = step["op"] as? String
            return op == "shuffle_from_discard_to_deck"
                || op == "reclaim_used_play"
        }
    }

    private func playerHasRestOfGameEffects() -> Bool {
        let persistentHit = persistents.contains { p in
            p.owner == .player && (p.spec["scope"] as? String) == "rest_of_game"
        }
        let weaponHit = weaponTransforms.contains { t in
            t.owner == .player && t.scope == "rest_of_game"
        }
        return persistentHit || weaponHit
    }

    private func playerRestOfGameEffectSummary() -> String {
        var labels: [String] = []
        for p in persistents where p.owner == .player && (p.spec["scope"] as? String) == "rest_of_game" {
            if let label = persistentSummaryLabel(spec: p.spec, owner: .player) {
                labels.append(label)
            }
        }
        for t in weaponTransforms where t.owner == .player && t.scope == "rest_of_game" {
            labels.append(weaponTransformLabel(target: t.target, from: t.from, to: t.to, scope: t.scope))
        }
        return labels.joined(separator: "\n• ")
    }

    /// Called by the view when the user confirms the Recycle warning.
    /// Clears the pending state and re-enters playerPlayCard, this
    /// time bypassing the confirmation gate.
    func confirmPendingRecycle() {
        guard let card = pendingRecycleCard else { return }
        pendingRecycleCard = nil
        pendingRecycleVictimSummary = ""
        playerPlayCard(card)
    }

    /// Called when the user backs out of the Recycle confirmation.
    func cancelPendingRecycle() {
        pendingRecycleCard = nil
        pendingRecycleVictimSummary = ""
    }

    private func drawPlayCard() {
        guard mode.showPlays else { return }
        guard !isBlocked(.player, kind: "block_draw") else { return }
        // UX#9 — auto-reshuffle when the playbook deck is empty.
        // Surface the reshuffle as a callout so the user sees it
        // happen rather than wondering where the new cards came from.
        if playerPlayDeck.isEmpty && !playerPlayDiscard.isEmpty {
            let count = playerPlayDiscard.count
            playerPlayDeck = playerPlayDiscard.shuffled()
            playerPlayDiscard = []
            cpuCallouts.append(ActionCallout(
                message: "Playbook reshuffled · \(count) cards back into deck",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                color: "00F5FF"
            ))
        }
        if let drawn = playerPlayDeck.first {
            playerPlayDeck.removeFirst()
            playerHand.append(drawn)
        }
    }

    private func cpuDrawPlayCard() {
        cpuPlaysRemaining = max(0, cpuPlaysRemaining - 1)
    }

    // MARK: - Resolution

    private func resolveCurrentBattle() {
        guard battles.indices.contains(currentBattle) else { return }

        // B.2 — fire on_plays_resolved persistents before we decide the
        // winner. Their power/hd deltas feed back into slot.*EffectPower
        // so conditional end-of-turn boosts (Steel Resolve, Baby Phoenix)
        // can actually sway the outcome of the battle they fire in.
        firePersistentTriggers(trigger: "on_plays_resolved")

        var slot = battles[currentBattle]

        // Transform-to-hot-dog: active hero's base power treated as 0
        let playerBase = slot.playerTransformedToHotDog ? 0 : (slot.playerCard?.power ?? 0)
        let cpuBase    = slot.cpuTransformedToHotDog    ? 0 : (slot.cpuCard?.power ?? 0)
        let playerPower = playerBase + slot.playerEffectPower
        let cpuPower    = cpuBase    + slot.cpuEffectPower

        slot.playerFinalPower = playerPower
        slot.cpuFinalPower    = cpuPower

        // B.8 check — Ultimatum Dog: `auto_lose_battle` intent forces the
        // zero-HD side to lose regardless of power. Checked here so it
        // supersedes the normal compare + the SUPER tiebreaker.
        if let forcedLoser = sideForcedToLoseForZeroHD() {
            if forcedLoser == .player {
                slot.result = .lose; cpuScore += 1; honors = .cpu
            } else {
                slot.result = .win; playerScore += 1; honors = .player
            }
            battles[currentBattle] = slot
            firePersistentTriggers(trigger: slot.result == .win ? "on_battle_win" : "on_battle_loss")
            checkMatchOver()
            return
        }

        if playerPower > cpuPower {
            slot.result = .win
            playerScore += 1
            honors = .player
        } else if cpuPower > playerPower {
            slot.result = .lose
            cpuScore += 1
            honors = .cpu
        } else {
            // Tie — SUPER weapon type wins ONLY in Playmaker mode (§4.3.2 Super Tie Breaker)
            // Rookie/Substitution: tied power = draw, no trophy (§4.1.2, §4.2.2)
            if mode == .playmaker {
                // Resolve weapon through the transform layer so `Only
                // Fire` + a SUPER-printed hero reads as FIRE here.
                let playerCtx = makeExecContext(self_: .player)
                let cpuCtx    = makeExecContext(self_: .cpu)
                let playerIsSuper = playerCtx.weapon(of: slot.playerCard, as: .player) == "SUPER"
                let cpuIsSuper    = cpuCtx.weapon(of: slot.cpuCard,       as: .cpu)    == "SUPER"
                if playerIsSuper && !cpuIsSuper {
                    slot.result = .win; playerScore += 1; honors = .player
                } else if cpuIsSuper && !playerIsSuper {
                    slot.result = .lose; cpuScore += 1; honors = .cpu
                } else {
                    slot.result = .tie
                }
            } else {
                slot.result = .tie
            }
        }

        battles[currentBattle] = slot

        // B.4 — battle resolution triggers. on_battle_win fires for the
        // winning side's persistents; on_battle_loss for the losing
        // side's. Ties skip both. Effects applied here can install
        // next-battle persistents, discard plays, recover HDs, etc.
        switch slot.result {
        case .win:
            firePersistentTriggers(trigger: "on_battle_win",  winner: .player)
            firePersistentTriggers(trigger: "on_battle_loss", winner: .player)
        case .lose:
            firePersistentTriggers(trigger: "on_battle_win",  winner: .cpu)
            firePersistentTriggers(trigger: "on_battle_loss", winner: .cpu)
        case .tie, .none:
            break
        }

        checkMatchOver()
    }

    // MARK: - Persistent-trigger firings (B.2, B.4, B.8)
    //
    // One dispatch point for every non-continuous trigger. Matches
    // persistents whose scope is active at this battle AND whose
    // `trigger` string equals the requested event. `winner` is used
    // for on_battle_win / on_battle_loss to filter to the right
    // owner; other triggers ignore it.
    private func firePersistentTriggers(trigger: String, winner: PlayExecContext.Side? = nil) {
        guard battles.indices.contains(currentBattle) else { return }
        var slot = battles[currentBattle]
        for inst in persistents {
            let persistentTrigger = inst.spec["trigger"] as? String
            guard persistentTrigger == trigger else { continue }
            let scope = inst.spec["scope"] as? String
            guard Self.isScopeActive(scope, installedAt: inst.installedAt,
                                     at: currentBattle, spec: inst.spec) else { continue }

            // on_battle_win / on_battle_loss filter to the right owner.
            if trigger == "on_battle_win", winner != nil, inst.owner != winner { continue }
            if trigger == "on_battle_loss", winner != nil, inst.owner == winner { continue }

            guard let eff = inst.spec["effect"] as? [String: Any] else { continue }
            let ctx = makeExecContext(self_: inst.owner)
            var out = PlayExecOut()
            PlayEffectExecutor.execStep(eff, ctx: ctx, out: &out)

            // Feed power deltas back into this battle's slot so
            // on_plays_resolved boosts can change the verdict.
            let playerDelta: Int
            let cpuDelta: Int
            if inst.owner == .player {
                playerDelta = out.selfDelta
                cpuDelta = out.oppDelta
            } else {
                cpuDelta = out.selfDelta
                playerDelta = out.oppDelta
            }
            slot.playerEffectPower += playerDelta
            slot.cpuEffectPower    += cpuDelta
            if playerDelta != 0 { pulse(.player) }
            if cpuDelta != 0    { pulse(.cpu) }
            inst.appliedAtBattle    = currentBattle
            inst.appliedPlayerDelta += playerDelta
            inst.appliedCpuDelta    += cpuDelta
            // Persistent effects can also produce HD changes (e.g.
            // Lunch Table's `hd_recover from:"discard" amount:2` at
            // battle_start). Without this pass, those HD deltas were
            // silently dropped because applyIntents only walks the
            // intents array, not the bare `selfHDDelta` / `oppHDDelta`
            // fields that hd_recover writes to.
            let ownerSide = inst.owner
            let oppSide: PlayExecContext.Side = ownerSide == .player ? .cpu : .player
            if out.selfHDDelta != 0 {
                applyHDRecover(side: ownerSide, amount: out.selfHDDelta)
            }
            if out.oppHDDelta != 0 {
                applyHDRecover(side: oppSide, amount: out.oppHDDelta)
            }
            // UX#3 — record itemized contribution for the Resolution
            // overlay. Label uses the trigger so coaches can see "End-
            // of-turn: Steel Resolve" rather than a bare delta.
            // Use the source card's name when known so the breakdown
            // reads "Baby Phoenix" / "2017 Cinderellas" instead of
            // generic "End-of-turn" / "Battle start" — the source name
            // is set when the persistent was installed.
            let triggerKind = trigger == "on_plays_resolved" ? "End-of-turn"
                              : trigger == "on_battle_win"    ? "Win"
                              : trigger == "on_battle_loss"   ? "Loss"
                              : trigger == "on_battle_start"  ? "Battle start"
                              : "Trigger"
            let triggerLabel = inst.sourceCard.isEmpty
                ? triggerKind
                : "\(inst.sourceCard) (\(triggerKind))"
            if playerDelta != 0 {
                slot.playerBreakdown.append(.init(label: triggerLabel, delta: playerDelta))
            }
            if cpuDelta != 0 {
                slot.cpuBreakdown.append(.init(label: triggerLabel, delta: cpuDelta))
            }

            // Thread the source card name through any child install
            // intent. Set before applyIntents, cleared after.
            _inheritedInstallSource = inst.sourceCard

            // Apply any structured intents (install next-battle
            // persistent, discard hand, recover HDs, etc.) exactly
            // like a normal play would.
            _ = applyIntents(out, actingSide: inst.owner)
            _inheritedInstallSource = ""

            // Surface trigger firings to the user — without this,
            // on_battle_win / on_plays_resolved / on_battle_start
            // boosts feel like the game changed numbers for no
            // reason. Compose a callout with whatever delta or note
            // applied so the player can connect cause to effect.
            var message = ""
            if playerDelta != 0 || cpuDelta != 0 {
                let recipientDelta = inst.owner == .player ? playerDelta : cpuDelta
                let oppDeltaToOwner = inst.owner == .player ? cpuDelta : playerDelta
                if recipientDelta != 0 {
                    message += "\(inst.owner == .player ? "Your" : "CPU") Hero \(recipientDelta > 0 ? "+\(recipientDelta)" : "\(recipientDelta)")"
                }
                if oppDeltaToOwner != 0 {
                    if !message.isEmpty { message += " · " }
                    message += "\(inst.owner == .player ? "CPU" : "Your") Hero \(oppDeltaToOwner > 0 ? "+\(oppDeltaToOwner)" : "\(oppDeltaToOwner)")"
                }
            }
            if !out.notifications.isEmpty {
                if !message.isEmpty { message += " — " }
                message += out.notifications.joined(separator: ", ")
            }
            if !message.isEmpty {
                let triggerKind = trigger == "on_battle_win"     ? "Win"
                                : trigger == "on_battle_loss"    ? "Loss"
                                : trigger == "on_plays_resolved" ? "End-of-turn"
                                : trigger == "on_battle_start"   ? "Battle start"
                                : "Trigger"
                let prefix = inst.sourceCard.isEmpty
                    ? triggerKind
                    : "\(inst.sourceCard) (\(triggerKind))"
                cpuCallouts.append(ActionCallout(
                    message: "\(prefix): \(message)",
                    icon: "bolt.fill",
                    color: "FFD166"
                ))
            }
        }
        battles[currentBattle] = slot
    }

    /// B.8 Ultimatum Dog: if an `auto_lose_battle` persistent is active
    /// with `target: "any_with_zero_hd"`, return the side (if any) that
    /// has zero HDs at end-of-turn. Both sides at zero → the owner's
    /// opponent is forced to lose (conservative reading).
    private func sideForcedToLoseForZeroHD() -> PlayExecContext.Side? {
        for inst in persistents {
            guard (inst.spec["trigger"] as? String) == "on_turn_end",
                  let eff = inst.spec["effect"] as? [String: Any],
                  (eff["op"] as? String) == "auto_lose_battle",
                  Self.isScopeActive(inst.spec["scope"] as? String,
                                     installedAt: inst.installedAt,
                                     at: currentBattle, spec: inst.spec)
            else { continue }
            let target = (eff["target"] as? String) ?? "any_with_zero_hd"
            guard target == "any_with_zero_hd" else { continue }
            let playerZero = playerHotDogs == 0
            let cpuZero    = cpuHotDogs    == 0
            if playerZero && !cpuZero { return .player }
            if cpuZero    && !playerZero { return .cpu }
            if playerZero && cpuZero {
                // Both zero — the opponent of the persistent's owner loses.
                return inst.owner == .player ? .cpu : .player
            }
        }
        return nil
    }

    private func checkMatchOver() {
        if playerScore >= 4 { matchOver = true; matchWinner = .player; phase = .matchOver }
        else if cpuScore >= 4 { matchOver = true; matchWinner = .cpu; phase = .matchOver }
        // 7 battles complete, no winner → Sudden Death (show match over)
        else if currentBattle == 6 && phase == .resolution && playerScore == cpuScore {
            matchOver = true; matchWinner = nil; phase = .matchOver
        }
    }

    private func moveToNextBattle() {
        battles[currentBattle].isActive = false
        // Scare Tactics window closes after the FOLLOWING battle
        // (installed at N → eligible during N+1 → expires when
        // moving N+1 → N+2). We compare currentBattle (N+1) to
        // playerScareRevealedAt + 1 (N+1).
        if playerRevealedScarePlay != nil
           && currentBattle >= playerScareRevealedAt + 1 {
            cpuCallouts.append(ActionCallout(
                message: "Scare Tactics window closed — no opp play met the threshold",
                icon: "eye.slash", color: "666680"
            ))
            playerRevealedScarePlay = nil
            playerScareRevealedAt = -1
        }
        cpuRevealedScarePlay = nil
        let next = currentBattle + 1
        if next >= 7 || matchOver {
            phase = .matchOver
            matchOver = true
            if playerScore > cpuScore { matchWinner = .player }
            else if cpuScore > playerScore { matchWinner = .cpu }
            return
        }
        currentBattle = next
        battles[currentBattle].isActive = true
        playerSubstituted = false; cpuSubstituted = false
        playerPassedPlays = false; cpuPassedPlays = false
        playerProtectedThisBattle = false
        cpuProtectedThisBattle = false
        playerPlayCapThisBattle = nil
        cpuPlayCapThisBattle = nil

        // Apply pending honors_set for this battle
        if let h = playerPendingHonors {
            honors = .player
            if h.scope == "next_battle" { playerPendingHonors = nil }
        } else if let h = cpuPendingHonors {
            honors = .cpu
            if h.scope == "next_battle" { cpuPendingHonors = nil }
        }
        // Purge expired blocks
        purgeExpiredBlocks()

        // B.9 — fire on_battle_start triggers for any persistent
        // whose scope matches this battle (e.g. Late Game Push reveals
        // its hd_recover at the start of Battle 7). Runs BEFORE the
        // marked_battle on_reveal pass so effects can layer.
        firePersistentTriggers(trigger: "on_battle_start")

        // Fire marked_battle on_reveal effects for this battle
        let fires = markedBattles.filter { $0.battleIdx == currentBattle }
        for mark in fires {
            let ctx = makeExecContext(self_: mark.side)
            var out = PlayExecOut()
            for s in mark.onReveal { PlayEffectExecutor.execStep(s, ctx: ctx, out: &out) }
            if out.hasEffect {
                if mark.side == .player {
                    battles[currentBattle].playerEffectPower += out.selfDelta
                    battles[currentBattle].cpuEffectPower    += out.oppDelta
                } else {
                    battles[currentBattle].cpuEffectPower    += out.selfDelta
                    battles[currentBattle].playerEffectPower += out.oppDelta
                }
                cpuCallouts.append(ActionCallout(
                    message: "Marked battle triggered",
                    icon: "flag.fill",
                    color: "FFD166"
                ))
            }
        }
        markedBattles.removeAll { $0.battleIdx == currentBattle }

        // Per rules: Sub phase comes before reveal for non-rookie
        phase = mode == .rookie ? .reveal : .sub
    }

    // MARK: - Structured effect context

    func makeExecContext(self_: PlayExecContext.Side) -> PlayExecContext {
        let slot = battles.indices.contains(currentBattle) ? battles[currentBattle] : BattleSlot(id: 0)
        let selfIsPlayer = self_ == .player
        let selfCard = selfIsPlayer ? slot.playerCard : slot.cpuCard
        let oppCard  = selfIsPlayer ? slot.cpuCard    : slot.playerCard
        let selfHD   = selfIsPlayer ? playerHotDogs   : cpuHotDogs
        let oppHD    = selfIsPlayer ? cpuHotDogs      : playerHotDogs
        let selfSub  = selfIsPlayer ? playerSubstituted : cpuSubstituted
        let selfHand = selfIsPlayer ? playerHand      : cpuHand
        let selfDiscard = selfIsPlayer ? playerPlayDiscard : []
        let selfHeroDeck = selfIsPlayer ? playerHeroDeck : cpuHeroDeck

        // Count completed battles by result from this side's perspective
        var won = 0, lost = 0, tied = 0
        for i in 0..<currentBattle where battles.indices.contains(i) {
            guard let r = battles[i].result else { continue }
            let isWon = (selfIsPlayer && r == .win) || (!selfIsPlayer && r == .lose)
            let isLost = (selfIsPlayer && r == .lose) || (!selfIsPlayer && r == .win)
            if isWon { won += 1 }
            else if isLost { lost += 1 }
            else if r == .tie { tied += 1 }
        }

        let playsUsed = selfIsPlayer ? slot.playerPlayedCards.count : slot.cpuPlayedCards.count

        // Snapshot in-scope weapon transforms into the context so every
        // condition eval reads through the same view. We pass dicts to
        // keep PlayEffects.swift free of PracticeStore types.
        let transformSnapshot: [[String: Any]] = weaponTransforms.compactMap { t in
            guard Self.isScopeActive(t.scope, installedAt: t.installedAt, at: currentBattle)
            else { return nil }
            var d: [String: Any] = [
                "owner":  t.owner == .player ? "player" : "cpu",
                "target": t.target,
                "to":     t.to,
            ]
            if let from = t.from, !from.isEmpty { d["from"] = from }
            return d
        }

        // Player's playbook draw pile — empty for CPU side (CPU has
        // a single fluid hand/pool with no separate draw deck).
        let selfPlayDeck: [Card] = selfIsPlayer ? playerPlayDeck : []

        return PlayExecContext(
            self_: self_,
            selfCard: selfCard, oppCard: oppCard,
            selfHD: selfHD, oppHD: oppHD,
            selfSubstituted: selfSub,
            selfHand: selfHand,
            selfDiscard: selfDiscard,
            selfHeroDeck: selfHeroDeck,
            selfPlayDeck: selfPlayDeck,
            selfWon: won, selfLost: lost, selfTied: tied,
            playsUsedThisBattle: playsUsed,
            battleIdx: currentBattle,
            battlesRemaining: 7 - currentBattle,
            honors: honors == .player ? "player" : "cpu",
            battles: battles,
            weaponTransforms: transformSnapshot
        )
    }

    /// Dry-run: compute the pending power delta that installed continuous/battle_start
    /// persistents will apply to an unrevealed future battle for the given side.
    /// Returns 0 for battles already revealed (the delta is already in playerEffectPower).
    func previewPersistentPower(for battleIdx: Int, side: PlayExecContext.Side) -> Int {
        guard battles.indices.contains(battleIdx) else { return 0 }
        if battles[battleIdx].isRevealed { return 0 }
        var total = 0
        for inst in persistents {
            let scope = inst.spec["scope"] as? String
            let trigger = inst.spec["trigger"] as? String
            guard trigger == "continuous" || trigger == "battle_start" else { continue }
            let inScope = Self.isScopeActive(scope, installedAt: inst.installedAt,
                                              at: battleIdx, spec: inst.spec)
            guard inScope, let eff = inst.spec["effect"] as? [String: Any] else { continue }
            // Evaluate the effect with a context rooted at the owner; translate to the asked side.
            var snapCtx = makeExecContext(self_: inst.owner)
            snapCtx.battleIdx = battleIdx
            snapCtx.selfCard = inst.owner == .player ? battles[battleIdx].playerCard : battles[battleIdx].cpuCard
            snapCtx.oppCard  = inst.owner == .player ? battles[battleIdx].cpuCard    : battles[battleIdx].playerCard
            var out = PlayExecOut()
            PlayEffectExecutor.execStep(eff, ctx: snapCtx, out: &out)
            guard out.hasEffect else { continue }
            // Translate owner's self/opp deltas to the asked side's perspective.
            if inst.owner == side { total += out.selfDelta }
            else                  { total += out.oppDelta }
        }
        return total
    }

    // MARK: - HD recover pipeline (B.5)
    //
    // Every positive HD change (recover) routes through this helper so
    // persistent modifier blocks can interpose: redirect first (swap
    // who the HDs go to), then cap (limit per-invocation amount), then
    // delta (add/subtract from the amount), then block (drop the whole
    // thing). A caller that passes `side: .cpu, amount: +3` may end up
    // applying `+4` to `.player` if a redirect + delta are both active.
    //
    // Negative amounts (spend) bypass the pipeline entirely — those
    // are deductions the player chose to make and the rules text
    // doesn't contemplate blocking them here.
    @discardableResult
    func applyHDRecover(side: PlayExecContext.Side, amount: Int) -> Int {
        if amount <= 0 {
            if side == .player { playerHotDogs = max(0, playerHotDogs + amount) }
            else               { cpuHotDogs    = max(0, cpuHotDogs    + amount) }
            return amount
        }
        var actualSide = side
        var actualAmount = amount

        // 1. Redirect
        for inst in persistents {
            guard let eff = inst.spec["effect"] as? [String: Any],
                  (eff["op"] as? String) == "redirect_hd_recover",
                  Self.isScopeActive(inst.spec["scope"] as? String,
                                     installedAt: inst.installedAt,
                                     at: currentBattle, spec: inst.spec)
            else { continue }
            // `from` is the instigating side *relative to the inst
            // owner*. If owner is .player and from is "opponent",
            // redirect fires when `side == .cpu`.
            let ownerSide = inst.owner
            let fromStr = (eff["from"] as? String) ?? "opponent"
            let toStr   = (eff["to"]   as? String) ?? "self"
            let fromSide: PlayExecContext.Side = fromStr == "self"
                ? ownerSide
                : (ownerSide == .player ? .cpu : .player)
            let toSide: PlayExecContext.Side = toStr == "self"
                ? ownerSide
                : (ownerSide == .player ? .cpu : .player)
            if actualSide == fromSide { actualSide = toSide }
        }

        // 2. Cap + 3. Delta (applied in that order)
        for inst in persistents {
            guard let eff = inst.spec["effect"] as? [String: Any],
                  (eff["op"] as? String) == "modify_hd_recover",
                  Self.isScopeActive(inst.spec["scope"] as? String,
                                     installedAt: inst.installedAt,
                                     at: currentBattle, spec: inst.spec)
            else { continue }
            let targetStr = (eff["target"] as? String) ?? "both"
            let applies: Bool
            switch targetStr {
            case "both": applies = true
            case "self": applies = actualSide == inst.owner
            default:     applies = actualSide != inst.owner
            }
            if !applies { continue }
            if let cap = eff["cap"] as? Int { actualAmount = min(actualAmount, cap) }
            if let d   = eff["delta"] as? Int { actualAmount += d }
        }

        // 4. Block
        if isBlocked(actualSide, kind: "block_hd_recover") {
            cpuCallouts.append(ActionCallout(
                message: "\(actualSide == .player ? "You" : "CPU") blocked from HD recovery",
                icon: "hand.raised.fill",
                color: "C0392B"
            ))
            return 0
        }
        actualAmount = max(0, actualAmount)
        if actualSide == .player { playerHotDogs = min(10, playerHotDogs + actualAmount) }
        else                     { cpuHotDogs    = min(10, cpuHotDogs    + actualAmount) }

        // Surface modifier-driven changes — only callout when the
        // applied amount differs from what the play asked for, OR the
        // recipient swapped. Keeps the banner quiet for vanilla
        // recovers while loud for actually-modified ones.
        if actualAmount != amount || actualSide != side {
            let from = side == .player ? "You" : "CPU"
            let to   = actualSide == .player ? "You" : "CPU"
            let label: String
            if actualSide != side {
                label = "HD recovery redirected: \(from) → \(to) (+\(actualAmount))"
            } else {
                label = "HD recovery: \(to) +\(actualAmount) (modified from +\(amount))"
            }
            cpuCallouts.append(ActionCallout(
                message: label,
                icon: "arrow.triangle.swap",
                color: "FFD166"
            ))
        }
        return actualAmount
    }

    /// Central persistent-install entry point. Weapon-transform specs
    /// (B.1) split into `weaponTransforms` instead of joining the main
    /// persistents list — reads of `ctx.weapon(of:as:)` only consult
    /// the transform array, keeping the hot-path condition eval cheap.
    /// All other persistents fall through unchanged.
    ///
    /// Every install also pushes a callout into `cpuCallouts` so the
    /// playmat surfaces what was just installed — without a callout the
    /// user has no visual signal that a persistent is in force.
    func installPersistent(owner: PlayExecContext.Side, spec: [String: Any], sourceCard: String = "") {
        if let effect = spec["effect"] as? [String: Any],
           (effect["op"] as? String) == "weapon_transform" {
            let scope = (spec["scope"] as? String) ?? "rest_of_game"
            let target = (effect["target"] as? String) ?? "self"
            let to = (effect["to"] as? String) ?? ""
            guard !to.isEmpty else { return }
            let from = effect["from"] as? String
            weaponTransforms.append(WeaponTransform(
                owner: owner,
                installedAt: currentBattle,
                scope: scope,
                target: target,
                from: from?.isEmpty == true ? nil : from,
                to: to,
                sourceCard: sourceCard
            ))
            cpuCallouts.append(ActionCallout(
                message: weaponTransformLabel(target: target, from: from, to: to, scope: scope),
                icon: "arrow.triangle.2.circlepath",
                color: "8B00FF"
            ))
            return
        }
        persistents.append(PersistentEffect(
            owner: owner,
            spec: spec,
            installedAt: currentBattle,
            sourceCard: sourceCard
        ))
        if let label = persistentSummaryLabel(spec: spec, owner: owner) {
            // Prepend source card name when known so the install
            // callout reads as "Baby Phoenix · End-of-turn +10"
            // instead of "End-of-turn +10."
            let prefix = sourceCard.isEmpty ? "" : "\(sourceCard) · "
            cpuCallouts.append(ActionCallout(
                message: prefix + label,
                icon: "infinity",
                color: "00F5FF"
            ))
        }
    }

    // MARK: - Active-effect summaries (UI surfacing)
    //
    // These power the on-mat persistent-effects banner. Returning
    // `nil` from `persistentSummaryLabel` means the persistent is
    // structural-only (no end-user signal needed).

    private func weaponTransformLabel(target: String, from: String?, to: String, scope: String) -> String {
        let scopeLabel = scopeDisplayLabel(scope)
        switch target {
        case "all_heroes":
            return "All Heroes → \(to) weapons \(scopeLabel)"
        case "self":
            if let from = from, !from.isEmpty {
                return "Your \(from) Heroes → \(to) weapons \(scopeLabel)"
            }
            return "Your Heroes → \(to) weapons \(scopeLabel)"
        case "opponent":
            return "Opponent's Heroes → \(to) weapons \(scopeLabel)"
        default:
            return "Weapon transform: → \(to) \(scopeLabel)"
        }
    }

    private func persistentSummaryLabel(spec: [String: Any], owner: PlayExecContext.Side) -> String? {
        guard let eff = spec["effect"] as? [String: Any] else { return nil }
        let op = (eff["op"] as? String) ?? ""
        let scope = scopeDisplayLabel(spec["scope"] as? String ?? "this_battle")
        let who = owner == .player ? "You" : "CPU"
        // Triggered persistents (on_battle_win / on_battle_loss / etc.)
        // wear a short prefix in the body so multi-branch cards like
        // Win or Weiners read as two distinct effects ("if win: …" /
        // "if loss: …") instead of two visually-identical pills.
        let trigger = (spec["trigger"] as? String) ?? ""
        let triggerPrefix: String = {
            switch trigger {
            case "on_battle_win":     return "if win → "
            case "on_battle_loss":    return "if loss → "
            case "on_plays_resolved": return "end of plays → "
            case "on_battle_start":   return "battle start → "
            case "on_opp_play":       return "on opp play → "
            case "on_turn_end":       return "turn end → "
            default:                  return ""
            }
        }()
        // Helper to attach the trigger prefix in front of an op-specific
        // body so it reads naturally in the pill.
        func withPrefix(_ body: String) -> String {
            triggerPrefix.isEmpty ? body : "\(triggerPrefix)\(body)"
        }
        switch op {
        case "modify_hd_recover":
            if let cap = eff["cap"] as? Int { return withPrefix("HD recovery capped at \(cap) \(scope)") }
            if let d = eff["delta"] as? Int { return withPrefix("HD recovery \(d > 0 ? "+\(d)" : "\(d)") \(scope)") }
            return withPrefix("HD recovery modifier active \(scope)")
        case "redirect_hd_recover":
            return withPrefix("\(who): redirect HD recovery \(scope)")
        case "block_hd_recover":
            let target = (eff["target"] as? String) ?? "self"
            switch target {
            case "both":     return withPrefix("Neither side recovers HDs \(scope)")
            case "opponent": return withPrefix("Opponent can't recover HDs \(scope)")
            default:         return withPrefix("\(who) can't recover HDs \(scope)")
            }
        case "auto_lose_battle":
            return withPrefix("Lose any battle with 0 HDs \(scope)")
        case "require_dice_roll":
            return withPrefix("Opponent must roll dice to play \(scope)")
        case "allow_hd_overspend":
            let max = (eff["max_deficit"] as? Int) ?? 0
            return withPrefix("\(who) can overspend HDs by \(max) \(scope)")
        case "power":
            // Conditional/continuous boosts (Fire Boost, Steel Resolve).
            if let delta = eff["delta"] as? Int {
                let target = (eff["target"] as? String) ?? "self"
                let recipient = target == "opponent"
                    ? (owner == .player ? "CPU Hero" : "Your Hero")
                    : (owner == .player ? "Your Hero" : "CPU Hero")
                return withPrefix("\(recipient) \(delta > 0 ? "+\(delta)" : "\(delta)") \(scope)")
            }
            return nil
        case "hd_recover":
            // Win or Weiners' loss branch, Lunch Table, etc.
            let amount: String
            if let n = eff["amount"] as? Int { amount = "\(n) HD" }
            else if (eff["amount"] as? String) == "all" { amount = "all HDs" }
            else { amount = "HDs" }
            let target = (eff["target"] as? String) ?? "self"
            let recipient = target == "opponent"
                ? (owner == .player ? "CPU" : "You")
                : (owner == .player ? "You" : "CPU")
            return withPrefix("\(recipient) recover \(amount) \(scope)")
        case "draw":
            // Win or Weiners' win branch, etc.
            let n = (eff["count"] as? Int) ?? 1
            let kind = (eff["kind"] as? String) ?? "play"
            let kindLabel = kind == "hero" ? "Hero" : "Play"
            return withPrefix("\(who) draw \(n) \(kindLabel)\(n == 1 ? "" : "s") \(scope)")
        default:
            // Unmapped persistent effect — surface a generic banner so
            // the user at least knows SOMETHING is in force, even if
            // we don't have a specific label yet.
            return withPrefix("\(who) installed \(op.replacingOccurrences(of: "_", with: " ")) \(scope)")
        }
    }

    /// Human-friendly suffix for any scope string.
    func scopeDisplayLabel(_ scope: String?) -> String {
        guard let s = scope else { return "" }
        switch s {
        case "rest_of_game":   return "(rest of game)"
        case "this_battle":    return "(this battle)"
        case "current":        return "(this battle)"
        case "next_battle":    return "(next battle)"
        case "this_and_next":  return "(this + next battle)"
        case "next_2_battles": return "(next 2 battles)"
        case "battles_4_7":    return "(battles 4–7)"
        default:
            if s.hasPrefix("battle_"),
               let n = Int(s.dropFirst("battle_".count)) {
                return "(battle \(n))"
            }
            if s == "next_N_battles" { return "(next N battles)" }
            return ""
        }
    }

    /// Effective weapon for a given Hero card seen from a particular
    /// seat. Routes through the same transform stack the executor
    /// uses, so what the user sees on the card matches what the rules
    /// engine evaluates. Returns the printed element when no transform
    /// applies; empty string for nil.
    func effectiveWeapon(of card: Card?, side: PlayExecContext.Side) -> String {
        guard let card else { return "" }
        // makeExecContext snapshots in-scope transforms into the ctx,
        // so this call is sufficient — no double-walk of the array.
        let ctx = makeExecContext(self_: side)
        return ctx.weapon(of: card, as: side)
    }

    /// True when the resolved weapon differs from the card's printed
    /// element — i.e., a transform is currently active on this hero.
    /// Used by the playmat to render the "transformed" indicator.
    func isWeaponTransformed(card: Card?, side: PlayExecContext.Side) -> Bool {
        guard let card else { return false }
        return effectiveWeapon(of: card, side: side) != card.element
    }

    /// Public, ordered list of currently-active persistent + weapon
    /// transforms with display info. The on-mat banner reads this and
    /// re-renders on every store mutation. Filters out anything not in
    /// scope so the banner shrinks as effects expire.
    ///
    /// `remaining` is the count of battles left for finite-scope
    /// effects (this_battle = 1, next_2_battles = 2 freshly-installed
    /// or 1 after a battle, etc.). Nil for `rest_of_game`. Drives the
    /// tick-down badge UX#11 calls for.
    var activeEffectsForUI: [(id: UUID, owner: PlayExecContext.Side, label: String, icon: String, color: String, remaining: Int?, sourceCard: String)] {
        var rows: [(UUID, PlayExecContext.Side, String, String, String, Int?, String)] = []
        for t in weaponTransforms where Self.isScopeActive(t.scope, installedAt: t.installedAt, at: currentBattle) {
            rows.append((
                UUID(),
                t.owner,
                weaponTransformLabel(target: t.target, from: t.from, to: t.to, scope: t.scope),
                "arrow.triangle.2.circlepath",
                "8B00FF",
                Self.battlesRemaining(for: t.scope, installedAt: t.installedAt, at: currentBattle, spec: nil),
                t.sourceCard
            ))
        }
        // One pill per active persistent. The previous attempt to
        // collapse multi-branch cards (Win or Weiners shows up as two
        // pills) by deduping on (owner, sourceCard, scope) caused the
        // banner to disappear entirely in some cases — a regression
        // worse than the original noise. Reverted; instead distinct
        // bodies handle the visual (see persistentSummaryLabel).
        for inst in persistents where Self.isScopeActive(inst.spec["scope"] as? String,
                                                          installedAt: inst.installedAt,
                                                          at: currentBattle, spec: inst.spec) {
            if let label = persistentSummaryLabel(spec: inst.spec, owner: inst.owner) {
                rows.append((
                    UUID(),
                    inst.owner,
                    label,
                    "infinity",
                    "00F5FF",
                    Self.battlesRemaining(for: inst.spec["scope"] as? String,
                                          installedAt: inst.installedAt,
                                          at: currentBattle,
                                          spec: inst.spec),
                    inst.sourceCard
                ))
            }
        }
        return rows
    }

    /// Battles left before the scope expires. Returns nil for unbounded
    /// (rest_of_game) or unrecognized scopes. Used by the tick-down
    /// badge so coaches see "3" or "1 left" on a persistent pill.
    static func battlesRemaining(for scope: String?,
                                  installedAt: Int,
                                  at battleIdx: Int,
                                  spec: [String: Any]?) -> Int? {
        guard let scope else { return nil }
        switch scope {
        case "rest_of_game":   return nil
        case "this_battle":    return battleIdx == installedAt ? 1 : 0
        case "current":        return battleIdx == installedAt ? 1 : 0
        case "next_battle":    return battleIdx == installedAt + 1 ? 1 : 0
        case "this_and_next":  return max(0, (installedAt + 1) - battleIdx + 1)
        case "next_2_battles": return max(0, (installedAt + 2) - battleIdx + 1)
        case "battles_4_7":    return max(0, 6 - battleIdx + 1)
        case "next_N_battles":
            let n = (spec?["n"] as? Int) ?? 1
            return max(0, (installedAt + n) - battleIdx + 1)
        default:
            if scope.hasPrefix("battle_"),
               let n = Int(scope.dropFirst("battle_".count)) {
                return battleIdx == n - 1 ? 1 : 0
            }
            return nil
        }
    }

    /// Apply continuous/battle-start persistents (Fire Boost, etc.) at reveal.
    func applyContinuousPersistents() {
        guard battles.indices.contains(currentBattle) else { return }
        var slot = battles[currentBattle]
        for inst in persistents {
            let scope = inst.spec["scope"] as? String
            let trigger = inst.spec["trigger"] as? String
            let inScope = Self.isScopeActive(scope, installedAt: inst.installedAt,
                                              at: currentBattle, spec: inst.spec)
            guard inScope else { continue }
            guard trigger == "continuous" || trigger == "battle_start" else { continue }
            guard let eff = inst.spec["effect"] as? [String: Any] else { continue }

            let ctx = makeExecContext(self_: inst.owner)
            var out = PlayExecOut()
            PlayEffectExecutor.execStep(eff, ctx: ctx, out: &out)
            guard out.hasEffect else { continue }

            // Translate self/opp deltas into player/cpu deltas for the slot
            let playerDelta: Int
            let cpuDelta: Int
            if inst.owner == .player {
                playerDelta = out.selfDelta
                cpuDelta = out.oppDelta
            } else {
                cpuDelta = out.selfDelta
                playerDelta = out.oppDelta
            }
            slot.playerEffectPower += playerDelta
            slot.cpuEffectPower    += cpuDelta
            // UX#3 — record itemized contribution. Pull a friendly
            // label from the persistent's own summary helper.
            let label = persistentSummaryLabel(spec: inst.spec, owner: inst.owner)
                ?? "Persistent effect"
            if playerDelta != 0 {
                slot.playerBreakdown.append(.init(label: label, delta: playerDelta))
            }
            if cpuDelta != 0 {
                slot.cpuBreakdown.append(.init(label: label, delta: cpuDelta))
            }

            // Record applied deltas so cancel_persistent can rewind the
            // current battle if it fires later.
            inst.appliedAtBattle = currentBattle
            inst.appliedPlayerDelta = playerDelta
            inst.appliedCpuDelta = cpuDelta
        }
        battles[currentBattle] = slot
    }

    // MARK: - Play Card Effect Resolver

    /// Returns (playerDelta, opponentDelta) — positive = bonus, negative = penalty.
    /// `playerCard` is the hero of the person who played the card.
    static func resolveEffect(card: Card, playerCard: Card?, cpuCard: Card?) -> (Int, Int) {
        guard let ability = card.playAbility, !ability.isEmpty else {
            return fallbackEffect(cost: card.playCost ?? 0)
        }

        // Numeric-only abilities (shorthand power values like "75", "100")
        if let numericValue = Int(ability.trimmingCharacters(in: .whitespaces)), numericValue > 0 {
            return (numericValue, 0)
        }

        let text = ability.lowercased()

        // ── Power swap / set effects ──────────────────────────────
        if text.contains("swap your hero's current power with your opponent") || text.contains("swap current power with your opponent") {
            let myPow = playerCard?.power ?? 0
            let theirPow = cpuCard?.power ?? 0
            return (theirPow - myPow, myPow - theirPow)
        }
        if text.contains("set your hero's power to 5 higher") || text.contains("set your hero's power to the same") {
            let theirPow = cpuCard?.power ?? 0
            let myPow = playerCard?.power ?? 0
            let target = text.contains("5 higher") ? theirPow + 5 : theirPow
            return (target - myPow, 0)
        }
        if text.contains("same power as your opponent") || text.contains("same as your opponent") {
            let diff = (cpuCard?.power ?? 0) - (playerCard?.power ?? 0)
            return (diff, 0)
        }
        if text.contains("power returns to its starting power") || text.contains("return to their starting power") {
            // Reset all effect bonuses — return negative of current effect
            return (0, 0) // handled as special case in caller
        }
        if text.contains("power is doubled") {
            return (playerCard?.power ?? 0, 0)
        }

        // ── Cancel effects ────────────────────────────────────────
        if text.contains("cancel every play your opponent") || text.contains("cancel all plays") {
            // In practice: negate opponent's accumulated bonuses
            return (0, 0) // actual cancellation would need battle slot access
        }
        if text.contains("can't run any plays this battle") && text.contains("opponent") {
            return (0, 0) // blocking effect
        }

        // ── Steal effects ─────────────────────────────────────────
        if text.contains("steal") {
            if let match = text.firstMatch(of: /steal -(\d+).*\+(\d+)/) {
                return (Int(match.2) ?? 5, -(Int(match.1) ?? 5))
            }
            // "steal" without explicit numbers
            return (5, -5)
        }
        if text.contains("opponent loses 1 hot dog") && text.contains("you gain 1 hot dog") {
            return (0, 0) // hot dog effect, not power
        }

        // ── Coin flip effects ─────────────────────────────────────
        if text.contains("flip a coin") {
            return resolveCoinFlip(text: text, playerCard: playerCard)
        }

        // ── Dice roll effects ─────────────────────────────────────
        if text.contains("roll a di") || text.contains("roll a die") {
            return resolveDiceRoll(text: text, playerCard: playerCard, cpuCard: cpuCard)
        }

        // ── Simple "+N" to your hero (broad match) ───────────────
        // "Your Hero gets +N", "give your Hero +N", "your current Hero gets +N", "this Hero gets +N"
        if let match = text.firstMatch(of: /(?:your|this|give your|the) (?:hero|current hero|hero's power|active hero).*?(?:gets?|gains?|in the active battle.*?gets) \+(\d+)/) {
            let bonus = Int(match.1) ?? 0
            // Check for conditional: "if ... weapon"
            if let weaponMatch = text.firstMatch(of: /if your hero has (?:a |an )?(\w+) weapon/) {
                let weapon = String(weaponMatch.1).uppercased()
                if playerCard?.element != weapon { return (0, 0) }
            }
            return (bonus, 0)
        }

        // ── "All your heroes get +N for the rest of the game" ────
        if let match = text.firstMatch(of: /all your heroes get \+(\d+)/) {
            return (Int(match.1) ?? 10, 0)
        }
        if let match = text.firstMatch(of: /all your opponent's heroes get -(\d+)/) {
            return (0, -(Int(match.1) ?? 10))
        }

        // ── Simple "-N" to opponent (broad match) ────────────────
        if let match = text.firstMatch(of: /opponent's hero(?:'s power)?.*?(?:gets?|loses?) -(\d+)/) {
            return (0, -(Int(match.1) ?? 0))
        }
        if let match = text.firstMatch(of: /lower.*?opponent.*?-(\d+)/) {
            return (0, -(Int(match.1) ?? 0))
        }
        if let match = text.firstMatch(of: /opponent's hero gets -(\d+)/) {
            return (0, -(Int(match.1) ?? 0))
        }
        // "their Hero gets -N"
        if let match = text.firstMatch(of: /their hero gets -(\d+)/) {
            return (0, -(Int(match.1) ?? 0))
        }
        // "give it -N" (referring to opponent)
        if text.contains("opponent") {
            if let match = text.firstMatch(of: /give it -(\d+)/) {
                return (0, -(Int(match.1) ?? 0))
            }
        }

        // ── Weapon-conditional boost ──────────────────────────────
        if let match = text.firstMatch(of: /if your hero has (?:a |an )?(\w+) weapon.*?\+(\d+)/) {
            let weapon = String(match.1).uppercased()
            let bonus = Int(match.2) ?? 0
            return playerCard?.element == weapon ? (bonus, 0) : (0, 0)
        }
        // "If your Hero has a X weapon, your opponent can't..." — blocking, no power change
        if text.contains("if your hero has") && text.contains("weapon") && (text.contains("can't") || text.contains("cannot")) {
            return (0, 0)
        }
        // "For the rest of the game, all Heroes with X weapons get +N"
        if let match = text.firstMatch(of: /all heroes with (\w+) weapons get \+(\d+)/) {
            let weapon = String(match.1).uppercased()
            let bonus = Int(match.2) ?? 10
            return playerCard?.element == weapon ? (bonus, 0) : (0, 0)
        }
        // "If your opponent's Hero has X weapon, give it -N"
        if let match = text.firstMatch(of: /opponent's hero has (?:a |an )?(\w+) weapon.*?-(\d+)/) {
            let weapon = String(match.1).uppercased()
            let penalty = Int(match.2) ?? 15
            return cpuCard?.element == weapon ? (0, -penalty) : (0, 0)
        }
        // "If your opponent's Hero has X weapon, your Hero gets +N"
        if let match = text.firstMatch(of: /opponent's hero has (?:a |an )?(\w+) weapon.*?your hero gets \+(\d+)/) {
            let weapon = String(match.1).uppercased()
            let bonus = Int(match.2) ?? 15
            return cpuCard?.element == weapon ? (bonus, 0) : (0, 0)
        }

        // ── Weapon type matching ──────────────────────────────────
        if text.contains("different weapon type") && text.contains("opponent") {
            let same = playerCard?.element == cpuCard?.element
            if let match = text.firstMatch(of: /\+(\d+)/) {
                let bonus = Int(match.1) ?? 10
                if text.contains("different") && text.contains("-") {
                    // opponent gets penalty
                    return same ? (0, 0) : (0, -bonus)
                }
                return same ? (0, 0) : (bonus, 0)
            }
        }

        // ── "can't drop below" — defensive bonus ─────────────────
        if text.contains("can't drop below") || text.contains("can't lose any more power") {
            if let match = text.firstMatch(of: /(\w+) weapon/) {
                let weapon = String(match.1).uppercased()
                if playerCard?.element == weapon { return (15, 0) }
            }
            return (0, 0)
        }
        // "can't have its power reduced" — protection
        if text.contains("can't have its power reduced") || text.contains("can't be affected") {
            return (10, 0) // treat as defensive bonus
        }

        // ── Conditional bonuses ───────────────────────────────────
        if text.contains("if this battle is tied") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                return (Int(match.1) ?? 1, 0)
            }
        }
        if text.contains("lost the previous") || text.contains("lost the first") || text.contains("lost the 2 previous") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                return (Int(match.1) ?? 15, 0)
            }
        }
        if text.contains("won the first battle") || text.contains("won the last battle") || text.contains("won 2 battles") || text.contains("won at least") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                return (Int(match.1) ?? 10, 0)
            }
        }
        if text.contains("if you substituted this battle") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                return (Int(match.1) ?? 10, 0)
            }
        }

        // ── Hot dog conditional ───────────────────────────────────
        if text.contains("hot dog") && text.contains("left") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                return (Int(match.1) ?? 10, 0)
            }
        }

        // ── Draw effects (power component only) ──────────────────
        // "Draw N Plays" with a power bonus: "Your Hero gets +10. Draw 2 Plays."
        if text.contains("draw") && text.contains("play") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                // Some draw cards also have power bonuses
                if text.contains("your hero gets") || text.contains("your hero loses") {
                    if text.contains("loses") {
                        if let lossMatch = text.firstMatch(of: /-(\d+)/) {
                            return (-(Int(lossMatch.1) ?? 0), 0)
                        }
                    }
                    return (Int(match.1) ?? 0, 0)
                }
            }
            return (0, 0) // pure draw effects handled by resolveDrawEffects
        }

        // ── Discard-based power ───────────────────────────────────
        if text.contains("discard") {
            // "Discard N Plays from your hand. Your opponent's Hero gets -N"
            if let match = text.firstMatch(of: /opponent's hero gets -(\d+)/) {
                return (0, -(Int(match.1) ?? 20))
            }
            // "Your Hero gets +N for every card discarded"
            if let match = text.firstMatch(of: /\+(\d+).*every card discarded/) {
                let perCard = Int(match.1) ?? 5
                return (perCard * 3, 0) // estimate 3 cards discarded
            }
            // "Discard another Play from your hand and your Hero gets +10"
            if let match = text.firstMatch(of: /your hero gets \+(\d+)/) {
                return (Int(match.1) ?? 10, 0)
            }
            return (0, 0) // pure discard effects
        }

        // ── "Both players" effects ────────────────────────────────
        if text.contains("both players") || text.contains("both heroes") {
            if let match = text.firstMatch(of: /your hero gets \+(\d+)/) {
                return (Int(match.1) ?? 10, 0)
            }
            return (0, 0) // neutral effects
        }

        // ── "For the rest of the game" persistent effects ────────
        if text.contains("for the rest of the game") {
            // These are persistent effects; approximate their power value
            if text.contains("substitutions are free") { return (0, 0) }
            if let match = text.firstMatch(of: /\+(\d+)/) {
                return (Int(match.1) ?? 5, 0)
            }
            if let match = text.firstMatch(of: /-(\d+)/) {
                return (0, -(Int(match.1) ?? 5))
            }
            return (5, 0)
        }

        // ── Swap hero effects ─────────────────────────────────────
        if text.contains("swap your hero") || text.contains("replace your hero") || text.contains("replace this hero") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                return (Int(match.1) ?? 10, 0)
            }
            return (0, 0) // hero swap without power change
        }

        // ── Hot dog economy (no power change) ─────────────────────
        if text.contains("recover") && text.contains("hot dog") { return (0, 0) }
        if text.contains("opponent") && text.contains("loses") && text.contains("hot dog") { return (0, 0) }
        if text.contains("hot dog") { return (0, 0) }

        // ── Honors effects ────────────────────────────────────────
        if text.contains("honors") { return (0, 0) }

        // ── Look/peek effects ─────────────────────────────────────
        if text.contains("look at") || text.contains("reveal the top") { return (0, 0) }

        // ── Re-order effects ──────────────────────────────────────
        if text.contains("re-order") { return (0, 0) }

        // ── Last resort: find any +N or -N ────────────────────────
        if let match = text.firstMatch(of: /\+(\d+)/) {
            return (Int(match.1) ?? 0, 0)
        }
        if let match = text.firstMatch(of: /-(\d+)/) {
            if text.contains("opponent") {
                return (0, -(Int(match.1) ?? 0))
            }
            return (-(Int(match.1) ?? 0), 0)
        }

        // Fallback
        return fallbackEffect(cost: card.playCost ?? 0)
    }

    private static func fallbackEffect(cost: Int) -> (Int, Int) {
        (cost * 6 + 5, 0)
    }

    private static func resolveCoinFlip(text: String, playerCard: Card? = nil) -> (Int, Int) {
        var flipCount = 1
        if let match = text.firstMatch(of: /flip a coin (\d+) times/) {
            flipCount = Int(match.1) ?? 1
        }

        var playerDelta = 0
        var cpuDelta = 0

        for _ in 0..<flipCount {
            let heads = Bool.random()

            if heads {
                // "heads, +X" pattern
                if let match = text.firstMatch(of: /heads.*?\+(\d+)/) {
                    playerDelta += Int(match.1) ?? 0
                }
                // "heads, opponent gets -X"
                if let match = text.firstMatch(of: /heads.*?opponent.*?-(\d+)/) {
                    cpuDelta -= Int(match.1) ?? 0
                }
                // "heads, your Hero gets +X" with weapon condition
                if playerDelta == 0 && cpuDelta == 0 {
                    if let match = text.firstMatch(of: /heads.*?hero gets \+(\d+)/) {
                        playerDelta += Int(match.1) ?? 0
                    }
                }
            } else {
                // "tails, +X" pattern
                if let match = text.firstMatch(of: /tails.*?\+(\d+)/) {
                    playerDelta += Int(match.1) ?? 0
                }
                // "tails, opponent gets -X"
                if let match = text.firstMatch(of: /tails.*?opponent.*?-(\d+)/) {
                    cpuDelta -= Int(match.1) ?? 0
                }
                // "tails, your Hero gets -X"
                if let match = text.firstMatch(of: /tails.*?(?:your hero|hero) (?:gets|loses) -(\d+)/) {
                    playerDelta -= Int(match.1) ?? 0
                }
            }
        }

        // Special: "3 times; 2 or more heads, +15"
        if text.contains("2 or more") && flipCount >= 3 {
            // Already handled by per-flip logic, but ensure something happens
        }

        // "power is doubled" on all heads
        if text.contains("power is doubled") && flipCount > 0 {
            let allHeads = (0..<flipCount).allSatisfy { _ in Bool.random() }
            if allHeads {
                return (playerCard?.power ?? 0, 0)
            }
            return (0, 0)
        }

        if playerDelta == 0 && cpuDelta == 0 {
            // Generic coin flip — give a small bonus on heads
            return Bool.random() ? (10, 0) : (0, 0)
        }
        return (playerDelta, cpuDelta)
    }

    private static func resolveDiceRoll(text: String, playerCard: Card? = nil, cpuCard: Card? = nil) -> (Int, Int) {
        let roll = Int.random(in: 1...6)

        // "roll a die; your Hero gets +5x the number"
        if text.contains("+5x the number") || text.contains("+5x") || text.contains("5x the number") {
            return (5 * roll, 0)
        }

        // "opponent's Hero gets -5x the number"
        if text.contains("-5x the number") || (text.contains("opponent") && text.contains("5x")) {
            return (0, -5 * roll)
        }

        // "roll a die two times; if numbers add up to 7, +100"
        if text.contains("two times") && text.contains("add up to 7") {
            let roll2 = Int.random(in: 1...6)
            if roll + roll2 == 7 { return (100, 0) }
            return (0, 0)
        }

        // "if you get a 1 or 6, power drops to 0. If 2-5, +25"
        if text.contains("drops to 0") || text.contains("goes to 0") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                let bonus = Int(match.1) ?? 25
                if text.contains("1 or 6") {
                    return (roll == 1 || roll == 6) ? (-(playerCard?.power ?? 999), 0) : (bonus, 0)
                }
                if text.contains("lands on a 1") || text.contains("lands on 1") {
                    return roll == 1 ? (-(playerCard?.power ?? 999), 0) : (bonus, 0)
                }
            }
        }

        // "if it lands on 3 or 4, +40. If not, +5"
        if let match = text.firstMatch(of: /lands on (\d+) or (\d+).*?\+(\d+)/) {
            let target1 = Int(match.1) ?? 3
            let target2 = Int(match.2) ?? 4
            let bonus = Int(match.3) ?? 40
            if roll == target1 || roll == target2 { return (bonus, 0) }
            if let fallbackMatch = text.firstMatch(of: /if not.*?\+(\d+)/) {
                return (Int(fallbackMatch.1) ?? 5, 0)
            }
            return (5, 0)
        }

        // "if it lands on 3-6, +25. If 1 or 2, -25"
        if text.contains("3-6") || text.contains("4-6") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                let bonus = Int(match.1) ?? 25
                let threshold = text.contains("4-6") ? 4 : 3
                if roll >= threshold { return (bonus, 0) }
                if let penaltyMatch = text.firstMatch(of: /-(\d+)/) {
                    return (-(Int(penaltyMatch.1) ?? 0), 0)
                }
                return (0, 0)
            }
        }

        // "if you roll a 5 or 6, +50"
        if text.contains("5 or 6") {
            if let match = text.firstMatch(of: /\+(\d+)/) {
                let bonus = Int(match.1) ?? 50
                return (roll >= 5) ? (bonus, 0) : (0, 0)
            }
        }

        // "Roll a dice 3 times. Your Hero gets +30 if you roll a 6."
        if text.contains("3 times") && text.contains("roll a 6") {
            let rolls = (0..<3).map { _ in Int.random(in: 1...6) }
            if rolls.contains(6) { return (30, 0) }
            return (0, 0)
        }

        // "roll a dice once. If 4-6, opponent gets -15. May roll again."
        if text.contains("roll again") {
            var total = 0
            var currentRoll = roll
            while currentRoll >= 4 {
                if let match = text.firstMatch(of: /-(\d+)/) {
                    total -= Int(match.1) ?? 15
                }
                currentRoll = Int.random(in: 1...6)
            }
            return (0, total)
        }

        // "Roll a dice to Recover Hot Dogs" — no power effect
        if text.contains("recover hot dog") { return (0, 0) }

        // "draw Plays equivalent to that number" — no power, draw handled separately
        if text.contains("draw plays equivalent") || text.contains("draw play") { return (0, 0) }

        // "if you roll a 6, swap current Power"
        if text.contains("swap current power") {
            if roll == 6 {
                let myPow = playerCard?.power ?? 0
                let theirPow = cpuCard?.power ?? 0
                return (theirPow - myPow, myPow - theirPow)
            }
            return (0, 0)
        }

        // Generic: pick a number, land on it = +N
        if let match = text.firstMatch(of: /\+(\d+)/) {
            let bonus = Int(match.1) ?? 20
            // "pick a number 1-6, roll" = 1/6 chance
            if text.contains("pick a number") {
                return roll == Int.random(in: 1...6) ? (bonus, 0) : (0, 0)
            }
            // "Both players roll, higher gets +25"
            if text.contains("both players roll") {
                let cpuRoll = Int.random(in: 1...6)
                if roll > cpuRoll { return (bonus, 0) }
                if cpuRoll > roll { return (0, 0) }
                // Tied
                if let tiedMatch = text.firstMatch(of: /tied.*?-(\d+)/) {
                    return (-(Int(tiedMatch.1) ?? 10), 0)
                }
                return (0, 0)
            }
            return (bonus, 0)
        }

        return (10, 0)
    }


    /// Description of what a play card's effect will do (for UI display).
    /// play-effects.json is authoritative: covers cards where cards.json has
    /// playAbility=null (e.g. National Starter Set variants of Loan Sharked).
    static func effectDescription(for card: Card) -> String {
        if let ability = card.playAbility, !ability.isEmpty { return ability }
        if let entry = PlayEffects.entry(for: card.name),
           let ability = entry["ability"] as? String,
           !ability.isEmpty {
            return ability
        }
        let cost = card.playCost ?? 0
        return "+\(cost * 6 + 5) Power"
    }

    // MARK: - Reset

    func resetMatch() {
        battles = []
        currentBattle = 0
        phase = .reveal
        playerScore = 0; cpuScore = 0
        playerHeroDeck = []; cpuHeroDeck = []
        playerBench = []; cpuBench = []
        playerHand = []; cpuHand = []
        playerPlayDeck = []; playerPlayDiscard = []
        playerHotDogs = 10; cpuHotDogs = 10
        matchOver = false; matchWinner = nil
        Self.deleteSavedMatch()
    }

    // MARK: - Persistence

    struct MatchSnapshot: Codable {
        var mode: PracticeMode
        var battles: [BattleSlot]
        var currentBattle: Int
        var phase: BattlePhase
        var playerScore: Int
        var cpuScore: Int
        var honors: Honors
        var playerHeroDeck: [Card]
        var playerBench: [Card]
        var playerHand: [Card]
        var playerPlayDeck: [Card]
        var playerPlayDiscard: [Card]
        var playerHotDogs: Int
        var playerHotDogDiscard: Int
        var cpuHeroDeck: [Card]
        var cpuBench: [Card]
        var cpuHand: [Card]
        var cpuHotDogs: Int
        var cpuPlaysRemaining: Int
        var allCardsPool: [Card]
        var playerSubstituted: Bool
        var cpuSubstituted: Bool
        var playerPassedPlays: Bool
        var cpuPassedPlays: Bool
        var matchOver: Bool
        var matchWinner: Honors?
        // State added 2026-04-16 for full effect coverage. Each field is
        // optional so we can still decode older saves; new saves always write them.
        var playerCostMods: [CostMod]? = nil
        var cpuCostMods: [CostMod]? = nil
        var playerBlocks: [BlockEntry]? = nil
        var cpuBlocks: [BlockEntry]? = nil
        var playerPendingHonors: ScopedFlag? = nil
        var cpuPendingHonors: ScopedFlag? = nil
        var playerFreeSub: ScopedFlag? = nil
        var cpuFreeSub: ScopedFlag? = nil
        var playerSubCostTransferFrom: PlayExecContext.Side? = nil
        var cpuSubCostTransferFrom: PlayExecContext.Side? = nil
        var markedBattles: [MarkedBattle]? = nil
        var persistents: [PersistentEffect]? = nil
    }

    private static var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("practice_match.json")
    }

    static var hasSavedMatch: Bool {
        FileManager.default.fileExists(atPath: saveURL.path)
    }

    func saveMatch() {
        // Never persist a completed match — starting again should start fresh.
        guard !matchOver else {
            Self.deleteSavedMatch()
            return
        }
        let snapshot = MatchSnapshot(
            mode: mode, battles: battles, currentBattle: currentBattle,
            phase: phase, playerScore: playerScore, cpuScore: cpuScore,
            honors: honors, playerHeroDeck: playerHeroDeck, playerBench: playerBench,
            playerHand: playerHand, playerPlayDeck: playerPlayDeck,
            playerPlayDiscard: playerPlayDiscard, playerHotDogs: playerHotDogs,
            playerHotDogDiscard: playerHotDogDiscard, cpuHeroDeck: cpuHeroDeck,
            cpuBench: cpuBench, cpuHand: cpuHand, cpuHotDogs: cpuHotDogs,
            cpuPlaysRemaining: cpuPlaysRemaining, allCardsPool: allCardsPool,
            playerSubstituted: playerSubstituted, cpuSubstituted: cpuSubstituted,
            playerPassedPlays: playerPassedPlays, cpuPassedPlays: cpuPassedPlays,
            matchOver: matchOver, matchWinner: matchWinner,
            playerCostMods: playerCostMods, cpuCostMods: cpuCostMods,
            playerBlocks: playerBlocks, cpuBlocks: cpuBlocks,
            playerPendingHonors: playerPendingHonors, cpuPendingHonors: cpuPendingHonors,
            playerFreeSub: playerFreeSub, cpuFreeSub: cpuFreeSub,
            playerSubCostTransferFrom: playerSubCostTransferFrom,
            cpuSubCostTransferFrom: cpuSubCostTransferFrom,
            markedBattles: markedBattles, persistents: persistents
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: Self.saveURL, options: .atomic)
        }
    }

    func restoreMatch() -> Bool {
        guard let data = try? Data(contentsOf: Self.saveURL),
              let snapshot = try? JSONDecoder().decode(MatchSnapshot.self, from: data) else { return false }
        mode = snapshot.mode
        battles = snapshot.battles
        currentBattle = snapshot.currentBattle
        phase = snapshot.phase
        playerScore = snapshot.playerScore
        cpuScore = snapshot.cpuScore
        honors = snapshot.honors
        playerHeroDeck = snapshot.playerHeroDeck
        playerBench = snapshot.playerBench
        playerHand = snapshot.playerHand
        playerPlayDeck = snapshot.playerPlayDeck
        playerPlayDiscard = snapshot.playerPlayDiscard
        playerHotDogs = snapshot.playerHotDogs
        playerHotDogDiscard = snapshot.playerHotDogDiscard
        cpuHeroDeck = snapshot.cpuHeroDeck
        cpuBench = snapshot.cpuBench
        cpuHand = snapshot.cpuHand
        cpuHotDogs = snapshot.cpuHotDogs
        cpuPlaysRemaining = snapshot.cpuPlaysRemaining
        allCardsPool = snapshot.allCardsPool
        playerSubstituted = snapshot.playerSubstituted
        cpuSubstituted = snapshot.cpuSubstituted
        playerPassedPlays = snapshot.playerPassedPlays
        cpuPassedPlays = snapshot.cpuPassedPlays
        matchOver = snapshot.matchOver
        matchWinner = snapshot.matchWinner
        // Effect-tracking state (all optional for back-compat with older saves)
        playerCostMods = snapshot.playerCostMods ?? []
        cpuCostMods = snapshot.cpuCostMods ?? []
        playerBlocks = snapshot.playerBlocks ?? []
        cpuBlocks = snapshot.cpuBlocks ?? []
        playerPendingHonors = snapshot.playerPendingHonors
        cpuPendingHonors = snapshot.cpuPendingHonors
        playerFreeSub = snapshot.playerFreeSub
        cpuFreeSub = snapshot.cpuFreeSub
        playerSubCostTransferFrom = snapshot.playerSubCostTransferFrom
        cpuSubCostTransferFrom = snapshot.cpuSubCostTransferFrom
        markedBattles = snapshot.markedBattles ?? []
        persistents = snapshot.persistents ?? []
        return true
    }

    static func deleteSavedMatch() {
        try? FileManager.default.removeItem(at: saveURL)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Collection helper
// ════════════════════════════════════════════════════════════════

private extension Array {
    mutating func removeFirst(where predicate: (Element) -> Bool) {
        if let idx = firstIndex(where: predicate) { remove(at: idx) }
    }
}
