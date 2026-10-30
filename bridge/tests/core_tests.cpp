#include "vrmc/clock.hpp"
#include "vrmc/ipc.hpp"
#include "vrmc/pose.hpp"
#include "vrmc/protocol.hpp"

#include <cassert>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <span>
#include <vector>

namespace {
int failures = 0;

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        ++failures;
    }
}

std::span<const uint8_t> payloadOf(const std::vector<uint8_t>& frame) {
    assert(frame.size() >= vrmc::kControlHeaderSize);
    return std::span<const uint8_t>(frame).subspan(vrmc::kControlHeaderSize);
}
} // namespace

int main() {
    using namespace vrmc;

    {
        ByteWriter w;
        w.u16(0x1234); w.u32(0x89ABCDEF); w.u64(0x0102030405060708ULL);
        ByteReader r(w.data());
        uint16_t a = 0; uint32_t b = 0; uint64_t c = 0;
        expect(r.u16(a) && a == 0x1234, "u16 endianness");
        expect(r.u32(b) && b == 0x89ABCDEF, "u32 endianness");
        expect(r.u64(c) && c == 0x0102030405060708ULL, "u64 endianness");
        expect(r.finished(), "reader finished");
        uint8_t overrun = 0;
        expect(!r.u8(overrun), "reader rejects overrun");
    }

    {
        auto frame = encodeHello(Hello{});
        auto header = decodeControlHeader(frame);
        expect(header.has_value(), "hello header decodes");
        expect(header->type == MessageType::Hello, "hello type");
        expect(header->payloadLength + kControlHeaderSize == frame.size(), "hello length");
        auto hello = decodeHello(payloadOf(frame));
        expect(hello.has_value(), "hello payload decodes");
        if (hello) {
            expect(hello->maxMajor == 1 && hello->authMode == 3, "hello fields");
        }
        auto truncated = std::span<const uint8_t>(frame).first(10);
        auto bad = decodeControlHeader(truncated);
        expect(!bad.has_value(), "truncated control header rejected");
    }

    {
        StreamConfig config;
        config.source = "Vivecraft DUAL 3840x1080";
        auto frame = encodeStreamConfig(config, 42);
        auto header = decodeControlHeader(frame);
        expect(header && header->type == MessageType::StreamConfig, "stream config type");
        ByteReader r(payloadOf(frame));
        uint16_t value16 = 0; uint32_t value32 = 0; float valuef = 0;
        uint8_t value8 = 0;
        expect(r.u16(value16) && value16 == 1, "config version");
        expect(r.u16(value16) && value16 == 3840, "video width");
        expect(r.u16(value16) && value16 == 1080, "video height");
        expect(r.u16(value16) && value16 == 1920, "eye width");
        expect(r.u16(value16) && value16 == 1080, "eye height");
        expect(r.u8(value8) && value8 == 0, "eye order");
        expect(r.u8(value8), "color space");
        expect(r.u8(value8) && value8 == 2, "codec");
        expect(r.u8(value8), "reserved");
        expect(r.u16(value16) && value16 == 90, "fps");
        expect(r.u16(value16) && value16 == 90, "display hz");
        expect(r.u32(value32) && value32 == 90000, "bitrate");
        expect(r.u16(value16), "keyframe");
        expect(r.u16(value16) && value16 == 1200, "max packet");
        expect(r.f32(valuef) && valuef > 0.05f, "ipd");
        float l = 0, rr = 0, t = 0, b = 0;
        expect(r.f32(l) && r.f32(rr) && r.f32(t) && r.f32(b) && l < rr && b < t, "projection");
    }

    {
        MediaHeader header{};
        header.type = MediaType::Video;
        header.fragmentIndex = 2;
        header.fragmentCount = 4;
        header.payloadLength = 3;
        header.sessionId = 7;
        header.frameId = 9;
        header.packetSequence = 1234;
        header.timestampNs = 987654321;
        auto bytes = encodeMediaHeader(header);
        auto decoded = decodeMediaHeader(bytes);
        expect(decoded.has_value(), "media header decodes");
        if (decoded) {
            expect(decoded->type == MediaType::Video, "media type");
            expect(decoded->fragmentIndex == 2 && decoded->fragmentCount == 4, "fragment fields");
            expect(decoded->frameId == 9 && decoded->packetSequence == 1234, "media ids");
        }
        std::array<uint8_t, 3> payload{1, 2, 3};
        auto datagram = mediaDatagram(
            MediaType::Video, payload, 7, 9, 1234, 987654321, 2, 4, kMediaFlagPlaintext | kMediaFlagKeyframe);
        expect(datagram.size() == kMediaHeaderSize + 3, "datagram length");
    }

    {
        FrameMeta meta{};
        meta.frameId = 55;
        meta.captureHeadPosition = {0.0f, 1.6f, 0.0f};
        meta.captureHeadOrientation = {0, 0, 0, 1};
        meta.clientHeadTimestampNs = 999;
        auto payload = encodeFrameMetaPayload(meta);
        auto decoded = decodeFrameMetaPayload(payload);
        expect(decoded.has_value(), "frame meta decodes");
        if (decoded) {
            expect(decoded->frameId == 55, "frame meta id");
            expect(decoded->clientHeadTimestampNs == 999, "frame meta client time");
        }
    }

    {
        ByteWriter w;
        w.u8(3);            // intent subtype
        w.u8(1);            // right
        w.u8(2);            // tracked
        w.u16(0);
        w.u32(77);          // sample
        w.vec3({0, 1, 0}); w.quat({0, 0, 0, 1});
        w.vec3({}); w.vec3({});
        w.f32(0.9f); w.f32(0.2f); w.f32(0.1f); w.f32(-0.2f);
        w.f32(0.0f); w.f32(0.0f); w.u32(0x3); w.u32(0);
        auto intent = decodeIntent(w.data());
        expect(intent.has_value(), "intent decodes");
        if (intent) {
            expect(intent->hand == 1 && intent->quality == 2, "intent fields");
            expect(intent->buttons == 0x3, "intent buttons");
        }
    }

    {
        auto frame = encodeClockPong(1, 100, 110, 120, 9);
        auto header = decodeControlHeader(frame);
        expect(header && header->type == MessageType::ClockPong, "clock pong type");
        expect(decodeClockPing(payloadOf(frame)).has_value() == false, "clock pong is not ping");
    }

    {
        IpcWriter writer("VRMC_TEST_IPC");
        IpcReader reader("VRMC_TEST_IPC");
        expect(writer.valid() && reader.valid(), "ipc opens");
        IpcSnapshot snapshot{};
        snapshot.sequence = 5;
        snapshot.hmd.position = {1, 2, 3};
        snapshot.left.trigger = 0.75f;
        writer.write(snapshot);
        IpcSnapshot read{};
        expect(reader.read(read), "ipc reads");
        expect(read.hmd.position.x == 1 && read.left.trigger > 0.7f, "ipc roundtrip");
    }

    {
        auto load = [](const char* name) -> std::vector<uint8_t> {
            std::ifstream input(std::string(VRMC_VECTOR_DIR) + "/" + name, std::ios::binary);
            return std::vector<uint8_t>((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
        };
        auto helloBytes = load("hello.bin");
        expect(!helloBytes.empty(), "hello vector exists");
        if (!helloBytes.empty()) {
            auto header = decodeControlHeader(helloBytes);
            expect(header && header->type == MessageType::Hello, "vector hello header");
            auto payload = std::span<const uint8_t>(helloBytes).subspan(kControlHeaderSize);
            auto hello = decodeHello(payload);
            expect(hello.has_value(), "vector hello payload");
            if (hello) {
                auto reencoded = encodeHello(*hello);
                expect(reencoded == helloBytes, "vector hello byte-identical");
            }
        }
        auto metaBytes = load("frame_meta.bin");
        if (!metaBytes.empty()) {
            auto header = decodeMediaHeader(metaBytes);
            expect(header && header->type == MediaType::FrameMeta, "vector meta header");
            auto payload = std::span<const uint8_t>(metaBytes).subspan(kMediaHeaderSize, header->payloadLength);
            auto meta = decodeFrameMetaPayload(payload);
            expect(meta && meta->frameId == 42 && meta->clientHeadTimestampNs == 777, "vector meta values");
        }
        auto intentBytes = load("intent.bin");
        if (!intentBytes.empty()) {
            auto header = decodeMediaHeader(intentBytes);
            expect(header && header->type == MediaType::Input, "vector intent header");
            auto payload = std::span<const uint8_t>(intentBytes).subspan(kMediaHeaderSize, header->payloadLength);
            auto intent = decodeIntent(payload);
            expect(intent && intent->hand == 1 && intent->buttons == 0x205, "vector intent values");
        }
    }

    {
        ClockSyncEstimator estimator;
        const int64_t offset = 5'000'000'000LL;
        for (int index = 0; index < 16; ++index) {
            const uint64_t t0 = static_cast<uint64_t>(index) * 1'000'000'000ULL;
            const uint64_t t1 = static_cast<uint64_t>(static_cast<int64_t>(t0) + offset + 2'000'000);
            const uint64_t t2 = t1 + 1'000'000;
            const uint64_t t3 = t0 + 5'000'000;
            estimator.add(ClockSample{t0, t1, t2, t3});
        }
        auto estimate = estimator.latest();
        expect(estimate.has_value(), "clock estimate exists");
        if (estimate) {
            expect(std::llabs(estimate->offset - offset) < 500'000, "clock offset");
            expect(estimate->roundTrip == 4'000'000, "clock rtt");
        }
        auto mapped = estimator.clientToHost(10'000'000'000ULL);
        expect(mapped && std::llabs(static_cast<int64_t>(*mapped) - 15'000'000'000LL) < 1'000'000,
               "clock mapping");
    }

    {
        const Quat q = pose_math::fromAxisAngle(Vec3{0, 1, 0}, 1.57079632679f);
        const Vec3 forward = pose_math::rotate(q, Vec3{0, 0, -1});
        expect(std::fabs(forward.x + 1) < 1e-4f, "quaternion forward");
        const Pose predicted = pose_math::predict(
            Pose{{0, 1, 0}, Quat{}}, Vec3{1, 0, 0}, Vec3{0, 10, 0}, 1.0f);
        expect(std::fabs(predicted.position.x - 0.05f) < 1e-5f, "pose prediction clamp");
        expect(std::fabs(pose_math::yaw(q) - 1.57079632679f) < 1e-4f, "yaw");
    }

    if (failures == 0) {
        std::cout << "VRMC C++ core tests passed\n";
        return 0;
    }
    std::cerr << failures << " failure(s)\n";
    return 1;
}
