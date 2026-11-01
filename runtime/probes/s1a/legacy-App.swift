import SwiftUI

@_silgen_name("vrmc_open_log") func vrmc_open_log(_ path: UnsafePointer<CChar>)
@_silgen_name("vrmc_run_java") func vrmc_run_java(_ bundlePath: UnsafePointer<CChar>) -> Int32

@main
struct S1AApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var status = "starting…"
    var body: some View {
        VStack(spacing: 12) {
            Text("VRMC S1a JIT probe").font(.headline)
            Text(status).font(.system(.body, design: .monospaced))
        }
        .padding()
        Button("Run JVM") { start() }
            .buttonStyle(.borderedProminent)
    }

    private func start() {
        let bundle = Bundle.main.bundlePath
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        let logPath = (docs as NSString).appendingPathComponent("s1a-jit.log")
        logPath.withCString { vrmc_open_log($0) }
        DispatchQueue.global(qos: .userInitiated).async {
            let rc = bundle.withCString { vrmc_run_java($0) }
            DispatchQueue.main.async { status = "JLI_Launch rc=\(rc)" }
        }
    }
}
