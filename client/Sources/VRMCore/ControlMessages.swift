import Foundation

// MARK: - Handshake

public struct HelloMessage: Equatable, Sendable {
    public var minMajor: UInt16
    public var maxMajor: UInt16
    public var minMinor: UInt16
    public var maxMinor: UInt16
    public var clientNonce: Data
    public var clientVersion: String
    public var clientPlatform: String
    public var requestedAuthMode: AuthMode
    public var capabilities: Capabilities

    public init(
        minMajor: UInt16 = 1,
        maxMajor: UInt16 = 1,
        minMinor: UInt16 = 0,
        maxMinor: UInt16 = 0,
        clientNonce: Data = Data(repeating: 0, count: 16),
        clientVersion: String = "0.1.0",
        clientPlatform: String = "visionOS",
        requestedAuthMode: AuthMode = .pairingCode,
        capabilities: Capabilities = [.handSkeleton, .headPose, .reprojection, .telemetry]
    ) {
        self.minMajor = minMajor
        self.maxMajor = maxMajor
        self.minMinor = minMinor
        self.maxMinor = maxMinor
        self.clientNonce = clientNonce
        self.clientVersion = clientVersion
        self.clientPlatform = clientPlatform
        self.requestedAuthMode = requestedAuthMode
        self.capabilities = capabilities
    }
}

public struct WelcomeMessage: Equatable, Sendable {
    public var major: UInt16
    public var minor: UInt16
    public var sessionId: UInt32
    public var serverNonce: Data
    public var authMode: AuthMode
    public var serverVersion: String
    public var hostName: String
    public var salt: Data
    public var capabilities: Capabilities

    public init(
        major: UInt16 = 1,
        minor: UInt16 = 0,
        sessionId: UInt32 = 0,
        serverNonce: Data = Data(repeating: 0, count: 16),
        authMode: AuthMode = .pairingCode,
        serverVersion: String = "0.1.0",
        hostName: String = "VRMC PC",
        salt: Data = Data(repeating: 0, count: 16),
        capabilities: Capabilities = [.handSkeleton, .headPose, .reprojection, .telemetry]
    ) {
        self.major = major
        self.minor = minor
        self.sessionId = sessionId
        self.serverNonce = serverNonce
        self.authMode = authMode
        self.serverVersion = serverVersion
        self.hostName = hostName
        self.salt = salt
        self.capabilities = capabilities
    }
}

public struct AuthChallengeMessage: Equatable, Sendable {
    public var transcriptHash: Data
    public var serverProof: Data

    public init(transcriptHash: Data, serverProof: Data) {
        self.transcriptHash = transcriptHash
        self.serverProof = serverProof
    }
}

public struct AuthResponseMessage: Equatable, Sendable {
    public var clientProof: Data
    public init(clientProof: Data) { self.clientProof = clientProof }
}

public struct AuthOKMessage: Equatable, Sendable {
    public var status: UInt8
    public var detail: String
    public init(status: UInt8 = 0, detail: String = "") {
        self.status = status
        self.detail = detail
    }
    public var isSuccess: Bool { status == 0 }
}

// MARK: - Stream configuration

public struct StreamConfig: Equatable, Sendable {
    public var configVersion: UInt16
    public var videoWidth: UInt16
    public var videoHeight: UInt16
    public var eyeWidth: UInt16
    public var eyeHeight: UInt16
    public var eyeOrder: EyeOrder
    public var colorSpace: ColorSpace
    public var codec: VideoCodec
    public var fps: UInt16
    public var displayHz: UInt16
    public var bitrateKbps: UInt32
    public var keyframeIntervalMs: UInt16
    public var maxPacketBytes: UInt16
    public var ipdMeters: Float
    public var leftProjection: ProjectionTangents
    public var rightProjection: ProjectionTangents
    public var leftEyeOffset: Vec3
    public var rightEyeOffset: Vec3
    public var flags: StreamFlags
    public var source: String
    public var mappingProfile: String

