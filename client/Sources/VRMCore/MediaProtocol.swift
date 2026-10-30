import Foundation

public enum MediaPacketType: UInt8, Sendable, Equatable {
    case video = 1
    case input = 2
    case audio = 3
    case frameMeta = 4
    case nack = 5
    case idrRequest = 6
    case keepAlive = 7
}

public struct MediaFlags: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let keyframe = MediaFlags(rawValue: 1 << 0)
    public static let config = MediaFlags(rawValue: 1 << 1)
    public static let retransmit = MediaFlags(rawValue: 1 << 2)
    public static let metaDuplicate = MediaFlags(rawValue: 1 << 3)
    public static let plaintext = MediaFlags(rawValue: 1 << 4)
}

public struct MediaHeader: Equatable, Sendable {
    public var version: UInt8
    public var type: MediaPacketType
    public var flags: MediaFlags
    public var fragmentIndex: UInt16
    public var fragmentCount: UInt16
    public var payloadLength: UInt16
    public var sessionId: UInt32
    public var frameId: UInt32
    public var packetSequence: UInt64
    public var timestampNs: UInt64

    public init(
        version: UInt8 = 1,
        type: MediaPacketType,
        flags: MediaFlags = [.plaintext],
        fragmentIndex: UInt16 = 0,
        fragmentCount: UInt16 = 1,
        payloadLength: UInt16 = 0,
        sessionId: UInt32 = 0,
        frameId: UInt32 = 0,
        packetSequence: UInt64 = 0,
        timestampNs: UInt64 = 0
    ) {
        self.version = version
        self.type = type
        self.flags = flags
        self.fragmentIndex = fragmentIndex
        self.fragmentCount = fragmentCount
        self.payloadLength = payloadLength
        self.sessionId = sessionId
        self.frameId = frameId
        self.packetSequence = packetSequence
        self.timestampNs = timestampNs
    }

    public func encoded() -> Data {
        var writer = ByteWriter(capacity: ProtocolConstants.mediaHeaderSize)
        writer.bytes(Data(ProtocolConstants.mediaMagic))
        writer.u8(version)
        writer.u8(type.rawValue)
        writer.u8(flags.rawValue)
        writer.u8(0)
        writer.u16(fragmentIndex)
        writer.u16(fragmentCount)
        writer.u16(payloadLength)
        writer.u32(sessionId)
        writer.u32(frameId)
        writer.u32(0)
        writer.u64(packetSequence)
        writer.u64(timestampNs)
        return writer.data
    }

    public static func decode(from data: Data) throws -> MediaHeader {
        guard data.count >= ProtocolConstants.mediaHeaderSize else {
            throw ProtocolError.truncated(field: "media header")
        }
        var reader = ByteReader(data)
        let magic = try reader.data(count: 2)
        guard magic.elementsEqual(ProtocolConstants.mediaMagic) else { throw ProtocolError.invalidMagic }
        let version = try reader.u8()
        guard version == 1 else { throw ProtocolError.unsupportedVersion(major: version, minor: 0) }
        let typeRaw = try reader.u8()
        guard let type = MediaPacketType(rawValue: typeRaw) else {
            throw ProtocolError.unknownMessageType(typeRaw)
        }
        let flags = MediaFlags(rawValue: try reader.u8())
        _ = try reader.u8()
        let fragmentIndex = try reader.u16()
        let fragmentCount = try reader.u16()
        let payloadLength = try reader.u16()
        let sessionId = try reader.u32()
        let frameId = try reader.u32()
        _ = try reader.u32()
        let packetSequence = try reader.u64()
        let timestamp = try reader.u64()
        guard fragmentCount > 0, fragmentIndex < fragmentCount else {
            throw ProtocolError.invalidValue(field: "fragment index/count")
        }
        guard payloadLength <= ProtocolConstants.maxMediaPayload else {
            throw ProtocolError.payloadTooLarge(Int(payloadLength))
        }
        return MediaHeader(
            version: version, type: type, flags: flags,
            fragmentIndex: fragmentIndex, fragmentCount: fragmentCount,
            payloadLength: payloadLength, sessionId: sessionId, frameId: frameId,
            packetSequence: packetSequence, timestampNs: timestamp
        )
    }

