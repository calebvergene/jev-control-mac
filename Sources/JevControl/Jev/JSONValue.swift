import Foundation

/// A minimal JSON tree, for the parts of the Jev request whose shape is decided
/// at runtime — the `state` object and the per-question criteria, where a value
/// may legitimately be null.
enum JSONValue: Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    static func strings(_ values: [String]) -> JSONValue {
        .array(values.map(JSONValue.string))
    }

    static func map(_ values: [String: String]) -> JSONValue {
        .object(values.mapValues(JSONValue.string))
    }
}
