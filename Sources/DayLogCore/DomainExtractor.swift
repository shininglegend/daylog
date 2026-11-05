import Foundation

/// Reduces a browser URL to the only thing DayLog stores: a hostname.
/// The full URL is never retained by callers; pass it here and drop it.
public enum DomainExtractor {
    /// Browser-internal schemes all map to the domain "chrome".
    static let internalSchemes: Set<String> = [
        "chrome", "chrome-extension", "chrome-untrusted", "chrome-search", "chrome-native",
        "devtools", "about", "view-source", "edge", "brave",
    ]

    public static let internalDomain = "chrome"
    public static let fileDomain = "file"

    public static func domain(fromURL raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let scheme = scheme(of: trimmed) else { return nil }
        if internalSchemes.contains(scheme) { return internalDomain }
        if scheme == "file" { return fileDomain }
        guard scheme == "http" || scheme == "https",
              let host = URLComponents(string: trimmed)?.host?.lowercased(),
              !host.isEmpty
        else { return nil }
        var h = host.hasSuffix(".") ? String(host.dropLast()) : host
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h.isEmpty ? nil : h
    }

    private static func scheme(of s: String) -> String? {
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let scheme = s[..<colon].lowercased()
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) })
        else { return nil }
        return scheme
    }
}
