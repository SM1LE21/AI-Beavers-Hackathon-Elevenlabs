import Foundation
import OSLog

public enum LiveServeDiagnostics {
    private static let logger = Logger(
        subsystem: "AiBeaversServeDetect",
        category: "LiveServe"
    )
    private static let captureLock = NSLock()
    private static var capturedSessionLines: [String] = []
    private static var isSessionCaptureActive = false

    public static func startSessionCapture() {
        captureLock.lock()
        defer { captureLock.unlock() }
        capturedSessionLines = []
        isSessionCaptureActive = true
    }

    public static func stopSessionCapture() {
        captureLock.lock()
        defer { captureLock.unlock() }
        isSessionCaptureActive = false
    }

    public static func clearSessionCapture() {
        captureLock.lock()
        defer { captureLock.unlock() }
        capturedSessionLines = []
        isSessionCaptureActive = false
    }

    public static func currentSessionCapture() -> [String] {
        captureLock.lock()
        defer { captureLock.unlock() }
        return capturedSessionLines
    }

    static func logCaptureAnalysisStats(
        _ stats: LiveCaptureAnalysisStats
    ) {
        recordDebug(
            "capture provider=\(stats.provider.rawValue) raw=\(stats.rawFrames) accepted=\(stats.acceptedFrames) dropped=\(stats.droppedFrames)"
        )
    }

    static func logPresenceRejection(
        provider: LivePoseProviderKind,
        report: LivePoseWindowPresenceReport
    ) {
        recordDebug(
            "presence_reject provider=\(provider.rawValue) reason=\(report.rejectionReason) validRatio=\(fixed(report.validFrameRatio, precision: 2)) body=\(fixed(report.medianBodyHeight, precision: 2)) torso=\(fixed(report.medianTorsoHeight, precision: 2)) shoulders=\(fixed(report.medianShoulderWidth, precision: 2)) legs=\(fixed(report.medianLegHeight, precision: 2))"
        )
    }

    static func logSegmentationSummary(
        provider: LivePoseProviderKind,
        frameCount: Int,
        eventCount: Int,
        eligibleCount: Int
    ) {
        recordDebug(
            "segmentation provider=\(provider.rawValue) frames=\(frameCount) events=\(eventCount) eligible=\(eligibleCount)"
        )
    }

    static func logEventRejection(
        provider: LivePoseProviderKind,
        event: ServeEvent,
        report: LiveServeEventValidationReport
    ) {
        recordDebug(
            "event_reject provider=\(provider.rawValue) impact=\(fixed(event.impactTimeSeconds, precision: 2)) trophy=\(fixed(event.trophyTimeSeconds, precision: 2)) delay=\(fixed(report.impactDelay, precision: 2)) confidence=\(fixed(event.confidence, precision: 2)) reasons=\(report.rejectionSummary) score=\(fixed(report.signalScore, precision: 2))"
        )
    }

    static func logEventEmission(
        provider: LivePoseProviderKind,
        event: ServeEvent
    ) {
        recordDebug(
            "event_emit provider=\(provider.rawValue) impact=\(fixed(event.impactTimeSeconds, precision: 2)) trophy=\(fixed(event.trophyTimeSeconds, precision: 2)) confidence=\(fixed(event.confidence, precision: 2))"
        )
    }

    static func logTossArmFault(
        trophyTimeSeconds: Double,
        handedness: Handedness,
        fault: TossArmFault
    ) {
        recordNotice(
            "toss_arm_fault trophy=\(fixed(trophyTimeSeconds, precision: 2)) tossSide=\(handedness.opposite.rawValue) bend=\(fault.bendDetected) straightest=\(fixed(fault.straightestAngle, precision: 1)) minAfter=\(fixed(fault.minAngleAfterStraight, precision: 1)) dip=\(fixed(fault.dipDegrees, precision: 1)) confidence=\(fixed(fault.measurementConfidence, precision: 2))"
        )
    }

    static func logServeTossDump(_ json: String) {
        recordNotice("serve_toss_dump " + json)
    }

    static func logSessionShadowContext(
        provider: LivePoseProviderKind,
        reason: String,
        timestampSeconds: Double
    ) {
        recordNotice(
            "session_shadow_context provider=\(provider.rawValue) time=\(fixed(timestampSeconds, precision: 2)) reason=\(reason)"
        )
    }

    static func logSessionShadowVerdict(
        provider: LivePoseProviderKind,
        serveNumber: Int,
        event: ServeEvent,
        verdict: ServeSessionShadowVerdict
    ) {
        recordNotice(
            "session_shadow_verdict provider=\(provider.rawValue) serve=\(serveNumber) impact=\(fixed(event.impactTimeSeconds, precision: 2)) trophy=\(fixed(event.trophyTimeSeconds, precision: 2)) confidence=\(fixed(event.confidence, precision: 2)) disposition=\(verdict.disposition.rawValue) reasons=\(verdict.reasonSummary)"
        )
    }

    static func logSessionPrimaryFilter(
        provider: LivePoseProviderKind,
        event: ServeEvent,
        verdict: ServeSessionShadowVerdict
    ) {
        recordNotice(
            "session_primary_filter provider=\(provider.rawValue) impact=\(fixed(event.impactTimeSeconds, precision: 2)) trophy=\(fixed(event.trophyTimeSeconds, precision: 2)) confidence=\(fixed(event.confidence, precision: 2)) disposition=\(verdict.disposition.rawValue) reasons=\(verdict.reasonSummary)"
        )
    }

