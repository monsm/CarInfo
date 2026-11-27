import SwiftUI

enum StackSpec {

    enum Card {
        static let radius = CGFloat(26)
        static let padH = CGFloat(18)
        static let padTop = CGFloat(17)
        static let padBottom = CGFloat(16)
        static let inset = CGFloat(18)
        static let gap = CGFloat(14)
    }


    static let settle = Animation.interpolatingSpring(mass: 1, stiffness: 130, damping: 16)
}
