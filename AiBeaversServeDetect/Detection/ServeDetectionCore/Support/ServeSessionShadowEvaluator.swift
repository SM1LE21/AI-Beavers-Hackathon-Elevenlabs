import Foundation

private struct ServeSessionShadowContextEvent {
    let reason: String
    let timestampSeconds: Double
}

public struct ServeSessionShadowVerdict {
    public enum Disposition: String {
        case keep
        case review
        case reject
    }

    public let disposition: Disposition
    public let rejectionReasons: [String]
    public let noteReasons: [String]

    public init(disposition: Disposition, rejectionReasons: [String], noteReasons: [String]) {
        self.disposition = disposition
        self.rejectionReasons = rejectionReasons
        self.noteReasons = noteReasons
    }

    public var accepted: Bool {
        disposition != .reject
    }

    public var reasonSummary: String {
        switch disposition {
        case .keep:
            return "keep"
        case .review:
            return "review:\(noteReasons.joined(separator: ","))"
        case .reject:
            return "reject:\(rejectionReasons.joined(separator: ","))"
        }
    }

    public var displayTitle: String {
        switch disposition {
        case .keep:
            return "Shadow keeps this serve"
        case .review:
            return "Shadow would review this serve"
        case .reject:
            return "Shadow would reject this serve"
        }
    }

    public var detailText: String {
        let reasons: [String]
        switch disposition {
        case .keep:
            return "Experimental shadow serve review would keep this serve."
        case .review:
            reasons = noteReasons
        case .reject:
            reasons = rejectionReasons
        }

        return reasons
            .map(ServeSessionShadowVerdict.displayReason(for:))
            .joined(separator: " • ")
    }

    public static func displayReason(for code: String) -> String {
        switch code {
        case "duplicate_without_reset":
            return "it landed too soon after the previous serve without a clear reset, so it looks like a duplicate"
        case "duplicate_after_recent_emit":
            return "it looks too similar to the previous counted serve and does not show a fresh toss, so it looks like a duplicate"
        case "recent_nonserve_motion":
            return "it happened soon after the previous serve but did not rebuild a believable serve motion, so it looks like non-serve movement"
        case "stale_trophy_pairing":
            return "it reuses body context from the previous serve window, so the trophy-to-impact pairing looks stale"
        case "missing_toss_lifecycle":
            return "the stricter pass could not find a believable toss rise leading into this event"
        case "weak_toss_lifecycle":
            return "the toss rise looked incomplete, so the serve shape is weaker than expected"
        case "missing_followthrough_lifecycle":
            return "the stricter pass could not find a believable post-impact follow-through"
        case "weak_followthrough_lifecycle":
            return "the post-impact continuation looked incomplete, so the serve shape is weaker than expected"
        case "implausible_impact_delay":
            return "the recovered trophy was too far before impact, so this looks like a stale pose pairing instead of one serve motion"
        case "long_impact_delay":
            return "the recovered trophy sat unusually far before impact, so the serve window looks stretched"
        case "reentry_glitch":
            return "the player left or snapped back into frame and the pose metrics spiked in a way that looks like a tracking glitch"
        case "serve_shape_outlier":
            return "the pose metrics spiked far outside the normal serve range, so this counted event is suspicious"
        case "weak_impact_geometry":
            return "the toss looked serve-like, but the impact geometry stayed too weak for a clean serve contact"
        case "presence_dropout_context":
            return "the body dropped out of frame around this detection"
        case "body_discontinuity_context":
            return "the body position or scale jumped abruptly around this detection"
        case "missing_candidate_window":
            return "the stricter pass could not build a stable body window"
        case "candidate_frame_count":
            return "there were too few stable body frames around trophy to impact"
        case "candidate_coverage":
            return "body coverage around the serve window was too sparse"
        case "candidate_gap":
            return "there was a large timing gap inside the serve window"
        case "candidate_torso_jump":
            return "the torso position changed too abruptly inside the serve window"
        case "candidate_scale_jump":
            return "the body scale changed too abruptly inside the serve window"
        default:
            return code.replacingOccurrences(of: "_", with: " ")
        }
    }
}

