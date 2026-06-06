import Foundation

public enum ServeSessionDetectionMode: String, CaseIterable, Identifiable {
    case legacyWithShadow
    case shadowPrimary

    public var id: String {
        rawValue
    }

    public var usesShadowReview: Bool {
        self == .legacyWithShadow
    }

    public var usesShadowAsPrimaryGate: Bool {
        self == .shadowPrimary
    }

    public var shortTitle: String {
        switch self {
        case .legacyWithShadow:
            return "Legacy"
        case .shadowPrimary:
            return "New"
        }
    }

    public var displayTitle: String {
        switch self {
        case .legacyWithShadow:
            return "Legacy + Shadow"
        case .shadowPrimary:
            return "New Detection"
        }
    }
}

public struct LiveCaptureAnalysisStats {
    public let provider: LivePoseProviderKind
    public let rawFrames: Int
    public let acceptedFrames: Int
    public let droppedFrames: Int

    public init(
        provider: LivePoseProviderKind,
        rawFrames: Int,
        acceptedFrames: Int,
        droppedFrames: Int
    ) {
        self.provider = provider
        self.rawFrames = rawFrames
        self.acceptedFrames = acceptedFrames
        self.droppedFrames = droppedFrames
    }
}

public struct LiveServeRejectedCandidate: Identifiable {
    public let id = UUID()
    public let provider: LivePoseProviderKind
    public let impactTimeSeconds: Double
    public let trophyTimeSeconds: Double
    public let confidence: Double
    public let delaySeconds: Double
    public let rejectionSummary: String
    public let signalScore: Double

    public init(
        provider: LivePoseProviderKind,
        impactTimeSeconds: Double,
        trophyTimeSeconds: Double,
        confidence: Double,
        delaySeconds: Double,
        rejectionSummary: String,
        signalScore: Double
    ) {
        self.provider = provider
        self.impactTimeSeconds = impactTimeSeconds
        self.trophyTimeSeconds = trophyTimeSeconds
        self.confidence = confidence
        self.delaySeconds = delaySeconds
        self.rejectionSummary = rejectionSummary
        self.signalScore = signalScore
    }
}

public struct LiveServeDebugSnapshot {
    public let provider: LivePoseProviderKind
    public let passedPresenceGate: Bool
    public let presenceValidRatio: Double
    public let presenceReason: String?
    public let presenceBodyHeight: Double
    public let presenceTorsoHeight: Double
    public let sequenceFrameCount: Int
    public let segmentationEventCount: Int
    public let pendingEventCount: Int
    public let rejectedEventCount: Int
    public let dedupedEventCount: Int
    public let eligibleEventCount: Int

    public init(
        provider: LivePoseProviderKind,
        passedPresenceGate: Bool,
        presenceValidRatio: Double,
        presenceReason: String?,
        presenceBodyHeight: Double,
        presenceTorsoHeight: Double,
        sequenceFrameCount: Int,
        segmentationEventCount: Int,
        pendingEventCount: Int,
        rejectedEventCount: Int,
        dedupedEventCount: Int,
        eligibleEventCount: Int
    ) {
        self.provider = provider
        self.passedPresenceGate = passedPresenceGate
        self.presenceValidRatio = presenceValidRatio
        self.presenceReason = presenceReason
        self.presenceBodyHeight = presenceBodyHeight
        self.presenceTorsoHeight = presenceTorsoHeight
        self.sequenceFrameCount = sequenceFrameCount
        self.segmentationEventCount = segmentationEventCount
        self.pendingEventCount = pendingEventCount
        self.rejectedEventCount = rejectedEventCount
        self.dedupedEventCount = dedupedEventCount
        self.eligibleEventCount = eligibleEventCount
    }
}

public struct LiveServeIngestResult {
    public let emittedServe: ServeEvent?
    public let snapshot: LiveServeDebugSnapshot
    public let rejectedCandidates: [LiveServeRejectedCandidate]
    public let shadowVerdict: ServeSessionShadowVerdict?
    public let shadowEvaluation: ServeSessionShadowEvaluation?
    /// Candidate that was fully evaluated by the shadow system and then rejected.
    /// Non-nil only when shadowPrimary mode rejects a promoted candidate.
    /// Carries the complete signal vector — used as hard negatives in training data.
    public let shadowRejectedServe: ServeEvent?
    public let shadowRejectedEvaluation: ServeSessionShadowEvaluation?

