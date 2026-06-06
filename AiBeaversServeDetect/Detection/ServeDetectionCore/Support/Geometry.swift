import CoreGraphics
import Foundation

func clamp(_ value: Double, lower: Double = 0.0, upper: Double = 1.0) -> Double {
    max(lower, min(upper, value))
}

func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}

func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2.0, y: (a.y + b.y) / 2.0)
}

func angleDegrees(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
    let ba = CGPoint(x: a.x - b.x, y: a.y - b.y)
    let bc = CGPoint(x: c.x - b.x, y: c.y - b.y)
    let denominator = hypot(ba.x, ba.y) * hypot(bc.x, bc.y)
    guard denominator > 0 else {
        return 0.0
    }
    let cosine = clamp(((ba.x * bc.x) + (ba.y * bc.y)) / denominator, lower: -1.0, upper: 1.0)
    return acos(cosine) * 180.0 / .pi
}

func lineAngleDegrees(_ a: CGPoint, _ b: CGPoint) -> Double {
    atan2(b.y - a.y, b.x - a.x) * 180.0 / .pi
}

func horizontalTiltDegrees(_ a: CGPoint, _ b: CGPoint) -> Double {
    let tilt = abs(lineAngleDegrees(a, b))
    return tilt > 90.0 ? 180.0 - tilt : tilt
}

func tiltFromVertical(_ a: CGPoint, _ b: CGPoint) -> Double {
    atan2(abs(b.x - a.x), abs(b.y - a.y) + 1e-9) * 180.0 / .pi
}

func targetScore(_ value: Double, target: Double, tolerance: Double) -> Double {
    guard tolerance > 0 else {
        return 0.0
    }
    return clamp(1.0 - abs(value - target) / tolerance)
}
