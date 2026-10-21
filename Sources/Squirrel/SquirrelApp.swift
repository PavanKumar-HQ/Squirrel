import SwiftUI
import SquirrelCore

@main
public struct SquirrelApp: App {
    @ObservedObject private var appState = AppState.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                VStack(spacing: 0) {
                    // Sidebar App Identity Header
                    HStack(spacing: 12) {
                        if let imagePath = Bundle.module.path(forResource: "AppIcon", ofType: "png"),
                           let nsImg = NSImage(contentsOfFile: imagePath) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 36, height: 36)
                                .cornerRadius(8)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(SquirrelTheme.brandWarm)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Squirrel")
                                .font(.system(size: 15, weight: .bold))
                            Text("Storage Optimizer")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    Divider()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)

                    // Navigation List with Dynamic Badge Counts
                    List(NavigationSection.allCases, selection: Binding(
                        get: { appState.selectedSection },
                        set: { newSec in if let s = newSec { appState.selectedSection = s } }
                    )) { section in
                        NavigationLink(value: section) {
                            HStack {
                                Label {
                                    Text(section.rawValue)
                                        .font(.system(size: 13, weight: .medium))
                                } icon: {
                                    Image(systemName: section.iconName)
                                        .font(.system(size: 14))
                                        .foregroundColor(appState.selectedSection == section ? .accentColor : .secondary)
                                }

                                Spacer()

                                // Section Badge Counts
                                if let count = badgeCount(for: section), count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                        .foregroundColor(section == .permissions ? .orange : (section == .findings ? .blue : .secondary))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(section == .permissions ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.12))
                                        )
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.sidebar)

                    Divider()
                        .padding(.horizontal, 12)

