/* Offline check that the JNI display-view byte layout matches VisionVR.pollDisplayViews().
 * Both sides must agree: per eye (left then right): tangents[4] then eye_to_head matrix[16]; then ipd.
 * Byte offsets: L tangents 0, L matrix 16, R tangents 80, R matrix 96, ipd 160; total 164 bytes. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    float tangents[4];
    float eye_to_head[16];
} eye_views;

typedef struct {
    eye_views eye[2];
    float ipd;
} display_views;

static int failures = 0;
static void check_float(const char *name, float actual, float expected) {
    int ok = actual == expected;
    printf("  %-24s actual=%.4f expected=%.4f %s\n", name, actual, expected, ok ? "ok" : "FAIL");
    if (!ok) failures++;
}

int main(void) {
    uint8_t buffer[164];
    memset(buffer, 0, sizeof(buffer));
    /* Values chosen so a wrong offset is immediately visible. */
    display_views views;
    memset(&views, 0, sizeof(views));
    for (int e = 0; e < 2; e++) {
        for (int k = 0; k < 4; k++) views.eye[e].tangents[k] = (float)(e * 100 + k);       /* 0..3, 100..103 */
        for (int k = 0; k < 16; k++) views.eye[e].eye_to_head[k] = (float)(e * 1000 + 10 + k); /* 10..25, 1010..1025 */
    }
    views.ipd = 0.0637f;

    /* JNI writer (bridge/src/vrmc_jni.c). */
    memcpy(buffer, views.eye[0].tangents, 4 * sizeof(float));
    memcpy(buffer + 16, views.eye[0].eye_to_head, 16 * sizeof(float));
    memcpy(buffer + 80, views.eye[1].tangents, 4 * sizeof(float));
    memcpy(buffer + 96, views.eye[1].eye_to_head, 16 * sizeof(float));
    memcpy(buffer + 160, &views.ipd, sizeof(float));

    printf("[display-views-layout] JNI vs Java/provider offsets\n");
    for (int e = 0; e < 2; e++) {
        int o = e * (4 + 16) * 4; /* VisionVR.pollDisplayViews() o */
        for (int k = 0; k < 4; k++) {
            float v;
            memcpy(&v, buffer + o + k * 4, sizeof(float));
            check_float(e == 0 ? "L tangent" : "R tangent", v, views.eye[e].tangents[k]);
        }
        for (int k = 0; k < 16; k++) {
            float v;
            memcpy(&v, buffer + o + 16 + k * 4, sizeof(float));
            check_float(e == 0 ? "L matrix" : "R matrix", v, views.eye[e].eye_to_head[k]);
        }
    }
    float ipd;
    memcpy(&ipd, buffer + 160, sizeof(float));
    check_float("ipd", ipd, views.ipd);
    printf(failures == 0 ? "[display-views-layout] PASS\n" : "[display-views-layout] FAIL\n");
    return failures == 0 ? 0 : 1;
}
