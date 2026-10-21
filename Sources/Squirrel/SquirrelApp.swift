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
                    CleanupSummaryModal(summary: summary) {
                        appState.showCleanupSummarySheet = false
                    }
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
        case .dashboard, .treemap:
            return nil
        }
    }
}

struct CleanupSummaryModal: View {
    let summary: CleanupSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: summary.itemsFailedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(summary.itemsFailedCount == 0 ? .green : .orange)

            Text("Cleanup Execution Complete")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reclaimed Space:")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: summary.totalBytesReclaimed, countStyle: .file))
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }

                HStack {
                    Text("Items Succeeded:")
                    Spacer()
                    Text("\(summary.itemsSucceededCount)")
                }

                if summary.itemsFailedCount > 0 {
                    HStack {
                        Text("Items Skipped / Failed:")
                        Spacer()
                        Text("\(summary.itemsFailedCount)")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .frame(maxWidth: 360)

            if !summary.failedItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Failed Items & Reasons:")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(summary.failedItems.keys), id: \.self) { path in
                                Text("• \(URL(fileURLWithPath: path).lastPathComponent): \(summary.failedItems[path] ?? "")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
                .frame(maxWidth: 360)
            }

            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}