    public init(
        configVersion: UInt16 = 1,
        videoWidth: UInt16 = 3_840,
        videoHeight: UInt16 = 1_080,
        eyeWidth: UInt16 = 1_920,
        eyeHeight: UInt16 = 1_080,
        eyeOrder: EyeOrder = .leftRight,
        colorSpace: ColorSpace = .sRGB,
        codec: VideoCodec = .hevc,
        fps: UInt16 = 90,
        displayHz: UInt16 = 90,
        bitrateKbps: UInt32 = 90_000,
        keyframeIntervalMs: UInt16 = 1_000,
        maxPacketBytes: UInt16 = 1_200,
        ipdMeters: Float = 0.064,
        leftProjection: ProjectionTangents = .symmetric100,
        rightProjection: ProjectionTangents = .symmetric100,
        leftEyeOffset: Vec3 = Vec3(-0.032, 0, 0),
        rightEyeOffset: Vec3 = Vec3(0.032, 0, 0),
        flags: StreamFlags = [.reprojection, .dualMirrorVerified],
        source: String = "Vivecraft DUAL 3840x1080",
        mappingProfile: String = "handmap-v1"
    ) {
        self.configVersion = configVersion
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.eyeWidth = eyeWidth
        self.eyeHeight = eyeHeight
        self.eyeOrder = eyeOrder
        self.colorSpace = colorSpace
        self.codec = codec
        self.fps = fps
        self.displayHz = displayHz
        self.bitrateKbps = bitrateKbps
        self.keyframeIntervalMs = keyframeIntervalMs
        self.maxPacketBytes = maxPacketBytes
        self.ipdMeters = ipdMeters
        self.leftProjection = leftProjection
        self.rightProjection = rightProjection
        self.leftEyeOffset = leftEyeOffset
        self.rightEyeOffset = rightEyeOffset
        self.flags = flags
        self.source = source
        self.mappingProfile = mappingProfile
    }

    public func validate() throws {
        guard configVersion == 1 else { throw ProtocolError.invalidValue(field: "configVersion") }
        guard videoWidth > 0, videoHeight > 0, eyeWidth > 0, eyeHeight > 0 else {
            throw ProtocolError.invalidValue(field: "video dimensions")
        }
        guard eyeWidth * 2 == videoWidth, eyeHeight == videoHeight else {
            throw ProtocolError.invalidValue(field: "eye geometry")
        }
        guard fps > 0, fps <= 240, displayHz > 0, displayHz <= 240 else {
            throw ProtocolError.invalidValue(field: "fps")
        }
        guard maxPacketBytes >= 256, maxPacketBytes <= ProtocolConstants.maxDatagramBytes else {
            throw ProtocolError.invalidValue(field: "maxPacketBytes")
        }
        guard leftProjection.isValid, rightProjection.isValid else {
            throw ProtocolError.invalidValue(field: "projection")
        }
        guard ipdMeters > 0.02, ipdMeters < 0.12 else {
            throw ProtocolError.invalidValue(field: "ipdMeters")
        }
        guard source.utf8.count <= 255, mappingProfile.utf8.count <= 255 else {
            throw ProtocolError.invalidValue(field: "string length")
        }
    }
}

public struct StartStreamMessage: Equatable, Sendable {
    public var startHostTimeNs: UInt64
    public var firstFrameId: UInt32
    public var flags: UInt32
    public init(startHostTimeNs: UInt64, firstFrameId: UInt32 = 1, flags: UInt32 = 0) {
        self.startHostTimeNs = startHostTimeNs
        self.firstFrameId = firstFrameId
        self.flags = flags
    }
}

public struct StopStreamMessage: Equatable, Sendable {
    public var reason: UInt8
    public var detail: String
    public init(reason: UInt8 = 0, detail: String = "") {
        self.reason = reason
        self.detail = detail
    }
}

public struct KeyframeRequestMessage: Equatable, Sendable {
    public var lastFrameId: UInt32
    public var reason: UInt8
    public var clientTimeNs: UInt64
    public init(lastFrameId: UInt32, reason: UInt8 = 0, clientTimeNs: UInt64 = 0) {
        self.lastFrameId = lastFrameId
        self.reason = reason
        self.clientTimeNs = clientTimeNs
    }
}

