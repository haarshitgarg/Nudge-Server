# Nudge Navigation Server

A Swift-based Model Context Protocol (MCP) server that provides advanced tools for macOS UI automation and application interaction. This server enables AI agents to interact with macOS applications through accessibility APIs using a sophisticated element-based approach with UI tree management.

## What is MCP?

The Model Context Protocol (MCP) is an open standard that enables AI assistants to securely connect to external data sources and tools. This server implements MCP to provide comprehensive macOS UI automation capabilities to AI agents.

## Requirements

- Swift 6.1 or later
- macOS 14.0 or later
- **Accessibility permissions** - The server requires accessibility permissions to interact with applications

## Tools Provided

This MCP server exposes the following tools:

### 1. `get_ui_elements`
Retrieves UI elements for an application in a tree structure with limited depth (2-3 levels). Automatically opens the application if not running, brings it to focus, and provides a comprehensive overview of the application state.

**Parameters:**
- `bundle_identifier` (string, required): Bundle identifier of the application (e.g., "com.apple.safari" for Safari, "com.apple.TextEdit" for TextEdit)

**Returns:** JSON tree structure with UI elements containing:
- `element_id`: Unique identifier for the element
- `description`: Human-readable description of the element
- `children`: Array of child elements

**Use case:** Get an overview of the application state. If you need more details about specific elements, use `update_ui_element_tree`.

### 2. `click_element_by_id`
Clicks a UI element by its ID using direct AXUIElement reference for maximum performance and reliability.

**Parameters:**
- `bundle_identifier` (string, required): Bundle identifier of the application
- `element_id` (string, required): Element ID obtained from `get_ui_elements`

**Returns:** Confirmation message when the element is successfully clicked.

### 3. `update_ui_element_tree`
Updates and returns the UI element tree for a specific element by its ID. Call this function when you need more information about the children of a particular UI element.

**Parameters:**
- `bundle_identifier` (string, required): Bundle identifier of the application
- `element_id` (string, required): Element ID to update and return tree from (obtained from `get_ui_elements`)

**Returns:** JSON tree structure with updated UI elements and their children.

**Use case:** When you need to explore deeper into the UI hierarchy of a specific element.

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
├── Package.swift                           # Swift package manifest
├── Sources/
│   ├── main_server.swift                   # Main server entry point
│   ├── servers/
│   │   ├── NavServer.swift                 # Main MCP server implementation
│   │   └── TestServer.swift                # Test server (development)
│   ├── managers/
│   │   └── StateManager.swift              # UI state management and element registry
│   ├── utility/
│   │   ├── utility.swift                   # Utility functions
│   │   └── StateManagerStructs.swift       # Data structures for UI elements
│   └── error/
│       └── NudgeError.swift                # Custom error types
├── Tests/
│   └── NudgeServerTests/
│       ├── WorkflowIntegrationTests.swift           # Complete workflow tests
│       ├── EnhancedStateManagerTests.swift          # Enhanced state manager tests
│       ├── ComprehensiveErrorHandlingTests.swift    # Comprehensive error handling tests
│       └── ComprehensiveStateManagerTests.swift     # Comprehensive state manager tests
└── Documentation/
    ├── ENHANCED_SERVER_GUIDE.md           # Enhanced server guide
    ├── GEMINI.md                          # Gemini integration guide
    └── REFACTORING_SUMMARY.md             # Refactoring summary
```

## Key Features

### Advanced UI Element Management
- **Element Registry**: Maintains a registry of UI elements with unique IDs for reliable interaction
- **Tree-based Discovery**: Provides hierarchical UI structure for comprehensive application understanding
- **Direct AXUIElement References**: Uses direct accessibility API references for maximum performance
- **Multi-Application Support**: Handles multiple applications simultaneously with proper state management

### Smart Application Handling
- **Auto-opening**: Automatically opens applications if not running
- **Focus Management**: Brings applications to focus before interaction
- **Window Detection**: Focuses on frontmost windows and menu bars
- **State Consistency**: Maintains consistent UI state across operations

### Comprehensive Testing
- **Workflow Integration Tests**: Tests complete workflows across multiple applications
- **Error Handling Tests**: Comprehensive error scenarios and recovery testing
- **Performance Tests**: Ensures operations complete within reasonable time limits
- **Multi-Application Tests**: Tests interaction with multiple applications simultaneously

## Usage with MCP Clients

This server runs in stdio mode and can be integrated with MCP-compatible clients. The server will:

1. Accept MCP protocol messages via stdin
2. Process tool calls for the 3 available tools
3. Return results via stdout
4. Handle errors gracefully with appropriate error messages

## Example Workflows

### Basic Application Interaction
1. Use `get_ui_elements` to discover UI elements and get their IDs
2. Use `click_element_by_id` to interact with specific elements
3. Use `update_ui_element_tree` to explore deeper into specific UI areas

### Advanced UI Automation
The server enables AI agents to:
- Navigate complex application interfaces using element IDs
- Understand application state through hierarchical UI trees
- Perform reliable interactions with persistent element references
- Handle multi-step workflows across different applications
- Recover from errors and maintain state consistency

### Supported Applications
Tested with:
- **TextEdit**: Text editing and document manipulation
- **Calculator**: Mathematical operations and button interactions
- **Safari**: Web browsing and navigation
- **And many more macOS applications**

## Development

This project uses:
- **Swift Package Manager** for dependency management
- **MCP Swift SDK** (v0.9.0+) for protocol implementation
- **Swift Service Lifecycle** (v2.8.0+) for server management
- **AppKit** for macOS integration
- **XCTest** for comprehensive testing

### Dependencies
```swift
dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.8.0")
]
```

## Error Handling

The server provides comprehensive error handling for:
- Missing accessibility permissions
- Application not found or not running
- Invalid UI elements or element IDs
- Element registry inconsistencies
- Network and protocol errors
- Invalid arguments and requests
- Multi-application state conflicts

All errors are returned as structured MCP error responses with descriptive messages and proper error recovery mechanisms.

## Testing

The project includes comprehensive tests covering:
- **Workflow Integration**: Complete end-to-end workflows
- **State Management**: UI element registry and state consistency
- **Error Handling**: All error scenarios and recovery paths
- **Performance**: Timing and efficiency of operations
- **Multi-Application**: Concurrent application handling

Run all tests with:
```bash
swift test
```

## Server Capabilities

When started, the server provides:
- 🚀 Auto-opening applications
- 📊 Tree-based UI structure discovery
- ⚡ Direct AXUIElement performance
- 🎯 Element ID-based interactions
- 🔄 UI tree updates and exploration
- 🛠️ Comprehensive error handling
- 📱 Multi-application support

Ready for advanced macOS UI automation tasks!
