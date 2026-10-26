import Foundation


extension CGPoint {

    func distance(to point: CGPoint) -> CGFloat {
        return hypot(point.x - self.x, point.y - self.y)
    }

}


func -(a: CGPoint, b: CGPoint) -> CGPoint {
    return CGPoint(x: a.x - b.x, y: a.y - b.y)
}
