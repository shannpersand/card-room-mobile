import Foundation
import Supabase

enum RoomServiceError: Error, LocalizedError {
    case notFound
    case alreadyStarted

    var errorDescription: String? {
        switch self {
        case .notFound: return "No room found with that code."
        case .alreadyStarted: return "That game has already started."
        }
    }
}

private struct NewPlayer: Encodable {
    let roomId: String
    let name: String
    let seatOrder: Int

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case name
        case seatOrder = "seat_order"
    }
}

private struct PlayerActiveUpdate: Encodable {
    let isActive: Bool
    let lastSeen: String

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case lastSeen = "last_seen"
    }
}

/// Thin wrapper over the `rooms`/`players` tables — mirrors the handful of Supabase calls
/// card-room's `src/pages/Landing.tsx`, `src/pages/Lobby.tsx`, and `src/pages/Game.tsx` make.
enum RoomService {
    /// Looks up a room by its 4-character code.
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

    /// Mirrors `joinRoom()` in `src/pages/Landing.tsx`: looks up the room, rejoins as the same
    /// seat if `PlayerSession` already has a player id for this exact room code (so
    /// backgrounding/relaunching the app doesn't create a duplicate seat), otherwise inserts a
    /// brand-new player at the next open seat. Blocks joining (new OR rejoining) once the room
    /// has already started — same limitation the web app has.
    static func joinOrRejoin(code: String, playerName: String) async throws -> (room: Room, player: Player) {
        let room = try await fetchRoom(code: code)
        if room.state == .playing { throw RoomServiceError.alreadyStarted }

        if let existingId = PlayerSession.playerId, PlayerSession.roomCode == code.uppercased() {
            let existing: [Player] = try await supabase
                .from("players")
                .select()
                .eq("id", value: existingId)
                .eq("room_id", value: room.id)
                .execute()
                .value
            if let player = existing.first {
                try await supabase
                    .from("players")
                    .update(PlayerActiveUpdate(isActive: true, lastSeen: ISO8601DateFormatter().string(from: Date())))
                    .eq("id", value: player.id)
                    .execute()
                return (room, player)
            }
        }

        let existingSeats: [Player] = try await supabase
            .from("players")
            .select()
            .eq("room_id", value: room.id)
            .order("seat_order", ascending: false)
            .limit(1)
            .execute()
            .value
        let nextSeat = (existingSeats.first?.seatOrder ?? -1) + 1

        let inserted: Player = try await supabase
            .from("players")
            .insert(NewPlayer(roomId: room.id, name: playerName, seatOrder: nextSeat))
            .select()
            .single()
            .execute()
            .value

        PlayerSession.save(playerId: inserted.id, roomCode: code.uppercased())
        return (room, inserted)
    }

    /// Periodic heartbeat — mirrors the Lobby's 10s `last_seen`/`is_active` update, so other
    /// clients can eventually tell a player's gone quiet (not currently surfaced in the UI, but
    /// kept consistent with what the web app already writes to these same rows).
    static func sendHeartbeat(playerId: String) async {
        _ = try? await supabase
            .from("players")
            .update(PlayerActiveUpdate(isActive: true, lastSeen: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: playerId)
            .execute()
    }

    /// Best-effort append to `action_log`, capped at the last 30 entries — mirrors `logAction`/
    /// `appendLog` in `src/pages/Game.tsx`. A failure here (e.g. a stale read racing another
    /// client's write) must never block the actual game-state update it's logging, so callers
    /// should fire this with `Task { await ... }` rather than awaiting it inline.
    static func logAction(roomId: String, entry: String) async {
        struct ActionLogRow: Decodable { let actionLog: [String]?
            enum CodingKeys: String, CodingKey { case actionLog = "action_log" }
        }
        struct ActionLogUpdate: Encodable { let actionLog: [String]
            enum CodingKeys: String, CodingKey { case actionLog = "action_log" }
        }
        do {
            let rows: [ActionLogRow] = try await supabase
                .from("rooms").select("action_log").eq("id", value: roomId).execute().value
            let current = rows.first?.actionLog ?? []
            let next = Array((current + [entry]).suffix(30))
            try await supabase.from("rooms").update(ActionLogUpdate(actionLog: next)).eq("id", value: roomId).execute()
        } catch {
            // Ignore — history is a nice-to-have, not required for gameplay to proceed.
        }
    }

    /// Subscribes to row-level changes on `rooms` for a single room id — the same mechanism
    /// card-room's web client uses so every player's screen stays in sync without polling.
    static func roomChannel(roomId: String) -> RealtimeChannelV2 {
        supabase.channel("room-\(roomId)")
    }
}
