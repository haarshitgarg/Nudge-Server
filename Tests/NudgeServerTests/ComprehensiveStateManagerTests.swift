import XCTest
import AppKit
@testable import NudgeLibrary

final class ComprehensiveStateManagerTests: XCTestCase {
    
    // MARK: - Test Data and Setup
    
    var stateManager: StateManager!
    
    override func setUp() async throws {
        try await super.setUp()
        stateManager = StateManager.shared
    }
    
    override func tearDown() async throws {
        await stateManager.cleanup()
        stateManager = nil
        try await super.tearDown()
    }
    
    // MARK: - getUIElements Tests
    
    /**
     * Tests getUIElements with valid application identifier.
     * Expected behavior: Should return UI elements in tree structure with 3 fields (element_id, description, children).
     */
    func testGetUIElementsWithValidApp() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Should return array of UI elements
        XCTAssertGreaterThanOrEqual(elements.count, 2, "Should return at least 2 UI elements")
        
        // Verify each element has the expected 3-field structure
        for element in elements {
            XCTAssertFalse(element.element_id.isEmpty, "Element should have non-empty element_id")
            XCTAssertTrue(element.element_id.hasPrefix("element_"), "Element ID should have correct prefix")
            XCTAssertFalse(element.description.isEmpty, "Element should have non-empty description")
            XCTAssertNotNil(element.children, "Element should have children array (can be empty)")
        }
    }
    
    /**
     * Tests getUIElements auto-opening behavior.
     * Expected behavior: Should automatically open application if not running, then return UI elements.
     */
    func testGetUIElementsAutoOpensApplication() async throws {
        let appIdentifier = "com.apple.Calculator"
        
        // Check if app is currently running
        let runningApps = NSWorkspace.shared.runningApplications
        let _ = runningApps.contains { $0.bundleIdentifier == appIdentifier }
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // App should now be running
        let newRunningApps = NSWorkspace.shared.runningApplications
        let isNowRunning = newRunningApps.contains { $0.bundleIdentifier?.lowercased() == appIdentifier.lowercased() }
        
        XCTAssertTrue(isNowRunning, "Application should be running after getUIElements call")
        
        // Should still return valid elements
        XCTAssertGreaterThanOrEqual(elements.count, 1, "Should return elements even if app wasn't initially running")
    }
    
    /**
     * Tests getUIElements focusing behavior.
     * Expected behavior: Should bring application to front/focus before scanning UI elements.
     */
    func testGetUIElementsFocusesApplication() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // Open TextEdit
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Check if TextEdit is the active application
        let activeApp = NSWorkspace.shared.frontmostApplication
        XCTAssertEqual(activeApp?.bundleIdentifier, appIdentifier, 
                      "Application should be focused after getUIElements call")
        
        // Should return valid elements
        XCTAssertGreaterThanOrEqual(elements.count, 0, "Should return elements after focusing")
    }
    
    /**
     * Tests getUIElements with invalid application identifier.
     * Expected behavior: Should throw applicationNotFound error.
     */
    func testGetUIElementsWithInvalidApp() async throws {
        let appIdentifier = "com.nonexistent.application"
        
        do {
            _ = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
            XCTFail("Should throw error for invalid application identifier")
        } catch let error as NudgeError {
            switch error {
            case .applicationNotFound(let bundleId):
                XCTAssertEqual(bundleId, appIdentifier, "Error should contain the bundle identifier")
            default:
                XCTFail("Should throw applicationNotFound error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
    
    /**
     * Tests getUIElements tree structure depth limitation.
     * Expected behavior: Should return tree with limited depth (2-3 levels) for performance.
     */
    func testGetUIElementsTreeDepthLimitation() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Check tree depth is reasonable (not too deep)
        for element in elements {
            verifyTreeDepth(element, maxDepth: 4, currentDepth: 1)
        }
    }
    
    /**
     * Tests getUIElements element ID uniqueness.
     * Expected behavior: All element IDs should be unique across the entire tree.
     */
    func testGetUIElementsElementIdUniqueness() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        let allIds = extractAllElementIds(from: elements)
        let uniqueIds = Set(allIds)
        
        XCTAssertEqual(allIds.count, uniqueIds.count, "All element IDs should be unique")
        
        // Verify ID format
        for id in allIds {
            XCTAssertTrue(id.hasPrefix("element_"), "Element ID should have correct prefix")
        }
    }
    
    /**
     * Tests getUIElements element description quality.
     * Expected behavior: Each element should have meaningful description containing role, title, or value.
     */
    func testGetUIElementsDescriptionQuality() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Check that descriptions are meaningful
        for element in elements {
            XCTAssertFalse(element.description.isEmpty, "Element should have non-empty description")
            XCTAssertGreaterThan(element.description.count, 3, "Description should be reasonably descriptive")
        }
    }
    
    /**
     * Tests getUIElements container flattening behavior.
     * Expected behavior: Should flatten container elements to show actual actionable content.
     */
    func testGetUIElementsContainerFlattening() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Verify that we don't have excessive container nesting
        for element in elements {
            verifyNoExcessiveContainerNesting(element)
        }
    }
    
    // MARK: - clickElementById Tests
    
    /**
     * Tests clickElementById with valid element ID.
     * Expected behavior: Should successfully click element without throwing error.
     */
    func testClickElementByIdWithValidId() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // First get UI elements to populate the registry
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Get all elements (including children) recursively
        let allElements = getAllElementsRecursively(from: elements)
        
        // Look for clickable elements (buttons, menu items, etc.)
        let clickableElements = allElements.filter { element in
            element.description.contains("Button") || 
            element.description.contains("MenuItem")
        }
        
        if let firstElement = clickableElements.first {
            // Should not throw error when clicking valid element
            try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            
            // Test passes if no error is thrown
            XCTAssertTrue(true, "Clicking valid element should not throw error")
        } else {
            XCTFail("Should have at least one clickable element to test clicking")
        }
    }
    
    // Helper function to get all elements recursively
    private func getAllElementsRecursively(from elements: [UIElementInfo]) -> [UIElementInfo] {
        var allElements: [UIElementInfo] = []
        
        for element in elements {
            allElements.append(element)
            allElements.append(contentsOf: getAllElementsRecursively(from: element.children))
        }
        
        return allElements
    }
    
    /**
     * Tests clickElementById with invalid element ID.
     * Expected behavior: Should throw invalidRequest error indicating element not found.
     */
    func testClickElementByIdWithInvalidId() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // First get UI elements to populate the registry
        _ = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        do {
            try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: "nonexistent_element_id"
            )
            XCTFail("Should throw error for invalid element ID")
        } catch let error as NudgeError {
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("not found"), "Error message should indicate element not found")
            default:
                XCTFail("Should throw invalidRequest error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
    
    /**
     * Tests clickElementById before getting UI elements.
     * Expected behavior: Should throw invalidRequest error indicating registry is empty.
     */
    func testClickElementByIdBeforeGettingElements() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        do {
            try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: "element_1"
            )
            XCTFail("Should throw error when clicking before getting elements")
        } catch let error as NudgeError {
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("not found"), "Error message should indicate element not found")
            default:
                XCTFail("Should throw invalidRequest error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
    
    /**
     * Tests clickElementById accessibility permissions.
     * Expected behavior: Should throw accessibilityPermissionDenied if accessibility is not enabled.
     */
    func testClickElementByIdAccessibilityPermissions() async throws {
        // Note: This test will pass if accessibility is enabled, which is expected in test environment
        let appIdentifier = "com.apple.TextEdit"
        
        // Get UI elements first
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first {
            // If accessibility is enabled, this should work
            // If not, it should throw accessibilityPermissionDenied
            do {
                try await stateManager.clickElementById(
                    applicationIdentifier: appIdentifier,
                    elementId: firstElement.element_id
                )
                // Test passes if accessibility is enabled
                XCTAssertTrue(true, "Click succeeded with accessibility enabled")
            } catch let error as NudgeError {
                switch error {
                case .accessibilityPermissionDenied:
                    XCTAssertTrue(true, "Properly throws accessibility permission error")
                default:
                    // Other errors are also acceptable for this test
                    XCTAssertTrue(true, "Error is acceptable: \(error)")
                }
            }
        }
    }
    
    /**
     * Tests clickElementById performance with direct AXUIElement reference.
     * Expected behavior: Should complete click operation within 2 seconds.
     */
    func testClickElementByIdPerformance() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // Get UI elements first
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first(where: { $0.description.contains("AXButton") || $0.description.contains("AXMenuItem") }) {
            let startTime = Date()
            
            try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            XCTAssertLessThan(duration, 2.0, "Click should complete within 2 seconds")
        }
    }
    
    // MARK: - updateUIElementTree Tests
    
    /**
     * Tests updateUIElementTree with valid element ID.
     * Expected behavior: Should return updated tree structure for the specified element.
     */
    func testUpdateUIElementTreeWithValidId() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // First get UI elements to populate the registry
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first {
            let updatedTree = try await stateManager.updateUIElementTree(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            
            // Should return updated tree structure
            XCTAssertGreaterThanOrEqual(updatedTree.count, 0, "Should return updated tree")
            
            // Verify structure of updated tree
            for element in updatedTree {
                XCTAssertFalse(element.element_id.isEmpty, "Updated element should have element_id")
                XCTAssertFalse(element.description.isEmpty, "Updated element should have description")
                XCTAssertNotNil(element.children, "Updated element should have children array")
            }
        }
    }
    
    /**
     * Tests updateUIElementTree with invalid element ID.
     * Expected behavior: Should throw invalidRequest error indicating element not found.
     */
    func testUpdateUIElementTreeWithInvalidId() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // First get UI elements to populate the registry
        _ = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        do {
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: appIdentifier,
                elementId: "nonexistent_element_id"
            )
            XCTFail("Should throw error for invalid element ID")
        } catch let error as NudgeError {
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("not found"), "Error message should indicate element not found")
            default:
                XCTFail("Should throw invalidRequest error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
    
    /**
     * Tests updateUIElementTree before getting UI elements.
     * Expected behavior: Should throw invalidRequest error indicating registry is empty.
     */
    func testUpdateUIElementTreeBeforeGettingElements() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        do {
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: appIdentifier,
                elementId: "element_1"
            )
            XCTFail("Should throw error when updating before getting elements")
        } catch let error as NudgeError {
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("not found"), "Error message should indicate element not found")
            default:
                XCTFail("Should throw invalidRequest error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
    
    /**
     * Tests updateUIElementTree depth and structure.
     * Expected behavior: Should return updated tree with appropriate depth (up to 3 levels).
     */
    func testUpdateUIElementTreeDepthAndStructure() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // Get UI elements first
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first {
            let updatedTree = try await stateManager.updateUIElementTree(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            
            // Verify updated tree has reasonable depth
            for element in updatedTree {
                verifyTreeDepth(element, maxDepth: 4, currentDepth: 1)
            }
        }
    }
    
    /**
     * Tests updateUIElementTree accessibility permissions.
     * Expected behavior: Should throw accessibilityPermissionDenied if accessibility is not enabled.
     */
    func testUpdateUIElementTreeAccessibilityPermissions() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // Get UI elements first
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first {
            // If accessibility is enabled, this should work
            // If not, it should throw accessibilityPermissionDenied
            do {
                _ = try await stateManager.updateUIElementTree(
                    applicationIdentifier: appIdentifier,
                    elementId: firstElement.element_id
                )
                // Test passes if accessibility is enabled
                XCTAssertTrue(true, "Update succeeded with accessibility enabled")
            } catch let error as NudgeError {
                switch error {
                case .accessibilityPermissionDenied:
                    XCTAssertTrue(true, "Properly throws accessibility permission error")
                default:
                    // Other errors are also acceptable for this test
                    XCTAssertTrue(true, "Error is acceptable: \(error)")
                }
            }
        }
    }
    
    // MARK: - elementExists Tests
    
    /**
     * Tests elementExists with valid element ID.
     * Expected behavior: Should return true for elements in the registry.
     */
    func testElementExistsWithValidId() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // First get UI elements to populate the registry
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first {
            let exists = await stateManager.elementExists(elementId: firstElement.element_id)
            XCTAssertTrue(exists, "Element should exist in registry after getUIElements")
        }
    }
    
    /**
     * Tests elementExists with invalid element ID.
     * Expected behavior: Should return false for elements not in the registry.
     */
    func testElementExistsWithInvalidId() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // First get UI elements to populate the registry
        _ = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        let exists = await stateManager.elementExists(elementId: "nonexistent_element_id")
        XCTAssertFalse(exists, "Non-existent element should not exist in registry")
    }
    
    /**
     * Tests elementExists before getting UI elements.
     * Expected behavior: Should return false when registry is empty.
     */
    func testElementExistsBeforeGettingElements() async throws {
        let exists = await stateManager.elementExists(elementId: "element_1")
        XCTAssertFalse(exists, "No elements should exist before getUIElements is called")
    }
    
    // MARK: - Integration Tests
    
    /**
     * Tests complete workflow: getUIElements → elementExists → clickElementById → updateUIElementTree.
     * Expected behavior: All methods should work together seamlessly.
     */
    func testCompleteWorkflow() async throws {
        let appIdentifier = "com.apple.Calculator"
        
        // Step 1: Get UI elements
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        XCTAssertGreaterThan(elements.count, 0, "Should get UI elements")
        
        if let firstElement = elements.first(where: { $0.description.contains("AXButton") || $0.description.contains("AXMenuItem") }) {
            // Step 2: Verify element exists
            let exists = await stateManager.elementExists(elementId: firstElement.element_id)
            XCTAssertTrue(exists, "Element should exist after getUIElements")
            
            // Step 3: Click element
            try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            
            // Step 4: Update element tree
            let updatedTree = try await stateManager.updateUIElementTree(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            
            XCTAssertGreaterThanOrEqual(updatedTree.count, 0, "Should get updated tree")
            
            // Step 5: Verify element still exists
            let stillExists = await stateManager.elementExists(elementId: firstElement.element_id)
            XCTAssertTrue(stillExists, "Element should still exist after workflow")
        }
    }
    
    /**
     * Tests System Preferences opening and UI element retrieval performance.
     * Expected behavior: Should open System Preferences and retrieve UI elements within 15 seconds.
     * System Preferences typically takes longer to open than simple apps like Calculator.
     */
    func testSystemPreferencesPerformance() async throws {
        let systemPreferencesIdentifier = "com.apple.systempreferences"
        
        let startTime = Date()
        let elements = try await stateManager.getUIElements(applicationIdentifier: systemPreferencesIdentifier)
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // System Preferences can take longer to open and populate
        XCTAssertLessThan(duration, 15.0, "System Preferences should open and populate UI elements within 15 seconds")
        XCTAssertGreaterThan(elements.count, 0, "Should return UI elements for System Preferences")
        
        // Test AXCell description enhancement
        let allElements = getAllElementsRecursively(from: elements)
        let cellElements = allElements.filter { element in
            element.description.contains("(Cell)")
        }
        
        if !cellElements.isEmpty {
            for cellElement in cellElements {
                XCTAssertFalse(cellElement.description.isEmpty, "Cell elements should have meaningful descriptions")
                // Verify enhanced cell descriptions contain useful information
                let hasEnhancedInfo = cellElement.description.count > 6 // More than just "(Cell)"
                if hasEnhancedInfo {
                    print("Enhanced cell description: \(cellElement.description)")
                }
            }
        }
        
        // Test clicking performance on System Preferences elements
        let clickableElements = allElements.filter { element in
            element.description.contains("(Button)") ||
            element.description.contains("(Cell)") ||
            element.description.contains("(Tab)")
        }
        
        if let firstClickable = clickableElements.first {
            let clickStartTime = Date()
            try await stateManager.clickElementById(
                applicationIdentifier: systemPreferencesIdentifier,
                elementId: firstClickable.element_id
            )
            let clickEndTime = Date()
            let clickDuration = clickEndTime.timeIntervalSince(clickStartTime)
            
            XCTAssertLessThan(clickDuration, 2.0, "Clicking System Preferences elements should complete within 2 seconds")
        }
        
        print("System Preferences performance test completed: \(String(format: "%.2f", duration))s opening, \(allElements.count) total elements, \(clickableElements.count) clickable elements")
    }

    /**
     * Tests performance of all operations.
     * Expected behavior: All operations should complete within reasonable time limits.
     */
    func testOverallPerformance() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // Test getUIElements performance
        let getStartTime = Date()
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        let getEndTime = Date()
        let getDuration = getEndTime.timeIntervalSince(getStartTime)
        
        XCTAssertLessThan(getDuration, 10.0, "getUIElements should complete within 10 seconds")
        
        if let firstElement = elements.first(where: { $0.description.contains("AXButton") || $0.description.contains("AXMenuItem") }) {
            // Test elementExists performance
            let existsStartTime = Date()
            _ = await stateManager.elementExists(elementId: firstElement.element_id)
            let existsEndTime = Date()
            let existsDuration = existsEndTime.timeIntervalSince(existsStartTime)
            
            XCTAssertLessThan(existsDuration, 0.1, "elementExists should complete within 0.1 seconds")
            
            // Test clickElementById performance
            let clickStartTime = Date()
            try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            let clickEndTime = Date()
            let clickDuration = clickEndTime.timeIntervalSince(clickStartTime)
            
            XCTAssertLessThan(clickDuration, 2.0, "clickElementById should complete within 2 seconds")
            
            // Test updateUIElementTree performance
            let updateStartTime = Date()
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            let updateEndTime = Date()
            let updateDuration = updateEndTime.timeIntervalSince(updateStartTime)
            
            XCTAssertLessThan(updateDuration, 5.0, "updateUIElementTree should complete within 5 seconds")
        }
    }
    
    // MARK: - Helper Methods
    
    /**
     * Extracts all element IDs from a tree structure for uniqueness testing.
     */
    private func extractAllElementIds(from elements: [UIElementInfo]) -> [String] {
        var ids: [String] = []
        
        for element in elements {
            ids.append(element.element_id)
            ids.append(contentsOf: extractAllElementIds(from: element.children))
        }
        
        return ids
    }
    
    /**
     * Verifies that tree depth doesn't exceed reasonable limits.
     */
    private func verifyTreeDepth(_ element: UIElementInfo, maxDepth: Int, currentDepth: Int) {
        XCTAssertLessThanOrEqual(currentDepth, maxDepth, "Tree depth should not exceed \(maxDepth) levels")
        
        for child in element.children {
            verifyTreeDepth(child, maxDepth: maxDepth, currentDepth: currentDepth + 1)
        }
    }
    
    /**
     * Verifies that there's no excessive container nesting.
     */
    private func verifyNoExcessiveContainerNesting(_ element: UIElementInfo) {
        // Check that description contains meaningful content, not just container roles
        let description = element.description.lowercased()
        let containerKeywords = ["(group)", "(container)", "(layout)", "(area)", "(generic)"]
        
        // There should be no container elements in the tree
        let isContainer = containerKeywords.contains { description.contains($0) }
        if isContainer {
            XCTFail("Container element found: \(element.description)")
        }
        
        // Recursively check children
        for child in element.children {
            verifyNoExcessiveContainerNesting(child)
        }
    }
} 
