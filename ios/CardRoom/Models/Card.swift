import Foundation

/// Mirrors `Suit` in card-room's `src/types.ts` — must stay in lockstep with the web app
/// since both clients read/write the same `rooms`/`players` rows.
enum Suit: String, Codable {
    case spades, hearts, diamonds, clubs
}

/// Mirrors `Rank` in card-room's `src/types.ts`.
enum Rank: String, Codable {
    case two = "2", three = "3", four = "4", five = "5", six = "6", seven = "7"
    case eight = "8", nine = "9", ten = "10"
    case jack = "J", queen = "Q", king = "K", ace = "A"
    case joker = "Joker"
}

/// Mirrors `Card` in card-room's `src/types.ts`.
struct Card: Codable, Identifiable, Equatable {
    let id: String      // e.g. "A-spades" — unique across a fresh deck
    let suit: Suit
    let rank: Rank
    let faceUp: Bool     // true = visible to all players on table/community; owner always sees their own hand
}
