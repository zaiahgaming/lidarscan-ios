import SwiftUI

public struct CaptureRowView: View {
    public let capture: SavedCapture

    public init(capture: SavedCapture) {
        self.capture = capture
    }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: capture.hasMesh ? "cube.fill" : "circle.grid.cross.fill")
                    .font(.system(size: 20))
                    .foregroundColor(capture.hasMesh ? .cyan : .green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(capture.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(capture.formattedDate)
                        .lineLimit(1)
                    Text("•")
                    Text("\(capture.frameCount) frames")
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(capture.formattedSize)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if capture.hasMesh {
                    Text("MESH")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.2))
                        .foregroundColor(.cyan)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
