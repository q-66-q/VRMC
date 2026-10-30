# Release Checklist

The authoritative release gate is [`VERIFY.md`](../../VERIFY.md) §10. This page is the release
engineer's runbook; it must not override VERIFY.

## 1. Freeze

- [ ] `main` clean, CI green, tag `vX.Y.Z-rc.N` created from the verified commit.
- [ ] `versions.env` pins Xcode/Swift/visionOS, OpenVR, NVENC headers, Minecraft/Fabric/
      Vivecraft, SteamVR baseline; hashes verified.
- [ ] No game/mod/SteamVR binaries, assets, secrets, device dumps, or build outputs in Git.
- [ ] `AGENT.md`, `VERIFY.md`, ADRs, protocol/hand/streaming docs current.

## 2. Build

```bash
./scripts/bootstrap.sh
./scripts/test_all.sh
./scripts/build_client.sh --device      # signed with release team
pwsh ./scripts/build_bridge.ps1 -Configuration Release   # on Windows
```

- [ ] Clean-checkout builds reproduced on a second machine.
- [ ] App archive/`Info.plist`/privacy manifest validated; usage strings correct.
- [ ] Driver DLL signed (if distribution requires) and manifest/resources complete.
- [ ] Host DLL/driver dependency scan: no unexpected runtime DLLs; NVENC is driver-provided.

## 3. Verify

- [ ] `VERIFY.md` AC-1..AC-6 all `PASS` with linked evidence.
- [ ] MT-01..MT-12 complete; NF-01..NF-15/HT-08..HT-10 pass or signed limitations.
- [ ] Latency report has raw CSV/camera evidence and meets AC-4 or has an accepted waiver.
- [ ] 60-minute soak; memory/thermal/fps; no P0/P1 defects.
- [ ] Security review: pairing/AEAD/replay/rate limiting; logs redacted. **Current dev build
      fails this item (insecure transport).**
- [ ] New-user reproducibility (MT-12) by a non-author.

## 4. Package

```bash
./scripts/package_release.sh X.Y.Z
./scripts/verify_release.sh X.Y.Z
```

- [ ] `artifacts/X.Y.Z/` contains client archive, Windows bridge zip, LICENSE,
      THIRD_PARTY_NOTICES, SHA256SUMS.
- [ ] No copyrighted game/mod content in artifacts.
- [ ] Release notes list features, known limitations, install/run links, and checksums.
- [ ] TestFlight/Ad Hoc build uploaded; device install verified from the artifact.

## 5. Sign-off

- [ ] Integration, verification, client, bridge, and release owners sign `VERIFY.md` §10.5.
- [ ] Tag `vX.Y.Z` (immutable), publish notes, archive evidence and CI logs.
- [ ] Post-release: monitor issues; ban any release that lacks evidence.

**Do not ship while `VERIFY.md` contains BLOCKED/NOT RUN acceptance rows or while the
insecure transport is the default.**
