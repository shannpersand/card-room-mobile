import SwiftUI

/// Switches between Join → Lobby → Game purely off state, rather than a `NavigationStack` —
/// the transition from Lobby to Game isn't a user-initiated push, it's the room's `state`
/// turning `.playing` out from under you (any player's realtime update can trigger it).
struct RootView: View {
    @State private var vm: RoomViewModel?

    var body: some View {
        Group {
            if let vm {
                // Deliberately a separate view (not inlined here) holding `vm` as
                // `@ObservedObject`: RootView's own `@State` only re-renders this `Group` when
                // `vm` itself is reassigned (nil → an instance), not when a property *inside*
                // that instance changes — so without this wrapper, `room.state` flipping to
                // `.playing` would update LobbyView's own content (it has the subscription)
                // but never actually swap LobbyView out for GameView, since nothing here would
                // notice the change to re-run this `if` check.
                ConnectedRoomView(vm: vm)
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

private struct ConnectedRoomView: View {
    @ObservedObject var vm: RoomViewModel

    var body: some View {
        if vm.room.state == .playing {
            GameView(vm: vm)
        } else {
            LobbyView(vm: vm)
        }
    }
}

#Preview {
    RootView()
}