    public init(
        emittedServe: ServeEvent?,
        snapshot: LiveServeDebugSnapshot,
        rejectedCandidates: [LiveServeRejectedCandidate],
        shadowVerdict: ServeSessionShadowVerdict?,
        shadowEvaluation: ServeSessionShadowEvaluation?,
        shadowRejectedServe: ServeEvent?,
        shadowRejectedEvaluation: ServeSessionShadowEvaluation?
    ) {
        self.emittedServe = emittedServe
        self.snapshot = snapshot
        self.rejectedCandidates = rejectedCandidates
        self.shadowVerdict = shadowVerdict
        self.shadowEvaluation = shadowEvaluation
        self.shadowRejectedServe = shadowRejectedServe
        self.shadowRejectedEvaluation = shadowRejectedEvaluation
    }
}

enum ServeSessionPrimaryGateDecision {
    case emit
    case hold
    case reject
}

struct ServeSessionPrimaryGateOutcome {
    let decision: ServeSessionPrimaryGateDecision
    let event: ServeEvent
    let evaluation: ServeSessionShadowEvaluation
}

private struct ServeSessionPrimaryPendingCandidate {
    var bestEvent: ServeEvent
    var bestEvaluation: ServeSessionShadowEvaluation
    var firstObservedAt: Double
    var lastObservedAt: Double
    var observationCount: Int

    mutating func observe(
        event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation,
        timestampSeconds: Double,
        shouldReplaceBest: Bool
    ) {
        if shouldReplaceBest {
            bestEvent = event
            bestEvaluation = evaluation
        }
        lastObservedAt = timestampSeconds
        observationCount += 1
    }
}

private struct ServeSessionPrimaryGateThresholds {
    let candidateImpactMatchSeconds: Double
    let candidateTrophyMatchSeconds: Double
    let minimumHoldSeconds: Double
    let maximumHoldSeconds: Double
    let minimumIdleFlushSeconds: Double
    let minimumObservations: Int
    let suspiciousKeepOutlierSignals: Int
    let maximumPromotableMissingTossDelaySeconds: Double
    let minimumPromotableMissingTossGapSeconds: Double
    let maximumPromotableLongDelaySeconds: Double
    let minimumPromotableMissingTossConfidence: Double
    let minimumPromotableMissingTossShoulderMarginRatio: Double
    let minimumPromotableMissingTossHitDropRatio: Double
    let minimumPromotableMissingTossHitTravelRatio: Double
    let minimumPromotableWeakFollowConfidence: Double
    let maximumPromotableMissingFollowDelaySeconds: Double
    let minimumPromotableMissingFollowConfidence: Double
    let minimumPromotableMissingFollowTrophyScore: Double
    let minimumPromotableMissingFollowShoulderMarginRatio: Double
    let minimumPromotableWeakFollowImpactLiftRatio: Double
    let minimumPromotableWeakFollowShoulderMarginRatio: Double

    static let `default` = ServeSessionPrimaryGateThresholds(
        candidateImpactMatchSeconds: 0.9,
        candidateTrophyMatchSeconds: 1.2,
        minimumHoldSeconds: 1.1,
        maximumHoldSeconds: 2.4,
        minimumIdleFlushSeconds: 0.8,
        minimumObservations: 2,
        suspiciousKeepOutlierSignals: 2,
        maximumPromotableMissingTossDelaySeconds: 1.25,
        minimumPromotableMissingTossGapSeconds: 6.5,
        maximumPromotableLongDelaySeconds: 2.0,
        minimumPromotableMissingTossConfidence: 0.58,
        minimumPromotableMissingTossShoulderMarginRatio: 0.95,
        minimumPromotableMissingTossHitDropRatio: 0.75,
        minimumPromotableMissingTossHitTravelRatio: 0.75,
        minimumPromotableWeakFollowConfidence: 0.45,
        maximumPromotableMissingFollowDelaySeconds: 0.25,
        minimumPromotableMissingFollowConfidence: 0.42,
        minimumPromotableMissingFollowTrophyScore: 0.42,
        minimumPromotableMissingFollowShoulderMarginRatio: 2.0,
        minimumPromotableWeakFollowImpactLiftRatio: 1.0,
        minimumPromotableWeakFollowShoulderMarginRatio: 0.6
    )
}

