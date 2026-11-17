import SwiftUI

/// A single playing card, rendered with card-room's actual card art (see `CardArt.swift` for
/// where the asset catalog images came from).
struct CardView: View {
    let card: Card
    var isOwner: Bool = false
    var width: CGFloat = 52
    /// The room's `back_color` (e.g. "blue", "gold") — picks which pre-recolored back art to
    /// show for a face-down card. Defaults to blue, same as the web app's `DEFAULT_BACK_COLOR`.
    var backColor: String? = nil

    private var showFace: Bool { isOwner || card.faceUp }
    private var height: CGFloat { width * (249.84 / 177.84) }

    var body: some View {
        Image(showFace ? CardArt.frontAssetName(card) : CardArt.backAssetName(backColor))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.08)
                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
            )
    }
}

#Preview {
    HStack {
        CardView(card: Card(id: "A-spades", suit: .spades, rank: .ace, faceUp: true))
        CardView(card: Card(id: "K-hearts", suit: .hearts, rank: .king, faceUp: false), isOwner: false, backColor: "gold")
    }
}
