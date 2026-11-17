import Foundation
import Supabase

private struct RoomDeckTurnUpdate: Encodable {
    let deck: [Card]
    let currentTurn: NullableField<String>

    enum CodingKeys: String, CodingKey {
        case deck
        case currentTurn = "current_turn"
    }
}

private struct PlayerHandStandingUpdate: Encodable {
    let hand: [Card]
    let isStanding: Bool

    enum CodingKeys: String, CodingKey {
        case hand
        case isStanding = "is_standing"
    }
}

private struct PlayerStandingUpdate: Encodable {
    let isStanding: Bool
    enum CodingKeys: String, CodingKey { case isStanding = "is_standing" }
}

private struct PlayerHandUpdate: Encodable {
    let hand: [Card]
}

/// Mirrors the Blackjack-relevant slice of `src/pages/Game.tsx`'s action functions (`hit` is
/// `drawFromDeck`'s Blackjack branch there; same for `stand` and the dealer-reveal effect).
enum GameService {
    /// Draws one card into `player`'s hand. Busting (value > 21) ends their turn immediately —
    /// otherwise it stays their turn (they can hit again).
    static func hit(room: Room, player: Player, orderedPlayers: [Player]) async throws {
        guard !room.deck.isEmpty else { return }
        var deck = room.deck
        let drawn = deck.removeFirst()
        let newHand = player.hand + [drawn]
        let value = Deck.blackjackValue(newHand)
        let busted = value > 21

        try await supabase
            .from("rooms")
            .update(RoomDeckTurnUpdate(deck: deck, currentTurn: NullableField(busted ? Deck.nextPlayer(in: orderedPlayers, after: player.id) : room.currentTurn)))
            .eq("id", value: room.id)
            .execute()
        try await supabase
            .from("players")
            .update(PlayerHandStandingUpdate(hand: newHand, isStanding: busted))
            .eq("id", value: player.id)
            .execute()

        let entry = busted
            ? "\(player.name) hit and busted with \(value)"
            : "\(player.name) hit — now at \(value)"
        await RoomService.logAction(roomId: room.id, entry: entry)
    }

    /// Ends `player`'s turn without drawing.
    static func stand(room: Room, player: Player, orderedPlayers: [Player]) async throws {
        let nextTurn = Deck.nextPlayer(in: orderedPlayers, after: player.id)
        try await supabase
            .from("players")
            .update(PlayerStandingUpdate(isStanding: true))
            .eq("id", value: player.id)
            .execute()
        try await supabase
            .from("rooms")
            .update(RoomDeckTurnUpdate(deck: room.deck, currentTurn: NullableField(nextTurn)))
            .eq("id", value: room.id)
            .execute()
        await RoomService.logAction(roomId: room.id, entry: "\(player.name) stood on \(Deck.blackjackValue(player.hand))")
    }

    /// Once every player (dealer included — they take a normal turn too, last in seat order)
    /// is standing or busted, flips the dealer's hidden second card face-up so the round's
    /// outcome is computable. Idempotent and safe to call from any client, since whichever
    /// client's `GameViewModel` notices the condition first will just be the one that writes
    /// it — matches the web app, which doesn't gate this to the dealer's own device either
    /// (their seat might be empty / a disconnected player).
    static func revealDealerHandIfNeeded(room: Room, orderedPlayers: [Player]) async {
        guard room.gameId == "blackjack",
              orderedPlayers.count > 0,
              orderedPlayers.allSatisfy(\.isStanding),
              let dealer = orderedPlayers.first,
              !dealer.hand.allSatisfy(\.faceUp)
        else { return }

        let revealedHand = dealer.hand.map { Card(id: $0.id, suit: $0.suit, rank: $0.rank, faceUp: true) }
        _ = try? await supabase
            .from("players")
            .update(PlayerHandUpdate(hand: revealedHand))
            .eq("id", value: dealer.id)
            .execute()
    }

    /// Manual version of the same reveal, for the dealer's "Reveal Hand" button — lets the
    /// dealer show their hand early, or as a fallback if the automatic reveal hasn't fired.
    static func revealDealerHand(dealer: Player) async {
        let revealedHand = dealer.hand.map { Card(id: $0.id, suit: $0.suit, rank: $0.rank, faceUp: true) }
        _ = try? await supabase
            .from("players")
            .update(PlayerHandUpdate(hand: revealedHand))
            .eq("id", value: dealer.id)
            .execute()
    }

    /// Mirrors `blackjackOutcome()` in `src/pages/Game.tsx`.
    static func outcome(playerValue: Int, dealerValue: Int) -> String {
        if playerValue > 21 { return "lose" }
        if dealerValue > 21 { return "win" }
        if playerValue > dealerValue { return "win" }
        if playerValue < dealerValue { return "lose" }
        return "push"
    }
}
