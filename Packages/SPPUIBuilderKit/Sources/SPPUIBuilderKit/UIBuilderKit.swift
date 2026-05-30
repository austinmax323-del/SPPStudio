import Foundation
import SPPCore

// MARK: - ComponentKind

public enum ComponentKind: String, Codable, Hashable, Sendable, CaseIterable {
    case view
    case label
    case button
    case textField
    case imageView
    case stackView
    case scrollView
    case tableView
    case collectionView
    case switch_
    case slider
    case progressView
    case activityIndicator
    case custom
}

// MARK: - StackAxis

public enum StackAxis: String, Codable, Hashable, Sendable {
    case horizontal
    case vertical
}

// MARK: - ContentMode

public enum ContentMode: String, Codable, Hashable, Sendable {
    case scaleToFill
    case scaleAspectFit
    case scaleAspectFill
    case center
}

// MARK: - ComponentFont

public struct ComponentFont: Codable, Hashable, Sendable {
    public var family: String
    public var size: Double
    public var weight: String

    public init(family: String = "SF Pro Text", size: Double = 17, weight: String = "regular") {
        self.family = family
        self.size = size
        self.weight = weight
    }

    // MARK: Presets

    public static let body = ComponentFont(family: "SF Pro Text", size: 17, weight: "regular")
    public static let headline = ComponentFont(family: "SF Pro Display", size: 17, weight: "semibold")
    public static let caption = ComponentFont(family: "SF Pro Text", size: 12, weight: "regular")
    public static let title = ComponentFont(family: "SF Pro Display", size: 28, weight: "bold")
}

// MARK: - ComponentStyle

public struct ComponentStyle: Codable, Hashable, Sendable {
    public var backgroundColor: SPPColor?
    public var foregroundColor: SPPColor?
    public var tintColor: SPPColor?
    public var cornerRadius: Double
    public var borderWidth: Double
    public var borderColor: SPPColor?
    public var opacity: Double
    public var shadowRadius: Double
    public var shadowColor: SPPColor?
    public var shadowOffset: SPPPoint
    public var padding: SPPEdgeInsets
    public var font: ComponentFont?

    public init(
        backgroundColor: SPPColor? = nil,
        foregroundColor: SPPColor? = nil,
        tintColor: SPPColor? = nil,
        cornerRadius: Double = 0,
        borderWidth: Double = 0,
        borderColor: SPPColor? = nil,
        opacity: Double = 1.0,
        shadowRadius: Double = 0,
        shadowColor: SPPColor? = nil,
        shadowOffset: SPPPoint = .zero,
        padding: SPPEdgeInsets = .zero,
        font: ComponentFont? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.tintColor = tintColor
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.opacity = opacity
        self.shadowRadius = shadowRadius
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.padding = padding
        self.font = font
    }

    public static let `default` = ComponentStyle()
}

// MARK: - ComponentBehavior

public struct ComponentBehavior: Codable, Hashable, Sendable {
    public var isHidden: Bool
    public var isUserInteractionEnabled: Bool
    public var accessibilityLabel: String?
    public var accessibilityIdentifier: String?
    /// Action identifier resolved through the event system when the component is tapped.
    public var onTapActionID: String?

    public init(
        isHidden: Bool = false,
        isUserInteractionEnabled: Bool = true,
        accessibilityLabel: String? = nil,
        accessibilityIdentifier: String? = nil,
        onTapActionID: String? = nil
    ) {
        self.isHidden = isHidden
        self.isUserInteractionEnabled = isUserInteractionEnabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTapActionID = onTapActionID
    }

    public static let `default` = ComponentBehavior()
}

// MARK: - SPPUIComponent

public struct SPPUIComponent: Identifiable, Codable, Sendable {
    public let id: UUID
    public var kind: ComponentKind
    public var name: String
    public var frame: SPPRect
    public var style: ComponentStyle
    public var behavior: ComponentBehavior
    public var children: [SPPUIComponent]
    /// Kind-specific extra properties (e.g., "text", "imageName", "axis").
    public var properties: [String: String]

    public init(
        id: UUID = UUID(),
        kind: ComponentKind,
        name: String,
        frame: SPPRect = .zero,
        style: ComponentStyle = .default,
        behavior: ComponentBehavior = .default,
        children: [SPPUIComponent] = [],
        properties: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.frame = frame
        self.style = style
        self.behavior = behavior
        self.children = children
        self.properties = properties
    }

