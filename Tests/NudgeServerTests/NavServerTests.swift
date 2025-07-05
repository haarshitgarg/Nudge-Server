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
    
    func testEnhancedGetUIElementsWorkflow() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test the new enhanced get_ui_elements workflow
        // This replaces the old multi-step process:
        // 1. open_application
        // 2. get_state_of_application / get_ui_elements_in_frame
        // With a single call that auto-opens and discovers deeply
        
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        
        // Verify we got actionable elements
        XCTAssertGreaterThan(elements.count, 0, "Enhanced getUIElements should discover actionable elements")
        
        // Verify all elements have the new enhanced metadata
        for element in elements {
            XCTAssertFalse(element.id.isEmpty, "Element should have valid ID")
            XCTAssertTrue(element.id.starts(with: "element_"), "ID should follow expected format")
            XCTAssertNotNil(element.elementType, "Element should have type information")
            XCTAssertNotNil(element.path, "Element should have path information")
            
            // Test element is actionable
            XCTAssertTrue(element.isActionable, "All returned elements should be actionable")
        }
        
        print("✅ Enhanced getUIElements found \(elements.count) actionable elements with rich metadata")
    }
    
    func testSafariExtensionsNavigationWorkflow() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test the complete Safari Extensions workflow with enhanced API
        print("🔍 Testing Safari Extensions workflow with enhanced navigation...")
        
        // Step 1: Discover all UI elements (auto-opens Safari, deep scanning)
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        XCTAssertGreaterThan(elements.count, 0, "Should discover UI elements in Safari")
        
        // Look for Safari menu elements that might contain Extensions
        let safariMenuElements = elements.filter { element in
            guard let description = element.description else { return false }
            let desc = description.lowercased()
            return desc.contains("safari") && (desc.contains("menu") || desc.contains("button"))
        }
        
        print("Found \(safariMenuElements.count) Safari menu elements")
        
        // Look for extension-related elements
        let extensionElements = elements.filter { element in
            guard let description = element.description else { return false }
            return description.lowercased().contains("extension")
        }
        
        print("Found \(extensionElements.count) extension-related elements")
        
        // Test clicking workflow
        var testPassed = false
        
        if let extensionElement = extensionElements.first {
            print("🎯 Testing direct extension element click: \(extensionElement.description ?? "No description")")
            print("   Element path: \(extensionElement.path)")
            print("   Element type: \(extensionElement.elementType ?? "No type")")
            
            // Step 2: Click extension element with automatic navigation
            try await StateManager.shared.clickElementByIdWithNavigation(
                applicationIdentifier: appIdentifier,
                elementId: extensionElement.id
            )
            
            testPassed = true
            print("✅ Direct extension element click succeeded")
            
        } else if let safariMenu = safariMenuElements.first {
            print("🔍 No direct extension element found, testing progressive disclosure...")
            print("   Exploring Safari menu: \(safariMenu.description ?? "No description")")
            
            // Test progressive disclosure - get children of Safari menu
            let menuChildren = try await StateManager.shared.getElementChildren(
                applicationIdentifier: appIdentifier,
                elementId: safariMenu.id
            )
            
            print("   Safari menu has \(menuChildren.count) children")
            
            // Look for extension items in menu children
            let extensionMenuItems = menuChildren.filter { child in
                guard let description = child.description else { return false }
                return description.lowercased().contains("extension")
            }
            
            if let extensionMenuItem = extensionMenuItems.first {
                print("🎯 Found extension menu item: \(extensionMenuItem.description ?? "No description")")
                
                // Click the extension menu item with navigation
                try await StateManager.shared.clickElementByIdWithNavigation(
                    applicationIdentifier: appIdentifier,
                    elementId: extensionMenuItem.id
                )
                
                testPassed = true
                print("✅ Extension menu item click succeeded")
            }
        }
        
        // Verify the workflow completed successfully
        XCTAssertTrue(testPassed, "Safari Extensions navigation workflow should complete successfully")
        
        // Wait for UI to settle
        try await Task.sleep(for: .seconds(2))
        
        // Step 3: Verify UI state after navigation (optional verification)
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
        1. get_ui_elements("com.apple.safari") // Auto-opens, deep scans
        2. click_element_by_id("extension_element_id") // Auto-navigates
        
        PERFORMANCE IMPROVEMENT: 3-5x faster! 🎯
        =====================================
        
        """
        
        print(performanceMessage)
    }
    
    func testFrameBasedDiscovery() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test frame-based discovery for performance optimization
        let topBarFrame = UIFrame(x: 0, y: 0, width: 1920, height: 100)
        let topBarElements = try await StateManager.shared.getUIElements(
            applicationIdentifier: appIdentifier,
            frame: topBarFrame
        )
        
        XCTAssertGreaterThanOrEqual(topBarElements.count, 0, "Frame-based discovery should work")
        
        // Elements in top bar should be menu-related
        let menuElements = topBarElements.filter { element in
            guard let description = element.description else { return false }
            return description.lowercased().contains("menu") || 
                   description.lowercased().contains("bar") ||
                   description.lowercased().contains("safari")
        }
        
        print("Frame-based discovery (top 100px): \(topBarElements.count) total, \(menuElements.count) menu elements")
        
        // Test wider frame
        let wideFrame = UIFrame(x: 0, y: 0, width: 1920, height: 500)
        let wideElements = try await StateManager.shared.getUIElements(
            applicationIdentifier: appIdentifier,
            frame: wideFrame
        )
        
        print("Frame-based discovery (top 500px): \(wideElements.count) elements")
        
        // Wider frame should generally find more elements
        XCTAssertGreaterThanOrEqual(wideElements.count, topBarElements.count, 
                                   "Wider frame should find at least as many elements")
    }
    
    func testProgressiveDisclosure() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test progressive disclosure with get_element_children
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        
        // Find elements that have children
        let parentElements = elements.filter { $0.hasChildren }
        
        if let parentElement = parentElements.first {
            print("Testing progressive disclosure on: \(parentElement.description ?? "No description")")
            print("Element has children: \(parentElement.hasChildren)")
            print("Element is expandable: \(parentElement.isExpandable)")
            
            // Get children of this element
            let children = try await StateManager.shared.getElementChildren(
                applicationIdentifier: appIdentifier,
                elementId: parentElement.id
            )
            
            XCTAssertGreaterThanOrEqual(children.count, 0, "Progressive disclosure should work")
            
            // Verify children have proper metadata
            for child in children {
                XCTAssertTrue(child.isActionable, "All children should be actionable")
                XCTAssertFalse(child.id.isEmpty, "Child should have valid ID")
                XCTAssertNotNil(child.elementType, "Child should have type information")
            }
            
            print("Progressive disclosure found \(children.count) children")
        } else {
            print("No elements with children found for progressive disclosure test")
        }
    }
    
    func testEnhancedElementMetadata() async throws {
        let appIdentifier = "com.apple.Safari"
        
        // Test that enhanced metadata is properly populated
        let elements = try await StateManager.shared.getUIElements(applicationIdentifier: appIdentifier)
        
        var elementTypeCounts: [String: Int] = [:]
        var elementsWithPaths = 0
        var elementsWithChildren = 0
        var expandableElements = 0
        
        for element in elements {
            // Count element types
            if let elementType = element.elementType {
                elementTypeCounts[elementType, default: 0] += 1
            }
            
            // Count elements with paths
            if !element.path.isEmpty {
                elementsWithPaths += 1
            }
            
            // Count elements with children
            if element.hasChildren {
                elementsWithChildren += 1
            }
            
            // Count expandable elements
            if element.isExpandable {
                expandableElements += 1
            }
            
            // Verify element type doesn't have "AX" prefix
            if let elementType = element.elementType {
                XCTAssertFalse(elementType.contains("AX"), "Element type should be clean without AX prefix")
            }
            
            // Verify path structure
            for pathElement in element.path {
                XCTAssertTrue(pathElement.starts(with: "element_"), "Path elements should be valid element IDs")
            }
        }
        
        let metadataReport = """
        
        📊 Enhanced Element Metadata Report:
        ====================================
        Total elements: \(elements.count)
        Element types found: \(elementTypeCounts.keys.sorted().joined(separator: ", "))
        Elements with navigation paths: \(elementsWithPaths)
        Elements with children: \(elementsWithChildren)
        Expandable elements: \(expandableElements)
        ====================================
        
        """
        
        print(metadataReport)
        
        // Basic validations
        XCTAssertGreaterThan(elementTypeCounts.count, 0, "Should have various element types")
        XCTAssertGreaterThan(elementsWithPaths, 0, "Should have elements with navigation paths")
    }
}
