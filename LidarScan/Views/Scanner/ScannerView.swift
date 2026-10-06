import SwiftUI

public struct ScannerView: View {
    @ObservedObject var captureManager: ARCaptureManager
    @State private var showingLibrary = false
    @State private var showingProcessing = false
    @State private var showingSaveError = false
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
                        showingProcessing = true
                        captureManager.finishCapture { saved in
                            if saved == nil {
                                showingProcessing = false
                                showingSaveError = true
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingLibrary) {
            LibraryView()
        }
        .alert(
            captureManager.sessionErrorMessage == nil ? "Could Not Save Scan" : "AR Session Error",
            isPresented: Binding(
                get: { captureManager.sessionErrorMessage != nil || showingSaveError },
                set: { isPresented in
                    if !isPresented {
                        captureManager.sessionErrorMessage = nil
                        showingSaveError = false
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(captureManager.sessionErrorMessage ?? captureManager.captureErrorMessage ?? "The scan could not be saved. Please try a shorter scan and check that your device has free storage.")
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
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                        VStack(spacing: 8) {
                            ProgressView(value: Double(captureManager.processingProgress))
                                .progressViewStyle(.linear)
                                .tint(.cyan)
                            Text("\(Int(captureManager.processingProgress * 100))% complete • \(captureManager.keyframeCount) frames")
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(.white.opacity(0.75))
                        }
                        .padding(.horizontal, 36)
                    }
                }
            }
        }
    }
}
