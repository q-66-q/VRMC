// VRMC Windows host: control plane, input-to-IPC bridge, and low-latency video sender.
//
// IMPORTANT: this target is compiled and tested on Windows only. The source is part of the
// M3 gate and must be exercised with SteamVR + Vivecraft before it can be called verified.

#include "file_source.hpp"
#include "nvenc_encoder.hpp"
#include "win_capture.hpp"
#include "vrmc/ipc.hpp"
#include "vrmc/protocol.hpp"

#include <Windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <condition_variable>
#include <iterator>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "ws2_32.lib")

namespace {
using namespace std::chrono_literals;
std::atomic<bool> g_running{true};

uint64_t nowNs() {
    static LARGE_INTEGER frequency{};
    static std::once_flag flag;
    std::call_once(flag, [] { QueryPerformanceFrequency(&frequency); });
    LARGE_INTEGER counter{};
    QueryPerformanceCounter(&counter);
    return static_cast<uint64_t>((static_cast<double>(counter.QuadPart) * 1e9) / frequency.QuadPart);
}

BOOL WINAPI consoleHandler(DWORD type) {
    if (type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT || type == CTRL_CLOSE_EVENT) {
        g_running = false;
        return TRUE;
    }
    return FALSE;
}

void logLine(const char* format, ...) {
    va_list args;
    va_start(args, format);
    std::vprintf(format, args);
    std::printf("\n");
    std::fflush(stdout);
    va_end(args);
}

bool sendAll(SOCKET socket, const void* data, size_t size) {
    const auto* bytes = static_cast<const uint8_t*>(data);
    while (size > 0) {
        int sent = send(socket, reinterpret_cast<const char*>(bytes), static_cast<int>(size), 0);
        if (sent <= 0) return false;
        bytes += sent;
        size -= static_cast<size_t>(sent);
    }
    return true;
}

bool recvExact(SOCKET socket, void* data, size_t size) {
    auto* bytes = static_cast<uint8_t*>(data);
    while (size > 0) {
        int received = recv(socket, reinterpret_cast<char*>(bytes), static_cast<int>(size), 0);
        if (received <= 0) return false;
        bytes += received;
        size -= static_cast<size_t>(received);
    }
    return true;
}

std::wstring widen(const std::string& value) {
    if (value.empty()) return {};
    int length = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
    std::wstring result(static_cast<size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), length);
    if (!result.empty() && result.back() == L'\0') result.pop_back();
    return result;
}

struct FindWindowData {
    std::wstring title;
    HWND result = nullptr;
};

BOOL CALLBACK enumWindows(HWND window, LPARAM pointer) {
    auto* data = reinterpret_cast<FindWindowData*>(pointer);
    if (!IsWindowVisible(window)) return TRUE;
    wchar_t title[512]{};
    GetWindowTextW(window, title, static_cast<int>(std::size(title)));
    if (data->title.empty() || std::wstring(title).find(data->title) != std::wstring::npos) {
        data->result = window;
        return FALSE;
    }
    return TRUE;
}

HWND findWindow(const std::string& title) {
    FindWindowData data{widen(title), nullptr};
    EnumWindows(enumWindows, reinterpret_cast<LPARAM>(&data));
    return data.result;
}

struct Options {
    std::string bindHost = "0.0.0.0";
    uint16_t controlPort = 48625;
    uint16_t mediaPort = 48626;
    uint16_t inputPort = 48627;
    std::string windowTitle = "Minecraft";
    std::string videoFile;
    uint32_t fps = 90;
    uint32_t bitrateKbps = 90000;
    uint32_t width = 3840;
    uint32_t height = 1080;
    bool hevc = true;
};

Options parseOptions(int argc, char** argv) {
    Options options;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        auto next = [&](std::string& target) { if (i + 1 < argc) target = argv[++i]; };
        if (arg == "--batch") { /* accepted for scripts; no window/console assumptions */ }
        else if (arg == "--host") next(options.bindHost);
        else if (arg == "--control-port") options.controlPort = static_cast<uint16_t>(std::stoi(argv[++i]));
        else if (arg == "--media-port") options.mediaPort = static_cast<uint16_t>(std::stoi(argv[++i]));
        else if (arg == "--input-port") options.inputPort = static_cast<uint16_t>(std::stoi(argv[++i]));
        else if (arg == "--window-title") next(options.windowTitle);
        else if (arg == "--video") next(options.videoFile);
        else if (arg == "--fps") options.fps = static_cast<uint32_t>(std::stoi(argv[++i]));
        else if (arg == "--bitrate") options.bitrateKbps = static_cast<uint32_t>(std::stoi(argv[++i]));
        else if (arg == "--width") options.width = static_cast<uint32_t>(std::stoi(argv[++i]));
        else if (arg == "--height") options.height = static_cast<uint32_t>(std::stoi(argv[++i]));
        else if (arg == "--h264") options.hevc = false;
        else if (arg == "--help") {
            std::printf("vrmc_host [--host IP] [--control-port N] [--media-port N] [--input-port N]\n"
                        "          [--window-title TEXT] [--video FILE] [--fps N] [--bitrate KBPS]\n"
                        "          [--width N] [--height N] [--h264]\n");
            std::exit(0);
        }
    }
    return options;
}

