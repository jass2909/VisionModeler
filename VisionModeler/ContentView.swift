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
    }

    @State private var storedObjects: [StoredObject] = []
    @State private var pendingPlacement: StoredObject? = nil

    @State private var pickedDirectory: URL? = nil
    @State private var directoryObjects: [StoredObject] = []
    @State private var showingDirectoryImporter: Bool = false

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
                            if showImmersive {
                                NotificationCenter.default.post(
                                    name: .placeObjectRequested,
                                    object: nil,
                                    userInfo: [
                                        "id": obj.id.uuidString,
                                        "name": obj.name,
                                        "url": obj.url?.absoluteString ?? ""
                                    ]
                                )
                            } else {
                                pendingPlacement = obj
                                showImmersive = true
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
                        pendingPlacement: $pendingPlacement
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
                    pickedDirectory = dir
                    loadObjects(from: dir)
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
                                "url": obj.url?.absoluteString ?? ""
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
        do {
            let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            let supportedExts: Set<String> = ["usdz", "reality"]
            for url in contents {
                if supportedExts.contains(url.pathExtension.lowercased()) {
                    directoryObjects.append(StoredObject(name: url.lastPathComponent, url: url))
                }
            }
            if directoryObjects.isEmpty {
                print("[ContentView] No supported model files in directory: \(directory)")
            }
        } catch {
            print("[ContentView] Failed to list directory: \(error)")
        }
    }
}


#Preview {
    ContentView(showImmersive: .constant(false))
        .environmentObject(SettingsStore())
}

