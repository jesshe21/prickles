import Foundation

enum PricklesState: String, Codable, Sendable {
    case good
    case error
}

struct PricklesStatus: Codable, Sendable, Equatable {
    var state: PricklesState
    var stateSince: Date?
    var lastChecked: Date?
    var sources: Sources?
    var schemaVersion: Int?

    struct Sources: Codable, Sendable, Equatable {
        var anthropic: Anthropic?
    }

    struct Anthropic: Codable, Sendable, Equatable {
        var status: String?
        var activeIncident: Incident?

        enum CodingKeys: String, CodingKey {
            case status
            case activeIncident = "active_incident"
        }
    }

    struct Incident: Codable, Sendable, Equatable {
        var id: String?
        var name: String?
        var url: String?
        var componentsDegraded: [String]?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case url
            case componentsDegraded = "components_degraded"
        }
    }

    enum CodingKeys: String, CodingKey {
        case state
        case stateSince = "state_since"
        case lastChecked = "last_checked"
        case sources
        case schemaVersion = "schema_version"
    }

    static let placeholderGood = PricklesStatus(
        state: .good,
        stateSince: Date().addingTimeInterval(-3600),
        lastChecked: Date(),
        sources: Sources(anthropic: Anthropic(status: "operational", activeIncident: nil)),
        schemaVersion: 1
    )

    static let placeholderError = PricklesStatus(
        state: .error,
        stateSince: Date().addingTimeInterval(-600),
        lastChecked: Date(),
        sources: Sources(anthropic: Anthropic(
            status: "incident",
            activeIncident: Incident(
                id: "sample",
                name: "Elevated errors on Claude.ai",
                url: "https://status.anthropic.com",
                componentsDegraded: ["claude.ai"]
            )
        )),
        schemaVersion: 1
    )
}

struct PricklesHistory: Codable, Sendable, Equatable {
    var entries: [Entry]
    var schemaVersion: Int?

    struct Entry: Codable, Sendable, Equatable, Identifiable {
        var state: PricklesState
        var from: Date
        var to: Date?
        var reason: String?

        var id: String { "\(state.rawValue)-\(from.timeIntervalSince1970)" }
        var isOngoing: Bool { to == nil }
    }

    enum CodingKeys: String, CodingKey {
        case entries
        case schemaVersion = "schema_version"
    }

    static let placeholder = PricklesHistory(
        entries: [
            Entry(state: .good, from: Date().addingTimeInterval(-3600), to: nil, reason: "operational"),
            Entry(state: .error, from: Date().addingTimeInterval(-7200), to: Date().addingTimeInterval(-3600), reason: "anthropic_incident"),
        ],
        schemaVersion: 1
    )
}

enum PricklesJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = iso.date(from: raw) ?? isoNoFrac.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO-8601 date: \(raw)"
            )
        }
        return d
    }()
}
