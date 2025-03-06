//
//  URLCommandHandler.swift
//  Loop
//
//  Created by Kami on 06/03/2025.
//

/*
 Loop URL Scheme Documentation
 ===========================

 The Loop app supports URL scheme commands for window management and automation.
 Base URL format: loop://<command>/<parameters>

 Available Commands:
 -----------------

 1. Window Direction Commands:
    Format: loop://direction/<direction>
    Examples:
    - loop://direction/left       (Move window to left half)
    - loop://direction/right      (Move window to right half)
    - loop://direction/top        (Move window to top half)
    - loop://direction/bottom     (Move window to bottom half)
    - loop://direction/maximize   (Maximize window)
    - loop://direction/center     (Center window)

 2. Screen Management:
    Format: loop://screen/<command>
    Examples:
    - loop://screen/next          (Move window to next screen)
    - loop://screen/previous      (Move window to previous screen)

 3. Shell Commands:
    Format: loop://shell/<command>
    Examples:
    - loop://shell/open%20-a%20Loop    (Activate Loop app)
    - loop://shell/osascript%20-e%20%22tell%20application%20%5C%22Loop%5C%22%20to%20activate%22
    Note: Commands must be URL encoded

 4. AppleScript Commands:
    Format: loop://applescript/<script>
    Examples:
    - loop://applescript/tell%20application%20%22Loop%22%20to%20activate
    Note: Scripts must be URL encoded

 Usage Tips:
 ----------
 1. All commands are case-insensitive
 2. Scripts and commands with spaces must be URL encoded
 3. Window commands operate on the frontmost non-terminal window

 Examples:
 --------
 # Move current window to right half
 open "loop://direction/right"

 # Activate Loop via shell command
 open "loop://shell/open%20-a%20Loop"

 # Activate Loop via AppleScript
 open "loop://applescript/tell%20application%20%22Loop%22%20to%20activate"
 */

import Foundation
import SwiftUI

/// Handles URL scheme commands for the Loop application
final class URLCommandHandler {
    // MARK: - Properties

    /// Tracks the last active window before Loop to handle window management
    private var lastActiveWindow: Window?
    private var lastActiveTime: Date?

    /// Stores the current command to avoid selecting terminal windows showing the command
    private var currentCommand: String?

    // MARK: - Types

    /// Available URL scheme commands
    enum Command: String, CaseIterable {
        case direction // Window positioning commands
        case screen // Multi-screen management
        case shell // Shell command execution
        case applescript // AppleScript execution

        /// Human-readable description of each command
        var description: String {
            switch self {
            case .direction: "Window direction command"
            case .screen: "Screen management"
            case .shell: "Execute shell command"
            case .applescript: "Execute AppleScript"
            }
        }
    }

    // MARK: - Public Methods

    /// Handles incoming URL scheme requests
    /// - Parameter url: The URL to process
    func handle(_ url: URL) {
        currentCommand = url.absoluteString
        print("[URLHandler] Processing URL: \(url)")

        // Validate URL scheme
        guard url.scheme?.lowercased() == "loop" else {
            print("[URLHandler] Invalid scheme: \(url.scheme ?? "nil")")
            return
        }

        // Parse URL components
        var components = [String]()
        if let host = url.host {
            components.append(host)
        }
        components.append(contentsOf: url.pathComponents.filter { $0 != "/" && !$0.isEmpty })
        print("[URLHandler] Path components: \(components)")

        // Validate command
        guard !components.isEmpty else {
            print("[URLHandler] No command specified")
            return
        }

        guard let commandString = components.first,
              let command = Command(rawValue: commandString.lowercased()) else {
            print("[URLHandler] Invalid command: \(components.first ?? "nil")")
            print("[URLHandler] Available commands: \(Command.allCases.map(\.rawValue).joined(separator: ", "))")
            return
        }

        // Process command
        print("[URLHandler] Processing command: \(command.rawValue)")
        let parameters = Array(components.dropFirst())
        print("[URLHandler] Parameters: \(parameters)")

        switch command {
        case .direction: handleDirectionCommand(parameters)
        case .screen: handleScreenCommand(parameters)
        case .shell: handleShellCommand(parameters)
        case .applescript: handleAppleScriptCommand(parameters)
        }
    }

    // MARK: - Private Methods

