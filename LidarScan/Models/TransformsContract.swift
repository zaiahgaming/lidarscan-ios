import Foundation

public struct TransformsData: Codable {
    public let camera_model: String
    public let w: Int
    public let h: Int
    public let fl_x: Double
    public let fl_y: Double
    public let cx: Double
    public let cy: Double
    public let k1: Double
    public let k2: Double
    public let p1: Double
    public let p2: Double
    public let ply_file_path: String
    public let frames: [TransformFrame]

    public init(
        cameraModel: String = "OPENCV",
        w: Int,
        h: Int,
        fl_x: Double,
        fl_y: Double,
        cx: Double,
        cy: Double,
        k1: Double = 0.0,
        k2: Double = 0.0,
        p1: Double = 0.0,
        p2: Double = 0.0,
        plyFilePath: String = "pointcloud.ply",
        frames: [TransformFrame]
    ) {
        self.camera_model = cameraModel
        self.w = w
        self.h = h
        self.fl_x = fl_x
        self.fl_y = fl_y
        self.cx = cx
        self.cy = cy
        self.k1 = k1
        self.k2 = k2
        self.p1 = p1
        self.p2 = p2
        self.ply_file_path = plyFilePath
        self.frames = frames
    }
}

public struct TransformFrame: Codable {
    public let file_path: String
    public let depth_file_path: String?
    public let confidence_file_path: String?
    public let fl_x: Double
    public let fl_y: Double
    public let cx: Double
    public let cy: Double
    public let transform_matrix: [[Double]]
    public let timestamp: Double

    public init(
        filePath: String,
        depthFilePath: String? = nil,
        confidenceFilePath: String? = nil,
        fl_x: Double,
        fl_y: Double,
        cx: Double,
        cy: Double,
        transformMatrix: [[Double]],
        timestamp: Double
    ) {
        self.file_path = filePath
        self.depth_file_path = depthFilePath
        self.confidence_file_path = confidenceFilePath
        self.fl_x = fl_x
        self.fl_y = fl_y
        self.cx = cx
        self.cy = cy
        self.transform_matrix = transformMatrix
        self.timestamp = timestamp
    }
}
