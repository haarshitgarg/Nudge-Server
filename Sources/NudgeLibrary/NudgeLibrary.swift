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

    /// Click a UI element by its ID
    public func clickElement(bundleIdentifier: String, elementId: String) async throws {
        try await StateManager.shared.clickElementById(applicationIdentifier: bundleIdentifier, elementId: elementId)
    }

    /// Update UI element tree for a specific element
    public func updateUIElementTree(bundleIdentifier: String, elementId: String) async throws -> [UIElementInfo] {
        return try await StateManager.shared.updateUIElementTree(applicationIdentifier: bundleIdentifier, elementId: elementId)
    }

}
