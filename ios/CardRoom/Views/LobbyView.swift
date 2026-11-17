import SwiftUI

/// Mirrors the bare essentials of `src/pages/Lobby.tsx`: the player list and the dealer's
/// "deal cards" control. Only Blackjack is wired up — the web app's game picker, AI "describe a
/// game" flow, and Saved Games are all out of scope for this pass (see README).
struct LobbyView: View {
    @ObservedObject var vm: RoomViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Room Code").font(.caption).foregroundStyle(.secondary)
                Text(vm.room.code).font(.largeTitle.bold().monospaced())
            }
            .padding(.top, 32)

            VStack(alignment: .leading, spacing: 0) {
                Text("Players (\(vm.orderedPlayers.count))")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                ForEach(vm.orderedPlayers) { player in
                    HStack {
                        if player.id == vm.dealer?.id {
                            Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                        }
                        Text(player.name)
                        if player.id == vm.myPlayerId {
                            Text("(you)").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
            }
            .padding(.horizontal)

            Spacer()

            if vm.isDealer {
                Button {
                    Task { await vm.dealBlackjack() }
                } label: {
                    if vm.isDealing {
                        ProgressView()
                    } else {
                        Text("Deal Blackjack").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.orderedPlayers.count < 2 || vm.isDealing)
                .padding(.horizontal, 40)

                if vm.orderedPlayers.count < 2 {
                    Text("Need at least 2 players to deal.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("Waiting for the dealer to deal...")
                    .foregroundStyle(.secondary)
            }

            if let error = vm.actionError {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .padding(.bottom, 40)
    }
}