    public func datagram(payload: Data) throws -> Data {
        guard payload.count <= ProtocolConstants.maxMediaPayload else {
            throw ProtocolError.payloadTooLarge(payload.count)
        }
        var header = self
        header.payloadLength = UInt16(payload.count)
        var output = header.encoded()
        output.append(payload)
        guard output.count <= ProtocolConstants.maxDatagramBytes else {
            throw ProtocolError.payloadTooLarge(output.count)
        }
        return output
    }

    public static func parseDatagram(_ data: Data) throws -> (MediaHeader, Data) {
        let header = try decode(from: data)
        let start = ProtocolConstants.mediaHeaderSize
        let end = start + Int(header.payloadLength)
        guard data.count >= end else { throw ProtocolError.truncated(field: "media payload") }
        guard data.count == end else { throw ProtocolError.trailingBytes(data.count - end) }
        return (header, data.subdata(in: start..<end))
    }
}

// MARK: - Metadata

public struct FrameMeta: Equatable, Sendable {
    public var frameId: UInt32
    public var captureHeadPosition: Vec3
    public var captureHeadOrientation: Quat
    public var flags: UInt32
    public var sourceFrameNumber: UInt64
    public var clientHeadTimestampNs: UInt64

    public init(
        frameId: UInt32,
        captureHeadPosition: Vec3,
        captureHeadOrientation: Quat,
        flags: UInt32 = 0,
        sourceFrameNumber: UInt64 = 0,
        clientHeadTimestampNs: UInt64 = 0
    ) {
        self.frameId = frameId
        self.captureHeadPosition = captureHeadPosition
        self.captureHeadOrientation = captureHeadOrientation
        self.flags = flags
        self.sourceFrameNumber = sourceFrameNumber
        self.clientHeadTimestampNs = clientHeadTimestampNs
    }

    public func encodePayload() throws -> Data {
        var writer = ByteWriter(capacity: 48)
        writer.u32(frameId)
        try writer.vec3(captureHeadPosition)
        try writer.quat(captureHeadOrientation)
        writer.u32(flags)
        writer.u64(sourceFrameNumber)
        writer.u64(clientHeadTimestampNs)
        return writer.data
    }

    public static func decodePayload(_ data: Data) throws -> FrameMeta {
        var reader = ByteReader(data)
        let frameId = try reader.u32()
        let position = try reader.vec3()
        let orientation = try reader.quat()
        let flags = try reader.u32()
        let source = try reader.u64()
        let clientHeadTimestampNs = try reader.u64()
        try reader.requireFinished()
        return FrameMeta(
            frameId: frameId, captureHeadPosition: position,
            captureHeadOrientation: orientation, flags: flags,
            sourceFrameNumber: source, clientHeadTimestampNs: clientHeadTimestampNs
        )
    }
}

public struct NackMessage: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var frameId: UInt32
        public var fragmentIndex: UInt16
        public init(frameId: UInt32, fragmentIndex: UInt16) {
            self.frameId = frameId
            self.fragmentIndex = fragmentIndex
        }
    }

    public var entries: [Entry]
    public init(entries: [Entry]) {
        self.entries = Array(entries.prefix(160))
    }

    public func encodePayload() throws -> Data {
        var writer = ByteWriter(capacity: 6 + entries.count * 6)
        if let first = entries.first {
            writer.u32(first.frameId)
            writer.u16(UInt16(entries.count))
        } else {
            writer.u32(0)
            writer.u16(0)
        }
        for entry in entries {
            writer.u32(entry.frameId)
            writer.u16(entry.fragmentIndex)
            writer.u16(0)
        }
        return writer.data
    }

    public static func decodePayload(_ data: Data) throws -> NackMessage {
        var reader = ByteReader(data)
        _ = try reader.u32()
        let count = try reader.u16()
        guard count <= 160 else { throw ProtocolError.invalidValue(field: "nack count") }
        var entries: [Entry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0..<count {
            entries.append(Entry(frameId: try reader.u32(), fragmentIndex: try reader.u16()))
            _ = try reader.u16()
        }
        try reader.requireFinished()
        return NackMessage(entries: entries)
    }
}

