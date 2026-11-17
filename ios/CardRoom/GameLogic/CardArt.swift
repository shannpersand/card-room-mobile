import Foundation

/// Mirrors the asset-naming side of card-room's `src/lib/cardArt.ts`. The actual art is
/// pre-rendered PNGs (converted from the web app's `src/assets/cards/*.svg` via a one-time
/// Playwright/Chromium render — Xcode's native SVG-in-asset-catalog import silently produces a
/// blank image for these particular files, confirmed empirically, likely because its SVG
/// subset doesn't handle a `<style>`-block-with-CSS-classes the way these are authored) baked
/// directly into `Assets.xcassets`, not fetched/recolored at runtime the way the web app's
/// card backs are — there are 6 pre-recolored `back-<color>` variants instead, one per
/// `BackColorKey`.
enum CardArt {
    private static let suitLetter: [Suit: String] = [.spades: "s", .hearts: "h", .diamonds: "d", .clubs: "c"]

    /// Asset catalog name for a card's face, e.g. "As", "10c", "Qh", "joker".
    static func frontAssetName(_ card: Card) -> String {
        if card.rank == .joker { return "joker" }
        return "\(card.rank.rawValue)\(suitLetter[card.suit] ?? "s")"
    }

    /// Asset catalog name for a recolored card back, e.g. "back-blue". Falls back to "back-blue"
    /// for an unrecognized/missing color key, same as `resolveBackColorHex`'s `DEFAULT_BACK_COLOR`.
    static func backAssetName(_ colorKey: String?) -> String {
        let known: Set<String> = ["blue", "red", "green", "purple", "black", "gold"]
        let key = colorKey.flatMap { known.contains($0) ? $0 : nil } ?? "blue"
        return "back-\(key)"
    }
}
