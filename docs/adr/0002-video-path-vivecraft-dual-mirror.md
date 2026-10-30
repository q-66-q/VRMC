# ADR-0002 — Capture Vivecraft's DUAL mirror instead of implementing direct mode

- **Status:** Accepted
- **Date:** 2026-10-29
- **Related:** ADR-0001, `docs/feasibility/FEASIBILITY_AUDIT.md` §6
- **Verification:** S-02 (source inspection PARTIAL; runtime NOT RUN)

## Context

The remote architecture needs a per-eye stereo source from Vivecraft. OpenVR offers no public
API for an application to read the eye textures that another application submitted, except
through a display driver or the compositor mirror. The obvious high-performance option is a
direct-mode driver: the driver allocates swap textures, SteamVR composites into them, and the
driver encodes them. That is how mature streaming systems work, but it requires D3D11/OpenGL
interop, swapchain lifecycle, frame pacing, and careful handling of SteamVR updates.

Vivecraft itself has a **DUAL** desktop mirror mode. Source inspection of tag
`1.21.11-1.3.15` (`ShaderHelper.java`) shows it blits `framebufferEye[0]` to the left half and
`framebufferEye[1]` to the right half of the game's main render target. The mirror modes are
documented as having no performance penalty. The game window can therefore contain a complete
side-by-side stereo pair without modifying Vivecraft.

## Decision

Use Vivecraft's **DUAL mirror** rendered into a dedicated 3840×1080 borderless game window as
the v1 video source. Capture the window with Windows Graphics Capture (WGC), convert to NV12,
and encode with NVENC HEVC/H.264.

The virtual HMD driver still provides a display component so SteamVR/Vivecraft initialise, but
it implements **no direct-mode frame submission** and does not capture eye textures. Its own
compositor output window is not used for streaming.

The host:

- validates the window size and mirror mode before streaming;
- verifies left/right halves and `dualMirrorSwap`;
- crops nothing (`dualMirrorCrop = 0`) so the client receives the full eye images;
- treats window loss/resize as a recoverable capture failure;
- records actual capture resolution, frame age, and eye order in `StreamConfig`.

## Consequences

### Positive

- No direct-mode driver, no GPU texture interop, no swapchain complexity.
- Works with the unmodified Vivecraft release; no patch/maintenance burden.
- Small driver surface, easier to audit and test.
- Leaves SteamVR's compositor behaviour intact.
- Mirror frame is already the raw eye image (no lens distortion), ideal for client
  reprojection.

### Negative

- Adds desktop composition and WGC capture latency (estimated 2–6 ms) and a possible frame of
  delay.
- Requires a visible, correctly sized game window; exclusive fullscreen and some remote
  desktop configurations are problematic.
- Captures at the game window's DUAL layout, not necessarily the HMD's recommended texture
  size; resolution/aspect must match the virtual HMD projection.
- Window manager/DPI/scaling issues can corrupt geometry; the host must validate.
- A future SteamVR/Vivecraft change to mirror behaviour can break capture; version pinning and
  a smoke test are required.

### Neutral

- The mirror is not an official stable API. It is a documented user-facing feature, but it can
  change between Vivecraft versions. Compatibility is verified per pinned version.
- If capture latency dominates, the direct-mode driver remains the upgrade path.

## Alternatives considered

| Alternative | Why not now |
| --- | --- |
| Direct-mode driver capture (ALVR-style) | Better potential latency, but 4–8× more driver complexity and risk; defer until measurements justify it. |
| OpenVR compositor mirror texture API | Public mirror API is generally one eye / distorted; not suitable for full stereo and not intended for frame transport. |
| SteamVR `GetMirrorTextureD3D11` | Same issue; no guaranteed per-eye stereo pair, compositor-dependent. |
| Capture the virtual HMD's desktop window | Same as DUAL mirror but only if the driver's compositor window is per-eye; our virtual display is not designed for that and DUAL is simpler. |
| Patch Vivecraft to expose eye textures | LGPL fork, version churn, violates unmodified-Vivecraft goal. |

## Implementation notes

- Set `displayMirrorMode = DUAL`, `dualMirrorSwap = false` initially, `dualMirrorCrop = 0`,
  mirror GUI as configured by the test plan.
- Game window: borderless, 3840×1080, no DPI scaling on the target monitor; verify WGC bounds.
- Capture at the window's client area, not the monitor; use a frame pool with a small ring.
- Eye textures are copied as one SBS frame; do not split/re-encode separately in v1.
- `StreamConfig` includes `width=3840`, `height=1080`, `eyeWidth=1920`, `eyeHeight=1080`,
  `eyeOrder=leftRight`, `projection`, `ipd`, `displayHz=90`.
- If the window cannot be captured at 72+ fps for 10 minutes, run S-02 fallback: evaluate
  direct mode (new ADR) before polishing M3.

## Revisit triggers

- DUAL capture cannot sustain 72 fps or shows tearing/missing eyes.
- Window capture latency exceeds the media budget after optimization.
- Vivecraft changes/removes DUAL mirror behaviour in a required version.
- User needs a setup where a visible game window is impossible (headless service).
