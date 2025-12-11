import SwiftUI
import RealityKit
import UniformTypeIdentifiers

struct ScenesView: View {
    @Binding var storedScenes: [ContentView.StoredObject]
    @Binding var showImmersive: Bool
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @EnvironmentObject var settings: SettingsStore
    
    @State private var showFileImporter = false

    var body: some View {
        List {
            if storedScenes.isEmpty {
                Text("No scenes imported.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(storedScenes) { scene in
                    HStack {
                        Text(scene.name)
                        Spacer()
                        Button("Enter") {
                            enterScene(scene)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                }
                .onDelete { indexSet in
                    storedScenes.remove(atOffsets: indexSet)
                }
            }
        }
        .navigationTitle("Scenes")
        .toolbar {
             ToolbarItem(placement: .primaryAction) {
                Button("Import Scene") {
                    showFileImporter = true
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.usdz, UTType(filenameExtension: "reality", conformingTo: .data) ?? .data],
            allowsMultipleSelection: false
        ) { result in
             switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                
                let bookmark = try? url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                
                let newScene = ContentView.StoredObject(
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    bookmark: bookmark
                )
                storedScenes.append(newScene)
                
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func enterScene(_ scene: ContentView.StoredObject) {
        Task {
            if !showImmersive {
                showImmersive = true
            }
             await openImmersiveSpace(id: "placeSpace")
             
             // Wait briefly to ensure space is ready
             try? await Task.sleep(nanoseconds: 500_000_000)

             var userInfo: [String: Any] = [
                "id": scene.id.uuidString,
                "name": scene.name,
                "bookmark": scene.bookmark as Any
             ]
             if let url = scene.url {
                 userInfo["url"] = url.absoluteString
             }
             
             NotificationCenter.default.post(
                name: Notification.Name("placeSceneRequested"),
                object: nil,
                userInfo: userInfo
             )
        }
    }
}
