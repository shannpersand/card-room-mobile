import Foundation
import Supabase

/// Which pile a pending drawn card came from — mirrors the `source` field of the web app's
/// local-only `golfPendingDraw` state in `src/pages/Game.tsx` (never written to the database;
/// `RoomViewModel` holds the equivalent here).
enum GolfDrawSource {
    case deck
    case discard
}

private struct RoomDeckUpdate: Encodable { let deck: [Card] }
private struct RoomDiscardUpdate: Encodable {
    let discardPile: [Card]
    enum CodingKeys: String, CodingKey { case discardPile = "discard_pile" }
}
private struct PlayerHandUpdate: Encodable { let hand: [Card] }
private struct RoomTurnUpdate: Encodable {
    let currentTurn: NullableField<String>
    enum CodingKeys: String, CodingKey { case currentTurn = "current_turn" }
}
private struct RoomKnockUpdate: Encodable {
    let golfKnockedBy: String
    let currentTurn: NullableField<String>
    enum CodingKeys: String, CodingKey { case golfKnockedBy = "golf_knocked_by"; case currentTurn = "current_turn" }
}
private struct GolfReadyUpdate: Encodable {
    let golfReady: Bool
    enum CodingKeys: String, CodingKey { case golfReady = "golf_ready" }
}

/// Mirrors the "--- Golf ---" section of `src/pages/Game.tsx`.
enum GolfService {
    static func drawFromDeck(room: Room) async throws -> Card {
        guard let drawn = room.deck.first else { throw RoomServiceError.notFound }
        let remaining = Array(room.deck.dropFirst())
        try await supabase.from("rooms").update(RoomDeckUpdate(deck: remaining)).eq("id", value: room.id).execute()
        return drawn
    }

    static func drawFromDiscard(room: Room) async throws -> Card {
        guard let drawn = room.discardPile.last else { throw RoomServiceError.notFound }
        let remaining = Array(room.discardPile.dropLast())
        try await supabase.from("rooms").update(RoomDiscardUpdate(discardPile: remaining)).eq("id", value: room.id).execute()
        return Card(id: drawn.id, suit: drawn.suit, rank: drawn.rank, faceUp: true)
    }

    /// Swaps `newCard` into hand slot `idx`; the replaced card goes face-up to discard. Returns
    /// the replaced card so the caller can update its local peek-tracking. Turn does NOT pass
    /// automatically — the player explicitly ends their turn (or knocks) once ready.
    @discardableResult
    static func performSwap(room: Room, player: Player, idx: Int, newCard: Card) async throws -> Card {
        let oldCard = player.hand[idx]
        var newHand = player.hand
        newHand[idx] = Card(id: newCard.id, suit: newCard.suit, rank: newCard.rank, faceUp: false)
        let discarded = Card(id: oldCard.id, suit: oldCard.suit, rank: oldCard.rank, faceUp: true)

        try await supabase.from("rooms").update(RoomDiscardUpdate(discardPile: room.discardPile + [discarded])).eq("id", value: room.id).execute()
        try await supabase.from("players").update(PlayerHandUpdate(hand: newHand)).eq("id", value: player.id).execute()
        await RoomService.logAction(roomId: room.id, entry: "\(player.name) swapped in a card, discarding \(oldCard.rank.rawValue)\(oldCard.suit.symbol)")
        return oldCard
    }

    /// Declines the swap — the drawn card goes straight to discard, hand stays as-is.
    static func discardDrawn(room: Room, player: Player, drawn: Card) async throws {
        let discarded = Card(id: drawn.id, suit: drawn.suit, rank: drawn.rank, faceUp: true)
        try await supabase.from("rooms").update(RoomDiscardUpdate(discardPile: room.discardPile + [discarded])).eq("id", value: room.id).execute()
        await RoomService.logAction(roomId: room.id, entry: "\(player.name) discarded \(discarded.rank.rawValue)\(discarded.suit.symbol) without swapping")
    }

    /// Passes the turn once the drawn card's been resolved. If this wraps back around to
    /// whoever knocked, reveals every hand and ends the round instead of just passing the turn.
    static func endTurn(room: Room, player: Player, orderedPlayers: [Player]) async throws {
        let nextTurn = Deck.nextPlayer(in: orderedPlayers, after: player.id)
        let revealing = room.golfKnockedBy != nil && nextTurn == room.golfKnockedBy
        try await supabase.from("rooms").update(RoomTurnUpdate(currentTurn: NullableField(revealing ? nil : nextTurn))).eq("id", value: room.id).execute()
        if revealing { await revealAllHands(orderedPlayers) }
        await RoomService.logAction(roomId: room.id, entry: "\(player.name) ended their turn")
    }

    /// Declares this was your last turn — everyone else gets exactly one more turn, then all
    /// hands reveal.
    static func knock(room: Room, player: Player, orderedPlayers: [Player]) async throws {
        let nextTurn = Deck.nextPlayer(in: orderedPlayers, after: player.id)
        try await supabase.from("rooms").update(RoomKnockUpdate(golfKnockedBy: player.id, currentTurn: NullableField(nextTurn))).eq("id", value: room.id).execute()
        await RoomService.logAction(roomId: room.id, entry: "\(player.name) knocked")
    }

    /// Dealer-only: ends the pre-game peek phase, handing the first turn to the dealer (same
    /// seat that already goes first for Blackjack).
    static func startGame(room: Room, dealerId: String) async throws {
        try await supabase.from("rooms").update(RoomTurnUpdate(currentTurn: NullableField(dealerId))).eq("id", value: room.id).execute()
        await RoomService.logAction(roomId: room.id, entry: "The dealer started the round")
    }

    /// Reveals every active player's hand — used when a turn wraps back around to whoever
    /// knocked.
    static func revealAllHands(_ players: [Player]) async {
        for player in players {
            let revealed = player.hand.map { Card(id: $0.id, suit: $0.suit, rank: $0.rank, faceUp: true) }
            _ = try? await supabase.from("players").update(PlayerHandUpdate(hand: revealed)).eq("id", value: player.id).execute()
        }
    }

    /// Marks this player as having used both their pre-game peeks — best-effort, same as the
    /// web app (a failure here just leaves the dealer's "Start game" button waiting).
    static func markPeeksUsed(playerId: String) async {
        _ = try? await supabase.from("players").update(GolfReadyUpdate(golfReady: true)).eq("id", value: playerId).execute()
    }
}
