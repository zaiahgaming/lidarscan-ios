import Foundation

public enum CaptureMode: String, CaseIterable, Identifiable {
    case lidarMesh = "LiDAR Mesh"
    case splatPhoto = "Photo / Splat"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lidarMesh:
            return "LiDAR Mesh"
        case .splatPhoto:
            return "Photo / Splat"
        }
    }

    public var description: String {
        switch self {
        case .lidarMesh:
            return "Real-time surface mesh reconstruction with LiDAR depth & keyframes"
        case .splatPhoto:
            return "High-fidelity spatial keyframes & point cloud for Gaussian Splatting"
        }
    }

    public var iconName: String {
        switch self {
        case .lidarMesh:
            return "square.stack.3d.down.forward"
        case .splatPhoto:
            return "camera.aperture"
        }
    }
}
