import Foundation

public enum InputSubtype: UInt8, Sendable, Equatable {
    case head = 1
    case hand = 2
    case intent = 3
}

public struct ControllerButtons: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let triggerClick = ControllerButtons(rawValue: 1 << 0)
    public static let gripClick = ControllerButtons(rawValue: 1 << 1)
    public static let a = ControllerButtons(rawValue: 1 << 2)
    public static let b = ControllerButtons(rawValue: 1 << 3)
    public static let system = ControllerButtons(rawValue: 1 << 4)
    public static let stickClick = ControllerButtons(rawValue: 1 << 5)
    public static let trackpadClick = ControllerButtons(rawValue: 1 << 6)
    public static let trackpadTouch = ControllerButtons(rawValue: 1 << 7)
    public static let triggerTouch = ControllerButtons(rawValue: 1 << 8)
    public static let gripTouch = ControllerButtons(rawValue: 1 << 9)
}

public struct HeadInput: Equatable, Sendable {
    public var quality: TrackingQuality
    public var flags: UInt16
    public var sampleId: UInt32
    public var pose: Pose
    public var linearVelocity: Vec3
    public var angularVelocity: Vec3

    public init(
        quality: TrackingQuality = .tracked,
        flags: UInt16 = 0,
        sampleId: UInt32 = 0,
        pose: Pose = .identity,
        linearVelocity: Vec3 = .zero,
        angularVelocity: Vec3 = .zero
    ) {
        self.quality = quality
        self.flags = flags
        self.sampleId = sampleId
        self.pose = pose
        self.linearVelocity = linearVelocity
        self.angularVelocity = angularVelocity
    }
}

public struct HandInput: Equatable, Sendable {
    public var snapshot: HandSnapshot
    public var flags: UInt16

    public init(snapshot: HandSnapshot, flags: UInt16 = 0) {
        self.snapshot = snapshot
        self.flags = flags
    }
}

public struct IntentInput: Equatable, Sendable {
    public var hand: HandChirality
    public var quality: TrackingQuality
    public var flags: UInt16
    public var sampleId: UInt32
    public var pose: Pose
    public var linearVelocity: Vec3
    public var angularVelocity: Vec3
    public var trigger: Float
    public var grip: Float
    public var stickX: Float
    public var stickY: Float
    public var trackpadX: Float
    public var trackpadY: Float
    public var buttons: ControllerButtons

    public init(
        hand: HandChirality,
        quality: TrackingQuality = .tracked,
        flags: UInt16 = 0,
        sampleId: UInt32 = 0,
        pose: Pose = .identity,
        linearVelocity: Vec3 = .zero,
        angularVelocity: Vec3 = .zero,
        trigger: Float = 0,
        grip: Float = 0,
        stickX: Float = 0,
        stickY: Float = 0,
        trackpadX: Float = 0,
        trackpadY: Float = 0,
        buttons: ControllerButtons = []
    ) {
        self.hand = hand
        self.quality = quality
        self.flags = flags
        self.sampleId = sampleId
        self.pose = pose
        self.linearVelocity = linearVelocity
        self.angularVelocity = angularVelocity
        self.trigger = trigger
        self.grip = grip
        self.stickX = stickX
        self.stickY = stickY
        self.trackpadX = trackpadX
        self.trackpadY = trackpadY
        self.buttons = buttons
    }

    public static func released(hand: HandChirality, quality: TrackingQuality = .invalid) -> IntentInput {
        IntentInput(hand: hand, quality: quality)
    }
}

public enum InputPayload: Equatable, Sendable {
    case head(HeadInput)
    case hand(HandInput)
    case intent(IntentInput)

    public var subtype: InputSubtype {
        switch self {
        case .head: return .head
        case .hand: return .hand
        case .intent: return .intent
        }
    }

    public func encodePayload() throws -> Data {
        var writer = ByteWriter(capacity: 1_024)
        writer.u8(subtype.rawValue)
        switch self {
        case .head(let input):
            writer.u8(input.quality.rawValue)
            writer.u16(input.flags)
            writer.u32(input.sampleId)
            try writer.vec3(input.pose.position)
            try writer.quat(input.pose.orientation)
            try writer.vec3(input.linearVelocity)
            try writer.vec3(input.angularVelocity)

        case .hand(let input):
            let snapshot = input.snapshot
            writer.u8(snapshot.chirality.rawValue)
            writer.u8(snapshot.quality.rawValue)
            writer.u16(input.flags)
            writer.u32(snapshot.sampleId)
            writer.u8(UInt8(HandJointName.count))
            writer.u8(0)
            try writer.vec3(snapshot.palmPosition)
            try writer.quat(snapshot.palmOrientation)
            for (index, joint) in snapshot.joints.enumerated() {
                writer.u8(UInt8(index))
                try writer.vec3(joint.position)
                try writer.quat(joint.orientation)
                try writer.f32(joint.radius)
            }

        case .intent(let input):
            writer.u8(input.hand.rawValue)
            writer.u8(input.quality.rawValue)
            writer.u16(input.flags)
            writer.u32(input.sampleId)
            try writer.vec3(input.pose.position)
            try writer.quat(input.pose.orientation)
            try writer.vec3(input.linearVelocity)
            try writer.vec3(input.angularVelocity)
            try writer.f32(clamp(input.trigger))
            try writer.f32(clamp(input.grip))
            try writer.f32(clampSigned(input.stickX))
            try writer.f32(clampSigned(input.stickY))
            try writer.f32(clampSigned(input.trackpadX))
            try writer.f32(clampSigned(input.trackpadY))
            writer.u32(input.buttons.rawValue)
            writer.u32(0)
        }
        return writer.data
    }

