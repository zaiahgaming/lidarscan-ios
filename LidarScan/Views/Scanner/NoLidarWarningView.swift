import SwiftUI

public struct NoLidarWarningView: View {
    public let onOpenLibrary: () -> Void
    public let onContinueAnyway: () -> Void

    public init(onOpenLibrary: @escaping () -> Void, onContinueAnyway: @escaping () -> Void) {
        self.onOpenLibrary = onOpenLibrary
        self.onContinueAnyway = onContinueAnyway
    }

    public var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(.orange)
                }

                VStack(spacing: 10) {
                    Text("LiDAR Scanner Required")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("This device lacks hardware LiDAR support. Full scene mesh reconstruction and LiDAR depth require an iPhone Pro (12 Pro through 16 Pro) or an iPad Pro with LiDAR.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                VStack(spacing: 12) {
                    Button(action: onOpenLibrary) {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("Open Scans Library")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.blue)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 32)

                    Button(action: onContinueAnyway) {
                        Text("Continue Anyway (Viewer / Debug)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
        }
    }
}
