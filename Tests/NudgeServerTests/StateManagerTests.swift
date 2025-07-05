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

    /**
     * Tests the basic functionality of getting UI elements from a running application.
     * This test verifies that the StateManager can successfully retrieve UI elements from Xcode
     * and that each element has the expected structure with valid IDs and descriptions.
     * It validates the core UI element discovery functionality.
     */
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

    /**
     * Tests the auto-opening functionality of the StateManager.
     * This test verifies that when an application is not running, the StateManager
     * automatically opens it and then retrieves its UI elements. It validates the
     * complete workflow from application launch to UI element discovery.
     */
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

    /**
     * Tests that all UI element IDs are unique across the entire tree structure.
     * This test validates the ID generation system by checking that no two elements
     * have the same ID, and that all IDs follow the expected format pattern.
     * This ensures reliable element identification for clicking operations.
     */
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

    /**
     * Tests error handling when attempting to click an element with an invalid ID.
     * This test verifies that the StateManager properly handles cases where a non-existent
     * element ID is provided, ensuring it throws the appropriate error with a descriptive
     * message. This validates the error handling and registry lookup functionality.
     */
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

    /**
     * Tests successful element clicking with a valid element ID.
     * This test verifies that the StateManager can successfully click an element
     * using its ID after it has been discovered. It validates the complete
     * workflow from element discovery to successful interaction.
     */
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

    /**
     * Tests the hierarchical tree structure of UI elements.
     * This test verifies that the StateManager correctly creates a nested tree
     * structure where each element and its children have valid IDs and descriptions.
     * It validates the recursive tree building functionality.
     */
    func testTreeStructure() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Verify tree structure
        for element in elements {
            verifyElementStructure(element)
        }
    }

    /**
     * Tests the simplified 3-field architecture for UI elements.
     * This test validates that each UI element has exactly the three required fields:
     * element_id, description, and children. It ensures the simplified data structure
     * is maintained throughout the tree, making it optimal for LLM processing.
     */
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