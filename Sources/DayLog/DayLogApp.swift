import AppKit
import SwiftUI

@main
struct DayLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            if let model = delegate.model {
                PopoverView()
                    .environment(model)
                    .environment(\.openMainWindow, OpenMainWindowAction { delegate.showMainWindow() })
            }
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let model: AppModel?
    var body: some View {
        Image(systemName: model?.status.symbol ?? "exclamationmark.triangle")
            .accessibilityLabel("DayLog: \(model?.status.description ?? "error")")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel?
    private var mainWindow: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let model = try AppModel()
            self.model = model
            if !model.settings.onboarded { showMainWindow() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "DayLog couldn't open its database"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }

    func showMainWindow() {
        guard let model else { return }
        if mainWindow == nil {
            mainWindow = MainWindowController(model: model) { [weak self] in self?.showMainWindow() }
        }
        mainWindow?.show()
    }
}

/// Lets SwiftUI views ask the app delegate to show the AppKit-managed main window.
struct OpenMainWindowAction {
    let action: () -> Void
    func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var openMainWindow = OpenMainWindowAction {}
}
