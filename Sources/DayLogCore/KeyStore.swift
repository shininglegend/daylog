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

/// All keys live in ONE generic-password item in the login keychain (a JSON map of
/// name -> base64 key), so macOS asks for keychain access once, not once per hour key.
/// Deleting an hour's key removes it from the map and rewrites the item, so destroyed
/// keys stay destroyed. The default access list (only this app, as identified by its
/// code signature) applies.
///
/// Earlier builds stored one item per key (service = key name). Those are still read on
/// demand, copied into the bundle item, and deleted.
public final class KeychainKeyStore: KeyStore {
    private static let account = "daylog"
    static let bundleService = "local.daylog.keys"
    private let lock = NSLock()
    private var bundle: [String: Data]?

    public init() {}

    // MARK: Bundle item

    private func bundleQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.bundleService,
            kSecAttrAccount as String: Self.account,
        ]
    }

    private func loadBundle() throws -> [String: Data] {
        if let bundle { return bundle }
        var query = bundleQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        var loaded: [String: Data] = [:]
        if status == errSecSuccess, let data = out as? Data {
            loaded = try JSONDecoder().decode([String: Data].self, from: data)
        } else if status != errSecItemNotFound {
            throw KeyStoreError.keychain(status)
        }
        bundle = loaded
        return loaded
    }

    private func saveBundle(_ keys: [String: Data]) throws {
        let data = try JSONEncoder().encode(keys)
        let status = SecItemUpdate(bundleQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = bundleQuery()
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = Self.bundleService
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeyStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw KeyStoreError.keychain(status)
        }
        bundle = keys
    }

    // MARK: Legacy per-key items

    private func legacyQuery(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name,
            kSecAttrAccount as String: Self.account,
        ]
    }

    private func legacyKey(_ name: String) throws -> Data? {
        var query = legacyQuery(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeyStoreError.keychain(status) }
        return data
    }

    private func deleteLegacy(_ name: String) throws {
        let status = SecItemDelete(legacyQuery(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyStoreError.keychain(status) }
    }

    // MARK: KeyStore

    public func key(named name: String) throws -> SymmetricKey? {
        lock.lock(); defer { lock.unlock() }
        return try lockedKey(named: name)
    }

    private func lockedKey(named name: String) throws -> SymmetricKey? {
        var keys = try loadBundle()
        if let data = keys[name] { return SymmetricKey(data: data) }
        guard let data = try legacyKey(name) else { return nil }
        keys[name] = data
        try saveBundle(keys)
        try? deleteLegacy(name)
        return SymmetricKey(data: data)
    }

    public func keyCreatingIfNeeded(named name: String) throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        if let k = try lockedKey(named: name) { return k }
        let key = SymmetricKey(size: .bits256)
        var keys = try loadBundle()
        keys[name] = key.withUnsafeBytes { Data($0) }
        try saveBundle(keys)
        return key
    }

    public func deleteKey(named name: String) throws {
        lock.lock(); defer { lock.unlock() }
        var keys = try loadBundle()
        if keys.removeValue(forKey: name) != nil { try saveBundle(keys) }
        try deleteLegacy(name)
    }

    public func allKeyNames() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        var names = Set(try loadBundle().keys)
        // Legacy items: attributes only, which never triggers an access prompt.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecSuccess, let items = out as? [[String: Any]] {
            for case let service as String in items.compactMap({ $0[kSecAttrService as String] }) where service != Self.bundleService {
                names.insert(service)
            }
        } else if status != errSecItemNotFound {
            throw KeyStoreError.keychain(status)
        }
        return names.filter { $0.hasPrefix(KeyNames.prefix) }
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
