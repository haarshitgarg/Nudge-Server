import os
import Foundation
import AppKit
import CoreGraphics

actor StateManager {
    static let shared = StateManager()
    private init() {}

    let log = OSLog(subsystem: "Harshit.NudgeServer", category: "StateManager")

    /// A dictionary to store UI state trees, keyed by application identifier
    private var uiStateTrees: [String: UIStateTree] = [:]
    
    /// Counter for generating unique element IDs
    private var elementIdCounter: Int = 0
    
    /// Registry to store AXUIElement references by element ID for direct action performance
    private var elementRegistry: [String: AXUIElement] = [:]

    /// Main method to get UI elements - checks if app is open, opens if not, fills tree structure
    func getUIElements(applicationIdentifier: String) async throws -> [UIElementInfo] {
        os_log("Getting UI elements for %@", log: log, type: .debug, applicationIdentifier)
        
        // Check if application is running, if not open it and wait for it to be fully registered
        if !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) {
            os_log("Auto-opening application %@", log: log, type: .info, applicationIdentifier)
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
            let menuElements = await buildUIElementTree(for: menuBar as! AXUIElement, applicationIdentifier: applicationIdentifier, maxDepth: maxDepth)
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
            "AXSplitLayoutArea"  // Split layout containers - flatten to show layout content
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
        
        if let role = role {
            let cleanRole = role.replacingOccurrences(of: "AX", with: "")
            descriptionParts.append("(\(cleanRole))")
        }
        
        if let help = help, !help.isEmpty, help != title {
            descriptionParts.append("- \(help)")
        } else if let description = description, !description.isEmpty, description != title {
            descriptionParts.append("- \(description)")
        }
        
        return descriptionParts.joined(separator: " ")
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
    func updateUIElementTree(applicationIdentifier: String, elementId: String) async throws -> [UIElementInfo] {
        os_log("Updating UI element tree for element %@ in %@", log: log, type: .debug, elementId, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let axElement = elementRegistry[elementId] else {
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' not found. Call get_ui_elements first to populate the tree.")
        }
        
        // Build new tree from the specified element (full depth for updates)
        let updatedTree = await buildUIElementTree(for: axElement, applicationIdentifier: applicationIdentifier)
        
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
        elementIdCounter = 0
    }
    
    /// Helper to safely get an attribute from an AXUIElement
    private func getAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    /// Clicks a UI element by its ID using direct AXUIElement reference
    func clickElementById(applicationIdentifier: String, elementId: String) async throws {
        os_log("Clicking element %@ for %@", log: log, type: .debug, elementId, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let axElement = elementRegistry[elementId] else {
            throw NudgeError.invalidRequest(message: "Element with ID '\(elementId)' not found. Call get_ui_elements first.")
        }
        
        // Perform click action directly on AXUIElement
        let result = AXUIElementPerformAction(axElement, kAXPressAction as CFString)
        if result != .success {
            throw NudgeError.invalidRequest(message: "Failed to click element with ID '\(elementId)'")
        }
        
        os_log("Successfully clicked element %@", log: log, type: .info, elementId)
    }

    /// Checks if an element exists in the registry (for testing)
    func elementExists(elementId: String) -> Bool {
        return elementRegistry[elementId] != nil
    }
} 