import DayLogCore
import SwiftUI

/// After a rule is added: offer to delete existing segments it matches.
struct RetroactivePrompt: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var matches: [Segment]?

    func body(content: Content) -> some View {
        content.alert(
            "Delete \(matches?.count ?? 0) existing matching \(matches?.count == 1 ? "entry" : "entries")?",
            isPresented: Binding(get: { (matches?.count ?? 0) > 0 }, set: { if !$0 { matches = nil } })
        ) {
            Button("Delete", role: .destructive) {
                model.deleteSegments(ids: matches?.map(\.id) ?? [])
                matches = nil
            }
            Button("Keep", role: .cancel) { matches = nil }
        } message: {
            Text("The new rule applies to activity from now on. You can also remove what it matches from the last 48 hours.")
        }
    }
}

extension View {
    func retroactivePrompt(_ matches: Binding<[Segment]?>) -> some View {
        modifier(RetroactivePrompt(matches: matches))
    }
}
