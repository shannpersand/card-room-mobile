import Foundation

/// Mirrors `GolfZeroRank` in card-room's `src/types.ts` — which court-card rank is worth 0 points.
enum GolfZeroRank: String, Codable {
    case queen = "Q", king = "K"
}

/// Mirrors `DealPlan` in card-room's `src/types.ts`. No CodingKeys needed — this struct lives
/// inside the `custom_game` jsonb column as a verbatim JS object, so its keys are already
/// camelCase (unlike top-level table columns, which Postgres convention keeps snake_case).
struct DealPlan: Codable, Equatable {
    let cardsPerPlayer: Int
    let splitEntireDeck: Bool    // War-style: ignore cardsPerPlayer, split whole deck evenly
    let discardPileStart: Bool   // start discard pile with 1 face-up card
    let handFaceUp: Bool         // are dealt hand cards visible to everyone (not just owner)
}

/// Mirrors `ClarifyingOption` in card-room's `src/types.ts` — only relevant to the AI-driven
/// "describe a game" flow on the web app's dealer settings panel; included here for parity
/// when reading `custom_game` off a room, not expected to be exercised by this app's own UI.
struct ClarifyingOption: Codable, Equatable {
    let key: String
    let label: String
    let type: String
    let choices: [Choice]

    struct Choice: Codable, Equatable {
        let label: String
        let value: String
    }
}

/// Mirrors `GeneratedGameConfig` in card-room's `src/types.ts` — the shape stored in a room's
/// `custom_game` column whenever `game_id == "custom"`.
struct GeneratedGameConfig: Codable, Equatable {
    let name: String
    let description: String
    let instructions: String
    let minPlayers: Int
    let maxPlayers: Int
    let turnBased: Bool
    let canDrawFromDiscard: Bool
    let showBlackjackControls: Bool
    let showHoldemControls: Bool
    let isGoFishLike: Bool
    let isGolfLike: Bool
    let golfZeroRank: GolfZeroRank
    let golfPairsCancel: Bool
    let dealPlan: DealPlan
    let clarifyingOptions: [ClarifyingOption]
}
