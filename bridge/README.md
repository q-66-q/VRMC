# Bridge (native VR bridge)

**Status:** ABI **v3** implemented 2026-11-01. v2 added the eye-frame handoff (M3-W3/W4); v3 adds the
immersive input channel (M4-W1): the fail-closed Java ABI is in `abi/vrmc_abi.h` and the additive
same-process native surface (outside the Java ABI version) in `abi/vrmc_native_shared.h`.
`src/vrmc_stub.c` (deterministic fake tracking/hands plus mutex-protected shared state; host-only)
and `src/vrmc_jni.c` (JNI shim for `dev.vrmc.provider.bridge.VrmcBridge`, including
`nativePollInput`) are the current bridge implementation. Host build/test:
`bridge/tests/run_tests.sh` — stub self-test (v3 accept / v2 reject), eye-frame handoff protocol +
ThreadSanitizer, ABI v3 input layout static asserts / publish-acquire-poll round-trip / sequence /
release snapshot / 500k torn-read stress + TSan, the cross-language fixture generator, display-view
layout, `scripts/build_bridge.sh MODE=both` (host + device dylib, symbol verification) and the
optional real MoltenVK+Metal host probe. `run_tests.sh [--skip-metal] [--skip-tsan]`; the full run is
the default. Real ARKit world/hand tracking and CompositorServices presentation live in
`runtime/native-shell` (M3/M4).

ObjC++/C layer between the JVM provider and visionOS frameworks, and the owner of the frame handoff
to CompositorServices.

Contents:

- `abi/` — versioned Java C ABI v3 (`vrmc_init`, `vrmc_get_tracking`, `vrmc_poll_input`,
  `vrmc_submit_eyes`, `vrmc_export_mtl_texture`, `vrmc_frame_timing`, `vrmc_recenter`,
  `vrmc_haptic`, and the v3 input structs `vrmc_hand_state` = 368 B / `vrmc_input_state` = 752 B)
  plus the additive native-shared surface (`vrmc_shared_eye_textures`, `vrmc_shared_set_tracking`,
  `vrmc_shared_set_display_views`, `vrmc_shared_publish_eyes`, `vrmc_shared_acquire_eyes`,
  `vrmc_shared_get_frame_sync`, `vrmc_shared_publish_input`, `vrmc_shared_acquire_input`,
  `vrmc_shared_input_sequence`).
- `src/` — stub/shared-state implementation + JNI shim.
- `tests/` — `bridge_sync_test.c` (eye-frame protocol, texture generation, publish_sequence, TSan
  concurrency), `bridge_input_test.c` (ABI v3 input: layout static asserts, round-trip, sequence,
  safe pre-publish zero snapshot, NULL/short/uninitialized rejection, release snapshot, 1-writer x
  4-reader torn-snapshot detection over 500k publishes + TSan build), `make_input_fixture.c`
  (cross-language contract fixture generator, see below), `bridge_metal_sync_host.mm` (real MoltenVK
  1.4.2 + Metal host probe), `run_tests.sh`.
- Still planned: `tracking/` (ARKit WorldTrackingProvider + 27-joint HandTrackingProvider live in the
  app-side compositor), `compositor/` (LayerRenderer setup, frame pacing), `graphics/` (the real
  device bridge object that owns the provider-side exportable timeline semaphore described in
  `abi/vrmc_native_shared.h`).

Immersive input channel contract (M4-W1, full text in `docs/analysis/immersive-input.md` §3):

- The compositor publishes one `vrmc_input_state` per frame with `vrmc_shared_publish_input()`
  (compositor thread). `hands[0]` is always LEFT and `hands[1]` always RIGHT, independent of the
  ARKit `chirality` field. One bridge mutex guards the whole 752-byte snapshot, so a reader can never
  observe a torn frame (left hand from frame N with the right hand from frame N+1).
- Publication is allowed **before** `vrmc_init` (the compositor may open the immersive space before
  the JVM/Minecraft VR initialization); it fails closed only on a NULL state. `vrmc_init` resets the
  channel, so the first poll after init is the documented safe zero snapshot.
- `vrmc_poll_input()` (JNI `nativePollInput`) requires init and a buffer of at least
  `sizeof(vrmc_input_state)`; before the first publish it returns 0 with a zeroed snapshot
  (`valid_mask = 0`) — "safe, no hands", not an error. `vrmc_shared_acquire_input()` fails closed
  before the first publish. `vrmc_shared_input_sequence()` starts at 0, becomes 1 on the first
  successful publish and only increases (change/staleness detection, never a clock).
- Release contract: when the immersive session ends the compositor must publish one zeroed snapshot
  (`valid_mask = 0`) before stopping, so the provider releases every held action (no stuck input).

Cross-language input fixture — **contract fixture for the provider's `VisionInputFixtureTest`**
(`provider/tests/dev/vrmc/provider/VisionInputFixtureTest.java`); do not change the bytes without
updating both sides:

- `argv[1]` (env `VRMC_INPUT_FIXTURE`): **exactly 752 bytes = one raw `vrmc_input_state`**, the
  deterministic "contract snapshot" (frame_index 8, valid_mask 3, both hands tracked, LEFT open,
  RIGHT pinch+fist). This is the primary fixture; offsets/strides are the ABI above.
- `<argv[1]>.frames` (env `VRMC_INPUT_FIXTURE_FRAMES`): **exactly 7520 bytes = ten concatenated raw
  `vrmc_input_state` records** (frames 0..9, each record 752 bytes, no header, record
  `timestamp_ns = 1e9 + frame_index * 150 ms`); this is the documented gesture-timeline contract
  fixture that the provider replays (right pinch press/hold/release; left fist press/hold with a
  450 ms hold that must fire exactly one fist-tap pulse at record 7 and no repeat at record 8;
  release at record 9). The record timestamps — not the replay cadence — drive the replay.
- Generator: `clang -O2 -I bridge/abi bridge/tests/make_input_fixture.c bridge/src/vrmc_stub.c
  -lpthread -o <out>/make_input_fixture && <out>/make_input_fixture <out>/input_fixture.bin`. It
  publishes the whole scenario through the bridge, re-reads every record with `vrmc_poll_input` and
  refuses to write on any mismatch, prints the per-record metrics table and machine-readable lines
  `fixture path=... bytes=752 sha256=...` / `fixture.frames path=... bytes=7520 sha256=...`
  (the sha256 is computed in-process). Scenario, joint geometry and expected thresholds are
  documented in the generator's file header.

Rules:

- The Java ABI is versioned and fails closed on mismatch; no silent fallback. Additive changes live in
  `vrmc_native_shared.h` and do not need an ABI bump.
- Frame submission must respect `presentationDeadline`; a missed frame is a defect, not a warning.
- Any behavior change to the ABI or handoff requires an ADR update and S4 re-run.
- The eye-frame handoff is **not** safe to sample without the published `(MTLSharedEvent, value)` pair.
  See `docs/analysis/bridge-sync.md` for the threading/lifetime/synchronization contract and the exact
  provider/compositor wiring.
- The input snapshot is an ABI v3 layout: any field/offset/size change is a major ABI bump and must
  update `bridge/tests/bridge_input_test.c`, the provider layout test, the fixture generator and the
  design doc table in the same change.
