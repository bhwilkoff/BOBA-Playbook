//
//  PracticeStore.swift
//  BOBAPlaybook
//
//  @Observable game state machine for Practice Battle mode.
//  Manages current match, phase progression, CPU AI, and score.
//

import Foundation

// ════════════════════════════════════════════════════════════════
// MARK: - Practice Game Mode
// ════════════════════════════════════════════════════════════════

enum PracticeMode: String, CaseIterable, Identifiable {
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

enum BattlePhase: String, CaseIterable {
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

enum BattleResult {
    case win, lose, tie
}

// ════════════════════════════════════════════════════════════════
// MARK: - Battle Slot
// ════════════════════════════════════════════════════════════════

struct BattleSlot: Identifiable {
    let id: Int   // 0-based battle index
    var playerCard: Card?
    var cpuCard: Card?
    var playerPlayedCards: [Card] = []
    var cpuPlayedCards: [Card] = []
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

    enum Honors { case player, cpu }

    // MARK: - Player Resources
    var playerHeroDeck: [Card] = []     // shuffled, remaining
    var playerBench: [Card] = []        // 4 cards
    var playerHand: [Card] = []         // play cards
    var playerHotDogs: Int = 10
    var playerHotDogDiscard: Int = 0

    // MARK: - CPU Resources
    var cpuHeroDeck: [Card] = []
    var cpuBench: [Card] = []
    var cpuHand: [Card] = []
    var cpuHotDogs: Int = 10
    var cpuPlaysRemaining: Int = 30

    // MARK: - Phase-level state
    var playerSubstituted: Bool = false
    var cpuSubstituted: Bool = false
    var playerPassedPlays: Bool = false
    var cpuPassedPlays: Bool = false

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
        // Build player deck
        let heroCards = allCards.filter { $0.cardType == "Hero" && ($0.power ?? 0) > 0 }
        let playCards = allCards.filter { $0.cardType == "Play" }

        playerHeroDeck = Array(heroCards.shuffled().prefix(60))
        cpuHeroDeck = Array(heroCards.shuffled().prefix(60))

        if mode.showPlays {
            playerHand = Array(playCards.shuffled().prefix(5))
            cpuHand = Array(playCards.shuffled().prefix(5))
        }

        // Set up battles
        battles = (0..<7).map { BattleSlot(id: $0) }

        // Place heroes in all 7 battles
        for i in 0..<7 {
            if i < playerHeroDeck.count { battles[i].playerCard = playerHeroDeck[i] }
            if i < cpuHeroDeck.count   { battles[i].cpuCard    = cpuHeroDeck[i] }
        }
        playerHeroDeck.removeFirst(min(7, playerHeroDeck.count))
        cpuHeroDeck.removeFirst(min(7, cpuHeroDeck.count))

        // Bench (Sub/Playmaker only)
        if mode.showBench {
            playerBench = Array(playerHeroDeck.prefix(4))
            playerHeroDeck.removeFirst(min(4, playerHeroDeck.count))
            cpuBench = Array(cpuHeroDeck.prefix(4))
            cpuHeroDeck.removeFirst(min(4, cpuHeroDeck.count))
        }

        // Reset scores
        playerScore = 0; cpuScore = 0
        playerHotDogs = 10; cpuHotDogs = 10
        honors = .player
        currentBattle = 0
        phase = .reveal
        matchOver = false
        matchWinner = nil

        battles[0].isActive = true
    }

    // MARK: - Phase Advance

