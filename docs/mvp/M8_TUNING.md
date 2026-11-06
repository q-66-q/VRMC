# M8 rendering tuning guide (generated)

Generated 2026-11-06T11:02:40Z on host GPU Apple M4 Pro by scripts/m8_tuning_guide.py.

This guide combines the **measured host quality ladder** (what the compositor's flat vs
fovea-weighted sharp shader does at each provider eye-target scale) with **pixel budgets**
for the expected device-class logical per-eye size 3660x3200.
Host numbers are a resampling proxy, not device optics; device acceptance still needs A6-A9
plus the operator visual statement (docs/mvp/M8_DEVICE_RUN.md, M8_DEVICE_HANDOFF.md).

## Measured upscale ladder (host Metal, synthetic pattern)

| eye scale | eye target | upscale | auto sharpening | PSNR bilinear | PSNR sharp | dPSNR | edge acutance |
|---|---|---|---|---|---|---|---|
| 0.400 | 768x432 | 2.50x | 0.450 | 14.31 dB | 14.22 dB | -0.09 | 1.11x |
| 0.500 | 960x540 | 2.00x | 0.350 | 22.16 dB | 21.65 dB | -0.51 | 1.12x |
| 0.625 | 1200x675 | 1.60x | 0.210 | 22.60 dB | 22.38 dB | -0.22 | 1.09x |
| 0.750 | 1440x810 | 1.33x | 0.117 | 22.19 dB | 22.14 dB | -0.05 | 1.03x |
| 1.000 | 1920x1080 | 1.00x | 0.000 | 99.00 dB | 99.00 dB | +0.00 | 1.00x |

Reading: the auto sharpening strength is the compositor formula (min(0.45,
(upscale-1)*0.35), zero at <=1.02); it is an acutance trade (bounded PSNR cost), and
raising the provider eye-target resolution is by far the largest sharpness lever.

## Device-class pixel budgets (per eye, logical 3660x3200)

| eye scale | eye target | eye MP | world target (SSAA 1.44x) | world MP | 2-eye world MP | SSAA pixel cost |
|---|---|---|---|---|---|---|
| 0.400 | 1464x1280 | 1.87 | 1757x1536 | 2.70 | 5.40 | 1.44x |
| 0.500 | 1830x1600 | 2.93 | 2196x1920 | 4.22 | 8.43 | 1.44x |
| 0.625 | 2288x2000 | 4.58 | 2746x2400 | 6.59 | 13.18 | 1.44x |
| 0.750 | 2745x2400 | 6.59 | 3294x2880 | 9.49 | 18.97 | 1.44x |
| 1.000 | 3660x3200 | 11.71 | 4392x3840 | 16.87 | 33.73 | 1.44x |

Budgets are the *world-render* pixels per frame (both eyes) at the given eye-target
scale, with and without the startup SSAA knob; the compositor's foveated drawable cost is
separate and covered by the max-render-quality knob.

## Recommendations for the D1 A/B

- 120 Hz first (the objective's hard part): start at --eye-scale 0.5 --target-hz 120
  --content-first on --sharpening auto. The ladder shows 0.4 is ~8 dB below 0.5, so prefer
  0.5+ and let the auto policy/content-first keep the cadence; watch the frame trace.
- Image quality at 90 Hz: raise --eye-scale toward 0.75-1.0 and/or enable
  --world-supersample 1.44 (SSAA, 1.44x world pixels, startup-only; relaunch). Sharpening is
  a no-op at scale 1.0 and mainly helps the sub-native 120 Hz case.
- Sharpening A/B: --sharpening off vs auto at the same eye scale; judge halos at edges.
- Whatever the result, collect it with scripts/m8_device_session.sh collect --report so the
  frame trace, A6-A9 and operator statement land in one artifact.

Commands (live unless noted):

    scripts/push_m8_render_config.sh --eye-scale 0.5 --target-hz 120 \
        --content-first on --sharpening auto
    scripts/push_m8_render_config.sh --world-supersample 1.44    # next launch (SSAA)
    scripts/push_m8_render_config.sh --sharpening off             # halo A/B

