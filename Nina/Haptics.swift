import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum Haptics {
    static func selection() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    static func lightImpact() {
        #if canImport(UIKit)
        impact(.light)
        #endif
    }

    static func mediumImpact() {
        #if canImport(UIKit)
        impact(.medium)
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        notification(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        notification(.warning)
        #endif
    }

    static func error() {
        #if canImport(UIKit)
        notification(.error)
        #endif
    }

    #if canImport(UIKit)
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
    #endif
}
