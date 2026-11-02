/*
 * VRMC M4-W1 deterministic hand-input fixture generator (host only, no device, no Metal).
 *
 * WHAT THIS IS
 * ------------
 * Produces the cross-language ABI v3 contract fixture: a deterministic vrmc_input_state stream is
 * published through the bridge (vrmc_shared_publish_input), read back through the Java-facing ABI
 * path (vrmc_poll_input) and written to disk for the Java provider's VisionInputFixtureTest. It
 * catches C-vs-Java struct offset/order/stride drift that unit tests on either side cannot see.
 * It is synthetic test data, never hands evidence.
 *
 * FILES WRITTEN (both consumed by provider/tests/dev/vrmc/provider/VisionInputFixtureTest.java)
 * -------------------------------------------------------------------------------------------
 *   argv[1]                 exactly 752 bytes = ONE raw vrmc_input_state: the "contract snapshot"
 *                           (frame_index 8, see table below). No header, no trailing bytes; its
 *                           sha256 is printed. Environment name in the selfcheck: VRMC_INPUT_FIXTURE.
 *   <argv[1]>.frames        exactly 7520 bytes = 10 concatenated raw vrmc_input_state records,
 *                           frames 0..9 in publish order, no header. Time-series contract fixture so
 *                           the Java test can replay the documented gesture timeline through
 *                           VisionInput using each record's own timestamp_ns (pacing-independent).
 *                           Env name: VRMC_INPUT_FIXTURE_FRAMES.
 * Both files are verified against vrmc_poll_input before they are written, so on success they are
 * byte-exact bridge output (not a locally assembled struct).
 *
 * BUILD (exactly what scripts/m4_input_selfcheck.sh runs):
 *   clang -O2 -I bridge/abi bridge/tests/make_input_fixture.c bridge/src/vrmc_stub.c -lpthread \
 *         -o <out>/make_input_fixture
 * USAGE:
 *   <out>/make_input_fixture <out.bin>
 *   Exit 0 on success; 2 usage; 3 init; 4 publish/sequence; 5 poll round-trip mismatch;
 *   6 file write; 7 output path too long.
 *
 * TIMELINE (10 scenario records in <argv[1]>.frames; all both hands tracked, valid_mask = 3;
 * record timestamp_ns = 1000000000 + frame_index * 150000000, i.e. a documented 150 ms spacing):
 *   rec  ts_ns        LEFT hand        RIGHT hand    expected raw gesture state
 *     0  1000000000   open             open          no gestures (acquisition frame)
 *     1  1150000000   open             pinch         RIGHT pinch raw press  (d < pinchOn)
 *     2  1300000000   open             pinch held    RIGHT pinch still pressed
 *     3  1450000000   open             open          RIGHT pinch released   (d > pinchOff)
 *     4  1600000000   fist             open          LEFT fist raw press    (r < fistOn)
 *     5  1750000000   fist held        open          LEFT fist held
 *     6  1900000000   fist held        open          LEFT fist held
 *     7  2050000000   fist held        open          LEFT fist held -> 450 ms continuous hold
 *                                                   >= 400 ms holdMs: EXACTLY ONE fist-tap pulse
 *                                                   fires AT THIS RECORD
 *     8  2200000000   fist still held  open          same hold continues -> NO repeat pulse
 *     9  2350000000   open             open          released; every source released afterwards
 *   Replay contract: consumers use each record's own timestamp_ns (the spacing is part of the
 *   fixture, not the replay cadence). 150 ms satisfies the provider's defaults: 100 ms
 *   released-state arming < 150 ms < 250 ms stale-input release. The 400 ms fist-tap hold is
 *   reached between records 4 and 7 (1600000000 -> 2050000000 ns = 450 ms), so a strict-default
 *   replay must fire one pulse at record 7 and no repeat at record 8.
 *
 * CONTRACT SNAPSHOT (the 752-byte primary file; an 11th publish, NOT part of the 10-record timeline;
 * its frame_index is deliberately distinct from the timeline numbering so it cannot be replayed):
 *   frame_index = 8, timestamp_ns = 1960000000, valid_mask = 3, both hands tracked
 *   LEFT  : open  -> pinch d = 0.0680 m (released, > pinchOff 0.045), fist r = 1.7900 (released)
 *   RIGHT : pinch AND fist held -> pinch d = 0.0050 m (raw press, < pinchOn 0.030),
 *           fist r = 0.9809 (raw fist, < fistOn 1.25). Both metrics exercisable in one snapshot.
 *   wrist_position: LEFT (-0.18, 1.20, -0.40), RIGHT (+0.18, 1.20, -0.40); wrist_orientation is the
 *   identity quaternion (0,0,0,1) -- consumers build the pose basis from the joint positions.
 *
 * GESTURE THRESHOLDS (docs/analysis/immersive-input.md §5.3; the Java side owns the tuned values,
 * this fixture only has to be clearly on one side of each threshold):
 *   pinchOn = 0.030 m   pinchOff = 0.045 m      d = |joint4 (thumb tip) - joint9 (index tip)|
 *   fistOn  = 1.250     fistOff  = 1.550        r = avg(|j9,j14,j19,j24 - j0|) / |j11 - j0|
 *
 * COORDINATES / JOINT GEOMETRY
 * ----------------------------
 * Device/anchor space exactly like vrmc_tracking_state.head: metres, y-up, -Z forward. The local
 * table below is a RIGHT hand in hand-local coordinates (+x radial/thumb side, +y distal toward the
 * fingertips, +z palmar-forward). A hand's world joint positions are:
 *     joint_world = wrist_position + (chirality == LEFT ? (-local.x, local.y, local.z) : local)
 * (left hand = mirror of the right hand about x). ARKit joint index order, 0..26:
 *   0 wrist, 1..4 thumb (1 knuckle, 2 intermediate base, 3 intermediate tip, 4 tip),
 *   5..9 index (5 metacarpal base, 6 knuckle, 7 intermediate base, 8 intermediate tip, 9 tip),
 *   10..14 middle (10 metacarpal base, 11 knuckle = palm length, 12 intermediate base,
 *   13 intermediate tip, 14 tip), 15..19 ring (15 metacarpal base, 16 knuckle, 17 intermediate
 *   base, 18 intermediate tip, 19 tip), 20..24 little (20 metacarpal base, 21 knuckle,
 *   22 intermediate base, 23 intermediate tip, 24 tip), 25..26 reserved ARKit extension joints
 *   (not consumed by W1; filled deterministically so no index is undefined).
 * W1 consumers use 0 (pose origin), 4/9 (pinch), 9/14/19/24 vs 0 and 11 (fist), 5/20 (hand side),
 * 9/0 (aim). The full 27-joint array is written so M4-W2+ consumers need no ABI change.
 *
 * JOINTS 0..26, RIGHT-HAND LOCAL (metres): [x, y, z]
 *   0  (0.000, 0.000, 0.000)   1  (0.025, 0.020, 0.010)   2  (0.038, 0.040, 0.020)
 *   3  (0.052, 0.070, 0.015)   4  (0.065, 0.105, 0.000)   5  (0.025, 0.015, 0.000)
 *   6  (0.025, 0.050, 0.000)   7  (0.025, 0.080, 0.000)   8  (0.025, 0.120, 0.000)
 *   9  (0.025, 0.160, 0.000)  10  (0.000, 0.015, 0.000)  11  (0.000, 0.090, 0.000)
 *  12  (0.000, 0.115, 0.000)  13  (0.000, 0.140, 0.000)  14  (0.000, 0.165, 0.000)
 *  15  (-0.025, 0.015, 0.000) 16  (-0.025, 0.080, 0.000) 17  (-0.025, 0.105, 0.000)
 *  18  (-0.025, 0.130, 0.000) 19  (-0.025, 0.158, 0.000) 20  (-0.048, 0.012, 0.000)
 *  21  (-0.048, 0.065, 0.000) 22  (-0.048, 0.095, 0.000) 23  (-0.048, 0.125, 0.000)
 *  24  (-0.048, 0.150, 0.000) 25  (0.000, 0.030, 0.020)  26  (0.000, -0.010, 0.020)
 * POSE OVERRIDES (all other joints keep the OPEN table above):
 *   pinch      : j4 = (0.029, 0.157, 0.000)  -> |j4-j9| = 0.0050 (raw press)
 *   pinch held : j4 = (0.030, 0.156, 0.000)  -> |j4-j9| = 0.0064
 *   fist       : j9  = (0.025, 0.070, 0.045), j14 = (0.000, 0.065, 0.055),
 *                j19 = (-0.025, 0.062, 0.050), j24 = (-0.048, 0.075, 0.040),
 *                j4  = (0.062, 0.100, 0.020) -> fist r = 0.9809, pinch d = 0.0538 (released)
 *   fist+pinch : the fist overrides, then j4 = j9 + (0.004, -0.003, 0.000) -> d = 0.0050, r = 0.9809
 *
 * STDOUT (machine-readable; consumed by logs, humans and the selfcheck)
 *   [vrmc-input-fixture] scenario=M4-W1 ...        header
 *   [vrmc-input-fixture] thresholds ...            the four thresholds + period
 *   frame=<i> valid_mask=3 ts_ns=... right_pinch=... left_pinch=... right_fist=... left_fist=...
 *           right_state=<pinch|pinch+fist|fist|open> left_state=...      one line per frame 0..8
 *   timeline frame=<i> valid_mask=3 ts_ns=... right_pinch=... left_pinch=... right_fist=...
 *           left_fist=... right_state=<pinch|pinch+fist|fist|open> left_state=...  (10 lines)
 *   contract frame=8 valid_mask=3 ...                                             (primary snapshot)
 *   [vrmc-input-fixture] published=11 sequence=11 poll_verified=1
 *   fixture path=<argv[1]> bytes=752 sha256=<hex>
 *   fixture.frames path=<argv[1]>.frames bytes=7520 sha256=<hex>
 *   records=10 record_bytes=752
 */
