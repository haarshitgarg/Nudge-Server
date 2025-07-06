import Foundation

/// Represents the UI state tree for a specific application.
public struct UIStateTree: Codable, Sendable {
    public let applicationIdentifier: String // e.g., bundle identifier
    public var treeData: [UIElementInfo] // Placeholder for the actual UI tree data (e.g., JSON, XML)
    public var isStale: Bool = false // Indicates if the UI tree needs to be updated
    public let lastUpdated: Date // Timestamp of the last update
}

/// Simplified UI element structure with only essential fields
public struct UIElementInfo: Codable, Sendable {
    public let element_id: String
    public let description: String
    public let children: [UIElementInfo]
}

extension UIElementInfo {
    /// Determines if this UI element is actionable by the user
    public var isActionable: Bool {
        // Simple check - if it has a description and ID, it's actionable
        return !element_id.isEmpty && !description.isEmpty
    }
}
