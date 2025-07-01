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
    let role: String? // AXRole of the element
    let isEnabled: Bool? // Whether the element is enabled/interactive
    let description: String? // AXDescription attribute
    let roleDescription: String? // AXRoleDescription attribute  
    let placeholderValue: String? // AXPlaceholderValue attribute
    
    /// Returns true if this element has meaningful content for LLM processing
    var hasMeaningfulContent: Bool {
        return (title != nil && !title!.isEmpty) || 
               (help != nil && !help!.isEmpty) ||
               (description != nil && !description!.isEmpty) ||
               (roleDescription != nil && !roleDescription!.isEmpty) ||
               (placeholderValue != nil && !placeholderValue!.isEmpty)
    }
    
    /// Returns true if this element is relevant for LLM decision-making and automation
    var isLLMRelevant: Bool {
        // First check: Filter out container/grouping elements that have no meaningful content
        let containerRoles = [
            "AXGroup",           // Generic grouping container
            "AXScrollArea",      // Scroll areas are usually not directly actionable
            "AXSplitter",        // UI splitters
            "AXLayoutArea",      // Layout containers
            "AXLayoutItem",      // Layout items
            "AXUnknown",         // Unknown elements
            "AXGenericElement",  // Generic elements without specific functionality
            "AXSplitGroup",      // Split view containers
            "AXToolbar",         // Toolbar containers (children are more relevant)
            "AXTabGroup"         // Tab group containers (individual tabs are more relevant)
        ]
        
        // Check if element has meaningful content
        let hasContent = (title != nil && !title!.isEmpty) || 
                        (help != nil && !help!.isEmpty) || 
                        (value != nil && !value!.isEmpty) ||
                        (identifier != nil && !identifier!.isEmpty)
        
        // For container roles, only keep them if they have meaningful content
        if let elementRole = role, containerRoles.contains(elementRole) {
            return hasContent
        }
        
        // Element should be enabled if it has an enabled state (filter out disabled splitters, etc.)
        let isInteractive = isEnabled ?? true // Assume enabled if not specified
        if isEnabled == false {
            return false // Always filter out explicitly disabled elements
        }
        
        // Filter out very small elements (likely decorative or spacers)
        let hasReasonableSize = frame?.width ?? 1 >= 10 && frame?.height ?? 1 >= 10
        
        // Define clearly interactive elements that should be prioritized
        let interactiveRoles = [
            "AXButton",          // Buttons
            "AXTextField",       // Text input fields
            "AXSecureTextField", // Password fields
            "AXPopUpButton",     // Dropdown menus
            "AXMenuButton",      // Menu buttons
            "AXMenuItem",        // Menu items
            "AXCheckBox",        // Checkboxes
            "AXRadioButton",     // Radio buttons
            "AXSlider",          // Sliders
            "AXIncrementor",     // Stepper controls
            "AXLink",            // Links
            "AXImage",           // Images (if they have help text or are clickable)
            "AXStaticText",      // Text elements (if they have meaningful content)
            "AXTab",             // Individual tabs
            "AXCell",            // Table/collection cells
            "AXRow",             // Table rows
            "AXOutline",         // Tree/outline items
            "AXList",            // Lists
            "AXTable",           // Tables
            "AXWebArea",         // Web content areas
            "AXApplication",     // Application elements
            "AXWindow",          // Windows
            "AXMenuBar",         // Menu bars
            "AXMenuBarItem"      // Menu bar items
        ]
        
        // Prioritize known interactive elements
        if let elementRole = role, interactiveRoles.contains(elementRole) {
            return hasContent && isInteractive && hasReasonableSize
        }
        
        // For unknown/other elements, be more permissive but still filter
        return hasContent && isInteractive && hasReasonableSize
    }
    
    /// Filters children to only include elements with meaningful content
    var meaningfulChildren: [UIElementInfo] {
        return children.filter { $0.hasMeaningfulContent }
    }
    
    /// Filters children to only include LLM-relevant elements
    var llmRelevantChildren: [UIElementInfo] {
        return children.filter { $0.isLLMRelevant }
    }
    
    /// Returns true if this element is actionable (user can interact with it)
    /// This is a stricter filter than isLLMRelevant, used specifically for getUIElementsInFrame
    var isActionable: Bool {
        // Must be enabled to be actionable
        guard isEnabled != false else { return false }
        
        // Must have reasonable size to be actionable
        let hasReasonableSize = frame?.width ?? 1 >= 15 && frame?.height ?? 1 >= 15
        guard hasReasonableSize else { return false }
        
        // Define truly actionable/interactive roles only
        let actionableRoles = [
            "AXButton",          // Buttons - directly clickable
            "AXTextField",       // Text input fields - user can type
            "AXSecureTextField", // Password fields - user can type
            "AXPopUpButton",     // Dropdown menus - user can select
            "AXMenuButton",      // Menu buttons - user can click
            "AXMenuItem",        // Menu items - user can select
            "AXCheckBox",        // Checkboxes - user can toggle
            "AXRadioButton",     // Radio buttons - user can select
            "AXSlider",          // Sliders - user can adjust
            "AXIncrementor",     // Stepper controls - user can increment/decrement
            "AXLink",            // Links - user can click
            "AXTab",             // Individual tabs - user can switch
            "AXMenuBarItem",     // Menu bar items - user can click
            "AXCell",            // Table/collection cells - user can select
            "AXRow",             // Table rows - user can select
            "AXComboBox",        // Combo boxes - user can select/type
            "AXSearchField",     // Search fields - user can type
            "AXTextArea",        // Text areas - user can type
            "AXProgressIndicator" // Progress indicators - if clickable/interactive
        ]
        
        // Check if element has an actionable role
        guard let elementRole = role, actionableRoles.contains(elementRole) else {
            return false
        }
        
        // For actionable elements, they should have some form of identification
        // (title, help, value, description, roleDescription, placeholderValue, or meaningful identifier)
        let hasIdentification = (title != nil && !title!.isEmpty) || 
                               (help != nil && !help!.isEmpty) || 
                               (value != nil && !value!.isEmpty) ||
                               (description != nil && !description!.isEmpty) ||
                               (roleDescription != nil && !roleDescription!.isEmpty) ||
                               (placeholderValue != nil && !placeholderValue!.isEmpty) ||
                               (identifier != nil && !identifier!.isEmpty && !identifier!.hasPrefix("_NS:"))
        
        return hasIdentification
    }
}
