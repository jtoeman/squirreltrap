import SwiftUI

/// Text and card styling for the frosted-blue-glass look. Kept as explicit values
/// rather than system semantic colors (.primary/.secondary) because the panel's
/// appearance is deliberately forced to vibrantDark for the glass material to
/// render at all — at that point, explicit control over exactly how "white" each
/// text tier is matters more than automatic light/dark adaptation.
extension Color {
    /// Headlines, item text, anything that should read as the main content.
    static let panelTextPrimary = Color.white.opacity(0.95)

    /// Captions, section labels, explainer text — present but de-emphasized.
    static let panelTextSecondary = Color.white.opacity(0.7)
}

/// A single floating glass card: brighter translucent blue than the panel
/// background, a soft light-to-clear top edge to suggest a glass highlight, and a
/// gentle drop shadow so it visibly separates from the tinted background behind it.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.24))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.32), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
