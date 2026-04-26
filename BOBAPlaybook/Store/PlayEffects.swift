//
//  PlayEffects.swift
//  BOBAPlaybook
//
//  Structured executor for play-effects.json. Mirrors the web executor in
//  js/practice.js: consumes an entry's effects[] array and returns deltas
//  + intents. Unknown ops log to `unknownOps` but never abort. The host
//  (PracticeStore) applies intents (hero swaps, blocks, peeks, etc.) after
//  the executor returns.
//

import Foundation

// ════════════════════════════════════════════════════════════════
// MARK: - Loader
// ════════════════════════════════════════════════════════════════

enum PlayEffects {
    private static var entries: [String: [String: Any]] = [:]
    private static var didLoad = false

    static func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let url = Bundle.main.url(forResource: "play-effects", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let e = root["entries"] as? [String: [String: Any]] else {
            return
        }
        entries = e
    }

    static func entry(for name: String) -> [String: Any]? {
        loadIfNeeded()
        return entries[name]
    }

    // Legality gate: true unless the entry declares an unmet `requires` condition.
    static func isPlayable(name: String, ctx: PlayExecContext) -> Bool {
        guard let e = entry(for: name),
              let req = e["requires"] as? [String: Any] else { return true }
        return PlayEffectExecutor.evalCondition(req, ctx: ctx)
    }

    // Every op the runtime implements. Used by entryHasUnknownOps to decide if
    // an "effect not fully simulated" badge should surface in the UI.
    private static let knownOps: Set<String> = [
        // Power / HD
        "power","power_set","power_swap","power_double","power_steal","power_cap_min",
        "power_reset","add_previous_hero_delta","add_top_hero_power_to_self",
        "hd","hd_recover","swap_hd_counts",
        // Plays / hand / discard
        "draw","discard","discard_top","discard_hand_all","shuffle_hand_into_deck",
        "shuffle_from_discard_to_deck","reclaim_used_play","variable_cost_bonus",
        // Randomness
        "coin_flip","dice_roll","compound_roll","dice_roll_again","versus_dice_roll",
        "dice_gate",  // persistent gate — opponent must roll to play (Leave It To Chance)
        // Legality / control
        "protect_self","cancel_opponent_plays","cap_opponent_plays",
        "block_sub","block_plays","block_draw","block_hd_recover",
        "honors_set","substitute_free","force_substitute",
        "play_cost_delta","cancel_persistent","persistent_delta","install_persistent",
        "player_choice","reveal_play_for_conditional_free",
        // Hero manipulation
        "swap_active_with_hand","swap_active_with_discard","swap_active_with_future_hero",
        "replace_active_with_top_hero_deck","replace_next_with_top_hero_deck",
        "replace_all_unrevealed_with_top_hero_deck","replace_active_from_hand",
        "discard_hero","discard_hero_from_hand","discard_revealed_hero",
        "transform_to_hot_dog","mark_future_battle",
        // Reveal / peek / search / copy
        "reveal","reveal_top","reveal_top_hero_deck","peek_and_reorder_top",
        "reveal_top_reorder_or_bottom","peek_opponent_hand","peek_unrevealed_hero",
        "reorder_unrevealed_heroes","shuffle_revealed_back","force_reveal_from_hand",
        "search","copy_last_play","play_revealed_free","play_top_of_playbook_free",
        "discard_revealed","deploy_chosen_revealed","discard_other_revealed",
        "add_chosen_revealed_to_hand_discard_rest","name_and_discard",
        // Choice
        "choice",
        // Specials
        "mirror_power_effects_to_opponent","flip_opponent_debuffs",
        "tax_per_hero_in_hand","transfer_sub_cost","end_battle_by_power",
        "weapon_debuff_or_penalty","note"
    ]

