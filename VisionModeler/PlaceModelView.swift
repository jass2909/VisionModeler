// Accessibility adaptations included:
// - High Contrast mode toggle that restyles panels and text for improved readability
// - Larger hit zones on buttons to aid motor accessibility

import SwiftUI
import RealityKit
import RealityKitContent

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

    private func makeEntity(for name: String) async throws -> Entity {
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
            // Placeholder: try to load bundled bottle; if missing, fall back to a primitive box
            if let e = try? await Entity(named: "Small_bottle", in: realityKitContentBundle) {
                e.setScale([0.01, 0.01, 0.01], relativeTo: nil)
                e.generateCollisionShapes(recursive: true)
                e.components.set(InputTargetComponent())
                return e
            } else {
                print("[PlaceModelView] Bundled asset 'Small_bottle' not found; using primitive fallback.")
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
                    Button(action: {
                        // Post removal request
                        NotificationCenter.default.post(
                            name: Notification.Name("removeObjectRequested"),
                            object: nil,
                            userInfo: ["id": id]
                        )
                    }) {
                        Label("Remove", systemImage: "trash")
                            .labelStyle(.iconOnly)
                            .padding(12)
                            .glassBackgroundEffect()
                    }
                    // Optional: Make it scale nicely on hover/focus is handled by system with standard controls
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
                        grabbedEntity = target
                        grabbedStartWorldPosition = target.position(relativeTo: nil)
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
                    let currentPos = entity.position(relativeTo: nil)
                    let alpha = dragSmoothing
                    let smoothedPos = currentPos + (targetWorldPos - currentPos) * alpha
                    entity.setPosition(smoothedPos, relativeTo: nil)
                }
                .onEnded { _ in
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
        .onReceive(NotificationCenter.default.publisher(for: .placeObjectRequested)) { note in
            guard let userInfo = note.userInfo,
                  let id = userInfo["id"] as? String,
                  let name = userInfo["name"] as? String else { return }
            
            print("[PlaceModelView] placeObjectRequested id=\(id) name=\(name)")
            
            Task {
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
                        entity = try await Entity.load(contentsOf: resolvedURL)
                    } else if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
                        print("[PlaceModelView] Loading via URL string: \(url)")
                        entity = try await Entity.load(contentsOf: url)
                    } else {
                        print("[PlaceModelView] Loading via generated/bundled entity for name=\(name)")
                        entity = try await make
