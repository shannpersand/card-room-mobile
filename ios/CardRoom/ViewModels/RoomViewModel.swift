import Foundation
import Supabase

struct GolfPendingDraw {
    let card: Card
    let source: GolfDrawSource
}

/// The live state of one joined room session — shared by `LobbyView` and `GameView`/`GolfView`
/// (the same instance carries over from one to the other, matching how both are really just two
/// perspectives on the same realtime-synced `rooms`/`players` rows). Mirrors the realtime
/// subscription pattern in card-room's `src/pages/Lobby.tsx` / `src/pages/Game.tsx`.
@MainActor
final class RoomViewModel: ObservableObject {
    @Published private(set) var room: Room
    @Published private(set) var players: [Player] = []
    @Published var actionError: String?
    @Published var isDealing = false

    // --- Golf: local-only peek state (never synced, so opponents never see it) + pending
    // draw-and-replace flow — mirrors `src/pages/Game.tsx`'s identically-named state. ---
    @Published var golfPeekedNow: Set<String> = []
    @Published var golfPeekUsed: Set<String> = []
    @Published var golfPendingDraw: GolfPendingDraw?
    @Published var golfHasActedThisTurn = false

    let myPlayerId: String
    private let decoder = JSONDecoder()
    private var channel: RealtimeChannelV2?
    private var subscribeTask: Task<Void, Never>?
    private var roomSyncTask: Task<Void, Never>?
    private var playerSyncTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    // Golf turn-tracking refs — mirrors `prevDeckLenRef`/`prevTurnHolderRef` in Game.tsx exactly,
    // including the quirk that a `nil` previous value never triggers the deck-reset branch but
    // DOES trigger the turn-reset branch (so arriving mid-game on your own turn still correctly
    // starts you at "haven't acted yet").
    private var previousDeckCount: Int?
    private var previousTurnHolder: String?

    init(room: Room, myPlayerId: String) {
        self.room = room
        self.myPlayerId = myPlayerId
        applyGolfTurnTracking(for: room)
    }

    var orderedPlayers: [Player] { players.filter(\.isActive).sorted { $0.seatOrder < $1.seatOrder } }
    var myPlayer: Player? { players.first { $0.id == myPlayerId } }
    var dealer: Player? { orderedPlayers.first }
    var isDealer: Bool { dealer?.id == myPlayerId }
    var isMyTurn: Bool { room.currentTurn == myPlayerId }
    var allStanding: Bool { !orderedPlayers.isEmpty && orderedPlayers.allSatisfy(\.isStanding) }

    // MARK: - Golf-derived state

    var golfRevealed: Bool {
        guard room.golfKnockedBy != nil, !orderedPlayers.isEmpty else { return false }
        return orderedPlayers.allSatisfy { $0.hand.allSatisfy(\.faceUp) }
    }
    /// Pre-game peek phase — `current_turn` is `nil` specifically because nobody's taken a turn
    /// yet, not because the round just ended (`golfKnockedBy == nil` disambiguates the two).
    var golfPreGame: Bool { room.gameId == "golf" && room.currentTurn == nil && room.golfKnockedBy == nil }
    var golfAllPeeked: Bool { !orderedPlayers.isEmpty && orderedPlayers.allSatisfy(\.golfReady) }
    var golfPeeksLeft: Int { max(0, 2 - golfPeekUsed.count - golfPeekedNow.count) }

    func golfScore(_ hand: [Card]) -> Int {
        // This app only ever deals the built-in Golf preset (zeroRank 'Q', pairsCancel false) —
        // see LobbyService.dealGolf — so these are hardcoded rather than read from a per-room
        // config the way the web app's AI-custom-game path would.
        Deck.golfHandValue(hand, zeroRank: .queen, pairsCancel: false)
    }

    var golfStatusText: String {
        if golfRevealed { return "Round over" }
        if golfPreGame { return "Peek your cards" }
        if golfPendingDraw != nil { return "Swap or discard" }
        if isMyTurn && golfHasActedThisTurn { return "Swapped!" }
        if isMyTurn { return "It’s your turn" }
        let name = orderedPlayers.first { $0.id == room.currentTurn }?.name ?? "A player"
        return "\(name)’s turn"
    }

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

        subscribeTask = Task {
            do {
                try await ch.subscribeWithError()
            } catch {
                // A silent failure here looks identical to a real logic bug (e.g. the room's
                // view just never advancing) — surfacing it directly, even crudely, is worth
                // far more than swallowing it the way a bare `try?` would.
                print("[RoomViewModel] Realtime subscribe failed: \(error)")
            }
        }

