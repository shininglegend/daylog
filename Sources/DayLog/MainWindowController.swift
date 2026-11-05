import AppKit
import SwiftUI

/// The main window is AppKit-managed so it can be opened at first launch and
/// from the popover regardless of SwiftUI scene state in a Dock-less app.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        let root = MainView()
            .environment(model)
            .environment(\.openMainWindow, OpenMainWindowAction(action: openMainWindow))
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "DayLog"
        window.setContentSize(NSSize(width: 900, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("DayLogMain")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        model.mainWindowUnlocked = false
    }
}
