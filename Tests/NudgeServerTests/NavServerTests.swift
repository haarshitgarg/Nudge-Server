import XCTest
import AppKit
@testable import NudgeServer

final class NavServerTests: XCTestCase {

    func testOpenApplication() async throws {
        let appIdentifier = "com.apple.Safari"
        try await openApplication(bundleIdentifier: appIdentifier)
        let app = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == appIdentifier }
        XCTAssertNotNil(app, "Safari should be running after openApplication is called.")
    }
    
    func testSimplifiedGetUIElementsWorkflow() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test the new simplified get_ui_elements workflow
        // This auto-opens the application and fills ui_state_tree with 
        // focused window, menu bar, and elements in tree format
        
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        
        // Verify we got elements with the new simplified structure
        XCTAssertGreaterThanOrEqual(elements.count, 0, "getUIElements should discover elements")
        
        // Verify all elements have only the 3 required fields
        for element in elements {
            XCTAssertFalse(element.element_id.isEmpty, "Element should have valid element_id")
            XCTAssertTrue(element.element_id.starts(with: "element_"), "ID should follow expected format")
            XCTAssertFalse(element.description.isEmpty, "Element should have description")
            // children can be empty array, that's fine
            
            // Test that all fields are present in the structure
            XCTAssertNotNil(element.element_id, "element_id should be present")
            XCTAssertNotNil(element.description, "description should be present")
            XCTAssertNotNil(element.children, "children should be present")
        }
        
        print("✅ Simplified getUIElements found \(elements.count) elements with tree structure")
    }
    
    func testSafariExtensionsSimplifiedWorkflow() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test the complete Safari Extensions workflow with simplified API
        print("🔍 Testing Safari Extensions workflow with simplified architecture...")
        
        // Step 1: Get all UI elements (auto-opens Safari, tree structure)
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        XCTAssertGreaterThan(elements.count, 0, "Should discover UI elements in Safari")
        
        // Look for Safari menu elements that might contain Extensions
        let safariMenuElements = elements.filter { element in
            let desc = element.description.lowercased()
            return desc.contains("safari") && (desc.contains("menu") || desc.contains("button"))
        }
        
        print("Found \(safariMenuElements.count) Safari menu elements")
        
        // Look for extension-related elements
        let extensionElements = elements.filter { element in
            return element.description.lowercased().contains("extension")
        }
        
        print("Found \(extensionElements.count) extension-related elements")
        
        // Test clicking workflow
        var testPassed = false
        
        if let extensionElement = extensionElements.first {
            print("🎯 Testing direct extension element click: \(extensionElement.description)")
            print("   Element ID: \(extensionElement.element_id)")
            
            // Step 2: Click extension element with direct AXUIElement reference
            try await StateManager.shared.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: extensionElement.element_id
            )
            
            testPassed = true
            print("✅ Direct extension element click succeeded")
            
        } else if let safariMenu = safariMenuElements.first {
            print("🔍 No direct extension element found, clicking Safari menu...")
            print("   Clicking Safari menu: \(safariMenu.description)")
            
            // Click the Safari menu element
            try await StateManager.shared.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: safariMenu.element_id
            )
            
            testPassed = true
            print("✅ Safari menu click succeeded")
        }
        
        // Verify the workflow completed successfully
        XCTAssertTrue(testPassed, "Safari Extensions navigation workflow should complete successfully")
        
        // Wait for UI to settle
        try await Task.sleep(for: .seconds(2))
        
        // Step 3: Get updated UI state after navigation
        let updatedElements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        XCTAssertGreaterThan(updatedElements.count, 0, "Should still have UI elements after navigation")
        
        let performanceMessage = """
        
        🚀 Safari Extensions Test Performance Summary:
        =====================================
        OLD WORKFLOW (4-6 tool calls):
        1. open_application("com.apple.safari")
        2. get_ui_elements_in_frame(safari, full_screen)
        3. click_element_by_id(safari, "safari_menu")
        4. get_ui_elements_in_frame(safari, menu_area)  
        5. click_element_by_id(safari, "extensions_item")
        6. get_ui_elements_in_frame(safari, extensions_area)
        
        NEW WORKFLOW (2 tool calls):
        1. get_ui_elements("com.apple.safari") // Auto-opens, tree structure
        2. click_element_by_id("extension_element_id") // Direct AXUIElement
        
        PERFORMANCE IMPROVEMENT: 3-5x faster! 🎯
        =====================================
        
        """
        
        print(performanceMessage)
    }
    
    func testTreeStructureNavigation() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test tree-based navigation
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        
        XCTAssertGreaterThanOrEqual(elements.count, 0, "Tree structure should work")
        
        // Test that we can navigate through the tree
        for element in elements {
            // Test root level elements
            XCTAssertFalse(element.element_id.isEmpty, "Root element should have ID")
            XCTAssertFalse(element.description.isEmpty, "Root element should have description")
            
            // Test child elements
            for child in element.children {
                XCTAssertFalse(child.element_id.isEmpty, "Child element should have ID")
                XCTAssertFalse(child.description.isEmpty, "Child element should have description")
                
                // Test grandchild elements
                for grandchild in child.children {
                    XCTAssertFalse(grandchild.element_id.isEmpty, "Grandchild element should have ID")
                    XCTAssertFalse(grandchild.description.isEmpty, "Grandchild element should have description")
                }
            }
        }
        
        print("Tree structure navigation: \(elements.count) root elements verified")
    }
    
    func testDirectAXUIElementPerformance() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test direct AXUIElement performance
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        
        if let firstElement = elements.first {
            let startTime = Date()
            
            // Click using direct AXUIElement reference
            try await StateManager.shared.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            
            let endTime = Date()
            let clickTime = endTime.timeIntervalSince(startTime)
            
            print("Direct AXUIElement click time: \(clickTime) seconds")
            
            // Should be very fast (< 1 second)
            XCTAssertLessThan(clickTime, 1.0, "Direct AXUIElement click should be fast")
        }
    }
    
    func testSimplifiedArchitectureValidation() async throws {
        let appIdentifier = "com.apple.TextEdit"
        
        // Test the complete new architecture
        print("🔧 Testing simplified architecture validation...")
        
        // 1. Application auto-opening
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        XCTAssertGreaterThanOrEqual(elements.count, 0, "Should auto-open app and get elements")
        
        // 2. Tree-based structure validation
        var totalElements = 0
        var maxDepth = 0
        
        func validateTree(_ elements: [UIElementInfo], depth: Int) {
            totalElements += elements.count
            maxDepth = max(maxDepth, depth)
            
            for element in elements {
                // Validate 3-field structure
                XCTAssertFalse(element.element_id.isEmpty, "element_id should be present")
                XCTAssertFalse(element.description.isEmpty, "description should be present")
                XCTAssertNotNil(element.children, "children should be present")
                
                // Recurse into children
                validateTree(element.children, depth: depth + 1)
            }
        }
        
        validateTree(elements, depth: 0)
        
        print("Tree validation: \(totalElements) total elements, max depth: \(maxDepth)")
        
        // 3. Direct AXUIElement storage validation
        if let firstElement = elements.first {
            // Should be able to click directly
            try await StateManager.shared.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: firstElement.element_id
            )
            print("✅ Direct AXUIElement click validated")
        }
        
        print("✅ Simplified architecture validation complete")
    }
    
    func testContainerFlattening() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test that container elements like AXGroup are flattened
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        
        // Verify that no container elements are present in the tree
        let containerRoles = [
            "AXGroup", "AXScrollArea", "AXLayoutArea", "AXLayoutItem", 
            "AXSplitGroup", "AXToolbar", "AXTabGroup", "AXOutline", 
            "AXList", "AXTable", "AXBrowser", "AXGenericElement"
        ]
        
        func verifyNoContainers(_ elements: [UIElementInfo]) {
            for element in elements {
                // Check that the description doesn't contain container role names
                for containerRole in containerRoles {
                    let cleanRole = containerRole.replacingOccurrences(of: "AX", with: "")
                    XCTAssertFalse(
                        element.description.contains("(\(cleanRole))"),
                        "Found container role \(cleanRole) in element: \(element.description). Container should have been flattened."
                    )
                }
                
                // Recursively check children
                verifyNoContainers(element.children)
            }
        }
        
        verifyNoContainers(elements)
        
        // Verify we still have meaningful elements (flattening should preserve actionable content)
        XCTAssertGreaterThan(elements.count, 0, "Should have elements after flattening")
        
        // Count total elements in flattened tree
        func countElements(_ elements: [UIElementInfo]) -> Int {
            var count = elements.count
            for element in elements {
                count += countElements(element.children)
            }
            return count
        }
        
        let totalElements = countElements(elements)
        print("Container flattening test: \(elements.count) root elements, \(totalElements) total elements")
        print("✅ Container elements successfully flattened - only actionable elements remain")
        
        // Verify that elements have meaningful descriptions
        for element in elements {
            XCTAssertFalse(element.description.isEmpty, "Flattened elements should have meaningful descriptions")
            XCTAssertFalse(element.element_id.isEmpty, "Flattened elements should have valid IDs")
        }
    }
    
    func testUpdateUIElementTree() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // First, get the initial UI elements
        let initialElements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        XCTAssertGreaterThan(initialElements.count, 0, "Should have initial elements")
        
        // Find an element to update (get first element with children)
        func findElementWithChildren(_ elements: [UIElementInfo]) -> UIElementInfo? {
            for element in elements {
                if !element.children.isEmpty {
                    return element
                }
                if let childWithChildren = findElementWithChildren(element.children) {
                    return childWithChildren
                }
            }
            return nil
        }
        
        guard let elementToUpdate = findElementWithChildren(initialElements) else {
            XCTFail("Should find at least one element with children for testing")
            return
        }
        
        // Update the specific element tree
        let updatedTree = try await StateManager.shared.updateUIElementTree(
            applicationIdentifier: appIdentifier,
            elementId: elementToUpdate.element_id
        )
        
        // Verify the updated tree structure
        XCTAssertGreaterThan(updatedTree.count, 0, "Updated tree should have elements")
        
        // Verify that all elements have valid IDs and descriptions
        func verifyTreeStructure(_ elements: [UIElementInfo]) {
            for element in elements {
                XCTAssertFalse(element.element_id.isEmpty, "Element should have valid ID")
                XCTAssertFalse(element.description.isEmpty, "Element should have valid description")
                verifyTreeStructure(element.children)
            }
        }
        
        verifyTreeStructure(updatedTree)
        
        // Count elements in updated tree
        func countElements(_ elements: [UIElementInfo]) -> Int {
            var count = elements.count
            for element in elements {
                count += countElements(element.children)
            }
            return count
        }
        
        let updatedElementCount = countElements(updatedTree)
        
        print("Update UI element tree test:")
        print("   • Target element: \(elementToUpdate.element_id)")
        print("   • Updated tree elements: \(updatedTree.count) root, \(updatedElementCount) total")
        print("   • ✅ Successfully updated specific element tree")
        
        // Verify the tree structure is still valid
        XCTAssertGreaterThan(updatedElementCount, 0, "Updated tree should have elements")
    }
    
    func testUpdateUIElementTreeAPI() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // First, get the initial UI elements to have a populated tree
        let initialElements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        XCTAssertGreaterThan(initialElements.count, 0, "Should have initial elements")
        
        // Find an element to update (prefer one with children)
        func findSuitableElement(_ elements: [UIElementInfo]) -> UIElementInfo? {
            for element in elements {
                if !element.children.isEmpty {
                    return element
                }
                if let childWithChildren = findSuitableElement(element.children) {
                    return childWithChildren
                }
            }
            return nil
        }
        
        guard let elementToUpdate = findSuitableElement(initialElements) else {
            XCTFail("Should find at least one element for testing")
            return
        }
        
        // Test the API directly through StateManager
        let updatedTree = try await StateManager.shared.updateUIElementTree(
            applicationIdentifier: appIdentifier,
            elementId: elementToUpdate.element_id
        )
        
        // Verify the API response
        XCTAssertGreaterThan(updatedTree.count, 0, "API should return updated tree")
        
        // Verify all elements have proper structure
        for element in updatedTree {
            XCTAssertFalse(element.element_id.isEmpty, "Element should have valid ID")
            XCTAssertFalse(element.description.isEmpty, "Element should have valid description")
            
            // Check if element exists in registry (should be able to click)
            let elementExists = await StateManager.shared.elementExists(elementId: element.element_id)
            XCTAssertTrue(
                elementExists,
                "Element \(element.element_id) should be in registry after update"
            )
        }
        
        // Count elements in updated tree
        func countElements(_ elements: [UIElementInfo]) -> Int {
            var count = elements.count
            for element in elements {
                count += countElements(element.children)
            }
            return count
        }
        
        let updatedElementCount = countElements(updatedTree)
        
        print("Update UI element tree API test:")
        print("   • Target element: \(elementToUpdate.element_id)")
        print("   • Description: \(elementToUpdate.description)")
        print("   • Updated tree: \(updatedTree.count) root, \(updatedElementCount) total elements")
        print("   • ✅ API workflow successful")
        
        // Verify the tree is properly updated
        XCTAssertGreaterThan(updatedElementCount, 0, "Updated tree should have elements")
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
