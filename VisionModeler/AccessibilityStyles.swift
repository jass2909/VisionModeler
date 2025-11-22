import SwiftUI

struct HighContrastButtonStyle: ButtonStyle {
    let enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if enabled {
                configuration.label
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 100))
                    .overlay(
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(Color.white, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.95), radius: 0, x: 1, y: 0)
                    .shadow(color: .black.opacity(0.95), radius: 0, x: -1, y: 0)
                    .shadow(color: .black.opacity(0.95), radius: 0, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.95), radius: 0, x: 0, y: -1)
                    .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            } else {
                configuration.label
            }
        }
    }
}

struct HighContrastTextOutline: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: .black.opacity(0.95), radius: 0, x: 1, y: 0)
                .shadow(color: .black.opacity(0.95), radius: 0, x: -1, y: 0)
                .shadow(color: .black.opacity(0.95), radius: 0, x: 0, y: 1)
                .shadow(color: .black.opacity(0.95), radius: 0, x: 0, y: -1)
        } else {
            content
        }
    }
}

extension View {
    func highContrastTextOutline(_ enabled: Bool) -> some View {
        self.modifier(HighContrastTextOutline(enabled: enabled))
    }
}