    // MARK: Tree traversal

    /// Returns this component and all descendants in depth-first order.
    public func allComponents() -> [SPPUIComponent] {
        var result: [SPPUIComponent] = [self]
        for child in children {
            result.append(contentsOf: child.allComponents())
        }
        return result
    }

    /// Searches this component and its descendants for a component matching `id`.
    public func component(id: UUID) -> SPPUIComponent? {
        if self.id == id { return self }
        for child in children {
            if let found = child.component(id: id) { return found }
        }
        return nil
    }
}

// MARK: - BuilderDocument

public struct BuilderDocument: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var schemaVersion: Int
    public var canvasSize: SPPSize
    public var rootComponents: [SPPUIComponent]

    public init(
        id: UUID = UUID(),
        name: String,
        schemaVersion: Int = 1,
        canvasSize: SPPSize = SPPSize(width: 390, height: 844),
        rootComponents: [SPPUIComponent] = []
    ) {
        self.id = id
        self.name = name
        self.schemaVersion = schemaVersion
        self.canvasSize = canvasSize
        self.rootComponents = rootComponents
    }

    // MARK: Queries

    /// Searches all root components and their descendants for a component matching `id`.
    public func component(id: UUID) -> SPPUIComponent? {
        for root in rootComponents {
            if let found = root.component(id: id) { return found }
        }
        return nil
    }

    // MARK: Mutations

    /// Inserts or replaces a root-level component matching by id.
    public mutating func upsertRootComponent(_ component: SPPUIComponent) {
        if let index = rootComponents.firstIndex(where: { $0.id == component.id }) {
            rootComponents[index] = component
        } else {
            rootComponents.append(component)
        }
    }

    /// Removes the root component whose id matches, if present.
    public mutating func removeRootComponent(id: UUID) {
        rootComponents.removeAll { $0.id == id }
    }
}

// MARK: - BuilderAction

public protocol BuilderAction: Sendable {
    func apply(to document: inout BuilderDocument)
    func undo(on document: inout BuilderDocument)
}

// MARK: - AddComponentAction

public struct AddComponentAction: BuilderAction {
    public let component: SPPUIComponent
    public let parentID: UUID?

    public init(component: SPPUIComponent, parentID: UUID? = nil) {
        self.component = component
        self.parentID = parentID
    }

    public func apply(to document: inout BuilderDocument) {
        if let parentID {
            document.insertComponent(component, intoParentWithID: parentID)
        } else {
            document.rootComponents.append(component)
        }
    }

    public func undo(on document: inout BuilderDocument) {
        document.removeComponent(id: component.id)
    }
}

// MARK: - RemoveComponentAction

public struct RemoveComponentAction: BuilderAction {
    public let componentID: UUID
    private var removed: SPPUIComponent?

    public init(componentID: UUID) {
        self.componentID = componentID
    }

    public func apply(to document: inout BuilderDocument) {
        // Capture the component before removal so undo can re-insert it.
        var mutableSelf = self
        mutableSelf.removed = document.component(id: componentID)
        document.removeComponent(id: componentID)
        // Swift value-type mutation: the caller's copy of the action won't carry
        // `removed`, but BuilderCommandHistory stores the action after apply so
        // we need a workaround — see BuilderCommandHistory.execute for details.
        _ = mutableSelf  // retained via history stack in execute()
    }

    public func undo(on document: inout BuilderDocument) {
        guard let component = removed else { return }
        document.rootComponents.append(component)
    }

    // Internal helper used by BuilderCommandHistory to capture the removed value.
    internal func capturing(from document: BuilderDocument) -> RemoveComponentAction {
        var copy = self
        copy.removed = document.component(id: componentID)
        return copy
    }
}

// MARK: - MoveComponentAction

public struct MoveComponentAction: BuilderAction {
    public let componentID: UUID
    public let newFrame: SPPRect
    public let oldFrame: SPPRect

    public init(componentID: UUID, newFrame: SPPRect, oldFrame: SPPRect) {
        self.componentID = componentID
        self.newFrame = newFrame
        self.oldFrame = oldFrame
    }

    public func apply(to document: inout BuilderDocument) {
        document.updateFrame(newFrame, forComponentWithID: componentID)
    }

    public func undo(on document: inout BuilderDocument) {
        document.updateFrame(oldFrame, forComponentWithID: componentID)
    }
}

