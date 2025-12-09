import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let placeObjectRequested = Notification.Name("placeObjectRequested")
    static let removeObjectRequested = Notification.Name("removeObjectRequested")
    static let scanSurfacesToggled = Notification.Name("scanSurfacesToggled")
}

struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @EnvironmentObject var settings: SettingsStore

    @Binding var showImmersive: Bool

    @State private var selectedMenu: MenuTopic? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    // Simple in-memory store of objects for now
    struct StoredObject: Identifiable, Hashable, Codable {
        let id: UUID
        var name: String
        var url: URL?
        var bookmark: Data? = nil
        
        // Add explicit init to allow default UUID
        init(id: UUID = UUID(), name: String, url: URL?, bookmark: Data? = nil) {
            self.id = id
            self.name = name
            self.url = url
            self.bookmark = bookmark
        }
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
                    pickDirectory(dir)
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
        .task {
            storedObjects = []
            // Load state on startup
            loadLibrary()
            loadPersistedObjects()
            storedObjects = directoryObjects
        }
        .onChange(of: storedObjects) { _, newValue in
            saveObjects(newValue)
        }
    }
    
    // MARK: - Persistence
    
    private func pickDirectory(_ url: URL) {
        pickedDirectory = url
        saveLibrary(url)
        importDirectory(url)
    }
    
    private func saveLibrary(_ url: URL) {
        // Create a security-scoped bookmark
        do {
            #if os(visionOS)
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            UserDefaults.standard.set(bookmark, forKey: "persistedLibraryBookmark")
            print("[Persistence] Saved library bookmark.")
        } catch {
            print("[Persistence] Failed to create library bookmark: \(error)")
        }
    }
    
    private func loadLibrary() {
        guard let bookmark = UserDefaults.standard.data(forKey: "persistedLibraryBookmark") else { return }
        do {
            var isStale = false
            #if os(visionOS)
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            #else
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            #endif
            
            if isStale {
                print("[Persistence] Library bookmark is stale.")
                // If it's stale, we might need to ask user to pick again, but we can try to use it.
            }
            
            let ok = url.startAccessingSecurityScopedResource()
            if ok {
                print("[Persistence] Loaded persisted library: \(url)")
                pickedDirectory = url
                // Note: We don't stop accessing immediately if we want to read it, but importDirectory does its own access management.
                // However, we should keep the variable accessed if we intend to hold it?
                // Actually `importDirectory` calls startAccessing internally too, which is fine (nested calls work with reference counting).
                // We'll release here and let importDirectory handle it.
                url.stopAccessingSecurityScopedResource()
                
                // Re-import (list files)
                importDirectory(url)
                self.storedObjects = self.directoryObjects
            } else {
                 print("[Persistence] Failed to access persisted library URL.")
            }
        } catch {
            print("[Persistence] Failed to resolve library bookmark: \(error)")
        }
    }
    
    private func saveObjects(_ objects: [StoredObject]) {
        do {
            let data = try JSONEncoder().encode(objects)
            UserDefaults.standard.set(data, forKey: "persistedStoredObjects")
        } catch {
            print("[Persistence] Failed to encode storedObjects: \(error)")
        }
    }
    
    private func loadPersistedObjects() {
        guard let data = UserDefaults.standard.data(forKey: "persistedStoredObjects") else { return }
        do {
            var loaded = try JSONDecoder().decode([StoredObject].self, from: data)
            print("[Persistence] Loaded \(loaded.count) objects from persistence.")
            
            // Re-inflate tokens
            for i in 0..<loaded.count {
                if let bookmark = loaded[i].bookmark {
                    do {
                        var isStale = false
                        #if os(visionOS)
                        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                        #else
                        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
                        #endif
                        
                        // We must start accessing if we want to use it later
                        // But managing the lifecycle of these access tokens is tricky.
                        // Usually, you start accessing right before using, and stop after.
                        // For now, we just resolve the URL. The view or placement logic will call startAccessing again when needed (via the bookmark in userInfo).
                        loaded[i].url = url
                    } catch {
                        print("[Persistence] Failed to resolve object bookmark for \(loaded[i].name): \(error)")
                    }
                }
            }
            storedObjects = loaded
        } catch {
            print("[Persistence] Failed to decode storedObjects: \(error)")
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
            let supportedExts: Set<String> = ["usdz", "reality", ]
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
                        
                        // Create bookmark for the local file if needed, or better, for the original if we want to persist source ref.
                        // But actually `importDirectory` implies copying to app documents?
                        // If we copy to app documents, we don't need security scope for the destination.
                        // But wait, the previous code copied it.
                        // The user said "persist selected library".
                        // If "Library" view just shows external files, we need bookmarks.
                        // If "Objects" list contains copied files, we don't need bookmarks for them (they are in app container).
                        // Let's create a bookmark for the *source* just in case or just rely on the copied path.
                        // StoredObject(name: url.lastPathComponent, url: dst) is safe for app restart if dst is in Documents.
                        
                        var obj = StoredObject(name: url.lastPathComponent, url: dst)
                        // If we want to persist the SOURCE bookmark to re-copy later? No need.
                        
                        directoryObjects.append(obj)
                    } catch {
                        print("[ContentView] Failed copying \(url.lastPathComponent): \(error)")
                    }

                    if fileAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
            self.storedObjects = self.directoryObjects
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