    static func entryHasUnknownOps(_ entry: [String: Any]?) -> Bool {
        guard let entry = entry else { return false }
        var found = false
        func walk(_ any: Any?) {
            if found { return }
            if let arr = any as? [Any] { for v in arr { walk(v) }; return }
            guard let s = any as? [String: Any] else { return }
            if let op = s["op"] as? String, !knownOps.contains(op) { found = true; return }
            for k in ["then","else","options","choice","effect","on_match","on_miss",
                     "heads","tails","if_match","on_reveal_effects","components",
                     "per_hero_cost","fallback","per_card","per_head","per_tail"] {
                if let v = s[k] { walk(v) }
            }
            if let branches = s["branches"] as? [[String: Any]] {
                for b in branches {
                    if let t = b["then"] { walk(t) }
                    if let e = b["effect"] { walk(e) }
                }
            }
        }
        walk(entry["effects"])
        walk(entry["persistent"])
        return found
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Executor context
// ════════════════════════════════════════════════════════════════

/// Mutable counters threaded through the executor via a reference-type wrapper
/// so struct-copy semantics of PlayExecContext don't drop updates made by
/// nested execStep calls.
final class ExecCounters {
    var cardsDiscardedByThisPlay: Int = 0
    /// Cost of the play picked by the most recent chooseTopAndKeepBest
    /// op IN THIS execution. Set by the op handler immediately so
    /// downstream conditionals in the same effects[] array can read
    /// the truthful chosen value via `chosen_play_cost`. Resets per
    /// execution since ExecCounters is built fresh each call.
    var chosenPlayCost: Int? = nil
}

struct PlayExecContext {
    enum Side: String, Codable { case player, cpu }

    let self_: Side
    var selfCard: Card?
    var oppCard: Card?
    var selfHD: Int
    var oppHD: Int
    var selfSubstituted: Bool
    var selfHand: [Card]
    var selfDiscard: [Card]
    var selfHeroDeck: [Card]
    /// The player's remaining playbook draw pile. Empty for CPU side
    /// (CPU has a single fluid hand/pool, no separate deck). Needed
    /// by ops that peek the top N plays — `add_chosen_revealed_to_hand
    /// _discard_rest` reads top N to predict the auto-chosen cost so
    /// downstream conditionals (Power Pick's "+10 if chosen ≥ 3") can
    /// read the truthful value at exec time, before the chooser
    /// intent has actually mutated PM state.
    var selfPlayDeck: [Card] = []
    var selfWon: Int
    var selfLost: Int
    var selfTied: Int
    var playsUsedThisBattle: Int
    var battleIdx: Int
    var battlesRemaining: Int
    var honors: String
    var battles: [BattleSlot]
    var counters: ExecCounters = ExecCounters()

    /// Snapshot of every weapon_transform currently in scope, ordered by
    /// install. Each dict carries `owner` ("player"/"cpu"), `target`
    /// ("all_heroes"|"self"|"opponent"), `to`, and optional `from`. Read
    /// via `weapon(of:as:)` — never inspect directly.
    var weaponTransforms: [[String: Any]] = []

    var opp: Side { self_ == .player ? .cpu : .player }

    /// Effective weapon for a card from the given controller's seat.
    /// Applies every in-scope `weapon_transform` in install order;
    /// later installs win on overlapping heroes (matches B.1 spec).
    /// Falls back to `card.element` when no transform applies. Returns
    /// the empty string for `nil`.
    ///
    /// Convention: `controller` is the side that OWNS the hero being
    /// asked about. A transform with `target: "self"` only applies when
    /// the transform's `owner` matches `controller`; `target:
    /// "opponent"` applies when it doesn't; `all_heroes` applies
    /// regardless.
    func weapon(of card: Card?, as controller: Side) -> String {
        guard let card else { return "" }
        var w = card.element
        for t in weaponTransforms {
            guard let target = t["target"] as? String,
                  let to = t["to"] as? String else { continue }
            let ownerStr = (t["owner"] as? String) ?? "player"
            let owner: Side = ownerStr == "cpu" ? .cpu : .player
            let applies: Bool
            switch target {
            case "all_heroes": applies = true
            case "self":       applies = controller == owner
            case "opponent":   applies = controller != owner
            default:           applies = false
            }
            if !applies { continue }
            if let from = t["from"] as? String, !from.isEmpty, from != w { continue }
            w = to
        }
        return w
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Intents (applied by PracticeStore after executor returns)
// ════════════════════════════════════════════════════════════════

enum PlayIntent {
    case notify(String)
    case peekHeroDeck(side: PlayExecContext.Side, count: Int)
    case swapActiveWithHand(side: PlayExecContext.Side)
    case swapActiveWithDiscard(side: PlayExecContext.Side, weaponFilter: String?)
    case swapActiveWithFutureHero(side: PlayExecContext.Side)
    case replaceActiveWithTopDeck(side: PlayExecContext.Side)
    case replaceNextWithTopDeck(side: PlayExecContext.Side)
    case replaceAllUnrevealedWithTopDeck(side: PlayExecContext.Side)
    case replaceActiveFromHand(side: PlayExecContext.Side)
    case discardActiveHero(side: PlayExecContext.Side)
    case discardHeroFromHand(side: PlayExecContext.Side)
    case discardRevealedHero(side: PlayExecContext.Side)
    case discardRevealedPlay(side: PlayExecContext.Side)
    case transformActiveToHotDog(side: PlayExecContext.Side)
    case markFutureBattle(side: PlayExecContext.Side, onReveal: [[String: Any]], selector: String)
    case forceSubstitute(target: PlayExecContext.Side, cost: Int)
    case mirrorPowerEffects(fromSide: PlayExecContext.Side, toSide: PlayExecContext.Side)
    case flipOpponentDebuffs(side: PlayExecContext.Side)
    case cancelPersistents(target: String)
    case peekOpponentHand(side: PlayExecContext.Side, count: Int, mode: String)
    case searchPlaybook(side: PlayExecContext.Side, filter: [String: Any], action: String)
    case copyLastPlay(side: PlayExecContext.Side)
    case taxPerHeroInHand(target: PlayExecContext.Side, perHDCost: Int, fallbackDiscards: Int)
    case transferSubCost(target: PlayExecContext.Side, amount: Int)
    case playRevealedFree(side: PlayExecContext.Side)
    case playTopOfPlaybookFree(targetHint: String)
    case peekUnrevealedHero(side: PlayExecContext.Side, selector: String)
    case reorderUnrevealedHeroes(side: PlayExecContext.Side)
    case revealTopPlays(side: PlayExecContext.Side, count: Int, andPlayFree: Bool)
    case revealTopHeroes(side: PlayExecContext.Side, count: Int, choose: Int)
    case installPersistent(owner: PlayExecContext.Side, spec: [String: Any])
    case installBlock(side: PlayExecContext.Side, kind: String, scope: String)
    case installHonors(side: PlayExecContext.Side, scope: String)
    case installSubstituteFree(side: PlayExecContext.Side, scope: String)
    case nameAndDiscard(target: PlayExecContext.Side)
    case endBattleByPower
    /// Player must pick `count` plays from their hand to discard.
    /// Surfaced when a `discard` op carries `mode: "choice"` on the
    /// player's side. CPU side auto-picks (no chooser UI possible).
    case chooseHandDiscard(side: PlayExecContext.Side, count: Int)
    /// Auto-discard `count` plays from `side`'s hand. Used when a
    /// `discard` op fires without `mode: "choice"` — host picks
    /// lowest-cost plays as a sensible default.
    case autoDiscardHand(side: PlayExecContext.Side, count: Int)
    /// Generic player choice — surface a sheet with `options` and
    /// run the chosen option's effects via the executor. CPU side
    /// auto-picks the option at index `cpuPick` (default 0).
    /// `prompt` is the headline shown above the options.
    case presentPlayerChoice(side: PlayExecContext.Side, prompt: String, options: [PlayChoiceOption], cpuPick: Int)
    /// Scare Tactics — pick a play from hand to "reveal." Host
    /// installs a one-shot persistent for next battle that watches
    /// for opp playing a card of cost ≥ the revealed card's cost;
    /// if so, the player gets the revealed card free.
    case revealForConditionalFree(side: PlayExecContext.Side)
    /// "Reveal top N, keep best 1, discard rest." Auto-picks the
    /// top-cost play (for kind="play") or top-power hero (for
    /// kind="hero") since neither side has a usable chooser UI.
    /// The chosen card moves to hand (plays) or bench (heroes); the
    /// other (count-1) cards go to the appropriate discard pile. The
    /// chosen card's cost is stashed on the host so the
    /// `chosen_play_cost` metric reads the actual chosen value
    /// (instead of the previous "max in hand" approximation).
    case chooseTopAndKeepBest(side: PlayExecContext.Side, kind: String, count: Int)
}

/// One option in a `player_choice` sheet. `label` is the button
/// caption, `effects` is the JSON effect array that runs when picked.
struct PlayChoiceOption {
    let label: String
    let effects: [[String: Any]]
}

// ════════════════════════════════════════════════════════════════
// MARK: - Executor output
// ════════════════════════════════════════════════════════════════

struct CostModInstall {
    let target: PlayExecContext.Side
    let delta: Int
    let scope: String
}

struct PlayExecOut {
    var selfDelta: Int = 0
    var oppDelta: Int = 0
    var selfHDDelta: Int = 0
    var oppHDDelta: Int = 0
    var draws: Int = 0
    var heroDraws: Int = 0
    var discards: Int = 0
    var protectSelf: Bool = false
    var cancelOpp: Bool = false
    var hasEffect: Bool = false
    var hasPersistent: Bool = false
    var unknownOps: [String] = []

    // Tier A intents
    var costModInstalls: [CostModInstall] = []
    var shuffleHandIntoDeck: Bool = false
    var shuffleDiscardToDeckCount: Int = 0
    var discardTopCount: Int = 0
    var discardHandAll: Bool = false
    /// B.12 — Rebuild / Return from the Depths use kind:"hero" to
    /// discard heroes from hand instead of plays. nil → legacy
    /// "plays" behavior; "hero" → strip heroes only.
    var discardHandAllKind: String? = nil
    var reclaimUsedPlayCount: Int = 0

    // Tier B/C intents
    var intents: [PlayIntent] = []
    var notifications: [String] = []

    // Reveal streams — used to drive the animated coin/dice overlay
    // in the practice UI. Each entry is one physical randomization:
    // a single coin flip (true = HEADS) or a single die roll (1–6).
    // Populated by `execCoinFlip` / `execDiceRoll`; the UI consumes
    // them to play a ~1s animation before the effect resolves in the
    // player's eyes.
    var coinFlips: [Bool] = []
    var diceRolls: [Int] = []
    /// "versus" (2 dice, side-by-side, high wins),
    /// "summed" (2+ dice, summed total — Lucky 7 etc.),
    /// "single" (default — one die OR one coin per slot).
    /// Used by the host to label the reveal overlay correctly.
    var revealMode: String = "single"
    /// Optional eyebrow text for the reveal overlay (e.g., the
    /// originating play card's name when known).
    var revealLabel: String = ""
}

// ════════════════════════════════════════════════════════════════
// MARK: - Executor
// ════════════════════════════════════════════════════════════════

enum PlayEffectExecutor {

    static func run(entry: [String: Any], ctx: PlayExecContext) -> PlayExecOut {
        var out = PlayExecOut()
        guard let effects = entry["effects"] as? [[String: Any]] else { return out }
        for step in effects {
            execStep(step, ctx: ctx, out: &out)
        }
        if let persistent = entry["persistent"] as? [[String: Any]], !persistent.isEmpty {
            out.hasPersistent = true
        }
        return out
    }

    // MARK: - Step dispatcher

    static func execStep(_ step: [String: Any], ctx: PlayExecContext, out: inout PlayExecOut) {
        // Branch: if / then / else
        if let cond = step["if"] as? [String: Any] {
            let pass = evalCondition(cond, ctx: ctx)
            let branch = pass ? step["then"] : step["else"]
            if let branch = branch as? [[String: Any]] {
                for s in branch { execStep(s, ctx: ctx, out: &out) }
            }
            return
        }
        // Choice / options: pick option with highest estimated self power and surface label
        if let options = (step["options"] ?? step["choice"]) as? [[String: Any]] {
            var bestScore = Int.min
            var bestEffects: [[String: Any]] = []
            var bestLabel: String? = nil
            for o in options {
                var probe = PlayExecOut()
                let effs = (o["effects"] as? [[String: Any]]) ?? []
                for s in effs { execStep(s, ctx: ctx, out: &probe) }
                let score = probe.selfDelta - probe.oppDelta + probe.selfHDDelta * 5
                if score > bestScore {
                    bestScore = score
                    bestEffects = effs
                    bestLabel = o["label"] as? String
                }
            }
            for s in bestEffects { execStep(s, ctx: ctx, out: &out) }
            if let label = bestLabel {
                out.notifications.append("Chose: \(label)")
                out.intents.append(.notify("Chose: \(label)"))
            }
            return
        }
        guard let op = step["op"] as? String else { return }

        switch op {
        case "power":
            let d = evalFormula(step["delta"], ctx: ctx)
            if (step["target"] as? String) == "opponent" { out.oppDelta += d } else { out.selfDelta += d }
            out.hasEffect = true

        case "power_set":
            let targetIsOpp = (step["target"] as? String) == "opponent"
            let card = targetIsOpp ? ctx.oppCard : ctx.selfCard
            let current = card?.power ?? 0
            var val = 0
            if let source = step["source"] as? [String: Any] {
                if let v = source["value"] as? Int { val = v }
                else {
                    let srcIsOpp = (source["target"] as? String) == "opponent"
                    let srcCard = srcIsOpp ? ctx.oppCard : ctx.selfCard
                    val = srcCard?.power ?? 0
                }
            }
            val += (step["offset"] as? Int) ?? 0
            let delta = val - current
            if targetIsOpp { out.oppDelta += delta } else { out.selfDelta += delta }
            out.hasEffect = true

        case "power_swap":
            let myP = ctx.selfCard?.power ?? 0
            let thP = ctx.oppCard?.power ?? 0
            out.selfDelta += thP - myP
            out.oppDelta  += myP - thP
            out.hasEffect = true

        case "power_double":
            let targetIsOpp = (step["target"] as? String) == "opponent"
            let card = targetIsOpp ? ctx.oppCard : ctx.selfCard
            let bonus = card?.power ?? 0
            if targetIsOpp { out.oppDelta += bonus } else { out.selfDelta += bonus }
            out.hasEffect = true

        case "power_steal":
            let amt = evalFormula(step["amount"], ctx: ctx)
            out.selfDelta += amt
            out.oppDelta  -= amt
            out.hasEffect = true

        case "power_cap_min":
            out.protectSelf = true
            out.hasEffect = true

        case "hd":
            let d = evalFormula(step["delta"], ctx: ctx)
            if (step["target"] as? String) == "opponent" { out.oppHDDelta += d } else { out.selfHDDelta += d }
            out.hasEffect = true

        case "hd_recover":
            // B.9 — `amount: "all"` recovers everything possible (host
            // clamps at 10). `from: "discard"` is informational only;
            // iOS doesn't track HDs as physical cards in a pile, so the
            // semantics are equivalent to a regular recover.
            let amt: Int
            if (step["amount"] as? String) == "all" {
                amt = 10  // clamped by applyHDRecover's min(10, ...)
            } else {
                amt = evalFormula(step["amount"], ctx: ctx)
            }
            if (step["target"] as? String) == "opponent" { out.oppHDDelta += amt } else { out.selfHDDelta += amt }
            out.hasEffect = true

        case "draw":
            let n = evalFormula(step["count"], ctx: ctx)
            if (step["kind"] as? String) == "hero" { out.heroDraws += n } else { out.draws += n }
            out.hasEffect = true

        case "discard":
            let n: Int
            if (step["count"] as? String) == "all" { n = 99 } else { n = evalFormula(step["count"], ctx: ctx) }
            out.discards += n
            ctx.counters.cardsDiscardedByThisPlay += n
            let mode = (step["mode"] as? String) ?? "auto"
            let kind = (step["kind"] as? String) ?? "play"
            let targetStr = (step["target"] as? String) ?? "self"
            // Resolve the side that needs to discard — `target: "self"`
            // is the actor; `target: "opponent"` is the other side.
            let discardSide: PlayExecContext.Side = targetStr == "opponent" ? ctx.opp : ctx.self_
            if kind == "play" {
                if mode == "choice" && discardSide == ctx.self_ {
                    // Player picks which plays to ditch (the actor
                    // chooses from their own hand).
                    out.intents.append(.chooseHandDiscard(side: discardSide, count: n))
                } else {
                    // Auto-pick (CPU, opponent-targeted, or non-choice
                    // mode). Host removes lowest-cost plays.
                    out.intents.append(.autoDiscardHand(side: discardSide, count: n))
                }
            }
            out.hasEffect = true

        case "coin_flip":
            execCoinFlip(step, ctx: ctx, out: &out)

        case "dice_roll":
            execDiceRoll(step, ctx: ctx, out: &out)

        case "compound_roll":
            execCompoundRoll(step, ctx: ctx, out: &out)

        case "dice_roll_again":
            // Re-roll while result is in while_match set. Accumulate (+/-) per provided step or
            // just notify number of extra rolls. Simpler impl: keep re-rolling and count.
            let whileMatch = (step["while_match"] as? [Int]) ?? [4,5,6]
            var extra = 0
            while extra < 10 {
                let r = Int.random(in: 1...6)
                if !whileMatch.contains(r) { break }
                extra += 1
            }
            if extra > 0 {
                out.notifications.append("Re-rolled \(extra) extra time\(extra == 1 ? "" : "s")")
            }
            out.hasEffect = true

        case "protect_self":
            out.protectSelf = true
            out.hasEffect = true

        case "cancel_opponent_plays", "cap_opponent_plays":
            // Both ops mean "opponent can't run plays this battle" —
            // route through the same installBlock infrastructure
            // block_plays uses, scoped to this_battle. The previous
            // implementation only set out.cancelOpp, which nothing
            // consumed (Flame Wall's effect was a silent no-op).
            // cap_opponent_plays is technically a soft cap (N plays
            // allowed), but the engine doesn't have a cap-N mechanism;
            // a hard block is the conservative fallback.
            out.intents.append(.installBlock(side: ctx.opp, kind: "block_plays", scope: "this_battle"))
            out.notifications.append(op == "cap_opponent_plays"
                ? "Opponent's play count capped this battle (treated as full block)"
                : "Opponent can't play any Plays this battle")
            out.hasEffect = true

        case "block_sub", "block_plays", "block_draw", "block_hd_recover":
            let scope = (step["scope"] as? String) ?? (step["duration"] as? String) ?? "this_battle"
            let targetStr = (step["target"] as? String) ?? "self"
            // Friendlier notification text — `op.replacing("_", " ")`
            // produced "block plays" which is grammar-broken UX. The
            // verb-phrase form below reads as a sentence and tells the
            // user *what* the block actually prevents.
            let actionPhrase: String
            switch op {
            case "block_plays":      actionPhrase = "play any Plays this battle"
            case "block_draw":       actionPhrase = "draw new Plays this battle"
            case "block_sub":        actionPhrase = "substitute this battle"
            case "block_hd_recover": actionPhrase = "recover Hot Dogs"
            default:                 actionPhrase = op.replacingOccurrences(of: "_", with: " ")
            }
            if targetStr == "both" {
                out.intents.append(.installBlock(side: .player, kind: op, scope: scope))
                out.intents.append(.installBlock(side: .cpu,    kind: op, scope: scope))
                out.notifications.append("Neither side can \(actionPhrase)")
            } else {
                let targetSide: PlayExecContext.Side = targetStr == "opponent" ? ctx.opp : ctx.self_
                out.intents.append(.installBlock(side: targetSide, kind: op, scope: scope))
                let who = targetSide == ctx.self_ ? "You" : "Opponent"
                let verb = who == "You" ? "can't" : "can't"
                out.notifications.append("\(who) \(verb) \(actionPhrase)")
            }
            out.hasEffect = true

        case "honors_set":
            let targetSide: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let scope = (step["scope"] as? String) ?? "next_battle"
            out.intents.append(.installHonors(side: targetSide, scope: scope))
            out.notifications.append("Honors → \(targetSide == .player ? "Player" : "CPU") (\(scope))")
            out.hasEffect = true

        case "substitute_free":
            let targetSide: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let scope = (step["scope"] as? String) ?? "next_battle"
            out.intents.append(.installSubstituteFree(side: targetSide, scope: scope))
            out.notifications.append("Free substitute (\(scope))")
            out.hasEffect = true

        case "variable_cost_bonus":
            let factor = (step["factor"] as? Int) ?? (step["per_hd"] as? Int) ?? 5
            let minCost = (step["min_cost"] as? Int) ?? 0
            let available = max(0, ctx.selfHD)
            let spend = max(minCost, min(available, 3))
            if spend > 0 {
                out.selfHDDelta -= spend
                out.selfDelta += factor * spend
                out.notifications.append("Spent \(spend) HD → +\(factor * spend) Power")
            }
            out.hasEffect = true

        case "add_previous_hero_delta":
            if ctx.battleIdx > 0, ctx.battles.indices.contains(ctx.battleIdx - 1) {
                let prev = ctx.battles[ctx.battleIdx - 1]
                let bonus = ctx.self_ == .player ? prev.playerEffectPower : prev.cpuEffectPower
                if (step["target"] as? String) == "opponent" { out.oppDelta += bonus } else { out.selfDelta += bonus }
            }
            out.hasEffect = true

        case "note":
            break

        // ── Tier A ops ────────────────────────────────────────────
        case "swap_hd_counts":
            out.selfHDDelta += (ctx.oppHD - ctx.selfHD)
            out.oppHDDelta  += (ctx.selfHD - ctx.oppHD)
            out.hasEffect = true

        case "play_cost_delta":
            let targetIsOpp = (step["target"] as? String) == "opponent"
            let target: PlayExecContext.Side = targetIsOpp ? ctx.opp : ctx.self_
            let delta = (step["delta"] as? Int) ?? 0
            let scope = (step["scope"] as? String) ?? "next_play_self"
            out.costModInstalls.append(CostModInstall(target: target, delta: delta, scope: scope))
            out.hasEffect = true

        case "shuffle_hand_into_deck":
            out.shuffleHandIntoDeck = true
            out.hasEffect = true

        case "shuffle_from_discard_to_deck":
            let n = (step["count"] as? Int) ?? -1
            out.shuffleDiscardToDeckCount = n
            out.hasEffect = true

        case "discard_top":
            let n = (step["count"] as? Int) ?? 1
            out.discardTopCount += n
            ctx.counters.cardsDiscardedByThisPlay += n
            out.hasEffect = true

        case "discard_hand_all":
            out.discardHandAll = true
            if let kind = step["kind"] as? String { out.discardHandAllKind = kind }
            // Update counter now so any same-execution power formula referencing
            // `cards_discarded_by_this_play` can read the correct value.
            ctx.counters.cardsDiscardedByThisPlay += ctx.selfHand.count
            out.hasEffect = true

        case "power_reset":
            if ctx.battles.indices.contains(ctx.battleIdx) {
                let b = ctx.battles[ctx.battleIdx]
                let selfEffect = ctx.self_ == .player ? b.playerEffectPower : b.cpuEffectPower
                let oppEffect  = ctx.self_ == .player ? b.cpuEffectPower    : b.playerEffectPower
                let t = step["target"] as? String
                let both = t == "both"
                let opp  = t == "opponent"
                if both || !opp { out.selfDelta -= selfEffect }
                if both || opp  { out.oppDelta  -= oppEffect }
            }
            out.hasEffect = true

        case "add_top_hero_power_to_self":
            if let top = ctx.selfHeroDeck.first {
                out.selfDelta += top.power ?? 0
            }
            out.hasEffect = true

        case "reclaim_used_play":
            out.reclaimUsedPlayCount += (step["count"] as? Int) ?? 1
            out.hasEffect = true

        // ── Tier B: Hero manipulation ────────────────────────────
        case "swap_active_with_hand":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.swapActiveWithHand(side: side))
            out.notifications.append("Swapped active hero with hand")
            out.hasEffect = true

        case "swap_active_with_discard":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let filter = step["weapon_filter"] as? String
            out.intents.append(.swapActiveWithDiscard(side: side, weaponFilter: filter))
            out.notifications.append("Swapped active with discard pile\(filter.map { " (filter: \($0))" } ?? "")")
            out.hasEffect = true

        case "swap_active_with_future_hero":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.swapActiveWithFutureHero(side: side))
            out.notifications.append("Swapped active with next battle's hero")
            out.hasEffect = true

        case "replace_active_with_top_hero_deck":
            let t = step["target"] as? String
            let sides: [PlayExecContext.Side] = t == "both" ? [ctx.self_, ctx.opp] : [t == "opponent" ? ctx.opp : ctx.self_]
            for s in sides { out.intents.append(.replaceActiveWithTopDeck(side: s)) }
            out.notifications.append("Replaced active hero from top of deck")
            out.hasEffect = true

        case "replace_next_with_top_hero_deck":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.replaceNextWithTopDeck(side: side))
            out.notifications.append("Replaced next battle's hero from top of deck")
            out.hasEffect = true

        case "replace_all_unrevealed_with_top_hero_deck":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.replaceAllUnrevealedWithTopDeck(side: side))
            out.notifications.append("Replaced all unrevealed heroes from deck")
            out.hasEffect = true

        case "replace_active_from_hand":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.replaceActiveFromHand(side: side))
            out.notifications.append("Replaced active hero from bench")
            out.hasEffect = true

        case "discard_hero":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let source = (step["source"] as? String) ?? "active"
            if source == "active" {
                out.intents.append(.discardActiveHero(side: side))
                out.notifications.append("Discarded active hero")
            } else {
                out.intents.append(.discardHeroFromHand(side: side))
                out.notifications.append("Discarded hero from hand")
            }
            out.hasEffect = true

        case "discard_hero_from_hand":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.discardHeroFromHand(side: side))
            out.notifications.append("Discarded hero from hand")
            out.hasEffect = true

