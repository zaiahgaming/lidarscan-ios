import SwiftUI

public struct ScannerView: View {
    @ObservedObject var captureManager: ARCaptureManager
    @State private var showingLibrary = false
    @State private var showingProcessing = false
    @State private var forceScannerBypass = false

    public init(captureManager: ARCaptureManager) {
        self.captureManager = captureManager
    }

    public var body: some View {
        ZStack {
            if !DeviceUtils.supportsLiDAR && !DeviceUtils.isSimulator && !forceScannerBypass {
                NoLidarWarningView(
                    onOpenLibrary: { showingLibrary = true },
                    onContinueAnyway: { forceScannerBypass = true }
                )
            } else {
                ARViewContainer(captureManager: captureManager)
                    .ignoresSafeArea()

                ScannerOverlayView(
                    captureManager: captureManager,
                    onOpenLibrary: { showingLibrary = true },
                    onFinishCapture: {
                        captureManager.finishCapture { _ in
                            showingProcessing = true
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingLibrary) {
            LibraryView()
        }
        .fullScreenCover(isPresented: $showingProcessing) {
            if let saved = captureManager.lastCompletedCapture {
                ProcessingView(capture: saved, onDismiss: {
                    showingProcessing = false
                    captureManager.lastCompletedCapture = nil
                    captureManager.restartSession()
                })
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text(captureManager.processingStage.isEmpty ? "Processing..." : captureManager.processingStage)
                            .font(.headline)
                            .foregroundColor(.white)
                        ProgressView(value: Double(captureManager.processingProgress))
                            .accentColor(.blue)
                            .padding(.horizontal, 48)
                    }
                }
            }
        }
    }
}
