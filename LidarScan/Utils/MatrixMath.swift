import Foundation
import simd

public enum MatrixMath {
    public static func toRowMajorArray(_ m: simd_float4x4) -> [[Double]] {
        return [
            [Double(m.columns.0.x), Double(m.columns.1.x), Double(m.columns.2.x), Double(m.columns.3.x)],
            [Double(m.columns.0.y), Double(m.columns.1.y), Double(m.columns.2.y), Double(m.columns.3.y)],
            [Double(m.columns.0.z), Double(m.columns.1.z), Double(m.columns.2.z), Double(m.columns.3.z)],
            [Double(m.columns.0.w), Double(m.columns.1.w), Double(m.columns.2.w), Double(m.columns.3.w)]
        ]
    }

    public static func colmapPose(from c2w_gl: simd_float4x4) -> (qw: Float, qx: Float, qy: Float, qz: Float, tx: Float, ty: Float, tz: Float) {
        var c2w_cv = c2w_gl
        c2w_cv.columns.1 = -c2w_gl.columns.1
        c2w_cv.columns.2 = -c2w_gl.columns.2

        let w2c = simd_inverse(c2w_cv)

        let tx = w2c.columns.3.x
        let ty = w2c.columns.3.y
        let tz = w2c.columns.3.z

        let r00 = w2c.columns.0.x
        let r01 = w2c.columns.1.x
        let r02 = w2c.columns.2.x
        let r10 = w2c.columns.0.y
        let r11 = w2c.columns.1.y
        let r12 = w2c.columns.2.y
        let r20 = w2c.columns.0.z
        let r21 = w2c.columns.1.z
        let r22 = w2c.columns.2.z

        let trace = r00 + r11 + r22
        var qw: Float = 1.0
        var qx: Float = 0.0
        var qy: Float = 0.0
        var qz: Float = 0.0

        if trace > 0.0 {
            let s = 0.5 / sqrt(trace + 1.0)
            qw = 0.25 / s
            qx = (r21 - r12) * s
            qy = (r02 - r20) * s
            qz = (r10 - r01) * s
        } else if (r00 > r11) && (r00 > r22) {
            let s = 2.0 * sqrt(1.0 + r00 - r11 - r22)
            qw = (r21 - r12) / s
            qx = 0.25 * s
            qy = (r01 + r10) / s
            qz = (r02 + r20) / s
        } else if r11 > r22 {
            let s = 2.0 * sqrt(1.0 + r11 - r00 - r22)
            qw = (r02 - r20) / s
            qx = (r01 + r10) / s
            qy = 0.25 * s
            qz = (r12 + r21) / s
        } else {
            let s = 2.0 * sqrt(1.0 + r22 - r00 - r11)
            qw = (r10 - r01) / s
            qx = (r02 + r20) / s
            qy = (r12 + r21) / s
            qz = 0.25 * s
        }

        let norm = sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
        if norm > 1e-6 {
            qw /= norm
            qx /= norm
            qy /= norm
            qz /= norm
        }

        return (qw, qx, qy, qz, tx, ty, tz)
    }

    public static func translationDistance(_ t1: simd_float4x4, _ t2: simd_float4x4) -> Float {
        let p1 = simd_float3(t1.columns.3.x, t1.columns.3.y, t1.columns.3.z)
        let p2 = simd_float3(t2.columns.3.x, t2.columns.3.y, t2.columns.3.z)
        return simd_distance(p1, p2)
    }

    public static func rotationAngleDegrees(_ t1: simd_float4x4, _ t2: simd_float4x4) -> Float {
        let r1_c0 = simd_float3(t1.columns.0.x, t1.columns.0.y, t1.columns.0.z)
        let r1_c1 = simd_float3(t1.columns.1.x, t1.columns.1.y, t1.columns.1.z)
        let r1_c2 = simd_float3(t1.columns.2.x, t1.columns.2.y, t1.columns.2.z)

        let r2_c0 = simd_float3(t2.columns.0.x, t2.columns.0.y, t2.columns.0.z)
        let r2_c1 = simd_float3(t2.columns.1.x, t2.columns.1.y, t2.columns.1.z)
        let r2_c2 = simd_float3(t2.columns.2.x, t2.columns.2.y, t2.columns.2.z)

        let trace = simd_dot(r1_c0, r2_c0) + simd_dot(r1_c1, r2_c1) + simd_dot(r1_c2, r2_c2)
        let cosAngle = max(-1.0, min(1.0, (trace - 1.0) / 2.0))
        return acos(cosAngle) * 180.0 / .pi
    }
}
