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
                VStack(alignment: .leading, spacing: 22) {
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
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

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
