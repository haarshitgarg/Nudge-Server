import Foundation
import MCP

public struct ToolParameters {
    public var name: String
    public var type: String
    public var description: String
    public var required: Bool

    public init(name: String, type: String, description: String, required: Bool) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }
}

public actor NudgeLibrary {
    static public let shared: NudgeLibrary = NudgeLibrary()
    var tools: [Tool] = []
    private init() {}

    public func addTool(name: String, description: String, parameters: [ToolParameters]?) {
        var params: [String: Value] = [:]
        var required: [Value] = []
        if let parameters = parameters {
            for para in parameters {
                params[para.name] = .object([
                    "type" : .string(para.type),
                    "description": .string(para.description)
                ])

                if para.required {
                    required.append(.string(para.name))
                }
            }
        }

        let tool = Tool(
            name: "\(name)",
            description: "\(description)",
            inputSchema: .object([
                "type": "object",
                "properties": .object(params),
                "required": .array(required)
            ])
        )

        self.tools.append(tool)
    }

    public func getNavTools() -> [Tool] {
        var curr_tools = NavServerTools.getAllTools()
        curr_tools.append(contentsOf: self.tools)
        return curr_tools
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
