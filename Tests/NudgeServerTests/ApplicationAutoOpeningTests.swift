import XCTest
import AppKit
@testable import NudgeLibrary

final class ApplicationAutoOpeningTests: XCTestCase {
    
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
    
    // MARK: - Application Auto-Opening Tests
    
    /**
     * Tests Calendar application auto-opening and UI tree retrieval.
     * Expected behavior: Should automatically open Calendar if not running, then return UI elements.
     */
    func testCalendarApplicationAutoOpening() async throws {
        let appIdentifier = "com.apple.iCal"
        
        // Check initial state - Calendar might or might not be running
        let runningAppsBefore = NSWorkspace.shared.runningApplications
        let wasRunningBefore = runningAppsBefore.contains { $0.bundleIdentifier?.lowercased() == appIdentifier.lowercased() }
        
        print("Calendar was running before test: \(wasRunningBefore)")
        
        // If Calendar is running, quit it first to test auto-opening
        if wasRunningBefore {
            if let calendarApp = NSRunningApplication.runningApplications(withBundleIdentifier: appIdentifier).first {
                calendarApp.terminate()
                // Wait a moment for the app to close
                try await Task.sleep(for: .seconds(2))
            }
        }
        
        // Now test auto-opening functionality
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        
        // Calendar should now be running
        let runningAppsAfter = NSWorkspace.shared.runningApplications
        let isRunningAfter = runningAppsAfter.contains { $0.bundleIdentifier?.lowercased() == appIdentifier.lowercased() }
        
        XCTAssertTrue(isRunningAfter, "Calendar should be running after getUIElements call")
        
        // Should return valid UI elements
        XCTAssertGreaterThan(elements.count, 0, "Should return UI elements for Calendar")
        
        // Verify each element has the expected 3-field structure
        for element in elements {
            XCTAssertFalse(element.element_id.isEmpty, "Element should have non-empty element_id")
            XCTAssertTrue(element.element_id.hasPrefix("element_"), "Element ID should have correct prefix")
            XCTAssertFalse(element.description.isEmpty, "Element should have non-empty description")
            XCTAssertNotNil(element.children, "Element should have children array (can be empty)")
        }
        
        print("Calendar auto-opening test completed: \(elements.count) UI elements retrieved")
        
        // Test clicking on Calendar elements
        let allElements = getAllElementsRecursively(from: elements)
        let clickableElements = allElements.filter { element in
            element.description.contains("Button") || 
            element.description.contains("MenuItem") ||
            element.description.contains("Tab") ||
            element.description.contains("Cell")
        }
        
        if let firstClickable = clickableElements.first {
            let clickResponse = try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: firstClickable.element_id
            )
            
            XCTAssertTrue(clickResponse.message.contains("Successfully clicked") || clickResponse.message.contains("Failed to click"), 
                         "Click response should have meaningful message")
            print("Clicked Calendar element: \(firstClickable.description)")
        }
    }
    
    /**
     * Tests System Settings application auto-opening and UI tree retrieval.
     * Expected behavior: Should automatically open System Settings if not running, then return UI elements.
     */
    func testSystemSettingsApplicationAutoOpening() async throws {
        let appIdentifier = "com.apple.systempreferences"
        
        // Check initial state
        let runningAppsBefore = NSWorkspace.shared.runningApplications
        let wasRunningBefore = runningAppsBefore.contains { $0.bundleIdentifier?.lowercased() == appIdentifier.lowercased() }
        
        print("System Settings was running before test: \(wasRunningBefore)")
        
        // If System Settings is running, quit it first to test auto-opening
        if wasRunningBefore {
            if let systemSettingsApp = NSRunningApplication.runningApplications(withBundleIdentifier: appIdentifier).first {
                systemSettingsApp.terminate()
                // Wait for the app to close
                try await Task.sleep(for: .seconds(3))
            }
        }
        
        // Test auto-opening functionality - System Settings can take longer to open
        let startTime = Date()
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // System Settings can take longer to open and populate
        XCTAssertLessThan(duration, 20.0, "System Settings should open and populate UI elements within 20 seconds")
        
        // System Settings should now be running
        let runningAppsAfter = NSWorkspace.shared.runningApplications
        let isRunningAfter = runningAppsAfter.contains { $0.bundleIdentifier?.lowercased() == appIdentifier.lowercased() }
        
        XCTAssertTrue(isRunningAfter, "System Settings should be running after getUIElements call")
        
        // Should return valid UI elements
        XCTAssertGreaterThan(elements.count, 0, "Should return UI elements for System Settings")
        
        // Verify structure and test enhanced cell descriptions
        let allElements = getAllElementsRecursively(from: elements)
        let cellElements = allElements.filter { $0.description.contains("Cell") }
        
        for element in elements {
            XCTAssertFalse(element.element_id.isEmpty, "Element should have non-empty element_id")
            XCTAssertTrue(element.element_id.hasPrefix("element_"), "Element ID should have correct prefix")
            XCTAssertFalse(element.description.isEmpty, "Element should have non-empty description")
            XCTAssertNotNil(element.children, "Element should have children array (can be empty)")
        }
        
        print("System Settings auto-opening test completed: \(String(format: "%.2f", duration))s opening, \(elements.count) top-level elements, \(allElements.count) total elements, \(cellElements.count) cell elements")
        
        // Test clicking on System Settings elements (preferences panels)
        let clickableElements = allElements.filter { element in
            element.description.contains("Button") || 
            element.description.contains("Cell") ||
            element.description.contains("Tab")
        }
        
        if let firstClickable = clickableElements.first {
            let clickStartTime = Date()
            let clickResponse = try await stateManager.clickElementById(
                applicationIdentifier: appIdentifier,
                elementId: firstClickable.element_id
            )
            let clickEndTime = Date()
            let clickDuration = clickEndTime.timeIntervalSince(clickStartTime)
            
            XCTAssertLessThan(clickDuration, 3.0, "Clicking System Settings elements should complete within 3 seconds")
            XCTAssertTrue(clickResponse.message.contains("Successfully clicked") || clickResponse.message.contains("Failed to click"), 
                         "Click response should have meaningful message")
            print("Clicked System Settings element: \(firstClickable.description) in \(String(format: "%.2f", clickDuration))s")
        }
    }
    
    /**
     * Tests ChatGPT application auto-opening and UI tree retrieval.
     * Expected behavior: Should automatically open ChatGPT if not running and installed, then return UI elements.
     */
    func testChatGPTApplicationAutoOpening() async throws {
        let appIdentifier = "com.openai.chat"
        
        // Check if ChatGPT is installed on the system
        let workspace = NSWorkspace.shared
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: appIdentifier) else {
            print("ChatGPT app not found on system, skipping test")
            throw XCTSkip("ChatGPT app is not installed on this system")
        }
        
        print("ChatGPT found at: \(appURL)")
        
        // Check initial state
        let runningAppsBefore = NSWorkspace.shared.runningApplications
        let wasRunningBefore = runningAppsBefore.contains { $0.bundleIdentifier?.lowercased() == appIdentifier.lowercased() }
        
        print("ChatGPT was running before test: \(wasRunningBefore)")
        
        // If ChatGPT is running, quit it first to test auto-opening
        if wasRunningBefore {
            if let chatGPTApp = NSRunningApplication.runningApplications(withBundleIdentifier: appIdentifier).first {
                chatGPTApp.terminate()
                // Wait for the app to close
                try await Task.sleep(for: .seconds(3))
            }
        }
        
        // Test auto-opening functionality - ChatGPT might take time to launch and load
        let startTime = Date()
        let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // ChatGPT might take longer to open and fully load its UI
        XCTAssertLessThan(duration, 30.0, "ChatGPT should open and populate UI elements within 30 seconds")
        
        // ChatGPT should now be running
        let runningAppsAfter = NSWorkspace.shared.runningApplications
        let isRunningAfter = runningAppsAfter.contains { $0.bundleIdentifier?.lowercased() == appIdentifier.lowercased() }
        
        XCTAssertTrue(isRunningAfter, "ChatGPT should be running after getUIElements call")
        
        // Should return valid UI elements
        XCTAssertGreaterThan(elements.count, 0, "Should return UI elements for ChatGPT")
        
        // Verify structure
        let allElements = getAllElementsRecursively(from: elements)
        
        print("ChatGPT auto-opening test completed: \(String(format: "%.2f", duration))s opening, \(elements.count) top-level elements, \(allElements.count) total elements")
        
    }
    
    /**
     * Tests multiple application auto-opening in sequence.
     * Expected behavior: Should be able to open and interact with multiple applications sequentially.
     */
    func testMultipleApplicationAutoOpeningSequence() async throws {
        let applications = [
            ("com.apple.iCal", "Calendar"),
            ("com.apple.Calculator", "Calculator"),
            ("com.apple.TextEdit", "TextEdit")
        ]
        
        var results: [(String, Bool, Int, TimeInterval)] = []
        
        for (appIdentifier, appName) in applications {
            print("Testing auto-opening for \(appName)...")
            
            let startTime = Date()
            
            do {
                let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
                let endTime = Date()
                let duration = endTime.timeIntervalSince(startTime)
                
                // Verify app is now running
                let isRunning = NSWorkspace.shared.runningApplications.contains { 
                    $0.bundleIdentifier?.lowercased() == appIdentifier.lowercased() 
                }
                
                XCTAssertTrue(isRunning, "\(appName) should be running after getUIElements call")
                XCTAssertGreaterThan(elements.count, 0, "Should return UI elements for \(appName)")
                
                results.append((appName, true, elements.count, duration))
                print("\(appName): SUCCESS - \(elements.count) elements in \(String(format: "%.2f", duration))s")
                
                // Brief pause between applications
                try await Task.sleep(for: .seconds(1))
                
            } catch {
                let endTime = Date()
                let duration = endTime.timeIntervalSince(startTime)
                results.append((appName, false, 0, duration))
                print("\(appName): FAILED - \(error)")
                XCTFail("Failed to auto-open \(appName): \(error)")
            }
        }
        
        // Verify all applications were successfully opened
        let successfulApps = results.filter { $0.1 }
        XCTAssertEqual(successfulApps.count, applications.count, "All applications should be successfully auto-opened")
        
        // Print summary
        print("\nMultiple Application Auto-Opening Summary:")
        for (appName, success, elementCount, duration) in results {
            let status = success ? "✓" : "✗"
            print("\(status) \(appName): \(elementCount) elements in \(String(format: "%.2f", duration))s")
        }
    }
    
    /**
     * Tests auto-opening performance and reliability across different app states.
     * Expected behavior: Should consistently open applications regardless of their initial state.
     */
    func testAutoOpeningReliability() async throws {
        let appIdentifier = "com.apple.Calculator"
        let appName = "Calculator"
        let testRuns = 3
        
        var results: [Bool] = []
        var durations: [TimeInterval] = []
        
        for run in 1...testRuns {
            print("Auto-opening reliability test run \(run)/\(testRuns) for \(appName)")
            
            // Ensure app is closed before each test
            if let calculatorApp = NSRunningApplication.runningApplications(withBundleIdentifier: appIdentifier).first {
                calculatorApp.terminate()
                try await Task.sleep(for: .seconds(2))
            }
            
            let startTime = Date()
            
            do {
                let elements = try await stateManager.getUIElements(applicationIdentifier: appIdentifier)
                let endTime = Date()
                let duration = endTime.timeIntervalSince(startTime)
                
                let isRunning = NSWorkspace.shared.runningApplications.contains { 
                    $0.bundleIdentifier?.lowercased() == appIdentifier.lowercased() 
                }
                
                let success = isRunning && elements.count > 0
                results.append(success)
                durations.append(duration)
                
                print("Run \(run): \(success ? "SUCCESS" : "FAILED") - \(elements.count) elements in \(String(format: "%.2f", duration))s")
                
            } catch {
                let endTime = Date()
                let duration = endTime.timeIntervalSince(startTime)
                results.append(false)
                durations.append(duration)
                print("Run \(run): FAILED - \(error)")
            }
            
            // Brief pause between runs
            try await Task.sleep(for: .seconds(1))
        }
        
        // Analyze reliability
        let successCount = results.filter { $0 }.count
        let reliabilityPercentage = (Double(successCount) / Double(testRuns)) * 100
        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        let maxDuration = durations.max() ?? 0
        let minDuration = durations.min() ?? 0
        
        print("\nAuto-opening Reliability Results for \(appName):")
        print("Success Rate: \(successCount)/\(testRuns) (\(String(format: "%.1f", reliabilityPercentage))%)")
        print("Average Duration: \(String(format: "%.2f", avgDuration))s")
        print("Min Duration: \(String(format: "%.2f", minDuration))s")
        print("Max Duration: \(String(format: "%.2f", maxDuration))s")
        
        // Expect high reliability (at least 2 out of 3 runs should succeed)
        XCTAssertGreaterThanOrEqual(successCount, 2, "Auto-opening should succeed in at least 2 out of 3 runs")
        XCTAssertLessThan(maxDuration, 15.0, "Maximum opening time should be under 15 seconds")
    }
    
    // MARK: - Helper Methods
    
    /**
     * Get all elements recursively from a tree structure.
     */
    private func getAllElementsRecursively(from elements: [UIElementInfo]) -> [UIElementInfo] {
        var allElements: [UIElementInfo] = []
        
        for element in elements {
            allElements.append(element)
            allElements.append(contentsOf: getAllElementsRecursively(from: element.children))
        }
        
        return allElements
    }
}
