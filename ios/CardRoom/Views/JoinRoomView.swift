import SwiftUI

/// First real screen: enter a 4-character room code created on *either* client (this app or
/// the web app) and confirm it resolves to a live room — proves the shared-backend path works
/// end to end before any game UI gets built on top of it.
struct JoinRoomView: View {
    @State private var code = ""
    @State private var room: Room?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
                    Task { await joinRoom() }
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

                if let room {
                    VStack(spacing: 4) {
                        Text("Found room \(room.code)").bold()
                        Text(room.gameName ?? "No game selected yet")
                            .foregroundStyle(.secondary)
                        Text("State: \(room.state.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)
                }
            }
            .padding()
        }
    }

    private func joinRoom() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            room = try await RoomService.fetchRoom(code: code)
        } catch {
            room = nil
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    JoinRoomView()
}
