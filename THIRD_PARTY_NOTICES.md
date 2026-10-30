# Third-party notices and licenses

VRMC's original source is licensed under Apache-2.0 (see `LICENSE`). This file lists
third-party software and services referenced by VRMC. **No Minecraft, Vivecraft, SteamVR,
Java runtime, or game-asset binaries are distributed with VRMC.**

## Runtime / user-installed (not bundled)

| Component | License / terms | How VRMC uses it |
| --- | --- | --- |
| Minecraft: Java Edition | Proprietary; Minecraft EULA and usage guidelines | User installs and owns it. VRMC does not distribute game code or assets. |
| Vivecraft (VivecraftMod) | LGPL-3.0 | User installs the unmodified mod. VRMC integrates at arm's length through SteamVR's public OpenVR interfaces and the network; no linking, patching, or redistribution. |
| Fabric Loader | Apache-2.0 | User installs; not bundled. |
| SteamVR | Steam Subscriber Agreement / SteamVR terms | User installs; VRMC does not distribute SteamVR binaries. |
| NVIDIA display driver / NVENC runtime | NVIDIA software license | Used at runtime via the user's driver; no NVIDIA binaries bundled. |

## Build / development dependencies

| Component | License | Use |
| --- | --- | --- |
| OpenVR SDK v2.15.6 (`headers/openvr_driver.h`, `openvr.h`) | BSD-3-Clause | SteamVR driver and host integration. Fetched/pinned at build time; notice retained. |
| NVIDIA Video Codec SDK headers (via FFmpeg nv-codec-headers) | MIT | NVENC encoding headers. No binaries bundled. |
| Apple Swift / SwiftUI / ARKit / CompositorServices / Metal / VideoToolbox / Network / CryptoKit | Apple SDK terms | visionOS client. |
| XcodeGen | MIT | Generates the Xcode project from `client/project.yml`. |
| Python 3 standard library | PSF-2.0 | Mock host, protocol tools, scripts. |
| CMake | BSD-3-Clause | Bridge build. |
| clang / MSVC | Apache-2.0 with LLVM exceptions / Microsoft license | Build toolchains. |

## OpenVR BSD-3-Clause notice

Copyright (c) 2015, Valve Corporation
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted
provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of
   conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of
   conditions and the following disclaimer in the documentation and/or other materials
   provided with the distribution.
3. Neither the name of Valve Corporation nor the names of its contributors may be used to
   endorse or promote products derived from this software without specific prior written
   permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

## Trademarks

Minecraft is a trademark of Microsoft Corporation. Vivecraft is a project of its respective
authors. Steam, SteamVR, and Valve are trademarks of Valve Corporation. Apple, Apple Vision
Pro, visionOS, Metal, and ARKit are trademarks of Apple Inc. VRMC is independent and is not
affiliated with or endorsed by any of these parties.
