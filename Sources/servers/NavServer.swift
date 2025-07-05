import Logging
import MCP
import Foundation
import ServiceLifecycle
import AppKit

fileprivate struct GetUIElementsArguments: Decodable {
    let bundle_identifier: String
}

fileprivate struct ClickElementByIdArguments: Decodable {
    let bundle_identifier: String
    let element_id: String
}

fileprivate struct UpdateUIElementTreeArguments: Decodable {
    let bundle_identifier: String
    let element_id: String
}

struct NavServer: Service {
    private let server: Server
    private let transport: Transport
    private let logger: Logger

    // Decoders
    private let jsondecoder = JSONDecoder()
    private let jsonencoder = JSONEncoder()

    init(server: Server, transport: Transport, logger: Logger) {
        self.logger = logger
        self.server = server
        self.transport = transport
    }

    public func setup() async {
        let tools: [Tool] = [
            Tool(
                name: "get_ui_elements",
                description: "Get UI elements for an application in a tree structure with limited depth (2-3 levels). Automatically opens the application if not running, brings it to focus, and fills ui_state_tree with focused window, menu bar, and elements. Returns tree with only 3 fields: element_id, description, children. Use this function to get an overview of the application state - if you need more details about specific elements, use update_ui_element_tree.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "bundle_identifier": .object([
                            "type": "string",
                            "description": "Bundle identifier of application (e.g., com.apple.safari for Safari)"
                        ])
                    ]),
                    "required": .array(["bundle_identifier"])
                ])
            ),
            
            Tool(
                name: "click_element_by_id",
                description: "Click a UI element by its ID using direct AXUIElement reference for maximum performance and reliability.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "bundle_identifier": .object([
                            "type": "string",
                            "description": "Bundle identifier of application"
                        ]),
                        "element_id": .object([
                            "type": "string",
                            "description": "Element ID obtained from get_ui_elements"
                        ])
                    ]),
                    "required": .array(["bundle_identifier", "element_id"])
                ])
            ),
            
            Tool(
                name: "update_ui_element_tree",
                description: "Update and return the UI element tree for a specific element by its ID. Call this function if you need more information about the children of a particular ui element. For example if from the available ui element id you feel like the final element must be under a certain element, call this function to get the updated tree.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "bundle_identifier": .object([
                            "type": "string",
                            "description": "Bundle identifier of application"
                        ]),
                        "element_id": .object([
                            "type": "string",
                            "description": "Element ID to update and return tree from (obtained from get_ui_elements)"
                        ])
                    ]),
                    "required": .array(["bundle_identifier", "element_id"])
                ])
            )
        ]
        
        await server.withMethodHandler(ListTools.self) { _ in
            logger.info("Listing navigation tools")
            return ListTools.Result(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let tool_name: String = params.name
            logger.info("Got tool call for: \(tool_name)")

            switch tool_name {
            case "get_ui_elements":
                logger.info("Getting UI elements in tree structure")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for get_ui_elements")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let args = try JSONDecoder().decode(GetUIElementsArguments.self, from: data)
                    
                    logger.info("Tree-based UI discovery for: \(args.bundle_identifier)")
                    let elements = try await StateManager.shared.getUIElements(
                        applicationIdentifier: args.bundle_identifier
                    )
                    
                    let elementsData = try jsonencoder.encode(elements)
                    guard let elementsString = String(data: elementsData, encoding: .utf8) else {
                        throw NudgeError.invalidRequest(message: "Failed to encode UI elements")
                    }
                    
                    logger.info("Successfully retrieved \(elements.count) UI elements for \(args.bundle_identifier) with limited depth")
                    return CallTool.Result(content: [.text(elementsString)], isError: false)
                } catch {
                    logger.error("Error in get_ui_elements: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
                }

            case "click_element_by_id":
                logger.info("Clicking element with direct AXUIElement reference")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for click_element_by_id")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let args = try JSONDecoder().decode(ClickElementByIdArguments.self, from: data)
                    
                    logger.info("Direct click for element \(args.element_id) in \(args.bundle_identifier)")

                    try await StateManager.shared.clickElementById(
                        applicationIdentifier: args.bundle_identifier,
                        elementId: args.element_id
                    )
                    
                    logger.info("Successfully clicked element \(args.element_id)")
                    return CallTool.Result(content: [.text("Successfully clicked element '\(args.element_id)'. UI has been updated - you can call get_ui_elements again to see the new state.")], isError: false)
                } catch {
                    logger.error("Error in click_element_by_id: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
                }

            case "update_ui_element_tree":
                logger.info("Updating UI element tree")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for update_ui_element_tree")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let args = try JSONDecoder().decode(UpdateUIElementTreeArguments.self, from: data)
                    
                    logger.info("Updating tree for element \(args.element_id) in \(args.bundle_identifier)")
                    let updatedTree = try await StateManager.shared.updateUIElementTree(
                        applicationIdentifier: args.bundle_identifier,
                        elementId: args.element_id
                    )
                    
                    let updatedTreeData = try jsonencoder.encode(updatedTree)
                    guard let updatedTreeString = String(data: updatedTreeData, encoding: .utf8) else {
                        throw NudgeError.invalidRequest(message: "Failed to encode updated UI element tree")
                    }
                    
                    logger.info("Successfully updated UI element tree for \(args.element_id)")
                    return CallTool.Result(content: [.text(updatedTreeString)], isError: false)
                } catch {
                    logger.error("Error in update_ui_element_tree: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
                }

            default:
                logger.warning("Unknown tool name: \(tool_name)")
                return CallTool.Result(content: [.text("Unknown tool: \(tool_name)")], isError: true)
            }
        }
    }

    func run() async throws {
        print("🚀 Starting Simplified Nudge Navigation Server...")
        print("📊 Server Capabilities:")
        print("   • Auto-opening applications")
        print("   • Tree-based UI structure")
        print("   • Direct AXUIElement performance")
        print("   • Simplified 3-field response")
        print("   • Focused window + menu bar scanning")
        print("   • Streamlined architecture")
        print("   • Ready for use!")
        
        try await server.start(transport: self.transport)
        try await Task.sleep(for: .seconds(60*60*24*365))
        print("⏰ Server timeout reached")
    }
}
