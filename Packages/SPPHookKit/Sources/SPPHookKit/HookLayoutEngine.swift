import Foundation

// NOTE: No SwiftUI or AppKit/UIKit imports — pure geometry only.

// MARK: - HookNodePosition

/// The computed canvas position for a single graph node.
public struct HookNodePosition: Sendable {
    /// The node whose position this describes.
    public let nodeID: UUID
    /// Horizontal position in points, measured from the canvas origin (top-left).
    public let x: Double
    /// Vertical position in points, measured from the canvas origin (top-left).
    public let y: Double

    public init(nodeID: UUID, x: Double, y: Double) {
        self.nodeID = nodeID
        self.x = x
        self.y = y
    }
}

// MARK: - HookLayoutResult

/// The complete output of a layout pass: per-node positions plus canvas bounds.
public struct HookLayoutResult: Sendable {
    /// Per-node positions, keyed by `HookNode.id`.
    public let positions: [UUID: HookNodePosition]
    /// Total canvas width required to contain all positioned nodes with padding.
    public let canvasWidth: Double
    /// Total canvas height required to contain all positioned nodes with padding.
    public let canvasHeight: Double

    public init(
        positions: [UUID: HookNodePosition],
        canvasWidth: Double,
        canvasHeight: Double
    ) {
        self.positions = positions
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    /// Convenience: returns a result with no nodes and zero canvas dimensions.
    public static let empty = HookLayoutResult(positions: [:], canvasWidth: 0, canvasHeight: 0)
}

// MARK: - HookLayoutEngine

/// Computes a layered, left-to-right graph layout for a `HookGraph`.
///
/// Algorithm:
/// 1. Obtain a topological sort from the graph (Kahn's algorithm with cycle fallback).
/// 2. Assign each node to a *layer* (column) via BFS from root nodes (in-degree == 0).
///    Nodes whose longest path from a root is `k` hops are placed in layer `k`.
/// 3. Within each layer nodes are stacked vertically in topological order.
/// 4. Canvas bounds are derived from the outermost position plus one cell of padding.
///
/// All work is actor-isolated; the caller `await`s `layout(graph:)`.
public actor HookLayoutEngine {

    // MARK: Configuration

    /// Horizontal distance (in points) between the centres of adjacent layers.
    public let nodeSpacingX: Double

    /// Vertical distance (in points) between the centres of adjacent nodes within a layer.
    public let nodeSpacingY: Double

    // MARK: Initializer

    public init(nodeSpacingX: Double = 200, nodeSpacingY: Double = 100) {
        self.nodeSpacingX = nodeSpacingX
        self.nodeSpacingY = nodeSpacingY
    }

    // MARK: Public API

    /// Runs a full layout pass and returns positions for every node in the graph.
    ///
    /// - Parameter graph: The `HookGraph` actor to lay out.
    /// - Returns: A `HookLayoutResult` with computed positions and canvas dimensions.
    public func layout(graph: HookGraph) async -> HookLayoutResult {
        // Snapshot the graph state we need.
        let sortedIDs   = await graph.topologicalSort()
        let allNodes    = await graph.nodes
        let allEdges    = await graph.edges

        guard !sortedIDs.isEmpty else { return .empty }

        // MARK: Layer Assignment via BFS

        // Build a forward adjacency list and in-degree map from the edge snapshot.
        let presentIDs = Set(allNodes.keys)
        var successors: [UUID: [UUID]] = [:]
        var inDegree:   [UUID: Int]   = [:]

        for id in presentIDs {
            successors[id] = []
            inDegree[id]   = 0
        }

        // Deduplicate edges (same src→dst might appear multiple times with different IDs).
        var seenPairs = Set<EdgePair>()
        for edge in allEdges.values {
            guard presentIDs.contains(edge.sourceID),
                  presentIDs.contains(edge.targetID) else { continue }
            let pair = EdgePair(src: edge.sourceID, dst: edge.targetID)
            guard seenPairs.insert(pair).inserted else { continue }
            successors[edge.sourceID]!.append(edge.targetID)
            inDegree[edge.targetID]!  += 1
        }

        // BFS: assign each node the length of its longest incoming path from a root.
        // We use the topological order to process nodes so parents are always handled
        // before children, allowing O(V+E) longest-path via relaxation.
        var layer: [UUID: Int] = [:]
        for id in sortedIDs {
            if (inDegree[id] ?? 0) == 0 {
                layer[id] = 0
            }
        }

        for id in sortedIDs {
            let currentLayer = layer[id] ?? 0
            for neighbour in successors[id] ?? [] {
                let proposed = currentLayer + 1
                if proposed > (layer[neighbour] ?? 0) {
                    layer[neighbour] = proposed
                }
            }
        }

        // Ensure every node has a layer even if the graph has disconnected components
        // or nodes that were not reachable from a topological root (cycle tail nodes).
        for id in sortedIDs where layer[id] == nil {
            layer[id] = 0
        }

        // MARK: Group nodes into layers, preserving topological order within each layer

        // Determine total number of layers.
        let maxLayer = layer.values.max() ?? 0

        // For each layer collect node IDs in topological order.
        var layerNodes: [[UUID]] = Array(repeating: [], count: maxLayer + 1)
        for id in sortedIDs {
            let l = layer[id] ?? 0
            layerNodes[l].append(id)
        }

        // MARK: Compute Positions

        // Padding equal to half a cell on each side.
        let paddingX = nodeSpacingX / 2
        let paddingY = nodeSpacingY / 2

        var positions: [UUID: HookNodePosition] = [:]
        positions.reserveCapacity(sortedIDs.count)

        for (layerIndex, nodeIDs) in layerNodes.enumerated() {
            let x = paddingX + Double(layerIndex) * nodeSpacingX
            for (rowIndex, nodeID) in nodeIDs.enumerated() {
                let y = paddingY + Double(rowIndex) * nodeSpacingY
                positions[nodeID] = HookNodePosition(nodeID: nodeID, x: x, y: y)
            }
        }

        // MARK: Canvas Bounds

        // Canvas must accommodate the rightmost centre plus a right-side padding.
        let canvasWidth: Double
        let canvasHeight: Double

        if positions.isEmpty {
            canvasWidth  = 0
            canvasHeight = 0
        } else {
            let maxX = positions.values.map(\.x).max()! + paddingX
            let maxY = positions.values.map(\.y).max()! + paddingY
            canvasWidth  = maxX
            canvasHeight = maxY
        }

        return HookLayoutResult(
            positions:    positions,
            canvasWidth:  canvasWidth,
            canvasHeight: canvasHeight
        )
    }

    // MARK: Private Helpers

    /// Lightweight struct used for deduplicating edges during layout.
    private struct EdgePair: Hashable {
        let src: UUID
        let dst: UUID
    }
}
