# Nudge Navigation Server

A Swift server application built with Swift Package Manager.

## Requirements

- Swift 6.1 or later
- macOS 10.15 or later

## Building and Running

### Build the project
```bash
swift build
```

### Run the server
```bash
swift run ServerSrc
```

### Run tests
```bash
swift test
```

## Project Structure

```
Nudge-server/
├── Package.swift          # Package manifest
├── Sources/
│   └── ServerSrc/
│       ├── main_server.swift  # Main server entry point
│       ├── NavServer.swift    # Nudge Navigation Server implementation
│       └── TestServer.swift   # Test server implementation (can be removed if no longer used)
└── Tests/
    └── CLIToolTests/
        └── CLIToolTests.swift
```

## Current Functionality

The Nudge Navigation Server provides functionality to interact with the macOS system, specifically to open applications using their bundle identifiers. It exposes a tool named `open_application` for this purpose.

## Development

This project uses Swift Package Manager for dependency management and building. The server is designed to be lightweight and efficient for handling HTTP requests. 
