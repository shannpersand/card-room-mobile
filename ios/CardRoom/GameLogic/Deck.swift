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

    /// Golf: the 2 jokers added to a standard deck — not part of `createDeck()` since no other
    /// game uses them.
    static func createGolfJokers() -> [Card] {
        [
            Card(id: "Joker-spades", suit: .spades, rank: .joker, faceUp: true),
            Card(id: "Joker-hearts", suit: .hearts, rank: .joker, faceUp: true),
        ]
    }

    /// Row/column pairs within Golf's 2×2 grid (0/1 top row, 2/3 bottom row) — deliberately
    /// excludes the two diagonals (0,3) and (1,2).
    private static let golfGridPairs: [(Int, Int)] = [(0, 1), (2, 3), (0, 2), (1, 3)]

    private static func golfCardValue(_ rank: Rank, zeroRank: GolfZeroRank) -> Int {
        if rank.rawValue == zeroRank.rawValue { return 0 }
        switch rank {
        case .joker: return 10
        case .two: return -2
        case .ace: return 1
        case .jack, .queen, .king: return 10
        default: return Int(rank.rawValue) ?? 0
        }
    }

    /// Golf hand value: face value for number cards, J/Q/K = 10 except whichever rank is
    /// `zeroRank` (worth 0), 2 = -2, Joker = 10, Ace = 1. When `pairsCancel` is set, two cards
    /// of the same rank sharing a row or column (not diagonal) both score 0 instead.
    static func golfHandValue(_ hand: [Card], zeroRank: GolfZeroRank = .queen, pairsCancel: Bool = false) -> Int {
        let values = hand.map { golfCardValue($0.rank, zeroRank: zeroRank) }

        if pairsCancel && hand.count == 4 {
            var canceled = Set<Int>()
            for (a, b) in golfGridPairs where hand[a].rank == hand[b].rank {
                canceled.insert(a); canceled.insert(b)
            }
            return values.enumerated().reduce(0) { total, pair in canceled.contains(pair.offset) ? total : total + pair.element }
        }

        return values.reduce(0, +)
    }
}
