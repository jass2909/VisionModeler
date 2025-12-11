import SwiftUI
import RealityKit
import ARKit
import RealityKitContent

extension PlaceModelView {
    
    func topMovableEntity(from entity: Entity) -> Entity {
        var current: Entity = entity
        while let parent = current.parent, parent !== worldAnchor {
            current = parent
        }
        return current
    }
    
    func isPlaneEntity(_ entity: Entity) -> Bool {
        for plane in planeEntities.values {
            if entity === plane || entity.isDescendant(of: plane) {
                return true
            }
        }
        return false
    }
    
    func updatePlane(_ anchor: PlaneAnchor) {
        let color = UIColor.lightGray.withAlphaComponent(0.1)
        let material = UnlitMaterial(color: color)
        
        let parentEntity: Entity
        if let existing = planeEntities[anchor.id] {
            parentEntity = existing
        } else {
            parentEntity = Entity()
            worldAnchor.addChild(parentEntity)
            planeEntities[anchor.id] = parentEntity
        }
        
        parentEntity.transform = Transform(matrix: anchor.originFromAnchorTransform)
        
        let visualName = "visual_plane"
        let visualEntity: ModelEntity
        if let child = parentEntity.findEntity(named: visualName) as? ModelEntity {
            visualEntity = child
        } else {
            visualEntity = ModelEntity()
            visualEntity.name = visualName
            parentEntity.addChild(visualEntity)
        }
        
        let width = anchor.geometry.extent.width
        let depth = anchor.geometry.extent.height
        let mesh = MeshResource.generatePlane(width: width, depth: depth)
        visualEntity.model = ModelComponent(mesh: mesh, materials: [material])
        visualEntity.position = .zero
        
        if !visualEntity.components.has(InputTargetComponent.self) {
            visualEntity.generateCollisionShapes(recursive: false)
            visualEntity.components.set(InputTargetComponent())
            visualEntity.components.set(PhysicsBodyComponent(mode: .static))
        }
        
        let anchorsRootName = "anchor_points_root"
        let anchorsRoot: Entity
        if let child = parentEntity.findEntity(named: anchorsRootName) {
            anchorsRoot = child
            anchorsRoot.children.removeAll()
        } else {
            anchorsRoot = Entity()
            anchorsRoot.name = anchorsRootName
            parentEntity.addChild(anchorsRoot)
        }
        anchorsRoot.position = .zero
        
        let density: Float = 0.1
        let gridWidth = anchor.geometry.extent.width
        let gridDepth = anchor.geometry.extent.height
        
        let cols = Int(gridWidth / density)
        let rows = Int(gridDepth / density)
        
        let pointMesh = MeshResource.generateSphere(radius: 0.010)
        let pointMat = UnlitMaterial(color: .white)
        
        let startX = -(Float(cols) * density) / 2.0
        let startZ = -(Float(rows) * density) / 2.0
        
        for r in 0...rows {
            for c in 0...cols {
                let x = startX + Float(c) * density
                let z = startZ + Float(r) * density
                
                if abs(x) <= gridWidth/2 && abs(z) <= gridDepth/2 {
                    let pointEntity = ModelEntity(mesh: pointMesh, materials: [pointMat])
                    pointEntity.position = SIMD3<Float>(x, 0.01, z)
                    pointEntity.name = "anchor_point"
                    
                    pointEntity.generateCollisionShapes(recursive: false)
                    pointEntity.components.set(InputTargetComponent())
                    pointEntity.components.set(HoverEffectComponent())
                    
                    anchorsRoot.addChild(pointEntity)
                }
            }
        }
    }
    
    func snapToNearestAnchor(_ worldPos: SIMD3<Float>) -> SIMD3<Float> {
        let density: Float = 0.1
        var bestPos = worldPos
        
        for plane in planeEntities.values {
            let localPos = plane.convert(position: worldPos, from: nil)
            let bounds = plane.visualBounds(relativeTo: plane)
            let width = bounds.extents.x
            let depth = bounds.extents.z
            
            if abs(localPos.x) <= (width / 2.0 + density) && abs(localPos.z) <= (depth / 2.0 + density) {
                let cols = Int(width / density)
                let rows = Int(depth / density)
                let startX = -(Float(cols) * density) / 2.0
                let startZ = -(Float(rows) * density) / 2.0
                
                let c = round((localPos.x - startX) / density)
                let r = round((localPos.z - startZ) / density)
                
                if c >= 0 && c <= Float(cols) && r >= 0 && r <= Float(rows) {
                    let snappedLocalX = startX + c * density
                    let snappedLocalZ = startZ + r * density
                    let snappedLocal = SIMD3<Float>(snappedLocalX, localPos.y, snappedLocalZ)
                    bestPos = plane.convert(position: snappedLocal, to: nil)
                    return bestPos
                }
            }
        }
        return bestPos
    }

    func toggleSound(for id: String) {
        guard let entity = placedEntities[id] else { return }

        if let controller = audioControllers[id] {
            controller.stop()
            audioControllers.removeValue(forKey: id)
            print("[PlaceModelView] Stopped audio for \(id)")
        } else {
            Task {
                do {
                    let resource: AudioFileResource
                    if let soundURL = entitySounds[id] {
                         let accessing = soundURL.startAccessingSecurityScopedResource()
                         defer { if accessing { soundURL.stopAccessingSecurityScopedResource() } }
                         print("[PlaceModelView] Loading assigned sound: \(soundURL)")
                         resource = try await AudioFileResource(contentsOf: soundURL, configuration: .init(loadingStrategy: .preload))
                    } else {
                        resource = try await AudioFileResource(named: "example_sound.mp3", configuration: .init(loadingStrategy: .preload))
                    }
                    
                    let controller = entity.prepareAudio(resource)
                    controller.gain = -5.0
                    controller.play()
                    audioControllers[id] = controller
                    print("[PlaceModelView] Started audio for \(id)")
                } catch {
                    print("[PlaceModelView] Failed to load audio: \(error)")
                }
            }
        }
    }

