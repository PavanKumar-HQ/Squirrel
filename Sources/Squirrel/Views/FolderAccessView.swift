import SwiftUI
import AppKit
import SquirrelCore

public struct FolderAccessView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Authorized Folders & Permissions")
                        .font(.system(size: 16, weight: .bold))
                    Text("Granted directories remembered across launches. Scan them repeatedly without permission dialogs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    LiquidGlassButton("Refresh Statuses", icon: "arrow.triangle.2.circlepath") {
                        appState.refreshFolderAccess()
                    }

                    LiquidGlassButton("Authorize Folder...", icon: "folder.badge.plus", isProminent: true) {
                        authorizeNewFolder()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if appState.authorizedFolders.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor.opacity(0.8))

                    Text("No Folders Authorized Yet")
                        .font(.headline)

                    Text("When you select Documents, Downloads, or project workspaces, Squirrel creates a persistent bookmark so you never need to authorize them again.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    LiquidGlassButton("Authorize a Folder Now", icon: "folder.badge.plus", isProminent: true) {
                        authorizeNewFolder()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                List {
                    Section {
                        ForEach(appState.authorizedFolders) { record in
                            folderRow(for: record)
                                .padding(.vertical, 6)
                        }
                    } header: {
                        HStack {
                            Text("PERSISTED FOLDER GRANTS (\(appState.authorizedFolders.count))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Stored in ~/Library/Application Support/Squirrel")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer / Privacy Architecture Note
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Native macOS Access Invariant")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Squirrel uses native security-scoped and persistent bookmarks. A grant for one directory never grants access to unrelated protected folders.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                LiquidGlassButton("Full Disk Access Settings", icon: "lock.shield") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func folderRow(for record: AuthorizedFolderRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: record.status.iconName)
                .font(.system(size: 20))
                .foregroundColor(statusColor(for: record.status))
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(record.displayName)
                        .font(.system(size: 13, weight: .semibold))

                    // Status Pill
                    Text(record.status.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(statusColor(for: record.status).opacity(0.15))
                        )
                        .foregroundColor(statusColor(for: record.status))

                    if record.isSecurityScoped {
                        Text("Security Scoped")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.12)))
                            .foregroundColor(.blue)
                    }
                }

                Text(record.resolvedPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 12) {
                    Text("Authorized: \(formattedDate(record.authorizedDate))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    if let lastAccess = record.lastAccessedDate {
                        Text("Last Scanned: \(formattedDate(lastAccess))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if record.status == .valid || record.status == .stale {
                    LiquidGlassButton("Scan Folder", icon: "play.fill", isProminent: true) {
                        appState.scanAuthorizedFolder(record: record)
                    }
                } else {
                    LiquidGlassButton("Reauthorize...", icon: "arrow.clockwise") {
                        reauthorizeFolder(record: record)
                    }
                }

                LiquidGlassButton("Revoke", icon: "xmark") {
                    appState.revokeFolderAccess(id: record.id)
                }
            }
        }
    }

    private func statusColor(for status: FolderAccessStatus) -> Color {
        switch status {
        case .valid: return .green
        case .stale: return .orange
        case .notFound, .permissionRestricted: return .red
        case .revoked: return .secondary
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func authorizeNewFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Authorize Folder"
        panel.message = "Choose a folder to authorize for Squirrel. Squirrel saves this authorization securely so you are not prompted again."

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try appState.authorizeFolder(url: url)
            } catch {
                showModalAlert(title: "Authorization Notice", message: error.localizedDescription)
            }
        }
    }

    private func reauthorizeFolder(record: AuthorizedFolderRecord) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: record.resolvedPath)
        panel.prompt = "Reauthorize"
        panel.message = "Re-grant access for '\(record.displayName)'. Squirrel will update the saved bookmark."

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try appState.authorizeFolder(url: url)
            } catch {
                showModalAlert(title: "Authorization Notice", message: error.localizedDescription)
            }
        }
    }

    private func showModalAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}
