//
//  PlayEffects.swift
//  BOBAPlaybook
//
//  Structured executor for play-effects.json. Mirrors the web executor in
//  js/practice.js: consumes an entry's effects[] array and returns
//  deltas/flags. Unknown ops are skipped (forward-compat). Callers fall
//  back to the regex resolver (PracticeStore.resolveEffect) when an entry
//  is missing or produces no mechanical effect.
//

import Foundation

// ════════════════════════════════════════════════════════════════
// MARK: - Loader
// ════════════════════════════════════════════════════════════════

enum PlayEffects {
    /// Keyed by Play card name. `[String: Any]` holds the raw JSON for each entry.
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
    // Only hard-gated cards set `requires`; everything else passes.
    static func isPlayable(name: String, ctx: PlayExecContext) -> Bool {
        guard let e = entry(for: name),
              let req = e["requires"] as? [String: Any] else { return true }
        return PlayEffectExecutor.evalCondition(req, ctx: ctx)
    }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Executor context
// ════════════════════════════════════════════════════════════════

struct PlayExecContext {
    enum Side { case player, cpu }

    let self_: Side
    var selfCard: Card?
    var oppCard: Card?
    var selfHD: Int
    var oppHD: Int
    var selfSubstituted: Bool
    var selfHand: [Card]
    var selfDiscard: [Card]
    var selfHeroDeck: [Card]
    var selfWon: Int
    var selfLost: Int
    var selfTied: Int
    var playsUsedThisBattle: Int
    var battleIdx: Int          // 0-based
    var battlesRemaining: Int
    var honors: String          // "player" / "cpu"
    var battles: [BattleSlot]

    var opp: Side { self_ == .player ? .cpu : .player }
}

// ════════════════════════════════════════════════════════════════
// MARK: - Executor output
// ════════════════════════════════════════════════════════════════

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
        // Choice / options: pick the option with the highest estimated self power
        if let options = (step["options"] ?? step["choice"]) as? [[String: Any]] {
            var bestScore = Int.min
            var bestEffects: [[String: Any]] = []
            for o in options {
                var probe = PlayExecOut()
                let effs = (o["effects"] as? [[String: Any]]) ?? []
                for s in effs { execStep(s, ctx: ctx, out: &probe) }
                let score = probe.selfDelta - probe.oppDelta + probe.selfHDDelta * 5
                if score > bestScore { bestScore = score; bestEffects = effs }
            }
            for s in bestEffects { execStep(s, ctx: ctx, out: &out) }
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
            let amt = evalFormula(step["amount"], ctx: ctx)
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
            out.hasEffect = true

        case "coin_flip":
            execCoinFlip(step, ctx: ctx, out: &out)

        case "dice_roll":
            execDiceRoll(step, ctx: ctx, out: &out)

        case "protect_self":
            out.protectSelf = true
            out.hasEffect = true

        case "cancel_opponent_plays", "cap_opponent_plays":
            out.cancelOpp = true
            out.hasEffect = true

        case "variable_cost_bonus":
            let factor = (step["factor"] as? Int) ?? (step["per_hd"] as? Int) ?? 5
            let available = max(0, ctx.selfHD)
            let spend = min(available, 3)  // auto heuristic
            if spend > 0 {
                out.selfHDDelta -= spend
                out.selfDelta += factor * spend
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

        default:
            out.unknownOps.append(op)
        }
    }

    // MARK: - Coin / dice

    private static func execCoinFlip(_ step: [String: Any], ctx: PlayExecContext, out: inout PlayExecOut) {
        let times = (step["times"] as? Int) ?? 1
        var results: [Bool] = []
        for _ in 0..<times { results.append(Bool.random()) }
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
        out.hasEffect = true
    }

