import DayLogCore
import SwiftUI

/// After a rule is added: offer to delete existing entries and older website totals it matches.
struct RetroactivePrompt: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var matches: RuleMatches?

    func body(content: Content) -> some View {
        content.alert(
            "Delete existing matching data?",
            isPresented: Binding(get: { matches.map { !$0.isEmpty } ?? false }, set: { if !$0 { matches = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let matches { model.deleteMatches(matches) }
                matches = nil
            }
            Button("Keep", role: .cancel) { matches = nil }
        } message: {
            Text("The new rule applies to activity from now on. You can also remove what it matches now: \(summary).")
        }
    }

    private var summary: String {
        let entries = matches?.segments.count ?? 0
        let sites = matches?.domainTotalKeys.count ?? 0
        var parts: [String] = []
        if entries > 0 { parts.append("\(entries) \(entries == 1 ? "entry" : "entries") from the last 48 hours") }
        if sites > 0 { parts.append("older website totals for \(sites) \(sites == 1 ? "domain" : "domains")") }
        return parts.joined(separator: " and ")
    }
}

extension View {
    func retroactivePrompt(_ matches: Binding<RuleMatches?>) -> some View {
        modifier(RetroactivePrompt(matches: matches))
    }
}
