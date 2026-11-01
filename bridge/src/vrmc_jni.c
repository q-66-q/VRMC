/*
 * JNI shim for the VRMC bridge (mirrors bridge/abi/vrmc_abi.h).
 * The Java side is dev.vrmc.provider.bridge.VrmcBridge; only scalars and preallocated direct buffers
 * cross the boundary (no per-frame allocation).
 */
#include <jni.h>
#include <string.h>
#include "vrmc_abi.h"

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
    JNIEnv *env, jclass clazz, jlong left, jlong right, jint frameIndex, jint width, jint height) {
    vrmc_eye_targets t;
    memset(&t, 0, sizeof(t));
    t.frame_index = (uint32_t)frameIndex;
    t.left_texture = (uint64_t)left;
    t.right_texture = (uint64_t)right;
    t.left_width = t.right_width = (uint32_t)width;
    t.left_height = t.right_height = (uint32_t)height;
    return (jint)vrmc_submit_eyes(&t);
}

JNIEXPORT jlong JNICALL Java_dev_vrmc_provider_bridge_VrmcBridge_nativeExportMTLTexture(
    JNIEnv *env, jclass clazz, jlong vkImage) {
    uint64_t out = 0;
    int32_t rc = vrmc_export_mtl_texture((uint64_t)vkImage, &out);
    return rc == 0 ? (jlong)out : 0;
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
