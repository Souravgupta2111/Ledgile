import Foundation

extension Double {
    /// Returns the string representation of the double without trailing zero if it's a whole number.
    /// Example: 2.0 returns "2", 2.5 returns "2.5".
    var cleanString: String {
        return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
    }
}