#include "vrmc_abi.h"
#include "vrmc_native_shared.h"
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FRAME_PERIOD_NS 150000000ull
#define BASE_TS_NS 1000000000ull
#define SCENARIO_FRAMES 10u
#define CONTRACT_FRAME_INDEX 8u
/* Independent of the timeline grid (1960000000 is not on the 150 ms grid), documented and stable. */
#define CONTRACT_TS_NS 1960000000ull

#define PINCH_ON_M 0.030f
#define PINCH_OFF_M 0.045f
#define FIST_ON 1.25f
#define FIST_OFF 1.55f

#define WRIST_LEFT_X (-0.18f)
#define WRIST_RIGHT_X (0.18f)
#define WRIST_Y 1.20f
#define WRIST_Z (-0.40f)

/* ------------------------------------------------------------------------------------------- */
/* SHA-256 (small self-contained implementation; the generator must print the sha256 of the bytes */
/* it wrote without depending on an external digest tool).                                       */
/* ------------------------------------------------------------------------------------------- */
typedef struct {
    uint32_t state[8];
    uint64_t bitlen;
    unsigned char data[64];
    size_t datalen;
} Sha256;

static uint32_t rotr32(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }

static const uint32_t SHA256_K[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};

static void sha256_transform(Sha256 *c, const unsigned char d[64]) {
    uint32_t m[64];
    for (int i = 0; i < 16; i++) {
        m[i] = ((uint32_t)d[i * 4] << 24) | ((uint32_t)d[i * 4 + 1] << 16) |
               ((uint32_t)d[i * 4 + 2] << 8) | (uint32_t)d[i * 4 + 3];
    }
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = rotr32(m[i - 15], 7) ^ rotr32(m[i - 15], 18) ^ (m[i - 15] >> 3);
        uint32_t s1 = rotr32(m[i - 2], 17) ^ rotr32(m[i - 2], 19) ^ (m[i - 2] >> 10);
        m[i] = m[i - 16] + s0 + m[i - 7] + s1;
    }
    uint32_t a = c->state[0], b = c->state[1], cc = c->state[2], dd = c->state[3];
    uint32_t e = c->state[4], f = c->state[5], g = c->state[6], h = c->state[7];
    for (int i = 0; i < 64; i++) {
        uint32_t s1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
        uint32_t ch = (e & f) ^ ((~e) & g);
        uint32_t t1 = h + s1 + ch + SHA256_K[i] + m[i];
        uint32_t s0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
        uint32_t maj = (a & b) ^ (a & cc) ^ (b & cc);
        uint32_t t2 = s0 + maj;
        h = g; g = f; f = e; e = dd + t1;
        dd = cc; cc = b; b = a; a = t1 + t2;
    }
    c->state[0] += a; c->state[1] += b; c->state[2] += cc; c->state[3] += dd;
    c->state[4] += e; c->state[5] += f; c->state[6] += g; c->state[7] += h;
}

