// VRMC virtual SteamVR driver.
//
// This driver exposes a display-less (but display-component-bearing) HMD and two
// Index-style controllers. It does not capture frames; Vivecraft's DUAL mirror is
// captured by vrmc_host. Tracking and input arrive through the versioned shared-memory
// IPC snapshot. Everything here is deliberately small and policy-free.

#include "openvr_driver.h"
#include "vrmc/ipc.hpp"
#include "vrmc/protocol.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>

#if defined(_WIN32)
#define VRMC_EXPORT extern "C" __declspec(dllexport)
#else
#define VRMC_EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {
using Clock = std::chrono::steady_clock;

void Log(const char* format, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    if (vr::VRDriverLog() != nullptr) {
        vr::VRDriverLog()->Log(buffer);
    }
}

vr::HmdQuaternion_t toHmdQuat(const vrmc::Quat& q) {
    vr::HmdQuaternion_t out{};
    out.w = q.w; out.x = q.x; out.y = q.y; out.z = q.z;
    return out;
}

vr::DriverPose_t makePose(const vrmc::Pose& pose, uint8_t quality, bool hmde) {
    vr::DriverPose_t out{};
    out.qWorldFromDriverRotation.w = 1;
    out.qDriverFromHeadRotation.w = 1;
    out.qRotation = toHmdQuat(pose.orientation);
    out.vecPosition[0] = pose.position.x;
    out.vecPosition[1] = pose.position.y;
    out.vecPosition[2] = pose.position.z;
    out.poseIsValid = quality != 0;
    out.deviceIsConnected = true;
    out.result = quality != 0 ? vr::TrackingResult_Running_OK : vr::TrackingResult_Running_OutOfRange;
    out.shouldApplyHeadModel = false;
    out.willDriftInYaw = false;
    (void)hmde;
    return out;
}

class HmdDisplayComponent final : public vr::IVRDisplayComponent {
public:
    void GetWindowBounds(int32_t* x, int32_t* y, uint32_t* width, uint32_t* height) override {
        *x = 0; *y = 0; *width = 1280; *height = 720;
    }
    bool IsDisplayOnDesktop() override { return true; }
    bool IsDisplayRealDisplay() override { return false; }
    void GetRecommendedRenderTargetSize(uint32_t* width, uint32_t* height) override {
        *width = 1920; *height = 1080;
    }
    void GetEyeOutputViewport(vr::EVREye eye, uint32_t* x, uint32_t* y, uint32_t* width, uint32_t* height) override {
        *y = 0; *width = 640; *height = 720;
        *x = eye == vr::Eye_Left ? 0 : 640;
    }
    void GetProjectionRaw(vr::EVREye, float* left, float* right, float* top, float* bottom) override {
        constexpr float kTan50 = 1.1917536f;
        constexpr float kTan45 = 1.0f;
        *left = -kTan50; *right = kTan50; *top = kTan45; *bottom = -kTan45;
    }
    vr::DistortionCoordinates_t ComputeDistortion(vr::EVREye, float u, float v) override {
        vr::DistortionCoordinates_t out{};
        out.rfRed[0] = out.rfGreen[0] = out.rfBlue[0] = u;
        out.rfRed[1] = out.rfGreen[1] = out.rfBlue[1] = v;
        return out;
    }
    bool ComputeInverseDistortion(vr::HmdVector2_t*, vr::EVREye, uint32_t, float, float) override {
        return false;
    }
};

class HmdDevice final : public vr::ITrackedDeviceServerDriver {
public:
    explicit HmdDevice(std::string serial) : serial_(std::move(serial)) {}

