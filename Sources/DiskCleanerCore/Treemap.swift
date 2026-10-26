// Treemap.swift – Squarified treemap layout (Bruls et al.)
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A simple rectangle struct for treemap layout, usable without CoreGraphics.
public struct TMRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { width * height }

    public static let zero = TMRect(x: 0, y: 0, width: 0, height: 0)
}

/// Squarified treemap layout algorithm.
public struct TreemapLayout: Sendable {

    public init() {}

    /// Lay out items with given sizes into the specified rectangle.
    /// Returns rects in the same order as the input sizes.
    /// Zero or negative sizes produce zero-area rects at the origin of `rect`.
    public static func layout(sizes: [Double], in rect: TMRect) -> [TMRect] {
        guard !sizes.isEmpty else { return [] }
        let totalArea = rect.width * rect.height
        let totalSize = sizes.reduce(0, +)

        // Build indexed items, filter positives
        struct IndexedItem {
            let index: Int
            let size: Double
        }

        var positiveItems: [IndexedItem] = []
        var results: [TMRect] = Array(repeating: TMRect.zero, count: sizes.count)

        for (i, s) in sizes.enumerated() {
            if s > 0 {
                positiveItems.append(IndexedItem(index: i, size: s))
            }
        }

        guard !positiveItems.isEmpty, totalSize > 0, totalArea > 0 else {
            return results
        }

        // Sort by size descending for squarification
        let sorted = positiveItems.sorted { $0.size > $1.size }
        // Normalize to areas
        let areas = sorted.map { $0.size / totalSize * totalArea }

        // Squarify
        let laidOut = squarify(areas: areas, in: rect)
        for (i, r) in laidOut.enumerated() {
            results[sorted[i].index] = r
        }

        return results
    }

    /// Lay out a FileNode's children, grouping tiny items into an "other" bucket.
    /// Returns (node-or-nil, rect) pairs. A nil node means it's the "other" bucket.
    public static func layoutChildren(
        of node: FileNode,
        in rect: TMRect,
        minFraction: Double = 0.005
    ) -> [(node: FileNode?, rect: TMRect)] {
        guard !node.children.isEmpty else { return [] }
        let total = Double(node.totalAllocatedSize)
        guard total > 0 else { return [] }

        var mainChildren: [FileNode] = []
        var otherSize: Double = 0

        for child in node.children {
            let childSize = Double(child.totalAllocatedSize)
            if childSize / total >= minFraction {
                mainChildren.append(child)
            } else {
                otherSize += childSize
            }
        }

        var sizes = mainChildren.map { Double($0.totalAllocatedSize) }
        if otherSize > 0 {
            sizes.append(otherSize)
        }

        let rects = layout(sizes: sizes, in: rect)
        var result: [(node: FileNode?, rect: TMRect)] = []
        for (i, child) in mainChildren.enumerated() {
            result.append((node: child, rect: rects[i]))
        }
        if otherSize > 0 {
            result.append((node: nil, rect: rects[sizes.count - 1]))
        }
        return result
    }

    // MARK: - Squarification internals

    private static func squarify(areas: [Double], in rect: TMRect) -> [TMRect] {
        var results: [TMRect] = Array(repeating: TMRect.zero, count: areas.count)
        var remaining = rect
        var idx = 0
        let n = areas.count

        while idx < n {
            let shorter: Double = min(remaining.width, remaining.height)
            if shorter <= 0 { break }

            // Greedily add items to the current row while aspect ratio improves
            var row: [Int] = [idx]
            var rowSum: Double = areas[idx]
            idx += 1

            while idx < n {
                let candidate = areas[idx]
                let newSum = rowSum + candidate
                let worstBefore = worstAspect(row: row.map { areas[$0] }, shorter: shorter, rowSum: rowSum)
                let testRow = row.map { areas[$0] } + [candidate]
                let worstAfter = worstAspectForAreas(areas: testRow, shorter: shorter, rowSum: newSum)
                if worstAfter <= worstBefore {
                    row.append(idx)
                    rowSum = newSum
                    idx += 1
                } else {
                    break
                }
            }

            // Lay out the row
            let rowLength = rowSum / shorter
            let isHorizontal = remaining.width >= remaining.height
            var offset: Double = 0

            for i in row {
                let itemLength = areas[i] / rowLength
                if isHorizontal {
                    results[i] = TMRect(
                        x: remaining.x,
                        y: remaining.y + offset,
                        width: rowLength,
                        height: itemLength
                    )
                } else {
                    results[i] = TMRect(
                        x: remaining.x + offset,
                        y: remaining.y,
                        width: itemLength,
                        height: rowLength
                    )
                }
                offset += itemLength
            }

            // Shrink remaining rect
            if isHorizontal {
                remaining = TMRect(
                    x: remaining.x + rowLength,
                    y: remaining.y,
                    width: remaining.width - rowLength,
                    height: remaining.height
                )
            } else {
                remaining = TMRect(
                    x: remaining.x,
                    y: remaining.y + rowLength,
                    width: remaining.width,
                    height: remaining.height - rowLength
                )
            }
        }

        return results
    }

    private static func worstAspect(row: [Double], shorter: Double, rowSum: Double) -> Double {
        return worstAspectForAreas(areas: row, shorter: shorter, rowSum: rowSum)
    }

    private static func worstAspectForAreas(areas: [Double], shorter: Double, rowSum: Double) -> Double {
        guard shorter > 0, rowSum > 0 else { return Double.infinity }
        let s2 = shorter * shorter
        var worst: Double = 0
        for a in areas {
            guard a > 0 else { continue }
            let r1 = (s2 * a) / (rowSum * rowSum)
            let r2 = (rowSum * rowSum) / (s2 * a)
            let aspect = max(r1, r2)
            worst = max(worst, aspect)
        }
        return worst
    }
}