public struct IdrRequestMessage: Equatable, Sendable {
    public var lastFrameId: UInt32
    public var reason: UInt8
    public var clientTimeNs: UInt64
    public init(lastFrameId: UInt32, reason: UInt8 = 0, clientTimeNs: UInt64 = 0) {
        self.lastFrameId = lastFrameId
        self.reason = reason
        self.clientTimeNs = clientTimeNs
    }

    public func encodePayload() throws -> Data {
        var writer = ByteWriter(capacity: 16)
        writer.u32(lastFrameId)
        writer.u8(reason)
        writer.reserve(u8: 3)
        writer.u64(clientTimeNs)
        return writer.data
    }

    public static func decodePayload(_ data: Data) throws -> IdrRequestMessage {
        var reader = ByteReader(data)
        let last = try reader.u32()
        let reason = try reader.u8()
        try reader.skip(3)
        let time = try reader.u64()
        try reader.requireFinished()
        return IdrRequestMessage(lastFrameId: last, reason: reason, clientTimeNs: time)
    }
}

public struct KeepAliveMessage: Equatable, Sendable {
    public var clientTimeNs: UInt64
    public var inputSequence: UInt64
    public init(clientTimeNs: UInt64, inputSequence: UInt64 = 0) {
        self.clientTimeNs = clientTimeNs
        self.inputSequence = inputSequence
    }

    public func encodePayload() -> Data {
        var writer = ByteWriter(capacity: 16)
        writer.u64(clientTimeNs)
        writer.u64(inputSequence)
        return writer.data
    }

    public static func decodePayload(_ data: Data) throws -> KeepAliveMessage {
        var reader = ByteReader(data)
        let time = try reader.u64()
        let sequence = try reader.u64()
        try reader.requireFinished()
        return KeepAliveMessage(clientTimeNs: time, inputSequence: sequence)
    }
}

// MARK: - Reassembly

public struct EncodedVideoFrame: Equatable, Sendable {
    public var frameId: UInt32
    public var timestampNs: UInt64
    public var isKeyframe: Bool
    public var isConfig: Bool
    public var data: Data

    public init(frameId: UInt32, timestampNs: UInt64, isKeyframe: Bool, isConfig: Bool, data: Data) {
        self.frameId = frameId
        self.timestampNs = timestampNs
        self.isKeyframe = isKeyframe
        self.isConfig = isConfig
        self.data = data
    }
}

public struct FrameAssemblerResult: Equatable, Sendable {
    public var completed: EncodedVideoFrame?
    public var nack: [NackMessage.Entry]?
    public var droppedFrameId: UInt32?
    public var requiresIDR: Bool
    public var droppedReason: String?

    public init(
        completed: EncodedVideoFrame? = nil,
        nack: [NackMessage.Entry]? = nil,
        droppedFrameId: UInt32? = nil,
        requiresIDR: Bool = false,
        droppedReason: String? = nil
    ) {
        self.completed = completed
        self.nack = nack
        self.droppedFrameId = droppedFrameId
        self.requiresIDR = requiresIDR
        self.droppedReason = droppedReason
    }
}

public final class FrameAssembler: @unchecked Sendable {
    private struct FrameState {
        var id: UInt32
        var expected: Int
        var fragments: [Data?]
        var received: Int
        var bytes: Int
        var firstSeen: Timestamp
        var lastNack: Timestamp?
        var timestampNs: UInt64
        var keyframe: Bool
        var config: Bool
    }

    private let lock = NSLock()
    private var current: FrameState?
    private var lastCompletedId: UInt32?
    private let nackDelayMs: Double
    private let dropDelayMs: Double

    public init(nackDelayMs: Double = 50, dropDelayMs: Double = 150) {
        self.nackDelayMs = nackDelayMs
        self.dropDelayMs = dropDelayMs
    }

