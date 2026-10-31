# Runtime (JVM/JIT on visionOS)

**Status:** not started. S1 groundwork, then C3.

Builds and packages the Java runtime that runs Minecraft 26.2 on visionOS, and owns the JIT launch
path.

Planned contents:

- `jre/` — OpenJDK 25 xros build scripts/patches (upstream: PojavLauncher mobile OpenJDK lineage).
- `jit/` — JIT26 (`brk #0xf00d`) request path, code-cache handling, launch-with-prepared-memory
  integration, and the failure UX when preparation is absent.
- `lwjgl/` — LWJGL 3.4.1 stubs/natives for visionOS (GLFW-no-API, Vulkan, OpenAL).
- `probes/` — the S1 reference-JVM harness (HotLoop + PrintCompilation capture).

Rules:

- S1 proves the mechanism with a reference JVM; C3 is the full OpenJDK 25 runtime
  (AGENT §4.5/§6). Do not conflate them.
- JIT evidence must include compiled-method output and a device run; the simulator is not evidence.
- All artifacts are hash-pinned in `versions.env`; no binaries committed.
