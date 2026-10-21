import SwiftUI
import SquirrelCore

public struct DuplicatesView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Toolbar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exact Duplicate Files")
                        .font(.system(size: 16, weight: .bold))
                    Text("Confirmed by full SHA-256 cryptographic hashing and byte-by-byte content verification.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("Byte-by-Byte Verified")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 0.8))

                if !appState.selectedDuplicatePaths.isEmpty {
                    Button(role: .destructive, action: {
                        appState.showDuplicateConfirmSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                            Text("Trash Selected (\(appState.selectedDuplicatePaths.count))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if appState.duplicateGroups.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("No Exact Duplicates Found")
                        .font(.headline)
                    Text("All scanned candidate files have unique byte contents across the scanned directory.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    let displayedGroups = Array(appState.duplicateGroups.prefix(appState.duplicatesDisplayLimit))
                    ForEach(displayedGroups) { group in
                        DuplicateGroupSectionView(
                            group: group,
                            selectedPaths: Binding(
                                get: { appState.selectedDuplicatePaths },
                                set: { appState.selectedDuplicatePaths = $0 }
                            )
                        )
                    }

                    if appState.duplicateGroups.count > appState.duplicatesDisplayLimit {
                        HStack {
                            Spacer()
                            Button("Load 50 More (Showing \(displayedGroups.count) of \(appState.duplicateGroups.count) groups)") {
                                appState.duplicatesDisplayLimit += 50
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Move Selected Duplicate Copies to Trash?",
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
            Text("Selected duplicate copies will be moved safely to macOS Trash. The original copy designated to keep will remain completely untouched.")
        }
    }
}

struct DuplicateGroupSectionView: View {
    let group: DuplicateGroup
    @Binding var selectedPaths: Set<String>

    var body: some View {
        Section {
            ForEach(group.files) { member in
                HStack(spacing: 12) {
                    if member.isRecommendedToKeep {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                            .frame(width: 18)
                    } else {
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
                        .frame(width: 18)
                    }

                    Image(systemName: member.isRecommendedToKeep ? "doc.fill" : "doc")
                        .font(.system(size: 15))
                        .foregroundColor(member.isRecommendedToKeep ? .blue : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(member.fileName)
                                .font(.system(size: 13, weight: .medium))

                            if member.isRecommendedToKeep {
                                Text("ORIGINAL (KEEP)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.14))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }

                        Text(member.path)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if let modDate = member.modificationDate {
                        Text(modDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if FileManager.default.fileExists(atPath: member.path) {
                        Button(action: {
                            NSWorkspace.shared.selectFile(member.path, inFileViewerRootedAtPath: "")
                        }) {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                }
                .padding(.vertical, 3)
            }
        } header: {
            HStack(spacing: 8) {
                Text("\(group.files.count) Copies • \(ByteCountFormatter.string(fromByteCount: group.fileSize, countStyle: .file)) each")
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                Text("SHA-256: \(group.sha256Hash.prefix(12))...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("Reclaimable: \(ByteCountFormatter.string(fromByteCount: group.potentialReclaimableBytes, countStyle: .file))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(.green)
            }
            .padding(.vertical, 6)
        }
    }
}
