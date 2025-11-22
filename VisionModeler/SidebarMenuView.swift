import SwiftUI

struct SidebarMenuView: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var selected: MenuTopic?

    var body: some View {
        List(MenuTopic.allCases, selection: $selected) { topic in
            Text(topic.rawValue)
                .highContrastTextOutline(settings.useHighContrast)
                .tag(topic)
        }
        .listStyle(.sidebar)
        .navigationTitle("Menu")
    }
}
