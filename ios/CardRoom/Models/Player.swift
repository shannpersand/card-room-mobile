import Foundation

/// Mirrors `Player` in card-room's `src/types.ts` — the `players` table.
struct Player: Codable, Identifiable, Equatable {
    let id: String
    let roomId: String
    let name: String
    let hand: [Card]
    let seatOrder: Int
    let isStanding: Bool   // Blackjack: has this player chosen to stand?
    let isActive: Bool
    let isBot: Bool
    let golfReady: Bool    // Golf: has this player finished peeking at their 2 starting cards?
    let lastSeen: String

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case name
        case hand
        case seatOrder = "seat_order"
        case isStanding = "is_standing"
        case isActive = "is_active"
        case isBot = "is_bot"
        case golfReady = "golf_ready"
        case lastSeen = "last_seen"
    }
}
