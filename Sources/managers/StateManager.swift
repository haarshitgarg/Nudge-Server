import os
import Foundation

actor StateManager {
    // Defined the class singleton to make sure there is only one state manager
    static let shared = StateManager()
    private init() {}

    let log = OSLog(subsystem: "Harshit.NudgeServer", category: "StateManager")

    /// Represents the UI state tree for a specific application.
    struct UIStateTree {
        let applicationIdentifier: String // e.g., bundle identifier
        var treeData: String // Placeholder for the actual UI tree data (e.g., JSON, XML)
        var isStale: Bool = false // Indicates if the UI tree needs to be updated
        let lastUpdated: Date // Timestamp of the last update
    }

    /// A dictionary to store UI state trees, keyed by application identifier.
    private var uiStateTrees: [String: UIStateTree] = [:]

    /// Adds or updates a UI state tree for a given application.
    func updateUIStateTree(applicationIdentifier: String, treeData: String) {
        let newTree = UIStateTree(applicationIdentifier: applicationIdentifier, treeData: treeData, isStale: false, lastUpdated: Date())
        uiStateTrees[applicationIdentifier] = newTree
        os_log("Updated UI state tree for %@", log: log, type: .debug, applicationIdentifier)
    }

    /// Marks a UI state tree as stale.
    func markUIStateTreeAsStale(applicationIdentifier: String) {
        uiStateTrees[applicationIdentifier]?.isStale = true
        os_log("Marked the tree stale for %@", log: log, type: .debug, applicationIdentifier)
    }

    /// Retrieves the UI state tree for a given application.
    func getUIStateTree(applicationIdentifier: String) -> UIStateTree? {
        return uiStateTrees[applicationIdentifier]
    }

}