final class ServeSessionPrimaryGateTracker {
    private let thresholds = ServeSessionPrimaryGateThresholds.default
    private var pendingCandidates: [ServeSessionPrimaryPendingCandidate] = []

    func reset() {
        pendingCandidates.removeAll()
    }

    func decide(
        event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation,
        latestTimestamp: Double
    ) -> ServeSessionPrimaryGateOutcome {
        trimExpiredCandidates(latestTimestamp: latestTimestamp)

        if evaluation.verdict.disposition == .reject {
            removeMatchingCandidate(for: event)
            return ServeSessionPrimaryGateOutcome(
                decision: .reject,
                event: event,
                evaluation: evaluation
            )
        }

        let requiresHold = requiresPrimaryHold(
            event: event,
            evaluation: evaluation
        )
        if !requiresHold {
            removeMatchingCandidate(for: event)
            return ServeSessionPrimaryGateOutcome(
                decision: .emit,
                event: event,
                evaluation: evaluation
            )
        }

        let candidateIndex = upsertPendingCandidate(
            event: event,
            evaluation: evaluation,
            latestTimestamp: latestTimestamp
        )
        let candidate = pendingCandidates[candidateIndex]

        if holdWindowSatisfied(for: candidate, at: latestTimestamp) {
            if shouldPromotePendingCandidate(candidate) {
                pendingCandidates.remove(at: candidateIndex)
                return ServeSessionPrimaryGateOutcome(
                    decision: .emit,
                    event: candidate.bestEvent,
                    evaluation: candidate.bestEvaluation
                )
            }

            if holdWindowExpired(for: candidate, at: latestTimestamp) {
                pendingCandidates.remove(at: candidateIndex)
                return ServeSessionPrimaryGateOutcome(
                    decision: .reject,
                    event: candidate.bestEvent,
                    evaluation: candidate.bestEvaluation
                )
            }
        }

        return ServeSessionPrimaryGateOutcome(
            decision: .hold,
            event: candidate.bestEvent,
            evaluation: candidate.bestEvaluation
        )
    }

    func flush(
        latestTimestamp: Double
    ) -> ServeSessionPrimaryGateOutcome? {
        trimExpiredCandidates(latestTimestamp: latestTimestamp)

        guard let candidateIndex = pendingCandidates.indices.first(where: { index in
            let candidate = pendingCandidates[index]
            return candidateReadyForIdleResolution(
                candidate,
                latestTimestamp: latestTimestamp
            )
        }) else {
            return nil
        }

        let candidate = pendingCandidates[candidateIndex]
        if shouldPromotePendingCandidate(candidate) {
            pendingCandidates.remove(at: candidateIndex)
            return ServeSessionPrimaryGateOutcome(
                decision: .emit,
                event: candidate.bestEvent,
                evaluation: candidate.bestEvaluation
            )
        }

        if holdWindowExpired(for: candidate, at: latestTimestamp) {
            pendingCandidates.remove(at: candidateIndex)
            return ServeSessionPrimaryGateOutcome(
                decision: .reject,
                event: candidate.bestEvent,
                evaluation: candidate.bestEvaluation
            )
        }

        return nil
    }

    private func upsertPendingCandidate(
        event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation,
        latestTimestamp: Double
    ) -> Int {
        if let candidateIndex = pendingCandidates.firstIndex(where: { candidate in
            matches(candidate.bestEvent, event)
        }) {
            let shouldReplaceBest = isBetterEvaluation(
                event: event,
                evaluation: evaluation,
                than: pendingCandidates[candidateIndex]
            )
            pendingCandidates[candidateIndex].observe(
                event: event,
                evaluation: evaluation,
                timestampSeconds: latestTimestamp,
                shouldReplaceBest: shouldReplaceBest
            )
            return candidateIndex
        }

        pendingCandidates.append(
            ServeSessionPrimaryPendingCandidate(
                bestEvent: event,
                bestEvaluation: evaluation,
                firstObservedAt: latestTimestamp,
                lastObservedAt: latestTimestamp,
                observationCount: 1
            )
        )
        return pendingCandidates.count - 1
    }

