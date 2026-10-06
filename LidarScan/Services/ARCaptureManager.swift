import Foundation
import ARKit
import RealityKit
import Combine
import AVFoundation

public final class ARCaptureManager: NSObject, ObservableObject, ARSessionDelegate {
    @Published public var mode: CaptureMode = .lidarMesh {
        didSet {
            if oldValue != mode {
                restartSession()
            }
        }
    }

    @Published public var isRecording = false
    @Published public var isPaused = false
    @Published public var trackingStateText = "Initializing..."
    @Published public var trackingIsNormal = false
    @Published public var coverageHint = "Ready to scan"
    @Published public var elapsedTime: TimeInterval = 0
    @Published public var keyframeCount = 0
    @Published public var pointCount = 0
    @Published public var recentKeyframeFlashed = false
    @Published public var sessionErrorMessage: String?

    @Published public var isProcessing = false
    @Published public var processingStage = ""
    @Published public var processingProgress: Float = 0.0
    @Published public var lastCompletedCapture: SavedCapture?
    @Published public var currentCaptureName = ""

    public var arView: ARView?
    private var timer: Timer?

    public let pointCloudManager = PointCloudManager()
    public let meshReconstructor = MeshReconstructor()
    public let keyframeManager = KeyframeManager()

    private var currentSessionFolder: URL?

    public override init() {
        super.init()
    }

    public func attach(arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        // Enable official RealityKit GPU-accelerated mesh visualization
        arView.debugOptions.insert(.showSceneUnderstanding)
        restartSession()
    }

