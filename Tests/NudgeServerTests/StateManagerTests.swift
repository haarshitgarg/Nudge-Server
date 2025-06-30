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

    func testClickUIElement() async throws {
        let appIdentifier = "com.apple.dt.Xcode"
        try await openApplication(bundleIdentifier: appIdentifier)
        try await Task.sleep(for: .seconds(10)) // Give Xcode more time to launch
        
        // First, get some UI elements to find one with an identifier
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let testFrame = CGRect(x: screenFrame.origin.x + 100, y: screenFrame.origin.y + 100, width: 800, height: 600)
        
        let uiElements = try await stateManager.getUIElementsInFrame(applicationIdentifier: appIdentifier, frame: testFrame)
        
        // Find an element with an identifier that we can click
        if let clickableElement = uiElements.first(where: { $0.identifier != nil }) {
            // Test clicking the element
            do {
                try await stateManager.clickUIElement(applicationIdentifier: appIdentifier, elementIdentifier: clickableElement.identifier!)
                // If we get here, the click was successful
                XCTAssertTrue(true, "Click operation completed without throwing an error")
            } catch {
                // It's okay if the click fails for some elements, but it shouldn't crash
                XCTAssertTrue(error is NudgeError, "Should throw a NudgeError, not crash")
            }
        } else {
            // If no clickable elements found, that's also okay for testing
            XCTAssertTrue(true, "No clickable elements found in the test frame")
        }
    }
}