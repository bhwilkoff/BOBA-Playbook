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

    enum Honors { case player, cpu }

    // MARK: - Player Resources
    var playerHeroDeck: [Card] = []     // shuffled, remaining
    var playerBench: [Card] = []        // 6 bench cards (matching web: 13 total = 7 battles + 6 bench)
    var playerHand: [Card] = []         // play cards in hand (5 max)
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
        if !allCards.isEmpty { allCardsPool = allCards }
        let pool = allCardsPool

        // Build hero pool — cards with images first for better visual experience
        let heroes = pool.filter { $0.cardType == "Hero" && ($0.power ?? 0) > 0 }
        let heroesWithImg = heroes.filter { !($0.imageFile ?? "").isEmpty }
        let heroesNoImg   = heroes.filter {  ($0.imageFile ?? "").isEmpty }
        let heroPool = heroesWithImg.shuffled() + heroesNoImg.shuffled()

        // Player: 7 battle + 6 bench = 13; CPU: next 13
        let playerPool = Array(heroPool.prefix(13))
        let cpuPool    = Array(heroPool.dropFirst(13).prefix(13))

        // Set up battles
        battles = (0..<7).map { i in
            var slot = BattleSlot(id: i)
            slot.playerCard = i < playerPool.count ? playerPool[i] : nil
            slot.cpuCard    = i < cpuPool.count    ? cpuPool[i]    : nil
            return slot
        }

        // Bench
        playerBench = mode.showBench ? Array(playerPool.dropFirst(7)) : []
        cpuBench    = mode.showBench ? Array(cpuPool.dropFirst(7))    : []

        // Remaining hero decks (for future draw — unused in simplified mode)
        playerHeroDeck = Array(heroPool.dropFirst(26))
        cpuHeroDeck    = []

        // Play cards
        let plays = pool.filter { $0.cardType == "Play" }.shuffled()
        if mode.showPlays {
            playerHand       = Array(plays.prefix(5))
            playerPlayDeck   = Array(plays.dropFirst(5))
            playerPlayDiscard = []
            cpuHand          = Array(plays.shuffled().prefix(5))
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
        phase = .reveal
        matchOver = false
        matchWinner = nil
        playerSubstituted = false; cpuSubstituted = false
        playerPassedPlays = false; cpuPassedPlays = false

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
        // Simplified power bonus: (cost * 6 + 5) — matches web implementation
        battles[currentBattle].playerEffectPower += cost * 6 + 5
        playerHotDogs -= cost
        playerPlayDiscard.append(card)
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
        // Easy AI: play 0-1 cards ~40% of the time
        let affordable = cpuHand.filter { ($0.playCost ?? 0) <= cpuHotDogs }
        if let card = affordable.randomElement(), Int.random(in: 0...9) < 4 {
            cpuHand.removeFirst(where: { $0 == card })
            battles[currentBattle].cpuPlayedCards.append(card)
            let cost = card.playCost ?? 0
            battles[currentBattle].cpuEffectPower += cost * 6 + 5
            cpuHotDogs -= cost
            cpuPlaysRemaining -= 1
        }
        cpuPassedPlays = true
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
        playerPlayDeck = []; playerPlayDiscard = []
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
