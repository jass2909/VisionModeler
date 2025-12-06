import SwiftUI

struct ObjectsView: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var storedObjects: [ContentView.StoredObject]
    @Binding var showImmersive: Bool
    @Binding var pendingPlacement: ContentView.StoredObject?
    
    var body: some View {
        List {
            if storedObjects.isEmpty {
                Text("No objects yet.").foregroundStyle(.secondary)
            } else {
                ForEach(storedObjects) { obj in
                    Button {
                        if showImmersive {
                            // Immersive space already open: post placement immediately
                            print("[ObjectsView] Immersive already open, placing \(obj.name) (\(obj.id))")
                            NotificationCenter.default.post(
                                name: .placeObjectRequested,
                                object: nil,
                                userInfo: [
                                    "id": obj.id.uuidString,
                                    "name": obj.name
                                ]
                            )
                        } else {
                            // Open immersive space and place after it opens
                            pendingPlacement = obj
                            showImmersive = true
                        }
                    } label: {
                        HStack {
                            Text(obj.name)
                            Spacer()
                            Text("Place")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    // Send removal requests for any deleted objects so the immersive space can remove them
                    let idsToRemove = indexSet.map { storedObjects[$0].id }
                    idsToRemove.forEach { id in
                        NotificationCenter.default.post(
                            name: .removeObjectRequested,
                            object: nil,
                            userInfo: [
                                "id": id.uuidString
                            ]
                        )
                    }
                    storedObjects.remove(atOffsets: indexSet)
                }
            }
        }
        .navigationTitle("Objects")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    if settings.useHighContrast {
                        Button {
                            storedObjects.append(ContentView.StoredObject(name: "Cube"))
                        } label: {
                            Text("Add Cube").highContrastTextOutline(true)
                        }
                        .buttonStyle(HighContrastButtonStyle(enabled: true))
                        
                        Button {
                            storedObjects.append(ContentView.StoredObject(name: "Sphere"))
                        } label: {
                            Text("Add Sphere").highContrastTextOutline(true)
                        }
                        .buttonStyle(HighContrastButtonStyle(enabled: true))
                        
                        Button {
                            storedObjects.append(ContentView.StoredObject(name: "Imported Model"))
                        } label: {
                            Text("Import Placeholder").highContrastTextOutline(true)
                        }
                        .buttonStyle(HighContrastButtonStyle(enabled: true))
                    } else {
                        Button("Add Cube") {
                            storedObjects.append(ContentView.StoredObject(name: "Cube"))
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Add Sphere") {
                            storedObjects.append(ContentView.StoredObject(name: "Sphere"))
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Import Placeholder") {
                            storedObjects.append(ContentView.StoredObject(name: "Imported Model"))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

#Preview {
    ObjectsView(
        storedObjects: .constant([ContentView.StoredObject(name: "Test Cube")]),
        showImmersive: .constant(false),
        pendingPlacement: .constant(nil)
    )
    .environmentObject(SettingsStore())
}
