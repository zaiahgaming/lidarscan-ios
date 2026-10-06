import Foundation
import ARKit
import SceneKit
import Combine
import AVFoundation

public final class ARCaptureManager: NSObject, ObservableObject, ARSessionDelegate, ARSCNViewDelegate {
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

    @Published public var isProcessing = false
    @Published public var processingStage = ""
    @Published public var processingProgress: Float = 0.0
    @Published public var lastCompletedCapture: SavedCapture?
    @Published public var currentCaptureName = ""

    public var sceneView: ARSCNView?
    private var timer: Timer?

    public let pointCloudManager = PointCloudManager()
    public let meshReconstructor = MeshReconstructor()
    public let keyframeManager = KeyframeManager()

    private var currentSessionFolder: URL?

    public override init() {
        super.init()
    }

    public func attach(sceneView: ARSCNView) {
        self.sceneView = sceneView
        sceneView.delegate = self
        sceneView.session.delegate = self
        restartSession()
    }

    public func restartSession() {
        guard let sceneView = sceneView else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            DispatchQueue.main.async {
                self.trackingStateText = "AR Not Supported"
            }
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.runARSession(on: sceneView)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self, let sceneView = self.sceneView else { return }
                    if granted {
                        self.runARSession(on: sceneView)
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
            self.runARSession(on: sceneView)
        }
    }

    private func runARSession(on sceneView: ARSCNView) {
        let configuration = ARWorldTrackingConfiguration()

        if DeviceUtils.supportsLiDAR {
            if mode == .lidarMesh {
                if DeviceUtils.supportsClassification {
                    configuration.sceneReconstruction = .meshWithClassification
                } else {
                    configuration.sceneReconstruction = .mesh
                }
            } else {
                configuration.sceneReconstruction = []
            }

            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            }
        }

        configuration.environmentTexturing = .automatic
        configuration.worldAlignment = .gravity

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func startCapture() {
        guard !isRecording else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let name = "Scan_\(timestamp)"
        self.currentCaptureName = name

        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let capturesDir = docDir.appendingPathComponent("Captures")
        let sessionFolder = capturesDir.appendingPathComponent(name)

        do {
            try FileManager.default.createDirectory(at: sessionFolder.appendingPathComponent("images"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sessionFolder.appendingPathComponent("depth"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sessionFolder.appendingPathComponent("confidence"), withIntermediateDirectories: true)
        } catch {
            print("Failed to create session directory: \(error)")
            return
        }

        self.currentSessionFolder = sessionFolder
        pointCloudManager.reset()
        meshReconstructor.reset()
        keyframeManager.reset()

        elapsedTime = 0
        keyframeCount = 0
        pointCount = 0
        isRecording = true
        isPaused = false
        coverageHint = "Scanning • Move smoothly around subject"

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording, !self.isPaused else { return }
            DispatchQueue.main.async {
                self.elapsedTime += 1
                self.pointCount = self.pointCloudManager.pointCount
            }
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
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.processingStage = "Error: \(error.localizedDescription)"
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
        }
        currentSessionFolder = nil
    }

    // MARK: - ARSessionDelegate

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update tracking status
        switch frame.camera.trackingState {
        case .normal:
            if !trackingIsNormal {
                trackingIsNormal = true
                trackingStateText = "Tracking Normal"
            }
        case .limited(let reason):
            trackingIsNormal = false
            switch reason {
            case .excessiveMotion:
                trackingStateText = "Limited: Excessive Motion"
                if isRecording && !isPaused { coverageHint = "Slow down movement" }
            case .insufficientFeatures:
                trackingStateText = "Limited: Low Features"
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

    // MARK: - ARSCNViewDelegate

    public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        meshReconstructor.update(anchor: meshAnchor)

        if mode == .lidarMesh {
            let overlayNode = buildMeshNode(for: meshAnchor)
            overlayNode.name = "meshOverlay"
            node.addChildNode(overlayNode)
        }
    }

    public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        meshReconstructor.update(anchor: meshAnchor)

        if mode == .lidarMesh {
            node.childNode(withName: "meshOverlay", recursively: false)?.removeFromParentNode()
            let overlayNode = buildMeshNode(for: meshAnchor)
            overlayNode.name = "meshOverlay"
            node.addChildNode(overlayNode)
        }
    }

    public func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        meshReconstructor.remove(anchor: meshAnchor)
    }

    private func buildMeshNode(for meshAnchor: ARMeshAnchor) -> SCNNode {
        let geom = meshAnchor.geometry
        let vSource = geom.vertices
        let fElement = geom.faces

        let scnVertices = (0..<vSource.count).map { i -> SCNVector3 in
            let ptr = vSource.buffer.contents().advanced(by: i * vSource.stride).assumingMemoryBound(to: Float.self)
            return SCNVector3(ptr[0], ptr[1], ptr[2])
        }
        let vertexSource = SCNGeometrySource(vertices: scnVertices)

        var indices: [Int32] = []
        let fBuf = fElement.buffer.contents()
        let bytesPerIndex = fElement.bytesPerIndex

        for i in 0..<fElement.count {
            for j in 0..<3 {
                if bytesPerIndex == 4 {
                    let idx = fBuf.advanced(by: (i * 3 + j) * 4).assumingMemoryBound(to: UInt32.self).pointee
                    indices.append(Int32(idx))
                } else {
                    let idx = fBuf.advanced(by: (i * 3 + j) * 2).assumingMemoryBound(to: UInt16.self).pointee
                    indices.append(Int32(idx))
                }
            }
        }

        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])

        let material = SCNMaterial()
        material.fillMode = .lines // Wireframe mesh overlay
        material.diffuse.contents = UIColor.systemCyan.withAlphaComponent(0.6)
        material.isDoubleSided = true
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }
}