class SharedState {
public:
    vrmc::IpcSnapshot snapshot;
    std::mutex mutex;
    uint64_t clientHeadTimestampNs = 0;
    uint32_t lastVideoFrameId = 0;
};

class VideoQueue {
public:
    void push(vrmc::EncodedAccessUnit unit) {
        std::lock_guard lock(mutex_);
        if (queue_.size() >= 2) queue_.pop_front();
        queue_.push_back(std::move(unit));
        cv_.notify_one();
    }
    bool pop(vrmc::EncodedAccessUnit& unit, std::atomic<bool>& running) {
        std::unique_lock lock(mutex_);
        cv_.wait_for(lock, 100ms, [&] { return !queue_.empty() || !running; });
        if (!running || queue_.empty()) return false;
        unit = std::move(queue_.front());
        queue_.pop_front();
        return true;
    }
    void clear() {
        std::lock_guard lock(mutex_);
        queue_.clear();
    }

private:
    std::mutex mutex_;
    std::condition_variable cv_;
    std::deque<vrmc::EncodedAccessUnit> queue_;
};

class Host {
public:
    Host(Options options, SharedState& state, VideoQueue& video)
        : options_(std::move(options)), state_(state), video_(video) {}
    ~Host() { stop(); }

    bool start() {
        if (!initializeSockets()) return false;
        if (!ipc_.valid()) {
            logLine("FATAL: cannot create shared memory %s", vrmc::kIpcName);
            return false;
        }
        if (!startVideo()) return false;
        controlThread_ = std::thread([this] { controlLoop(); });
        inputThread_ = std::thread([this] { inputLoop(); });
        senderThread_ = std::thread([this] { senderLoop(); });
        logLine("host ready: control=%u media=%u input=%u", options_.controlPort, options_.mediaPort, options_.inputPort);
        return true;
    }

    void stop() {
        g_running = false;
        if (socket_ != INVALID_SOCKET) closesocket(socket_);
        if (inputSocket_ != INVALID_SOCKET) closesocket(inputSocket_);
        if (controlThread_.joinable()) controlThread_.join();
        if (inputThread_.joinable()) inputThread_.join();
        if (senderThread_.joinable()) senderThread_.join();
        capture_.stop();
        encoder_.shutdown();
        if (videoThread_.joinable()) videoThread_.join();
        WSACleanup();
    }

private:
    bool initializeSockets() {
        WSADATA data{};
        if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
            logLine("FATAL: WSAStartup failed");
            return false;
        }
        socket_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        inputSocket_ = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (socket_ == INVALID_SOCKET || inputSocket_ == INVALID_SOCKET) {
            logLine("FATAL: socket creation failed");
            return false;
        }
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_port = htons(options_.controlPort);
        inet_pton(AF_INET, options_.bindHost.c_str(), &address.sin_addr);
        if (bind(socket_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
            logLine("FATAL: control bind failed (%d)", WSAGetLastError());
            return false;
        }
        if (listen(socket_, 1) != 0) {
            logLine("FATAL: listen failed");
            return false;
        }
        sockaddr_in inputAddress{};
        inputAddress.sin_family = AF_INET;
        inputAddress.sin_port = htons(options_.inputPort);
        inet_pton(AF_INET, options_.bindHost.c_str(), &inputAddress.sin_addr);
        if (bind(inputSocket_, reinterpret_cast<sockaddr*>(&inputAddress), sizeof(inputAddress)) != 0) {
            logLine("FATAL: input bind failed (%d)", WSAGetLastError());
            return false;
        }
        u_long nonBlocking = 1;
        ioctlsocket(inputSocket_, FIONBIO, &nonBlocking);
        return true;
    }

