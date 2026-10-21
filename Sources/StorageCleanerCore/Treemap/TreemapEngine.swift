import Foundation
import CoreGraphics

/// A node in the storage visualization hierarchy.
public struct TreemapNode: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let path: String
    public let size: Int64
    public let category: StorageCategory
    public let isDirectory: Bool
    public var children: [TreemapNode]
    public var rect: CGRect

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        size: Int64,
        category: StorageCategory,
        isDirectory: Bool,
        children: [TreemapNode] = [],
        rect: CGRect = .zero
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.category = category
        self.isDirectory = isDirectory
        self.children = children
        self.rect = rect
    }
}

/// Squarified Treemap layout generator (Bruls, Huizing, van Wijk).
public struct TreemapEngine {
    public static func buildHierarchy(from items: [StorageItem]) -> TreemapNode {
        // Group by category first
        var categoryBuckets: [StorageCategory: [StorageItem]] = [:]
        for item in items {
            let cat = determineCategory(for: item)
            categoryBuckets[cat, default: []].append(item)
        }

        var rootChildren: [TreemapNode] = []
        var rootTotalSize: Int64 = 0

        for (category, catItems) in categoryBuckets {
            let catSize = catItems.reduce(0) { $0 + $1.allocatedSize }
            rootTotalSize += catSize

            // Sub-group largest items / subfolders within category
            let topItems = catItems
                .sorted { $0.allocatedSize > $1.allocatedSize }
                .prefix(25) // Top 25 largest items per category to keep UI crisp

            let childNodes = topItems.map { item in
                TreemapNode(
                    name: item.name,
                    path: item.path,
                    size: max(item.allocatedSize, 1024),
                    category: category,
                    isDirectory: item.isDirectory,
                    children: []
                )
            }

            let catNode = TreemapNode(
                name: category.rawValue,
                path: category.rawValue,
                size: max(catSize, 1024),
                category: category,
                isDirectory: true,
                children: childNodes
            )
            rootChildren.append(catNode)
        }

        rootChildren.sort { $0.size > $1.size }

        return TreemapNode(
            name: "Storage Overview",
            path: "/",
            size: max(rootTotalSize, 1024),
            category: .otherUserData,
            isDirectory: true,
            children: rootChildren
        )
    }

    /// Computes squarified bounding rectangles for children inside the given canvas bounds.
    public static func layoutSquarified(node: inout TreemapNode, bounds: CGRect) {
        node.rect = bounds
        guard !node.children.isEmpty, bounds.width > 0, bounds.height > 0 else { return }

        var children = node.children.sorted { $0.size > $1.size }
        let totalSize = children.reduce(0) { $0 + max(1, $1.size) }
        guard totalSize > 0 else { return }

        // Normalize values to available area
        let area = Double(bounds.width * bounds.height)
        let normalizedWeights: [Double] = children.map { Double($0.size) / Double(totalSize) * area }

        var remainingBounds = bounds
        var currentSlice: [Int] = []
        var currentIndex = 0

        while currentIndex < children.count {
            let nextIndex = currentIndex

            var testSlice = currentSlice
            testSlice.append(nextIndex)

            let isWidthShort = remainingBounds.width < remainingBounds.height
            let length = Double(isWidthShort ? remainingBounds.width : remainingBounds.height)

            if currentSlice.isEmpty || worstRatio(weights: testSlice.map { normalizedWeights[$0] }, length: length) <= worstRatio(weights: currentSlice.map { normalizedWeights[$0] }, length: length) {
                currentSlice.append(nextIndex)
                currentIndex += 1
            } else {
                // Layout current row/slice
                layoutRow(slice: currentSlice, weights: normalizedWeights, bounds: &remainingBounds, children: &children)
                currentSlice.removeAll()
            }
        }

        if !currentSlice.isEmpty {
            layoutRow(slice: currentSlice, weights: normalizedWeights, bounds: &remainingBounds, children: &children)
        }

        node.children = children
    }

    private static func layoutRow(
        slice: [Int],
        weights: [Double],
        bounds: inout CGRect,
        children: inout [TreemapNode]
    ) {
        guard !slice.isEmpty else { return }
        let sliceWeight = slice.reduce(0.0) { $0 + weights[$1] }
        let isVertical = bounds.width < bounds.height

        if isVertical {
            let rowHeight = CGFloat(sliceWeight / Double(max(1.0, bounds.width)))
            var currentX = bounds.minX

            for idx in slice {
                let itemWidth = CGFloat(weights[idx] / Double(max(1.0, rowHeight)))
                let itemRect = CGRect(x: currentX, y: bounds.minY, width: itemWidth, height: rowHeight)
                children[idx].rect = itemRect
                currentX += itemWidth
            }
            bounds = CGRect(x: bounds.minX, y: bounds.minY + rowHeight, width: bounds.width, height: max(0, bounds.height - rowHeight))
        } else {
            let rowWidth = CGFloat(sliceWeight / Double(max(1.0, bounds.height)))
            var currentY = bounds.minY

            for idx in slice {
                let itemHeight = CGFloat(weights[idx] / Double(max(1.0, rowWidth)))
                let itemRect = CGRect(x: bounds.minX, y: currentY, width: rowWidth, height: itemHeight)
                children[idx].rect = itemRect
                currentY += itemHeight
            }
            bounds = CGRect(x: bounds.minX + rowWidth, y: bounds.minY, width: max(0, bounds.width - rowWidth), height: bounds.height)
        }
    }

    private static func worstRatio(weights: [Double], length: Double) -> Double {
        guard !weights.isEmpty, length > 0 else { return Double.greatestFiniteMagnitude }
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return Double.greatestFiniteMagnitude }

        let minWeight = weights.min() ?? 1.0
        let maxWeight = weights.max() ?? 1.0
        let lenSq = length * length

        let ratio1 = (lenSq * maxWeight) / (sum * sum)
        let ratio2 = (sum * sum) / (lenSq * minWeight)
        return max(ratio1, ratio2)
    }

    private static func determineCategory(for item: StorageItem) -> StorageCategory {
        let path = item.path.lowercased()
        if path.contains("/caches/") || path.hasSuffix("/caches") {
            return .userCaches
        } else if path.contains("/logs/") || path.hasSuffix(".log") || path.hasSuffix(".diag") || path.hasSuffix(".crash") {
            return .systemLogs
        } else if path.hasSuffix(".dmg") || path.hasSuffix(".pkg") || path.hasSuffix(".iso") || path.contains("/downloads/") {
            return .downloadsAndInstallers
        } else if item.logicalSize >= 100 * 1024 * 1024 {
            return .largeFiles
        } else {
            return .otherUserData
        }
    }
}
