import SwiftUI
import RealityKit
import RealityKitContent
import ModelIO

enum ModelFactory {
    @MainActor
    static func makeEntity(for name: String) async throws -> Entity {
        let lower = name.lowercased()
        let url = URL(fileURLWithPath: lower)
        let supportedExtensions = ["glb", "gltf", "obj", "fbx", "usd", "usdc", "usda", "usdz"]
        if supportedExtensions.contains(url.pathExtension) {
            print("[ModelFactory] Loading external 3D model: \(name)")
            if url.pathExtension == "usdz" || url.pathExtension == "usd" || url.pathExtension == "usdc" || url.pathExtension == "usda" {
                let e = try await Entity.load(contentsOf: url)
                e.generateCollisionShapes(recursive: true)
                e.components.set(InputTargetComponent())
                return e
            } else {
                let entity = try ModelEntity.loadModel(contentsOf: url)
                entity.components.set(InputTargetComponent())
                entity.generateCollisionShapes(recursive: true)
                return entity
            }
        }
        
        switch name {
        case "Cube":
            let size: Float = 0.2
            let mesh = MeshResource.generateBox(size: size)
            let mat = SimpleMaterial(color: .red, isMetallic: false)
            let e = ModelEntity(mesh: mesh, materials: [mat])
            let shape = ShapeResource.generateBox(size: [size, size, size])
            e.components.set(CollisionComponent(shapes: [shape]))
            e.components.set(InputTargetComponent())
            return e
        case "Sphere":
            let radius: Float = 0.12
            let mesh = MeshResource.generateSphere(radius: radius)
            let mat = SimpleMaterial(color: .blue, isMetallic: false)
            let e = ModelEntity(mesh: mesh, materials: [mat])
            let shape = ShapeResource.generateSphere(radius: radius)
            e.components.set(CollisionComponent(shapes: [shape]))
            e.components.set(InputTargetComponent())
            return e
        case "Cone":
            let height: Float = 0.2
            let radius: Float = 0.1
            let mesh = MeshResource.generateCone(height: height, radius: radius)
            let mat = SimpleMaterial(color: .green, isMetallic: false)
            let e = ModelEntity(mesh: mesh, materials: [mat])

            let shape = ShapeResource.generateBox(width: radius*2, height: height, depth: radius*2)
            e.components.set(CollisionComponent(shapes: [shape]))
            e.components.set(InputTargetComponent())
            return e
        case "Cylinder":
            let height: Float = 0.2
            let radius: Float = 0.1
            let mesh = MeshResource.generateCylinder(height: height, radius: radius)
            let mat = SimpleMaterial(color: .yellow, isMetallic: false)
            let e = ModelEntity(mesh: mesh, materials: [mat])

            let shape = ShapeResource.generateCapsule(height: height, radius: radius)
            e.components.set(CollisionComponent(shapes: [shape]))
            e.components.set(InputTargetComponent())
            return e
        case "Plane":
            let width: Float = 0.3
            let depth: Float = 0.3
            let mesh = MeshResource.generatePlane(width: width, depth: depth)
            let mat = SimpleMaterial(color: .gray, isMetallic: false)
            let e = ModelEntity(mesh: mesh, materials: [mat])
            
            let shape = ShapeResource.generateBox(width: width, height: 0.01, depth: depth)
            e.components.set(CollisionComponent(shapes: [shape]))
            e.components.set(InputTargetComponent())
            return e
        default:
            if let e = try? await Entity(named: "Small_bottle", in: realityKitContentBundle) {
                e.setScale([0.01, 0.01, 0.01], relativeTo: nil)
                if !e.components.has(CollisionComponent.self) {
                    e.generateCollisionShapes(recursive: true)
                }
                e.components.set(InputTargetComponent())
                return e
            } else {
                print("[ModelFactory] Bundled asset missing; using fallback.")
                let size: Float = 0.15
                let mesh = MeshResource.generateBox(size: size)
                let mat = SimpleMaterial(color: .gray, isMetallic: false)
                let e = ModelEntity(mesh: mesh, materials: [mat])
                let shape = ShapeResource.generateBox(size: [size, size, size])
                e.components.set(CollisionComponent(shapes: [shape]))
                e.components.set(InputTargetComponent())
                return e
            }
        }
    }
    
    @MainActor
    static func loadEntity(from url: URL) async throws -> Entity {
        let ext = url.pathExtension.lowercased()
        if ["usdz", "reality", "usd", "usda", "usdc", "rcproject"].contains(ext) {
            return try await Entity.load(contentsOf: url)
        } else {

             do {
                return try ModelEntity.loadModel(contentsOf: url)
            } catch {
                print("[ModelFactory] ModelEntity.loadModel failed: \(error). Attempting fallback.")
                let asset = MDLAsset(url: url)
                if asset.count == 0 {
                    throw error
                }
                var objects: [MDLObject] = []
                for i in 0..<asset.count {
                    objects.append(asset.object(at: i))
                }
                let mesh = try MeshResource.generate(from: objects as! [MeshDescriptor])
                let material = SimpleMaterial(color: .gray, isMetallic: false)
                let entity = ModelEntity(mesh: mesh, materials: [material])
                entity.name = url.lastPathComponent
                return entity
            }
        }
    }
    
    @MainActor
    static func configureLoadedEntity(_ entity: Entity) {
        let bounds = entity.visualBounds(relativeTo: entity)
        let size = bounds.extents
        let maxDim = max(size.x, max(size.y, size.z))
        
        if maxDim > 1.0 || maxDim < 0.05 {
            let targetDim: Float = 0.3
            let scaleStr = targetDim / (maxDim > 0 ? maxDim : 0.3)
            entity.setScale([scaleStr, scaleStr, scaleStr], relativeTo: nil)
        }
        

        if let animation = entity.availableAnimations.first {
            entity.playAnimation(animation.repeat())
        }
        
        if entity.components.has(ModelComponent.self) {
            entity.generateCollisionShapes(recursive: true)
        } else {
            let bounds = entity.visualBounds(relativeTo: entity)
            let shape = ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)
            entity.components.set(CollisionComponent(shapes: [shape]))
        }
        
        entity.components.set(InputTargetComponent())
        let physics = PhysicsBodyComponent(mode: .kinematic)
        entity.components.set(physics)
    }
    
    static func addAppliedText(_ text: String, to entity: Entity) {
        let modelBounds = entity.visualBounds(relativeTo: entity)
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
        
        let parentScale = entity.scale(relativeTo: nil)
        let safeScaleX = parentScale.x != 0 ? parentScale.x : 1.0
        let safeScaleY = parentScale.y != 0 ? parentScale.y : 1.0
        let safeScaleZ = parentScale.z != 0 ? parentScale.z : 1.0
        
        textEntity.scale = SIMD3<Float>(1.0 / safeScaleX, 1.0 / safeScaleY, 1.0 / safeScaleZ)
        let meshBounds = textEntity.model?.mesh.bounds.extents ?? .zero
        
        textEntity.position = SIMD3(
            -(meshBounds.x * textEntity.scale.x) / 2,
            modelBounds.max.y + (0.05 * textEntity.scale.y),
            0
        )
        entity.addChild(textEntity)
    }
}
