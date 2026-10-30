#include "nvenc_encoder.hpp"

#include <Windows.h>
#include <d3d11.h>
#include <ffnvcodec/nvEncodeAPI.h>

#include <algorithm>
#include <cstring>
#include <sstream>

namespace vrmc {
namespace {
std::string nvError(NV_ENCODE_API_FUNCTION_LIST* api, void* encoder, NVENCSTATUS status) {
    if (encoder != nullptr && api != nullptr && api->nvEncGetLastErrorString != nullptr) {
        const char* message = api->nvEncGetLastErrorString(encoder);
        if (message != nullptr) return message;
    }
    return "NVENC error " + std::to_string(static_cast<int>(status));
}

std::string hresultText(HRESULT hr) {
    std::ostringstream stream;
    stream << "HRESULT 0x" << std::hex << static_cast<unsigned long>(hr);
    return stream.str();
}
}

struct NvencEncoder::Impl {
    HMODULE module = nullptr;
    NV_ENCODE_API_FUNCTION_LIST api{};
    void* encoder = nullptr;
    NV_ENC_REGISTERED_PTR registered = nullptr;
    NV_ENC_INPUT_PTR mapped = nullptr;
    NV_ENC_OUTPUT_PTR bitstream = nullptr;
    void* event = nullptr;
    ID3D11Texture2D* inputTexture = nullptr;
    ID3D11Device* device = nullptr;
    ID3D11DeviceContext* context = nullptr;
    uint32_t width = 0;
    uint32_t height = 0;
    uint64_t frameIndex = 0;
    bool hevc = true;

    bool createInputTexture(std::string& error) {
        D3D11_TEXTURE2D_DESC desc{};
        desc.Width = width;
        desc.Height = height;
        desc.MipLevels = 1;
        desc.ArraySize = 1;
        desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        desc.SampleDesc.Count = 1;
        desc.Usage = D3D11_USAGE_DEFAULT;
        desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
        HRESULT hr = device->CreateTexture2D(&desc, nullptr, &inputTexture);
        if (FAILED(hr)) {
            error = "CreateTexture2D for NVENC input failed: " + hresultText(hr);
            return false;
        }
        NV_ENC_REGISTER_RESOURCE reg{};
        reg.version = NV_ENC_REGISTER_RESOURCE_VER;
        reg.resourceType = NV_ENC_INPUT_RESOURCE_TYPE_DIRECTX;
        reg.width = width;
        reg.height = height;
        reg.bufferFormat = NV_ENC_BUFFER_FORMAT_ABGR;
        reg.resourceToRegister = inputTexture;
        NVENCSTATUS status = api.nvEncRegisterResource(encoder, &reg);
        if (status != NV_ENC_SUCCESS) {
            error = nvError(&api, encoder, status);
            return false;
        }
        registered = reg.registeredResource;
        return true;
    }

