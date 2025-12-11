import SwiftUI
import RealityKit
import UIKit

struct ObjectControlView: View {
    let id: String
    let isLocked: Bool
    let isPhysicsDisabled: Bool
    let isPlaying: Bool
    let isColorPickerOpen: Bool
    
    var onRemove: () -> Void
    var onToggleLock: () -> Void
    var onTogglePhysics: () -> Void
    var onToggleSound: () -> Void
    var onToggleColorPicker: () -> Void
    var onPrepareExport: () -> Void
    var onColorSelected: (UIColor) -> Void
    
    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Button(action: onRemove) {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                
                Button(action: onToggleLock) {
                    Label(isLocked ? "Unlock" : "Lock", systemImage: isLocked ? "lock.fill" : "lock.open.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                
                Button(action: onTogglePhysics) {
                    Label(isPhysicsDisabled ? "Physics Off" : "Physics On", systemImage: isPhysicsDisabled ? "atom" : "atom")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(isPhysicsDisabled ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                
                Button(action: onToggleSound) {
                    Label(isPlaying ? "Stop Sound" : "Play Sound", systemImage: isPlaying ? "speaker.wave.3.fill" : "speaker.slash.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(isPlaying ? .blue : .primary)
                }
                .buttonStyle(.plain)
                
                Button(action: onToggleColorPicker) {
                    Label("Colors", systemImage: "paintpalette")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(isColorPickerOpen ? .blue : .primary)
                }
                .buttonStyle(.plain)
                
                Button(action: onPrepareExport) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
            }
            
            if isColorPickerOpen {
                HStack(spacing: 12) {
                    ColorButton(color: .red, action: { onColorSelected(.red) })
                    ColorButton(color: .green, action: { onColorSelected(.green) })
                    ColorButton(color: .blue, action: { onColorSelected(.blue) })
                    ColorButton(color: .yellow, action: { onColorSelected(.yellow) })
                    ColorButton(color: .black, action: { onColorSelected(.black) })
                    ColorButton(color: .white, action: { onColorSelected(.white) })
                    ColorButton(color: .gray, action: { onColorSelected(.gray) })
                }
                .padding(.top, 8)
            }
        }
        .padding(12)
        .glassBackgroundEffect()
    }
}

struct ColorButton: View {
    let color: UIColor
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "circle.fill")
                .font(.title)
                .foregroundStyle(Color(uiColor: color))
        }
    }
}

struct AnchorMenuView: View {
    let onPlaceCube: () -> Void
    let onPlaceSphere: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Place Object")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack(spacing: 12) {
                Button("Cube", action: onPlaceCube)
                    .buttonStyle(.bordered)
                
                Button("Sphere", action: onPlaceSphere)
                    .buttonStyle(.bordered)
            }
            
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.borderless)
                .tint(.red)
        }
        .padding()
        .glassBackgroundEffect()
    }
}

struct InstructionView: View {
    let name: String
    
    var body: some View {
        VStack {
            Text("Select an anchor point to place")
            Text(name).fontWeight(.bold)
        }
        .font(.title)
        .padding()
        .glassBackgroundEffect()
    }
}
