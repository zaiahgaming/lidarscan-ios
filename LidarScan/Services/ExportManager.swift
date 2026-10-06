import Foundation
import simd

public final class ExportManager: @unchecked Sendable {
    public static let shared = ExportManager()

    public struct ExportProgress {
        public let stage: String
        public let progress: Float
    }

    public func finalizeCapture(
        captureName: String,
        captureFolder: URL,
        mode: CaptureMode,
        keyframes: [KeyframeRecord],
        pointCloudManager: PointCloudManager,
        meshReconstructor: MeshReconstructor,
        progressHandler: @escaping (ExportProgress) -> Void
    ) throws -> SavedCapture {
        let fileManager = FileManager.default

        // 1. Point Cloud PLY
        progressHandler(ExportProgress(stage: "Generating pointcloud.ply...", progress: 0.15))
        let plyURL = captureFolder.appendingPathComponent("pointcloud.ply")
        try pointCloudManager.writePLY(to: plyURL)

        // 2. Mesh Reconstruction (if in LiDAR Mesh mode and anchors exist)
        let meshFolder = captureFolder.appendingPathComponent("mesh")
        var hasMesh = false
        if mode == .lidarMesh && meshReconstructor.anchorCount > 0 {
            progressHandler(ExportProgress(stage: "Exporting OBJ, PLY, USDZ, GLB mesh...", progress: 0.35))
            let (vCount, _) = try meshReconstructor.exportAll(to: meshFolder)
            hasMesh = vCount > 0
        }

        // 3. transforms.json (nerfstudio format)
        progressHandler(ExportProgress(stage: "Writing transforms.json...", progress: 0.55))
        let firstFrame = keyframes.first
        let width = firstFrame?.imageWidth ?? 1920
        let height = firstFrame?.imageHeight ?? 1440
        let fx = Double(firstFrame?.intrinsics[0][0] ?? 1440.0)
        let fy = Double(firstFrame?.intrinsics[1][1] ?? 1440.0)
        let cx = Double(firstFrame?.intrinsics[2][0] ?? 960.0)
        let cy = Double(firstFrame?.intrinsics[2][1] ?? 720.0)

        var transformFrames: [TransformFrame] = []
        for kf in keyframes {
            let kfFx = Double(kf.intrinsics[0][0])
            let kfFy = Double(kf.intrinsics[1][1])
            let kfCx = Double(kf.intrinsics[2][0])
            let kfCy = Double(kf.intrinsics[2][1])
            let rowMajorMatrix = MatrixMath.toRowMajorArray(kf.transform)

            transformFrames.append(TransformFrame(
                filePath: kf.imageRelativePath,
                depthFilePath: kf.depthRelativePath,
                confidenceFilePath: kf.confidenceRelativePath,
                fl_x: kfFx,
                fl_y: kfFy,
                cx: kfCx,
                cy: kfCy,
                transformMatrix: rowMajorMatrix,
                timestamp: kf.timestamp
            ))
        }

        let transformsData = TransformsData(
            cameraModel: "OPENCV",
            w: width,
            h: height,
            fl_x: fx,
            fl_y: fy,
            cx: cx,
            cy: cy,
            k1: 0.0,
            k2: 0.0,
            p1: 0.0,
            p2: 0.0,
            plyFilePath: "pointcloud.ply",
            frames: transformFrames
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let transformsJsonData = try encoder.encode(transformsData)
        try transformsJsonData.write(to: captureFolder.appendingPathComponent("transforms.json"))

        // 4. metadata.json
        progressHandler(ExportProgress(stage: "Writing metadata.json...", progress: 0.70))
        let metadata = CaptureMetadata(
            device: DeviceUtils.deviceModelIdentifier,
            frameCount: keyframes.count,
            hasMesh: hasMesh,
            hasDepth: true
        )
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: captureFolder.appendingPathComponent("metadata.json"))

        // 5. COLMAP sparse/0/
        progressHandler(ExportProgress(stage: "Writing COLMAP model...", progress: 0.80))
        let colmapFolder = captureFolder.appendingPathComponent("colmap/sparse/0")
        try fileManager.createDirectory(at: colmapFolder, withIntermediateDirectories: true)

        try writeColmapCameras(keyframes: keyframes, to: colmapFolder.appendingPathComponent("cameras.txt"))
        try writeColmapImages(keyframes: keyframes, to: colmapFolder.appendingPathComponent("images.txt"))
        try writeColmapPoints(points: pointCloudManager.getAllPoints(), to: colmapFolder.appendingPathComponent("points3D.txt"))

        // 6. Zip archive: <name>.lidarscan.zip
        progressHandler(ExportProgress(stage: "Creating \(captureName).lidarscan.zip...", progress: 0.90))
        let parentDir = captureFolder.deletingLastPathComponent()
        let zipURL = parentDir.appendingPathComponent("\(captureName).lidarscan.zip")

        try ZipWriter.zip(
            folderURL: captureFolder,
            rootFolderName: captureName,
            destinationZipURL: zipURL
        )

        let fileSize = (try? zipURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        progressHandler(ExportProgress(stage: "Complete!", progress: 1.0))

        return SavedCapture(
            name: captureName,
            folderURL: captureFolder,
            zipURL: zipURL,
            createdDate: Date(),
            frameCount: keyframes.count,
            pointCount: pointCloudManager.pointCount,
            hasMesh: hasMesh,
            fileSize: Int64(fileSize)
        )
    }

    private func writeColmapCameras(keyframes: [KeyframeRecord], to url: URL) throws {
        var content = "# Camera list with one line of data per camera:\n#   CAMERA_ID, MODEL, WIDTH, HEIGHT, PARAMS[]\n# Number of cameras: \(keyframes.count)\n"
        for (i, kf) in keyframes.enumerated() {
            let camId = i + 1
            let fx = kf.intrinsics[0][0]
            let fy = kf.intrinsics[1][1]
            let cx = kf.intrinsics[2][0]
            let cy = kf.intrinsics[2][1]
            content += "\(camId) PINHOLE \(kf.imageWidth) \(kf.imageHeight) \(fx) \(fy) \(cx) \(cy)\n"
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeColmapImages(keyframes: [KeyframeRecord], to url: URL) throws {
        var content = "# Image list with two lines of data per image:\n#   IMAGE_ID, QW, QX, QY, QZ, TX, TY, TZ, CAMERA_ID, NAME\n#   POINTS2D[] as (X, Y, POINT3D_ID)\n# Number of images: \(keyframes.count)\n"
        for (i, kf) in keyframes.enumerated() {
            let imgId = i + 1
            let (qw, qx, qy, qz, tx, ty, tz) = MatrixMath.colmapPose(from: kf.transform)
            content += "\(imgId) \(qw) \(qx) \(qy) \(qz) \(tx) \(ty) \(tz) \(imgId) \(kf.imageRelativePath)\n\n"
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeColmapPoints(points: [PointRecord], to url: URL) throws {
        let subsampled = points.prefix(100_000)
        let handle = try FileHandle(forWritingTo: {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            return url
        }())
        defer { try? handle.close() }

        let header = "# 3D point list with one line of data per point:\n#   POINT3D_ID, X, Y, Z, R, G, B, ERROR, TRACK[] as (IMAGE_ID, POINT2D_IDX)\n# Number of points: \(subsampled.count)\n"
        if let hData = header.data(using: .utf8) { handle.write(hData) }

        var buffer = ""
        for (i, pt) in subsampled.enumerated() {
            let ptId = i + 1
            buffer += "\(ptId) \(pt.position.x) \(pt.position.y) \(pt.position.z) \(pt.r) \(pt.g) \(pt.b) 0.0\n"
            if buffer.count > 64 * 1024 {
                if let d = buffer.data(using: .utf8) { handle.write(d) }
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty, let d = buffer.data(using: .utf8) {
            handle.write(d)
        }
    }
}
