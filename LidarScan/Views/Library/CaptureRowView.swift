import SwiftUI

/// A single scan row. Uses system text styles so rows grow gracefully with
/// Dynamic Type instead of clipping fixed-size text.
public struct CaptureRowView: View {
    public let capture: SavedCapture

    public init(capture: SavedCapture) {
        self.capture = capture
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: capture.hasMesh ? "cube.fill" : "circle.grid.cross.fill")
                .font(.title3)
                .foregroundStyle(capture.hasMesh ? Color.cyan : Color.green)
                .frame(width: 40, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(capture.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 5) {
                    Text(capture.formattedDate)
                    Text("•")
                    Text("\(capture.frameCount) frames")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(capture.formattedSize)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if capture.hasMesh {
                    Text("MESH")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.cyan.opacity(0.18), in: Capsule())
                        .foregroundStyle(.cyan)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
