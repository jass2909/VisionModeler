import SwiftUI
import ModelIO
import RealityKit
import RealityKitContent
import ARKit
import UniformTypeIdentifiers

struct PlaceModelView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismissImmersiveSpace) var dismiss

    @State var worldAnchor = AnchorEntity(.world(transform: matrix_identity_float4x4))
    @State var rootEntity = Entity()
    @State var placedEntities: [String: Entity] = [:]

    @State var lockedEntityIDs: Set<String> = []
    @State var physicsDisabledEntityIDs: Set<String> = []

    @State private var grabbedEntity: Entity? = nil
    @State private var grabbedStartWorldPosition: SIMD3<Float>? = nil

    @State private var isScaling: Bool = false
    @State private var baselineScale: SIMD3<Float>? = nil
    @State private var isRotating: Bool = false
    @State private var baselineOrientation: simd_quatf? = nil
    @State private var rotationBaselineX: CGFloat? = nil

    @State private var updateSubscription: EventSubscription? = nil

    @State private var placeObserver: NSObjectProtocol?
    @State private var removeObserver: NSObjectProtocol?

    @State var session = ARKitSession()
    @State var planeDetection = PlaneDetectionProvider(alignments: [.horizontal])
    @State var planeEntities: [UUID: Entity] = [:]

    @State private var isScanningSubscribed = false
    
    @State var pendingPlacement: (id: String, name: String, source: [AnyHashable: Any])? = nil
    
    @State var selectedAnchorPosition: SIMD3<Float>? = nil
    
    @State var audioControllers: [String: AudioPlaybackController] = [:]
    @State var entitySounds: [String: URL] = [:]
    @State var colorPickerOpenForID: String? = nil
    
    @State var entitySources: [String: URL] = [:]
    @State var entityColors: [String: UIColor] = [:]
    @State var entityAnimationStates: [String: Bool] = [:]
    @State private var currentSceneEntity: Entity? = nil

    private let dragSensitivity: Float = 1
    private let dragSmoothing: Float = 0.2

    var body: some View {
        RealityView { content, attachments in
            worldAnchor.addChild(rootEntity)
            content.add(worldAnchor)
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
            }
        } update: { content, attachments in
            for (id, entity) in placedEntities {
                if let attachmentEntity = attachments.entity(for: id) {
                    if attachmentEntity.parent == nil {
                        entity.addChild(attachmentEntity)
                        
                        if !entity.components.has(HoverEffectComponent.self) {
                            entity.components.set(HoverEffectComponent())
                        }
                        
                        let parentWorldScale = entity.scale(relativeTo: nil)
                        let invScale = SIMD3<Float>(
                            1.0 / (parentWorldScale.x > 1e-4 ? parentWorldScale.x : 1.0),
                            1.0 / (parentWorldScale.y > 1e-4 ? parentWorldScale.y : 1.0),
                            1.0 / (parentWorldScale.z > 1e-4 ? parentWorldScale.z : 1.0)
                        )
                        attachmentEntity.setScale(invScale, relativeTo: entity)
                        
                        let worldBounds = entity.visualBounds(relativeTo: nil)
                        let worldTopY = worldBounds.max.y
                        let entityWorldPos = entity.position(relativeTo: nil)
                        
                        var targetWorldPos = entityWorldPos
                        targetWorldPos.y = worldTopY + 0.15
                        
                        attachmentEntity.setPosition(targetWorldPos, relativeTo: nil)
                        attachmentEntity.components.set(BillboardComponent())
                    }
                }
            }

            
            if let navAttachment = attachments.entity(for: "sceneNavigation") {
                if currentSceneEntity != nil {
                    if navAttachment.parent == nil {
                        worldAnchor.addChild(navAttachment)
                        navAttachment.position = SIMD3(0, 1.0, -0.5)
                    }
                } else {
                    navAttachment.removeFromParent()
                }
            }
        } attachments: {
            ForEach(Array(placedEntities.keys), id: \.self) { id in
                Attachment(id: id) {
                    ObjectControlView(
                        id: id,
                        isLocked: lockedEntityIDs.contains(id),
                        isPhysicsDisabled: physicsDisabledEntityIDs.contains(id),
                        isPlaying: audioControllers[id] != nil,
                        isAnimating: entityAnimationStates[id] ?? false,
                        isColorPickerOpen: colorPickerOpenForID == id,
                        onRemove: {
                            NotificationCenter.default.post(
                                name: Notification.Name("removeObjectRequested"),
                                object: nil,
                                userInfo: ["id": id, "deleteFromLibrary": true]
                            )
                        },
                        onToggleLock: {
                            if lockedEntityIDs.contains(id) {
                                lockedEntityIDs.remove(id)
                            } else {
                                lockedEntityIDs.insert(id)
                            }
                        },
                        onTogglePhysics: {
                            if let entity = placedEntities[id], var physics = entity.components[PhysicsBodyComponent.self] {
                                if physicsDisabledEntityIDs.contains(id) {
                                    physicsDisabledEntityIDs.remove(id)
                                    physics.mode = .dynamic
                                } else {
                                    physicsDisabledEntityIDs.insert(id)
                                    physics.mode = .kinematic
                                }
                                entity.components.set(physics)
                            }
                        },
                        onToggleSound: {
                            toggleSound(for: id)
                        },
                        onToggleAnimation: {
                            toggleAnimation(for: id)
                        },
                        onToggleColorPicker: {
                            if colorPickerOpenForID == id {
                                colorPickerOpenForID = nil
                            } else {
                                colorPickerOpenForID = id
                            }
                        },
                        onPrepareExport: {
                            prepareExport(for: id)
                        },
                        onColorSelected: { color in
                            applyColor(color, to: id)
                        }
                    )
                }
            }
            
            Attachment(id: "anchorMenu") {
                if let _ = selectedAnchorPosition {
                    AnchorMenuView(
                        onPlaceCube: {
                            if let pos = selectedAnchorPosition {
                                Task { await placeObject(name: "Cube", at: pos) }
                                selectedAnchorPosition = nil
                            }
                        },
                        onPlaceSphere: {
                            if let pos = selectedAnchorPosition {
                                Task { await placeObject(name: "Sphere", at: pos) }
                                selectedAnchorPosition = nil
                            }
                        },
                        onCancel: {
                            selectedAnchorPosition = nil
                        }
                    )
                }
            }
            
            Attachment(id: "instruction") {
                if let name = pendingPlacement?.name {
                    InstructionView(name: name)
                }
            }
            
            Attachment(id: "sceneNavigation") {
                if currentSceneEntity != nil {
                    SceneNavigationControl(
                        onMove: { delta in
                            moveRoot(delta)
                        },
                        onRotate: { angle in
                            rotateRoot(angle)
                        },
                        onReset: {
                            resetRoot()
                        }
                    )
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
                        if isPlaneEntity(target) { return }
                        
                        if let id = placedEntities.first(where: { $0.value === target })?.key,
                           lockedEntityIDs.contains(id) {
                            return
                        }
                        
                        grabbedEntity = target
                        grabbedStartWorldPosition = target.position(relativeTo: nil)
                        
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
                    
                    let snappedTargetPos = snapToNearestAnchor(targetWorldPos)
                    
                    let currentPos = entity.position(relativeTo: nil)
                    let alpha = dragSmoothing
                    let smoothedPos = currentPos + (snappedTargetPos - currentPos) * alpha
                    entity.setPosition(smoothedPos, relativeTo: nil)
                }
                .onEnded { _ in
                    let entityToRestore = grabbedEntity
                    grabbedEntity = nil
                    grabbedStartWorldPosition = nil
                    
                    if isScaling || isRotating { return }
                    
                    if let entity = entityToRestore,
                       var physics = entity.components[PhysicsBodyComponent.self] {
                        
                        let id = placedEntities.first(where: { $0.value === entity })?.key
                        if let id = id, physicsDisabledEntityIDs.contains(id) {
                            physics.mode = .kinematic
                        } else {
                            physics.mode = .dynamic
                        }
                        entity.components.set(physics)
                    }
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    let entity = topMovableEntity(from: value.entity)
                    if isPlaneEntity(entity) { return }
                    if let id = placedEntities.first(where: { $0.value === entity })?.key,
                       lockedEntityIDs.contains(id) {
                        return
                    }

                    if !isScaling {
                        isScaling = true
                        baselineScale = entity.scale(relativeTo: nil)
                        
                        if var physics = entity.components[PhysicsBodyComponent.self] {
                            physics.mode = .kinematic
                            entity.components.set(physics)
                        }
                    }
                    guard let base = baselineScale else { return }
                    let factor = Float(value.magnification)
                    let clamped = max(0.05, min(5.0, factor))
                    let newScale = base * clamped
                    entity.setScale(newScale, relativeTo: nil)
                }
                .onEnded { value in
                    isScaling = false
                    baselineScale = nil
                    
                    if grabbedEntity == nil {
                        let entity = topMovableEntity(from: value.entity)
                        if var physics = entity.components[PhysicsBodyComponent.self] {
                            let id = placedEntities.first(where: { $0.value === entity })?.key
                            if let id = id, physicsDisabledEntityIDs.contains(id) {
                                physics.mode = .kinematic
                            } else {
                                physics.mode = .dynamic
                            }
                            entity.components.set(physics)
                        }
                    }
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .onChanged { _ in
                    guard let entity = grabbedEntity else { return }
                    if !isRotating {
                        isRotating = true
                        baselineOrientation = entity.orientation(relativeTo: nil)
                        rotationBaselineX = nil
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
                    let sensitivity: Float = 0.004
                    let radians = Float(dx) * sensitivity
                    let delta = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
                    entity.setOrientation(delta * base, relativeTo: nil)
                }
                .onEnded { _ in
                    rotationBaselineX = nil
                }
        )
        .simultaneousGesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
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
                    if let pending = pendingPlacement {
                        let loc = value.location3D
                        let pWorld = SIMD3<Float>(Float(loc.x), Float(loc.y), Float(loc.z))
                        
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
            
            let pending = (id: id, name: name, source: userInfo)
            let defaultPos = SIMD3<Float>(0, 1.2, -1.0)
            
            Task {
                await placePendingObject(pending, at: defaultPos)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .placeSceneRequested)) { note in
            guard let userInfo = note.userInfo else { return }
            print("[PlaceModelView] Received placeSceneRequested")
            
            Task {
                // Remove existing scene
                if let existing = currentSceneEntity {
                    existing.removeFromParent()
                    currentSceneEntity = nil
                }
                
                var entity: Entity?
                if let bookmark = userInfo["bookmark"] as? Data {
                     var isStale = false
                     if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                         let ok = url.startAccessingSecurityScopedResource()
                         defer { if ok { url.stopAccessingSecurityScopedResource() } }
                         entity = try? await ModelFactory.loadEntity(from: url)
                     }
                } else if let urlStr = userInfo["url"] as? String, let url = URL(string: urlStr) {
                    entity = try? await ModelFactory.loadEntity(from: url)
                }
                
                if let scene = entity {
                    scene.name = "SceneRoot"
                    scene.position = .zero
                    // Default orientation etc.
                    
                    rootEntity.addChild(scene)
                    currentSceneEntity = scene
                    print("[PlaceModelView] Scene placed.")
                } else {
                    print("[PlaceModelView] Failed to load scene entity")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .removeObjectRequested)) { note in
             guard let userInfo = note.userInfo,
                   let id = userInfo["id"] as? String,
                   let entity = placedEntities[id] else { return }

             print("[PlaceModelView] removeObjectRequested id=\(id)")

             if let grabbed = grabbedEntity, (entity === grabbed || grabbed.isDescendant(of: entity)) {
                 grabbedEntity = nil
                 grabbedStartWorldPosition = nil
             }

             entity.removeFromParent()
             placedEntities.removeValue(forKey: id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanSurfacesToggled)) { note in
             guard let userInfo = note.userInfo,
                   let enabled = userInfo["enabled"] as? Bool else { return }
             
             Task {
                 if enabled {
                     print("[PlaceModelView] Starting plane detection...")
                     let newProvider = PlaneDetectionProvider(alignments: [.horizontal])
                     planeDetection = newProvider
                     
                     do {
                         try await session.run([newProvider])
                         await processPlaneUpdates(newProvider)
                     } catch {
                         print("[PlaceModelView] ARKit session failed: \(error)")
                     }
                 } else {
                     print("[PlaceModelView] Stopping plane detection...")
                     session.stop()
                    for entity in planeEntities.values {
                         entity.removeFromParent()
                     }
                     planeEntities.removeAll()
                 }
             }
        }
    }
}
