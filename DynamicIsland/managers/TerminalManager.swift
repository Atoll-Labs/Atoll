/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 * Adapted from SwiftTerm (https://github.com/migueldeicaza/SwiftTerm)
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

// MARK: - Stable Container

/// Container NSView that shields its terminal child from zero-sized frames.
///
/// When the notch closes, SwiftUI removes the `NSViewRepresentable` from the
/// hierarchy — but later re-adds the same `containerView` on reopen.  During
/// that insertion, SwiftUI momentarily sets the frame to `.zero`.  Without
/// protection, AppKit's autoresizing mask propagates the zero frame to the
/// terminal child, causing SwiftTerm's `processSizeChange` to resize the
/// emulator to 2 cols × 1 row (the enforced minimum), which destroys the
/// scrollback buffer.
///
/// We bypass `super.resizeSubviews(withOldSize:)` entirely and manually set
/// children to fill the container's bounds.  This avoids the autoresizing
/// calculation which produces corrupt geometry when `oldSize` was `.zero`
/// (recorded during the transient removal) but the child kept its previous
/// large frame.
final class StableTerminalContainerView: NSView {
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let size = bounds.size
        // Block degenerate sizes — the terminal would collapse to 2×1
        guard size.width >= 10, size.height >= 10 else { return }
        // Manually fill children to bounds — bypasses autoresizing math
        // that breaks when oldSize was zero but child kept its old frame.
        for child in subviews {
            child.frame = bounds
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // When re-inserted into a window (notch reopened), force a full
        // redraw so SwiftTerm re-renders the terminal buffer contents.
        for child in subviews {
            child.needsDisplay = true
        }
    }
}

// MARK: - Terminal Manager

/// Manages the Guake-style dropdown terminal session lifecycle.
/// The terminal is lazily created when the user first switches to the terminal tab,
/// and the process is kept alive across notch open/close cycles.
///
/// Uses a stable `StableTerminalContainerView` as the host so that SwiftUI's
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

    /// Stable container returned to SwiftUI — never deallocated.
    /// Uses `StableTerminalContainerView` to prevent zero-frame transients
    /// from destroying the scrollback buffer.
    let containerView: StableTerminalContainerView = {
        let v = StableTerminalContainerView(frame: .zero)
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
            // Force a redraw — the view may have been off-screen (notch closed)
            // and needs to re-render the terminal buffer.
            existing.needsDisplay = true
            return
        }

        // Use the container's current bounds if valid, otherwise a reasonable
        // default.  SwiftTerm's init calls setupOptions() which reads the
        // frame — a zero frame creates a 2×1 terminal that is corrected
        // once the container gets its proper layout size.
        let initialFrame = containerView.bounds.size.width >= 10
            ? containerView.bounds
            : CGRect(x: 0, y: 0, width: 400, height: 300)

        let view = LocalProcessTerminalView(frame: initialFrame)
        view.autoresizingMask = [.width, .height]

        // Apply all settings from Defaults
        applyAllSettings(to: view)

        view.processDelegate = delegate

        // Mount inside the stable container
        containerView.subviews.forEach { $0.removeFromSuperview() }
        containerView.addSubview(view)
        terminalView = view

        // If the container already has a valid size, snap the child to it.
        let containerSize = containerView.bounds.size
        if containerSize.width >= 10, containerSize.height >= 10 {
            view.frame = containerView.bounds
        }
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
    ///
    /// Instead of bumping a generation counter (which forced SwiftUI to destroy
    /// and recreate the `NSViewRepresentable` — recycling the same `containerView`
    /// across identities which broke layout), we simply nil out `terminalView`
    /// and change `@Published` state.  SwiftUI's `updateNSView` will fire,
    /// see the nil terminal, and call `ensureTerminalView` to mount a new one.
    func restartShell() {
        // Terminate the running process gracefully
        terminalView?.terminate()
        // Remove old terminal from container
        terminalView?.removeFromSuperview()
        terminalView = nil
        isProcessRunning = false
        terminalTitle = "Terminal"
    }

    /// Updates the terminal title from the shell escape sequence.
    func updateTitle(_ title: String) {
        terminalTitle = title
    }

    // MARK: - Font Resolution

    /// Resolves the terminal font from the user's chosen family and size.
    ///
    /// - If `family` is empty, returns the system monospaced font.
    /// - Otherwise tries `NSFont(name:size:)` and falls back to system monospaced
    ///   when the name is invalid or the font is not installed.
    private func resolveFont(family: String, size: CGFloat) -> NSFont {
        if !family.isEmpty, let custom = NSFont(name: family, size: size) {
            return custom
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Settings Application

    /// Applies all persisted settings to a terminal view at creation time.
    private func applyAllSettings(to view: LocalProcessTerminalView) {
        // Font
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        let fontFamily = Defaults[.terminalFontFamily]
        view.font = resolveFont(family: fontFamily, size: fontSize)

        // Opacity
        view.layer?.opacity = Float(Defaults[.terminalOpacity])

        // Colors
        view.nativeBackgroundColor = NSColor(Defaults[.terminalBackgroundColor])
        view.nativeForegroundColor = NSColor(Defaults[.terminalForegroundColor])
        view.caretColor = NSColor(Defaults[.terminalCursorColor])

        // Cursor style
        let cursorStyle = TerminalCursorStyleOption(rawValue: Defaults[.terminalCursorStyle])
            ?? .blinkBlock
        view.getTerminal().options.cursorStyle = cursorStyle.swiftTermStyle

        // Scrollback
        let scrollback = Defaults[.terminalScrollbackLines]
        view.getTerminal().buffer.changeHistorySize(scrollback)
        view.getTerminal().options.scrollback = scrollback

        // Input behavior
        view.optionAsMetaKey = Defaults[.terminalOptionAsMeta]
        view.allowMouseReporting = Defaults[.terminalMouseReporting]

        // Rendering
        view.useBrightColors = Defaults[.terminalBoldAsBright]
    }

    /// Updates font size on the live terminal view.
    func applyFontSize(_ size: Double) {
        guard let view = terminalView else { return }
        let fontFamily = Defaults[.terminalFontFamily]
        view.font = resolveFont(family: fontFamily, size: CGFloat(size))
    }

    /// Updates font family on the live terminal view.
    func applyFontFamily(_ family: String) {
        guard let view = terminalView else { return }
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        view.font = resolveFont(family: family, size: fontSize)
    }

    /// Updates opacity on the live terminal view.
    func applyOpacity(_ opacity: Double) {
        guard let view = terminalView else { return }
        view.layer?.opacity = Float(opacity)
    }

    /// Updates cursor style on the live terminal view.
    func applyCursorStyle(_ style: TerminalCursorStyleOption) {
        guard let view = terminalView else { return }
        view.getTerminal().options.cursorStyle = style.swiftTermStyle
        view.setNeedsDisplay(view.bounds)
    }

    /// Updates scrollback buffer size on the live terminal view.
    func applyScrollback(_ lines: Int) {
        guard let view = terminalView else { return }
        view.getTerminal().buffer.changeHistorySize(lines)
        view.getTerminal().options.scrollback = lines
    }

    /// Updates option-as-meta on the live terminal view.
    func applyOptionAsMeta(_ enabled: Bool) {
        guard let view = terminalView else { return }
        view.optionAsMetaKey = enabled
    }

    /// Updates mouse reporting on the live terminal view.
    func applyMouseReporting(_ enabled: Bool) {
        guard let view = terminalView else { return }
        view.allowMouseReporting = enabled
    }

    /// Updates bold-as-bright on the live terminal view.
    func applyBoldAsBright(_ enabled: Bool) {
        guard let view = terminalView else { return }
        view.useBrightColors = enabled
    }

    /// Updates background color on the live terminal view.
    func applyBackgroundColor(_ color: SwiftUI.Color) {
        guard let view = terminalView else { return }
        view.nativeBackgroundColor = NSColor(color)
    }

    /// Updates foreground color on the live terminal view.
    func applyForegroundColor(_ color: SwiftUI.Color) {
        guard let view = terminalView else { return }
        view.nativeForegroundColor = NSColor(color)
    }

    /// Updates cursor color on the live terminal view.
    func applyCursorColor(_ color: SwiftUI.Color) {
        guard let view = terminalView else { return }
        view.caretColor = NSColor(color)
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

// MARK: - Cursor Style Bridge

/// Codable-friendly cursor style enum that bridges to SwiftTerm's `CursorStyle`.
enum TerminalCursorStyleOption: String, CaseIterable, Defaults.Serializable {
    case blinkBlock = "blinkBlock"
    case steadyBlock = "steadyBlock"
    case blinkUnderline = "blinkUnderline"
    case steadyUnderline = "steadyUnderline"
    case blinkBar = "blinkBar"
    case steadyBar = "steadyBar"

    var swiftTermStyle: CursorStyle {
        switch self {
        case .blinkBlock: return .blinkBlock
        case .steadyBlock: return .steadyBlock
        case .blinkUnderline: return .blinkUnderline
        case .steadyUnderline: return .steadyUnderline
        case .blinkBar: return .blinkBar
        case .steadyBar: return .steadyBar
        }
    }

    var displayName: String {
        switch self {
        case .blinkBlock: return "Block (blinking)"
        case .steadyBlock: return "Block (steady)"
        case .blinkUnderline: return "Underline (blinking)"
        case .steadyUnderline: return "Underline (steady)"
        case .blinkBar: return "Bar (blinking)"
        case .steadyBar: return "Bar (steady)"
        }
    }
}
