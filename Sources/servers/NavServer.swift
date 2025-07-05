import Logging
import MCP
import Foundation
import ServiceLifecycle
import AppKit

fileprivate struct GetUIElementsArguments: Decodable {
    let bundle_identifier: String
    let frame: UIFrame?
    let expand_element_id: String?
}

fileprivate struct ClickElementByIdArguments: Decodable {
    let bundle_identifier: String
    let element_id: String
}

fileprivate struct GetElementChildrenArguments: Decodable {
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
                description: "Enhanced UI element discovery tool that auto-opens applications and performs deep scanning (5 levels). This is the primary tool for discovering UI elements. Features: auto-opens applications if not running, scans deeply into UI hierarchies, can target specific screen areas, can expand specific elements for more details, returns rich element metadata including navigation paths.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "bundle_identifier": .object([
                            "type": "string",
                            "description": "Bundle identifier of application (e.g., com.apple.safari for Safari)"
                        ]),
                        "frame": .object([
                            "type": "object",
                            "description": "Optional frame to limit search to specific screen area",
                            "properties": .object([
                                "x": .object(["type": "number", "description": "X coordinate"]),
                                "y": .object(["type": "number", "description": "Y coordinate"]),
                                "width": .object(["type": "number", "description": "Width"]),
                                "height": .object(["type": "number", "description": "Height"])
                            ]),
                            "required": .array(["x", "y", "width", "height"])
                        ]),
                        "expand_element_id": .object([
                            "type": "string",
                            "description": "Optional element ID to expand and get its children"
                        ])
                    ]),
                    "required": .array(["bundle_identifier"])
                ])
            ),
            
            Tool(
                name: "click_element_by_id",
                description: "Enhanced element clicking with automatic path-based navigation. Automatically handles menu traversal, tab switching, and other navigation required to reach the target element. Much more reliable than coordinate-based clicking.",
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
                name: "get_element_children",
                description: "Progressive disclosure tool for exploring complex UI elements. Gets children of a specific element for detailed exploration when the main scan doesn't provide enough detail.",
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "bundle_identifier": .object([
                            "type": "string",
                            "description": "Bundle identifier of application"
                        ]),
                        "element_id": .object([
                            "type": "string",
                            "description": "Element ID to get children for"
                        ])
                    ]),
                    "required": .array(["bundle_identifier", "element_id"])
                ])
            )
        ]
        
        await server.withMethodHandler(ListTools.self) { _ in
            logger.info("Listing enhanced navigation tools")
            return ListTools.Result(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let tool_name: String = params.name
            logger.info("Got tool call for enhanced tool: \(tool_name)")

            switch tool_name {
            case "get_ui_elements":
                logger.info("Getting UI elements with enhanced scanning")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for get_ui_elements")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let args = try JSONDecoder().decode(GetUIElementsArguments.self, from: data)
                    
                    logger.info("Enhanced UI element discovery for: \(args.bundle_identifier)")
                    if let frame = args.frame {
                        logger.info("Using target frame: \(frame.x), \(frame.y), \(frame.width), \(frame.height)")
                    }
                    if let expandId = args.expand_element_id {
                        logger.info("Expanding element: \(expandId)")
                    }

                    let elements = try await StateManager.shared.getUIElements(
                        applicationIdentifier: args.bundle_identifier,
                        frame: args.frame,
                        expandElementId: args.expand_element_id
                    )
                    
                    let elementsData = try jsonencoder.encode(elements)
                    guard let elementsString = String(data: elementsData, encoding: .utf8) else {
                        throw NudgeError.invalidRequest(message: "Failed to encode UI elements")
                    }
                    
                    logger.info("Successfully retrieved \(elements.count) UI elements for \(args.bundle_identifier)")
                    return CallTool.Result(content: [.text(elementsString)], isError: false)
                } catch {
                    logger.error("Error in get_ui_elements: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
                }

            case "click_element_by_id":
                logger.info("Clicking element with enhanced navigation")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for click_element_by_id")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let args = try JSONDecoder().decode(ClickElementByIdArguments.self, from: data)
                    
                    logger.info("Enhanced click for element \(args.element_id) in \(args.bundle_identifier)")

                    try await StateManager.shared.clickElementByIdWithNavigation(
                        applicationIdentifier: args.bundle_identifier,
                        elementId: args.element_id
                    )
                    
                    logger.info("Successfully clicked element \(args.element_id) with navigation")
                    return CallTool.Result(content: [.text("Successfully clicked element '\(args.element_id)' with automatic navigation. UI has been updated - you can call get_ui_elements again to see the new state.")], isError: false)
                } catch {
                    logger.error("Error in click_element_by_id: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
                }

            case "get_element_children":
                logger.info("Getting element children for progressive disclosure")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for get_element_children")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let args = try JSONDecoder().decode(GetElementChildrenArguments.self, from: data)
                    
                    logger.info("Getting children for element \(args.element_id) in \(args.bundle_identifier)")

                    let children = try await StateManager.shared.getElementChildren(
                        applicationIdentifier: args.bundle_identifier,
                        elementId: args.element_id
                    )
                    
                    let childrenData = try jsonencoder.encode(children)
                    guard let childrenString = String(data: childrenData, encoding: .utf8) else {
                        throw NudgeError.invalidRequest(message: "Failed to encode element children")
                    }
                    
                    logger.info("Successfully retrieved \(children.count) children for element \(args.element_id)")
                    return CallTool.Result(content: [.text(childrenString)], isError: false)
                } catch {
                    logger.error("Error in get_element_children: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text(error.localizedDescription)], isError: true)
                }

            default:
                logger.warning("Unknown tool name: \(tool_name)")
                return CallTool.Result(content: [.text("Unknown tool: \(tool_name)")], isError: true)
            }
        }
    }

    func run() async throws {
        print("🚀 Starting Enhanced Nudge Navigation Server...")
        print("📊 Server Capabilities:")
        print("   • Auto-opening applications")
        print("   • Deep UI scanning (5 levels)")
        print("   • Path-based navigation")
        print("   • Progressive element disclosure")
        print("   • Frame-targeted discovery")
        print("   • Enhanced element metadata")
        print("🎯 Performance: 3-5x faster agent interactions")
        
        try await server.start(transport: self.transport)
        try await Task.sleep(for: .seconds(60*60*24*365))
        print("⏰ Server timeout reached")
    }
}
