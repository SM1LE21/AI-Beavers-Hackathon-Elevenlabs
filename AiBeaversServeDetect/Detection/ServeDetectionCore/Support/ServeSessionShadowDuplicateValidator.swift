import Foundation

public enum ServeSessionShadowRecentMotionKind: String {
    case clear
    case duplicate
    case nonserveMotion
}

struct ServeSessionShadowDuplicateThresholds {
    let recentWindowSeconds: Double
    let maximumResetOnlyWindowSeconds: Double
    let staleWindowSlackSeconds: Double
    let minimumStaleImpactDelaySeconds: Double
    let maximumBodyDriftRatio: Double
    let maximumScaleChangeRatio: Double
    let maximumImpactLiftDifference: Double
    let maximumTossLiftDifference: Double
    let maximumImpactDelayDifference: Double
    let minimumSimilaritySignals: Int

    static let `default` = ServeSessionShadowDuplicateThresholds(
        recentWindowSeconds: 4.5,
        maximumResetOnlyWindowSeconds: 2.25,
        staleWindowSlackSeconds: 0.15,
        minimumStaleImpactDelaySeconds: 1.75,
        maximumBodyDriftRatio: 0.95,
        maximumScaleChangeRatio: 0.30,
        maximumImpactLiftDifference: 0.22,
        maximumTossLiftDifference: 0.18,
        maximumImpactDelayDifference: 0.45,
        minimumSimilaritySignals: 3
    )
}

public struct ServeSessionShadowDuplicateReport {
    public let accepted: Bool
    public let impactGapSeconds: Double
    public let staleWindowOverlapSeconds: Double
    public let similaritySignals: Int
    public let recentMotionKind: ServeSessionShadowRecentMotionKind
    public let rejectionReasons: [String]

    public init(
        accepted: Bool,
        impactGapSeconds: Double,
        staleWindowOverlapSeconds: Double,
        similaritySignals: Int,
        recentMotionKind: ServeSessionShadowRecentMotionKind,
        rejectionReasons: [String]
    ) {
        self.accepted = accepted
        self.impactGapSeconds = impactGapSeconds
        self.staleWindowOverlapSeconds = staleWindowOverlapSeconds
        self.similaritySignals = similaritySignals
        self.recentMotionKind = recentMotionKind
        self.rejectionReasons = rejectionReasons
    }
}

private struct ServeSessionShadowEventFingerprint {
    let impactBodyState: ServeSessionShadowBodyState
    let impactWristLiftRatio: Double
    let trophyTossLiftRatio: Double
    let impactDelaySeconds: Double
}

enum ServeSessionShadowDuplicateValidator {
    static func report(
        current: ServeEvent,
        previous: ServeEvent?,
        in sequence: PoseSequence,
        resetSatisfied: Bool,
        tossStrength: ServeSessionShadowLifecycleStrength,
        impactStrength: ServeSessionShadowImpactStrength,
        thresholds: ServeSessionShadowDuplicateThresholds = .default
    ) -> ServeSessionShadowDuplicateReport {
        guard let previous else {
            return ServeSessionShadowDuplicateReport(
                accepted: true,
                impactGapSeconds: 0.0,
                staleWindowOverlapSeconds: 0.0,
                similaritySignals: 0,
                recentMotionKind: .clear,
                rejectionReasons: []
            )
        }

        let impactGapSeconds = current.impactTimeSeconds - previous.impactTimeSeconds
        guard impactGapSeconds > 0, impactGapSeconds <= thresholds.recentWindowSeconds else {
            return ServeSessionShadowDuplicateReport(
                accepted: true,
                impactGapSeconds: impactGapSeconds,
                staleWindowOverlapSeconds: 0.0,
                similaritySignals: 0,
                recentMotionKind: .clear,
                rejectionReasons: []
            )
        }
        guard current.handedness == previous.handedness else {
            return ServeSessionShadowDuplicateReport(
                accepted: true,
                impactGapSeconds: impactGapSeconds,
                staleWindowOverlapSeconds: 0.0,
                similaritySignals: 0,
                recentMotionKind: .clear,
                rejectionReasons: []
            )
        }

        let staleWindowOverlapSeconds = (previous.endTimeSeconds + thresholds.staleWindowSlackSeconds)
            - current.trophyTimeSeconds
        let similaritySignals = similaritySignalCount(
            current: current,
            previous: previous,
            in: sequence,
            thresholds: thresholds
        )

        var rejectionReasons: [String] = []
        let recentMotionKind: ServeSessionShadowRecentMotionKind
        if staleWindowOverlapSeconds > 0,
           current.impactTimeSeconds - current.trophyTimeSeconds >= thresholds.minimumStaleImpactDelaySeconds
        {
            rejectionReasons.append("stale_trophy_pairing")
            recentMotionKind = .duplicate
        } else if !resetSatisfied && impactGapSeconds <= thresholds.maximumResetOnlyWindowSeconds {
            rejectionReasons.append("duplicate_without_reset")
            recentMotionKind = .duplicate
        } else if similaritySignals >= thresholds.minimumSimilaritySignals {
            rejectionReasons.append("duplicate_after_recent_emit")
            recentMotionKind = .duplicate
        } else if tossStrength == .missing,
                  impactStrength != .credible
        {
            rejectionReasons.append("recent_nonserve_motion")
            recentMotionKind = .nonserveMotion
        } else {
            recentMotionKind = .clear
        }

        return ServeSessionShadowDuplicateReport(
            accepted: rejectionReasons.isEmpty,
            impactGapSeconds: impactGapSeconds,
            staleWindowOverlapSeconds: max(staleWindowOverlapSeconds, 0.0),
            similaritySignals: similaritySignals,
            recentMotionKind: recentMotionKind,
            rejectionReasons: rejectionReasons
        )
    }

