import Foundation
import VRMCore
import CoreMedia
import CoreVideo
import VideoToolbox

public enum VideoDecoderError: Error, Equatable, CustomStringConvertible {
    case missingParameterSets
    case formatDescription(OSStatus)
    case blockBuffer(OSStatus)
    case sampleBuffer(OSStatus)
    case sessionCreation(OSStatus)
    case decode(OSStatus)
    case noImageBuffer

    public var description: String {
        switch self {
        case .missingParameterSets: return "missing parameter sets"
        case .formatDescription(let status): return "format description failed (\(status))"
        case .blockBuffer(let status): return "block buffer failed (\(status))"
        case .sampleBuffer(let status): return "sample buffer failed (\(status))"
        case .sessionCreation(let status): return "decompression session failed (\(status))"
        case .decode(let status): return "decode failed (\(status))"
        case .noImageBuffer: return "decoder produced no image buffer"
        }
    }
}

public struct DecodedVideoFrame: @unchecked Sendable {
    public var pixelBuffer: CVPixelBuffer
    public var presentationTime: CMTime
    public var timestamp: Timestamp
    public var frameId: UInt32

    public init(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, timestamp: Timestamp, frameId: UInt32) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
        self.timestamp = timestamp
        self.frameId = frameId
    }
}

/// Low-latency VideoToolbox decoder for Annex-B H.264/HEVC access units.
/// The decoder keeps parameter sets across frames and recreates its session only when
/// the format description changes. It is safe to call `decode` from one producer queue;
/// the output callback may run on another queue.
public final class VideoDecoder: @unchecked Sendable {
    public typealias Output = @Sendable (DecodedVideoFrame) -> Void

    private let codec: VideoCodec
    private let output: Output
    private let lock = NSLock()
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var vps: Data?
    private var sps: Data?
    private var pps: Data?
    private var lastParameterSetHash: Int = 0

    public init(codec: VideoCodec, output: @escaping Output) {
        self.codec = codec
        self.output = output
    }

    deinit {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        formatDescription = nil
        vps = nil
        sps = nil
        pps = nil
        lastParameterSetHash = 0
    }

    public func decode(accessUnit: Data, timestamp: Timestamp, frameId: UInt32) throws {
        let units = AnnexBParser.split(accessUnit, codec: codec)
        guard !units.isEmpty else { throw VideoDecoderError.missingParameterSets }

        lock.lock()
        defer { lock.unlock() }

        var formatChanged = false
        for unit in units where unit.isParameterSet {
            switch codec {
            case .h264:
                if unit.type == 7 { sps = unit.data; formatChanged = true }
                if unit.type == 8 { pps = unit.data; formatChanged = true }
            case .hevc:
                if unit.type == 32 { vps = unit.data; formatChanged = true }
                if unit.type == 33 { sps = unit.data; formatChanged = true }
                if unit.type == 34 { pps = unit.data; formatChanged = true }
            }
        }

        let hash = [vps, sps, pps].compactMap { $0 }.reduce(0) { $0 ^ $1.hashValue }
        if formatDescription == nil || (formatChanged && hash != lastParameterSetHash) {
            try rebuildFormatDescription()
            lastParameterSetHash = hash
        }
        guard let formatDescription else { throw VideoDecoderError.missingParameterSets }
        if session == nil {
            try createSession(formatDescription: formatDescription)
        }
        guard let session else { throw VideoDecoderError.sessionCreation(kVTInvalidSessionErr) }

        let avcc = AnnexBParser.avcc(units)
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            throw VideoDecoderError.blockBuffer(status)
        }
        status = avcc.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }
        guard status == kCMBlockBufferNoErr else { throw VideoDecoderError.blockBuffer(status) }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: Int64(timestamp.nanoseconds), timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avcc.count
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw VideoDecoderError.sampleBuffer(status)
        }

        let frameTimestamp = timestamp
        let frameOutput = output
        var infoFlags = VTDecodeInfoFlags()
        status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [],
            infoFlagsOut: &infoFlags
        ) { status, _, imageBuffer, _, presentationTime, _ in
            guard status == noErr, let imageBuffer else { return }
            let pixelBuffer = imageBuffer as CVPixelBuffer
            frameOutput(DecodedVideoFrame(
                pixelBuffer: pixelBuffer,
                presentationTime: presentationTime,
                timestamp: frameTimestamp,
                frameId: frameId
            ))
        }
        guard status == noErr else { throw VideoDecoderError.decode(status) }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }

    public var dimensions: (width: Int, height: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard let formatDescription else { return nil }
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        return (Int(dimensions.width), Int(dimensions.height))
    }

    private func rebuildFormatDescription() throws {
        guard let sps, let pps else { throw VideoDecoderError.missingParameterSets }
        var description: CMVideoFormatDescription?
        var status: OSStatus = noErr
        switch codec {
        case .h264:
            status = withParameterSetPointers([sps, pps]) { pointers, sizes in
                pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        guard let pointerBase = pointerBuffer.baseAddress,
                              let sizeBase = sizeBuffer.baseAddress else {
                            return kCMFormatDescriptionError_InvalidParameter
                        }
                        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: pointers.count,
                            parameterSetPointers: pointerBase,
                            parameterSetSizes: sizeBase,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &description
                        )
                    }
                }
            }
        case .hevc:
            guard let vps else { throw VideoDecoderError.missingParameterSets }
            status = withParameterSetPointers([vps, sps, pps]) { pointers, sizes in
                pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        guard let pointerBase = pointerBuffer.baseAddress,
                              let sizeBase = sizeBuffer.baseAddress else {
                            return kCMFormatDescriptionError_InvalidParameter
                        }
                        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: pointers.count,
                            parameterSetPointers: pointerBase,
                            parameterSetSizes: sizeBase,
                            nalUnitHeaderLength: 4,
                            extensions: nil,
                            formatDescriptionOut: &description
                        )
                    }
                }
            }
        }
        guard status == noErr, let description else {
            throw VideoDecoderError.formatDescription(status)
        }
        formatDescription = description
        if let session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
    }

    /// Keeps every parameter-set buffer alive while the format-description call uses
    /// pointers into them.
    private func withParameterSetPointers(
        _ sets: [Data],
        _ body: ([UnsafePointer<UInt8>], [Int]) -> OSStatus
    ) -> OSStatus {
        func recurse(
            _ index: Int,
            _ pointers: inout [UnsafePointer<UInt8>],
            _ sizes: inout [Int]
        ) -> OSStatus {
            guard index < sets.count else { return body(pointers, sizes) }
            return sets[index].withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                    return kCMFormatDescriptionError_InvalidParameter
                }
                pointers.append(base)
                sizes.append(sets[index].count)
                defer {
                    pointers.removeLast()
                    sizes.removeLast()
                }
                return recurse(index + 1, &pointers, &sizes)
            }
        }
        var pointers: [UnsafePointer<UInt8>] = []
        var sizes: [Int] = []
        return recurse(0, &pointers, &sizes)
    }

    private func createSession(formatDescription: CMVideoFormatDescription) throws {
        let decoderSpecification: [String: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true,
            kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder as String: false,
        ]
        let imageAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpecification as CFDictionary,
            imageBufferAttributes: imageAttributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &newSession
        )
        guard status == noErr, let newSession else {
            throw VideoDecoderError.sessionCreation(status)
        }
        session = newSession
    }
}
