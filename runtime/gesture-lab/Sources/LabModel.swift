import Foundation
import SwiftUI
import RealityKit
import ARKit
import simd
import AVFoundation

/// Gesture Lab: a standalone visionOS app that records labelled ARKit hand-skeleton + head data so the
/// M7 gesture thresholds can be fitted offline (scripts/m7_lab_*.py, scripts/m7_eval_replay.py) and
/// replayed through the real engine (provider M7LabReplay). Recordings are JSON Lines files in the
/// app's Documents (`gesturelab-<LABEL>-<timestamp>.jsonl`), pulled with scripts/m7_pull_lab_data.sh.
@MainActor
final class LabModel: ObservableObject {
    @Published private(set) var running = false
    @Published var status = "not started"
    @Published private(set) var visibleJointCount = 0
    @Published private(set) var sampleCount = 0
    @Published var classification = "idle"
    @Published var selectedLabel = "CLIMB_ALTERNATE"
    @Published var recording = false
    @Published var recordFile = "—"
    @Published var logFile = "gesturelab.log"
    @Published var guidedActive = false
    @Published var guidedPrompt = "ready"
    @Published var guidedProgress = ""
    @Published var recordRemaining = 0
    @Published var headTracked = false
    @Published var headPositionText = "—"
    @Published var leftFeatures = "—"
    @Published var rightFeatures = "—"

    let root = Entity()
    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private let worldTracking = WorldTrackingProvider()
    private let classifier = LabClassifier()
    private var jointEntities: [String: ModelEntity] = [:]
    private var boneEntities: [String: ModelEntity] = [:]
    private var sceneReady = false
    private var runningTask: Task<Void, Never>?
    private var headWorld = SIMD3<Float>(repeating: 0)
    private var headMatrix = matrix_identity_float4x4
    private var fileHandle: FileHandle?
    private var lastWriteTime: TimeInterval = 0
    private var lastSample: [String: Any] = [:]
    private var logHandle: FileHandle?
    private var headMarker: ModelEntity?
    private let speech = AVSpeechSynthesizer()
    private var guidedTask: Task<Void, Never>?
    private var timedRecordingTask: Task<Void, Never>?

    func setupScene() {
        guard !sceneReady else { return }
        sceneReady = true
        root.name = "gesture-lab-hands"
        let markerMesh = MeshResource.generateSphere(radius: 0.025)
        var markerMaterial = SimpleMaterial()
        markerMaterial.color = .init(tint: .yellow)
        let marker = ModelEntity(mesh: markerMesh, materials: [markerMaterial])
        marker.name = "head-marker"
        marker.isEnabled = false
        root.addChild(marker)
        headMarker = marker
        log("scene ready")
    }

    func start() async {
        guard !running else { return }
        log("requesting ARKit authorization (hand tracking + world sensing)")
        status = "requesting hand-tracking authorization..."
        let auth = await session.requestAuthorization(for: [.handTracking, .worldSensing])
        log("authorization hand=\(String(describing: auth[.handTracking])) world=\(String(describing: auth[.worldSensing]))")
        guard auth[.handTracking] == .allowed else {
            log("hand tracking not allowed")
            status = "hand tracking not allowed (\(String(describing: auth[.handTracking])))"
            return
        }
        guard HandTrackingProvider.isSupported else {
            status = "hand tracking unsupported on this device"
            return
        }
        do {
            try await session.run([handTracking, worldTracking])
        } catch {
            log("ARKit session failed: \(error)")
            status = "ARKit session failed: \(error)"
            return
        }
        running = true
        log("ARKit session running")
        status = "tracking hands"
        runningTask = Task { [weak self] in
            guard let self else { return }
            for await update in self.handTracking.anchorUpdates {
                if Task.isCancelled { break }
                self.ingest(update.anchor)
            }
        }
    }

    private func syncHead(timestamp: TimeInterval) {
        guard let device = worldTracking.queryDeviceAnchor(atTimestamp: timestamp),
              device.trackingState == .tracked else {
            headTracked = false
            headMarker?.isEnabled = false
            return
        }
        let transform = device.originFromAnchorTransform
        headWorld = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        headMatrix = transform
        headTracked = true
        headPositionText = String(format: "x=%.3f y=%.3f z=%.3f", headWorld.x, headWorld.y, headWorld.z)
        if let marker = headMarker {
            marker.isEnabled = true
            marker.transform = Transform(matrix: transform)
        }
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        speech.speak(utterance)
    }

