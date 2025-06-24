import Logging
import MCP 
import Foundation
import ServiceLifecycle

struct TestServer: Service {
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
            name: "example_tool", 
            description: "This is just an example tool", 
            inputSchema: .object([
                "type":"object",
                "properties":.object([:])
            ])
        )]
        await server.withMethodHandler(ListTools.self) { _ in
            logger.info("Listing tools")
            return ListTools.Result(tools:tools)
        }

        await server.withMethodHandler(CallTool.self) { _ in
            return CallTool.Result(content: [.text("Sample call for the tools")], isError: false)
        }
    }

    
    func run() async throws {
        print("Starting the server...")
        try await server.start(transport:self.transport)
        try await Task.sleep(for: .seconds(60*60*24*365))
        print("Stoppint the serveer after timeout")
    }
}
