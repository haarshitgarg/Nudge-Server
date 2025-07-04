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
            uiElements.append(contentsOf: await buildUIElementInfo(for: focusedWindow, currentDepth: 0, maxDepth: 2))
        } else {
            // Fallback to getting all windows if no focused window is found
            var allWindowsValue: CFTypeRef?
            let allWindowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &allWindowsValue)

            if allWindowsResult == .success {
                let allWindows = allWindowsValue as! [AXUIElement]
                for window in allWindows {
                    uiElements.append(contentsOf: await buildUIElementInfo(for: window, currentDepth: 0, maxDepth: 2))
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
        let help = getAttribute(element, kAXHelpAttribute) as? String
        let role = getAttribute(element, kAXRoleAttribute) as? String
        
        // Additional accessibility attributes that might contain useful information
        let description = getAttribute(element, kAXDescriptionAttribute) as? String
        let placeholderValue = getAttribute(element, kAXPlaceholderValueAttribute) as? String

        // Define roles that should be completely ignored (not actionable/useful for LLM)
        let rolesToIgnore = [
            "AXStaticText",      // Static text - usually just labels/info, not actionable
            "AXImage",           // Decorative images - usually not clickable/actionable
            "AXUnknown",         // Unknown elements - not useful
            "AXGenericElement"   // Generic elements - usually not actionable
        ]
        
        // Define roles that provide context but should be merged with parent (not standalone)
        let rolesToMergeWithParent = [
            "AXHeading",         // Headings provide context but aren't actionable
            "AXText",            // Text elements that provide context
            "AXLabel"            // Labels that provide context
        ]
        
        // Check if this element should be completely ignored
        if let elementRole = role, rolesToIgnore.contains(elementRole) {
            // Skip this element entirely - return empty array
            return []
        }
        
        // Check if this element should be merged with parent (extract info but don't create element)
        if let elementRole = role, rolesToMergeWithParent.contains(elementRole) {
            // Extract the text content from this element and return it as context
            var contextInfo: [String] = []
            
            if let title = title, !title.isEmpty {
                contextInfo.append("Context: \(title)")
            }
            
            if let valueAttr = valueAttr, !valueAttr.isEmpty {
                contextInfo.append("Context: \(valueAttr)")
            }
            
            if let help = help, !help.isEmpty {
                contextInfo.append("Context: \(help)")
            }
            
            if let description = description, !description.isEmpty {
                contextInfo.append("Context: \(description)")
            }
            
            // Instead of creating a UIElementInfo, we'll return the children with context info
            // But we need a way to pass this context up - for now, let's create a special "context" element
            if !contextInfo.isEmpty {
                let contextDescription = contextInfo.joined(separator: " | ")
                
                // Get children and add context to them
                var childrenWithContext: [UIElementInfo] = []
                if currentDepth < maxDepth {
                    var value: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                    if result == .success, let axChildren = value as? [AXUIElement] {
                        for child in axChildren {
                            childrenWithContext.append(contentsOf: await buildUIElementInfo(for: child, currentDepth: currentDepth + 1, maxDepth: maxDepth))
                        }
                    }
                }
                
                // If we have children, add context to the first actionable child
                if !childrenWithContext.isEmpty {
                    for i in 0..<childrenWithContext.count {
                        if childrenWithContext[i].isActionable {
                            // Add context to this child's description
                            let existingDesc = childrenWithContext[i].description ?? ""
                            let newDesc = existingDesc.isEmpty ? contextDescription : "\(contextDescription) | \(existingDesc)"
                            let updatedChild = UIElementInfo(
                                frame: childrenWithContext[i].frame,
                                description: newDesc,
                                children: childrenWithContext[i].children
                            )
                            childrenWithContext[i] = updatedChild
                            break
                        }
                    }
                }
                
                return childrenWithContext
            } else {
                // No useful context, just return children
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
                return children
            }
        }
        
        // Define container roles that should ALWAYS be flattened (never appear in final tree)
        let containerRolesToFlatten = [
            "AXGroup",           // Generic grouping container - ALWAYS flatten
            "AXSplitGroup",      // Split view containers - ALWAYS flatten  
            "AXScrollArea",      // Scroll areas - ALWAYS flatten to show content
            "AXLayoutArea",      // Layout containers - ALWAYS flatten
            "AXLayoutItem",      // Layout items - ALWAYS flatten
            "AXSplitter",        // UI splitters - ALWAYS flatten
            "AXToolbar",         // Toolbar containers - ALWAYS flatten
            "AXTabGroup"         // Tab group containers - ALWAYS flatten
        ]
        
        // Check if this element should be flattened - if yes, ALWAYS flatten regardless of content
        if let elementRole = role, containerRolesToFlatten.contains(elementRole) {
            // ALWAYS flatten container elements - collect children instead of the container itself
            var flattenedChildren: [UIElementInfo] = []
            
            if currentDepth < maxDepth {
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                if result == .success, let axChildren = value as? [AXUIElement] {
                    for child in axChildren {
                        flattenedChildren.append(contentsOf: await buildUIElementInfo(for: child, currentDepth: currentDepth, maxDepth: maxDepth))
                    }
                }
            }
            
            return flattenedChildren
        }

        // Create combined description from all available text attributes
        var descriptionParts: [String] = []
        
        if let role = role {
            descriptionParts.append("Role: \(role)")
        }
        
        if let title = title, !title.isEmpty {
            descriptionParts.append("Title: \(title)")
        }
        
        if let valueAttr = valueAttr, !valueAttr.isEmpty {
            descriptionParts.append("Value: \(valueAttr)")
        }
        
        if let help = help, !help.isEmpty {
            descriptionParts.append("Help: \(help)")
        }
        
        if let description = description, !description.isEmpty {
            descriptionParts.append("Description: \(description)")
        }
        
        if let placeholderValue = placeholderValue, !placeholderValue.isEmpty {
            descriptionParts.append("Placeholder: \(placeholderValue)")
        }
        
        let combinedDescription = descriptionParts.isEmpty ? nil : descriptionParts.joined(separator: " | ")

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
        if role == "AXButton" && combinedDescription != nil {
            os_log("Button found - combined description: %@", 
                   log: log, type: .debug, 
                   combinedDescription!)
        }
        
        let elementInfo = UIElementInfo(
            frame: frame,
            description: combinedDescription,
            children: children
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

        let clickCoordinate: CGPoint = CGPoint(x: coordinate.x, y: coordinate.y)

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
