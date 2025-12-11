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


    struct StoredObject: Identifiable, Hashable, Codable {
        let id: UUID
        var name: String
        var url: URL?
        var bookmark: Data? = nil
        var soundURL: URL? = nil
        var soundBookmark: Data? = nil
        

        init(id: UUID = UUID(), name: String, url: URL?, bookmark: Data? = nil, soundURL: URL? = nil, soundBookmark: Data? = nil) {
            self.id = id
            self.name = name
            self.url = url
            self.bookmark = bookmark
            self.soundURL = soundURL
            self.soundBookmark = soundBookmark
        }
    }

    @State private var storedObjects: [StoredObject] = []
    @State private var storedScenes: [StoredObject] = []
    @State private var pendingPlacement: StoredObject? = nil

    @State private var pickedDirectory: URL? = nil
    @State private var directoryObjects: [StoredObject] = []
    @State private var showingDirectoryImporter: Bool = false
    // Export State
    @State private var exportDocument: ExportFileDocument? = nil
    @State private var isExporting: Bool = false
    @State private var exportFilename: String = "model"
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
                case .scenes:
                    ScenesView(
                         storedScenes: $storedScenes,
                         showImmersive: $showImmersive
                    )
                case .library:
                    LibraryView(
                        objects: $directoryObjects,
                        pickDirectory: { showingDirectoryImporter = true },
                        place: { obj in

                            pendingPlacement = obj
                            
                            if !showImmersive {
                                showImmersive = true
                            } else {

                                Task {
                                    var userInfo: [String: Any] = [
                                        "id": obj.id.uuidString,
                                        "name": obj.name,
                                        "bookmark": obj.bookmark as Any
                                    ]
                                    
                                    if let soundUrl = obj.soundURL {
                                        userInfo["soundURL"] = soundUrl.absoluteString
                                    }
                                    if let soundBookmark = obj.soundBookmark {
                                        userInfo["soundBookmark"] = soundBookmark
                                    }
                                    
                                    if let url = obj.url {
                                        userInfo["url"] = url.absoluteString
                                    } else {

                                        switch obj.name {
                                        case "Cube": userInfo["named"] = "CubePlaceholder"
                                        case "Sphere": userInfo["named"] = "SpherePlaceholder"
                                        default: break
                                        }
                                    }
                                    
                                    print("[ContentView] Posting placeObjectRequested (Library) for \(obj.name) (\(obj.id))")
                                    NotificationCenter.default.post(
                                        name: .placeObjectRequested,
                                        object: nil,
                                        userInfo: userInfo
                                    )
                                    pendingPlacement = nil
                                }
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
                        pendingPlacement: $pendingPlacement
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

        .onChange(of: showImmersive) { _, newValue in
            if newValue {
                Task {
                    await openImmersiveSpace(id: "placeSpace")

                    if let obj = pendingPlacement {

                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                        
                        var userInfo: [String: Any] = [
                            "id": obj.id.uuidString,
                            "name": obj.name,
                            "bookmark": obj.bookmark as Any
                        ]
                        
                        if let soundUrl = obj.soundURL {
                            userInfo["soundURL"] = soundUrl.absoluteString
                        }
                        if let soundBookmark = obj.soundBookmark {
                            userInfo["soundBookmark"] = soundBookmark
                        }
                        
                        if let url = obj.url {
                            userInfo["url"] = url.absoluteString
                        } else {

                            switch obj.name {
                            case "Cube": userInfo["named"] = "CubePlaceholder"
                            case "Sphere": userInfo["named"] = "SpherePlaceholder"
                            default: break
                            }
                        }
                        
                        print("[ContentView] Posting placeObjectRequested for \(obj.name) (\(obj.id))")
                        NotificationCenter.default.post(
                            name: .placeObjectRequested,
                            object: nil,
                            userInfo: userInfo
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

            loadLibrary()
            loadPersistedObjects()
            loadPersistedScenes()
            storedObjects = directoryObjects
        }
        .onChange(of: storedObjects) { _, newValue in
            saveObjects(newValue)
        }
        .onChange(of: storedScenes) { _, newValue in
            saveScenes(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .removeObjectRequested)) { note in
            guard let userInfo = note.userInfo,
                  let idString = userInfo["id"] as? String,
                  let id = UUID(uuidString: idString) else { return }
            

            settings.placedIDs.remove(id)
            

            if let delete = userInfo["deleteFromLibrary"] as? Bool, delete {
                if let index = storedObjects.firstIndex(where: { $0.id == id }) {
                    print("[ContentView] removeObjectRequested -> Deleting object \(id) from library")
                    storedObjects.remove(at: index)
                }
            }
        }
        .fileExporter(
             isPresented: $isExporting,
             document: exportDocument,
             contentType: .usdz,
             defaultFilename: exportFilename
         ) { result in
             switch result {
             case .success(let url):
                 print("[ContentView] Exported to \(url)")
             case .failure(let error):
                 print("[ContentView] Export failed: \(error)")
             }
         }
         .onReceive(NotificationCenter.default.publisher(for: Notification.Name("exportObjectRequested"))) { note in
             if let userInfo = note.userInfo,
                let url = userInfo["url"] as? URL,
                let filename = userInfo["filename"] as? String {
                 print("[ContentView] exportObjectRequested: \(filename)")
                 exportFilename = filename
                 exportDocument = ExportFileDocument(fileURL: url)
                 isExporting = true
             }
         }
    }
    
    // MARK: - Persistence
    
    private func pickDirectory(_ url: URL) {
        pickedDirectory = url
        saveLibrary(url)
        importDirectory(url)
    }
    
    private func saveLibrary(_ url: URL) {

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
            }
            
            let ok = url.startAccessingSecurityScopedResource()
            if ok {
                print("[Persistence] Loaded persisted library: \(url)")
                pickedDirectory = url
                // Note: We don't stop accessing immediately if we want to read it, but importDirectory does its own access management.
                url.stopAccessingSecurityScopedResource()
                

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
                        
                        var obj = StoredObject(name: url.lastPathComponent, url: dst)
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
    
    private func saveScenes(_ scenes: [StoredObject]) {
        do {
            let data = try JSONEncoder().encode(scenes)
            UserDefaults.standard.set(data, forKey: "persistedStoredScenes")
        } catch {
            print("[Persistence] Failed to encode storedScenes: \(error)")
        }
    }
    
    private func loadPersistedScenes() {
        guard let data = UserDefaults.standard.data(forKey: "persistedStoredScenes") else { return }
        do {
             var loaded = try JSONDecoder().decode([StoredObject].self, from: data)
             print("[Persistence] Loaded \(loaded.count) scenes.")
             
             for i in 0..<loaded.count {
                 if let bookmark = loaded[i].bookmark {
                     do {
                         var isStale = false
                         let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                         loaded[i].url = url
                     } catch {
                         print("Failed to resolve scene bookmark: \(error)")
                     }
                 }
             }
             storedScenes = loaded
        } catch {
            print("[Persistence] Failed to decode storedScenes: \(error)")
        }
    }
}


#Preview {
    ContentView(showImmersive: .constant(false))
        .environmentObject(SettingsStore())
}

