import SwiftUI

/// Animated scanning globe with orbital pulse wave for disk and system sweeps.
/// Uses PhaseAnimator / TimelineView without @State to ensure 100% compatibility
/// with Apple CommandLineTools Swift compilers.
public struct ScanningGlobeView: View {
    let icon: String
    let subtitle: String

    public init(icon: String = "globe.americas.fill", subtitle: String = "Scanning...") {
        self.icon = icon
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: 12) {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let angle = (time.truncatingRemainder(dividingBy: 3.0)) / 3.0 * 360.0
                let pulse = 1.0 + 0.2 * sin(time * 3.0)

                ZStack {
                    // Pulsing ring
                    Circle()
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                        .scaleEffect(CGFloat(pulse))

                    // Globe core
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 26, height: 26)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .rotationEffect(.degrees(angle))
                }
                .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                Text("Analyzing system storage")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Animated moon with twinkling glow for developer workspace scanning.
public struct DevMoonScanningView: View {
    let subtitle: String

    public init(subtitle: String = "Scanning Repositories...") {
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let pulse = 1.0 + 0.15 * sin(time * 2.5)

                ZStack {
                    Circle()
                        .fill(SquirrelTheme.brandWarm.opacity(0.18))
                        .frame(width: 32, height: 32)
                        .scaleEffect(CGFloat(pulse))

                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 15))
                        .foregroundColor(SquirrelTheme.brandWarm)
                }
                .frame(width: 34, height: 34)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Developer Sweep")
                    .font(.system(size: 11, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
