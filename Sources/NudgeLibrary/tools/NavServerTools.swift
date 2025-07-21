import Foundation
import MCP

public struct NavServerTools {
    public static let tools: [Tool] = [
        Tool(
            name: "get_ui_elements",
            description: "Get UI elements for an application in a tree structure with limited depth (2-3 levels). Automatically opens the application if not running, brings it to focus, and fills ui_state_tree with elements from focused window and menu bar. Returns tree with only 3 fields: element_id, description, children. Use this function to get an overview of the application state and its UI elements",
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
            description: "Click a UI element by its ID using direct AXUIElement reference for maximum performance and reliability. Returns a struct that includes the status of the operation and a new ui tree with the original element at its root to help find any other specific elements if required.",
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
        ),
        
        Tool(
            name: "set_text_in_element",
            description: "Use this tool to write text into text boxes, url location, mail area, code editor etc. It returns the updated UI tree after writing the text",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "bundle_identifier": .object([
                        "type": "string",
                        "description": "Bundle identifier of application"
                    ]),
                    "element_id": .object([
                        "type": "string",
                        "description": "Element ID of the text field (obtained from get_ui_elements)"
                    ]),
                    "text": .object([
                        "type": "string",
                        "description": "Text to set in the text field"
                    ])
                ]),
                "required": .array(["bundle_identifier", "element_id", "text"])
            ])
        )
    ]
    
    public static func getAllTools() -> [Tool] {
        return tools
    }
}
