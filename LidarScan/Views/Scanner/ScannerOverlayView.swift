import SwiftUI

public struct ScannerOverlayView: View {
    @ObservedObject var captureManager: ARCaptureManager
    public let onOpenLibrary: () -> Void
    public let onFinishCapture: () -> Void

    public init(
        captureManager: ARCaptureManager,
        onOpenLibrary: @escaping () -> Void,
        onFinishCapture: @escaping () -> Void
    ) {
        self.captureManager = captureManager
        self.onOpenLibrary = onOpenLibrary
        self.onFinishCapture = onFinishCapture
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func formatPoints(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    public var body: some View {
        ZStack {
            // Flash feedback when a keyframe is snapped
            if captureManager.recentKeyframeFlashed {
                Color.white.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                // Top Bar
                HStack(alignment: .center, spacing: 12) {
                    // Mode Picker
                    if !captureManager.isRecording {
                        Picker("Mode", selection: $captureManager.mode) {
                            ForEach(CaptureMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(maxWidth: 240)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: captureManager.mode.iconName)
                                .font(.system(size: 13, weight: .bold))
                            Text(captureManager.mode.title)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                    }

                    Spacer()

                    // Tracking state pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(captureManager.trackingIsNormal ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(captureManager.trackingStateText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)

                    // Library Button
                    if !captureManager.isRecording {
                        Button(action: onOpenLibrary) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()

                // Center Coverage Hint Banner
                if captureManager.isRecording {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 12))
                        Text(captureManager.coverageHint)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(captureManager.coverageHint.contains("slower") ? .yellow : .white)
                    .cornerRadius(14)
                    .padding(.bottom, 24)
                }

                // Bottom HUD and Controls
                VStack(spacing: 16) {
                    // Stats HUD
                    if captureManager.isRecording {
                        HStack(spacing: 24) {
                            VStack(spacing: 2) {
                                Text("TIME")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.gray)
                                Text(formatTime(captureManager.elapsedTime))
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                            }

                            Divider().frame(height: 24).background(Color.gray.opacity(0.4))

                            VStack(spacing: 2) {
                                Text("KEYFRAMES")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.gray)
                                Text("\(captureManager.keyframeCount)")
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.cyan)
                            }

                            Divider().frame(height: 24).background(Color.gray.opacity(0.4))

                            VStack(spacing: 2) {
                                Text("POINTS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.gray)
                                Text(formatPoints(captureManager.pointCount))
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                    }

                    // Recording Buttons
                    HStack(spacing: 40) {
                        if captureManager.isRecording {
                            // Pause / Resume Button
                            Button(action: { captureManager.togglePause() }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 52, height: 52)
                                    Image(systemName: captureManager.isPaused ? "play.fill" : "pause.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }

                            // Finish Button (Checkmark)
                            Button(action: onFinishCapture) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 72, height: 72)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }

                            // Cancel Button
                            Button(action: { captureManager.cancelCapture() }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 52, height: 52)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.red)
                                }
                            }
                        } else {
                            // Start Recording Button
                            Button(action: { captureManager.startCapture() }) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 76, height: 76)
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 62, height: 62)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
}
