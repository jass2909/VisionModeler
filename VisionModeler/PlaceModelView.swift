import SwiftUI
import RealityKit
import RealityKitContent

struct PlaceModelView: View {
    @Environment(\.dismissImmersiveSpace) var dismiss
    @State private var model: Entity?
    @State private var grabbedEntity: Entity? = nil
    @State private var grabbedStartWorldPosition: SIMD3<Float>? = nil

    private let dragSensitivity: Float = 1
    private let dragSmoothing: Float = 0.2

    private func isDescendant(_ child: Entity, of ancestor: Entity) -> Bool {
        var current: Entity? = child
        while let c = current {
            if c === ancestor { return true }
            current = c.parent
        }
        return false
    }

    var body: some View {
        RealityView { content in
            let entity = try! await Entity(named: "Small_bottle",
                                           in: realityKitContentBundle)
            
            entity.setScale([0.01,0.01,0.01], relativeTo: nil)
            entity.position = [0, 0, -1]   // 1m vor dir
            
            entity.generateCollisionShapes(recursive: true)
            entity.components.set(InputTargetComponent())
            content.add(entity)
            model = entity
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    if grabbedEntity == nil {
                        let target: Entity
                        if let model, isDescendant(value.entity, of: model) {
                            target = model
                        } else {
                            // Move the tapped entity's root
                            var root = value.entity
                            while let p = root.parent { root = p }
                            target = root
                        }
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
    }
}

