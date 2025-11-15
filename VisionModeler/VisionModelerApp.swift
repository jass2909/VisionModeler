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

    var body: some Scene {
        WindowGroup {
            ContentView(showImmersive: $showImmersive)
        }

        ImmersiveSpace(id: "placeSpace") {
            PlaceModelView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
