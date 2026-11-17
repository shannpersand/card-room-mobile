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

    // Custom decoder: `golfReady` tolerates a missing `golf_ready` column (defaults to false)
    // rather than failing the whole decode. The web app's JS client never validates row shape
    // at runtime, so a pending migration degrades silently there (the field just reads
    // `undefined`/falsy) — Swift's Codable is strict by default and would otherwise crash this
    // app outright on any row from a database that hasn't had every migration in
    // `supabase-schema.sql` applied yet, which is a materially worse failure mode for the exact
    // same underlying situation.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        roomId = try c.decode(String.self, forKey: .roomId)
        name = try c.decode(String.self, forKey: .name)
        hand = try c.decode([Card].self, forKey: .hand)
        seatOrder = try c.decode(Int.self, forKey: .seatOrder)
        isStanding = try c.decode(Bool.self, forKey: .isStanding)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        isBot = try c.decode(Bool.self, forKey: .isBot)
        golfReady = try c.decodeIfPresent(Bool.self, forKey: .golfReady) ?? false
        lastSeen = try c.decode(String.self, forKey: .lastSeen)
    }

    init(id: String, roomId: String, name: String, hand: [Card], seatOrder: Int, isStanding: Bool, isActive: Bool, isBot: Bool, golfReady: Bool, lastSeen: String) {
        self.id = id
        self.roomId = roomId
        self.name = name
        self.hand = hand
        self.seatOrder = seatOrder
        self.isStanding = isStanding
        self.isActive = isActive
        self.isBot = isBot
        self.golfReady = golfReady
        self.lastSeen = lastSeen
    }
}
