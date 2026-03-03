/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import SwiftUI
import SwiftTerm
import Defaults

/// Manages the Guake-style dropdown terminal session lifecycle.
/// The terminal is lazily created when the user first switches to the terminal tab,
/// and the process is kept alive across notch open/close cycles.
///
/// Uses a stable `containerView` (NSView) as the host so that SwiftUI's
/// `NSViewRepresentable` lifecycle (make/update/dismantle) never tears down
/// the actual terminal.  The `LocalProcessTerminalView` is added as a subview
/// of the container and survives notch close/open cycles.
@MainActor
class TerminalManager: ObservableObject {
    static let shared = TerminalManager()

    /// Whether a shell process is currently running.
    @Published var isProcessRunning: Bool = false

    /// The current terminal title reported by the shell.
    @Published var terminalTitle: String = "Terminal"

    /// Bumped on restart so the `NSViewRepresentable` can recreate via `.id()`.
    @Published var sessionGeneration: Int = 0

    /// Stable container returned to SwiftUI — never deallocated.
    let containerView: NSView = {
        let v = NSView(frame: .zero)
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true
        return v
    }()

    /// The actual terminal view (child of `containerView`).
    private(set) var terminalView: LocalProcessTerminalView?

    private init() {}

    // MARK: - Lifecycle

    /// Ensures the terminal view exists inside the container and returns the container.
    /// Call this from the `NSViewRepresentable` wrapper.
    func ensureTerminalView(delegate: LocalProcessTerminalViewDelegate) {
        if let existing = terminalView, existing.superview === containerView {
            // Already mounted — just re-wire the delegate in case the coordinator changed.
            existing.processDelegate = delegate
            return
        }

        let view = LocalProcessTerminalView(frame: containerView.bounds)
        view.autoresizingMask = [.width, .height]

        // Apply font size from settings
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        if let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) as NSFont? {
            view.font = font
        }

        // Apply opacity
        view.layer?.opacity = Float(Defaults[.terminalOpacity])

        // Configure the dark terminal appearance
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .white

        view.processDelegate = delegate

        // Mount inside the stable container
        containerView.subviews.forEach { $0.removeFromSuperview() }
        containerView.addSubview(view)
        terminalView = view
    }

    /// Starts the shell process if not already running.
    func startShellProcess() {
        guard let view = terminalView, !isProcessRunning else { return }

        let shell = Defaults[.terminalShellPath]
        let execName = "-" + (shell as NSString).lastPathComponent  // login shell convention

        view.startProcess(
            executable: shell,
            args: [],
            environment: buildEnvironment(),
            execName: execName
        )
        isProcessRunning = true
    }

    /// Called when the shell process terminates.
    func processDidTerminate(exitCode: Int32?) {
        isProcessRunning = false
    }

    /// Restarts the shell by tearing down the old terminal and creating a fresh one.
    func restartShell() {
        // Terminate the running process gracefully
        terminalView?.terminate()
        // Remove old terminal from container
        terminalView?.removeFromSuperview()
        terminalView = nil
        isProcessRunning = false
        terminalTitle = "Terminal"
        // Bump generation so the SwiftUI representable re-mounts
        sessionGeneration += 1
    }

    /// Updates the terminal title from the shell escape sequence.
    func updateTitle(_ title: String) {
        terminalTitle = title
    }

    /// Updates font size on the live terminal view.
    func applyFontSize(_ size: Double) {
        guard let view = terminalView else { return }
        if let font = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular) as NSFont? {
            view.font = font
        }
    }

    /// Updates opacity on the live terminal view.
    func applyOpacity(_ opacity: Double) {
        guard let view = terminalView else { return }
        view.layer?.opacity = Float(opacity)
    }

    // MARK: - Environment

    /// Builds the environment for the child shell process.
    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        // Remove TERM_PROGRAM if set by a parent terminal
        env.removeValue(forKey: "TERM_PROGRAM")
        return env.map { "\($0.key)=\($0.value)" }
    }
}
