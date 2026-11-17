import Foundation
import Supabase

/// The live state of one joined room session — shared by `LobbyView` and `GameView` (the same
/// instance carries over from one to the other, matching how both are really just two
/// perspectives on the same realtime-synced `rooms`/`players` rows). Mirrors the realtime
/// subscription pattern in card-room's `src/pages/Lobby.tsx` / `src/pages/Game.tsx`.
@MainActor
final class RoomViewModel: ObservableObject {
    @Published private(set) var room: Room
    @Published private(set) var players: [Player] = []
    @Published var actionError: String?
    @Published var isDealing = false

    let myPlayerId: String
    private let decoder = JSONDecoder()
    private var channel: RealtimeChannelV2?
    private var subscribeTask: Task<Void, Never>?
    private var roomSyncTask: Task<Void, Never>?
    private var playerSyncTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    init(room: Room, myPlayerId: String) {
        self.room = room
        self.myPlayerId = myPlayerId
    }

    var orderedPlayers: [Player] { players.filter(\.isActive).sorted { $0.seatOrder < $1.seatOrder } }
    var myPlayer: Player? { players.first { $0.id == myPlayerId } }
    var dealer: Player? { orderedPlayers.first }
    var isDealer: Bool { dealer?.id == myPlayerId }
    var isMyTurn: Bool { room.currentTurn == myPlayerId }
    var allStanding: Bool { !orderedPlayers.isEmpty && orderedPlayers.allSatisfy(\.isStanding) }

    func loadPlayers() async {
        if let fetched = try? await RoomService.fetchPlayers(roomId: room.id) {
            players = fetched
        }
    }

    /// Opens the realtime channel and starts the heartbeat. Call once per screen that needs
    /// live updates; `stopSync()` tears everything down (call from `.onDisappear`, or when
    /// navigating from Lobby to Game — `startSync()` again there re-opens a fresh channel).
    func startSync() {
        let ch = supabase.channel("room-\(room.id)")
        channel = ch

        let roomUpdates = ch.postgresChange(UpdateAction.self, schema: "public", table: "rooms", filter: .eq("id", value: room.id))
        let playerChanges = ch.postgresChange(AnyAction.self, schema: "public", table: "players", filter: .eq("room_id", value: room.id))

        subscribeTask = Task { try? await ch.subscribeWithError() }

        roomSyncTask = Task { [weak self] in
            guard let self else { return }
            for await change in roomUpdates {
                guard let updated: Room = try? change.decodeRecord(decoder: self.decoder) else { continue }
                self.room = updated
                await GameService.revealDealerHandIfNeeded(room: updated, orderedPlayers: self.orderedPlayers)
            }
        }

        playerSyncTask = Task { [weak self] in
            guard let self else { return }
            for await change in playerChanges {
                switch change {
                case .insert(let action):
                    guard let player: Player = try? action.decodeRecord(decoder: self.decoder) else { continue }
                    if !self.players.contains(where: { $0.id == player.id }) {
                        self.players.append(player)
                    }
                case .update(let action):
                    guard let player: Player = try? action.decodeRecord(decoder: self.decoder) else { continue }
                    if let idx = self.players.firstIndex(where: { $0.id == player.id }) {
                        self.players[idx] = player
                    }
                    await GameService.revealDealerHandIfNeeded(room: self.room, orderedPlayers: self.orderedPlayers)
                case .delete(let action):
                    guard let old: Player = try? action.decodeOldRecord(decoder: self.decoder) else { continue }
                    self.players.removeAll { $0.id == old.id }
                }
            }
        }

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                await RoomService.sendHeartbeat(playerId: self.myPlayerId)
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func stopSync() {
        subscribeTask?.cancel()
        roomSyncTask?.cancel()
        playerSyncTask?.cancel()
        heartbeatTask?.cancel()
        if let channel { Task { await supabase.removeChannel(channel) } }
    }

    // MARK: - Lobby actions

    func dealBlackjack() async {
        guard isDealer, orderedPlayers.count >= 2 else {
            actionError = "Need at least 2 players to deal."
            return
        }
        isDealing = true
        defer { isDealing = false }
        do {
            try await LobbyService.dealBlackjack(room: room, orderedPlayers: orderedPlayers)
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Game actions

    func hit() async {
        guard let me = myPlayer, isMyTurn else { return }
        do {
            try await GameService.hit(room: room, player: me, orderedPlayers: orderedPlayers)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func stand() async {
        guard let me = myPlayer, isMyTurn else { return }
        do {
            try await GameService.stand(room: room, player: me, orderedPlayers: orderedPlayers)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func revealDealerHand() async {
        guard isDealer, let dealer else { return }
        await GameService.revealDealerHand(dealer: dealer)
    }
}
