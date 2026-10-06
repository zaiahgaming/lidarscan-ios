import SwiftUI

public struct CaptureRowView: View {
    public let capture: SavedCapture

    public init(capture: SavedCapture) {
        self.capture = capture
    }

    public var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 52, height: 52)
                Image(systemName: capture.hasMesh ? "cube.fill" : "circle.grid.cross.fill")
                    .font(.system(size: 22))
                    .foregroundColor(capture.hasMesh ? .cyan : .green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(capture.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(capture.formattedDate)
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text("\(capture.frameCount) frames")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(capture.formattedSize)
                    .font(.caption.monospaced())
                    .foregroundColor(.gray)

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
