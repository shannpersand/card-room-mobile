import SwiftUI

/// Mirrors the Golf-relevant slice of `src/pages/Game.tsx`: pre-game peek, deck/discard draw,
/// swap-or-discard, Knock!/End Turn, and round results. Assumes `vm.room.gameId == "golf"`.
struct GolfView: View {
    @ObservedObject var vm: RoomViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !otherPlayers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(otherPlayers) { player in
                            otherPlayerRow(player)
                        }
                    }
                }

                Text(vm.golfStatusText)
                    .font(.headline)
                    .foregroundStyle(.orange)

                if vm.golfRevealed {
                    roundResults
                }

                deckRow

                if let pending = vm.golfPendingDraw {
                    pendingDrawSection(pending)
                }

                myGridSection

                if vm.golfPreGame {
                    startGameSection
                } else if !vm.golfRevealed {
                    knockEndTurnSection
                }

                if let error = vm.actionError {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .padding()
        }
    }

    private var otherPlayers: [Player] {
        vm.orderedPlayers.filter { $0.id != vm.myPlayerId }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vm.room.gameName ?? "Golf").font(.title.bold())
            Text("Room \(vm.room.code) · \(vm.room.deck.count) cards left")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func otherPlayerRow(_ player: Player) -> some View {
        let isTurn = vm.room.currentTurn == player.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isTurn { Circle().fill(.green).frame(width: 8, height: 8) }
                Text(player.name).font(.subheadline.bold())
                if player.id == vm.dealer?.id { Text("★").foregroundStyle(.yellow) }
                Spacer()
                if player.id == vm.room.golfKnockedBy { Text("knocked").font(.caption).foregroundStyle(.orange) }
            }
            LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 4) {
                ForEach(Array(player.hand.prefix(4).enumerated()), id: \.offset) { _, card in
                    CardView(card: card, width: 40)
                }
            }
        }
        .padding(10)
        .background(isTurn ? Color.green.opacity(0.1) : Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var deckRow: some View {
        let canDraw = vm.isMyTurn && vm.golfPendingDraw == nil && !vm.golfHasActedThisTurn
        return HStack(spacing: 20) {
            VStack(spacing: 4) {
                Button {
                    Task { await vm.golfDrawFromDeck() }
                } label: {
                    CardView(card: Card(id: "draw-pile", suit: .spades, rank: .ace, faceUp: false), width: 52)
                }
                .disabled(!canDraw || vm.room.deck.isEmpty)
                Text("Draw · \(vm.room.deck.count)").font(.caption).foregroundStyle(.secondary)
            }
            if let top = vm.room.discardPile.last {
                VStack(spacing: 4) {
                    Button {
                        Task { await vm.golfDrawFromDiscard() }
                    } label: {
                        CardView(card: top, width: 52)
                    }
                    .disabled(!canDraw)
                    Text("Discard").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pendingDrawSection(_ pending: GolfPendingDraw) -> some View {
        VStack(spacing: 8) {
            CardView(card: Card(id: pending.card.id, suit: pending.card.suit, rank: pending.card.rank, faceUp: true), width: 60)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange, lineWidth: 2))
            Text("Tap one of your cards to swap, or discard it")
                .font(.caption).foregroundStyle(.secondary)
            Button("Discard") { Task { await vm.golfDiscardDrawnCard() } }
                .buttonStyle(.bordered)
        }
    }

    private var myGridSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your hand").font(.subheadline.bold())
                Spacer()
                if !vm.golfRevealed {
                    Text(vm.golfPendingDraw != nil ? "Tap a card to replace it" : "Peeks left: \(vm.golfPeeksLeft)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.fixed(70)), GridItem(.fixed(70))], spacing: 8) {
                ForEach(Array((vm.myPlayer?.hand ?? []).enumerated()), id: \.offset) { idx, card in
                    let peeking = vm.golfPeekedNow.contains(card.id)
                    Button {
                        Task { await vm.golfTapCard(card, idx: idx) }
                    } label: {
                        CardView(card: Card(id: card.id, suit: card.suit, rank: card.rank, faceUp: card.faceUp || peeking), isOwner: false, width: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(peeking ? .blue : .clear, lineWidth: 2)
                            )
                    }
                    .disabled(vm.golfRevealed)
                }
            }
        }
    }

    private var startGameSection: some View {
        let canStart = vm.isDealer && vm.golfAllPeeked
        return VStack(spacing: 6) {
            Button {
                Task { await vm.golfStartGame() }
            } label: {
                Text(vm.golfAllPeeked ? (vm.isDealer ? "Start Game" : "Waiting for dealer to start") : "Waiting for players to peek")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)
        }
    }

    private var knockEndTurnSection: some View {
        let resolved = vm.isMyTurn && vm.golfHasActedThisTurn && vm.golfPendingDraw == nil
        let canKnock = resolved && vm.room.golfKnockedBy == nil
        return HStack(spacing: 12) {
            Button("Knock!") { Task { await vm.golfKnock() } }
                .buttonStyle(.bordered)
                .disabled(!canKnock)
            Button("End Turn") { Task { await vm.golfEndTurn() } }
                .buttonStyle(.borderedProminent)
                .disabled(!resolved)
        }
    }

    private var roundResults: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ROUND RESULTS").font(.caption.bold()).foregroundStyle(.orange)
            ForEach(vm.orderedPlayers.sorted { vm.golfScore($0.hand) < vm.golfScore($1.hand) }) { player in
                HStack {
                    Text(player.name + (player.id == vm.room.golfKnockedBy ? " (knocked)" : ""))
                    Spacer()
                    Text("\(vm.golfScore(player.hand))").bold()
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