    bool startVideo() {
        if (!options_.videoFile.empty()) {
            std::string error;
            if (!fileSource_.open(options_.videoFile, options_.fps, error)) {
                logLine("FATAL: %s", error.c_str());
                return false;
            }
            videoThread_ = std::thread([this] { fileVideoLoop(); });
            logLine("video source: file %s", options_.videoFile.c_str());
            return true;
        }

        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        HWND window = findWindow(options_.windowTitle);
        if (window == nullptr) {
            logLine("FATAL: window '%s' not found. Start Vivecraft and set the DUAL mirror window.",
                    options_.windowTitle.c_str());
            return false;
        }
        std::string error;
        if (!capture_.initialize(error)) {
            logLine("FATAL: capture init: %s", error.c_str());
            return false;
        }
        if (!capture_.start(window, [this](ID3D11Texture2D* texture, uint64_t timestamp) {
                onCapturedFrame(texture, timestamp);
            }, error)) {
            logLine("FATAL: capture start: %s", error.c_str());
            return false;
        }
        options_.width = capture_.width();
        options_.height = capture_.height();
        if (!encoder_.initialize(capture_.device(), capture_.context(), capture_.width(), capture_.height(),
                                 options_.fps, options_.bitrateKbps, options_.hevc, error)) {
            logLine("FATAL: NVENC init: %s", error.c_str());
            return false;
        }
        logLine("video source: WGC window '%s' %ux%u", options_.windowTitle.c_str(), capture_.width(), capture_.height());
        return true;
    }

    void onCapturedFrame(ID3D11Texture2D* texture, uint64_t timestamp) {
        if (!g_running) return;
        vrmc::EncodedAccessUnit unit;
        std::string error;
        const bool force = forceIDR_.exchange(false);
        if (!encoder_.encode(texture, timestamp, force, unit, error)) {
            logLine("encode error: %s", error.c_str());
            return;
        }
        unit.timestampNs = timestamp;
        video_.push(std::move(unit));
    }

    void fileVideoLoop() {
        const auto interval = std::chrono::microseconds(1'000'000 / std::max<uint32_t>(options_.fps, 1));
        auto next = std::chrono::steady_clock::now();
        while (g_running) {
            vrmc::EncodedAccessUnit unit;
            if (!fileSource_.next(unit)) break;
            unit.timestampNs = nowNs();
            video_.push(std::move(unit));
            next += interval;
            std::this_thread::sleep_until(next);
        }
    }

    void controlLoop() {
        while (g_running) {
            SOCKET client = accept(socket_, nullptr, nullptr);
            if (client == INVALID_SOCKET) {
                std::this_thread::sleep_for(100ms);
                continue;
            }
            logLine("control client connected");
            controlClient_ = client;
            handleControl(client);
            controlClient_ = INVALID_SOCKET;
            closesocket(client);
            logLine("control client disconnected");
        }
    }

    bool sendControl(SOCKET client, vrmc::MessageType type, const std::vector<uint8_t>& frame) {
        (void)type;
        return sendAll(client, frame.data(), frame.size());
    }

