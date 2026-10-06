import Foundation
import ARKit
import CoreImage
import CoreGraphics
import simd

public final class KeyframeManager: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.zaiah.lidarscan.keyframes", qos: .userInitiated)
    private let ciContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])

    private var lastKeyframeTransform: simd_float4x4?
    private var lastKeyframeTime: TimeInterval = 0
    private var keyframes: [KeyframeRecord] = []
    private var keyframeIndex = 0

    // Thresholds: >5cm translation or >5 deg rotation
    public let minTranslationDelta: Float = 0.05
    public let minRotationDelta: Float = 5.0
    public let maxTranslationalVelocity: Float = 1.0 // m/s
    public let maxAngularVelocity: Float = 75.0 // deg/s

    public var recordedKeyframes: [KeyframeRecord] {
        queue.sync { keyframes }
    }

    public var keyframeCount: Int {
        queue.sync { keyframes.count }
    }

    public init() {}

    public func reset() {
        queue.sync {
            lastKeyframeTransform = nil
            lastKeyframeTime = 0
            keyframes.removeAll()
            keyframeIndex = 0
        }
    }

    public enum FrameAcceptance {
        case accept
        case skipTooClose
        case skipBlurryOrFast(String)
        case skipBadTracking
    }

    public func evaluateFrame(_ frame: ARFrame) -> FrameAcceptance {
        // 1. Check tracking state
        guard frame.camera.trackingState == .normal else {
            return .skipBadTracking
        }

        let currentTransform = frame.camera.transform
        let currentTime = frame.timestamp

        // First frame is always accepted
        guard let lastTransform = lastKeyframeTransform else {
            return .accept
        }

        let dt = max(0.001, currentTime - lastKeyframeTime)
        let tDist = MatrixMath.translationDistance(lastTransform, currentTransform)
        let rAngle = MatrixMath.rotationAngleDegrees(lastTransform, currentTransform)

        let tVel = tDist / Float(dt)
        let rVel = rAngle / Float(dt)

        if tVel > maxTranslationalVelocity || rVel > maxAngularVelocity {
            return .skipBlurryOrFast("Move slower for sharper capture")
        }

        if tDist >= minTranslationDelta || rAngle >= minRotationDelta {
            return .accept
        }

        return .skipTooClose
    }

    public func recordKeyframe(
        from frame: ARFrame,
        baseFolder: URL,
        pointCloudManager: PointCloudManager,
        completion: (@Sendable (KeyframeRecord?) -> Void)? = nil
    ) {
        let transform = frame.camera.transform
        let intrinsics = frame.camera.intrinsics
        let timestamp = frame.timestamp
        let capturedImage = frame.capturedImage
        let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
        let confidenceMap = frame.smoothedSceneDepth?.confidenceMap ?? frame.sceneDepth?.confidenceMap

        queue.async { [weak self] in
            guard let self = self else { return }

            self.lastKeyframeTransform = transform
            self.lastKeyframeTime = timestamp
            let currentIndex = self.keyframeIndex
            self.keyframeIndex += 1

            let frameString = String(format: "frame_%05d", currentIndex)
            let imgRelPath = "images/\(frameString).jpg"
            let imgURL = baseFolder.appendingPathComponent(imgRelPath)

            // Ensure parent images directory exists
            try? FileManager.default.createDirectory(at: imgURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            // Save JPEG full res (orientation = sensor landscape, no rotation)
            let ciImage = CIImage(cvPixelBuffer: capturedImage)
            let cs = ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
            if let jpegData = self.ciContext.jpegRepresentation(
                of: ciImage,
                colorSpace: cs,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]
            ) {
                try? jpegData.write(to: imgURL, options: .atomic)
            }

            var depthRelPath: String? = nil
            var confRelPath: String? = nil

            if let depth = depthMap, let conf = confidenceMap {
                let dRel = "depth/\(frameString).png"
                let cRel = "confidence/\(frameString).png"
                let depthURL = baseFolder.appendingPathComponent(dRel)
                let confURL = baseFolder.appendingPathComponent(cRel)

                try? FileManager.default.createDirectory(at: depthURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: confURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                // Save 16-bit uint16 depth PNG
                try? RawPNGWriter.writeDepthPNG(pixelBuffer: depth, to: depthURL)

                // Save 8-bit confidence PNG
                try? RawPNGWriter.writeConfidencePNG(pixelBuffer: conf, to: confURL)

                // Accumulate into colored point cloud
                pointCloudManager.addPoints(
                    depthBuffer: depth,
                    confidenceBuffer: conf,
                    imageBuffer: capturedImage,
                    intrinsics: intrinsics,
                    c2w: transform
                )

                depthRelPath = dRel
                confRelPath = cRel
            }

            let w = CVPixelBufferGetWidth(capturedImage)
            let h = CVPixelBufferGetHeight(capturedImage)

            let record = KeyframeRecord(
                index: currentIndex,
                timestamp: timestamp,
                transform: transform,
                intrinsics: intrinsics,
                imageWidth: w,
                imageHeight: h,
                imageRelativePath: imgRelPath,
                depthRelativePath: depthRelPath,
                confidenceRelativePath: confRelPath
            )

            self.keyframes.append(record)
            completion?(record)
        }
    }
}