    /// Handles window direction commands (left, right, top, bottom, etc.)
    /// - Parameter parameters: Direction parameters from the URL
    private func handleDirectionCommand(_ parameters: [String]) {
        guard let directionStr = parameters.first?.lowercased() else {
            print("[URLHandler] No direction specified")
            print("[URLHandler] Available directions: \(WindowDirection.allCases.map { $0.rawValue.lowercased() }.joined(separator: ", "))")
            return
        }

        print("[URLHandler] Processing direction: \(directionStr)")

        // Try exact match first
        if let direction = WindowDirection.allCases.first(where: { $0.rawValue.lowercased() == directionStr }) {
            executeWindowAction(direction)
            return
        }

        // Try common aliases
        let direction: WindowDirection?
        switch directionStr {
        case "left": direction = .leftHalf
        case "right": direction = .rightHalf
        case "top": direction = .topHalf
        case "bottom": direction = .bottomHalf
        default:
            // Try without "half" suffix
            let withoutHalf = directionStr.replacingOccurrences(of: "half", with: "")
            direction = WindowDirection.allCases.first { $0.rawValue.lowercased() == withoutHalf }
        }

        if let direction {
            executeWindowAction(direction)
        } else {
            print("[URLHandler] Invalid direction: \(directionStr)")
            print("[URLHandler] Available directions:")
            print("  Basic: left, right, top, bottom")
            print("  Full names: \(WindowDirection.allCases.map { $0.rawValue.lowercased() }.joined(separator: ", "))")
        }
    }

    /// Executes a window movement/resize action
    /// - Parameter direction: The direction to move/resize the window
    private func executeWindowAction(_ direction: WindowDirection) {
        print("[URLHandler] Executing direction: \(direction.rawValue)")

        // Get all windows and filter for eligible ones
        let allWindows = WindowEngine.windowList
        print("[URLHandler] Found \(allWindows.count) total windows")

        let visibleWindows = allWindows.filter { win in
            guard let app = win.nsRunningApplication else {
                print("[URLHandler] Window has no application: \(win.title ?? "unknown")")
                return false
            }

            let isLoop = app.bundleIdentifier == Bundle.main.bundleIdentifier
            let isRegular = app.activationPolicy == .regular
            let isVisible = !win.isHidden && !win.minimized

            logWindowDetails(win, app, isLoop, isRegular, isVisible, false)

            return !isLoop && isRegular && isVisible
        }

        print("[URLHandler] Found \(visibleWindows.count) eligible windows")

        // Find target window
        guard let window = findTargetWindow(from: visibleWindows) else {
            print("[URLHandler] No suitable windows found")
            return
        }

        guard let screen = NSScreen.main else {
            print("[URLHandler] Failed to get main screen")
            return
        }

        logSelectedWindow(window, screen)

        // Execute the action
        let action = WindowAction(direction)
        print("[URLHandler] Resizing window with action: \(direction.rawValue)")

        activateAndResizeWindow(window, action, screen)
    }

    /// Handles screen management commands (next, previous)
    /// - Parameter parameters: Screen command parameters
    private func handleScreenCommand(_ parameters: [String]) {
        guard let command = parameters.first?.lowercased(),
              let window = try? WindowEngine.getFrontmostWindow() else {
            print("[URLHandler] No screen command or window")
            return
        }

        print("[URLHandler] Processing screen command: \(command)")

        let direction: WindowDirection
        switch command {
        case "next": direction = .nextScreen
        case "previous": direction = .previousScreen
        default:
            print("[URLHandler] Invalid screen command: \(command)")
            return
        }

        moveWindowToScreen(window, direction)
    }

    /// Handles shell command execution
    /// - Parameter parameters: Shell command parameters
    private func handleShellCommand(_ parameters: [String]) {
        guard !parameters.isEmpty else {
            print("[URLHandler] No shell command specified")
            return
        }

        let command = parameters.joined(separator: " ")
        print("[URLHandler] Executing shell command: \(command)")

        executeShellCommand(command)
    }

    /// Handles AppleScript execution
    /// - Parameter parameters: AppleScript parameters
    private func handleAppleScriptCommand(_ parameters: [String]) {
        guard !parameters.isEmpty else {
            print("[URLHandler] No AppleScript specified")
            return
        }

        let script = parameters.joined(separator: " ")
        print("[URLHandler] Executing AppleScript: \(script)")

        executeAppleScript(script)
    }

