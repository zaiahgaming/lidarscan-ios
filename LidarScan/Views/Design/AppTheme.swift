import SwiftUI

// MARK: - Adaptive Liquid Glass
//
// Apple's current design language (iOS 26+) uses Liquid Glass for controls
// that float above content such as a live camera feed. On iOS 17–25 the same
// views fall back to system blur materials, so every surface is a genuine
// system material — never a hand-mixed translucent color.

extension View {
    /// Liquid Glass on iOS 26+, `ultraThinMaterial` on earlier releases.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Rounded-card variant used for grouped content.
    @ViewBuilder
    func adaptiveGlassCard(cornerRadius: CGFloat = 20) -> some View {
        adaptiveGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Glass Icon Button
//
// HIG: maintain a 44×44pt minimum hit target and let controls grow with
// Dynamic Type. Fixed pt sizes are replaced by `@ScaledMetric`.

struct GlassIconButton: View {
    let systemImage: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 17

    init(systemImage: String, diameter: CGFloat = 44, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self._diameter = ScaledMetric(wrappedValue: diameter, relativeTo: .body)
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: max(diameter, 44), height: max(diameter, 44))
        }
        .adaptiveGlass(in: Circle())
        .accessibilityLabel(Text(systemImage.replacingOccurrences(of: ".", with: " ")))
    }
}

// MARK: - Stat Chip
//
// A labeled value readout for the capture HUD. Monospaced digits keep the
// layout stable while values tick up during a recording.

struct StatChip: View {
    let title: String
    let value: String
    var tint: Color = .white

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Shutter Button
//
// The primary capture control. Scales with Dynamic Type while keeping the
// classic record affordance of a filled circle inside a ring.

struct ShutterButton: View {
    let action: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 76
    @ScaledMetric(relativeTo: .largeTitle) private var innerSize: CGFloat = 62

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                Circle()
                    .fill(.red)
                    .padding(7)
            }
            .frame(width: max(size, 60), height: max(size, 60))
        }
        .accessibilityLabel(Text("Start recording"))
    }
}
