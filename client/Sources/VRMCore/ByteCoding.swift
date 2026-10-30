import Foundation

public enum ProtocolError: Error, Equatable, CustomStringConvertible, Sendable {
    case truncated(field: String)
    case invalidMagic
    case unsupportedVersion(major: UInt8, minor: UInt8)
    case unknownMessageType(UInt8)
    case payloadTooLarge(Int)
    case invalidValue(field: String)
    case trailingBytes(Int)
    case badStringLength(UInt16)
    case badUTF8
    case nonFinite(field: String)
    case invalidSession
    case sequenceOutOfWindow
    case encryptionRequired
    case authenticationFailed

    public var description: String {
        switch self {
        case .truncated(let field): return "truncated while reading \(field)"
        case .invalidMagic: return "invalid magic"
        case .unsupportedVersion(let major, let minor): return "unsupported version \(major).\(minor)"
        case .unknownMessageType(let type): return "unknown message type \(type)"
        case .payloadTooLarge(let size): return "payload too large (\(size))"
        case .invalidValue(let field): return "invalid value for \(field)"
        case .trailingBytes(let count): return "\(count) trailing bytes"
        case .badStringLength(let length): return "bad string length \(length)"
        case .badUTF8: return "invalid UTF-8"
        case .nonFinite(let field): return "non-finite value in \(field)"
        case .invalidSession: return "invalid session"
        case .sequenceOutOfWindow: return "sequence outside replay window"
        case .encryptionRequired: return "encryption required"
        case .authenticationFailed: return "authentication failed"
        }
    }
}

public struct ByteWriter: Sendable {
    private(set) public var data = Data()

    public init(capacity: Int = 128) {
        data.reserveCapacity(capacity)
    }

    public mutating func u8(_ value: UInt8) { data.append(value) }

    public mutating func u16(_ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    public mutating func u32(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    public mutating func u64(_ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    public mutating func i32(_ value: Int32) { u32(UInt32(bitPattern: value)) }
    public mutating func i64(_ value: Int64) { u64(UInt64(bitPattern: value)) }

    public mutating func f32(_ value: Float) throws {
        guard value.isFinite else { throw ProtocolError.nonFinite(field: "f32") }
        u32(value.bitPattern)
    }

    public mutating func vec3(_ value: Vec3) throws {
        try f32(value.x); try f32(value.y); try f32(value.z)
    }

    public mutating func quat(_ value: Quat) throws {
        try f32(value.x); try f32(value.y); try f32(value.z); try f32(value.w)
    }

    public mutating func string(_ value: String, maxLength: Int = 255) throws {
        let bytes = Data(value.utf8)
        guard bytes.count <= min(maxLength, Int(UInt16.max)) else {
            throw ProtocolError.invalidValue(field: "string length")
        }
        u16(UInt16(bytes.count))
        data.append(bytes)
    }

    public mutating func bytes(_ value: Data) { data.append(value) }

    public mutating func reserve(u8 count: Int) {
        data.append(contentsOf: repeatElement(0, count: count))
    }
}

public struct ByteReader: Sendable {
    private let data: Data
    private var index: Int = 0

    public init(_ data: Data) {
        self.data = data
    }

    public var remaining: Int { data.count - index }
    public var position: Int { index }

    public mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw ProtocolError.truncated(field: "u8") }
        defer { index += 1 }
        return data[data.startIndex + index]
    }

    public mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw ProtocolError.truncated(field: "u16") }
        let start = data.startIndex + index
        index += 2
        return UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
    }

    public mutating func u32() throws -> UInt32 {
        guard remaining >= 4 else { throw ProtocolError.truncated(field: "u32") }
        let start = data.startIndex + index
        index += 4
        return UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }

    public mutating func u64() throws -> UInt64 {
        guard remaining >= 8 else { throw ProtocolError.truncated(field: "u64") }
        let start = data.startIndex + index
        index += 8
        var value: UInt64 = 0
        for offset in 0..<8 {
            value |= UInt64(data[start + offset]) << UInt64(offset * 8)
        }
        return value
    }

    public mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    public mutating func i64() throws -> Int64 { Int64(bitPattern: try u64()) }

    public mutating func f32() throws -> Float {
        let value = Float(bitPattern: try u32())
        guard value.isFinite else { throw ProtocolError.nonFinite(field: "f32") }
        return value
    }

    public mutating func vec3() throws -> Vec3 {
        Vec3(try f32(), try f32(), try f32())
    }

    public mutating func quat() throws -> Quat {
        let value = Quat(try f32(), try f32(), try f32(), try f32()).normalized()
        guard value.lengthSquared > 0.5 else { throw ProtocolError.invalidValue(field: "quaternion") }
        return value
    }

    public mutating func string(maxLength: Int = 255) throws -> String {
        let length = try u16()
        guard length <= UInt16(min(maxLength, 65_535)) else {
            throw ProtocolError.badStringLength(length)
        }
        return try string(bytes: Int(length))
    }

    public mutating func string(bytes length: Int) throws -> String {
        guard remaining >= length else { throw ProtocolError.truncated(field: "string bytes") }
        let start = data.startIndex + index
        index += length
        guard let value = String(data: data[start..<start + length], encoding: .utf8) else {
            throw ProtocolError.badUTF8
        }
        return value
    }

    public mutating func data(count: Int) throws -> Data {
        guard count >= 0, remaining >= count else { throw ProtocolError.truncated(field: "bytes") }
        let start = data.startIndex + index
        index += count
        return data[start..<start + count]
    }

    public mutating func skip(_ count: Int) throws {
        guard count >= 0, remaining >= count else { throw ProtocolError.truncated(field: "skip") }
        index += count
    }

    public func requireFinished() throws {
        guard remaining == 0 else { throw ProtocolError.trailingBytes(remaining) }
    }
}