    public static func decodePayload(_ data: Data) throws -> InputPayload {
        var reader = ByteReader(data)
        let raw = try reader.u8()
        guard let subtype = InputSubtype(rawValue: raw) else {
            throw ProtocolError.invalidValue(field: "input subtype")
        }
        let payload: InputPayload
        switch subtype {
        case .head:
            let qualityRaw = try reader.u8()
            guard let quality = TrackingQuality(rawValue: qualityRaw) else {
                throw ProtocolError.invalidValue(field: "tracking quality")
            }
            let flags = try reader.u16()
            let sampleId = try reader.u32()
            let position = try reader.vec3()
            let orientation = try reader.quat()
            let linear = try reader.vec3()
            let angular = try reader.vec3()
            payload = .head(HeadInput(
                quality: quality, flags: flags, sampleId: sampleId,
                pose: Pose(position: position, orientation: orientation),
                linearVelocity: linear, angularVelocity: angular
            ))

        case .hand:
            let chiralityRaw = try reader.u8()
            guard let chirality = HandChirality(rawValue: chiralityRaw) else {
                throw ProtocolError.invalidValue(field: "chirality")
            }
            let qualityRaw = try reader.u8()
            guard let quality = TrackingQuality(rawValue: qualityRaw) else {
                throw ProtocolError.invalidValue(field: "tracking quality")
            }
            let flags = try reader.u16()
            let sampleId = try reader.u32()
            let jointCount = try reader.u8()
            _ = try reader.u8()
            guard jointCount == UInt8(HandJointName.count) else {
                throw ProtocolError.invalidValue(field: "joint count")
            }
            let palmPosition = try reader.vec3()
            let palmOrientation = try reader.quat()
            var joints = Array(repeating: HandJoint.unavailable, count: HandJointName.count)
            for _ in 0..<HandJointName.count {
                let jointId = try reader.u8()
                guard jointId < UInt8(HandJointName.count) else {
                    throw ProtocolError.invalidValue(field: "joint id")
                }
                joints[Int(jointId)] = HandJoint(
                    position: try reader.vec3(),
                    orientation: try reader.quat(),
                    radius: try reader.f32()
                )
            }
            payload = .hand(HandInput(snapshot: HandSnapshot(
                chirality: chirality,
                timestamp: .zero,
                quality: quality,
                sampleId: sampleId,
                joints: joints,
                palmPosition: palmPosition,
                palmOrientation: palmOrientation
            ), flags: flags))

        case .intent:
            let handRaw = try reader.u8()
            guard let hand = HandChirality(rawValue: handRaw) else {
                throw ProtocolError.invalidValue(field: "chirality")
            }
            let qualityRaw = try reader.u8()
            guard let quality = TrackingQuality(rawValue: qualityRaw) else {
                throw ProtocolError.invalidValue(field: "tracking quality")
            }
            let flags = try reader.u16()
            let sampleId = try reader.u32()
            let position = try reader.vec3()
            let orientation = try reader.quat()
            let linear = try reader.vec3()
            let angular = try reader.vec3()
            let trigger = try reader.f32()
            let grip = try reader.f32()
            let stickX = try reader.f32()
            let stickY = try reader.f32()
            let trackpadX = try reader.f32()
            let trackpadY = try reader.f32()
            let buttons = ControllerButtons(rawValue: try reader.u32())
            _ = try reader.u32()
            payload = .intent(IntentInput(
                hand: hand, quality: quality, flags: flags, sampleId: sampleId,
                pose: Pose(position: position, orientation: orientation),
                linearVelocity: linear, angularVelocity: angular,
                trigger: trigger, grip: grip, stickX: stickX, stickY: stickY,
                trackpadX: trackpadX, trackpadY: trackpadY, buttons: buttons
            ))
        }
        try reader.requireFinished()
        return payload
    }

    public func datagram(sessionId: UInt32, sequence: UInt64, timestampNs: UInt64) throws -> Data {
        let payload = try encodePayload()
        let header = MediaHeader(
            type: .input, flags: [.plaintext],
            fragmentIndex: 0, fragmentCount: 1,
            payloadLength: UInt16(payload.count), sessionId: sessionId,
            frameId: 0, packetSequence: sequence, timestampNs: timestampNs
        )
        return try header.datagram(payload: payload)
    }

    /// Parses an input datagram and attaches the header timestamp to hand snapshots.
    public static func parseDatagram(_ data: Data) throws -> (MediaHeader, InputPayload) {
        let (header, payload) = try MediaHeader.parseDatagram(data)
        guard header.type == .input else {
            throw ProtocolError.invalidValue(field: "input datagram type")
        }
        var decoded = try decodePayload(payload)
        if case .hand(var hand) = decoded {
            hand.snapshot.timestamp = Timestamp(nanoseconds: header.timestampNs)
            decoded = .hand(hand)
        }
        return (header, decoded)
    }
}

private func clamp(_ value: Float) -> Float {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

private func clampSigned(_ value: Float) -> Float {
    guard value.isFinite else { return 0 }
    return min(max(value, -1), 1)
}