    void handleControl(SOCKET client) {
        try {
            uint8_t headerBytes[vrmc::kControlHeaderSize];
            if (!recvExact(client, headerBytes, sizeof(headerBytes))) return;
            auto header = vrmc::decodeControlHeader(std::span<const uint8_t>(headerBytes, sizeof(headerBytes)));
            if (!header || header->type != vrmc::MessageType::Hello) return;
            std::vector<uint8_t> payload(header->payloadLength);
            if (!payload.empty() && !recvExact(client, payload.data(), payload.size())) return;
            auto hello = vrmc::decodeHello(payload);
            if (!hello) return;
            sessionId_ = static_cast<uint32_t>(nowNs() & 0x7FFFFFFF) | 1;
            logLine("HELLO %s %s auth=%u", hello->clientPlatform.c_str(), hello->clientVersion.c_str(), hello->authMode);
            sendControl(client, vrmc::MessageType::Welcome, vrmc::encodeWelcome(sessionId_));
            sendControl(client, vrmc::MessageType::AuthOK, vrmc::encodeAuthOK(sessionId_));

            vrmc::StreamConfig config;
            config.videoWidth = static_cast<uint16_t>(std::min<uint32_t>(options_.width, UINT16_MAX));
            config.videoHeight = static_cast<uint16_t>(std::min<uint32_t>(options_.height, UINT16_MAX));
            config.eyeWidth = static_cast<uint16_t>(config.videoWidth / 2);
            config.eyeHeight = config.videoHeight;
            config.fps = static_cast<uint16_t>(std::min<uint32_t>(options_.fps, UINT16_MAX));
            config.displayHz = 90;
            config.bitrateKbps = options_.bitrateKbps;
            config.codec = options_.hevc ? 2 : 1;
            config.flags = 1; // reprojection enabled
            config.source = options_.videoFile.empty() ? "Vivecraft DUAL (WGC)" : "VRMC file source";
            sendControl(client, vrmc::MessageType::StreamConfig, vrmc::encodeStreamConfig(config, sessionId_));
            sendControl(client, vrmc::MessageType::StartStream, vrmc::encodeStartStream(sessionId_, nowNs()));

            while (g_running) {
                if (!recvExact(client, headerBytes, sizeof(headerBytes))) break;
                auto incoming = vrmc::decodeControlHeader(std::span<const uint8_t>(headerBytes, sizeof(headerBytes)));
                if (!incoming) break;
                std::vector<uint8_t> body(incoming->payloadLength);
                if (!body.empty() && !recvExact(client, body.data(), body.size())) break;
                switch (incoming->type) {
                case vrmc::MessageType::ClockPing: {
                    auto ping = vrmc::decodeClockPing(body);
                    if (ping) {
                        const uint64_t t1 = nowNs();
                        const uint64_t t2 = nowNs();
                        sendControl(client, vrmc::MessageType::ClockPong,
                                    vrmc::encodeClockPong(sessionId_, ping->first, t1, t2, ping->second));
                    }
                    break;
                }
                case vrmc::MessageType::SessionState: {
                    auto state = vrmc::decodeSessionState(body);
                    if (state) logLine("session state phase=%u detail=%s", std::get<0>(*state), std::get<3>(*state).c_str());
                    break;
                }
                case vrmc::MessageType::KeyframeRequest:
                    forceIDR_ = true;
                    break;
                case vrmc::MessageType::Disconnect:
                    return;
                default:
                    break;
                }
            }
        } catch (...) {
            logLine("control exception");
        }
    }

    void inputLoop() {
        uint8_t buffer[65535];
        auto lastPacket = std::chrono::steady_clock::now();
        bool markedInvalid = false;
        while (g_running) {
            sockaddr_in from{};
            int fromLength = sizeof(from);
            int count = recvfrom(inputSocket_, reinterpret_cast<char*>(buffer), sizeof(buffer), 0,
                                 reinterpret_cast<sockaddr*>(&from), &fromLength);
            const auto now = std::chrono::steady_clock::now();
            if (now - lastPacket > 500ms) {
                if (!markedInvalid) {
                    std::lock_guard lock(state_.mutex);
                    state_.snapshot.hmdQuality = 0;
                    state_.snapshot.left.quality = 0;
                    state_.snapshot.right.quality = 0;
                    state_.snapshot.left.buttons = 0;
                    state_.snapshot.right.buttons = 0;
                    state_.snapshot.left.trigger = state_.snapshot.left.grip = 0;
                    state_.snapshot.right.trigger = state_.snapshot.right.grip = 0;
                    state_.snapshot.hostTimeNs = nowNs();
                    ipc_.write(state_.snapshot);
                    markedInvalid = true;
                }
            }
            if (count <= 0) {
                std::this_thread::sleep_for(2ms);
                continue;
            }
            lastPacket = now;
            markedInvalid = false;
            auto header = vrmc::decodeMediaHeader(std::span<const uint8_t>(buffer, static_cast<size_t>(count)));
            if (!header || header->type != vrmc::MediaType::Input) continue;
            if (header->payloadLength > static_cast<uint16_t>(count - vrmc::kMediaHeaderSize)) continue;
            std::span<const uint8_t> payload(buffer + vrmc::kMediaHeaderSize, header->payloadLength);
            std::lock_guard lock(state_.mutex);
            if (auto head = vrmc::decodeHead(payload)) {
                state_.snapshot.hmd = head->pose;
                state_.snapshot.hmdQuality = head->quality;
                state_.snapshot.clientHeadTimestampNs = header->timestampNs;
                state_.clientHeadTimestampNs = header->timestampNs;
                state_.snapshot.hostTimeNs = nowNs();
            } else if (auto intent = vrmc::decodeIntent(payload)) {
                auto& controller = intent->hand == 0 ? state_.snapshot.left : state_.snapshot.right;
                controller.pose = intent->pose;
                controller.quality = intent->quality;
                controller.buttons = intent->buttons;
                controller.trigger = intent->trigger;
                controller.grip = intent->grip;
                controller.stickX = intent->stickX;
                controller.stickY = intent->stickY;
                controller.trackpadX = intent->trackpadX;
                controller.trackpadY = intent->trackpadY;
                state_.snapshot.hostTimeNs = nowNs();
            } else {
                continue;
            }
            clientAddress_ = from;
            hasClient_ = true;
            ipc_.write(state_.snapshot);
        }
    }

