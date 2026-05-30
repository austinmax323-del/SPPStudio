import Foundation
import SPPCore

// MARK: - HookNodeKind

/// Classifies the runtime mechanism a hook node represents.
public enum HookNodeKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// An Objective-C instance or class method swizzle.
    case methodHook
    /// A C-function-level hook (e.g. fishhook / MSHookFunction).
    case functionHook
    /// A Logos `%hook` class declaration (container for method hooks).
    case classHook
    /// A constructor / initializer hook.
    case ctorHook
    /// A destructor / dealloc hook.
    case dtorHook
    /// An `NSNotificationCenter` observer registration.
    case notificationObserver
    /// A `NSUserDefaults` / preference-bundle observer.
    case preferenceObserver
    /// A hook that targets SpringBoard exclusively.
    case springBoardHook
    /// A tweak lifecycle entry point (e.g. `%ctor`, `%dtor`).
    case lifecycleHook
}

// MARK: - MethodSignature

/// Describes the full Objective-C method signature for a hook node.
public struct MethodSignature: Codable, Hashable, Sendable {
    /// The Objective-C class name, or `nil` for free functions.
    public var className: String?
    /// The selector string (e.g. `"viewDidLoad"` or `"setFrame:"`).
    public var selectorName: String
    /// `true` when the method is a class ("+") method; `false` for instance ("-").
    public var isClassMethod: Bool
    /// The return-type encoding or human-readable type name (e.g. `"void"`, `"id"`).
    public var returnType: String
    /// Ordered list of argument type encodings or human-readable type names.
    public var argumentTypes: [String]

    public init(
        className: String? = nil,
        selectorName: String,
        isClassMethod: Bool = false,
        returnType: String = "void",
        argumentTypes: [String] = []
    ) {
        self.className = className
        self.selectorName = selectorName
        self.isClassMethod = isClassMethod
        self.returnType = returnType
        self.argumentTypes = argumentTypes
    }

    /// Human-readable Objective-C message expression.
    ///
    /// Examples:
    /// - `-[ViewController viewDidLoad]`
    /// - `+[NSObject alloc]`
    /// - `-[UIView setFrame:]`
    public var displayName: String {
        let prefix = isClassMethod ? "+" : "-"
        if let cls = className {
            return "\(prefix)[\(cls) \(selectorName)]"
        }
        return "\(prefix)[\(selectorName)]"
    }
}

// MARK: - HookNode

/// A single vertex in the hook graph, representing one hooking point.
public struct HookNode: Identifiable, Codable, Hashable, Sendable {
    /// Stable unique identifier.
    public let id: UUID
    /// The mechanism used by this hook.
    public var kind: HookNodeKind
    /// Short human-readable label shown in the graph UI.
    public var label: String
    /// Optional parsed method signature when `kind` is `.methodHook` or `.classHook`.
    public var signature: MethodSignature?
    /// The `SPPFile.id` of the source file that contains this hook, if known.
    public var sourceFileID: UUID?
    /// 1-based source line of the hook declaration, if known.
    public var sourceLine: Int?
    /// Freeform key-value metadata (e.g. `["framework": "UIKit"]`).
    public var metadata: [String: String]
    /// Optional `HookGroup.id` this node belongs to.
    public var groupID: UUID?

    public init(
        id: UUID = UUID(),
        kind: HookNodeKind,
        label: String,
        signature: MethodSignature? = nil,
        sourceFileID: UUID? = nil,
        sourceLine: Int? = nil,
        metadata: [String: String] = [:],
        groupID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.signature = signature
        self.sourceFileID = sourceFileID
        self.sourceLine = sourceLine
        self.metadata = metadata
        self.groupID = groupID
    }
}

// MARK: - HookEdgeKind

/// The semantic relationship between two nodes connected by a `HookEdge`.
public enum HookEdgeKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// The source node calls the target node (direct invocation).
    case calls
    /// The source node overrides / swizzles the target node.
    case overrides
    /// The source node requires the target node to be loaded first.
    case dependsOn
    /// The source node activates / enables the target node at runtime.
    case activates
    /// The source node suppresses or disables the target node.
    case suppressedBy
}

// MARK: - HookEdge

