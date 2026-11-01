# JIT scripts for the M1 device stack

`amethyst.js` — the StikDebug script assigned to the launcher for JIT26 in M1. It is the concatenation
of Amethyst's `UniversalJIT26.js` and `UniversalJIT26Extension.js` (both GPL-3.0, from
`AngelAuraMC/Amethyst-iOS`). The extension is required from **app launch** because Amethyst's startup
dyld validation bypass can issue JIT26 commands (including command 4, "prepare for patching") before the
game handshake sends the extension.

- sha256: `7fb4b14b7a9caa6e4723b9a41125030b15db6e4f7e8fb1d9be41f8be9f0fa9b9`
- Deploy: `scripts/push_jit_script.sh runtime/jit/amethyst.js`
- Assign on device: StikDebug → long-press the launcher → Assign Script → `amethyst.js`
- License: GPL-3.0 (same as the Amethyst source it comes from); see `THIRD_PARTY_NOTICES.md`.
