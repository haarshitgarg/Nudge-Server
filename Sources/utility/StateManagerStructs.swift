import Foundation

/// Represents the UI state tree for a specific application.
struct UIStateTree: Codable, Sendable {
    let applicationIdentifier: String // e.g., bundle identifier
    var treeData: [UIElementInfo] // Placeholder for the actual UI tree data (e.g., JSON, XML)
    var isStale: Bool = false // Indicates if the UI tree needs to be updated
    let lastUpdated: Date // Timestamp of the last update
}

struct UIElementInfo: Codable, Sendable {
    let role: String
    let subrole: String?
    let title: String?
    let value: String?
    let frame: CGRect?
    let identifier: String?
    let help: String?
    let isEnabled: Bool?
    let isSelected: Bool?
    let isFocused: Bool?
    let children: [UIElementInfo]
}
