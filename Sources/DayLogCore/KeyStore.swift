import CryptoKit
import Foundation
import Security

/// Named 256-bit keys. All names start with `KeyNames.prefix`.
public protocol KeyStore: AnyObject {
    func key(named name: String) throws -> SymmetricKey?
    /// Returns the existing key or creates, stores, and returns a new random one.
    func keyCreatingIfNeeded(named name: String) throws -> SymmetricKey
    func deleteKey(named name: String) throws
    func allKeyNames() throws -> [String]
}

public enum KeyNames {
    public static let prefix = "local.daylog."
    public static let totals = "local.daylog.totals"
    public static let segmentPrefix = "local.daylog.seg."

    /// Hour buckets are in UTC so DST changes never make two hours share a name.
    static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHH"
        return f
    }()

    public static func segmentKey(for date: Date) -> String {
        segmentPrefix + hourFormatter.string(from: date)
    }

    /// Start of the UTC hour a segment key covers, or nil if `name` isn't a segment key.
    public static func hourStart(ofSegmentKey name: String) -> Date? {
        guard name.hasPrefix(segmentPrefix) else { return nil }
        return hourFormatter.date(from: String(name.dropFirst(segmentPrefix.count)))
    }
}

public enum KeyStoreError: Error {
    case keychain(OSStatus)
}

/// Generic-password items in the login keychain. The default access list
/// (only this app, as identified by its code signature) applies.
public final class KeychainKeyStore: KeyStore {
    private static let account = "daylog"
    private var cache: [String: SymmetricKey] = [:]

    public init() {}

    private func baseQuery(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name,
            kSecAttrAccount as String: Self.account,
        ]
    }

    public func key(named name: String) throws -> SymmetricKey? {
        if let k = cache[name] { return k }
        var query = baseQuery(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeyStoreError.keychain(status) }
        let key = SymmetricKey(data: data)
        cache[name] = key
        return key
    }

    public func keyCreatingIfNeeded(named name: String) throws -> SymmetricKey {
        if let k = try key(named: name) { return k }
        let key = SymmetricKey(size: .bits256)
        var query = baseQuery(name)
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        query[kSecAttrLabel as String] = name
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try self.key(named: name) { return existing }
        guard status == errSecSuccess else { throw KeyStoreError.keychain(status) }
        cache[name] = key
        return key
    }

    public func deleteKey(named name: String) throws {
        cache[name] = nil
        let status = SecItemDelete(baseQuery(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyStoreError.keychain(status) }
    }

    public func allKeyNames() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = out as? [[String: Any]] else { throw KeyStoreError.keychain(status) }
        return items.compactMap { $0[kSecAttrService as String] as? String }.filter { $0.hasPrefix(KeyNames.prefix) }
    }
}

/// Test double. Never touches the keychain.
public final class InMemoryKeyStore: KeyStore {
    public private(set) var keys: [String: SymmetricKey] = [:]
    public init() {}
    public func key(named name: String) throws -> SymmetricKey? { keys[name] }
    public func keyCreatingIfNeeded(named name: String) throws -> SymmetricKey {
        if let k = keys[name] { return k }
        let k = SymmetricKey(size: .bits256)
        keys[name] = k
        return k
    }
    public func deleteKey(named name: String) throws { keys[name] = nil }
    public func allKeyNames() throws -> [String] { Array(keys.keys) }
}