    private func log(_ message: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("gesturelab.log")
        if logHandle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            logHandle = try? FileHandle(forWritingTo: url)
        }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        try? logHandle?.write(contentsOf: Data(line.utf8))
    }

    func stop() {
        guidedTask?.cancel()
        guidedTask = nil
        timedRecordingTask?.cancel()
        timedRecordingTask = nil
        guidedActive = false
        runningTask?.cancel()
        runningTask = nil
        stopRecording()
        guard running else { return }
        session.stop()
        running = false
        status = "stopped"
        log("session stopped")
    }

    /// Spoken walkthrough of every action: 2 s to get ready, 5 s recorded per label, 1.5 s rest.
    /// The label names are the dataset keys the analysis/replay scripts look for; keep them in sync.
    func startGuidedCapture() {
        guard running, !recording, !guidedActive else { return }
        let actions = ["MENU_RIGHT_PINCH", "ESCAPE_LEFT_FIST", "WALK_BOTH_FISTS", "JUMP_HEAD",
                       "SNEAK_HEAD", "TELEPORT_LEFT_PINCH", "ATTACK_RIGHT_SWING",
                       "EAT_RIGHT_HAND_HEAD", "BOW_BOTH_FISTS", "PLACE_RIGHT_PINCH",
                       "BREAK_RIGHT_PINCH_HOLD",
                       "INVENTORY_BOTH_FISTS", "HOTBAR_RIGHT_TAP", "CLIMB_ALTERNATE"]
        guidedActive = true
        guidedTask?.cancel()
        guidedTask = Task { [weak self] in
            guard let self else { return }
            for (index, action) in actions.enumerated() {
                if Task.isCancelled { break }
                self.guidedProgress = "\(index + 1)/\(actions.count)"
                self.selectedLabel = action
                self.guidedPrompt = "prepare: \(action)"
                self.speak("Prepare for \(action.replacingOccurrences(of: "_", with: " ")). 2 seconds.")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                self.startRecording(label: action)
                self.guidedPrompt = "recording: \(action)"
                self.speak("Go.")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.stopRecording()
                if Task.isCancelled { break }
                self.guidedPrompt = "rest"
                self.speak("Rest.")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            self.guidedActive = false
            self.guidedPrompt = "guided capture finished"
            self.speak("Guided capture finished.")
        }
    }

    func startTimedRecording(seconds: Int = 30) {
        guard running, !recording else { return }
        guard startRecording() else { return }
        timedRecordingTask?.cancel()
        recordRemaining = seconds
        speak("Recording \(seconds) seconds. Go.")
        timedRecordingTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: seconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                self.recordRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if Task.isCancelled { return }
            self.recordRemaining = 0
            self.stopRecording()
            self.speak("Recording finished. Stop and save is complete.")
        }
    }

    @discardableResult
    func startRecording(label: String? = nil) -> Bool {
        guard running, !recording else { return false }
        if let label { selectedLabel = label }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeLabel = selectedLabel.replacingOccurrences(of: "/", with: "-")
        let url = docs.appendingPathComponent("gesturelab-\(safeLabel)-\(formatter.string(from: Date())).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            status = "could not open recording file"
            return false
        }
        fileHandle = handle
        recordFile = url.lastPathComponent
        recording = true
        status = "recording \(url.lastPathComponent)"
        log("recording started: \(url.lastPathComponent) label=\(selectedLabel)")
        return true
    }

    func stopRecording() {
        timedRecordingTask?.cancel()
        timedRecordingTask = nil
        recordRemaining = 0
        guard recording else { return }
        try? fileHandle?.close()
        fileHandle = nil
        recording = false
        status = "recording saved: \(recordFile)"
        log("recording stopped: \(recordFile) samples=\(sampleCount)")
    }

    /// Appends one JSONL sample: `t` (Unix seconds), `label`, head position + 4x4 world matrix, each
    /// hand's joints as 16-float column-major world matrices, the live features and the lab classifier
    /// output. Throttled to ~20 Hz (one line per 50 ms), which keeps files small while still resolving
    /// taps and swings.
    private func writeSample(left: HandAnchor?, right: HandAnchor?, lf: LabHandFeatures, rf: LabHandFeatures) {
        guard recording, let handle = fileHandle else { return }
        let now = Date().timeIntervalSince1970
        guard now - lastWriteTime > 0.05 else { return }
        lastWriteTime = now
        var sample: [String: Any] = [
            "t": now,
            "label": selectedLabel,
            "headTracked": headTracked,
            "head": headTracked ? [headMatrix.columns.3.x, headMatrix.columns.3.y, headMatrix.columns.3.z] : [0, 0, 0],
            "headMatrix": headTracked ? [headMatrix.columns.0.x, headMatrix.columns.0.y, headMatrix.columns.0.z, headMatrix.columns.0.w,
                                          headMatrix.columns.1.x, headMatrix.columns.1.y, headMatrix.columns.1.z, headMatrix.columns.1.w,
                                          headMatrix.columns.2.x, headMatrix.columns.2.y, headMatrix.columns.2.z, headMatrix.columns.2.w,
                                          headMatrix.columns.3.x, headMatrix.columns.3.y, headMatrix.columns.3.z, headMatrix.columns.3.w] : [],
            "left": handDictionary(left),
            "right": handDictionary(right),
            "leftFeatures": featureDictionary(lf),
            "rightFeatures": featureDictionary(rf)
        ]
        sample["classifier"] = classification
        if let data = try? JSONSerialization.data(withJSONObject: sample),
           let line = String(data: data, encoding: .utf8) {
            try? handle.write(contentsOf: Data((line + "\n").utf8))
            sampleCount += 1
        }
    }

    private func handDictionary(_ anchor: HandAnchor?) -> [String: Any] {
        guard let anchor, anchor.isTracked, let skeleton = anchor.handSkeleton else { return ["tracked": false] }
        var joints: [[String: Any]] = []
        for joint in skeleton.allJoints {
            let m = simd_mul(anchor.originFromAnchorTransform, joint.anchorFromJointTransform)
            joints.append([
                "name": String(describing: joint.name),
                "tracked": joint.isTracked,
                "m": [m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
                      m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
                      m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
                      m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w]
            ])
        }
        return ["tracked": true, "chirality": anchor.chirality == .left ? "left" : "right", "joints": joints]
    }

    private func featureDictionary(_ f: LabHandFeatures) -> [String: Any] {
        ["tracked": f.tracked, "pinch": f.pinch, "fistRatio": f.fistRatio,
         "isPinch": f.isPinch, "isFist": f.isFist, "speed": f.speed, "verticalSpeed": f.verticalSpeed]
    }

    /// Called for every hand-anchor update (each hand updates independently): refreshes the head pose,
    /// moves the joint/bone debug visuals (entities are created once and reused), runs the classifier on
    /// the latest snapshot of both hands, and records a sample when recording.
    private func ingest(_ anchor: HandAnchor) {
        // queryDeviceAnchor expects the system uptime clock (the same clock ARKit timestamps use).
        syncHead(timestamp: ProcessInfo.processInfo.systemUptime)
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else { return }
        let handKey = anchor.chirality == .left ? "L" : "R"
        let color: UIColor = anchor.chirality == .left ? .cyan : .orange
        for joint in skeleton.allJoints {
            let key = "\(handKey)-\(String(describing: joint.name))"
            let matrix = simd_mul(anchor.originFromAnchorTransform, joint.anchorFromJointTransform)
            let entity: ModelEntity
            if let existing = jointEntities[key] {
                entity = existing
            } else {
                let mesh = MeshResource.generateSphere(radius: 0.008)
                var material = SimpleMaterial()
                material.color = .init(tint: color)
                entity = ModelEntity(mesh: mesh, materials: [material])
                entity.name = key
                root.addChild(entity)
                jointEntities[key] = entity
            }
            entity.transform = Transform(matrix: matrix)
            if let parent = joint.parentJoint {
                let parentMatrix = simd_mul(anchor.originFromAnchorTransform,
                                            parent.anchorFromJointTransform)
                let p0 = SIMD3<Float>(parentMatrix.columns.3.x, parentMatrix.columns.3.y, parentMatrix.columns.3.z)
                let p1 = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
                let delta = p1 - p0
                let length = simd_length(delta)
                if length > 0.0005 {
                    let boneKey = "\(handKey)-\(String(describing: joint.name))-bone"
                    let bone: ModelEntity
                    if let existing = boneEntities[boneKey] {
                        bone = existing
                    } else {
                        let mesh = MeshResource.generateCylinder(height: 1.0, radius: 0.0025)
                        var material = SimpleMaterial()
                        material.color = .init(tint: color)
                        bone = ModelEntity(mesh: mesh, materials: [material])
                        bone.name = boneKey
                        root.addChild(bone)
                        boneEntities[boneKey] = bone
                    }
                    // Unit cylinder along +Y, rotated onto the parent→joint segment and scaled to its length.
                    let rotation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: delta / length)
                    bone.transform = Transform(scale: SIMD3<Float>(1, length, 1),
                                               rotation: rotation,
                                               translation: (p0 + p1) * 0.5)
                }
            }
        }
        let newJointCount = jointEntities.count
        if visibleJointCount == 0 && newJointCount > 0 { log("first hand joints received; total=\(newJointCount)") }
        visibleJointCount = newJointCount
        let now = ProcessInfo.processInfo.systemUptime
        let (leftAnchor, rightAnchor) = latestHands()
        let (lf, rf, output) = classifier.update(left: leftAnchor, right: rightAnchor,
                                                 head: headTracked ? headWorld : nil, time: now)
        classification = output.label + (output.detail.isEmpty ? "" : " [\(output.detail)]")
        leftFeatures = String(format: "pinch=%.3f fist=%.2f", lf.pinch, lf.fistRatio)
        rightFeatures = String(format: "pinch=%.3f fist=%.2f", rf.pinch, rf.fistRatio)
        if recording {
            // Write on either hand's update: left-hand-only actions previously starved the recorder
            // because only right-hand anchor updates produced samples.
            writeSample(left: leftAnchor, right: rightAnchor, lf: lf, rf: rf)
        }
    }

    private func latestHands() -> (HandAnchor?, HandAnchor?) {
        // HandTrackingProvider keeps latest anchors; use its published snapshot when available.
        let anchors = handTracking.latestAnchors
        return (anchors.leftHand, anchors.rightHand)
    }
}
