import AVFoundation
import Foundation

@MainActor
final class ServeDetectionViewModel: ObservableObject {
    enum Phase {
        case preview
        case starting
        case detecting
        case stopping
    }

    @Published var statusMessage = "Camera preview is starting."
    @Published var errorMessage: String?
    @Published var latestOverlayFrame: LiveOverlayFrame?
    @Published var serveCount = 0
    @Published var lastServe: ServeEvent?
    @Published var phase: Phase = .preview
    @Published var isCameraReady = false

    private let captureService = LivePoseCaptureService(
        overlayPoseFPS: 24.0,
        analysisPoseFPS: 10.0,
        providerKind: .mlKit,
        sessionPreset: .hd1280x720,
        replayMode: .debugBuffer,
        cameraPosition: .back
    )
    private let analysisWorker = ServeSessionAnalysisWorker()
    private let voiceFeedback = VoiceFeedback()

    private var didConfigureCallbacks = false
    private var sessionID = 0
    private var nextAnalysisSequenceNumber = 0
    private var pendingIngestCount = 0
    private var latestPoseTimestampSeconds = 0.0
    private var lastDetectionDelaySeconds: Double?

    var captureSession: AVCaptureSession {
        captureService.session
    }

    var isDetecting: Bool {
        phase == .starting || phase == .detecting
    }

    var isTransitioning: Bool {
        phase == .starting || phase == .stopping
    }

    var lastDetectionTitle: String {
        guard let lastServe else {
            return isDetecting ? "Waiting for a serve" : "Ready"
        }
        return "Serve \(lastServe.serveIndex) detected"
    }

    var lastDetectionDetail: String {
        guard let lastServe else {
            return isDetecting
                ? "Serve normally. The detector usually emits a few seconds after impact."
                : "Start detection, step fully into frame, then hit a real serve."
        }

        let confidence = Int((lastServe.confidence * 100).rounded())
        let impact = String(format: "%.2fs", lastServe.impactTimeSeconds)
        let delayText: String
        if let lastDetectionDelaySeconds {
            delayText = String(format: "Detected %.1fs after impact.", lastDetectionDelaySeconds)
        } else {
            delayText = "Detected after impact."
        }
        return "Impact \(impact). \(lastServe.handednessLabel). Confidence \(confidence)%. \(delayText)"
    }

    func onAppear() {
        configureCallbacksIfNeeded()
        captureService.requestAccessAndStart(previewOnly: true)
    }

    func onDisappear() {
        captureService.stop()
        invalidateSession()
    }

