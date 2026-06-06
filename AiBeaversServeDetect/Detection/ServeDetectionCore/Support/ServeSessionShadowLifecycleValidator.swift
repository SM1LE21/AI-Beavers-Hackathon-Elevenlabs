import CoreGraphics
import Foundation

public enum ServeSessionShadowLifecycleStrength: String {
    case strong
    case weak
    case missing

    public var accepted: Bool {
        self != .missing
    }
}

public enum ServeSessionShadowImpactStrength: String {
    case credible
    case weak
    case missing

    public var accepted: Bool {
        self != .missing
    }
}

struct ServeSessionShadowLifecycleThresholds {
    let tossLeadInSeconds: Double
    let tossWindowPaddingSeconds: Double
    let minimumTossFrameCount: Int
    let strongTossPeakLiftRatio: Double
    let weakTossPeakLiftRatio: Double
    let strongTossRiseRatio: Double
    let weakTossRiseRatio: Double
    let strongPeakTrophyScore: Double
    let weakPeakTrophyScore: Double
    let minimumRaisedTossFrames: Int
    let minimumRisingSteps: Int
    let minimumRisingStepDelta: Double
    let followThroughSeconds: Double
    let minimumFollowThroughFrameCount: Int
    let strongImpactWristLiftRatio: Double
    let weakImpactWristLiftRatio: Double
    let strongImpactShoulderMarginRatio: Double
    let weakImpactShoulderMarginRatio: Double
    let strongImpactElbowAngle: Double
    let weakImpactElbowAngle: Double
    let strongHitDropRatio: Double
    let weakHitDropRatio: Double
    let strongHitTravelRatio: Double
    let weakHitTravelRatio: Double
    let extremeTossPeakLiftRatio: Double
    let extremeTossRiseRatio: Double
    let extremeHitTravelRatio: Double

    static let `default` = ServeSessionShadowLifecycleThresholds(
        tossLeadInSeconds: 0.75,
        tossWindowPaddingSeconds: 0.20,
        minimumTossFrameCount: 4,
        strongTossPeakLiftRatio: 0.16,
        weakTossPeakLiftRatio: 0.08,
        strongTossRiseRatio: 0.14,
        weakTossRiseRatio: 0.08,
        strongPeakTrophyScore: 0.30,
        weakPeakTrophyScore: 0.22,
        minimumRaisedTossFrames: 2,
        minimumRisingSteps: 2,
        minimumRisingStepDelta: 0.02,
        followThroughSeconds: 0.45,
        minimumFollowThroughFrameCount: 3,
        strongImpactWristLiftRatio: 0.16,
        weakImpactWristLiftRatio: 0.06,
        strongImpactShoulderMarginRatio: 0.22,
        weakImpactShoulderMarginRatio: 0.12,
        strongImpactElbowAngle: 148.0,
        weakImpactElbowAngle: 135.0,
        strongHitDropRatio: 0.10,
        weakHitDropRatio: 0.05,
        strongHitTravelRatio: 0.20,
        weakHitTravelRatio: 0.10,
        extremeTossPeakLiftRatio: 4.0,
        extremeTossRiseRatio: 6.0,
        extremeHitTravelRatio: 4.5
    )
}

public struct ServeSessionShadowLifecycleReport {
    public let tossStrength: ServeSessionShadowLifecycleStrength
    public let impactStrength: ServeSessionShadowImpactStrength
    public let followThroughStrength: ServeSessionShadowLifecycleStrength
    public let tossFrameCount: Int
    public let followThroughFrameCount: Int
    public let tossPeakLiftRatio: Double
    public let tossRiseRatio: Double
    public let tossRaisedFrameCount: Int
    public let tossRisingStepCount: Int
    public let peakTrophyScore: Double
    /// Toss-arm elbow angle at the trophy frame, in degrees. nil when no sample falls
    /// within the trophy tolerance window. Added 2026-05-04 (v0.2.0) to enable
    /// pose-frame-free downstream technique analysis.
    public let tossArmAngleAtTrophy: Double?
    public let impactWristLiftRatio: Double
    public let impactShoulderMarginRatio: Double
    public let impactElbowAngle: Double
    public let impactDelaySeconds: Double
    public let hitDropRatio: Double
    public let hitTravelRatio: Double
    public let outlierSignalCount: Int
    public let outlierReasons: [String]
    public let rejectionReasons: [String]
    public let noteReasons: [String]

