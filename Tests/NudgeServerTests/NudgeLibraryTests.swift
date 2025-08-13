import XCTest
import AppKit
@testable import NudgeLibrary

final class NudgeLibraryTests: XCTestCase {
    
    // MARK: - Test Data and Setup
    
    var nudgeLibrary: NudgeLibrary!
    
    override func setUp() async throws {
        try await super.setUp()
        nudgeLibrary = NudgeLibrary.shared
        // Clean up any existing tools for clean test state
        await resetLibraryTools()
    }
    
    override func tearDown() async throws {
        await resetLibraryTools()
        nudgeLibrary = nil
        try await super.tearDown()
    }
    
    // Helper method to reset tools array for clean test state
    private func resetLibraryTools() async {
        // Since we can't directly reset the tools array, we'll work with the current state
        // In a real scenario, you might want to add a reset method to NudgeLibrary
    }
    
    // MARK: - Core Functionality Tests
    
    /**
     * Tests adding a tool with multiple parameters (both required and optional).
     * Expected behavior: Tool should be added with correct parameter schema.
     */
    func testAddToolWithMultipleParameters() async throws {
        let parameters = [
            ToolParameters(name: "required_param", type: "string", description: "A required parameter", required: true),
            ToolParameters(name: "optional_param", type: "number", description: "An optional parameter", required: false),
            ToolParameters(name: "boolean_param", type: "boolean", description: "A boolean parameter", required: true)
        ]
        
        await nudgeLibrary.addTool(
            name: "test_tool_multiple_params",
            description: "A test tool with multiple parameters",
            parameters: parameters
        )
        
        let tools = await nudgeLibrary.getNavTools()
        
        // Find our added tool
        let addedTool = tools.first { $0.name == "test_tool_multiple_params" }
        XCTAssertNotNil(addedTool, "Tool should be added to the tools list")
        
        guard let tool = addedTool else { return }
        
        // Verify tool properties
        XCTAssertEqual(tool.name, "test_tool_multiple_params", "Tool name should match")
        XCTAssertEqual(tool.description, "A test tool with multiple parameters", "Tool description should match")
        
        // Verify input schema structure
        guard case .object(let schemaDict) = tool.inputSchema else {
            XCTFail("Input schema should be an object")
            return
        }
        
        XCTAssertEqual(schemaDict["type"], "object", "Schema type should be object")
        
        // Verify properties
        guard case .object(let properties) = schemaDict["properties"] else {
            XCTFail("Properties should be an object")
            return
        }
        
        XCTAssertEqual(properties.count, 3, "Should have 3 parameters")
        XCTAssertTrue(properties.keys.contains("required_param"), "Should contain required_param")
        XCTAssertTrue(properties.keys.contains("optional_param"), "Should contain optional_param")
        XCTAssertTrue(properties.keys.contains("boolean_param"), "Should contain boolean_param")
        
        // Verify required array
        guard case .array(let requiredArray) = schemaDict["required"] else {
            XCTFail("Required should be an array")
            return
        }
        
        XCTAssertEqual(requiredArray.count, 2, "Should have 2 required parameters")
        XCTAssertTrue(requiredArray.contains(.string("required_param")), "Should include required_param in required array")
        XCTAssertTrue(requiredArray.contains(.string("boolean_param")), "Should include boolean_param in required array")
        XCTAssertFalse(requiredArray.contains(.string("optional_param")), "Should not include optional_param in required array")
    }
    
    /**
     * Tests adding a tool with no parameters.
     * Expected behavior: Tool should be added with empty parameters schema.
     */
    func testAddToolWithNoParameters() async throws {
        await nudgeLibrary.addTool(
            name: "test_tool_no_params",
            description: "A test tool with no parameters",
            parameters: nil
        )
        
        let tools = await nudgeLibrary.getNavTools()
        
        let addedTool = tools.first { $0.name == "test_tool_no_params" }
        XCTAssertNotNil(addedTool, "Tool should be added to the tools list")
        
        guard let tool = addedTool else { return }
        
        // Verify tool properties
        XCTAssertEqual(tool.name, "test_tool_no_params", "Tool name should match")
        XCTAssertEqual(tool.description, "A test tool with no parameters", "Tool description should match")
        
        // Verify input schema structure
        guard case .object(let schemaDict) = tool.inputSchema else {
            XCTFail("Input schema should be an object")
            return
        }
        
        // Verify properties is empty
        guard case .object(let properties) = schemaDict["properties"] else {
            XCTFail("Properties should be an object")
            return
        }
        
        XCTAssertEqual(properties.count, 0, "Should have 0 parameters")
        
        // Verify required array is empty
        guard case .array(let requiredArray) = schemaDict["required"] else {
            XCTFail("Required should be an array")
            return
        }
        
        XCTAssertEqual(requiredArray.count, 0, "Should have 0 required parameters")
    }
    
