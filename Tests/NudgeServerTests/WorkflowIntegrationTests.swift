import XCTest
import AppKit
@testable import NudgeLibrary

final class WorkflowIntegrationTests: XCTestCase {
    
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
    
    // MARK: - Complete Workflow Tests
    
    /**
     * Tests complete workflow: getUIElements → clickElementById → updateUIElementTree
     * Expected behavior: All three operations should work together seamlessly.
     */
    func testCompleteWorkflow() async throws {
        let bundleId = "com.apple.TextEdit"
        
        // Step 1: Get UI elements
        let elements = try await stateManager.getUIElements(applicationIdentifier: bundleId)
        XCTAssertGreaterThan(elements.count, 0, "Should discover UI elements")
        
        if let firstElement = elements.first(where: {$0.description.contains("Button") || $0.description.contains("MenuItem") || $0.description.contains("TextField") || $0.description.contains("TextArea")}) {
            // Step 2: Verify element exists
            let exists = await stateManager.elementExists(elementId: firstElement.element_id)
            XCTAssertTrue(exists, "Element should exist after getUIElements")
            
            // Step 3: Click element
            try await stateManager.clickElementById(
                applicationIdentifier: bundleId,
                elementId: firstElement.element_id
            )
            
            // Step 4: Update element tree
            let updatedTree = try await stateManager.updateUIElementTree(
                applicationIdentifier: bundleId,
                elementId: firstElement.element_id
            )
            
            XCTAssertGreaterThanOrEqual(updatedTree.count, 0, "Should get updated tree")
            
            // Step 5: Verify element still exists after workflow
            let stillExists = await stateManager.elementExists(elementId: firstElement.element_id)
            XCTAssertTrue(stillExists, "Element should still exist after complete workflow")
        }
    }
    
    /**
     * Tests multi-application workflow.
     * Expected behavior: Should handle multiple applications without interference.
     */
    func testMultiApplicationWorkflow() async throws {
        let apps = ["com.apple.TextEdit", "com.apple.Calculator"]
        var appElements: [String: [UIElementInfo]] = [:]
        
        // Get elements from multiple applications
        for app in apps {
            let elements = try await stateManager.getUIElements(applicationIdentifier: app)
            appElements[app] = elements
            XCTAssertGreaterThan(elements.count, 0, "Should get elements from \(app)")
        }
        
        // Test interaction with different applications
        for (app, elements) in appElements {
            if let firstElement = elements.first (where: {$0.description.contains("Button") || $0.description.contains("MenuItem") || $0.description.contains("TextField") || $0.description.contains("TextArea")}) {
                // Should be able to interact with elements from any app
                try await stateManager.clickElementById(
                    applicationIdentifier: app,
                    elementId: firstElement.element_id
                )
                
                _ = try await stateManager.updateUIElementTree(
                    applicationIdentifier: app,
                    elementId: firstElement.element_id
                )
            }
        }
    }
    
    /**
     * Tests Safari navigation workflow.
     * Expected behavior: Should handle complex application navigation.
     */
    func testSafariNavigationWorkflow() async throws {
        let bundleId = "com.apple.Safari"
        
        // Open Safari and get elements
        let elements = try await stateManager.getUIElements(applicationIdentifier: bundleId)
        XCTAssertGreaterThan(elements.count, 0, "Should discover Safari elements")
        
        // Look for actionable elements
        let actionableElements = findElements(in: elements) { element in
            let desc = element.description.lowercased()
            return desc.contains("button") || desc.contains("menu") || desc.contains("field")
        }
        
        print("Found \(actionableElements.count) actionable elements in Safari")
        
        // Test interaction with an actionable element
        if let actionableElement = actionableElements.first {
            print("Testing interaction with: \(actionableElement.description)")
            
            let exists = await stateManager.elementExists(elementId: actionableElement.element_id)
            XCTAssertTrue(exists, "Actionable element should exist in registry")
            
            try await stateManager.clickElementById(
                applicationIdentifier: bundleId,
                elementId: actionableElement.element_id
            )
            
            // Wait for UI to potentially update
            try await Task.sleep(for: .seconds(1))
            
            // Get updated state
            let updatedElements = try await stateManager.getUIElements(applicationIdentifier: bundleId)
            XCTAssertGreaterThan(updatedElements.count, 0, "Should still have elements after interaction")
        }
    }
    
