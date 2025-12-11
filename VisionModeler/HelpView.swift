import SwiftUI

struct HelpView: View {
    @EnvironmentObject var settings: SettingsStore
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Help / Readme").font(.title2.bold()).highContrastTextOutline(settings.useHighContrast)
                Text("• Drag the object to reposition it in space.\n• Use the Menu to access Contrast, Help, and Placement settings.\n• Placement Lock disables moving the object.").highContrastTextOutline(settings.useHighContrast)
                Text("Tips").font(.headline).highContrastTextOutline(settings.useHighContrast)
                Text("If interactions feel too sensitive, adjust drag sensitivity and smoothing in code.").highContrastTextOutline(settings.useHighContrast)
                
                Divider().padding(.vertical, 8)

                Text("Tutorial")
                    .font(.headline)
                    .highContrastTextOutline(settings.useHighContrast)

                Text("You can revisit the onboarding tutorial at any time.")
                    .foregroundStyle(.secondary)
                    .highContrastTextOutline(settings.useHighContrast)

                HStack {
                    Button {
                        hasSeenTutorial = false // Triggers the tutorial sheet via .tutorialOnFirstLaunch()
                    } label: {
                        Label("Show Tutorial Again", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    if !hasSeenTutorial {
                        Text("Will appear now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                            .highContrastTextOutline(settings.useHighContrast)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
