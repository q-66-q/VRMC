#pragma once

#include <cstdint>
#include <string>
#include <vector>
#include <memory>

struct ID3D11Device;
struct ID3D11DeviceContext;
struct ID3D11Texture2D;

namespace vrmc {

struct EncodedAccessUnit {
    std::vector<uint8_t> data;
    bool keyframe = false;
    uint64_t timestampNs = 0;
    uint64_t frameIndex = 0;
};

/// Low-latency HEVC/H.264 encoder backed by the NVIDIA driver's NVENC API.
/// The header is provided by FFmpeg's nv-codec-headers; the runtime DLL comes with the
/// user's NVIDIA driver. No NVIDIA binaries are bundled.
class NvencEncoder {
public:
    NvencEncoder();
    ~NvencEncoder();
    NvencEncoder(const NvencEncoder&) = delete;
    NvencEncoder& operator=(const NvencEncoder&) = delete;

    bool initialize(
        ID3D11Device* device, ID3D11DeviceContext* context,
        uint32_t width, uint32_t height, uint32_t fps,
        uint32_t bitrateKbps, bool hevc, std::string& error);
    bool encode(
        ID3D11Texture2D* source, uint64_t timestampNs, bool forceIDR,
        EncodedAccessUnit& output, std::string& error);
    void shutdown();
    [[nodiscard]] bool isReady() const { return ready_; }
    [[nodiscard]] bool isHevc() const { return hevc_; }

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
    bool ready_ = false;
    bool hevc_ = true;
};

} // namespace vrmc
