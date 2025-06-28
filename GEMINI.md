# Gemini Agent Guidelines for Nudge-Server Project

This document outlines specific guidelines for the Gemini agent when interacting with and modifying the `Nudge-Server` project. Adhering to these principles will ensure efficient, maintainable, and high-quality contributions.

## Code Contribution Philosophy

1.  **Incremental Changes:** Avoid large, monolithic code drops. Prefer to introduce changes in small, logical, and digestible pieces. This facilitates easier review, debugging, and understanding.
2.  **Suggest, Don't Just Implement:** When appropriate, provide suggestions or alternative approaches before directly implementing complex solutions. This allows for collaborative decision-making and ensures alignment with project goals.
3.  **Big Picture Thinking:** Always consider the broader architectural implications and long-term maintainability of any proposed change. Avoid short-term fixes that might lead to technical debt or complicate future development. Think about scalability, testability, and adherence to existing patterns.
4. Write as many test cases as you can. Check the whole codebase and based on that add test cases whenever prompted. 

## Boilerplate Code Generation

When asked to add boilerplate code, pay close attention to special markers within the codebase:

*   **`// AI MARKER <instruction>`**: If you encounter a comment formatted as `// AI MARKER <instruction>`, use the `<instruction>` part to guide the generation of the boilerplate code. This marker will provide specific context or requirements for the code to be inserted at that location. Extract relevant information from this instruction to tailor the generated code appropriately.

By following these guidelines, the Gemini agent will contribute more effectively and seamlessly to the `Nudge-Server` project.
