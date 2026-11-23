import SwiftUI
import SquirrelCore

/// Clean, native Apple macOS UI effect for active scanning sweeps.
/// Refined, minimal typography and subtle native animations — strictly no neon colors and no gradients.
public struct NativeScanEffectView: View {
    let title: String
    let subtitle: String

    public init(title: String = "Scanning Storage...", subtitle: String = "Auditing caches & artifacts") {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: 12) {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let angle = (time.truncatingRemainder(dividingBy: 2.0)) / 2.0 * 360.0

                ZStack {
                    // Outer subtle circular track
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1.5)
                        .frame(width: 28, height: 28)

                    // Rotating scanning arc (flat accent color, no gradients)
                    Circle()
                        .trim(from: 0.0, to: 0.28)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(angle))

                    // Minimal center dot
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 4, height: 4)
                }
                .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Clean, native Apple macOS UI card for live deletion progress.
/// Uses standard Apple solid colors, monospaced typography, and flat system progress bars.
/// Strictly zero neon colors and zero gradients.
public struct NativeDeleteEffectView: View {
    let currentItem: String
    let cleanedBytes: Int64
    let totalBytes: Int64
    let cleanedCount: Int
    let totalCount: Int

    public init(
        currentItem: String,
        cleanedBytes: Int64,
        totalBytes: Int64,
        cleanedCount: Int,
        totalCount: Int
    ) {
        self.currentItem = currentItem
        self.cleanedBytes = cleanedBytes
        self.totalBytes = totalBytes
        self.cleanedCount = cleanedCount
        self.totalCount = totalCount
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Minimal trash icon with subtle native pulsing opacity
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let opacity = 0.65 + 0.35 * abs(sin(time * 2.5))

                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.04))
                        .frame(width: 42, height: 42)

                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .opacity(opacity)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                        Text("Cleaning in progress...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Text(SquirrelFormatters.formatPrecise(cleanedBytes))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                    +
                    Text(" / \(SquirrelFormatters.formatPrecise(totalBytes))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Flat solid system progress bar (NO gradients, NO neon)
                let fraction: Double = totalBytes > 0 ? min(1.0, Double(cleanedBytes) / Double(totalBytes)) : 0
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(6, geo.size.width * CGFloat(fraction)), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(currentItem.isEmpty ? "Preparing safe trash move..." : "Removing: \(currentItem)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text("\(cleanedCount) of \(totalCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

