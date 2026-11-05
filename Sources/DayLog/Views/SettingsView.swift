import DayLogCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false
    @State private var automation: Permissions.AutomationStatus = .unknown
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Recording") {
                Picker("Check every", selection: setting(\.pollInterval)) {
                    ForEach([2.0, 5, 10, 15, 30], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                Picker("Idle after", selection: setting(\.idleThreshold)) {
                    ForEach([60.0, 120, 300, 600, 900], id: \.self) { Text("\(Int($0) / 60) minutes").tag($0) }
                }
                Picker("Keep daily totals", selection: setting(\.totalsRetentionDays)) {
                    ForEach(Preferences.retentionChoices, id: \.self) { days in
                        Text(days.map { "\($0) days" } ?? "Forever").tag(days)
                    }
                }
                Text("Window titles, websites, and individual entries are always deleted after 48 hours.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        if on != model.launchAtLogin { model.setLaunchAtLogin(on) }
                        launchAtLogin = model.launchAtLogin
                    }
                Toggle("Require Touch ID to open this window", isOn: setting(\.requireTouchID))
                Text("This only locks the window. It is not encryption: the data on disk is protected by its own keys either way.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Accessibility (window titles)") {
                    HStack {
                        status(model.accessibilityGranted ? "Allowed" : "Not allowed", ok: model.accessibilityGranted)
                        Button("Open Settings") { Permissions.openAccessibilitySettings() }
                    }
                }
                LabeledContent("Automation: Google Chrome (websites)") {
                    HStack {
                        status(automationText, ok: automation == .granted)
                        Button("Open Settings") { Permissions.openAutomationSettings() }
                    }
                }
            }

            Section("Data") {
                LabeledContent("Location") {
                    Text(model.store.directory.path).textSelection(.enabled).font(.caption)
                }
                Button("Delete All Data…", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .task(id: model.revision) {
            automation = Permissions.chromeAutomationStatus()
            launchAtLogin = model.launchAtLogin
        }
        .confirmationDialog("Delete all DayLog data?", isPresented: $confirmDelete) {
            Button("Delete All Data", role: .destructive) { model.deleteAllData() }
        } message: {
            Text("This permanently deletes the database, all totals and rules, and DayLog's encryption keys from your keychain.")
        }
    }

    private var automationText: String {
        if model.chromeDenied { return "Not allowed" }
        return switch automation {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not asked yet"
        case .chromeNotRunning: "Chrome not running"
        case .unknown: "Unknown"
        }
    }

    private func status(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(ok ? .green : .secondary)
    }

    private func setting<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { v in model.updateSettings { $0[keyPath: keyPath] = v } })
    }
}