    void cleanup() {
        if (encoder != nullptr && api.nvEncDestroyBitstreamBuffer != nullptr && bitstream != nullptr) {
            api.nvEncDestroyBitstreamBuffer(encoder, bitstream);
            bitstream = nullptr;
        }
        if (encoder != nullptr && api.nvEncUnregisterResource != nullptr && registered != nullptr) {
            api.nvEncUnregisterResource(encoder, registered);
            registered = nullptr;
        }
        if (encoder != nullptr && api.nvEncUnregisterAsyncEvent != nullptr && event != nullptr) {
            NV_ENC_EVENT_PARAMS eventParams{};
            eventParams.version = NV_ENC_EVENT_PARAMS_VER;
            eventParams.completionEvent = event;
            api.nvEncUnregisterAsyncEvent(encoder, &eventParams);
            event = nullptr;
        }
        if (event != nullptr) {
            CloseHandle(event);
            event = nullptr;
        }
        if (inputTexture != nullptr) {
            inputTexture->Release();
            inputTexture = nullptr;
        }
        if (encoder != nullptr && api.nvEncDestroyEncoder != nullptr) {
            api.nvEncDestroyEncoder(encoder);
            encoder = nullptr;
        }
        if (module != nullptr) {
            FreeLibrary(module);
            module = nullptr;
        }
    }
};

NvencEncoder::NvencEncoder() : impl_(std::make_unique<Impl>()) {}

NvencEncoder::~NvencEncoder() { shutdown(); }

bool NvencEncoder::initialize(
    ID3D11Device* device, ID3D11DeviceContext* context,
    uint32_t width, uint32_t height, uint32_t fps,
    uint32_t bitrateKbps, bool hevc, std::string& error) {
    shutdown();
    if (device == nullptr || context == nullptr || width == 0 || height == 0) {
        error = "invalid NVENC device/dimensions";
        return false;
    }
    auto& d = *impl_;
    d.device = device;
    d.context = context;
    d.width = width;
    d.height = height;
    d.hevc = hevc;
    hevc_ = hevc;

    d.module = LoadLibraryA("nvEncodeAPI64.dll");
    if (d.module == nullptr) {
        error = "nvEncodeAPI64.dll not found; install an NVIDIA driver";
        return false;
    }
    using GetMaxVersion = NVENCSTATUS(NVENCAPI*)(uint32_t*);
    using CreateInstance = NVENCSTATUS(NVENCAPI*)(NV_ENCODE_API_FUNCTION_LIST*);
    auto getMax = reinterpret_cast<GetMaxVersion>(GetProcAddress(d.module, "NvEncodeAPIGetMaxSupportedVersion"));
    auto create = reinterpret_cast<CreateInstance>(GetProcAddress(d.module, "NvEncodeAPICreateInstance"));
    if (getMax == nullptr || create == nullptr) {
        error = "NVENC API entry points missing";
        d.cleanup();
        return false;
    }
    uint32_t maxVersion = 0;
    if (getMax(&maxVersion) != NV_ENC_SUCCESS || maxVersion < NVENCAPI_VERSION) {
        error = "NVIDIA driver is too old for this NVENC API";
        d.cleanup();
        return false;
    }
    d.api.version = NV_ENCODE_API_FUNCTION_LIST_VER;
    if (create(&d.api) != NV_ENC_SUCCESS) {
        error = "NvEncodeAPICreateInstance failed";
        d.cleanup();
        return false;
    }

    NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS session{};
    session.version = NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS_VER;
    session.deviceType = NV_ENC_DEVICE_TYPE_DIRECTX;
    session.device = device;
    session.apiVersion = NVENCAPI_VERSION;
    NVENCSTATUS status = d.api.nvEncOpenEncodeSessionEx(&session, &d.encoder);
    if (status != NV_ENC_SUCCESS) {
        error = nvError(&d.api, d.encoder, status);
        d.cleanup();
        return false;
    }

    NV_ENC_CONFIG config{};
    config.version = NV_ENC_CONFIG_VER;
    config.profileGUID = hevc ? NV_ENC_HEVC_PROFILE_MAIN_GUID : NV_ENC_H264_PROFILE_HIGH_GUID;
    config.gopLength = std::max<uint32_t>(fps, 1);
    config.frameIntervalP = 1;
    config.rcParams.version = NV_ENC_RC_PARAMS_VER;
    config.rcParams.rateControlMode = NV_ENC_PARAMS_RC_CBR;
    config.rcParams.averageBitRate = bitrateKbps * 1000;
    config.rcParams.maxBitRate = bitrateKbps * 1000;
    config.rcParams.vbvBufferSize = std::max<uint32_t>(bitrateKbps * 1000 / std::max<uint32_t>(fps, 1), 1);
    config.rcParams.vbvInitialDelay = config.rcParams.vbvBufferSize / 2;
    config.rcParams.zeroReorderDelay = 1;
    config.rcParams.enableLookahead = 0;
    config.rcParams.lowDelayKeyFrameScale = 1;
    config.rcParams.multiPass = NV_ENC_MULTI_PASS_DISABLED;
    if (hevc) {
        config.encodeCodecConfig.hevcConfig.idrPeriod = std::max<uint32_t>(fps, 1);
        config.encodeCodecConfig.hevcConfig.repeatSPSPPS = 1;
        config.encodeCodecConfig.hevcConfig.outputAUD = 1;
        config.encodeCodecConfig.hevcConfig.maxNumRefFramesInDPB = 1;
    } else {
        config.encodeCodecConfig.h264Config.idrPeriod = std::max<uint32_t>(fps, 1);
        config.encodeCodecConfig.h264Config.repeatSPSPPS = 1;
        config.encodeCodecConfig.h264Config.outputAUD = 1;
        config.encodeCodecConfig.h264Config.maxNumRefFrames = 1;
    }

    NV_ENC_INITIALIZE_PARAMS init{};
    init.version = NV_ENC_INITIALIZE_PARAMS_VER;
    init.encodeGUID = hevc ? NV_ENC_CODEC_HEVC_GUID : NV_ENC_CODEC_H264_GUID;
    init.presetGUID = NV_ENC_PRESET_P1_GUID;
    init.tuningInfo = NV_ENC_TUNING_INFO_ULTRA_LOW_LATENCY;
    init.encodeWidth = width;
    init.encodeHeight = height;
    init.maxEncodeWidth = width;
    init.maxEncodeHeight = height;
    init.frameRateNum = std::max<uint32_t>(fps, 1);
    init.frameRateDen = 1;
    init.enablePTD = 1;
    init.bufferFormat = NV_ENC_BUFFER_FORMAT_ABGR;
    init.encodeConfig = &config;
    status = d.api.nvEncInitializeEncoder(d.encoder, &init);
    if (status != NV_ENC_SUCCESS) {
        error = nvError(&d.api, d.encoder, status);
        d.cleanup();
        return false;
    }

    NV_ENC_CREATE_BITSTREAM_BUFFER bitstream{};
    bitstream.version = NV_ENC_CREATE_BITSTREAM_BUFFER_VER;
    status = d.api.nvEncCreateBitstreamBuffer(d.encoder, &bitstream);
    if (status != NV_ENC_SUCCESS) {
        error = nvError(&d.api, d.encoder, status);
        d.cleanup();
        return false;
    }
    d.bitstream = bitstream.bitstreamBuffer;

    d.event = CreateEventA(nullptr, FALSE, FALSE, nullptr);
    if (d.event == nullptr) {
        error = "CreateEvent failed";
        d.cleanup();
        return false;
    }
    NV_ENC_EVENT_PARAMS eventParams{};
    eventParams.version = NV_ENC_EVENT_PARAMS_VER;
    eventParams.completionEvent = d.event;
    status = d.api.nvEncRegisterAsyncEvent(d.encoder, &eventParams);
    if (status != NV_ENC_SUCCESS) {
        error = nvError(&d.api, d.encoder, status);
        d.cleanup();
        return false;
    }
    if (!d.createInputTexture(error)) {
        d.cleanup();
        return false;
    }
    ready_ = true;
    return true;
}

bool NvencEncoder::encode(
    ID3D11Texture2D* source, uint64_t timestampNs, bool forceIDR,
    EncodedAccessUnit& output, std::string& error) {
    if (!ready_ || source == nullptr) {
        error = "NVENC not ready";
        return false;
    }
    auto& d = *impl_;
    d.context->CopyResource(d.inputTexture, source);
    d.context->Flush();

    NV_ENC_MAP_INPUT_RESOURCE map{};
    map.version = NV_ENC_MAP_INPUT_RESOURCE_VER;
    map.registeredResource = d.registered;
    NVENCSTATUS status = d.api.nvEncMapInputResource(d.encoder, &map);
    if (status != NV_ENC_SUCCESS) {
        error = nvError(&d.api, d.encoder, status);
        return false;
    }

    NV_ENC_PIC_PARAMS params{};
    params.version = NV_ENC_PIC_PARAMS_VER;
    params.inputBuffer = map.mappedResource;
    params.bufferFmt = NV_ENC_BUFFER_FORMAT_ABGR;
    params.inputWidth = d.width;
    params.inputHeight = d.height;
    params.inputPitch = d.width * 4;
    params.outputBitstream = d.bitstream;
    params.completionEvent = d.event;
    params.inputTimeStamp = timestampNs;
    params.pictureStruct = NV_ENC_PIC_STRUCT_FRAME;
    params.frameIdx = static_cast<uint32_t>(d.frameIndex);
    if (forceIDR) params.encodePicFlags |= NV_ENC_PIC_FLAG_FORCEIDR;

    status = d.api.nvEncEncodePicture(d.encoder, &params);
    if (status != NV_ENC_SUCCESS) {
        d.api.nvEncUnmapInputResource(d.encoder, map.mappedResource);
        error = nvError(&d.api, d.encoder, status);
        return false;
    }
    d.api.nvEncUnmapInputResource(d.encoder, map.mappedResource);
    WaitForSingleObject(d.event, 1000);

    NV_ENC_LOCK_BITSTREAM lock{};
    lock.version = NV_ENC_LOCK_BITSTREAM_VER;
    lock.outputBitstream = d.bitstream;
    lock.doNotWait = 0;
    status = d.api.nvEncLockBitstream(d.encoder, &lock);
    if (status != NV_ENC_SUCCESS) {
        error = nvError(&d.api, d.encoder, status);
        return false;
    }
    output.data.assign(
        static_cast<const uint8_t*>(lock.bitstreamBufferPtr),
        static_cast<const uint8_t*>(lock.bitstreamBufferPtr) + lock.bitstreamSizeInBytes);
    output.keyframe = lock.pictureType == NV_ENC_PIC_TYPE_IDR || lock.pictureType == NV_ENC_PIC_TYPE_I;
    output.timestampNs = timestampNs;
    output.frameIndex = d.frameIndex++;
    d.api.nvEncUnlockBitstream(d.encoder, d.bitstream);
    return true;
}

void NvencEncoder::shutdown() {
    ready_ = false;
    if (impl_) impl_->cleanup();
}

} // namespace vrmc
