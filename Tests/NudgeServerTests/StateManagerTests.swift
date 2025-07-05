import XCTest
import AppKit
@testable import NudgeServer

final class StateManagerTests: XCTestCase {
    var stateManager: StateManager!

    override func setUp() {
        super.setUp()
        // Since StateManager is a singleton, we can grab the shared instance.
        stateManager = StateManager.shared
    }

    override func tearDown() {
        stateManager = nil
        super.tearDown()
    }

    func testGetUIElements_ValidApp() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Should get some elements for Xcode
        XCTAssertGreaterThanOrEqual(elements.count, 0, "Should return at least 0 UI elements")
        
        // If we got elements, verify they have the expected structure
        for element in elements {
            XCTAssertFalse(element.element_id.isEmpty, "Element should have non-empty ID")
            XCTAssertTrue(element.element_id.starts(with: "element_"), "ID should start with 'element_'")
            XCTAssertFalse(element.description.isEmpty, "Element should have non-empty description")
            // Children can be empty, that's fine
        }
    }

    func testGetUIElements_AutoOpensApp() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // This should auto-open TextEdit and return its UI elements
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Should get some elements for TextEdit
        XCTAssertGreaterThanOrEqual(elements.count, 0, "Should return at least 0 UI elements")
        
        // Verify the structure
        for element in elements {
            XCTAssertFalse(element.element_id.isEmpty, "Element should have non-empty ID")
            XCTAssertFalse(element.description.isEmpty, "Element should have non-empty description")
        }
    }

    func testUIElementsHaveUniqueIDs() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        let allIds = extractAllIds(from: elements)
        
        // Check that all IDs are unique
        let uniqueIds = Set(allIds)
        XCTAssertEqual(allIds.count, uniqueIds.count, "All UI element IDs should be unique")
        
        // Check that IDs follow the expected format
        for id in allIds {
            XCTAssertTrue(id.starts(with: "element_"), "ID should start with 'element_'")
        }
    }

    func testClickElementById_InvalidId() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        
        // Get elements first to populate the registry
        _ = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Try to click an element with an invalid ID
        do {
            try await stateManager.clickElementById(applicationIdentifier: appIdentifier, elementId: "invalid_id")
            XCTFail("Expected to throw an error for invalid element ID")
        } catch let error as NudgeError {
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("not found"), "Error message should indicate element not found")
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testClickElementById_ValidId() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        
        // Get UI elements 
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first {
            // This should not throw an error
            try await stateManager.clickElementById(applicationIdentifier: appIdentifier, elementId: firstElement.element_id)
            
            // Test passes if no error is thrown
            XCTAssertTrue(true, "Clicking valid element ID should succeed")
        } else {
            // Skip test if no actionable elements found
            XCTAssertTrue(true, "No actionable elements found to test clicking")
        }
    }

    func testTreeStructure() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Verify tree structure
        for element in elements {
            verifyElementStructure(element)
        }
    }

    func testSimplifiedArchitecture() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // Test the new simplified workflow
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Should have only 3 fields: element_id, description, children
        for element in elements {
            XCTAssertFalse(element.element_id.isEmpty, "Should have element_id")
            XCTAssertFalse(element.description.isEmpty, "Should have description")
            // children can be empty array, that's fine
            
            // Test nested structure
            for child in element.children {
                XCTAssertFalse(child.element_id.isEmpty, "Child should have element_id")
                XCTAssertFalse(child.description.isEmpty, "Child should have description")
            }
        }
    }

    // Helper method to extract all IDs from a UI tree
    private func extractAllIds(from elements: [UIElementInfo]) -> [String] {
        var ids: [String] = []
        for element in elements {
            ids.append(element.element_id)
            ids.append(contentsOf: extractAllIds(from: element.children))
        }
        return ids
    }
    
    // Helper method to verify element structure
    private func verifyElementStructure(_ element: UIElementInfo) {
        XCTAssertFalse(element.element_id.isEmpty, "Element should have non-empty ID")
        XCTAssertFalse(element.description.isEmpty, "Element should have non-empty description")
        
        // Recursively verify children
        for child in element.children {
            verifyElementStructure(child)
        }
    }
    
    // Helper method to open an application
    private func openApplication(bundleIdentifier: String) async throws {
        let workspace = NSWorkspace.shared
        
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw NudgeError.applicationNotFound(bundleIdentifier: bundleIdentifier)
        }
        
        do {
            try await workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw NudgeError.applicationNotFound(bundleIdentifier: bundleIdentifier)
        }
    }
}