public struct ServeSessionShadowEvaluation {
    public let verdict: ServeSessionShadowVerdict
    public let lifecycleReport: ServeSessionShadowLifecycleReport
    public let duplicateReport: ServeSessionShadowDuplicateReport
    public let continuityReport: ServeSessionShadowContinuityReport
    public let relatedContextReasons: [String]
    public let glitchContextReasons: [String]

    public init(
        verdict: ServeSessionShadowVerdict,
        lifecycleReport: ServeSessionShadowLifecycleReport,
        duplicateReport: ServeSessionShadowDuplicateReport,
        continuityReport: ServeSessionShadowContinuityReport,
        relatedContextReasons: [String],
        glitchContextReasons: [String]
    ) {
        self.verdict = verdict
        self.lifecycleReport = lifecycleReport
        self.duplicateReport = duplicateReport
        self.continuityReport = continuityReport
        self.relatedContextReasons = relatedContextReasons
        self.glitchContextReasons = glitchContextReasons
    }
}

final class ServeSessionShadowEvaluator {
    private let maximumConsecutivePresenceFailures = 2
    private let discontinuityTrailingWindowSeconds = 0.75
    private let maximumWindowBodyJumpRatio = 1.15
    private let maximumWindowScaleChangeRatio = 0.55
    private let contextRetentionSeconds = 2.0
    private let contextLogCooldownSeconds = 0.75
    private let duplicateWindowSeconds = 2.25
    private let lowConfidenceThreshold = 0.38
    private let weakValidationSignalThreshold = 0.60
    private let longImpactDelaySeconds = 1.85
    private let maximumPlausibleImpactDelaySeconds = 2.20
    private let suspiciousRecentLongDelaySeconds = 2.0
    private let suspiciousRecentLongDelayGapSeconds = 5.0
    private let glitchContextLeadSeconds = 1.0
    private let glitchContextTrailSeconds = 1.5
    private let minimumReentryOutlierSignals = 2
    private let minimumServeLikeImpactShoulderMarginRatio = 0.55
    private let minimumServeLikeHitDropRatio = 0.70
    private let minimumServeLikeHitTravelRatio = 0.35
    private let suspiciousWeakImpactDelaySeconds = 1.0
    private let suspiciousWeakImpactConfidence = 0.45

    private var consecutivePresenceFailures = 0
    private var lastStableWindowBodyState: ServeSessionShadowBodyState?
    private var pendingResetStateServe: ServeEvent?
    private var lastReferenceServe: ServeEvent?
    private var contextEvents: [ServeSessionShadowContextEvent] = []

    func reset() {
        consecutivePresenceFailures = 0
        lastStableWindowBodyState = nil
        pendingResetStateServe = nil
        lastReferenceServe = nil
        contextEvents.removeAll()
    }

    func observe(
        sequence: PoseSequence,
        latestTimestamp: Double,
        presenceReport: LivePoseWindowPresenceReport,
        provider: LivePoseProviderKind
    ) {
        pruneExpiredContext(latestTimestamp: latestTimestamp)
        refreshResetState(sequence: sequence)

        if presenceReport.accepted {
            consecutivePresenceFailures = 0
        } else {
            consecutivePresenceFailures += 1
            if consecutivePresenceFailures >= maximumConsecutivePresenceFailures {
                noteContext(
                    reason: "presence_dropout_context",
                    timestampSeconds: latestTimestamp,
                    provider: provider
                )
            }
        }

        let recentBodyStates = serveSessionShadowBodyStates(
            in: sequence,
            startTime: latestTimestamp - discontinuityTrailingWindowSeconds,
            endTime: latestTimestamp
        )
        guard let currentWindowBodyState = averagedServeSessionShadowBodyState(recentBodyStates) else {
            return
        }

        if let lastStableWindowBodyState,
           isDiscontinuity(from: lastStableWindowBodyState, to: currentWindowBodyState)
        {
            noteContext(
                reason: "body_discontinuity_context",
                timestampSeconds: latestTimestamp,
                provider: provider
            )
        }

        self.lastStableWindowBodyState = currentWindowBodyState
    }

