import Foundation

enum MenuTopic: String, CaseIterable, Identifiable, Hashable {
    case contrast = "Contrast"
    case help = "Help"
    case placement = "Placement"
    case scenes = "Scenes"
    case library = "Library"


    var id: String { rawValue }
}
