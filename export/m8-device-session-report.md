# M8 device-session report

Generated: 2026-11-07T09:04:55Z  -  pull: /tmp/vrmc-m8-device

Classifier: exit 2 - RESULT: PARTIAL (A8 display cadence=PARTIAL)

## Build identity (recorded candidate)

| item | value |
|---|---|
| bundle | dev.vrmc.vrmc (version 1.2.0) |
| app tree sha256 | 6773acf1504178f17115d9c49bf5c096903a1d5275d3b4e6a0d8535ad33280dc |
| framework sha256 | d53e148a49a7b2204a640de54a070ac61c35d64361c23ae499585beed2cabb45 |
| provider jar sha256 | 2cc9626aefc0fd3e9c81cd6289c9aa621f24dee829d698ebca2b4a66676396ad (144529 bytes) |
| device | <D1-UDID> |

## A6-A9 classifier output

    [m8-device] dir=/tmp/vrmc-m8-device
    [m8-device] logs: compositor=vrmc-compositor.log shell=vrmc-shell.log provider=MISSING status=vrmc-status.json
    row                                      status     detail
    A6 foveation active                      PASS       
    A7 4K-class display + provider eye targets PASS       provider eye target from vrmc-status.json render summary
    A8 display cadence                       PARTIAL    displayHz=90.0 (90 Hz; 120 Hz NOT achieved); repeated frames 0/240
    A9 pacing / regressions                  PASS       pacing from vrmc-status.json (90 ms window); provider: missedTarget=15 in the last window
      display: logical L=6261x5023 R=6261x5023 physical=2432x2368 foveation=1 rateMaps=2 quality=1.0
      vrmc-status.json render: eyeTarget=2824x2264 displayLogical=6261x5023 foveation=1 rateMaps=2 displayHz=90.0 target=0(auto(display)) resizes=6
      m8 frame trace: 420 window(s) displayHz 90.0-90.0 target=90 final eyeTarget=2824x2264 scale 0.25-0.65 (final 0.45) resizes=6
      measured display cadence: 90.0 Hz  foveated sharpening: 0.43
    [m8-device] RESULT: PARTIAL (A8 display cadence=PARTIAL)
    [m8-device] logs in /tmp/vrmc-m8-device

## Key log lines

    ### compositor
    [vrmc-comp] render feedback: displayHz=90.0 presentHz=88.5 p50=11.11ms p95=11.11ms repeats=3/240 quality=1.00 sharpen=0.43 logical L=6261x5023 R=6261x5023 physical=2432x2368 foveation=1 rateMaps=2 published=459 errors=0
    [vrmc-comp] render feedback: displayHz=90.0 presentHz=90.0 p50=11.11ms p95=11.11ms repeats=0/240 quality=1.00 sharpen=0.43 logical L=6261x5023 R=6261x5023 physical=2432x2368 foveation=1 rateMaps=2 published=471 errors=0
    [vrmc-comp] render feedback: displayHz=90.0 presentHz=89.6 p50=11.11ms p95=11.11ms repeats=1/240 quality=1.00 sharpen=0.43 logical L=6261x5023 R=6261x5023 physical=2432x2368 foveation=1 rateMaps=2 published=483 errors=0
    [vrmc-comp] render feedback: displayHz=90.0 presentHz=89.6 p50=11.11ms p95=11.11ms repeats=1/240 quality=1.00 sharpen=0.43 logical L=6261x5023 R=6261x5023 physical=2432x2368 foveation=1 rateMaps=2 published=495 errors=0
    [vrmc-comp] render feedback: displayHz=90.0 presentHz=89.6 p50=11.11ms p95=11.11ms repeats=1/240 quality=1.00 sharpen=0.43 logical L=6261x5023 R=6261x5023 physical=2432x2368 foveation=1 rateMaps=2 published=507 errors=0
    [vrmc-comp] render feedback: displayHz=90.0 presentHz=89.6 p50=11.11ms p95=11.11ms repeats=1/240 quality=1.00 sharpen=0.43 logical L=6261x5023 R=6261x5023 physical=2432x2368 foveation=1 rateMaps=2 published=519 errors=0
    [vrmc-comp] render feedback: displayHz=90.0 presentHz=90.0 p50=11.11ms p95=11.11ms repeats=0/240 quality=1.00 sharpen=0.43 logical L=6261x5023 R=6261x5023 physical=2432x2368 foveation=1 rateMaps=2 published=531 errors=0
    [vrmc-comp] render feedback: displayHz=90.0 presentHz=90.0 p50=11.11ms p95=11.11ms repeats=0/240 quality=1.00 sharpen=0.43 logical L=6261x5023 R=6261x5023 physical=2432x2368 foveation=1 rateMaps=2 published=543 errors=0

    ### provider

    ### shell
    [shell] 2026-11-07 09:02:39 +0000 layer config: supportsFoveation=true defaultRenderQuality=0.43500003 qualitySupported=true maxRenderQuality=1.00 supportedLayouts=["cp_layer_renderer_layout(rawValue: 0)", "cp_layer_renderer_layout(rawValue: 2)"]
    [shell] 2026-11-07 09:02:39 +0000 layer config: layout=cp_layer_renderer_layout(rawValue: 0) foveation=true (supported=true disabledByFlag=false) maxRenderQuality=1.00

## Frame trace (vrmc-m8-trace.csv)

Rows: 420

    frame,timestamp_ms,display_hz,target_hz,eye_w,eye_h,scale,resizes,missed_target,samples,p50_ms,p95_ms,foveation,rate_maps,quality,max_quality,content_first,reductions
    5280,1794042218325,90.00,90,2824,2264,0.45,6,2,240,11.34,13.78,1,2,1.00,1.00,1,0

## Operator visual statement

NOT PROVIDED. Record: image sharpness vs the pre-M8 build, jagged edges (SSAA/A-B), halo
impression of foveated sharpening, comfort at 90 vs 120 Hz, and whether 120 Hz was pursued.

## Interpretation / next steps

- PARTIAL: inspect the failing row(s) above; tune with
  scripts/push_m8_render_config.sh --target-hz/--eye-scale/--sharpening/--content-first,
  and --world-supersample 1.44 (relaunch) for the jaggedness A/B.
- Evidence bundle: VERIFY.md section 6 + docs/mvp/M8_DEVICE_HANDOFF.md; include this report as an
  artifact and pull the whole /tmp/vrmc-m8-device directory.
