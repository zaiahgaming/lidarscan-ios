import SwiftUI

/// Success screen shown immediately after a scan finishes saving.
public struct ProcessingView: View {
    public let capture: SavedCapture
    public let onDismiss: () -> Void

    @State private var showing3DViewer = false
    @State private var showingStudioUpload = false
    @State private var showingShareSheet = false

    public init(capture: SavedCapture, onDismiss: @escaping () -> Void) {
        self.capture = capture
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.green.opacity(0.16))
                    .frame(width: 92, height: 92)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.green)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Scan Saved")
                    .font(.title2.bold())
                Text(capture.name)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 24)
            }

            statGrid
                .padding(.horizontal, 24)

            Spacer()

            actionButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showing3DViewer) {
            CaptureDetailView(capture: capture)
        }
        .sheet(isPresented: $showingStudioUpload) {
            StudioUploadSheet(capture: capture)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let zip = capture.zipURL {
                ShareSheet(activityItems: [zip])
            }
        }
    }

    private var statGrid: some View {
        HStack(spacing: 12) {
            StatCard(title: "Frames", value: "\(capture.frameCount)", icon: "camera.fill", tint: .cyan)
            StatCard(title: "Points", value: formatNumber(capture.pointCount), icon: "circle.grid.cross.fill", tint: .green)
            StatCard(title: "Size", value: capture.formattedSize, icon: "doc.zipper", tint: .blue)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showing3DViewer = true
            } label: {
                Label("Interactive 3D Viewer", systemImage: "cube.transparent.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showingStudioUpload = true
            } label: {
                Label("Send to PC Studio", systemImage: "desktopcomputer")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 12) {
                Button {
                    showingShareSheet = true
                } label: {
                    Label("Share Zip", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button(action: onDismiss) {
                    Text("New Scan")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000.0)
        } else if num >= 1_000 {
            return String(format: "%.1fk", Double(num) / 1_000.0)
        } else {
            return "\(num)"
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
            Text(value)
                .font(.body.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