    func evaluateEmittedServe(
        _ event: ServeEvent,
        in sequence: PoseSequence,
        latestTimestamp: Double,
        detectionMode: ServeSessionDetectionMode,
        validationThresholds: LiveServeEventValidationThresholds,
        provider: LivePoseProviderKind
    ) -> ServeSessionShadowEvaluation {
        pruneExpiredContext(latestTimestamp: latestTimestamp)

        let validationReport = LiveServeEventValidator.report(
            for: event,
            in: sequence,
            thresholds: validationThresholds
        )
        let lifecycleReport = ServeSessionShadowLifecycleValidator.report(
            for: event,
            in: sequence
        )
        let continuityReport = ServeSessionShadowContinuityValidator.report(
            for: event,
            in: sequence
        )
        let relatedContextReasons = relatedContextReasons(for: event)
        let glitchContextReasons = glitchContextReasons(
            for: event,
            latestTimestamp: latestTimestamp
        )
        let duplicateReport = ServeSessionShadowDuplicateValidator.report(
            current: event,
            previous: lastReferenceServe,
            in: sequence,
            resetSatisfied: resetStateSatisfied(before: event, in: sequence),
            tossStrength: lifecycleReport.tossStrength,
            impactStrength: lifecycleReport.impactStrength
        )
        LiveServeDiagnostics.logSessionShadowSignals(
            provider: provider,
            event: event,
            lifecycleReport: lifecycleReport,
            duplicateReport: duplicateReport,
            continuityReport: continuityReport
        )

        var rejectionReasons = duplicateReport.rejectionReasons
        var noteReasons: [String] = []

        let lowConfidence = event.confidence < lowConfidenceThreshold
        let weakValidation = validationReport.signalScore <= weakValidationSignalThreshold
            || validationReport.satisfiedSignals == validationThresholds.minimumSatisfiedSignals
        let hasCatastrophicWindowLoss = continuityReport.rejectionReasons.contains("missing_candidate_window")
            || (continuityReport.rejectionReasons.contains("candidate_frame_count")
                && continuityReport.rejectionReasons.contains("candidate_coverage"))

        if lifecycleReport.impactDelaySeconds > maximumPlausibleImpactDelaySeconds {
            rejectionReasons.append("implausible_impact_delay")
        }

        if lifecycleReport.tossStrength == .missing {
            if shouldRejectMissingTossLifecycle(
                lifecycleReport: lifecycleReport,
                lowConfidence: lowConfidence,
                weakValidation: weakValidation
            ) {
                rejectionReasons.append("missing_toss_lifecycle")
            } else {
                noteReasons.append("missing_toss_lifecycle")
            }
        }

        if lifecycleReport.followThroughStrength == .missing {
            if shouldRejectMissingFollowThroughLifecycle(
                lifecycleReport: lifecycleReport,
                lowConfidence: lowConfidence,
                weakValidation: weakValidation
            ) {
                rejectionReasons.append("missing_followthrough_lifecycle")
            } else {
                noteReasons.append("missing_followthrough_lifecycle")
            }
        }

        if rejectionReasons.isEmpty,
           shouldRejectReentryGlitch(
                lifecycleReport: lifecycleReport,
                glitchContextReasons: glitchContextReasons
           )
        {
            rejectionReasons.append("reentry_glitch")
        } else if rejectionReasons.isEmpty,
                  lifecycleReport.outlierSignalCount >= minimumReentryOutlierSignals,
                  !lifecycleReport.hasStrongLifecycle
        {
            noteReasons.append("serve_shape_outlier")
        }

        if rejectionReasons.isEmpty,
           shouldReviewWeakImpactGeometry(
                event: event,
                lifecycleReport: lifecycleReport,
                continuityReport: continuityReport
           )
        {
            noteReasons.append("weak_impact_geometry")
        }

        if rejectionReasons.isEmpty {
            noteReasons.append(contentsOf: lifecycleReport.noteReasons)
        }
        if rejectionReasons.isEmpty,
           lifecycleReport.impactDelaySeconds > longImpactDelaySeconds,
           (!lifecycleReport.hasStrongLifecycle
                || shouldReviewRecentLongDelayPairing(
                    detectionMode: detectionMode,
                    lifecycleReport: lifecycleReport,
                    duplicateReport: duplicateReport,
                    continuityReport: continuityReport
                ))
        {
            noteReasons.append("long_impact_delay")
        }

        if rejectionReasons.isEmpty,
           !lifecycleReport.hasStrongLifecycle
        {
            noteReasons.append(contentsOf: relatedContextReasons)
            if !hasCatastrophicWindowLoss {
                noteReasons.append(contentsOf: continuityReport.rejectionReasons)
            }
        }

        let normalizedRejectionReasons = dedupedReasons(rejectionReasons)
        let normalizedNoteReasons = dedupedReasons(noteReasons)
        let disposition: ServeSessionShadowVerdict.Disposition
        if !normalizedRejectionReasons.isEmpty {
            disposition = .reject
        } else if !normalizedNoteReasons.isEmpty {
            disposition = .review
        } else {
            disposition = .keep
        }

        if shouldRecordReferenceServe(
            disposition: disposition,
            detectionMode: detectionMode
        ) {
            pendingResetStateServe = event
            lastReferenceServe = event
        }

        let verdict = ServeSessionShadowVerdict(
            disposition: disposition,
            rejectionReasons: normalizedRejectionReasons,
            noteReasons: normalizedNoteReasons
        )

        return ServeSessionShadowEvaluation(
            verdict: verdict,
            lifecycleReport: lifecycleReport,
            duplicateReport: duplicateReport,
            continuityReport: continuityReport,
            relatedContextReasons: relatedContextReasons,
            glitchContextReasons: glitchContextReasons
        )
    }

