#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace vrmc {

inline constexpr std::array<uint8_t, 4> kControlMagic{'V', 'R', 'M', 'C'};
inline constexpr std::array<uint8_t, 2> kMediaMagic{'V', 'M'};
inline constexpr uint8_t kVersionMajor = 1;
inline constexpr uint8_t kVersionMinor = 0;
inline constexpr size_t kControlHeaderSize = 24;
inline constexpr size_t kMediaHeaderSize = 40;
inline constexpr size_t kMaxControlPayload = 1'048'576;
inline constexpr size_t kMaxDatagram = 1'200;
inline constexpr size_t kMaxMediaPayload = 1'144;
inline constexpr size_t kMaxStringBytes = 255;

enum class MessageType : uint8_t {
    Hello = 0x01,
    Welcome = 0x02,
    AuthChallenge = 0x03,
    AuthResponse = 0x04,
    AuthOK = 0x05,
    StreamConfig = 0x06,
    StartStream = 0x07,
    StopStream = 0x08,
    KeyframeRequest = 0x09,
    SessionState = 0x0A,
    ClockPing = 0x0B,
    ClockPong = 0x0C,
    TelemetryClient = 0x0D,
    TelemetryHost = 0x0E,
    SetQuality = 0x0F,
    InputConfig = 0x10,
    Haptic = 0x11,
    Heartbeat = 0x12,
    Disconnect = 0x13,
    Error = 0x14,
    AudioConfig = 0x15,
};

enum class MediaType : uint8_t {
    Video = 1,
    Input = 2,
    Audio = 3,
    FrameMeta = 4,
    Nack = 5,
    IdrRequest = 6,
    KeepAlive = 7,
};

inline constexpr uint8_t kControlFlagPlaintext = 1u << 0;
inline constexpr uint8_t kMediaFlagKeyframe = 1u << 0;
inline constexpr uint8_t kMediaFlagConfig = 1u << 1;
inline constexpr uint8_t kMediaFlagRetransmit = 1u << 2;
inline constexpr uint8_t kMediaFlagMetaDuplicate = 1u << 3;
inline constexpr uint8_t kMediaFlagPlaintext = 1u << 4;

struct Vec3 {
    float x = 0, y = 0, z = 0;
};

struct Quat {
    float x = 0, y = 0, z = 0, w = 1;
};

struct Pose {
    Vec3 position{};
    Quat orientation{};
};

struct ControlHeader {
    uint8_t major = kVersionMajor;
    uint8_t minor = kVersionMinor;
    MessageType type = MessageType::Error;
    uint8_t flags = kControlFlagPlaintext;
    uint32_t sessionId = 0;
    uint32_t sequence = 0;
    uint32_t payloadLength = 0;
};

struct MediaHeader {
    uint8_t version = 1;
    MediaType type = MediaType::Video;
    uint8_t flags = kMediaFlagPlaintext;
    uint16_t fragmentIndex = 0;
    uint16_t fragmentCount = 1;
    uint16_t payloadLength = 0;
    uint32_t sessionId = 0;
    uint32_t frameId = 0;
    uint64_t packetSequence = 0;
    uint64_t timestampNs = 0;
};

struct Hello {
    uint16_t minMajor = 1, maxMajor = 1, minMinor = 0, maxMinor = 0;
    std::array<uint8_t, 16> nonce{};
    std::string clientVersion;
    std::string clientPlatform;
    uint8_t authMode = 3;
    uint32_t capabilities = 0;
};

struct StreamProjection {
    float left = -1.1917536f;
    float right = 1.1917536f;
    float top = 1.0f;
    float bottom = -1.0f;
};

struct StreamConfig {
    uint16_t configVersion = 1;
    uint16_t videoWidth = 3840;
    uint16_t videoHeight = 1080;
    uint16_t eyeWidth = 1920;
    uint16_t eyeHeight = 1080;
    uint8_t eyeOrder = 0;
    uint8_t colorSpace = 0;
    uint8_t codec = 2; // 1 H.264, 2 HEVC
    uint16_t fps = 90;
    uint16_t displayHz = 90;
    uint32_t bitrateKbps = 90000;
    uint16_t keyframeIntervalMs = 1000;
    uint16_t maxPacketBytes = 1200;
    float ipdMeters = 0.064f;
    StreamProjection leftProjection{};
    StreamProjection rightProjection{};
    Vec3 leftEyeOffset{-0.032f, 0, 0};
    Vec3 rightEyeOffset{0.032f, 0, 0};
    uint32_t flags = 0;
    std::string source;
    std::string mappingProfile = "handmap-v1";
};

struct FrameMeta {
    uint32_t frameId = 0;
    Vec3 captureHeadPosition{};
    Quat captureHeadOrientation{};
    uint32_t flags = 0;
    uint64_t sourceFrameNumber = 0;
    uint64_t clientHeadTimestampNs = 0;
};

struct HeadPose {
    uint8_t quality = 0;
    uint16_t flags = 0;
    uint32_t sampleId = 0;
    Pose pose{};
    Vec3 linearVelocity{};
    Vec3 angularVelocity{};
};

