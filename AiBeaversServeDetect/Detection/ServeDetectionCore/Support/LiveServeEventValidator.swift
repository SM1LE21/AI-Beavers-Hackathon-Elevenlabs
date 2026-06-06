import CoreGraphics
import Foundation

struct LiveServeEventValidationThresholds {
    let minimumTrophyPeakScore: Double
    let minimumTrophySupportFrames: Int
    let minimumTossWristLiftRatio: Double
    let minimumTossArmAngle: Double
    let minimumImpactShoulderMargin: Double
    let minimumImpactWristLiftRatio: Double
    let minimumImpactDelaySeconds: Double
    let maximumImpactDelaySeconds: Double
    let minimumSatisfiedSignals: Int

    static let `default` = LiveServeEventValidationThresholds(
        minimumTrophyPeakScore: 0.24,
        minimumTrophySupportFrames: 1,
        minimumTossWristLiftRatio: 0.24,
        minimumTossArmAngle: 128.0,
        minimumImpactShoulderMargin: 0.15,
        minimumImpactWristLiftRatio: 0.22,
        minimumImpactDelaySeconds: 0.2,
        maximumImpactDelaySeconds: 2.7,
        minimumSatisfiedSignals: 3
    )
}

private struct LiveImpactSnapshot {
    let wristLiftRatio: Double
    let shoulderMarginRatio: Double
}

struct LiveServeEventValidationReport {
    let accepted: Bool
    let impactDelay: Double
    let trophySupportCount: Int
    let maxTossWristLift: Double
    let maxTossArmAngle: Double
    let impactShoulderMargin: Double?
    let impactWristLift: Double?
    let satisfiedSignals: Int
    let signalScore: Double
    let rejectionReasons: [String]

    var rejectionSummary: String {
        rejectionReasons.isEmpty ? "none" : rejectionReasons.joined(separator: ",")
    }
}

enum LiveServeEventValidator {
    static func accepts(
        event: ServeEvent,
        in sequence: PoseSequence,
        thresholds: LiveServeEventValidationThresholds = .default
    ) -> Bool {
        report(
            for: event,
            in: sequence,
            thresholds: thresholds
        ).accepted
    }

    static func report(
        for event: ServeEvent,
        in sequence: PoseSequence,
        thresholds: LiveServeEventValidationThresholds = .default
    ) -> LiveServeEventValidationReport {
        let impactDelay = event.impactTimeSeconds - event.trophyTimeSeconds
        var rejectionReasons: [String] = []

        let preImpactMetrics = metricsLeadingIntoImpact(
            event: event,
            sequence: sequence
        )

        let trophySupportCount = preImpactMetrics.filter { metrics in
            abs(metrics.timestampSeconds - event.trophyTimeSeconds) <= 0.45
                && metrics.trophyScore >= thresholds.minimumTrophyPeakScore
        }.count
        let maxTossWristLift = preImpactMetrics.map(\.tossWristLiftRatio).max() ?? 0.0
        let maxTossArmAngle = preImpactMetrics.map(\.tossArmAngle).max() ?? 0.0
        let impactSnapshot = impactSnapshot(
            near: event.impactTimeSeconds,
            handedness: event.handedness,
            sequence: sequence
        )

        if impactDelay < thresholds.minimumImpactDelaySeconds || impactDelay > thresholds.maximumImpactDelaySeconds {
            rejectionReasons.append("impact_delay")
        }

        if preImpactMetrics.isEmpty {
            rejectionReasons.append("missing_preimpact")
        }

        var satisfiedSignals = 0
        if trophySupportCount >= thresholds.minimumTrophySupportFrames {
            satisfiedSignals += 1
        } else {
            rejectionReasons.append("weak_trophy")
        }

        if maxTossWristLift >= thresholds.minimumTossWristLiftRatio {
            satisfiedSignals += 1
        } else {
            rejectionReasons.append("low_toss_lift")
        }

        if maxTossArmAngle >= thresholds.minimumTossArmAngle {
            satisfiedSignals += 1
        } else {
            rejectionReasons.append("low_toss_angle")
        }

        if let impactSnapshot {
            if impactSnapshot.shoulderMarginRatio >= thresholds.minimumImpactShoulderMargin {
                satisfiedSignals += 1
            } else {
                rejectionReasons.append("low_impact_margin")
            }

            if impactSnapshot.wristLiftRatio >= thresholds.minimumImpactWristLiftRatio {
                satisfiedSignals += 1
            } else {
                rejectionReasons.append("low_impact_lift")
            }
        } else {
            rejectionReasons.append("missing_impact_frame")
        }

        let signalScore = Double(satisfiedSignals) / 5.0
        let hasDelayFailure = rejectionReasons.contains("impact_delay")
        let hasImpactSignal = impactSnapshot.map {
            $0.shoulderMarginRatio >= thresholds.minimumImpactShoulderMargin
                || $0.wristLiftRatio >= thresholds.minimumImpactWristLiftRatio
        } ?? false
        let hasTossSignal = trophySupportCount >= thresholds.minimumTrophySupportFrames
            || maxTossWristLift >= thresholds.minimumTossWristLiftRatio
            || maxTossArmAngle >= thresholds.minimumTossArmAngle

        return LiveServeEventValidationReport(
            accepted: !hasDelayFailure
                && hasImpactSignal
                && hasTossSignal
                && satisfiedSignals >= thresholds.minimumSatisfiedSignals,
            impactDelay: impactDelay,
            trophySupportCount: trophySupportCount,
            maxTossWristLift: maxTossWristLift,
            maxTossArmAngle: maxTossArmAngle,
            impactShoulderMargin: impactSnapshot?.shoulderMarginRatio,
            impactWristLift: impactSnapshot?.wristLiftRatio,
            satisfiedSignals: satisfiedSignals,
            signalScore: signalScore,
            rejectionReasons: rejectionReasons
        )
    }

