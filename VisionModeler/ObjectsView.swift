import SwiftUI
import RealityKit
import RealityKitContent
import UniformTypeIdentifiers

struct ObjectPreviewItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var url: String?
}

struct ObjectsView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Binding var storedObjects: [ContentView.StoredObject]
    @Binding var showImmersive: Bool
    @Binding var pendingPlacement: ContentView.StoredObject?
    @Binding var placedIDs: Set<UUID>
    @State private var previewingObject: ContentView.StoredObject? = nil
    @State private var isScanning: Bool = false
    @State private var showingSoundImporter = false
    @State private var objectForSound: UUID? = nil
    
    var body: some View {
        List {
            if storedObjects.isEmpty {
                Text("No objects yet.").foregroundStyle(.secondary)
            } else {
                ForEach(storedObjects) { obj in
                    HStack {
                        Text(obj.name)
                        Spacer()
                        HStack(spacing: 12) {
                            if !placedIDs.contains(obj.id) {
                                Button {
                                    // Mark as placed and route through immersive open + delayed post
                                    placedIDs.insert(obj.id)
                                    pendingPlacement = obj
                                    if !showImmersive { showImmersive = true }
                                    Task {
                                        await openImmersiveSpace(id: "placeSpace")
                                        try? await Task.sleep(nanoseconds: 300_000_000)
                                        print("[ObjectsView] Posting placeObjectRequested for \(obj.name) (\(obj.id))")
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
                                            // Provide a named fallback for bundled placeholders when no URL is available
                                            switch obj.name {
                                            case "Cube":
                                                userInfo["named"] = "CubePlaceholder"
                                            case "Sphere":
                                                userInfo["named"] = "SpherePlaceholder"
                                            default:
                                                break
                                            }
                                        }
                                        NotificationCenter.default.post(
                                            name: .placeObjectRequested,
                                            object: nil,
                                            userInfo: userInfo
                                        )
                                    }
                                } label: {
                                    Text("Place")
                                }
                                .buttonStyle(.bordered)
                            .buttonStyle(.bordered)
                            
                            Button {
                                objectForSound = obj.id
                                showingSoundImporter = true
                            } label: {
                                if obj.soundURL != nil {
                                    Label("Sound", systemImage: "speaker.wave.2.fill")
                                } else {
                                    Text("Sound")
                                }
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Text("Placed").foregroundStyle(.secondary)
                        }

                        Button {
                            openWindow(value: PreviewItem(
                                id: obj.id,
                                name: obj.name,
                                url: obj.url?.absoluteString
                            ))
                        } label: {
                            Text("View")
                        }
                        .buttonStyle(.bordered)
                        }
                    }
                }
                .onDelete { indexSet in
                    // Send removal requests for any deleted objects so the immersive space can remove them
                    let idsToRemove = indexSet.map { storedObjects[$0].id }
                    idsToRemove.forEach { id in
                        NotificationCenter.default.post(
                            name: .removeObjectRequested,
                            object: nil,
                            userInfo: [
                                "id": id.uuidString
                            ]
                        )
                    }
                    storedObjects.remove(atOffsets: indexSet)
                    placedIDs.subtract(idsToRemove)
                }
            }
        }
        .navigationTitle("Objects")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button(isScanning ? "Stop Scanning" : "Scan Surfaces") {
                        isScanning.toggle()
                        let wasClosed = !showImmersive
                        if isScanning && wasClosed {
                            showImmersive = true
                        }
                        
                        Task {
                            if isScanning && wasClosed {
                                await openImmersiveSpace(id: "placeSpace")
                                // Give the view a moment to initialize and subscribe
                                try? await Task.sleep(nanoseconds: 500_000_000)
                            }
                            
                            // Notify the immersive view
                            NotificationCenter.default.post(
                                name: .scanSurfacesToggled,
                                object: nil,
                                userInfo: ["enabled": isScanning]
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(isScanning ? .red : .blue)
                    
                    if settings.useHighContrast {
                        Button {
                            if let url = Bundle.main.url(forResource: "CubePlaceholder", withExtension: "usdz") {
                                storedObjects.append(ContentView.StoredObject(name: "Cube", url: url))
                            } else {
                                storedObjects.append(ContentView.StoredObject(name: "Cube", url: nil))
                            }
                        } label: {
                            Text("Add Cube").highContrastTextOutline(true)
                        }
                        .buttonStyle(HighContrastButtonStyle(enabled: true))
                        
                        Button {
                            if let url = Bundle.main.url(forResource: "SpherePlaceholder", withExtension: "usdz") {
                                storedObjects.append(ContentView.StoredObject(name: "Sphere", url: url))
                            } else {
                                storedObjects.append(ContentView.StoredObject(name: "Sphere", url: nil))
                            }
                        } label: {
                            Text("Add Sphere").highContrastTextOutline(true)
                        }
                        .buttonStyle(HighContrastButtonStyle(enabled: true))
                        
                        Button {
                            storedObjects.append(ContentView.StoredObject(name: "Imported Model", url: nil))
                        } label: {
                            Text("Import Placeholder").highContrastTextOutline(true)
                        }
                        .buttonStyle(HighContrastButtonStyle(enabled: true))
                    } else {
                        Button("Add Cube") {
                            if let url = Bundle.main.url(forResource: "CubePlaceholder", withExtension: "usdz") {
                                storedObjects.append(ContentView.StoredObject(name: "Cube", url: url))
                            } else {
                                storedObjects.append(ContentView.StoredObject(name: "Cube", url: nil))
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Add Sphere") {
                            if let url = Bundle.main.url(forResource: "SpherePlaceholder", withExtension: "usdz") {
                                storedObjects.append(ContentView.StoredObject(name: "Sphere", url: url))
                            } else {
                                storedObjects.append(ContentView.StoredObject(name: "Sphere", url: nil))
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Import Placeholder") {
                            storedObjects.append(ContentView.StoredObject(name: "Imported Model", url: nil))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .sheet(item: $previewingObject) { obj in
            ModelPreviewView(object: obj)
                .environmentObject(settings)
        }
        .fileImporter(isPresented: $showingSoundImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    guard let objectId = objectForSound else { return }
                    if let index = storedObjects.firstIndex(where: { $0.id == objectId }) {
                        // Create bookmark
                        do {
                            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                            storedObjects[index].soundURL = url
                            storedObjects[index].soundBookmark = bookmark
                        } catch {
                            print("Error creating bookmark for sound: \(error)")
                        }
                    }
                }
            case .failure(let error):
                print("Error picking sound: \(error)")
            }
        }
    }
}

struct Model3DView: View {
    let object: ContentView.StoredObject
    var appliedText: String? = nil

    var body: some View {
        Group {
            if let url = object.url {
                RealityView { content in
                    do {
                        let entity = try await ModelEntity(contentsOf: url)
                        
                        let container = Entity()
                        container.name = "Container"
                        container.addChild(entity)
                        
                        // Center the entity based on its visual bounds
                        let bounds = entity.visualBounds(relativeTo: nil)
                        entity.position = -bounds.center
                        
                        // Apply a default scale similar to the original .scaleEffect(0.3)
                        container.scale = SIMD3(repeating: 0.3)
                        
                        content.add(container)
                    } catch {
                        print("Error loading model: \(error)")
                    }
                } update: { content in
                    if let container = content.entities.first(where: { $0.name == "Container" }) {
                        updateText(on: container, text: appliedText)
                    }
                }
                .frame(width: 350, height: 350)
            } else {
                switch object.name {
                case "Cube":
                    RealityView { content in
                        let mesh = MeshResource.generateBox(size: 0.2)
                        let mat = SimpleMaterial(color: .red, isMetallic: false)
                        let e = ModelEntity(mesh: mesh, materials: [mat])
                        
                        let container = Entity()
                        container.name = "Container"
                        container.addChild(e)
                        
                        content.add(container)
                    } update: { content in
                        if let container = content.entities.first(where: { $0.name == "Container" }) {
                            updateText(on: container, text: appliedText)
                        }
                    }
                    .frame(width: 350, height: 350)
                    .overlay(alignment: .bottom) {
                        Text("Cube preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                case "Sphere":
                    RealityView { content in
                        let mesh = MeshResource.generateSphere(radius: 0.12)
                        let mat = SimpleMaterial(color: .blue, isMetallic: false)
                        let e = ModelEntity(mesh: mesh, materials: [mat])
                        
                        let container = Entity()
                        container.name = "Container"
                        container.addChild(e)
                        
                        content.add(container)
                    } update: { content in
                        if let container = content.entities.first(where: { $0.name == "Container" }) {
                            updateText(on: container, text: appliedText)
                        }
                    }
                    .frame(width: 350, height: 350)
                    .overlay(alignment: .bottom) {
                        Text("Sphere preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                default:
                    Text("No model available")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private func updateText(on container: Entity, text: String?) {
        if let existing = container.findEntity(named: "AppliedText") {
            existing.removeFromParent()
        }

        guard let text = text, !text.isEmpty else { return }

        // Calculate bounds of existing content (excluding the text we just removed)
        let modelBounds = container.visualBounds(relativeTo: container)

        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.05),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let material = SimpleMaterial(color: .white, isMetallic: false)
        let textEntity = ModelEntity(mesh: mesh, materials: [material])
        textEntity.name = "AppliedText"

        let textBounds = textEntity.visualBounds(relativeTo: nil)
        
        // Position text centered above the model
        textEntity.position = SIMD3(
            -textBounds.extents.x / 2,
            modelBounds.max.y + 0.05,
            0
        )

        container.addChild(textEntity)
    }
}

struct ModelPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var previewScale: CGFloat = 1.0
    @State private var yaw: Angle = .degrees(0)
    @State private var pitch: Angle = .degrees(0)
    @State private var textToApply: String = ""
    let object: ContentView.StoredObject

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Model3DView(object: object, appliedText: textToApply)
                    .scaleEffect(previewScale)
                    .rotation3DEffect(pitch, axis: (x: 1, y: 0, z: 0))
                    .rotation3DEffect(yaw, axis: (x: 0, y: 1, z: 0))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let yawSensitivity: Double = 0.4
                                let pitchSensitivity: Double = 0.4
                                yaw = .degrees(value.translation.width * yawSensitivity)
                                pitch = .degrees(-value.translation.height * pitchSensitivity)
                            }
                    )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                         TextField("Apply Text", text: $textToApply)
                             .textFieldStyle(.roundedBorder)
                         if !textToApply.isEmpty {
                             Button {
                                textToApply = ""
                             } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                             }
                         }
                    }
                    .padding(.bottom, 8)

                    HStack {
                        Text("Scale")
                        Spacer()
                        Text(String(format: "%.2fx", previewScale))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $previewScale, in: 0.1...3.0, step: 0.05)
                }
                .padding(.horizontal)
            }
            .navigationTitle(object.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button("Place") {
                            Task {
                                // Ensure the immersive space is open
                                await openImmersiveSpace(id: "placeSpace")
                                // Give it a moment to initialize
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                
                                var userInfo: [String: Any] = [
                                    "id": object.id.uuidString,
                                    "name": object.name,
                                    "bookmark": object.bookmark as Any,
                                    "appliedText": textToApply
                                ]
                                if let url = object.url {
                                    userInfo["url"] = url.absoluteString
                                } else {
                                    // Fallback names for built-ins
                                    switch object.name {
                                    case "Cube": userInfo["named"] = "CubePlaceholder"
                                    case "Sphere": userInfo["named"] = "SpherePlaceholder"
                                    default: break
                                    }
                                }
                                
                                NotificationCenter.default.post(
                                    name: .placeObjectRequested,
                                    object: nil,
                                    userInfo: userInfo
                                )
                                dismiss()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        
                        if settings.useHighContrast {
                            Button(action: { dismiss() }) {
                                Text("Done").highContrastTextOutline(true)
                            }
                            .buttonStyle(HighContrastButtonStyle(enabled: true))
                        } else {
                            Button("Done") { dismiss() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("previewScaleChanged"))) { output in
            guard let userInfo = output.userInfo,
                  let idString = userInfo["id"] as? String,
                  let scale = userInfo["scale"] as? CGFloat,
                  idString == object.id.uuidString else { return }
            previewScale = scale
        }
    }
}

#Preview {
    ObjectsView(
        storedObjects: .constant([ContentView.StoredObject(name: "Test Cube", url: nil)]),
        showImmersive: .constant(false),
        pendingPlacement: .constant(nil),
        placedIDs: .constant([])
    )
    .environmentObject(SettingsStore())
}
