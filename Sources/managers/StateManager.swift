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
            uiElements.append(contentsOf: await buildUIElementInfo(for: focusedWindow, currentDepth: 0, maxDepth: 3))
        } else {
            // Fallback to getting all windows if no focused window is found
            var allWindowsValue: CFTypeRef?
            let allWindowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &allWindowsValue)

            if allWindowsResult == .success {
                let allWindows = allWindowsValue as! [AXUIElement]
                for window in allWindows {
                    uiElements.append(contentsOf: await buildUIElementInfo(for: window, currentDepth: 0, maxDepth: 3))
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
            uiElements.append(contentsOf: await buildUIElementInfo(for: menuBar, currentDepth: 0, maxDepth: 3))
        } else {
            os_log("Could not get any menu bar. That is weird", log: log, type: .debug)
            // TODO: To decide if this is strictly necessary. Do all apps require menu bar
            throw NudgeError.invalidRequest(message: "\(applicationIdentifier) doesn't have any accessible menu bars.")
        }

        let newTree = UIStateTree(applicationIdentifier: applicationIdentifier, treeData: uiElements, isStale: false, lastUpdated: Date())
        uiStateTrees[applicationIdentifier] = newTree
        os_log("Successfully updated UI state tree for %@", log: log, type: .debug, applicationIdentifier)
    }

    /// Recursively builds UIElementInfo from an AXUIElement, flattening container elements during collection.
    private func buildUIElementInfo(for element: AXUIElement, currentDepth: Int, maxDepth: Int) async -> [UIElementInfo] {
        // Extract attributes first to determine if this element should be flattened
        let title = getAttribute(element, kAXTitleAttribute) as? String
        let valueAttr = getAttribute(element, kAXValueAttribute) as? String
        let identifier = getAttribute(element, kAXIdentifierAttribute) as? String
        let help = getAttribute(element, kAXHelpAttribute) as? String
        let role = getAttribute(element, kAXRoleAttribute) as? String
        let isEnabled = getAttribute(element, kAXEnabledAttribute) as? Bool
        
        // Additional accessibility attributes that might contain useful information
        let description = getAttribute(element, kAXDescriptionAttribute) as? String
        let roleDescription = getAttribute(element, kAXRoleDescriptionAttribute) as? String
        let placeholderValue = getAttribute(element, kAXPlaceholderValueAttribute) as? String

        // Define roles that should be completely ignored (not actionable/useful for LLM)
        let rolesToIgnore = [
            "AXStaticText",      // Static text - usually just labels/info, not actionable
            "AXImage",           // Decorative images - usually not clickable/actionable
            "AXUnknown",         // Unknown elements - not useful
            "AXGenericElement"   // Generic elements - usually not actionable
        ]
        
        // Check if this element should be completely ignored
        if let elementRole = role, rolesToIgnore.contains(elementRole) {
            // Skip this element entirely - return empty array
            return []
        }
        
        // Define container roles that should be flattened during collection
        let containerRolesToFlatten = [
            "AXGroup",           // Generic grouping container - flatten these
            "AXSplitGroup",      // Split view containers - flatten these  
            "AXScrollArea",      // Scroll areas - flatten to show content
            "AXLayoutArea",      // Layout containers - flatten these
            "AXLayoutItem",      // Layout items - flatten these
            "AXSplitter",        // UI splitters - flatten these
            "AXToolbar",         // Toolbar containers - flatten these
            "AXTabGroup"         // Tab group containers - flatten these
        ]
        
        // Check if this element should be flattened
        if let elementRole = role, containerRolesToFlatten.contains(elementRole) {
            // For container elements, only preserve them if they have USER-MEANINGFUL content
            // Be very strict - only title and help are considered user-meaningful for containers
            // Technical identifiers, descriptions, and role descriptions don't count for containers
            let hasUserMeaningfulContent = (title != nil && !title!.isEmpty) || 
                                         (help != nil && !help!.isEmpty)
            
            // For container elements, flatten if:
            // 1. They have no user-meaningful content (identifiers don't count), OR
            // 2. They are disabled (like AXSplitter with isEnabled=false)
            let shouldFlatten = !hasUserMeaningfulContent || (isEnabled == false)
            
            if shouldFlatten && currentDepth < maxDepth {
                // Flatten: collect children directly instead of creating this container
                // Don't increment depth since we're not adding a meaningful hierarchy layer
                var flattenedChildren: [UIElementInfo] = []
                
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                if result == .success, let axChildren = value as? [AXUIElement] {
                    for child in axChildren {
                        flattenedChildren.append(contentsOf: await buildUIElementInfo(for: child, currentDepth: currentDepth, maxDepth: maxDepth))
                    }
                }
                
                return flattenedChildren
            } else if shouldFlatten {
                // Empty container with no content and no children - skip it entirely
                return []
            }
        }

        // For non-container elements or containers with meaningful content, build normally
        var children: [UIElementInfo] = []
        if currentDepth < maxDepth {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            if result == .success, let axChildren = value as? [AXUIElement] {
                for child in axChildren {
                    children.append(contentsOf: await buildUIElementInfo(for: child, currentDepth: currentDepth + 1, maxDepth: maxDepth))
                }
            }
        }

        var frame: CGRect? = nil
        if let positionValue = getAttribute(element, kAXPositionAttribute),
           let sizeValue = getAttribute(element, kAXSizeAttribute) {
            var position: CGPoint = .zero
            var size: CGSize = .zero
            if AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) && AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
                frame = CGRect(origin: position, size: size)
            }
        }

        // Debug logging to help understand what attributes are being captured
        if role == "AXButton" && (title != nil || description != nil || roleDescription != nil) {
            os_log("Button found - title: %@, description: %@, roleDescription: %@, identifier: %@", 
                   log: log, type: .debug, 
                   title ?? "nil", 
                   description ?? "nil", 
                   roleDescription ?? "nil", 
                   identifier ?? "nil")
        }
        
        let elementInfo = UIElementInfo(
            title: title,
            help: help,
            value: valueAttr,
            identifier: identifier,
            frame: frame,
            children: children,
            role: role,
            isEnabled: isEnabled,
            description: description,
            roleDescription: roleDescription,
            placeholderValue: placeholderValue
        )
        
        return [elementInfo]
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

        // Filter to only include truly actionable elements for LLM decision-making
        let filteredElements = relevantElements.filter { element in
            // Keep only elements that users can directly interact with
            return element.isActionable
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
            let elementInfos = await buildUIElementInfo(for: element, currentDepth: currentDepth, maxDepth: 0) // Don't recurse here, we'll handle children separately
            collectedElements.append(contentsOf: elementInfos)
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

        let clickCoordinate: CGPoint = CGPoint(x: coordinate.x + 10, y: coordinate.y + 10)

        // Use Core Graphics to perform the click at the specified coordinate
        let clickEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: clickCoordinate, mouseButton: .left)
        let releaseEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: clickCoordinate, mouseButton: .left)
        
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
