
import Foundation

/// A generic error raised by NutritionKit.
public struct NutritionKitError: Error, CustomStringConvertible, Sendable {
    /// A human-readable description of the error.
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

enum NumberFormatting {
    /// Format a value with at most `decimalPlaces` and at least `minDecimalPlaces` fraction digits.
    static func format(_ value: Double, decimalPlaces: Int, minDecimalPlaces: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = decimalPlaces
        formatter.minimumFractionDigits = minDecimalPlaces

        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
