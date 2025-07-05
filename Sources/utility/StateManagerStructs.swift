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
    let elementType: String? // Type of element (Button, TextField, etc.)
    let hasChildren: Bool // Whether this element has child elements
    let isExpandable: Bool // Whether this element can be expanded for more details
    let path: [String] // Navigation path from root to this element (element IDs)
    let role: String? // AX role for internal use
    
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
    
    // Custom encoding to produce cleaner JSON for LLM
    enum CodingKeys: String, CodingKey {
        case id, description, elementType, hasChildren, isExpandable, path
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(elementType, forKey: .elementType)
        try container.encode(hasChildren, forKey: .hasChildren)
        try container.encode(isExpandable, forKey: .isExpandable)
        try container.encode(path, forKey: .path)
        // Note: Removed frame and children from JSON output to keep it clean for LLM
        // The frame is not needed since we use accessibility API for clicking
        // Children are handled separately through expansion
    }
    
    // Standard initializer for creating UIElementInfo in code
    init(id: String, frame: CGRect?, description: String?, children: [UIElementInfo], elementType: String? = nil, hasChildren: Bool = false, isExpandable: Bool = false, path: [String] = [], role: String? = nil) {
        self.id = id
        self.frame = frame
        self.description = description
        self.children = children
        self.elementType = elementType
        self.hasChildren = hasChildren
        self.isExpandable = isExpandable
        self.path = path
        self.role = role
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        elementType = try container.decodeIfPresent(String.self, forKey: .elementType)
        hasChildren = try container.decodeIfPresent(Bool.self, forKey: .hasChildren) ?? false
        isExpandable = try container.decodeIfPresent(Bool.self, forKey: .isExpandable) ?? false
        path = try container.decodeIfPresent([String].self, forKey: .path) ?? []
        // Set defaults for properties not in JSON
        frame = nil
        children = []
        role = nil
    }
}

/// Represents a frame for targeting specific UI areas
struct UIFrame: Codable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    
    var cgRect: CGRect {
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
