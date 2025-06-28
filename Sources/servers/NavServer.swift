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
        let tools: [Tool] = [Tool(
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

            Tool(
                name: "get_ui_elements", 
                description: "This tool will get the UI elements of a window for an application. It takes input as the bundle_identifier, and returns an array of availale ui elements. Eg input: com.apple.safari, output: [{title: dummy_title, ui_element_id: dummy_id, ...}, {}, ...]", 
                inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"]),
                    ]),
                    "required": .array(["bundle_identifier"])
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
            case "click_the_ui_element":
                return CallTool.Result(content: [.text("Successfull")], isError: false)
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
