import SwiftUI
import SquirrelCore

public struct HistoryView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Liquid Glass Tab Selector Bar
            HStack {
                Picker("View", selection: Binding(
                    get: { appState.selectedHistoryTab },
                    set: { appState.selectedHistoryTab = $0 }
                )) {
                    Text("Operation Journal (\(appState.journalEntries.count))").tag(0)
                    Text("Managed Quarantine (\(appState.quarantineRecords.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.green)
                    Text("Undo & Rollback Safe")
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

            if appState.selectedHistoryTab == 0 {
                JournalListView(entries: appState.journalEntries)
            } else {
                QuarantineListView(
                    records: appState.quarantineRecords,
                    onRestore: { record in
                        appState.restoreQuarantineItem(record: record)
                    }
                )
            }
        }
    }
}

struct JournalListView: View {
    let entries: [JournalEntry]

    var body: some View {
        if entries.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("No Operations Recorded Yet")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Operations executed during cleanup will be logged here with byte-level verification.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(entries) { entry in
                HStack(spacing: 12) {
                    Image(systemName: iconForAction(entry.actionType))
                        .font(.system(size: 15))
                        .foregroundColor(entry.status == .failed ? .red : .accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.sanitizedName)
                                .font(.system(size: 13, weight: .medium))
                            Text(entry.actionType.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }

                        Text(entry.originalPath)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let err = entry.errorMessage {
                            Text("Error: \(err)")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if entry.bytesReclaimed > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: entry.bytesReclaimed, countStyle: .file))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)
        }
    }

    private func iconForAction(_ action: JournalActionType) -> String {
        switch action {
        case .movedToTrash: return "trash"
        case .movedToQuarantine: return "archivebox"
        case .directRemoved: return "xmark.bin"
        case .restoredFromQuarantine: return "arrow.uturn.backward"
        }
    }
}

struct QuarantineListView: View {
    let records: [QuarantineRecord]
    let onRestore: (QuarantineRecord) -> Void

    var body: some View {
        if records.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("Quarantine Is Empty")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Items moved to managed quarantine for safe rollback will be displayed here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(records) { record in
                HStack(spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: record.originalPath).lastPathComponent)
                            .font(.system(size: 13, weight: .medium))
                        Text(record.originalPath)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Quarantined on \(record.timestamp.formatted(date: .abbreviated, time: .shortened)) • SHA-256: \(record.sha256.prefix(12))...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())

                    LiquidGlassButton("Restore File", icon: "arrow.uturn.backward") {
                        onRestore(record)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
    }
}
