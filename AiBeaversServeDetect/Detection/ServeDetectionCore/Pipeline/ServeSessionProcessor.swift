import Foundation

final class ServeSessionProcessor {
    private let segmentationFPS = 10.0
    private let bufferWindowSeconds = 12.0
    private let analysisIntervalSeconds = 0.5
    private let minimumBufferedDurationSeconds = 5.0
    private let endOfStreamDrainSeconds = 8.0
    private let primaryTrophyRecoveryLookbackSeconds = 1.65
    private let primaryTrophyRecoveryMinimumLeadSeconds = 0.10
    private let primaryTrophyRecoveryMinimumScore = 0.26
    private let primaryTrophyRecoveryScoreSlack = 0.10
    private let primaryTrophyRecoveryMinimumDelayImprovementSeconds = 0.35
    private let primaryTrophyRecoveryMaximumDelaySeconds = 1.85

    private var providerKind: LivePoseProviderKind = .mlKit
    private var detectionMode: ServeSessionDetectionMode = .legacyWithShadow
    private var providerTuning = LiveServeProviderTuning.for(.mlKit)
    private var bufferedFrames: [PoseFrame] = []
    private var lastAnalyzedTimestamp = -Double.greatestFiniteMagnitude
    private let shadowEvaluator = ServeSessionShadowEvaluator()
    private let primaryGateTracker = ServeSessionPrimaryGateTracker()
    private let emissionTracker = LiveServeEmissionTracker(retentionSeconds: 12.0)

    func configure(
        providerKind: LivePoseProviderKind,
        detectionMode: ServeSessionDetectionMode
    ) {
        self.providerKind = providerKind
        self.detectionMode = detectionMode
        providerTuning = LiveServeProviderTuning.for(providerKind)
    }

    func reset() {
        bufferedFrames.removeAll()
        lastAnalyzedTimestamp = -Double.greatestFiniteMagnitude
        shadowEvaluator.reset()
        primaryGateTracker.reset()
        emissionTracker.reset()
    }

    func ingest(frame: PoseFrame) -> LiveServeIngestResult? {
        bufferedFrames.append(frame)
        trimBuffer(endingAt: frame.timestampSeconds)

        guard bufferedDuration >= minimumBufferedDurationSeconds else {
            return nil
        }

        guard frame.timestampSeconds >= lastAnalyzedTimestamp + analysisIntervalSeconds else {
            return nil
        }

        let sequence = segmentationSequence()
        guard sequence.frames.count >= 12 else {
            return nil
        }

        lastAnalyzedTimestamp = frame.timestampSeconds
        return analyze(
            sequence: sequence,
            latestTimestamp: frame.timestampSeconds,
            refreshShadowContext: true
        )
    }

    func drainPending(finalTimestamp: Double) -> [LiveServeIngestResult] {
        guard bufferedDuration >= minimumBufferedDurationSeconds else {
            return []
        }

        let sequence = segmentationSequence()
        guard sequence.frames.count >= 12 else {
            return []
        }

        var drainedResults: [LiveServeIngestResult] = []
        var latestTimestamp = max(
            finalTimestamp,
            bufferedFrames.last?.timestampSeconds ?? finalTimestamp,
            lastAnalyzedTimestamp
        )
        let drainDeadline = latestTimestamp + endOfStreamDrainSeconds

        while latestTimestamp + analysisIntervalSeconds <= drainDeadline + 1e-9 {
            latestTimestamp += analysisIntervalSeconds
            guard let result = analyze(
                sequence: sequence,
                latestTimestamp: latestTimestamp,
                refreshShadowContext: false
            ) else {
                continue
            }
            if result.emittedServe != nil || result.shadowRejectedServe != nil {
                drainedResults.append(result)
            }
        }

        lastAnalyzedTimestamp = max(lastAnalyzedTimestamp, latestTimestamp)
        return drainedResults
    }

