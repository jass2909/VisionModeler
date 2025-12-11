import RealityKit

extension Entity {
    func isDescendant(of ancestor: Entity) -> Bool {
        var current: Entity? = self
        while let c = current {
            if c === ancestor { return true }
            current = c.parent
        }
        return false
    }
}
