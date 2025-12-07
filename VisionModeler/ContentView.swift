import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let placeObjectRequested = Notification.Name("placeObjectRequested")
    static let removeObjectRequested = Notification.Name("removeObjectRequested")
}

struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @EnvironmentObject var settings: SettingsStore

    @Binding var showImmersive: Bool

    @State private var selectedMenu: MenuTopic? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    // Simple in-memory store of objects for now
    struct StoredObject: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var url: URL?
        var bookmark: Data? = nil
    }

    @State private var storedObjects: [StoredObject] = []
    @State private var pendingPlacement: StoredObject? = nil

    @State private var pickedDirectory: URL? = nil
    @State private var directoryObjects: [StoredObject] = []
    @State private var showingDirectoryImporter: Bool = false
    @State private var placedIDs: Set<UUID> = []

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarMenuView(selected: $selectedMenu)
                .navigationTitle("Menu")
                .toolbar {
                    if columnVisibility != .detailOnly {
                        ToolbarItem(placement: .topBarTrailing) {
                            if settings.useHighContrast {
                                Button(action: {
                                    withAnimation(.easeInOut) {
                                        selectedMenu = nil
                                        columnVisibility = .detailOnly
                                    }
                                }) {
                                    Text("Back").highContrastTextOutline(settings.useHighContrast)
                                }
                                .buttonStyle(HighContrastButtonStyle(enabled: true))
                            } else {
                                Button(action: {
                                    withAnimation(.easeInOut) {
                                        selectedMenu = nil
                                        columnVisibility = .detailOnly
                                    }
                                }) {
                                    Text("Back")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
        } detail: {
            VStack {
                switch selectedMenu {
                case .contrast:
                    ContrastSettingsView()
                case .help:
                    HelpView()
                case .placement:
                    PlacementSettingsView()
                case .library:
                    LibraryView(
                        objects: $directoryObjects,
                        pickDirectory: { showingDirectoryImporter = true },
                        place: { obj in
                            // Always route through immersive open to ensure observers are installed
                            pendingPlacement = obj
                            if !showImmersive { showImmersive = true }
                            Task {
                                // Ensure immersive space is open (idempotent)
                                await openImmersiveSpace(id: "placeSpace")
                                // Small delay to ensure PlaceModelView observers are installed
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                print("[ContentView] Posting placeObjectRequested (Library) for \(obj.name) (\(obj.id))")
                                NotificationCenter.default.post(
                                    name: .placeObjectRequested,
                                    object: nil,
                                    userInfo: [
                                        "id": obj.id.uuidString,
                                        "name": obj.name,
                                        "url": obj.url?.absoluteString ?? "",
                                        "bookmark": obj.bookmark as Any
                                    ]
                                )
                                pendingPlacement = nil
                            }
                        },
                        addToObjects: { obj in
                            if let url = obj.url {
                                let exists = storedObjects.contains { $0.url == url }
                                if !exists { storedObjects.append(obj) }
                            } else {
                                let exists = storedObjects.contains { $0.name == obj.name && $0.url == nil }
                                if !exists { storedObjects.append(obj) }
                            }
                        }
                    )
                case .objects:
                    ObjectsView(
                        storedObjects: $storedObjects,
                        showImmersive: $showImmersive,
                        pendingPlacement: $pendingPlacement,
                        placedIDs: $placedIDs
                    )
                case .none:
                    ObjectsView(
                        storedObjects: $storedObjects,
                        showImmersive: $showImmersive,
                        pendingPlacement: $pendingPlacement,
                        placedIDs: $placedIDs
                    )
                }
            }
            .toolbar {
                if columnVisibility == .detailOnly {
                    ToolbarItem(placement: .topBarLeading) {
                        if settings.useHighContrast {
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    columnVisibility = .all
                                }
                            }) {
                                Text("Menu").highContrastTextOutline(settings.useHighContrast)
                            }
                            .buttonStyle(HighContrastButtonStyle(enabled: true))
                        } else {
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    columnVisibility = .all
                                }
                            }) {
                                Text("Menu")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

            }
        }
        .fileImporter(isPresented: $showingDirectoryImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let dir = urls.first {
                    pickedDirectory = dir
                    importDirectory(dir)
                }
            case .failure(let error):
                print("[ContentView] Directory import failed: \(error)")
            }
        }
        .controlSize(settings.useHighContrast ? .large : .regular)
        //.buttonStyle(HighContrastButtonStyle(enabled: settings.useHighContrast))  // Removed as per instructions
        .onChange(of: showImmersive) { _, newValue in
            if newValue {
                Task {
                    await openImmersiveSpace(id: "placeSpace")
                    // After the immersive space is opened, send the placement request if any
                    if let obj = pendingPlacement {
                        // Small delay to ensure PlaceModelView observers are installed
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                        print("[ContentView] Posting placeObjectRequested for \(obj.name) (\(obj.id))")
                        NotificationCenter.default.post(
                            name: .placeObjectRequested,
                            object: nil,
                            userInfo: [
                                "id": obj.id.uuidString,
                                "name": obj.name,
                                "url": obj.url?.absoluteString ?? "",
                                "bookmark": obj.bookmark as Any
                            ]
                        )
                        pendingPlacement = nil
                    } else {
                        print("[ContentView] No pendingPlacement after opening immersive space")
                    }
                }
            }
        }
    }

    private func loadObjects(from directory: URL) {
        directoryObjects.removeAll()
        let fm = FileManager.default
        let startedAccess = directory.startAccessingSecurityScopedResource()
        if !startedAccess {
            print("[ContentView] Warning: Failed to start security-scoped access for directory: \(directory)")
        }
        defer {
            if startedAccess {
                directory.stopAccessingSecurityScopedResource()
                print("[ContentView] Stopped security-scoped access for directory: \(directory.lastPathComponent)")
            }
        }
        do {
            let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            let supportedExts: Set<String> = ["usdz", "reality"]
            for url in contents {
                if supportedExts.contains(url.pathExtension.lowercased()) {
#if os(visionOS)
                    let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
#else
                    let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
#endif
                    directoryObjects.append(StoredObject(name: url.lastPathComponent, url: url, bookmark: bookmark))
                }
            }
            if directoryObjects.isEmpty {
                print("[ContentView] No supported model files in directory: \(directory)")
            }
        } catch {
            print("[ContentView] Failed to list directory: \(error)")
        }
    }

    private func importDirectory(_ directory: URL) {
        directoryObjects.removeAll()

        let startedAccess = directory.startAccessingSecurityScopedResource()
        if !startedAccess {
            print("[ContentView] Warning: Failed to start security-scoped access for directory: \(directory)")
        }
        defer {
            if startedAccess {
                directory.stopAccessingSecurityScopedResource()
                print("[ContentView] Stopped security-scoped access for directory: \(directory.lastPathComponent)")
            }
        }

        let fm = FileManager.default
        let appFolder = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let supportedExts: Set<String> = ["usdz", "reality"]

        do {
            let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

            for url in contents {
                if supportedExts.contains(url.pathExtension.lowercased()) {
                    let dst = appFolder.appendingPathComponent(url.lastPathComponent)

                    if fm.fileExists(atPath: dst.path) {
                        try? fm.removeItem(at: dst)
                    }

                    let fileAccess = url.startAccessingSecurityScopedResource()
                    if !fileAccess {
                        print("[ContentView] Warning: Failed to start security-scoped access for file: \(url.lastPathComponent)")
                    }

                    do {
                        try fm.copyItem(at: url, to: dst)
                        directoryObjects.append(
                            StoredObject(name: url.lastPathComponent, url: dst)
                        )
                    } catch {
                        print("[ContentView] Failed copying \(url.lastPathComponent): \(error)")
                    }

                    if fileAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }

            if directoryObjects.isEmpty {
                print("[ContentView] No supported model files found in imported directory: \(directory)")
            }
        } catch {
            print("[ContentView] Failed to read picked directory: \(error)")
        }
    }
}


#Preview {
    ContentView(showImmersive: .constant(false))
        .environmentObject(SettingsStore())
}

