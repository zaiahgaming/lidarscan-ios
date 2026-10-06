import SwiftUI
import ARKit
import SceneKit

public struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var captureManager: ARCaptureManager

    public init(captureManager: ARCaptureManager) {
        self.captureManager = captureManager
    }

    public func makeUIView(context: Context) -> ARSCNView {
        let scnView = ARSCNView(frame: .zero)
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = true
        scnView.showsStatistics = false

        captureManager.attach(sceneView: scnView)
        return scnView
    }

    public func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