    func applyColor(_ color: UIColor, to id: String) {
        guard let root = placedEntities[id] else { return }
        
        entityColors[id] = color
        
        func setMaterial(_ entity: Entity) {
            if let modelEntity = entity as? ModelEntity, var modelComp = modelEntity.model {
               let material = SimpleMaterial(color: color, isMetallic: false)
               modelComp.materials = Array(repeating: material, count: modelComp.materials.count)
               modelEntity.model = modelComp
            }
            
            for child in entity.children {
                setMaterial(child)
            }
        }
        setMaterial(root)
    }

    func prepareExport(for id: String) {
        if let source = entitySources[id] {
            if let color = entityColors[id] {
                Task {
                    if let exportedURL = try? await ExportManager.exportWithColor(source: source, color: color) {
                         NotificationCenter.default.post(
                            name: Notification.Name("exportObjectRequested"),
                            object: nil,
                            userInfo: [
                                "url": exportedURL,
                                "filename": source.deletingPathExtension().lastPathComponent + "_colored"
                            ]
                        )
                    } else {
                         NotificationCenter.default.post(
                            name: Notification.Name("exportObjectRequested"),
                            object: nil,
                            userInfo: [
                                "url": source,
                                "filename": source.deletingPathExtension().lastPathComponent
                            ]
                        )
                    }
                }
            } else {
                NotificationCenter.default.post(
                    name: Notification.Name("exportObjectRequested"),
                    object: nil,
                    userInfo: [
                        "url": source,
                        "filename": source.deletingPathExtension().lastPathComponent
                    ]
                )
            }
        } else if let entity = placedEntities[id] {
            if let generated = try? ExportManager.generateUSDZ(for: entity) {
                 NotificationCenter.default.post(
                    name: Notification.Name("exportObjectRequested"),
                    object: nil,
                    userInfo: [
                        "url": generated,
                        "filename": "ExportedModel"
                    ]
                )
            } else {
                print("[PlaceModelView] Cannot export: source not found and generation failed.")
            }
        }
    }
    
    func placeObject(name: String, at worldPosition: SIMD3<Float>) async {
        let id = UUID().uuidString
        do {
            print("[PlaceModelView] Placing \(name) at \(worldPosition)")
            let entity = try await ModelFactory.makeEntity(for: name)
            
            var physics = PhysicsBodyComponent(mode: .dynamic)
            entity.components.set(physics)
            
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
    
    func placePendingObject(_ pending: (id: String, name: String, source: [AnyHashable: Any]), at worldPosition: SIMD3<Float>) async {
         let id = pending.id
         let name = pending.name
         let userInfo = pending.source
         
         do {
             var entity: Entity
             
             if let bookmark = userInfo["bookmark"] as? Data {
                 entity = try await ModelFactory.makeEntity(for: name) // Fallback logic? No, load via bookmark.
                 // Actually ModelFactory doesn't do bookmark logic directly, we need to resolve it.
                 // Wait, I should have put the bookmark resolution in ModelFactory or here.
                 // I'll put it in ModelFactory.loadEntity but it takes URL.
                 // Let's resolve here then call loadEntity.
                 
                 var isStale = false
                 let resolvedURL = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                 let ok = resolvedURL.startAccessingSecurityScopedResource()
                 defer { if ok { resolvedURL.stopAccessingSecurityScopedResource() } }
                 entity = try await ModelFactory.loadEntity(from: resolvedURL)
                 
                 if let tempURL = try? await ExportManager.cacheModel(fromBookmark: bookmark) {
                     entitySources[id] = tempURL
                 }
                 
             } else if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
                 entity = try await ModelFactory.loadEntity(from: url)
                 if url.isFileURL {
                    if let tempURL = try? await ExportManager.cacheModel(from: url) {
                        entitySources[id] = tempURL
                    }
                 } else {
                     entitySources[id] = url
                 }
             } else {
                 entity = try await ModelFactory.makeEntity(for: name)
             }
             
             ModelFactory.configureLoadedEntity(entity)

             if let text = userInfo["appliedText"] as? String, !text.isEmpty {
                 ModelFactory.addAppliedText(text, to: entity)
             }
             
             if let sBookmark = userInfo["soundBookmark"] as? Data {
                 var isStale = false
                 if let sUrl = try? URL(resolvingBookmarkData: sBookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                      entitySounds[id] = sUrl
                 }
             } else if let sUrlStr = userInfo["soundURL"] as? String, let sUrl = URL(string: sUrlStr) {
                 entitySounds[id] = sUrl
             }

             let bounds = entity.visualBounds(relativeTo: entity)
             let scale = entity.scale(relativeTo: nil).x
             let bottomY = bounds.min.y * scale
             
             entity.position = worldPosition + SIMD3<Float>(0, -bottomY + 0.05, 0)
             
             worldAnchor.addChild(entity)
             placedEntities[id] = entity
             physicsDisabledEntityIDs.insert(id)
         } catch {
             print("[PlaceModelView] Failed to place entity for id=\(id) name=\(name): \(error)")
         }
    }
    
    @MainActor
    func processPlaneUpdates(_ provider: PlaneDetectionProvider) async {
        for await update in provider.anchorUpdates {
            let anchor = update.anchor
            switch update.event {
            case .added, .updated:
                updatePlane(anchor)
            case .removed:
                if let entity = planeEntities[anchor.id] {
                    entity.removeFromParent()
                    planeEntities.removeValue(forKey: anchor.id)
                }
            }
        }
    }
}