    private static func execDiceRoll(_ step: [String: Any], ctx: PlayExecContext, out: inout PlayExecOut) {
        let count = (step["count"] as? Int) ?? 1
        var rolls: [Int] = []
        for _ in 0..<count { rolls.append(Int.random(in: 1...6)) }
        let sum = rolls.reduce(0, +)
        let agg = (step["aggregate"] as? String) ?? (count > 1 ? "sum" : "")
        let matchValue = agg == "sum" ? sum : (rolls.first ?? 0)

        if let branches = step["branches"] as? [[String: Any]] {
            var elseBranch: [[String: Any]]? = nil
            var matched = false
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
                for s in elseBranch { execStep(s, ctx: ctx, out: &out) }
            }
        }
        if step["on_match"] != nil || step["on_miss"] != nil {
            let branchAny: Any? = (Double.random(in: 0..<1) < 1.0/6.0) ? step["on_match"] : step["on_miss"]
            if let branch = branchAny as? [[String: Any]] {
                for s in branch { execStep(s, ctx: ctx, out: &out) }
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

        switch type {
        case "weapon":
            return card?.element == (cond["weapon"] as? String)

        case "weapon_same":
            if (cond["between"] as? String) == "self_opp" {
                return ctx.selfCard?.element == ctx.oppCard?.element
            }
            return false

        case "weapon_different":
            if (cond["between"] as? String) == "self_opp" {
                return ctx.selfCard?.element != ctx.oppCard?.element
            }
            return false

        case "hd_count":
            let v = selfView ? ctx.selfHD : ctx.oppHD
            return cmp(v, cond["comparison"] as? String, cond["value"] as? Int)

        case "hand_count":
            let v = selfView ? ctx.selfHand.count : 0
            return cmp(v, cond["comparison"] as? String, cond["value"] as? Int)

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
        let factor = (obj["factor"] as? Int) ?? 1
        let offset = (obj["offset"] as? Int) ?? 0
        let metric = obj["metric"] as? String
        let m = evalMetric(metric, args: obj, ctx: ctx)
        var result = factor * m + offset
        if let minV = obj["min"] as? Int { result = max(minV, result) }
        if let maxV = obj["max"] as? Int { result = min(maxV, result) }
        return result
    }

    private static func evalMetric(_ metric: String?, args: [String: Any], ctx: PlayExecContext) -> Int {
        guard let metric = metric else { return 0 }
        let target = (args["target"] as? String) ?? "self"
        let selfView = target == "self"

        switch metric {
        case "plays_used_this_battle":
            return selfView ? ctx.playsUsedThisBattle : 0
        case "plays_used_total":
            return 0
        case "heroes_used_total":
            let weapon = args["weapon"] as? String
            var n = 0
            for i in 0...ctx.battleIdx where ctx.battles.indices.contains(i) {
                let slot = ctx.battles[i]
                let card: Card? = selfView
                    ? (ctx.self_ == .player ? slot.playerCard : slot.cpuCard)
                    : (ctx.self_ == .player ? slot.cpuCard : slot.playerCard)
                guard let card = card else { continue }
                if let weapon = weapon, card.element != weapon { continue }
                n += 1
            }
            return n
        case "heroes_revealed_total":
            return ctx.battleIdx + 1
        case "battles_won":
            return selfView ? ctx.selfWon : ctx.selfLost
        case "battles_lost":
            return selfView ? ctx.selfLost : ctx.selfWon
        case "battles_tied":
            return ctx.selfTied
        case "battles_remaining":
            return ctx.battlesRemaining
        case "hd_count":
            return selfView ? ctx.selfHD : ctx.oppHD
        case "hand_count":
            return selfView ? ctx.selfHand.count : 0
        case "discard_count":
            let kind = args["kind"] as? String
            let pile = selfView ? ctx.selfDiscard : []
            switch kind {
            case "hero":    return pile.filter { $0.cardType == "Hero" }.count
            case "play":    return pile.filter { $0.cardType == "Play" }.count
            case "hot_dog": return pile.filter { $0.cardType == "HotDog" }.count
            default:        return pile.count
            }
        default:
            return 0
        }
    }
}