static void sha256_init(Sha256 *c) {
    c->datalen = 0;
    c->bitlen = 0;
    c->state[0] = 0x6a09e667u; c->state[1] = 0xbb67ae85u; c->state[2] = 0x3c6ef372u; c->state[3] = 0xa54ff53au;
    c->state[4] = 0x510e527fu; c->state[5] = 0x9b05688cu; c->state[6] = 0x1f83d9abu; c->state[7] = 0x5be0cd19u;
}

static void sha256_update(Sha256 *c, const void *data, size_t len) {
    const unsigned char *p = (const unsigned char *)data;
    for (size_t i = 0; i < len; i++) {
        c->data[c->datalen++] = p[i];
        if (c->datalen == 64) {
            sha256_transform(c, c->data);
            c->bitlen += 512;
            c->datalen = 0;
        }
    }
}

static void sha256_final(Sha256 *c, unsigned char out[32]) {
    size_t i = c->datalen;
    if (c->datalen < 56) {
        c->data[i++] = 0x80;
        while (i < 56) c->data[i++] = 0x00;
    } else {
        c->data[i++] = 0x80;
        while (i < 64) c->data[i++] = 0x00;
        sha256_transform(c, c->data);
        memset(c->data, 0, 56);
    }
    c->bitlen += (uint64_t)c->datalen * 8;
    for (int k = 0; k < 8; k++) c->data[63 - k] = (unsigned char)(c->bitlen >> (8 * k));
    sha256_transform(c, c->data);
    for (int k = 0; k < 8; k++) {
        out[k * 4 + 0] = (unsigned char)(c->state[k] >> 24);
        out[k * 4 + 1] = (unsigned char)(c->state[k] >> 16);
        out[k * 4 + 2] = (unsigned char)(c->state[k] >> 8);
        out[k * 4 + 3] = (unsigned char)(c->state[k]);
    }
}

