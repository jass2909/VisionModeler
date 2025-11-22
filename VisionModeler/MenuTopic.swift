import Foundation

enum MenuTopic: String, CaseIterable, Identifiable, Hashable {
    case contrast = "Contrast"
    case help = "Help"
    case placement = "Placement"

    var id: String { rawValue }
}
