import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    enum Tab: Hashable { case timeline, breakdown, rules, settings }
    @State private var tab: Tab = .timeline

    var body: some View {
        Group {
            if model.settings.requireTouchID && !model.mainWindowUnlocked {
                LockedView()
            } else if !model.settings.onboarded {
                OnboardingView()
            } else {
                VStack(spacing: 0) {
                    if !model.accessibilityGranted || model.chromeDenied {
                        PermissionBanners().padding([.horizontal, .top])
                    }
                    TabView(selection: $tab) {
                        TimelineView().tabItem { Text("Timeline") }.tag(Tab.timeline)
                        BreakdownView().tabItem { Text("Breakdown") }.tag(Tab.breakdown)
                        RulesView().tabItem { Text("Rules") }.tag(Tab.rules)
                        SettingsView().tabItem { Text("Settings") }.tag(Tab.settings)
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct LockedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("DayLog is locked").font(.title2)
            Button("Unlock with Touch ID") { model.unlockMainWindow() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.unlockMainWindow() }
    }
}
