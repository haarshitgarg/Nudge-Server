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
    
    /// Counter for generating unique element IDs
    private var elementIdCounter: Int = 0
    
    /// Registry to store all discovered UI elements by their IDs across different discovery methods
    private var elementRegistry: [String: (element: UIElementInfo, axElement: AXUIElement, applicationIdentifier: String)] = [:]

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

        // Clear existing elements for this application from the registry to avoid stale elements
        elementRegistry = elementRegistry.filter { $0.value.applicationIdentifier != applicationIdentifier }
        os_log("Cleared existing UI elements for %@ before rebuilding state tree", log: log, type: .debug, applicationIdentifier)

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var uiElements: [UIElementInfo] = []

        // Try to get the focused window first
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        if focusedWindowResult == .success {
            let focusedWindow = focusedWindowValue as! AXUIElement
            let windowElements = await buildUIElementInfo(for: focusedWindow, currentDepth: 0, maxDepth: 2, applicationIdentifier: applicationIdentifier, parentPath: [])
            uiElements.append(contentsOf: windowElements)
        } else {
            // Fallback to getting all windows if no focused window is found
            var allWindowsValue: CFTypeRef?
            let allWindowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &allWindowsValue)

            if allWindowsResult == .success {
                let allWindows = allWindowsValue as! [AXUIElement]
                for window in allWindows {
                    let windowElements = await buildUIElementInfo(for: window, currentDepth: 0, maxDepth: 2, applicationIdentifier: applicationIdentifier, parentPath: [])
                    uiElements.append(contentsOf: windowElements)
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
            let menuElements = await buildUIElementInfo(for: menuBar, currentDepth: 0, maxDepth: 3, applicationIdentifier: applicationIdentifier, parentPath: [])
            uiElements.append(contentsOf: menuElements)
        } else {
            os_log("Could not get any menu bar. That is weird", log: log, type: .debug)
            // TODO: To decide if this is strictly necessary. Do all apps require menu bar
            throw NudgeError.invalidRequest(message: "\(applicationIdentifier) doesn't have any accessible menu bars.")
        }

        // Elements are registered during building phase

        let newTree = UIStateTree(applicationIdentifier: applicationIdentifier, treeData: uiElements, isStale: false, lastUpdated: Date())
        uiStateTrees[applicationIdentifier] = newTree
        os_log("Successfully updated UI state tree for %@", log: log, type: .debug, applicationIdentifier)
    }

    /// Generates a unique ID for a UI element
    private func generateElementId() -> String {
        elementIdCounter += 1
        return "element_\(elementIdCounter)"
    }

    /// Registers a UI element with its AXUIElement in the element registry
    private func registerElement(_ element: UIElementInfo, axElement: AXUIElement, for applicationIdentifier: String) {
        elementRegistry[element.id] = (element: element, axElement: axElement, applicationIdentifier: applicationIdentifier)
    }

    /// Clears all UI elements for a specific application from the registry
    /// This is useful for cleanup when an application's UI state becomes stale
    func clearElementsForApplication(_ applicationIdentifier: String) {
        let beforeCount = elementRegistry.count
        elementRegistry = elementRegistry.filter { $0.value.applicationIdentifier != applicationIdentifier }
        let afterCount = elementRegistry.count
        let clearedCount = beforeCount - afterCount
        os_log("Manually cleared %d UI elements for %@", log: log, type: .debug, clearedCount, applicationIdentifier)
    }

    /// Clears all UI elements from the registry
    /// This is useful for complete cleanup or memory management
    func clearAllElements() {
        let clearedCount = elementRegistry.count
        elementRegistry.removeAll()
        os_log("Cleared all %d UI elements from registry", log: log, type: .debug, clearedCount)
    }

    /// Gets the current status of the element registry for debugging
    func getRegistryStatus() -> (totalElements: Int, applicationBreakdown: [String: Int]) {
        var applicationBreakdown: [String: Int] = [:]
        for (_, entry) in elementRegistry {
            applicationBreakdown[entry.applicationIdentifier, default: 0] += 1
        }
        return (totalElements: elementRegistry.count, applicationBreakdown: applicationBreakdown)
    }

    /// Recursively builds UIElementInfo from an AXUIElement, flattening container elements during collection.
    private func buildUIElementInfo(for element: AXUIElement, currentDepth: Int, maxDepth: Int, applicationIdentifier: String, parentPath: [String] = []) async -> [UIElementInfo] {
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
                                childrenWithContext.append(contentsOf: await buildUIElementInfo(for: child, currentDepth: currentDepth + 1, maxDepth: maxDepth, applicationIdentifier: applicationIdentifier, parentPath: parentPath))
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
                                id: childrenWithContext[i].id,
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
                            children.append(contentsOf: await buildUIElementInfo(for: child, currentDepth: currentDepth + 1, maxDepth: maxDepth, applicationIdentifier: applicationIdentifier, parentPath: parentPath))
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
                        flattenedChildren.append(contentsOf: await buildUIElementInfo(for: child, currentDepth: currentDepth, maxDepth: maxDepth, applicationIdentifier: applicationIdentifier, parentPath: parentPath))
                    }
                }
            }
            
            return flattenedChildren
        }

        // Create clean, concise description focusing on what's useful for LLM decision-making
        var descriptionParts: [String] = []
        
        // Start with the most important identifier (title, then value, then role)
        if let title = title, !title.isEmpty {
            descriptionParts.append(title)
        } else if let valueAttr = valueAttr, !valueAttr.isEmpty {
            descriptionParts.append(valueAttr)
        } else if let role = role {
            // Clean up role name for better readability
            let cleanRole = role.replacingOccurrences(of: "AX", with: "").lowercased()
            descriptionParts.append("(\(cleanRole))")
        }
        
        // Add context if available and different from title
        if let help = help, !help.isEmpty, help != title {
            descriptionParts.append("- \(help)")
        } else if let description = description, !description.isEmpty, description != title {
            descriptionParts.append("- \(description)")
        } else if let placeholderValue = placeholderValue, !placeholderValue.isEmpty {
            descriptionParts.append("- \(placeholderValue)")
        }
        
        let combinedDescription = descriptionParts.isEmpty ? nil : descriptionParts.joined(separator: " ")

        // Generate element ID early so it can be used in the path
        let elementId = generateElementId()
        let currentPath = parentPath + [elementId]
        
        // For non-container elements or containers with meaningful content, build normally
        var children: [UIElementInfo] = []
        if currentDepth < maxDepth {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                                if result == .success, let axChildren = value as? [AXUIElement] {
                        for child in axChildren {
                            children.append(contentsOf: await buildUIElementInfo(for: child, currentDepth: currentDepth + 1, maxDepth: maxDepth, applicationIdentifier: applicationIdentifier, parentPath: currentPath))
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
        
        let elementType = role?.replacingOccurrences(of: "AX", with: "")
        let hasChildren = !children.isEmpty
        let isExpandable = await isElementExpandable(element)
        
        let elementInfo = UIElementInfo(
            id: elementId,
            frame: frame,
            description: combinedDescription,
            children: children,
            elementType: elementType,
            hasChildren: hasChildren,
            isExpandable: isExpandable,
            path: currentPath,
            role: role
        )
        
        // Only register actionable elements to keep registry clean and focused
        if elementInfo.isActionable {
            registerElement(elementInfo, axElement: element, for: applicationIdentifier)
        }
        
        return [elementInfo]
    }

    /// Performs a click action on an AXUIElement using the accessibility API
    private func performClick(element: AXUIElement) {
        os_log("Performing click on element, title: %{public}@, type: %{public}@", log: log, type: .debug, getStringAttribute(element, kAXTitleAttribute) ?? "No title", getStringAttribute(element, kAXRoleAttribute) ?? "No role")
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result != .success {
            os_log("Failed to perform click on element, title: %{public}@, type: %{public}@", log: log, type: .error, getStringAttribute(element, kAXTitleAttribute) ?? "No title", getStringAttribute(element, kAXRoleAttribute) ?? "No role")
        }
    }

    /// Helper method to get string attributes safely
    private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        return getAttribute(element, attribute) as? String
    }

    /// Clicks a UI element by its ID using the robust accessibility API
    func clickElementById(applicationIdentifier: String, elementId: String) async throws {
        os_log("Attempting to click element with ID %@ in application %@", log: log, type: .debug, elementId, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            os_log("Accessibility permissions denied. Cannot click element for %@", log: log, type: .error, applicationIdentifier)
            throw NudgeError.accessibilityPermissionDenied
        }

        // Find the element by ID in the registry
        guard let registryEntry = elementRegistry[elementId] else {
            os_log("Element with ID %@ not found in registry", log: log, type: .error, elementId)
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' not found. Make sure to call get_state_of_application or get_ui_elements_in_frame first to discover elements.")
        }
        
        // Verify the element belongs to the correct application
        guard registryEntry.applicationIdentifier == applicationIdentifier else {
            os_log("Element with ID %@ belongs to different application %@, not %@", log: log, type: .error, elementId, registryEntry.applicationIdentifier, applicationIdentifier)
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' belongs to application '\(registryEntry.applicationIdentifier)', not '\(applicationIdentifier)'")
        }
        
        let element = registryEntry.element
        let axElement = registryEntry.axElement
        
        // Check if the element is actionable
        guard element.isActionable else {
            os_log("Element with ID %@ is not actionable", log: log, type: .error, elementId)
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' is not actionable")
        }
        
        // Use the robust accessibility API to perform the click
        performClick(element: axElement)
        
        os_log("Successfully clicked element with ID %@ using accessibility API", log: log, type: .debug, elementId)
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

        // Clear existing elements for this application to avoid stale elements and memory leaks
        // This ensures each call gets fresh, current UI elements
        elementRegistry = elementRegistry.filter { $0.value.applicationIdentifier != applicationIdentifier }
        os_log("Cleared existing UI elements for %@ to ensure fresh discovery", log: log, type: .debug, applicationIdentifier)

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var relevantElements: [UIElementInfo] = []

        // Get the focused window first
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        if focusedWindowResult == .success {
            let focusedWindow = focusedWindowValue as! AXUIElement
            let windowElements = await collectElementsInFrame(from: focusedWindow, targetFrame: frame, currentDepth: 0, maxDepth: 10, applicationIdentifier: applicationIdentifier)
            relevantElements.append(contentsOf: windowElements)
        } else {
            // Fallback to getting all windows if no focused window is found
            var allWindowsValue: CFTypeRef?
            let allWindowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &allWindowsValue)

            if allWindowsResult == .success {
                let allWindows = allWindowsValue as! [AXUIElement]
                for window in allWindows {
                    let windowElements = await collectElementsInFrame(from: window, targetFrame: frame, currentDepth: 0, maxDepth: 10, applicationIdentifier: applicationIdentifier)
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

        // Elements are registered during building phase

        os_log("Found %d relevant UI elements in frame for %@", log: log, type: .debug, filteredElements.count, applicationIdentifier)
        return filteredElements
    }

    /// Recursively collects UI elements that intersect with the target frame.
    private func collectElementsInFrame(from element: AXUIElement, targetFrame: CGRect, currentDepth: Int, maxDepth: Int, applicationIdentifier: String) async -> [UIElementInfo] {
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
            let elementInfos = await buildUIElementInfo(for: element, currentDepth: currentDepth, maxDepth: 0, applicationIdentifier: applicationIdentifier, parentPath: []) // Don't recurse here, we'll handle children separately
            collectedElements.append(contentsOf: elementInfos)
        }

        // Recursively check children if we haven't reached max depth
        if currentDepth < maxDepth {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            if result == .success, let axChildren = value as? [AXUIElement] {
                for child in axChildren {
                    let childElements = await collectElementsInFrame(from: child, targetFrame: targetFrame, currentDepth: currentDepth + 1, maxDepth: maxDepth, applicationIdentifier: applicationIdentifier)
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

    /// Gets UI elements for an application with enhanced features:
    /// - Auto-opens applications if not running
    /// - Scans up to 5 levels deep
    /// - Can target specific screen areas
    /// - Can expand specific elements for more details
    func getUIElements(applicationIdentifier: String, frame: UIFrame? = nil, expandElementId: String? = nil) async throws -> [UIElementInfo] {
        os_log("Getting UI elements for %@ with frame: %@ and expand element: %@", log: log, type: .debug, applicationIdentifier, frame != nil ? "Specified" : "None", expandElementId ?? "None")
        
        // Auto-open application if not running
        if !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) {
            os_log("Auto-opening application %@", log: log, type: .info, applicationIdentifier)
            try await openApplication(bundleIdentifier: applicationIdentifier)
            // Give the application time to fully start
            try await Task.sleep(for: .seconds(3))
        }
        
        // If expanding a specific element, handle that separately
        if let expandId = expandElementId {
            return try await getElementChildren(applicationIdentifier: applicationIdentifier, elementId: expandId)
        }
        
        // If frame is specified, get elements in that frame
        if let targetFrame = frame {
            return try await getUIElementsInFrame(applicationIdentifier: applicationIdentifier, frame: targetFrame.cgRect)
        }
        
        // Otherwise, get full screen elements with deep scanning
        // Use a full screen frame to get all elements
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let fullScreenFrame = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
        
        // Use the working getUIElementsInFrame method but with deeper scanning
        return try await getUIElementsInFrameDeep(applicationIdentifier: applicationIdentifier, frame: fullScreenFrame, maxDepth: 5)
    }
    
    /// Enhanced version of getUIElementsInFrame with configurable depth
    private func getUIElementsInFrameDeep(applicationIdentifier: String, frame: CGRect, maxDepth: Int = 5) async throws -> [UIElementInfo] {
        os_log("Getting UI elements in frame with deep scanning (depth: %d) for %@", log: log, type: .debug, maxDepth, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) else {
            throw NudgeError.applicationNotRunning(bundleIdentifier: applicationIdentifier)
        }

        // Clear existing elements for this application
        elementRegistry = elementRegistry.filter { $0.value.applicationIdentifier != applicationIdentifier }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var relevantElements: [UIElementInfo] = []

        // Get focused window first
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        if focusedWindowResult == .success {
            let focusedWindow = focusedWindowValue as! AXUIElement
            let windowElements = await collectElementsInFrameDeep(from: focusedWindow, targetFrame: frame, currentDepth: 0, maxDepth: maxDepth, applicationIdentifier: applicationIdentifier)
            relevantElements.append(contentsOf: windowElements)
        } else {
            // Fallback to all windows
            var allWindowsValue: CFTypeRef?
            let allWindowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &allWindowsValue)

            if allWindowsResult == .success {
                let allWindows = allWindowsValue as! [AXUIElement]
                for window in allWindows {
                    let windowElements = await collectElementsInFrameDeep(from: window, targetFrame: frame, currentDepth: 0, maxDepth: maxDepth, applicationIdentifier: applicationIdentifier)
                    relevantElements.append(contentsOf: windowElements)
                }
            }
        }

        // Also get menu bar elements with deep scanning
        var menuBarValue: CFTypeRef?
        let menuBarResult = AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue)
        if menuBarResult == .success {
            let menuBar = menuBarValue as! AXUIElement
            let menuElements = await collectElementsInFrameDeep(from: menuBar, targetFrame: frame, currentDepth: 0, maxDepth: maxDepth, applicationIdentifier: applicationIdentifier)
            relevantElements.append(contentsOf: menuElements)
        }

        // Filter to only actionable elements
        let actionableElements = relevantElements.filter { $0.isActionable }
        
        os_log("Deep scanning found %d total elements, %d actionable for %@", log: log, type: .info, relevantElements.count, actionableElements.count, applicationIdentifier)
        return actionableElements
    }
    
    /// Enhanced version of collectElementsInFrame with configurable depth
    private func collectElementsInFrameDeep(from element: AXUIElement, targetFrame: CGRect, currentDepth: Int, maxDepth: Int, applicationIdentifier: String) async -> [UIElementInfo] {
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

        // For deep scanning, we want to include elements even if they don't have frames or intersect
        // This ensures we get menu items and other elements that might not have traditional frames
        let shouldInclude = elementFrame == nil || elementFrame!.intersects(targetFrame) || currentDepth <= 2
        
        if shouldInclude {
            // Build the UI element info for this element
            let elementInfos = await buildUIElementInfo(for: element, currentDepth: currentDepth, maxDepth: 0, applicationIdentifier: applicationIdentifier, parentPath: [])
            collectedElements.append(contentsOf: elementInfos)
        }

        // Always recurse for deep scanning, regardless of frame intersection
        if currentDepth < maxDepth {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            if result == .success, let axChildren = value as? [AXUIElement] {
                for child in axChildren {
                    let childElements = await collectElementsInFrameDeep(from: child, targetFrame: targetFrame, currentDepth: currentDepth + 1, maxDepth: maxDepth, applicationIdentifier: applicationIdentifier)
                    collectedElements.append(contentsOf: childElements)
                }
            }
        }

        return collectedElements
    }
    
    /// Gets children of a specific element for progressive disclosure
    func getElementChildren(applicationIdentifier: String, elementId: String) async throws -> [UIElementInfo] {
        os_log("Getting children for element %@ in application %@", log: log, type: .debug, elementId, applicationIdentifier)
        
        guard let registryEntry = elementRegistry[elementId] else {
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' not found")
        }
        
        let axElement = registryEntry.axElement
        let elementInfo = registryEntry.element
        
        // Build children with deeper scanning
        let children = await buildUIElementInfo(for: axElement, currentDepth: 0, maxDepth: 3, applicationIdentifier: applicationIdentifier, parentPath: elementInfo.path + [elementId])
        
        return children.filter { $0.isActionable }
    }
    
    /// Enhanced click function that handles path-based navigation
    func clickElementByIdWithNavigation(applicationIdentifier: String, elementId: String) async throws {
        os_log("Attempting to click element %@ with navigation for %@", log: log, type: .debug, elementId, applicationIdentifier)
        
        guard let registryEntry = elementRegistry[elementId] else {
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' not found")
        }
        
        let elementInfo = registryEntry.element
        let targetElement = registryEntry.axElement
        
        // Navigate through the path to reach the element
        try await navigateToElement(applicationIdentifier: applicationIdentifier, path: elementInfo.path, targetElement: targetElement)
        
        os_log("Successfully navigated to and clicked element %@", log: log, type: .info, elementId)
    }
    
    /// Navigates through a path of elements to reach a target
    private func navigateToElement(applicationIdentifier: String, path: [String], targetElement: AXUIElement) async throws {
        os_log("Navigating through path with %d elements", log: log, type: .debug, path.count)
        
        // Click through each element in the path
        for elementId in path {
            guard let pathEntry = elementRegistry[elementId] else {
                os_log("Path element %@ not found in registry", log: log, type: .error, elementId)
                continue
            }
            
            let pathElement = pathEntry.axElement
            
            // Check if this element needs to be expanded (like menus)
            if await isElementExpandable(pathElement) {
                os_log("Expanding path element %@", log: log, type: .debug, elementId)
                performClick(element: pathElement)
                
                // Brief pause to allow UI to update
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
        
        // Finally click the target element
        performClick(element: targetElement)
    }
    
    /// Checks if an element should be expanded during navigation
    private func isElementExpandable(_ element: AXUIElement) async -> Bool {
        guard let role = getAttribute(element, kAXRoleAttribute) as? String else { return false }
        
        let expandableRoles = [
            "AXMenuButton", "AXMenuItem", "AXPopUpButton", "AXMenuBarItem"
        ]
        
        return expandableRoles.contains(role)
    }
    
    /// Flattens a tree of UI elements into a single array
    private func flattenElements(_ elements: [UIElementInfo]) -> [UIElementInfo] {
        var flattened: [UIElementInfo] = []
        
        for element in elements {
            flattened.append(element)
            flattened.append(contentsOf: flattenElements(element.children))
        }
        
        return flattened
    }
    
    /// Updates UI state tree with deeper scanning (5 levels)
    private func updateUIStateTreeDeep(applicationIdentifier: String) async throws {
        os_log("Updating UI state tree with deep scanning for %@", log: log, type: .debug, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) else {
            throw NudgeError.applicationNotRunning(bundleIdentifier: applicationIdentifier)
        }

        // Clear existing elements for this application
        elementRegistry = elementRegistry.filter { $0.value.applicationIdentifier != applicationIdentifier }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var uiElements: [UIElementInfo] = []

        // Get focused window first
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        if focusedWindowResult == .success {
            let focusedWindow = focusedWindowValue as! AXUIElement
            let windowElements = await buildUIElementInfo(for: focusedWindow, currentDepth: 0, maxDepth: 5, applicationIdentifier: applicationIdentifier, parentPath: [])
            uiElements.append(contentsOf: windowElements)
        } else {
            // Fallback to all windows
            var allWindowsValue: CFTypeRef?
            let allWindowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &allWindowsValue)

            if allWindowsResult == .success {
                let allWindows = allWindowsValue as! [AXUIElement]
                for window in allWindows {
                    let windowElements = await buildUIElementInfo(for: window, currentDepth: 0, maxDepth: 5, applicationIdentifier: applicationIdentifier, parentPath: [])
                    uiElements.append(contentsOf: windowElements)
                }
            }
        }

        // Get menu bar with deeper scanning
        var menuBarValue: CFTypeRef?
        let menuBarResult = AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue)
        if menuBarResult == .success {
            let menuBar = menuBarValue as! AXUIElement
            let menuElements = await buildUIElementInfo(for: menuBar, currentDepth: 0, maxDepth: 5, applicationIdentifier: applicationIdentifier, parentPath: [])
            uiElements.append(contentsOf: menuElements)
        }

        let newTree = UIStateTree(applicationIdentifier: applicationIdentifier, treeData: uiElements, isStale: false, lastUpdated: Date())
        uiStateTrees[applicationIdentifier] = newTree
        
        os_log("Successfully updated deep UI state tree for %@ with %d elements", log: log, type: .info, applicationIdentifier, uiElements.count)
    }

}
