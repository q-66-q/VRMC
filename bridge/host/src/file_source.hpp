#pragma once

#include "nvenc_encoder.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace vrmc {

/// Streams pre-encoded Annex-B access units from a file at the configured rate.
/// Used for host/control-path testing and simulator demos when a GPU/window is absent.
class FileVideoSource {
public:
    bool open(const std::string& path, uint32_t fps, std::string& error);
    bool next(EncodedAccessUnit& output);
    void rewind();
    [[nodiscard]] uint32_t fps() const { return fps_; }

private:
    std::vector<EncodedAccessUnit> units_;
    size_t index_ = 0;
    uint32_t fps_ = 30;
};

} // namespace vrmc
