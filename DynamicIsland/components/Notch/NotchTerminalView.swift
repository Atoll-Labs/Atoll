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

import SwiftUI
import SwiftTerm
import Defaults

// MARK: - NSViewRepresentable wrapper for SwiftTerm

/// Bridges SwiftTerm's `LocalProcessTerminalView` (NSView) into SwiftUI.
///
/// Returns `TerminalManager.containerView` (a stable NSView) so that
/// SwiftUI's view lifecycle never tears down the actual terminal.  The
/// real `LocalProcessTerminalView` lives as a subview of that container
/// and survives notch close/open and tab-switch cycles.
struct TerminalNSViewRepresentable: NSViewRepresentable {
    @ObservedObject var terminalManager = TerminalManager.shared

    func makeNSView(context: Context) -> NSView {
        context.coordinator.terminalManager = terminalManager
        terminalManager.ensureTerminalView(delegate: context.coordinator)
        if !terminalManager.isProcessRunning {
            terminalManager.startShellProcess()
        }
        return terminalManager.containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-mount terminal if it was restarted (generation bumped).
        terminalManager.ensureTerminalView(delegate: context.coordinator)
        if !terminalManager.isProcessRunning {
            terminalManager.startShellProcess()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminalManager: TerminalManager?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal resized — no action needed; SwiftTerm handles reflow.
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor in
                terminalManager?.updateTitle(title)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Could be used for breadcrumbs in the future.
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                terminalManager?.processDidTerminate(exitCode: exitCode)
            }
        }
    }
}

// MARK: - Notch Tab View

/// Guake-style dropdown terminal tab for the notch.
/// Dynamically sizes up to half the screen height; content scrolls when the
/// terminal buffer exceeds the visible area (handled internally by SwiftTerm).
struct NotchTerminalView: View {
    @ObservedObject var terminalManager = TerminalManager.shared
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.enableTerminalFeature) var enableTerminalFeature
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    var body: some View {
        VStack(spacing: 0) {
            if enableTerminalFeature {
                // Terminal header bar
                HStack {
                    Image(systemName: "apple.terminal")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))

                    Text(terminalManager.terminalTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    // Restart button
                    Button {
                        terminalManager.restartShell()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Restart shell")
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)

                Divider()
                    .padding(.horizontal, 8)

                // Terminal content — .id(sessionGeneration) forces
                // representable recreation only after an explicit restart.
                TerminalNSViewRepresentable(terminalManager: terminalManager)
                    .id(terminalManager.sessionGeneration)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .padding(.top, 4)
                    .onHover { hovering in
                        updateSuppression(for: hovering)
                    }
            } else {
                // Feature disabled placeholder
                VStack(spacing: 8) {
                    Image(systemName: "apple.terminal")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    Text("Terminal is disabled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Enable it in Settings → Terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear {
            updateSuppression(for: false)
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}