static void sha256_hex(const void *data, size_t len, char out[65]) {
    Sha256 c;
    unsigned char digest[32];
    sha256_init(&c);
    sha256_update(&c, data, len);
    sha256_final(&c, digest);
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < 32; i++) {
        out[i * 2] = hex[digest[i] >> 4];
        out[i * 2 + 1] = hex[digest[i] & 0xf];
    }
    out[64] = '\0';
}

/* ------------------------------------------------------------------------------------------- */
/* Deterministic hand geometry                                                                   */
/* ------------------------------------------------------------------------------------------- */
typedef enum {
    POSE_OPEN = 0,
    POSE_PINCH,
    POSE_PINCH_HELD,
    POSE_FIST,
    POSE_FIST_PINCH
} HandPose;

/* Right-hand local joint table (metres); identical to the table in the file header. */
static const float kOpenLocal[VRMC_HAND_JOINT_COUNT][3] = {
    {0.000f, 0.000f, 0.000f},   {0.025f, 0.020f, 0.010f},   {0.038f, 0.040f, 0.020f},
    {0.052f, 0.070f, 0.015f},   {0.065f, 0.105f, 0.000f},   {0.025f, 0.015f, 0.000f},
    {0.025f, 0.050f, 0.000f},   {0.025f, 0.080f, 0.000f},   {0.025f, 0.120f, 0.000f},
    {0.025f, 0.160f, 0.000f},   {0.000f, 0.015f, 0.000f},   {0.000f, 0.090f, 0.000f},
    {0.000f, 0.115f, 0.000f},   {0.000f, 0.140f, 0.000f},   {0.000f, 0.165f, 0.000f},
    {-0.025f, 0.015f, 0.000f},  {-0.025f, 0.080f, 0.000f},  {-0.025f, 0.105f, 0.000f},
    {-0.025f, 0.130f, 0.000f},  {-0.025f, 0.158f, 0.000f},  {-0.048f, 0.012f, 0.000f},
    {-0.048f, 0.065f, 0.000f},  {-0.048f, 0.095f, 0.000f},  {-0.048f, 0.125f, 0.000f},
    {-0.048f, 0.150f, 0.000f},  {0.000f, 0.030f, 0.020f},   {0.000f, -0.010f, 0.020f}};

