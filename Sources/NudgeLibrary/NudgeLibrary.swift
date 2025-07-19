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
    public func clickElement(bundleIdentifier: String, elementId: String) async throws -> click_response {
        return try await StateManager.shared.clickElementById(applicationIdentifier: bundleIdentifier, elementId: elementId)
    }

    public func clickElement(arguments: [String: Value]) async throws -> click_response {
        guard let bundleIdentifier = arguments["bundle_identifier"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a bundle_identifier")
        }
        guard let elementId = arguments["element_id"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a element_id")
        }
        return try await StateManager.shared.clickElementById(applicationIdentifier: bundleIdentifier, elementId: elementId)
    }

    /// Set text in a UI element by its ID
    public func setTextInElement(bundleIdentifier: String, elementId: String, text: String) async throws -> text_input_response {
        return try await StateManager.shared.setTextInElement(applicationIdentifier: bundleIdentifier, elementId: elementId, text: text)
    }

    public func setTextInElement(arguments: [String: Value]) async throws -> text_input_response {
        guard let bundleIdentifier = arguments["bundle_identifier"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a bundle_identifier")
        }
        guard let elementId = arguments["element_id"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a element_id")
        }
        guard let text = arguments["text"]?.stringValue else {
            throw NudgeError.invalidArgument(parameter: "Dict", value: "arguements", reason: "Does not have a text")
        }
        return try await StateManager.shared.setTextInElement(applicationIdentifier: bundleIdentifier, elementId: elementId, text: text)
    }

}
