import AppKit

struct LockScreenDisplayContext {
    let screen: NSScreen
    let frame: NSRect
    let identifier: String
}

@MainActor
final class LockScreenDisplayContextProvider {
    static let shared = LockScreenDisplayContextProvider()

    private(set) var context: LockScreenDisplayContext?
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        refresh(reason: "init")
        registerObservers()
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
    }

    @discardableResult
    func refresh(reason: String) -> LockScreenDisplayContext? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            context = nil
            return nil
        }

        let snapshot = LockScreenDisplayContext(
            screen: screen,
            frame: screen.frame,
            identifier: screen.localizedName
        )

        context = snapshot
        return snapshot
    }

    func contextSnapshot() -> LockScreenDisplayContext? {
        if let context {
            return context
        }
        return refresh(reason: "snapshot-miss")
    }

    private func registerObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(reason: "screen-parameters")
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(reason: "screens-did-wake")
        }

        let spaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(reason: "space-changed")
        }

        workspaceObservers = [wakeObserver, spaceObserver]
    }
}
