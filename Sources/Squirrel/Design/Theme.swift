import SwiftUI
import SquirrelCore

/// Design tokens and semantic styling adhering to Apple Human Interface Guidelines.
public enum SquirrelTheme {
    // Brand colors
    public static let brandWarm = Color(red: 0.76, green: 0.46, blue: 0.22)
    public static let brandAccent = Color.accentColor

    // Semantic category tint colors
    public static func color(for category: StorageCategory) -> Color {
        switch category {
        case .userCaches:
            return Color.teal
        case .systemLogs:
            return Color.indigo
        case .downloadsAndInstallers:
            return Color.orange
        case .largeFiles:
            return Color.purple
        case .duplicates:
            return Color.pink
        case .appLeftovers:
            return Color.yellow
        case .otherUserData:
            return Color.gray
        }
    }

    // Standard card styling with crisp native contrast
    public struct SolidCardModifier: ViewModifier {
        let cornerRadius: CGFloat

        public func body(content: Content) -> some View {
            content
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }

    // Elevated surface for sidebars and inspectors
    public struct ElevatedCardModifier: ViewModifier {
        let cornerRadius: CGFloat

        public func body(content: Content) -> some View {
            content
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
    }
}

extension View {
    /// Standard native solid surface for dense content (treemaps, listings, details) where stable contrast is required.
    public func solidCard(cornerRadius: CGFloat = 10) -> some View {
        self.modifier(SquirrelTheme.SolidCardModifier(cornerRadius: cornerRadius))
    }

    /// Elevated surface for sidebars and panels.
    public func elevatedCard(cornerRadius: CGFloat = 10) -> some View {
        self.modifier(SquirrelTheme.ElevatedCardModifier(cornerRadius: cornerRadius))
    }
}
