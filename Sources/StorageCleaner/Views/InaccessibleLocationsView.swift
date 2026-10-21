import SwiftUI
import StorageCleanerCore

public struct InaccessibleLocationsView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inaccessible Locations")
                        .font(.headline)
                    Text("These paths could not be fully read due to macOS permissions, SIP, or system protection boundaries. The cleaner never invents numbers for skipped directories.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if appState.inaccessibleLocations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("All Scanned Locations Were Accessible")
                        .font(.headline)
                    Text("No permission denied errors or skipped directories were encountered during the last scan.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.inaccessibleLocations) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.orange)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(2)
                            Text(item.reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }

            Divider()

            // FDA Guidance Box
            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
                Text("To inspect protected directories such as Mail, Safari, and Messages caches, you can optionally grant Full Disk Access to StorageCleaner in macOS System Settings > Privacy & Security > Full Disk Access.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}
