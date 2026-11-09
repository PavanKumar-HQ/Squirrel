import SwiftUI
import SquirrelCore

public struct ReadyToCleanView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var summary: ReadyToCleanSummary {
        appState.readyToCleanSummary
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Feedback Banner if clean recently finished
                    if appState.showCleanResultBanner, let result = appState.lastCleanResult {
                        cleanupFeedbackBanner(result)
                    }

                    // Header Section
                    headerSection

                    // 4 Clean Group Cards
                    VStack(spacing: 12) {
                        ForEach(CleanGroupCategory.allCases) { category in
                            categoryCard(for: category)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 90) // Clearance for bottom bar
            }

            // Bottom Sticky Action Bar (Matching Mole's bottom bar)
            bottomActionBar
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if summary.items.isEmpty && !appState.isAuditingHub {
                appState.performHubAudit()
            }
        }
        .alert(isPresented: $appState.showHubConfirmClean) {
            Alert(
                title: Text("Clean \(formatted(summary.totalCleanableBytes))?"),
                message: Text("Selected build artifacts, caches, and snapshots will be safely moved to macOS Trash or purged. This cannot be undone."),
                primaryButton: .destructive(Text("Clean \(formatted(summary.totalCleanableBytes))")) {
                    Task {
                        await appState.cleanSelectedHubItems()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Cleanup Feedback Banner
    private func cleanupFeedbackBanner(_ result: CleanResultFeedback) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text("Cleaned \(formatted(result.reclaimedBytes)) successfully!")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                Text("\(result.itemsCleanedCount) items removed.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if result.itemsSkippedCount > 0 {
                    Text("\(result.itemsSkippedCount) items deferred because their application or CLI process is actively running.")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
            }

            Spacer()

            Button {
                appState.showCleanResultBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.green.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text("Ready to clean")
                    .font(.system(size: 26, weight: .bold))

                Spacer()

                if appState.isAuditingHub {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(appState.hubAuditProgress)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button {
                        appState.performHubAudit()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rescan categories")
                }
            }

            HStack(spacing: 6) {
                let cleanableStr = formatted(summary.totalCleanableBytes)
                let availableStr = formatted(appState.volumeSpace.availableCapacity + summary.totalCleanableBytes)

                Text("\(cleanableStr) cleanable")
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("·")
                    .foregroundColor(.secondary)

                Text("\(availableStr) free after")
                    .foregroundColor(.secondary)

                if !summary.hasFullDiskAccess {
                    Text("·")
                        .foregroundColor(.secondary)

                    Text("Some caches were skipped")
                        .foregroundColor(.secondary)

                    Button("Enable Disk Access") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(SquirrelTheme.brandWarm)
                    .underline()
                }
            }
            .font(.system(size: 13))
        }
    }

    // MARK: - Category Card
    private func categoryCard(for category: CleanGroupCategory) -> some View {
        let items = summary.items(for: category)
        let totalBytes = summary.size(for: category)
        let isExpanded = appState.expandedHubCategories.contains(category)
        let allSelected = !items.isEmpty && items.allSatisfy { $0.isSelected }
        let someSelected = items.contains { $0.isSelected }

        return VStack(spacing: 0) {
            // Main Category Row
            HStack(alignment: .center, spacing: 14) {
                // Checkbox
                Button {
                    appState.toggleHubCategory(category: category, isSelected: !allSelected)
                } label: {
                    Image(systemName: allSelected ? "checkmark.square.fill" : (someSelected ? "minus.square.fill" : "square"))
                        .font(.system(size: 16))
                        .foregroundColor(allSelected || someSelected ? SquirrelTheme.brandWarm : .secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)

                // Category Title & Subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(category.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Total Size
                Text(items.isEmpty ? "Zero KB" : formatted(totalBytes))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(items.isEmpty ? .secondary.opacity(0.5) : .primary)

                // Expand/Collapse Chevron
                Button {
                    if isExpanded {
                        appState.expandedHubCategories.remove(category)
                    } else {
                        appState.expandedHubCategories.insert(category)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Expanded Items List
            if isExpanded && !items.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

                VStack(spacing: 0) {
                    ForEach(items) { item in
                        itemRow(for: item)
                    }
                }
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.02))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Item Row inside Card
    private func itemRow(for item: CleanableItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                if let idx = appState.readyToCleanSummary.items.firstIndex(where: { $0.id == item.id }) {
                    appState.readyToCleanSummary.items[idx].isSelected.toggle()
                }
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(item.isSelected ? SquirrelTheme.brandWarm : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    if item.isProcessRunning {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                            Text(item.activeProcessName ?? "Running")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(4)
                    }
                }

                Text(item.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(formatted(item.sizeBytes))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    // MARK: - Bottom Action Bar
    private var bottomActionBar: some View {
        let selectedCount = summary.items.filter { $0.isSelected }.count
        let totalCleanable = summary.totalCleanableBytes

        return HStack(alignment: .center) {
            // Count
            Text("\(selectedCount) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            // Selection shortcuts
            HStack(spacing: 6) {
                Button("All") {
                    appState.selectAllHubItems(selected: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SquirrelTheme.brandWarm)

                Text("·")
                    .foregroundColor(.secondary)

                Button("None") {
                    appState.selectAllHubItems(selected: false)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

                Text("·")
                    .foregroundColor(.secondary)

                Button("Recommended") {
                    appState.selectRecommendedHubItems()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SquirrelTheme.brandWarm)
            }
            .padding(.leading, 8)

            Spacer()

            // Main Action Pill Button
            Button {
                appState.showHubConfirmClean = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Permanently clean \(formatted(totalCleanable))")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(totalCleanable > 0 ? SquirrelTheme.brandWarm : Color.gray.opacity(0.4))
                )
            }
            .buttonStyle(.plain)
            .disabled(totalCleanable == 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Color(NSColor.windowBackgroundColor)
                .shadow(color: Color.black.opacity(0.12), radius: 6, y: -2)
        )
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
