import CryptoKit
import Foundation

/// Column encryption for segments and the domain totals HMAC.
public final class Crypto {
    public enum Field: String { case title, domain }

    private let keys: KeyStore

    public init(keys: KeyStore) { self.keys = keys }

    /// AES-GCM with a fresh random nonce; returns the combined nonce+ciphertext+tag.
    /// The field name is authenticated so a title box can't be swapped into the domain column.
    public func seal(_ plaintext: String, field: Field, segmentStart: Date) throws -> Data {
        let key = try keys.keyCreatingIfNeeded(named: KeyNames.segmentKey(for: segmentStart))
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: key, authenticating: Data(field.rawValue.utf8))
        return box.combined!  // non-nil with the default 12-byte nonce
    }

    public enum OpenResult: Equatable {
        case value(String)
        /// The hour key was purged (crypto-shredded) or the box is corrupt.
        case expired
    }

    public func open(_ box: Data, field: Field, segmentStart: Date) -> OpenResult {
        guard let key = try? keys.key(named: KeyNames.segmentKey(for: segmentStart)),
              let sealed = try? AES.GCM.SealedBox(combined: box),
              let data = try? AES.GCM.open(sealed, using: key, authenticating: Data(field.rawValue.utf8)),
              let s = String(data: data, encoding: .utf8)
        else { return .expired }
        return .value(s)
    }

    // MARK: Totals

    private func totalsKey() throws -> SymmetricKey {
        try keys.keyCreatingIfNeeded(named: KeyNames.totals)
    }

    /// Stable, keyed identifier for a domain in `daily_totals`.
    public func domainHMAC(_ domain: String) throws -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(domain.utf8), using: try totalsKey())
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    public func sealLabel(_ domain: String) throws -> Data {
        try AES.GCM.seal(Data(domain.utf8), using: try totalsKey(), authenticating: Data("label".utf8)).combined!
    }

    public func openLabel(_ box: Data) -> String? {
        guard let key = try? keys.key(named: KeyNames.totals),
              let sealed = try? AES.GCM.SealedBox(combined: box),
              let data = try? AES.GCM.open(sealed, using: key, authenticating: Data("label".utf8))
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
