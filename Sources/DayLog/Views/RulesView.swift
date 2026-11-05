import DayLogCore
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Rule.ID?
    @State private var editing: RuleDraft?
    @State private var retroMatches: [Segment]?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Matching activity is recorded as \"Blocked\" with no app, title, or website. Rules apply at capture time.")
                .font(.callout).foregroundStyle(.secondary)
            Table(model.rules, selection: $selection) {
                TableColumn("Type") { Text($0.type.displayName) }
                TableColumn("Pattern") { Text($0.pattern).textSelection(.enabled) }
                TableColumn("Added") { Text($0.createdAt.formatted(date: .abbreviated, time: .shortened)) }
            }
            .contextMenu(forSelectionType: Rule.ID.self) { ids in
                if let rule = rule(ids.first) {
                    Button("Edit…") { editing = RuleDraft(rule) }
                    Button("Delete", role: .destructive) { model.deleteRule(rule) }
                }
            } primaryAction: { ids in
                if let rule = rule(ids.first) { editing = RuleDraft(rule) }
            }
            HStack {
                Button("Add Rule…") { editing = RuleDraft() }
                Button("Edit…") { if let r = rule(selection) { editing = RuleDraft(r) } }.disabled(selection == nil)
                Button("Delete") { if let r = rule(selection) { model.deleteRule(r) } }.disabled(selection == nil)
            }
        }
        .sheet(item: $editing) { draft in
            RuleEditor(draft: draft) { saved in
                if let rule = saved.existing {
                    var updated = rule
                    updated.type = saved.type
                    updated.pattern = saved.pattern
                    retroMatches = model.updateRule(updated)
                } else {
                    retroMatches = model.addRule(type: saved.type, pattern: saved.pattern)
                }
            }
        }
        .retroactivePrompt($retroMatches)
    }

    private func rule(_ id: Rule.ID?) -> Rule? { model.rules.first { $0.id == id } }
}

struct RuleDraft: Identifiable {
    let id = UUID()
    var existing: Rule?
    var type: RuleType = .titleContains
    var pattern = ""

    init() {}
    init(_ rule: Rule) {
        existing = rule
        type = rule.type
        pattern = rule.pattern
    }
}

private struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: RuleDraft
    let onSave: (RuleDraft) -> Void

    private var trimmed: String { draft.pattern.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var error: String? {
        if trimmed.isEmpty { return "" }
        if draft.type == .titleRegex && !RuleMatcher.isValidRegex(trimmed) { return "Not a valid regular expression." }
        return nil
    }

    var body: some View {
        Form {
            Picker("Type", selection: $draft.type) {
                ForEach(RuleType.allCases) { Text($0.displayName).tag($0) }
            }
            TextField("Pattern", text: $draft.pattern, prompt: Text(placeholder))
            if let error, !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(draft.existing == nil ? "Add" : "Save") {
                    draft.pattern = trimmed
                    dismiss()
                    onSave(draft)
                }
                .disabled(error != nil)
            }
        }
    }

    private var placeholder: String {
        switch draft.type {
        case .app: "com.example.App"
        case .domain: "example.com"
        case .titleContains: "Private"
        case .titleRegex: "(?i)^invoice \\d+"
        }
    }

    private var help: String {
        switch draft.type {
        case .app: "Exact bundle identifier."
        case .domain: "Matches the domain and all of its subdomains."
        case .titleContains: "Case-insensitive substring of the window title."
        case .titleRegex: "ICU regular expression on the window title. Case-sensitive unless you add (?i)."
        }
    }
}
