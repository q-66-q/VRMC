# M8 quality ladder (host Metal probe)

Purpose: put numbers on the compositor's upscale trade so the device A/B (and the sharpening default)
has an objective baseline. The probe builds a 1920x1080 procedural reference, box-downsamples it to
several "game eye-target" sizes (the scale the provider would choose for 120 Hz), then upscales it back
into a 1920x1080 logical drawable with the compositor's **flat** shader and with its **fovea-weighted
sharp** shader at the auto strength the compositor would use, and measures both against the reference.

Metrics exclude the top 1.5% of rows (the compositor's green mode-badge strip).

| eye-target scale | eye target | upscale | auto sharpening | PSNR bilinear | PSNR sharp | Δ PSNR | edge-acutance ratio |
|---|---|---|---|---|---|---|---|
| 0.400 | 768x432 | 2.50x | 0.450 | 14.31 dB | 14.22 dB | −0.09 | **1.11x** |
| 0.500 | 960x540 | 2.00x | 0.350 | 22.16 dB | 21.65 dB | −0.51 | **1.12x** |
| 0.625 | 1200x675 | 1.60x | 0.210 | 22.60 dB | 22.38 dB | −0.22 | **1.09x** |
| 0.750 | 1440x810 | 1.33x | 0.117 | 22.19 dB | 22.14 dB | −0.05 | **1.03x** |
| 1.000 | 1920x1080 | 1.00x | 0.000 | 99.0 dB | 99.0 dB | 0.00 | 1.00x |

(Apple M4 Pro; the exact dB values are pattern/resampling dependent — the probe asserts the stable
properties, not these numbers.)

Interpretation:
- a **smaller eye target costs real detail** (0.4x is ~8 dB below 0.5x on this pattern), so the M8
  auto policy raising the provider resolution is doing the heavy lifting for sharpness;
- **foveated sharpening is an acutance trade, not a PSNR win**: it lowers PSNR by ≤0.5 dB while raising
  edge acutance 3–12% (stronger at aggressive upscales, which is what the auto strength targets);
- at scale 1.0 the auto strength is 0, so the pass is a no-op (identity, 99 dB) — matches the
  compositor's `upscale > 1.02` gate;
- 120 Hz at 4K-class per eye will run well below scale 1.0 on device, so the aggressive-upscale rows
  (0.4–0.625) are the relevant ones: expect sharper edges than bilinear with a small bounded fidelity
  cost, best combined with the SSAA knob when the goal is image quality at 90 Hz.

Checks (7): smallest eye target clearly worst; milder upscale clearly better; identity lossless; no
sharpening at identity; acutance gain at every upscaled scale; gain shrinks as upscale shrinks;
fidelity trade bounded (≤1.5 dB).

Run: `runtime/probes/m8-quality-ladder/run.sh` (exit 0 PASS / 1 FAIL / 2 SKIP).