public struct SessionStateMessage: Equatable, Sendable {
    public var phase: SessionPhase
    public var reason: UInt16
    public var detail: String
    public var flags: SessionFlags
    public init(phase: SessionPhase, reason: UInt16 = 0, detail: String = "", flags: SessionFlags = []) {
        self.phase = phase
        self.reason = reason
        self.detail = detail
        self.flags = flags
    }
}

public struct ClockPingMessage: Equatable, Sendable {
    public var t0: UInt64
    public var pingId: UInt32
    public init(t0: UInt64, pingId: UInt32) {
        self.t0 = t0
        self.pingId = pingId
    }
}

public struct ClockPongMessage: Equatable, Sendable {
    public var t0: UInt64
    public var t1: UInt64
    public var t2: UInt64
    public var pingId: UInt32
    public init(t0: UInt64, t1: UInt64, t2: UInt64, pingId: UInt32) {
        self.t0 = t0
        self.t1 = t1
        self.t2 = t2
        self.pingId = pingId
    }
}

public struct ClientTelemetryMessage: Equatable, Sendable {
    public var framesReceived: UInt32
    public var framesDecoded: UInt32
    public var framesPresented: UInt32
    public var framesDropped: UInt32
    public var decodeAvgUs: UInt32
    public var decodeP95Us: UInt32
    public var renderAvgUs: UInt32
    public var renderP95Us: UInt32
    public var inputSent: UInt32
    public var inputLost: UInt32
    public var lastFrameId: UInt32
    public var latencyP50Us: UInt32
    public var latencyP95Us: UInt32
    public var queueDepth: UInt16
    public var flags: UInt16

    public init(
        framesReceived: UInt32 = 0,
        framesDecoded: UInt32 = 0,
        framesPresented: UInt32 = 0,
        framesDropped: UInt32 = 0,
        decodeAvgUs: UInt32 = 0,
        decodeP95Us: UInt32 = 0,
        renderAvgUs: UInt32 = 0,
        renderP95Us: UInt32 = 0,
        inputSent: UInt32 = 0,
        inputLost: UInt32 = 0,
        lastFrameId: UInt32 = 0,
        latencyP50Us: UInt32 = 0,
        latencyP95Us: UInt32 = 0,
        queueDepth: UInt16 = 0,
        flags: UInt16 = 0
    ) {
        self.framesReceived = framesReceived
        self.framesDecoded = framesDecoded
        self.framesPresented = framesPresented
        self.framesDropped = framesDropped
        self.decodeAvgUs = decodeAvgUs
        self.decodeP95Us = decodeP95Us
        self.renderAvgUs = renderAvgUs
        self.renderP95Us = renderP95Us
        self.inputSent = inputSent
        self.inputLost = inputLost
        self.lastFrameId = lastFrameId
        self.latencyP50Us = latencyP50Us
        self.latencyP95Us = latencyP95Us
        self.queueDepth = queueDepth
        self.flags = flags
    }
}

public struct HostTelemetryMessage: Equatable, Sendable {
    public var captured: UInt32
    public var encoded: UInt32
    public var packetsSent: UInt64
    public var packetsLost: UInt32
    public var nacks: UInt32
    public var idrRequests: UInt32
    public var captureAvgUs: UInt32
    public var encodeAvgUs: UInt32
    public var encodeP95Us: UInt32
    public var queueDepth: UInt16
    public var bitrateKbps: UInt32
    public var fpsX100: UInt32

    public init(
        captured: UInt32 = 0,
        encoded: UInt32 = 0,
        packetsSent: UInt64 = 0,
        packetsLost: UInt32 = 0,
        nacks: UInt32 = 0,
        idrRequests: UInt32 = 0,
        captureAvgUs: UInt32 = 0,
        encodeAvgUs: UInt32 = 0,
        encodeP95Us: UInt32 = 0,
        queueDepth: UInt16 = 0,
        bitrateKbps: UInt32 = 0,
        fpsX100: UInt32 = 0
    ) {
        self.captured = captured
        self.encoded = encoded
        self.packetsSent = packetsSent
        self.packetsLost = packetsLost
        self.nacks = nacks
        self.idrRequests = idrRequests
        self.captureAvgUs = captureAvgUs
        self.encodeAvgUs = encodeAvgUs
        self.encodeP95Us = encodeP95Us
        self.queueDepth = queueDepth
        self.bitrateKbps = bitrateKbps
        self.fpsX100 = fpsX100
    }
}

