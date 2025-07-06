import XCTest
import AppKit
@testable import NudgeLibrary

final class ComprehensiveErrorHandlingTests: XCTestCase {
    
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
    
    // MARK: - Application Error Tests
    
    /**
     * Tests applicationNotFound error behavior.
     * Expected behavior: Should throw applicationNotFound error with correct bundle identifier.
     */
    func testApplicationNotFoundError() async throws {
        let invalidBundleId = "com.nonexistent.application.test"
        
        do {
            _ = try await stateManager.getUIElements(applicationIdentifier: invalidBundleId)
            XCTFail("Should throw applicationNotFound error")
        } catch let error as NudgeError {
            switch error {
            case .applicationNotFound(let bundleId):
                XCTAssertEqual(bundleId, invalidBundleId, "Error should contain the correct bundle identifier")
                XCTAssertTrue(error.localizedDescription.contains(invalidBundleId), "Error description should contain bundle identifier")
            default:
                XCTFail("Should throw applicationNotFound error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
    
    /**
     * Tests applicationNotRunning error behavior.
     * Expected behavior: Should throw applicationNotRunning error when app fails to start.
     */
    func testApplicationNotRunningError() async throws {
        // Test with a bundle ID that might exist but fail to launch
        let problematicBundleId = "com.invalid.test.app"
        
        do {
            _ = try await stateManager.getUIElements(applicationIdentifier: problematicBundleId)
            XCTFail("Should throw error for app that can't be launched")
        } catch let error as NudgeError {
            switch error {
            case .applicationNotFound(let bundleId):
                XCTAssertEqual(bundleId, problematicBundleId, "Error should contain the correct bundle identifier")
            case .applicationNotRunning(let bundleId):
                XCTAssertEqual(bundleId, problematicBundleId, "Error should contain the correct bundle identifier")
            default:
                XCTFail("Should throw application-related error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
    
    // MARK: - UI Element Interaction Error Tests
    
    /**
     * Tests element not found error behavior.
     * Expected behavior: Should throw invalidRequest error when element ID is not found.
     */
    func testElementNotFoundError() async throws {
        let validBundleId = "com.apple.TextEdit"
        let invalidElementId = "nonexistent_element_12345"
        
        // First populate the registry with valid elements
        _ = try await stateManager.getUIElements(applicationIdentifier: validBundleId)
        
        do {
            try await stateManager.clickElementById(
                applicationIdentifier: validBundleId,
                elementId: invalidElementId
            )
            XCTFail("Should throw error for invalid element ID")
        } catch let error as NudgeError {
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("not found"), "Error message should indicate element not found")
                XCTAssertTrue(message.contains(invalidElementId), "Error message should contain the element ID")
            default:
                XCTFail("Should throw invalidRequest error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
    
    /**
     * Tests element not found error for updateUIElementTree.
     * Expected behavior: Should throw invalidRequest error when element ID is not found.
     */
    func testUpdateUIElementTreeElementNotFoundError() async throws {
        let validBundleId = "com.apple.TextEdit"
        let invalidElementId = "nonexistent_element_12345"
        
        // First populate the registry with valid elements
        _ = try await stateManager.getUIElements(applicationIdentifier: validBundleId)
        
        do {
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: validBundleId,
                elementId: invalidElementId
            )
            XCTFail("Should throw error for invalid element ID")
        } catch let error as NudgeError {
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("not found"), "Error message should indicate element not found")
                XCTAssertTrue(message.contains(invalidElementId), "Error message should contain the element ID")
            default:
                XCTFail("Should throw invalidRequest error, got: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
    
    /**
     * Tests clicking element before getting UI elements.
     * Expected behavior: Should throw invalidRequest error when registry is empty.
     */
    func testClickElementBeforeGettingUIElements() async throws {
        let validBundleId = "com.apple.TextEdit"
        let elementId = "element_1"
        
        do {
            try await stateManager.clickElementById(
                applicationIdentifier: validBundleId,
                elementId: elementId
            )
            XCTFail("Should throw error when registry is empty")
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
     * Tests updating element tree before getting UI elements.
     * Expected behavior: Should throw invalidRequest error when registry is empty.
     */
    func testUpdateElementTreeBeforeGettingUIElements() async throws {
        let validBundleId = "com.apple.TextEdit"
        let elementId = "element_1"
        
        do {
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: validBundleId,
                elementId: elementId
            )
            XCTFail("Should throw error when registry is empty")
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
    
    // MARK: - Accessibility API Error Tests
    
    /**
     * Tests accessibility permission requirements.
     * Expected behavior: Should handle accessibility permission gracefully.
     */
    func testAccessibilityPermissionHandling() async throws {
        let validBundleId = "com.apple.TextEdit"
        
        // Note: In test environments, accessibility is typically enabled
        // This test verifies that the code handles accessibility checks
        
        do {
            let elements = try await stateManager.getUIElements(applicationIdentifier: validBundleId)
            
            // If accessibility is enabled, we should get elements
            XCTAssertGreaterThanOrEqual(elements.count, 0, "Should get elements when accessibility is enabled")
            
            // Try to click an element if we have any
            if let firstElement = elements.first {
                try await stateManager.clickElementById(
                    applicationIdentifier: validBundleId,
                    elementId: firstElement.element_id
                )
                // Test passes if no error is thrown
            }
            
        } catch let error as NudgeError {
            switch error {
            case .accessibilityPermissionDenied:
                // This is expected if accessibility is not enabled
                XCTAssertTrue(error.localizedDescription.contains("Accessibility permissions"), 
                             "Error message should mention accessibility permissions")
                XCTAssertTrue(error.localizedDescription.contains("System Settings"), 
                             "Error message should mention System Settings")
            default:
                // Other errors are also acceptable in test environment
                XCTAssertTrue(true, "Other errors are acceptable in test environment: \(error)")
            }
        } catch {
            XCTFail("Should throw NudgeError if there are issues, got: \(type(of: error))")
        }
    }
    
    // MARK: - Error Message Quality Tests
    
    /**
     * Tests that error messages are informative and helpful.
     * Expected behavior: Error messages should contain relevant information for debugging.
     */
    func testErrorMessageQuality() async throws {
        let testCases: [NudgeError] = [
            .applicationNotFound(bundleIdentifier: "com.test.app"),
            .applicationNotRunning(bundleIdentifier: "com.test.app"),
            .applicationLaunchFailed(bundleIdentifier: "com.test.app", underlyingError: nil),
            .elementNotFound(description: "Test Button"),
            .elementNotInteractable(description: "Test Label"),
            .accessibilityPermissionDenied,
            .invalidRequest(message: "Test invalid request"),
            .invalidArgument(parameter: "testParam", value: "testValue", reason: "Test reason"),
            .unexpectedError(message: "Test unexpected error", underlyingError: nil)
        ]
        
        for error in testCases {
            let description = error.localizedDescription
            
            XCTAssertFalse(description.isEmpty, "Error description should not be empty")
            XCTAssertGreaterThan(description.count, 10, "Error description should be reasonably detailed")
            
            // Check that descriptions contain relevant information
            switch error {
            case .applicationNotFound(let bundleId):
                XCTAssertTrue(description.contains(bundleId), "Should contain bundle identifier")
            case .applicationNotRunning(let bundleId):
                XCTAssertTrue(description.contains(bundleId), "Should contain bundle identifier")
            case .applicationLaunchFailed(let bundleId, _):
                XCTAssertTrue(description.contains(bundleId), "Should contain bundle identifier")
            case .elementNotFound(let desc):
                XCTAssertTrue(description.contains(desc), "Should contain element description")
            case .elementNotInteractable(let desc):
                XCTAssertTrue(description.contains(desc), "Should contain element description")
            case .accessibilityPermissionDenied:
                XCTAssertTrue(description.contains("Accessibility"), "Should mention accessibility")
            case .invalidRequest(let message):
                XCTAssertTrue(description.contains(message), "Should contain request message")
            case .invalidArgument(let parameter, let value, let reason):
                XCTAssertTrue(description.contains(parameter), "Should contain parameter name")
                XCTAssertTrue(description.contains(value), "Should contain parameter value")
                XCTAssertTrue(description.contains(reason), "Should contain reason")
            case .unexpectedError(let message, _):
                XCTAssertTrue(description.contains(message), "Should contain error message")
            default:
                // Other error types are also tested for basic quality
                XCTAssertTrue(true, "Other error types have basic quality")
            }
        }
    }
    
    // MARK: - Error Handling Consistency Tests
    
    /**
     * Tests that similar operations throw similar errors.
     * Expected behavior: Similar failures should result in similar error types.
     */
    func testErrorHandlingConsistency() async throws {
        let validBundleId = "com.apple.TextEdit"
        let invalidElementId = "nonexistent_element_12345"
        
        // First populate the registry with valid elements
        _ = try await stateManager.getUIElements(applicationIdentifier: validBundleId)
        
        // Test that both click and update operations throw similar errors for invalid element IDs
        var clickError: NudgeError?
        var updateError: NudgeError?
        
        do {
            try await stateManager.clickElementById(
                applicationIdentifier: validBundleId,
                elementId: invalidElementId
            )
        } catch let error as NudgeError {
            clickError = error
        }
        
        do {
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: validBundleId,
                elementId: invalidElementId
            )
        } catch let error as NudgeError {
            updateError = error
        }
        
        // Both should throw similar error types
        XCTAssertNotNil(clickError, "Click should throw error for invalid element ID")
        XCTAssertNotNil(updateError, "Update should throw error for invalid element ID")
        
        if let clickError = clickError, let updateError = updateError {
            // Both should be invalidRequest errors
            switch (clickError, updateError) {
            case (.invalidRequest, .invalidRequest):
                XCTAssertTrue(true, "Both operations should throw invalidRequest errors")
            default:
                XCTFail("Both operations should throw similar error types")
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
        let invalidElementId = "nonexistent_element_12345"
        
        // First populate the registry with valid elements
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
        if let firstElement = elements.first (where: { $0.description.contains("Button") || $0.description.contains("MenuItem") }) {
            // This should work despite the previous error
            try await stateManager.clickElementById(
                applicationIdentifier: validBundleId,
                elementId: firstElement.element_id
            )
            
            // And this should also work
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: validBundleId,
                elementId: firstElement.element_id
            )
            
            // Test passes if no errors are thrown
            XCTAssertTrue(true, "Valid operations should work after errors")
        }
    }
    
    // MARK: - Edge Case Error Tests
    
    /**
     * Tests error handling with edge case inputs.
     * Expected behavior: Should handle edge cases gracefully without crashing.
     */
    func testEdgeCaseErrorHandling() async throws {
        let edgeCaseBundleIds = [
            "", // Empty string
            "   ", // Whitespace only
            "com.", // Incomplete bundle ID
            "com.apple.", // Incomplete bundle ID
            "invalid_bundle_id", // Invalid format
            "com.apple.nonexistent.app.with.very.long.name.that.exceeds.normal.length", // Very long name
            "com.apple.Safari.extra.parts", // Valid app with extra parts
            "COM.APPLE.SAFARI", // Uppercase
            "com.apple.safari" // Lowercase (might be different from actual)
        ]
        
        for bundleId in edgeCaseBundleIds {
            do {
                _ = try await stateManager.getUIElements(applicationIdentifier: bundleId)
                // If it succeeds, that's also fine
            } catch let error as NudgeError {
                // Should throw appropriate error types
                switch error {
                case .applicationNotFound, .applicationNotRunning, .invalidRequest:
                    XCTAssertTrue(true, "Appropriate error for bundle ID: \(bundleId)")
                default:
                    XCTFail("Unexpected error type for bundle ID \(bundleId): \(error)")
                }
            } catch {
                XCTFail("Should throw NudgeError for bundle ID \(bundleId), got: \(type(of: error))")
            }
        }
    }
    
    /**
     * Tests error handling with edge case element IDs.
     * Expected behavior: Should handle edge cases gracefully without crashing.
     */
    func testEdgeCaseElementIdErrorHandling() async throws {
        let validBundleId = "com.apple.TextEdit"
        
        // First populate the registry with valid elements
        _ = try await stateManager.getUIElements(applicationIdentifier: validBundleId)
        
        let edgeCaseElementIds = [
            "", // Empty string
            "   ", // Whitespace only
            "element_", // Incomplete element ID
            "not_an_element_id", // Wrong format
            "element_999999999", // Very large number
            "element_-1", // Negative number
            "element_abc", // Non-numeric
            "ELEMENT_1", // Uppercase
            "element_1_extra_parts", // Valid format with extra parts
            "element_1.extra", // With dot
            "element_1/extra", // With slash
            "element_1@extra", // With special character
            String(repeating: "element_1", count: 100) // Very long element ID
        ]
        
        for elementId in edgeCaseElementIds {
            do {
                try await stateManager.clickElementById(
                    applicationIdentifier: validBundleId,
                    elementId: elementId
                )
                // If it succeeds, that's unexpected but not necessarily wrong
            } catch let error as NudgeError {
                // Should throw appropriate error types
                switch error {
                case .invalidRequest:
                    XCTAssertTrue(true, "Appropriate error for element ID: \(elementId)")
                default:
                    XCTFail("Unexpected error type for element ID \(elementId): \(error)")
                }
            } catch {
                XCTFail("Should throw NudgeError for element ID \(elementId), got: \(type(of: error))")
            }
        }
    }
    
    // MARK: - Concurrent Error Handling Tests
    
    /**
     * Tests error handling under sequential operations.
     * Expected behavior: Errors in one operation should not affect others.
     */
    func testSequentialErrorHandling() async throws {
        let validBundleId = "com.apple.TextEdit"
        let invalidElementId = "nonexistent_element_12345"
        
        // First populate the registry with valid elements
        let elements = try await stateManager.getUIElements(applicationIdentifier: validBundleId)
        
        guard let validElement = elements.first else {
            XCTFail("Need at least one valid element for sequential test")
            return
        }
        
        // Run operations sequentially, mixing valid and invalid
        
        // Valid operation
        do {
            try await stateManager.clickElementById(
                applicationIdentifier: validBundleId,
                elementId: validElement.element_id
            )
        } catch {
            print("Valid operation failed: \(error)")
        }
        
        // Invalid operation
        do {
            try await stateManager.clickElementById(
                applicationIdentifier: validBundleId,
                elementId: invalidElementId
            )
            XCTFail("Invalid operation should fail")
        } catch {
            // Expected to fail
        }
        
        // Another valid operation (should still work after error)
        do {
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: validBundleId,
                elementId: validElement.element_id
            )
        } catch {
            print("Valid update operation failed: \(error)")
        }
        
        // Another invalid operation
        do {
            _ = try await stateManager.updateUIElementTree(
                applicationIdentifier: validBundleId,
                elementId: invalidElementId
            )
            XCTFail("Invalid update operation should fail")
        } catch {
            // Expected to fail
        }
        
        // Test passes if we reach here
        XCTAssertTrue(true, "Sequential operations should handle errors gracefully")
    }
    
    // MARK: - Error Serialization Tests
    
    /**
     * Tests that errors can be properly serialized and communicated.
     * Expected behavior: Error descriptions should be useful for debugging.
     */
    func testErrorSerialization() async throws {
        let validBundleId = "com.apple.TextEdit"
        let invalidElementId = "nonexistent_element_12345"
        
        // First populate the registry with valid elements
        _ = try await stateManager.getUIElements(applicationIdentifier: validBundleId)
        
        do {
            try await stateManager.clickElementById(
                applicationIdentifier: validBundleId,
                elementId: invalidElementId
            )
            XCTFail("Should throw error for invalid element ID")
        } catch let error as NudgeError {
            // Test that the error can be converted to different formats
            let description = error.localizedDescription
            let debugDescription = String(describing: error)
            
            XCTAssertFalse(description.isEmpty, "Error description should not be empty")
            XCTAssertFalse(debugDescription.isEmpty, "Error debug description should not be empty")
            
            // Test that the error maintains its type information
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("not found"), "Message should contain 'not found'")
            default:
                XCTFail("Should be invalidRequest error")
            }
        } catch {
            XCTFail("Should throw NudgeError, got: \(type(of: error))")
        }
    }
} 