    /**
     * Tests adding a tool with only required parameters.
     * Expected behavior: All parameters should be in the required array.
     */
    func testAddToolWithOnlyRequiredParameters() async throws {
        let parameters = [
            ToolParameters(name: "param1", type: "string", description: "First required parameter", required: true),
            ToolParameters(name: "param2", type: "number", description: "Second required parameter", required: true)
        ]
        
        await nudgeLibrary.addTool(
            name: "test_tool_required_only",
            description: "A test tool with only required parameters",
            parameters: parameters
        )
        
        let tools = await nudgeLibrary.getNavTools()
        let addedTool = tools.first { $0.name == "test_tool_required_only" }
        XCTAssertNotNil(addedTool, "Tool should be added to the tools list")
        
        guard let tool = addedTool,
              case .object(let schemaDict) = tool.inputSchema,
              case .array(let requiredArray) = schemaDict["required"] else {
            XCTFail("Could not access tool schema")
            return
        }
        
        XCTAssertEqual(requiredArray.count, 2, "Should have 2 required parameters")
        XCTAssertTrue(requiredArray.contains(.string("param1")), "Should include param1 in required array")
        XCTAssertTrue(requiredArray.contains(.string("param2")), "Should include param2 in required array")
    }
    
    /**
     * Tests adding a tool with only optional parameters.
     * Expected behavior: Required array should be empty.
     */
    func testAddToolWithOnlyOptionalParameters() async throws {
        let parameters = [
            ToolParameters(name: "opt_param1", type: "string", description: "First optional parameter", required: false),
            ToolParameters(name: "opt_param2", type: "boolean", description: "Second optional parameter", required: false)
        ]
        
        await nudgeLibrary.addTool(
            name: "test_tool_optional_only",
            description: "A test tool with only optional parameters",
            parameters: parameters
        )
        
        let tools = await nudgeLibrary.getNavTools()
        let addedTool = tools.first { $0.name == "test_tool_optional_only" }
        XCTAssertNotNil(addedTool, "Tool should be added to the tools list")
        
        guard let tool = addedTool,
              case .object(let schemaDict) = tool.inputSchema,
              case .array(let requiredArray) = schemaDict["required"],
              case .object(let properties) = schemaDict["properties"] else {
            XCTFail("Could not access tool schema")
            return
        }
        
        XCTAssertEqual(requiredArray.count, 0, "Should have 0 required parameters")
        XCTAssertEqual(properties.count, 2, "Should have 2 total parameters")
        XCTAssertTrue(properties.keys.contains("opt_param1"), "Should contain opt_param1")
        XCTAssertTrue(properties.keys.contains("opt_param2"), "Should contain opt_param2")
    }
    
    // MARK: - Tool Integration Tests
    
    /**
     * Tests that added tools appear in getNavTools() return value.
     * Expected behavior: Both original NavServerTools and new tools should be present.
     */
    func testAddedToolsAppearInGetNavTools() async throws {
        // Get initial tools count (original NavServerTools)
        let initialTools = await nudgeLibrary.getNavTools()
        let initialCount = initialTools.count
        
        // Add a new tool
        await nudgeLibrary.addTool(
            name: "integration_test_tool",
            description: "A tool for testing integration",
            parameters: [
                ToolParameters(name: "test_param", type: "string", description: "A test parameter", required: true)
            ]
        )
        
        // Get tools after adding
        let updatedTools = await nudgeLibrary.getNavTools()
        
        XCTAssertEqual(updatedTools.count, initialCount + 1, "Should have one more tool after adding")
        
        // Verify the new tool is present
        let newTool = updatedTools.first { $0.name == "integration_test_tool" }
        XCTAssertNotNil(newTool, "New tool should be present in tools list")
        
        // Verify original tools are still present
        let originalToolNames = ["get_ui_elements", "click_element_by_id", "set_text_in_element", "save_to_clipboard", "ask_user"]
        for originalToolName in originalToolNames {
            let originalTool = updatedTools.first { $0.name == originalToolName }
            XCTAssertNotNil(originalTool, "Original tool \(originalToolName) should still be present")
        }
    }
    
