import Foundation

enum MenuTopic: String, CaseIterable, Identifiable, Hashable {
    case contrast = "Contrast"
    case help = "Help"
    case placement = "Placement"
    case library = "Library"
    case objects = "Objects"


    var id: String { rawValue }
}
