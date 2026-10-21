import SwiftUI
import SquirrelCore

@main
public struct SquirrelApp: App {
    @ObservedObject private var appState = AppState.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(NavigationSection.allCases, selection: Binding(
                    get: { appState.selectedSection },
                    set: { newSec in if let s = newSec { appState.selectedSection = s } }
                )) { section in
                    NavigationLink(value: section) {
                        Label {
                            Text(section.rawValue)
                        } icon: {
                            Image(systemName: section.iconName)
                        }
                    }
                }
                .navigationTitle("Squirrel")
                .listStyle(.sidebar)
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
            .frame(minWidth: 920, minHeight: 620)
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
