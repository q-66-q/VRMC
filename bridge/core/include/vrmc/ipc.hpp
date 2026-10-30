#pragma once

#include "vrmc/protocol.hpp"

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>

namespace vrmc {

inline constexpr uint32_t kIpcMagic = 0x43524D56; // "VMRC" little-endian
inline constexpr uint32_t kIpcVersion = 1;
inline constexpr const char* kIpcName = "VRMC_IPC_v1";

struct ControllerIpc {
    Pose pose{};
    uint8_t quality = 0; // 0 invalid, 1 degraded, 2 tracked
    uint16_t flags = 0;
    uint32_t buttons = 0;
    float trigger = 0;
    float grip = 0;
    float stickX = 0;
    float stickY = 0;
    float trackpadX = 0;
    float trackpadY = 0;
};

struct IpcSnapshot {
    uint32_t magic = kIpcMagic;
    uint32_t version = kIpcVersion;
    uint64_t sequence = 0;
    uint64_t hostTimeNs = 0;
    uint64_t clientHeadTimestampNs = 0;
    Pose hmd{};
    uint8_t hmdQuality = 0;
    uint8_t reserved = 0;
    uint16_t sessionFlags = 0;
    ControllerIpc left{};
    ControllerIpc right{};
    float hapticAmplitude[2]{0, 0};
};

struct SharedLayout {
    alignas(8) uint32_t seqlock = 0;
    uint32_t reserved = 0;
    IpcSnapshot snapshot{};
};

/// Portable seqlock access for a shared-memory layout. Writer and reader must share the
/// same endianness/ABI (true for the supported Windows x64 host/driver pair).
class IpcWriter {
public:
    explicit IpcWriter(const std::string& name = kIpcName);
    ~IpcWriter();
    IpcWriter(const IpcWriter&) = delete;
    IpcWriter& operator=(const IpcWriter&) = delete;
    [[nodiscard]] bool valid() const { return layout_ != nullptr; }
    void write(const IpcSnapshot& snapshot) noexcept;
    [[nodiscard]] SharedLayout* layout() const { return layout_; }

private:
    SharedLayout* layout_ = nullptr;
#ifdef _WIN32
    void* handle_ = nullptr;
#else
    int fd_ = -1;
    std::string name_;
#endif
};

class IpcReader {
public:
    explicit IpcReader(const std::string& name = kIpcName);
    ~IpcReader();
    IpcReader(const IpcReader&) = delete;
    IpcReader& operator=(const IpcReader&) = delete;
    [[nodiscard]] bool valid() const { return layout_ != nullptr; }
    [[nodiscard]] bool read(IpcSnapshot& output) const noexcept;

private:
    SharedLayout* layout_ = nullptr;
#ifdef _WIN32
    void* handle_ = nullptr;
#else
    int fd_ = -1;
    std::string name_;
#endif
};

} // namespace vrmc