/// A directed edge in the hook graph connecting a source node to a target node.
public struct HookEdge: Identifiable, Codable, Hashable, Sendable {
    /// Stable unique identifier.
    public let id: UUID
    /// The originating node's `id`.
    public var sourceID: UUID
    /// The destination node's `id`.
    public var targetID: UUID
    /// The semantic relationship this edge encodes.
    public var kind: HookEdgeKind

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        targetID: UUID,
        kind: HookEdgeKind
    ) {
        self.id = id
        self.sourceID = sourceID
        self.targetID = targetID
        self.kind = kind
    }
}

// MARK: - HookGroup

/// A named collection of related nodes that can be collapsed for clarity.
public struct HookGroup: Identifiable, Codable, Sendable {
    /// Stable unique identifier.
    public let id: UUID
    /// Human-readable group label.
    public var label: String
    /// Ordered list of member `HookNode` IDs.
    public var nodeIDs: [UUID]
    /// When `true` the group is rendered collapsed in the UI.
    public var isCollapsed: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        nodeIDs: [UUID] = [],
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.label = label
        self.nodeIDs = nodeIDs
        self.isCollapsed = isCollapsed
    }
}

// MARK: - HookActivationChain

/// An ordered sequence of nodes that activate one after another at runtime.
public struct HookActivationChain: Identifiable, Codable, Sendable {
    /// Stable unique identifier.
    public let id: UUID
    /// Human-readable chain label.
    public var label: String
    /// Nodes in activation order; first element fires first.
    public var orderedNodeIDs: [UUID]

    public init(
        id: UUID = UUID(),
        label: String,
        orderedNodeIDs: [UUID] = []
    ) {
        self.id = id
        self.label = label
        self.orderedNodeIDs = orderedNodeIDs
    }
}

// MARK: - RuntimePatchOrder

/// Records the runtime patching position of a node in a multi-hook chain.
public struct RuntimePatchOrder: Codable, Sendable {
    /// The node whose patch position is described.
    public var nodeID: UUID
    /// Zero-based index in the runtime patch sequence.
    public var patchIndex: Int
    /// Human-readable explanation for this ordering decision.
    public var reason: String

    public init(nodeID: UUID, patchIndex: Int, reason: String) {
        self.nodeID = nodeID
        self.patchIndex = patchIndex
        self.reason = reason
    }
}

// MARK: - ConstructorGraph

/// Describes the constructor (`%ctor`) execution order across a tweak's components.
public struct ConstructorGraph: Codable, Sendable {
    /// Ordered constructor entries; lower `priority` fires earlier.
    public var entries: [CtorEntry]

    public init(entries: [CtorEntry] = []) {
        self.entries = entries
    }

    // MARK: CtorEntry

    /// A single constructor entry in the graph.
    public struct CtorEntry: Codable, Sendable {
        /// The `HookNode.id` of the lifecycle node this entry describes.
        public var nodeID: UUID
        /// Lower values execute first (analogous to `__attribute__((constructor(priority)))`).
        public var priority: Int
        /// The Mach-O image (dylib/bundle) name this constructor lives in, if known.
        public var imageName: String?

        public init(nodeID: UUID, priority: Int, imageName: String? = nil) {
            self.nodeID = nodeID
            self.priority = priority
            self.imageName = imageName
        }
    }
}

// MARK: - HookGraph

