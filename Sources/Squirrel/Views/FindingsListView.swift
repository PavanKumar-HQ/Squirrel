import SwiftUI
import SquirrelCore

public struct FindingsListView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Native Filter & Search Toolbar
            HStack(spacing: 12) {
                Picker("Filter", selection: Binding(
                    get: { appState.selectedFindingFilterIndex },
                    set: {
                        appState.selectedFindingFilterIndex = $0
                        appState.findingsDisplayLimit = 100
                    }
                )) {
                    Text("All (\(appState.findings.count))").tag(0)
                    Text("Safe to Clean (\(safeCount))").tag(1)
                    Text("Review (\(reviewCount))").tag(2)
                    Text("Keep (\(keepCount))").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 440)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search findings...", text: Binding(
                        get: { appState.findingSearchText },
                        set: {
                            appState.findingSearchText = $0
                            appState.findingsDisplayLimit = 100
                        }
                    ))
                    .textFieldStyle(.plain)

                    if !appState.findingSearchText.isEmpty {
                        Button(action: {
                            appState.findingSearchText = ""
                            appState.findingsDisplayLimit = 100
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 0.8))
                .frame(maxWidth: 240)

                if !appState.selectedFindingIds.isEmpty {
                    Button(role: .destructive, action: {
                        appState.showFindingConfirmSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.fill")
                            Text("Clean Selected (\(appState.selectedFindingIds.count))")
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

            // Findings List / Table
            if filteredFindings.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.green.opacity(0.8))
                    Text("No findings match the current filter")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(appState.findings.isEmpty ? "Run a scan to analyze storage opportunities." : "Try clearing search or choosing another filter category.")
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
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if appState.expandedFindingId == finding.id {
                                        appState.expandedFindingId = nil
                                    } else {
                                        appState.expandedFindingId = finding.id
                                    }
                                }
                            }
                        )
                    }

                    if currentSourceCount > filteredFindings.count {
                        HStack {
                            Spacer()
                            Button("Load 100 More (Showing \(filteredFindings.count) of \(currentSourceCount))") {
                                appState.findingsDisplayLimit += 100
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
            Text("Selected files will be handled according to their verified safety policy (moved to Trash or managed quarantine with full undo capability).")
        }
    }

    private var safeCount: Int {
        appState.safeCount
    }

    private var reviewCount: Int {
        appState.reviewCount
    }

    private var keepCount: Int {
        appState.keepCount
    }

    private var currentSource: [Finding] {
        switch appState.selectedFindingFilterIndex {
        case 1: return appState.safeFindings
        case 2: return appState.reviewFindings
        case 3: return appState.keepFindings
        default: return appState.findings
        }
    }

    private var currentSourceCount: Int {
        switch appState.selectedFindingFilterIndex {
        case 1: return appState.safeCount
        case 2: return appState.reviewCount
        case 3: return appState.keepCount
        default: return appState.findings.count
        }
    }

    private var filteredFindings: [Finding] {
        let source = currentSource
        if appState.findingSearchText.isEmpty {
            return Array(source.prefix(appState.findingsDisplayLimit))
        } else {
            let query = appState.findingSearchText
            return Array(source.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.path.localizedCaseInsensitiveContains(query) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(query)
            }.prefix(appState.findingsDisplayLimit))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in onToggleSelect() }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                Image(systemName: finding.category.iconName)
                    .font(.system(size: 15))
                    .foregroundColor(SquirrelTheme.color(for: finding.category))
                    .frame(width: 28, height: 28)
                    .background(SquirrelTheme.color(for: finding.category).opacity(0.12))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(finding.path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(action: {
                    NSWorkspace.shared.selectFile(finding.path, inFileViewerRootedAtPath: "")
                }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                EligibilityBadge(eligibility: finding.eligibility)

                Text(ByteCountFormatter.string(fromByteCount: finding.allocatedSize, countStyle: .file))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(width: 85, alignment: .trailing)

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Rule:")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.secondary)
                                Text(finding.ruleId)
                                    .font(.caption2.weight(.semibold).monospaced())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                            }
                            Text(finding.ruleDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Recovery Strategy")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)
                            Text(finding.recoveryMethod.rawValue)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.primary)
                        }
                    }

                    if !finding.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Technical Evidence:")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)
                            ForEach(finding.evidence, id: \.self) { ev in
                                HStack(spacing: 5) {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(ev)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Safety & Consequences:")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)
                        Text(finding.consequencesExplanation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 36)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EligibilityBadge: View {
    let eligibility: CleanupEligibility

    var body: some View {
        Text(eligibility.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bgColor.opacity(0.14))
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
