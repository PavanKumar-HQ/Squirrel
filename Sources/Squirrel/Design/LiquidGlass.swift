import SwiftUI

/// Reusable Apple Liquid Glass design language integration for Squirrel.
/// Uses native macOS 26+ / 27+ Liquid Glass APIs (glassEffect, GlassEffectContainer, .glass buttonStyle)
/// with seamless, high-fidelity fallback to ultraThinMaterial and specular borders on earlier macOS versions.
public struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tintColor: Color?

    public init(shape: S, interactive: Bool = false, tintColor: Color? = nil) {
        self.shape = shape
        self.interactive = interactive
        self.tintColor = tintColor
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let baseGlass: Glass = Glass.regular
            let tintedGlass: Glass = tintColor.map { baseGlass.tint($0) } ?? baseGlass
            let finalGlass: Glass = interactive ? tintedGlass.interactive() : tintedGlass
            content
                .glassEffect(finalGlass, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
    }
}

extension View {
    /// Applies native Liquid Glass to this view using the specified shape and optional tint.
    public func liquidGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        self.modifier(LiquidGlassModifier(shape: shape, interactive: interactive, tintColor: tint))
    }

    /// Convenience modifier for capsule-shaped Liquid Glass controls.
    public func liquidGlassCapsule(interactive: Bool = false, tint: Color? = nil) -> some View {
        self.modifier(LiquidGlassModifier(shape: Capsule(), interactive: interactive, tintColor: tint))
    }

    /// Convenience modifier for rounded-rectangle Liquid Glass containers.
    public func liquidGlassCard(cornerRadius: CGFloat = 12, interactive: Bool = false, tint: Color? = nil) -> some View {
        self.modifier(LiquidGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive, tintColor: tint))
    }
}

/// Coordinated container grouping multiple interactive glass elements.
public struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    public init(spacing: CGFloat? = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            HStack(spacing: spacing) {
                content()
            }
            .padding(6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        }
    }
}

/// Native interactive button with Apple Liquid Glass styling where supported.
public struct LiquidGlassButton: View {
    let title: String
    let icon: String?
    let isProminent: Bool
    let role: ButtonRole?
    let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        isProminent: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isProminent = isProminent
        self.role = role
        self.action = action
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            if isProminent {
                Button(role: role, action: action) {
                    buttonLabel
                }
                .buttonStyle(GlassProminentButtonStyle())
            } else {
                Button(role: role, action: action) {
                    buttonLabel
                }
                .buttonStyle(GlassButtonStyle())
            }
        } else {
            if isProminent {
                Button(role: role, action: action) {
                    buttonLabel
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else {
                Button(role: role, action: action) {
                    buttonLabel
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var buttonLabel: some View {
        HStack(spacing: 5) {
            if let icon = icon {
                Image(systemName: icon)
            }
            Text(title)
        }
    }
}
