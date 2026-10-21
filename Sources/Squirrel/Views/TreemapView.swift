import SwiftUI
import SquirrelCore

public struct TreemapView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Liquid Glass Navigation & Breadcrumbs Bar
            HStack(spacing: 8) {
                Button(action: {
                    appState.resetTreemapToOverview()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive")
                        Text("Overview")
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(appState.activeTreemapRoot.id == appState.treemapRoot.id ? .primary : .accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(appState.activeTreemapRoot.id == appState.treemapRoot.id ? Color.secondary.opacity(0.12) : Color.clear)
                )

                ForEach(Array(appState.treemapBreadcrumbs.enumerated()), id: \.offset) { index, crumb in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))

                    Button(action: {
                        appState.navigateTreemapBreadcrumb(at: index)
                    }) {
                        Text(crumb.name)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(index == appState.treemapBreadcrumbs.count - 1 ? .primary : .accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }

                Spacer()

                if let selected = appState.selectedTreemapNode {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(SquirrelTheme.color(for: selected.category))
                            .frame(width: 8, height: 8)
                        Text("\(selected.name) — \(ByteCountFormatter.string(fromByteCount: selected.size, countStyle: .file))")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .liquidGlassCapsule()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

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
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No items to display for this node")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Select another directory from the overview or breadcrumbs.")
                                    .font(.caption)
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
                .frame(minWidth: 420, minHeight: 320)

                // Selected Item Inspector Sidebar
                if let selected = appState.selectedTreemapNode {
                    TreemapInspectorView(node: selected, appState: appState)
                        .frame(minWidth: 280, maxWidth: 360)
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SquirrelTheme.color(for: node.category),
                                SquirrelTheme.color(for: node.category).opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                isSelected ? Color.white : (isHovered ? Color.white.opacity(0.6) : Color.black.opacity(0.12)),
                                lineWidth: isSelected ? 2.5 : 0.8
                            )
                    )
                    .shadow(color: isSelected ? Color.black.opacity(0.2) : Color.clear, radius: 4, x: 0, y: 2)

                if node.rect.width > 54 && node.rect.height > 32 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)

                        if node.rect.height > 46 {
                            Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundColor(.white.opacity(0.92))
                                .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
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
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }
}

struct TreemapInspectorView: View {
    let node: TreemapNode
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: node.category.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(SquirrelTheme.color(for: node.category))
                        .frame(width: 36, height: 36)
                        .background(SquirrelTheme.color(for: node.category).opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(node.category.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("METRICS & METADATA")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    InspectorRow(label: "Allocated Size", value: ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                    InspectorRow(label: "Item Type", value: node.isDirectory ? "Directory / Bundle" : "Regular File")
                    InspectorRow(label: "Filesystem Path", value: node.path)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("CATEGORY DESCRIPTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(node.category.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(spacing: 8) {
                    if !node.children.isEmpty {
                        LiquidGlassButton("Drill Down into Folder", icon: "arrow.down.forward.and.arrow.up.backward") {
                            appState.drillDownTreemap(to: node)
                        }
                    }

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
                        .controlSize(.regular)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }
}
