import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Binding var objects: [ContentView.StoredObject]
    var pickDirectory: () -> Void
    var place: (ContentView.StoredObject) -> Void
    var addToObjects: (ContentView.StoredObject) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Pick Directory") {
                    pickDirectory()
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding()

            if objects.isEmpty {
                VStack {
                    Spacer()
                    Text("No models found in the selected directory.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(objects) { obj in
                    HStack {
                        Text(obj.name)
                        Spacer()
                        Button("Add") {
                            addToObjects(obj)
                        }
                        .buttonStyle(.bordered)
                        Button("Place") {
                            place(obj)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Library")
    }
}

#Preview {
    struct LibraryPreviewHost: View {
        @State private var sampleObjects: [ContentView.StoredObject] = [
            .init(name: "Sample.usdz", url: nil),
            .init(name: "Robot.reality", url: nil)
        ]

        var body: some View {
            NavigationStack {
                LibraryView(
                    objects: $sampleObjects,
                    pickDirectory: {},
                    place: { obj in print("Place: \(obj.name)") },
                    addToObjects: { obj in print("Add: \(obj.name)") }
                )
            }
        }
    }

    return LibraryPreviewHost()
}
