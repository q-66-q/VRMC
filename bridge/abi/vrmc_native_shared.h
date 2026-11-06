#ifndef VRMC_NATIVE_SHARED_H
#define VRMC_NATIVE_SHARED_H
/*
 * Native-side shared surface between the app process and the VRMC bridge dylib (M3-W2/W3/W4).
 *
 * These entry points are NOT part of the Java ABI contract and do not require an ABI version bump:
 * the Java provider keeps using vrmc_abi.h (v2). They let the visionOS app-side CompositorServices
 * renderer, running in the SAME process as the JVM (Amethyst launches JVM in-process), read the latest
 * per-eye MTLTextures submitted by the provider and push ARKit tracking poses into the bridge so the
 * provider's vrmc_get_tracking returns real device poses instead of the stub.
 *
 * Build as part of libvrmc_bridge; the app resolves these symbols from the same dylib instance the
 * JVM loads (System.load path is shared; the app should dlopen it RTLD_GLOBAL first or link the same
 * install path).
 *
 * Threading model: the provider calls the vrmc_* / vrmc_shared_* publish entry points from the JVM
 * render thread; the CompositorServices renderer calls the read/acquire entry points from its own
 * render thread. Every cross-thread struct copy below is published and read under one bridge-internal
 * mutex, so a reader can never observe a torn frame (e.g. a new left texture with the previous right
 * texture, or a texture handle with a stale signal value).
 */
#include <stdint.h>
#include "vrmc_abi.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------------------------- */
/* GPU frame synchronization + eye-frame handoff (M3-W3/W4 "black immersive" root-cause work).   */
/* ------------------------------------------------------------------------------------------- */
/*
 * The provider (JVM) exports the eye MTLTextures from the game's MoltenVK device; the compositor
 * samples them from a different MTLCommandQueue. Without an explicit dependency that read is a GPU
 * data race: the compositor can sample a frame while the game command buffer is still writing it.
 * (Observed on device: unsynchronized readbacks of the same texture returned mutually impossible
 * snapshots - e.g. left eye bright 120/120/120 while the right eye read 0/0/0 and the right alpha
 * alternated 0/255 between probes of the same frame.)
 *
 * Sync contract (S4a evidence EV-0063 host / EV-0065 device):
 *  1. The provider creates ONE VkSemaphore with VK_SEMAPHORE_TYPE_TIMELINE and a
 *     VkExportMetalObjectCreateInfoEXT{METAL_SHARED_EVENT} in the create-info pNext chain, then
 *     exports its MTLSharedEvent via vkExportMetalObjectsEXT (binary semaphores export nil).
 *  2. The provider signals that timeline semaphore with a monotonically increasing value from the
 *     game's own Vulkan submission after the eye render commands (MC 26.2's VulkanCommandEncoder
 *     exposes signalSemaphore(vkSemaphore, value, stageMask)).
 *  3. The provider publishes the frame with vrmc_shared_publish_eyes(targets, sync) where all fields
 *     of the struct are copied atomically with the eye targets.
 *  4. The compositor calls vrmc_shared_acquire_eyes(), and if frame.sync.valid != 0 it encodes
 *     [commandBuffer encodeWaitForEvent:(id<MTLSharedEvent>)frame.sync.shared_event
 *                                 value:frame.sync.signal_value]
 *     BEFORE the render pass that samples frame.eyes.left_texture / frame.eyes.right_texture.
 *     The wait is a no-op when sync.valid == 0 (legacy/unsynchronized publishers).
 *
 * Lifetime contract: the texture fields are opaque id<MTLTexture> pointers owned by the provider
 * (owned by the eye VRTextureTargets and destroyed on resize / render-target reinit). The bridge
 * cannot retain Objective-C objects; the compositor must retain both textures for the lifetime of
 * the command buffer it encodes them in, re-acquire every frame, and treat a change of
 * texture_generation as "the old handles may be dead now". publish_sequence lets the compositor
 * detect a newer frame and drop duplicate draws.
 */

