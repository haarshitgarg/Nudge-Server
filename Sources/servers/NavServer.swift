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

fileprivate struct ClickUIElement: Decodable {
    let bundle_identifier: String
    let ui_element_id: String
}

fileprivate struct ClickAtCoordinate: Decodable {
    let bundle_identifier: String
    let x: Double
    let y: Double
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
                    description: "This tool get the current state of the application. It returns a UI tree in json format of the top level of application that the llm can use to formulate a plan of action",
                    inputSchema: .object([
                        "type":"object",
                        "properties": .object([
                            "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"])
                        ]),
                        "required": .array(["bundle_identifier"])
                    ])
                ),

                Tool(
                    name: "click_the_ui_element", 
                    description: "This tool will click the UI element. It takes input as ui_element_id. Returns if the click was successful or an appropriate error message", 
                    inputSchema: .object([
                        "type": "object",
                        "properties": .object([
                            "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"]),
                            "ui_element_id": .object(["type": "string", "description": "The id of the UI element to be clicked"])
                        ]),
                        "required": .array(["bundle_identifier", "ui_element_id"])
                    ])
                ),

                // Tool(
                //     name: "get_ui_elements", 
                //     description: "This tool will get the UI elements of a window for an application. It takes input as the bundle_identifier, and returns an array of availale ui elements. Eg input: com.apple.safari, output: [{title: dummy_title, ui_element_id: dummy_id, ...}, {}, ...]", 
                //     inputSchema: .object([
                //         "type": "object",
                //         "properties": .object([
                //             "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"]),
                //         ]),
                //         "required": .array(["bundle_identifier"])
                //     ])
                // ),

                Tool(
                    name: "get_ui_elements_in_frame", 
                    description: "This tool gets UI elements within a specified rectangular frame in the frontmost window of an application. Useful for agents to explore specific areas of the UI.", 
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
                    description: "This tool clicks at a specific coordinate within an application window. Useful when you know the exact position but not the element identifier.", 
                    inputSchema: .object([
                        "type": "object",
                        "properties": .object([
                            "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"]),
                            "x": .object(["type": "number", "description": "X coordinate to click at"]),
                            "y": .object(["type": "number", "description": "Y coordinate to click at"])
                        ]),
                        "required": .array(["bundle_identifier", "x", "y"])
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
            case "get_ui_elements":
                return CallTool.Result(content: [.text("[{\"ui_element_id\": \"id_1\", \"element_description\":\"Log in button\"}, {\"ui_element_id\": \"id_2\", \"element_description\":\"Log in button\"}]")], isError: false)
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
            case "click_the_ui_element":
                logger.info("Attempting to click UI element")
                guard let arguments = params.arguments else {
                    logger.error("Missing arguments for click_the_ui_element.")
                    return CallTool.Result(content: [.text("Missing arguments")], isError: true)
                }

                do {
                    let data = try JSONEncoder().encode(arguments)
                    let clickArgs = try JSONDecoder().decode(ClickUIElement.self, from: data)
                    let bundleIdentifier = clickArgs.bundle_identifier
                    let elementId = clickArgs.ui_element_id
                    
                    logger.info("Attempting to click element with ID '\(elementId)' in application '\(bundleIdentifier)'")

                    try await StateManager.shared.clickUIElement(applicationIdentifier: bundleIdentifier, elementIdentifier: elementId)
                    
                    logger.info("Successfully clicked UI element with ID '\(elementId)'")
                    return CallTool.Result(content: [.text("Successfully clicked UI element with ID '\(elementId)'")], isError: false)
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
                    return CallTool.Result(content: [.text("Successfully clicked at coordinate \(coordinate)")], isError: false)
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
        print("Stoppint the serveer after timeout")
    }

}
