import Foundation

private func issue(category: String, severity: Double, message: String) -> FeedbackItem {
    FeedbackItem(category: category, severity: clamp(severity), message: message)
}

public func generateFeedback(metrics: FrameMetrics, maxItems: Int = 4) -> [FeedbackItem] {
    var issues: [FeedbackItem] = []

    if metrics.stanceWidthRatio < 0.85 {
        issues.append(
            issue(
                category: "stance",
                severity: (0.85 - metrics.stanceWidthRatio) / 0.35,
                message: "Stance is narrow at trophy pose. Widen the base slightly."
            )
        )
    } else if metrics.stanceWidthRatio > 2.0 {
        issues.append(
            issue(
                category: "stance",
                severity: (metrics.stanceWidthRatio - 2.0) / 0.5,
                message: "Stance is too wide at trophy pose. Narrow the base a little."
            )
        )
    }

    if metrics.meanKneeAngle > 145.0 {
        issues.append(
            issue(
                category: "legs",
                severity: (metrics.meanKneeAngle - 145.0) / 30.0,
                message: "Knees are too straight. Load more through the legs."
            )
        )
    } else if metrics.meanKneeAngle < 85.0 {
        issues.append(
            issue(
                category: "legs",
                severity: (85.0 - metrics.meanKneeAngle) / 25.0,
                message: "Leg load is too deep. Ease the bend slightly."
            )
        )
    }

    if metrics.tossArmAngle < 155.0 || metrics.tossWristLiftRatio < 0.9 {
        let severity = max((155.0 - metrics.tossArmAngle) / 45.0, (0.9 - metrics.tossWristLiftRatio) / 0.6)
        issues.append(
            issue(
                category: "toss_arm",
                severity: severity,
                message: "Reach taller with the toss arm and keep it extended to trophy pose."
            )
        )
    }

    if metrics.hitArmAngle > 145.0 {
        issues.append(
            issue(
                category: "hitting_arm",
                severity: (metrics.hitArmAngle - 145.0) / 35.0,
                message: "Hitting arm opens too early. Keep the elbow more loaded."
            )
        )
    } else if metrics.hitArmAngle < 60.0 {
        issues.append(
            issue(
                category: "hitting_arm",
                severity: (60.0 - metrics.hitArmAngle) / 25.0,
                message: "Hitting arm is too collapsed. Build a cleaner throwing shape."
            )
        )
    }

    if metrics.tossShoulderLiftRatio < 0.12 || metrics.shoulderTiltDegrees < 10.0 {
        let severity = max((0.12 - metrics.tossShoulderLiftRatio) / 0.2, (10.0 - metrics.shoulderTiltDegrees) / 10.0)
        issues.append(
            issue(
                category: "shoulders",
                severity: severity,
                message: "Create more shoulder tilt so the toss side stays higher at trophy pose."
            )
        )
    }

    if metrics.trunkTiltDegrees > 28.0 {
        issues.append(
            issue(
                category: "balance",
                severity: (metrics.trunkTiltDegrees - 28.0) / 15.0,
                message: "Trunk is leaning too far. Stack more cleanly over the base."
            )
        )
    } else if metrics.trunkTiltDegrees < 4.0 {
        issues.append(
            issue(
                category: "balance",
                severity: (4.0 - metrics.trunkTiltDegrees) / 4.0,
                message: "Stay a touch taller through trophy pose."
            )
        )
    }

    if issues.isEmpty {
        return [
            FeedbackItem(
                category: "summary",
                severity: 0.0,
                message: "Trophy pose looks balanced. Stance, loading, and arm shape are in range."
            )
        ]
    }

    return issues.sorted { $0.severity > $1.severity }.prefix(maxItems).map { $0 }
}