    public init(
        tossStrength: ServeSessionShadowLifecycleStrength,
        impactStrength: ServeSessionShadowImpactStrength,
        followThroughStrength: ServeSessionShadowLifecycleStrength,
        tossFrameCount: Int,
        followThroughFrameCount: Int,
        tossPeakLiftRatio: Double,
        tossRiseRatio: Double,
        tossRaisedFrameCount: Int,
        tossRisingStepCount: Int,
        peakTrophyScore: Double,
        tossArmAngleAtTrophy: Double?,
        impactWristLiftRatio: Double,
        impactShoulderMarginRatio: Double,
        impactElbowAngle: Double,
        impactDelaySeconds: Double,
        hitDropRatio: Double,
        hitTravelRatio: Double,
        outlierSignalCount: Int,
        outlierReasons: [String],
        rejectionReasons: [String],
        noteReasons: [String]
    ) {
        self.tossStrength = tossStrength
        self.impactStrength = impactStrength
        self.followThroughStrength = followThroughStrength
        self.tossFrameCount = tossFrameCount
        self.followThroughFrameCount = followThroughFrameCount
        self.tossPeakLiftRatio = tossPeakLiftRatio
        self.tossRiseRatio = tossRiseRatio
        self.tossRaisedFrameCount = tossRaisedFrameCount
        self.tossRisingStepCount = tossRisingStepCount
        self.peakTrophyScore = peakTrophyScore
        self.tossArmAngleAtTrophy = tossArmAngleAtTrophy
        self.impactWristLiftRatio = impactWristLiftRatio
        self.impactShoulderMarginRatio = impactShoulderMarginRatio
        self.impactElbowAngle = impactElbowAngle
        self.impactDelaySeconds = impactDelaySeconds
        self.hitDropRatio = hitDropRatio
        self.hitTravelRatio = hitTravelRatio
        self.outlierSignalCount = outlierSignalCount
        self.outlierReasons = outlierReasons
        self.rejectionReasons = rejectionReasons
        self.noteReasons = noteReasons
    }

    public var tossAccepted: Bool {
        tossStrength.accepted
    }

    public var followThroughAccepted: Bool {
        followThroughStrength.accepted
    }

    public var hasStrongLifecycle: Bool {
        tossStrength == .strong
            && impactStrength == .credible
            && followThroughStrength == .strong
    }
}

private struct ServeSessionShadowLifecycleSample {
    let timestampSeconds: Double
    let trophyScore: Double
    let tossArmAngle: Double
    let tossWristLiftRatio: Double
    let hitWristLiftRatio: Double
    let hitShoulderMarginRatio: Double
    let hitElbowAngle: Double
    let hitWristPoint: CGPoint
    let bodyScale: Double
}

