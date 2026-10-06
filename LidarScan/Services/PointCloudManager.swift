import Foundation
import CoreVideo
import simd

public final class PointCloudManager: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.zaiah.lidarscan.pointcloud", qos: .userInitiated)
    private var voxels: [VoxelKey: PointRecord] = [:]
    private let voxelSize: Float = 0.01 // 1 cm voxel resolution
    private let maxPoints: Int = 400_000

    public var pointCount: Int {
        queue.sync { voxels.count }
    }

    public init() {}

    public func reset() {
        queue.sync {
            voxels.removeAll(keepingCapacity: true)
        }
    }

    public func addPoints(
        depthBuffer: CVPixelBuffer,
        confidenceBuffer: CVPixelBuffer,
        imageBuffer: CVPixelBuffer,
        intrinsics: simd_float3x3,
        c2w: simd_float4x4
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.voxels.count >= self.maxPoints { return }

            CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
            CVPixelBufferLockBaseAddress(confidenceBuffer, .readOnly)
            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)
                CVPixelBufferUnlockBaseAddress(confidenceBuffer, .readOnly)
                CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
            }

            let dWidth = CVPixelBufferGetWidth(depthBuffer)
            let dHeight = CVPixelBufferGetHeight(depthBuffer)
            guard let dBase = CVPixelBufferGetBaseAddress(depthBuffer),
                  let cBase = CVPixelBufferGetBaseAddress(confidenceBuffer) else { return }

            let dBytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
            let cBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceBuffer)

            let imgWidth = CVPixelBufferGetWidth(imageBuffer)
            let imgHeight = CVPixelBufferGetHeight(imageBuffer)
            let isBiPlanar = CVPixelBufferIsPlanar(imageBuffer) && CVPixelBufferGetPlaneCount(imageBuffer) >= 2

            let lumaBase = isBiPlanar ? CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0) : nil
            let lumaBPR = isBiPlanar ? CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0) : 0
            let chromaBase = isBiPlanar ? CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1) : nil
            let chromaBPR = isBiPlanar ? CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1) : 0

            // Intrinsics scaling from RGB image resolution to depth map resolution
            let sx = Float(dWidth) / Float(imgWidth)
            let sy = Float(dHeight) / Float(imgHeight)
            let fx_d = intrinsics[0][0] * sx
            let fy_d = intrinsics[1][1] * sy
            let cx_d = intrinsics[2][0] * sx
            let cy_d = intrinsics[2][1] * sy

            guard fx_d > 0.0, fy_d > 0.0 else { return }

            // Stride to sample evenly
            let step = 1
            for v in stride(from: 0, to: dHeight, by: step) {
                let dRow = dBase.advanced(by: v * dBytesPerRow).assumingMemoryBound(to: Float32.self)
                let cRow = cBase.advanced(by: v * cBytesPerRow).assumingMemoryBound(to: UInt8.self)

                for u in stride(from: 0, to: dWidth, by: step) {
                    let conf = cRow[u]
                    guard conf >= 1 else { continue } // Medium or High confidence only

                    let depth = dRow[u]
                    guard !depth.isNaN, !depth.isInfinite, depth > 0.15, depth < 5.0 else { continue }

                    // Camera frame: X right, Y up, -Z forward (ARKit convention)
                    let x_cam = (Float(u) + 0.5 - cx_d) / fx_d * depth
                    let y_cam = -(Float(v) + 0.5 - cy_d) / fy_d * depth
                    let z_cam = -depth

                    let p_cam4 = simd_float4(x_cam, y_cam, z_cam, 1.0)
                    let p_world4 = c2w * p_cam4
                    let p_world = simd_float3(p_world4.x, p_world4.y, p_world4.z)

                    let key = VoxelKey(position: p_world, voxelSize: self.voxelSize)
                    if self.voxels[key] != nil { continue }

                    // Sample RGB
                    var r: UInt8 = 200, g: UInt8 = 200, b: UInt8 = 200
                    if isBiPlanar, let luma = lumaBase, let chroma = chromaBase {
                        let imgX = min(imgWidth - 1, max(0, Int(Float(u) / sx)))
                        let imgY = min(imgHeight - 1, max(0, Int(Float(v) / sy)))

                        let yVal = Float(luma.advanced(by: imgY * lumaBPR + imgX).assumingMemoryBound(to: UInt8.self).pointee)
                        let chromaPtr = chroma.advanced(by: (imgY / 2) * chromaBPR + (imgX / 2) * 2).assumingMemoryBound(to: UInt8.self)
                        let cbVal = Float(chromaPtr[0]) - 128.0
                        let crVal = Float(chromaPtr[1]) - 128.0

                        r = UInt8(clamping: Int((yVal + 1.402 * crVal).rounded()))
                        g = UInt8(clamping: Int((yVal - 0.344136 * cbVal - 0.714136 * crVal).rounded()))
                        b = UInt8(clamping: Int((yVal + 1.772 * cbVal).rounded()))
                    }

                    self.voxels[key] = PointRecord(position: p_world, r: r, g: g, b: b)
                    if self.voxels.count >= self.maxPoints { break }
                }
            }
        }
    }

    public func getAllPoints() -> [PointRecord] {
        queue.sync {
            Array(voxels.values)
        }
    }

    public func writePLY(to destinationURL: URL) throws {
        let points = getAllPoints()
        let count = points.count

        let header = "ply\nformat binary_little_endian 1.0\nelement vertex \(count)\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n"

        guard let headerData = header.data(using: .ascii) else {
            throw NSError(domain: "PointCloudManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PLY header"])
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        fileManager.createFile(atPath: destinationURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }

        handle.write(headerData)

        // Stream binary points in 64KB batches
        var buffer = Data(capacity: 64 * 1024)
        for pt in points {
            var x = pt.position.x.bitPattern.littleEndian
            var y = pt.position.y.bitPattern.littleEndian
            var z = pt.position.z.bitPattern.littleEndian
            withUnsafeBytes(of: &x) { buffer.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { buffer.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { buffer.append(contentsOf: $0) }
            buffer.append(pt.r)
            buffer.append(pt.g)
            buffer.append(pt.b)

            if buffer.count >= 60 * 1024 {
                handle.write(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            handle.write(buffer)
        }
    }
}