    private func analyze(
        sequence: PoseSequence,
        latestTimestamp: Double,
        refreshShadowContext: Bool
    ) -> LiveServeIngestResult? {
        let presenceReport = LivePoseWindowPresenceValidator.report(
            for: sequence,
            thresholds: providerTuning.presenceThresholds
        )

        let events = ServeSegmentation.detect(in: sequence)
        if refreshShadowContext {
            shadowEvaluator.observe(
                sequence: sequence,
                latestTimestamp: latestTimestamp,
                presenceReport: presenceReport,
                provider: providerKind
            )
        }

        var eligibleEvents: [ServeEvent] = []
        var pendingEventCount = 0
        var rejectedEventCount = 0
        var dedupedEventCount = 0
        var rejectedCandidates: [LiveServeRejectedCandidate] = []

        for event in events {
            let decisionLagAge = latestTimestamp - event.impactTimeSeconds
            guard decisionLagAge >= providerTuning.decisionLagSeconds else {
                pendingEventCount += 1
                rejectedCandidates.append(
                    LiveServeRejectedCandidate(
                        provider: providerKind,
                        impactTimeSeconds: event.impactTimeSeconds,
                        trophyTimeSeconds: event.trophyTimeSeconds,
                        confidence: event.confidence,
                        delaySeconds: decisionLagAge,
                        rejectionSummary: "decision_lag",
                        signalScore: 0.0
                    )
                )
                continue
            }

            let validationReport = LiveServeEventValidator.report(
                for: event,
                in: sequence,
                thresholds: providerTuning.validationThresholds
            )
            guard validationReport.accepted else {
                rejectedEventCount += 1
                LiveServeDiagnostics.logEventRejection(
                    provider: providerKind,
                    event: event,
                    report: validationReport
                )
                rejectedCandidates.append(
                    LiveServeRejectedCandidate(
                        provider: providerKind,
                        impactTimeSeconds: event.impactTimeSeconds,
                        trophyTimeSeconds: event.trophyTimeSeconds,
                        confidence: event.confidence,
                        delaySeconds: validationReport.impactDelay,
                        rejectionSummary: validationReport.rejectionSummary,
                        signalScore: validationReport.signalScore
                    )
                )
                continue
            }
            eligibleEvents.append(event)
        }

        let emissionUpdate = emissionTracker.ingest(
            validatedCandidates: eligibleEvents,
            latestTimestamp: latestTimestamp,
            thresholds: providerTuning.emissionThresholds
        )
        pendingEventCount += emissionUpdate.heldCandidates.count
        dedupedEventCount += emissionUpdate.dedupedCandidates.count
        rejectedCandidates.append(
            contentsOf: emissionUpdate.heldCandidates.map { event in
                LiveServeRejectedCandidate(
                    provider: providerKind,
                    impactTimeSeconds: event.impactTimeSeconds,
                    trophyTimeSeconds: event.trophyTimeSeconds,
                    confidence: event.confidence,
                    delaySeconds: latestTimestamp - event.impactTimeSeconds,
                    rejectionSummary: "cluster_hold",
                    signalScore: event.confidence
                )
            }
        )
        rejectedCandidates.append(
            contentsOf: emissionUpdate.dedupedCandidates.map { event in
                LiveServeRejectedCandidate(
                    provider: providerKind,
                    impactTimeSeconds: event.impactTimeSeconds,
                    trophyTimeSeconds: event.trophyTimeSeconds,
                    confidence: event.confidence,
                    delaySeconds: latestTimestamp - event.impactTimeSeconds,
                    rejectionSummary: "dedupe_similarity",
                    signalScore: event.confidence
                )
            }
        )

        if !presenceReport.accepted {
            LiveServeDiagnostics.logPresenceRejection(
                provider: providerKind,
                report: presenceReport
            )
        }

        LiveServeDiagnostics.logSegmentationSummary(
            provider: providerKind,
            frameCount: sequence.frames.count,
            eventCount: events.count,
            eligibleCount: emissionUpdate.emittedServe == nil ? 0 : 1
        )

        guard let nextServe = emissionUpdate.emittedServe else {
            if detectionMode.usesShadowAsPrimaryGate,
               let flushedOutcome = primaryGateTracker.flush(latestTimestamp: latestTimestamp)
            {
                emissionTracker.registerEmittedServe(
                    flushedOutcome.event,
                    thresholds: providerTuning.emissionThresholds
                )
                return ingestResult(
                    for: flushedOutcome,
                    sequence: sequence,
                    presenceReport: presenceReport,
                    sequenceFrameCount: sequence.frames.count,
                    segmentationEventCount: events.count,
                    pendingEventCount: pendingEventCount,
                    rejectedEventCount: rejectedEventCount,
                    dedupedEventCount: dedupedEventCount,
                    rejectedCandidates: rejectedCandidates
                )
            }

            let snapshot = makeDebugSnapshot(
                passedPresenceGate: presenceReport.accepted,
                presenceReport: presenceReport,
                sequenceFrameCount: sequence.frames.count,
                segmentationEventCount: events.count,
                pendingEventCount: pendingEventCount,
                rejectedEventCount: rejectedEventCount,
                dedupedEventCount: dedupedEventCount,
                eligibleEventCount: 0
            )
            return LiveServeIngestResult(
                emittedServe: nil,
                snapshot: snapshot,
                rejectedCandidates: rejectedCandidates,
                shadowVerdict: nil,
                shadowEvaluation: nil,
                shadowRejectedServe: nil,
                shadowRejectedEvaluation: nil
            )
        }

        var primaryServe = nextServe
        var shadowEvaluation = shadowEvaluator.evaluateEmittedServe(
            nextServe,
            in: sequence,
            latestTimestamp: latestTimestamp,
            detectionMode: detectionMode,
            validationThresholds: providerTuning.validationThresholds,
            provider: providerKind
        )
        if detectionMode.usesShadowAsPrimaryGate,
           let recoveredPrimaryCandidate = recoverPrimaryCandidate(
                from: nextServe,
                evaluation: shadowEvaluation,
                in: sequence,
                latestTimestamp: latestTimestamp,
                presenceAccepted: presenceReport.accepted
           )
        {
            primaryServe = recoveredPrimaryCandidate.event
            shadowEvaluation = recoveredPrimaryCandidate.evaluation
        }
        let shadowVerdict = shadowEvaluation.verdict
        var resolvedServe = nextServe
        if detectionMode.usesShadowAsPrimaryGate {
            let primaryOutcome = primaryGateTracker.decide(
                event: primaryServe,
                evaluation: shadowEvaluation,
                latestTimestamp: latestTimestamp
            )
            let primaryEvent = primaryOutcome.event
            let primaryVerdict = primaryOutcome.evaluation.verdict
            switch primaryOutcome.decision {
            case .emit:
                emissionTracker.registerEmittedServe(
                    primaryEvent,
                    thresholds: providerTuning.emissionThresholds
                )
                if primaryVerdict.disposition != .keep {
                    LiveServeDiagnostics.logSessionPrimaryPromote(
                        provider: providerKind,
                        event: primaryEvent,
                        verdict: primaryVerdict
                    )
                }
                resolvedServe = primaryEvent
            case .hold:
                emissionTracker.forgetEmittedServe(primaryServe)
                pendingEventCount += 1
                LiveServeDiagnostics.logSessionPrimaryHold(
                    provider: providerKind,
                    event: primaryEvent,
                    verdict: primaryVerdict
                )
                let snapshot = makeDebugSnapshot(
                    passedPresenceGate: presenceReport.accepted,
                    presenceReport: presenceReport,
                    sequenceFrameCount: sequence.frames.count,
                    segmentationEventCount: events.count,
                    pendingEventCount: pendingEventCount,
                    rejectedEventCount: rejectedEventCount,
                    dedupedEventCount: dedupedEventCount,
                    eligibleEventCount: 0
                )
                return LiveServeIngestResult(
                    emittedServe: nil,
                    snapshot: snapshot,
                    rejectedCandidates: rejectedCandidates,
                    shadowVerdict: nil,
                    shadowEvaluation: nil,
                    shadowRejectedServe: nil,
                    shadowRejectedEvaluation: nil
                )
            case .reject:
                emissionTracker.forgetEmittedServe(primaryServe)
                rejectedEventCount += 1
                rejectedCandidates.append(
                    LiveServeRejectedCandidate(
                        provider: providerKind,
                        impactTimeSeconds: primaryEvent.impactTimeSeconds,
                        trophyTimeSeconds: primaryEvent.trophyTimeSeconds,
                        confidence: primaryEvent.confidence,
                        delaySeconds: latestTimestamp - primaryEvent.impactTimeSeconds,
                        rejectionSummary: primaryVerdict.reasonSummary,
                        signalScore: primaryEvent.confidence
                    )
                )
                LiveServeDiagnostics.logSessionPrimaryFilter(
                    provider: providerKind,
                    event: primaryEvent,
                    verdict: primaryVerdict
                )
                let snapshot = makeDebugSnapshot(
                    passedPresenceGate: presenceReport.accepted,
                    presenceReport: presenceReport,
                    sequenceFrameCount: sequence.frames.count,
                    segmentationEventCount: events.count,
                    pendingEventCount: pendingEventCount,
                    rejectedEventCount: rejectedEventCount,
                    dedupedEventCount: dedupedEventCount,
                    eligibleEventCount: 0
                )
                return LiveServeIngestResult(
                    emittedServe: nil,
                    snapshot: snapshot,
                    rejectedCandidates: rejectedCandidates,
                    shadowVerdict: nil,
                    shadowEvaluation: nil,
                    shadowRejectedServe: primaryEvent,
                    shadowRejectedEvaluation: primaryOutcome.evaluation
                )
            }
        }

        let snapshot = makeDebugSnapshot(
            passedPresenceGate: presenceReport.accepted,
            presenceReport: presenceReport,
            sequenceFrameCount: sequence.frames.count,
            segmentationEventCount: events.count,
            pendingEventCount: pendingEventCount,
            rejectedEventCount: rejectedEventCount,
            dedupedEventCount: dedupedEventCount,
            eligibleEventCount: 1
        )
        if detectionMode.usesShadowAsPrimaryGate {
            emissionTracker.registerEmittedServe(
                resolvedServe,
                thresholds: providerTuning.emissionThresholds
            )
        }
        LiveServeDiagnostics.logEventEmission(
            provider: providerKind,
            event: resolvedServe
        )
        return LiveServeIngestResult(
            emittedServe: serveEventApplyingTossArmFault(resolvedServe, in: sequence),
            snapshot: snapshot,
            rejectedCandidates: rejectedCandidates,
            shadowVerdict: detectionMode.usesShadowReview ? shadowVerdict : nil,
            shadowEvaluation: shadowEvaluation,
            shadowRejectedServe: nil,
            shadowRejectedEvaluation: nil
        )
    }

