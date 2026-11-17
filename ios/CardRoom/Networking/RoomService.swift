import Foundation
import Supabase

enum RoomServiceError: Error, LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: return "No room found with that code."
        }
    }
}

/// Thin wrapper over the `rooms`/`players` tables — mirrors the handful of Supabase calls
/// card-room's `src/pages/Lobby.tsx` and `src/pages/Game.tsx` make, as a starting point for
/// this app's own game-room screens.
enum RoomService {
    /// Looks up a room by its 4-character code, same as the web app's "Join a Game" flow.
    static func fetchRoom(code: String) async throws -> Room {
        let rooms: [Room] = try await supabase
            .from("rooms")
            .select()
            .eq("code", value: code.uppercased())
            .execute()
            .value
        guard let room = rooms.first else { throw RoomServiceError.notFound }
        return room
    }

    static func fetchPlayers(roomId: String) async throws -> [Player] {
        try await supabase
            .from("players")
            .select()
            .eq("room_id", value: roomId)
            .order("seat_order")
            .execute()
            .value
    }

    /// Subscribes to row-level changes on `rooms` for a single room id — the same mechanism
    /// card-room's web client uses so every player's screen stays in sync without polling.
    /// Call `.subscribe()` on the returned channel, then listen on the async stream it hands
    /// back from `.postgresChange(UpdateAction.self, ...)` (see Supabase-Swift's Realtime docs)
    /// to react to each update.
    static func roomChannel(roomId: String) -> RealtimeChannelV2 {
        supabase.channel("room-\(roomId)")
    }
}
