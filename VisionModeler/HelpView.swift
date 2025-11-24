import SwiftUI

struct HelpView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Help / Readme").font(.title2.bold()).highContrastTextOutline(settings.useHighContrast)
                Text("• Drag the object to reposition it in space.\n• Use the Menu to access Contrast, Help, and Placement settings.\n• Placement Lock disables moving the object.").highContrastTextOutline(settings.useHighContrast)
                Text("Tips").font(.headline).highContrastTextOutline(settings.useHighContrast)
                Text("If interactions feel too sensitive, adjust drag sensitivity and smoothing in code.").highContrastTextOutline(settings.useHighContrast)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