        case "discard_revealed_hero", "discard_revealed":
            let t = step["target"] as? String
            let sides: [PlayExecContext.Side] = t == "both" ? [ctx.self_, ctx.opp] : [t == "opponent" ? ctx.opp : ctx.self_]
            for s in sides { out.intents.append(op == "discard_revealed_hero" ? .discardRevealedHero(side: s) : .discardRevealedPlay(side: s)) }
            out.notifications.append(op == "discard_revealed_hero" ? "Discarded revealed hero" : "Discarded revealed play")
            out.hasEffect = true

        case "transform_to_hot_dog":
            let tgt = step["target"] as? String
            let side: PlayExecContext.Side = tgt == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.transformActiveToHotDog(side: side))
            out.notifications.append("Active hero transformed → Hot Dog")
            out.hasEffect = true

        case "reveal_play_for_conditional_free":
            // Scare Tactics — host opens a hand-based chooser, then
            // installs a one-shot next-battle persistent gated on
            // opponent's play cost.
            out.intents.append(.revealForConditionalFree(side: ctx.self_))
            out.hasEffect = true

        case "player_choice":
            // Generic chooser: present `options[]` to the player.
            // Each option has a `label` and a list of `effects`.
            // CPU side picks `cpu_pick` (default 0). Player side
            // routes through the host's chooser sheet.
            let prompt = (step["prompt"] as? String) ?? "Choose one"
            guard let rawOptions = step["options"] as? [[String: Any]],
                  !rawOptions.isEmpty
            else {
                out.unknownOps.append("player_choice (no options)")
                return
            }
            let parsed: [PlayChoiceOption] = rawOptions.compactMap { o in
                guard let label = o["label"] as? String else { return nil }
                let effects = (o["effects"] as? [[String: Any]]) ?? []
                return PlayChoiceOption(label: label, effects: effects)
            }
            let cpuPick = (step["cpu_pick"] as? Int) ?? 0
            out.intents.append(.presentPlayerChoice(
                side: ctx.self_,
                prompt: prompt,
                options: parsed,
                cpuPick: cpuPick
            ))
            out.hasEffect = true

        case "install_persistent":
            // A persistent's `effect` can call this op to install a
            // CHILD persistent at fire time. Used for "next-battle
            // delivery" patterns: a parent installs at on_battle_win
            // (rest_of_game), then per-win it installs a one-shot
            // child scoped to next_battle that delivers the actual
            // power/HD effect. Without this op, you can't express
            // "after I win, +5 next battle."
            if let spec = step["spec"] as? [String: Any] {
                out.intents.append(.installPersistent(owner: ctx.self_, spec: spec))
                out.notifications.append("Installed follow-up effect")
            }
            out.hasEffect = true

        case "mark_future_battle":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let onReveal = (step["on_reveal_effects"] as? [[String: Any]]) ?? []
            // Selector controls how the target battle is picked.
            // "unrevealed_hero_player_pick" → host opens a chooser
            // (Delayed Recovery: "Choose one of your unrevealed
            // Heroes"). Default / unknown / opponent side → random
            // unrevealed pick.
            let selector = (step["selector"] as? String) ?? "random"
            out.intents.append(.markFutureBattle(side: side, onReveal: onReveal, selector: selector))
            out.notifications.append("Marked a future battle")
            out.hasEffect = true

        case "force_substitute":
            let target: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let cost = (step["cost"] as? Int) ?? 2
            out.intents.append(.forceSubstitute(target: target, cost: cost))
            out.notifications.append("Forced substitute (cost \(cost) HD)")
            out.hasEffect = true

        // ── Tier B/C: Reveal / peek / search / copy ───────────────
        case "reveal_top_hero_deck":
            let t = step["target"] as? String
            let count = (step["count"] as? Int) ?? 1
            let sides: [PlayExecContext.Side] = t == "both" ? [ctx.self_, ctx.opp] : [t == "opponent" ? ctx.opp : ctx.self_]
            for s in sides { out.intents.append(.peekHeroDeck(side: s, count: count)) }
            out.hasEffect = true

        case "peek_unrevealed_hero":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let selector = (step["selector"] as? String) ?? "self_next_battle"
            out.intents.append(.peekUnrevealedHero(side: side, selector: selector))
            out.hasEffect = true

        case "reorder_unrevealed_heroes":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.reorderUnrevealedHeroes(side: side))
            out.notifications.append("Reordered unrevealed heroes")
            out.hasEffect = true

        case "reveal":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let kind = (step["kind"] as? String) ?? "hero"
            let count = (step["count"] as? Int) ?? 1
            let choose = (step["choose"] as? Int) ?? 0
            if kind == "hero" {
                out.intents.append(.revealTopHeroes(side: side, count: count, choose: choose))
            } else {
                out.intents.append(.revealTopPlays(side: side, count: count, andPlayFree: false))
            }
            out.hasEffect = true

        case "reveal_top":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let count = (step["count"] as? Int) ?? 1
            let kind = (step["kind"] as? String) ?? "play"
            if kind == "play" {
                out.intents.append(.revealTopPlays(side: side, count: count, andPlayFree: false))
            } else {
                out.intents.append(.peekHeroDeck(side: side, count: count))
            }
            out.hasEffect = true

        case "peek_and_reorder_top":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let count = (step["count"] as? Int) ?? 3
            out.intents.append(.revealTopPlays(side: side, count: count, andPlayFree: false))
            out.notifications.append("Peeked + reordered top \(count) plays")
            out.hasEffect = true

        case "reveal_top_reorder_or_bottom":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let count = (step["count"] as? Int) ?? 2
            out.intents.append(.revealTopPlays(side: side, count: count, andPlayFree: false))
            out.notifications.append("Peeked opponent's top \(count) plays")
            out.hasEffect = true

        case "shuffle_revealed_back":
            out.notifications.append("Shuffled revealed plays back into deck")
            out.hasEffect = true

        case "force_reveal_from_hand":
            let target: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let count = (step["count"] as? Int) ?? 1
            out.intents.append(.peekOpponentHand(side: ctx.self_, count: count, mode: "chooser"))
            out.notifications.append("Forced \(target == .player ? "you" : "opponent") to reveal \(count) play\(count == 1 ? "" : "s")")
            out.hasEffect = true

        case "peek_opponent_hand":
            let side = ctx.self_
            let count = (step["count"] as? Int) ?? 1
            let mode = (step["mode"] as? String) ?? "random"
            out.intents.append(.peekOpponentHand(side: side, count: count, mode: mode))
            out.hasEffect = true

        case "search":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let filter = (step["filter"] as? [String: Any]) ?? [:]
            let action = (step["action"] as? String) ?? "play_free"
            out.intents.append(.searchPlaybook(side: side, filter: filter, action: action))
            out.notifications.append("Searched Playbook (\(action))")
            out.hasEffect = true

        case "copy_last_play":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.copyLastPlay(side: side))
            out.notifications.append("Copied last play")
            out.hasEffect = true

        case "play_revealed_free":
            let side: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.playRevealedFree(side: side))
            out.notifications.append("Played revealed card free")
            out.hasEffect = true

        case "play_top_of_playbook_free":
            let targetHint = (step["target"] as? String) ?? "winner"
            out.intents.append(.playTopOfPlaybookFree(targetHint: targetHint))
            out.notifications.append("\(targetHint.capitalized) plays top of Playbook free")
            out.hasEffect = true

        case "versus_dice_roll":
            out.revealMode = "versus"
            out.revealLabel = "VERSUS ROLL"
            // Both sides roll a single die; winner runs `winner_effect`.
            // Tie → no-op (re-roll deferred for now). Both rolls land
            // in `out.diceRolls` so the existing dice-reveal overlay
            // animates them side-by-side. When the OPPONENT wins, the
            // winner_effect still runs but with `target` swapped via
            // a synthetic `target: "opponent"` rewrite — that way
            // play_top_of_playbook_free fires for the right seat.
            let selfRoll = Int.random(in: 1...6)
            let oppRoll  = Int.random(in: 1...6)
            out.diceRolls.append(contentsOf: [selfRoll, oppRoll])
            let selfWins = selfRoll > oppRoll
            let tied     = selfRoll == oppRoll
            let outcome: String = tied
                ? "TIE — no effect"
                : (selfWins ? "YOU WIN the roll" : "OPPONENT WINS the roll")
            out.notifications.append("Versus roll: you \(selfRoll), opponent \(oppRoll) — \(outcome)")
            if !tied, let winnerEffects = step["winner_effect"] as? [[String: Any]] {
                for effect in winnerEffects {
                    var rewritten = effect
                    if selfWins {
                        // Already self-perspective; rewrite "winner" → "self"
                        if (rewritten["target"] as? String) == "winner" {
                            rewritten["target"] = "self"
                        }
                    } else {
                        // Opponent wins; rewrite "winner" → "opponent"
                        if (rewritten["target"] as? String) == "winner" {
                            rewritten["target"] = "opponent"
                        } else if (rewritten["target"] as? String) == "self" {
                            rewritten["target"] = "opponent"
                        }
                    }
                    execStep(rewritten, ctx: ctx, out: &out)
                }
            }
            out.hasEffect = true

        case "discard_other_revealed":
            out.notifications.append("Discarded other revealed cards")
            out.hasEffect = true

        case "deploy_chosen_revealed":
            out.notifications.append("Deployed chosen revealed hero")
            out.hasEffect = true

        case "add_chosen_revealed_to_hand_discard_rest":
            // Real implementation: emit an intent that actually moves
            // cards from the playbook deck to hand/discard. Auto-picks
            // the best card (highest cost for plays, highest power for
            // heroes) since the player chooser sheet for top-of-deck
            // picks isn't built. Computes the auto-chosen card cost
            // immediately and stashes it on counters so any downstream
            // conditional in the same effects[] array reads the
            // truthful value via the `chosen_play_cost` metric.
            let kind = (step["kind"] as? String) ?? "play"
            let count = (step["count"] as? Int) ?? 3
            // Predict the auto-pick so chosen_play_cost works at
            // exec time (the actual state mutation happens later in
            // applyIntent).
            if kind == "play" {
                let topN = Array(ctx.selfPlayDeck.prefix(count))
                let best = topN.max(by: { ($0.playCost ?? 0) < ($1.playCost ?? 0) })
                ctx.counters.chosenPlayCost = best?.playCost ?? 0
            }
            out.intents.append(.chooseTopAndKeepBest(side: ctx.self_, kind: kind, count: count))
            out.notifications.append("Picked best of top \(count) from \(kind == "hero" ? "hero deck" : "playbook")")
            out.hasEffect = true

        case "name_and_discard":
            let target: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            out.intents.append(.nameAndDiscard(target: target))
            ctx.counters.cardsDiscardedByThisPlay += 1
            out.hasEffect = true

        // ── Tier C: Complex specials ──────────────────────────────
        case "mirror_power_effects_to_opponent":
            // Copy self's current effect power deltas onto opponent (this battle only).
            if ctx.battles.indices.contains(ctx.battleIdx) {
                let b = ctx.battles[ctx.battleIdx]
                let selfEff = ctx.self_ == .player ? b.playerEffectPower : b.cpuEffectPower
                out.oppDelta += selfEff
                out.notifications.append("Mirrored \(selfEff) power to opponent")
            }
            out.intents.append(.mirrorPowerEffects(fromSide: ctx.self_, toSide: ctx.opp))
            out.hasEffect = true

        case "flip_opponent_debuffs":
            // Convert current negative self effect power into positive bonus.
            if ctx.battles.indices.contains(ctx.battleIdx) {
                let b = ctx.battles[ctx.battleIdx]
                let selfEff = ctx.self_ == .player ? b.playerEffectPower : b.cpuEffectPower
                if selfEff < 0 {
                    out.selfDelta += (-selfEff * 2)
                    out.notifications.append("Flipped \(selfEff) debuff → +\(-selfEff) bonus")
                }
            }
            out.intents.append(.flipOpponentDebuffs(side: ctx.self_))
            out.hasEffect = true

        case "cancel_persistent":
            let target = (step["target"] as? String) ?? "opponent"
            out.intents.append(.cancelPersistents(target: target))
            out.notifications.append("Canceled persistent effects (\(target))")
            out.hasEffect = true

        case "persistent_delta":
            // Wrap as a persistent install
            let spec = step
            out.intents.append(.installPersistent(owner: ctx.self_, spec: spec))
            out.hasEffect = true

        case "tax_per_hero_in_hand":
            let target: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            var perHDCost = 0
            if let per = step["per_hero_cost"] as? [String: Any],
               let delta = per["delta"] as? Int {
                perHDCost = delta
            }
            var fallbackDiscards = 0
            if let fb = step["fallback"] as? [String: Any],
               (fb["op"] as? String) == "discard",
               let count = fb["count"] as? Int {
                fallbackDiscards = count
            }
            out.intents.append(.taxPerHeroInHand(target: target, perHDCost: perHDCost, fallbackDiscards: fallbackDiscards))
            out.hasEffect = true

        case "transfer_sub_cost":
            let target: PlayExecContext.Side = (step["target"] as? String) == "opponent" ? ctx.opp : ctx.self_
            let amount = (step["amount"] as? Int) ?? 2
            out.intents.append(.transferSubCost(target: target, amount: amount))
            out.notifications.append("Paying next sub for \(target == .player ? "player" : "opponent")")
            out.hasEffect = true

        case "end_battle_by_power":
            out.intents.append(.endBattleByPower)
            out.notifications.append("Battle ended immediately by current power")
            out.hasEffect = true

        case "weapon_debuff_or_penalty":
            // Auto-pick opp weapon → if match, apply if_match; else penalty applies
            let oppWeapon = ctx.weapon(of: ctx.oppCard, as: ctx.opp)
            if !oppWeapon.isEmpty,
               let ifMatch = step["if_match"] as? [String: Any] {
                execStep(ifMatch, ctx: ctx, out: &out)
                out.notifications.append("Named weapon matched")
            } else if let elseStep = step["else"] as? [String: Any] {
                execStep(elseStep, ctx: ctx, out: &out)
                out.notifications.append("Named weapon missed — penalty")
            }
            out.hasEffect = true

        default:
            out.unknownOps.append(op)
        }
    }

    // MARK: - Coin / dice

    private static func execCoinFlip(_ step: [String: Any], ctx: PlayExecContext, out: inout PlayExecOut) {
        let times = (step["times"] as? Int) ?? 1
        var results: [Bool] = []
        for _ in 0..<times { results.append(Bool.random()) }
        out.coinFlips.append(contentsOf: results)
        let heads = results.filter { $0 }.count
        let tails = times - heads

        if heads > 0, let headsArr = step["heads"] as? [[String: Any]] {
            for _ in 0..<heads { for s in headsArr { execStep(s, ctx: ctx, out: &out) } }
        }
        if tails > 0, let tailsArr = step["tails"] as? [[String: Any]] {
            for _ in 0..<tails { for s in tailsArr { execStep(s, ctx: ctx, out: &out) } }
        }
        if let branches = step["branches"] as? [[String: Any]] {
            for br in branches {
                let ag = br["aggregate"] as? String
                var fire = false
                var repeats = 1
                switch ag {
                case "all_heads":          fire = heads == times
                case "all_tails":          fire = tails == times
                case "at_least_n_heads":
                    let n = (br["n"] as? Int) ?? (step["n"] as? Int) ?? 1
                    fire = heads >= n
                case "at_least_n_tails":
                    let n = (br["n"] as? Int) ?? (step["n"] as? Int) ?? 1
                    fire = tails >= n
                case "exact_heads":
                    let n = (br["n"] as? Int) ?? (step["n"] as? Int) ?? 0
                    fire = heads == n
                case "per_head":           fire = heads > 0; repeats = heads
                case "per_tail":           fire = tails > 0; repeats = tails
                default:
                    if let on = br["on"] as? [Int] { fire = on.contains(heads) }
                }
                if fire, let then = br["then"] as? [[String: Any]] {
                    for _ in 0..<repeats { for s in then { execStep(s, ctx: ctx, out: &out) } }
                }
            }
        }
        if let ag = step["aggregate"] as? String {
            var fire = false
            switch ag {
            case "all_heads":          fire = heads == times
            case "all_tails":          fire = tails == times
            case "at_least_n_heads":   fire = heads >= ((step["n"] as? Int) ?? 1)
            case "at_least_n_tails":   fire = tails >= ((step["n"] as? Int) ?? 1)
            case "exact_heads":        fire = heads == ((step["n"] as? Int) ?? 0)
            default: break
            }
            let branch = fire ? (step["then"] as? [[String: Any]]) : (step["else"] as? [[String: Any]])
            if let branch = branch { for s in branch { execStep(s, ctx: ctx, out: &out) } }
        }
        // Visual reveal — emoji + sequence so coaches see WHICH faces
        // came up, not just the aggregate count. "🪙 HEADS · TAILS · HEADS"
        // is more diagnostic than "2 heads / 1 tails."
        let faces = results.map { $0 ? "HEADS" : "TAILS" }
        let glyphs = String(repeating: "🪙", count: results.count)
        out.notifications.append("\(glyphs) \(faces.joined(separator: " · "))")
        out.hasEffect = true
    }

    private static func execDiceRoll(_ step: [String: Any], ctx: PlayExecContext, out: inout PlayExecOut) {
        let count = (step["count"] as? Int) ?? 1
        var rolls: [Int] = []
        for _ in 0..<count { rolls.append(Int.random(in: 1...6)) }
        out.diceRolls.append(contentsOf: rolls)
        let sum = rolls.reduce(0, +)
        let agg = (step["aggregate"] as? String) ?? (count > 1 ? "sum" : "")
        let matchValue = agg == "sum" ? sum : (rolls.first ?? 0)
        // Tag the reveal mode so the overlay can render two dice as
        // "DIE 1 + DIE 2 = SUM N" for summed rolls (Lucky 7) vs as
        // distinct dice for any other multi-die count.
        if count > 1 && out.revealMode == "single" {
            out.revealMode = agg == "sum" ? "summed" : "single"
        }

        // Track whether ANY branch (or the else branch) actually
        // produced a triggered effect — used to surface a clear
        // "no power added" notification when the roll missed and
        // the else branch is empty (Fire Roll, Ice Roll, etc.).
        var matched = false
        var elseFiredAndEmpty = false
        if let branches = step["branches"] as? [[String: Any]] {
            var elseBranch: [[String: Any]]? = nil
            for br in branches {
                if let onStr = br["on"] as? String, onStr == "else" {
                    elseBranch = br["then"] as? [[String: Any]]
                    continue
                }
                if let on = br["on"] as? [Int], on.contains(matchValue),
                   let then = br["then"] as? [[String: Any]] {
                    matched = true
                    for s in then { execStep(s, ctx: ctx, out: &out) }
                }
            }
            if !matched, let elseBranch = elseBranch {
                if elseBranch.isEmpty { elseFiredAndEmpty = true }
                for s in elseBranch { execStep(s, ctx: ctx, out: &out) }
            } else if !matched {
                elseFiredAndEmpty = true
            }
        }
        if step["on_match"] != nil || step["on_miss"] != nil {
            let branchAny: Any? = (Double.random(in: 0..<1) < 1.0/6.0) ? step["on_match"] : step["on_miss"]
            if let branch = branchAny as? [[String: Any]] {
                for s in branch { execStep(s, ctx: ctx, out: &out) }
            }
        }
        // Visual reveal — die-face emoji per roll so coaches see the
        // actual values, not just the aggregate. "🎲 4 · 6 (sum 10)"
        let dieFaces = ["⚀","⚁","⚂","⚃","⚄","⚅"]
        let pretty = rolls.map { r in (r >= 1 && r <= 6) ? dieFaces[r-1] + " " + String(r) : String(r) }
        let line = rolls.count > 1
            ? "🎲 \(pretty.joined(separator: " · ")) (sum \(sum))"
            : "🎲 \(pretty.first ?? "")"
        out.notifications.append(line)
        // When the roll didn't trigger any branch (and the else branch
        // was empty or absent), explicitly state that no effect fired
        // — otherwise the user just sees the dice glyph with no
        // explanation of why their power didn't change. This is the
        // Fire Roll / Ice Roll / etc. failed-roll case.
        if elseFiredAndEmpty {
            out.notifications.append("Roll didn't trigger any effect")
        }
        out.hasEffect = true
    }

    private static func execCompoundRoll(_ step: [String: Any], ctx: PlayExecContext, out: inout PlayExecOut) {
        guard let components = step["components"] as? [[String: Any]] else { return }
        var coinHeads: Bool? = nil
        var dieVal: Int? = nil
        for comp in components {
            let op = comp["op"] as? String
            if op == "coin_flip" {
                let r = Bool.random()
                coinHeads = r
                out.coinFlips.append(r)
            } else if op == "dice_roll" {
                let r = Int.random(in: 1...6)
                dieVal = r
                out.diceRolls.append(r)
            }
        }
        guard let branches = step["branches"] as? [[String: Any]] else { return }
        for br in branches {
            let matchObj = br["match"]
            var fire = false
            if let m = matchObj as? String, m == "otherwise" {
                // handled below if no other branch fires — skip for now
                continue
            }
            if let m = matchObj as? [String: Any] {
                var ok = true
                if let want = m["coin"] as? String {
                    let got = coinHeads == true ? "heads" : "tails"
                    if got != want { ok = false }
                }
                if let range = m["die_range"] as? [Int], range.count == 2, let d = dieVal {
                    if !(d >= range[0] && d <= range[1]) { ok = false }
                }
                fire = ok
            }
            if fire, let effects = br["effect"] as? [[String: Any]] {
                for s in effects { execStep(s, ctx: ctx, out: &out) }
                out.hasEffect = true
                out.notifications.append("Compound roll → branch matched")
                return
            }
        }
        // fallback: otherwise
        for br in branches {
            if let m = br["match"] as? String, m == "otherwise",
               let effects = br["effect"] as? [[String: Any]] {
                for s in effects { execStep(s, ctx: ctx, out: &out) }
                out.notifications.append("Compound roll → otherwise")
                break
            }
        }
        out.hasEffect = true
    }

    // MARK: - Conditions

    static func evalCondition(_ cond: [String: Any], ctx: PlayExecContext) -> Bool {
        let type = (cond["type"] as? String) ?? ""
        let target = (cond["target"] as? String) ?? "self"
        let selfView = target == "self"
        let card = selfView ? ctx.selfCard : ctx.oppCard

        // Helper closures — compute the controller (which seat owns a
        // given card) so `ctx.weapon(of:as:)` applies the right
        // transform targeting. Heroes in `selfHand` / `selfCard` /
        // `selfHeroDeck` all belong to ctx.self_; opp-side heroes
        // belong to ctx.opp.
        let selfSide = ctx.self_
        let oppSide  = ctx.opp

        switch type {
        case "weapon":
            let controller = selfView ? selfSide : oppSide
            return ctx.weapon(of: card, as: controller) == (cond["weapon"] as? String)

        case "weapon_same":
            if (cond["between"] as? String) == "self_opp" {
                return ctx.weapon(of: ctx.selfCard, as: selfSide)
                    == ctx.weapon(of: ctx.oppCard,  as: oppSide)
            }
            return false

        case "weapon_different":
            if (cond["between"] as? String) == "self_opp" {
                return ctx.weapon(of: ctx.selfCard, as: selfSide)
                    != ctx.weapon(of: ctx.oppCard,  as: oppSide)
            }
            return false

        case "weapon_streak":
            // Check last N battles (by heroes revealed) share same weapon as weapon_ref
            let length = (cond["length"] as? Int) ?? 2
            let ref = (cond["weapon_ref"] as? String) ?? "current_hero"
            var refWeapon: String? = nil
            if ref == "current_hero" {
                let card = selfView ? ctx.selfCard : ctx.oppCard
                let controller = selfView ? selfSide : oppSide
                let w = ctx.weapon(of: card, as: controller)
                refWeapon = w.isEmpty ? nil : w
            }
            guard let w = refWeapon else { return false }
            var matched = 0
            var i = ctx.battleIdx - 1
            while i >= 0 && matched < length {
                guard ctx.battles.indices.contains(i) else { break }
                let slot = ctx.battles[i]
                let heroSide: PlayExecContext.Side = selfView ? selfSide : oppSide
                let hero: Card? = heroSide == .player ? slot.playerCard : slot.cpuCard
                if ctx.weapon(of: hero, as: heroSide) == w { matched += 1 } else { break }
                i -= 1
            }
            return matched >= length

        case "previous_two_heroes_share_weapon":
            guard ctx.battleIdx >= 2 else { return false }
            let b1 = ctx.battles[ctx.battleIdx - 1]
            let b2 = ctx.battles[ctx.battleIdx - 2]
            let side: PlayExecContext.Side = selfView ? selfSide : oppSide
            let h1: Card? = side == .player ? b1.playerCard : b1.cpuCard
            let h2: Card? = side == .player ? b2.playerCard : b2.cpuCard
            let w1 = ctx.weapon(of: h1, as: side)
            let w2 = ctx.weapon(of: h2, as: side)
            return !w1.isEmpty && w1 == w2

        case "previous_and_current_share_weapon":
            guard ctx.battleIdx >= 1 else { return false }
            let cur = ctx.selfCard
            let prev = ctx.battles[ctx.battleIdx - 1]
            let side: PlayExecContext.Side = selfView ? selfSide : oppSide
            let prevHero: Card? = side == .player ? prev.playerCard : prev.cpuCard
            let curW  = ctx.weapon(of: cur,      as: side)
            let prevW = ctx.weapon(of: prevHero, as: side)
            return !curW.isEmpty && curW == prevW

        case "opponent_played_weapon_match":
            let ref = (cond["weapon_ref"] as? String) ?? "self_current_hero"
            let selfW = ctx.weapon(of: ctx.selfCard, as: selfSide)
            let refWeapon: String? = ref == "self_current_hero"
                ? (selfW.isEmpty ? nil : selfW)
                : nil
            guard let w = refWeapon,
                  ctx.battles.indices.contains(ctx.battleIdx) else { return false }
            let b = ctx.battles[ctx.battleIdx]
            let oppPlays = selfSide == .player ? b.cpuPlayedCards : b.playerPlayedCards
            return oppPlays.contains { $0.element == w }   // Play cards have no weapon transform; their `element` is stable.

        case "next_hero_power_gt":
            let side: PlayExecContext.Side = target == "opponent" ? ctx.opp : ctx.self_
            let nextIdx = ctx.battleIdx + 1
            guard ctx.battles.indices.contains(nextIdx) else { return false }
            let slot = ctx.battles[nextIdx]
            let card: Card? = side == .player ? slot.playerCard : slot.cpuCard
            guard let v = cond["value"] as? Int else { return false }
            return (card?.power ?? 0) > v

        case "next_hero_weapon_equals":
            let side: PlayExecContext.Side = target == "opponent" ? ctx.opp : ctx.self_
            let nextIdx = ctx.battleIdx + 1
            guard ctx.battles.indices.contains(nextIdx) else { return false }
            let slot = ctx.battles[nextIdx]
            let card: Card? = side == .player ? slot.playerCard : slot.cpuCard
            let want = cond["weapon"] as? String
            if want == "player_named" {
                return true
            }
            return ctx.weapon(of: card, as: side) == want

        case "hd_count":
            let v = selfView ? ctx.selfHD : ctx.oppHD
            return cmp(v, cond["comparison"] as? String, cond["value"] as? Int)

        case "hd_count_compare":
            // self vs opp comparison
            let c = cond["comparison"] as? String
            switch c {
            case "opp_gt_self":  return ctx.oppHD > ctx.selfHD
            case "self_gt_opp":  return ctx.selfHD > ctx.oppHD
            case "opp_lt_self":  return ctx.oppHD < ctx.selfHD
            case "self_lt_opp":  return ctx.selfHD < ctx.oppHD
            case "eq":           return ctx.selfHD == ctx.oppHD
            default:             return false
            }

        case "hand_count":
            let v = selfView ? ctx.selfHand.count : 0
            return cmp(v, cond["comparison"] as? String, cond["value"] as? Int)

        case "hand_count_compare":
            let c = cond["comparison"] as? String
            let selfCt = ctx.selfHand.count
            switch c {
            case "opp_gt_self":  return 0 > selfCt  // opp hand unknown; assume not
            case "self_gt_opp":  return selfCt > 0
            default:             return false
            }

        case "discard_count":
            let pile = selfView ? ctx.selfDiscard : []
            let kind = cond["kind"] as? String
            let count: Int
            switch kind {
            case "hero":    count = pile.filter { $0.cardType == "Hero" }.count
            case "play":    count = pile.filter { $0.cardType == "Play" }.count
            case "hot_dog": count = pile.filter { $0.cardType == "HotDog" }.count
            default:        count = pile.count
            }
            return cmp(count, cond["comparison"] as? String, cond["value"] as? Int)

        case "discarded_hero_weapon_matches_active":
            let pile = selfView ? ctx.selfDiscard : []
            let activeSide: PlayExecContext.Side = selfView ? ctx.self_ : ctx.opp
            let activeW = ctx.weapon(of: ctx.selfCard, as: activeSide)
            guard !activeW.isEmpty else { return false }
            return pile.contains {
                $0.cardType == "Hero" && ctx.weapon(of: $0, as: activeSide) == activeW
            }

        case "plays_used":
            // Honor `scope`. Default is "this_battle" for back-compat.
            // No Huddle ("If you ran a Play in the previous Battle…")
            // explicitly sets scope: "prev_battle" — without honoring
            // it the condition trivially evaluates against THIS
            // battle's count (often non-zero by the time the card
            // resolves) and the +15 fires every battle.
            let scope = (cond["scope"] as? String) ?? "this_battle"
            let count: Int
            switch scope {
            case "prev_battle":
                guard ctx.battleIdx > 0,
                      ctx.battles.indices.contains(ctx.battleIdx - 1) else { return false }
                let prev = ctx.battles[ctx.battleIdx - 1]
                let plays = selfView
                    ? (ctx.self_ == .player ? prev.playerPlayedCards : prev.cpuPlayedCards)
                    : (ctx.self_ == .player ? prev.cpuPlayedCards : prev.playerPlayedCards)
                count = plays.count
            default:
                count = selfView ? ctx.playsUsedThisBattle : 0
            }
            return cmp(count, cond["comparison"] as? String, cond["value"] as? Int)

        case "power_threshold":
            let p = card?.power ?? 0
            return cmp(p, cond["comparison"] as? String, cond["value"] as? Int)

        case "battle_num":
            return cmp(ctx.battleIdx + 1, cond["comparison"] as? String, cond["value"] as? Int)

        case "battles_won":
            let v = selfView ? ctx.selfWon : ctx.selfLost
            return cmp(v, cond["comparison"] as? String, cond["value"] as? Int)

        case "battles_lost":
            let v = selfView ? ctx.selfLost : ctx.selfWon
            return cmp(v, cond["comparison"] as? String, cond["value"] as? Int)

        case "battle_won_nth":
            // Did this side win the nth battle?
            guard let n = cond["n"] as? Int, n >= 1, ctx.battles.indices.contains(n - 1) else { return false }
            let r = ctx.battles[n - 1].result
            let won = (ctx.self_ == .player && r == .win) || (ctx.self_ == .cpu && r == .lose)
            return won

        case "battles_won_streak":
            // Count trailing wins up to current battle
            var streak = 0
            var i = ctx.battleIdx - 1
            while i >= 0 {
                guard ctx.battles.indices.contains(i) else { break }
                let r = ctx.battles[i].result
                let won = (ctx.self_ == .player && r == .win) || (ctx.self_ == .cpu && r == .lose)
                if won { streak += 1; i -= 1 } else { break }
            }
            return cmp(streak, cond["comparison"] as? String, cond["value"] as? Int)

        case "battles_lost_first_n":
            guard let n = cond["n"] as? Int, n >= 1 else { return false }
            var lost = 0
            for i in 0..<min(n, ctx.battleIdx) {
                guard ctx.battles.indices.contains(i) else { break }
                let r = ctx.battles[i].result
                let isLost = (ctx.self_ == .player && r == .lose) || (ctx.self_ == .cpu && r == .win)
                if isLost { lost += 1 }
            }
            return lost >= n

        case "battle_tied":
            guard ctx.battles.indices.contains(ctx.battleIdx) else { return false }
            let slot = ctx.battles[ctx.battleIdx]
            let pp = (slot.playerCard?.power ?? 0) + slot.playerEffectPower
            let cp = (slot.cpuCard?.power ?? 0) + slot.cpuEffectPower
            return pp == cp

        case "battle_winning":
            let pp = ctx.selfCard?.power ?? 0
            let cp = ctx.oppCard?.power ?? 0
            return pp > cp

        case "battle_losing":
            let pp = ctx.selfCard?.power ?? 0
            let cp = ctx.oppCard?.power ?? 0
            return pp < cp

        case "prev_battle":
            guard ctx.battleIdx > 0, ctx.battles.indices.contains(ctx.battleIdx - 1) else { return false }
            let r = ctx.battles[ctx.battleIdx - 1].result
            let result = cond["result"] as? String
            let won = (ctx.self_ == .player && r == .win) || (ctx.self_ == .cpu && r == .lose)
            let lost = (ctx.self_ == .player && r == .lose) || (ctx.self_ == .cpu && r == .win)
            switch result {
            case "won":  return won
            case "lost": return lost
            case "tied": return r == .tie
            default:     return false
            }

        case "substituted_this_battle":
            return selfView ? ctx.selfSubstituted : false

        case "honors":
            return ctx.honors == (ctx.self_ == .player ? "player" : "cpu")

        case "hero_name":
            if let want = cond["equals"] as? String {
                return card?.name == want || card?.hero == want
            }
            return false

        case "metric_compare":
            let l = cond["left"].map { evalFormula($0, ctx: ctx) } ?? 0
            let r = cond["right"].map { evalFormula($0, ctx: ctx) } ?? 0
            return cmp(l, cond["comparison"] as? String, r)

        case "all":
            guard let arr = cond["of"] as? [[String: Any]] else { return false }
            return arr.allSatisfy { evalCondition($0, ctx: ctx) }

        case "any":
            guard let arr = cond["of"] as? [[String: Any]] else { return false }
            return arr.contains { evalCondition($0, ctx: ctx) }

        case "not":
            guard let inner = cond["cond"] as? [String: Any] else { return false }
            return !evalCondition(inner, ctx: ctx)

        default:
            return false
        }
    }

    private static func cmp(_ v: Int, _ comparison: String?, _ target: Int?) -> Bool {
        guard let target = target else { return false }
        switch comparison {
        case "gte": return v >= target
        case "gt":  return v >  target
        case "lte": return v <= target
        case "lt":  return v <  target
        case "eq":  return v == target
        case "neq": return v != target
        default:    return false
        }
    }

    // MARK: - Formula / metric

    static func evalFormula(_ val: Any?, ctx: PlayExecContext) -> Int {
        guard let val = val else { return 0 }
        if let n = val as? Int { return n }
        if let d = val as? Double { return Int(d) }
        guard let obj = val as? [String: Any] else { return 0 }
        if let v = obj["value"] as? Int { return v }

        // B.3 nested-formula shape: {formula, left, right} for
        // multiply/min/max/add/sub. The `metric` field may be a nested
        // {type, target, ...} dict instead of a bare string; we route
        // it through evalMetric regardless.
        if let kind = obj["formula"] as? String {
            let l = evalFormula(obj["left"],  ctx: ctx)
            let r = evalFormula(obj["right"], ctx: ctx)
            switch kind {
            case "min":      return min(l, r)
            case "max":      return max(l, r)
            case "add":      return l + r
            case "sub":      return l - r
            case "multiply":
                // Back-compat: multiply may appear as either a binary
                // {left, right} or the older flat {factor, metric}
                // shape. Prefer the flat shape when `factor`/`metric`
                // are present.
                if obj["factor"] != nil || obj["metric"] != nil {
                    let factor = (obj["factor"] as? Int) ?? 1
                    let m = evalMetricAny(obj["metric"], args: obj, ctx: ctx)
                    let offset = (obj["offset"] as? Int) ?? 0
                    var result = factor * m + offset
                    if let minV = obj["min"] as? Int { result = Swift.max(minV, result) }
                    if let maxV = obj["max"] as? Int { result = Swift.min(maxV, result) }
                    return result
                }
                return l * r
            default:
                return 0
            }
        }

        // Flat shape: {factor, metric, offset?, min?, max?}
        let factor = (obj["factor"] as? Int) ?? 1
        let offset = (obj["offset"] as? Int) ?? 0
        let m = evalMetricAny(obj["metric"], args: obj, ctx: ctx)
        var result = factor * m + offset
        if let minV = obj["min"] as? Int { result = max(minV, result) }
        if let maxV = obj["max"] as? Int { result = min(maxV, result) }
        return result
    }

    /// Metric dispatcher that accepts either a bare string ("battles_won")
    /// or a nested dict ({"type": "battles_won", "target": "self"}).
    /// Unknown shapes return 0. Keeps evalFormula readable.
    private static func evalMetricAny(_ val: Any?, args: [String: Any], ctx: PlayExecContext) -> Int {
        if let name = val as? String {
            return evalMetric(name, args: args, ctx: ctx)
        }
        if let nested = val as? [String: Any] {
            let type = nested["type"] as? String
            // Nested metric's own args override the outer formula's args
            // (so `{type: "discard_count", target: "opponent", kind: "hero"}`
            // can reach evalMetric as if it were a flat lookup).
            return evalMetric(type, args: nested, ctx: ctx)
        }
        return 0
    }

    private static func evalMetric(_ metric: String?, args: [String: Any], ctx: PlayExecContext) -> Int {
        guard let metric = metric else { return 0 }
        let target = (args["target"] as? String) ?? "self"
        let selfView = target == "self"

        switch metric {
        case "plays_used_this_battle":
            // Return THIS battle's play count for the requested side.
            // Previously hard-returned 0 for `target: "opponent"`, so
            // formula-driven persistents like Overcommited's "-5 per
            // play opp ran" silently computed to zero on the next
            // battle even after the persistent fixed install path.
            if selfView { return ctx.playsUsedThisBattle }
            guard ctx.battles.indices.contains(ctx.battleIdx) else { return 0 }
            let slot = ctx.battles[ctx.battleIdx]
            let oppPlays = ctx.self_ == .player
                ? slot.cpuPlayedCards
                : slot.playerPlayedCards
            return oppPlays.count

        case "plays_used_total":
            return 0

        case "heroes_used_total":
            let weapon = args["weapon"] as? String
            let side: PlayExecContext.Side = selfView ? ctx.self_ : ctx.opp
            var n = 0
            for i in 0...ctx.battleIdx where ctx.battles.indices.contains(i) {
                let slot = ctx.battles[i]
                let card: Card? = side == .player ? slot.playerCard : slot.cpuCard
                guard let card = card else { continue }
                if let weapon = weapon, ctx.weapon(of: card, as: side) != weapon { continue }
                n += 1
            }
            return n

        case "heroes_revealed_total":
            return ctx.battleIdx + 1

        case "revealed_hero_power":
            // Power of the active hero for `target`
            let card = selfView ? ctx.selfCard : ctx.oppCard
            return card?.power ?? 0

        case "current_power", "starting_power":
            let card = selfView ? ctx.selfCard : ctx.oppCard
            return card?.power ?? 0

        case "drawn_hero_power":
            // Best guess: top of target's hero deck
            let deck = selfView ? ctx.selfHeroDeck : []
            return deck.first?.power ?? 0

        case "drawn_play_cost":
            // Peek top of selfHand (closest proxy)
            return ctx.selfHand.first?.playCost ?? 0

        case "revealed_play_cost":
            return ctx.selfHand.first?.playCost ?? 0

        case "chosen_play_cost":
            // Returns the cost of the play just chosen by an
            // add_chosen_revealed_to_hand_discard_rest op IN THIS
            // execution (Power Pick et al.). Falls back to the legacy
            // "max cost in hand" approximation when no chooser ran in
            // this exec call.
            if let chosen = ctx.counters.chosenPlayCost { return chosen }
            return ctx.selfHand.map { $0.playCost ?? 0 }.max() ?? 0

        case "discard_pile_heroes":
            let pile = selfView ? ctx.selfDiscard : []
            return pile.filter { $0.cardType == "Hero" }.count

        case "discard_pile_heroes_weapon_match":
            // Count heroes in discard whose weapon matches active hero
            let pile = selfView ? ctx.selfDiscard : []
            let side: PlayExecContext.Side = selfView ? ctx.self_ : ctx.opp
            let activeW = ctx.weapon(of: ctx.selfCard, as: side)
            guard !activeW.isEmpty else { return 0 }
            return pile.filter {
                $0.cardType == "Hero" && ctx.weapon(of: $0, as: side) == activeW
            }.count

        case "discard_pile_count_excluding_hd":
            let pile = selfView ? ctx.selfDiscard : []
            return pile.filter { $0.cardType != "HotDog" }.count

        case "distinct_weapons_revealed":
            var weapons = Set<String>()
            for i in 0...ctx.battleIdx where ctx.battles.indices.contains(i) {
                let slot = ctx.battles[i]
                let pw = ctx.weapon(of: slot.playerCard, as: .player)
                let cw = ctx.weapon(of: slot.cpuCard,    as: .cpu)
                if !pw.isEmpty { weapons.insert(pw) }
                if !cw.isEmpty { weapons.insert(cw) }
            }
            return weapons.count

        case "battles_won":
            return selfView ? ctx.selfWon : ctx.selfLost

        case "battles_lost":
            return selfView ? ctx.selfLost : ctx.selfWon

        case "battles_lost_streak":
            var streak = 0
            var i = ctx.battleIdx - 1
            while i >= 0 {
                guard ctx.battles.indices.contains(i) else { break }
                let r = ctx.battles[i].result
                let lost = (ctx.self_ == .player && r == .lose) || (ctx.self_ == .cpu && r == .win)
                if lost { streak += 1; i -= 1 } else { break }
            }
            return streak

        case "battles_tied":
            return ctx.selfTied

        case "battles_remaining":
            return ctx.battlesRemaining

        case "hd_count":
            return selfView ? ctx.selfHD : ctx.oppHD

        case "hd_count_before_cost":
            return selfView ? ctx.selfHD : ctx.oppHD

        case "hand_count":
            return selfView ? ctx.selfHand.count : 0

        case "hd_discarded_this_battle":
            // Not tracked per-battle precisely — approximate from HD baseline
            return max(0, 10 - (selfView ? ctx.selfHD : ctx.oppHD))

        case "opponent_hd_used_this_battle":
            return max(0, 10 - ctx.oppHD)

        case "cards_discarded_by_this_play":
            return ctx.counters.cardsDiscardedByThisPlay

        case "plays_in_hand_before_shuffle":
            return ctx.selfHand.count

        case "discard_count":
            let kind = args["kind"] as? String
            let pile = selfView ? ctx.selfDiscard : []
            switch kind {
            case "hero":    return pile.filter { $0.cardType == "Hero" }.count
            case "play":    return pile.filter { $0.cardType == "Play" }.count
            case "hot_dog": return pile.filter { $0.cardType == "HotDog" }.count
            default:        return pile.count
            }

        case "discarded_plays_cost_gte":
            let minCost = (args["min_cost"] as? Int) ?? (args["offset"] as? Int) ?? 3
            let pile = selfView ? ctx.selfDiscard : []
            return pile.filter { $0.cardType == "Play" && ($0.playCost ?? 0) >= minCost }.count

        default:
            return 0
        }
    }
}