    private func trimBuffer(endingAt latestTimestamp: Double) {
        bufferedFrames.removeAll { frame in
            latestTimestamp - frame.timestampSeconds > bufferWindowSeconds
        }
    }

    private var bufferedDuration: Double {
        guard let firstTimestamp = bufferedFrames.first?.timestampSeconds,
              let lastTimestamp = bufferedFrames.last?.timestampSeconds
        else {
            return 0.0
        }
        return lastTimestamp - firstTimestamp
    }

    private func resampledFrames() -> [PoseFrame] {
        guard let firstTimestamp = bufferedFrames.first?.timestampSeconds else {
            return []
        }

        let frameInterval = 1.0 / segmentationFPS
        var nextTimestamp = firstTimestamp
        var selectedFrames: [PoseFrame] = []

        for frame in bufferedFrames {
            if frame.timestampSeconds + 1e-9 < nextTimestamp {
                continue
            }
            selectedFrames.append(frame)
            nextTimestamp += frameInterval
        }

        return selectedFrames
    }

    private func segmentationSequence() -> PoseSequence {
        let segmentationFrames = resampledFrames()
        let normalizedFrames = segmentationFrames.enumerated().map { offset, bufferedFrame in
            PoseFrame(
                index: offset,
                timestampSeconds: bufferedFrame.timestampSeconds,
                landmarks: bufferedFrame.landmarks
            )
        }

        return PoseSequence(
            fps: segmentationFPS,
            frames: normalizedFrames,
            source: "ServeSession"
        )
    }

