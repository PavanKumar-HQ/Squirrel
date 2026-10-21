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

                    // Native Target Indicator Pill
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 0.8))
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

                // 5. Storage Distribution Breakdown Bar (Fast, zero-lag overview)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Storage Distribution")
                                .font(.title3.weight(.bold))
                            Text("Disk space allocation by category from current scan.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !appState.scannedItems.isEmpty {
                            Button(action: {
                                appState.selectedSection = .treemap
                            }) {
                                HStack(spacing: 4) {
                                    Text("Open Interactive Treemap")
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
                                .frame(height: 140)

                            VStack(spacing: 10) {
                                Image(systemName: "square.grid.3x3.topleft.filled")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary.opacity(0.7))
                                Text("No Scan Data Available")
                                    .font(.headline)
                                Text("Run a scan on standard folders or choose a custom directory above.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    } else {
                        StorageCategoryBreakdownBar(appState: appState)
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
                    Button(role: .destructive, action: onCancel) {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Stop Scan")
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 8) {
                        Button(action: onSelectFolder) {
                            HStack(spacing: 5) {
                                Image(systemName: "folder.badge.gearshape")
                                Text("Choose Folder...")
                            }
                        }
                        .buttonStyle(.bordered)

                        Button(action: onScanStandard) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Scan Standard")
                            }
                        }
                        .buttonStyle(.borderedProminent)
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
                                .frame(height: 12)

                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(8, geo.size.width * CGFloat(fractionUsed)), height: 12)
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
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

struct StorageCategoryBreakdownBar: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let categoryTotals = computeCategoryTotals()
            let totalScanned = categoryTotals.values.reduce(0, +)

            if totalScanned > 0 {
                // Segmented visual bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(StorageCategory.allCases, id: \.self) { cat in
                            let catBytes = categoryTotals[cat] ?? 0
                            if catBytes > 0 {
                                let width = max(4, geo.size.width * CGFloat(Double(catBytes) / Double(totalScanned)))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(SquirrelTheme.color(for: cat))
                                    .frame(width: width, height: 14)
                            }
                        }
                    }
                }
                .frame(height: 14)

                // Category legend chips
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 8) {
                    ForEach(StorageCategory.allCases, id: \.self) { cat in
                        let catBytes = categoryTotals[cat] ?? 0
                        if catBytes > 0 {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(SquirrelTheme.color(for: cat))
                                    .frame(width: 8, height: 8)
                                Text(cat.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: catBytes, countStyle: .file))
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }
            } else {
                Text("No categorized items discovered in current scan.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .solidCard(cornerRadius: 10)
    }

    private func computeCategoryTotals() -> [StorageCategory: Int64] {
        var totals: [StorageCategory: Int64] = [:]
        for item in appState.scannedItems {
            let cat = determineCategory(for: item)
            totals[cat, default: 0] += item.allocatedSize
        }
        return totals
    }

    private func determineCategory(for item: StorageItem) -> StorageCategory {
        let path = item.path.lowercased()
        if path.contains("/caches/") || path.hasSuffix("/caches") {
            return .userCaches
        } else if path.contains("/logs/") || path.hasSuffix(".log") || path.hasSuffix(".diag") || path.hasSuffix(".crash") {
            return .systemLogs
        } else if path.hasSuffix(".dmg") || path.hasSuffix(".pkg") || path.hasSuffix(".iso") || path.contains("/downloads/") {
            return .downloadsAndInstallers
        } else if item.logicalSize >= 100 * 1024 * 1024 {
            return .largeFiles
        } else {
            return .otherUserData
        }
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
        .solidCard(cornerRadius: 8)
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
                    Image(systemName: "checkmark.shield.fill")
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
                    Button(action: onCleanSafely) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Clean Safely (\(ByteCountFormatter.string(fromByteCount: safeToCleanBytes, countStyle: .file)))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
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
