import SwiftUI

struct PlacementSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Placement Settings").font(.title2.bold()).highContrastTextOutline(settings.useHighContrast)
            Toggle(isOn: $settings.isPlacementLocked) {
                Text("Lock Placement").highContrastTextOutline(settings.useHighContrast)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
