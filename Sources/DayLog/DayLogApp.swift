import SwiftUI

@main
struct DayLogApp: App {
    var body: some Scene {
        MenuBarExtra("DayLog", systemImage: "clock") {
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}
