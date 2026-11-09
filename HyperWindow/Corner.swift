import Foundation


enum Corner: CustomStringConvertible, Equatable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    var description: String {
        switch self {
            case .topLeft:
                return "1️⃣"
            case .topRight:
                return "2️⃣"
            case .bottomRight:
                return "3️⃣"
            case .bottomLeft:
                return "4️⃣"
        }
    }

    static func corner(for position: CGPoint, in size: CGSize) -> Self {
        let x = position.x / size.width
        let y = position.y / size.height
        guard !x.isNaN, !y.isNaN else { return .bottomRight }

        switch (x >= 0.5, y >= 0.5) {
            case (false, false):
                return .topLeft
            case (true, false):
                return .topRight
            case (true, true):
                return .bottomRight
            case (false, true):
                return .bottomLeft
        }
    }
}
