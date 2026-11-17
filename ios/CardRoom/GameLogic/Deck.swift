import Foundation

/// Mirrors card-room's `src/lib/deck.ts` — must stay behaviorally identical (same card ids,
/// same shuffle semantics not required since each client shuffles its own freshly-dealt deck,
/// but the deck composition and value math absolutely must match or results between the web
/// and this app would disagree about who won).
enum Deck {
    static let ranks: [Rank] = [.two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .jack, .queen, .king, .ace]
    private static let suits: [Suit] = [.spades, .hearts, .diamonds, .clubs]

    static func createDeck() -> [Card] {
        suits.flatMap { suit in
            ranks.map { rank in Card(id: "\(rank.rawValue)-\(suit.rawValue)", suit: suit, rank: rank, faceUp: true) }
        }
    }

    static func shuffled(_ cards: [Card]) -> [Card] {
        cards.shuffled()
    }

    /// Blackjack hand value, with Aces counting as 11 unless that would bust the hand.
    static func blackjackValue(_ hand: [Card]) -> Int {
        var total = 0
        var aces = 0
        for card in hand {
            switch card.rank {
            case .ace: total += 11; aces += 1
            case .king, .queen, .jack, .ten: total += 10
            case .joker: break // never dealt in Blackjack
            default: total += Int(card.rank.rawValue) ?? 0
            }
        }
        while total > 21 && aces > 0 { total -= 10; aces -= 1 }
        return total
    }

    /// Returns the next player id in seat_order after `currentId`, wrapping around.
    static func nextPlayer(in players: [Player], after currentId: String?) -> String? {
        let active = players.filter(\.isActive).sorted { $0.seatOrder < $1.seatOrder }
        guard !active.isEmpty else { return nil }
        guard let currentId, let idx = active.firstIndex(where: { $0.id == currentId }) else {
            return active[0].id
        }
        return active[(idx + 1) % active.count].id
    }
}
