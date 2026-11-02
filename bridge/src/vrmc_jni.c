/*
 * JNI shim for the VRMC bridge (mirrors bridge/abi/vrmc_abi.h + bridge/abi/vrmc_native_shared.h).
 * The Java side is dev.vrmc.provider.bridge.VrmcBridge; only scalars and preallocated direct buffers
 * cross the boundary (no per-frame allocation).
 *
 * Two eye-submission entry points:
 *   nativeSubmitEyes       - legacy ABI v2 path, publishes the eye targets without a GPU sync pair.
 *   nativeSubmitEyesSynced - additive native-shared path: publishes the eye targets together with the
 *                            exported MTLSharedEvent + timeline value the compositor must wait on
 *                            before sampling (see vrmc_native_shared.h). The Java ABI v2 structs are
 *                            unchanged; the provider selects this call once it has an exportable
 *                            timeline semaphore wired into its frame submission.
 *
 * Both paths report the provider's per-eye frustum from the *published display views* when the
 * compositor has provided them (the provider renders exactly that frustum), falling back to the
 * symmetric halfFovRad the Java layer passes while no display views exist.
 */
#include <jni.h>
#include <math.h>
#include <string.h>
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"

/* Fill the ABI eye-target struct from scalar arguments. Uses the CompositorServices display view
 * tangents when available so vrmc_eye_targets never reports the old symmetric 110 deg stub while the
 * provider is actually rendering the headset frustum. */
static void fill_eye_targets(vrmc_eye_targets *t, jlong left, jlong right, jint frameIndex,
                             jint width, jint height, jfloat halfFovRad) {
    memset(t, 0, sizeof(*t));
    vrmc_display_views views;
    if (vrmc_shared_get_display_views(&views) != 0) {
        for (int eye = 0; eye < 2; eye++) {
            float *fov = (eye == 0) ? t->left_fov : t->right_fov;
            fov[0] = -halfFovRad;
            fov[1] = halfFovRad;
            fov[2] = halfFovRad;
            fov[3] = -halfFovRad;
        }
    } else {
        const float *leftTan = views.left_tangents;   /* left, right, up, down (signed) */
        const float *rightTan = views.right_tangents;
        for (int i = 0; i < 4; i++) {
            t->left_fov[i] = atanf(leftTan[i]);
            t->right_fov[i] = atanf(rightTan[i]);
        }
    }
    t->frame_index = (uint32_t)frameIndex;
    t->left_texture = (uint64_t)left;
    t->right_texture = (uint64_t)right;
    t->left_width = t->right_width = (uint32_t)width;
    t->left_height = t->right_height = (uint32_t)height;
}

JNIEXPORT jint JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeAbiVersion(JNIEnv *env, jclass clazz) {
    return (jint)vrmc_abi_version();
}

JNIEXPORT jint JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeInit(JNIEnv *env, jclass clazz, jstring caps) {
    if (caps == NULL) return -2;
    const char *chars = (*env)->GetStringUTFChars(env, caps, NULL);
    if (chars == NULL) return -3;
    int32_t rc = vrmc_init(chars, strlen(chars));
    (*env)->ReleaseStringUTFChars(env, caps, chars);
    return (jint)rc;
}

JNIEXPORT jstring JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeLastError(JNIEnv *env, jclass clazz) {
    return (*env)->NewStringUTF(env, vrmc_last_error());
}

JNIEXPORT jint JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeGetTracking(JNIEnv *env, jclass clazz, jobject buf) {
    if (buf == NULL) return -4;
    void *dst = (*env)->GetDirectBufferAddress(env, buf);
    if (dst == NULL) return -5;
    vrmc_tracking_state t;
    int32_t rc = vrmc_get_tracking(&t, 0);
    if (rc == 0) memcpy(dst, &t, sizeof(t));
    return (jint)rc;
}

JNIEXPORT jint JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeSubmitEyes(
    JNIEnv *env, jclass clazz, jlong left, jlong right, jint frameIndex, jint width, jint height, jfloat halfFovRad) {
    vrmc_eye_targets t;
    fill_eye_targets(&t, left, right, frameIndex, width, height, halfFovRad);
    return (jint)vrmc_submit_eyes(&t);
}

JNIEXPORT jint JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeSubmitEyesSynced(
    JNIEnv *env, jclass clazz, jlong left, jlong right, jint frameIndex, jint width, jint height,
    jfloat halfFovRad, jlong sharedEvent, jlong signalValue) {
    vrmc_eye_targets t;
    fill_eye_targets(&t, left, right, frameIndex, width, height, halfFovRad);
    if (sharedEvent == 0 || signalValue == 0) {
        /* No exported timeline event yet (e.g. VK_EXT_metal_objects not enabled this launch): fall
         * back to the unsynchronized publication so the compositor degrades to today's behaviour. */
        return (jint)vrmc_shared_publish_eyes(&t, NULL);
    }
    vrmc_shared_frame_sync sync;
    memset(&sync, 0, sizeof(sync));
    sync.shared_event = (uint64_t)sharedEvent;
    sync.signal_value = (uint64_t)signalValue;
    sync.frame_index = (uint32_t)frameIndex;
    sync.valid = 1;
    return (jint)vrmc_shared_publish_eyes(&t, &sync);
}

JNIEXPORT jlong JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeExportMTLTexture(
    JNIEnv *env, jclass clazz, jlong vkImage) {
    uint64_t out = 0;
    int32_t rc = vrmc_export_mtl_texture((uint64_t)vkImage, &out);
    return rc == 0 ? (jlong)out : 0;
}

JNIEXPORT jlong JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeGetDisplayViews(
    JNIEnv *env, jclass clazz, jobject out) {
    if (out == NULL) return 0;
    jbyte *base = (*env)->GetDirectBufferAddress(env, out);
    jlong capacity = (*env)->GetDirectBufferCapacity(env, out);
    if (base == NULL || capacity < (jlong)(sizeof(vrmc_display_views) - sizeof(uint32_t))) return 0;
    vrmc_display_views views;
    uint32_t gen = vrmc_shared_get_display_views(&views);
    if (gen == 0) return 0;
    /* Floats only (no generation). Layout MUST match VisionVR.pollDisplayViews():
     *   per eye (left then right): tangents[4], eye_to_head matrix[16]; then ipd.
     * Byte offsets: L tangents 0, L matrix 16, R tangents 80, R matrix 96, ipd 160. */
    memcpy(base, views.left_tangents, 4 * sizeof(float));
    memcpy(base + 16, views.left_eye_to_head, 16 * sizeof(float));
    memcpy(base + 80, views.right_tangents, 4 * sizeof(float));
    memcpy(base + 96, views.right_eye_to_head, 16 * sizeof(float));
    memcpy(base + 160, &views.ipd_m, sizeof(float));
    return (jlong)gen;
}

JNIEXPORT jint JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeFrameTiming(JNIEnv *env, jclass clazz, jobject buf) {
    if (buf == NULL) return -4;
    void *dst = (*env)->GetDirectBufferAddress(env, buf);
    if (dst == NULL) return -5;
    vrmc_frame_timing_t t;
    int32_t rc = vrmc_frame_timing(&t);
    if (rc == 0) memcpy(dst, &t, sizeof(t));
    return (jint)rc;
}