    vr::EVRInitError Activate(uint32_t objectId) override {
        objectId_ = objectId;
        active_ = true;
        auto container = vr::VRProperties()->TrackedDeviceToPropertyContainer(objectId_);
        vr::VRProperties()->SetStringProperty(container, vr::Prop_ModelNumber_String, "VRMC Virtual HMD");
        vr::VRProperties()->SetStringProperty(container, vr::Prop_SerialNumber_String, serial_.c_str());
        vr::VRProperties()->SetStringProperty(container, vr::Prop_ManufacturerName_String, "VRMC");
        vr::VRProperties()->SetStringProperty(container, vr::Prop_TrackingSystemName_String, "vrmc");
        vr::VRProperties()->SetFloatProperty(container, vr::Prop_DisplayFrequency_Float, 90.0f);
        vr::VRProperties()->SetFloatProperty(container, vr::Prop_UserIpdMeters_Float, 0.064f);
        vr::VRProperties()->SetFloatProperty(container, vr::Prop_UserHeadToEyeDepthMeters_Float, 0.0f);
        vr::VRProperties()->SetFloatProperty(container, vr::Prop_SecondsFromVsyncToPhotons_Float, 0.011111f);
        vr::VRProperties()->SetBoolProperty(container, vr::Prop_IsOnDesktop_Bool, false);
        vr::VRProperties()->SetBoolProperty(container, vr::Prop_DisplayDebugMode_Bool, true);
        Log("VRMC HMD active (serial %s)", serial_.c_str());
        return vr::VRInitError_None;
    }
    void Deactivate() override { active_ = false; objectId_ = vr::k_unTrackedDeviceIndexInvalid; }
    void EnterStandby() override {}
    void* GetComponent(const char* nameAndVersion) override {
        if (std::strcmp(nameAndVersion, vr::IVRDisplayComponent_Version) == 0) return &display_;
        return nullptr;
    }
    void DebugRequest(const char*, char* response, uint32_t size) override {
        if (size > 0) response[0] = '\0';
    }
    vr::DriverPose_t GetPose() override { return makePose(snapshot_.hmd, snapshot_.hmdQuality, true); }

    void Update(const vrmc::IpcSnapshot& snapshot) { snapshot_ = snapshot; }
    void UpdateInvalid() {
        snapshot_.hmdQuality = 0;
        snapshot_.hmd.orientation = {0, 0, 0, 1};
    }
    void Run() {
        if (!active_ || objectId_ == vr::k_unTrackedDeviceIndexInvalid) return;
        auto pose = makePose(snapshot_.hmd, snapshot_.hmdQuality, true);
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(objectId_, pose, sizeof(pose));
    }
    const std::string& serial() const { return serial_; }

private:
    std::string serial_;
    HmdDisplayComponent display_;
    vrmc::IpcSnapshot snapshot_{};
    std::atomic<bool> active_{false};
    uint32_t objectId_ = vr::k_unTrackedDeviceIndexInvalid;
};

class ControllerDevice final : public vr::ITrackedDeviceServerDriver {
public:
    ControllerDevice(vr::ETrackedControllerRole role, std::string serial)
        : role_(role), serial_(std::move(serial)) {}

