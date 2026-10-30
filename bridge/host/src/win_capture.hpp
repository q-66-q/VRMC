#pragma once

#include <Windows.h>
#include <d3d11.h>
#include <functional>
#include <memory>
#include <string>

namespace vrmc {

/// Captures the client area of a top-level window with Windows Graphics Capture.
/// Frames are delivered on the WGC callback thread as a D3D11 texture owned by the
/// capture pool. The callback must not release the texture; copy what it needs.
class WindowCapture {
public:
    using FrameCallback = std::function<void(ID3D11Texture2D*, uint64_t timestampNs)>;
    WindowCapture();
    ~WindowCapture();
    WindowCapture(const WindowCapture&) = delete;
    WindowCapture& operator=(const WindowCapture&) = delete;

    bool initialize(std::string& error);
    bool start(HWND window, FrameCallback callback, std::string& error);
    void stop();
    [[nodiscard]] ID3D11Device* device() const { return device_.get(); }
    [[nodiscard]] ID3D11DeviceContext* context() const { return context_.get(); }
    [[nodiscard]] uint32_t width() const { return width_; }
    [[nodiscard]] uint32_t height() const { return height_; }

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
    ID3D11Device* device_ = nullptr;
    ID3D11DeviceContext* context_ = nullptr;
    uint32_t width_ = 0;
    uint32_t height_ = 0;
};

} // namespace vrmc
