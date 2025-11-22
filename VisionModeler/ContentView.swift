import SwiftUI

struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @EnvironmentObject var settings: SettingsStore

    @Binding var showImmersive: Bool

    @State private var selectedMenu: MenuTopic? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarMenuView(selected: $selectedMenu)
                .navigationTitle("Menu")
                .toolbar {
                    if columnVisibility != .detailOnly {
                        ToolbarItem(placement: .topBarTrailing) {
                            if settings.useHighContrast {
                                Button(action: {
                                    withAnimation(.easeInOut) {
                                        selectedMenu = nil
                                        columnVisibility = .detailOnly
                                    }
                                }) {
                                    Text("Back").highContrastTextOutline(settings.useHighContrast)
                                }
                                .buttonStyle(HighContrastButtonStyle(enabled: true))
                            } else {
                                Button(action: {
                                    withAnimation(.easeInOut) {
                                        selectedMenu = nil
                                        columnVisibility = .detailOnly
                                    }
                                }) {
                                    Text("Back")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
        } detail: {
            VStack {
                switch selectedMenu {
                case .contrast:
                    ContrastSettingsView()
                case .help:
                    HelpView()
                case .placement:
                    PlacementSettingsView()
                case .none:
                    VStack {
                        ModelView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if settings.useHighContrast {
                            Button(action: { showImmersive = true }) {
                                Text("In Raum platzieren").highContrastTextOutline(true)
                            }
                            .buttonStyle(HighContrastButtonStyle(enabled: true))
                            .contentShape(Rectangle())
                            .padding()
                            .disabled(settings.isPlacementLocked)
                        } else {
                            Button(action: { showImmersive = true }) {
                                Text("In Raum platzieren")
                            }
                            .buttonStyle(.bordered)
                            .contentShape(Rectangle())
                            .padding()
                            .disabled(settings.isPlacementLocked)
                        }
                    }
                }
            }
            .toolbar {
                if columnVisibility == .detailOnly {
                    ToolbarItem(placement: .topBarLeading) {
                        if settings.useHighContrast {
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    columnVisibility = .all
                                }
                            }) {
                                Text("Menu").highContrastTextOutline(settings.useHighContrast)
                            }
                            .buttonStyle(HighContrastButtonStyle(enabled: true))
                        } else {
                            Button(action: {
                                withAnimation(.easeInOut) {
                                    columnVisibility = .all
                                }
                            }) {
                                Text("Menu")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .controlSize(settings.useHighContrast ? .large : .regular)
        //.buttonStyle(HighContrastButtonStyle(enabled: settings.useHighContrast))  // Removed as per instructions
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
        .environmentObject(SettingsStore())
}
