#include "win_capture.hpp"

#include <d3d11.h>
#include <dxgi1_2.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>

#include <chrono>
#include <iterator>
#include <mutex>

using namespace winrt;
using namespace Windows::Graphics::Capture;
using namespace Windows::Graphics::DirectX;
using namespace Windows::Graphics::DirectX::Direct3D11;

namespace vrmc {

struct WindowCapture::Impl {
    std::mutex mutex;
    GraphicsCaptureItem item{nullptr};
    Direct3D11CaptureFramePool framePool{nullptr};
    GraphicsCaptureSession session{nullptr};
    FrameCallback callback;
    HWND window = nullptr;
    uint32_t width = 0;
    uint32_t height = 0;
    bool running = false;

    void onFrame(Direct3D11CaptureFramePool const&, Direct3D11CaptureFramePool::FrameArrivedEventArgs const& args) {
        std::lock_guard lock(mutex);
        if (!running) return;
        auto frame = args.Frame();
        if (!frame) return;
        auto size = frame.ContentSize();
        if (static_cast<uint32_t>(size.Width) != width || static_cast<uint32_t>(size.Height) != height) {
            // A resized window invalidates the pool; let the host reject the stream.
            return;
        }
        try {
            auto access = frame.Surface().as<IDirect3DDxgiInterfaceAccess>();
            com_ptr<ID3D11Texture2D> texture;
            check_hresult(access->GetDXGIInterface(__uuidof(ID3D11Texture2D), texture.put_void()));
            const auto timestamp = std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count();
            if (callback) callback(texture.get(), static_cast<uint64_t>(timestamp));
        } catch (...) {
            // A lost frame/pool is recoverable; the host will report capture degraded.
        }
        frame.Close();
    }
};

WindowCapture::WindowCapture() : impl_(std::make_unique<Impl>()) {}

WindowCapture::~WindowCapture() {
    stop();
    if (context_) context_->Release();
    if (device_) device_->Release();
}

bool WindowCapture::initialize(std::string& error) {
    D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
    ID3D11Device* device = nullptr;
    ID3D11DeviceContext* context = nullptr;
    HRESULT hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        levels, static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION,
        &device, nullptr, &context);
    if (FAILED(hr)) {
        error = "D3D11CreateDevice failed";
        return false;
    }
    device_ = device;
    context_ = context;
    return true;
}

bool WindowCapture::start(HWND window, FrameCallback callback, std::string& error) {
    if (device_ == nullptr || window == nullptr) {
        error = "capture not initialized or no window";
        return false;
    }
    try {
        com_ptr<IDXGIDevice> dxgiDevice;
        check_hresult(device_->QueryInterface(__uuidof(IDXGIDevice), dxgiDevice.put_void()));
        IDirect3DDevice winrtDevice{nullptr};
        check_hresult(CreateDirect3D11DeviceFromDXGIDevice(
            dxgiDevice.get(), reinterpret_cast<IInspectable**>(put_abi(winrtDevice))));

        auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
        GraphicsCaptureItem item{nullptr};
        check_hresult(interop->CreateForWindow(
            window,
            guid_of<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
            put_abi(item)));

        const auto size = item.Size();
        impl_->item = item;
        impl_->window = window;
        impl_->width = static_cast<uint32_t>(size.Width);
        impl_->height = static_cast<uint32_t>(size.Height);
        impl_->callback = std::move(callback);
        width_ = impl_->width;
        height_ = impl_->height;
        if (width_ == 0 || height_ == 0) {
            error = "capture window has zero size";
            return false;
        }

        impl_->framePool = Direct3D11CaptureFramePool::CreateFreeThreaded(
            winrtDevice, DirectPixelFormat::B8G8R8A8UIntNormalized, 3, size);
        impl_->session = impl_->framePool.CreateCaptureSession(item);
        impl_->framePool.FrameArrived(
            {this, [this](auto const& sender, auto const& args) { impl_->onFrame(sender, args); }});
        {
            std::lock_guard lock(impl_->mutex);
            impl_->running = true;
        }
        impl_->session.StartCapture();
        return true;
    } catch (hresult_error const& exception) {
        error = to_string(exception.message());
        return false;
    }
}

void WindowCapture::stop() {
    if (!impl_) return;
    {
        std::lock_guard lock(impl_->mutex);
        impl_->running = false;
    }
    if (impl_->session) impl_->session.Close();
    if (impl_->framePool) impl_->framePool.Close();
    impl_->session = nullptr;
    impl_->framePool = nullptr;
    impl_->item = nullptr;
}

} // namespace vrmc
