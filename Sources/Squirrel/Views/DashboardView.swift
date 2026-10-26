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

                // Incomplete / Cancelled Notification Banner
                if appState.scanStatus == .cancelled {
                    ScanCancelledCard()
                }

                // 4. Opportunities Summary & Action Banner
                if appState.scanStatus == .completed {
                    OpportunitiesSummaryCard(
                        safeToCleanBytes: appState.safeToCleanBytes,
                        reviewBytes: appState.reviewRecommendedBytes,
                        duplicateBytes: appState.duplicatePotentialReclaimBytes,
                        onCleanSafely: {
                            appState.showCleanSafelyConfirm = true
                        },
                        onNavigateToFindings: {
                            appState.selectedFindingFilterIndex = 2 // Switch to Review filter
                            appState.selectedSection = .findings
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
            // Header matching macOS System Settings > General > Storage
            HStack(alignment: .firstTextBaseline) {
                Text(volume.volumeName)
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                if volume.totalCapacity > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: volume.usedSpace, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: volume.totalCapacity, countStyle: .file)) used")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
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
                let total = Double(max(1, volume.totalCapacity))
                let availableStr = ByteCountFormatter.string(fromByteCount: volume.availableCapacity, countStyle: .file)

                // Segmented Storage Bar matching Apple System Settings
                GeometryReader { geo in
                    let width = geo.size.width

                    ZStack(alignment: .leading) {
                        // Empty/Available Track (Dark Gray)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 18)

                        // Categorized segments
                        if let categories = volume.auditReport?.categories, !categories.isEmpty {
                            HStack(spacing: 0.8) {
                                ForEach(categories) { cat in
                                    let segWidth = max(2.0, CGFloat(Double(cat.measuredBytes) / total * Double(width)))
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(Color(hex: cat.colorHex) ?? Color.gray)
                                        .frame(width: segWidth, height: 18)
                                }
                            }
                        } else {
                            let fractionUsed = Double(volume.usedSpace) / total
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor)
                                .frame(width: max(4, CGFloat(fractionUsed * Double(width))), height: 18)
                        }

                        // Centered Available Storage Label inside track
                        HStack {
                            Spacer()
                            Text(availableStr)
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundColor(.primary.opacity(0.85))
                                .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
                                .padding(.trailing, 14)
                        }
                    }
                }
                .frame(height: 18)

                // Native Apple Legend Row
                HStack(spacing: 14) {
                    if let categories = volume.auditReport?.categories, !categories.isEmpty {
                        ForEach(categories) { cat in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: cat.colorHex) ?? Color.gray)
                                    .frame(width: 7, height: 7)
                                Text(cat.categoryName)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .help("\(cat.categoryName): \(ByteCountFormatter.string(fromByteCount: cat.measuredBytes, countStyle: .file))\n\(cat.observationNotes)")
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                            Text("Used").font(.system(size: 11))
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                            Text("Available").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 2)

                Divider()
                    .padding(.vertical, 2)

                // Actions and APFS Metadata row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        if volume.purgeableSpace > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                Text("Purgeable by APFS: \(ByteCountFormatter.string(fromByteCount: volume.purgeableSpace, countStyle: .file)) • Container allocation: \(ByteCountFormatter.string(fromByteCount: volume.rawPhysicalUsedSpace, countStyle: .file))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 6) {
                            Text("Source: Foundation URLResourceValues (APFS)")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            if let date = lastScanDate {
                                Text("• Last Scan: \(date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if scanStatus == .scanning {
                        Button(role: .destructive, action: onCancel) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Stop Scan")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        HStack(spacing: 8) {
                            Button(action: onSelectFolder) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.badge.gearshape")
                                    Text("Choose Folder...")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(action: onScanStandard) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Scan Standard")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
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

struct ScanCancelledCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 20))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Scan Incomplete (Cancelled by User)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Traversal was interrupted before all folders were indexed. Findings reflect partial traversal only, and cleanup actions are withheld until a complete scan finishes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

struct OpportunitiesSummaryCard: View {
    let safeToCleanBytes: Int64
    let reviewBytes: Int64
    let duplicateBytes: Int64
    let onCleanSafely: () -> Void
    let onNavigateToFindings: () -> Void

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
                    if reviewBytes > 0 {
                        Button(action: onNavigateToFindings) {
                            HStack(spacing: 4) {
                                Text("Review Recommended:")
                                Text(ByteCountFormatter.string(fromByteCount: reviewBytes, countStyle: .file))
                                    .fontWeight(.bold)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    } else {
                        Text("Review Recommended: \(ByteCountFormatter.string(fromByteCount: reviewBytes, countStyle: .file))")
                    }

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
