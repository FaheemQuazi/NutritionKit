
import CoreGraphics
import SwiftUI

// MARK: - CGPoint vector helpers

extension CGPoint {
    /// Vector addition.
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    /// Vector subtraction.
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    /// Scalar multiplication.
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    /// The length of the vector from the origin to this point.
    var magnitude: CGFloat {
        (x * x + y * y).squareRoot()
    }

    /// A unit-length vector pointing in the same direction, or zero for the zero vector.
    var normalized: CGPoint {
        let magnitude = self.magnitude
        guard magnitude > 0 else { return .zero }

        return CGPoint(x: x / magnitude, y: y / magnitude)
    }
}

// MARK: - CameraRect

/// Four normalized corner points (top-left, top-right, bottom-left, bottom-right) describing a
/// quadrilateral overlay on the camera feed. Conforms to `VectorArithmetic` so it can be animated.
public struct CameraRect: VectorArithmetic, Sendable {
    /// Top-left corner.
    public var first: CGPoint

    /// Top-right corner.
    public var second: CGPoint

    /// Bottom-left corner.
    public var third: CGPoint

    /// Bottom-right corner.
    public var fourth: CGPoint

    /// Create a camera rectangle from its four corners.
    public init(_ first: CGPoint, _ second: CGPoint, _ third: CGPoint, _ fourth: CGPoint) {
        self.first = first
        self.second = second
        self.third = third
        self.fourth = fourth
    }

    // MARK: AdditiveArithmetic

    public static var zero: CameraRect {
        .init(.zero, .zero, .zero, .zero)
    }

    public static func + (lhs: CameraRect, rhs: CameraRect) -> CameraRect {
        .init(lhs.first + rhs.first, lhs.second + rhs.second,
              lhs.third + rhs.third, lhs.fourth + rhs.fourth)
    }

    public static func - (lhs: CameraRect, rhs: CameraRect) -> CameraRect {
        .init(lhs.first - rhs.first, lhs.second - rhs.second,
              lhs.third - rhs.third, lhs.fourth - rhs.fourth)
    }

    // MARK: VectorArithmetic

    public mutating func scale(by rhs: Double) {
        let scale = CGFloat(rhs)
        first = first * scale
        second = second * scale
        third = third * scale
        fourth = fourth * scale
    }

    public var magnitudeSquared: Double {
        func sq(_ p: CGPoint) -> Double { Double(p.x * p.x + p.y * p.y) }
        return sq(first) + sq(second) + sq(third) + sq(fourth)
    }
}
