import Logging
import MCP
import Foundation
import ServiceLifecycle
import AppKit

fileprivate struct OpenApplicationArguments: Decodable {
    let bundle_identifier: String
}

fileprivate struct GetStateOfApplication: Decodable {
    let bundle_identifier: String
}

fileprivate struct GetUIElementsInFrame: Decodable {
    let bundle_identifier: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

fileprivate struct ClickAtCoordinate: Decodable {
    let bundle_identifier: String
    let x: Double
    let y: Double
}

fileprivate struct ClickElementById: Decodable {
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
                name: "open_application",
                description: "This tool opens application in a Mac PC",
                inputSchema: .object([
                    "type":"object",
                    "properties":.object([
                        "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"])
                    ]),
                    "required" : .array(["bundle_identifier"])
                ])),

                Tool(
                    name: "get_state_of_application", 
                    description: "This tool gets the current state of the application. It returns a UI tree in json format of the top level of application that the llm can use to formulate a plan of action. Each UI element has a unique ID that can be used with click_element_by_id.",
                    inputSchema: .object([
                        "type":"object",
                        "properties": .object([
                            "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"])
                        ]),
                        "required": .array(["bundle_identifier"])
                    ])
                ),

                Tool(
                    name: "get_ui_elements_in_frame", 
                    description: "This tool gets actionable UI elements within a specified rectangular frame in the frontmost window of an application. Each element has a unique ID that can be used with click_element_by_id. This is the preferred way to discover UI elements for interaction.", 
                    inputSchema: .object([
                        "type": "object",
                        "properties": .object([
                            "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"]),
                            "x": .object(["type": "number", "description": "X coordinate of the top-left corner of the frame"]),
                            "y": .object(["type": "number", "description": "Y coordinate of the top-left corner of the frame"]),
                            "width": .object(["type": "number", "description": "Width of the frame"]),
                            "height": .object(["type": "number", "description": "Height of the frame"])
                        ]),
                        "required": .array(["bundle_identifier", "x", "y", "width", "height"])
                    ])
                ),

                Tool(
                    name: "click_at_coordinate", 
                    description: "This tool clicks at a specific coordinate within an application window. Useful when you know the exact position of the element you want to click on. Make sure you give location such that it is not at the borders of the element. For example if the frame has x=100, y=100, width=100, height=100, then you should give x=150, y=150. This is because the click will be at the center of the element.", 
                    inputSchema: .object([
                        "type": "object",
                        "properties": .object([
                            "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"]),
                            "x": .object(["type": "number", "description": "X coordinate to click at"]),
                            "y": .object(["type": "number", "description": "Y coordinate to click at"])
                        ]),
                        "required": .array(["bundle_identifier", "x", "y"])
                    ])
                ),

                Tool(
                    name: "click_element_by_id", 
                    description: "This tool clicks a UI element by its unique ID using the robust accessibility API (AXUIElementPerformAction). This is the most reliable way to click elements as it directly interacts with the UI element through the system's accessibility framework. The element IDs are obtained from get_ui_elements_in_frame or get_state_of_application tools.", 
                    inputSchema: .object([
                        "type": "object",
                        "properties": .object([
                            "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"]),
                            "element_id": .object(["type": "string", "description": "Unique ID of the element to click, obtained from get_ui_elements_in_frame or get_state_of_application"])
                        ]),
                        "required": .array(["bundle_identifier", "element_id"])
                    ])
                )
        ]
        await server.withMethodHandler(ListTools.self) { _ in
            logger.info("Listing tools")
            return ListTools.Result(tools:tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let tool_name: String = params.name
            logger.info("Got tool call for tool name \(tool_name)")

            switch tool_name {
            case "open_application":
                logger.info("Attempting to open application.")

                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for open_application.")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let appArgs = try JSONDecoder().decode(OpenApplicationArguments.self, from: data)
                    let bundleIdentifier = appArgs.bundle_identifier
                    
                    logger.info("Extracted bundle identifier: \(bundleIdentifier)")

                    try await openApplication(bundleIdentifier: bundleIdentifier) 
                    logger.info("Opened application: \(bundleIdentifier)")
                    return CallTool.Result(content: [.text("Application \(bundleIdentifier) is now open")], isError: false)
                } catch {
                    logger.error("Returned with error: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text("\(error.localizedDescription)")], isError: true)
                }
            case "get_state_of_application":
                logger.info("Attempting to get the state of application")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for get_state_of_application.")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let appArgs = try JSONDecoder().decode(GetStateOfApplication.self, from: data)
                    let bundleIdentifier = appArgs.bundle_identifier
                    
                    logger.info("Extracted bundle identifier: \(bundleIdentifier)")

                    let stateTree = try await StateManager.shared.getUIStateTree(applicationIdentifier: bundleIdentifier)
                    let stateTreeData = try jsonencoder.encode(stateTree)
                    guard let stateTreeString = String(data: stateTreeData, encoding: .utf8) else {
                        throw NudgeError.uiStateTreeNotFound(applicationIdentifier: bundleIdentifier)
                    }
                    logger.info("Got state of application: \(bundleIdentifier)")
                    return CallTool.Result(content: [.text("\(stateTreeString)")], isError: false)
                } catch {
                    logger.error("Returned with error: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text("\(error.localizedDescription)")], isError: true)
                }
            case "get_ui_elements_in_frame":
                logger.info("Attempting to get UI elements in frame")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for get_ui_elements_in_frame.")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let frameArgs = try JSONDecoder().decode(GetUIElementsInFrame.self, from: data)
                    let bundleIdentifier = frameArgs.bundle_identifier
                    let frame = CGRect(x: frameArgs.x, y: frameArgs.y, width: frameArgs.width, height: frameArgs.height)
                    
                    logger.info("Extracted frame parameters: x=\(frameArgs.x), y=\(frameArgs.y), width=\(frameArgs.width), height=\(frameArgs.height) for \(bundleIdentifier)")

                    let uiElements = try await StateManager.shared.getUIElementsInFrame(applicationIdentifier: bundleIdentifier, frame: frame)
                    let elementsData = try jsonencoder.encode(uiElements)
                    guard let elementsString = String(data: elementsData, encoding: .utf8) else {
                        throw NudgeError.invalidRequest(message: "Failed to encode UI elements to JSON")
                    }
                    logger.info("Got \(uiElements.count) UI elements in frame for \(bundleIdentifier)")
                    return CallTool.Result(content: [.text(elementsString)], isError: false)
                } catch {
                    logger.error("Returned with error: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text("\(error.localizedDescription)")], isError: true)
                }
            case "click_at_coordinate":
                logger.info("Attempting to click at coordinate")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for click_at_coordinate.")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let coordinateArgs = try JSONDecoder().decode(ClickAtCoordinate.self, from: data)
                    let bundleIdentifier = coordinateArgs.bundle_identifier
                    let coordinate = CGPoint(x: coordinateArgs.x, y: coordinateArgs.y)
                    
                    logger.info("Attempting to click at coordinate \(coordinate) in application \(bundleIdentifier)")

                    try await StateManager.shared.clickAtCoordinate(applicationIdentifier: bundleIdentifier, coordinate: coordinate)
                    
                    logger.info("Successfully clicked at coordinate \(coordinate)")
                    return CallTool.Result(content: [.text("Successfully clicked at coordinate \(coordinate). LLM will need to get the the current ui elements in frame to see the effect of the click.")], isError: false)
                } catch {
                    logger.error("Returned with error: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text("\(error.localizedDescription)")], isError: true)
                }
            
            case "click_element_by_id":
                logger.info("Attempting to click element by ID")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for click_element_by_id.")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let clickArgs = try JSONDecoder().decode(ClickElementById.self, from: data)
                    let bundleIdentifier = clickArgs.bundle_identifier
                    let elementId = clickArgs.element_id
                    
                    logger.info("Attempting to click element with ID \(elementId) in application \(bundleIdentifier)")

                    try await StateManager.shared.clickElementById(applicationIdentifier: bundleIdentifier, elementId: elementId)
                    
                    logger.info("Successfully clicked element with ID \(elementId)")
                    return CallTool.Result(content: [.text("Successfully clicked element with ID \(elementId). LLM will need to get the actionable elements again to see the effect of the click.")], isError: false)
                } catch {
                    logger.error("Returned with error: \(error.localizedDescription)")
                    return CallTool.Result(content: [.text("\(error.localizedDescription)")], isError: true)
                }
            
            default:
                logger.warning("Unknown tool name: \(tool_name)")
                return CallTool.Result(content: [.text("Unknown tool")], isError: true)
            }
        }
    }

    
    func run() async throws {
        print("Starting the server...")
        try await server.start(transport:self.transport)
        try await Task.sleep(for: .seconds(60*60*24*365))
        print("Stopping the server after timeout")
    }

}
