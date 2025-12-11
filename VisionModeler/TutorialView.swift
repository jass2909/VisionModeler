import SwiftUI

// MARK: - Tutorial Presentation
// Attach `.tutorialOnFirstLaunch()` to your app's root view to automatically
// present the tutorial on first launch. Example:
//
// struct RootView: View {
//     var body: some View {
//         ContentView()
//             .tutorialOnFirstLaunch()
//     }
// }
//
// The tutorial will be shown once. After the user taps "Got it", it will not
// appear again across app launches (persisted via @AppStorage).

private let hasSeenTutorialKey = "hasSeenTutorial"

struct TutorialOnFirstLaunch: ViewModifier {
    @AppStorage(hasSeenTutorialKey) private var hasSeenTutorial: Bool = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: .constant(!hasSeenTutorial)) {
                TutorialView()
            }
    }
}

extension View {
    /// Presents the tutorial automatically on first launch.
    func tutorialOnFirstLaunch() -> some View {
        modifier(TutorialOnFirstLaunch())
    }
}

// MARK: - Tutorial View
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(hasSeenTutorialKey) private var hasSeenTutorial: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    Group {
                        TutorialCard(
                            icon: "sparkles",
                            title: "Welcome to VisionModeler",
                            content: "This quick tour highlights the key areas of the app and the main controls you’ll use every day. You can revisit Help from Settings any time."
                        )

                        TutorialCard(
                            icon: "plus.square.on.square",
                            title: "Adding Shapes",
                            content: "Open Objects and tap Add Shape to insert built‑in primitives like Cube, Sphere, Cone, Cylinder, or Plane."
                        )

                        TutorialCard(
                            icon: "viewfinder",
                            title: "Placing in the World",
                            content: "Use Place on an object to open the immersive space. Tap an anchor point on the grid to place it precisely, or place directly in front of you."
                        )

                        TutorialCard(
                            icon: "hand.point.up.left",
                            title: "Moving Objects",
                            content: "Grab and drag to move. Objects snap to nearby anchor points. Pinch to scale and drag horizontally with two hands to rotate."
                        )

                        TutorialCard(
                            icon: "trash",
                            title: "Deleting Objects",
                            content: "Use the floating toolbar above an object or press edit in the object list, and tap the Trash button to remove it from the scene."
                        )

                        TutorialCard(
                            icon: "atom",
                            title: "Adding Gravity",
                            content: "Toggle Physics On in the object’s floating toolbar to enable gravity and collisions. Toggle again to keep it fixed in place."
                        )

                        TutorialCard(
                            icon: "paintpalette",
                            title: "Changing Colors",
                            content: "Open the color palette from the floating toolbar and pick a color to restyle the selected object instantly."
                        )

                        TutorialCard(
                            icon: "folder",
                            title: "Custom Objects from Library",
                            content: "Use Library to pick a directory or import USDZ/Reality files. Add them to Objects, then Place to bring them into your scene."
                        )
                    }

                    footer
                }
                .padding(24)
            }
            .navigationTitle("Quick Tour")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Got it") {
                        completeTutorial()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .interactiveDismissDisabled(!hasSeenTutorial) // prevent accidental dismiss before acknowledgement
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "eye.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("VisionModeler")
                        .font(.largeTitle.bold())
                    Text("Add, place, and preview models in AR.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Tips")
                .font(.headline)
            Text("You can import data by dragging files into the app, and you can export trained models for deployment. If you need help later, check Settings → Help.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(role: .cancel) {
                    // Allow skipping once; still mark as seen to avoid re-showing on next launch.
                    completeTutorial()
                } label: {
                    Label("Got it", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func completeTutorial() {
        hasSeenTutorial = true
        dismiss()
    }
}

// MARK: - Reusable Card
private struct TutorialCard: View {
    let icon: String
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(content)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color(.systemBackground)
            .ignoresSafeArea()
        EmptyView()
            .tutorialOnFirstLaunch()
    }
}
