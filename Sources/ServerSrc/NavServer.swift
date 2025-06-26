import Logging
import MCP 
import Foundation
import ServiceLifecycle

struct NavServer: Service {
    private let server: Server
    private let transport: Transport
    private let logger: Logger

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
                    "name_of_application": .object(["type": "string", "description": "Name of the application to open"])
                ]),
                "required" : .array(["name_of_application"])
            ])
        )]
        await server.withMethodHandler(ListTools.self) { _ in
            logger.info("Listing tools")
            return ListTools.Result(tools:tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let tool_name: String = params.name
            logger.info("Got tool call for tool name \(tool_name)")
            switch tool_name {
            case "open_application":
                logger.info("Opening application...")
                break
            default:
                break
            }
            return CallTool.Result(content: [.text("Application is now open")], isError: false)
        }
    }

    
    func run() async throws {
        print("Starting the server...")
        try await server.start(transport:self.transport)
        try await Task.sleep(for: .seconds(60*60*24*365))
        print("Stoppint the serveer after timeout")
    }

    // MARK: Application related stuff
}
