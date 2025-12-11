import SwiftUI
import RealityKit

struct SceneNavigationControl: View {
    var onMove: (SIMD3<Float>) -> Void
    var onRotate: (Float) -> Void
    var onReset: () -> Void
    
    // Timer for continuous movement? For now, simple clicks.
    let moveStep: Float = 0.1 // 10cm
    let rotStep: Float = .pi / 12 // 15 degrees
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Navigate Scene")
                .font(.headline)
            
            HStack(spacing: 30) {
                // Joystick for X/Z Movement
                VStack(spacing: 8) {
                    Text("Move").font(.caption).foregroundStyle(.secondary)
                    JoystickView { vector in
                        
                        let forwardBack = -vector.y * 0.2 
                        let leftRight = -vector.x * 0.2
                
                        onMove(SIMD3(leftRight, 0, forwardBack))
                    }
                }
                
                Divider()
                
                VStack(spacing: 24) {
                    // Vertical Movement
                    VStack(spacing: 8) {
                        Text("Height").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button {
                                onMove(SIMD3(0, moveStep, 0)) // Down
                            } label: {
                                Image(systemName: "arrow.down.to.line")
                                    .padding(4)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                onMove(SIMD3(0, -moveStep, 0)) // Up
                            } label: {
                                Image(systemName: "arrow.up.to.line")
                                    .padding(4)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Rotation
                    VStack(spacing: 8) {
                        Text("Rotate").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button {
                                onRotate(-rotStep)
                            } label: {
                                Image(systemName: "arrow.uturn.left")
                                    .padding(4)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                onRotate(rotStep)
                            } label: {
                                Image(systemName: "arrow.uturn.right")
                                    .padding(4)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    Button("Reset", action: onReset)
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
        }
        .padding()
        .glassBackgroundEffect()
    }
}

#Preview {
    SceneNavigationControl(onMove: { _ in }, onRotate: { _ in }, onReset: {})
}
