import Foundation

// Host tests for runtime/native-shell/Sources/ModProvisioner.swift (built by tests/run_tests.sh).
// Each case runs in a fresh temp "Documents" tree; prints "[provisioning-test] PASS" on success.

@main
struct ModProvisionerTests {
    static var checks = 0
    static var failures = 0

    static func check(_ condition: Bool, _ label: String, file: StaticString = #file, line: UInt = #line) {
        checks += 1
        if !condition {
            failures += 1
            print("[provisioning-test] FAIL \(label) (line \(line))")
        }
    }

    struct Sandbox {
        let root: URL
        var docs: URL { root.appendingPathComponent("Documents") }
        var mods: URL { docs.appendingPathComponent("instances/default/mods") }
        var bundle: URL { root.appendingPathComponent("App.app/vrmc") }
        var bundledProvider: URL { bundle.appendingPathComponent("vrmc-provider.jar") }

        init() {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("vrmc-provisioning-\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            try! FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        }

        func write(_ text: String, to url: URL) {
            try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try! Data(text.utf8).write(to: url)
        }

        func read(_ url: URL) -> String? {
            return (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
        }

        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

        func provisioner(pin: String? = nil, bundled: Bool = true) -> ModProvisioner {
            var manifest = ModProvisioningManifest.builtIn
            if let pin { manifest.vivecraftSha256 = pin }
            return ModProvisioner(documentsDir: docs, modsDir: mods,
                                  bundledProvider: bundled ? bundledProvider : nil, manifest: manifest)
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    static func sha(_ text: String, in sandbox: Sandbox) -> String {
        let url = sandbox.root.appendingPathComponent("hash-\(UUID().uuidString)")
        sandbox.write(text, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return ModProvisioner.sha256(of: url)!
    }

    static func main() {
        freshInstall()
        upToDateAndAdoption()
        upgradeOnlyWhenUntouched()
        userManagedKept()
        resetFlag()
        noBundle()
        vivecraftImport()
        vivecraftInbox()
        vivecraftRejected()
        vivecraftInstalledStates()
        duplicates()
        manifestLoading()
        reportLines()
        print("[provisioning-test] \(checks) checks, \(failures) failures")
        if failures == 0 {
            print("[provisioning-test] PASS")
        } else {
            print("[provisioning-test] FAILED")
            exit(1)
        }
    }

    static func freshInstall() {
        let s = Sandbox(); defer { s.cleanup() }
        s.write("provider-v1", to: s.bundledProvider)
        let report = s.provisioner().run()
        let h = sha("provider-v1", in: s)
        check(report.provider == .installed(sha256: h), "fresh: provider installed")
        check(s.read(s.mods.appendingPathComponent("vrmc-provider.jar")) == "provider-v1", "fresh: jar content")
        check(s.exists(s.docs.appendingPathComponent("vrmc-provisioning.json")), "fresh: state written")
        check(report.vivecraft == .missing, "fresh: vivecraft missing")
        check(!report.ready && report.providerPresent, "fresh: not ready without vivecraft")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: s.mods.path)) ?? []
        check(leftovers == ["vrmc-provider.jar"], "fresh: no temp files left (\(leftovers))")
    }

    static func upToDateAndAdoption() {
        let s = Sandbox(); defer { s.cleanup() }
        s.write("provider-v1", to: s.bundledProvider)
        // Manually copied identical jar, no state file: adopted as up to date.
        s.write("provider-v1", to: s.mods.appendingPathComponent("vrmc-provider.jar"))
        let report = s.provisioner().run()
        check(report.provider == .upToDate(sha256: sha("provider-v1", in: s)), "uptodate: identical jar")
        check(s.exists(s.docs.appendingPathComponent("vrmc-provisioning.json")), "uptodate: adopted into state")
        // Bundle moves on -> adopted jar upgrades.
        s.write("provider-v2", to: s.bundledProvider)
        let next = s.provisioner().run()
        check(next.provider == .upgraded(from: sha("provider-v1", in: s), to: sha("provider-v2", in: s)),
              "uptodate: adopted jar upgrades later")
    }

    static func upgradeOnlyWhenUntouched() {
        let s = Sandbox(); defer { s.cleanup() }
        s.write("provider-v1", to: s.bundledProvider)
        _ = s.provisioner().run()
        s.write("provider-v2", to: s.bundledProvider)
        let report = s.provisioner().run()
        check(report.provider == .upgraded(from: sha("provider-v1", in: s), to: sha("provider-v2", in: s)),
              "upgrade: outcome")
        check(s.read(s.mods.appendingPathComponent("vrmc-provider.jar")) == "provider-v2", "upgrade: content")
        let again = s.provisioner().run()
        check(again.provider == .upToDate(sha256: sha("provider-v2", in: s)), "upgrade: idempotent")
    }

    static func userManagedKept() {
        let s = Sandbox(); defer { s.cleanup() }
        s.write("provider-v1", to: s.bundledProvider)
        _ = s.provisioner().run()
        // Developer push replaces the jar; a later app update must not clobber it.
        s.write("provider-dev", to: s.mods.appendingPathComponent("vrmc-provider.jar"))
        s.write("provider-v2", to: s.bundledProvider)
        let report = s.provisioner().run()
        check(report.provider == .userManaged(sha256: sha("provider-dev", in: s)), "user-managed: outcome")
        check(s.read(s.mods.appendingPathComponent("vrmc-provider.jar")) == "provider-dev", "user-managed: kept")
        check(report.providerPresent, "user-managed: counts as present")
    }

    static func resetFlag() {
        let s = Sandbox(); defer { s.cleanup() }
        s.write("provider-v1", to: s.bundledProvider)
        s.write("provider-dev", to: s.mods.appendingPathComponent("vrmc-provider.jar"))
        let flag = s.docs.appendingPathComponent("vrmc-provider-reset.flag")
        s.write("", to: flag)
        let report = s.provisioner().run()
        check(report.provider == .reset(sha256: sha("provider-v1", in: s)), "reset: outcome")
        check(s.read(s.mods.appendingPathComponent("vrmc-provider.jar")) == "provider-v1", "reset: bundled restored")
        check(!s.exists(flag), "reset: flag consumed")
        // Flag on an already-current jar is consumed and harmless.
        s.write("", to: flag)
        check(s.provisioner().run().provider == .upToDate(sha256: sha("provider-v1", in: s)), "reset: no-op when current")
        check(!s.exists(flag), "reset: flag consumed when current")
    }

    static func noBundle() {
        let s = Sandbox(); defer { s.cleanup() }
        check(s.provisioner(bundled: false).run().provider == .noBundle(installedSha256: nil), "nobundle: missing")
        s.write("provider-dev", to: s.mods.appendingPathComponent("vrmc-provider.jar"))
        let report = s.provisioner(bundled: false).run()
        check(report.provider == .noBundle(installedSha256: sha("provider-dev", in: s)), "nobundle: present")
        check(report.providerPresent, "nobundle: present counts")
        // Bundled path configured but file absent behaves the same.
        check(s.provisioner(bundled: true).run().provider == .noBundle(installedSha256: sha("provider-dev", in: s)),
              "nobundle: configured but absent")
    }

    static func vivecraftImport() {
        let s = Sandbox(); defer { s.cleanup() }
        s.write("provider-v1", to: s.bundledProvider)
        let drop = s.docs.appendingPathComponent("vivecraft-26.2-1.3.15-fabric (1).jar")
        s.write("vivecraft-official", to: drop)
        let report = s.provisioner(pin: sha("vivecraft-official", in: s)).run()
        check(report.vivecraft == .imported(from: "vivecraft-26.2-1.3.15-fabric (1).jar"), "import: outcome")
        check(s.read(s.mods.appendingPathComponent("vivecraft-26.2-1.3.15-fabric.jar")) == "vivecraft-official",
              "import: canonical name")
        check(!s.exists(drop), "import: source moved")
        check(report.ready, "import: ready")
        let again = s.provisioner(pin: sha("vivecraft-official", in: s)).run()
        check(again.vivecraft == .verified(fileName: "vivecraft-26.2-1.3.15-fabric.jar"), "import: verified next launch")
    }

    static func vivecraftInbox() {
        let s = Sandbox(); defer { s.cleanup() }
        s.write("vivecraft-official", to: s.docs.appendingPathComponent("Inbox/Vivecraft-fabric.jar"))
        let report = s.provisioner(pin: sha("vivecraft-official", in: s)).run()
        check(report.vivecraft == .imported(from: "Vivecraft-fabric.jar"), "inbox: AirDrop import, case-insensitive")
    }

    static func vivecraftRejected() {
        let s = Sandbox(); defer { s.cleanup() }
        let drop = s.docs.appendingPathComponent("vivecraft-tampered.jar")
        s.write("vivecraft-tampered", to: drop)
        let report = s.provisioner(pin: sha("vivecraft-official", in: s)).run()
        check(report.vivecraft == .rejected(fileName: "vivecraft-tampered.jar", sha256: sha("vivecraft-tampered", in: s)),
              "reject: outcome")
        check(s.exists(drop), "reject: left in place")
        check(!s.exists(s.mods.appendingPathComponent("vivecraft-26.2-1.3.15-fabric.jar")), "reject: not installed")
        // A good jar alongside a bad one still imports.
        s.write("vivecraft-official", to: s.docs.appendingPathComponent("vivecraft-z.jar"))
        let next = s.provisioner(pin: sha("vivecraft-official", in: s)).run()
        check(next.vivecraft == .imported(from: "vivecraft-z.jar"), "reject: good candidate wins")
        // No pin -> never imports.
        let t = Sandbox(); defer { t.cleanup() }
        t.write("vivecraft-official", to: t.docs.appendingPathComponent("vivecraft.jar"))
        check(t.provisioner(pin: "").run().vivecraft == .noPin, "reject: empty pin disables import")
        check(t.provisioner(pin: "TBD").run().vivecraft == .noPin, "reject: TBD pin disables import")
    }

    static func vivecraftInstalledStates() {
        let s = Sandbox(); defer { s.cleanup() }
        s.write("vivecraft-other-version", to: s.mods.appendingPathComponent("vivecraft-26.2-1.4.0-fabric.jar"))
        let report = s.provisioner(pin: sha("vivecraft-official", in: s)).run()
        check(report.vivecraft == .unverified(fileName: "vivecraft-26.2-1.4.0-fabric.jar",
                                              sha256: sha("vivecraft-other-version", in: s)),
              "installed: unverified kept")
        check(report.vivecraftPresent, "installed: unverified still present")
        check(s.exists(s.mods.appendingPathComponent("vivecraft-26.2-1.4.0-fabric.jar")), "installed: not deleted")
    }

    static func duplicates() {
        let s = Sandbox(); defer { s.cleanup() }
        s.write("a", to: s.mods.appendingPathComponent("vrmc-provider.jar"))
        s.write("b", to: s.mods.appendingPathComponent("vrmc-provider-old.jar"))
        s.write("c", to: s.mods.appendingPathComponent("vivecraft-a.jar"))
        s.write("d", to: s.mods.appendingPathComponent("vivecraft-b.jar"))
        s.write("e", to: s.mods.appendingPathComponent("vivecraft-c.jar.disabled"))
        let warnings = s.provisioner(bundled: false).run().warnings
        check(warnings.count == 2, "dupes: two warnings (\(warnings))")
        check(warnings.first?.contains("vrmc-provider-old.jar") == true, "dupes: names provider duplicate")
        check(warnings.last?.contains("vivecraft-b.jar") == true, "dupes: names vivecraft duplicate")
        check(warnings.allSatisfy { !$0.contains(".disabled") }, "dupes: disabled jars ignored")
    }

    static func manifestLoading() {
        let s = Sandbox(); defer { s.cleanup() }
        check(ModProvisioningManifest.load(from: nil) == .builtIn, "manifest: nil -> built-in")
        let url = s.bundle.appendingPathComponent("provisioning.json")
        s.write("not json", to: url)
        check(ModProvisioningManifest.load(from: url) == .builtIn, "manifest: garbage -> built-in")
        let pin = String(repeating: "AB", count: 32)
        s.write("{\"vivecraftFileName\":\"vivecraft-x.jar\",\"vivecraftSha256\":\"\(pin)\"}", to: url)
        let loaded = ModProvisioningManifest.load(from: url)
        check(loaded.vivecraftFileName == "vivecraft-x.jar", "manifest: file name")
        check(loaded.vivecraftSha256 == pin.lowercased(), "manifest: pin lower-cased")
        s.write("{\"vivecraftFileName\":\"../escape.jar\",\"vivecraftSha256\":\"TBD\"}", to: url)
        check(ModProvisioningManifest.load(from: url) == .builtIn, "manifest: unsafe name / TBD pin rejected")
        check(ModProvisioningManifest.isHexSha256(ModProvisioningManifest.builtIn.vivecraftSha256),
              "manifest: built-in pin well-formed")
    }

    static func reportLines() {
        let report = ModProvisionReport(provider: .missingLike, vivecraft: .missing, warnings: ["w"])
        check(report.lines.count == 3, "report: three lines")
        check(report.lines[0].contains("MISSING"), "report: provider missing wording")
        check(report.lines[2] == "warning: w", "report: warning prefix")
        let failed = ModProvisionReport(provider: .failed("x"), vivecraft: .failed("x"), warnings: [])
        check(!failed.ready && !failed.providerPresent && !failed.vivecraftPresent, "report: failure not ready")
    }
}

extension ProviderProvisionOutcome {
    static var missingLike: ProviderProvisionOutcome { .noBundle(installedSha256: nil) }
}
