import SwiftUI
import StorageCleanerCore

public struct DuplicatesView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header stats & Action
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exact Duplicate Files")
                        .font(.headline)
                    Text("Identified by matching full SHA-256 cryptographic hashes. User review is required before removal.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !appState.selectedDuplicatePaths.isEmpty {
                    Button(action: { appState.showDuplicateConfirmSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Remove Selected Copies (\(appState.selectedDuplicatePaths.count))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if appState.duplicateGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No Exact Duplicates Found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("All scanned files appear to have unique contents.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.duplicateGroups) { group in
                        DuplicateGroupSectionView(
                            group: group,
                            selectedPaths: Binding(
                                get: { appState.selectedDuplicatePaths },
                                set: { appState.selectedDuplicatePaths = $0 }
                            )
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Remove Selected Duplicate Copies?",
            isPresented: Binding(
                get: { appState.showDuplicateConfirmSheet },
                set: { appState.showDuplicateConfirmSheet = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Move \(appState.selectedDuplicatePaths.count) Copies to Trash", role: .destructive) {
                appState.executeDuplicateCleanup()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected duplicate copies will be moved to macOS Trash. The original copy you chose to keep remains untouched.")
        }
    }
}

struct DuplicateGroupSectionView: View {
    let group: DuplicateGroup
    @Binding var selectedPaths: Set<String>

    var body: some View {
        Section {
            ForEach(group.files) { member in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { selectedPaths.contains(member.path) },
                        set: { isChecked in
                            if isChecked {
                                selectedPaths.insert(member.path)
                            } else {
                                selectedPaths.remove(member.path)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    Image(systemName: "doc")
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(member.fileName)
                                .font(.body.weight(.medium))

                            if member.isRecommendedToKeep {
                                Text("RECOMMENDED TO KEEP")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }

                        Text(member.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let modDate = member.modificationDate {
                        Text(modDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if FileManager.default.fileExists(atPath: member.path) {
                        Button(action: {
                            NSWorkspace.shared.selectFile(member.path, inFileViewerRootedAtPath: "")
                        }) {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                Text("\(group.files.count) Copies • \(ByteCountFormatter.string(fromByteCount: group.fileSize, countStyle: .file)) each")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("SHA-256: \(group.sha256Hash.prefix(12))...")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)

                Text("Reclaimable: \(ByteCountFormatter.string(fromByteCount: group.potentialReclaimableBytes, countStyle: .file))")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.green)
            }
            .padding(.vertical, 4)
        }
    }
}
