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
                        // vector.x is Left/Right (Scene X)
                        // vector.y is Back/Forward (Scene Z)
                        // User Push UP (Negative Y on screen) -> Move Forward (Negative Z)
                        // User Push DOWN (Positive Y on screen) -> Move Backward (Positive Z)
                        // User Push RIGHT (Positive X) -> Move Right (Positive X)
                        
                        // We need to map vector to root movement.
                        // If user pushes UP (stick y < 0), they want to go forward.
                        // Moving root forward means root moves towards camera?
                        // No. "Navigate scene" usually means Moving the Camera (User).
                        // Since we can't move the user, we move the ROOT in the OPPOSITE direction.
                        // Move User Forward (-Z) = Move Root Backward (+Z).
                        // Wait.
                        
                        // Let's stick to the previous implementation logic:
                        // Previous: Arrow UP -> onMove(0, 0, -step) -> Root.pos += (0,0,-step)
                        // If root moves -Z (away), objects move away. User feels like moving backwards?
                        // Let's re-verify Standard Navigation: "Walk Forward"
                        // If I walk forward, objects get closer (z decreases relative to me).
                        // If root is at (0,0,-1) (in front of me)
                        // I want to walk towards it. I move +Z??? No, -Z is forward in WebXR/Unity usually, but RealityKit +Z is towards user.
                        // RealityKit: +Z is towards user.
                        // Objects are at (0,0,0) (on my head?) or (0,0,-1) (forward).
                        // If I want to "Forward", I want to get closer to (0,0,-1).
                        // Since I stay at (0,0,0) (world origin), I must pull the world towards me (+Z).
                        // So "Walk Forward" = Root moves +Z.
                        
                        // Previous implementation:
                        // Button "Arrow Down" -> `onMove(SIMD3(0, 0, moveStep))` (Z+)
                        // Button "Arrow Up" -> `onMove(SIMD3(0, 0, -moveStep))` (Z-)
                        // Arrow Up icon usually means "Walk Forward".
                        // So Arrow Up -> Z- -> Root moves away. User moves Backwards?
                        // Let's rely on "Intuitive":
                        // Joystick Up (y < 0) -> "Forward".
                        // We want "Walk Forward".
                        // Logic:
                        // Joystick Y < 0 (Up) -> Move scene +Z (Closer).
                        // Joystick Y > 0 (Down) -> Move scene -Z (Away).
                        // Joystick X > 0 (Right) -> "Straf Right". Scene moves Left (-X).
                        // Joystick X < 0 (Left) -> "Straf Left". Scene moves Right (+X).
                        
                        let forwardBack = -vector.y * 0.2 
                        let leftRight = -vector.x * 0.2
                        
                        // joystick y is negative when up. -(-y) = +y.
                        // So Up -> +Z (Scene moves towards us = Walk Forward). Correct.
                        
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
