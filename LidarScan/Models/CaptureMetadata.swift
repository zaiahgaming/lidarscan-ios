import Foundation

public struct CaptureMetadata: Codable {
    public let format: String
    public let version: Int
    public let app_version: String
    public let device: String
    public let created: String
    public let frame_count: Int
    public let has_mesh: Bool
    public let has_depth: Bool
    public let depth_units: String
    public let coordinate_system: String

    public init(
        format: String = "lidarscan",
        version: Int = 1,
        appVersion: String = "1.0.0",
        device: String,
        created: String = ISO8601DateFormatter().string(from: Date()),
        frameCount: Int,
        hasMesh: Bool,
        hasDepth: Bool,
        depthUnits: String = "millimeters",
        coordinateSystem: String = "ARKit (right-handed, Y up, camera looks -Z)"
    ) {
        self.format = format
        self.version = version
        self.app_version = appVersion
        self.device = device
        self.created = created
        self.frame_count = frameCount
        self.has_mesh = hasMesh
        self.has_depth = hasDepth
        self.depth_units = depthUnits
        self.coordinate_system = coordinateSystem
    }
}
