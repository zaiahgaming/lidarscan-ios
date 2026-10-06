import SwiftUI

public struct LibraryView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var captures: [SavedCapture] = []
    @State private var selectedCapture: SavedCapture?
    @State private var captureToShare: SavedCapture?
    @State private var captureToUpload: SavedCapture?
    @State private var captureToRename: SavedCapture?
    @State private var renameText = ""
    @State private var showingRenameAlert = false

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.09)
                    .ignoresSafeArea()

                if captures.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No Scans Yet")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Text("Completed scans will appear here and in the Files app.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        ForEach(captures) { capture in
                            CaptureRowView(capture: capture)
                                .listRowBackground(Color.white.opacity(0.04))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCapture = capture
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteCapture(capture)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        captureToRename = capture
                                        renameText = capture.name
                                        showingRenameAlert = true
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        captureToUpload = capture
                                    } label: {
                                        Label("PC Studio", systemImage: "desktopcomputer")
                                    }
                                    .tint(.blue)

                                    Button {
                                        captureToShare = capture
                                    } label: {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.green)
                                }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .refreshable {
                        loadCaptures()
                    }
                }
            }
            .navigationBarTitle("Scans Library", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }.foregroundColor(.white),
                trailing: Button(action: loadCaptures) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.white)
                }
            )
            .onAppear(perform: loadCaptures)
            .sheet(item: $selectedCapture) { capture in
                CaptureDetailView(capture: capture)
            }
            .sheet(item: $captureToUpload) { capture in
                StudioUploadSheet(capture: capture)
            }
            .sheet(item: $captureToShare) { capture in
                if let zip = capture.zipURL, FileManager.default.fileExists(atPath: zip.path) {
                    ShareSheet(activityItems: [zip])
                }
            }
            .alert("Rename Capture", isPresented: $showingRenameAlert) {
                TextField("Capture Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let c = captureToRename {
                        renameCapture(c, newName: renameText)
                    }
                }
            }
        }
    }

    private func loadCaptures() {
        let fileManager = FileManager.default
        let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let capturesDir = docDir.appendingPathComponent("Captures")

        guard let contents = try? fileManager.contentsOfDirectory(at: capturesDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            captures = []
            return
        }

        var loaded: [SavedCapture] = []
        for url in contents {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let name = url.lastPathComponent
                let zipURL = capturesDir.appendingPathComponent("\(name).lidarscan.zip")
                let hasZip = fileManager.fileExists(atPath: zipURL.path)

                let metaURL = url.appendingPathComponent("metadata.json")
                var frameCount = 0
                var hasMesh = false
                if let metaData = try? Data(contentsOf: metaURL),
                   let meta = try? JSONDecoder().decode(CaptureMetadata.self, from: metaData) {
                    frameCount = meta.frame_count
                    hasMesh = meta.has_mesh
                }

                let pointCount = (try? fileManager.contentsOfDirectory(at: url.appendingPathComponent("images"), includingPropertiesForKeys: nil).count) ?? 0

                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                let size = hasZip ? ((try? zipURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) : 0

                loaded.append(SavedCapture(
                    name: name,
                    folderURL: url,
                    zipURL: hasZip ? zipURL : nil,
                    createdDate: date,
                    frameCount: frameCount > 0 ? frameCount : pointCount,
                    pointCount: pointCount * 2500, // estimated if not read
                    hasMesh: hasMesh,
                    fileSize: Int64(size)
                ))
            }
        }

        self.captures = loaded.sorted { $0.createdDate > $1.createdDate }
    }

    private func deleteCapture(_ capture: SavedCapture) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: capture.folderURL)
        if let zip = capture.zipURL {
            try? fileManager.removeItem(at: zip)
        }
        loadCaptures()
    }

    private func renameCapture(_ capture: SavedCapture, newName: String) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName != capture.name else { return }

        let fileManager = FileManager.default
        let newFolder = capture.folderURL.deletingLastPathComponent().appendingPathComponent(cleanName)
        let newZip = capture.folderURL.deletingLastPathComponent().appendingPathComponent("\(cleanName).lidarscan.zip")

        try? fileManager.moveItem(at: capture.folderURL, to: newFolder)
        if let zip = capture.zipURL, fileManager.fileExists(atPath: zip.path) {
            try? fileManager.moveItem(at: zip, to: newZip)
        }
        loadCaptures()
    }
}
