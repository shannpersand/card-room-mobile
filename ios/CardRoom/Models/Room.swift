import Foundation

/// Mirrors `GameState` in card-room's `src/types.ts`.
enum GameState: String, Codable {
    case lobby, playing, finished
}

/// Mirrors `HoldemStage` in card-room's `src/types.ts`.
enum HoldemStage: String, Codable {
    case preflop, flop, turn, river
}

/// Mirrors `Room` in card-room's `src/types.ts` — the `rooms` table. This is the row every
/// client (web and this app alike) reads/writes and subscribes to via Realtime to stay in sync.
struct Room: Codable, Identifiable, Equatable {
    let id: String
    let code: String
    let gameId: String?
    let gameName: String?
    let state: GameState
    let deck: [Card]
    let communityCards: [Card]
    let discardPile: [Card]
    let currentTurn: String?       // player id
    let holdemStage: HoldemStage?
    let customGame: GeneratedGameConfig?
    let actionLog: [String]
    let backColor: String
    let golfKnockedBy: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case gameId = "game_id"
        case gameName = "game_name"
        case state
        case deck
        case communityCards = "community_cards"
        case discardPile = "discard_pile"
        case currentTurn = "current_turn"
        case holdemStage = "holdem_stage"
        case customGame = "custom_game"
        case actionLog = "action_log"
        case backColor = "back_color"
        case golfKnockedBy = "golf_knocked_by"
        case createdAt = "created_at"
    }
}