    private func recoverPrimaryCandidate(
        from event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation,
        in sequence: PoseSequence,
        latestTimestamp: Double,
        presenceAccepted: Bool
    ) -> (event: ServeEvent, evaluation: ServeSessionShadowEvaluation)? {
        guard shouldAttemptPrimaryTrophyRecovery(
            event: event,
            evaluation: evaluation,
            presenceAccepted: presenceAccepted
        ) else {
            return nil
        }

        guard let recoveredEvent = recoveredPrimaryEvent(
            from: event,
            evaluation: evaluation,
            in: sequence
        ) else {
            return nil
        }

        let recoveredEvaluation = shadowEvaluator.evaluateEmittedServe(
            recoveredEvent,
            in: sequence,
            latestTimestamp: latestTimestamp,
            detectionMode: detectionMode,
            validationThresholds: providerTuning.validationThresholds,
            provider: providerKind
        )
        guard recoveredPrimaryCandidateIsBetter(
            initialEvent: event,
            initialEvaluation: evaluation,
            recoveredEvent: recoveredEvent,
            recoveredEvaluation: recoveredEvaluation
        ) else {
            return nil
        }

        LiveServeDiagnostics.logSessionPrimaryReanchor(
            provider: providerKind,
            originalEvent: event,
            recoveredEvent: recoveredEvent,
            recoveredVerdict: recoveredEvaluation.verdict
        )
        return (recoveredEvent, recoveredEvaluation)
    }

