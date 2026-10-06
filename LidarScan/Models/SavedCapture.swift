import Foundation

public struct SavedCapture: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public let folderURL: URL
    public var zipURL: URL?
    public let createdDate: Date
    public var frameCount: Int
    public var pointCount: Int
    public var hasMesh: Bool
    public var fileSize: Int64

    public init(
        id: UUID = UUID(),
        name: String,
        folderURL: URL,
        zipURL: URL? = nil,
        createdDate: Date = Date(),
        frameCount: Int = 0,
        pointCount: Int = 0,
        hasMesh: Bool = false,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.folderURL = folderURL
        self.zipURL = zipURL
        self.createdDate = createdDate
        self.frameCount = frameCount
        self.pointCount = pointCount
        self.hasMesh = hasMesh
        self.fileSize = fileSize
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: createdDate)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