    public func restartSession() {
        guard let arView = arView else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            DispatchQueue.main.async {
                self.trackingStateText = "AR Not Supported"
            }
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.runARSession(on: arView)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self, let arView = self.arView else { return }
                    if granted {
                        self.runARSession(on: arView)
                    } else {
                        self.trackingStateText = "Camera Access Denied"
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.trackingStateText = "Camera Access Denied"
            }
        @unknown default:
            self.runARSession(on: arView)
        }
    }

    private func runARSession(on arView: ARView) {
        let configuration = ARWorldTrackingConfiguration()

        // Check the individual ARKit capabilities before enabling optional LiDAR features.
        if mode == .lidarMesh && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            if DeviceUtils.supportsClassification {
                configuration.sceneReconstruction = .meshWithClassification
            } else {
                configuration.sceneReconstruction = .mesh
            }
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            configuration.sceneReconstruction = []
            arView.debugOptions.remove(.showSceneUnderstanding)
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }

        configuration.environmentTexturing = .automatic
        configuration.worldAlignment = .gravity
        sessionErrorMessage = nil
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func startCapture() {
        guard !isRecording else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            trackingStateText = "Camera Access Required"
            return
        }
        guard ARWorldTrackingConfiguration.isSupported else {
            trackingStateText = "AR Not Supported"
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        currentCaptureName = "Scan_\(timestamp)"

        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionFolder = docDir.appendingPathComponent("Captures", isDirectory: true)
            .appendingPathComponent(currentCaptureName, isDirectory: true)

        do {
            let fm = FileManager.default
            try fm.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
            try fm.createDirectory(at: sessionFolder.appendingPathComponent("images"), withIntermediateDirectories: true)
            try fm.createDirectory(at: sessionFolder.appendingPathComponent("depth"), withIntermediateDirectories: true)
            try fm.createDirectory(at: sessionFolder.appendingPathComponent("confidence"), withIntermediateDirectories: true)
            try fm.createDirectory(at: sessionFolder.appendingPathComponent("mesh"), withIntermediateDirectories: true)
            currentSessionFolder = sessionFolder
        } catch {
            print("Failed to create session folder: \(error)")
            return
        }

        keyframeManager.reset()
        pointCloudManager.reset()
        meshReconstructor.reset()

        elapsedTime = 0
        keyframeCount = 0
        pointCount = 0
        isRecording = true
        isPaused = false
        coverageHint = "Move device slowly around the object"

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording, !self.isPaused else { return }
            DispatchQueue.main.async {
                self.elapsedTime += 1
                self.pointCount = self.pointCloudManager.pointCount
            }
        }
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.isPaused = false
            self.timer?.invalidate()
            self.timer = nil
            self.trackingIsNormal = false
            self.trackingStateText = "AR Session Error"
            self.sessionErrorMessage = error.localizedDescription
        }
    }

    public func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.trackingIsNormal = false
            self.trackingStateText = "AR Session Interrupted"
        }
    }

    public func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.restartSession()
        }
    }

    public func togglePause() {
        isPaused.toggle()
        if isPaused {
            coverageHint = "Paused"
        } else {
            coverageHint = "Scanning • Continue moving"
        }
    }

    public func finishCapture(completion: @escaping (SavedCapture?) -> Void) {
        guard isRecording, let folder = currentSessionFolder else {
            completion(nil)
            return
        }

        isRecording = false
        isPaused = false
        timer?.invalidate()
        timer = nil

        isProcessing = true
        processingStage = "Preparing capture data..."
        processingProgress = 0.05

        let captureName = currentCaptureName
        let currentMode = mode
        let keyframes = keyframeManager.recordedKeyframes

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let saved = try ExportManager.shared.finalizeCapture(
                    captureName: captureName,
                    captureFolder: folder,
                    mode: currentMode,
                    keyframes: keyframes,
                    pointCloudManager: self.pointCloudManager,
                    meshReconstructor: self.meshReconstructor
                ) { progress in
                    DispatchQueue.main.async {
                        self.processingStage = progress.stage
                        self.processingProgress = progress.progress
                    }
                }

                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastCompletedCapture = saved
                    completion(saved)
                }
            } catch {
                print("Failed to finalize capture: \(error)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(nil)
                }
            }
        }
    }

    public func cancelCapture() {
        isRecording = false
        isPaused = false
        timer?.invalidate()
        timer = nil

        if let folder = currentSessionFolder {
            try? FileManager.default.removeItem(at: folder)
            currentSessionFolder = nil
        }

        keyframeManager.reset()
        pointCloudManager.reset()
        meshReconstructor.reset()

        elapsedTime = 0
        keyframeCount = 0
        pointCount = 0
        coverageHint = "Capture cancelled"
    }

    // MARK: - ARSessionDelegate

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update tracking state
        switch frame.camera.trackingState {
        case .normal:
            trackingIsNormal = true
            trackingStateText = "Tracking Normal"
            if !isRecording {
                coverageHint = "Aim camera and tap Record"
            }
        case .limited(let reason):
            trackingIsNormal = false
            switch reason {
            case .excessiveMotion:
                trackingStateText = "Limited: Too Fast"
                if isRecording && !isPaused { coverageHint = "Slow down movement" }
            case .insufficientFeatures:
                trackingStateText = "Limited: Low Detail"
                if isRecording && !isPaused { coverageHint = "Aim at textured surfaces" }
            case .initializing:
                trackingStateText = "Limited: Initializing..."
            case .relocalizing:
                trackingStateText = "Limited: Relocalizing..."
            @unknown default:
                trackingStateText = "Limited Tracking"
            }
        case .notAvailable:
            trackingIsNormal = false
            trackingStateText = "Tracking Not Available"
        }

        // Auto keyframe collection during active recording
        guard isRecording, !isPaused, let folder = currentSessionFolder else { return }

        let evaluation = keyframeManager.evaluateFrame(frame)
        switch evaluation {
        case .accept:
            keyframeManager.recordKeyframe(
                from: frame,
                baseFolder: folder,
                pointCloudManager: pointCloudManager
            ) { [weak self] record in
                guard let self = self, record != nil else { return }
                DispatchQueue.main.async {
                    self.keyframeCount = self.keyframeManager.keyframeCount
                    self.pointCount = self.pointCloudManager.pointCount
                    self.triggerKeyframeFlash()
                    self.coverageHint = "Keyframe \(self.keyframeCount) captured"
                }
            }
        case .skipBlurryOrFast(let hint):
            DispatchQueue.main.async {
                self.coverageHint = hint
            }
        case .skipTooClose, .skipBadTracking:
            break
        }
    }

    private func triggerKeyframeFlash() {
        recentKeyframeFlashed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.recentKeyframeFlashed = false
        }
    }

    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshReconstructor.update(anchor: meshAnchor)
            }
        }
    }

    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshReconstructor.update(anchor: meshAnchor)
            }
        }
    }

    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshReconstructor.remove(anchor: meshAnchor)
            }
        }
    }
}