        roomSyncTask = Task { [weak self] in
            guard let self else { return }
            for await change in roomUpdates {
                guard let updated: Room = try? change.decodeRecord(decoder: self.decoder) else { continue }
                self.applyGolfTurnTracking(for: updated)
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

    /// Golf: the deck only ever shrinks during a round — an increase means a fresh deal just
    /// landed, so reset the local peek budget and any in-flight draw. Also resets
    /// `golfHasActedThisTurn` exactly when a new turn starts for this player (not on every
    /// re-render while it's still their turn). Must run BEFORE `self.room` is reassigned, since
    /// it compares the incoming room against the previously-seen one.
    private func applyGolfTurnTracking(for newRoom: Room) {
        let len = newRoom.deck.count
        if let previousDeckCount, len > previousDeckCount {
            golfPeekedNow = []
            golfPeekUsed = []
            golfPendingDraw = nil
            golfHasActedThisTurn = false
        }
        previousDeckCount = len

        let holder = newRoom.currentTurn
        if holder == myPlayerId && previousTurnHolder != myPlayerId {
            golfHasActedThisTurn = false
        }
        previousTurnHolder = holder
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

    func dealGolf() async {
        guard isDealer, orderedPlayers.count >= 2 else {
            actionError = "Need at least 2 players to deal."
            return
        }
        isDealing = true
        defer { isDealing = false }
        do {
            try await LobbyService.dealGolf(room: room, orderedPlayers: orderedPlayers)
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Blackjack actions

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

    // MARK: - Golf actions

    func golfDrawFromDeck() async {
        guard golfPendingDraw == nil, !golfHasActedThisTurn, isMyTurn, !room.deck.isEmpty else { return }
        actionError = nil
        do {
            let card = try await GolfService.drawFromDeck(room: room)
            golfPendingDraw = GolfPendingDraw(card: card, source: .deck)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func golfDrawFromDiscard() async {
        guard golfPendingDraw == nil, !golfHasActedThisTurn, isMyTurn, !room.discardPile.isEmpty else { return }
        actionError = nil
        do {
            let card = try await GolfService.drawFromDiscard(room: room)
            golfPendingDraw = GolfPendingDraw(card: card, source: .discard)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Mirrors `handleGolfCardClick`: peeking is a private action with no turn restriction, so
    /// only the swap branch (reachable only while `golfPendingDraw` is set, which itself can
    /// only happen on your own turn) is implicitly turn-gated.
    func golfTapCard(_ card: Card, idx: Int) async {
        guard !golfRevealed, let me = myPlayer else { return }

        if let pending = golfPendingDraw {
            do {
                let oldCard = try await GolfService.performSwap(room: room, player: me, idx: idx, newCard: pending.card)
                golfPendingDraw = nil
                golfHasActedThisTurn = true
                // The replaced card is gone — free its peek-tracking, but permanently count any
                // in-progress peek as used so swapping mid-peek can't dodge the two-peek budget.
                golfPeekedNow.remove(oldCard.id)
                golfPeekUsed.insert(oldCard.id)
            } catch {
                actionError = error.localizedDescription
            }
            return
        }

        if golfPeekUsed.contains(card.id) { return }
        if golfPeekedNow.contains(card.id) {
            golfPeekedNow.remove(card.id)
            golfPeekUsed.insert(card.id)
            // Both allotted peeks now used (and closed) — tell the room this player's ready, so
            // the dealer's Start Game button can light up once everyone else is too.
            if golfPeekUsed.count >= 2 && !me.golfReady {
                await GolfService.markPeeksUsed(playerId: me.id)
            }
            return
        }
        guard golfPeekedNow.count + golfPeekUsed.count < 2 else { return }
        golfPeekedNow.insert(card.id)
    }

    func golfDiscardDrawnCard() async {
        guard let me = myPlayer, let pending = golfPendingDraw else { return }
        do {
            try await GolfService.discardDrawn(room: room, player: me, drawn: pending.card)
            golfPendingDraw = nil
            golfHasActedThisTurn = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    func golfEndTurn() async {
        guard let me = myPlayer, isMyTurn, golfPendingDraw == nil, golfHasActedThisTurn else { return }
        actionError = nil
        do {
            try await GolfService.endTurn(room: room, player: me, orderedPlayers: orderedPlayers)
            golfHasActedThisTurn = false
        } catch {
            actionError = error.localizedDescription
        }
    }

    func golfKnock() async {
        guard let me = myPlayer, isMyTurn, golfPendingDraw == nil, golfHasActedThisTurn, room.golfKnockedBy == nil else { return }
        actionError = nil
        do {
            try await GolfService.knock(room: room, player: me, orderedPlayers: orderedPlayers)
            golfHasActedThisTurn = false
        } catch {
            actionError = error.localizedDescription
        }
    }

    func golfStartGame() async {
        guard isDealer, golfPreGame, golfAllPeeked, let dealerId = dealer?.id else { return }
        actionError = nil
        do {
            try await GolfService.startGame(room: room, dealerId: dealerId)
        } catch {
            actionError = error.localizedDescription
        }
    }
}