public struct SetQualityMessage: Equatable, Sendable {
    public var maxBitrateKbps: UInt32
    public var targetFps: UInt16
    public var scalePercent: UInt16
    public var flags: UInt32
    public init(maxBitrateKbps: UInt32, targetFps: UInt16 = 90, scalePercent: UInt16 = 100, flags: UInt32 = 0) {
        self.maxBitrateKbps = maxBitrateKbps
        self.targetFps = targetFps
        self.scalePercent = scalePercent
        self.flags = flags
    }
}

public struct InputConfigMessage: Equatable, Sendable {
    public var mappingProfile: String
    public var predictionMs: UInt16
    public var flags: UInt32
    public init(mappingProfile: String = "handmap-v1", predictionMs: UInt16 = 50, flags: UInt32 = 0) {
        self.mappingProfile = mappingProfile
        self.predictionMs = predictionMs
        self.flags = flags
    }
}

public enum HapticHand: UInt8, Sendable, Equatable {
    case left = 0
    case right = 1
    case both = 2
}

public struct HapticMessage: Equatable, Sendable {
    public var hand: HapticHand
    public var amplitude: Float
    public var durationMs: UInt16
    public var frequencyHz: UInt16
    public init(hand: HapticHand, amplitude: Float, durationMs: UInt16 = 80, frequencyHz: UInt16 = 160) {
        self.hand = hand
        self.amplitude = amplitude
        self.durationMs = durationMs
        self.frequencyHz = frequencyHz
    }
}

public struct HeartbeatMessage: Equatable, Sendable {
    public var hostTimeNs: UInt64
    public var phase: SessionPhase
    public var flags: UInt16
    public init(hostTimeNs: UInt64 = 0, phase: SessionPhase = .ready, flags: UInt16 = 0) {
        self.hostTimeNs = hostTimeNs
        self.phase = phase
        self.flags = flags
    }
}

public struct DisconnectMessage: Equatable, Sendable {
    public var reason: UInt8
    public var detail: String
    public init(reason: UInt8 = 0, detail: String = "") {
        self.reason = reason
        self.detail = detail
    }
}

public struct AudioConfigMessage: Equatable, Sendable {
    public init() {}
}

// MARK: - Control message

public enum ControlMessage: Equatable, Sendable {
    case hello(HelloMessage)
    case welcome(WelcomeMessage)
    case authChallenge(AuthChallengeMessage)
    case authResponse(AuthResponseMessage)
    case authOK(AuthOKMessage)
    case streamConfig(StreamConfig)
    case startStream(StartStreamMessage)
    case stopStream(StopStreamMessage)
    case keyframeRequest(KeyframeRequestMessage)
    case sessionState(SessionStateMessage)
    case clockPing(ClockPingMessage)
    case clockPong(ClockPongMessage)
    case telemetryClient(ClientTelemetryMessage)
    case telemetryHost(HostTelemetryMessage)
    case setQuality(SetQualityMessage)
    case inputConfig(InputConfigMessage)
    case haptic(HapticMessage)
    case heartbeat(HeartbeatMessage)
    case disconnect(DisconnectMessage)
    case error(ErrorPayload)
    case audioConfig(AudioConfigMessage)

    public var type: MessageType {
        switch self {
        case .hello: return .hello
        case .welcome: return .welcome
        case .authChallenge: return .authChallenge
        case .authResponse: return .authResponse
        case .authOK: return .authOK
        case .streamConfig: return .streamConfig
        case .startStream: return .startStream
        case .stopStream: return .stopStream
        case .keyframeRequest: return .keyframeRequest
        case .sessionState: return .sessionState
        case .clockPing: return .clockPing
        case .clockPong: return .clockPong
        case .telemetryClient: return .telemetryClient
        case .telemetryHost: return .telemetryHost
        case .setQuality: return .setQuality
        case .inputConfig: return .inputConfig
        case .haptic: return .haptic
        case .heartbeat: return .heartbeat
        case .disconnect: return .disconnect
        case .error: return .error
        case .audioConfig: return .audioConfig
        }
    }

