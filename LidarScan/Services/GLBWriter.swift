import Foundation
import simd

public enum GLBWriter {
    public static func writeGLB(vertices: [simd_float3], faces: [[Int32]], to destinationURL: URL) throws {
        guard !vertices.isEmpty else {
            throw NSError(domain: "GLBWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot export empty mesh"])
        }

        // Calculate bounding box
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude

        var vertexData = Data(capacity: vertices.count * 12)
        for v in vertices {
            minX = min(minX, v.x)
            minY = min(minY, v.y)
            minZ = min(minZ, v.z)
            maxX = max(maxX, v.x)
            maxY = max(maxY, v.y)
            maxZ = max(maxZ, v.z)

            var x = v.x.littleEndian
            var y = v.y.littleEndian
            var z = v.z.littleEndian
            withUnsafeBytes(of: &x) { vertexData.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { vertexData.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { vertexData.append(contentsOf: $0) }
        }

        // Flatten faces
        var indexData = Data(capacity: faces.count * 3 * 4)
        var totalIndices = 0
        for face in faces {
            for idx in face.prefix(3) {
                var val = UInt32(max(0, idx)).littleEndian
                withUnsafeBytes(of: &val) { indexData.append(contentsOf: $0) }
                totalIndices += 1
            }
        }

        let vertexByteLength = vertexData.count
        let indexByteOffset = vertexByteLength
        let indexByteLength = indexData.count
        var binBuffer = Data()
        binBuffer.append(vertexData)
        binBuffer.append(indexData)

        // Pad binBuffer to 4-byte alignment
        let binPadding = (4 - (binBuffer.count % 4)) % 4
        if binPadding > 0 {
            binBuffer.append(Data(repeating: 0, count: binPadding))
        }

        let totalBinLength = binBuffer.count

        let jsonObject: [String: Any] = [
            "asset": [
                "version": "2.0",
                "generator": "LidarScan"
            ],
            "scene": 0,
            "scenes": [
                ["nodes": [0]]
            ],
            "nodes": [
                ["mesh": 0]
            ],
            "meshes": [
                [
                    "primitives": [
                        [
                            "attributes": [
                                "POSITION": 0
                            ],
                            "indices": 1,
                            "mode": 4
                        ]
                    ]
                ]
            ],
            "accessors": [
                [
                    "bufferView": 0,
                    "byteOffset": 0,
                    "componentType": 5126, // FLOAT
                    "count": vertices.count,
                    "type": "VEC3",
                    "min": [minX, minY, minZ],
                    "max": [maxX, maxY, maxZ]
                ],
                [
                    "bufferView": 1,
                    "byteOffset": 0,
                    "componentType": 5125, // UNSIGNED_INT
                    "count": totalIndices,
                    "type": "SCALAR"
                ]
            ],
            "bufferViews": [
                [
                    "buffer": 0,
                    "byteOffset": 0,
                    "byteLength": vertexByteLength,
                    "target": 34962 // ARRAY_BUFFER
                ],
                [
                    "buffer": 0,
                    "byteOffset": indexByteOffset,
                    "byteLength": indexByteLength,
                    "target": 34963 // ELEMENT_ARRAY_BUFFER
                ]
            ],
            "buffers": [
                [
                    "byteLength": totalBinLength
                ]
            ]
        ]

        var jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        let jsonPadding = (4 - (jsonData.count % 4)) % 4
        if jsonPadding > 0 {
            jsonData.append(Data(repeating: 0x20, count: jsonPadding)) // space padding
        }

        // Header: 12 bytes
        // Chunk 0: 8 bytes + JSON
        // Chunk 1: 8 bytes + BIN
        let totalFileLength = UInt32(12 + 8 + jsonData.count + 8 + binBuffer.count)

        var glbData = Data()
        var magic = UInt32(0x46546C67).littleEndian // "glTF"
        var version = UInt32(2).littleEndian
        var fileLen = totalFileLength.littleEndian
        glbData.append(Data(bytes: &magic, count: 4))
        glbData.append(Data(bytes: &version, count: 4))
        glbData.append(Data(bytes: &fileLen, count: 4))

        // Chunk 0: JSON
        var jsonChunkLength = UInt32(jsonData.count).littleEndian
        var jsonChunkType = UInt32(0x4E4F534A).littleEndian // "JSON"
        glbData.append(Data(bytes: &jsonChunkLength, count: 4))
        glbData.append(Data(bytes: &jsonChunkType, count: 4))
        glbData.append(jsonData)

        // Chunk 1: BIN
        var binChunkLength = UInt32(binBuffer.count).littleEndian
        var binChunkType = UInt32(0x004E4942).littleEndian // "BIN\0"
        glbData.append(Data(bytes: &binChunkLength, count: 4))
        glbData.append(Data(bytes: &binChunkType, count: 4))
        glbData.append(binBuffer)

        try glbData.write(to: destinationURL, options: .atomic)
    }
}