static void pose_local(HandPose pose, float local[VRMC_HAND_JOINT_COUNT][3]) {
    memcpy(local, kOpenLocal, sizeof(kOpenLocal));
    switch (pose) {
        case POSE_OPEN:
            break;
        case POSE_PINCH:
            local[4][0] = 0.029f; local[4][1] = 0.157f; local[4][2] = 0.000f;
            break;
        case POSE_PINCH_HELD:
            local[4][0] = 0.030f; local[4][1] = 0.156f; local[4][2] = 0.000f;
            break;
        case POSE_FIST:
        case POSE_FIST_PINCH:
            local[9][0] = 0.025f;  local[9][1] = 0.070f;  local[9][2] = 0.045f;
            local[14][0] = 0.000f; local[14][1] = 0.065f; local[14][2] = 0.055f;
            local[19][0] = -0.025f; local[19][1] = 0.062f; local[19][2] = 0.050f;
            local[24][0] = -0.048f; local[24][1] = 0.075f; local[24][2] = 0.040f;
            local[4][0] = 0.062f;  local[4][1] = 0.100f;  local[4][2] = 0.020f;
            if (pose == POSE_FIST_PINCH) {
                local[4][0] = local[9][0] + 0.004f;
                local[4][1] = local[9][1] - 0.003f;
                local[4][2] = local[9][2];
            }
            break;
    }
}

static void fill_hand(vrmc_hand_state *hand, uint32_t chirality, float wrist_x, HandPose pose,
                      uint64_t timestamp_ns) {
    float local[VRMC_HAND_JOINT_COUNT][3];
    pose_local(pose, local);
    memset(hand, 0, sizeof(*hand));
    hand->tracked = 1;
    hand->chirality = chirality;
    hand->timestamp_ns = timestamp_ns;
    hand->wrist_orientation.x = 0.0f;
    hand->wrist_orientation.y = 0.0f;
    hand->wrist_orientation.z = 0.0f;
    hand->wrist_orientation.w = 1.0f;
    hand->wrist_position.x = wrist_x;
    hand->wrist_position.y = WRIST_Y;
    hand->wrist_position.z = WRIST_Z;
    float mirror = (chirality == 0) ? -1.0f : 1.0f; /* chirality 0 = left = mirror about x */
    for (int j = 0; j < VRMC_HAND_JOINT_COUNT; j++) {
        hand->joints[j].x = wrist_x + mirror * local[j][0];
        hand->joints[j].y = WRIST_Y + local[j][1];
        hand->joints[j].z = WRIST_Z + local[j][2];
    }
}

/* hands[0] = LEFT, hands[1] = RIGHT (explicit slots, independent of chirality). */
static void fill_frame(vrmc_input_state *state, uint32_t frame_index, uint64_t timestamp_ns,
                       HandPose left, HandPose right) {
    memset(state, 0, sizeof(*state));
    state->frame_index = frame_index;
    state->valid_mask = 0x3u; /* bit0 = left tracked, bit1 = right tracked */
    state->timestamp_ns = timestamp_ns;
    fill_hand(&state->hands[VRMC_INPUT_LEFT_HAND], 0, WRIST_LEFT_X, left, timestamp_ns);
    fill_hand(&state->hands[VRMC_INPUT_RIGHT_HAND], 1, WRIST_RIGHT_X, right, timestamp_ns);
}

static float joint_distance(const vrmc_vec3 *a, const vrmc_vec3 *b) {
    float dx = a->x - b->x, dy = a->y - b->y, dz = a->z - b->z;
    return sqrtf(dx * dx + dy * dy + dz * dz);
}

static float pinch_distance(const vrmc_hand_state *hand) {
    return joint_distance(&hand->joints[4], &hand->joints[9]);
}

static float fist_ratio(const vrmc_hand_state *hand) {
    float avg = (joint_distance(&hand->joints[9], &hand->joints[0]) +
                 joint_distance(&hand->joints[14], &hand->joints[0]) +
                 joint_distance(&hand->joints[19], &hand->joints[0]) +
                 joint_distance(&hand->joints[24], &hand->joints[0])) /
                4.0f;
    return avg / joint_distance(&hand->joints[11], &hand->joints[0]);
}

