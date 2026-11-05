import DayLogCore
import SwiftUI

struct TimelineView: View {
    @Environment(AppModel.self) private var model

    @State private var segments: [Segment] = []
    @State private var search = ""
    @State private var appFilter: String?
    @State private var retroMatches: [Segment]?
    @State private var titleRuleDraft: TitleRuleDraft?

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
                TextField("Search titles, apps, websites", text: $search)
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
        .task(id: model.revision) { segments = model.liveSegments() }
        .retroactivePrompt($retroMatches)
        .sheet(item: $titleRuleDraft) { draft in
            TitleRuleSheet(draft: draft) { pattern in
                retroMatches = model.addRule(type: .titleContains, pattern: pattern)
            }
        }
    }

    private var appNames: [String] {
        Array(Set(segments.compactMap { $0.state.idle ? nil : $0.state.appName })).sorted()
    }

    private var isFiltering: Bool { !search.isEmpty || appFilter != nil }

    /// Newest first. Idle and unrecorded periods appear as gaps (hidden while filtering).
    private var items: [Item] {
        let q = search.trimmingCharacters(in: .whitespaces)
        var out: [Item] = []
        var newerStart: Date?
        for s in segments.reversed() {
            if s.state.idle {
                if !isFiltering { out.append(.gap(id: "i\(s.id)", start: s.start, end: s.end, idle: true)) }
                newerStart = s.start
                continue
            }
            if let appFilter, s.state.appName != appFilter { continue }
            if !q.isEmpty {
                let hay = [s.state.appName, s.state.title, s.state.domain].compactMap { $0 }
                guard hay.contains(where: { $0.localizedCaseInsensitiveContains(q) }) else { continue }
            }
            if !isFiltering, let newer = newerStart, newer.timeIntervalSince(s.end) >= Self.minGap {
                out.append(.gap(id: "g\(s.id)", start: s.end, end: newer, idle: false))
            }
            out.append(.segment(s))
            newerStart = s.start
        }
        return out
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
        HStack {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text("\(idle ? "Idle" : "Not recording") · \(Fmt.time(start))–\(Fmt.time(end)) · \(Fmt.duration(end.timeIntervalSince(start)))")
                .font(.caption).foregroundStyle(.secondary).fixedSize()
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
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
