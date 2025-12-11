import Foundation
import UIKit
import RealityKit
import ModelIO

enum ExportManager {
    static func cacheModel(fromBookmark bookmark: Data) async throws -> URL {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        return try await cacheModel(from: url)
    }

    static func cacheModel(from url: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = url.lastPathComponent
        let dest = tempDir.appendingPathComponent(UUID().uuidString + "_" + filename)
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }
    
    static func exportWithColor(source: URL, color: UIColor) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = source.deletingPathExtension().lastPathComponent + "_colored.usdz"
        let dest = tempDir.appendingPathComponent(filename)
        
        let asset = MDLAsset(url: source)
        let scatteringFunction = MDLPhysicallyPlausibleScatteringFunction()
        let material = MDLMaterial(name: "coloredMaterial", scatteringFunction: scatteringFunction)
        
        var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let colorVal = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
        
        let property = MDLMaterialProperty(name: "baseColor", semantic: .baseColor, float4: colorVal)
        material.setProperty(property)
        
        for i in 0..<asset.count {
            let object = asset.object(at: i)
            applyMaterialRecursively(object, material: material)
        }
        
        try asset.export(to: dest)
        return dest
    }
    
    private static func applyMaterialRecursively(_ object: MDLObject, material: MDLMaterial) {
        if let mesh = object as? MDLMesh {
            for submesh in mesh.submeshes as? [MDLSubmesh] ?? [] {
               submesh.material = material
            }
        }
        for i in 0..<object.children.count {
            applyMaterialRecursively(object.children[i], material: material)
        }
    }

    static func generateUSDZ(for entity: Entity) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString).usdz")
        let asset = MDLAsset()
        
        let mesh = MDLMesh.newBox(withDimensions: SIMD3<Float>(0.2, 0.2, 0.2),
                                  segments: [1,1,1],
                                  geometryType: .triangles,
                                  inwardNormals: false,
                                  allocator: nil)
        asset.add(mesh)
        
        try asset.export(to: fileURL)
        return fileURL
    }
}
