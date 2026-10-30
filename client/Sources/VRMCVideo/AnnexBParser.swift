import Foundation
import VRMCore

public struct NALUnit: Equatable, Sendable {
    public var data: Data
    public var type: UInt8
    public var isParameterSet: Bool

    public init(data: Data, type: UInt8, isParameterSet: Bool) {
        self.data = data
        self.type = type
        self.isParameterSet = isParameterSet
    }
}

public enum AnnexBParser {
    /// Splits an Annex-B byte stream into NAL units without start codes.
    public static func split(_ data: Data, codec: VideoCodec) -> [NALUnit] {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return [] }
        var starts: [Int] = []
        var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                starts.append(index)
                index += 3
            } else if index + 3 < bytes.count,
                      bytes[index] == 0, bytes[index + 1] == 0,
                      bytes[index + 2] == 0, bytes[index + 3] == 1 {
                starts.append(index)
                index += 4
            } else {
                index += 1
            }
        }
        guard !starts.isEmpty else { return [] }
        var units: [NALUnit] = []
        for (position, start) in starts.enumerated() {
            let headerLength = start + 2 < bytes.count && bytes[start + 2] == 1 ? 3 : 4
            let payloadStart = start + headerLength
            let payloadEnd = position + 1 < starts.count ? starts[position + 1] : bytes.count
            guard payloadStart < payloadEnd else { continue }
            let payload = Data(bytes[payloadStart..<payloadEnd])
            guard let first = payload.first else { continue }
            let type: UInt8
            let isParameterSet: Bool
            switch codec {
            case .h264:
                type = first & 0x1F
                isParameterSet = type == 7 || type == 8
            case .hevc:
                type = (first >> 1) & 0x3F
                isParameterSet = type == 32 || type == 33 || type == 34
            }
            units.append(NALUnit(data: payload, type: type, isParameterSet: isParameterSet))
        }
        return units
    }

    /// Converts NAL units to the AVCC length-prefixed format expected by VideoToolbox.
    public static func avcc(_ units: [NALUnit]) -> Data {
        var output = Data()
        for unit in units {
            let length = UInt32(unit.data.count)
            output.append(UInt8(truncatingIfNeeded: length >> 24))
            output.append(UInt8(truncatingIfNeeded: length >> 16))
            output.append(UInt8(truncatingIfNeeded: length >> 8))
            output.append(UInt8(truncatingIfNeeded: length))
            output.append(unit.data)
        }
        return output
    }

    public static func nalType(_ data: Data, codec: VideoCodec) -> UInt8? {
        guard let first = data.first else { return nil }
        return codec == .h264 ? (first & 0x1F) : ((first >> 1) & 0x3F)
    }
}
