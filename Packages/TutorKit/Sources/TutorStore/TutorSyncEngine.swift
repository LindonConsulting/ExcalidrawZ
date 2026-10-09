import Foundation
import GRDB
import TutorModels
import TutorSync

/// Two-way sync between the local GRDB database and the TutorKit Supabase project.
///
/// Rows share their ids on both sides. Tables with `updatedAt` sync incrementally
/// (push rows changed since the last push, pull rows changed since the last pull,
/// latest `updatedAt` wins). Reference and join tables (sections, points, topic
/// links…) are pushed whole and pulled whole; they are small.
/// Cursors live in the local `meta` table under `sync.push.<table>` / `sync.pull.<table>`.
public final class TutorSyncEngine: Sendable {
    public struct Report: Sendable, CustomStringConvertible {
        public var pushed: [String: Int] = [:]
        public var pulled: [String: Int] = [:]
        public var description: String {
            let up = pushed.values.reduce(0, +), down = pulled.values.reduce(0, +)
            return "pushed \(up) rows, pulled \(down) rows"
        }
    }

    /// One local table mapped to one remote table.
    struct Table: Sendable {
        var local: String
        var remote: String
        /// Columns identifying a row (local names).
        var key: [String]
        /// Local columns that never leave this machine.
        var localOnly: Set<String> = []
        /// Tables with no `updatedAt` are pushed and pulled whole.
        var hasUpdatedAt: Bool = true
    }

    /// Parents before children, so foreign keys hold on push.
    static let tables: [Table] = [
        Table(local: "course", remote: "courses", key: ["id"], hasUpdatedAt: false),
        Table(local: "specification", remote: "specifications", key: ["id"], hasUpdatedAt: false),
        Table(local: "specSection", remote: "spec_sections", key: ["id"], hasUpdatedAt: false),
        Table(local: "specPoint", remote: "spec_points", key: ["id"], hasUpdatedAt: false),
        Table(local: "topic", remote: "topics", key: ["id"], hasUpdatedAt: false),
        Table(local: "student", remote: "students", key: ["id"], localOnly: ["remoteID", "remoteSyncedAt"]),
        Table(local: "studentContact", remote: "student_contacts", key: ["id"], hasUpdatedAt: false),
        Table(local: "enrolment", remote: "enrolments", key: ["id"], localOnly: ["remoteID"]),
        Table(local: "question", remote: "questions", key: ["id"], localOnly: ["remoteID"]),
        Table(local: "questionTopic", remote: "question_topics", key: ["questionID", "topicID"], hasUpdatedAt: false),
        Table(local: "questionSpecPoint", remote: "question_spec_points", key: ["questionID", "specPointID"], hasUpdatedAt: false),
        Table(local: "lesson", remote: "lessons", key: ["id"], localOnly: ["remoteID"]),
        Table(local: "lessonTopic", remote: "lesson_topics", key: ["lessonID", "topicID"], hasUpdatedAt: false),
        Table(local: "outcome", remote: "outcomes", key: ["id"], localOnly: ["remoteID"]),
        Table(local: "topicProgress", remote: "topic_progress", key: ["studentID", "topicID"], localOnly: ["remoteID"]),
        Table(local: "coverageMark", remote: "coverage_marks", key: ["studentID", "specPointID"], hasUpdatedAt: false),
    ]

    private let database: TutorDatabase
    private let client: SupabaseRESTClient
    private let pageSize = 500

    public init(database: TutorDatabase, client: SupabaseRESTClient) {
        self.database = database
        self.client = client
    }

    /// Pull first so remote edits land before local ones are pushed on top.
    public func sync() async throws -> Report {
        var report = try await pull()
        let pushReport = try await push()
        report.pushed = pushReport.pushed
        return report
    }

    // MARK: Push

