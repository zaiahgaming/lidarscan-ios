import SwiftUI

/// Controls that float above the live AR camera feed.
///
/// Layout follows Apple's camera-UI guidance: a small top bar for mode and
/// status, one hint line centered above the controls, and a single bottom
/// cluster holding the stats readout and shutter controls. Everything scales
/// with Dynamic Type and adapts to compact (landscape) height.
public struct ScannerOverlayView: View {
    @ObservedObject var captureManager: ARCaptureManager
    public let onOpenLibrary: () -> Void
    public let onFinishCapture: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var secondaryControl: CGFloat = 52

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
            keyframeFlash
            VStack(spacing: 0) {
                topBar
                Spacer()
                if captureManager.isRecording && verticalSizeClass != .compact {
                    hintBanner
                }
                bottomCluster
            }
        }
        .animation(.easeOut(duration: 0.2), value: captureManager.recentKeyframeFlashed)
    }

    // MARK: - Flash feedback

    @ViewBuilder
    private var keyframeFlash: some View {
        if captureManager.recentKeyframeFlashed {
            Color.white.opacity(0.22)
                .ignoresSafeArea()
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if captureManager.isRecording {
                modeBadge
            } else {
                Picker("Mode", selection: $captureManager.mode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trackingPill

            if !captureManager.isRecording {
                GlassIconButton(systemImage: "folder.fill", diameter: 40, action: onOpenLibrary)
                    .accessibilityLabel(Text("Open scans library"))
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var modeBadge: some View {
        Label(captureManager.mode.title, systemImage: captureManager.mode.iconName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .adaptiveGlass(in: Capsule())
    }

    private var trackingPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(captureManager.trackingIsNormal ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(captureManager.trackingStateText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .adaptiveGlass(in: Capsule())
    }

    // MARK: - Hint banner

    private var hintBanner: some View {
        Label {
            Text(captureManager.coverageHint)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
        } icon: {
            Image(systemName: "hand.tap.fill")
                .font(.footnote)
        }
        .foregroundStyle(captureManager.coverageHint.contains("slower") ? Color.yellow : Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .adaptiveGlass(in: Capsule())
        .padding(.bottom, 24)
    }

    // MARK: - Bottom cluster

    private var bottomCluster: some View {
        VStack(spacing: 14) {
            if captureManager.isRecording {
                statsHUD
            }
            controls
        }
        .padding(.bottom, 16)
    }

    /// At accessibility text sizes the three readouts no longer fit on one
    /// line, so `ViewThatFits` moves them into a vertical stack instead of
    /// truncating or overflowing.
    @ViewBuilder
    private var statsHUD: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                statReadouts
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .adaptiveGlassCard(cornerRadius: 18)

            VStack(spacing: 8) {
                statReadouts
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .adaptiveGlassCard(cornerRadius: 18)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var statReadouts: some View {
        StatChip(title: "Time", value: formatTime(captureManager.elapsedTime))
        divider
        StatChip(title: "Keyframes", value: "\(captureManager.keyframeCount)", tint: .cyan)
        divider
        StatChip(title: "Points", value: formatPoints(captureManager.pointCount), tint: .green)
    }

    private var divider: some View {
        Divider()
            .frame(height: 26)
            .opacity(0.4)
    }

    private var controls: some View {
        HStack(spacing: 36) {
            if captureManager.isRecording {
                GlassIconButton(
                    systemImage: captureManager.isPaused ? "play.fill" : "pause.fill",
                    diameter: secondaryControl
                ) {
                    captureManager.togglePause()
                }
                .accessibilityLabel(Text(captureManager.isPaused ? "Resume" : "Pause"))

                finishButton

                GlassIconButton(systemImage: "xmark", diameter: secondaryControl) {
                    captureManager.cancelCapture()
                }
                .tint(.red)
                .accessibilityLabel(Text("Cancel capture"))
            } else {
                Spacer()
                ShutterButton { captureManager.startCapture() }
                Spacer()
            }
        }
        .frame(minHeight: 76)
    }

    private var finishButton: some View {
        Button(action: onFinishCapture) {
            Image(systemName: "checkmark")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: max(secondaryControl + 20, 72), height: max(secondaryControl + 20, 72))
                .background(Circle().fill(Color.green))
        }
        .accessibilityLabel(Text("Finish capture"))
    }
}