    public func encodePayload() throws -> Data {
        var writer = ByteWriter(capacity: 128)
        switch self {
        case .hello(let message):
            writer.u16(message.minMajor)
            writer.u16(message.maxMajor)
            writer.u16(message.minMinor)
            writer.u16(message.maxMinor)
            try writeFixedBytes(message.clientNonce, count: 16, field: "clientNonce", writer: &writer)
            try writer.string(message.clientVersion)
            try writer.string(message.clientPlatform)
            writer.u8(message.requestedAuthMode.rawValue)
            writer.u32(message.capabilities.rawValue)

        case .welcome(let message):
            writer.u16(message.major)
            writer.u16(message.minor)
            writer.u32(message.sessionId)
            try writeFixedBytes(message.serverNonce, count: 16, field: "serverNonce", writer: &writer)
            writer.u8(message.authMode.rawValue)
            try writer.string(message.serverVersion)
            try writer.string(message.hostName)
            try writeFixedBytes(message.salt, count: 16, field: "salt", writer: &writer)
            writer.u32(message.capabilities.rawValue)

        case .authChallenge(let message):
            try writeFixedBytes(message.transcriptHash, count: 32, field: "transcriptHash", writer: &writer)
            try writeFixedBytes(message.serverProof, count: 32, field: "serverProof", writer: &writer)

        case .authResponse(let message):
            try writeFixedBytes(message.clientProof, count: 32, field: "clientProof", writer: &writer)

        case .authOK(let message):
            writer.u8(message.status)
            try writer.string(message.detail)

        case .streamConfig(let config):
            try config.validate()
            writer.u16(config.configVersion)
            writer.u16(config.videoWidth)
            writer.u16(config.videoHeight)
            writer.u16(config.eyeWidth)
            writer.u16(config.eyeHeight)
            writer.u8(config.eyeOrder.rawValue)
            writer.u8(config.colorSpace.rawValue)
            writer.u8(config.codec.rawValue)
            writer.u8(0)
            writer.u16(config.fps)
            writer.u16(config.displayHz)
            writer.u32(config.bitrateKbps)
            writer.u16(config.keyframeIntervalMs)
            writer.u16(config.maxPacketBytes)
            try writer.f32(config.ipdMeters)
            try writeProjection(config.leftProjection, writer: &writer)
            try writeProjection(config.rightProjection, writer: &writer)
            try writer.vec3(config.leftEyeOffset)
            try writer.vec3(config.rightEyeOffset)
            writer.u32(config.flags.rawValue)
            try writer.string(config.source)
            try writer.string(config.mappingProfile)

        case .startStream(let message):
            writer.u64(message.startHostTimeNs)
            writer.u32(message.firstFrameId)
            writer.u32(message.flags)

        case .stopStream(let message):
            writer.u8(message.reason)
            try writer.string(message.detail)

        case .keyframeRequest(let message):
            writer.u32(message.lastFrameId)
            writer.u8(message.reason)
            writer.reserve(u8: 3)
            writer.u64(message.clientTimeNs)

        case .sessionState(let message):
            writer.u8(message.phase.rawValue)
            writer.u16(message.reason)
            writer.u32(message.flags.rawValue)
            try writer.string(message.detail)

        case .clockPing(let message):
            writer.u64(message.t0)
            writer.u32(message.pingId)

        case .clockPong(let message):
            writer.u64(message.t0)
            writer.u64(message.t1)
            writer.u64(message.t2)
            writer.u32(message.pingId)

        case .telemetryClient(let message):
            writer.u32(message.framesReceived)
            writer.u32(message.framesDecoded)
            writer.u32(message.framesPresented)
            writer.u32(message.framesDropped)
            writer.u32(message.decodeAvgUs)
            writer.u32(message.decodeP95Us)
            writer.u32(message.renderAvgUs)
            writer.u32(message.renderP95Us)
            writer.u32(message.inputSent)
            writer.u32(message.inputLost)
            writer.u32(message.lastFrameId)
            writer.u32(message.latencyP50Us)
            writer.u32(message.latencyP95Us)
            writer.u16(message.queueDepth)
            writer.u16(message.flags)

        case .telemetryHost(let message):
            writer.u32(message.captured)
            writer.u32(message.encoded)
            writer.u64(message.packetsSent)
            writer.u32(message.packetsLost)
            writer.u32(message.nacks)
            writer.u32(message.idrRequests)
            writer.u32(message.captureAvgUs)
            writer.u32(message.encodeAvgUs)
            writer.u32(message.encodeP95Us)
            writer.u16(message.queueDepth)
            writer.u16(0)
            writer.u32(message.bitrateKbps)
            writer.u32(message.fpsX100)

        case .setQuality(let message):
            writer.u32(message.maxBitrateKbps)
            writer.u16(message.targetFps)
            writer.u16(message.scalePercent)
            writer.u32(message.flags)

        case .inputConfig(let message):
            try writer.string(message.mappingProfile)
            writer.u16(message.predictionMs)
            writer.u32(message.flags)

        case .haptic(let message):
            writer.u8(message.hand.rawValue)
            try writer.f32(message.amplitude)
            writer.u16(message.durationMs)
            writer.u16(message.frequencyHz)

        case .heartbeat(let message):
            writer.u64(message.hostTimeNs)
            writer.u8(message.phase.rawValue)
            writer.u16(message.flags)
            writer.u8(0)

        case .disconnect(let message):
            writer.u8(message.reason)
            try writer.string(message.detail)

        case .error(let payload):
            writer.u16(payload.code.rawValue)
            try writer.string(payload.detail)

        case .audioConfig:
            break
        }
        return writer.data
    }

