import SwiftUI
import RealityKit
import RealityKitContent

struct ModelView: View {
    @State private var model: Entity?

    var body: some View {
        RealityView { content in
            
            // --- 3D Modell laden (USDZ in RealityKitContent) ---
            let entity = try! await Entity(named: "Small_bottle",
                                           in: realityKitContentBundle)

            entity.generateCollisionShapes(recursive: true)
            entity.setScale([0.01,0.01,0.01], relativeTo: nil)
            entity.position = [0, 0, 0.15]
            content.add(entity)
            // Debug Cube
            let cube = ModelEntity(mesh: .generateBox(size: 0.2))
            cube.position = [0, 0, 0]
            cube.model?.materials = [SimpleMaterial(color: .red, isMetallic: false)]
            //content.add(cube)
            model = entity
        }
    }
}
