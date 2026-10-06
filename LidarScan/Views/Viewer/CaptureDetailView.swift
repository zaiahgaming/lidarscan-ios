import SwiftUI

public struct CaptureDetailView: View {
    public let capture: SavedCapture
    @Environment(\.presentationMode) var presentationMode

    @State private var preferPointCloud = false
    @State private var showWireframe = false
    @State private var showingStudioUpload = false
    @State private var showingShareSheet = false

    public init(capture: SavedCapture) {
        self.capture = capture
    }

    public var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(capture.name)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("\(capture.frameCount) frames • \(capture.formattedSize)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.leading, 6)

                    Spacer()

                    Button(action: { showingStudioUpload = true }) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }

                    Button(action: { showingShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

                // 3D Scene View
                ZStack(alignment: .bottomTrailing) {
                    SceneKitModelView(
                        captureFolder: capture.folderURL,
                        showWireframe: showWireframe,
                        preferPointCloud: preferPointCloud
                    )
                    .ignoresSafeArea()

                    // Floating 3D Controls
                    VStack(spacing: 10) {
                        Button(action: { preferPointCloud.toggle() }) {
                            Image(systemName: preferPointCloud ? "circle.grid.cross.fill" : "cube.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Circle())
                        }

                        Button(action: { showWireframe.toggle() }) {
                            Image(systemName: showWireframe ? "square.dashed" : "square")
                                .font(.system(size: 16))
                                .foregroundColor(showWireframe ? .cyan : .white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Circle())
                        }
                    }
                    .padding(16)
                }

                // Info Footer
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Captured")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        Text(capture.formattedDate)
                            .font(.caption)
                            .foregroundColor(.white)
                    }

                    Divider().frame(height: 24).background(Color.gray.opacity(0.3))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Points")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        Text("\(capture.pointCount)")
                            .font(.caption.monospaced())
                            .foregroundColor(.green)
                    }

                    Divider().frame(height: 24).background(Color.gray.opacity(0.3))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mesh")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        Text(capture.hasMesh ? "OBJ/PLY/USDZ/GLB" : "None")
                            .font(.caption)
                            .foregroundColor(capture.hasMesh ? .cyan : .gray)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.6))
            }
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
}
