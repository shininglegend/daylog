import Foundation

extension DayLogStore {
    public func rules() throws -> [Rule] {
        try db.query("SELECT id, type, pattern, created_at FROM rules ORDER BY created_at") { r in
            guard let type = RuleType(rawValue: r.text(1) ?? "") else { return nil }
            return Rule(id: r.int(0), type: type, pattern: r.text(2) ?? "", createdAt: Date(timeIntervalSince1970: r.double(3)))
        }.compactMap { $0 }
    }

    @discardableResult
    public func addRule(type: RuleType, pattern: String) throws -> Rule {
        let now = clock.now
        try db.run("INSERT INTO rules (type, pattern, created_at) VALUES (?, ?, ?)", [type.rawValue, pattern, now.timeIntervalSince1970])
        return Rule(id: db.lastInsertRowID, type: type, pattern: pattern, createdAt: now)
    }

    public func updateRule(_ rule: Rule) throws {
        try db.run("UPDATE rules SET type = ?, pattern = ? WHERE id = ?", [rule.type.rawValue, rule.pattern, rule.id])
    }

    public func deleteRule(id: Int64) throws {
        try db.run("DELETE FROM rules WHERE id = ?", [id])
    }
}
