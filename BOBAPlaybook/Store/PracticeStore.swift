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

struct BattleSlot: Identifiable, Codable {
    let id: Int   // 0-based battle index
    var playerCard: Card?
    var cpuCard: Card?
    var playerPlayedCards: [Card] = []
    var cpuPlayedCards: [Card] = []
    var playerEffectPower: Int = 0   // bonus from played play cards
    var cpuEffectPower: Int = 0
    var playerFinalPower: Int = 0
    var cpuFinalPower: Int = 0
    var result: BattleResult?
    var isActive: Bool = false
    var isRevealed: Bool = false
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
    var playerHand: [Card] = []         // play cards in hand (4 starting, draw 1/battle)
    var playerPlayDeck: [Card] = []     // remaining play cards
    var playerPlayDiscard: [Card] = []  // played/discarded play cards
    var playerHotDogs: Int = 10
    var playerHotDogDiscard: Int = 0

    // MARK: - CPU Resources
    var cpuHeroDeck: [Card] = []
    var cpuBench: [Card] = []
    var cpuHand: [Card] = []
    var cpuHotDogs: Int = 10
    var cpuPlaysRemaining: Int = 30

    // MARK: - Cached card pool (for Play Again)
    var allCardsPool: [Card] = []

    // MARK: - Phase-level state
    var playerSubstituted: Bool = false
    var cpuSubstituted: Bool = false
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
    }
    var cpuCallouts: [ActionCallout] = []
    var lastEffectCallout: ActionCallout? = nil  // coin flip / dice result

    // CPU play queue — shown one at a time, user dismisses each
    var cpuPlayQueue: [ActionCallout] = []
    var currentCpuPlay: ActionCallout? = nil

    // CPU sub callout — shown once, user dismisses
    var cpuSubCallout: ActionCallout? = nil

    // MARK: - Match completed?
    var matchOver: Bool = false
    var matchWinner: Honors?

    // MARK: - Computed

    var currentSlot: BattleSlot? {
        battles.indices.contains(currentBattle) ? battles[currentBattle] : nil
    }

    var playerHeroForCurrentBattle: Card? { currentSlot?.playerCard }
    var cpuHeroForCurrentBattle: Card? { currentSlot?.cpuCard }

    // MARK: - Setup / Start

    func startMatch(allCards: [Card]) {
        Self.deleteSavedMatch()
        if !allCards.isEmpty { allCardsPool = allCards }
        let pool = allCardsPool

        // Build hero pool — cards with images first for better visual experience
        let heroes = pool.filter { $0.cardType == "Hero" && ($0.power ?? 0) > 0 }
        let heroesWithImg = heroes.filter { !($0.imageFile ?? "").isEmpty }
        let heroesNoImg   = heroes.filter {  ($0.imageFile ?? "").isEmpty }
        let heroPool = heroesWithImg.shuffled() + heroesNoImg.shuffled()

        // Player: 7 battle + 4 bench = 11; CPU: next 11
        let playerPool = Array(heroPool.prefix(11))
        let cpuPool    = Array(heroPool.dropFirst(11).prefix(11))

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
        playerHeroDeck = Array(heroPool.dropFirst(22).prefix(49))
        cpuHeroDeck    = []

        // Play cards (4 starting hand per rules — §4.3.1 "Each Player draws four Plays")
        let plays = pool.filter { $0.cardType == "Play" }.shuffled()
        if mode.showPlays {
            playerHand       = Array(plays.prefix(4))
            playerPlayDeck   = Array(plays.dropFirst(4))
            playerPlayDiscard = []
            cpuHand          = Array(plays.shuffled().prefix(4))
        } else {
            playerHand = []; playerPlayDeck = []; playerPlayDiscard = []
            cpuHand = []
        }

        // Reset scores and state
        playerScore = 0; cpuScore = 0
        playerHotDogs = 10; cpuHotDogs = 10
        cpuPlaysRemaining = 30
        honors = .player
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
                // Stay in reveal phase so user can see the cards before plays begin
                if mode == .rookie || mode == .substitution {
                    // Rookie/Substitution: no play phase, resolve immediately
                    resolveCurrentBattle()
                    phase = .resolution
                }
                // Playmaker: stay in .reveal — user presses again to enter play phase
            } else {
                // Second press (Playmaker only): cards already revealed, move to play phase
                phase = .play
                playerPassedPlays = false
                cpuPassedPlays = false
                cpuPreparePlayTurn()
            }

        case .play:
            phase = .resolution
            resolveCurrentBattle()

        case .resolution:
            phase = .cleanup
            drawPlayCard()
            cpuDrawPlayCard()

        case .cleanup:
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
        }
        if cpuPlayQueue.isEmpty {
            currentCpuPlay = nil
            cpuPassedPlays = true
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
              playerHotDogs >= 2,
              benchIndex < playerBench.count else { return }

        battles[currentBattle].playerCard = playerBench[benchIndex]
        // Original hero goes to discard (removed from bench)
        playerBench.remove(at: benchIndex)

        playerHotDogs -= 2
        playerHotDogDiscard += 2

        // Draw a new hero from hero deck to replace the bench slot (per rules)
        if let drawn = playerHeroDeck.first {
            playerHeroDeck.removeFirst()
            playerBench.append(drawn)
        }

        playerSubstituted = true

        // Substitution completes the sub phase — advance automatically
        advancePhase()
    }

    // MARK: - Play Card (Player)

    func playerPlayCard(_ card: Card) {
        guard phase == .play,
              let cost = card.playCost,
              playerHotDogs >= cost,
              playerHand.contains(card) else { return }

        lastEffectCallout = nil
        playerHand.removeFirst(where: { $0 == card })
        battles[currentBattle].playerPlayedCards.append(card)

        let ability = (card.playAbility ?? "").lowercased()
        let (playerDelta, cpuDelta) = Self.resolveEffect(card: card, playerCard: battles[currentBattle].playerCard, cpuCard: battles[currentBattle].cpuCard)
        battles[currentBattle].playerEffectPower += playerDelta
        battles[currentBattle].cpuEffectPower += cpuDelta

        // Handle shuffle/draw effects
        resolveDrawEffects(ability: ability)

        // Set effect callout for coin flips / dice rolls (auto-dismiss after delay)
        if ability.contains("flip a coin") {
            let result = playerDelta > 0 || cpuDelta < 0 ? "Success!" : "No effect"
            lastEffectCallout = ActionCallout(message: "Coin flip: \(result) (\(playerDelta > 0 ? "+\(playerDelta)" : "\(cpuDelta)"))", icon: "circle.fill", color: playerDelta > 0 ? "4CAF50" : "C0392B")
            scheduleEffectDismiss()
        } else if ability.contains("roll a di") {
            lastEffectCallout = ActionCallout(message: "Dice roll: \(playerDelta > 0 ? "+\(playerDelta)" : "\(cpuDelta)") Power", icon: "dice.fill", color: playerDelta > 0 ? "4CAF50" : "C0392B")
            scheduleEffectDismiss()
        } else if playerDelta != 0 || cpuDelta != 0 {
            // Show power change callout for all effects
            var parts: [String] = []
            if playerDelta > 0 { parts.append("+\(playerDelta) to you") }
            if playerDelta < 0 { parts.append("\(playerDelta) to you") }
            if cpuDelta < 0 { parts.append("\(cpuDelta) to opponent") }
            if cpuDelta > 0 { parts.append("+\(cpuDelta) to opponent") }
            lastEffectCallout = ActionCallout(
                message: "\(card.name): \(parts.joined(separator: ", "))",
                icon: "sparkles",
                color: playerDelta > 0 ? "00F5FF" : "FF4D00"
            )
            scheduleEffectDismiss()
        }

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
        if cpuPassedPlays { phase = .resolution; resolveCurrentBattle() }
    }

    // MARK: - CPU AI

    private func cpuTakeSubstitutionTurn() {
        cpuSubCallout = nil
        guard mode.showBench, !cpuSubstituted, cpuHotDogs >= 2, !cpuBench.isEmpty else {
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
            cpuBench.remove(at: bestIdx)
            battles[currentBattle].cpuCard = best
            cpuHotDogs -= 2

            // Sub happens before reveal — don't reveal original or new hero names
            let pendingCallout = ActionCallout(
                message: "CPU spent 2 Hot Dogs to substitute their hero",
                icon: "arrow.triangle.2.circlepath",
                color: "FF4D00"
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

        var cardsPlayed = 0
        let maxPlays = Int.random(in: 1...3)
        var tempHotDogs = cpuHotDogs

        while cardsPlayed < maxPlays && cpuPlaysRemaining > 0 {
            let affordable = cpuHand.filter { ($0.playCost ?? 0) <= tempHotDogs }
            guard let card = affordable.min(by: { ($0.playCost ?? 0) < ($1.playCost ?? 0) }) else { break }

            cpuHand.removeFirst(where: { $0 == card })
            battles[currentBattle].cpuPlayedCards.append(card)
            let cost = card.playCost ?? 0

            // CPU effects: swap player/cpu deltas since CPU is the one playing
            let (cpuDelta, playerDelta) = Self.resolveEffect(card: card, playerCard: battles[currentBattle].cpuCard, cpuCard: battles[currentBattle].playerCard)

            tempHotDogs -= cost
            cpuHotDogs -= cost
            cpuPlaysRemaining -= 1
            cardsPlayed += 1

            let desc = Self.effectDescription(for: card)
            cpuPlayQueue.append(ActionCallout(
                message: "CPU played \(card.name) (\(cost) HD) — \(desc)",
                icon: "rectangle.stack",
                color: "8B00FF",
                card: card,
                playerDelta: playerDelta,
                cpuDelta: cpuDelta
            ))
        }

        if cpuPlayQueue.isEmpty {
            cpuPassedPlays = true
        } else {
            // Show first play immediately
            currentCpuPlay = cpuPlayQueue.removeFirst()
        }
    }

    private func drawPlayCard() {
        guard mode.showPlays else { return }
        // Reshuffle discard into deck if deck is empty
        if playerPlayDeck.isEmpty && !playerPlayDiscard.isEmpty {
            playerPlayDeck = playerPlayDiscard.shuffled()
            playerPlayDiscard = []
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
        var slot = battles[currentBattle]

        let playerPower = (slot.playerCard?.power ?? 0) + slot.playerEffectPower
        let cpuPower    = (slot.cpuCard?.power ?? 0)    + slot.cpuEffectPower

        slot.playerFinalPower = playerPower
        slot.cpuFinalPower    = cpuPower

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
                let playerIsSuper = slot.playerCard?.element == "SUPER"
                let cpuIsSuper    = slot.cpuCard?.element == "SUPER"
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
        checkMatchOver()
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
        // Per rules: Sub phase comes before reveal for non-rookie
        phase = mode == .rookie ? .reveal : .sub
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
    static func effectDescription(for card: Card) -> String {
        guard let ability = card.playAbility, !ability.isEmpty else {
            let cost = card.playCost ?? 0
            return "+\(cost * 6 + 5) Power"
        }
        return ability
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
    }

    private static var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("practice_match.json")
    }

    static var hasSavedMatch: Bool {
        FileManager.default.fileExists(atPath: saveURL.path)
    }

    func saveMatch() {
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
            matchOver: matchOver, matchWinner: matchWinner
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