enum ServeSessionShadowLifecycleValidator {
    static func report(
        for event: ServeEvent,
        in sequence: PoseSequence,
        thresholds: ServeSessionShadowLifecycleThresholds = .default
    ) -> ServeSessionShadowLifecycleReport {
        let impactDelaySeconds = max(event.impactTimeSeconds - event.trophyTimeSeconds, 0.0)
        let tossSamples = samples(
            in: sequence,
            handedness: event.handedness,
            startTime: max(0.0, event.trophyTimeSeconds - thresholds.tossLeadInSeconds),
            endTime: min(event.impactTimeSeconds - 0.05, event.trophyTimeSeconds + thresholds.tossWindowPaddingSeconds)
        )
        let tossReport = evaluateTossLifecycle(
            tossSamples,
            targetTimestamp: event.trophyTimeSeconds,
            thresholds: thresholds
        )

        let impactSample = nearestSample(
            in: sequence,
            handedness: event.handedness,
            timestampSeconds: event.impactTimeSeconds,
            toleranceSeconds: 0.18
        )
        let impactStrength = evaluateImpactStrength(
            impactSample,
            thresholds: thresholds
        )

        let followThroughSamples = samples(
            in: sequence,
            handedness: event.handedness,
            startTime: event.impactTimeSeconds,
            endTime: event.impactTimeSeconds + thresholds.followThroughSeconds
        )
        let followThroughReport = evaluateFollowThroughLifecycle(
            followThroughSamples,
            targetTimestamp: event.impactTimeSeconds,
            impactStrength: impactStrength,
            thresholds: thresholds
        )

        var rejectionReasons: [String] = []
        var noteReasons: [String] = []
        if tossReport.strength == .missing {
            rejectionReasons.append("missing_toss_lifecycle")
        } else if tossReport.strength == .weak {
            noteReasons.append("weak_toss_lifecycle")
        }
        if followThroughReport.strength == .missing {
            rejectionReasons.append("missing_followthrough_lifecycle")
        } else if followThroughReport.strength == .weak {
            noteReasons.append("weak_followthrough_lifecycle")
        }
        let outlierReasons = evaluateOutlierReasons(
            tossPeakLiftRatio: tossReport.peakLiftRatio,
            tossRiseRatio: tossReport.riseRatio,
            hitTravelRatio: followThroughReport.travelRatio,
            thresholds: thresholds
        )

        // Sample nearest the trophy frame to surface tossArmAngleAtTrophy as a public signal.
        // Reuses the same toss-arm extraction the per-frame metrics already compute.
        let trophySample = nearestSample(
            in: sequence,
            handedness: event.handedness,
            timestampSeconds: event.trophyTimeSeconds,
            toleranceSeconds: 0.18
        )

        return ServeSessionShadowLifecycleReport(
            tossStrength: tossReport.strength,
            impactStrength: impactStrength,
            followThroughStrength: followThroughReport.strength,
            tossFrameCount: tossReport.frameCount,
            followThroughFrameCount: followThroughReport.frameCount,
            tossPeakLiftRatio: tossReport.peakLiftRatio,
            tossRiseRatio: tossReport.riseRatio,
            tossRaisedFrameCount: tossReport.raisedFrameCount,
            tossRisingStepCount: tossReport.risingStepCount,
            peakTrophyScore: tossReport.peakTrophyScore,
            tossArmAngleAtTrophy: trophySample?.tossArmAngle,
            impactWristLiftRatio: impactSample?.hitWristLiftRatio ?? 0.0,
            impactShoulderMarginRatio: impactSample?.hitShoulderMarginRatio ?? 0.0,
            impactElbowAngle: impactSample?.hitElbowAngle ?? 0.0,
            impactDelaySeconds: impactDelaySeconds,
            hitDropRatio: followThroughReport.dropRatio,
            hitTravelRatio: followThroughReport.travelRatio,
            outlierSignalCount: outlierReasons.count,
            outlierReasons: outlierReasons,
            rejectionReasons: rejectionReasons,
            noteReasons: noteReasons
        )
    }

    private static func samples(
        in sequence: PoseSequence,
        handedness: Handedness,
        startTime: Double,
        endTime: Double
    ) -> [ServeSessionShadowLifecycleSample] {
        guard endTime > startTime else {
            return []
        }

        return sequence.frames.compactMap { frame in
            guard frame.timestampSeconds >= startTime, frame.timestampSeconds <= endTime else {
                return nil
            }
            return lifecycleSample(for: frame, handedness: handedness)
        }
    }

    private static func nearestSample(
        in sequence: PoseSequence,
        handedness: Handedness,
        timestampSeconds: Double,
        toleranceSeconds: Double
    ) -> ServeSessionShadowLifecycleSample? {
        let sample = sequence.frames.compactMap { frame in
            lifecycleSample(for: frame, handedness: handedness)
        }.min(by: { lhs, rhs in
            abs(lhs.timestampSeconds - timestampSeconds) < abs(rhs.timestampSeconds - timestampSeconds)
        })
        guard let sample else {
            return nil
        }
        return abs(sample.timestampSeconds - timestampSeconds) <= toleranceSeconds ? sample : nil
    }

