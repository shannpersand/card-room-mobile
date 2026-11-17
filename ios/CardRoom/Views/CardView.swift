import SwiftUI

/// A single playing card. Face-down renders a plain colored back (no card-art assets have been
/// ported from card-room's web bundle yet — this is a deliberately simple native placeholder,
/// not a port of the web app's SVG card art).
struct CardView: View {
    let card: Card
    var isOwner: Bool = false
    var width: CGFloat = 52

    private var showFace: Bool { isOwner || card.faceUp }
    private var isRed: Bool { card.suit == .hearts || card.suit == .diamonds }

    private var suitSymbol: String {
        switch card.suit {
        case .spades: return "♠"
        case .hearts: return "♥"
        case .diamonds: return "♦"
        case .clubs: return "♣"
        }
    }

    private var rankLabel: String {
        card.rank == .joker ? "J*" : card.rank.rawValue
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(showFace ? Color.white : Color.blue)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
            )
            .overlay {
                if showFace {
                    VStack(spacing: 2) {
                        Text(rankLabel).font(.system(size: width * 0.26, weight: .bold))
                        Text(suitSymbol).font(.system(size: width * 0.3))
                    }
                    .foregroundStyle(isRed ? .red : .black)
                }
            }
            .frame(width: width, height: width * 1.4)
    }
}

#Preview {
    HStack {
        CardView(card: Card(id: "A-spades", suit: .spades, rank: .ace, faceUp: true))
        CardView(card: Card(id: "K-hearts", suit: .hearts, rank: .king, faceUp: false), isOwner: false)
    }
}
