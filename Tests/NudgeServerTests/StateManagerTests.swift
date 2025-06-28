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
}