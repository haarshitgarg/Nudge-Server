import os
import Foundation
import AppKit
import CoreGraphics

actor StateManager {
    // Defined the class singleton to make sure there is only one state manager
    static let shared = StateManager()
    private init() {}

    let log = OSLog(subsystem: "Harshit.NudgeServer", category: "StateManager")


    /// A dictionary to store UI state trees, keyed by application identifier.
    private var uiStateTrees: [String: UIStateTree] = [:]

    /// Adds or updates a UI state tree for a given application.
    func updateUIStateTree(applicationIdentifier: String) async throws {
        os_log("Attempting to update UI state tree for %@", log: log, type: .debug, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            os_log("Accessibility permissions denied. Cannot update UI tree for %@", log: log, type: .error, applicationIdentifier)
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) else {
            os_log("Application %@ not running. Cannot update UI tree.", log: log, type: .error, applicationIdentifier)
            throw NudgeError.applicationNotRunning(bundleIdentifier: applicationIdentifier)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var uiElements: [UIElementInfo] = []

        // Try to get the focused window first
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        if focusedWindowResult == .success {
            let focusedWindow = focusedWindowValue as! AXUIElement
            uiElements.append(await buildUIElementInfo(for: focusedWindow, currentDepth: 0, maxDepth: 1))
        } else {
            // Fallback to getting all windows if no focused window is found
            var allWindowsValue: CFTypeRef?
            let allWindowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &allWindowsValue)

            if allWindowsResult == .success {
                let allWindows = allWindowsValue as! [AXUIElement]
                for window in allWindows {
                    uiElements.append(await buildUIElementInfo(for: window, currentDepth: 0, maxDepth: 1))
                }
            } else {
                os_log("Could not get any windows for application %@. Error: %d", log: log, type: .error, applicationIdentifier, allWindowsResult.rawValue)
                throw NudgeError.invalidRequest(message: "\(applicationIdentifier) doesn't have any accessible windows.")
            }
        }

        var menuBarValue: CFTypeRef?
        let menuBarResult = AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue)
        if menuBarResult == .success {
            let menuBar = menuBarValue as! AXUIElement
            uiElements.append(await buildUIElementInfo(for: menuBar, currentDepth: 0, maxDepth: 1))
        } else {
        }

        let newTree = UIStateTree(applicationIdentifier: applicationIdentifier, treeData: uiElements, isStale: false, lastUpdated: Date())
        uiStateTrees[applicationIdentifier] = newTree
        os_log("Successfully updated UI state tree for %@", log: log, type: .debug, applicationIdentifier)
    }

    /// Recursively builds UIElementInfo from an AXUIElement.
    private func buildUIElementInfo(for element: AXUIElement, currentDepth: Int, maxDepth: Int) async -> UIElementInfo {
        var children: [UIElementInfo] = []
        if currentDepth < maxDepth {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            if result == .success, let axChildren = value as? [AXUIElement] {
                for child in axChildren {
                    children.append(await buildUIElementInfo(for: child, currentDepth: currentDepth + 1, maxDepth: maxDepth))
                }
            }
        }

        // Extract attributes
        let title = getAttribute(element, kAXTitleAttribute) as? String
        let valueAttr = getAttribute(element, kAXValueAttribute) as? String
        let identifier = getAttribute(element, kAXIdentifierAttribute) as? String
        let help = getAttribute(element, kAXHelpAttribute) as? String

        var frame: CGRect? = nil
        if let positionValue = getAttribute(element, kAXPositionAttribute),
           let sizeValue = getAttribute(element, kAXSizeAttribute) {
            var position: CGPoint = .zero
            var size: CGSize = .zero
            if AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) && AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
                frame = CGRect(origin: position, size: size)
            }
        }

        return UIElementInfo(
            title: title,
            help: help,
            value: valueAttr,
            identifier: identifier,
            frame: frame,
            children: children
        )
    }

    /// Helper to safely get an attribute from an AXUIElement.
    private func getAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    /// Marks a UI state tree as stale.
    func markUIStateTreeAsStale(applicationIdentifier: String) {
        uiStateTrees[applicationIdentifier]?.isStale = true
        os_log("Marked the tree stale for %@", log: log, type: .debug, applicationIdentifier)
    }

    /// Retrieves the UI state tree for a given application.
    func getUIStateTree(applicationIdentifier: String) throws -> UIStateTree {
        guard let stateTree = uiStateTrees[applicationIdentifier] else {
            throw NudgeError.uiStateTreeNotFound(applicationIdentifier: applicationIdentifier)
        }
        return stateTree
    }


    // AI MARKER: WORK ON GET UI ELEMENT

    /// Gets UI elements within a specified frame in the frontmost window of an application.
    /// This function is designed to help agents navigate by providing relevant UI items in a specific area.
    func getUIElementsInFrame(applicationIdentifier: String, frame: CGRect) async throws -> [UIElementInfo] {
        os_log("Attempting to get UI elements in frame (x:%.1f, y:%.1f, w:%.1f, h:%.1f) for application %@", log: log, type: .debug, frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            os_log("Accessibility permissions denied. Cannot get UI elements for %@", log: log, type: .error, applicationIdentifier)
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) else {
            os_log("Application %@ not running. Cannot get UI elements.", log: log, type: .error, applicationIdentifier)
            throw NudgeError.applicationNotRunning(bundleIdentifier: applicationIdentifier)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var relevantElements: [UIElementInfo] = []

        // Get the focused window first
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        if focusedWindowResult == .success {
            let focusedWindow = focusedWindowValue as! AXUIElement
            let windowElements = await collectElementsInFrame(from: focusedWindow, targetFrame: frame, currentDepth: 0, maxDepth: 10)
            relevantElements.append(contentsOf: windowElements)
        } else {
            // Fallback to getting all windows if no focused window is found
            var allWindowsValue: CFTypeRef?
            let allWindowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &allWindowsValue)

            if allWindowsResult == .success {
                let allWindows = allWindowsValue as! [AXUIElement]
                for window in allWindows {
                    let windowElements = await collectElementsInFrame(from: window, targetFrame: frame, currentDepth: 0, maxDepth: 10)
                    relevantElements.append(contentsOf: windowElements)
                }
            } else {
                os_log("Could not get any windows for application %@. Error: %d", log: log, type: .error, applicationIdentifier, allWindowsResult.rawValue)
                throw NudgeError.invalidRequest(message: "\(applicationIdentifier) doesn't have any accessible windows.")
            }
        }

        // Filter out elements that are not relevant for navigation (like invisible elements)
        let filteredElements = relevantElements.filter { element in
            // Keep elements that have meaningful content
            return element.hasMeaningfulContent
        }

        os_log("Found %d relevant UI elements in frame for %@", log: log, type: .debug, filteredElements.count, applicationIdentifier)
        return filteredElements
    }

    /// Recursively collects UI elements that intersect with the target frame.
    private func collectElementsInFrame(from element: AXUIElement, targetFrame: CGRect, currentDepth: Int, maxDepth: Int) async -> [UIElementInfo] {
        var collectedElements: [UIElementInfo] = []

        // Get the frame of the current element
        var elementFrame: CGRect?
        if let positionValue = getAttribute(element, kAXPositionAttribute),
           let sizeValue = getAttribute(element, kAXSizeAttribute) {
            var position: CGPoint = .zero
            var size: CGSize = .zero
            if AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) && AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
                elementFrame = CGRect(origin: position, size: size)
            }
        }

        // Check if this element intersects with the target frame
        if let frame = elementFrame, frame.intersects(targetFrame) {
            // Build the UI element info for this element
            let elementInfo = await buildUIElementInfo(for: element, currentDepth: currentDepth, maxDepth: 0) // Don't recurse here, we'll handle children separately
            collectedElements.append(elementInfo)
        }

        // Recursively check children if we haven't reached max depth
        if currentDepth < maxDepth {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            if result == .success, let axChildren = value as? [AXUIElement] {
                for child in axChildren {
                    let childElements = await collectElementsInFrame(from: child, targetFrame: targetFrame, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                    collectedElements.append(contentsOf: childElements)
                }
            }
        }

        return collectedElements
    }

    /// Gets UI elements in a rectangular area defined by top-left and bottom-right coordinates.
    /// This is a convenience function that creates a CGRect from coordinates.
    func getUIElementsInArea(applicationIdentifier: String, topLeft: CGPoint, bottomRight: CGPoint) async throws -> [UIElementInfo] {
        let frame = CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
        return try await getUIElementsInFrame(applicationIdentifier: applicationIdentifier, frame: frame)
    }

    /// Gets UI elements within a circular area around a center point.
    func getUIElementsInRadius(applicationIdentifier: String, center: CGPoint, radius: CGFloat) async throws -> [UIElementInfo] {
        let frame = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        
        let elementsInFrame = try await getUIElementsInFrame(applicationIdentifier: applicationIdentifier, frame: frame)
        
        // Since we no longer store frame in UIElementInfo, we need to filter differently
        // For now, return all elements in the frame since we can't calculate distance without frame
        // TODO: Consider adding frame back if circular filtering is important
        return elementsInFrame
    }

    /// Finds and clicks a UI element by its identifier.
    func clickUIElement(applicationIdentifier: String, elementIdentifier: String) async throws {
        os_log("Attempting to click UI element with identifier %@ in application %@", log: log, type: .debug, elementIdentifier, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            os_log("Accessibility permissions denied. Cannot click UI element for %@", log: log, type: .error, applicationIdentifier)
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) else {
            os_log("Application %@ not running. Cannot click UI element.", log: log, type: .error, applicationIdentifier)
            throw NudgeError.applicationNotRunning(bundleIdentifier: applicationIdentifier)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        
        // Search for the element in the application
        guard let targetElement = await findElementByIdentifier(in: axApp, identifier: elementIdentifier) else {
            os_log("UI element with identifier %@ not found in application %@", log: log, type: .error, elementIdentifier, applicationIdentifier)
            throw NudgeError.elementNotFound(description: "Element with identifier '\(elementIdentifier)' not found")
        }

        // Check if the element is enabled
        if let isEnabled = getAttribute(targetElement, kAXEnabledAttribute) as? Bool, !isEnabled {
            os_log("UI element with identifier %@ is not enabled", log: log, type: .error, elementIdentifier)
            throw NudgeError.elementNotInteractable(description: "Element with identifier '\(elementIdentifier)' is not enabled")
        }

        // Perform the click action
        let clickResult = AXUIElementPerformAction(targetElement, kAXPressAction as CFString)
        if clickResult != .success {
            os_log("Failed to click UI element with identifier %@. Error: %d", log: log, type: .error, elementIdentifier, clickResult.rawValue)
            throw NudgeError.clickFailed(description: "Failed to click element '\(elementIdentifier)'", underlyingError: nil)
        }

        os_log("Successfully clicked UI element with identifier %@", log: log, type: .debug, elementIdentifier)
    }

    /// Clicks at a specific coordinate within an application window.
    func clickAtCoordinate(applicationIdentifier: String, coordinate: CGPoint) async throws {
        os_log("Attempting to click at coordinate (%.1f, %.1f) in application %@", log: log, type: .debug, coordinate.x, coordinate.y, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            os_log("Accessibility permissions denied. Cannot click at coordinate for %@", log: log, type: .error, applicationIdentifier)
            throw NudgeError.accessibilityPermissionDenied
        }

        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) else {
            os_log("Application %@ not running. Cannot click at coordinate.", log: log, type: .error, applicationIdentifier)
            throw NudgeError.applicationNotRunning(bundleIdentifier: applicationIdentifier)
        }

        // Use Core Graphics to perform the click at the specified coordinate
        let clickEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: coordinate, mouseButton: .left)
        let releaseEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: coordinate, mouseButton: .left)
        
        clickEvent?.post(tap: .cghidEventTap)
        releaseEvent?.post(tap: .cghidEventTap)

        os_log("Successfully clicked at coordinate (%.1f, %.1f)", log: log, type: .debug, coordinate.x, coordinate.y)
    }

    /// Recursively searches for a UI element by its identifier.
    private func findElementByIdentifier(in element: AXUIElement, identifier: String) async -> AXUIElement? {
        // Check if current element has the target identifier
        if let elementId = getAttribute(element, kAXIdentifierAttribute) as? String, elementId == identifier {
            return element
        }

        // Recursively search children
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        if result == .success, let axChildren = value as? [AXUIElement] {
            for child in axChildren {
                if let found = await findElementByIdentifier(in: child, identifier: identifier) {
                    return found
                }
            }
        }

        return nil
    }

}
