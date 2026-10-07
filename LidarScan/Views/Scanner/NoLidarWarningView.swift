import SwiftUI

/// Shown when the device has no LiDAR hardware.
/// Uses the system empty-state component for a native look.
public struct NoLidarWarningView: View {
    public let onOpenLibrary: () -> Void
    public let onContinueAnyway: () -> Void

    public init(onOpenLibrary: @escaping () -> Void, onContinueAnyway: @escaping () -> Void) {
        self.onOpenLibrary = onOpenLibrary
        self.onContinueAnyway = onContinueAnyway
    }

    public var body: some View {
        VStack(spacing: 28) {
            ContentUnavailableView {
                Label("LiDAR Scanner Required", systemImage: "sensor.tag.radiowaves.forward")
            } description: {
                Text("Full scene mesh reconstruction and LiDAR depth need an iPhone Pro (12 Pro or later) or an iPad Pro with LiDAR.")
            }

            VStack(spacing: 12) {
                Button {
                    onOpenLibrary()
                } label: {
                    Label("Open Scans Library", systemImage: "folder.fill")
                        .font(.headline)
                        .frame(maxWidth: 320, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onContinueAnyway) {
                    Text("Continue Anyway (Viewer / Debug)")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .preferredColorScheme(.dark)
    }
}
