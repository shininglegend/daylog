import Foundation

/// A user note on a stretch of time, usually a gap the recorder couldn't see
/// ("Call with Jim", "Lunch"). Encrypted with the hour key of `start` and purged
/// after 48 hours like segments. Notes never affect totals.
public struct Note: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var start: Date
    public var end: Date
    /// nil when the note couldn't be decrypted (see `expired` / `unavailable`).
    public var text: String?
    public var expired: Bool
    public var unavailable: Bool

    public init(id: Int64, start: Date, end: Date, text: String?, expired: Bool = false, unavailable: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.expired = expired
        self.unavailable = unavailable
    }

    public func overlaps(start: Date, end: Date) -> Bool { self.start < end && self.end > start }
}

extension DayLogStore {
    @discardableResult
    public func addNote(start: Date, end: Date, text: String) throws -> Note {
        let box = try crypto.seal(text, field: .note, segmentStart: start)
        try db.run(#"INSERT INTO notes (start, "end", text) VALUES (?, ?, ?)"#,
                   [start.timeIntervalSince1970, end.timeIntervalSince1970, box])
        return Note(id: db.lastInsertRowID, start: start, end: end, text: text)
    }

    public func updateNote(_ note: Note, text: String) throws {
        let box = try crypto.seal(text, field: .note, segmentStart: note.start)
        try db.run("UPDATE notes SET text = ? WHERE id = ?", [box, note.id])
    }

    public func deleteNote(id: Int64) throws {
        try db.run("DELETE FROM notes WHERE id = ?", [id])
    }

    /// Notes overlapping [from, to), decrypted in memory, oldest first.
    public func notes(from: Date, to: Date) throws -> [Note] {
        try db.query(
            #"SELECT id, start, "end", text FROM notes WHERE "end" > ? AND start < ? ORDER BY start"#,
            [from.timeIntervalSince1970, to.timeIntervalSince1970]
        ) { r in
            let start = Date(timeIntervalSince1970: r.double(1))
            var note = Note(id: r.int(0), start: start, end: Date(timeIntervalSince1970: r.double(2)), text: nil)
            if let box = r.blob(3) {
                switch crypto.open(box, field: .note, segmentStart: start) {
                case .value(let s): note.text = s
                case .expired: note.expired = true
                case .unavailable: note.unavailable = true
                }
            }
            return note
        }
    }

    /// Notes in the live 48-hour window.
    public func liveNotes() throws -> [Note] {
        let now = clock.now
        return try notes(from: now.addingTimeInterval(-Self.liveWindow), to: now.addingTimeInterval(1))
    }
}
