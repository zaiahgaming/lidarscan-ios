import Foundation
import simd

public struct KeyframeRecord {
    public let index: Int
    public let timestamp: TimeInterval
    public let transform: simd_float4x4
    public let intrinsics: simd_float3x3
    public let imageWidth: Int
    public let imageHeight: Int
    public let imageRelativePath: String
    public let depthRelativePath: String?
    public let confidenceRelativePath: String?

    public init(
        index: Int,
        timestamp: TimeInterval,
        transform: simd_float4x4,
        intrinsics: simd_float3x3,
        imageWidth: Int,
        imageHeight: Int,
        imageRelativePath: String,
        depthRelativePath: String? = nil,
        confidenceRelativePath: String? = nil
    ) {
        self.index = index
        self.timestamp = timestamp
        self.transform = transform
        self.intrinsics = intrinsics
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageRelativePath = imageRelativePath
        self.depthRelativePath = depthRelativePath
        self.confidenceRelativePath = confidenceRelativePath
    }
}