    vr::EVRInitError Activate(uint32_t objectId) override {
        objectId_ = objectId;
        active_ = true;
        auto container = vr::VRProperties()->TrackedDeviceToPropertyContainer(objectId_);
        auto hand = role_ == vr::TrackedControllerRole_LeftHand ? "Left" : "Right";
        vr::VRProperties()->SetStringProperty(container, vr::Prop_ModelNumber_String, "VRMC Knuckles");
        vr::VRProperties()->SetStringProperty(container, vr::Prop_SerialNumber_String, serial_.c_str());
        vr::VRProperties()->SetStringProperty(container, vr::Prop_ManufacturerName_String, "VRMC");
        vr::VRProperties()->SetStringProperty(container, vr::Prop_TrackingSystemName_String, "vrmc");
        vr::VRProperties()->SetInt32Property(container, vr::Prop_ControllerRoleHint_Int32, role_);
        vr::VRProperties()->SetStringProperty(container, vr::Prop_ControllerType_String, "knuckles");
        vr::VRProperties()->SetStringProperty(container, vr::Prop_InputProfilePath_String,
                                               "{vrmc}/input/vrmc_knuckles_profile.json");

        vr::VRDriverInput()->CreateScalarComponent(container, "/input/trigger/value", &handles_[TriggerValue],
                                                   vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/trigger/click", &handles_[TriggerClick]);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/trigger/touch", &handles_[TriggerTouch]);
        vr::VRDriverInput()->CreateScalarComponent(container, "/input/grip/value", &handles_[GripValue],
                                                   vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/grip/click", &handles_[GripClick]);
        vr::VRDriverInput()->CreateScalarComponent(container, "/input/thumbstick/x", &handles_[StickX],
                                                   vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
        vr::VRDriverInput()->CreateScalarComponent(container, "/input/thumbstick/y", &handles_[StickY],
                                                   vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/thumbstick/click", &handles_[StickClick]);
        vr::VRDriverInput()->CreateScalarComponent(container, "/input/trackpad/x", &handles_[TrackpadX],
                                                   vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
        vr::VRDriverInput()->CreateScalarComponent(container, "/input/trackpad/y", &handles_[TrackpadY],
                                                   vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/trackpad/click", &handles_[TrackpadClick]);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/trackpad/touch", &handles_[TrackpadTouch]);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/a/click", &handles_[AClick]);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/a/touch", &handles_[ATouch]);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/b/click", &handles_[BClick]);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/b/touch", &handles_[BTouch]);
        vr::VRDriverInput()->CreateBooleanComponent(container, "/input/system/click", &handles_[SystemClick]);
        vr::VRDriverInput()->CreateHapticComponent(container, "/output/haptic", &handles_[Haptic]);
        Log("VRMC %s controller active (serial %s)", hand, serial_.c_str());
        return vr::VRInitError_None;
    }
    void Deactivate() override { active_ = false; objectId_ = vr::k_unTrackedDeviceIndexInvalid; }
    void EnterStandby() override {}
    void* GetComponent(const char*) override { return nullptr; }
    void DebugRequest(const char*, char* response, uint32_t size) override {
        if (size > 0) response[0] = '\0';
    }
    vr::DriverPose_t GetPose() override { return makePose(state_.pose, state_.quality, false); }

    void Update(const vrmc::ControllerIpc& state) { state_ = state; }
    void UpdateInvalid() {
        state_.quality = 0;
        state_.buttons = 0;
        state_.trigger = state_.grip = 0;
        state_.stickX = state_.stickY = state_.trackpadX = state_.trackpadY = 0;
    }
    void Run() {
        if (!active_ || objectId_ == vr::k_unTrackedDeviceIndexInvalid) return;
        const auto& s = state_;
        auto boolButton = [&](uint32_t bit) { return (s.buttons & bit) != 0; };
        vr::VRDriverInput()->UpdateScalarComponent(handles_[TriggerValue], std::clamp(s.trigger, 0.0f, 1.0f), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[TriggerClick], boolButton(1u << 0), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[TriggerTouch], boolButton(1u << 8) || s.trigger > 0.1f, 0.0);
        vr::VRDriverInput()->UpdateScalarComponent(handles_[GripValue], std::clamp(s.grip, 0.0f, 1.0f), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[GripClick], boolButton(1u << 1), 0.0);
        vr::VRDriverInput()->UpdateScalarComponent(handles_[StickX], std::clamp(s.stickX, -1.0f, 1.0f), 0.0);
        vr::VRDriverInput()->UpdateScalarComponent(handles_[StickY], std::clamp(s.stickY, -1.0f, 1.0f), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[StickClick], boolButton(1u << 5), 0.0);
        vr::VRDriverInput()->UpdateScalarComponent(handles_[TrackpadX], std::clamp(s.trackpadX, -1.0f, 1.0f), 0.0);
        vr::VRDriverInput()->UpdateScalarComponent(handles_[TrackpadY], std::clamp(s.trackpadY, -1.0f, 1.0f), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[TrackpadClick], boolButton(1u << 6), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[TrackpadTouch], boolButton(1u << 7), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[AClick], boolButton(1u << 2), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[ATouch], boolButton(1u << 2), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[BClick], boolButton(1u << 3), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[BTouch], boolButton(1u << 3), 0.0);
        vr::VRDriverInput()->UpdateBooleanComponent(handles_[SystemClick], boolButton(1u << 4), 0.0);
        auto pose = makePose(s.pose, s.quality, false);
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(objectId_, pose, sizeof(pose));
    }
    const std::string& serial() const { return serial_; }

private:
    enum Handle {
        TriggerValue, TriggerClick, TriggerTouch,
        GripValue, GripClick,
        StickX, StickY, StickClick,
        TrackpadX, TrackpadY, TrackpadClick, TrackpadTouch,
        AClick, ATouch, BClick, BTouch, SystemClick, Haptic,
        HandleCount
    };
    vr::ETrackedControllerRole role_;
    std::string serial_;
    vrmc::ControllerIpc state_{};
    vr::VRInputComponentHandle_t handles_[HandleCount]{};
    std::atomic<bool> active_{false};
    uint32_t objectId_ = vr::k_unTrackedDeviceIndexInvalid;
};

class DeviceProvider final : public vr::IServerTrackedDeviceProvider {
public:
    vr::EVRInitError Init(vr::IVRDriverContext* context) override {
        VR_INIT_SERVER_DRIVER_CONTEXT(context);
        Log("VRMC driver initializing");
        hmd_ = std::make_unique<HmdDevice>("VRMC-HMD-001");
        left_ = std::make_unique<ControllerDevice>(vr::TrackedControllerRole_LeftHand, "VRMC-L-001");
        right_ = std::make_unique<ControllerDevice>(vr::TrackedControllerRole_RightHand, "VRMC-R-001");

        if (!vr::VRServerDriverHost()->TrackedDeviceAdded(hmd_->serial().c_str(), vr::TrackedDeviceClass_HMD, hmd_.get())) {
            Log("Failed to add HMD");
            return vr::VRInitError_Driver_Unknown;
        }
        if (!vr::VRServerDriverHost()->TrackedDeviceAdded(left_->serial().c_str(), vr::TrackedDeviceClass_Controller, left_.get()) ||
            !vr::VRServerDriverHost()->TrackedDeviceAdded(right_->serial().c_str(), vr::TrackedDeviceClass_Controller, right_.get())) {
            Log("Failed to add controllers");
            return vr::VRInitError_Driver_Unknown;
        }
        EnsureReader();
        lastRead_ = Clock::now();
        return vr::VRInitError_None;
    }

    void Cleanup() override {
        hmd_.reset();
        left_.reset();
        right_.reset();
        reader_.reset();
    }
    const char* const* GetInterfaceVersions() override { return vr::k_InterfaceVersions; }
    bool ShouldBlockStandbyMode() override { return false; }
    void EnterStandby() override {}
    void LeaveStandby() override {}
    void RunFrame() override {
        if (!reader_ || !reader_->valid()) {
            EnsureReader();
        }
        bool valid = false;
        if (reader_ && reader_->valid()) {
            vrmc::IpcSnapshot snapshot{};
            if (reader_->read(snapshot)) {
                hmd_->Update(snapshot);
                left_->Update(snapshot.left);
                right_->Update(snapshot.right);
                lastRead_ = Clock::now();
                valid = true;
            }
        }
        if (!valid && std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - lastRead_).count() > 250) {
            if (hmd_) hmd_->UpdateInvalid();
            if (left_) left_->UpdateInvalid();
            if (right_) right_->UpdateInvalid();
        }
        if (hmd_) hmd_->Run();
        if (left_) left_->Run();
        if (right_) right_->Run();
    }

private:
    void EnsureReader() {
        if (reader_ && reader_->valid()) return;
        reader_ = std::make_unique<vrmc::IpcReader>(vrmc::kIpcName);
    }
    std::unique_ptr<HmdDevice> hmd_;
    std::unique_ptr<ControllerDevice> left_;
    std::unique_ptr<ControllerDevice> right_;
    std::unique_ptr<vrmc::IpcReader> reader_;
    Clock::time_point lastRead_ = Clock::now();
};

DeviceProvider g_provider;
} // namespace

VRMC_EXPORT void* HmdDriverFactory(const char* interfaceName, int* returnCode) {
    if (std::strcmp(interfaceName, vr::IServerTrackedDeviceProvider_Version) == 0) {
        return &g_provider;
    }
    if (returnCode != nullptr) {
        *returnCode = vr::VRInitError_Init_InterfaceNotFound;
    }
    return nullptr;
}