    private func shouldAttemptPrimaryTrophyRecovery(
        event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation,
        presenceAccepted: Bool
    ) -> Bool {
        guard detectionMode.usesShadowAsPrimaryGate else {
            return false
        }

        guard presenceAccepted else {
            return false
        }

        let reasons = Set(
            evaluation.verdict.rejectionReasons
                + evaluation.verdict.noteReasons
        )
        let lifecycleReport = evaluation.lifecycleReport
        guard reasons.contains("implausible_impact_delay")
            || reasons.contains("long_impact_delay")
        else {
            return false
        }

        guard lifecycleReport.impactDelaySeconds > 1.6 else {
            return false
        }

        guard evaluation.duplicateReport.rejectionReasons.isEmpty,
              evaluation.glitchContextReasons.isEmpty
        else {
            return false
        }

        let strongLifecycleSignals =
            lifecycleReport.tossStrength == .strong
                || lifecycleReport.followThroughStrength == .strong
        return event.confidence >= 0.5
            && lifecycleReport.impactStrength.accepted
            && strongLifecycleSignals
    }

    private func recoveredPrimaryEvent(
        from event: ServeEvent,
        evaluation: ServeSessionShadowEvaluation,
        in sequence: PoseSequence
    ) -> ServeEvent? {
        let windowStart = max(
            0.0,
            event.impactTimeSeconds - primaryTrophyRecoveryLookbackSeconds
        )
        let windowEnd = event.impactTimeSeconds - primaryTrophyRecoveryMinimumLeadSeconds
        guard windowEnd > windowStart else {
            return nil
        }

        let recentMetrics = sequence.frames.compactMap { frame -> FrameMetrics? in
            guard frame.timestampSeconds >= windowStart,
                  frame.timestampSeconds <= windowEnd,
                  let metrics = sideFrameMetrics(frame: frame, handedness: event.handedness),
                  metrics.trophyScore >= primaryTrophyRecoveryMinimumScore
            else {
                return nil
            }
            return metrics
        }
        guard let peakRecentScore = recentMetrics.map(\.trophyScore).max() else {
            return nil
        }

        let viableMetrics = recentMetrics.filter { metrics in
            metrics.trophyScore >= peakRecentScore - primaryTrophyRecoveryScoreSlack
        }
        guard let bestMetrics = viableMetrics.max(by: { lhs, rhs in
            primaryTrophyRecoveryScore(lhs, impactTimeSeconds: event.impactTimeSeconds)
                < primaryTrophyRecoveryScore(rhs, impactTimeSeconds: event.impactTimeSeconds)
        }) else {
            return nil
        }

        let recoveredDelay = event.impactTimeSeconds - bestMetrics.timestampSeconds
        guard recoveredDelay <= primaryTrophyRecoveryMaximumDelaySeconds,
              evaluation.lifecycleReport.impactDelaySeconds - recoveredDelay >= primaryTrophyRecoveryMinimumDelayImprovementSeconds
        else {
            return nil
        }

        return ServeEvent(
            serveIndex: event.serveIndex,
            startTimeSeconds: max(0.0, bestMetrics.timestampSeconds - 2.0),
            endTimeSeconds: event.endTimeSeconds,
            trophyTimeSeconds: bestMetrics.timestampSeconds,
            impactTimeSeconds: event.impactTimeSeconds,
            confidence: max(event.confidence, min(bestMetrics.trophyScore, 0.75)),
            handedness: event.handedness,
            feedback: generateFeedback(metrics: bestMetrics)
        )
    }