    public func push() async throws -> Report {
        var report = Report()
        for table in Self.tables {
            let since = try database.meta("sync.push.\(table.local)").flatMap(Self.parseDate)
            let startedAt = Date()
            let wire = try wireRows(for: table, since: since)
            guard !wire.isEmpty else { continue }
            let onConflict = table.key.count > 1 ? table.key.map(Self.snakeCase).joined(separator: ",") : nil
            for chunk in stride(from: 0, to: wire.count, by: pageSize) {
                try await client.upsertRows(Array(wire[chunk..<min(chunk + pageSize, wire.count)]), into: table.remote, onConflict: onConflict)
            }
            report.pushed[table.remote] = wire.count
            try database.setMeta("sync.push.\(table.local)", Self.formatDate(startedAt))
        }
        return report
    }

    /// Synchronous read so GRDB's non-async overload is used (rows are not Sendable).
    private func wireRows(for table: Table, since: Date?) throws -> [[String: Any]] {
        try database.writer.read { db in
            let rows: [Row]
            if table.hasUpdatedAt, let since {
                rows = try Row.fetchAll(db, sql: "SELECT * FROM \(table.local) WHERE updatedAt > ?", arguments: [since])
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT * FROM \(table.local)")
            }
            return rows.map { Self.wire($0, dropping: table.localOnly) }
        }
    }

    // MARK: Pull

    public func pull() async throws -> Report {
        var report = Report()
        for table in Self.tables {
            let since = try database.meta("sync.pull.\(table.local)")
            let startedAt = Date()
            var filters: [URLQueryItem] = []
            if table.hasUpdatedAt, let since { filters.append(URLQueryItem(name: "updated_at", value: "gt.\(since)")) }
            var offset = 0
            var applied = 0
            while true {
                let page = try await client.selectRows(from: table.remote, filters: filters, order: table.key.map(Self.snakeCase).joined(separator: ","),
                                                       limit: pageSize, offset: offset)
                if page.isEmpty { break }
                applied += try apply(page, to: table)
                offset += page.count
                if page.count < pageSize { break }
            }
            if applied > 0 { report.pulled[table.remote] = applied }
            try database.setMeta("sync.pull.\(table.local)", Self.formatDate(startedAt))
        }
        return report
    }

    /// Upserts remote rows locally; a local row with a newer `updatedAt` wins.
    func apply(_ rows: [[String: Any]], to table: Table) throws -> Int {
        let columns = try database.writer.read { db in try db.columns(in: table.local).map(\.name) }
        var applied = 0
        try database.writer.write { db in
            for remote in rows {
                var local: [String: DatabaseValueConvertible?] = [:]
                for (snake, value) in remote {
                    let name = Self.camelCase(snake)
                    guard columns.contains(name) else { continue }
                    local[name] = Self.localValue(value, column: name)
                }
                let keyValues = table.key.map { local[$0] ?? nil }
                let whereSQL = table.key.map { "\($0) = ?" }.joined(separator: " AND ")
                if table.hasUpdatedAt,
                   let existing = try Date.fetchOne(db, sql: "SELECT updatedAt FROM \(table.local) WHERE \(whereSQL)", arguments: StatementArguments(keyValues)),
                   let incomingValue = local["updatedAt"] ?? nil, let incoming = incomingValue as? Date, incoming <= existing {
                    continue
                }
                let names = local.keys.sorted()
                let placeholders = names.map { _ in "?" }.joined(separator: ", ")
                let updates = names.filter { !table.key.contains($0) }.map { "\($0) = excluded.\($0)" }.joined(separator: ", ")
                var sql = "INSERT INTO \(table.local) (\(names.joined(separator: ", "))) VALUES (\(placeholders))"
                sql += updates.isEmpty ? " ON CONFLICT DO NOTHING" : " ON CONFLICT(\(table.key.joined(separator: ", "))) DO UPDATE SET \(updates)"
                try db.execute(sql: sql, arguments: StatementArguments(names.map { local[$0] ?? nil }))
                applied += 1
            }
        }
        return applied
    }

    // MARK: Wire format

    /// GRDB row → JSON object with snake_case keys, ISO dates, UUID strings, JSON arrays for JSON text columns.
    static func wire(_ row: Row, dropping: Set<String>) -> [String: Any] {
        var object: [String: Any] = [:]
        for column in row.columnNames where !dropping.contains(column) {
            let value: DatabaseValue = row[column]
            object[snakeCase(column)] = jsonValue(value, column: column)
        }
        return object
    }

