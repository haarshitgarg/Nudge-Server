import Foundation

enum NudgeError: LocalizedError {
    // MARK: - Application Errors
    case applicationNotFound(bundleIdentifier: String)
    case applicationNotRunning(bundleIdentifier: String)
    case applicationLaunchFailed(bundleIdentifier: String, underlyingError: Error?)
    case applicationQuitFailed(bundleIdentifier: String, underlyingError: Error?)

    // MARK: - UI Element Interaction Errors
    case elementNotFound(description: String)
    case elementNotInteractable(description: String)
    case clickFailed(description: String, underlyingError: Error?)
    case typeTextFailed(description: String, underlyingError: Error?)
    case valueRetrievalFailed(description: String, underlyingError: Error?)
    case attributeNotFound(elementDescription: String, attribute: String)

    // MARK: - Accessibility API Errors
    case accessibilityPermissionDenied
    case accessibilityAPIError(underlyingError: Error?)
    case invalidAXUIElement(description: String)

    // MARK: - State Management Errors
    case uiStateTreeNotFound(applicationIdentifier: String)
    case uiStateTreeStale(applicationIdentifier: String)

    // MARK: - Network/Communication Errors (if applicable for server-side)
    case networkError(underlyingError: Error)
    case serverError(message: String)
    case invalidRequest(message: String)
    case invalidResponse(message: String)

    // MARK: - General Errors
    case invalidArgument(parameter: String, value: String, reason: String)
    case unexpectedError(message: String, underlyingError: Error?)
    case notImplemented(feature: String)

    var errorDescription: String? {
        switch self {
        case .applicationNotFound(let bundleIdentifier):
            return "Application with bundle identifier '\(bundleIdentifier)' was not found."
        case .applicationNotRunning(let bundleIdentifier):
            return "Application with bundle identifier '\(bundleIdentifier)' is not currently running."
        case .applicationLaunchFailed(let bundleIdentifier, let error):
            return "Failed to launch application '\(bundleIdentifier)'. Error: \(error?.localizedDescription ?? "Unknown error")."
        case .applicationQuitFailed(let bundleIdentifier, let error):
            return "Failed to quit application '\(bundleIdentifier)'. Error: \(error?.localizedDescription ?? "Unknown error")."

        case .elementNotFound(let description):
            return "UI element not found: \(description)."
        case .elementNotInteractable(let description):
            return "UI element is not interactable: \(description)."
        case .clickFailed(let description, let error):
            return "Failed to click on element '\(description)'. Error: \(error?.localizedDescription ?? "Unknown error")."
        case .typeTextFailed(let description, let error):
            return "Failed to type text into element '\(description)'. Error: \(error?.localizedDescription ?? "Unknown error")."
        case .valueRetrievalFailed(let description, let error):
            return "Failed to retrieve value from element '\(description)'. Error: \(error?.localizedDescription ?? "Unknown error")."
        case .attributeNotFound(let elementDescription, let attribute):
            return "Attribute '\(attribute)' not found for element: \(elementDescription)."

        case .accessibilityPermissionDenied:
            return "Accessibility permissions are denied. Please grant access in System Settings > Privacy & Security > Accessibility."
        case .accessibilityAPIError(let error):
            return "An error occurred with the macOS Accessibility API. Error: \(error?.localizedDescription ?? "Unknown error")."
        case .invalidAXUIElement(let description):
            return "Invalid AXUIElement encountered: \(description)."

        case .uiStateTreeNotFound(let applicationIdentifier):
            return "UI state tree not found for application: \(applicationIdentifier)."
        case .uiStateTreeStale(let applicationIdentifier):
            return "UI state tree for application '\(applicationIdentifier)' is marked as stale and needs to be updated."

        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)."
        case .serverError(let message):
            return "Server error: \(message)."
        case .invalidRequest(let message):
            return "Invalid request received: \(message)."
        case .invalidResponse(let message):
            return "Invalid response from server: \(message)."

        case .invalidArgument(let parameter, let value, let reason):
            return "Invalid argument for parameter '\(parameter)': '\(value)'. Reason: \(reason)."
        case .unexpectedError(let message, let error):
            return "An unexpected error occurred: \(message). Underlying error: \(error?.localizedDescription ?? "None")."
        case .notImplemented(let feature):
            return "Feature not yet implemented: \(feature)."
        }
    }
}
