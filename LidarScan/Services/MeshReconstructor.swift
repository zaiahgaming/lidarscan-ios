import Foundation
import ARKit
import SceneKit
import simd

public final class MeshReconstructor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.zaiah.lidarscan.mesh", qos: .userInitiated)
    private var anchors: [UUID: ARMeshAnchor] = [:]

    public init() {}

    public func reset() {
        queue.sync {
            anchors.removeAll()
        }
    }

    public func update(anchor: ARMeshAnchor) {
        queue.async { [weak self] in
            self?.anchors[anchor.identifier] = anchor
        }
    }

    public func remove(anchor: ARMeshAnchor) {
        queue.async { [weak self] in
            self?.anchors.removeValue(forKey: anchor.identifier)
        }
    }

    public var anchorCount: Int {
        queue.sync { anchors.count }
    }

    public struct ConsolidatedMesh {
        public let vertices: [simd_float3]
        public let faces: [[Int32]]
    }

    public func consolidateMesh() -> ConsolidatedMesh {
        queue.sync {
            var allVertices: [simd_float3] = []
            var allFaces: [[Int32]] = []

            for (_, anchor) in anchors {
                let geom = anchor.geometry
                let vSource = geom.vertices
                let fElement = geom.faces

                let baseOffset = Int32(allVertices.count)
                let vBuffer = vSource.buffer.contents()
                let vStride = vSource.stride

                for i in 0..<vSource.count {
                    let ptr = vBuffer.advanced(by: i * vStride).assumingMemoryBound(to: Float.self)
                    let localV = simd_float4(ptr[0], ptr[1], ptr[2], 1.0)
                    let worldV = anchor.transform * localV
                    allVertices.append(simd_float3(worldV.x, worldV.y, worldV.z))
                }

                let fBuffer = fElement.buffer.contents()
                let bytesPerIndex = fElement.bytesPerIndex

                for i in 0..<fElement.count {
                    var tri: [Int32] = []
                    for j in 0..<3 {
                        let idx: Int32
                        if bytesPerIndex == 4 {
                            let val = fBuffer.advanced(by: (i * 3 + j) * 4).assumingMemoryBound(to: UInt32.self).pointee
                            idx = Int32(val)
                        } else {
                            let val = fBuffer.advanced(by: (i * 3 + j) * 2).assumingMemoryBound(to: UInt16.self).pointee
                            idx = Int32(val)
                        }
                        tri.append(baseOffset + idx)
                    }
                    allFaces.append(tri)
                }
            }

            return ConsolidatedMesh(vertices: allVertices, faces: allFaces)
        }
    }

    public func exportAll(to meshFolder: URL) throws -> (vertexCount: Int, faceCount: Int) {
        let mesh = consolidateMesh()
        guard !mesh.vertices.isEmpty else {
            return (0, 0)
        }

        try FileManager.default.createDirectory(at: meshFolder, withIntermediateDirectories: true)

        // 1. OBJ + MTL
        let objURL = meshFolder.appendingPathComponent("mesh.obj")
        let mtlURL = meshFolder.appendingPathComponent("mesh.mtl")
        try exportOBJ(mesh: mesh, objURL: objURL, mtlURL: mtlURL)

        // 2. PLY
        let plyURL = meshFolder.appendingPathComponent("mesh.ply")
        try exportPLY(mesh: mesh, plyURL: plyURL)

        // 3. GLB
        let glbURL = meshFolder.appendingPathComponent("mesh.glb")
        try GLBWriter.writeGLB(vertices: mesh.vertices, faces: mesh.faces, to: glbURL)

        // 4. USDZ
        let usdzURL = meshFolder.appendingPathComponent("mesh.usdz")
        exportUSDZ(mesh: mesh, usdzURL: usdzURL)

        return (mesh.vertices.count, mesh.faces.count)
    }

    private func exportOBJ(mesh: ConsolidatedMesh, objURL: URL, mtlURL: URL) throws {
        let mtlContent = """
        newmtl default
        Kd 0.75 0.75 0.75
        Ka 0.20 0.20 0.20
        d 1.0
        illum 2
        """
        try mtlContent.write(to: mtlURL, atomically: true, encoding: .utf8)

        let handle = try FileHandle(forWritingTo: {
            FileManager.default.createFile(atPath: objURL.path, contents: nil)
            return objURL
        }())
        defer { try? handle.close() }

        let header = "mtllib mesh.mtl\no mesh\n"
        if let hData = header.data(using: .utf8) { handle.write(hData) }

        var buf = ""
        for v in mesh.vertices {
            buf += "v \(v.x) \(v.y) \(v.z)\n"
            if buf.count > 64 * 1024 {
                if let d = buf.data(using: .utf8) { handle.write(d) }
                buf.removeAll(keepingCapacity: true)
            }
        }

        buf += "usemtl default\n"
        for f in mesh.faces {
            buf += "f \(f[0] + 1) \(f[1] + 1) \(f[2] + 1)\n"
            if buf.count > 64 * 1024 {
                if let d = buf.data(using: .utf8) { handle.write(d) }
                buf.removeAll(keepingCapacity: true)
            }
        }

        if !buf.isEmpty, let d = buf.data(using: .utf8) {
            handle.write(d)
        }
    }

    private func exportPLY(mesh: ConsolidatedMesh, plyURL: URL) throws {
        let header = "ply\nformat binary_little_endian 1.0\nelement vertex \(mesh.vertices.count)\nproperty float x\nproperty float y\nproperty float z\nelement face \(mesh.faces.count)\nproperty list uchar int vertex_indices\nend_header\n"

        guard let headerData = header.data(using: .ascii) else { return }

        FileManager.default.createFile(atPath: plyURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: plyURL)
        defer { try? handle.close() }

        handle.write(headerData)

        var vBuf = Data(capacity: 64 * 1024)
        for v in mesh.vertices {
            var x = v.x.bitPattern.littleEndian
            var y = v.y.bitPattern.littleEndian
            var z = v.z.bitPattern.littleEndian
            withUnsafeBytes(of: &x) { vBuf.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { vBuf.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { vBuf.append(contentsOf: $0) }

            if vBuf.count >= 60 * 1024 {
                handle.write(vBuf)
                vBuf.removeAll(keepingCapacity: true)
            }
        }
        if !vBuf.isEmpty { handle.write(vBuf) }

        var fBuf = Data(capacity: 64 * 1024)
        for f in mesh.faces {
            fBuf.append(3) // 3 vertices per face
            var i0 = f[0].littleEndian
            var i1 = f[1].littleEndian
            var i2 = f[2].littleEndian
            withUnsafeBytes(of: &i0) { fBuf.append(contentsOf: $0) }
            withUnsafeBytes(of: &i1) { fBuf.append(contentsOf: $0) }
            withUnsafeBytes(of: &i2) { fBuf.append(contentsOf: $0) }

            if fBuf.count >= 60 * 1024 {
                handle.write(fBuf)
                fBuf.removeAll(keepingCapacity: true)
            }
        }
        if !fBuf.isEmpty { handle.write(fBuf) }
    }

    private func exportUSDZ(mesh: ConsolidatedMesh, usdzURL: URL) {
        guard !mesh.vertices.isEmpty, !mesh.faces.isEmpty else { return }

        let scnVertices = mesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        let vertexSource = SCNGeometrySource(vertices: scnVertices)

        var flatIndices: [Int32] = []
        flatIndices.reserveCapacity(mesh.faces.count * 3)
        for face in mesh.faces {
            flatIndices.append(contentsOf: face.prefix(3))
        }

        let element = SCNGeometryElement(indices: flatIndices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])

        let node = SCNNode(geometry: geometry)
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)

        scene.write(to: usdzURL, options: nil, delegate: nil, progressHandler: nil)
    }
}
