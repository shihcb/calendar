import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Cross-platform Tactile Haptic Generator for iOS & macOS
public struct HapticManager {
    public static func trigger(_ style: HapticStyle = .light) {
        #if os(iOS)
        switch style {
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        }
        #elseif os(macOS)
        let performance = NSHapticFeedbackManager.defaultPerformer
        switch style {
        case .light, .medium:
            performance.perform(.alignment, performanceTime: .now)
        case .heavy, .success, .warning:
            performance.perform(.levelChange, performanceTime: .now)
        }
        #endif
    }
}

public enum HapticStyle {
    case light
    case medium
    case heavy
    case success
    case warning
}

/// View Modifier to trigger haptic feedback on tap / button click
public struct HapticTapModifier: ViewModifier {
    let style: HapticStyle
    
    public func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    HapticManager.trigger(style)
                }
            )
    }
}

extension View {
    public func withHaptic(_ style: HapticStyle = .light) -> some View {
        self.modifier(HapticTapModifier(style: style))
    }
}
