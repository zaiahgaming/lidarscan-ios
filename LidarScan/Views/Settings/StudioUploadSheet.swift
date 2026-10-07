import SwiftUI

/// Send a capture ZIP to a PC running LidarScan Studio.
/// Uses a native grouped form; the last successful server is remembered.
public struct StudioUploadSheet: View {
    public let capture: SavedCapture
    @Environment(\.dismiss) private var dismiss

    @StateObject private var bonjourClient = BonjourClient()
    @StateObject private var uploadClient = StudioUploadClient()

    @AppStorage("lastStudioHost") private var lastStudioHost = ""
    @AppStorage("lastStudioPort") private var lastStudioPort = 8765

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
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: "desktopcomputer")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                        Text("Send to PC Studio")
                            .font(.title3.bold())
                        Text(capture.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(capture.formattedSize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                discoveredSection

                manualSection

                if uploadClient.isUploading || uploadCompleted {
                    statusSection
                }

                Section {
                    Button(action: startUpload) {
                        HStack {
                            if uploadClient.isUploading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                            }
                            Text(uploadClient.isUploading ? "Uploading…" : "Upload to PC Studio")
                        }
                        .frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .disabled(!canUpload || uploadClient.isUploading)
                }
            }
            .navigationTitle("PC Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Upload Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                bonjourClient.startBrowsing()
            }
            .onDisappear {
                bonjourClient.stopBrowsing()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var discoveredSection: some View {
        Section {
            if bonjourClient.discoveredServers.isEmpty {
                Label {
                    Text(bonjourClient.browseError ?? "Searching the local network for Studio servers…")
                        .font(.footnote)
                } icon: {
                    if bonjourClient.browseError == nil {
                        ProgressView()
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(bonjourClient.browseError == nil ? Color.secondary : Color.orange)
            } else {
                ForEach(bonjourClient.discoveredServers) { server in
                    Button {
                        selectAndPingServer(server)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(verbatim: "\(selectedHost.isEmpty ? server.host : selectedHost):\(server.port)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)

                                if server.candidateIPs.count > 1 {
                                    ipChips(for: server)
                                }
                            }
                            Spacer()
                            if selectedHost == server.host || server.candidateIPs.contains(selectedHost) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Discovered Studios")
        }
    }

    private func ipChips(for server: DiscoveredStudio) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(server.candidateIPs, id: \.self) { ip in
                    Button {
                        selectedHost = ip
                        selectedPort = server.port
                        uploadClient.ping(host: ip, port: server.port) { _, _ in }
                    } label: {
                        Text(ip)
                            .font(.caption2.monospacedDigit().weight(selectedHost == ip ? .bold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                selectedHost == ip ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedHost == ip ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var manualSection: some View {
        Section {
            HStack(spacing: 10) {
                TextField("e.g. 192.168.0.212", text: $manualHost)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Port", text: $manualPort)
                    .keyboardType(.numberPad)
                    .frame(width: 84)
            }

            if !lastStudioHost.isEmpty {
                Button {
                    manualHost = lastStudioHost
                    manualPort = String(lastStudioPort)
                    selectedHost = lastStudioHost
                    selectedPort = lastStudioPort
                    uploadClient.ping(host: lastStudioHost, port: lastStudioPort) { _, _ in }
                } label: {
                    Label {
                        Text(verbatim: "Last used: \(lastStudioHost):\(lastStudioPort)")
                            .font(.footnote.monospacedDigit())
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }

            Button {
                let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
                let port = Int(manualPort) ?? 8765
                guard !host.isEmpty else { return }
                selectedHost = host
                selectedPort = port
                uploadClient.ping(host: host, port: port) { _, _ in }
            } label: {
                Label("Ping Studio Server", systemImage: "network")
            }
            .disabled(manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let pingSuccess = uploadClient.lastPingSuccess {
                Label {
                    Text(uploadClient.lastPingMessage)
                        .font(.footnote)
                } icon: {
                    Circle()
                        .fill(pingSuccess ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
                .foregroundStyle(pingSuccess ? Color.green : Color.red)
            }
        } header: {
            Text("Manual Address")
        }
    }

    private var statusSection: some View {
        Section("Transfer") {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: uploadClient.uploadProgress)
                    .tint(uploadCompleted ? Color.green : Color.accentColor)

                Text(uploadClient.uploadStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if uploadCompleted {
                    Label("Transfer successful!", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private var canUpload: Bool {
        !selectedHost.isEmpty && (targetZipURL != nil || FileManager.default.fileExists(atPath: capture.folderURL.path))
    }

    private func selectAndPingServer(_ server: DiscoveredStudio) {
        let hostsToTry = !server.candidateIPs.isEmpty ? server.candidateIPs : [server.host]
        tryPingHosts(hostsToTry, port: server.port, index: 0)
    }

    private func tryPingHosts(_ hosts: [String], port: Int, index: Int) {
        guard index < hosts.count else { return }
        let host = hosts[index]
        self.selectedHost = host
        self.selectedPort = port
        uploadClient.ping(host: host, port: port) { success, _ in
            if !success && index + 1 < hosts.count {
                self.tryPingHosts(hosts, port: port, index: index + 1)
            }
        }
    }

    private func startUpload() {
        uploadCompleted = false
        var zipURL = targetZipURL
        if zipURL == nil {
            let parentDir = capture.folderURL.deletingLastPathComponent()
            let generatedZip = parentDir.appendingPathComponent("\(capture.name).lidarscan.zip")
            uploadClient.uploadStatus = "Compressing scan for upload…"
            do {
                try ZipWriter.zip(folderURL: capture.folderURL, rootFolderName: capture.name, destinationZipURL: generatedZip)
                zipURL = generatedZip
            } catch {
                uploadClient.uploadStatus = "Error compressing capture: \(error.localizedDescription)"
                return
            }
        }

        guard let finalZip = zipURL else {
            uploadClient.uploadStatus = "Error: .lidarscan.zip not found"
            return
        }

        uploadClient.upload(
            zipURL: finalZip,
            captureName: capture.name,
            host: selectedHost,
            port: selectedPort
        ) { result in
            switch result {
            case .success:
                lastStudioHost = selectedHost
                lastStudioPort = selectedPort
                uploadCompleted = true
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
