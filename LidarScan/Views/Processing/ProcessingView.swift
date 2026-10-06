import SwiftUI

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
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Success Badge
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 88, height: 88)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.green)
                }

                VStack(spacing: 8) {
                    Text("Capture Processed!")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text(capture.name)
                        .font(.headline)
                        .foregroundColor(.gray)
                }

                // Stats Grid
                HStack(spacing: 16) {
                    StatCard(title: "FRAMES", value: "\(capture.frameCount)", icon: "camera.fill", color: .cyan)
                    StatCard(title: "POINTS", value: formatNumber(capture.pointCount), icon: "circle.grid.cross.fill", color: .green)
                    StatCard(title: "SIZE", value: capture.formattedSize, icon: "doc.zipper", color: .blue)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: { showing3DViewer = true }) {
                        HStack {
                            Image(systemName: "cube.transparent.fill")
                            Text("Interactive 3D Viewer")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.blue)
                        .cornerRadius(14)
                    }

                    Button(action: { showingStudioUpload = true }) {
                        HStack {
                            Image(systemName: "desktopcomputer")
                            Text("Send to PC Studio")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(14)
                    }

                    HStack(spacing: 12) {
                        Button(action: { showingShareSheet = true }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Zip")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                        }

                        Button(action: onDismiss) {
                            Text("New Scan")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
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
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
}
