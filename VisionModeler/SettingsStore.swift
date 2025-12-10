import SwiftUI

final class SettingsStore: ObservableObject {
    @Published var useHighContrast: Bool = false
    @Published var isPlacementLocked: Bool = false
    @Published var placedIDs: Set<UUID> = []
}
