import os
import Foundation
import AppKit
import CoreGraphics

public actor StateManager {
    static public let shared = StateManager()
    private init() {}

    let log = OSLog(subsystem: "Harshit.NudgeServer", category: "StateManager")

    /// A dictionary to store UI state trees, keyed by application identifier
    private var uiStateTrees: [String: UIStateTree] = [:]
    
    /// Counter for generating unique element IDs
    private var elementIdCounter: Int = 0
    
    /// Registry to store AXUIElement references by element ID for direct action performance
    private var elementRegistry: [String: AXUIElement] = [:]

    /// Main method to get UI elements - checks if app is open, opens if not, fills tree structure
    public func getUIElements(applicationIdentifier: String) async throws -> [UIElementInfo] {
        os_log("Getting UI elements for %@", log: log, type: .debug, applicationIdentifier)
        
        // Check if application is running, if not open it and wait for it to be fully registered
        if !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) {
            os_log("Auto-opening application %@", log: log, type: .info, applicationIdentifier)
            print("Auto-opening application \(applicationIdentifier)")
            try await openApplication(bundleIdentifier: applicationIdentifier)
            // Wait for the application to be fully registered in the system
            try await waitForApplication(bundleIdentifier: applicationIdentifier)
        }
        
        // Bring application to front/focus
        try await focusApplication(bundleIdentifier: applicationIdentifier)
        
        // Fill the UI state tree with focused window, menu bar, and elements (limited depth)
        try await fillUIStateTree(applicationIdentifier: applicationIdentifier, maxDepth: 2)
        
        // Return the tree structure
        return uiStateTrees[applicationIdentifier]?.treeData ?? []
    }
    
    /// Fills the UI state tree with focused window, menu bar, and elements in tree-based format
    private func fillUIStateTree(applicationIdentifier: String, maxDepth: Int = Int.max) async throws {
        os_log("Filling UI state tree for %@ with max depth %d", log: log, type: .debug, applicationIdentifier, maxDepth)

        guard AXIsProcessTrusted() else {
            throw NudgeError.accessibilityPermissionDenied
        }

        // App is guaranteed to be running by this point (checked in getUIElements)
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) else {
            os_log("Application %@ not found in running applications during tree fill", log: log, type: .error, applicationIdentifier)
            throw NudgeError.applicationNotRunning(bundleIdentifier: applicationIdentifier)
        }

        // Clear existing elements for this application
        clearElementsForApplication(applicationIdentifier)

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var treeData: [UIElementInfo] = []

        // Get focused window
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)

        if focusedWindowResult == .success, let focusedWindow = focusedWindowValue {
            let windowElements = await buildUIElementTree(for: focusedWindow as! AXUIElement, applicationIdentifier: applicationIdentifier, maxDepth: maxDepth)
            treeData.append(contentsOf: windowElements)
        }

        // Get menu bar
        var menuBarValue: CFTypeRef?
        let menuBarResult = AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue)
        if menuBarResult == .success, let menuBar = menuBarValue {
            let menuElements = await buildUIElementTree(for: menuBar as! AXUIElement, applicationIdentifier: applicationIdentifier, maxDepth: maxDepth + 1)
            treeData.append(contentsOf: menuElements)
        }

        // Store the tree in ui_state_tree
        let stateTree = UIStateTree(applicationIdentifier: applicationIdentifier, treeData: treeData, isStale: false, lastUpdated: Date())
        uiStateTrees[applicationIdentifier] = stateTree
        
        os_log("Successfully filled UI state tree for %@ with %d root elements", log: log, type: .info, applicationIdentifier, treeData.count)
    }
    
    /// Recursively builds UI element tree with only 3 fields: element_id, description, children
    /// Flattens container elements by returning their children directly
    private func buildUIElementTree(for element: AXUIElement, applicationIdentifier: String, maxDepth: Int = Int.max, currentDepth: Int = 0) async -> [UIElementInfo] {
        // Check if we've exceeded the maximum depth
        if currentDepth > maxDepth {
            return []
        }
        
        // Get element role to determine if it should be flattened
        guard let role = getAttribute(element, kAXRoleAttribute) as? String else {
            return []
        }
        
        // Define container roles that should be flattened (not stored, just return their children)
        let containerRolesToFlatten = [
            "AXGroup",           // Generic grouping containers - flatten to show actual content
            "AXScrollArea",      // Scroll areas - flatten to show scrollable content
            "AXLayoutArea",      // Layout containers - flatten to show arranged content
            "AXLayoutItem",      // Layout items - flatten to show contained content
            "AXSplitGroup",      // Split view containers - flatten to show split content
            "AXToolbar",         // Toolbar containers - flatten to show toolbar buttons
            "AXTabGroup",        // Tab group containers - flatten to show individual tabs
            "AXOutline",         // Outline containers - flatten to show outline items
            "AXList",            // List containers - flatten to show list items
            "AXTable",           // Table containers - flatten to show table content
            "AXBrowser",         // Browser containers - flatten to show browser content
            "AXGenericElement",  // Generic elements - usually non-actionable containers
            "AXSplitter",        // Splitter containers - flatten to show split panes
            "AXDockItem",        // Dock items - flatten to show dock content
            "AXDrawer",          // Drawer containers - flatten to show drawer content
            "AXPane",            // Pane containers - flatten to show pane content
            "AXSplitLayoutArea", // Split layout containers - flatten to show layout content
            "AXCell"
        ]
        
        // Check if this element should be flattened
        if containerRolesToFlatten.contains(role) {
            // Flatten: don't create an element for this container, just return its children
            var flattenedChildren: [UIElementInfo] = []
            
            var childrenValue: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
            
            if childrenResult == .success, let axChildren = childrenValue as? [AXUIElement] {
                for child in axChildren {
                    flattenedChildren.append(contentsOf: await buildUIElementTree(for: child, applicationIdentifier: applicationIdentifier, maxDepth: maxDepth, currentDepth: currentDepth))
                }
            }
            
            return flattenedChildren
        }
        

        
        // For non-container elements, create the element normally
        let elementId = generateElementId()
        
        // Store the AXUIElement for direct action performance
        elementRegistry[elementId] = element
        
        // Build description from available attributes
        let description = buildDescription(for: element)
        
        // Get children recursively
        var children: [UIElementInfo] = []
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        
        if childrenResult == .success, let axChildren = childrenValue as? [AXUIElement] {
            for child in axChildren {
                children.append(contentsOf: await buildUIElementTree(for: child, applicationIdentifier: applicationIdentifier, maxDepth: maxDepth, currentDepth: currentDepth + 1))
            }
        }
        
        // Only return elements that are actionable or have actionable children
        if isElementActionable(element) || !children.isEmpty {
            return [UIElementInfo(
                element_id: elementId,
                description: description,
                children: children
            )]
        }
        
        return []
    }
    
    /// Builds a concise description from element attributes
    private func buildDescription(for element: AXUIElement) -> String {
        var descriptionParts: [String] = []
        
        // Get key attributes
        let title = getAttribute(element, kAXTitleAttribute) as? String
        let value = getAttribute(element, kAXValueAttribute) as? String
        let role = getAttribute(element, kAXRoleAttribute) as? String
        let help = getAttribute(element, kAXHelpAttribute) as? String
        let description = getAttribute(element, kAXDescriptionAttribute) as? String
        
        // Build description prioritizing most important info
        if let title = title, !title.isEmpty {
            descriptionParts.append(title)
        }
        
        if let value = value, !value.isEmpty, value != title {
            descriptionParts.append(value)
        }
        
        // Special handling for AXCell elements - extract information from children
        if let role = role, role == "AXRow" || role == "AXColumn" {
            let childrenInfo = extractChildrenInfo(from: element)
            if !childrenInfo.isEmpty {
                descriptionParts.append(contentsOf: childrenInfo)
            }
        }
        
        if let role = role {
            let cleanRole = role.replacingOccurrences(of: "AX", with: "")
            descriptionParts.append("(\(cleanRole))")
        }
        
        if let help = help, !help.isEmpty, help != title {
            descriptionParts.append("- \(help)")
        } else if let description = description, !description.isEmpty, description != title {
            descriptionParts.append("- \(description)")
        }
        
        return descriptionParts.joined(separator: ", ")
    }
    
    /// Extracts useful information from children elements (used for AXCell, AXRow, AXColumn)
    private func extractChildrenInfo(from element: AXUIElement) -> [String] {
        var childrenInfo: [String] = []
        
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        
        if childrenResult == .success, let axChildren = childrenValue as? [AXUIElement] {
            for child in axChildren {
                // Get text content from child elements
                if let childTitle = getAttribute(child, kAXTitleAttribute) as? String, !childTitle.isEmpty {
                    childrenInfo.append(childTitle)
                }
                
                if let childValue = getAttribute(child, kAXValueAttribute) as? String, !childValue.isEmpty {
                    childrenInfo.append(childValue)
                }
                
                // For text fields and static text, get the value
                if let childRole = getAttribute(child, kAXRoleAttribute) as? String {
                    if childRole == "AXStaticText" || childRole == "AXTextField" {
                        if let text = getAttribute(child, kAXValueAttribute) as? String, !text.isEmpty {
                            childrenInfo.append(text)
                        }
                    }
                    
                    // Special handling for AXCell children - extract info from their children (grandchildren)
                    if childRole == "AXCell" {
                        let grandchildrenInfo = extractChildrenInfo(from: child)
                        childrenInfo.append(contentsOf: grandchildrenInfo)
                    }
                }
            }
        }
        
        // Remove duplicates and empty strings
        return Array(Set(childrenInfo)).filter { !$0.isEmpty }
    }
    
    /// Checks if an element is actionable
    private func isElementActionable(_ element: AXUIElement) -> Bool {
        guard let role = getAttribute(element, kAXRoleAttribute) as? String else { return false }
        
        let actionableRoles = [
            "AXButton", "AXTextField", "AXSecureTextField", "AXPopUpButton", 
            "AXMenuButton", "AXMenuItem", "AXCheckBox", "AXRadioButton", 
            "AXSlider", "AXIncrementor", "AXLink", "AXTab", "AXMenuBarItem", 
            "AXCell", "AXRow", "AXComboBox", "AXSearchField", "AXTextArea"
        ]
        
        return actionableRoles.contains(role)
    }
    
    /// Updates and returns the UI element tree for a specific element by its ID
    /// This allows for efficient partial tree updates without rescanning the entire application
    public func updateUIElementTree(applicationIdentifier: String, elementId: String) async throws -> [UIElementInfo] {
        os_log("Updating UI element tree for element %@ in %@", log: log, type: .debug, elementId, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let axElement = elementRegistry[elementId] else {
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' not found. Call get_ui_elements first to populate the tree.")
        }
        
        // Build new tree from the specified element (full depth for updates)
        let updatedTree = await buildUIElementTree(for: axElement, applicationIdentifier: applicationIdentifier, maxDepth: 3)
        
        // Update the internal tree structure by replacing the element
        if let existingTree = uiStateTrees[applicationIdentifier] {
            // Find and replace the element in the existing tree
            let updatedTreeData = replaceElementInTree(existingTree.treeData, targetElementId: elementId, newTree: updatedTree)
            
            // Create a new tree with updated data
            let newTree = UIStateTree(
                applicationIdentifier: applicationIdentifier,
                treeData: updatedTreeData,
                isStale: false,
                lastUpdated: Date()
            )
            
            uiStateTrees[applicationIdentifier] = newTree
            
            os_log("Successfully updated UI element tree for %@ with %d elements", log: log, type: .info, elementId, updatedTree.count)
        }
        
        return updatedTree
    }
    
    /// Helper method to replace an element in the tree structure
    private func replaceElementInTree(_ tree: [UIElementInfo], targetElementId: String, newTree: [UIElementInfo]) -> [UIElementInfo] {
        var updatedTree: [UIElementInfo] = []
        
        for element in tree {
            if element.element_id == targetElementId {
                // Replace this element with the new tree
                updatedTree.append(contentsOf: newTree)
            } else {
                // Keep the element but check its children recursively
                let updatedChildren = replaceElementInTree(element.children, targetElementId: targetElementId, newTree: newTree)
                updatedTree.append(UIElementInfo(
                    element_id: element.element_id,
                    description: element.description,
                    children: updatedChildren
                ))
            }
        }
        
        return updatedTree
    }

    /// Opens an application by bundle identifier
    private func openApplication(bundleIdentifier: String) async throws {
        let workspace = NSWorkspace.shared
        
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw NudgeError.applicationNotFound(bundleIdentifier: bundleIdentifier)
        }
        
        do {
            try await workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw NudgeError.applicationNotFound(bundleIdentifier: bundleIdentifier)
        }
    }
    
    /// Waits for an application to be fully registered in the system after opening
    private func waitForApplication(bundleIdentifier: String) async throws {
        let maxRetries = 10
        var retryCount = 0
        var delay: TimeInterval = 0.5
        
        while retryCount < maxRetries {
            // Check if application is now running
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            if !apps.isEmpty {
                print("App is running")
                return
            }
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier?.lowercased() == bundleIdentifier.lowercased() }) {
                os_log("Application %@ is now running after %d retries", log: log, type: .info, bundleIdentifier, retryCount)
                return
            }
            
            os_log("Waiting for application %@ to be registered (retry %d/%d)", log: log, type: .debug, bundleIdentifier, retryCount + 1, maxRetries)
            
            // Wait before retrying
            try await Task.sleep(for: .seconds(delay))
            
            // Exponential backoff with a maximum delay
            delay = min(delay * 1.5, 3.0)
            retryCount += 1
        }
        
        // If we get here, the app didn't start within our timeout
        throw NudgeError.applicationNotRunning(bundleIdentifier: bundleIdentifier)
    }
    
    /// Brings an application to the front/focus
    private func focusApplication(bundleIdentifier: String) async throws {
        // App is guaranteed to be running by this point (checked in getUIElements)
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == bundleIdentifier.lowercased() }) else {
            os_log("Application %@ not found in running applications during focus", log: log, type: .error, bundleIdentifier)
            throw NudgeError.applicationNotRunning(bundleIdentifier: bundleIdentifier)
        }
        
        // Activate the application to bring it to the front
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        
        // Give the application time to come to the front
        try await Task.sleep(for: .seconds(1))
        
        os_log("Successfully focused application %@", log: log, type: .info, bundleIdentifier)
    }
    
    /// Generates a unique element ID
    private func generateElementId() -> String {
        elementIdCounter += 1
        return "element_\(elementIdCounter)"
    }
    
    /// Clears all elements for a specific application
    private func clearElementsForApplication(_ applicationIdentifier: String) {
        // Remove from registry - for simplicity, we'll clear all elements when refreshing any app
        elementRegistry.removeAll()
        if( elementIdCounter >= 500) {
            elementIdCounter = 0
        }
    }
    
    /// Helper to safely get an attribute from an AXUIElement
    private func getAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }
    
    /// Gets the bundle identifier of the currently frontmost (active) application
    private func getCurrentFrontmostApplication() -> String? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            os_log("No frontmost application found", log: log, type: .error)
            return nil
        }
        
        let bundleId = frontmostApp.bundleIdentifier
        os_log("Current frontmost application: %@", log: log, type: .debug, bundleId ?? "unknown")
        return bundleId
    }
    /// Performs coordinate-based double-click as fallback when accessibility actions fail
    private func performDoubleClickFallback(element: AXUIElement) async throws -> Bool {
        // Get element position
        var positionValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        
        guard positionResult == .success,
              let position = positionValue,
              CFGetTypeID(position) == AXValueGetTypeID() else {
            os_log("Double-click fallback failed: Could not get element position", log: log, type: .error)
            return false
        }
        
        var point = CGPoint.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point) else {
            os_log("Double-click fallback failed: Could not extract CGPoint", log: log, type: .error)
            return false
        }
        
        // Get element size to click in center
        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        if sizeResult == .success,
           let size = sizeValue,
           CFGetTypeID(size) == AXValueGetTypeID() {
            var cgSize = CGSize.zero
            if AXValueGetValue(size as! AXValue, .cgSize, &cgSize) {
                point.x += cgSize.width / 2
                point.y += cgSize.height / 2
            }
        }
        
        os_log("Performing double-click at position (%f, %f)", log: log, type: .debug, point.x, point.y)
        
        // Create double-click events
        guard let mouseDown1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let mouseUp1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left),
              let mouseDown2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let mouseUp2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            os_log("Double-click fallback failed: Could not create mouse events", log: log, type: .error)
            return false
        }
        
        // Set click count for double-click
        mouseDown2.setIntegerValueField(.mouseEventClickState, value: 2)
        mouseUp2.setIntegerValueField(.mouseEventClickState, value: 2)
        
        // Post events with proper timing
        mouseDown1.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(10))
        mouseUp1.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(50))
        mouseDown2.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(10))
        mouseUp2.post(tap: .cghidEventTap)
        
        // Allow time for action to take effect
        try await Task.sleep(for: .milliseconds(200))
        
        os_log("Double-click completed", log: log, type: .debug)
        return true
    }

    /// Clicks a UI element by its ID using direct AXUIElement reference
    public func clickElementById(applicationIdentifier: String, elementId: String) async throws -> click_response {
        os_log("Clicking element %{public}@", log: log, type: .debug, elementId)

        guard AXIsProcessTrusted() else {
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let axElement = elementRegistry[elementId] else {
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' not found. Call get_ui_elements first.")
        }

        // Ensure the application is focused before performing any actions
        try await focusApplication(bundleIdentifier: applicationIdentifier)

        let elementSubrole = getAttribute(axElement, kAXSubroleAttribute) as? String
        
        // For AXOutlineRow elements (like Xcode project list), use double-click to open
        if elementSubrole == "AXOutlineRow" {
            os_log("AXOutlineRow detected - attempting double-click to open project", log: log, type: .info)
            
            // Try double-click first (this actually opens projects)
            do {
                let doubleClickSuccess = try await performDoubleClickFallback(element: axElement)
                if doubleClickSuccess {
                    // Wait for UI changes to settle
                    try await Task.sleep(for: .milliseconds(500))
                    
                    // Get the current frontmost application after the action
                    let currentFrontmostApp = getCurrentFrontmostApplication() ?? applicationIdentifier
                    let uitree = try await getUIElements(applicationIdentifier: currentFrontmostApp)
                    
                    let message = currentFrontmostApp != applicationIdentifier 
                        ? "Successfully clicked - the UI switched to \(currentFrontmostApp)"
                        : "Successfully clicked"
                    
                    return click_response(message: message, uiTree: uitree)
                }
            } catch {
                os_log("Double-click failed: %{public}@", log: log, type: .error, error.localizedDescription)
            }
            
            // Fallback to selection (better than complete failure)
            let result = AXUIElementPerformAction(axElement, "AXShowDefaultUI" as CFString)
            if result == .success {
                // Wait for UI changes to settle
                try await Task.sleep(for: .milliseconds(300))
                
                // Get complete UI tree for current frontmost app
                let currentFrontmostApp = getCurrentFrontmostApplication() ?? applicationIdentifier
                let uitree = try await getUIElements(applicationIdentifier: currentFrontmostApp)
                
                return click_response(message: "Project selected (not opened - double-click failed)", uiTree: uitree)
            }
            
            return click_response(message: "Failed to interact with project row", uiTree: [])
        }
        
        // For standard elements (buttons, etc.), use AXPress
        let result = AXUIElementPerformAction(axElement, kAXPressAction as CFString)
        if result == .success {
            // Wait for UI changes to settle
            try await Task.sleep(for: .milliseconds(300))
            
            // Get the current frontmost application after the action
            let currentFrontmostApp = getCurrentFrontmostApplication() ?? applicationIdentifier
            let uitree = try await getUIElements(applicationIdentifier: currentFrontmostApp)
            
            let message = currentFrontmostApp != applicationIdentifier 
                ? "Successfully clicked element - switched to \(currentFrontmostApp)"
                : "Successfully clicked the element"
            
            return click_response(message: message, uiTree: uitree)
        }
        
        // Simple fallback for standard elements
        let confirmResult = AXUIElementPerformAction(axElement, "AXConfirm" as CFString)
        if confirmResult == .success {
            // Wait for UI changes to settle
            try await Task.sleep(for: .milliseconds(300))
            
            // Get the current frontmost application after the action
            let currentFrontmostApp = getCurrentFrontmostApplication() ?? applicationIdentifier
            let uitree = try await getUIElements(applicationIdentifier: currentFrontmostApp)
            
            let message = currentFrontmostApp != applicationIdentifier 
                ? "Successfully clicked element - switched to \(currentFrontmostApp)"
                : "Successfully clicked the element"
            
            return click_response(message: message, uiTree: uitree)
        }
        
        return click_response(message: "Failed to click element with ID: \(elementId)", uiTree: [])
        
    }

    /// Sets text in a UI element by its ID using direct AXUIElement reference
    public func setTextInElement(applicationIdentifier: String, elementId: String, text: String) async throws -> text_input_response {
        // Delay after pressing Enter to allow page loading/processing
        let delayAfterEnter: TimeInterval = 0.5
        
        os_log("Setting text in element %{public}@ to: %{public}@", log: log, type: .debug, elementId, text)

        guard AXIsProcessTrusted() else {
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let axElement = elementRegistry[elementId] else {
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' not found. Call get_ui_elements first.")
        }

        // Verify the element is a text field
        guard let role = getAttribute(axElement, kAXRoleAttribute) as? String else {
            throw NudgeError.invalidRequest(message: "Could not determine element role for element '\(elementId)'.")
        }
        
        let textFieldRoles = ["AXTextField", "AXSecureTextField", "AXSearchField", "AXTextArea", "AXComboBox"]
        guard textFieldRoles.contains(role) else {
            throw NudgeError.invalidRequest(message: "Element '\(elementId)' is not a text field (role: \(role)). Text can only be set in text fields.")
        }

        // Ensure the application is focused before performing any actions
        try await focusApplication(bundleIdentifier: applicationIdentifier)

        // Focus the text field element first
        let focusResult = AXUIElementSetAttributeValue(axElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if focusResult != .success {
            // If direct focus fails, try focusing the parent window first
            var windowValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(axElement, kAXWindowAttribute as CFString, &windowValue) == .success,
               let window = windowValue {
                // Focus the window first
                AXUIElementSetAttributeValue(window as! AXUIElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                // Then focus the text field
                AXUIElementSetAttributeValue(axElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
        }
        
        // Small delay to ensure focus is set
        try await Task.sleep(for: .milliseconds(100))

        // Try to set the text using AXValue attribute
        let setValueResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFString)
        
        if setValueResult == .success {
            os_log("Successfully set text using AXValue attribute", log: log, type: .info)
            
            // Perform enter operation after setting text
            var message = "Successfully set text in element"
            do {
                try await performEnterOperation()
                message += " and pressed Enter"
                
                // Add delay after enter to allow page loading
                if delayAfterEnter > 0 {
                    try await Task.sleep(for: .seconds(delayAfterEnter))
                    message += " (waited \(Int(delayAfterEnter * 1000))ms for page to load)"
                }
            } catch {
                os_log("Enter operation failed: %{public}@", log: log, type: .error, error.localizedDescription)
                message += " but Enter operation failed"
            }
            
            let uitree = try await getUIElements(applicationIdentifier: applicationIdentifier)
            return text_input_response(message: message, uiTree: uitree)
        }
        
        // Fallback: Try using selected text attribute
        os_log("AXValue failed, trying selected text fallback", log: log, type: .debug)
        
        // First, select all existing text
        var textRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(axElement, kAXVisibleCharacterRangeAttribute as CFString, &textRangeValue) == .success,
           let textRange = textRangeValue {
            let selectAllResult = AXUIElementSetAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, textRange)
            if selectAllResult == .success {
                // Now replace the selected text
                let replaceResult = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFString)
                if replaceResult == .success {
                    os_log("Successfully set text using selected text fallback", log: log, type: .info)
                    
                    // Perform enter operation after setting text
                    var message = "Successfully set text in element (using fallback)"
                    do {
                        try await performEnterOperation()
                        message += " and pressed Enter"
                        
                        // Add delay after enter to allow page loading
                        if delayAfterEnter > 0 {
                            try await Task.sleep(for: .seconds(delayAfterEnter))
                            message += " (waited \(Int(delayAfterEnter * 1000))ms for page to load)"
                        }
                    } catch {
                        os_log("Enter operation failed: %{public}@", log: log, type: .error, error.localizedDescription)
                        message += " but Enter operation failed"
                    }
                    
                    let uitree = try await getUIElements(applicationIdentifier: applicationIdentifier)
                    return text_input_response(message: message, uiTree: uitree)
                }
            }
        }
        
        // Final fallback: Just try to set selected text directly
        let directReplaceResult = AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFString)
        if directReplaceResult == .success {
            os_log("Successfully set text using direct selected text", log: log, type: .info)
            
            // Perform enter operation after setting text
            var message = "Successfully set text in element (using direct fallback)"
            do {
                try await performEnterOperation()
                message += " and pressed Enter"
                
                // Add delay after enter to allow page loading
                if delayAfterEnter > 0 {
                    try await Task.sleep(for: .seconds(delayAfterEnter))
                    message += " (waited \(Int(delayAfterEnter * 1000))ms for page to load)"
                }
            } catch {
                os_log("Enter operation failed: %{public}@", log: log, type: .error, error.localizedDescription)
                message += " but Enter operation failed"
            }
            
            let uitree = try await getUIElements(applicationIdentifier: applicationIdentifier)
            return text_input_response(message: message, uiTree: uitree)
        }
        
        os_log("All text setting methods failed for element %{public}@", log: log, type: .error, elementId)
        return text_input_response(message: "Failed to set text in element with ID: \(elementId)", uiTree: [])
    }

    /// Performs enter key press operation on a focused element
    private func performEnterOperation() async throws {
        os_log("Performing enter key press operation", log: log, type: .debug)
        
        // Create enter key press event
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: false) else {
            os_log("Failed to create enter key events", log: log, type: .error)
            throw NudgeError.invalidRequest(message: "Failed to create enter key events")
        }
        
        // Post the key events
        keyDownEvent.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(10))
        keyUpEvent.post(tap: .cghidEventTap)
        
        // Small delay to allow the action to complete
        try await Task.sleep(for: .milliseconds(100))
        
        os_log("Enter key press operation completed", log: log, type: .info)
    }

    /// Checks if an element exists in the registry (for testing)
    func elementExists(elementId: String) -> Bool {
        return elementRegistry[elementId] != nil
    }

    public func cleanup() {
        elementRegistry.removeAll()
        if(elementIdCounter >= 500) {
            elementIdCounter = 0
        }
        uiStateTrees.removeAll()
    }
} 
