import SwiftUI

/// Switches between Join → Lobby → Game purely off state, rather than a `NavigationStack` —
/// the transition from Lobby to Game isn't a user-initiated push, it's the room's `state`
/// turning `.playing` out from under you (any player's realtime update can trigger it), which
/// this model handles for free since both screens just observe the same `RoomViewModel`.
struct RootView: View {
    @State private var vm: RoomViewModel?

    var body: some View {
        Group {
            if let vm {
                if vm.room.state == .playing {
                    GameView(vm: vm)
                } else {
                    LobbyView(vm: vm)
                }
            } else {
                JoinRoomView { room, player in
                    vm = RoomViewModel(room: room, myPlayerId: player.id)
                }
            }
        }
        .task(id: vm.map(ObjectIdentifier.init)) {
            guard let vm else { return }
            await vm.loadPlayers()
            vm.startSync()
        }
    }
}

#Preview {
    RootView()
}
