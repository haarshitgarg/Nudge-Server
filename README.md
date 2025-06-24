# Nudge Server

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
│       └── TestServer.swift   # Test server implementation
└── Tests/
    └── CLIToolTests/
        └── CLIToolTests.swift
```

## Current Functionality

The server provides a basic HTTP server implementation with test endpoints.

## Development

This project uses Swift Package Manager for dependency management and building. The server is designed to be lightweight and efficient for handling HTTP requests. 