// MARK: - UpdateStyleAction

public struct UpdateStyleAction: BuilderAction {
    public let componentID: UUID
    public let newStyle: ComponentStyle
    public let oldStyle: ComponentStyle

    public init(componentID: UUID, newStyle: ComponentStyle, oldStyle: ComponentStyle) {
        self.componentID = componentID
        self.newStyle = newStyle
        self.oldStyle = oldStyle
    }

    public func apply(to document: inout BuilderDocument) {
        document.updateStyle(newStyle, forComponentWithID: componentID)
    }

    public func undo(on document: inout BuilderDocument) {
        document.updateStyle(oldStyle, forComponentWithID: componentID)
    }
}

// MARK: - BuilderCommandHistory

/// Manages undo/redo history for a BuilderDocument. Not thread-safe — call on the main thread.
public final class BuilderCommandHistory {
    private var undoStack: [any BuilderAction] = []
    private var redoStack: [any BuilderAction] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Executes `action`, applies it to `document`, and records it for undo.
    public func execute(_ action: any BuilderAction, on document: inout BuilderDocument) {
        // Special-case RemoveComponentAction so that the captured snapshot is stored.
        if let removeAction = action as? RemoveComponentAction {
            let capturing = removeAction.capturing(from: document)
            capturing.apply(to: &document)
            undoStack.append(capturing)
        } else {
            action.apply(to: &document)
            undoStack.append(action)
        }
        redoStack.removeAll()
    }

    /// Undoes the most recent action.
    public func undo(on document: inout BuilderDocument) {
        guard let action = undoStack.popLast() else { return }
        action.undo(on: &document)
        redoStack.append(action)
    }

    /// Redoes the most recently undone action.
    public func redo(on document: inout BuilderDocument) {
        guard let action = redoStack.popLast() else { return }
        action.apply(to: &document)
        undoStack.append(action)
    }

    /// Clears all undo and redo history.
    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

// MARK: - BuilderDocument internal mutation helpers

extension BuilderDocument {

    /// Recursively inserts `component` as a child of the component whose id is `parentID`.
    mutating func insertComponent(_ component: SPPUIComponent, intoParentWithID parentID: UUID) {
        for index in rootComponents.indices {
            if rootComponents[index].insertChild(component, intoParentWithID: parentID) { return }
        }
    }

    /// Recursively removes the component whose id matches from the document tree.
    mutating func removeComponent(id: UUID) {
        rootComponents.removeAll { $0.id == id }
        for index in rootComponents.indices {
            rootComponents[index].removeChild(id: id)
        }
    }

    /// Recursively updates the frame of the component whose id matches.
    mutating func updateFrame(_ frame: SPPRect, forComponentWithID id: UUID) {
        for index in rootComponents.indices {
            rootComponents[index].updateFrame(frame, forID: id)
        }
    }

    /// Recursively updates the style of the component whose id matches.
    mutating func updateStyle(_ style: ComponentStyle, forComponentWithID id: UUID) {
        for index in rootComponents.indices {
            rootComponents[index].updateStyle(style, forID: id)
        }
    }
}

// MARK: - SPPUIComponent internal mutation helpers

extension SPPUIComponent {

    /// Attempts to insert `child` into the subtree rooted at this component.
    /// Returns `true` if the insertion was performed.
    @discardableResult
    mutating func insertChild(_ child: SPPUIComponent, intoParentWithID parentID: UUID) -> Bool {
        if id == parentID {
            children.append(child)
            return true
        }
        for index in children.indices {
            if children[index].insertChild(child, intoParentWithID: parentID) { return true }
        }
        return false
    }

    /// Removes the direct child whose id matches, and recurses into remaining children.
    mutating func removeChild(id: UUID) {
        children.removeAll { $0.id == id }
        for index in children.indices {
            children[index].removeChild(id: id)
        }
    }

    /// Updates the frame of this node or a descendant whose id matches.
    mutating func updateFrame(_ frame: SPPRect, forID targetID: UUID) {
        if id == targetID { self.frame = frame; return }
        for index in children.indices {
            children[index].updateFrame(frame, forID: targetID)
        }
    }

    /// Updates the style of this node or a descendant whose id matches.
    mutating func updateStyle(_ style: ComponentStyle, forID targetID: UUID) {
        if id == targetID { self.style = style; return }
        for index in children.indices {
            children[index].updateStyle(style, forID: targetID)
        }
    }
}
