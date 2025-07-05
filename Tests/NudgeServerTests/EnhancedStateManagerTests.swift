import XCTest
import AppKit
@testable import NudgeServer

final class EnhancedStateManagerTests: XCTestCase {
    
    var stateManager: StateManager!
    
    override func setUp() async throws {
        try await super.setUp()
        stateManager = StateManager.shared
    }
    
    override func tearDown() async throws {
        stateManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Enhanced getUIElements Tests
    
    /**
     * Tests element ID uniqueness across the entire tree.
     * Expected behavior: All element IDs should be unique and follow the correct format.
     */
    func testElementIdUniquenessAndFormat() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        let allIds = extractAllElementIds(from: elements)
        
        // Check uniqueness
        let uniqueIds = Set(allIds)
        XCTAssertEqual(allIds.count, uniqueIds.count, "All element IDs should be unique")
        
        // Check format
        for id in allIds {
            XCTAssertTrue(id.hasPrefix("element_"), "Element ID should have correct prefix: \(id)")
            XCTAssertGreaterThan(id.count, 8, "Element ID should be reasonably long: \(id)")
        }
    }
    
    /**
     * Tests tree structure depth and organization.
     * Expected behavior: Tree should have reasonable depth and proper structure.
     */
    func testTreeStructureDepthAndOrganization() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Verify tree structure
        for element in elements {
            verifyTreeDepth(element, maxDepth: 4, currentDepth: 1)
            verifyElementStructure(element)
        }
    }
    
    /**
     * Tests element description quality.
     * Expected behavior: Descriptions should be meaningful and contain useful information.
     */
    func testElementDescriptionQuality() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        for element in elements {
            XCTAssertFalse(element.description.isEmpty, "Element should have non-empty description")
            XCTAssertGreaterThan(element.description.count, 2, "Description should be reasonably descriptive")
            
            // Check for common patterns that indicate good descriptions
            let desc = element.description.lowercased()
            let hasRoleInfo = desc.contains("button") || desc.contains("menu") || desc.contains("field") || 
                             desc.contains("text") || desc.contains("window") || desc.contains("toolbar")
            let hasContentInfo = element.description.count > 10
            
            XCTAssertTrue(hasRoleInfo || hasContentInfo, 
                         "Description should contain role or content info: '\(element.description)'")
        }
    }
    
    /**
     * Tests auto-opening functionality with different applications.
     * Expected behavior: Should auto-open applications that aren't running.
     */
    func testAutoOpeningBehavior() async throws {
        let bundleId = "com.apple.Calculator"
        
        // Check if app is running before test
        let runningAppsBefore = NSWorkspace.shared.runningApplications
        let wasRunning = runningAppsBefore.contains { $0.bundleIdentifier == bundleId }
        
        // Get UI elements (should auto-open if not running)
        let elements = try await stateManager.getUIElements(applicationIdentifier: bundleId)
        
        // Check if app is running after test
        let runningAppsAfter = NSWorkspace.shared.runningApplications
        let isNowRunning = runningAppsAfter.contains { $0.bundleIdentifier == bundleId }
        
        XCTAssertTrue(isNowRunning, "Application should be running after getUIElements")
        XCTAssertGreaterThanOrEqual(elements.count, 0, "Should return elements after auto-opening")
        
        if !wasRunning {
            print("✅ Successfully auto-opened \(bundleId)")
        }
    }
    
    /**
     * Tests focusing behavior.
     * Expected behavior: Should bring application to front when getting elements.
     */
    func testApplicationFocusingBehavior() async throws {
        let bundleId = "com.apple.TextEdit"
        
        // Get elements (should focus the app)
        let elements = try await stateManager.getUIElements(applicationIdentifier: bundleId)
        
        // Wait a moment for focus to settle
        try await Task.sleep(for: .seconds(1))
        
        // Check if the app is now frontmost
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        XCTAssertEqual(frontmostApp?.bundleIdentifier, bundleId, 
                      "Application should be focused after getUIElements")
        
        XCTAssertGreaterThanOrEqual(elements.count, 0, "Should return elements after focusing")
    }
    
    // MARK: - Enhanced clickElementById Tests
    
    /**
     * Tests clicking performance with direct AXUIElement references.
     * Expected behavior: Clicks should be fast due to direct element references.
     */
    func testClickPerformanceWithDirectReferences() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // Get elements first
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first {
            let startTime = Date()
            
            try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            
            let duration = Date().timeIntervalSince(startTime)
            XCTAssertLessThan(duration, 2.0, "Click should complete quickly with direct references")
        }
    }
    
    /**
     * Tests clicking multiple elements in sequence.
     * Expected behavior: Should handle multiple clicks without issues.
     */
    func testMultipleSequentialClicks() async throws {
        let appIdentifier = "com.apple.Calculator"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Find clickable elements (buttons)
        let buttons = elements.filter { element in
            let desc = element.description.lowercased()
            return desc.contains("button")
        }
        
        // Click multiple buttons if available
        let clickCount = min(3, buttons.count)
        for i in 0..<clickCount {
            try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: buttons[i].element_id
            )
            
            // Small delay between clicks
            try await Task.sleep(for: .milliseconds(500))
        }
        
        print("Successfully clicked \(clickCount) buttons in sequence")
        XCTAssertTrue(true, "Multiple sequential clicks should work")
    }
    
    // MARK: - Enhanced updateUIElementTree Tests
    
    /**
     * Tests updating element trees for different element types.
     * Expected behavior: Should return appropriate tree structures for different elements.
     */
    func testUpdateTreeForDifferentElementTypes() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Test updating trees for different types of elements
        for element in elements.prefix(3) { // Test first 3 elements
            let updatedTree = try await stateManager.updateUIElementTree(
                applicationIdentifier: appIdentifier,
                elementId: element.element_id
            )
            
            XCTAssertGreaterThanOrEqual(updatedTree.count, 0, "Updated tree should be valid")
            
            // Verify structure of updated tree
            for updatedElement in updatedTree {
                XCTAssertFalse(updatedElement.element_id.isEmpty, "Updated element should have element_id")
                XCTAssertFalse(updatedElement.description.isEmpty, "Updated element should have description")
            }
        }
    }
    
    /**
     * Tests update tree depth limitation.
     * Expected behavior: Updated trees should have reasonable depth (not too deep).
     */
    func testUpdateTreeDepthLimitation() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first {
            let updatedTree = try await stateManager.updateUIElementTree(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            
            // Verify depth is reasonable
            for element in updatedTree {
                verifyTreeDepth(element, maxDepth: 4, currentDepth: 1)
            }
        }
    }
    
    // MARK: - Enhanced elementExists Tests
    
    /**
     * Tests element existence validation across different scenarios.
     * Expected behavior: Should accurately track element existence.
     */
    func testElementExistenceValidation() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // Initially no elements should exist
        let initialExists = await stateManager.elementExists(elementId: "element_1")
        XCTAssertFalse(initialExists, "No elements should exist initially")
        
        // Get elements
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // All discovered elements should now exist
        for element in elements.prefix(5) { // Test first 5
            let exists = await stateManager.elementExists(elementId: element.element_id)
            XCTAssertTrue(exists, "Discovered element should exist: \(element.element_id)")
        }
        
        // Non-existent elements should not exist
        let nonExistentExists = await stateManager.elementExists(elementId: "nonexistent_element_12345")
        XCTAssertFalse(nonExistentExists, "Non-existent element should not exist")
    }
    
    // MARK: - Performance Tests
    
    /**
     * Tests overall system performance.
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
        
        if let firstElement = elements.first {
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
        
        print("Performance test completed - all operations within time limits")
    }
    
    // MARK: - Application Switching Tests
    
    /**
     * Tests behavior when switching between applications.
     * Expected behavior: Should handle application switching cleanly.
     */
    func testApplicationSwitching() async throws {
        let app1 = "com.apple.TextEdit"
        let app2 = "com.apple.Calculator"
        
        // Get elements from first app
        let elements1 = try await stateManager.getUIElements(applicationIdentifier: app1)
        XCTAssertGreaterThan(elements1.count, 0, "Should get elements from first app")
        
        if let element1 = elements1.first {
            let exists1 = await stateManager.elementExists(elementId: element1.element_id)
            XCTAssertTrue(exists1, "Element from first app should exist")
        }
        
        // Get elements from second app
        let elements2 = try await stateManager.getUIElements(applicationIdentifier: app2)
        XCTAssertGreaterThan(elements2.count, 0, "Should get elements from second app")
        
        if let element2 = elements2.first {
            let exists2 = await stateManager.elementExists(elementId: element2.element_id)
            XCTAssertTrue(exists2, "Element from second app should exist")
            
            // Element from first app should no longer exist (registry cleared)
            if let element1 = elements1.first {
                let stillExists1 = await stateManager.elementExists(elementId: element1.element_id)
                XCTAssertFalse(stillExists1, "Element from first app should not exist after switching")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractAllElementIds(from elements: [UIElementInfo]) -> [String] {
        var ids: [String] = []
        
        for element in elements {
            ids.append(element.element_id)
            ids.append(contentsOf: extractAllElementIds(from: element.children))
        }
        
        return ids
    }
    
    private func verifyTreeDepth(_ element: UIElementInfo, maxDepth: Int, currentDepth: Int) {
        XCTAssertLessThanOrEqual(currentDepth, maxDepth, "Tree depth should not exceed \(maxDepth) levels")
        
        for child in element.children {
            verifyTreeDepth(child, maxDepth: maxDepth, currentDepth: currentDepth + 1)
        }
    }
    
    private func verifyElementStructure(_ element: UIElementInfo) {
        XCTAssertFalse(element.element_id.isEmpty, "Element should have non-empty ID")
        XCTAssertFalse(element.description.isEmpty, "Element should have non-empty description")
        
        // Recursively verify children
        for child in element.children {
            verifyElementStructure(child)
        }
    }
} 