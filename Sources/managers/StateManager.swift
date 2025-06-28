import os
import Foundation
import AppKit

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
        let role = getAttribute(element, kAXRoleAttribute) as? String ?? "Unknown"
        let subrole = getAttribute(element, kAXSubroleAttribute) as? String
        let title = getAttribute(element, kAXTitleAttribute) as? String
        let valueAttr = getAttribute(element, kAXValueAttribute) as? String
        let identifier = getAttribute(element, kAXIdentifierAttribute) as? String
        let help = getAttribute(element, kAXHelpAttribute) as? String
        let isEnabled = getAttribute(element, kAXEnabledAttribute) as? Bool
        let isSelected = getAttribute(element, kAXSelectedAttribute) as? Bool
        let isFocused = getAttribute(element, kAXFocusedAttribute) as? Bool

        var frame: CGRect?
        if let positionValue = getAttribute(element, kAXPositionAttribute),
           let sizeValue = getAttribute(element, kAXSizeAttribute) {
            var position: CGPoint = .zero
            var size: CGSize = .zero
            if AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) && AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
                frame = CGRect(origin: position, size: size)
            }
        }

        return UIElementInfo(
            role: role,
            subrole: subrole,
            title: title,
            value: valueAttr,
            frame: frame,
            identifier: identifier,
            help: help,
            isEnabled: isEnabled,
            isSelected: isSelected,
            isFocused: isFocused,
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

}