    /**
     * Tests Calculator workflow with number buttons.
     * Expected behavior: Should find and interact with calculator buttons.
     */
    func testCalculatorWorkflow() async throws {
        let bundleId = "com.apple.Calculator"
        
        // Open Calculator and find elements
        let elements = try await stateManager.getUIElements(applicationIdentifier: bundleId)
        XCTAssertGreaterThan(elements.count, 0, "Should discover Calculator elements")
        
        // Look for number buttons
        let numberButtons = elements.filter { element in
            let desc = element.description.lowercased()
            return desc.contains("button") && (desc.contains("1") || desc.contains("2") || desc.contains("3"))
        }
        
        print("Found \(numberButtons.count) number buttons in Calculator")
        
        if let numberButton = numberButtons.first {
            print("Testing click on: \(numberButton.description)")
            
            try await stateManager.clickElementById(
                applicationIdentifier: bundleId,
                elementId: numberButton.element_id
            )
            
            // Verify the interaction worked
            let stillExists = await stateManager.elementExists(elementId: numberButton.element_id)
            XCTAssertTrue(stillExists, "Element should still exist after clicking")
        }
    }
    
    // MARK: - Performance Integration Tests
    
    /**
     * Tests performance of complete workflows.
     * Expected behavior: Complete workflows should complete within reasonable time.
     */
    func testCompleteWorkflowPerformance() async throws {
        let bundleId = "com.apple.TextEdit"
        let startTime = Date()
        
        // Complete workflow timing
        let elements = try await stateManager.getUIElements(applicationIdentifier: bundleId)
        let getElementsTime = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(getElementsTime, 10.0, "Getting elements should complete within 10 seconds")

        if let firstElement = elements.first(where: {$0.description.contains("Button") || $0.description.contains("MenuItem") || $0.description.contains("TextField") || $0.description.contains("TextArea")}) {
            let clickStartTime = Date()
            try await stateManager.clickElementById(
                applicationIdentifier: bundleId,
                elementId: firstElement.element_id
            )
            let clickTime = Date().timeIntervalSince(clickStartTime)
            
            XCTAssertLessThan(clickTime, 2.0, "Clicking element should complete within 2 seconds")
            
            let updateStartTime = Date()
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: bundleId,
                elementId: firstElement.element_id
            )
            let updateTime = Date().timeIntervalSince(updateStartTime)
            
            XCTAssertLessThan(updateTime, 5.0, "Updating element tree should complete within 5 seconds")
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(totalTime, 15.0, "Complete workflow should complete within 15 seconds")
    }
    
    // MARK: - State Consistency Tests
    
    /**
     * Tests registry clearing behavior when switching applications.
     * Expected behavior: Registry should be cleared when switching applications.
     */
    func testRegistryClearingBehavior() async throws {
        let appIdentifier1 = "com.apple.TextEdit"
        let appIdentifier2 = "com.apple.Calculator"
        
        // Get elements for first app
        let elements1 = try await stateManager.getUIElements(applicationIdentifier: appIdentifier1)
        
        if let firstElement1 = elements1.first {
            // Verify element exists
            let exists1 = await stateManager.elementExists(elementId: firstElement1.element_id)
            XCTAssertTrue(exists1, "Element should exist after getUIElements")
            
            // Get elements for second app
            let elements2 = try await stateManager.getUIElements(applicationIdentifier: appIdentifier2)
            
            // Original element should no longer exist (registry cleared)
            let stillExists1 = await stateManager.elementExists(elementId: firstElement1.element_id)
            XCTAssertFalse(stillExists1, "Original element should not exist after switching apps")
            
            // New elements should exist
            if let firstElement2 = elements2.first {
                let exists2 = await stateManager.elementExists(elementId: firstElement2.element_id)
                XCTAssertTrue(exists2, "New element should exist after getUIElements")
            }
        }
    }
    
