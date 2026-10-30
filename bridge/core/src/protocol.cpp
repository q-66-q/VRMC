#include "vrmc/protocol.hpp"

#include <algorithm>
#include <bit>
#include <cstring>
#include <cmath>
#include <tuple>
#include <utility>

namespace vrmc {
namespace {
inline uint32_t floatBits(float value) {
    return std::bit_cast<uint32_t>(value);
}
inline float bitsFloat(uint32_t value) {
    return std::bit_cast<float>(value);
}
}

void ByteWriter::u16(uint16_t value) {
    data_.push_back(static_cast<uint8_t>(value));
    data_.push_back(static_cast<uint8_t>(value >> 8));
}

void ByteWriter::u32(uint32_t value) {
    for (int shift = 0; shift < 32; shift += 8) {
        data_.push_back(static_cast<uint8_t>(value >> shift));
    }
}

void ByteWriter::u64(uint64_t value) {
    for (int shift = 0; shift < 64; shift += 8) {
        data_.push_back(static_cast<uint8_t>(value >> shift));
    }
}

void ByteWriter::f32(float value) {
    u32(floatBits(value));
}

void ByteWriter::bytes(std::span<const uint8_t> value) {
    data_.insert(data_.end(), value.begin(), value.end());
}

void ByteWriter::string(std::string_view value) {
    if (value.size() > kMaxStringBytes) return;
    u16(static_cast<uint16_t>(value.size()));
    data_.insert(data_.end(), value.begin(), value.end());
}

void ByteWriter::vec3(const Vec3& value) {
    f32(value.x); f32(value.y); f32(value.z);
}

void ByteWriter::quat(const Quat& value) {
    f32(value.x); f32(value.y); f32(value.z); f32(value.w);
}

bool ByteReader::u8(uint8_t& value) {
    if (remaining() < 1) return false;
    value = data_[offset_++];
    return true;
}

bool ByteReader::u16(uint16_t& value) {
    if (remaining() < 2) return false;
    value = static_cast<uint16_t>(data_[offset_]) |
            static_cast<uint16_t>(data_[offset_ + 1] << 8);
    offset_ += 2;
    return true;
}

bool ByteReader::u32(uint32_t& value) {
    if (remaining() < 4) return false;
    value = static_cast<uint32_t>(data_[offset_]) |
            (static_cast<uint32_t>(data_[offset_ + 1]) << 8) |
            (static_cast<uint32_t>(data_[offset_ + 2]) << 16) |
            (static_cast<uint32_t>(data_[offset_ + 3]) << 24);
    offset_ += 4;
    return true;
}

bool ByteReader::u64(uint64_t& value) {
    if (remaining() < 8) return false;
    value = 0;
    for (int index = 0; index < 8; ++index) {
        value |= static_cast<uint64_t>(data_[offset_ + index]) << (index * 8);
    }
    offset_ += 8;
    return true;
}

bool ByteReader::f32(float& value) {
    uint32_t bits = 0;
    if (!u32(bits)) return false;
    value = bitsFloat(bits);
    return true;
}

bool ByteReader::bytes(size_t count, std::span<const uint8_t>& value) {
    if (remaining() < count) return false;
    value = data_.subspan(offset_, count);
    offset_ += count;
    return true;
}

bool ByteReader::string(std::string& value) {
    uint16_t length = 0;
    if (!u16(length) || length > kMaxStringBytes || remaining() < length) return false;
    value.assign(reinterpret_cast<const char*>(data_.data() + offset_), length);
    offset_ += length;
    return true;
}

bool ByteReader::vec3(Vec3& value) {
    return f32(value.x) && f32(value.y) && f32(value.z);
}

bool ByteReader::quat(Quat& value) {
    if (!f32(value.x) || !f32(value.y) || !f32(value.z) || !f32(value.w)) return false;
    const float length = value.x * value.x + value.y * value.y + value.z * value.z + value.w * value.w;
    if (length < 0.25f) return false;
    const float inverse = 1.0f / std::sqrt(length);
    value.x *= inverse; value.y *= inverse; value.z *= inverse; value.w *= inverse;
    return true;
}

std::vector<uint8_t> encodeControlHeader(const ControlHeader& header) {
    ByteWriter writer;
    writer.bytes(kControlMagic);
    writer.u8(header.major);
    writer.u8(header.minor);
    writer.u8(static_cast<uint8_t>(header.type));
    writer.u8(header.flags);
    writer.u32(header.sessionId);
    writer.u32(header.sequence);
    writer.u32(header.payloadLength);
    writer.u32(0);
    return writer.take();
}

std::optional<ControlHeader> decodeControlHeader(std::span<const uint8_t> data) {
    if (data.size() < kControlHeaderSize) return std::nullopt;
    if (!std::equal(kControlMagic.begin(), kControlMagic.end(), data.begin())) return std::nullopt;
    ByteReader reader(data);
    std::span<const uint8_t> magic;
    uint8_t major = 0, minor = 0, typeRaw = 0, flags = 0;
    uint32_t session = 0, sequence = 0, payloadLength = 0, reserved = 0;
    if (!reader.bytes(4, magic) || !reader.u8(major) || !reader.u8(minor) ||
        !reader.u8(typeRaw) || !reader.u8(flags) || !reader.u32(session) ||
        !reader.u32(sequence) || !reader.u32(payloadLength) || !reader.u32(reserved)) {
        return std::nullopt;
    }
    if (major != kVersionMajor || payloadLength > kMaxControlPayload) return std::nullopt;
    if (typeRaw < static_cast<uint8_t>(MessageType::Hello) ||
        typeRaw > static_cast<uint8_t>(MessageType::AudioConfig)) {
        return std::nullopt;
    }
    return ControlHeader{
        major, minor, static_cast<MessageType>(typeRaw), flags, session, sequence, payloadLength
    };
}

std::vector<uint8_t> controlFrame(
    MessageType type, std::span<const uint8_t> payload,
    uint32_t sessionId, uint32_t sequence, uint8_t flags) {
    if (payload.size() > kMaxControlPayload) return {};
    ControlHeader header{};
    header.type = type;
    header.flags = flags;
    header.sessionId = sessionId;
    header.sequence = sequence;
    header.payloadLength = static_cast<uint32_t>(payload.size());
    auto output = encodeControlHeader(header);
    output.insert(output.end(), payload.begin(), payload.end());
    return output;
}

std::vector<uint8_t> encodeHello(const Hello& hello) {
    ByteWriter w;
    w.u16(hello.minMajor); w.u16(hello.maxMajor);
    w.u16(hello.minMinor); w.u16(hello.maxMinor);
    w.bytes(hello.nonce);
    w.string(hello.clientVersion);
    w.string(hello.clientPlatform);
    w.u8(hello.authMode);
    w.u32(hello.capabilities);
    return controlFrame(MessageType::Hello, w.data());
}

std::optional<Hello> decodeHello(std::span<const uint8_t> payload) {
    ByteReader r(payload);
    Hello hello;
    std::span<const uint8_t> nonce;
    if (!r.u16(hello.minMajor) || !r.u16(hello.maxMajor) ||
        !r.u16(hello.minMinor) || !r.u16(hello.maxMinor) ||
        !r.bytes(16, nonce) || !r.string(hello.clientVersion) ||
        !r.string(hello.clientPlatform) || !r.u8(hello.authMode) ||
        !r.u32(hello.capabilities) || !r.finished()) {
        return std::nullopt;
    }
    std::copy(nonce.begin(), nonce.end(), hello.nonce.begin());
    return hello;
}

std::vector<uint8_t> encodeWelcome(
    uint32_t sessionId, std::string_view hostName, std::string_view serverVersion, uint8_t authMode) {
    ByteWriter w;
    w.u16(1); w.u16(0); w.u32(sessionId);
    const std::array<uint8_t, 16> nonce{2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2};
    w.bytes(nonce);
    w.u8(authMode);
    w.string(serverVersion);
    w.string(hostName);
    const std::array<uint8_t, 16> salt{};
    w.bytes(salt);
    w.u32(0x3F);
    return controlFrame(MessageType::Welcome, w.data(), sessionId);
}

std::vector<uint8_t> encodeAuthOK(uint32_t sessionId) {
    ByteWriter w;
    w.u8(0);
    w.string("");
    return controlFrame(MessageType::AuthOK, w.data(), sessionId);
}

std::vector<uint8_t> encodeStreamConfig(const StreamConfig& config, uint32_t sessionId) {
    ByteWriter w;
    w.u16(config.configVersion);
    w.u16(config.videoWidth); w.u16(config.videoHeight);
    w.u16(config.eyeWidth); w.u16(config.eyeHeight);
    w.u8(config.eyeOrder); w.u8(config.colorSpace); w.u8(config.codec); w.u8(0);
    w.u16(config.fps); w.u16(config.displayHz);
    w.u32(config.bitrateKbps);
    w.u16(config.keyframeIntervalMs); w.u16(config.maxPacketBytes);
    w.f32(config.ipdMeters);
    for (const auto& projection : {config.leftProjection, config.rightProjection}) {
        w.f32(projection.left); w.f32(projection.right);
        w.f32(projection.top); w.f32(projection.bottom);
    }
    w.vec3(config.leftEyeOffset); w.vec3(config.rightEyeOffset);
    w.u32(config.flags);
    w.string(config.source);
    w.string(config.mappingProfile);
    return controlFrame(MessageType::StreamConfig, w.data(), sessionId);
}

std::vector<uint8_t> encodeStartStream(
    uint32_t sessionId, uint64_t hostTimeNs, uint32_t firstFrameId) {
    ByteWriter w;
    w.u64(hostTimeNs); w.u32(firstFrameId); w.u32(0);
    return controlFrame(MessageType::StartStream, w.data(), sessionId);
}

std::vector<uint8_t> encodeClockPong(
    uint32_t sessionId, uint64_t t0, uint64_t t1, uint64_t t2, uint32_t pingId) {
    ByteWriter w;
    w.u64(t0); w.u64(t1); w.u64(t2); w.u32(pingId);
    return controlFrame(MessageType::ClockPong, w.data(), sessionId);
}

std::vector<uint8_t> encodeSessionState(
    uint32_t sessionId, uint8_t phase, uint16_t reason, uint32_t flags, std::string_view detail) {
    ByteWriter w;
    w.u8(phase); w.u16(reason); w.u32(flags); w.string(detail);
    return controlFrame(MessageType::SessionState, w.data(), sessionId);
}

std::optional<std::pair<uint64_t, uint32_t>> decodeClockPing(std::span<const uint8_t> payload) {
    ByteReader r(payload);
    uint64_t t0 = 0; uint32_t pingId = 0;
    if (!r.u64(t0) || !r.u32(pingId) || !r.finished()) return std::nullopt;
    return std::pair{t0, pingId};
}

std::optional<std::tuple<uint8_t, uint16_t, uint32_t, std::string>> decodeSessionState(
    std::span<const uint8_t> payload) {
    ByteReader r(payload);
    uint8_t phase = 0; uint16_t reason = 0; uint32_t flags = 0; std::string detail;
    if (!r.u8(phase) || !r.u16(reason) || !r.u32(flags) || !r.string(detail) || !r.finished()) {
        return std::nullopt;
    }
    return std::tuple{phase, reason, flags, detail};
}

std::optional<std::tuple<uint32_t, uint8_t, uint64_t>> decodeKeyframeRequest(
    std::span<const uint8_t> payload) {
    ByteReader r(payload);
    uint32_t frameId = 0; uint8_t reason = 0; uint64_t time = 0;
    std::span<const uint8_t> reserved;
    if (!r.u32(frameId) || !r.u8(reason) || !r.bytes(3, reserved) ||
        !r.u64(time) || !r.finished()) {
        return std::nullopt;
    }
    return std::tuple{frameId, reason, time};
}

std::vector<uint8_t> encodeMediaHeader(const MediaHeader& header) {
    ByteWriter w;
    w.bytes(kMediaMagic);
    w.u8(header.version);
    w.u8(static_cast<uint8_t>(header.type));
    w.u8(header.flags);
    w.u8(0);
    w.u16(header.fragmentIndex);
    w.u16(header.fragmentCount);
    w.u16(header.payloadLength);
    w.u32(header.sessionId);
    w.u32(header.frameId);
    w.u32(0);
    w.u64(header.packetSequence);
    w.u64(header.timestampNs);
    return w.take();
}

std::optional<MediaHeader> decodeMediaHeader(std::span<const uint8_t> data) {
    if (data.size() < kMediaHeaderSize) return std::nullopt;
    if (data[0] != kMediaMagic[0] || data[1] != kMediaMagic[1]) return std::nullopt;
    ByteReader r(data);
    std::span<const uint8_t> magic;
    MediaHeader header;
    uint8_t version = 0, type = 0, flags = 0, reserved = 0;
    uint32_t reserved2 = 0;
    if (!r.bytes(2, magic) || !r.u8(version) || !r.u8(type) || !r.u8(flags) ||
        !r.u8(reserved) || !r.u16(header.fragmentIndex) ||
        !r.u16(header.fragmentCount) || !r.u16(header.payloadLength) ||
        !r.u32(header.sessionId) || !r.u32(header.frameId) || !r.u32(reserved2) ||
        !r.u64(header.packetSequence) || !r.u64(header.timestampNs)) {
        return std::nullopt;
    }
    if (version != 1 || header.fragmentCount == 0 ||
        header.fragmentIndex >= header.fragmentCount ||
        header.payloadLength > kMaxMediaPayload) {
        return std::nullopt;
    }
    if (type < static_cast<uint8_t>(MediaType::Video) ||
        type > static_cast<uint8_t>(MediaType::KeepAlive)) {
        return std::nullopt;
    }
    (void)reserved;
    header.version = version;
    header.type = static_cast<MediaType>(type);
    header.flags = flags;
    return header;
}

std::vector<uint8_t> mediaDatagram(
    MediaType type, std::span<const uint8_t> payload, uint32_t sessionId,
    uint32_t frameId, uint64_t packetSequence, uint64_t timestampNs,
    uint16_t fragmentIndex, uint16_t fragmentCount, uint8_t flags) {
    if (payload.size() > kMaxMediaPayload) return {};
    MediaHeader header{};
    header.type = type;
    header.flags = flags;
    header.fragmentIndex = fragmentIndex;
    header.fragmentCount = fragmentCount;
    header.payloadLength = static_cast<uint16_t>(payload.size());
    header.sessionId = sessionId;
    header.frameId = frameId;
    header.packetSequence = packetSequence;
    header.timestampNs = timestampNs;
    auto output = encodeMediaHeader(header);
    output.insert(output.end(), payload.begin(), payload.end());
    return output;
}

std::vector<uint8_t> encodeFrameMetaPayload(const FrameMeta& meta) {
    ByteWriter w;
    w.u32(meta.frameId);
    w.vec3(meta.captureHeadPosition);
    w.quat(meta.captureHeadOrientation);
    w.u32(meta.flags);
    w.u64(meta.sourceFrameNumber);
    w.u64(meta.clientHeadTimestampNs);
    return w.take();
}

std::optional<FrameMeta> decodeFrameMetaPayload(std::span<const uint8_t> payload) {
    ByteReader r(payload);
    FrameMeta meta;
    if (!r.u32(meta.frameId) || !r.vec3(meta.captureHeadPosition) ||
        !r.quat(meta.captureHeadOrientation) || !r.u32(meta.flags) ||
        !r.u64(meta.sourceFrameNumber) || !r.u64(meta.clientHeadTimestampNs) ||
        !r.finished()) {
        return std::nullopt;
    }
    return meta;
}

std::vector<uint8_t> encodeNackPayload(std::span<const std::pair<uint32_t, uint16_t>> entries) {
    ByteWriter w;
    if (!entries.empty()) w.u32(entries.front().first);
    else w.u32(0);
    w.u16(static_cast<uint16_t>(std::min<size_t>(entries.size(), 160)));
    for (size_t index = 0; index < entries.size() && index < 160; ++index) {
        w.u32(entries[index].first);
        w.u16(entries[index].second);
        w.u16(0);
    }
    return w.take();
}

std::optional<HeadPose> decodeHead(std::span<const uint8_t> payload) {
    ByteReader r(payload);
    uint8_t subtype = 0;
    if (!r.u8(subtype) || subtype != 1) return std::nullopt;
    HeadPose head;
    if (!r.u8(head.quality) || !r.u16(head.flags) || !r.u32(head.sampleId) ||
        !r.vec3(head.pose.position) || !r.quat(head.pose.orientation) ||
        !r.vec3(head.linearVelocity) || !r.vec3(head.angularVelocity) || !r.finished()) {
        return std::nullopt;
    }
    return head;
}

std::optional<Intent> decodeIntent(std::span<const uint8_t> payload) {
    ByteReader r(payload);
    uint8_t subtype = 0;
    if (!r.u8(subtype) || subtype != 3) return std::nullopt;
    Intent intent;
    uint32_t reserved = 0;
    if (!r.u8(intent.hand) || !r.u8(intent.quality) || !r.u16(intent.flags) ||
        !r.u32(intent.sampleId) || !r.vec3(intent.pose.position) ||
        !r.quat(intent.pose.orientation) || !r.vec3(intent.linearVelocity) ||
        !r.vec3(intent.angularVelocity) || !r.f32(intent.trigger) ||
        !r.f32(intent.grip) || !r.f32(intent.stickX) || !r.f32(intent.stickY) ||
        !r.f32(intent.trackpadX) || !r.f32(intent.trackpadY) ||
        !r.u32(intent.buttons) || !r.u32(reserved) || !r.finished()) {
        return std::nullopt;
    }
    return intent;
}

std::vector<uint8_t> encodeIdrRequestPayload(
    uint32_t lastFrameId, uint8_t reason, uint64_t clientTimeNs) {
    ByteWriter w;
    w.u32(lastFrameId); w.u8(reason); w.u8(0); w.u8(0); w.u8(0); w.u64(clientTimeNs);
    return w.take();
}

} // namespace vrmc
