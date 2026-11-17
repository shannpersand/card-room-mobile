import SwiftUI

/// Join a room by its 4-character code — mirrors `joinRoom()` in `src/pages/Landing.tsx`:
/// inserts a real player row (or reuses this device's existing one if rejoining), not just a
/// read-only lookup.
struct JoinRoomView: View {
    let onJoined: (Room, Player) -> Void

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Card Room")
                .font(.largeTitle.bold())

            TextField("Room code", text: $code)
                .textCase(.uppercase)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .multilineTextAlignment(.center)
                .font(.title2.monospaced())
                .padding()
                .background(.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.prefix(4))
                }

            Button {
                Task { await join() }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Join Room")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.count != 4 || isLoading)
            .padding(.horizontal, 40)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func join() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            // Only used if this is a brand-new player (joinOrRejoin ignores it when reusing an
            // existing seat) — no name customization UI yet, matching this pass's scope.
            let (room, player) = try await RoomService.joinOrRejoin(code: code, playerName: FunName.generate())
            onJoined(room, player)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    JoinRoomView(onJoined: { _, _ in })
}