    static func logSessionPrimaryHold(
        provider: LivePoseProviderKind,
        event: ServeEvent,
        verdict: ServeSessionShadowVerdict
    ) {
        recordNotice(
            "session_primary_hold provider=\(provider.rawValue) impact=\(fixed(event.impactTimeSeconds, precision: 2)) trophy=\(fixed(event.trophyTimeSeconds, precision: 2)) confidence=\(fixed(event.confidence, precision: 2)) disposition=\(verdict.disposition.rawValue) reasons=\(verdict.reasonSummary)"
        )
    }

    static func logSessionPrimaryPromote(
        provider: LivePoseProviderKind,
        event: ServeEvent,
        verdict: ServeSessionShadowVerdict
    ) {
        recordNotice(
            "session_primary_promote provider=\(provider.rawValue) impact=\(fixed(event.impactTimeSeconds, precision: 2)) trophy=\(fixed(event.trophyTimeSeconds, precision: 2)) confidence=\(fixed(event.confidence, precision: 2)) disposition=\(verdict.disposition.rawValue) reasons=\(verdict.reasonSummary)"
        )
    }

    static func logSessionPrimaryReanchor(
        provider: LivePoseProviderKind,
        originalEvent: ServeEvent,
        recoveredEvent: ServeEvent,
        recoveredVerdict: ServeSessionShadowVerdict
    ) {
        recordNotice(
            "session_primary_reanchor provider=\(provider.rawValue) impact=\(fixed(recoveredEvent.impactTimeSeconds, precision: 2)) trophy_from=\(fixed(originalEvent.trophyTimeSeconds, precision: 2)) trophy_to=\(fixed(recoveredEvent.trophyTimeSeconds, precision: 2)) confidence=\(fixed(recoveredEvent.confidence, precision: 2)) disposition=\(recoveredVerdict.disposition.rawValue) reasons=\(recoveredVerdict.reasonSummary)"
        )
    }

    static func logSessionShadowSignals(
        provider: LivePoseProviderKind,
        event: ServeEvent,
        lifecycleReport: ServeSessionShadowLifecycleReport,
        duplicateReport: ServeSessionShadowDuplicateReport,
        continuityReport: ServeSessionShadowContinuityReport
    ) {
        let continuitySummary = continuityReport.rejectionReasons.isEmpty
            ? "none"
            : continuityReport.rejectionReasons.joined(separator: ",")
        let lifecycleReasons = lifecycleReport.rejectionReasons.isEmpty && lifecycleReport.noteReasons.isEmpty
            ? "none"
            : (lifecycleReport.rejectionReasons + lifecycleReport.noteReasons).joined(separator: ",")
        let outlierSummary = lifecycleReport.outlierReasons.isEmpty
            ? "none"
            : lifecycleReport.outlierReasons.joined(separator: ",")

        recordNotice(
            "session_shadow_signals provider=\(provider.rawValue) impact=\(fixed(event.impactTimeSeconds, precision: 2)) toss=\(lifecycleReport.tossStrength.rawValue) tossFrames=\(lifecycleReport.tossFrameCount) tossPeak=\(fixed(lifecycleReport.tossPeakLiftRatio, precision: 2)) tossRise=\(fixed(lifecycleReport.tossRiseRatio, precision: 2)) trophy=\(fixed(lifecycleReport.peakTrophyScore, precision: 2)) impactState=\(lifecycleReport.impactStrength.rawValue) impactLift=\(fixed(lifecycleReport.impactWristLiftRatio, precision: 2)) shoulderMargin=\(fixed(lifecycleReport.impactShoulderMarginRatio, precision: 2)) elbow=\(fixed(lifecycleReport.impactElbowAngle, precision: 1)) delay=\(fixed(lifecycleReport.impactDelaySeconds, precision: 2)) follow=\(lifecycleReport.followThroughStrength.rawValue) followFrames=\(lifecycleReport.followThroughFrameCount) hitDrop=\(fixed(lifecycleReport.hitDropRatio, precision: 2)) hitTravel=\(fixed(lifecycleReport.hitTravelRatio, precision: 2)) outlierSignals=\(lifecycleReport.outlierSignalCount) outliers=\(outlierSummary) recent=\(duplicateReport.recentMotionKind.rawValue) duplicateGap=\(fixed(duplicateReport.impactGapSeconds, precision: 2)) staleOverlap=\(fixed(duplicateReport.staleWindowOverlapSeconds, precision: 2)) duplicateSignals=\(duplicateReport.similaritySignals) lifecycle=\(lifecycleReasons) continuity=\(continuitySummary)"
        )
    }

    private static func recordDebug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        recordSessionLine(message)
    }

    private static func recordNotice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        recordSessionLine(message)
    }

    private static func recordSessionLine(_ message: String) {
        captureLock.lock()
        defer { captureLock.unlock() }
        guard isSessionCaptureActive else { return }
        capturedSessionLines.append(message)
    }

    private static func fixed(_ value: Double, precision: Int) -> String {
        String(format: "%.\(precision)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