/* Producer-published GPU timeline that makes one eye frame safe to sample. */
typedef struct {
    uint64_t shared_event; /* opaque id<MTLSharedEvent> exported from a timeline VkSemaphore; 0 = none */
    uint64_t signal_value; /* wait until signaledValue >= this before sampling; 0 when valid == 0 */
    uint32_t frame_index;  /* provider frame index this value belongs to (vrmc_eye_targets.frame_index) */
    uint32_t valid;        /* 1 = (shared_event, signal_value) is a usable wait pair, 0 = no sync */
} vrmc_shared_frame_sync;

/* One atomically publishable eye frame: texture handles + GPU sync + change detection. */
typedef struct {
    vrmc_eye_targets eyes;         /* left/right MTLTexture handles, sizes, FOVs, provider frame index */
    vrmc_shared_frame_sync sync;   /* GPU timeline wait target for those textures */
    uint64_t publish_sequence;     /* starts at 1 and increases on every publish (0 = nothing yet) */
    uint32_t texture_generation;   /* increases when the left/right handles or sizes change */
    uint32_t reserved;             /* explicit padding, keep zero */
} vrmc_shared_eye_frame;

/* Publish the latest eye targets plus (optionally) their GPU sync pair, atomically.
 * Called by the provider render thread (e.g. from VisionRenderer.endFrame()/JNI). sync may be NULL
 * for legacy/unsynchronized builds, which clears the sync of the published frame. Returns 0 on
 * success; fails closed (nonzero) on bad arguments / bridge not initialized. */
int32_t vrmc_shared_publish_eyes(const vrmc_eye_targets *targets, const vrmc_shared_frame_sync *sync);

/* Atomically acquire the latest published frame (eyes + sync + sequence + texture generation).
 * Safe to call from the compositor thread every frame. Returns 0 and fills *out on success; fails
 * closed (nonzero) before the provider has published a frame. */
int32_t vrmc_shared_acquire_eyes(vrmc_shared_eye_frame *out);

/* Latest eye targets only (legacy accessor, kept for older compositor builds). Equivalent to
 * vrmc_shared_acquire_eyes() but drops the sync pair. Prefer vrmc_shared_acquire_eyes(). */
int32_t vrmc_shared_eye_textures(vrmc_eye_targets *out);

/* Latest GPU sync pair (context/values only, no textures). Returns 0 on success; nonzero when no
 * frame has been published yet. sync->valid is 0 for an unsynchronized publisher. */
int32_t vrmc_shared_get_frame_sync(vrmc_shared_frame_sync *out);

/* ------------------------------------------------------------------------------------------- */
/* Tracking                                                                                      */
/* ------------------------------------------------------------------------------------------- */

/* Drop the stored provider eye textures (called from the provider on VR/game teardown so the
 * compositor stops sampling handles whose VkImage/MTLTexture is about to be destroyed). */
void vrmc_shared_clear_eye_textures(void);

/* Game/VR teardown signal: the provider sets this from VisionVR.destroy() so the compositor/shell can
 * dismiss the immersive space instead of leaving a stale test-pattern scene after the game exits.
 * Also counts as an explicit reason for the compositor's no-eye fallback. */
void vrmc_shared_signal_game_stopping(void);
int32_t vrmc_shared_game_stopping(void);
void vrmc_shared_clear_game_stopping(void);

/* Push a tracking state (ARKit device anchor + predicted time) into the bridge. Subsequent
 * vrmc_get_tracking calls return this state until cleared. Returns 0 on success.
 * Allowed before vrmc_init (the compositor can start before the JVM provider initializes). */
int32_t vrmc_shared_set_tracking(const vrmc_tracking_state *state);

/* Drop the native tracking override; vrmc_get_tracking reverts to the stub identity. */
void vrmc_shared_clear_tracking(void);

