import Charts
import DayLogCore
import SwiftUI

struct BreakdownView: View {
    @Environment(AppModel.self) private var model

    enum Range: String, CaseIterable, Identifiable {
        case today = "Today", yesterday = "Yesterday", week = "7 days", month = "30 days", custom = "Custom"
        var id: String { rawValue }
    }

    @State private var range: Range = .today
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var customEnd = Date()
    @State private var apps: [BreakdownRow] = []
    @State private var domains: [BreakdownRow] = []

    private static let chartLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                if range == .custom {
                    DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                }
                Spacer()
                Text("Active: \(Fmt.duration(total))").font(.headline.monospacedDigit())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    BarChart(title: "Apps", rows: apps, total: total, limit: Self.chartLimit)
                    BarChart(title: "Websites (Chrome)", rows: domains, total: total, limit: Self.chartLimit)
                }
            }
        }
        .task(id: ReloadKey(range: range, start: customStart, end: customEnd, revision: model.revision)) { reload() }
    }

    private struct ReloadKey: Equatable {
        var range: Range, start: Date, end: Date, revision: Int
    }

    private var total: TimeInterval { apps.reduce(0) { $0 + $1.seconds } }

    private func reload() {
        let cal = Calendar.current
        let today = model.now
        let (first, last): (Date, Date) = switch range {
        case .today: (today, today)
        case .yesterday: (cal.date(byAdding: .day, value: -1, to: today)!, cal.date(byAdding: .day, value: -1, to: today)!)
        case .week: (cal.date(byAdding: .day, value: -6, to: today)!, today)
        case .month: (cal.date(byAdding: .day, value: -29, to: today)!, today)
        case .custom: (min(customStart, customEnd), max(customStart, customEnd))
        }
        apps = model.breakdown(.app, firstDay: first, lastDay: last)
        domains = model.breakdown(.domain, firstDay: first, lastDay: last)
    }
}

private struct BarChart: View {
    let title: String
    let rows: [BreakdownRow]
    /// Share is of total active time across all apps.
    let total: TimeInterval
    let limit: Int

    private var shown: [BreakdownRow] {
        guard rows.count > limit else { return rows }
        let rest = rows.dropFirst(limit - 1).reduce(0) { $0 + $1.seconds }
        return Array(rows.prefix(limit - 1)) + [BreakdownRow(label: "Other (\(rows.count - limit + 1))", seconds: rest)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            if rows.isEmpty {
                Text("No data for this range").foregroundStyle(.secondary)
            } else {
                Chart(shown) { row in
                    BarMark(x: .value("Time", row.seconds / 3600), y: .value("Name", row.label))
                        .annotation(position: .trailing) {
                            Text("\(Fmt.duration(row.seconds)) · \(Fmt.percent(row.seconds, of: total))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                }
                .chartXAxisLabel("Hours")
                .chartYScale(domain: shown.map(\.label))
                .frame(height: CGFloat(shown.count) * 28 + 40)
            }
        }
    }
}