                    // Sidebar Footer: Real Volume Space Mini-Pill
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.scanStatus == .scanning ? Color.blue : Color.green)
                                .frame(width: 7, height: 7)
                            Text(appState.volumeSpace.volumeName)
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text("\(ByteCountFormatter.string(fromByteCount: appState.volumeSpace.availableCapacity, countStyle: .file)) free")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundColor(.secondary)
                        }

                        let fraction = appState.volumeSpace.totalCapacity > 0 ? Double(appState.volumeSpace.usedSpace) / Double(appState.volumeSpace.totalCapacity) : 0
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(width: max(4, g.size.width * CGFloat(fraction)), height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                    .padding(10)
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            } detail: {
                Group {
                    switch appState.selectedSection {
                    case .dashboard:
                        DashboardView(appState: appState)
                    case .findings:
                        FindingsListView(appState: appState)
                    case .treemap:
                        TreemapView(appState: appState)
                    case .duplicates:
                        DuplicatesView(appState: appState)
                    case .history:
                        HistoryView(appState: appState)
                    case .permissions:
                        InaccessibleLocationsView(appState: appState)
                    case .diagnostics:
                        DiagnosticsView(appState: appState)
                    }
                }
                .frame(minWidth: 700, minHeight: 520)
            }
            .frame(minWidth: 940, minHeight: 640)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if appState.scanStatus == .scanning {
                        LiquidGlassButton("Stop Scan", icon: "xmark.circle.fill", role: .destructive) {
                            appState.cancelScan()
                        }
                    } else {
                        LiquidGlassContainer(spacing: 6) {
                            LiquidGlassButton("Choose Folder...", icon: "folder.badge.gearshape") {
                                appState.selectCustomFolderAndScan()
                            }
                            LiquidGlassButton("Scan Standard", icon: "arrow.triangle.2.circlepath", isProminent: true) {
                                appState.startScan()
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { appState.showCleanupSummarySheet },
                set: { appState.showCleanupSummarySheet = $0 }
            )) {
                if let summary = appState.lastCleanupSummary {
                    CleanupVerificationModal(
                        summary: summary,
                        onViewDiagnostics: {
                            appState.showCleanupSummarySheet = false
                            appState.selectedSection = .diagnostics
                        },
                        onDismiss: {
                            appState.showCleanupSummarySheet = false
                        }
                    )
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }

    private func badgeCount(for section: NavigationSection) -> Int? {
        switch section {
        case .findings:
            return appState.findings.isEmpty ? nil : appState.findings.count
        case .duplicates:
            return appState.duplicateGroups.isEmpty ? nil : appState.duplicateGroups.count
        case .permissions:
            return appState.inaccessibleLocations.isEmpty ? nil : appState.inaccessibleLocations.count
        case .history:
            return appState.quarantineRecords.isEmpty ? nil : appState.quarantineRecords.count
        case .dashboard, .treemap, .diagnostics:
            return nil
        }
    }
}

/// Comprehensive, evidence-based post-cleanup verification modal presenting the 5 storage metrics,
/// candidate breakdown, APFS volume capacity delta, and known measurement limitations.
struct CleanupVerificationModal: View {
    let summary: CleanupSummary
    let onViewDiagnostics: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: summary.itemsFailedCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(summary.itemsFailedCount == 0 ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cleanup Verification Report")
                        .font(.title2.weight(.bold))
                    Text("Volume: \(summary.afterCapacity.volumeName) • \(summary.timestamp.formatted(date: .abbreviated, time: .standard))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Confidence Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(summary.confidenceLevel == .verifiedByFilesystem ? Color.green : (summary.confidenceLevel == .partiallyVerified ? Color.blue : Color.orange))
                        .frame(width: 6, height: 6)
                    Text(summary.confidenceLevel.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }

            // Candidate Breakdown (4 items)
            HStack(spacing: 10) {
                metricMiniCard(title: "Discovered", value: "\(summary.candidatesDiscoveredCount)", icon: "magnifyingglass")
                metricMiniCard(title: "Eligible", value: "\(summary.itemsEligibleCount)", icon: "checkmark.circle")
                metricMiniCard(title: "Skipped", value: "\(summary.itemsSkippedCount)", icon: "forward.frame")
                metricMiniCard(title: "Processed", value: "\(summary.itemsSucceededCount)", icon: "trash.circle")
            }

            // The 5 Storage Recovery Metrics Table
            VStack(alignment: .leading, spacing: 8) {
                Text("Storage Recovery Accounting")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                VStack(spacing: 6) {
                    metricDetailRow(
                        num: "1",
                        title: "Logical Bytes Identified",
                        val: ByteCountFormatter.string(fromByteCount: summary.logicalBytesIdentified, countStyle: .file),
                        desc: "Sum of file sizes, deduplicating hard links"
                    )
                    Divider()
                    metricDetailRow(
                        num: "2",
                        title: "Estimated Reclaimable",
                        val: ByteCountFormatter.string(fromByteCount: summary.estimatedReclaimableBytes, countStyle: .file),
                        desc: "Physical allocation accounting for nested folders"
                    )
                    Divider()
                    metricDetailRow(
                        num: "3",
                        title: "Bytes Successfully Processed",
                        val: ByteCountFormatter.string(fromByteCount: summary.bytesSuccessfullyProcessed, countStyle: .file),
                        desc: "Files safely trashed, quarantined, or removed"
                    )
                    Divider()
                    metricDetailRow(
                        num: "4",
                        title: "Observed Filesystem Delta",
                        val: formatDelta(summary.observedCapacityDelta),
                        desc: "APFS available space delta (after − before)"
                    )
                    Divider()
                    metricDetailRow(
                        num: "5",
                        title: "Verified Reclaimed Storage",
                        val: ByteCountFormatter.string(fromByteCount: summary.verifiedReclaimedBytes, countStyle: .file),
                        desc: "Amount verified by post-cleanup OS measurement",
                        isHighlighted: true
                    )
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // Measurement Limitations
            if !summary.knownLimitations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Measurement Notes & APFS Behavior:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    ForEach(summary.knownLimitations.prefix(2), id: \.self) { limitation in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(limitation)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.yellow.opacity(0.08))
                .cornerRadius(6)
            }

            // Failed items (if any)
            if !summary.failedItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Failed / Inaccessible Items (\(summary.itemsFailedCount)):")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(summary.failedItems.keys), id: \.self) { path in
                                Text("• \(URL(fileURLWithPath: path).lastPathComponent): \(summary.failedItems[path] ?? "")")
                                    .font(.system(size: 10).monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 60)
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button("View Full Diagnostics") {
                    onViewDiagnostics()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(minWidth: 520, maxWidth: 560)
    }

    private func metricMiniCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func metricDetailRow(num: String, title: String, val: String, desc: String, isHighlighted: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(num)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(isHighlighted ? Color.green : Color.accentColor))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(desc)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(val)
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundColor(isHighlighted ? .green : .primary)
        }
    }

    private func formatDelta(_ delta: Int64) -> String {
        let prefix = delta > 0 ? "+" : ""
        return "\(prefix)\(ByteCountFormatter.string(fromByteCount: delta, countStyle: .file))"
    }
}

