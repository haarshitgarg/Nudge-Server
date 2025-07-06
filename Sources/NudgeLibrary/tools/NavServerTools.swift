import Foundation
import MCP

public struct NavServerTools {
    public static let tools: [Tool] = [
        Tool(
            name: "get_ui_elements",
            description: "Get UI elements for an application in a tree structure with limited depth (2-3 levels). Automatically opens the application if not running, brings it to focus, and fills ui_state_tree with focused window, menu bar, and elements. Returns tree with only 3 fields: element_id, description, children. Use this function to get an overview of the application state - if you need more details about specific elements, use update_ui_element_tree.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "bundle_identifier": .object([
                        "type": "string",
                        "description": "Bundle identifier of application (e.g., com.apple.safari for Safari)"
                    ])
                ]),
                "required": .array(["bundle_identifier"])
            ])
        ),
        
        Tool(
            name: "click_element_by_id",
            description: "Click a UI element by its ID using direct AXUIElement reference for maximum performance and reliability.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "bundle_identifier": .object([
                        "type": "string",
                        "description": "Bundle identifier of application"
                    ]),
                    "element_id": .object([
                        "type": "string",
                        "description": "Element ID obtained from get_ui_elements"
                    ])
                ]),
                "required": .array(["bundle_identifier", "element_id"])
            ])
        ),
        
        Tool(
            name: "update_ui_element_tree",
            description: "Update and return the UI element tree for a specific element by its ID. Call this function if you need more information about the children of a particular ui element. For example if from the available ui element id you feel like the final element must be under a certain element, call this function to get the updated tree.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "bundle_identifier": .object([
                        "type": "string",
                        "description": "Bundle identifier of application"
                    ]),
                    "element_id": .object([
                        "type": "string",
                        "description": "Element ID to update and return tree from (obtained from get_ui_elements)"
                    ])
                ]),
                "required": .array(["bundle_identifier", "element_id"])
            ])
        )
    ]
    
    public static func getAllTools() -> [Tool] {
        return tools
    }
}
