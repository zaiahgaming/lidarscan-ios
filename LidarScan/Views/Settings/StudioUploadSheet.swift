import SwiftUI

public struct StudioUploadSheet: View {
    public let capture: SavedCapture
    @Environment(\.presentationMode) var presentationMode

    @StateObject private var bonjourClient = BonjourClient()
    @StateObject private var uploadClient = StudioUploadClient()

    @State private var manualHost = ""
    @State private var manualPort = "8765"
    @State private var selectedHost = ""
    @State private var selectedPort = 8765
    @State private var uploadCompleted = false
    @State private var errorMessage: String?

    public init(capture: SavedCapture) {
        self.capture = capture
    }

    private var targetZipURL: URL? {
        if let zip = capture.zipURL, FileManager.default.fileExists(atPath: zip.path) {
            return zip
        }
        let fallback = capture.folderURL.deletingLastPathComponent().appendingPathComponent("\(capture.name).lidarscan.zip")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.09)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Capture Info Header
                        VStack(spacing: 6) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                            Text("Send to PC Studio")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            Text(capture.name)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Text(capture.formattedSize)
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                        .padding(.top, 10)

                        // Discovered Servers Section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("DISCOVERED STUDIOS (BONJOUR)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gray)
                                Spacer()
                                if bonjourClient.isBrowsing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            }
                            .padding(.horizontal, 4)

                            if bonjourClient.discoveredServers.isEmpty {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundColor(.gray)
                                    Text("Searching local network for _lidarscan._tcp...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            } else {
                                ForEach(bonjourClient.discoveredServers) { server in
                                    Button(action: {
                                        selectedHost = server.host
                                        selectedPort = server.port
                                        uploadClient.ping(host: server.host, port: server.port) { _, _ in }
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(server.name)
                                                    .font(.headline)
                                                    .foregroundColor(.white)
                                                Text("http://\(server.host):\(server.port)")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                            if selectedHost == server.host && selectedPort == server.port {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .padding()
                                        .background(Color.white.opacity(selectedHost == server.host ? 0.12 : 0.05))
                                        .cornerRadius(12)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Manual Entry Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MANUAL IP & PORT")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)

                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    TextField("e.g. 192.168.0.148", text: $manualHost)
                                        .font(.subheadline)
                                        .padding(10)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                        .keyboardType(.numbersAndPunctuation)
                                        .autocapitalization(.none)

                                    TextField("8765", text: $manualPort)
                                        .font(.subheadline)
                                        .padding(10)
                                        .frame(width: 80)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                        .keyboardType(.numberPad)
                                }

                                Button(action: {
                                    let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let port = Int(manualPort) ?? 8765
                                    guard !host.isEmpty else { return }
                                    selectedHost = host
                                    selectedPort = port
                                    uploadClient.ping(host: host, port: port) { _, _ in }
                                }) {
                                    HStack {
                                        Image(systemName: "network")
                                        Text("Ping Studio Server")
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(Color.gray.opacity(0.3))
                                    .cornerRadius(8)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)

                            // Ping Status Pill
                            if let pingSuccess = uploadClient.lastPingSuccess {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(pingSuccess ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    Text(uploadClient.lastPingMessage)
                                        .font(.caption)
                                        .foregroundColor(pingSuccess ? .green : .red)
                                    Spacer()
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal)

                        // Upload Status & Progress Bar
                        if uploadClient.isUploading || uploadCompleted {
                            VStack(spacing: 10) {
                                ProgressView(value: uploadClient.uploadProgress)
                                    .accentColor(.blue)

                                Text(uploadClient.uploadStatus)
                                    .font(.subheadline)
                                    .foregroundColor(.white)

                                if uploadCompleted {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Transfer successful!")
                                            .font(.headline)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // Upload Button
                        Button(action: startUpload) {
                            HStack {
                                if uploadClient.isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                }
                                Text(uploadClient.isUploading ? "Uploading..." : "Upload to PC Studio")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(canUpload ? Color.blue : Color.gray.opacity(0.3))
                            .cornerRadius(14)
                        }
                        .disabled(!canUpload || uploadClient.isUploading)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitle("PC Transfer", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            }.foregroundColor(.white))
            .onAppear {
                bonjourClient.startBrowsing()
            }
            .onDisappear {
                bonjourClient.stopBrowsing()
            }
        }
    }

    private var canUpload: Bool {
        !selectedHost.isEmpty && targetZipURL != nil
    }

    private func startUpload() {
        guard let zipURL = targetZipURL else {
            uploadClient.uploadStatus = "Error: .lidarscan.zip not found"
            return
        }

        uploadCompleted = false
        uploadClient.upload(
            zipURL: zipURL,
            captureName: capture.name,
            host: selectedHost,
            port: selectedPort
        ) { result in
            switch result {
            case .success:
                uploadCompleted = true
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
