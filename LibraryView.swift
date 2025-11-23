import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var settings: SettingsStore

    @Binding var objects: [ContentView.StoredObject]
    var pickDirectory: () -> Void
    var place: (ContentView.StoredObject) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if settings.useHighContrast {
                    Button(action: pickDirectory) {
                        Text("Choose Directory").highContrastTextOutline(true)
                    }
                    .buttonStyle(HighContrastButtonStyle(enabled: true))
                } else {
                    Button("Choose Directory", action: pickDirectory)
                        .buttonStyle(.bordered)
                }
            }
            .padding([.horizontal, .top])

            List {
                if objects.isEmpty {
                    Text("No models found. Choose a directory.").foregroundStyle(.secondary)
                } else {
                    ForEach(objects) { obj in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(obj.name)
                                if let url = obj.url {
                                    Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if settings.useHighContrast {
                                Button(action: { place(obj) }) {
                                    Text("Place").highContrastTextOutline(true)
                                }
                                .buttonStyle(HighContrastButtonStyle(enabled: true))
                            } else {
                                Button("Place") { place(obj) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Library")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    LibraryView(objects: .constant([]), pickDirectory: {}, place: { _ in })
        .environmentObject(SettingsStore())
}
