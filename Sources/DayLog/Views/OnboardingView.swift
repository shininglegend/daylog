import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to DayLog").font(.largeTitle.bold())
            Text("DayLog records which app, window title, and Chrome website you're using, so you can see where your time went. Everything stays on this Mac: it makes no network connections, takes no screenshots, and logs no keystrokes. Titles and websites are encrypted and deleted after 48 hours; only daily totals are kept longer.")
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(
                title: "Accessibility",
                detail: "Lets DayLog read the title of the focused window. Without it, DayLog records only app names.",
                granted: model.accessibilityGranted
            ) {
                HStack {
                    Button("Request Access") { Permissions.promptAccessibility() }
                    Button("Open Settings") { Permissions.openAccessibilitySettings() }
                }
            }

            PermissionRow(
                title: "Automation: Google Chrome",
                detail: "Lets DayLog ask Chrome for the active tab's address, from which it keeps only the domain. macOS asks the first time Chrome is in front. Incognito windows are never recorded. If you deny it, DayLog keeps working without websites.",
                granted: nil
            ) { EmptyView() }

            Spacer()
            HStack {
                Spacer()
                Button("Start Recording") { model.completeOnboarding() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .frame(maxWidth: 640)
    }
}

private struct PermissionRow<Actions: View>: View {
    let title: String
    let detail: String
    let granted: Bool?
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted == true ? "checkmark.circle.fill" : granted == false ? "xmark.circle" : "questionmark.circle")
                .foregroundStyle(granted == true ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                actions
            }
        }
    }
}