    /**
     * Tests adding multiple tools and confirming all are included.
     * Expected behavior: All added tools should be present in the tools list.
     */
    func testAddingMultipleTools() async throws {
        let toolsToAdd = [
            ("tool_1", "First test tool"),
            ("tool_2", "Second test tool"),
            ("tool_3", "Third test tool")
        ]
        
        // Add multiple tools
        for (name, description) in toolsToAdd {
            await nudgeLibrary.addTool(
                name: name,
                description: description,
                parameters: [
                    ToolParameters(name: "param", type: "string", description: "A parameter", required: false)
                ]
            )
        }
        
        let tools = await nudgeLibrary.getNavTools()
        
        // Verify all added tools are present
        for (name, description) in toolsToAdd {
            let tool = tools.first { $0.name == name }
            XCTAssertNotNil(tool, "Tool \(name) should be present")
            XCTAssertEqual(tool?.description, description, "Tool \(name) should have correct description")
        }
    }
    
    // MARK: - Parameter Schema Validation Tests
    
    /**
     * Tests parameter types are correctly converted to MCP Value structure.
     * Expected behavior: Parameter types should be properly represented in the schema.
     */
    func testParameterTypeConversion() async throws {
        let parameterDefinitions = [
            ("string_param", "string", "String parameter", true),
            ("number_param", "number", "Number parameter", true),
            ("boolean_param", "boolean", "Boolean parameter", true),
            ("array_param", "array", "Array parameter", false)
        ]
        
        let parameters = parameterDefinitions.map { name, type, description, required in
            ToolParameters(name: name, type: type, description: description, required: required)
        }
        
        await nudgeLibrary.addTool(
            name: "type_conversion_test",
            description: "Testing parameter type conversion",
            parameters: parameters
        )
        
        let tools = await nudgeLibrary.getNavTools()
        let tool = tools.first { $0.name == "type_conversion_test" }
        XCTAssertNotNil(tool, "Tool should be added")
        
        guard let addedTool = tool,
              case .object(let schemaDict) = addedTool.inputSchema,
              case .object(let properties) = schemaDict["properties"] else {
            XCTFail("Could not access tool schema properties")
            return
        }
        
        // Verify each parameter type using the original definitions
        for (name, expectedType, expectedDescription, _) in parameterDefinitions {
            guard case .object(let paramDict) = properties[name] else {
                XCTFail("Parameter \(name) should be an object")
                continue
            }
            
            XCTAssertEqual(paramDict["type"], .string(expectedType), "Parameter \(name) should have correct type")
            XCTAssertEqual(paramDict["description"], .string(expectedDescription), "Parameter \(name) should have correct description")
        }
    }
    
    /**
     * Tests that required parameters array is correctly populated.
     * Expected behavior: Only required parameters should appear in the required array.
     */
    func testRequiredParametersArray() async throws {
        let parameterDefinitions = [
            ("required_1", "string", "Required param 1", true),
            ("optional_1", "string", "Optional param 1", false),
            ("required_2", "number", "Required param 2", true),
            ("optional_2", "boolean", "Optional param 2", false)
        ]
        
        let parameters = parameterDefinitions.map { name, type, description, required in
            ToolParameters(name: name, type: type, description: description, required: required)
        }
        
        await nudgeLibrary.addTool(
            name: "required_params_test",
            description: "Testing required parameters handling",
            parameters: parameters
        )
        
        let tools = await nudgeLibrary.getNavTools()
        let tool = tools.first { $0.name == "required_params_test" }
        
        guard let addedTool = tool,
              case .object(let schemaDict) = addedTool.inputSchema,
              case .array(let requiredArray) = schemaDict["required"] else {
            XCTFail("Could not access tool schema required array")
            return
        }
        
        XCTAssertEqual(requiredArray.count, 2, "Should have exactly 2 required parameters")
        XCTAssertTrue(requiredArray.contains(.string("required_1")), "Should include required_1")
        XCTAssertTrue(requiredArray.contains(.string("required_2")), "Should include required_2")
        XCTAssertFalse(requiredArray.contains(.string("optional_1")), "Should not include optional_1")
        XCTAssertFalse(requiredArray.contains(.string("optional_2")), "Should not include optional_2")
    }
    
    // MARK: - Edge Case Tests
    