    public static func decodePayload(type: MessageType, data: Data) throws -> ControlMessage {
        var reader = ByteReader(data)
        let message: ControlMessage
        switch type {
        case .hello:
            let minMajor = try reader.u16()
            let maxMajor = try reader.u16()
            let minMinor = try reader.u16()
            let maxMinor = try reader.u16()
            let nonce = try reader.data(count: 16)
            let version = try reader.string()
            let platform = try reader.string()
            let authRaw = try reader.u8()
            guard let auth = AuthMode(rawValue: authRaw) else {
                throw ProtocolError.invalidValue(field: "authMode")
            }
            let capabilities = Capabilities(rawValue: try reader.u32())
            message = .hello(HelloMessage(
                minMajor: minMajor, maxMajor: maxMajor, minMinor: minMinor, maxMinor: maxMinor,
                clientNonce: nonce, clientVersion: version, clientPlatform: platform,
                requestedAuthMode: auth, capabilities: capabilities
            ))

        case .welcome:
            let major = try reader.u16()
            let minor = try reader.u16()
            let sessionId = try reader.u32()
            let nonce = try reader.data(count: 16)
            let authRaw = try reader.u8()
            guard let auth = AuthMode(rawValue: authRaw) else {
                throw ProtocolError.invalidValue(field: "authMode")
            }
            let version = try reader.string()
            let hostName = try reader.string()
            let salt = try reader.data(count: 16)
            let capabilities = Capabilities(rawValue: try reader.u32())
            message = .welcome(WelcomeMessage(
                major: major, minor: minor, sessionId: sessionId, serverNonce: nonce,
                authMode: auth, serverVersion: version, hostName: hostName, salt: salt,
                capabilities: capabilities
            ))

        case .authChallenge:
            message = .authChallenge(AuthChallengeMessage(
                transcriptHash: try reader.data(count: 32),
                serverProof: try reader.data(count: 32)
            ))

        case .authResponse:
            message = .authResponse(AuthResponseMessage(clientProof: try reader.data(count: 32)))

        case .authOK:
            message = .authOK(AuthOKMessage(status: try reader.u8(), detail: try reader.string()))

        case .streamConfig:
            let configVersion = try reader.u16()
            let videoWidth = try reader.u16()
            let videoHeight = try reader.u16()
            let eyeWidth = try reader.u16()
            let eyeHeight = try reader.u16()
            let eyeRaw = try reader.u8()
            let colorRaw = try reader.u8()
            let codecRaw = try reader.u8()
            _ = try reader.u8()
            guard let eyeOrder = EyeOrder(rawValue: eyeRaw) else {
                throw ProtocolError.invalidValue(field: "eyeOrder")
            }
            guard let colorSpace = ColorSpace(rawValue: colorRaw) else {
                throw ProtocolError.invalidValue(field: "colorSpace")
            }
            guard let codec = VideoCodec(rawValue: codecRaw) else {
                throw ProtocolError.invalidValue(field: "codec")
            }
            let fps = try reader.u16()
            let displayHz = try reader.u16()
            let bitrate = try reader.u32()
            let keyframe = try reader.u16()
            let maxPacket = try reader.u16()
            let ipd = try reader.f32()
            let leftProjection = try readProjection(reader: &reader)
            let rightProjection = try readProjection(reader: &reader)
            let leftOffset = try reader.vec3()
            let rightOffset = try reader.vec3()
            let flags = StreamFlags(rawValue: try reader.u32())
            let source = try reader.string()
            let mapping = try reader.string()
            let config = StreamConfig(
                configVersion: configVersion, videoWidth: videoWidth, videoHeight: videoHeight,
                eyeWidth: eyeWidth, eyeHeight: eyeHeight, eyeOrder: eyeOrder,
                colorSpace: colorSpace, codec: codec, fps: fps, displayHz: displayHz,
                bitrateKbps: bitrate, keyframeIntervalMs: keyframe, maxPacketBytes: maxPacket,
                ipdMeters: ipd, leftProjection: leftProjection, rightProjection: rightProjection,
                leftEyeOffset: leftOffset, rightEyeOffset: rightOffset, flags: flags,
                source: source, mappingProfile: mapping
            )
            try config.validate()
            message = .streamConfig(config)

        case .startStream:
            message = .startStream(StartStreamMessage(
                startHostTimeNs: try reader.u64(),
                firstFrameId: try reader.u32(),
                flags: try reader.u32()
            ))

        case .stopStream:
            message = .stopStream(StopStreamMessage(reason: try reader.u8(), detail: try reader.string()))

        case .keyframeRequest:
            let last = try reader.u32()
            let reason = try reader.u8()
            try reader.skip(3)
            let time = try reader.u64()
            message = .keyframeRequest(KeyframeRequestMessage(lastFrameId: last, reason: reason, clientTimeNs: time))

        case .sessionState:
            let phaseRaw = try reader.u8()
            guard let phase = SessionPhase(rawValue: phaseRaw) else {
                throw ProtocolError.invalidValue(field: "session phase")
            }
            let reason = try reader.u16()
            let flags = SessionFlags(rawValue: try reader.u32())
            let detail = try reader.string()
            message = .sessionState(SessionStateMessage(phase: phase, reason: reason, detail: detail, flags: flags))

        case .clockPing:
            message = .clockPing(ClockPingMessage(t0: try reader.u64(), pingId: try reader.u32()))

        case .clockPong:
            message = .clockPong(ClockPongMessage(
                t0: try reader.u64(), t1: try reader.u64(), t2: try reader.u64(), pingId: try reader.u32()
            ))

        case .telemetryClient:
            message = .telemetryClient(ClientTelemetryMessage(
                framesReceived: try reader.u32(), framesDecoded: try reader.u32(),
                framesPresented: try reader.u32(), framesDropped: try reader.u32(),
                decodeAvgUs: try reader.u32(), decodeP95Us: try reader.u32(),
                renderAvgUs: try reader.u32(), renderP95Us: try reader.u32(),
                inputSent: try reader.u32(), inputLost: try reader.u32(),
                lastFrameId: try reader.u32(), latencyP50Us: try reader.u32(),
                latencyP95Us: try reader.u32(), queueDepth: try reader.u16(),
                flags: try reader.u16()
            ))

        case .telemetryHost:
            let captured = try reader.u32()
            let encoded = try reader.u32()
            let packetsSent = try reader.u64()
            let packetsLost = try reader.u32()
            let nacks = try reader.u32()
            let idrRequests = try reader.u32()
            let captureAvgUs = try reader.u32()
            let encodeAvgUs = try reader.u32()
            let encodeP95Us = try reader.u32()
            let queueDepth = try reader.u16()
            _ = try reader.u16()
            let bitrateKbps = try reader.u32()
            let fpsX100 = try reader.u32()
            message = .telemetryHost(HostTelemetryMessage(
                captured: captured, encoded: encoded,
                packetsSent: packetsSent, packetsLost: packetsLost,
                nacks: nacks, idrRequests: idrRequests,
                captureAvgUs: captureAvgUs, encodeAvgUs: encodeAvgUs,
                encodeP95Us: encodeP95Us, queueDepth: queueDepth,
                bitrateKbps: bitrateKbps, fpsX100: fpsX100
            ))

        case .setQuality:
            message = .setQuality(SetQualityMessage(
                maxBitrateKbps: try reader.u32(), targetFps: try reader.u16(),
                scalePercent: try reader.u16(), flags: try reader.u32()
            ))

        case .inputConfig:
            message = .inputConfig(InputConfigMessage(
                mappingProfile: try reader.string(), predictionMs: try reader.u16(),
                flags: try reader.u32()
            ))

        case .haptic:
            let handRaw = try reader.u8()
            guard let hand = HapticHand(rawValue: handRaw) else {
                throw ProtocolError.invalidValue(field: "haptic hand")
            }
            message = .haptic(HapticMessage(
                hand: hand, amplitude: try reader.f32(), durationMs: try reader.u16(),
                frequencyHz: try reader.u16()
            ))

        case .heartbeat:
            let hostTime = try reader.u64()
            let phaseRaw = try reader.u8()
            guard let phase = SessionPhase(rawValue: phaseRaw) else {
                throw ProtocolError.invalidValue(field: "heartbeat phase")
            }
            let flags = try reader.u16()
            _ = try reader.u8()
            message = .heartbeat(HeartbeatMessage(hostTimeNs: hostTime, phase: phase, flags: flags))

        case .disconnect:
            message = .disconnect(DisconnectMessage(reason: try reader.u8(), detail: try reader.string()))

        case .error:
            let codeRaw = try reader.u16()
            guard let code = ErrorCode(rawValue: codeRaw) else {
                throw ProtocolError.invalidValue(field: "error code")
            }
            message = .error(ErrorPayload(code: code, detail: try reader.string()))

        case .audioConfig:
            message = .audioConfig(AudioConfigMessage())
        }
        try reader.requireFinished()
        return message
    }

