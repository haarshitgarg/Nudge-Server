import Foundation

/// Represents the UI state tree for a specific application.
struct UIStateTree: Codable, Sendable {
    let applicationIdentifier: String // e.g., bundle identifier
    var treeData: [UIElementInfo] // Placeholder for the actual UI tree data (e.g., JSON, XML)
    var isStale: Bool = false // Indicates if the UI tree needs to be updated
    let lastUpdated: Date // Timestamp of the last update
}

struct UIElementInfo: Codable, Sendable {
    let title: String?
    let help: String?
    let value: String?
    let identifier: String?
    let frame: CGRect?
    let children: [UIElementInfo]
    
    /// Returns true if this element has meaningful content for LLM processing
    var hasMeaningfulContent: Bool {
        return (title != nil && !title!.isEmpty) || (help != nil && !help!.isEmpty)
    }
    
    /// Filters children to only include elements with meaningful content
    var meaningfulChildren: [UIElementInfo] {
        return children.filter { $0.hasMeaningfulContent }
    }
}