/// The primary data layer for the hook graph.
///
/// All mutations are actor-isolated; callers `await` on each operation.
/// Topology queries (edges(from:), topologicalSort) are also actor-isolated
/// to guarantee a consistent snapshot of the graph.
public actor HookGraph {

    // MARK: Storage

    /// All nodes keyed by their `id`.
    public private(set) var nodes: [UUID: HookNode] = [:]

    /// All edges keyed by their `id`.
    public private(set) var edges: [UUID: HookEdge] = [:]

    /// All groups keyed by their `id`.
    public private(set) var groups: [UUID: HookGroup] = [:]

    /// All activation chains in definition order.
    public private(set) var activationChains: [HookActivationChain] = []

    /// Insertion-order list of node IDs; used as fallback when a cycle is detected.
    private var nodeInsertionOrder: [UUID] = []

    // MARK: Initializer

    public init() {}

    // MARK: Node Mutations

    /// Inserts or replaces a node.  If a node with the same `id` already exists it is overwritten.
    public func addNode(_ node: HookNode) {
        if nodes[node.id] == nil {
            nodeInsertionOrder.append(node.id)
        }
        nodes[node.id] = node
    }

    /// Removes the node with the given `id` together with all incident edges.
    public func removeNode(id: UUID) {
        nodes.removeValue(forKey: id)
        nodeInsertionOrder.removeAll { $0 == id }
        // Prune every edge that references this node.
        let incident = edges.values.filter { $0.sourceID == id || $0.targetID == id }
        for edge in incident {
            edges.removeValue(forKey: edge.id)
        }
        // Remove from groups.
        for key in groups.keys {
            groups[key]?.nodeIDs.removeAll { $0 == id }
        }
        // Remove from activation chains.
        for index in activationChains.indices {
            activationChains[index].orderedNodeIDs.removeAll { $0 == id }
        }
    }

    // MARK: Edge Mutations

    /// Inserts or replaces an edge.
    public func addEdge(_ edge: HookEdge) {
        edges[edge.id] = edge
    }

    /// Removes the edge with the given `id`.
    public func removeEdge(id: UUID) {
        edges.removeValue(forKey: id)
    }

    // MARK: Group Mutations

    /// Inserts a new group.  Does not deduplicate; use `upsertGroup` if needed.
    public func addGroup(_ group: HookGroup) {
        groups[group.id] = group
    }

    /// Inserts the group if no group with its `id` exists; otherwise replaces it.
    public func upsertGroup(_ group: HookGroup) {
        groups[group.id] = group
    }

    // MARK: Activation Chain Mutations

    /// Appends an activation chain.
    public func addActivationChain(_ chain: HookActivationChain) {
        activationChains.append(chain)
    }

    // MARK: Queries

    /// Returns the node with the given `id`, or `nil`.
    public func node(id: UUID) -> HookNode? {
        nodes[id]
    }

    /// Returns all edges whose `sourceID` matches `nodeID`.
    public func edges(from nodeID: UUID) -> [HookEdge] {
        edges.values.filter { $0.sourceID == nodeID }
    }

    /// Returns all edges whose `targetID` matches `nodeID`.
    public func edges(to nodeID: UUID) -> [HookEdge] {
        edges.values.filter { $0.targetID == nodeID }
    }

    // MARK: Topological Sort (Kahn's Algorithm)

    /// Returns node IDs in a valid topological order using Kahn's algorithm.
    ///
    /// - Considers only nodes that are currently present in the graph.
    /// - If the graph contains a cycle the remaining cyclic nodes are appended
    ///   in their original insertion order so that every node ID is represented
    ///   in the result exactly once.
    public func topologicalSort() -> [UUID] {
        let presentIDs = Set(nodes.keys)
        guard !presentIDs.isEmpty else { return [] }

        // Build adjacency: successors[u] = set of v where edge u→v exists.
        var successors: [UUID: Set<UUID>] = [:]
        var inDegree: [UUID: Int] = [:]

        for id in presentIDs {
            successors[id] = []
            inDegree[id] = 0
        }

        for edge in edges.values {
            let src = edge.sourceID
            let dst = edge.targetID
            // Only consider edges where both endpoints are present nodes.
            guard presentIDs.contains(src), presentIDs.contains(dst) else { continue }
            if successors[src]!.insert(dst).inserted {
                inDegree[dst, default: 0] += 1
            }
        }

        // Seed the queue with all zero-in-degree nodes, respecting insertion order.
        var queue: [UUID] = nodeInsertionOrder.filter { presentIDs.contains($0) && inDegree[$0, default: 0] == 0 }
        var sorted: [UUID] = []
        sorted.reserveCapacity(presentIDs.count)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            sorted.append(current)

            // Iterate over successors in a deterministic order derived from insertion order.
            let succs = successors[current] ?? []
            let orderedSuccs = nodeInsertionOrder.filter { succs.contains($0) }
            for neighbour in orderedSuccs {
                inDegree[neighbour]! -= 1
                if inDegree[neighbour]! == 0 {
                    queue.append(neighbour)
                }
            }
        }

        // If sorted count < present count there is a cycle; append remaining nodes
        // in their original insertion order so the caller always gets a full list.
        if sorted.count < presentIDs.count {
            let emitted = Set(sorted)
            let cycleNodes = nodeInsertionOrder.filter { presentIDs.contains($0) && !emitted.contains($0) }
            sorted.append(contentsOf: cycleNodes)
        }

        return sorted
    }
}