    private func relatedContextReasons(for event: ServeEvent) -> [String] {
        let contextWindowStart = max(0.0, event.trophyTimeSeconds - 0.35)
        let contextWindowEnd = event.impactTimeSeconds + 0.15
        return dedupedReasons(
            contextEvents
                .filter { context in
                    context.timestampSeconds >= contextWindowStart
                        && context.timestampSeconds <= contextWindowEnd
                }
                .map(\.reason)
        )
    }

    private func refreshResetState(sequence: PoseSequence) {
        guard let pendingResetStateServe else {
            return
        }

        let report = ServeSessionShadowResetStateValidator.report(
            after: pendingResetStateServe,
            in: sequence
        )
        if report.satisfied {
            self.pendingResetStateServe = nil
        }
    }

    private func glitchContextReasons(
        for event: ServeEvent,
        latestTimestamp: Double
    ) -> [String] {
        let contextWindowStart = max(0.0, event.trophyTimeSeconds - glitchContextLeadSeconds)
        let contextWindowEnd = min(latestTimestamp, event.impactTimeSeconds + glitchContextTrailSeconds)
        return dedupedReasons(
            contextEvents
                .filter { context in
                    context.timestampSeconds >= contextWindowStart
                        && context.timestampSeconds <= contextWindowEnd
                        && (context.reason == "presence_dropout_context"
                            || context.reason == "body_discontinuity_context")
                }
                .map(\.reason)
        )
    }

    private func noteContext(
        reason: String,
        timestampSeconds: Double,
        provider: LivePoseProviderKind
    ) {
        let previousTimestamp = contextEvents
            .last(where: { $0.reason == reason })?
            .timestampSeconds
        let shouldLog = previousTimestamp.map { timestampSeconds - $0 > contextLogCooldownSeconds } ?? true

        contextEvents.append(
            ServeSessionShadowContextEvent(
                reason: reason,
                timestampSeconds: timestampSeconds
            )
        )
        if shouldLog {
            LiveServeDiagnostics.logSessionShadowContext(
                provider: provider,
                reason: reason,
                timestampSeconds: timestampSeconds
            )
        }
    }

    private func pruneExpiredContext(latestTimestamp: Double) {
        contextEvents.removeAll { context in
            latestTimestamp - context.timestampSeconds > contextRetentionSeconds
        }
    }

    private func dedupedReasons(_ reasons: [String]) -> [String] {
        Array(NSOrderedSet(array: reasons)) as? [String] ?? reasons
    }

    private func shouldRecordReferenceServe(
        disposition: ServeSessionShadowVerdict.Disposition,
        detectionMode: ServeSessionDetectionMode
    ) -> Bool {
        if detectionMode.usesShadowAsPrimaryGate {
            return disposition == .keep
        }
        return disposition != .reject
    }

