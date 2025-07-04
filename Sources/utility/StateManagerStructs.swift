import Foundation

/// Represents the UI state tree for a specific application.
struct UIStateTree: Codable, Sendable {
    let applicationIdentifier: String // e.g., bundle identifier
    var treeData: [UIElementInfo] // Placeholder for the actual UI tree data (e.g., JSON, XML)
    var isStale: Bool = false // Indicates if the UI tree needs to be updated
    let lastUpdated: Date // Timestamp of the last update
}

struct UIElementInfo: Codable, Sendable {
    let id: String // Unique identifier for this element
    let frame: CGRect?
    let description: String?
    let children: [UIElementInfo]
    
    /// Returns true if this element is actionable (user can interact with it)
    var isActionable: Bool {
        // Must have a description to be actionable
        guard let desc = description, !desc.isEmpty else { return false }
        
        // Must have reasonable size to be actionable
        let hasReasonableSize = frame?.width ?? 1 >= 15 && frame?.height ?? 1 >= 15
        guard hasReasonableSize else { return false }
        
        // Check if description contains actionable roles
        let actionableRoles = [
            "AXButton", "AXTextField", "AXSecureTextField", "AXPopUpButton", 
            "AXMenuButton", "AXMenuItem", "AXCheckBox", "AXRadioButton", 
            "AXSlider", "AXIncrementor", "AXLink", "AXTab", "AXMenuBarItem", 
            "AXCell", "AXRow", "AXComboBox", "AXSearchField", "AXTextArea"
        ]
        
        return actionableRoles.contains { desc.contains($0) }
    }
}
