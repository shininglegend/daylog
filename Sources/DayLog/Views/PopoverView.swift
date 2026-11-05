import DayLogCore
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openMainWindow) private var openMainWindow

    @State private var activeToday: TimeInterval = 0
    @State private var topApps: [BreakdownRow] = []
    @State private var topDomains: [BreakdownRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.status.description, systemImage: model.status.symbol)
                    .font(.headline)
                Spacer()
            }
            if let until = model.pausedUntil, model.status == .paused {
                Text(until == .distantFuture ? "Paused until resumed" : "Paused until \(Fmt.time(until))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PermissionBanners()

            Divider()
            HStack {
                Text("Active today").foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.duration(activeToday)).font(.title3.monospacedDigit())
            }
            TopList(title: "Top apps", rows: topApps, total: activeToday)
            TopList(title: "Top websites", rows: topDomains, total: nil)

            Divider()
            HStack {
                if model.status == .paused {
                    Button("Resume") { model.resume() }
                } else {
                    Text("Pause:").foregroundStyle(.secondary)
                    Button("15m") { model.pause(minutes: 15) }
                    Button("1h") { model.pause(minutes: 60) }
                    Button("Until resumed") { model.pause(minutes: nil) }
                }
            }
            .controlSize(.small)
            HStack {
                Button("Open DayLog") { openMainWindow() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 320)
        .task(id: model.revision) { reload() }
    }

    private func reload() {
        let today = model.now
        let apps = model.breakdown(.app, firstDay: today, lastDay: today)
        activeToday = apps.reduce(0) { $0 + $1.seconds }
        topApps = Array(apps.prefix(5))
        topDomains = Array(model.breakdown(.domain, firstDay: today, lastDay: today).prefix(5))
    }
}

private struct TopList: View {
    let title: String
    let rows: [BreakdownRow]
    let total: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            if rows.isEmpty {
                Text("Nothing yet").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                HStack {
                    Text(row.label).lineLimit(1)
                    Spacer()
                    if let total { Text(Fmt.percent(row.seconds, of: total)).foregroundStyle(.secondary) }
                    Text(Fmt.duration(row.seconds)).monospacedDigit()
                }
                .font(.callout)
            }
        }
    }
}

/// Non-blocking notices about missing permissions.
struct PermissionBanners: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.accessibilityGranted {
            Banner(text: "Window titles need Accessibility permission.", button: "Open Settings") {
                Permissions.openAccessibilitySettings()
            }
        }
        if model.chromeDenied {
            Banner(text: "Chrome websites aren't recorded because Automation for Google Chrome is off. Turn on DayLog → Google Chrome in Privacy & Security → Automation.",
                   button: "Open Settings") {
                Permissions.openAutomationSettings()
            }
        }
    }
}

struct Banner: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
                Button(button, action: action).controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}
