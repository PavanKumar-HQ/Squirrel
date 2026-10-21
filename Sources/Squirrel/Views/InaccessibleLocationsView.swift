import SwiftUI
import SquirrelCore

public struct InaccessibleLocationsView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inaccessible Locations")
                        .font(.system(size: 16, weight: .bold))
                    Text("Locations skipped due to macOS System Integrity Protection (SIP) or TCC permissions. Squirrel never invents estimates for skipped directories.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.orange)
                    Text("\(appState.inaccessibleLocations.count) Skipped")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .liquidGlassCapsule()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if appState.inaccessibleLocations.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.green.opacity(0.85))
                    Text("All Scanned Locations Were Accessible")
                        .font(.headline)
                    Text("No permission denied errors or skipped directories were encountered during the last scan.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.inaccessibleLocations) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.path)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(2)
                                .truncationMode(.middle)
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
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)

                Text("To inspect protected directories (e.g. Mail, Safari, Messages caches), you can optionally grant Full Disk Access to Squirrel in macOS System Settings > Privacy & Security > Full Disk Access.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                LiquidGlassButton("Open Privacy Settings", icon: "arrow.up.forward.app") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}