    private func resetStateSatisfied(
        before event: ServeEvent,
        in sequence: PoseSequence
    ) -> Bool {
        guard let lastReferenceServe else {
            return true
        }
        guard event.impactTimeSeconds - lastReferenceServe.impactTimeSeconds <= duplicateWindowSeconds * 2.0 else {
            return true
        }

        let cutoffTimestamp = max(
            lastReferenceServe.impactTimeSeconds + 0.05,
            event.trophyTimeSeconds - 0.05
        )
        let preServeFrames = sequence.frames.filter { frame in
            frame.timestampSeconds <= cutoffTimestamp
        }
        let preServeSequence = PoseSequence(
            fps: sequence.fps,
            frames: preServeFrames,
            source: sequence.source
        )
        let report = ServeSessionShadowResetStateValidator.report(
            after: lastReferenceServe,
            in: preServeSequence
        )
        return report.satisfied
    }

    private func shouldRejectMissingTossLifecycle(
        lifecycleReport: ServeSessionShadowLifecycleReport,
        lowConfidence: Bool,
        weakValidation: Bool
    ) -> Bool {
        lifecycleReport.impactStrength != .credible
            || !lifecycleReport.followThroughStrength.accepted
            || lowConfidence
            || weakValidation
    }

    private func shouldRejectMissingFollowThroughLifecycle(
        lifecycleReport: ServeSessionShadowLifecycleReport,
        lowConfidence: Bool,
        weakValidation: Bool
    ) -> Bool {
        lifecycleReport.impactStrength == .missing
            || (lifecycleReport.tossStrength == .missing && lowConfidence)
            || (lowConfidence && weakValidation)
    }

    private func shouldRejectReentryGlitch(
        lifecycleReport: ServeSessionShadowLifecycleReport,
        glitchContextReasons: [String]
    ) -> Bool {
        lifecycleReport.outlierSignalCount >= minimumReentryOutlierSignals
            && !glitchContextReasons.isEmpty
    }

    private func shouldReviewRecentLongDelayPairing(
        detectionMode: ServeSessionDetectionMode,
        lifecycleReport: ServeSessionShadowLifecycleReport,
        duplicateReport: ServeSessionShadowDuplicateReport,
        continuityReport: ServeSessionShadowContinuityReport
    ) -> Bool {
        detectionMode.usesShadowAsPrimaryGate
            && lifecycleReport.impactDelaySeconds >= suspiciousRecentLongDelaySeconds
            && duplicateReport.impactGapSeconds > 0
            && duplicateReport.impactGapSeconds <= suspiciousRecentLongDelayGapSeconds
            && (
                lifecycleReport.outlierSignalCount > 0
                    || continuityReport.rejectionReasons.contains("candidate_torso_jump")
                    || continuityReport.rejectionReasons.contains("candidate_scale_jump")
            )
    }

    private func shouldReviewWeakImpactGeometry(
        event: ServeEvent,
        lifecycleReport: ServeSessionShadowLifecycleReport,
        continuityReport: ServeSessionShadowContinuityReport
    ) -> Bool {
        guard lifecycleReport.impactStrength == .credible else {
            return false
        }

        guard lifecycleReport.impactShoulderMarginRatio < minimumServeLikeImpactShoulderMarginRatio,
              lifecycleReport.hitDropRatio < minimumServeLikeHitDropRatio,
              lifecycleReport.hitTravelRatio < minimumServeLikeHitTravelRatio
        else {
            return false
        }

        return continuityReport.rejectionReasons.contains("candidate_torso_jump")
            || continuityReport.rejectionReasons.contains("candidate_scale_jump")
            || continuityReport.rejectionReasons.contains("candidate_coverage")
            || continuityReport.rejectionReasons.contains("candidate_gap")
            || lifecycleReport.outlierSignalCount > 0
            || lifecycleReport.impactDelaySeconds >= suspiciousWeakImpactDelaySeconds
            || event.confidence < suspiciousWeakImpactConfidence
    }

    private func isDiscontinuity(
        from previous: ServeSessionShadowBodyState,
        to current: ServeSessionShadowBodyState
    ) -> Bool {
        serveSessionShadowTorsoJumpRatio(from: previous, to: current) > maximumWindowBodyJumpRatio
            || serveSessionShadowBodyScaleChangeRatio(from: previous, to: current) > maximumWindowScaleChangeRatio
    }
}