    private func trimExpiredCandidates(latestTimestamp: Double) {
        pendingCandidates.removeAll { candidate in
            latestTimestamp - candidate.lastObservedAt > thresholds.maximumHoldSeconds * 2.0
        }
    }

    private func removeMatchingCandidate(for event: ServeEvent) {
        pendingCandidates.removeAll { candidate in
            matches(candidate.bestEvent, event)
        }
    }

    private func matches(_ lhs: ServeEvent, _ rhs: ServeEvent) -> Bool {
        lhs.handedness == rhs.handedness
            && abs(lhs.impactTimeSeconds - rhs.impactTimeSeconds) <= thresholds.candidateImpactMatchSeconds
            && abs(lhs.trophyTimeSeconds - rhs.trophyTimeSeconds) <= thresholds.candidateTrophyMatchSeconds
    }

    private func holdWindowSatisfied(
        for candidate: ServeSessionPrimaryPendingCandidate,
        at latestTimestamp: Double
    ) -> Bool {
        candidate.observationCount >= thresholds.minimumObservations
            || latestTimestamp - candidate.firstObservedAt >= thresholds.minimumHoldSeconds
    }

    private func holdWindowExpired(
        for candidate: ServeSessionPrimaryPendingCandidate,
        at latestTimestamp: Double
    ) -> Bool {
        latestTimestamp - candidate.firstObservedAt >= thresholds.maximumHoldSeconds
    }

    private func candidateReadyForIdleResolution(
        _ candidate: ServeSessionPrimaryPendingCandidate,
        latestTimestamp: Double
    ) -> Bool {
        latestTimestamp - candidate.lastObservedAt >= thresholds.minimumIdleFlushSeconds
            && holdWindowSatisfied(for: candidate, at: latestTimestamp)
    }

    private func requiresPrimaryHold(
        event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation
    ) -> Bool {
        switch evaluation.verdict.disposition {
        case .reject:
            return true
        case .review:
            return true
        case .keep:
            return isSuspiciousKeep(event: event, evaluation: evaluation)
        }
    }

    private func isSuspiciousKeep(
        event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation
    ) -> Bool {
        let lifecycleReport = evaluation.lifecycleReport
        return lifecycleReport.outlierSignalCount >= thresholds.suspiciousKeepOutlierSignals
            || !evaluation.glitchContextReasons.isEmpty
            || (!evaluation.relatedContextReasons.isEmpty && event.confidence < 0.6)
    }

    private func shouldPromotePendingCandidate(
        _ candidate: ServeSessionPrimaryPendingCandidate
    ) -> Bool {
        let evaluation = candidate.bestEvaluation
        switch evaluation.verdict.disposition {
        case .reject:
            return false
        case .keep:
            return !isSuspiciousKeep(event: candidate.bestEvent, evaluation: evaluation)
        case .review:
            return shouldPromoteReview(
                event: candidate.bestEvent,
                evaluation: evaluation
            )
        }
    }

    private func isBetterEvaluation(
        event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation,
        than candidate: ServeSessionPrimaryPendingCandidate
    ) -> Bool {
        evaluationScore(
            event: event,
            evaluation: evaluation
        ) > evaluationScore(
            event: candidate.bestEvent,
            evaluation: candidate.bestEvaluation
        )
    }

    private func evaluationScore(
        event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation
    ) -> Int {
        let lifecycleReport = evaluation.lifecycleReport
        var score = Int(event.confidence * 1000.0)

        switch evaluation.verdict.disposition {
        case .keep:
            score += 3000
        case .review:
            score += shouldPromoteReview(event: event, evaluation: evaluation) ? 2200 : 1400
        case .reject:
            score += 200
        }

        switch lifecycleReport.tossStrength {
        case .strong:
            score += 220
        case .weak:
            score += 80
        case .missing:
            score -= 120
        }

        switch lifecycleReport.impactStrength {
        case .credible:
            score += 220
        case .weak:
            score += 70
        case .missing:
            score -= 180
        }

        switch lifecycleReport.followThroughStrength {
        case .strong:
            score += 220
        case .weak:
            score += 80
        case .missing:
            score -= 140
        }

        score -= Int(lifecycleReport.impactDelaySeconds * 140.0)
        score -= evaluation.verdict.rejectionReasons.count * 260
        score -= evaluation.verdict.noteReasons.count * 40
        score -= evaluation.glitchContextReasons.count * 120
        score -= evaluation.relatedContextReasons.count * 30
        score -= lifecycleReport.outlierSignalCount * 80

        return score
    }

