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
    
    @State private var previewingObject: ContentView.StoredObject? = nil
    @State private var isScanning: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showShapePicker: Bool = false
    @State private var showingSoundImporter = false
    @State private var objectForSound: UUID? = nil
    
    var body: some View {
        ZStack {
            List {
                if storedObjects.isEmpty {
                    Text("No objects yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(storedObjects) { obj in
                        HStack {
                            Text(obj.name)
                            Spacer()
                            HStack(spacing: 12) {
                                if !settings.placedIDs.contains(obj.id) {
                                    Button {
                                        // Mark as placed and route through immersive open + delayed post
                                        settings.placedIDs.insert(obj.id)
                                        pendingPlacement = obj
                                        if !showImmersive {
                                            // Trigger opening via state change.
                                            // The actual placement will be handled by ContentView's onChange(of: showImmersive)
                                            showImmersive = true
                                        } else {
                                            // Immersive space already open, post immediately
                                            Task {
                                                // Ensure space is active (idempotent)
                                                await openImmersiveSpace(id: "placeSpace")
                                                
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
                                                    case "Cone":
                                                        userInfo["named"] = "Cone"
                                                    case "Cylinder":
                                                        userInfo["named"] = "Cylinder"
                                                    case "Plane":
                                                        userInfo["named"] = "Plane"
                                                    default:
                                                        break
                                                    }
                                                }
                                                
                                                NotificationCenter.default.post(
                                                    name: .placeObjectRequested,
                                                    object: nil,
                                                    userInfo: userInfo
                                                )
                                                pendingPlacement = nil
                                            }
                                        }
                                    } label: {
                                        Text("Place")
                                    }
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
                        settings.placedIDs.subtract(idsToRemove)
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
                                showShapePicker = true
                            } label: {
                                Text("Add Shape").highContrastTextOutline(true)
                            }
                            .buttonStyle(HighContrastButtonStyle(enabled: true))
                            .popover(isPresented: $showShapePicker) {
                                VStack(spacing: 12) {
                                    Button {
                                        if let url = Bundle.main.url(forResource: "CubePlaceholder", withExtension: "usdz") {
                                            storedObjects.append(ContentView.StoredObject(name: "Cube", url: url))
                                        } else {
                                            storedObjects.append(ContentView.StoredObject(name: "Cube", url: nil))
                                        }
                                        showShapePicker = false
                                    } label: {
                                        Label("Cube", systemImage: "cube")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        if let url = Bundle.main.url(forResource: "SpherePlaceholder", withExtension: "usdz") {
                                            storedObjects.append(ContentView.StoredObject(name: "Sphere", url: url))
                                        } else {
                                            storedObjects.append(ContentView.StoredObject(name: "Sphere", url: nil))
                                        }
                                        showShapePicker = false
                                    } label: {
                                        Label("Sphere", systemImage: "circle")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        storedObjects.append(ContentView.StoredObject(name: "Cone", url: nil))
                                        showShapePicker = false
                                    } label: {
                                        Label("Cone", systemImage: "cone")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        storedObjects.append(ContentView.StoredObject(name: "Cylinder", url: nil))
                                        showShapePicker = false
                                    } label: {
                                        Label("Cylinder", systemImage: "cylinder")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        storedObjects.append(ContentView.StoredObject(name: "Plane", url: nil))
                                        showShapePicker = false
                                    } label: {
                                        Label("Plane", systemImage: "square")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding()
                                .frame(width: 240)
                                .presentationCompactAdaptation(.popover)
                            }
                            
                            Button {
                                showFileImporter = true
                            } label: {
                                Text("Import USDZ").highContrastTextOutline(true)
                            }
                            .buttonStyle(HighContrastButtonStyle(enabled: true))
                        } else {
                            Button("Add Shape") {
                                showShapePicker = true
                            }
                            .buttonStyle(.bordered)
                            .popover(isPresented: $showShapePicker) {
                                VStack(spacing: 12) {
                                    Button {
                                        if let url = Bundle.main.url(forResource: "CubePlaceholder", withExtension: "usdz") {
                                            storedObjects.append(ContentView.StoredObject(name: "Cube", url: url))
                                        } else {
                                            storedObjects.append(ContentView.StoredObject(name: "Cube", url: nil))
                                        }
                                        showShapePicker = false
                                    } label: {
                                        Label("Cube", systemImage: "cube")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        if let url = Bundle.main.url(forResource: "SpherePlaceholder", withExtension: "usdz") {
                                            storedObjects.append(ContentView.StoredObject(name: "Sphere", url: url))
                                        } else {
                                            storedObjects.append(ContentView.StoredObject(name: "Sphere", url: nil))
                                        }
                                        showShapePicker = false
                                    } label: {
                                        Label("Sphere", systemImage: "circle")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        storedObjects.append(ContentView.StoredObject(name: "Cone", url: nil))
                                        showShapePicker = false
                                    } label: {
                                        Label("Cone", systemImage: "cone")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        storedObjects.append(ContentView.StoredObject(name: "Cylinder", url: nil))
                                        showShapePicker = false
                                    } label: {
                                        Label("Cylinder", systemImage: "cylinder")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        storedObjects.append(ContentView.StoredObject(name: "Plane", url: nil))
                                        showShapePicker = false
                                    } label: {
                                        Label("Plane", systemImage: "square")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding()
                                .frame(width: 240)
                                .presentationCompactAdaptation(.popover)
                            }
                            
                            Button("Import USDZ") {
                                showFileImporter = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
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
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.usdz, UTType(filenameExtension: "reality", conformingTo: .data) ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else {
                        print("Access denied")
                        return
                    }
                    
                    let bookmark = try? url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    
                    let newObject = ContentView.StoredObject(
                        name: url.deletingPathExtension().lastPathComponent,
                        url: url,
                        bookmark: bookmark
                    )
                    storedObjects.append(newObject)
                    
                case .failure(let error):
                    print("Import failed: \(error.localizedDescription)")
                }
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
                case "Cone":
                    RealityView { content in
                        let mesh = MeshResource.generateCone(height: 0.2, radius: 0.1)
                        let mat = SimpleMaterial(color: .green, isMetallic: false)
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
                        Text("Cone preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                case "Cylinder":
                    RealityView { content in
                        let mesh = MeshResource.generateCylinder(height: 0.2, radius: 0.1)
                        let mat = SimpleMaterial(color: .yellow, isMetallic: false)
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
                        Text("Cylinder preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                case "Plane":
                    RealityView { content in
                        let mesh = MeshResource.generatePlane(width: 0.3, depth: 0.3)
                        let mat = SimpleMaterial(color: .gray, isMetallic: false)
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
                        Text("Plane preview")
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
    
    // State
    @State private var previewScale: CGFloat = 1.0
    
    // Rotation State
    @State private var currentYaw: Double = 0
    @State private var currentPitch: Double = 0
    @State private var lastYaw: Double = 0
    @State private var lastPitch: Double = 0
    
    @State private var textToApply: String = ""
    
    let object: ContentView.StoredObject
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background Gradient for Premium feel (subtle)
                RadialGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.clear]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 500
                )
                .ignoresSafeArea()
                
                // 3D Content
                VStack {
                    Spacer()
                    Model3DView(object: object, appliedText: textToApply)
                        .scaleEffect(previewScale)
                        .rotation3DEffect(.degrees(currentPitch), axis: (x: 1, y: 0, z: 0))
                        .rotation3DEffect(.degrees(currentYaw), axis: (x: 0, y: 1, z: 0))
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    Spacer()
                }
            }
            .contentShape(Rectangle()) // Make the whole area tappable/draggable
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let sensitivity = 0.5
                        currentYaw = lastYaw + value.translation.width * sensitivity
                        currentPitch = lastPitch - value.translation.height * sensitivity
                    }
                    .onEnded { _ in
                        lastYaw = currentYaw
                        lastPitch = currentPitch
                    }
            )
            .navigationTitle(object.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        let isPlaced = settings.placedIDs.contains(object.id)
                        Button(isPlaced ? "Placed" : "Place") {
                            if isPlaced { return }
                            Task {
                                await openImmersiveSpace(id: "placeSpace")
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                
                                settings.placedIDs.insert(object.id)
                                
                                var userInfo: [String: Any] = [
                                    "id": object.id.uuidString,
                                    "name": object.name,
                                    "bookmark": object.bookmark as Any,
                                    "appliedText": textToApply
                                ]
                                if let url = object.url {
                                    userInfo["url"] = url.absoluteString
                                } else {
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
                        .disabled(isPlaced)
                        .buttonStyle(.borderedProminent)
                        .tint(isPlaced ? .gray : .blue)
                        
                        Button("Done") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .ornament(attachmentAnchor: .scene(.bottom)) {
                HStack(spacing: 24) {
                    // Scale Control
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scale: \(String(format: "%.1fx", previewScale))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            
                            Slider(value: $previewScale, in: 0.1...3.0, step: 0.1)
                                .frame(width: 280)
                                .tint(.blue)
                        }
                    }
                    .padding(.horizontal, 8)
                    
                    Divider()
                        .frame(height: 30)
                    
                    // Label Control
                    HStack(spacing: 12) {
                        Image(systemName: "textformat")
                            .foregroundStyle(.secondary)
                        
                        TextField("Apply 3D Label", text: $textToApply)
                            .textFieldStyle(.plain)
                            .frame(width: 180)
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        
                        if !textToApply.isEmpty {
                            Button { textToApply = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .glassBackgroundEffect()
            }
        }
    }
}

#Preview {
    ObjectsView(
        storedObjects: .constant([ContentView.StoredObject(name: "Test Cube", url: nil)]),
        showImmersive: .constant(false),
        pendingPlacement: .constant(nil)
    )
    .environmentObject(SettingsStore())
}