    static let jsonColumns: Set<String> = ["freeTags", "aliases"]
    static let dateColumns: Set<String> = ["createdAt", "updatedAt", "deletedAt", "importedAt", "startedAt", "endedAt", "startAt", "endAt",
                                            "shownAt", "lastRevisedAt", "markedAt", "remoteSyncedAt"]
    static let boolColumns: Set<String> = ["isPrimary", "isFocus", "billable", "active"]
    static let uuidColumns: Set<String> = ["id", "studentID", "enrolmentID", "specificationID", "sectionID", "specPointID", "questionID",
                                            "lessonID", "remoteID", "deckID"]

    static func jsonValue(_ value: DatabaseValue, column: String) -> Any {
        switch value.storage {
            case .null: return NSNull()
            case .int64(let i): return boolColumns.contains(column) ? (i != 0) : i
            case .double(let d): return d
            case .string(let s):
                if dateColumns.contains(column), let date = parseDate(s) { return formatDate(date) }
                if jsonColumns.contains(column), let data = s.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) { return array }
                return s
            case .blob(let data):
                if data.count == 16 { return NSUUID(uuidBytes: [UInt8](data)).uuidString.lowercased() }
                return data.base64EncodedString()
        }
    }

    static func localValue(_ value: Any, column: String) -> DatabaseValueConvertible? {
        if value is NSNull { return nil }
        if let s = value as? String {
            if uuidColumns.contains(column) || column.hasSuffix("ID"), let uuid = UUID(uuidString: s), s.count == 36 { return uuid }
            if dateColumns.contains(column), let date = parseDate(s) { return date }
            return s
        }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber {
            if boolColumns.contains(column) { return n.boolValue }
            if n.doubleValue == n.doubleValue.rounded() { return n.int64Value }
            return n.doubleValue
        }
        if let array = value as? [Any], let data = try? JSONSerialization.data(withJSONObject: array) { return String(decoding: data, as: UTF8.self) }
        return nil
    }

    static func snakeCase(_ name: String) -> String {
        var out = ""
        let chars = Array(name)
        for (i, c) in chars.enumerated() {
            if c.isUppercase {
                let prevLower = i > 0 && !chars[i - 1].isUppercase
                let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
                if i > 0 && (prevLower || nextLower) { out.append("_") }
                out.append(c.lowercased())
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func camelCase(_ name: String) -> String {
        var out = ""
        var upper = false
        for c in name {
            if c == "_" { upper = true; continue }
            out.append(upper ? c.uppercased() : String(c))
            upper = false
        }
        // id suffixes: student_id → studentID, section_id → sectionID
        if out.hasSuffix("Id"), out.count > 2 { out = String(out.dropLast(2)) + "ID" }
        if out.hasSuffix("Json") { out = String(out.dropLast(4)) + "JSON" }
        return out
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let grdb: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()

    /// Accepts ISO8601 (any fraction length, Z or ±HH:MM), Postgres "YYYY-MM-DD HH:MM:SS.ffffff+00" and GRDB's "yyyy-MM-dd HH:mm:ss.SSS".
    static func parseDate(_ s: String) -> Date? {
        if let d = grdb.date(from: s) { return d }
        var t = s.replacingOccurrences(of: " ", with: "T")
        if t.hasSuffix("+00:00") { t = String(t.dropLast(6)) + "Z" }
        else if t.hasSuffix("+00") { t = String(t.dropLast(3)) + "Z" }
        if let dot = t.firstIndex(of: ".") {
            let after = t[t.index(after: dot)...]
            let digits = after.prefix { $0.isNumber }
            let rest = after.dropFirst(digits.count)
            if digits.count != 3 {
                let frac = (String(digits) + "000").prefix(3)
                t = String(t[...dot]) + frac + rest
            }
        }
        if !t.hasSuffix("Z"), !t.contains("+"), !t.dropFirst(11).contains("-") { t += "Z" }
        return isoFractional.date(from: t) ?? iso.date(from: t)
    }

    static func formatDate(_ d: Date) -> String { isoFractional.string(from: d) }
}
