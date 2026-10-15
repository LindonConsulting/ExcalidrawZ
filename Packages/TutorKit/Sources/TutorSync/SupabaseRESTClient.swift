import Foundation
import TutorModels

/// Minimal PostgREST client for the ConwyMaths Supabase project.
/// Uses the service-role key (tutor's own machine), stored by the app in the Keychain.
public struct SupabaseRESTClient: Sendable {
    public enum ClientError: LocalizedError {
        case http(Int, String)
        case notConfigured
        public var errorDescription: String? {
            switch self {
                case .http(let code, let body): return "Supabase request failed (HTTP \(code)): \(body)"
                case .notConfigured: return "Supabase sync is not configured. Add the project URL and key in Settings → Lessons."
            }
        }
    }

    public var baseURL: URL
    public var apiKey: String
    public var session: URLSession = .shared

    public init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: s) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: s) { return date }
            let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.timeZone = TimeZone(identifier: "UTC")
            if let date = day.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unrecognised date \(s)")
        }
        return d
    }()

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, prefer: String? = nil) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(path)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.http(0, "No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }

    public func select<T: Decodable>(_ type: T.Type, from table: String, columns: String = "*", filters: [URLQueryItem] = [], order: String? = nil) async throws -> [T] {
        var query = [URLQueryItem(name: "select", value: columns)] + filters
        if let order { query.append(URLQueryItem(name: "order", value: order)) }
        let data = try await send(try request("GET", table, query: query))
        return try Self.decoder.decode([T].self, from: data)
    }

    @discardableResult
    public func insert<T: Encodable, R: Decodable>(_ rows: [T], into table: String, returning: R.Type) async throws -> [R] {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try await send(try request("POST", table, body: try encoder.encode(rows), prefer: "return=representation"))
        return try Self.decoder.decode([R].self, from: data)
    }

    public func update<T: Encodable>(_ patch: T, in table: String, filters: [URLQueryItem]) async throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        _ = try await send(try request("PATCH", table, query: filters, body: try encoder.encode(patch), prefer: "return=minimal"))
    }

    /// Quick connectivity check: counts students.
    public func ping() async throws -> Int {
        try await selectRows(from: "students", columns: "id", filters: [URLQueryItem(name: "deleted_at", value: "is.null")]).count
    }

    // MARK: Raw JSON rows (used by the sync engine)

    /// Rows as JSON dictionaries; dates stay ISO8601 strings.
    public func selectRows(from table: String, columns: String = "*", filters: [URLQueryItem] = [], order: String? = nil,
                           limit: Int? = nil, offset: Int? = nil) async throws -> [[String: Any]] {
        var query = [URLQueryItem(name: "select", value: columns)] + filters
        if let order { query.append(URLQueryItem(name: "order", value: order)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { query.append(URLQueryItem(name: "offset", value: String(offset))) }
        let data = try await send(try request("GET", table, query: query))
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// Insert-or-update on the primary key (or `onConflict` columns).
    public func upsertRows(_ rows: [[String: Any]], into table: String, onConflict: String? = nil) async throws {
        guard !rows.isEmpty else { return }
        var query: [URLQueryItem] = []
        if let onConflict { query.append(URLQueryItem(name: "on_conflict", value: onConflict)) }
        let body = try JSONSerialization.data(withJSONObject: rows)
        _ = try await send(try request("POST", table, query: query, body: body, prefer: "resolution=merge-duplicates,return=minimal"))
    }
}

// MARK: - Remote rows

public struct RemoteStudent: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var year_group: String?
    public var target_grade: String?
    public var management: String?
    public var notes: String?
    public var rapport_notes: String?
    public var parent_name: String?
    public var parent_phone: String?
    public var parent_email: String?
    public var deleted_at: Date?
}

public struct RemoteEnrolment: Codable, Sendable, Identifiable {
    public var id: UUID
    public var student_id: UUID
    public var course_id: String
    public var board: String?
    public var tier: String?
    public var active: Bool?
}

public struct RemoteDeck: Codable, Sendable, Identifiable {
    public var id: UUID
    public var slug: String
    public var title: String
    public var deck_type: String?
    public var card_count: Int?
}

public struct RemoteDeckAssignment: Codable, Sendable, Identifiable {
    public var id: UUID
    public var deck_id: UUID
    public var student_id: UUID
    public var assigned_at: Date?
    public var due_at: Date?
    public var completed_at: Date?
    public var notes: String?
}

public extension SupabaseRESTClient {
    func fetchStudents(includeTest: Bool = false) async throws -> [RemoteStudent] {
        var filters = [URLQueryItem(name: "deleted_at", value: "is.null")]
        if !includeTest { filters.append(URLQueryItem(name: "name", value: "not.ilike.Test%")) }
        return try await select(RemoteStudent.self, from: "students", filters: filters, order: "name.asc")
    }

    func fetchEnrolments() async throws -> [RemoteEnrolment] {
        try await select(RemoteEnrolment.self, from: "student_enrolments", order: "created_at.asc")
    }

    func fetchDecks() async throws -> [RemoteDeck] {
        try await select(RemoteDeck.self, from: "decks", columns: "id,slug,title,deck_type,card_count", order: "title.asc")
    }

    func fetchDeckAssignments() async throws -> [RemoteDeckAssignment] {
        try await select(RemoteDeckAssignment.self, from: "deck_assignments", order: "assigned_at.desc")
    }
}

/// Maps a ConwyMaths enrolment onto TutorKit's subject / level / board / tier.
public enum EnrolmentMapper {
    public static func map(courseID: String, board: String?, tier: String?) -> (subject: Subject, level: QualificationLevel, board: ExamBoard?, tier: Tier?) {
        let course = courseID.lowercased()
        let subject: Subject = course.contains("cs") || course.contains("comp") ? .computerScience : .maths
        let level: QualificationLevel
        if course.hasPrefix("alevel") { level = .aLevel }
        else if course.hasPrefix("gcse") { level = .gcse }
        else if course.hasPrefix("ks3") || course.hasPrefix("ks2") { level = .ks3 }
        else { level = .other }
        let examBoard = ExamBoard.allCases.first { $0.rawValue.caseInsensitiveCompare(board ?? "") == .orderedSame }
        let examTier: Tier? = {
            switch (tier ?? "").lowercased() {
                case "higher": return .higher
                case "foundation": return .foundation
                default: return nil
            }
        }()
        return (subject, level, examBoard, examTier)
    }
}