/* ------------------------------------------------------------------------------------------- */
/* Display views                                                                                 */
/* ------------------------------------------------------------------------------------------- */

/* Display views: the headset's real per-eye frustum and eye-to-head transform, published by the
 * CompositorServices renderer and consumed by the provider so Minecraft renders the display's
 * projection directly (macstream's ViewsConfig/local_view_transform equivalent). Tangents are signed
 * left/right/up/down (left and down negative); matrices are 16 floats, column-major view->device. */
typedef struct {
    uint32_t generation;         /* written by the bridge */
    float left_tangents[4];      /* left, right, up, down (signed tangents) */
    float right_tangents[4];
    float left_eye_to_head[16];  /* view->device, column-major */
    float right_eye_to_head[16];
    float ipd_m;
} vrmc_display_views;

/* Publish the latest display views. The bridge bumps generation only when the payload changes.
 * Returns 0 on success. */
int32_t vrmc_shared_set_display_views(const vrmc_display_views *views);

/* Read the latest display views. Fills *out (generation included) and returns the generation
 * (0 = none yet). */
uint32_t vrmc_shared_get_display_views(vrmc_display_views *out);

/* ------------------------------------------------------------------------------------------- */
/* Gaze / hand selection (M4-W2)                                                                */
/* ------------------------------------------------------------------------------------------- */
/*
 * The compositor renders a grid of CompositorServices tracking areas over the presented layer; the
 * system applies the true-gaze hover effect and tags indirect pinch activations with the tracking
 * area identifier. The SwiftUI layer receives those events and publishes a small event here; the JVM
 * provider polls it through JNI nativePollGazeEvent and turns the tile id into a GUI click.
 *
 * Only the LATEST event is retained (events are one-shot and tiny); a poll consumes it. A single
 * producer (compositor/SwiftUI) and a single consumer (provider) makes this lock-protected mailbox
 * sufficient; tile_id == 0 is invalid and must not be published.
 */
#define VRMC_GAZE_GRID_W 32
#define VRMC_GAZE_GRID_H 18
typedef struct {
    uint64_t tile_id;      /* 1 + y*grid_w + x; 0 invalid */
    uint32_t phase;        /* 1 active, 2 ended, 3 cancelled (SpatialEventCollection.Event.Phase) */
    uint32_t kind;         /* 0 unknown, 1 indirectPinch, 2 directPinch, 3 touch, ... */
    uint32_t grid_w;       /* actual compositor grid (may be clamped below VRMC_GAZE_GRID_W) */
    uint32_t grid_h;
    uint64_t timestamp_ns; /* monotonic publish time */
} vrmc_gaze_event;

int32_t vrmc_shared_publish_gaze_event(const vrmc_gaze_event *event);
/* 1 = event returned and consumed, 0 = mailbox empty, <0 = error. */
int32_t vrmc_shared_poll_gaze_event(vrmc_gaze_event *out);
void vrmc_shared_clear_gaze_events(void);

/* ------------------------------------------------------------------------------------------- */
/* Input (M4-W1 immersive input: ARKit hand tracking -> JVM provider gestures)                   */
/* ------------------------------------------------------------------------------------------- */
/*
 * The compositor thread publishes the per-frame hand input snapshot; the JVM render thread polls
 * it through vrmc_poll_input (JNI nativePollInput). State is copied under one bridge-internal
 * mutex, so a reader never observes a torn snapshot (e.g. left hand from frame N with the right
 * hand from frame N+1).
 *
 * Release contract: when the compositor stops (immersive session ends / layer invalidated), it must
 * publish one zeroed snapshot with valid_mask = 0 before exiting, so a consumer releases every held
 * action instead of acting on a stale press. Consumers additionally treat a snapshot older than
 * 250 ms (or a frozen vrmc_shared_input_sequence) as tracking loss.
 */
int32_t vrmc_shared_publish_input(const vrmc_input_state *state);
int32_t vrmc_shared_acquire_input(vrmc_input_state *out);
/* Monotonic publish counter: 0 before the first publish, incremented by every successful publish.
 * Consumers use it only for change/staleness detection (never as a clock). */