    void senderLoop() {
        while (g_running) {
            vrmc::EncodedAccessUnit unit;
            if (!video_.pop(unit, g_running)) continue;
            sockaddr_in target{};
            bool ready = false;
            {
                std::lock_guard lock(state_.mutex);
                target = clientAddress_;
                ready = hasClient_;
            }
            if (!ready) continue;
            SOCKET udp = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
            if (udp == INVALID_SOCKET) continue;
            const uint32_t frameId = ++state_.lastVideoFrameId;
            vrmc::FrameMeta meta;
            meta.frameId = frameId;
            meta.captureHeadPosition = state_.snapshot.hmd.position;
            meta.captureHeadOrientation = state_.snapshot.hmd.orientation;
            meta.clientHeadTimestampNs = state_.clientHeadTimestampNs;
            meta.sourceFrameNumber = unit.frameIndex;
            auto metaPayload = vrmc::encodeFrameMetaPayload(meta);
            for (int copy = 0; copy < 2; ++copy) {
                auto metaDatagram = vrmc::mediaDatagram(
                    vrmc::MediaType::FrameMeta, metaPayload, sessionId_, frameId,
                    packetSequence_++, nowNs(), 0, 1,
                    vrmc::kMediaFlagPlaintext | vrmc::kMediaFlagMetaDuplicate);
                sendto(udp, reinterpret_cast<const char*>(metaDatagram.data()), static_cast<int>(metaDatagram.size()), 0,
                       reinterpret_cast<sockaddr*>(&target), sizeof(target));
            }
            const size_t fragmentCount = (unit.data.size() + vrmc::kMaxMediaPayload - 1) / vrmc::kMaxMediaPayload;
            for (size_t index = 0; index < fragmentCount; ++index) {
                const size_t offset = index * vrmc::kMaxMediaPayload;
                const size_t length = std::min(vrmc::kMaxMediaPayload, unit.data.size() - offset);
                uint8_t flags = vrmc::kMediaFlagPlaintext;
                if (unit.keyframe) flags |= vrmc::kMediaFlagKeyframe;
                if (index == 0) flags |= vrmc::kMediaFlagConfig;
                auto datagram = vrmc::mediaDatagram(
                    vrmc::MediaType::Video, std::span<const uint8_t>(unit.data.data() + offset, length),
                    sessionId_, frameId, packetSequence_++, unit.timestampNs,
                    static_cast<uint16_t>(index), static_cast<uint16_t>(fragmentCount), flags);
                sendto(udp, reinterpret_cast<const char*>(datagram.data()), static_cast<int>(datagram.size()), 0,
                       reinterpret_cast<sockaddr*>(&target), sizeof(target));
            }
            closesocket(udp);
            state_.lastVideoFrameId = frameId;
        }
    }

    Options options_;
    SharedState& state_;
    VideoQueue& video_;
    vrmc::IpcWriter ipc_;
    vrmc::WindowCapture capture_;
    vrmc::NvencEncoder encoder_;
    vrmc::FileVideoSource fileSource_;
    SOCKET socket_ = INVALID_SOCKET;
    SOCKET inputSocket_ = INVALID_SOCKET;
    SOCKET controlClient_ = INVALID_SOCKET;
    std::thread controlThread_;
    std::thread inputThread_;
    std::thread senderThread_;
    std::thread videoThread_;
    std::atomic<bool> forceIDR_{false};
    std::atomic<uint64_t> packetSequence_{0};
    uint32_t sessionId_ = 0;
    sockaddr_in clientAddress_{};
    std::atomic<bool> hasClient_{false};
};
} // namespace

int main(int argc, char** argv) {
    SetConsoleCtrlHandler(consoleHandler, TRUE);
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    Options options = parseOptions(argc, argv);
    SharedState state;
    state.snapshot.magic = vrmc::kIpcMagic;
    state.snapshot.version = vrmc::kIpcVersion;
    VideoQueue video;
    Host host(options, state, video);
    if (!host.start()) {
        host.stop();
        return 1;
    }
    while (g_running) {
        std::this_thread::sleep_for(500ms);
    }
    host.stop();
    return 0;
}