    private func primaryTrophyRecoveryScore(
        _ metrics: FrameMetrics,
        impactTimeSeconds: Double
    ) -> Double {
        let delaySeconds = impactTimeSeconds - metrics.timestampSeconds
        return (metrics.trophyScore * 1000.0)
            + (metrics.tossWristLiftRatio * 120.0)
            + (metrics.tossShoulderLiftRatio * 80.0)
            - (delaySeconds * 140.0)
    }

    private func recoveredPrimaryCandidateIsBetter(
        initialEvent: ServeEvent,
        initialEvaluation: ServeSessionShadowEvaluation,
        recoveredEvent: ServeEvent,
        recoveredEvaluation: ServeSessionShadowEvaluation
    ) -> Bool {
        if recoveredEvaluation.verdict.disposition != .keep,
           recoveredEvaluation.verdict.noteReasons.contains("missing_toss_lifecycle")
        {
            return false
        }

        let recoveredDelay = recoveredEvaluation.lifecycleReport.impactDelaySeconds
        let initialDelay = initialEvaluation.lifecycleReport.impactDelaySeconds
        guard recoveredDelay < initialDelay else {
            return false
        }

        let initialRank = primaryVerdictRank(initialEvaluation.verdict.disposition)
        let recoveredRank = primaryVerdictRank(recoveredEvaluation.verdict.disposition)
        guard recoveredRank >= initialRank else {
            return false
        }

        if recoveredRank > initialRank {
            return true
        }

        if recoveredEvaluation.verdict.rejectionReasons.count < initialEvaluation.verdict.rejectionReasons.count {
            return true
        }

        if recoveredEvaluation.verdict.noteReasons.count < initialEvaluation.verdict.noteReasons.count,
           recoveredEvent.confidence + 0.02 >= initialEvent.confidence
        {
            return true
        }

        return recoveredEvaluation.verdict.reasonSummary != initialEvaluation.verdict.reasonSummary
            && recoveredDelay <= primaryTrophyRecoveryMaximumDelaySeconds
    }

    private func primaryVerdictRank(
        _ disposition: ServeSessionShadowVerdict.Disposition
    ) -> Int {
        switch disposition {
        case .reject:
            return 0
        case .review:
            return 1
        case .keep:
            return 2
        }
    }