    func startDetecting() {
        guard phase == .preview else {
            return
        }

        errorMessage = nil
        serveCount = 0
        lastServe = nil
        lastDetectionDelaySeconds = nil
        latestPoseTimestampSeconds = 0.0
        nextAnalysisSequenceNumber = 0
        pendingIngestCount = 0
        sessionID += 1
        let activeSessionID = sessionID
        let worker = analysisWorker

        phase = .starting
        statusMessage = "Starting ML Kit pose tracking."
        captureService.resetDebugClipBuffer()
        LiveServeDiagnostics.startSessionCapture()

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await worker.startSession(
                id: activeSessionID,
                providerKind: .mlKit,
                detectionMode: .shadowPrimary
            )
            await MainActor.run {
                guard self.sessionID == activeSessionID else { return }
                self.phase = .detecting
                self.statusMessage = "Detecting serves. Keep your full body visible."
                self.captureService.requestAccessAndStart(previewOnly: false)
            }
        }
    }

    func stopDetecting() {
        guard phase == .detecting || phase == .starting else {
            return
        }

        phase = .stopping
        statusMessage = "Stopping detection."
        captureService.setPoseProcessingEnabled(false)
        if pendingIngestCount == 0 {
            drainAndReturnToPreview()
        }
    }

    private func configureCallbacksIfNeeded() {
        guard !didConfigureCallbacks else {
            return
        }
        didConfigureCallbacks = true

        captureService.onReadyStateChange = { [weak self] isReady in
            Task { @MainActor in
                self?.isCameraReady = isReady
                if !isReady, self?.phase == .preview {
                    self?.latestOverlayFrame = nil
                }
                if !isReady, self?.phase == .starting {
                    self?.phase = .preview
                    self?.statusMessage = "Camera access is required to start detecting."
                }
            }
        }

        captureService.onStatusMessage = { [weak self] message in
            Task { @MainActor in
                guard let self, self.phase != .detecting else { return }
                self.statusMessage = message
            }
        }

        captureService.onError = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.errorMessage = message
                if self.phase == .starting {
                    self.phase = .preview
                    self.statusMessage = "Camera access is required to start detecting."
                }
            }
        }

        captureService.onOverlayPoseFrame = { [weak self] overlayFrame in
            Task { @MainActor in
                self?.latestOverlayFrame = overlayFrame
            }
        }

        captureService.onPoseFrame = { [weak self] poseFrame in
            Task { @MainActor in
                self?.handlePoseFrame(poseFrame)
            }
        }
    }

    private func handlePoseFrame(_ poseFrame: PoseFrame?) {
        guard let poseFrame else {
            return
        }
        latestPoseTimestampSeconds = poseFrame.timestampSeconds
        guard phase == .detecting else {
            return
        }
        scheduleAnalysis(for: poseFrame)
    }

    private func scheduleAnalysis(for poseFrame: PoseFrame) {
        let activeSessionID = sessionID
        let sequenceNumber = nextAnalysisSequenceNumber
        let worker = analysisWorker
        nextAnalysisSequenceNumber += 1
        pendingIngestCount += 1

        Task(priority: .userInitiated) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.ingestFinished()
                }
            }
            guard let self else { return }
            let orderedResults = await worker.ingest(
                frame: poseFrame,
                sessionID: activeSessionID,
                sequenceNumber: sequenceNumber
            )

            await MainActor.run {
                guard self.sessionID == activeSessionID else { return }
                for orderedResult in orderedResults {
                    self.apply(orderedResult)
                }
            }
        }
    }

    private func ingestFinished() {
        pendingIngestCount = max(pendingIngestCount - 1, 0)
        if phase == .stopping, pendingIngestCount == 0 {
            drainAndReturnToPreview()
        }
    }

    private func drainAndReturnToPreview() {
        let activeSessionID = sessionID
        let finalTimestamp = latestPoseTimestampSeconds
        let worker = analysisWorker
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let drainedResults = await worker.drainPendingServes(
                sessionID: activeSessionID,
                finalTimestamp: finalTimestamp
            )
            await MainActor.run {
                guard self.sessionID == activeSessionID else { return }
                for result in drainedResults {
                    self.apply(result, detectedAtSeconds: finalTimestamp)
                }
                LiveServeDiagnostics.stopSessionCapture()
                self.phase = .preview
                self.statusMessage = self.serveCount == 0
                    ? "Stopped. No serves detected."
                    : "Stopped. \(self.serveCount) serve(s) detected."
                self.captureService.requestAccessAndStart(previewOnly: true)
            }
        }
    }

    private func apply(_ orderedResult: ServeSessionOrderedIngestResult) {
        apply(
            orderedResult.result,
            detectedAtSeconds: orderedResult.frameTimestampSeconds
        )
    }

    private func apply(_ result: LiveServeIngestResult, detectedAtSeconds: Double) {
        guard let serve = result.emittedServe else {
            return
        }
        serveCount += 1
        lastServe = ServeEvent(
            serveIndex: serveCount,
            startTimeSeconds: serve.startTimeSeconds,
            endTimeSeconds: serve.endTimeSeconds,
            trophyTimeSeconds: serve.trophyTimeSeconds,
            impactTimeSeconds: serve.impactTimeSeconds,
            confidence: serve.confidence,
            handedness: serve.handedness,
            feedback: serve.feedback
        )
        lastDetectionDelaySeconds = max(detectedAtSeconds - serve.impactTimeSeconds, 0)
        statusMessage = "Serve \(serveCount) detected."
        let hasTossArmFault = serve.feedback.contains { $0.category == "toss_arm" }
        speakServeFeedback(hasTossArmFault: hasTossArmFault)
    }

    private func speakServeFeedback(hasTossArmFault: Bool) {
        let line = hasTossArmFault
            ? "Heads up. Your tossing arm bent during the ball toss. Keep it straight all the way up."
            : "Nice serve. Your tossing arm stayed straight through the toss."
        voiceFeedback.speak(line)
    }

    private func invalidateSession() {
        sessionID += 1
        let invalidatedSessionID = sessionID
        let worker = analysisWorker
        LiveServeDiagnostics.clearSessionCapture()
        Task(priority: .userInitiated) {
            await worker.resetSession(
                id: invalidatedSessionID,
                providerKind: .mlKit,
                detectionMode: .shadowPrimary
            )
        }
    }
}