struct Intent {
    uint8_t hand = 0; // 0 left, 1 right
    uint8_t quality = 0;
    uint16_t flags = 0;
    uint32_t sampleId = 0;
    Pose pose{};
    Vec3 linearVelocity{};
    Vec3 angularVelocity{};
    float trigger = 0;
    float grip = 0;
    float stickX = 0;
    float stickY = 0;
    float trackpadX = 0;
    float trackpadY = 0;
    uint32_t buttons = 0;
};

class ByteWriter {
public:
    ByteWriter() = default;
    void u8(uint8_t value) { data_.push_back(value); }
    void u16(uint16_t value);
    void u32(uint32_t value);
    void u64(uint64_t value);
    void i32(int32_t value) { u32(static_cast<uint32_t>(value)); }
    void f32(float value);
    void bytes(std::span<const uint8_t> value);
    void string(std::string_view value);
    void vec3(const Vec3& value);
    void quat(const Quat& value);
    [[nodiscard]] const std::vector<uint8_t>& data() const { return data_; }
    [[nodiscard]] std::vector<uint8_t> take() { return std::move(data_); }

private:
    std::vector<uint8_t> data_;
};

class ByteReader {
public:
    explicit ByteReader(std::span<const uint8_t> data) : data_(data) {}
    [[nodiscard]] bool u8(uint8_t& value);
    [[nodiscard]] bool u16(uint16_t& value);
    [[nodiscard]] bool u32(uint32_t& value);
    [[nodiscard]] bool u64(uint64_t& value);
    [[nodiscard]] bool f32(float& value);
    [[nodiscard]] bool bytes(size_t count, std::span<const uint8_t>& value);
    [[nodiscard]] bool string(std::string& value);
    [[nodiscard]] bool vec3(Vec3& value);
    [[nodiscard]] bool quat(Quat& value);
    [[nodiscard]] bool finished() const { return offset_ == data_.size(); }
    [[nodiscard]] size_t remaining() const { return data_.size() - offset_; }

private:
    std::span<const uint8_t> data_;
    size_t offset_ = 0;
};

[[nodiscard]] std::vector<uint8_t> encodeControlHeader(const ControlHeader& header);
[[nodiscard]] std::optional<ControlHeader> decodeControlHeader(std::span<const uint8_t> data);
[[nodiscard]] std::vector<uint8_t> controlFrame(
    MessageType type, std::span<const uint8_t> payload,
    uint32_t sessionId = 0, uint32_t sequence = 0, uint8_t flags = kControlFlagPlaintext);

[[nodiscard]] std::vector<uint8_t> encodeHello(const Hello& hello);
[[nodiscard]] std::optional<Hello> decodeHello(std::span<const uint8_t> payload);

[[nodiscard]] std::vector<uint8_t> encodeWelcome(
    uint32_t sessionId, std::string_view hostName = "VRMC host",
    std::string_view serverVersion = "0.1.0", uint8_t authMode = 3);
[[nodiscard]] std::vector<uint8_t> encodeAuthOK(uint32_t sessionId);
[[nodiscard]] std::vector<uint8_t> encodeStreamConfig(const StreamConfig& config, uint32_t sessionId);
[[nodiscard]] std::vector<uint8_t> encodeStartStream(
    uint32_t sessionId, uint64_t hostTimeNs, uint32_t firstFrameId = 1);
[[nodiscard]] std::vector<uint8_t> encodeClockPong(
    uint32_t sessionId, uint64_t t0, uint64_t t1, uint64_t t2, uint32_t pingId);
[[nodiscard]] std::vector<uint8_t> encodeSessionState(
    uint32_t sessionId, uint8_t phase, uint16_t reason, uint32_t flags = 0,
    std::string_view detail = "");

[[nodiscard]] std::optional<std::pair<uint64_t, uint32_t>> decodeClockPing(std::span<const uint8_t> payload);
[[nodiscard]] std::optional<std::tuple<uint8_t, uint16_t, uint32_t, std::string>> decodeSessionState(
    std::span<const uint8_t> payload);
[[nodiscard]] std::optional<std::tuple<uint32_t, uint8_t, uint64_t>> decodeKeyframeRequest(
    std::span<const uint8_t> payload);

[[nodiscard]] std::vector<uint8_t> encodeMediaHeader(const MediaHeader& header);
[[nodiscard]] std::optional<MediaHeader> decodeMediaHeader(std::span<const uint8_t> data);
[[nodiscard]] std::vector<uint8_t> mediaDatagram(
    MediaType type, std::span<const uint8_t> payload, uint32_t sessionId,
    uint32_t frameId, uint64_t packetSequence, uint64_t timestampNs,
    uint16_t fragmentIndex = 0, uint16_t fragmentCount = 1,
    uint8_t flags = kMediaFlagPlaintext);

[[nodiscard]] std::vector<uint8_t> encodeFrameMetaPayload(const FrameMeta& meta);
[[nodiscard]] std::optional<FrameMeta> decodeFrameMetaPayload(std::span<const uint8_t> payload);
[[nodiscard]] std::vector<uint8_t> encodeNackPayload(
    std::span<const std::pair<uint32_t, uint16_t>> entries);
[[nodiscard]] std::optional<HeadPose> decodeHead(std::span<const uint8_t> payload);
[[nodiscard]] std::optional<Intent> decodeIntent(std::span<const uint8_t> payload);
[[nodiscard]] std::vector<uint8_t> encodeIdrRequestPayload(
    uint32_t lastFrameId, uint8_t reason, uint64_t clientTimeNs);

} // namespace vrmc
