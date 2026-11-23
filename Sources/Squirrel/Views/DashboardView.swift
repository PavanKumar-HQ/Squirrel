import SwiftUI
import AppKit
import SquirrelCore

public struct DashboardView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Clean Top Header
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dashboard")
                            .font(.system(size: 22, weight: .bold))
                        Text("\(appState.volumeSpace.volumeName) — \(SquirrelFormatters.formatAppleDecimalCompact(appState.volumeSpace.usedSpace)) of \(SquirrelFormatters.formatAppleDecimalCompact(appState.volumeSpace.totalCapacity)) used")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Target Scope Pill
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Text(appState.scanTargetDescription)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220)

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
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                }

                // 2. Real-Time Active Cleaning Indicator (Visible when clearing up)
                if appState.isCleaning {
                    NativeDeleteEffectView(
                        currentItem: appState.liveCleaningItemName,
                        cleanedBytes: appState.liveCleanedBytes,
                        totalBytes: appState.liveTotalToCleanBytes,
                        cleanedCount: appState.liveCleanedCount,
                        totalCount: appState.liveTotalCount
                    )
                }

                // 3. Cleanup Completion Feedback Banner
                if appState.showCleanResultBanner, let result = appState.lastCleanResult {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clean Complete: Freed \(SquirrelFormatters.formatAppleDecimalCompact(result.reclaimedBytes))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.primary)

                            Text("\(result.itemsCleanedCount) items permanently removed. APFS storage refreshed.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            appState.showCleanResultBanner = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green.opacity(0.25), lineWidth: 1)
                    )
                }

                // 4. Hero Storage Volume Capacity Card
                VolumeCapacityCard(
                    volume: appState.volumeSpace,
                    scanStatus: appState.scanStatus,
                    onScan: {
                        appState.startScan()
                    },
                    onCancel: {
                        appState.cancelScan()
                    }
                )

                // 5. Active Scan Progress Card
                if appState.scanStatus == .scanning {
                    HStack(spacing: 12) {
                        NativeScanEffectView(
                            title: "Scanning Storage...",
                            subtitle: "\(appState.scanProgress.itemsScannedCount) items indexed (\(SquirrelFormatters.formatPrecise(appState.scanProgress.bytesScannedTotal)))"
                        )

                        Spacer()

                        Button("Stop", role: .destructive) {
                            appState.cancelScan()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .solidCard(cornerRadius: 10)
                }

                // Scan Cancelled Banner
                if appState.scanStatus == .cancelled {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.orange)

                        Text("Scan cancelled by user. Partial results are displayed below.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                // 6. Action Opportunities Summary (Clean Hero)
                if appState.scanStatus == .completed {
                    CleanActionSummaryCard(
                        safeToCleanBytes: appState.safeToCleanBytes,
                        reviewBytes: appState.reviewRecommendedBytes,
                        duplicateBytes: appState.duplicatePotentialReclaimBytes,
                        isCleaning: appState.isCleaning,
                        onCleanNow: {
                            appState.showCleanSafelyConfirm = true
                        },
                        onNavigateToFindings: {
                            appState.selectedFindingFilterIndex = 2 // Review filter
                            appState.selectedSection = .findings
                        },
                        onNavigateToDuplicates: {
                            appState.selectedSection = .duplicates
                        }
                    )
                }

                // 7. Top Cleanup Opportunities Preview (Streamlined, minimal)
                if !appState.findings.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Top Cleanup Opportunities")
                                .font(.system(size: 14, weight: .bold))

                            Spacer()

                            Button("View All (\(appState.findings.count))") {
                                appState.selectedSection = .findings
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accentColor)
                        }

                        VStack(spacing: 6) {
                            ForEach(Array(appState.findings.prefix(4))) { finding in
                                HStack(spacing: 12) {
                                    Image(systemName: finding.category.iconName)
                                        .font(.system(size: 14))
                                        .foregroundColor(SquirrelTheme.color(for: finding.category))
                                        .frame(width: 26, height: 26)
                                        .background(SquirrelTheme.color(for: finding.category).opacity(0.12))
                                        .cornerRadius(6)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(finding.title)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(finding.path)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Button(action: {
                                        NSWorkspace.shared.selectFile(finding.path, inFileViewerRootedAtPath: "")
                                    }) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Reveal in Finder")

                                    Text(ByteCountFormatter.string(fromByteCount: finding.allocatedSize, countStyle: .file))
                                        .font(.system(size: 12, weight: .semibold).monospacedDigit())

                                    Text(finding.eligibility == .safeToClean ? "Safe" : "Review")
                                        .font(.system(size: 9, weight: .bold))
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
            .padding(22)
        }
        .confirmationDialog(
            "Clean Safe Items?",
            isPresented: Binding(
                get: { appState.showCleanSafelyConfirm },
                set: { appState.showCleanSafelyConfirm = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Clean \(SquirrelFormatters.formatAppleDecimalCompact(appState.safeToCleanBytes))", role: .destructive) {
                appState.executeSafeBatch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Verified non-essential build caches and old diagnostic logs will be permanently deleted to immediately free up APFS disk space.")
        }
    }
}

// MARK: - Subcomponents
private struct VolumeCapacityCard: View {
    let volume: VolumeSpace
    let scanStatus: ScanStatus
    let onScan: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header matching macOS System Settings
            HStack(alignment: .firstTextBaseline) {
                Text(volume.volumeName)
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                if volume.totalCapacity > 0 {
                    Text("\(SquirrelFormatters.formatAppleDecimalCompact(volume.usedSpace)) used of \(SquirrelFormatters.formatAppleDecimalCompact(volume.totalCapacity))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            if volume.totalCapacity > 0 {
                let total = Double(max(1, volume.totalCapacity))
                let availableStr = "\(SquirrelFormatters.formatAppleDecimalCompact(volume.availableCapacity)) available"

                // Apple-Style Segmented Bar
                GeometryReader { geo in
                    let width = geo.size.width

                    ZStack(alignment: .leading) {
                        // Background Track
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 16)

                        // Segmented bar
                        if let categories = volume.auditReport?.categories, !categories.isEmpty {
                            HStack(spacing: 0.8) {
                                ForEach(categories) { cat in
                                    let segWidth = max(2.0, CGFloat(Double(cat.measuredBytes) / total * Double(width)))
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(Color(hex: cat.colorHex) ?? Color.gray)
                                        .frame(width: segWidth, height: 16)
                                }
                            }
                        } else {
                            let fractionUsed = Double(volume.usedSpace) / total
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.accentColor)
                                .frame(width: max(4, CGFloat(fractionUsed * Double(width))), height: 16)
                        }

                        // Available Label on right
                        HStack {
                            Spacer()
                            Text(availableStr)
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundColor(.primary.opacity(0.85))
                                .padding(.trailing, 10)
                        }
                    }
                }
                .frame(height: 16)

                // Clean Legend Row
                HStack(spacing: 12) {
                    if let categories = volume.auditReport?.categories, !categories.isEmpty {
                        ForEach(categories) { cat in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: cat.colorHex) ?? Color.gray)
                                    .frame(width: 6, height: 6)
                                Text(cat.categoryName)
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            Text("Used").font(.system(size: 11))
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                            Text("Available").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 2)

                // Card Footer: Clean Status & Single Primary Action
                HStack(alignment: .center) {
                    Text("Matches Apple System Settings Storage (\(SquirrelFormatters.formatAppleDecimalCompact(volume.availableCapacity)) available)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

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
                        Button(action: onScan) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(scanStatus == .completed ? "Scan Again" : "Scan Mac")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .solidCard(cornerRadius: 12)
    }
}

private struct CleanActionSummaryCard: View {
    let safeToCleanBytes: Int64
    let reviewBytes: Int64
    let duplicateBytes: Int64
    let isCleaning: Bool
    let onCleanNow: () -> Void
    let onNavigateToFindings: () -> Void
    let onNavigateToDuplicates: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(safeToCleanBytes > 0 ? .green : .secondary)
                    Text("Safe to Clean")
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(SquirrelFormatters.formatAppleDecimalCompact(safeToCleanBytes))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(safeToCleanBytes > 0 ? .green : .secondary)

                Text("Validated non-essential caches, toolchain build outputs, and old diagnostic logs.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if safeToCleanBytes > 0 {
                    Button(action: onCleanNow) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                            Text("Clean \(SquirrelFormatters.formatAppleDecimalCompact(safeToCleanBytes))")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.regular)
                    .disabled(isCleaning)
                } else {
                    Text("All Safe Items Cleaned")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }

                HStack(spacing: 10) {
                    if reviewBytes > 0 {
                        Button(action: onNavigateToFindings) {
                            HStack(spacing: 3) {
                                Text("Review:")
                                Text(SquirrelFormatters.formatAppleDecimalCompact(reviewBytes))
                                    .fontWeight(.bold)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    }

                    if duplicateBytes > 0 {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))

                        Button(action: onNavigateToDuplicates) {
                            HStack(spacing: 3) {
                                Text("Duplicates:")
                                Text(SquirrelFormatters.formatAppleDecimalCompact(duplicateBytes))
                                    .fontWeight(.bold)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .padding(16)
        .solidCard(cornerRadius: 12)
    }
}
