import SwiftUI
import RealityKit
import ARKit

public struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var captureManager: ARCaptureManager

    public init(captureManager: ARCaptureManager) {
        self.captureManager = captureManager
    }

    public func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        captureManager.attach(arView: arView)
        return arView
    }

    public func updateUIView(_ uiView: ARView, context: Context) {}
}
