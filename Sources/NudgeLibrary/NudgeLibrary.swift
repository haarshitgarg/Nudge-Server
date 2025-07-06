import Foundation
import MCP

public actor NudgeLibrary {
    static public let shared: NudgeLibrary = NudgeLibrary()
    private init() {}

    public func getNavTools() -> [Tool] {
        return NavServerTools.getAllTools()
    }

    public func getUIElements(bundleIdentifier: String) async throws -> [UIElementInfo] {
        return try await StateManager.shared.getUIElements(applicationIdentifier: bundleIdentifier)
    }

    public func getUIElements(arguments: [String: Value]) async throws -> [UIElementInfo] {
        guard let bundleIdentifier = arguments["bundle_identifier"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a bundle_identifier")
        }
        return try await StateManager.shared.getUIElements(applicationIdentifier: bundleIdentifier)
    }

    /// Click a UI element by its ID
    public func clickElement(bundleIdentifier: String, elementId: String) async throws {
        try await StateManager.shared.clickElementById(applicationIdentifier: bundleIdentifier, elementId: elementId)
    }

    public func clickElement(arguments: [String: Value]) async throws {
        guard let bundleIdentifier = arguments["bundle_identifier"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a bundle_identifier")
        }
        guard let elementId = arguments["element_id"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a element_id")
        }
        try await StateManager.shared.clickElementById(applicationIdentifier: bundleIdentifier, elementId: elementId)
    }

    /// Update UI element tree for a specific element
    public func updateUIElementTree(bundleIdentifier: String, elementId: String) async throws -> [UIElementInfo] {
        return try await StateManager.shared.updateUIElementTree(applicationIdentifier: bundleIdentifier, elementId: elementId)
    }

    public func updateUIElementTree(arguments: [String: Value]) async throws -> [UIElementInfo] {
        guard let bundleIdentifier = arguments["bundle_identifier"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a bundle_identifier")
        }
        guard let elementId = arguments["element_id"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a element_id")
        }
        return try await StateManager.shared.updateUIElementTree(applicationIdentifier: bundleIdentifier, elementId: elementId)
    }

}