    private static func similaritySignalCount(
        current: ServeEvent,
        previous: ServeEvent,
        in sequence: PoseSequence,
        thresholds: ServeSessionShadowDuplicateThresholds
    ) -> Int {
        guard
            let currentFingerprint = fingerprint(for: current, in: sequence),
            let previousFingerprint = fingerprint(for: previous, in: sequence)
        else {
            return 0
        }

        var signals = 0
        if serveSessionShadowTorsoJumpRatio(
            from: previousFingerprint.impactBodyState,
            to: currentFingerprint.impactBodyState
        ) <= thresholds.maximumBodyDriftRatio {
            signals += 1
        }
        if serveSessionShadowBodyScaleChangeRatio(
            from: previousFingerprint.impactBodyState,
            to: currentFingerprint.impactBodyState
        ) <= thresholds.maximumScaleChangeRatio {
            signals += 1
        }
        if abs(currentFingerprint.impactWristLiftRatio - previousFingerprint.impactWristLiftRatio)
            <= thresholds.maximumImpactLiftDifference
        {
            signals += 1
        }
        if abs(currentFingerprint.trophyTossLiftRatio - previousFingerprint.trophyTossLiftRatio)
            <= thresholds.maximumTossLiftDifference
        {
            signals += 1
        }
        if abs(currentFingerprint.impactDelaySeconds - previousFingerprint.impactDelaySeconds)
            <= thresholds.maximumImpactDelayDifference
        {
            signals += 1
        }

        return signals
    }

    private static func fingerprint(
        for event: ServeEvent,
        in sequence: PoseSequence
    ) -> ServeSessionShadowEventFingerprint? {
        guard
            let impactFrame = nearestFrame(
                in: sequence,
                timestampSeconds: event.impactTimeSeconds,
                toleranceSeconds: 0.18
            ),
            let trophyFrame = nearestFrame(
                in: sequence,
                timestampSeconds: event.trophyTimeSeconds,
                toleranceSeconds: 0.25
            ),
            let impactBodyState = serveSessionShadowBodyState(for: impactFrame),
            let trophyMetrics = sideFrameMetrics(frame: trophyFrame, handedness: event.handedness)
        else {
            return nil
        }

        return ServeSessionShadowEventFingerprint(
            impactBodyState: impactBodyState,
            impactWristLiftRatio: hitWristLiftRatio(
                for: impactFrame,
                handedness: event.handedness,
                bodyScale: impactBodyState.bodyScale
            ),
            trophyTossLiftRatio: trophyMetrics.tossWristLiftRatio,
            impactDelaySeconds: max(event.impactTimeSeconds - event.trophyTimeSeconds, 0.0)
        )
    }

    private static func nearestFrame(
        in sequence: PoseSequence,
        timestampSeconds: Double,
        toleranceSeconds: Double
    ) -> PoseFrame? {
        let nearest = sequence.frames.min(by: { lhs, rhs in
            abs(lhs.timestampSeconds - timestampSeconds) < abs(rhs.timestampSeconds - timestampSeconds)
        })
        guard let nearest else {
            return nil
        }
        return abs(nearest.timestampSeconds - timestampSeconds) <= toleranceSeconds ? nearest : nil
    }

    private static func hitWristLiftRatio(
        for frame: PoseFrame,
        handedness: Handedness,
        bodyScale: Double
    ) -> Double {
        guard
            let leftShoulder = frame.point(.leftShoulder),
            let rightShoulder = frame.point(.rightShoulder),
            let hitWrist = frame.point(handedness == .right ? .rightWrist : .leftWrist)
        else {
            return 0.0
        }

        let shoulderCenter = midpoint(leftShoulder, rightShoulder)
        return (shoulderCenter.y - hitWrist.y) / max(bodyScale, 1e-6)
    }
}
