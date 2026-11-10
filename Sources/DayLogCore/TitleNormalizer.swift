import Foundation

/// Strips the parts of a window title that change while you keep working on the
/// same thing, so they don't split one activity into many segments.
public enum TitleNormalizer {
    public static func normalize(_ title: String?) -> String? {
        guard var t = title?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        // Zoom/view suffix used by Adobe apps: "Doc.indd @ 61% [GPU Preview]",
        // "Photo.psd @ 66.7% (Layer 1, RGB/8)". Everything from " @ NN%" on is dropped.
        t = t.replacing(/\s+@\s+\d+(?:[.,]\d+)?%.*$/, with: "")
        // Unsaved-changes marker: "*Doc.indd" (Adobe), "Doc — Edited" (AppKit).
        if t.hasPrefix("*") { t.removeFirst() }
        for suffix in [" — Edited", " - Edited"] where t.hasSuffix(suffix) {
            t.removeLast(suffix.count)
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
