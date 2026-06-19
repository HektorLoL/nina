import SwiftUI
import UIKit

enum NinaTheme {
    static let mint = Color(red: 0.22, green: 0.76, blue: 0.72)
    static let mintInk = dynamic(
        light: UIColor(red: 0.11, green: 0.43, blue: 0.35, alpha: 1),
        dark: UIColor(red: 0.55, green: 0.95, blue: 0.86, alpha: 1)
    )
    static let coral = Color(red: 0.98, green: 0.45, blue: 0.38)
    static let sky = Color(red: 0.29, green: 0.58, blue: 0.96)
    static let amber = Color(red: 0.96, green: 0.70, blue: 0.22)
    static let gold = Color(red: 1.00, green: 0.78, blue: 0.22)
    static let lavender = Color(red: 0.62, green: 0.48, blue: 0.94)
    static let avatarFace = Color(red: 1.00, green: 0.98, blue: 0.93)
    static let avatarInk = Color(red: 0.12, green: 0.15, blue: 0.18)
    static let premiumInk = Color(red: 0.14, green: 0.10, blue: 0.04)

    static let ink = dynamic(
        light: UIColor(red: 0.12, green: 0.15, blue: 0.18, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.96, blue: 0.95, alpha: 1)
    )
    static let muted = dynamic(
        light: UIColor(red: 0.44, green: 0.48, blue: 0.52, alpha: 1),
        dark: UIColor(red: 0.68, green: 0.73, blue: 0.76, alpha: 1)
    )
    static let paper = dynamic(
        light: UIColor(red: 1.00, green: 0.98, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.13, blue: 0.15, alpha: 1)
    )
    static let cream = dynamic(
        light: UIColor(red: 1.00, green: 0.95, blue: 0.87, alpha: 1),
        dark: UIColor(red: 0.17, green: 0.18, blue: 0.19, alpha: 1)
    )
    static let line = dynamic(
        light: UIColor(red: 0.90, green: 0.88, blue: 0.82, alpha: 1),
        dark: UIColor(red: 0.27, green: 0.31, blue: 0.33, alpha: 1)
    )
    static let card = dynamic(
        light: UIColor(red: 1.00, green: 0.98, blue: 0.94, alpha: 0.88),
        dark: UIColor(red: 0.13, green: 0.16, blue: 0.18, alpha: 0.94)
    )
    static let field = dynamic(
        light: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.94),
        dark: UIColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 0.96)
    )
    static let bar = dynamic(
        light: UIColor(red: 1.00, green: 0.98, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.11, blue: 0.13, alpha: 1)
    )
    static let sheet = dynamic(
        light: UIColor(red: 1.00, green: 0.99, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1)
    )
    static let cardStroke = dynamic(
        light: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.75),
        dark: UIColor(red: 0.24, green: 0.29, blue: 0.31, alpha: 0.90)
    )
    static let taskCard = dynamic(
        light: UIColor(red: 1.00, green: 0.98, blue: 0.94, alpha: 0.88),
        dark: UIColor(red: 0.13, green: 0.16, blue: 0.18, alpha: 0.94)
    )
    static let taskCardStroke = dynamic(
        light: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.75),
        dark: UIColor(red: 0.24, green: 0.29, blue: 0.31, alpha: 0.90)
    )
    static let shadow = dynamic(
        light: UIColor(red: 0.12, green: 0.15, blue: 0.18, alpha: 0.08),
        dark: UIColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.36)
    )

    private static let screenTop = dynamic(
        light: UIColor(red: 1.00, green: 0.995, blue: 0.975, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.10, blue: 0.11, alpha: 1)
    )
    private static let screenMiddle = dynamic(
        light: UIColor(red: 1.00, green: 0.985, blue: 0.955, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 1)
    )
    private static let screenBottom = dynamic(
        light: UIColor(red: 1.00, green: 0.995, blue: 0.975, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.10, blue: 0.11, alpha: 1)
    )

    static let screenGradient = LinearGradient(
        colors: [screenTop, screenMiddle, screenBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let premiumGradient = LinearGradient(
        colors: [gold, mint, lavender],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

extension MemberTone {
    var color: Color {
        switch self {
        case .mint: NinaTheme.mint
        case .coral: NinaTheme.coral
        case .sky: NinaTheme.sky
        case .amber: NinaTheme.amber
        case .lavender: NinaTheme.lavender
        }
    }

    var softColor: Color {
        color.opacity(0.16)
    }
}

extension View {
    func ninaScreenBackground() -> some View {
        background(NinaTheme.screenGradient.ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    func ninaSheetBackground() -> some View {
        background(NinaTheme.sheet.ignoresSafeArea())
            .toolbarBackground(NinaTheme.sheet, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    func cardShadow() -> some View {
        shadow(color: NinaTheme.shadow, radius: 18, x: 0, y: 10)
    }
}
