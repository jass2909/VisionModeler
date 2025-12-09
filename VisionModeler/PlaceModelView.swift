// Accessibility adaptations included:
// - High Contrast mode toggle that restyles panels and text for improved readability
// - Larger hit zones on buttons to aid motor accessibility

import SwiftUI
import ModelIO
import RealityKit
import RealityKitContent
import ARKit

extension Entity {
    func isDescendant(of ancestor: Entity) -> Bool {
        var current: Entity? = self
        while let c = current {
            if c === ancestor { return true }
            current = c.parent
        }
        return false
    }
}

struct PlaceModelView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismissImmersiveSpace) var dismiss

    // World anchor and placed entities store
    @State private var worldAnchor = AnchorEntity(.world(transform: matrix_identity_float4x4))
    @State private var placedEntities: [String: Entity] = [:]

    @State private var lockedEntityIDs: Set<String> = []
    @State private var physicsDisabledEntityIDs: Set<String> = []

    // Gesture state
    @State private var grabbedEntity: Entity? = nil
    @State private var grabbedStartWorldPosition: SIMD3<Float>? = nil

    // Scaling state (two-hand pinch via MagnificationGesture)
    @State private var isScaling: Bool = false
    @State private var baselineScale: SIMD3<Float>? = nil
    // Rotation state (two-hand rotate via RotationGesture)
    @State private var isRotating: Bool = false
    @State private var baselineOrientation: simd_quatf? = nil
    @State private var rotationBaselineX: CGFloat? = nil

    @State private var updateSubscription: EventSubscription? = nil

    // Observers
    @State private var placeObserver: NSObjectProtocol?
    @State private var removeObserver: NSObjectProtocol?

    // ARKit Scan State
    @State private var session = ARKitSession()
    @State private var planeDetection = PlaneDetectionProvider(alignments: [.horizontal])
    @State private var planeEntities: [UUID: Entity] = [:]

    @State private var isScanningSubscribed = false
    
    // Pending placement state
    @State private var pendingPlacement: (id: String, name: String, source: [AnyHashable: Any])? = nil
    
    // Anchor Menu State
    @State private var selectedAnchorPosition: SIMD3<Float>? = nil
    
    // Audio State
    @State private var audioControllers: [String: AudioPlaybackController] = [:]



    private let dragSensitivity: Float = 1
    private let dragSmoothing: Float = 0.2

    private func topMovableEntity(from entity: Entity) -> Entity {
        var current: Entity = entity
        // Climb up until the parent is the worldAnchor or there is no parent.
        while let parent = current.parent, parent !== worldAnchor {
            current = parent
        }
        return current
    }
    private func isPlaneEntity(_ entity: Entity) -> Bool {
        for plane in planeEntities.values {
            if entity === plane || entity.isDescendant(of: plane) {
                return true
            }
        }
        return false
    }

    private func updatePlane(_ anchor: PlaneAnchor) {
        // Prepare visualization material
        // Use light gray half transparent coloring as requested
        let color = UIColor.lightGray.withAlphaComponent(0.1)
        let material = UnlitMaterial(color: color)
        
        // Create or get the parent entity (representing the anchor, at anchor.transform)
        let parentEntity: Entity
        if let existing = planeEntities[anchor.id] {
            parentEntity = existing
        } else {
            parentEntity = Entity()
            worldAnchor.addChild(parentEntity)
            planeEntities[anchor.id] = parentEntity
        }
        
        // Update parent transform
        parentEntity.transform = Transform(matrix: anchor.originFromAnchorTransform)
        
        // Create mesh entity (representing the plane extent, offset by geometry.center)
        // Check if we already have the visual child
        let visualName = "visual_plane"
        let visualEntity: ModelEntity
        if let child = parentEntity.findEntity(named: visualName) as? ModelEntity {
            visualEntity = child
        } else {
            visualEntity = ModelEntity()
            visualEntity.name = visualName
            parentEntity.addChild(visualEntity)
        }
        
        // Update mesh
        let width = anchor.geometry.extent.width
        let depth = anchor.geometry.extent.height // height in 2D extent usually maps to depth in 3D XZ plane
        let mesh = MeshResource.generatePlane(width: width, depth: depth)
        visualEntity.model = ModelComponent(mesh: mesh, materials: [material])
        
        // Update local offset
        // Visual positioned at anchor origin (rather than geometry center) to avoid visual offset
        visualEntity.position = .zero
        
        // Ensure we can tap on it AND collide physically
        if !visualEntity.components.has(InputTargetComponent.self) {
            visualEntity.generateCollisionShapes(recursive: false)
            visualEntity.components.set(InputTargetComponent())
            // Static physics body for planes so objects can land on them
            visualEntity.components.set(PhysicsBodyComponent(mode: .static))
        }
        
        // Visualize Anchor Points Grid
        let anchorsRootName = "anchor_points_root"
        let anchorsRoot: Entity
        if let child = parentEntity.findEntity(named: anchorsRootName) {
            anchorsRoot = child
            // Clear existing points to refresh grid
            anchorsRoot.children.removeAll()
        } else {
            anchorsRoot = Entity()
            anchorsRoot.name = anchorsRootName
            parentEntity.addChild(anchorsRoot)
        }
        
        // Position root at geometry center
        anchorsRoot.position = .zero
        
        // Generate grid
        let density: Float = 0.1 // 30cm spacing
        let gridWidth = anchor.geometry.extent.width
        let gridDepth = anchor.geometry.extent.height
        
        let cols = Int(gridWidth / density)
        let rows = Int(gridDepth / density)
        
        // Create a reusable mesh/material
        let pointMesh = MeshResource.generateSphere(radius: 0.010)
        let pointMat = UnlitMaterial(color: .white)
        
        // Offset to start from top-left corner relative to center
        let startX = -(Float(cols) * density) / 2.0
        let startZ = -(Float(rows) * density) / 2.0
        
        for r in 0...rows {
            for c in 0...cols {
                let x = startX + Float(c) * density
                let z = startZ + Float(r) * density
                
                // Check if point is within bounds
                if abs(x) <= gridWidth/2 && abs(z) <= gridDepth/2 {
                    let pointEntity = ModelEntity(mesh: pointMesh, materials: [pointMat])
                    pointEntity.position = SIMD3<Float>(x, 0.01, z)
                    pointEntity.name = "anchor_point"
                    
                    // Make interactive
                    pointEntity.generateCollisionShapes(recursive: false)
                    pointEntity.components.set(InputTargetComponent())
                    pointEntity.components.set(HoverEffectComponent())
                    
                    anchorsRoot.addChild(pointEntity)
                }
            }
        }
    }
    
    private func snapToNearestAnchor(_ worldPos: SIMD3<Float>) -> SIMD3<Float> {
        let density: Float = 0.1 // Match the grid density
        var bestPos = worldPos
        // Distance threshold to trigger snapping (e.g., must be relatively close to the plane's 'valid' area)
        // Since we check bounds, this is implicitly checking if we are "over" the plane.
        
        for plane in planeEntities.values {
            // Get position in plane's local space
            let localPos = plane.convert(position: worldPos, from: nil)
            
            // Get plane bounds
            let bounds = plane.visualBounds(relativeTo: plane)
            let width = bounds.extents.x
            let depth = bounds.extents.z
            
            // Check if within bounds (plus a margin)
            // This effectively checks if the world position projects onto the plane surface
            if abs(localPos.x) <= (width / 2.0 + density) && abs(localPos.z) <= (depth / 2.0 + density) {
                
                // Calculate grid params matching updatePlane
                let cols = Int(width / density)
                let rows = Int(depth / density)
                let startX = -(Float(cols) * density) / 2.0
                let startZ = -(Float(rows) * density) / 2.0
                
                // Find nearest grid indices
                let c = round((localPos.x - startX) / density)
                let r = round((localPos.z - startZ) / density)
                
                // Clamp to valid grid range (0...cols, 0...rows)
                if c >= 0 && c <= Float(cols) && r >= 0 && r <= Float(rows) {
                    let snappedLocalX = startX + c * density
                    let snappedLocalZ = startZ + r * density
                    
                    // We snap X and Z (surface coordinates), but preserve Y (distance from surface)
                    // This allows the user to lift the object but keeps it aligned to the grid.
                    let snappedLocal = SIMD3<Float>(snappedLocalX, localPos.y, snappedLocalZ)
                    
                    // Convert back to world
                    bestPos = plane.convert(position: snappedLocal, to: nil)
                    
                    // We found a valid snap plane, we can return immediately (or find closest if multiple)
                    // Assuming non-overlapping planes for simplicity
                    return bestPos
                }
            }
        }
        
        return bestPos
    }

    private func makeEntity(for name: String) async throws -> Entity {
        // Support primitive names OR full file names (GLB, OBJ, FBX, USD, USDA, USDC)
        let lower = name.lowercased()
        let url = URL(fileURLWithPath: lower)

        // Detect 3D file formats
        let supportedExtensions = ["glb", "gltf", "obj", "fbx", "usd", "usdc", "usda", "usdz"]
        if supportedExtensions.contains(url.pathExtension) {
            print("[PlaceModelView] Loading external 3D model: \(name)")

            // Load via RealityKit (USDZ/USD) or ModelIO → RealityKit (GLB/OBJ/FBX)
            if url.pathExtension == "usdz" || url.pathExtension == "usd" || url.pathExtension == "usdc" || url.pathExtension == "usda" {
                // Native RealityKit load
                let e = try await Entity.load(contentsOf: url)
                e.generateCollisionShapes(recursive: true)
                e.components.set(InputTargetComponent())
                return e
            } else {
                // Load non‑USDZ formats using ModelIO → RealityKit
                let mdlAsset = MDLAsset(url: url)
                let mdlObject = mdlAsset.object(at: 0)

                let entity = try ModelEntity.loadModel(contentsOf: url)
                entity.components.set(InputTargetComponent())
                entity.generateCollisionShapes(recursive: true)
                return entity
            }
        }

        // OLD predefined models (Cube / Sphere / fallback)
        switch name {
        case "Cube":
            let mesh = MeshResource.generateBox(size: 0.2)
            let mat = SimpleMaterial(color: .red, isMetallic: false)
            let e = ModelEntity(mesh: mesh, materials: [mat])
            e.generateCollisionShapes(recursive: true)
            e.components.set(InputTargetComponent())
            return e

        case "Sphere":
            let mesh = MeshResource.generateSphere(radius: 0.12)
            let mat = SimpleMaterial(color: .blue, isMetallic: false)
            let e = ModelEntity(mesh: mesh, materials: [mat])
            e.generateCollisionShapes(recursive: true)
            e.components.set(InputTargetComponent())
            return e

        default:
            // Fallback bottle asset
            if let e = try? await Entity(named: "Small_bottle", in: realityKitContentBundle) {
                e.setScale([0.01, 0.01, 0.01], relativeTo: nil)
                e.generateCollisionShapes(recursive: true)
                e.components.set(InputTargetComponent())
                return e
            } else {
                print("[PlaceModelView] Bundled asset 'Small_bottle' missing; using primitive fallback.")
                let mesh = MeshResource.generateBox(size: 0.15)
                let mat = SimpleMaterial(color: .gray, isMetallic: false)
                let e = ModelEntity(mesh: mesh, materials: [mat])
                e.generateCollisionShapes(recursive: true)
                e.components.set(InputTargetComponent())
                return e
            }
        }
    }

    var body: some View {
        RealityView { content, attachments in
            // Add a persistent world anchor; do not add any default models here.
            content.add(worldAnchor)
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                // Reserved for future hand-tracking driven scaling updates
            }
        } update: { content, attachments in
            // Sync attachments
            for (id, entity) in placedEntities {
                // Check if we have an attachment for this entity
                if let attachmentEntity = attachments.entity(for: id) {
                    // If the attachment is not yet parented to the entity, add it
                    if attachmentEntity.parent == nil {
                        entity.addChild(attachmentEntity)
                        
                        // Ensure model has hover effect for gaze feedback
                        if !entity.components.has(HoverEffectComponent.self) {
                            entity.components.set(HoverEffectComponent())
                        }
                        
                        // Calculate bounds to position the button above the model
                        // We use the entity's visual bounds relative to itself to get the unscaled size,
                        // then we apply logic to handle the parent scale.
                        // However, simpler is to position relative to local bounds.
                        let bounds = entity.visualBounds(relativeTo: entity)
                        let topY = bounds.max.y
                        
                        // Local offset: Place it 5cm above the bounding box.
                        // Since `entity.scale` affects local space, we must check if we need to compensate.
                        // If we set local position to `topY + 0.05`, and parent scale is `0.01`,
                        // the world offset is `(topY + 0.05) * 0.01`. That might be too small if topY is small.
                        // But `topY` is in local units. If the mesh is 100m tall and scale is 0.01, world is 1m.
                        // If mesh is 0.2m tall (cube) and scale is 1, world is 0.2m.
                        
                        // We want the button to be a fixed world size and fixed world distance above the object.
                        // 1. Reset attachment scale to world 1.0 (inverse of parent world scale).
                        let parentWorldScale = entity.scale(relativeTo: nil)
                        // Avoid division by zero
                        let invScale = SIMD3<Float>(
                            1.0 / (parentWorldScale.x > 1e-4 ? parentWorldScale.x : 1.0),
                            1.0 / (parentWorldScale.y > 1e-4 ? parentWorldScale.y : 1.0),
                            1.0 / (parentWorldScale.z > 1e-4 ? parentWorldScale.z : 1.0)
                        )
                        attachmentEntity.setScale(invScale, relativeTo: entity)
                        
                        // 2. Position it.
                        // We need the world Y of the top of the object.
                        // World Bounds max Y relative to entity center?
                        let worldBounds = entity.visualBounds(relativeTo: nil)
                        let worldTopY = worldBounds.max.y
                        let entityWorldPos = entity.position(relativeTo: nil)
                        
                        // We want attachment world Y = worldTopY + 0.15 (15cm clearance)
                        // We can set world position directly.
                        var targetWorldPos = entityWorldPos
                        targetWorldPos.y = worldTopY + 0.15
                        
                        attachmentEntity.setPosition(targetWorldPos, relativeTo: nil)
                        
                        // Billboard so it faces user
                        attachmentEntity.components.set(BillboardComponent())
                    }
                }
            }
        } attachments: {
            ForEach(Array(placedEntities.keys), id: \.self) { id in
                Attachment(id: id) {
                    HStack(spacing: 8) {
                        Button(action: {
                            NotificationCenter.default.post(
                                name: Notification.Name("removeObjectRequested"),
                                object: nil,
                                userInfo: ["id": id]
                            )
                        }) {
                            Label("Remove", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.plain)
                        
                        let isLocked = lockedEntityIDs.contains(id)
                        Button(action: {
                            if isLocked {
                                lockedEntityIDs.remove(id)
                            } else {
                                lockedEntityIDs.insert(id)
                            }
                        }) {
                            Label(isLocked ? "Unlock" : "Lock", systemImage: isLocked ? "lock.fill" : "lock.open.fill")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.plain)
                        
                        let isPhysicsDisabled = physicsDisabledEntityIDs.contains(id)
                        Button(action: {
                            if let entity = placedEntities[id], var physics = entity.components[PhysicsBodyComponent.self] {
                                if isPhysicsDisabled {
                                    // Enable Physics
                                    physicsDisabledEntityIDs.remove(id)
                                    physics.mode = .dynamic
                                } else {
                                    // Disable Physics
                                    physicsDisabledEntityIDs.insert(id)
                                    physics.mode = .kinematic
                                }
                                entity.components.set(physics)
                            }
                        }) {
                            Label(isPhysicsDisabled ? "Physics Off" : "Physics On", systemImage: isPhysicsDisabled ? "atom" : "atom")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(isPhysicsDisabled ? .secondary : .primary)
                        }
                        .buttonStyle(.plain)
                        
                        let isPlaying = audioControllers[id] != nil
                        Button(action: {
                            toggleSound(for: id)
                        }) {
                            Label(isPlaying ? "Stop Sound" : "Play Sound", systemImage: isPlaying ? "speaker.wave.3.fill" : "speaker.slash.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(isPlaying ? .blue : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .glassBackgroundEffect()
                }
            }
            
            
            Attachment(id: "anchorMenu") {
                if selectedAnchorPosition != nil {
                    VStack(spacing: 12) {
                        Text("Place Object")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        HStack(spacing: 12) {
                            Button("Cube") {
                                if let pos = selectedAnchorPosition {
                                    Task { await placeObject(name: "Cube", at: pos) }
                                    selectedAnchorPosition = nil
                                }
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Sphere") {
                                if let pos = selectedAnchorPosition {
                                    Task { await placeObject(name: "Sphere", at: pos) }
                                    selectedAnchorPosition = nil
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Button("Cancel", role: .cancel) {
                            selectedAnchorPosition = nil
                        }
                        .buttonStyle(.borderless)
                        .tint(.red)
                    }
                    .padding()
                    .glassBackgroundEffect()
                }
            }
            
            Attachment(id: "instruction") {
                if let name = pendingPlacement?.name {
                    VStack {
                        Text("Select an anchor point to place")
                        Text(name).fontWeight(.bold)
                    }
                    .font(.title)
                    .padding()
                    .glassBackgroundEffect()
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    if settings.isPlacementLocked { return }
                    if isScaling || isRotating { return }

                    if grabbedEntity == nil {
                        let target = topMovableEntity(from: value.entity)
                        // Prevent moving plane visualization entities
                        if isPlaneEntity(target) { return }
                        
                        // Check if locked
                        if let id = placedEntities.first(where: { $0.value === target })?.key,
                           lockedEntityIDs.contains(id) {
                            return
                        }
                        
                        grabbedEntity = target
                        grabbedStartWorldPosition = target.position(relativeTo: nil)
                        
                        // Switch to kinematic while dragging so it doesn't fight us
                        if var physics = target.components[PhysicsBodyComponent.self] {
                            physics.mode = .kinematic
                            target.components.set(physics)
                        }
                    }

                    guard let entity = grabbedEntity,
                          let startWorld = grabbedStartWorldPosition else { return }

                    let t = value.translation3D
                    let p0View = Point3D(x: 0, y: 0, z: 0)
                    let p1View = Point3D(x: t.x, y: t.y, z: t.z)
                    let p0World = value.convert(p0View, from: .local, to: .scene)
                    let p1World = value.convert(p1View, from: .local, to: .scene)
                    let worldDelta = SIMD3<Float>(Float(p1World.x - p0World.x),
                                                  Float(p1World.y - p0World.y),
                                                  Float(p1World.z - p0World.z)) * dragSensitivity
                    let targetWorldPos = startWorld + worldDelta
                    
                    // Apply snapping
                    let snappedTargetPos = snapToNearestAnchor(targetWorldPos)
                    
                    let currentPos = entity.position(relativeTo: nil)
                    let alpha = dragSmoothing
                    // Smooth towards the snapped target
                    let smoothedPos = currentPos + (snappedTargetPos - currentPos) * alpha
                    entity.setPosition(smoothedPos, relativeTo: nil)
                }
                .onEnded { _ in
                    // Re-enable dynamic physics when dropped, unless disabled
                    if let entity = grabbedEntity,
                       var physics = entity.components[PhysicsBodyComponent.self] {
                        
                        // Check if physics is disabled for this entity
                        let id = placedEntities.first(where: { $0.value === entity })?.key
                        if let id = id, physicsDisabledEntityIDs.contains(id) {
                            physics.mode = .kinematic
                        } else {
                            physics.mode = .dynamic
                        }
                        entity.components.set(physics)
                    }
                    
                    grabbedEntity = nil
                    grabbedStartWorldPosition = nil
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    // Only scale while an entity is grabbed
                    guard let entity = grabbedEntity else { return }
                    // Initialize baseline once when scaling starts
                    if !isScaling {
                        isScaling = true
                        baselineScale = entity.scale(relativeTo: nil)
                    }
                    guard let base = baselineScale else { return }
                    // Clamp the magnification value to a reasonable range to avoid jumps
                    let factor = Float(value.magnitude)
                    let clamped = max(0.05, min(5.0, factor))
                    let newScale = SIMD3<Float>(base.x * clamped, base.y * clamped, base.z * clamped)
                    entity.setScale(newScale, relativeTo: nil)
                }
                .onEnded { _ in
                    isScaling = false
                    baselineScale = nil
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .onChanged { _ in
                    // Enter rotation mode when a two-hand rotation gesture begins
                    guard let entity = grabbedEntity else { return }
                    if !isRotating {
                        isRotating = true
                        baselineOrientation = entity.orientation(relativeTo: nil)
                        rotationBaselineX = nil // will be set by the horizontal drag below
                    }
                }
                .onEnded { _ in
                    isRotating = false
                    baselineOrientation = nil
                    rotationBaselineX = nil
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isRotating, let entity = grabbedEntity, let base = baselineOrientation else { return }
                    if rotationBaselineX == nil {
                        rotationBaselineX = value.translation.width
                    }
                    let dx = value.translation.width - (rotationBaselineX ?? 0)
                    // Sensitivity factor: tweak as needed for comfortable rotation speed
                    let sensitivity: Float = 0.004
                    let radians = Float(dx) * sensitivity
                    let delta = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
                    entity.setOrientation(delta * base, relativeTo: nil)
                }
                .onEnded { _ in
                    // Do not exit rotation mode here; RotationGesture end will clear it
                    rotationBaselineX = nil
                }
        )
        .simultaneousGesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Interaction Mode: Open Menu if no placement is pending
                    if pendingPlacement == nil {
                        if value.entity.name == "anchor_point" {
                            let pWorld = value.convert(value.location3D, from: .local, to: .scene)
                            print("[PlaceModelView] Tapped anchor point at \(pWorld). Opening menu.")
                            selectedAnchorPosition = pWorld
                        }
                    }
                }
        )
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    // Placement Mode: Place pending object (untargeted catch-all)
                    if let pending = pendingPlacement {
                        let loc = value.location3D
                        let pWorld = SIMD3<Float>(Float(loc.x), Float(loc.y), Float(loc.z))
                        
                        // Try to snap to nearest anchor if within range
                        let targetPos = snapToNearestAnchor(pWorld)
                        
                        print("[PlaceModelView] Tapped at \(pWorld) (snapped: \(targetPos)). Placing pending object.")
                        
                        Task {
                            await placePendingObject(pending, at: targetPos)
                            pendingPlacement = nil
                        }
                    }
                }
        )
        .onReceive(NotificationCenter.default.publisher(for: .placeObjectRequested)) { note in
            guard let userInfo = note.userInfo,
                  let id = userInfo["id"] as? String,
                  let name = userInfo["name"] as? String else { return }
            
            print("[PlaceModelView] placeObjectRequested id=\(id) name=\(name) -> Placing immediately in front")
            
            // Construct pending tuple just to pass to helper, or call helper directly
            let pending = (id: id, name: name, source: userInfo)
            
            // Place in front of user (approx 1m forward, 1.2m high)
            // Note: In ImmersiveSpace, origin is usually feet/floor. 
            let defaultPos = SIMD3<Float>(0, 1.2, -1.0)
            
            Task {
                await placePendingObject(pending, at: defaultPos)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .removeObjectRequested)) { note in
             guard let userInfo = note.userInfo,
                   let id = userInfo["id"] as? String,
                   let entity = placedEntities[id] else { return }

             print("[PlaceModelView] removeObjectRequested id=\(id)")

             // If currently dragging this entity (or a child), cancel the drag first
             if let grabbed = grabbedEntity, (entity === grabbed || grabbed.isDescendant(of: entity)) {
                 grabbedEntity = nil
                 grabbedStartWorldPosition = nil
             }

             // Remove from scene immediately
             entity.removeFromParent()

             // Update state
             placedEntities.removeValue(forKey: id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanSurfacesToggled)) { note in
             guard let userInfo = note.userInfo,
                   let enabled = userInfo["enabled"] as? Bool else { return }
             
             Task {
                 if enabled {
                     print("[PlaceModelView] Starting plane detection...")
                     // Create new provider instance to avoid reuse crash
                     let newProvider = PlaneDetectionProvider(alignments: [.horizontal])
                     planeDetection = newProvider
                     
                     do {
                         try await session.run([newProvider])
                         
                         // Start processing updates
                         await processPlaneUpdates(newProvider)
                     } catch {
                         print("[PlaceModelView] ARKit session failed: \(error)")
                     }
                 } else {
                     print("[PlaceModelView] Stopping plane detection...")
                     session.stop()
                     // Clear visualized planes
                     for entity in planeEntities.values {
                         entity.removeFromParent()
                     }
                     planeEntities.removeAll()
                 }
             }
        }
    }

    // Process plane updates
    @MainActor
    func processPlaneUpdates(_ provider: PlaneDetectionProvider) async {
        for await update in provider.anchorUpdates {
            let anchor = update.anchor
            
            switch update.event {
            case .added, .updated:
                // Update or create visualization
                updatePlane(anchor)
            case .removed:
                // Remove visualization
                if let entity = planeEntities[anchor.id] {
                    entity.removeFromParent()
                    planeEntities.removeValue(forKey: anchor.id)
                }
            }
        }
    }
    private func configureLoadedEntity(_ entity: Entity) {
        // 1. Normalize Scale
        // Get bounds in local space (assuming scale 1)
        let bounds = entity.visualBounds(relativeTo: entity)
        let size = bounds.extents
        let maxDim = max(size.x, max(size.y, size.z))
        
        // If object is too big (>1m) or too small (<5cm), resize to ~30cm
        if maxDim > 1.0 || maxDim < 0.05 {
            print("[PlaceModelView] Resizing entity. Original max dim: \(maxDim)")
            let targetDim: Float = 0.3
            let scaleStr = targetDim / (maxDim > 0 ? maxDim : 0.3)
            entity.setScale([scaleStr, scaleStr, scaleStr], relativeTo: nil)
        }
        
        // 2. Physics & Interaction
        // Important: Recursive generation ensures all child meshes get colliders
        entity.generateCollisionShapes(recursive: true)
        entity.components.set(InputTargetComponent())
        
        // 3. Dynamic Physics
        // User requested physics disabled by default (.kinematic)
        var physics = PhysicsBodyComponent(mode: .kinematic)
        entity.components.set(physics)
    }

    private func loadEntity(from url: URL) async throws -> Entity {
        let ext = url.pathExtension.lowercased()
        if ["usdz", "reality", "usd", "usda", "usdc", "rcproject"].contains(ext) {
            return try await Entity.load(contentsOf: url)
        } else {
            // Use ModelEntity.loadModel for formats like FBX, OBJ, GLB which rely on ModelIO
            // Run in a Task to bridge sync/async if needed, though loadModel is sync
            return try await Task { @MainActor in 
                do {
                    return try ModelEntity.loadModel(contentsOf: url)
                } catch {
                    print("[PlaceModelView] ModelEntity.loadModel failed: \(error). Attempting fallback via MDLAsset.")
                    // Fallback: Load mesh via ModelIO directly
                    let asset = MDLAsset(url: url)
                    if asset.count == 0 {
                        throw error // Re-throw original if MDLAsset also failed to load anything
                    }
                    
                    // Proceed to generate mesh from the first object
                    // Note: This only preserves geometry, typically no materials or full hierarchy
                    // We try to aggregate all objects if possible.
                    var objects: [MDLObject] = []
                    for i in 0..<asset.count {
                        objects.append(asset.object(at: i))
                    }
                    
                    let mesh = try MeshResource.generate(from: objects as! [MeshDescriptor])
                    let material = SimpleMaterial(color: .gray, isMetallic: false) // Fallback material
                    let entity = ModelEntity(mesh: mesh, materials: [material])
                    entity.name = url.lastPathComponent
                    return entity
                }
            }.value
        }
    }

    func placePendingObject(_ pending: (id: String, name: String, source: [AnyHashable: Any]), at worldPosition: SIMD3<Float>) async {
         let id = pending.id
         let name = pending.name
         let userInfo = pending.source
         
         do {
             let entity: Entity
             
             if let bookmark = userInfo["bookmark"] as? Data {
                 var isStale = false
#if os(visionOS)
                 let resolvedURL = try URL(resolvingBookmarkData: bookmark,
                                           options: [],
                                           relativeTo: nil,
                                           bookmarkDataIsStale: &isStale)
                 let ok = resolvedURL.startAccessingSecurityScopedResource()
#else
                 let resolvedURL = try URL(resolvingBookmarkData: bookmark,
                                           options: [.withSecurityScope],
                                           relativeTo: nil,
                                           bookmarkDataIsStale: &isStale)
                 let ok = resolvedURL.startAccessingSecurityScopedResource()
#endif
                 defer { if ok { resolvedURL.stopAccessingSecurityScopedResource() } }
                 print("[PlaceModelView] Loading via bookmark: stale=\(isStale) url=\(resolvedURL)")
                 entity = try await loadEntity(from: resolvedURL)
             } else if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
                 print("[PlaceModelView] Loading via URL string: \(url)")
                 entity = try await loadEntity(from: url)
             } else {
                 print("[PlaceModelView] Loading via generated/bundled entity for name=\(name)")
                 entity = try await makeEntity(for: name)
             }

             // Configure the entity (scale, physics, collision)
             configureLoadedEntity(entity)

             // Position the entity at the tap location
             // Adjust Y using bounds so it sits ON the point rather than origin intersection
             let bounds = entity.visualBounds(relativeTo: entity)
             
             // Scale has been applied to 'entity' transform, but 'visualBounds(relativeTo: entity)' return local unscaled bounds?
             // No, relativeTo: entity ignores the entity's own scale. We need parent-relative bounds to see effect of scale?
             // Actually, simplest is to use the bounds relative to nil (world) but we haven't added it to world yet.
             // Or relative to itself, then multiply by scale.
             let scale = entity.scale(relativeTo: nil).x // uniform
             let bottomY = bounds.min.y * scale
             
             // We want world Y to be worldPosition.y - bottomY (so the bottom sits at worldPosition.y)
             // offset = -bottomY
             
             entity.position = worldPosition + SIMD3<Float>(0, -bottomY + 0.05, 0) // +5cm drop
             
             // Add entity under worldAnchor and store by id

             // Add entity under worldAnchor and store by id
             worldAnchor.addChild(entity)
             placedEntities[id] = entity
             physicsDisabledEntityIDs.insert(id)
         } catch {
             print("[PlaceModelView] Failed to place entity for id=\(id) name=\(name): \(error)")
         }
    }
    func placeObject(name: String, at worldPosition: SIMD3<Float>) async {
        let id = UUID().uuidString
        do {
            print("[PlaceModelView] Placing \(name) at \(worldPosition)")
            let entity = try await makeEntity(for: name)
            
            // Ensure the entity is prepared for interactions and physics
            entity.generateCollisionShapes(recursive: true)
            entity.components.set(InputTargetComponent())
            
            // Dynamic physics body for gravity
            // We set it to kinematic initially if we are placing it precisely?
            // User requested "fall on in if not let go above it", implying dynamic.
            var physics = PhysicsBodyComponent(mode: .dynamic)
            // Adjust properties if needed (mass, friction, etc.)
            entity.components.set(physics)
            
            // Make it stand on the point?
            // If the point is on surface, entity origin is usually center?
            // Cube size 0.2 -> center up by 0.1
            // Sphere radius 0.12 -> center up by 0.12
            // We can adjust based on bounding box.
            
            let bounds = entity.visualBounds(relativeTo: entity)
            let bottomY = bounds.min.y
            let offset = -bottomY
            
            entity.position = worldPosition + SIMD3<Float>(0, offset, 0)
            
            worldAnchor.addChild(entity)
            placedEntities[id] = entity
        } catch {
            print("[PlaceModelView] Failed to place menu object \(name): \(error)")
        }
    }
    
    private func toggleSound(for id: String) {
        guard let entity = placedEntities[id] else { return }

        if let controller = audioControllers[id] {
            // Stop
            controller.stop()
            audioControllers.removeValue(forKey: id)
            print("[PlaceModelView] Stopped audio for \(id)")
        } else {
            // Play
            Task {
                do {
                    // Try to load a sound file named "example_sound.mp3" from the main bundle.
                    // Note: You must add a sound file with this name to your Xcode project for this to work.
                    let resource = try await AudioFileResource(named: "example_sound.mp3", configuration: .init(loadingStrategy: .preload))
                    
                    let controller = entity.prepareAudio(resource)
                    controller.gain = -5.0 // Slightly lower volume
                    controller.play()
                    audioControllers[id] = controller
                    print("[PlaceModelView] Started audio for \(id)")
                } catch {
                    print("[PlaceModelView] Failed to load example_sound.mp3: \(error). Please add an audio file with this name to your main application bundle.")
                }
            }
        }
    }
}

