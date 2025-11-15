import SwiftUI
import RealityKit
import RealityKitContent

struct PlaceModelView: View {
    @Environment(\.dismissImmersiveSpace) var dismiss
    
    var body: some View {
        RealityView { content in
            let entity = try! await Entity(named: "Small_bottle",
                                           in: realityKitContentBundle)
            
            entity.setScale([0.01,0.01,0.01], relativeTo: nil)
            entity.position = [0, 0, -1]   // 1m vor dir
            
            entity.generateCollisionShapes(recursive: true)
            content.add(entity)
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    value.entity.position = value.convert(value.location3D, from: .local, to: .scene)
                }
        )
    }
}
