import SwiftUI
import SquirrelCore

public struct DashboardView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Squirrel Brand Header
                HStack(spacing: 14) {
                    if let imagePath = Bundle.module.path(forResource: "AppIcon", ofType: "png"),
                       let nsImg = NSImage(contentsOfFile: imagePath) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .cornerRadius(10)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 0.65, green: 0.42, blue: 0.22))
                                .frame(width: 48, height: 48)
                            Image(systemName: "leaf.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Squirrel")
                            .font(.system(size: 22, weight: .bold))
                        Text("A little more room for your Mac.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 2)

                // 1. Storage Capacity Card
                VolumeCapacityCard(
                    volume: appState.volumeSpace,
                    lastScanDate: appState.lastScanDate,
                    scanStatus: appState.scanStatus,
                    onScan: {
                        appState.startScan()
                    },
                    onCancel: {
                        appState.cancelScan()
                    }
                )

                // 2. Scan Progress (if active)
                if appState.scanStatus == .scanning {
                    ScanProgressCard(progress: appState.scanProgress)
                }

                // 3. Cleanup Opportunities & Action Banner
                if appState.scanStatus == .completed {
                    OpportunitiesSummaryCard(
                        safeToCleanBytes: appState.safeToCleanBytes,
                        reviewBytes: appState.reviewRecommendedBytes,
                        duplicateBytes: appState.duplicatePotentialReclaimBytes,
                        onCleanSafely: {
                            appState.showCleanSafelyConfirm = true
                        }
                    )
                }

                // 4. Interactive Treemap Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Storage Distribution")
                                .font(.title3.weight(.bold))
                            Text("Interactive squarified treemap visualizes proportional storage consumption.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    if appState.scannedItems.isEmpty {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .frame(height: 320)

                            VStack(spacing: 12) {
                                Image(systemName: "square.grid.3x3.topleft.filled")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No Storage Data Available")
                                    .font(.headline)
                                Text("Click 'Scan Disk' above to map real disk usage.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        TreemapView(appState: appState)
                            .frame(height: 380)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                }

                // 5. Top Cleanup Opportunities Preview
                if !appState.findings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Cleanup Opportunities")
                            .font(.title3.weight(.bold))

                        VStack(spacing: 8) {
                            ForEach(appState.findings.prefix(5)) { finding in
                                HStack {
                                    Image(systemName: finding.category.iconName)
                                        .foregroundColor(finding.eligibility == .safeToClean ? .green : .orange)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(finding.title)
                                            .font(.body.weight(.medium))
                                        Text(finding.ruleDescription)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(ByteCountFormatter.string(fromByteCount: finding.allocatedSize, countStyle: .file))
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                }
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .confirmationDialog(
            "Execute Safe Cleanup?",
            isPresented: Binding(
                get: { appState.showCleanSafelyConfirm },
                set: { appState.showCleanSafelyConfirm = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Clean Safely (\(ByteCountFormatter.string(fromByteCount: appState.safeToCleanBytes, countStyle: .file)))", role: .destructive) {
                appState.executeSafeBatch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only allowlisted items meeting strict safety criteria (inactive caches and old logs) will be processed. Eligible items will be moved to managed quarantine or Trash.")
        }
    }
}

// MARK: - Subcomponents
struct VolumeCapacityCard: View {
    let volume: VolumeSpace
    let lastScanDate: Date?
    let scanStatus: ScanStatus
    let onScan: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.volumeName)
                        .font(.title3.weight(.bold))
                    HStack(spacing: 6) {
                        Text("Status: \(scanStatus.rawValue)")
                        if let date = lastScanDate {
                            Text("• Last Scan: \(date.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                if scanStatus == .scanning {
                    Button(action: onCancel) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                            Text("Stop Scan")
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onScan) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Scan Disk")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }

            let fractionUsed = volume.totalCapacity > 0 ? Double(volume.usedSpace) / Double(volume.totalCapacity) : 0.0

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 12)

                        Capsule()
                            .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * CGFloat(fractionUsed)), height: 12)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("Used: \(ByteCountFormatter.string(fromByteCount: volume.usedSpace, countStyle: .file)) (\(Int(fractionUsed * 100))%)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("Available: \(ByteCountFormatter.string(fromByteCount: volume.availableCapacity, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: volume.totalCapacity, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct ScanProgressCard: View {
    let progress: ScanProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Analyzing: \(progress.currentPath)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(progress.itemsScannedCount) items (\(ByteCountFormatter.string(fromByteCount: progress.bytesScannedTotal, countStyle: .file)))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct OpportunitiesSummaryCard: View {
    let safeToCleanBytes: Int64
    let reviewBytes: Int64
    let duplicateBytes: Int64
    let onCleanSafely: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Safe Cleanup Opportunity")
                    .font(.headline)
                Text("Validated non-essential caches and stale diagnostic logs.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(ByteCountFormatter.string(fromByteCount: safeToCleanBytes, countStyle: .file))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundColor(safeToCleanBytes > 0 ? .green : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if safeToCleanBytes > 0 {
                    Button(action: onCleanSafely) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Clean Safely (\(ByteCountFormatter.string(fromByteCount: safeToCleanBytes, countStyle: .file)))")
                        }
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                } else {
                    Text("No Safe Batch Items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Text("Review Recommended: \(ByteCountFormatter.string(fromByteCount: reviewBytes, countStyle: .file))")
                    Text("•")
                    Text("Duplicates: \(ByteCountFormatter.string(fromByteCount: duplicateBytes, countStyle: .file))")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}