    public func reset() {
        lock.lock()
        current = nil
        lock.unlock()
    }

    public func ingest(header: MediaHeader, payload: Data, now: Timestamp = .now()) -> FrameAssemblerResult {
        lock.lock()
        defer { lock.unlock() }

        guard header.type == .video, header.fragmentCount <= UInt16(ProtocolConstants.maxFragments) else {
            return FrameAssemblerResult(requiresIDR: true, droppedReason: "invalid video fragment")
        }
        let count = Int(header.fragmentCount)
        let index = Int(header.fragmentIndex)
        guard index < count else {
            return FrameAssemblerResult(requiresIDR: true, droppedReason: "fragment index out of range")
        }

        var result = FrameAssemblerResult()

        if let frame = current, frame.id != header.frameId {
            let isNewer = Int32(bitPattern: header.frameId &- frame.id) > 0
            if !isNewer {
                // Late fragment for an already replaced frame.
                return result
            }
            if frame.received < frame.expected {
                result.droppedFrameId = frame.id
                result.requiresIDR = true
                result.droppedReason = "new frame before previous completion"
            }
            current = nil
        }

        if current == nil {
            let totalBytes = payload.count * count
            guard totalBytes <= ProtocolConstants.maxVideoFrameBytes else {
                return FrameAssemblerResult(requiresIDR: true, droppedReason: "frame too large")
            }
            current = FrameState(
                id: header.frameId,
                expected: count,
                fragments: Array(repeating: nil, count: count),
                received: 0,
                bytes: 0,
                firstSeen: now,
                lastNack: nil,
                timestampNs: header.timestampNs,
                keyframe: header.flags.contains(.keyframe),
                config: header.flags.contains(.config)
            )
        }

        guard var frame = current, frame.id == header.frameId else {
            return FrameAssemblerResult(requiresIDR: true, droppedReason: "frame state mismatch")
        }
        guard index < frame.expected else {
            return FrameAssemblerResult(requiresIDR: true, droppedReason: "fragment count changed")
        }
        if frame.fragments[index] == nil {
            frame.fragments[index] = payload
            frame.received += 1
            frame.bytes += payload.count
        }
        current = frame

        if frame.received == frame.expected, let data = assemble(frame) {
            lastCompletedId = frame.id
            current = nil
            result.completed = EncodedVideoFrame(
                frameId: frame.id,
                timestampNs: frame.timestampNs,
                isKeyframe: frame.keyframe,
                isConfig: frame.config,
                data: data
            )
        }
        return result
    }

    public func poll(now: Timestamp = .now()) -> FrameAssemblerResult {
        lock.lock()
        defer { lock.unlock() }
        guard let frame = current else { return FrameAssemblerResult() }
        let age = Double(now.distance(to: frame.firstSeen)) / 1_000_000
        if age >= dropDelayMs {
            current = nil
            return FrameAssemblerResult(
                droppedFrameId: frame.id,
                requiresIDR: true,
                droppedReason: "reassembly timeout"
            )
        }
        if age >= nackDelayMs {
            if let last = frame.lastNack, now.distance(to: last) < 50_000_000 {
                return FrameAssemblerResult()
            }
            var missing: [NackMessage.Entry] = []
            for (index, fragment) in frame.fragments.enumerated() where fragment == nil {
                missing.append(NackMessage.Entry(frameId: frame.id, fragmentIndex: UInt16(index)))
                if missing.count >= 160 { break }
            }
            if !missing.isEmpty {
                current?.lastNack = now
                return FrameAssemblerResult(nack: missing)
            }
        }
        return FrameAssemblerResult()
    }

    public var incompleteFrameId: UInt32? {
        lock.lock()
        defer { lock.unlock() }
        return current?.id
    }

    private func assemble(_ frame: FrameState) -> Data? {
        var data = Data()
        data.reserveCapacity(frame.bytes)
        for fragment in frame.fragments {
            guard let fragment else { return nil }
            data.append(fragment)
        }
        return data
    }
}
