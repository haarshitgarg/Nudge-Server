import Logging
import MCP
import Foundation
import ServiceLifecycle

// A service can be implemented by a struct, class or actor. For this example we are using a struct.
@main
struct Application {
    static let logger = Logger(label: "Application")
    
    static func main() async throws {
        let server = Server(
            name: "Test Server", 
            version: "1.0.0", 
            capabilities: .init( 
                tools: .init(listChanged: true)
            )
        )
        let transport = StdioTransport()
        let service = TestServer(server:server, transport: transport, logger: logger)
        await service.setup()
        
        let serviceGroup = ServiceGroup(
            services: [service],
            gracefulShutdownSignals: [.sigterm],
            logger: logger
        )
        
        try await serviceGroup.run()
    }
}
