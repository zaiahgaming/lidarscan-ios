import SwiftUI
import SceneKit
import simd

public struct SceneKitModelView: UIViewRepresentable {
    public let captureFolder: URL
    public let showWireframe: Bool
    public let preferPointCloud: Bool

    public init(captureFolder: URL, showWireframe: Bool = false, preferPointCloud: Bool = false) {
        self.captureFolder = captureFolder
        self.showWireframe = showWireframe
        self.preferPointCloud = preferPointCloud
    }

    public func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        let scene = buildScene()
        scnView.scene = scene
        return scnView
    }

    public func updateUIView(_ scnView: SCNView, context: Context) {
        // Toggle wireframe on materials
        if let root = scnView.scene?.rootNode {
            applyWireframe(node: root, wireframe: showWireframe)
        }
    }

    private func applyWireframe(node: SCNNode, wireframe: Bool) {
        if let geom = node.geometry {
            for mat in geom.materials {
                mat.fillMode = wireframe ? .lines : .fill
            }
        }
        for child in node.childNodes {
            applyWireframe(node: child, wireframe: wireframe)
        }
    }

    private func buildScene() -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode

        let meshObjURL = captureFolder.appendingPathComponent("mesh/mesh.obj")
        let meshUsdzURL = captureFolder.appendingPathComponent("mesh/mesh.usdz")
        let plyURL = captureFolder.appendingPathComponent("pointcloud.ply")

        var loadedNode: SCNNode?

        if !preferPointCloud {
            if FileManager.default.fileExists(atPath: meshUsdzURL.path),
               let loadedScene = try? SCNScene(url: meshUsdzURL, options: nil) {
                let container = SCNNode()
                for child in loadedScene.rootNode.childNodes {
                    container.addChildNode(child)
                }
                loadedNode = container
            } else if FileManager.default.fileExists(atPath: meshObjURL.path),
                      let loadedScene = try? SCNScene(url: meshObjURL, options: nil) {
                let container = SCNNode()
                for child in loadedScene.rootNode.childNodes {
                    container.addChildNode(child)
                }
                loadedNode = container
            }
        }

        // Fall back to point cloud if preferred or mesh not found
        if loadedNode == nil && FileManager.default.fileExists(atPath: plyURL.path) {
            loadedNode = loadPointCloudNode(from: plyURL)
        }

        if let node = loadedNode {
            root.addChildNode(node)

            // Adjust camera to frame model
            let (minVec, maxVec) = node.boundingBox
            let center = SCNVector3(
                (minVec.x + maxVec.x) / 2.0,
                (minVec.y + maxVec.y) / 2.0,
                (minVec.z + maxVec.z) / 2.0
            )
            let radius = max(max(maxVec.x - minVec.x, maxVec.y - minVec.y), maxVec.z - minVec.z)

            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(center.x, center.y + (radius * 0.4), center.z + max(1.0, radius * 1.5))
            cameraNode.look(at: center)
            root.addChildNode(cameraNode)
        } else {
            // Placeholder cube if nothing found
            let box = SCNBox(width: 0.2, height: 0.2, length: 0.2, chamferRadius: 0.02)
            box.firstMaterial?.diffuse.contents = UIColor.systemBlue
            let boxNode = SCNNode(geometry: box)
            root.addChildNode(boxNode)
        }

        return scene
    }

    private func loadPointCloudNode(from plyURL: URL) -> SCNNode? {
        guard let data = try? Data(contentsOf: plyURL) else { return nil }
        guard let headerEnd = data.range(of: "end_header\n".data(using: .ascii)!) else { return nil }

        let binaryData = data.subdata(in: headerEnd.upperBound..<data.count)
        let stride = 15 // 12 bytes float (x,y,z) + 3 bytes (r,g,b)
        let pointCount = binaryData.count / stride
        guard pointCount > 0 else { return nil }

        var vertices: [SCNVector3] = []
        var colors: [SCNVector3] = []
        vertices.reserveCapacity(pointCount)
        colors.reserveCapacity(pointCount)

        binaryData.withUnsafeBytes { rawPtr in
            for i in 0..<pointCount {
                let offset = i * stride
                let x = rawPtr.loadUnaligned(fromByteOffset: offset, as: Float.self)
                let y = rawPtr.loadUnaligned(fromByteOffset: offset + 4, as: Float.self)
                let z = rawPtr.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)
                let r = Float(rawPtr.loadUnaligned(fromByteOffset: offset + 12, as: UInt8.self)) / 255.0
                let g = Float(rawPtr.loadUnaligned(fromByteOffset: offset + 13, as: UInt8.self)) / 255.0
                let b = Float(rawPtr.loadUnaligned(fromByteOffset: offset + 14, as: UInt8.self)) / 255.0

                vertices.append(SCNVector3(x, y, z))
                colors.append(SCNVector3(r, g, b))
            }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let colorSource = SCNGeometrySource(
            data: Data(bytes: colors, count: colors.count * MemoryLayout<SCNVector3>.stride),
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.stride
        )

        let indices = (0..<Int32(vertices.count)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 3.0
        element.minimumPointScreenSpaceRadius = 1.0
        element.maximumPointScreenSpaceRadius = 8.0

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        return SCNNode(geometry: geometry)
    }
}