    private func ingestResult(
        for primaryOutcome: ServeSessionPrimaryGateOutcome,
        sequence: PoseSequence,
        presenceReport: LivePoseWindowPresenceReport,
        sequenceFrameCount: Int,
        segmentationEventCount: Int,
        pendingEventCount: Int,
        rejectedEventCount: Int,
        dedupedEventCount: Int,
        rejectedCandidates: [LiveServeRejectedCandidate]
    ) -> LiveServeIngestResult {
        let primaryEvent = primaryOutcome.event
        let primaryVerdict = primaryOutcome.evaluation.verdict

        switch primaryOutcome.decision {
        case .emit:
            if primaryVerdict.disposition != .keep {
                LiveServeDiagnostics.logSessionPrimaryPromote(
                    provider: providerKind,
                    event: primaryEvent,
                    verdict: primaryVerdict
                )
            }
            let snapshot = makeDebugSnapshot(
                passedPresenceGate: presenceReport.accepted,
                presenceReport: presenceReport,
                sequenceFrameCount: sequenceFrameCount,
                segmentationEventCount: segmentationEventCount,
                pendingEventCount: pendingEventCount,
                rejectedEventCount: rejectedEventCount,
                dedupedEventCount: dedupedEventCount,
                eligibleEventCount: 1
            )
            LiveServeDiagnostics.logEventEmission(
                provider: providerKind,
                event: primaryEvent
            )
            return LiveServeIngestResult(
                emittedServe: serveEventApplyingTossArmFault(primaryEvent, in: sequence),
                snapshot: snapshot,
                rejectedCandidates: rejectedCandidates,
                shadowVerdict: nil,
                shadowEvaluation: primaryOutcome.evaluation,
                shadowRejectedServe: nil,
                shadowRejectedEvaluation: nil
            )
        case .hold:
            let snapshot = makeDebugSnapshot(
                passedPresenceGate: presenceReport.accepted,
                presenceReport: presenceReport,
                sequenceFrameCount: sequenceFrameCount,
                segmentationEventCount: segmentationEventCount,
                pendingEventCount: pendingEventCount + 1,
                rejectedEventCount: rejectedEventCount,
                dedupedEventCount: dedupedEventCount,
                eligibleEventCount: 0
            )
            return LiveServeIngestResult(
                emittedServe: nil,
                snapshot: snapshot,
                rejectedCandidates: rejectedCandidates,
                shadowVerdict: nil,
                shadowEvaluation: nil,
                shadowRejectedServe: nil,
                shadowRejectedEvaluation: nil
            )
        case .reject:
            let snapshot = makeDebugSnapshot(
                passedPresenceGate: presenceReport.accepted,
                presenceReport: presenceReport,
                sequenceFrameCount: sequenceFrameCount,
                segmentationEventCount: segmentationEventCount,
                pendingEventCount: pendingEventCount,
                rejectedEventCount: rejectedEventCount + 1,
                dedupedEventCount: dedupedEventCount,
                eligibleEventCount: 0
            )
            LiveServeDiagnostics.logSessionPrimaryFilter(
                provider: providerKind,
                event: primaryEvent,
                verdict: primaryVerdict
            )
            return LiveServeIngestResult(
                emittedServe: nil,
                snapshot: snapshot,
                rejectedCandidates: rejectedCandidates + [
                    LiveServeRejectedCandidate(
                        provider: providerKind,
                        impactTimeSeconds: primaryEvent.impactTimeSeconds,
                        trophyTimeSeconds: primaryEvent.trophyTimeSeconds,
                        confidence: primaryEvent.confidence,
                        delaySeconds: primaryOutcome.evaluation.lifecycleReport.impactDelaySeconds,
                        rejectionSummary: primaryVerdict.reasonSummary,
                        signalScore: primaryEvent.confidence
                    )
                ],
                shadowVerdict: nil,
                shadowEvaluation: nil,
                shadowRejectedServe: primaryEvent,
                shadowRejectedEvaluation: primaryOutcome.evaluation
            )
        }
    }

    private func makeDebugSnapshot(
        passedPresenceGate: Bool,
        presenceReport: LivePoseWindowPresenceReport,
        sequenceFrameCount: Int,
        segmentationEventCount: Int,
        pendingEventCount: Int,
        rejectedEventCount: Int,
        dedupedEventCount: Int,
        eligibleEventCount: Int
    ) -> LiveServeDebugSnapshot {
        LiveServeDebugSnapshot(
            provider: providerKind,
            passedPresenceGate: passedPresenceGate,
            presenceValidRatio: presenceReport.validFrameRatio,
            presenceReason: presenceReport.rejectionReason.isEmpty ? nil : presenceReport.rejectionReason,
            presenceBodyHeight: presenceReport.medianBodyHeight,
            presenceTorsoHeight: presenceReport.medianTorsoHeight,
            sequenceFrameCount: sequenceFrameCount,
            segmentationEventCount: segmentationEventCount,
            pendingEventCount: pendingEventCount,
            rejectedEventCount: rejectedEventCount,
            dedupedEventCount: dedupedEventCount,
            eligibleEventCount: eligibleEventCount
        )
    }
}