    /**
     * Tests adding tool with empty parameters array.
     * Expected behavior: Tool should be added with empty schema.
     */
    func testAddToolWithEmptyParametersArray() async throws {
        await nudgeLibrary.addTool(
            name: "empty_params_test",
            description: "Testing empty parameters array",
            parameters: []
        )
        
        let tools = await nudgeLibrary.getNavTools()
        let tool = tools.first { $0.name == "empty_params_test" }
        XCTAssertNotNil(tool, "Tool should be added even with empty parameters array")
        
        guard let addedTool = tool,
              case .object(let schemaDict) = addedTool.inputSchema,
              case .object(let properties) = schemaDict["properties"],
              case .array(let requiredArray) = schemaDict["required"] else {
            XCTFail("Could not access tool schema")
            return
        }
        
        XCTAssertEqual(properties.count, 0, "Should have 0 parameters")
        XCTAssertEqual(requiredArray.count, 0, "Should have 0 required parameters")
    }
    
    /**
     * Tests adding tool with empty name or description.
     * Expected behavior: Tool should be added but with empty values.
     */
    func testAddToolWithEmptyNameOrDescription() async throws {
        await nudgeLibrary.addTool(
            name: "",
            description: "",
            parameters: nil
        )
        
        let tools = await nudgeLibrary.getNavTools()
        let tool = tools.first { $0.name == "" }
        XCTAssertNotNil(tool, "Tool should be added even with empty name")
        
        guard let addedTool = tool else { return }
        XCTAssertEqual(addedTool.name, "", "Tool name should be empty")
        XCTAssertEqual(addedTool.description, "", "Tool description should be empty")
    }
    
    /**
     * Tests parameter names with special characters.
     * Expected behavior: Special characters should be handled correctly in parameter names.
     */
    func testParameterNamesWithSpecialCharacters() async throws {
        let parameterDefinitions = [
            ("param_with_underscore", "string", "Parameter with underscore", true),
            ("param-with-dash", "string", "Parameter with dash", false),
            ("param.with.dots", "string", "Parameter with dots", true)
        ]
        
        let parameters = parameterDefinitions.map { name, type, description, required in
            ToolParameters(name: name, type: type, description: description, required: required)
        }
        
        await nudgeLibrary.addTool(
            name: "special_chars_test",
            description: "Testing special characters in parameter names",
            parameters: parameters
        )
        
        let tools = await nudgeLibrary.getNavTools()
        let tool = tools.first { $0.name == "special_chars_test" }
        XCTAssertNotNil(tool, "Tool should be added with special character parameter names")
        
        guard let addedTool = tool,
              case .object(let schemaDict) = addedTool.inputSchema,
              case .object(let properties) = schemaDict["properties"],
              case .array(let requiredArray) = schemaDict["required"] else {
            XCTFail("Could not access tool schema")
            return
        }
        
        XCTAssertTrue(properties.keys.contains("param_with_underscore"), "Should handle underscore in parameter name")
        XCTAssertTrue(properties.keys.contains("param-with-dash"), "Should handle dash in parameter name")
        XCTAssertTrue(properties.keys.contains("param.with.dots"), "Should handle dots in parameter name")
        
        XCTAssertEqual(requiredArray.count, 2, "Should have 2 required parameters")
        XCTAssertTrue(requiredArray.contains(.string("param_with_underscore")), "Should include parameter with underscore in required array")
        XCTAssertTrue(requiredArray.contains(.string("param.with.dots")), "Should include parameter with dots in required array")
    }
    
    /**
     * Tests very long parameter descriptions.
     * Expected behavior: Long descriptions should be handled correctly.
     */
    func testVeryLongParameterDescriptions() async throws {
        let longDescription = String(repeating: "This is a very long description. ", count: 100)
        
        let parameters = [
            ToolParameters(name: "param_with_long_desc", type: "string", description: longDescription, required: true)
        ]
        
        await nudgeLibrary.addTool(
            name: "long_description_test",
            description: "Testing very long parameter descriptions",
            parameters: parameters
        )
        
        let tools = await nudgeLibrary.getNavTools()
        let tool = tools.first { $0.name == "long_description_test" }
        XCTAssertNotNil(tool, "Tool should be added with long parameter description")
        
        guard let addedTool = tool,
              case .object(let schemaDict) = addedTool.inputSchema,
              case .object(let properties) = schemaDict["properties"],
              case .object(let paramDict) = properties["param_with_long_desc"] else {
            XCTFail("Could not access parameter with long description")
            return
        }
        
        XCTAssertEqual(paramDict["description"], .string(longDescription), "Long description should be preserved")
        XCTAssertGreaterThan(longDescription.count, 1000, "Description should actually be long for this test")
    }
}
