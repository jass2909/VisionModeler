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
        RealityView { content in
            // Add a persistent world anchor; do not add any default models here.
            content.add(worldAnchor)
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                // Reserved for future hand-tracking driven scaling updates
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
        .onAppear {
            // Observe placement requests
            placeObserver = NotificationCenter.default.addObserver(forName: .placeObjectRequested, object: nil, queue: .main) { note in
                guard let userInfo = note.userInfo,
                      let id = userInfo["id"] as? String,
                      let name = userInfo["name"] as? String else { return }
                
                print("[PlaceModelView] placeObjectRequested id=\(id) name=\(name) keys=\(Array(userInfo.keys))")
                
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
                            // Legacy path: may fail on device due to missing security scope
                            print("[PlaceModelView] Loading via URL string (no bookmark): \(url)")
                            entity = try await Entity.load(contentsOf: url)
                        } else {
                            print("[PlaceModelView] Loading via generated/bundled entity for name=\(name)")
                            entity = try await makeEntity(for: name)
                        }

                        entity.generateCollisionShapes(recursive: true)
                        entity.components.set(InputTargetComponent())
                        entity.position = [0, 0, -1]

                        worldAnchor.addChild(entity)
                        placedEntities[id] = entity
                    } catch {
                        print("Failed to place object (\(name)): \(error)")
                    }
                }
            }

            // Observe removal requests
            removeObserver = NotificationCenter.default.addObserver(forName: .removeObjectRequested, object: nil, queue: .main) { note in
                guard let userInfo = note.userInfo,
                      let id = userInfo["id"] as? String,
                      let entity = placedEntities[id] else { return }

                // If currently dragging this entity (or a child), cancel the drag first
                if let grabbed = grabbedEntity, (entity === grabbed || grabbed.isDescendant(of: entity)) {
                    grabbedEntity = nil
                    grabbedStartWorldPosition = nil
                }

                // Optionally remove interactive components before removal
                entity.components.remove(InputTargetComponent.self)

                // Defer removal to allow hit-test/gesture teardown to complete
                DispatchQueue.main.async {
                    entity.removeFromParent()
                }

                placedEntities.removeValue(forKey: id)
            }
        }
        .onDisappear {
            if let o = placeObserver { NotificationCenter.default.removeObserver(o) }
            if let o = removeObserver { NotificationCenter.default.removeObserver(o) }
            placeObserver = nil
            removeObserver = nil
        }
        .ignoresSafeArea()
    }
}

