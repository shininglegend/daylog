import Foundation

enum Fmt {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    static func percent(_ part: TimeInterval, of whole: TimeInterval) -> String {
        guard whole > 0 else { return "0%" }
        return (part / whole).formatted(.percent.precision(.fractionLength(0)))
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
