import DayLogCore
import SwiftUI

struct TimelineView: View {
    @Environment(AppModel.self) private var model

    @State private var segments: [Segment] = []
    @State private var search = ""
    @State private var appFilter: String?
    @State private var retroMatches: RuleMatches?
    @State private var titleRuleDraft: TitleRuleDraft?
    @State private var notes: [Note] = []
    @State private var noteDraft: NoteDraft?

    private enum Item: Identifiable {
        case segment(Segment)
        case gap(id: String, start: Date, end: Date, idle: Bool)
        var id: String {
            switch self {
            case .segment(let s): "s\(s.id)"
            case .gap(let id, _, _, _): id
            }
        }
    }

    /// Breaks shorter than this between recorded segments aren't shown as gaps.
    private static let minGap: TimeInterval = 60

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Search titles, apps, websites, notes", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("App", selection: $appFilter) {
                    Text("All apps").tag(String?.none)
                    ForEach(appNames, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(maxWidth: 220)
            }
            List(items) { item in
                switch item {
                case .segment(let s): row(s)
                case .gap(_, let start, let end, let idle): gapRow(start: start, end: end, idle: idle)
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("No activity in the last 48 hours", systemImage: "clock")
                }
            }
        }
        .task(id: model.revision) {
            segments = model.liveSegments()
            notes = model.liveNotes()
        }
        .retroactivePrompt($retroMatches)
        .sheet(item: $titleRuleDraft) { draft in
            TitleRuleSheet(draft: draft) { pattern in
                retroMatches = model.addRule(type: .titleContains, pattern: pattern)
            }
        }
        .sheet(item: $noteDraft) { draft in
            NoteSheet(draft: draft) { text in
                model.saveNote(draft.existing, start: draft.start, end: draft.end, text: text)
            }
        }
    }

    private var appNames: [String] {
        Array(Set(segments.compactMap { $0.state.idle ? nil : $0.state.appName })).sorted()
    }

    private var isFiltering: Bool { !search.isEmpty || appFilter != nil }

    /// Newest first. Idle and unrecorded periods appear as gaps. While filtering,
    /// gaps are shown only when their note matches the search.
    private var items: [Item] {
        var all: [Item] = []
        var newerStart: Date?
        for s in segments.reversed() {
            if s.state.idle {
                all.append(.gap(id: "i\(s.id)", start: s.start, end: s.end, idle: true))
            } else {
                if let newer = newerStart, newer.timeIntervalSince(s.end) >= Self.minGap {
                    all.append(.gap(id: "g\(s.id)", start: s.end, end: newer, idle: false))
                }
                all.append(.segment(s))
            }
            newerStart = s.start
        }
        guard isFiltering else { return all }
        let q = search.trimmingCharacters(in: .whitespaces)
        return all.filter { item in
            switch item {
            case .segment(let s):
                if let appFilter, s.state.appName != appFilter { return false }
                guard !q.isEmpty else { return true }
                let hay = [s.state.appName, s.state.title, s.state.domain].compactMap { $0 }
                return hay.contains { $0.localizedCaseInsensitiveContains(q) }
            case .gap(_, let start, let end, _):
                guard appFilter == nil, !q.isEmpty else { return false }
                return note(start: start, end: end)?.text?.localizedCaseInsensitiveContains(q) == true
            }
        }
    }

    /// The note attached to a gap: the first one overlapping its time range.
    private func note(start: Date, end: Date) -> Note? {
        notes.first { $0.overlaps(start: start, end: end) }
    }

    private func row(_ s: Segment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(Fmt.time(s.start))–\(Fmt.time(s.end))")
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(s.state.appName ?? "Unknown").bold()
                    if let d = s.state.domain { Text(d).foregroundStyle(.blue) }
                    Spacer()
                    Text(Fmt.duration(s.duration)).monospacedDigit().foregroundStyle(.secondary)
                }
                if s.expired {
                    Text("[expired]").foregroundStyle(.secondary)
                } else if s.unavailable {
                    Text("[keychain unavailable]").foregroundStyle(.secondary)
                } else if let t = s.state.title {
                    Text(t).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu { contextMenu(s) }
    }

    @ViewBuilder
    private func contextMenu(_ s: Segment) -> some View {
        if let id = s.state.bundleID {
            Button("Block this app") { retroMatches = model.addRule(type: .app, pattern: id) }
        }
        if let d = s.state.domain {
            Button("Block this domain") { retroMatches = model.addRule(type: .domain, pattern: d) }
        }
        if !s.state.blocked {
            Button("Block titles containing…") { titleRuleDraft = TitleRuleDraft(text: s.state.title ?? "") }
        }
        Divider()
        Button("Delete entry", role: .destructive) { model.deleteSegments(ids: [s.id]) }
    }

    private func gapRow(start: Date, end: Date, idle: Bool) -> some View {
        let note = note(start: start, end: end)
        let edit = { noteDraft = NoteDraft(existing: note, start: start, end: end, text: note?.text ?? "") }
        return VStack(spacing: 2) {
            HStack {
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                Text("\(idle ? "Idle" : "Not recording") · \(Fmt.time(start))–\(Fmt.time(end)) · \(Fmt.duration(end.timeIntervalSince(start)))")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
                Button(action: edit) {
                    Image(systemName: note == nil ? "square.and.pencil" : "pencil")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(note == nil ? "Add a note for this time" : "Edit note")
                .accessibilityLabel(note == nil ? "Add note" : "Edit note")
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            }
            if let note {
                Group {
                    if let text = note.text {
                        Text(text).textSelection(.enabled)
                    } else {
                        Text(note.expired ? "[expired]" : "[keychain unavailable]").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
        .contextMenu {
            Button(note == nil ? "Add Note…" : "Edit Note…", action: edit)
            if let note {
                Button("Delete Note", role: .destructive) { model.deleteNote(note) }
            }
        }
    }
}

/// A note being added or edited for a gap's time range.
struct NoteDraft: Identifiable {
    let id = UUID()
    var existing: Note?
    var start: Date
    var end: Date
    var text: String
}

private struct NoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: NoteDraft
    /// Saving blank text deletes an existing note.
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.existing == nil ? "Add Note" : "Edit Note").font(.headline)
            Text("\(Fmt.time(draft.start))–\(Fmt.time(draft.end)). Notes are encrypted and deleted after 48 hours, like window titles.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("What were you doing?", text: $draft.text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    dismiss()
                    onSave(draft.text)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.existing == nil && draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }
}

struct TitleRuleDraft: Identifiable {
    let id = UUID()
    var text: String
}

private struct TitleRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: TitleRuleDraft
    let onAdd: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Block titles containing").font(.headline)
            Text("Edit down to the part that identifies what you want to block. Matching ignores case.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Text", text: $draft.text).textFieldStyle(.roundedBorder).frame(width: 420)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add Rule") {
                    let p = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                    onAdd(p)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }
}
