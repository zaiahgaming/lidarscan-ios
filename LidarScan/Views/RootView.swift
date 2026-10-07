import SwiftUI

public struct RootView: View {
    @StateObject private var captureManager = ARCaptureManager()

    public init() {}

    public var body: some View {
        ScannerView(captureManager: captureManager)
            .preferredColorScheme(.dark)
            .tint(.cyan)
    }
}
