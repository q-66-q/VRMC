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
 */
#include <stdint.h>
#include "vrmc_abi.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Latest eye targets submitted by vrmc_submit_eyes. Returns 0 and fills *out on success; fails closed
 * (nonzero) if the provider has not submitted a frame yet. Left/right texture fields are opaque Metal
 * texture handles valid in this process. */
int32_t vrmc_shared_eye_textures(vrmc_eye_targets *out);

/* Push a tracking state (ARKit device anchor + predicted time) into the bridge. Subsequent
 * vrmc_get_tracking calls return this state until cleared. Returns 0 on success. */
int32_t vrmc_shared_set_tracking(const vrmc_tracking_state *state);

/* Drop the native tracking override; vrmc_get_tracking reverts to the stub identity. */
void vrmc_shared_clear_tracking(void);

#ifdef __cplusplus
}
#endif
#endif /* VRMC_NATIVE_SHARED_H */
