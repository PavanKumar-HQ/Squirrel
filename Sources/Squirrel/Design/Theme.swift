import SwiftUI
import SquirrelCore

/// Design tokens and semantic styling adhering to Apple Human Interface Guidelines.
public enum SquirrelTheme {
    // Brand colors
    public static let brandWarm = Color(red: 0.76, green: 0.46, blue: 0.22)
    public static let brandAccent = Color.accentColor

    // Semantic category tint colors adhering to Apple HIG
    public static func color(for category: StorageCategory) -> Color {
        switch category {
        case .userCaches:
            return Color(red: 0.18, green: 0.64, blue: 0.74) // Refined Ocean Teal
        case .systemLogs:
            return Color(red: 0.42, green: 0.46, blue: 0.80) // Slate Indigo
        case .downloadsAndInstallers:
            return Color(red: 0.90, green: 0.52, blue: 0.20) // Warm Amber
        case .largeFiles:
            return Color(red: 0.66, green: 0.38, blue: 0.84) // Royal Violet
        case .duplicates:
            return Color(red: 0.88, green: 0.35, blue: 0.42) // Coral Rose
        case .appLeftovers:
            return Color(red: 0.88, green: 0.68, blue: 0.22) // Warm Gold
        case .otherUserData:
            return Color(red: 0.52, green: 0.56, blue: 0.62) // Neutral Slate
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

extension Color {
    public init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
