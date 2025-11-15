import SwiftUI

struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace

    @Binding var showImmersive: Bool

    var body: some View {
        VStack {
            ModelView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button("In Raum platzieren") {
                showImmersive = true
            }
            .padding()
        }
        .onChange(of: showImmersive) { _, newValue in
            if newValue {
                Task {
                    await openImmersiveSpace(id: "placeSpace")
                }
            }
        }
    }
}

#Preview {
    ContentView(showImmersive: .constant(false))
}
