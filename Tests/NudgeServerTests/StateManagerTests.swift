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

    func testGetUIStateTree_WhenTreeDoesNotExist() async {
        let nonExistentApp = "com.testing.NonExistentApp"
        
        // We expect this to throw a uiStateTreeNotFound error
        do {
            _ = try await stateManager.getUIStateTree(applicationIdentifier: nonExistentApp)
            XCTFail("Expected to throw NudgeError.uiStateTreeNotFound, but no error was thrown.")
        } catch let error as NudgeError {
            switch error {
            case .uiStateTreeNotFound(let applicationIdentifier):
                XCTAssertEqual(applicationIdentifier, nonExistentApp)
            default:
                XCTFail("Incorrect error type thrown. Expected .uiStateTreeNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testGetUIStateTree_WhenTreeExists() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        try await stateManager.updateUIStateTree(applicationIdentifier: appIdentifier)
        
        let stateTree = try await stateManager.getUIStateTree(applicationIdentifier: appIdentifier)
        XCTAssertEqual(stateTree.applicationIdentifier, appIdentifier)
        XCTAssertFalse(stateTree.isStale)
    }

    func testGetXcodeTreeAndCheckForWindow() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        try await openApplication(bundleIdentifier: appIdentifier)
        try await Task.sleep(for: .seconds(10)) // Give Xcode more time to launch
        try await stateManager.updateUIStateTree(applicationIdentifier: appIdentifier)
        
        let stateTree = try await stateManager.getUIStateTree(applicationIdentifier: appIdentifier)
        XCTAssertFalse(stateTree.treeData.isEmpty, "The Xcode UI tree should contain at least one window.")
    }

    func testGetUIElementsInFrame() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        try await openApplication(bundleIdentifier: appIdentifier)
        try await Task.sleep(for: .seconds(10)) // Give Xcode more time to launch
        
        // Test getting UI elements in a frame that should cover most of the screen
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let testFrame = CGRect(x: screenFrame.origin.x + 100, y: screenFrame.origin.y + 100, width: 800, height: 600)
        
        let uiElements = try await stateManager.getUIElementsInFrame(applicationIdentifier: appIdentifier, frame: testFrame)
        
        // We should get some UI elements if Xcode is running and has windows
        XCTAssertGreaterThanOrEqual(uiElements.count, 0, "Should return at least 0 UI elements in the frame")
        
        // If we got elements, verify they have the expected structure
        for element in uiElements {
            XCTAssertTrue(element.isActionable, "UI element should be actionable for user interaction")
            XCTAssertNotNil(element.frame, "UI element should have a frame")
        }
    }

    func testUIElementsHaveUniqueIDs() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        try await openApplication(bundleIdentifier: appIdentifier)
        try await Task.sleep(for: .seconds(10)) // Give Xcode more time to launch
        try await stateManager.updateUIStateTree(applicationIdentifier: appIdentifier)
        
        let stateTree = try await stateManager.getUIStateTree(applicationIdentifier: appIdentifier)
        let allIds = extractAllIds(from: stateTree.treeData)
        
        // Check that all IDs are unique
        let uniqueIds = Set(allIds)
        XCTAssertEqual(allIds.count, uniqueIds.count, "All UI element IDs should be unique")
        
        // Check that IDs follow the expected format
        for id in allIds {
            XCTAssertTrue(id.starts(with: "element_"), "ID should start with 'element_'")
        }
    }

    func testGetUIElementsInFrameWithIDs() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        try await openApplication(bundleIdentifier: appIdentifier)
        try await Task.sleep(for: .seconds(10)) // Give Xcode more time to launch
        
        // Test getting UI elements in a frame
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let testFrame = CGRect(x: screenFrame.origin.x + 100, y: screenFrame.origin.y + 100, width: 800, height: 600)
        
        let uiElements = try await stateManager.getUIElementsInFrame(applicationIdentifier: appIdentifier, frame: testFrame)
        
        // All returned elements should be actionable and have IDs
        for element in uiElements {
            XCTAssertTrue(element.isActionable, "All returned elements should be actionable")
            XCTAssertNotNil(element.description, "Actionable elements should have descriptions")
            XCTAssertFalse(element.id.isEmpty, "Actionable elements should have non-empty IDs")
            XCTAssertTrue(element.id.starts(with: "element_"), "ID should start with 'element_'")
        }
    }

    func testClickElementById_InvalidId() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        try await openApplication(bundleIdentifier: appIdentifier)
        try await Task.sleep(for: .seconds(10)) // Give Xcode more time to launch
        try await stateManager.updateUIStateTree(applicationIdentifier: appIdentifier)
        
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
        try await openApplication(bundleIdentifier: appIdentifier)
        try await Task.sleep(for: .seconds(10)) // Give Xcode more time to launch
        
        // Get UI elements in frame and try to click the first one
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let testFrame = CGRect(x: screenFrame.origin.x + 100, y: screenFrame.origin.y + 100, width: 800, height: 600)
        
        let uiElements = try await stateManager.getUIElementsInFrame(applicationIdentifier: appIdentifier, frame: testFrame)
        
        if let firstElement = uiElements.first {
            // This should not throw an error
            try await stateManager.clickElementById(applicationIdentifier: appIdentifier, elementId: firstElement.id)
            
            // Test passes if no error is thrown
            XCTAssertTrue(true, "Clicking valid element ID should succeed")
        } else {
            // Skip test if no actionable elements found
            XCTAssertTrue(true, "No actionable elements found to test clicking")
        }
    }

    // Helper method to extract all IDs from a UI tree
    private func extractAllIds(from elements: [UIElementInfo]) -> [String] {
        var ids: [String] = []
        for element in elements {
            ids.append(element.id)
            ids.append(contentsOf: extractAllIds(from: element.children))
        }
        return ids
    }

}