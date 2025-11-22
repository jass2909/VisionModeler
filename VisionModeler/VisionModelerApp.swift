//
//  VisionModelerApp.swift
//  VisionModeler
//
//  Created by jasmeet singh on 15.11.25.
//

import SwiftUI

@main
struct VisionModelerApp: App {
    @State private var showImmersive = false
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView(showImmersive: $showImmersive)
                .environmentObject(settings)
        }

        ImmersiveSpace(id: "placeSpace") {
            PlaceModelView()
                .environmentObject(settings)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
