# Nudge Navigation Server

A Swift-based Model Context Protocol (MCP) server that provides tools for macOS UI automation and application interaction. This server enables AI agents to interact with macOS applications through accessibility APIs.

## What is MCP?

The Model Context Protocol (MCP) is an open standard that enables AI assistants to securely connect to external data sources and tools. This server implements MCP to provide macOS UI automation capabilities to AI agents.

## Requirements

- Swift 6.1 or later
- macOS 14.0 or later
- **Accessibility permissions** - The server requires accessibility permissions to interact with applications

## Tools Provided

This MCP server exposes the following tools:

### 1. `open_application`
Opens macOS applications using their bundle identifiers.

**Parameters:**
- `bundle_identifier` (string, required): Bundle identifier of the application (e.g., "com.apple.safari" for Safari, "com.apple.dt.Xcode" for Xcode)

**Returns:** Confirmation message when the application is successfully opened.

### 2. `get_state_of_application`
Retrieves the current UI state tree of an application in JSON format. This provides a hierarchical view of the application's UI elements that AI agents can use to understand the current state and plan actions.

**Parameters:**
- `bundle_identifier` (string, required): Bundle identifier of the application

**Returns:** JSON representation of the application's UI state tree containing elements, their properties, and hierarchical relationships.

### 3. `get_ui_elements_in_frame`
Gets UI elements within a specified rectangular frame in the frontmost window of an application. Useful for exploring specific areas of the UI.

**Parameters:**
- `bundle_identifier` (string, required): Bundle identifier of the application
- `x` (number, required): X coordinate of the top-left corner of the frame
- `y` (number, required): Y coordinate of the top-left corner of the frame  
- `width` (number, required): Width of the frame
- `height` (number, required): Height of the frame

**Returns:** JSON array of UI elements within the specified frame, including their properties and actionability status.

### 4. `click_at_coordinate`
Clicks at a specific coordinate within an application window. Useful when you know the exact position of an element.

**Parameters:**
- `bundle_identifier` (string, required): Bundle identifier of the application
- `x` (number, required): X coordinate to click at
- `y` (number, required): Y coordinate to click at

**Returns:** Confirmation message when the click is successfully executed.

## Setup and Installation

### 1. Build the project
```bash
swift build
```

### 2. Run the server
```bash
swift run NudgeServer
```

### 3. Run tests
```bash
swift test
```

## Accessibility Permissions

⚠️ **Important:** This server requires accessibility permissions to function properly.

1. Go to **System Preferences** → **Security & Privacy** → **Privacy** → **Accessibility**
2. Add your terminal application or the built executable to the list of allowed applications
3. Ensure the checkbox is checked for the application

Without these permissions, the server will throw `accessibilityPermissionDenied` errors.

## Project Structure

```
Nudge-Server/
├── Package.swift                    # Swift package manifest
├── Sources/
│   ├── main_server.swift           # Main server entry point
│   ├── servers/
│   │   ├── NavServer.swift         # Main MCP server implementation
│   │   └── TestServer.swift        # Test server (development)
│   ├── managers/
│   │   └── StateManager.swift      # UI state management
│   ├── utility/
│   │   ├── utility.swift           # Utility functions
│   │   └── StateManagerStructs.swift  # Data structures
│   └── error/
│       └── NudgeError.swift        # Custom error types
└── Tests/
    └── NudgeServerTests/
        ├── StateManagerTests.swift  # State manager tests
        └── NavServerTests.swift     # Server tests
```

## Usage with MCP Clients

This server runs in stdio mode and can be integrated with MCP-compatible clients. The server will:

1. Accept MCP protocol messages via stdin
2. Process tool calls for the 4 available tools
3. Return results via stdout
4. Handle errors gracefully with appropriate error messages

## Example Workflows

### Basic Application Interaction
1. Use `open_application` to launch an application
2. Use `get_state_of_application` to understand the current UI state
3. Use `get_ui_elements_in_frame` to explore specific areas
4. Use `click_at_coordinate` to interact with specific elements

### UI Automation
The server is designed to enable AI agents to:
- Navigate complex application interfaces
- Understand application state through UI trees
- Perform precise interactions with UI elements
- Automate repetitive tasks across different macOS applications

## Development

This project uses:
- **Swift Package Manager** for dependency management
- **MCP Swift SDK** for protocol implementation
- **Swift Service Lifecycle** for server management
- **AppKit** for macOS integration
- **XCTest** for testing

The server is designed to be lightweight, efficient, and focused on providing reliable UI automation capabilities for AI agents.

## Error Handling

The server provides comprehensive error handling for:
- Missing accessibility permissions
- Application not found or not running
- Invalid UI elements or coordinates
- Network and protocol errors
- Invalid arguments and requests

All errors are returned as structured MCP error responses with descriptive messages.