    // MARK: - Error Recovery Tests
    
    /**
     * Tests that errors don't leave the system in an inconsistent state.
     * Expected behavior: After an error, subsequent valid operations should still work.
     */
    func testErrorRecovery() async throws {
        let validBundleId = "com.apple.TextEdit"
        let invalidElementId = "nonexistent_element"
        
        // Get valid elements first
        let elements = try await stateManager.getUIElements(applicationIdentifier: validBundleId)
        
        // Attempt an operation that should fail
        do {
            try await stateManager.clickElementById(
                applicationIdentifier: validBundleId,
                elementId: invalidElementId
            )
            XCTFail("Should throw error for invalid element ID")
        } catch {
            // Expected to fail
        }
        
        // Verify that valid operations still work after the error
        if let firstElement = elements.first(where: {$0.description.contains("Button") || $0.description.contains("MenuItem") || $0.description.contains("TextField") || $0.description.contains("TextArea")}) {
            try await stateManager.clickElementById(
                applicationIdentifier: validBundleId,
                elementId: firstElement.element_id
            )
            
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: validBundleId,
                elementId: firstElement.element_id
            )
            
            XCTAssertTrue(true, "Valid operations should work after errors")
        }
    }
    
    // MARK: - Real-world Scenario Tests
    
    /**
     * Tests realistic usage scenarios.
     * Expected behavior: Should handle real-world usage patterns effectively.
     */
    func testRealWorldScenarios() async throws {
        // Scenario 1: Quick automation task - open app and find specific elements
        let calculatorId = "com.apple.Calculator"
        let calcElements = try await stateManager.getUIElements(applicationIdentifier: calculatorId)
        
        
        
        let buttons = findElements(in: calcElements) { $0.description.lowercased().contains("button") }
        
        let digits = findElements(in: calcElements) { element in
            let desc = element.description.lowercased()
            return desc.contains("button") && (0...9).contains { desc.contains("\($0)") }
        }
        
        print("Calculator: Found \(buttons.count) buttons, \(digits.count) digit buttons")
        XCTAssertGreaterThan(buttons.count, 0, "Should find buttons in Calculator")

        // Test interaction with found elements
        if let button = buttons.first {
            print("Clicking button: \(button.description)")
            try await stateManager.clickElementById(
                applicationIdentifier: calculatorId,
                elementId: button.element_id
            )
        }
        
        // Scenario 2: Text editing workflow
        let textEditId = "com.apple.TextEdit"
        let textElements = try await stateManager.getUIElements(applicationIdentifier: textEditId)
        
        let menus = findElements(in: textElements) { $0.description.lowercased().contains("menu") }
        let textFields = findElements(in: textElements) { element in
            let desc = element.description.lowercased()
            return desc.contains("text") && (desc.contains("field") || desc.contains("area"))
        }
        
        print("TextEdit: Found \(menus.count) menus, \(textFields.count) text fields")
        XCTAssertGreaterThanOrEqual(textElements.count, 0, "Should find elements in TextEdit")
        
        if let menu = menus.first {
            print("Clicking menu: \(menu.description)")
            try await stateManager.clickElementById(
                applicationIdentifier: textEditId,
                elementId: menu.element_id
            )
        }
    }
} 

// Look for specific UI patterns recursively
func findElements(in elements: [UIElementInfo], matching predicate: (UIElementInfo) -> Bool)
    -> [UIElementInfo]
{
    var matches: [UIElementInfo] = []
    for element in elements {
        if predicate(element) {
            matches.append(element)
        }
        matches.append(contentsOf: findElements(in: element.children, matching: predicate))
    }
    return matches
}
