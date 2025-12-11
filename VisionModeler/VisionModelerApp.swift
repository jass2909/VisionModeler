//
//  VisionModelerApp.swift
//  VisionModeler
//
//  Created by jasmeet singh on 15.11.25.
//

import SwiftUI

struct PreviewItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    // Store URL as string to match existing `.flatMap { URL(string: $0) }` usage
    var url: String?
}

struct PreviewControlsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var previewScale: CGFloat = 1.0
    let object: ContentView.StoredObject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scale")
                Spacer()
                Text(String(format: "%.2fx", previewScale))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $previewScale, in: 0.1...3.0, step: 0.05)
                .onChange(of: previewScale) { _, newValue in
                    NotificationCenter.default.post(
                        name: Notification.Name("previewScaleChanged"),
                        object: nil,
                        userInfo: [
                            "id": object.id.uuidString,
                            "scale": newValue
                        ]
                    )
                }
        }
        .padding()
        .controlSize(settings.useHighContrast ? .large : .regular)
    }
}

@main
struct VisionModelerApp: App {
    @State private var showImmersive = false
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView(showImmersive: $showImmersive)
                .environmentObject(settings)
                .tutorialOnFirstLaunch()
        }
        WindowGroup(id: "modelPreview", for: PreviewItem.self) { $item in
            if let item = item {
                let obj = ContentView.StoredObject(
                    id: item.id,
                    name: item.name,
                    url: item.url.flatMap { URL(string: $0) }
                )
                NavigationStack {
                    ModelPreviewView(object: obj)
                        .environmentObject(settings)
                }
            } else {
                NavigationStack {
                    Text("No preview item selected")
                        .environmentObject(settings)
                }
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)
        .windowResizability(.automatic)

        ImmersiveSpace(id: "placeSpace") {
            PlaceModelView()
                .environmentObject(settings)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

