import Foundation
import simd

public struct PointRecord {
    public let position: simd_float3
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(position: simd_float3, r: UInt8, g: UInt8, b: UInt8) {
        self.position = position
        self.r = r
        self.g = g
        self.b = b
    }
}

public struct VoxelKey: Hashable {
    public let x: Int32
    public let y: Int32
    public let z: Int32

    public init(x: Int32, y: Int32, z: Int32) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(position: simd_float3, voxelSize: Float) {
        self.x = Int32(floor(position.x / voxelSize))
        self.y = Int32(floor(position.y / voxelSize))
        self.z = Int32(floor(position.z / voxelSize))
    }
}
