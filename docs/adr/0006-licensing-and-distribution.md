# ADR-0006 — Licensing, distribution, and platform compliance

- **Status:** Accepted
- **Date:** 2026-10-29
- **Related:** ADR-0001, `THIRD_PARTY_NOTICES.md`, `docs/user/INSTALL.md`
- **Verification:** `VERIFY.md` §8 (NOT RUN)

## Context

VRMC integrates with proprietary Minecraft, LGPL-3.0 Vivecraft, SteamVR/OpenVR, NVIDIA
encoding, and Apple's visionOS. A release must respect all licenses, the Minecraft EULA,
Apple platform rules, and user privacy. The project must be reproducible for a developer
without distributing game or mod binaries.

## Decision

1. **VRMC original code is Apache-2.0.** This applies to the client, protocol, host, driver,
   tools, and docs authored for VRMC. Third-party components retain their licenses and are
   listed in `THIRD_PARTY_NOTICES.md`.
2. **No Minecraft, Minecraft assets, Vivecraft JARs, SteamVR binaries, Java runtimes, or
   mod-loader binaries are committed or shipped.** Install scripts fetch user-owned/official
   artifacts from their official sources with pinned checksums, or instruct the user to
   install them. Release artifacts contain only VRMC code.
3. **Vivecraft is used unmodified at arm's length.** VRMC communicates through SteamVR's
   public OpenVR interfaces and the network. It does not link to, patch, decompile, or
   redistribute Vivecraft. No Vivecraft source is copied into VRMC. If a companion mod is
   ever added, it must be LGPL-3.0, separately distributed, and approved by a new ADR.
4. **OpenVR SDK is BSD-3-Clause.** Pin v2.15.6 (or a reviewed later version), include the
   notice, and use only public headers/interfaces.
5. **NVIDIA NVENC** is accessed via the NVIDIA driver/runtime and redistributable headers;
   include the NVIDIA notice. Do not bundle NVIDIA binaries. FFmpeg, if used, must be a
   separate LGPL-compatible build or dynamically linked with notices; no GPL binary in the
   repo.
6. **Apple compliance:** public APIs only; no JIT, jailbreak, private entitlements, or
   sideload-only capabilities required for the documented distribution path. The app includes
   `NSHandsTrackingUsageDescription`, `NSLocalNetworkUsageDescription`, a privacy manifest,
   and an encryption export declaration. Hand/video data stays on the user's LAN by default.
7. **TestFlight/Ad Hoc is the v1 distribution path.** App Store distribution is not assumed;
   if pursued, a policy review is required before claiming support.
8. **Minecraft EULA:** user must own Minecraft; VRMC does not bypass authentication or
   distribute game content; server play uses normal Minecraft/Vivecraft networking.
9. **Security and privacy:** encrypted sessions, pairing, no telemetry by default, no hand or
   video data in logs, user-initiated diagnostics. Release artifacts include a privacy
   manifest and data-flow documentation.
10. **Attribution:** README and notices credit Vivecraft, OpenVR, Fabric, Minecraft, NVIDIA,
    Apple frameworks, and any other dependencies accurately, without implying endorsement.

## Consequences

### Positive

- Clean legal boundary and reproducible user setup.
- No copyrighted binaries in the repository or CI artifacts.
- Compatible with normal Apple developer distribution and privacy expectations.
- Users can update Minecraft/Vivecraft independently; VRMC does not fork them.

### Negative

- Setup is multi-step and depends on third-party installers/accounts.
- Version drift can break compatibility; pins/checksums and compatibility tests are required.
- LGPL compliance for any future companion mod constrains design.
- App Store review may still reject remote-game-streaming or local-network features; v1 does
  not promise App Store availability.

### Neutral

- The driver is installed into SteamVR's drivers directory by a user-run script; it is not
  bundled with SteamVR.
- Minecraft/Vivecraft are downloaded by the user, not by VRMC CI.

## Required release checks

- Artifact scan: no `.jar` for Minecraft/Vivecraft/Fabric, no Minecraft assets, no SteamVR
  binaries, no Java runtime.
- `THIRD_PARTY_NOTICES.md` complete and accurate; OpenVR/NVIDIA/FFmpeg notices included.
- License headers/SPDX identifiers on new source files.
- Privacy manifest, usage strings, local-network purpose, encryption declaration validated.
- No private API symbols; `nm`/static analysis and App Store validation.
- Pairing/encryption implemented; logs redacted; data-flow diagram current.
- User guide tells the user to purchase/install Minecraft and install Vivecraft/SteamVR
  themselves.

## Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Bundle Vivecraft/Minecraft for convenience | Violates EULA/LGPL distribution terms and acceptance constraints. |
| Fork Vivecraft and ship a patched JAR | LGPL obligations, version churn, violates unmodified runtime goal. |
| GPL the entire project | Not required; would complicate proprietary host components and adoption; Apache-2.0 is sufficient for original code. |
| Ignore encryption for LAN | Privacy/App Review/security risk; unacceptable for hand and video data. |
| Rely on App Store only | Adds policy risk and delays; TestFlight/Ad Hoc is a legitimate v1 path. |

## Revisit triggers

- Addition of a companion mod or any Vivecraft-derived code → new ADR + LGPL review.
- App Store submission → dedicated policy/privacy review.
- New codec/transport dependency → license and notice update.
- Apple changes hand-tracking/local-network permissions → update usage strings and tests.
