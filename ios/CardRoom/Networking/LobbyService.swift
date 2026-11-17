import Foundation
import Supabase

private struct DealRoomUpdate: Encodable {
    let gameId: String
    let gameName: String
    let state: GameState
    let deck: [Card]
    let currentTurn: NullableField<String>
    let actionLog: [String]

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case gameName = "game_name"
        case state
        case deck
        case currentTurn = "current_turn"
        case actionLog = "action_log"
    }
}

private struct DealPlayerUpdate: Encodable {
    let hand: [Card]
    let isStanding: Bool

    enum CodingKeys: String, CodingKey {
        case hand
        case isStanding = "is_standing"
    }
}

private struct GolfReadyReset: Encodable {
    let golfReady: Bool
    enum CodingKeys: String, CodingKey { case golfReady = "golf_ready" }
}

private struct DealGolfRoomUpdate: Encodable {
    let gameId: String
    let gameName: String
    let state: GameState
    let deck: [Card]
    let discardPile: [Card]
    let currentTurn: NullableField<String>
    let actionLog: [String]
    let golfKnockedBy: NullableField<String>

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case gameName = "game_name"
        case state
        case deck
        case discardPile = "discard_pile"
        case currentTurn = "current_turn"
        case actionLog = "action_log"
        case golfKnockedBy = "golf_knocked_by"
    }
}

/// Mirrors the two presets this app implements — `ALL_GAMES.find(g => g.id === 'blackjack' /
/// 'golf')`'s `deal()` in card-room's `src/lib/games.ts`.
enum LobbyService {
    /// Shuffles a fresh deck and deals Blackjack hands: 2 cards each, dealt round-robin, with
    /// the dealer's (lowest `seat_order`, i.e. `orderedPlayers[0]`) second card face-down so
    /// everyone else sees it as hidden. First turn goes to the player after the dealer — the
    /// dealer still gets a normal turn later, when turn order wraps back around to them.
    static func dealBlackjack(room: Room, orderedPlayers: [Player]) async throws {
        var deck = Deck.shuffled(Deck.createDeck())
        var hands: [[Card]] = Array(repeating: [], count: orderedPlayers.count)

        for round in 0..<2 {
            for p in 0..<orderedPlayers.count {
                let faceUp = !(p == 0 && round == 1)
                var card = deck.removeFirst()
                card = Card(id: card.id, suit: card.suit, rank: card.rank, faceUp: faceUp)
                hands[p].append(card)
            }
        }

        let firstTurnId = orderedPlayers.count > 1 ? orderedPlayers[1].id : orderedPlayers.first?.id

        for (i, player) in orderedPlayers.enumerated() {
            try await supabase
                .from("players")
                .update(DealPlayerUpdate(hand: hands[i], isStanding: false))
                .eq("id", value: player.id)
                .execute()
        }

        try await supabase
            .from("rooms")
            .update(DealRoomUpdate(
                gameId: "blackjack",
                gameName: "Blackjack",
                state: .playing,
                deck: deck,
                currentTurn: NullableField(firstTurnId),
                actionLog: []
            ))
            .eq("id", value: room.id)
            .execute()
    }

    /// Shuffles a standard deck + 2 jokers and deals Golf's 4-card 2×2 grid, all face-down, plus
    /// a 1-card face-up discard pile to start. Starts in the pre-game peek phase (`current_turn`
    /// stays `nil` — the dealer explicitly starts the round later, once everyone's peeked, via
    /// `GolfService.startGame`), not turn-based play like Blackjack.
    static func dealGolf(room: Room, orderedPlayers: [Player]) async throws {
        var deck = Deck.shuffled(Deck.createDeck() + Deck.createGolfJokers())
        var hands: [[Card]] = Array(repeating: [], count: orderedPlayers.count)

        for _ in 0..<4 {
            for p in 0..<orderedPlayers.count {
                let card = deck.removeFirst()
                hands[p].append(Card(id: card.id, suit: card.suit, rank: card.rank, faceUp: false))
            }
        }
        let topDiscard = deck.removeFirst()
        let discardPile = [Card(id: topDiscard.id, suit: topDiscard.suit, rank: topDiscard.rank, faceUp: true)]

        for (i, player) in orderedPlayers.enumerated() {
            try await supabase
                .from("players")
                .update(DealPlayerUpdate(hand: hands[i], isStanding: false))
                .eq("id", value: player.id)
                .execute()
            // Separate, best-effort call — see dealBlackjack's note on why this must never be
            // bundled into the same update as the hand write above.
            _ = try? await supabase
                .from("players")
                .update(GolfReadyReset(golfReady: false))
                .eq("id", value: player.id)
                .execute()
        }

        try await supabase
            .from("rooms")
            .update(DealGolfRoomUpdate(
                gameId: "golf",
                gameName: "Golf",
                state: .playing,
                deck: deck,
                discardPile: discardPile,
                currentTurn: NullableField(nil),
                actionLog: [],
                golfKnockedBy: NullableField(nil)
            ))
            .eq("id", value: room.id)
            .execute()
    }
}
