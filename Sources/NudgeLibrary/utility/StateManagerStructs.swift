import Foundation

/// Represents the UI state tree for a specific application.
public struct UIStateTree: Codable, Sendable {
    let applicationIdentifier: String // e.g., bundle identifier
    var treeData: [UIElementInfo] // Placeholder for the actual UI tree data (e.g., JSON, XML)
    var isStale: Bool = false // Indicates if the UI tree needs to be updated
    let lastUpdated: Date // Timestamp of the last update
}

/// Simplified UI element structure with only essential fields
public struct UIElementInfo: Codable, Sendable {
    let element_id: String
    let description: String
    let children: [UIElementInfo]
}

extension UIElementInfo {
    /// Determines if this UI element is actionable by the user
    var isActionable: Bool {
        // Simple check - if it has a description and ID, it's actionable
        return !element_id.isEmpty && !description.isEmpty
    }
}
