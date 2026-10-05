import SwiftUI

// One constant for the whole app; web/src/rating.ts holds the same code and the preflight fails when they differ.
enum NinaRating {
    static let currentCode = "L"

    static let knownCodes = ["L", "10", "12", "14", "16", "18"]

    static var current: NinaRatingDescriptor {
        NinaRatingDescriptor(code: currentCode)
    }
}

struct NinaRatingDescriptor: Hashable {
    var code: String

    var isLivre: Bool {
        code == "L"
    }

    var name: String {
        isLivre ? "Livre" : "Não recomendado para menores de \(code) anos"
    }

    var symbolText: String {
        code
    }

    var accessibilityLabel: String {
        isLivre
            ? "Classificação indicativa: livre"
            : "Classificação indicativa: não recomendado para menores de \(code) anos"
    }

    var termsPhrase: String {
        isLivre ? "livre" : "não recomendada para menores de \(code) anos"
    }
}

// The symbol shows only what NinaRating.currentCode says; the screen never decides a rating of its own.
struct ClassIndMark: View {
    var rating: NinaRatingDescriptor = NinaRating.current
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(NinaTheme.classInd(rating.code))
            .frame(width: size, height: size)
            .overlay(
                Text(rating.symbolText)
                    .font(.system(size: size * (rating.symbolText.count > 1 ? 0.46 : 0.58), weight: .heavy))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.5)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rating.accessibilityLabel)
    }
}
