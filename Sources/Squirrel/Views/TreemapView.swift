import SwiftUI
import SquirrelCore

public struct TreemapView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Navigation & Breadcrumbs Bar
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
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 0.8))
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
                    let computedRoot = computeCachedLayout(for: appState.activeTreemapRoot, in: CGRect(origin: .zero, size: size))

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
                                let hasNestedChildren = !child.children.isEmpty && (child.children.first?.rect.width ?? 0) > 0

                                if hasNestedChildren {
                                    // Group Container Background & Header
                                    ZStack(alignment: .topLeading) {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(SquirrelTheme.color(for: child.category).opacity(0.06))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(
                                                        appState.selectedTreemapNode?.id == child.id ? Color.accentColor : SquirrelTheme.color(for: child.category).opacity(0.3),
                                                        lineWidth: appState.selectedTreemapNode?.id == child.id ? 2.0 : 1.0
                                                    )
                                            )

                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(SquirrelTheme.color(for: child.category))
                                                .frame(width: 8, height: 8)

                                            Text(child.name)
                                                .font(.system(size: 11, weight: .bold))
                                                .lineLimit(1)

                                            Text("• \(ByteCountFormatter.string(fromByteCount: child.size, countStyle: .file))")
                                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                                .foregroundColor(.secondary)

                                            Text("(\(child.children.count) items)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)

                                            Spacer()

                                            Button(action: {
                                                appState.drillDownTreemap(to: child)
                                            }) {
                                                HStack(spacing: 3) {
                                                    Text("Drill Down")
                                                    Image(systemName: "chevron.right")
                                                }
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(.accentColor)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 8)
                                        .frame(width: max(0, child.rect.width), height: 24, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            appState.selectedTreemapNode = child
                                        }
                                    }
                                    .frame(width: max(0, child.rect.width), height: max(0, child.rect.height))
                                    .offset(x: child.rect.minX, y: child.rect.minY)

                                    // Inner child tiles
                                    ForEach(child.children) { innerChild in
                                        if innerChild.rect.width > 2 && innerChild.rect.height > 2 {
                                            TreemapTileView(
                                                node: innerChild,
                                                isSelected: appState.selectedTreemapNode?.id == innerChild.id,
                                                isHovered: appState.hoveredTreemapNodeId == innerChild.id,
                                                onSelect: {
                                                    appState.selectedTreemapNode = innerChild
                                                },
                                                onDrillDown: {
                                                    appState.drillDownTreemap(to: innerChild)
                                                }
                                            )
                                            .frame(width: max(0, innerChild.rect.width), height: max(0, innerChild.rect.height))
                                            .offset(x: innerChild.rect.minX, y: innerChild.rect.minY)
                                            .onHover { hovering in
                                                if hovering {
                                                    if appState.hoveredTreemapNodeId != innerChild.id {
                                                        appState.hoveredTreemapNodeId = innerChild.id
                                                    }
                                                } else if appState.hoveredTreemapNodeId == innerChild.id {
                                                    appState.hoveredTreemapNodeId = nil
                                                }
                                            }
                                        }
                                    }
                                } else {
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
                                        if hovering {
                                            if appState.hoveredTreemapNodeId != child.id {
                                                appState.hoveredTreemapNodeId = child.id
                                            }
                                        } else if appState.hoveredTreemapNodeId == child.id {
                                            appState.hoveredTreemapNodeId = nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 420, minHeight: 320)

                // Selected Item Inspector Sidebar
                if let selected = appState.selectedTreemapNode {
                    TreemapInspectorView(node: selected, appState: appState)
                        .frame(minWidth: 320, idealWidth: 340, maxWidth: 420)
                }
            }
        }
    }

    private func computeCachedLayout(for node: TreemapNode, in bounds: CGRect) -> TreemapNode {
        if let cached = appState.treemapCachedLayout, cached.rootId == node.id, cached.size == bounds.size {
            return cached.node
        }
        var mutable = node
        TreemapEngine.layoutSquarified(node: &mutable, bounds: bounds)
        appState.treemapCachedLayout = (node.id, bounds.size, mutable)
        return mutable
    }
}

struct TreemapTileView: View {
    let node: TreemapNode
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onDrillDown: () -> Void

    private var tileBaseColor: Color {
        let base = SquirrelTheme.color(for: node.category)
        let hashOffset = Double(abs(node.name.hashValue) % 7) - 3.0
        let opacity = max(0.74, min(0.98, 0.88 + (hashOffset * 0.03)))
        return base.opacity(opacity)
    }

    private var fileIconName: String {
        if node.isDirectory {
            return "folder.fill"
        }
        let lower = node.name.lowercased()
        if lower.hasSuffix(".dmg") || lower.hasSuffix(".iso") {
            return "externaldrive.fill"
        } else if lower.hasSuffix(".pkg") || lower.hasSuffix(".xip") || lower.hasSuffix(".zip") || lower.hasSuffix(".tar.gz") {
            return "shippingbox.fill"
        } else if lower.hasSuffix(".app") {
            return "app.fill"
        } else if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".mkv") {
            return "film.fill"
        } else if lower.hasSuffix(".pdf") {
            return "doc.richtext.fill"
        } else if lower.hasSuffix(".log") {
            return "doc.text.fill"
        } else {
            return "doc.fill"
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tileBaseColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isSelected ? Color.white : (isHovered ? Color.white.opacity(0.9) : Color.black.opacity(0.18)),
                            lineWidth: isSelected ? 2.5 : (isHovered ? 1.5 : 0.8)
                        )
                )

            if node.rect.width > 42 && node.rect.height > 24 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: fileIconName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))

                        Text(node.name)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
                    }

                    if node.rect.height > 40 {
                        Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundColor(.white.opacity(0.95))
                            .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
                    }

                    if node.isDirectory && node.rect.height > 64 && node.rect.width > 90 {
                        Text("Double-click to open")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 1)
                    }
                }
                .padding(5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if node.isDirectory && !node.children.isEmpty {
                onDrillDown()
            } else if FileManager.default.fileExists(atPath: node.path) {
                NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
            }
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .help("\(node.name) — \(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))\n\(node.path)")
        .contextMenu {
            Button("Inspect Item") { onSelect() }
            if node.isDirectory && !node.children.isEmpty {
                Button("Drill Down into \(node.name)") { onDrillDown() }
            }
            if FileManager.default.fileExists(atPath: node.path) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("METRICS & METADATA")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    InspectorRow(label: "Allocated Size", value: ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                    InspectorRow(label: "Item Type", value: node.isDirectory ? "Directory / Bundle" : "Regular File")

                    VStack(alignment: .leading, spacing: 3) {
                        Text("FILESYSTEM PATH")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(node.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
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

                Spacer(minLength: 20)

                VStack(spacing: 8) {
                    if node.isDirectory && !node.children.isEmpty {
                        Button(action: {
                            appState.drillDownTreemap(to: node)
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.right.and.arrow.up.left")
                                Text("Drill Down into \(node.name)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }

                    if FileManager.default.fileExists(atPath: node.path) {
                        Button(action: {
                            NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                        }) {
                            HStack {
                                Image(systemName: "arrow.up.right.square")
                                Text("Reveal in Finder")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(node.path, forType: .string)
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Path")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
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
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}
