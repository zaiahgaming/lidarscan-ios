import Foundation

public enum ZipWriter {

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

    private static func crc32(for fileURL: URL) throws -> (crc: UInt32, size: UInt32) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var c: UInt32 = 0xFFFFFFFF
        var totalSize: UInt32 = 0
        let chunkSize = 64 * 1024

        while true {
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            totalSize += UInt32(data.count)
            for byte in data {
                let index = Int((c ^ UInt32(byte)) & 0xFF)
                c = crcTable[index] ^ (c >> 8)
            }
        }
        return (c ^ 0xFFFFFFFF, totalSize)
    }

    private struct ZipEntry {
        let relativePath: String
        let sourceURL: URL
        let crc32: UInt32
        let size: UInt32
        var localHeaderOffset: UInt32 = 0
    }

    /// Zips a folder recursively into destinationZipURL.
    /// The root directory inside the zip will be rootFolderName (e.g. "Scan_01/metadata.json")
    public static func zip(
        folderURL: URL,
        rootFolderName: String,
        destinationZipURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        let fileManager = FileManager.default

        // Collect all regular files recursively
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "ZipWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to enumerate directory"])
        }

        var entries: [ZipEntry] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true {
                let subPath = fileURL.path.replacingOccurrences(of: folderURL.path, with: "")
                let cleanSubPath = subPath.hasPrefix("/") ? String(subPath.dropFirst()) : subPath
                let archivePath = "\(rootFolderName)/\(cleanSubPath)"

                let (crc, size) = try crc32(for: fileURL)
                entries.append(ZipEntry(
                    relativePath: archivePath,
                    sourceURL: fileURL,
                    crc32: crc,
                    size: size
                ))
            }
        }

        guard entries.count <= Int(UInt16.max) else {
            throw NSError(domain: "ZipWriter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Capture contains too many files for a standard ZIP archive."])
        }
        let totalBytes = entries.reduce(UInt64(0)) { $0 + UInt64($1.size) }
        guard totalBytes <= UInt64(UInt32.max) else {
            throw NSError(domain: "ZipWriter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Capture is larger than the supported 4 GB ZIP format limit."])
        }

        if fileManager.fileExists(atPath: destinationZipURL.path) {
            try fileManager.removeItem(at: destinationZipURL)
        }
        fileManager.createFile(atPath: destinationZipURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: destinationZipURL)
        defer { try? outHandle.close() }

        var currentOffset: UInt32 = 0
        var bytesWritten: UInt64 = 0
        var lastReportedProgress = 0.0

        // 1. Write Local File Headers + Data
        for i in 0..<entries.count {
            entries[i].localHeaderOffset = currentOffset
            let entry = entries[i]
            let pathBytes = Array(entry.relativePath.utf8)

            var localHeader = Data()
            var sig = UInt32(0x04034b50).littleEndian
            var version = UInt16(20).littleEndian
            var flags = UInt16(0x0800).littleEndian // UTF-8 filename flag
            var method = UInt16(0).littleEndian    // STORE (0)
            var modTime = UInt16(0).littleEndian
            var modDate = UInt16(0).littleEndian
            var crc = entry.crc32.littleEndian
            var cSize = entry.size.littleEndian
            var uSize = entry.size.littleEndian
            var nameLen = UInt16(pathBytes.count).littleEndian
            var extraLen = UInt16(0).littleEndian

            localHeader.append(Data(bytes: &sig, count: 4))
            localHeader.append(Data(bytes: &version, count: 2))
            localHeader.append(Data(bytes: &flags, count: 2))
            localHeader.append(Data(bytes: &method, count: 2))
            localHeader.append(Data(bytes: &modTime, count: 2))
            localHeader.append(Data(bytes: &modDate, count: 2))
            localHeader.append(Data(bytes: &crc, count: 4))
            localHeader.append(Data(bytes: &cSize, count: 4))
            localHeader.append(Data(bytes: &uSize, count: 4))
            localHeader.append(Data(bytes: &nameLen, count: 2))
            localHeader.append(Data(bytes: &extraLen, count: 2))
            localHeader.append(contentsOf: pathBytes)

            outHandle.write(localHeader)
            currentOffset += UInt32(localHeader.count)

            // Stream file contents
            let inHandle = try FileHandle(forReadingFrom: entry.sourceURL)
            while true {
                let chunk = inHandle.readData(ofLength: 64 * 1024)
                if chunk.isEmpty { break }
                outHandle.write(chunk)
                currentOffset += UInt32(chunk.count)
                bytesWritten += UInt64(chunk.count)
                if totalBytes > 0 {
                    let fraction = Double(bytesWritten) / Double(totalBytes)
                    if fraction >= lastReportedProgress + 0.01 || fraction >= 1.0 {
                        lastReportedProgress = fraction
                        progressHandler?(fraction)
                    }
                }
            }
            try? inHandle.close()
        }

        let centralDirectoryOffset = currentOffset
        var centralDirectoryData = Data()

        // 2. Write Central Directory Headers
        for entry in entries {
            let pathBytes = Array(entry.relativePath.utf8)

            var sig = UInt32(0x02014b50).littleEndian
            var verMade = UInt16(20).littleEndian
            var verNeed = UInt16(20).littleEndian
            var flags = UInt16(0x0800).littleEndian
            var method = UInt16(0).littleEndian
            var modTime = UInt16(0).littleEndian
            var modDate = UInt16(0).littleEndian
            var crc = entry.crc32.littleEndian
            var cSize = entry.size.littleEndian
            var uSize = entry.size.littleEndian
            var nameLen = UInt16(pathBytes.count).littleEndian
            var extraLen = UInt16(0).littleEndian
            var commentLen = UInt16(0).littleEndian
            var diskStart = UInt16(0).littleEndian
            var intAttr = UInt16(0).littleEndian
            var extAttr = UInt32(0).littleEndian
            var relOffset = entry.localHeaderOffset.littleEndian

            centralDirectoryData.append(Data(bytes: &sig, count: 4))
            centralDirectoryData.append(Data(bytes: &verMade, count: 2))
            centralDirectoryData.append(Data(bytes: &verNeed, count: 2))
            centralDirectoryData.append(Data(bytes: &flags, count: 2))
            centralDirectoryData.append(Data(bytes: &method, count: 2))
            centralDirectoryData.append(Data(bytes: &modTime, count: 2))
            centralDirectoryData.append(Data(bytes: &modDate, count: 2))
            centralDirectoryData.append(Data(bytes: &crc, count: 4))
            centralDirectoryData.append(Data(bytes: &cSize, count: 4))
            centralDirectoryData.append(Data(bytes: &uSize, count: 4))
            centralDirectoryData.append(Data(bytes: &nameLen, count: 2))
            centralDirectoryData.append(Data(bytes: &extraLen, count: 2))
            centralDirectoryData.append(Data(bytes: &commentLen, count: 2))
            centralDirectoryData.append(Data(bytes: &diskStart, count: 2))
            centralDirectoryData.append(Data(bytes: &intAttr, count: 2))
            centralDirectoryData.append(Data(bytes: &extAttr, count: 4))
            centralDirectoryData.append(Data(bytes: &relOffset, count: 4))
            centralDirectoryData.append(contentsOf: pathBytes)
        }

        outHandle.write(centralDirectoryData)
        let centralDirectorySize = UInt32(centralDirectoryData.count)

        // 3. Write End of Central Directory Record (EOCD)
        var eocd = Data()
        var eocdSig = UInt32(0x06054b50).littleEndian
        var diskNum = UInt16(0).littleEndian
        var cdDisk = UInt16(0).littleEndian
        var numEntriesDisk = UInt16(entries.count).littleEndian
        var totalEntries = UInt16(entries.count).littleEndian
        var cdSize = centralDirectorySize.littleEndian
        var cdOffset = centralDirectoryOffset.littleEndian
        var commentLen = UInt16(0).littleEndian

        eocd.append(Data(bytes: &eocdSig, count: 4))
        eocd.append(Data(bytes: &diskNum, count: 2))
        eocd.append(Data(bytes: &cdDisk, count: 2))
        eocd.append(Data(bytes: &numEntriesDisk, count: 2))
        eocd.append(Data(bytes: &totalEntries, count: 2))
        eocd.append(Data(bytes: &cdSize, count: 4))
        eocd.append(Data(bytes: &cdOffset, count: 4))
        eocd.append(Data(bytes: &commentLen, count: 2))

        outHandle.write(eocd)
    }
}