    private func shouldPromoteReview(
        event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation
    ) -> Bool {
        let noteReasons = Set(evaluation.verdict.noteReasons)
        let lifecycleReport = evaluation.lifecycleReport
        let softOnlyReasons: Set<String> = [
            "candidate_frame_count",
            "candidate_coverage",
            "candidate_gap",
            "candidate_torso_jump",
            "candidate_scale_jump",
            "body_discontinuity_context"
        ]

        if noteReasons.isSubset(of: softOnlyReasons) {
            return true
        }

        if noteReasons == Set(["missing_toss_lifecycle"]),
           lifecycleReport.impactStrength == .credible,
           lifecycleReport.followThroughStrength == .strong,
           lifecycleReport.impactDelaySeconds <= thresholds.maximumPromotableMissingTossDelaySeconds,
           event.confidence >= thresholds.minimumPromotableMissingTossConfidence,
           lifecycleReport.impactShoulderMarginRatio >= thresholds.minimumPromotableMissingTossShoulderMarginRatio,
           lifecycleReport.hitDropRatio >= thresholds.minimumPromotableMissingTossHitDropRatio,
           lifecycleReport.hitTravelRatio >= thresholds.minimumPromotableMissingTossHitTravelRatio,
           evaluation.glitchContextReasons.isEmpty,
           evaluation.relatedContextReasons.isEmpty,
           evaluation.duplicateReport.impactGapSeconds == 0
                || evaluation.duplicateReport.impactGapSeconds >= thresholds.minimumPromotableMissingTossGapSeconds
        {
            return true
        }

        if noteReasons == Set(["weak_followthrough_lifecycle"])
            || noteReasons == Set(["weak_followthrough_lifecycle", "candidate_scale_jump"])
            || noteReasons == Set(["weak_followthrough_lifecycle", "candidate_torso_jump"])
            || noteReasons == Set(["weak_followthrough_lifecycle", "candidate_torso_jump", "candidate_scale_jump"])
        {
            return lifecycleReport.tossStrength == .strong
                && lifecycleReport.impactStrength.accepted
                && lifecycleReport.impactDelaySeconds <= 1.35
                && event.confidence >= thresholds.minimumPromotableWeakFollowConfidence
                && lifecycleReport.impactWristLiftRatio >= thresholds.minimumPromotableWeakFollowImpactLiftRatio
                && lifecycleReport.impactShoulderMarginRatio >= thresholds.minimumPromotableWeakFollowShoulderMarginRatio
        }

        if noteReasons == Set(["missing_followthrough_lifecycle", "candidate_frame_count", "candidate_scale_jump"]) {
            return lifecycleReport.tossStrength == .strong
                && lifecycleReport.impactStrength == .credible
                && lifecycleReport.impactDelaySeconds <= thresholds.maximumPromotableMissingFollowDelaySeconds
                && event.confidence >= thresholds.minimumPromotableMissingFollowConfidence
                && lifecycleReport.peakTrophyScore >= thresholds.minimumPromotableMissingFollowTrophyScore
                && lifecycleReport.impactShoulderMarginRatio >= thresholds.minimumPromotableMissingFollowShoulderMarginRatio
                && evaluation.glitchContextReasons.isEmpty
                && evaluation.relatedContextReasons.isEmpty
        }

        if noteReasons.contains("long_impact_delay"),
           !noteReasons.contains("missing_toss_lifecycle"),
           !noteReasons.contains("missing_followthrough_lifecycle")
        {
            return lifecycleReport.tossStrength == .strong
                && lifecycleReport.impactStrength == .credible
                && lifecycleReport.followThroughStrength.accepted
                && lifecycleReport.impactDelaySeconds <= thresholds.maximumPromotableLongDelaySeconds
                && event.confidence >= 0.58
        }

        return false
    }
}
