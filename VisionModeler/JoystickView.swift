import SwiftUI

struct JoystickView: View {
    var onStickChanged: (SIMD2<Float>) -> Void
    
    @State private var stickPosition: CGSize = .zero
    @State private var isDragging = false
    @State private var timer: Timer? = nil
    
    // Joystick configuration
    let maxRadius: CGFloat = 60
    let stickSize: CGFloat = 50
    let sensitivity: Float = 0.05 // Movement per tick
    
    var body: some View {
        ZStack {
            // Background Base
            Circle()
                .fill(.regularMaterial)
                .frame(width: maxRadius * 2.5, height: maxRadius * 2.5)
                .shadow(radius: 5)
            
            // The Stick
            Circle()
                .fill(isDragging ? Color.blue : Color.gray.opacity(0.8))
                .frame(width: stickSize, height: stickSize)
                .offset(stickPosition)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            stateUpdated(translation: value.translation)
                        }
                        .onEnded { _ in
                            isDragging = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                stickPosition = .zero
                            }
                            stopTimer()
                            onStickChanged(.zero)
                        }
                )
        }
    }
    
    private func stateUpdated(translation: CGSize) {
        // Limit the stick to the radius
        let distance = sqrt(translation.width * translation.width + translation.height * translation.height)
        let angle = atan2(translation.height, translation.width)
        
        var constrainedDist = distance
        if distance > maxRadius {
            constrainedDist = maxRadius
        }
        
        let x = cos(angle) * constrainedDist
        let y = sin(angle) * constrainedDist
        
        stickPosition = CGSize(width: x, height: y)
        
        // Start emitting values if needed
        startTimer()
    }
    
    private func startTimer() {
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
                emitValue()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func emitValue() {
        // Normalize values to -1...1
        let xVal = Float(stickPosition.width / maxRadius)
        let yVal = Float(stickPosition.height / maxRadius)
        
        // Apply sensitivity and invert Y for natural forward pressing
        let moveX = xVal * sensitivity
        let moveY = yVal * sensitivity 
        
        // Return (X, Y) where Y is "forward/backward" (Z in 3D usually)
        onStickChanged(SIMD2(moveX, moveY))
    }
}

#Preview {
    JoystickView { val in
        print("Joy: \(val)")
    }
}
