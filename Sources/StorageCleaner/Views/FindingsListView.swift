import SwiftUI
import StorageCleanerCore

public struct FindingsListView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Filter and Action Toolbar
            HStack(spacing: 12) {
                Picker("Filter", selection: Binding(
                    get: { appState.selectedFindingFilterIndex },
                    set: { appState.selectedFindingFilterIndex = $0 }
                )) {
                    Text("All Findings").tag(0)
                    Text("Safe to Clean").tag(1)
                    Text("Review Recommended").tag(2)
                    Text("Keep / Excluded").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Spacer()

                TextField("Search findings...", text: Binding(
                    get: { appState.findingSearchText },
                    set: { appState.findingSearchText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

                if !appState.selectedFindingIds.isEmpty {
                    Button(action: { appState.showFindingConfirmSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Clean Selected (\(appState.selectedFindingIds.count))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Findings List
            if filteredFindings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No findings match the current filter")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Try changing the filter or running a fresh scan.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredFindings) { finding in
                        FindingRowView(
                            finding: finding,
                            isSelected: appState.selectedFindingIds.contains(finding.id),
                            isExpanded: appState.expandedFindingId == finding.id,
                            onToggleSelect: {
                                if appState.selectedFindingIds.contains(finding.id) {
                                    appState.selectedFindingIds.remove(finding.id)
                                } else {
                                    appState.selectedFindingIds.insert(finding.id)
                                }
                            },
                            onToggleExpand: {
                                if appState.expandedFindingId == finding.id {
                                    appState.expandedFindingId = nil
                                } else {
                                    appState.expandedFindingId = finding.id
                                }
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Clean Selected Items?",
            isPresented: Binding(
                get: { appState.showFindingConfirmSheet },
                set: { appState.showFindingConfirmSheet = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Clean \(appState.selectedFindingIds.count) Items", role: .destructive) {
                appState.executeSelectedFindings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected files will be handled according to their verified recovery policy (moved to Trash or managed quarantine).")
        }
    }

    private var filteredFindings: [Finding] {
        appState.findings.filter { finding in
            let matchesFilter: Bool
            switch appState.selectedFindingFilterIndex {
            case 0: matchesFilter = true
            case 1: matchesFilter = finding.eligibility == .safeToClean
            case 2: matchesFilter = finding.eligibility == .reviewRecommended
            case 3: matchesFilter = finding.eligibility == .keep
            default: matchesFilter = true
            }

            if !matchesFilter { return false }
            if appState.findingSearchText.isEmpty { return true }
            return finding.title.localizedCaseInsensitiveContains(appState.findingSearchText) ||
                   finding.path.localizedCaseInsensitiveContains(appState.findingSearchText) ||
                   finding.category.rawValue.localizedCaseInsensitiveContains(appState.findingSearchText)
        }
    }
}

struct FindingRowView: View {
    let finding: Finding
    let isSelected: Bool
    let isExpanded: Bool
    let onToggleSelect: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in onToggleSelect() }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                Image(systemName: finding.category.iconName)
                    .foregroundColor(colorForEligibility(finding.eligibility))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(finding.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                EligibilityBadge(eligibility: finding.eligibility)

                Text(ByteCountFormatter.string(fromByteCount: finding.allocatedSize, countStyle: .file))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .frame(width: 80, alignment: .trailing)

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Detection Rule: \(finding.ruleId)")
                                .font(.caption.weight(.bold))
                            Text(finding.ruleDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Recovery Method")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)
                            Text(finding.recoveryMethod.rawValue)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }

                    if !finding.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Technical Evidence:")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)
                            ForEach(finding.evidence, id: \.self) { ev in
                                HStack(spacing: 4) {
                                    Text("•")
                                    Text(ev)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Possible Consequences:")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)
                        Text(finding.consequencesExplanation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Spacer()
                        if FileManager.default.fileExists(atPath: finding.path) {
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(finding.path, inFileViewerRootedAtPath: "")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.leading, 32)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private func colorForEligibility(_ eligibility: CleanupEligibility) -> Color {
        switch eligibility {
        case .safeToClean: return .green
        case .reviewRecommended: return .orange
        case .keep: return .secondary
        }
    }
}

struct EligibilityBadge: View {
    let eligibility: CleanupEligibility

    var body: some View {
        Text(eligibility.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bgColor.opacity(0.15))
            .foregroundColor(bgColor)
            .cornerRadius(4)
    }

    private var bgColor: Color {
        switch eligibility {
        case .safeToClean: return .green
        case .reviewRecommended: return .orange
        case .keep: return .secondary
        }
    }
}
