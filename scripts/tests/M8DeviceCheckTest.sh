#!/bin/bash
# Host test for scripts/m8_device_check.sh (M8 device verification classifier). No device needed.
#
# Creates synthetic device-like log pulls for the four outcomes and asserts the classifier's exit code
# and key output rows:
#   pass        -> exit 0 (A6-A9 all PASS, 120 Hz, foveation active, 4K-class logical, provider resizes)
#   hz90        -> exit 2 (PARTIAL: measured cadence 90 Hz, not 120)
#   oldbuild    -> exit 3 (NOT RUN: no M8 lines in the logs)
#   failed      -> exit 4 (FAIL: compositor reports a render-feedback publication failure)
#   status-only -> exit 0 (vrmc-status.json render/pacing summary only, no logs: fallback path)
#
# Usage: scripts/tests/M8DeviceCheckTest.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="${TMPDIR:-/tmp}/vrmc-m8-device-check-test"
rm -rf "$T"
mkdir -p "$T"

fail=0
check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "[m8-device-test] PASS: $name"; else echo "[m8-device-test] FAIL: $name"; fail=1; fi
}

write_pass_logs() { # write_pass_logs <dir> <display-hz> <target-hz>
  local dir="$1" hz="$2" target="$3"
  mkdir -p "$dir"
  cat > "$dir/vrmc-compositor.log" <<EOF
[vrmc-comp] starting compositor thread (generation 1)
[vrmc-comp] layer configuration colorFormat=115 depthFormat=252 foveation=1 layout=2 maxRenderQuality=1.00
[vrmc-comp] render quality: fixed 1.00 (max=1.00; Documents/vrmc-render-quality.txt=absent)
[vrmc-comp] frame pacing: minimumFrameRepeatCount=0 (0 = present every display frame)
[vrmc-comp] foveation rate map view 0 (left): screen=3660x3200 physical=2412x2108 layerCount=1 fovealCentrePhysical=(1206.00,1054.00) fovealScale=(1.000,1.000) drawable=2412x2108 viewport=(0,0,2412,2108) rateMaps=2
[vrmc-comp] render feedback: mono drawable (1 view, simulator); right logical size mirrored from left (3660x3200) for channel verification - device builds publish both eyes
[vrmc-comp] display geometry: logical L=3660x3200 R=3660x3200 physical drawable=2412x2108 foveation=1 rateMaps=2 renderQuality=1.00 (provider eye targets should track the logical size; foveation reduces physical memory/compositor cost, not the provider's own render cost)
[vrmc-comp] render feedback published: logical L=3660x3200 R=3660x3200 physical=2412x2108 foveation=1 rateMaps=2 quality=1.00 displayHz=0.0 frame=0.00ms
[vrmc-comp] render feedback: displayHz=${hz} presentHz=${hz} p50=8.34ms p95=8.71ms repeats=1/240 quality=1.00 logical L=3660x3200 R=3660x3200 physical=2412x2108 foveation=1 rateMaps=2 published=120 errors=0
[vrmc-comp] first presented frame: drawables=1 presented=1 views=2 frame=0 generation=1 -> posting VRMCCompositorRunning
EOF
  cat > "$dir/vrmc-shell.log" <<EOF
[shell] 2026-11-06 08:44:24 +0000 vrmc_shell_start invoked
[shell] 2026-11-06 08:44:26 +0000 onlaunch attempt 1 openImmersiveSpace result=opened epoch=0
[shell] 2026-11-06 08:44:27 +0000 layer config: supportsFoveation=true defaultRenderQuality=0.50 qualitySupported=true maxRenderQuality=1.00 supportedLayouts=["cp_layer_renderer_layout(rawValue: 0)", "cp_layer_renderer_layout(rawValue: 2)"]
[shell] 2026-11-06 08:44:27 +0000 layer config: layout=cp_layer_renderer_layout(rawValue: 0) foveation=true (supported=true disabledByFlag=false) maxRenderQuality=1.00
EOF
  cat > "$dir/vrmc-m8-trace.csv" <<'EOF'
frame,timestamp_ms,display_hz,target_hz,eye_w,eye_h,scale,resizes,missed_target,samples,p50_ms,p95_ms,foveation,rate_maps,quality,max_quality,content_first,reductions
240,1762418630000,120.04,120,1832,1600,0.50,1,2,240,8.31,9.75,1,2,1.00,1.00,0,0
480,1762418631000,120.00,120,2200,1928,0.60,2,0,240,8.29,9.10,1,2,1.00,1.00,0,0
EOF
  cat > "$dir/latestlog.txt" <<EOF
[21:36:02] [Render thread/INFO] (LoggedPrintStream) [STDOUT]: [VRMC-M8] render settings: logical L=3660x3200 R=3660x3200 drawable=2412x2108 foveation=1 rateMaps=2 (foveated display path) quality=1.00/1.00 displayHz=120.0 frame=8.34ms providerEye=0x0 frameIndex=1234
[21:36:04] [Render thread/INFO] (LoggedPrintStream) [STDOUT]: [VRMC-M8] eye target resize #1: 1024x1024 -> 1832x1600 (logical=3660x3200 scale=0.50 auto(default); displayHz=120.0 quality=1.00/1.00)
[21:36:10] [Render thread/INFO] (LoggedPrintStream) [STDOUT]: [VRMC-M8] render state frame=3600 eyeTarget=3664x3200 logical=3660x3200 drawable=2412x2108 foveation=1 rateMaps=2 displayHz=120.0 quality=1.00/1.00 scale=1.00(auto(file)) resizes=4
[21:36:25] [Render thread/INFO] (LoggedPrintStream) [STDOUT]: [VRMC-M5] diag: pollHz=119.9 frames=3597 maxGapMs=17.2 p50Ms=8.36 p95Ms=9.26 p95MaxMs=11.37 missed90=0 missedTarget=4 targetHz=${target} screen=none seated=false hands=L1 R1 displayViewsGen=21238 trackedFrames=26565 playerPresent=1 displayHz=${hz} foveation=1 rateMaps=2 logical=3660x3200 eyeTarget=3664x3200 scale=1.00 resizes=4
EOF
}

# --- case 1: 120 Hz device-like PASS ---------------------------------------------------------
write_pass_logs "$T/pass" 120.0 120
out=$("$ROOT/scripts/m8_device_check.sh" --from "$T/pass" 2>&1); rc=$?
echo "$out"
check "pass exit code 0" test "$rc" -eq 0
check "pass reports A6-A9" bash -c "echo \"\$1\" | grep -q 'RESULT: PASS (A6-A9)'" _ "$out"
check "pass reports 120 Hz" bash -c "echo \"\$1\" | grep -q 'displayHz=120.0 (120 Hz)'" _ "$out"
check "pass reports 4K-class logical" bash -c "echo \"\$1\" | grep -q 'logical L=3660x3200'" _ "$out"
check "pass reports m8 frame trace" bash -c "echo \"\$1\" | grep -q 'm8 frame trace: 2 window(s)'" _ "$out"

# --- case 2: 90 Hz -> PARTIAL --------------------------------------------------------------
write_pass_logs "$T/hz90" 90.0 90
out=$("$ROOT/scripts/m8_device_check.sh" --from "$T/hz90" 2>&1); rc=$?
check "hz90 exit code 2" test "$rc" -eq 2
check "hz90 names the cadence row" bash -c "echo \"\$1\" | grep -q '120 Hz NOT achieved'" _ "$out"
check "hz90 overall PARTIAL" bash -c "echo \"\$1\" | grep -q 'RESULT: PARTIAL'" _ "$out"

# --- case 3: old build / no M8 lines -> NOT RUN --------------------------------------------
write_pass_logs "$T/oldbuild" 120.0 120
grep -v 'M8\|foveation\|render feedback\|display geometry' "$T/oldbuild/vrmc-compositor.log" > "$T/oldbuild/compositor.tmp"
mv "$T/oldbuild/compositor.tmp" "$T/oldbuild/vrmc-compositor.log"
: > "$T/oldbuild/latestlog.txt"
out=$("$ROOT/scripts/m8_device_check.sh" --from "$T/oldbuild" 2>&1); rc=$?
check "oldbuild exit code 3" test "$rc" -eq 3
check "oldbuild reports NOT RUN" bash -c "echo \"\$1\" | grep -q 'RESULT: NOT RUN'" _ "$out"

# --- case 4: render-feedback publish failure -> FAIL ---------------------------------------
write_pass_logs "$T/failed" 120.0 120
echo "[vrmc-comp] render feedback publish FAILED rc=-1; the provider keeps its own eye-target sizing (bridge-side validation error)" >> "$T/failed/vrmc-compositor.log"
out=$("$ROOT/scripts/m8_device_check.sh" --from "$T/failed" 2>&1); rc=$?
check "failed exit code 4" test "$rc" -eq 4
check "failed reports FAIL" bash -c "echo \"\$1\" | grep -q 'RESULT: FAIL'" _ "$out"

# --- case 5: vrmc-status.json-only pull -> PASS via the status fallback ----------------------
mkdir -p "$T/status-only"
cat > "$T/status-only/vrmc-status.json" <<'EOF'
{
  "generatedAt": "2026-11-06T10:00:00Z",
  "abi": 3,
  "frameP50Ms": 8.36,
  "frameP95Ms": 9.26,
  "missed90Frames": 0,
  "render": "eyeTarget=3664x3200 displayLogical=3660x3200 drawable=2412x2108 foveation=1 rateMaps=2 displayHz=120.0 target=120(120Hz(file)) scale=1.00(auto) resizes=4 valid=1"
}
EOF
out=$("$ROOT/scripts/m8_device_check.sh" --from "$T/status-only" 2>&1); rc=$?
check "status-only pull exit code 0 (fallback)" test "$rc" -eq 0
check "status-only pull uses vrmc-status.json" bash -c "echo \"\$1\" | grep -q 'status=vrmc-status.json'" _ "$out"
check "status-only pull PASS A6-A9" bash -c "echo \"\$1\" | grep -q 'RESULT: PASS (A6-A9)'" _ "$out"

# --- case 6: trace-only cadence fallback (rotated feedback line) ------------------------------
# A real pull can lose the periodic 'render feedback: displayHz=' summary while the compositor geometry
# and the provider frame trace survive. A8 must then fall back to the trace's last display_hz.
mkdir -p "$T/trace-only"
cat > "$T/trace-only/vrmc-compositor.log" <<'EOF'
[vrmc-comp] starting compositor thread (generation 1)
[vrmc-comp] layer configuration colorFormat=115 depthFormat=252 foveation=1 layout=2 maxRenderQuality=1.00
[vrmc-comp] render quality: fixed 1.00 (max=1.00; Documents/vrmc-render-quality.txt=absent)
[vrmc-comp] frame pacing: minimumFrameRepeatCount=0 (0 = present every display frame)
[vrmc-comp] foveation rate map view 0 (left): screen=3660x3200 physical=2412x2108 layerCount=1 fovealCentrePhysical=(1206.00,1054.00) fovealScale=(1.000,1.000) drawable=2412x2108 viewport=(0,0,2412,2108) rateMaps=2
[vrmc-comp] display geometry: logical L=3660x3200 R=3660x3200 physical drawable=2412x2108 foveation=1 rateMaps=2 renderQuality=1.00 (provider eye targets should track the logical size; foveation reduces physical memory/compositor cost, not the provider's own render cost)
[vrmc-comp] render feedback published: logical L=3660x3200 R=3660x3200 physical=2412x2108 foveation=1 rateMaps=2 quality=1.00 displayHz=0.0 frame=0.00ms
EOF
cat > "$T/trace-only/vrmc-shell.log" <<'EOF'
[shell] 2026-11-06 08:44:27 +0000 layer config: supportsFoveation=true defaultRenderQuality=0.50 qualitySupported=true maxRenderQuality=1.00 supportedLayouts=["cp_layer_renderer_layout(rawValue: 0)", "cp_layer_renderer_layout(rawValue: 2)"]
[shell] 2026-11-06 08:44:27 +0000 layer config: layout=cp_layer_renderer_layout(rawValue: 0) foveation=true (supported=true disabledByFlag=false) maxRenderQuality=1.00
EOF
cat > "$T/trace-only/vrmc-m8-trace.csv" <<'EOF'
frame,timestamp_ms,display_hz,target_hz,eye_w,eye_h,scale,resizes,missed_target,samples,p50_ms,p95_ms,foveation,rate_maps,quality,max_quality,content_first,reductions
240,1762418630000,120.04,120,1832,1600,0.50,1,2,240,8.31,9.75,1,2,1.00,1.00,0,0
EOF
out=$("$ROOT/scripts/m8_device_check.sh" --from "$T/trace-only" 2>&1); rc=$?
check "trace-only pull exit code 2 (A7/A9 PARTIAL)" test "$rc" -eq 2
check "trace-only A8 falls back to the frame trace" bash -c "echo \"\$1\" | grep -q 'from vrmc-m8-trace.csv'" _ "$out"
check "trace-only prints the trace summary" bash -c "echo \"\$1\" | grep -q 'm8 frame trace: 1 window(s)'" _ "$out"

# --- case 7: malformed/binary logs must not crash the classifier ----------------------------
mkdir -p "$T/malformed"
head -c 2048 /dev/urandom > "$T/malformed/vrmc-compositor.log"
head -c 2048 /dev/urandom > "$T/malformed/latestlog.txt"
head -c 512 /dev/urandom > "$T/malformed/vrmc-shell.log"
out=$("$ROOT/scripts/m8_device_check.sh" --from "$T/malformed" 2>&1); rc=$?
check "malformed pull exit code 3 (NOT RUN)" test "$rc" -eq 3
check "malformed pull reports NOT RUN" bash -c "echo \"\$1\" | grep -q 'RESULT: NOT RUN'" _ "$out"
check "malformed pull has no Python traceback" bash -c "! echo \"\$1\" | grep -q 'Traceback'" _ "$out"

if [ "$fail" != "0" ]; then
  echo "[m8-device-test] RESULT: FAIL"
  exit 1
fi
echo "[m8-device-test] RESULT: PASS (7 classifier outcomes; host-only, no device)"