static const char *gesture_label(float pinch_d, float fist_r) {
    int pinch = pinch_d < PINCH_ON_M;
    int fist = fist_r < FIST_ON;
    if (pinch && fist) return "pinch+fist";
    if (pinch) return "pinch";
    if (fist) return "fist";
    return "open";
}

/* Publish + poll-verify one snapshot. Returns 0 on success. */
static int publish_verified(const vrmc_input_state *state, vrmc_input_state *out_polled) {
    if (vrmc_shared_publish_input(state) != 0) {
        fprintf(stderr, "[vrmc-input-fixture] publish failed: %s\n", vrmc_last_error());
        return -1;
    }
    vrmc_input_state got;
    memset(&got, 0xAA, sizeof(got));
    if (vrmc_poll_input(&got, sizeof(got)) != 0) {
        fprintf(stderr, "[vrmc-input-fixture] poll failed: %s\n", vrmc_last_error());
        return -1;
    }
    if (memcmp(&got, state, sizeof(got)) != 0) {
        fprintf(stderr, "[vrmc-input-fixture] poll round-trip mismatch on frame_index=%u\n",
                state->frame_index);
        return -1;
    }
    if (out_polled != NULL) *out_polled = got;
    return 0;
}

static void print_row(const char *kind, const vrmc_input_state *s) {
    const vrmc_hand_state *left = &s->hands[VRMC_INPUT_LEFT_HAND];
    const vrmc_hand_state *right = &s->hands[VRMC_INPUT_RIGHT_HAND];
    float lp = pinch_distance(left), rp = pinch_distance(right);
    float lf = fist_ratio(left), rf = fist_ratio(right);
    printf("%s frame=%u valid_mask=%u ts_ns=%llu right_pinch=%.4f left_pinch=%.4f "
           "right_fist=%.4f left_fist=%.4f right_state=%s left_state=%s\n",
           kind, s->frame_index, s->valid_mask, (unsigned long long)s->timestamp_ns, rp, lp, rf, lf,
           gesture_label(rp, rf), gesture_label(lp, lf));
}