    func advancePhase() {
        guard !matchOver else { return }

        switch phase {
        case .reveal:
            battles[currentBattle].isRevealed = true
            if mode == .rookie {
                resolveCurrentBattle()
                phase = .resolution
            } else {
                phase = .sub
                playerSubstituted = false
                cpuSubstituted = false
                cpuTakeSubstitutionTurn()
            }

        case .sub:
            if mode == .playmaker {
                phase = .play
                playerPassedPlays = false
                cpuPassedPlays = false
                cpuTakePlayTurn()
            } else {
                resolveCurrentBattle()
                phase = .resolution
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
    }

    // MARK: - Substitution (Player)

    func playerSubstitute(benchIndex: Int) {
        guard phase == .sub,
              !playerSubstituted,
              playerHotDogs >= 2,
              benchIndex < playerBench.count else { return }

        let current = battles[currentBattle].playerCard
        battles[currentBattle].playerCard = playerBench[benchIndex]
        if let current { playerBench[benchIndex] = current } else { playerBench.remove(at: benchIndex) }

        // Draw replacement if deck has cards
        if let drawn = playerHeroDeck.first {
            playerHeroDeck.removeFirst()
            if benchIndex < playerBench.count {
                playerBench.append(drawn)
            }
        }

        playerHotDogs -= 2
        playerSubstituted = true
    }

    // MARK: - Play Card (Player)

    func playerPlayCard(_ card: Card) {
        guard phase == .play,
              let cost = card.playCost,
              playerHotDogs >= cost,
              playerHand.contains(card) else { return }

        playerHand.removeFirst(where: { $0 == card })
        battles[currentBattle].playerPlayedCards.append(card)
        playerHotDogs -= cost
    }

    func playerPassPlays() {
        guard phase == .play else { return }
        playerPassedPlays = true
        if cpuPassedPlays { phase = .resolution; resolveCurrentBattle() }
    }

    // MARK: - CPU AI (Easy difficulty)

    private func cpuTakeSubstitutionTurn() {
        guard mode.showBench, !cpuSubstituted, cpuHotDogs >= 2 else {
            cpuSubstituted = true; return
        }
        let currentPower = battles[currentBattle].cpuCard?.power ?? 0
        let benchAvg = cpuBench.compactMap(\.power).reduce(0, +) / max(1, cpuBench.count)
        if currentPower < benchAvg, Int.random(in: 0...1) == 1 {
            if let bestIdx = cpuBench.indices.max(by: { (cpuBench[$0].power ?? 0) < (cpuBench[$1].power ?? 0) }) {
                let best = cpuBench[bestIdx]
                cpuBench[bestIdx] = battles[currentBattle].cpuCard ?? best
                battles[currentBattle].cpuCard = best
                cpuHotDogs -= 2
            }
        }
        cpuSubstituted = true
    }

    private func cpuTakePlayTurn() {
        guard mode == .playmaker, !cpuPassedPlays, !playerPassedPlays else {
            cpuPassedPlays = true; return
        }
        // Easy AI: play a random affordable card
        let affordable = cpuHand.filter { ($0.playCost ?? 0) <= cpuHotDogs }
        if let card = affordable.randomElement(), Int.random(in: 0...1) == 1 {
            cpuHand.removeFirst(where: { $0 == card })
            battles[currentBattle].cpuPlayedCards.append(card)
            cpuHotDogs -= card.playCost ?? 0
            cpuPlaysRemaining -= 1
        } else {
            cpuPassedPlays = true
        }
    }

    private func drawPlayCard() {
        // In a real game, draw from playbook deck — simplified: noop for now
    }

    private func cpuDrawPlayCard() {
        cpuPlaysRemaining = max(0, cpuPlaysRemaining - 1)
    }

    // MARK: - Resolution

    private func resolveCurrentBattle() {
        guard battles.indices.contains(currentBattle) else { return }
        var slot = battles[currentBattle]

        let playerPower = (slot.playerCard?.power ?? 0) + slot.playerPlayedCards.reduce(0) { $0 + ($1.power ?? 0) }
        let cpuPower    = (slot.cpuCard?.power ?? 0)    + slot.cpuPlayedCards.reduce(0)    { $0 + ($1.power ?? 0) }

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
            // Tie — SUPER weapon type wins if applicable
            let playerIsSuper = slot.playerCard?.element == "SUPER"
            let cpuIsSuper    = slot.cpuCard?.element == "SUPER"
            if playerIsSuper && !cpuIsSuper {
                slot.result = .win; playerScore += 1; honors = .player
            } else if cpuIsSuper && !playerIsSuper {
                slot.result = .lose; cpuScore += 1; honors = .cpu
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
        phase = .reveal
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
        playerHotDogs = 10; cpuHotDogs = 10
        matchOver = false; matchWinner = nil
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
