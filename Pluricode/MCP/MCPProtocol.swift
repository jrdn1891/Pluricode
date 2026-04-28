import Foundation

enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int64.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }
    var intValue: Int? {
        switch self {
        case .int(let v): Int(v)
        case .double(let v): Int(v)
        default: nil
        }
    }
    var boolValue: Bool? { if case .bool(let v) = self { return v } else { return nil } }
    var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v } else { return nil } }
    var arrayValue: [JSONValue]? { if case .array(let v) = self { return v } else { return nil } }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] } else { return nil }
    }

    static func from(_ obj: [String: Any]) -> JSONValue {
        .object(obj.mapValues { wrap($0) })
    }

    private static func wrap(_ value: Any) -> JSONValue {
        if let v = value as? String { return .string(v) }
        if let v = value as? Bool { return .bool(v) }
        if let v = value as? Int { return .int(Int64(v)) }
        if let v = value as? Int64 { return .int(v) }
        if let v = value as? Double { return .double(v) }
        if let v = value as? [Any] { return .array(v.map(wrap)) }
        if let v = value as? [String: Any] { return .object(v.mapValues(wrap)) }
        if value is NSNull { return .null }
        return .null
    }
}

struct JSONRPCError: Error, Codable {
    let code: Int
    let message: String
    let data: JSONValue?

    static let parseError = JSONRPCError(code: -32700, message: "Parse error", data: nil)
    static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request", data: nil)
    static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found", data: nil)
    static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params", data: nil)
    static let internalError = JSONRPCError(code: -32603, message: "Internal error", data: nil)

    static func invalid(_ message: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: message, data: nil)
    }
    static func application(_ message: String) -> JSONRPCError {
        JSONRPCError(code: -32000, message: message, data: nil)
    }
}

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONValue?
    let result: JSONValue?
    let error: JSONRPCError?

    init(id: JSONValue?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JSONValue?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

enum MCPFraming {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    static func splitLines(buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        return lines
    }
}
