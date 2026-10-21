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
                // 1. Top Section: Hero Header & Target Bar
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Storage Overview")
                            .font(.system(size: 22, weight: .bold))
                        Text("Accurate APFS volume analytics, evidence-based recommendations, and space breakdown.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Liquid Glass Target Indicator Pill
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                        Text(appState.scanTargetDescription)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 240)

                        Button("Change...") {
                            appState.selectCustomFolderAndScan()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .liquidGlassCapsule(interactive: true)
                }

                // 2. Volume Capacity Card
                VolumeCapacityCard(
                    volume: appState.volumeSpace,
                    scanTargetDescription: appState.scanTargetDescription,
                    lastScanDate: appState.lastScanDate,
                    scanStatus: appState.scanStatus,
                    onScanStandard: {
                        appState.startScan()
                    },
                    onSelectFolder: {
                        appState.selectCustomFolderAndScan()
                    },
                    onCancel: {
                        appState.cancelScan()
                    }
                )

                // 3. Scan Progress (Active Traversal)
                if appState.scanStatus == .scanning {
                    ScanProgressCard(progress: appState.scanProgress, onCancel: {
                        appState.cancelScan()
                    })
                }

                // 4. Opportunities Summary & Action Banner
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

                // 5. Storage Distribution Preview
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Storage Distribution")
                                .font(.title3.weight(.bold))
                            Text("Proportional squarified treemap visualizes disk allocation from current scan.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !appState.scannedItems.isEmpty {
                            Button(action: {
                                appState.selectedSection = .treemap
                            }) {
                                HStack(spacing: 4) {
                                    Text("Explore Full Treemap")
                                    Image(systemName: "arrow.right")
                                }
                                .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                    }

                    if appState.scannedItems.isEmpty {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .frame(height: 280)

                            VStack(spacing: 12) {
                                Image(systemName: "square.grid.3x3.topleft.filled")
                                    .font(.system(size: 42))
                                    .foregroundColor(.secondary.opacity(0.7))
                                Text("No Storage Data Available")
                                    .font(.headline)
                                Text("Run a scan on standard folders or choose a custom directory above.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                LiquidGlassButton("Scan Standard Folders", icon: "arrow.triangle.2.circlepath", isProminent: true) {
                                    appState.startScan()
                                }
                                .padding(.top, 4)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    } else {
                        TreemapView(appState: appState)
                            .frame(height: 380)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }

                // 6. Top Cleanup Opportunities Preview
                if !appState.findings.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Top Cleanup Opportunities")
                                .font(.title3.weight(.bold))
                            Spacer()
                            Button("View All (\(appState.findings.count))") {
                                appState.selectedSection = .findings
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.accentColor)
                        }

                        VStack(spacing: 8) {
                            ForEach(appState.findings.prefix(5)) { finding in
                                HStack(spacing: 12) {
                                    Image(systemName: finding.category.iconName)
                                        .font(.system(size: 16))
                                        .foregroundColor(SquirrelTheme.color(for: finding.category))
                                        .frame(width: 28, height: 28)
                                        .background(SquirrelTheme.color(for: finding.category).opacity(0.12))
                                        .cornerRadius(6)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(finding.title)
                                            .font(.body.weight(.medium))
                                        Text(finding.path)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Button(action: {
                                        NSWorkspace.shared.selectFile(finding.path, inFileViewerRootedAtPath: "")
                                    }) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Reveal in Finder")

                                    Text(ByteCountFormatter.string(fromByteCount: finding.allocatedSize, countStyle: .file))
                                        .font(.subheadline.weight(.semibold).monospacedDigit())

                                    Text(finding.eligibility.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(finding.eligibility == .safeToClean ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                        )
                                        .foregroundColor(finding.eligibility == .safeToClean ? .green : .orange)
                                }
                                .padding(10)
                                .solidCard(cornerRadius: 8)
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
            Text("Only allowlisted items meeting strict safety criteria (inactive caches and old diagnostic logs) will be processed. Eligible items will be moved to managed quarantine or Trash.")
        }
    }
}

// MARK: - Subcomponents
struct VolumeCapacityCard: View {
    let volume: VolumeSpace
    let scanTargetDescription: String
    let lastScanDate: Date?
    let scanStatus: ScanStatus
    let onScanStandard: () -> Void
    let onSelectFolder: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(volume.volumeName)
                            .font(.title3.weight(.bold))
                        Text("(\(volume.mountPoint))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text("Source: \(volume.measurementSource)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)

                        Text("Status: \(scanStatus.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let date = lastScanDate {
                            Text("• Last Scan: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                if scanStatus == .scanning {
                    LiquidGlassButton("Stop Scan", icon: "xmark.circle.fill", role: .destructive, action: onCancel)
                } else {
                    LiquidGlassContainer(spacing: 8) {
                        LiquidGlassButton("Choose Folder...", icon: "folder.badge.gearshape", action: onSelectFolder)
                        LiquidGlassButton("Scan Standard", icon: "arrow.triangle.2.circlepath", isProminent: true, action: onScanStandard)
                    }
                }
            }

            if volume.totalCapacity == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Volume storage capacity is currently unavailable from macOS filesystem APIs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else {
                let fractionUsed = Double(volume.usedSpace) / Double(volume.totalCapacity)

                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.16))
                                .frame(height: 14)

                            Capsule()
                                .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geo.size.width * CGFloat(fractionUsed)), height: 14)
                        }
                    }
                    .frame(height: 14)

                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("Used: \(ByteCountFormatter.string(fromByteCount: volume.usedSpace, countStyle: .file)) (\(Int(fractionUsed * 100))%)")
                                .font(.caption.monospacedDigit())
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                            Text("Available: \(ByteCountFormatter.string(fromByteCount: volume.availableCapacity, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: volume.totalCapacity, countStyle: .file))")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }

                    if volume.opportunisticAvailableCapacity > volume.availableCapacity {
                        let purgeable = volume.opportunisticAvailableCapacity - volume.availableCapacity
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                            Text("Purgeable by macOS APFS under storage pressure: \(ByteCountFormatter.string(fromByteCount: purgeable, countStyle: .file))")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .solidCard(cornerRadius: 12)
    }
}

struct ScanProgressCard: View {
    let progress: ScanProgress
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Analyzing: \(progress.currentPath)")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(progress.itemsScannedCount) items discovered (\(ByteCountFormatter.string(fromByteCount: progress.bytesScannedTotal, countStyle: .file)))")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundColor(.red)
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 10)
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
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.green)
                    Text("Safe Cleanup Opportunity")
                        .font(.headline)
                }

                Text("Validated non-essential caches and stale diagnostic logs meeting strict safety rules.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(ByteCountFormatter.string(fromByteCount: safeToCleanBytes, countStyle: .file))
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(safeToCleanBytes > 0 ? .green : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if safeToCleanBytes > 0 {
                    LiquidGlassButton("Clean Safely (\(ByteCountFormatter.string(fromByteCount: safeToCleanBytes, countStyle: .file)))", icon: "sparkles", isProminent: true, action: onCleanSafely)
                } else {
                    Text("No Safe Batch Items Found")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }

                HStack(spacing: 12) {
                    Text("Review Recommended: \(ByteCountFormatter.string(fromByteCount: reviewBytes, countStyle: .file))")
                    Text("•")
                    Text("Duplicates: \(ByteCountFormatter.string(fromByteCount: duplicateBytes, countStyle: .file))")
                }
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .solidCard(cornerRadius: 12)
    }
}