    // MARK: - Helper Methods

    /// Logs window details for debugging
    private func logWindowDetails(_ window: Window, _ app: NSRunningApplication, _ isLoop: Bool, _ isRegular: Bool, _ isVisible: Bool, _ isShowingCommand: Bool) {
        print("[URLHandler] Window: \(window.title ?? "unknown")")
        print("  - App: \(app.localizedName ?? "unknown")")
        print("  - Bundle ID: \(app.bundleIdentifier ?? "unknown")")
        print("  - Is Loop: \(isLoop)")
        print("  - Is Regular: \(isRegular)")
        print("  - Is Visible: \(isVisible)")
        print("  - Is Showing Command: \(isShowingCommand)")
    }

    /// Finds the most appropriate target window
    private func findTargetWindow(from visibleWindows: [Window]) -> Window? {
        // Try last active window
        if let lastWindow = lastActiveWindow,
           let app = lastWindow.nsRunningApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier,
           !lastWindow.isHidden, !lastWindow.minimized,
           let lastTime = lastActiveTime,
           lastTime.timeIntervalSinceNow > -5 {
            print("[URLHandler] Using last active window: \(lastWindow.title ?? "unknown")")
            return lastWindow
        }

        // Try frontmost window
        if let frontmost = try? WindowEngine.getFrontmostWindow(),
           let app = frontmost.nsRunningApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            print("[URLHandler] Using frontmost window: \(frontmost.title ?? "unknown")")
            return frontmost
        }

        // Use first visible window that isn't Loop
        return visibleWindows.first
    }

    /// Logs selected window details
    private func logSelectedWindow(_ window: Window, _ screen: NSScreen) {
        print("[URLHandler] Selected window for action:")
        print("  - Title: \(window.title ?? "unknown")")
        print("  - App: \(window.nsRunningApplication?.localizedName ?? "unknown")")
        print("  - Screen: \(screen.localizedName)")
        print("  - Current Frame: \(window.frame)")
    }

    /// Activates and resizes a window
    private func activateAndResizeWindow(_ window: Window, _ action: WindowAction, _ screen: NSScreen) {
        // Store as last active window
        lastActiveWindow = window
        lastActiveTime = Date()

        // Activate the window's application
        if let app = window.nsRunningApplication {
            print("[URLHandler] Activating application: \(app.localizedName ?? "unknown")")
            app.activate(options: .activateIgnoringOtherApps)
        }

        // Resize with delay to ensure activation is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("[URLHandler] Executing resize operation")
            WindowEngine.resize(window, to: action, on: screen)
            print("[URLHandler] New window frame: \(window.frame)")
        }
    }

    /// Moves a window to another screen
    private func moveWindowToScreen(_ window: Window, _ direction: WindowDirection) {
        if let currentScreen = ScreenManager.screenContaining(window),
           let targetScreen = direction == .nextScreen ?
           ScreenManager.nextScreen(from: currentScreen) :
           ScreenManager.previousScreen(from: currentScreen) {
            let action = WindowAction(direction)
            print("[URLHandler] Moving window to screen: \(targetScreen.localizedName)")
            DispatchQueue.main.async {
                WindowEngine.resize(window, to: action, on: targetScreen)
            }
        } else {
            print("[URLHandler] Failed to find target screen")
        }
    }

    /// Executes a shell command
    private func executeShellCommand(_ command: String) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("[URLHandler] Shell output: \(output)")
            }

            task.waitUntilExit()
            print("[URLHandler] Shell command completed with status: \(task.terminationStatus)")
        } catch {
            print("[URLHandler] Error executing shell command: \(error)")
        }
    }

    /// Executes an AppleScript
    private func executeAppleScript(_ script: String) {
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?

        DispatchQueue.global(qos: .userInitiated).async {
            let result = appleScript?.executeAndReturnError(&error)

            DispatchQueue.main.async {
                if let error {
                    print("[URLHandler] Error executing AppleScript: \(error)")
                } else if let result {
                    print("[URLHandler] AppleScript executed successfully")
                    print("[URLHandler] Result: \(result.stringValue ?? "no output")")
                }
            }
        }
    }
}