    private static func lifecycleSample(
        for frame: PoseFrame,
        handedness: Handedness
    ) -> ServeSessionShadowLifecycleSample? {
        guard
            let metrics = sideFrameMetrics(frame: frame, handedness: handedness),
            let leftShoulder = frame.point(.leftShoulder),
            let rightShoulder = frame.point(.rightShoulder),
            let leftHip = frame.point(.leftHip),
            let rightHip = frame.point(.rightHip),
            let hitShoulder = frame.point(handedness == .right ? .rightShoulder : .leftShoulder),
            let hitElbow = frame.point(handedness == .right ? .rightElbow : .leftElbow),
            let hitWrist = frame.point(handedness == .right ? .rightWrist : .leftWrist)
        else {
            return nil
        }

        let shoulderCenter = midpoint(leftShoulder, rightShoulder)
        let bodyScale = max(distance(leftShoulder, rightShoulder), distance(leftHip, rightHip), 1e-6)
        return ServeSessionShadowLifecycleSample(
            timestampSeconds: frame.timestampSeconds,
            trophyScore: metrics.trophyScore,
            tossArmAngle: metrics.tossArmAngle,
            tossWristLiftRatio: metrics.tossWristLiftRatio,
            hitWristLiftRatio: (shoulderCenter.y - hitWrist.y) / bodyScale,
            hitShoulderMarginRatio: (hitShoulder.y - hitWrist.y) / bodyScale,
            hitElbowAngle: angleDegrees(hitShoulder, hitElbow, hitWrist),
            hitWristPoint: hitWrist,
            bodyScale: bodyScale
        )
    }

    private static func evaluateTossLifecycle(
        _ samples: [ServeSessionShadowLifecycleSample],
        targetTimestamp: Double,
        thresholds: ServeSessionShadowLifecycleThresholds
    ) -> (
        strength: ServeSessionShadowLifecycleStrength,
        frameCount: Int,
        peakLiftRatio: Double,
        riseRatio: Double,
        raisedFrameCount: Int,
        risingStepCount: Int,
        peakTrophyScore: Double
    ) {
        guard samples.count >= thresholds.minimumTossFrameCount else {
            return (.missing, samples.count, 0.0, 0.0, 0, 0, 0.0)
        }

        let peakIndex = samples.indices.min(by: { lhs, rhs in
            abs(samples[lhs].timestampSeconds - targetTimestamp) < abs(samples[rhs].timestampSeconds - targetTimestamp)
        }) ?? (samples.count - 1)
        let leadInSamples = Array(samples[...peakIndex])
        let baselineLift = leadInSamples.map(\.tossWristLiftRatio).min() ?? 0.0
        let peakLift = leadInSamples.map(\.tossWristLiftRatio).max() ?? 0.0
        let peakTrophyScore = leadInSamples.map(\.trophyScore).max() ?? 0.0
        let riseRatio = peakLift - baselineLift
        let raisedFrameCount = leadInSamples.filter {
            $0.tossWristLiftRatio >= thresholds.weakTossPeakLiftRatio
        }.count
        let risingStepCount = zip(leadInSamples.dropLast(), leadInSamples.dropFirst())
            .filter { earlier, later in
                later.tossWristLiftRatio - earlier.tossWristLiftRatio >= thresholds.minimumRisingStepDelta
            }
            .count

        let strength: ServeSessionShadowLifecycleStrength
        if peakLift >= thresholds.strongTossPeakLiftRatio
            && riseRatio >= thresholds.strongTossRiseRatio
            && (peakTrophyScore >= thresholds.weakPeakTrophyScore
                || raisedFrameCount >= thresholds.minimumRaisedTossFrames)
        {
            strength = .strong
        } else if peakLift >= thresholds.weakTossPeakLiftRatio
            && riseRatio >= thresholds.weakTossRiseRatio
            && (peakTrophyScore >= thresholds.weakPeakTrophyScore
                || raisedFrameCount >= thresholds.minimumRaisedTossFrames
                || risingStepCount >= thresholds.minimumRisingSteps)
        {
            strength = peakTrophyScore >= thresholds.strongPeakTrophyScore ? .strong : .weak
        } else if peakTrophyScore >= thresholds.strongPeakTrophyScore
            && raisedFrameCount >= thresholds.minimumRaisedTossFrames
            && risingStepCount >= thresholds.minimumRisingSteps
        {
            strength = .strong
        } else if peakTrophyScore >= thresholds.weakPeakTrophyScore
            && raisedFrameCount >= thresholds.minimumRaisedTossFrames
        {
            strength = .weak
        } else {
            strength = .missing
        }

        return (
            strength,
            samples.count,
            peakLift,
            riseRatio,
            raisedFrameCount,
            risingStepCount,
            peakTrophyScore
        )
    }

