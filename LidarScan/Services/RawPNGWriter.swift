import Foundation
import CoreVideo
import Compression

public enum RawPNGWriter {

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((c ^ UInt32(byte)) & 0xFF)
            c = crcTable[index] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }

    private static func makeChunk(type: String, data: Data) -> Data {
        var chunk = Data()
        var length = UInt32(data.count).bigEndian
        chunk.append(Data(bytes: &length, count: 4))

        let typeData = type.data(using: .ascii)!
        chunk.append(typeData)
        chunk.append(data)

        var typeAndData = Data()
        typeAndData.append(typeData)
        typeAndData.append(data)
        var crc = crc32(typeAndData).bigEndian
        chunk.append(Data(bytes: &crc, count: 4))

        return chunk
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    private static func compressZlib(_ sourceData: Data) -> Data? {
        let destCapacity = max(sourceData.count + 1024, 65536)
        var destData = Data(count: destCapacity)

        let compressedSize = sourceData.withUnsafeBytes { srcPtr -> Int in
            destData.withUnsafeMutableBytes { dstPtr -> Int in
                guard let dstBase = dstPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let srcBase = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_encode_buffer(
                    dstBase,
                    destCapacity,
                    srcBase,
                    sourceData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard compressedSize > 0 else { return nil }
        destData.count = compressedSize

        // Apple's COMPRESSION_ZLIB produces raw DEFLATE (RFC 1951) — despite the
        // name it omits the zlib (RFC 1950) 2-byte header and Adler-32 trailer.
        // PNG IDAT streams must be real zlib, so wrap the deflate output here.
        var wrapped = Data([0x78, 0x01]) // CMF: 32K window, FLG: fastest
        wrapped.append(destData)
        var checksum = adler32(sourceData).bigEndian
        wrapped.append(Data(bytes: &checksum, count: 4))
        return wrapped
    }

    /// Writes 16-bit uint16 depth PNG in millimeters (LiDAR resolution 256x192, 0 = invalid)
    public static func writeDepthPNG(pixelBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "RawPNGWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to access pixel buffer memory"])
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Raw scanlines: for each row, 1 filter byte (0) + width * 2 bytes
        var rawScanlines = Data(capacity: height * (1 + width * 2))

        for y in 0..<height {
            rawScanlines.append(0) // Filter byte: None
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let depthMeters = rowPtr[x]
                let val_mm: UInt16
                if depthMeters.isNaN || depthMeters.isInfinite || depthMeters <= 0.0 {
                    val_mm = 0
                } else {
                    let mm = Double(depthMeters) * 1000.0
                    val_mm = UInt16(clamping: Int(mm.rounded()))
                }
                var be = val_mm.bigEndian
                withUnsafeBytes(of: &be) { rawScanlines.append(contentsOf: $0) }
            }
        }

        guard let idatData = compressZlib(rawScanlines) else {
            throw NSError(domain: "RawPNGWriter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to compress PNG IDAT chunk"])
        }

        var pngData = Data(pngSignature)

        // IHDR
        var ihdr = Data()
        var w = UInt32(width).bigEndian
        var h = UInt32(height).bigEndian
        ihdr.append(Data(bytes: &w, count: 4))
        ihdr.append(Data(bytes: &h, count: 4))
        ihdr.append(16) // bit depth: 16-bit
        ihdr.append(0)  // color type: Grayscale
        ihdr.append(0)  // compression: Deflate
        ihdr.append(0)  // filter: standard
        ihdr.append(0)  // interlace: none
        pngData.append(makeChunk(type: "IHDR", data: ihdr))

        // IDAT
        pngData.append(makeChunk(type: "IDAT", data: idatData))

        // IEND
        pngData.append(makeChunk(type: "IEND", data: Data()))

        try pngData.write(to: url, options: .atomic)
    }

    /// Writes 8-bit confidence PNG (values 0/1/2)
    public static func writeConfidencePNG(pixelBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "RawPNGWriter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to access pixel buffer memory"])
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var rawScanlines = Data(capacity: height * (1 + width))

        for y in 0..<height {
            rawScanlines.append(0) // Filter byte: None
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                rawScanlines.append(rowPtr[x])
            }
        }

        guard let idatData = compressZlib(rawScanlines) else {
            throw NSError(domain: "RawPNGWriter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to compress confidence IDAT chunk"])
        }

        var pngData = Data(pngSignature)

        // IHDR
        var ihdr = Data()
        var w = UInt32(width).bigEndian
        var h = UInt32(height).bigEndian
        ihdr.append(Data(bytes: &w, count: 4))
        ihdr.append(Data(bytes: &h, count: 4))
        ihdr.append(8) // bit depth: 8-bit
        ihdr.append(0) // color type: Grayscale
        ihdr.append(0) // compression: Deflate
        ihdr.append(0) // filter: standard
        ihdr.append(0) // interlace: none
        pngData.append(makeChunk(type: "IHDR", data: ihdr))

        // IDAT
        pngData.append(makeChunk(type: "IDAT", data: idatData))

        // IEND
        pngData.append(makeChunk(type: "IEND", data: Data()))

        try pngData.write(to: url, options: .atomic)
    }
}