    private static func metricsLeadingIntoImpact(
        event: ServeEvent,
        sequence: PoseSequence
    ) -> [FrameMetrics] {
        let windowStart = max(0.0, event.impactTimeSeconds - 2.5)
        let windowEnd = event.impactTimeSeconds - 0.05

        return sequence.frames.compactMap { frame in
            guard frame.timestampSeconds >= windowStart, frame.timestampSeconds <= windowEnd else {
                return nil
            }
            return sideFrameMetrics(frame: frame, handedness: event.handedness)
        }
    }

    private static func impactSnapshot(
        near impactTime: Double,
        handedness: Handedness,
        sequence: PoseSequence
    ) -> LiveImpactSnapshot? {
        guard let impactFrame = nearestFrame(to: impactTime, in: sequence.frames) else {
            return nil
        }
        return impactSnapshot(frame: impactFrame, handedness: handedness)
    }

    private static func nearestFrame(to timestamp: Double, in frames: [PoseFrame]) -> PoseFrame? {
        frames.min { lhs, rhs in
            abs(lhs.timestampSeconds - timestamp) < abs(rhs.timestampSeconds - timestamp)
        }
    }

    private static func impactSnapshot(
        frame: PoseFrame,
        handedness: Handedness
    ) -> LiveImpactSnapshot? {
        guard
            let leftShoulder = frame.point(.leftShoulder),
            let rightShoulder = frame.point(.rightShoulder),
            let leftHip = frame.point(.leftHip),
            let rightHip = frame.point(.rightHip),
            let hitShoulder = frame.point(handedness == .right ? .rightShoulder : .leftShoulder),
            let hitWrist = frame.point(handedness == .right ? .rightWrist : .leftWrist)
        else {
            return nil
        }

        let shoulderCenter = midpoint(leftShoulder, rightShoulder)
        let bodyScale = max(distance(leftShoulder, rightShoulder), distance(leftHip, rightHip), 1e-6)
        return LiveImpactSnapshot(
            wristLiftRatio: (shoulderCenter.y - hitWrist.y) / bodyScale,
            shoulderMarginRatio: (hitShoulder.y - hitWrist.y) / bodyScale
        )
    }
}