    public func encoded(sessionId: UInt32, sequence: UInt32, flags: ControlFlags = .plaintext) throws -> Data {
        let payload = try encodePayload()
        guard payload.count <= ProtocolConstants.maxControlPayload else {
            throw ProtocolError.payloadTooLarge(payload.count)
        }
        let header = ControlHeader(
            type: type,
            flags: flags,
            sessionId: sessionId,
            sequence: sequence,
            payloadLength: UInt32(payload.count)
        )
        var output = header.encoded()
        output.append(payload)
        return output
    }

    public static func decode(_ data: Data) throws -> (ControlHeader, ControlMessage) {
        let header = try ControlHeader.decode(from: data)
        let payloadStart = ProtocolConstants.controlHeaderSize
        let payloadEnd = payloadStart + Int(header.payloadLength)
        guard data.count >= payloadEnd else {
            throw ProtocolError.truncated(field: "control payload")
        }
        guard data.count == payloadEnd else {
            throw ProtocolError.trailingBytes(data.count - payloadEnd)
        }
        let payload = data.subdata(in: payloadStart..<payloadEnd)
        let message = try decodePayload(type: header.type, data: payload)
        return (header, message)
    }
}

// MARK: - Helpers

private func writeFixedBytes(_ data: Data, count: Int, field: String, writer: inout ByteWriter) throws {
    guard data.count == count else { throw ProtocolError.invalidValue(field: field) }
    writer.bytes(data)
}

private func writeProjection(_ projection: ProjectionTangents, writer: inout ByteWriter) throws {
    guard projection.isValid else { throw ProtocolError.invalidValue(field: "projection") }
    try writer.f32(projection.left)
    try writer.f32(projection.right)
    try writer.f32(projection.top)
    try writer.f32(projection.bottom)
}

private func readProjection(reader: inout ByteReader) throws -> ProjectionTangents {
    let projection = ProjectionTangents(
        left: try reader.f32(), right: try reader.f32(),
        top: try reader.f32(), bottom: try reader.f32()
    )
    guard projection.isValid else { throw ProtocolError.invalidValue(field: "projection") }
    return projection
}