uint64_t vrmc_shared_input_sequence(void);

/* ------------------------------------------------------------------------------------------- */
/* Render feedback (M8: foveated 4K/120 rendering)                                               */
/* ------------------------------------------------------------------------------------------- */
/*
 * Compositor -> provider render feedback, refreshed every compositor frame and read by the provider
 * from its render thread. The CompositorServices layer knows what the display actually asks for; the
 * provider must size its own stereo eye textures to that instead of a hardcoded 1024x1024:
 *
 *  - left/right_logical_* is the per-eye view size at the current render quality (the resolution at
 *    which one provider pixel maps 1:1 to one displayed pixel in the fovea). With foveation enabled
 *    the PHYSICAL drawable is smaller (drawable_width/height); the system expands the high-density
 *    centre back to the logical size when it presents.
 *  - foveation_enabled/rate_map_count report whether dynamic rasterization-rate (foveated) rendering
 *    is active. The provider does not render through the rate map itself (its eye textures are
 *    uniform); the flag tells it the display path is foveated and how much centre detail the system
 *    can use.
 *  - display_hz/frame_time_ms are measured by the compositor from consecutive presentation times, so
 *    the provider can target the real display cadence (e.g. 120 Hz) instead of assuming 90 Hz.
 *  - provider_eye_* is an optional compositor-side recommendation (0 = the provider derives its own
 *    target from the logical size and its render-scale policy).
 *
 * This is an additive native-shared channel (same class as display views / input): the Java ABI
 * structs in vrmc_abi.h are unchanged. Publication is allowed before vrmc_init (the compositor can
 * run before the JVM); acquire returns 0 with a zeroed valid=0 payload before the first publish.
 * Whole-struct copies happen under one bridge-internal mutex, so readers never see a torn payload.
 */
#define VRMC_RENDER_SETTINGS_VERSION 1u
typedef struct {
    uint32_t version;             /* VRMC_RENDER_SETTINGS_VERSION */
    uint32_t valid;               /* 1 = fields valid, 0 = nothing published yet / uninitialized */
    uint32_t frame_index;         /* compositor frame number the payload was measured on */
    uint32_t foveation_enabled;   /* 1 = layer foveation enabled (rate maps active) */
    uint32_t rate_map_count;      /* rate maps on the built_in drawable (0 = no foveation) */
    uint32_t left_logical_width;  /* per-eye LOGICAL view size at the current render quality, px */
    uint32_t left_logical_height;
    uint32_t right_logical_width;
    uint32_t right_logical_height;
    uint32_t drawable_width;      /* PHYSICAL built_in drawable texture extent, px */
    uint32_t drawable_height;
    float render_quality;         /* current LayerRenderer render quality [0,1] */
    float max_render_quality;     /* configured maximum render quality [0,1] */
    float display_hz;             /* measured display cadence (Hz); 0 = unknown */
    float frame_time_ms;          /* measured compositor frame interval EWMA (ms); 0 = unknown */
    uint32_t provider_eye_width;  /* optional compositor recommendation, 0 = provider derives */
    uint32_t provider_eye_height;
} vrmc_render_settings;

/* Publish the latest render feedback (compositor thread). Returns 0 on success, nonzero on a NULL /
 * malformed payload (valid must be 0 or 1, version must match, quality in [0,1], sizes sane). */
int32_t vrmc_shared_publish_render_settings(const vrmc_render_settings *settings);

/* Acquire the latest render feedback (provider render thread through JNI). Returns 0 and fills *out;
 * before the first publish *out is zeroed with valid=0 ("no display feedback yet", not an error). */
int32_t vrmc_shared_acquire_render_settings(vrmc_render_settings *out);

#ifdef __cplusplus
}
#endif
#endif /* VRMC_NATIVE_SHARED_H */
