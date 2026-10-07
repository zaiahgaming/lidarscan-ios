import SwiftUI

/// Full 3D inspection of a saved capture. Uses a real navigation toolbar
/// instead of a hand-drawn bar so titles, actions, and safe areas all behave
/// exactly like the rest of the system.
public struct CaptureDetailView: View {
    public let capture: SavedCapture
    @Environment(\.dismiss) private var dismiss

    @State private var preferPointCloud = false
    @State private var showWireframe = false
    @State private var showingStudioUpload = false
    @State private var showingShareSheet = false

    public init(capture: SavedCapture) {
        self.capture = capture
    }

    public var body: some View {
        NavigationStack {
            SceneKitModelView(
                captureFolder: capture.folderURL,
                showWireframe: showWireframe,
                preferPointCloud: preferPointCloud
            )
            .ignoresSafeArea()
            .overlay(alignment: .bottomTrailing) {
                viewerControls
                    .padding(16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if verticalSizeClass != .compact {
                    infoFooter
                }
            }
            .navigationTitle(capture.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingStudioUpload = true
                    } label: {
                        Label("Send to PC", systemImage: "desktopcomputer")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingStudioUpload) {
            StudioUploadSheet(capture: capture)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let zip = capture.zipURL {
                ShareSheet(activityItems: [zip])
            }
        }
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var viewerControls: some View {
        VStack(spacing: 12) {
            GlassIconButton(
                systemImage: preferPointCloud ? "circle.grid.cross.fill" : "cube.fill",
                diameter: 44
            ) {
                preferPointCloud.toggle()
            }
            .accessibilityLabel(Text(preferPointCloud ? "Show mesh" : "Show point cloud"))

            GlassIconButton(
                systemImage: showWireframe ? "square.dashed" : "square",
                diameter: 44
            ) {
                showWireframe.toggle()
            }
            .accessibilityLabel(Text(showWireframe ? "Hide wireframe" : "Show wireframe"))
        }
    }

    private var infoFooter: some View {
        HStack(spacing: 18) {
            footerStat(title: "Captured", value: capture.formattedDate)

            Divider().frame(height: 26).opacity(0.4)

            footerStat(title: "Points", value: "\(capture.pointCount)", tint: .green)

            Divider().frame(height: 26).opacity(0.4)

            footerStat(
                title: "Mesh",
                value: capture.hasMesh ? "OBJ · PLY · USDZ · GLB" : "None",
                tint: capture.hasMesh ? .cyan : nil
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .adaptiveGlassCard(cornerRadius: 0)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func footerStat(title: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(tint ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
