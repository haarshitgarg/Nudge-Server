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
        
        // Check if application is running, if not open it
        if !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) {
            os_log("Auto-opening application %@", log: log, type: .info, applicationIdentifier)
            try await openApplication(bundleIdentifier: applicationIdentifier)
            // Give the application time to fully start
            try await Task.sleep(for: .seconds(3))
        }
        
        // Fill the UI state tree with focused window, menu bar, and elements
        try await fillUIStateTree(applicationIdentifier: applicationIdentifier)
        
        // Return the tree structure
        return uiStateTrees[applicationIdentifier]?.treeData ?? []
    }
    
    /// Fills the UI state tree with focused window, menu bar, and elements in tree-based format
    private func fillUIStateTree(applicationIdentifier: String) async throws {
        os_log("Filling UI state tree for %@", log: log, type: .debug, applicationIdentifier)

        guard AXIsProcessTrusted() else {
            throw NudgeError.accessibilityPermissionDenied
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == applicationIdentifier.lowercased() }) else {
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
            let windowElements = await buildUIElementTree(for: focusedWindow as! AXUIElement, applicationIdentifier: applicationIdentifier)
            treeData.append(contentsOf: windowElements)
        }

        // Get menu bar
        var menuBarValue: CFTypeRef?
        let menuBarResult = AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue)
        if menuBarResult == .success, let menuBar = menuBarValue {
            let menuElements = await buildUIElementTree(for: menuBar as! AXUIElement, applicationIdentifier: applicationIdentifier)
            treeData.append(contentsOf: menuElements)
        }

        // Store the tree in ui_state_tree
        let stateTree = UIStateTree(applicationIdentifier: applicationIdentifier, treeData: treeData, isStale: false, lastUpdated: Date())
        uiStateTrees[applicationIdentifier] = stateTree
        
        os_log("Successfully filled UI state tree for %@ with %d root elements", log: log, type: .info, applicationIdentifier, treeData.count)
    }
    
    /// Recursively builds UI element tree with only 3 fields: element_id, description, children
    /// Flattens container elements by returning their children directly
    private func buildUIElementTree(for element: AXUIElement, applicationIdentifier: String) async -> [UIElementInfo] {
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
            "AXGenericElement"   // Generic elements - usually non-actionable containers
        ]
        
        // Check if this element should be flattened
        if containerRolesToFlatten.contains(role) {
            // Flatten: don't create an element for this container, just return its children
            var flattenedChildren: [UIElementInfo] = []
            
            var childrenValue: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
            
            if childrenResult == .success, let axChildren = childrenValue as? [AXUIElement] {
                for child in axChildren {
                    flattenedChildren.append(contentsOf: await buildUIElementTree(for: child, applicationIdentifier: applicationIdentifier))
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
                children.append(contentsOf: await buildUIElementTree(for: child, applicationIdentifier: applicationIdentifier))
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
} 