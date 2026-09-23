import CoreGraphics

enum Radius {

    static let sm: CGFloat = 8

    static let field: CGFloat = 12

    static let md: CGFloat = 16

    static let lg: CGFloat = 20

    static let card: CGFloat = 26

    static let cardLarge: CGFloat = 30

    static let button: CGFloat = 17

    static func pill(_ height: CGFloat) -> CGFloat { height / 2 }
}
