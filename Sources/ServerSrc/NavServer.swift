import Logging
import MCP
import Foundation
import ServiceLifecycle
import AppKit

fileprivate struct OpenApplicationArguments: Decodable {
    let bundle_identifier: String
}

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
                    "bundle_identifier": .object(["type": "string", "description": "Bundle identifier of application. For example: com.apple.safari for Safari or com.apple.dt.Xcode for Xcode"])
                ]),
                "required" : .array(["bundle_identifier"])
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

                    if await self.openApplication(bundleIdentifier: bundleIdentifier) {
                        logger.info("Successfully launched application \(bundleIdentifier).")
                        return CallTool.Result(content: [.text("Application \(bundleIdentifier) is now open")], isError: false)
                    } else {
                        logger.error("Failed to launch application \(bundleIdentifier).")
                        return CallTool.Result(content: [.text("Bundle identifier is incorrect")], isError: true)
                    }
                } catch {
                    logger.error("Failed to decode arguments for open_application: \(error)")
                    return CallTool.Result(content: [.text("Invalid arguments format")], isError: true)
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

    // MARK: Application related stuff
    private func openApplication(bundleIdentifier: String) async -> Bool {
        logger.info("Checking accessibility permissions.")
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permissions are not granted. Please grant them in System Settings.")
            return false
        }

        logger.info("Permissions granted. Attempting to launch \(bundleIdentifier).")
        
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            logger.error("Could not find application with bundle ID: \(bundleIdentifier).")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()

        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            logger.info("Successfully initiated launch for application: \(bundleIdentifier)")
            return true
        } catch {
            logger.error("Failed to launch application \(bundleIdentifier) with error: \(error)")
            return false
        }
    }
}
