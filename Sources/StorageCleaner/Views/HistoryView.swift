import SwiftUI
import StorageCleanerCore

public struct HistoryView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: Binding(
                get: { appState.selectedHistoryTab },
                set: { appState.selectedHistoryTab = $0 }
            )) {
                Text("Operation Journal").tag(0)
                Text("Quarantine & Recovery").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 340)
            .padding(12)

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
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No Operations Recorded Yet")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Operations executed during cleanup will be logged here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(entries) { entry in
                HStack(spacing: 12) {
                    Image(systemName: iconForAction(entry.actionType))
                        .foregroundColor(entry.status == .failed ? .red : .primary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.sanitizedName)
                                .font(.body.weight(.medium))
                            Text(entry.actionType.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }

                        Text(entry.originalPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if let err = entry.errorMessage {
                            Text("Error: \(err)")
                                .font(.caption)
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
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.vertical, 4)
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
            VStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("Quarantine Is Empty")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Files moved to managed quarantine for safe rollback will appear here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(records) { record in
                HStack(spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: record.originalPath).lastPathComponent)
                            .font(.body.weight(.medium))
                        Text(record.originalPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("Quarantined on \(record.timestamp.formatted(date: .abbreviated, time: .shortened)) • SHA-256: \(record.sha256.prefix(12))...")
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file))
                        .font(.subheadline.monospacedDigit())

                    Button("Restore") {
                        onRestore(record)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
    }
}
