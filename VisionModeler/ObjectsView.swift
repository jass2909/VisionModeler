import SwiftUI
import RealityKit
import RealityKitContent

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
    }
}

struct Model3DView: View {
    let object: ContentView.StoredObject

    var body: some View {
        // Note: Avoid `Model3D(model:)` which can lead to generic inference errors; prefer `Model3D(url:)` or `Model3D(named:)`.
        Group {
            if let url = object.url {
                // Load from a file URL
                Model3D(url: url)
                       .frame(width: 350, height: 350)
                       .scaleEffect(0.3)
            } else {
                switch object.name {
                case "Cube":
                    RealityView { content in
                        let mesh = MeshResource.generateBox(size: 0.2)
                        let mat = SimpleMaterial(color: .red, isMetallic: false)
                        let e = ModelEntity(mesh: mesh, materials: [mat])
                        content.add(e)
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
                        content.add(e)
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
}

struct ModelPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow
    @State private var previewScale: CGFloat = 1.0
    @State private var yaw: Angle = .degrees(0)
    @State private var pitch: Angle = .degrees(0)
    let object: ContentView.StoredObject

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Model3DView(object: object)
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
