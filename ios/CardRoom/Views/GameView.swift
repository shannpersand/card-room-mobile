import SwiftUI

/// Mirrors the Blackjack-relevant slice of `src/pages/Game.tsx`. Only Blackjack is implemented
/// — this view assumes `vm.room.gameId == "blackjack"` (the only mode `LobbyView` can deal).
struct GameView: View {
    @ObservedObject var vm: RoomViewModel

    private var myValue: Int { vm.myPlayer.map { Deck.blackjackValue($0.hand) } ?? 0 }
    private var dealerValue: Int { vm.dealer.map { Deck.blackjackValue($0.hand) } ?? 0 }
    private var allDone: Bool { vm.allStanding && !vm.orderedPlayers.isEmpty }

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

                if vm.isDealer {
                    Button("Reveal Hand") { Task { await vm.revealDealerHand() } }
                        .font(.caption)
                }

                if allDone {
                    roundResults
                }

                myHandSection

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
            Text(vm.room.gameName ?? "Blackjack").font(.title.bold())
            Text("Room \(vm.room.code) · \(vm.room.deck.count) cards left")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func otherPlayerRow(_ player: Player) -> some View {
        let isTurn = vm.room.currentTurn == player.id
        let value = Deck.blackjackValue(player.hand)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isTurn { Circle().fill(.green).frame(width: 8, height: 8) }
                Text(player.name).font(.subheadline.bold())
                if player.id == vm.dealer?.id { Text("★").foregroundStyle(.yellow) }
                Spacer()
                if player.isStanding {
                    Text(value > 21 ? "BUST" : "STAND")
                        .font(.caption.bold())
                        .foregroundStyle(value > 21 ? .red : .orange)
                }
            }
            HStack(spacing: 4) {
                ForEach(player.hand) { card in
                    CardView(card: card, width: 40)
                }
            }
        }
        .padding(10)
        .background(isTurn ? Color.green.opacity(0.1) : Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var myHandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your hand").font(.subheadline.bold())
                Spacer()
                Text("Value: \(myValue)").font(.subheadline)
            }
            HStack(spacing: 6) {
                ForEach(vm.myPlayer?.hand ?? []) { card in
                    CardView(card: card, isOwner: true, width: 52)
                }
            }

            if let me = vm.myPlayer {
                if me.isStanding {
                    Text(myValue > 21 ? "You busted on \(myValue)." : "You stood on \(myValue).")
                        .foregroundStyle(.secondary)
                } else if vm.isMyTurn {
                    HStack(spacing: 12) {
                        Button("Hit") { Task { await vm.hit() } }
                            .buttonStyle(.borderedProminent)
                        Button("Stand") { Task { await vm.stand() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    let turnPlayer = vm.orderedPlayers.first { $0.id == vm.room.currentTurn }
                    Text("Waiting for \(turnPlayer?.name ?? "the next player")...")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 8)
    }

    private var roundResults: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ROUND RESULTS").font(.caption.bold()).foregroundStyle(.orange)
            ForEach(vm.orderedPlayers.dropFirst()) { player in
                let value = Deck.blackjackValue(player.hand)
                let outcome = GameService.outcome(playerValue: value, dealerValue: dealerValue)
                let label = outcome == "win" ? "Win" : outcome == "lose" ? (value > 21 ? "Bust" : "Lose") : "Push"
                let color: Color = outcome == "win" ? .green : outcome == "lose" ? .red : .secondary
                HStack {
                    Text("\(player.name) (\(value))")
                    Spacer()
                    Text(label).bold().foregroundStyle(color)
                }
                .font(.subheadline)
            }
            if vm.dealer != nil {
                Divider()
                HStack {
                    Text("Dealer (\(dealerValue))")
                    Spacer()
                    if dealerValue > 21 { Text("Bust").bold().foregroundStyle(.red) }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
