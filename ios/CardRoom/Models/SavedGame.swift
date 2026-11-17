import Foundation

/// Mirrors `SavedGame` in card-room's `src/types.ts` — the `saved_games` table (reusable
/// AI-designed/edited game configs, shared across all players and all clients).
struct SavedGame: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let config: GeneratedGameConfig
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case config
        case createdAt = "created_at"
    }
}
