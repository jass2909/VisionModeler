import SwiftUI

struct ContrastSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contrast Settings").font(.title2.bold()).highContrastTextOutline(settings.useHighContrast)
            Toggle(isOn: $settings.useHighContrast) {
                Text("High Contrast Mode").highContrastTextOutline(settings.useHighContrast)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
