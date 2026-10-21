import SwiftUI
import StorageCleanerCore

public struct TreemapView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Breadcrumbs Bar
            HStack(spacing: 8) {
                Button(action: {
                    appState.resetTreemapToOverview()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive")
                        Text("Overview")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(appState.activeTreemapRoot.id == appState.treemapRoot.id ? .primary : .accentColor)

                ForEach(Array(appState.treemapBreadcrumbs.enumerated()), id: \.offset) { index, crumb in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button(action: {
                        appState.navigateTreemapBreadcrumb(at: index)
                    }) {
                        Text(crumb.name)
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(index == appState.treemapBreadcrumbs.count - 1 ? .primary : .accentColor)
                }

                Spacer()

                if let selected = appState.selectedTreemapNode {
                    Text("\(selected.name) — \(ByteCountFormatter.string(fromByteCount: selected.size, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main Treemap canvas and details split
            HSplitView {
                // Interactive Treemap Canvas
                GeometryReader { geo in
                    let size = geo.size
                    let computedRoot = computeLayout(for: appState.activeTreemapRoot, in: CGRect(origin: .zero, size: size))

                    ZStack(alignment: .topLeading) {
                        Color(NSColor.underPageBackgroundColor)

                        if computedRoot.children.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "folder.badge.questionmark")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("No items to display for this node")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ForEach(computedRoot.children) { child in
                                TreemapTileView(
                                    node: child,
                                    isSelected: appState.selectedTreemapNode?.id == child.id,
                                    isHovered: appState.hoveredTreemapNodeId == child.id,
                                    onSelect: {
                                        appState.selectedTreemapNode = child
                                    },
                                    onDrillDown: {
                                        appState.drillDownTreemap(to: child)
                                    }
                                )
                                .frame(width: max(0, child.rect.width), height: max(0, child.rect.height))
                                .offset(x: child.rect.minX, y: child.rect.minY)
                                .onHover { hovering in
                                    appState.hoveredTreemapNodeId = hovering ? child.id : nil
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 400, minHeight: 300)

                // Selected Item Inspector Sidebar
                if let selected = appState.selectedTreemapNode {
                    TreemapInspectorView(node: selected, appState: appState)
                        .frame(minWidth: 260, maxWidth: 320)
                }
            }
        }
    }

    private func computeLayout(for node: TreemapNode, in bounds: CGRect) -> TreemapNode {
        var mutable = node
        TreemapEngine.layoutSquarified(node: &mutable, bounds: bounds)
        return mutable
    }
}

struct TreemapTileView: View {
    let node: TreemapNode
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onDrillDown: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorForCategory(node.category))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.accentColor : (isHovered ? Color.white.opacity(0.4) : Color.black.opacity(0.1)), lineWidth: isSelected ? 2.5 : 1)
                    )

                if node.rect.width > 50 && node.rect.height > 30 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.white)

                        if node.rect.height > 44 {
                            Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Inspect Item") { onSelect() }
            if !node.children.isEmpty {
                Button("Drill Down into \(node.name)") { onDrillDown() }
            }
            if FileManager.default.fileExists(atPath: node.path) {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    private func colorForCategory(_ category: StorageCategory) -> Color {
        switch category {
        case .userCaches:
            return Color(red: 0.22, green: 0.53, blue: 0.78)
        case .systemLogs:
            return Color(red: 0.45, green: 0.50, blue: 0.58)
        case .downloadsAndInstallers:
            return Color(red: 0.85, green: 0.52, blue: 0.22)
        case .largeFiles:
            return Color(red: 0.80, green: 0.35, blue: 0.35)
        case .duplicates:
            return Color(red: 0.60, green: 0.40, blue: 0.75)
        case .appLeftovers:
            return Color(red: 0.35, green: 0.65, blue: 0.55)
        case .otherUserData:
            return Color(red: 0.35, green: 0.45, blue: 0.60)
        }
    }
}

struct TreemapInspectorView: View {
    let node: TreemapNode
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: node.category.iconName)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text(node.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(node.category.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    LabelValueRow(label: "Allocated Size", value: ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                    LabelValueRow(label: "Type", value: node.isDirectory ? "Folder" : "File")
                    LabelValueRow(label: "Path", value: node.path)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Category Scope")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(node.category.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if FileManager.default.fileExists(atPath: node.path) {
                    Button(action: {
                        NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.forward.square")
                            Text("Reveal in Finder")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct LabelValueRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(3)
        }
    }
}
