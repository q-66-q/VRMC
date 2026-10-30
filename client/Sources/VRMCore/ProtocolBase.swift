import Foundation

public enum ProtocolConstants {
    public static let magic: [UInt8] = [0x56, 0x52, 0x4D, 0x43] // "VRMC"
    public static let mediaMagic: [UInt8] = [0x56, 0x4D]       // "VM"
    public static let versionMajor: UInt8 = 1
    public static let versionMinor: UInt8 = 0
    public static let controlHeaderSize = 24
    public static let mediaHeaderSize = 40
    public static let maxControlPayload = 1_048_576
    public static let maxDatagramBytes = 1_200
    public static let maxMediaPayload = 1_144
    public static let maxVideoFrameBytes = 8 * 1_024 * 1_024
    public static let maxFragments = 1_024
    public static let maxStringBytes = 255
    public static let controlPort: UInt16 = 48_625
    public static let mediaPort: UInt16 = 48_626
    public static let inputPort: UInt16 = 48_627
}

public struct ControlFlags: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let plaintext = ControlFlags(rawValue: 1 << 0)
    public static let authRequired = ControlFlags(rawValue: 1 << 1)
}

public enum MessageType: UInt8, CaseIterable, Sendable {
    case hello = 0x01
    case welcome = 0x02
    case authChallenge = 0x03
    case authResponse = 0x04
    case authOK = 0x05
    case streamConfig = 0x06
    case startStream = 0x07
    case stopStream = 0x08
    case keyframeRequest = 0x09
    case sessionState = 0x0A
    case clockPing = 0x0B
    case clockPong = 0x0C
    case telemetryClient = 0x0D
    case telemetryHost = 0x0E
    case setQuality = 0x0F
    case inputConfig = 0x10
    case haptic = 0x11
    case heartbeat = 0x12
    case disconnect = 0x13
    case error = 0x14
    case audioConfig = 0x15
}

public struct ControlHeader: Equatable, Sendable {
    public var versionMajor: UInt8
    public var versionMinor: UInt8
    public var type: MessageType
    public var flags: ControlFlags
    public var sessionId: UInt32
    public var sequence: UInt32
    public var payloadLength: UInt32

    public init(
        versionMajor: UInt8 = ProtocolConstants.versionMajor,
        versionMinor: UInt8 = ProtocolConstants.versionMinor,
        type: MessageType,
        flags: ControlFlags = .plaintext,
        sessionId: UInt32 = 0,
        sequence: UInt32 = 0,
        payloadLength: UInt32 = 0
    ) {
        self.versionMajor = versionMajor
        self.versionMinor = versionMinor
        self.type = type
        self.flags = flags
        self.sessionId = sessionId
        self.sequence = sequence
        self.payloadLength = payloadLength
    }

    public func encoded() -> Data {
        var writer = ByteWriter(capacity: ProtocolConstants.controlHeaderSize)
        writer.bytes(Data(ProtocolConstants.magic))
        writer.u8(versionMajor)
        writer.u8(versionMinor)
        writer.u8(type.rawValue)
        writer.u8(flags.rawValue)
        writer.u32(sessionId)
        writer.u32(sequence)
        writer.u32(payloadLength)
        writer.u32(0)
        return writer.data
    }

    public static func decode(from data: Data) throws -> ControlHeader {
        guard data.count >= ProtocolConstants.controlHeaderSize else {
            throw ProtocolError.truncated(field: "control header")
        }
        var reader = ByteReader(data)
        let magic = try reader.data(count: 4)
        guard magic.elementsEqual(ProtocolConstants.magic) else { throw ProtocolError.invalidMagic }
        let versionMajor = try reader.u8()
        let versionMinor = try reader.u8()
        let typeRaw = try reader.u8()
        guard let type = MessageType(rawValue: typeRaw) else {
            throw ProtocolError.unknownMessageType(typeRaw)
        }
        let flags = ControlFlags(rawValue: try reader.u8())
        let sessionId = try reader.u32()
        let sequence = try reader.u32()
        let payloadLength = try reader.u32()
        _ = try reader.u32() // reserved
        guard versionMajor == ProtocolConstants.versionMajor else {
            throw ProtocolError.unsupportedVersion(major: versionMajor, minor: versionMinor)
        }
        guard payloadLength <= UInt32(ProtocolConstants.maxControlPayload) else {
            throw ProtocolError.payloadTooLarge(Int(payloadLength))
        }
        return ControlHeader(
            versionMajor: versionMajor,
            versionMinor: versionMinor,
            type: type,
            flags: flags,
            sessionId: sessionId,
            sequence: sequence,
            payloadLength: payloadLength
        )
    }
}

// MARK: - Shared enums

public enum AuthMode: UInt8, Sendable, Equatable {
    case pairingCode = 1
    case token = 2
    case insecureDev = 3
}

public struct Capabilities: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let handSkeleton = Capabilities(rawValue: 1 << 0)
    public static let headPose = Capabilities(rawValue: 1 << 1)
    public static let reprojection = Capabilities(rawValue: 1 << 2)
    public static let audio = Capabilities(rawValue: 1 << 3)
    public static let haptics = Capabilities(rawValue: 1 << 4)
    public static let telemetry = Capabilities(rawValue: 1 << 5)
}

public enum EyeOrder: UInt8, Sendable, Equatable {
    case leftRight = 0
    case rightLeft = 1
}

public enum ColorSpace: UInt8, Sendable, Equatable {
    case sRGB = 0
    case linear = 1
}

public enum VideoCodec: UInt8, Sendable, Equatable {
    case h264 = 1
    case hevc = 2
}

public struct StreamFlags: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let reprojection = StreamFlags(rawValue: 1 << 0)
    public static let dualMirrorVerified = StreamFlags(rawValue: 1 << 1)
    public static let audioEnabled = StreamFlags(rawValue: 1 << 2)
    public static let verticalFlip = StreamFlags(rawValue: 1 << 3)
}

public enum SessionPhase: UInt8, Sendable, Equatable {
    case idle = 0
    case connecting = 1
    case authenticating = 2
    case ready = 3
    case streaming = 4
    case degraded = 5
    case reconnecting = 6
    case stopping = 7
    case error = 8
}

public struct SessionFlags: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let captureDegraded = SessionFlags(rawValue: 1 << 0)
    public static let encoderDegraded = SessionFlags(rawValue: 1 << 1)
    public static let networkDegraded = SessionFlags(rawValue: 1 << 2)
    public static let trackingDegraded = SessionFlags(rawValue: 1 << 3)
}

public enum ErrorCode: UInt16, Sendable, Equatable {
    case unsupported = 1
    case badVersion = 2
    case badPacket = 3
    case auth = 4
    case rateLimited = 5
    case busy = 6
    case internalError = 7
    case captureUnavailable = 8
    case encoderUnavailable = 9
    case timeout = 10
}

public struct ErrorPayload: Equatable, Sendable {
    public var code: ErrorCode
    public var detail: String

    public init(code: ErrorCode, detail: String = "") {
        self.code = code
        self.detail = detail
    }
}
