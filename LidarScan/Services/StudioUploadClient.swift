import Foundation

public final class StudioUploadClient: NSObject, ObservableObject, URLSessionTaskDelegate {
    @Published public var isUploading: Bool = false
    @Published public var uploadProgress: Double = 0.0
    @Published public var uploadStatus: String = ""
    @Published public var lastPingSuccess: Bool?
    @Published public var lastPingMessage: String = ""

    private var activeCompletion: ((Result<String, Error>) -> Void)?
    private var tempUploadFileURL: URL?

    public override init() {
        super.init()
    }

    public func ping(host: String, port: Int, completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: "http://\(host):\(port)/api/ping") else {
            completion(false, "Invalid host URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastPingSuccess = false
                    self?.lastPingMessage = error.localizedDescription
                    completion(false, error.localizedDescription)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let name = json["name"] as? String else {
                    self?.lastPingSuccess = false
                    self?.lastPingMessage = "Invalid response from server"
                    completion(false, "Invalid server response")
                    return
                }

                self?.lastPingSuccess = true
                self?.lastPingMessage = "Connected to \(name)"
                completion(true, "Connected to \(name)")
            }
        }.resume()
    }

    public func upload(
        zipURL: URL,
        captureName: String,
        host: String,
        port: Int,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let uploadURL = URL(string: "http://\(host):\(port)/api/upload") else {
            completion(.failure(NSError(domain: "StudioUploadClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        isUploading = true
        uploadProgress = 0.0
        uploadStatus = "Preparing upload..."
        self.activeCompletion = completion

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let boundary = "Boundary-\(UUID().uuidString)"
            let tempDir = FileManager.default.temporaryDirectory
            let tempBodyURL = tempDir.appendingPathComponent("upload_\(UUID().uuidString).tmp")
            self.tempUploadFileURL = tempBodyURL

            FileManager.default.createFile(atPath: tempBodyURL.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: tempBodyURL) else {
                DispatchQueue.main.async {
                    self.isUploading = false
                    completion(.failure(NSError(domain: "StudioUploadClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create temp multipart body"])))
                }
                return
            }

            // 1. Part "name"
            var nameHeader = "--\(boundary)\r\n"
            nameHeader += "Content-Disposition: form-data; name=\"name\"\r\n\r\n"
            nameHeader += "\(captureName)\r\n"
            if let d = nameHeader.data(using: .utf8) { handle.write(d) }

            // 2. Part "file"
            var fileHeader = "--\(boundary)\r\n"
            fileHeader += "Content-Disposition: form-data; name=\"file\"; filename=\"\(zipURL.lastPathComponent)\"\r\n"
            fileHeader += "Content-Type: application/zip\r\n\r\n"
            if let d = fileHeader.data(using: .utf8) { handle.write(d) }

            // Stream zip file into body
            if let zipHandle = try? FileHandle(forReadingFrom: zipURL) {
                while true {
                    let chunk = zipHandle.readData(ofLength: 64 * 1024)
                    if chunk.isEmpty { break }
                    handle.write(chunk)
                }
                try? zipHandle.close()
            }

            // Closing boundary
            let footer = "\r\n--\(boundary)--\r\n"
            if let d = footer.data(using: .utf8) { handle.write(d) }
            try? handle.close()

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120.0

            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            let task = session.uploadTask(with: request, fromFile: tempBodyURL)
            task.resume()
        }
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = totalBytesExpectedToSend > 0 ? Double(totalBytesSent) / Double(totalBytesExpectedToSend) : 0.0
        let sentMB = Double(totalBytesSent) / 1_048_576.0
        let totalMB = Double(totalBytesExpectedToSend) / 1_048_576.0

        DispatchQueue.main.async {
            self.uploadProgress = progress
            self.uploadStatus = String(format: "Uploading: %.1f MB / %.1f MB (%.0f%%)", sentMB, totalMB, progress * 100)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let temp = tempUploadFileURL {
            try? FileManager.default.removeItem(at: temp)
            tempUploadFileURL = nil
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isUploading = false

            if let error = error {
                self.uploadStatus = "Upload failed: \(error.localizedDescription)"
                self.activeCompletion?(.failure(error))
                self.activeCompletion = nil
                return
            }

            if let response = task.response as? HTTPURLResponse, response.statusCode == 200 {
                self.uploadProgress = 1.0
                self.uploadStatus = "Upload complete!"
                self.activeCompletion?(.success("Successfully uploaded"))
            } else {
                let err = NSError(domain: "StudioUploadClient", code: 3, userInfo: [NSLocalizedDescriptionKey: "Server returned error"])
                self.uploadStatus = "Upload failed (server error)"
                self.activeCompletion?(.failure(err))
            }
            self.activeCompletion = nil
        }
    }
}
