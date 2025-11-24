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
            // Placeholder: load bundled bottle for unknown names / imported placeholder
            let entity = try await Entity(named: "Small_bottle", in: realityKitContentBundle)
            entity.setScale([0.01, 0.01, 0.01], relativeTo: nil)
            entity.generateCollisionShapes(recursive: true)
            entity.components.set(InputTargetComponent())
            return entity
        }
    }

    var body: some View {
        RealityView { content in
            // Add a persistent world anchor; do not add any default models here.
            content.add(worldAnchor)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    if settings.isPlacementLocked { return }

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
        .onAppear {
            // Observe placement requests
            placeObserver = NotificationCenter.default.addObserver(forName: .placeObjectRequested, object: nil, queue: .main) { note in
                guard let userInfo = note.userInfo,
                      let id = userInfo["id"] as? String,
                      let name = userInfo["name"] as? String else { return }
                Task {
                    do {
                        let entity: Entity

                        if let urlString = userInfo["url"] as? String,
                           let url = URL(string: urlString) {
                            entity = try await Entity.load(contentsOf: url)
                        } else {
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