static int write_file(const char *path, const void *data, size_t len) {
    FILE *f = fopen(path, "wb");
    if (f == NULL) {
        fprintf(stderr, "[vrmc-input-fixture] cannot open %s for writing\n", path);
        return -1;
    }
    size_t written = fwrite(data, 1, len, f);
    int rc = fclose(f);
    if (written != len || rc != 0) {
        fprintf(stderr, "[vrmc-input-fixture] short write to %s (%zu/%zu)\n", path, written, len);
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <out.bin>\n", argv[0]);
        return 2;
    }
    const char *out_path = argv[1];
    char frames_path[4096];
    int path_len = snprintf(frames_path, sizeof(frames_path), "%s.frames", out_path);
    if (path_len < 0 || (size_t)path_len >= sizeof(frames_path)) {
        fprintf(stderr, "[vrmc-input-fixture] output path too long for the .frames sidecar\n");
        return 7;
    }

    static const char *caps = "{\"abi\":3,\"eyes\":2,\"hands\":2,\"input\":1}";
    if (vrmc_init(caps, strlen(caps)) != 0) {
        fprintf(stderr, "[vrmc-input-fixture] bridge init failed: %s\n", vrmc_last_error());
        return 3;
    }
    printf("[vrmc-input-fixture] scenario=M4-W1 deterministic hand input "
           "(10-record timeline + 1 contract snapshot)\n");
    printf("[vrmc-input-fixture] thresholds pinchOn=%.3f pinchOff=%.3f fistOn=%.2f fistOff=%.2f "
           "frame_period_ns=%llu\n",
           (double)PINCH_ON_M, (double)PINCH_OFF_M, (double)FIST_ON, (double)FIST_OFF,
           (unsigned long long)FRAME_PERIOD_NS);
    printf("[vrmc-input-fixture] replay_expectation frame_period_ms=150 (>arming 100ms, <stale 250ms); "
           "right_pinch press@rec1 held@rec2 released@rec3; left_fist press@rec4, "
           "hold@rec4..rec7=450ms >= holdMs 400ms -> exactly one fist-tap pulse at rec7, "
           "no repeat at rec8, released at rec9\n");

    static const struct {
        HandPose left;
        HandPose right;
    } kScenario[SCENARIO_FRAMES] = {
        {POSE_OPEN, POSE_OPEN},        /* 0: acquisition, both open */
        {POSE_OPEN, POSE_PINCH},       /* 1: right pinch on */
        {POSE_OPEN, POSE_PINCH_HELD},  /* 2: right pinch held */
        {POSE_OPEN, POSE_OPEN},        /* 3: right pinch off */
        {POSE_FIST, POSE_OPEN},        /* 4: left fist on */
        {POSE_FIST, POSE_OPEN},        /* 5: left fist held */
        {POSE_FIST, POSE_OPEN},        /* 6: left fist held */
        {POSE_FIST, POSE_OPEN},        /* 7: left fist held, 450 ms -> one tap pulse fires here */
        {POSE_FIST, POSE_OPEN},        /* 8: same hold continues -> no repeat pulse */
        {POSE_OPEN, POSE_OPEN},        /* 9: both released */
    };

    vrmc_input_state timeline[SCENARIO_FRAMES];
    for (uint32_t i = 0; i < SCENARIO_FRAMES; i++) {
        uint64_t ts = BASE_TS_NS + (uint64_t)i * FRAME_PERIOD_NS;
        fill_frame(&timeline[i], i, ts, kScenario[i].left, kScenario[i].right);
        if (publish_verified(&timeline[i], NULL) != 0) return 4;
        print_row("timeline", &timeline[i]);
    }

    /* Contract snapshot: the 752-byte primary file. Right hand exercises pinch AND fist metrics at
     * once; left hand is clearly released. Published as an 11th publish (frame_index 8, an index that
     * is deliberately distinct from the timeline numbering) so its bytes are still verified bridge
     * output. It is NOT part of the .frames timeline. */
    vrmc_input_state contract;
    fill_frame(&contract, CONTRACT_FRAME_INDEX, CONTRACT_TS_NS, POSE_OPEN, POSE_FIST_PINCH);
    vrmc_input_state contract_polled;
    if (publish_verified(&contract, &contract_polled) != 0) return 4;
    print_row("contract", &contract_polled);

    uint64_t expected_seq = SCENARIO_FRAMES + 1ull;
    if (vrmc_shared_input_sequence() != expected_seq) {
        fprintf(stderr, "[vrmc-input-fixture] sequence=%llu want %llu\n",
                (unsigned long long)vrmc_shared_input_sequence(), (unsigned long long)expected_seq);
        return 4;
    }
    printf("[vrmc-input-fixture] published=%llu sequence=%llu poll_verified=1\n",
           (unsigned long long)expected_seq, (unsigned long long)vrmc_shared_input_sequence());

    /* Primary: exactly sizeof(vrmc_input_state) bytes polled from the bridge. */
    unsigned char primary[sizeof(vrmc_input_state)];
    memcpy(primary, &contract_polled, sizeof(primary));
    if (write_file(out_path, primary, sizeof(primary)) != 0) return 6;

    /* Sidecar: 10 concatenated records, frames 0..9 in publish order. */
    unsigned char frames[SCENARIO_FRAMES * sizeof(vrmc_input_state)];
    for (uint32_t i = 0; i < SCENARIO_FRAMES; i++) {
        memcpy(frames + (size_t)i * sizeof(vrmc_input_state), &timeline[i], sizeof(vrmc_input_state));
    }
    if (write_file(frames_path, frames, sizeof(frames)) != 0) return 6;

    char primary_sha[65];
    char frames_sha[65];
    sha256_hex(primary, sizeof(primary), primary_sha);
    sha256_hex(frames, sizeof(frames), frames_sha);
    printf("fixture path=%s bytes=%zu sha256=%s\n", out_path, sizeof(primary), primary_sha);
    printf("fixture.frames path=%s bytes=%zu sha256=%s\n", frames_path, sizeof(frames), frames_sha);
    printf("records=%u record_bytes=%zu\n", SCENARIO_FRAMES, sizeof(vrmc_input_state));
    return 0;
}