    private static func evaluateImpactStrength(
        _ sample: ServeSessionShadowLifecycleSample?,
        thresholds: ServeSessionShadowLifecycleThresholds
    ) -> ServeSessionShadowImpactStrength {
        guard let sample else {
            return .missing
        }

        if sample.hitWristLiftRatio >= thresholds.strongImpactWristLiftRatio
            && sample.hitShoulderMarginRatio >= thresholds.strongImpactShoulderMarginRatio
            && sample.hitElbowAngle >= thresholds.strongImpactElbowAngle
        {
            return .credible
        }
        if sample.hitWristLiftRatio >= thresholds.weakImpactWristLiftRatio
            && sample.hitShoulderMarginRatio >= thresholds.weakImpactShoulderMarginRatio
            && sample.hitElbowAngle >= thresholds.weakImpactElbowAngle
        {
            return .weak
        }
        return .missing
    }

    private static func evaluateFollowThroughLifecycle(
        _ samples: [ServeSessionShadowLifecycleSample],
        targetTimestamp: Double,
        impactStrength: ServeSessionShadowImpactStrength,
        thresholds: ServeSessionShadowLifecycleThresholds
    ) -> (
        strength: ServeSessionShadowLifecycleStrength,
        frameCount: Int,
        dropRatio: Double,
        travelRatio: Double
    ) {
        guard samples.count >= thresholds.minimumFollowThroughFrameCount else {
            return (.missing, samples.count, 0.0, 0.0)
        }

        let impactIndex = samples.indices.min(by: { lhs, rhs in
            abs(samples[lhs].timestampSeconds - targetTimestamp) < abs(samples[rhs].timestampSeconds - targetTimestamp)
        }) ?? 0
        let impactSample = samples[impactIndex]
        let followThroughSamples = Array(samples[impactIndex...])
        let minimumPostImpactLift = followThroughSamples.map(\.hitWristLiftRatio).min() ?? impactSample.hitWristLiftRatio
        let hitDropRatio = impactSample.hitWristLiftRatio - minimumPostImpactLift
        let hitTravelRatio = followThroughSamples.map { sample in
            distance(sample.hitWristPoint, impactSample.hitWristPoint) / max(sample.bodyScale, impactSample.bodyScale, 1e-6)
        }.max() ?? 0.0

        let strength: ServeSessionShadowLifecycleStrength
        if impactStrength == .credible
            && (hitDropRatio >= thresholds.strongHitDropRatio
                || hitTravelRatio >= thresholds.strongHitTravelRatio)
        {
            strength = .strong
        } else if impactStrength.accepted
            && (hitDropRatio >= thresholds.weakHitDropRatio
                || hitTravelRatio >= thresholds.weakHitTravelRatio)
        {
            strength = .weak
        } else {
            strength = .missing
        }

        return (strength, samples.count, hitDropRatio, hitTravelRatio)
    }

    private static func evaluateOutlierReasons(
        tossPeakLiftRatio: Double,
        tossRiseRatio: Double,
        hitTravelRatio: Double,
        thresholds: ServeSessionShadowLifecycleThresholds
    ) -> [String] {
        var reasons: [String] = []
        if tossPeakLiftRatio >= thresholds.extremeTossPeakLiftRatio {
            reasons.append("extreme_toss_peak")
        }
        if tossRiseRatio >= thresholds.extremeTossRiseRatio {
            reasons.append("extreme_toss_rise")
        }
        if hitTravelRatio >= thresholds.extremeHitTravelRatio {
            reasons.append("extreme_hit_travel")
        }
        return reasons
    }
}
