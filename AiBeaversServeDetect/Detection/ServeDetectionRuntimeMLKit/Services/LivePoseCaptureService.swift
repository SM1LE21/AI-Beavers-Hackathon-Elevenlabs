import AVFoundation
import Foundation
import ImageIO

public enum LivePoseCaptureError: LocalizedError {
    case cameraUnavailable
    case inputCreationFailed
    case outputCreationFailed

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "No camera is available for live serve detection."
        case .inputCreationFailed:
            return "The camera input could not be created."
        case .outputCreationFailed:
            return "The camera output could not be created."
        }
    }
}

public final class LivePoseCaptureService: NSObject {
    public enum ReplayMode {
        case debugBuffer
        case fullSessionSource
    }

    public let session = AVCaptureSession()

    public var onPoseFrame: ((PoseFrame?) -> Void)?
    public var onTechniquePoseFrame: ((PoseFrame) -> Void)?
    public var onOverlayPoseFrame: ((LiveOverlayFrame?) -> Void)?
    public var onDebugClipReady: ((LiveServeDebugClip) -> Void)?
    public var onSourceVideoReady: ((URL) -> Void)?
    public var onAnalysisStats: ((LiveCaptureAnalysisStats) -> Void)?
    public var onStatusMessage: ((String) -> Void)?
    public var onReadyStateChange: ((Bool) -> Void)?
    public var onError: ((String) -> Void)?

    private let minimumOverlayConfidence = 0.08
    private let minimumOverlayLandmarkCount = 6
    private let overlayPoseFPS: Double
    private let analysisPoseFPS: Double
    private let sessionPreset: AVCaptureSession.Preset
    private let replayMode: ReplayMode
    private let providerOrientation: CGImagePropertyOrientation = .right
    private let sessionQueue = DispatchQueue(label: "app.aibeavers.serve.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "app.aibeavers.serve.camera.video", qos: .userInitiated)
    private let overlayTracker = OverlayPoseTracker()
    private let debugClipRecorder = LiveServeDebugClipRecorder()
    private let sessionReplayRecorder = SessionReplayRecorder()

    private var providerKind: LivePoseProviderKind
    private var providerTuning: LiveServeProviderTuning
    private var provider: LivePoseProvider
    private var providerGeneration = 0
    private var cameraPosition: AVCaptureDevice.Position
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isRunning = false
    private var isPoseProcessingEnabled = true
    private var isReplayRecordingActive = false
    private var isProcessingPose = false
    private var firstTimestamp: Double?
    private var lastOverlayTimestamp = -Double.greatestFiniteMagnitude
    private var lastAnalysisTimestamp = -Double.greatestFiniteMagnitude
    private var lastAnalysisStatsTimestamp = -Double.greatestFiniteMagnitude
    private var nextFrameIndex = 0
    private var rawAnalysisPoseFrameCount = 0
    private var acceptedAnalysisPoseFrameCount = 0
    private var droppedAnalysisPoseFrameCount = 0

    public init(
        overlayPoseFPS: Double,
        analysisPoseFPS: Double,
        providerKind: LivePoseProviderKind = .mlKit,
        sessionPreset: AVCaptureSession.Preset = .vga640x480,
        replayMode: ReplayMode = .debugBuffer,
        cameraPosition: AVCaptureDevice.Position = .back
    ) {
        self.overlayPoseFPS = overlayPoseFPS
        self.analysisPoseFPS = analysisPoseFPS
        self.providerKind = providerKind
        self.sessionPreset = sessionPreset
        self.replayMode = replayMode
        self.cameraPosition = cameraPosition
        providerTuning = LiveServeProviderTuning.for(providerKind)
        provider = LivePoseProviderFactory.make(kind: providerKind)
        super.init()
        debugClipRecorder.onClipReady = { [weak self] clip in
            self?.onDebugClipReady?(clip)
        }
        sessionReplayRecorder.onClipReady = { [weak self] clip in
            self?.onDebugClipReady?(clip)
        }
        sessionReplayRecorder.onSourceVideoReady = { [weak self] url in
            self?.onSourceVideoReady?(url)
        }
    }

    public func requestAccessAndStart(previewOnly: Bool = false) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start(previewOnly: previewOnly)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else {
                    return
                }
                if granted {
                    self.start(previewOnly: previewOnly)
                } else {
                    self.emitReady(false)
                    self.emitError("Camera access is required for live serve detection.")
                }
            }
        case .denied, .restricted:
            emitReady(false)
            emitError("Camera access is required for live serve detection.")
        @unknown default:
            emitReady(false)
            emitError("Camera access could not be verified.")
        }
    }

    public func setPoseProcessingEnabled(_ isEnabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.setPoseProcessingEnabledLocked(isEnabled)
            if self.isRunning {
                self.emitCurrentProviderStatus()
            }
        }
    }

    public func start(previewOnly: Bool = false) {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }

                self.setPoseProcessingEnabledLocked(!previewOnly)

                guard !self.isRunning else {
                    self.emitReady(true)
                    self.emitCurrentProviderStatus()
                    return
                }

                self.resetSamplingState()
                self.session.startRunning()
                self.isRunning = true
                self.emitReady(true)
                self.emitCurrentProviderStatus()
            } catch {
                self.emitReady(false)
                self.emitError(error.localizedDescription)
            }
        }
    }

    public func stop() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            guard self.isRunning else {
                return
            }
            self.session.stopRunning()
            self.isRunning = false
            self.provider.stop()
            if self.replayMode == .fullSessionSource, self.isReplayRecordingActive {
                self.sessionReplayRecorder.finishSession()
                self.isReplayRecordingActive = false
            }
            self.resetSamplingState()
            self.emitOverlayPose(nil)
            self.emitPose(nil)
            self.emitReady(false)
        }
    }

    public func setProvider(_ newProviderKind: LivePoseProviderKind) {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            guard newProviderKind != self.providerKind else {
                return
            }

            self.provider.stop()
            self.providerKind = newProviderKind
            self.providerTuning = LiveServeProviderTuning.for(newProviderKind)
            self.provider = LivePoseProviderFactory.make(kind: newProviderKind)
            self.providerGeneration += 1
            self.resetSamplingState()
            self.resetReplayArtifacts()
            self.emitOverlayPose(nil)
            self.emitPose(nil)
            self.emitCurrentProviderStatus()
        }
    }

    public func resetDebugClipBuffer() {
        resetReplayArtifacts()
    }

    public func setCameraPosition(_ newCameraPosition: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            guard newCameraPosition != self.cameraPosition else {
                return
            }

            self.cameraPosition = newCameraPosition
            guard self.isConfigured else {
                return
            }

            do {
                try self.reconfigureCameraInput()
                self.provider.stop()
                self.resetSamplingState()
                self.emitOverlayPose(nil)
                self.emitPose(nil)
                if self.isRunning {
                    self.emitCurrentProviderStatus()
                }
            } catch {
                self.emitError(error.localizedDescription)
            }
        }
    }

    public func exportDebugClip(for event: ServeEvent, serveNumber: Int) {
        switch replayMode {
        case .debugBuffer:
            debugClipRecorder.exportClip(
                for: event,
                serveNumber: serveNumber,
                provider: providerKind
            )
        case .fullSessionSource:
            sessionReplayRecorder.enqueueClipExport(
                for: event,
                serveNumber: serveNumber,
                provider: providerKind
            )
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = sessionPreset

        do {
            try configureCameraInput()
        } catch {
            session.commitConfiguration()
            throw error
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw LivePoseCaptureError.outputCreationFailed
        }
        session.addOutput(output)
        configureVideoConnection(output.connection(with: .video))

        session.commitConfiguration()
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        guard isPoseProcessingEnabled else {
            return
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp.isFinite else {
            return
        }
        guard overlayPoseFPS > 0 else {
            return
        }
        guard timestamp - lastOverlayTimestamp >= (1.0 / overlayPoseFPS) else {
            return
        }
        guard !isProcessingPose else {
            return
        }

        lastOverlayTimestamp = timestamp
        isProcessingPose = true

        let normalizedTimestamp: Double
        if let firstTimestamp {
            normalizedTimestamp = timestamp - firstTimestamp
        } else {
            firstTimestamp = timestamp
            normalizedTimestamp = 0.0
        }

        if isPoseProcessingEnabled {
            switch replayMode {
            case .debugBuffer:
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    debugClipRecorder.ingest(
                        pixelBuffer: pixelBuffer,
                        timestampSeconds: normalizedTimestamp
                    )
                }
            case .fullSessionSource:
                sessionReplayRecorder.ingest(sampleBuffer: sampleBuffer)
            }
        }

        let frameIndex = nextFrameIndex
        nextFrameIndex += 1
        let currentProviderGeneration = providerGeneration
        let providerOutput = provider.process(
            sampleBuffer: sampleBuffer,
            orientation: providerOrientation,
            frameIndex: frameIndex,
            timestampSeconds: normalizedTimestamp
        )

        handleProcessedPoseFrame(
            providerOutput,
            sourceTimestamp: timestamp,
            normalizedTimestamp: normalizedTimestamp,
            providerGeneration: currentProviderGeneration
        )
    }

    private func handleProcessedPoseFrame(
        _ providerOutput: LivePoseProviderOutput?,
        sourceTimestamp: Double,
        normalizedTimestamp: Double,
        providerGeneration: Int
    ) {
        defer {
            isProcessingPose = false
        }

        guard providerGeneration == self.providerGeneration else {
            return
        }

        let rawPoseFrame = providerOutput?.rawPoseFrame
        let rawOverlayFrame = providerOutput?.overlayFrame ?? bodyOnlyOverlayFrame(from: rawPoseFrame)
        let liveOverlayFrame = overlayPoseFrame(
            from: rawOverlayFrame,
            minimumConfidence: minimumOverlayConfidence,
            minimumLandmarkCount: minimumOverlayLandmarkCount
        )
        emitOverlayPose(
            overlayTracker.stabilize(
                frame: liveOverlayFrame,
                timestampSeconds: normalizedTimestamp
            )
        )
        if isPoseProcessingEnabled, let rawPoseFrame {
            emitTechniquePose(rawPoseFrame)
        }

        guard isPoseProcessingEnabled else {
            emitPose(nil)
            return
        }
        guard analysisPoseFPS > 0 else {
            emitPose(nil)
            return
        }
        guard sourceTimestamp - lastAnalysisTimestamp >= (1.0 / analysisPoseFPS) else {
            return
        }

        lastAnalysisTimestamp = sourceTimestamp
        if rawPoseFrame != nil {
            rawAnalysisPoseFrameCount += 1
        }
        let liveAnalysisFrame = analysisPoseFrame(
            from: rawPoseFrame,
            minimumConfidence: providerTuning.analysisMinimumConfidence
        )
        if liveAnalysisFrame == nil, rawPoseFrame != nil {
            droppedAnalysisPoseFrameCount += 1
        } else if liveAnalysisFrame != nil {
            acceptedAnalysisPoseFrameCount += 1
        }
        maybeLogAnalysisStats(timestamp: normalizedTimestamp)
        emitPose(liveAnalysisFrame)
    }

    private func emitCurrentProviderStatus() {
        if isPoseProcessingEnabled {
            emitStatus("Camera live with \(providerKind.displayName). Start a session when ready.")
        } else {
            emitStatus("Camera preview live. Start a session when ready.")
        }
        if isPoseProcessingEnabled, let issueMessage = provider.issueMessage {
            emitError(issueMessage)
        }
    }

    private func emitOverlayPose(_ overlayFrame: LiveOverlayFrame?) {
        onOverlayPoseFrame?(overlayFrame)
    }

    private func emitPose(_ poseFrame: PoseFrame?) {
        onPoseFrame?(poseFrame)
    }

    private func emitTechniquePose(_ poseFrame: PoseFrame) {
        onTechniquePoseFrame?(poseFrame)
    }

    private func emitAnalysisStats(_ stats: LiveCaptureAnalysisStats) {
        onAnalysisStats?(stats)
    }

    private func emitStatus(_ message: String) {
        onStatusMessage?(message)
    }

    private func emitReady(_ isReady: Bool) {
        onReadyStateChange?(isReady)
    }

    private func emitError(_ message: String) {
        onError?(message)
    }

    private func resetSamplingState() {
        firstTimestamp = nil
        lastOverlayTimestamp = -Double.greatestFiniteMagnitude
        lastAnalysisTimestamp = -Double.greatestFiniteMagnitude
        lastAnalysisStatsTimestamp = -Double.greatestFiniteMagnitude
        nextFrameIndex = 0
        isProcessingPose = false
        rawAnalysisPoseFrameCount = 0
        acceptedAnalysisPoseFrameCount = 0
        droppedAnalysisPoseFrameCount = 0
        overlayTracker.reset()
    }

    private func resetReplayArtifacts() {
        switch replayMode {
        case .debugBuffer:
            debugClipRecorder.reset()
        case .fullSessionSource:
            sessionReplayRecorder.reset()
            isReplayRecordingActive = false
        }
    }

    private func setPoseProcessingEnabledLocked(_ isEnabled: Bool) {
        guard isEnabled != isPoseProcessingEnabled || !isConfigured else {
            return
        }

        isPoseProcessingEnabled = isEnabled
        provider.stop()
        resetSamplingState()
        emitOverlayPose(nil)
        emitPose(nil)

        guard replayMode == .fullSessionSource else {
            return
        }

        if isEnabled {
            guard !isReplayRecordingActive else {
                return
            }
            sessionReplayRecorder.beginSession()
            isReplayRecordingActive = true
        } else if isReplayRecordingActive {
            sessionReplayRecorder.finishSession()
            isReplayRecordingActive = false
        }
    }

    private func configureCameraInput() throws {
        let input = try makeCameraInput(for: cameraPosition)
        guard session.canAddInput(input) else {
            throw LivePoseCaptureError.inputCreationFailed
        }
        session.addInput(input)
        videoInput = input
    }

    private func reconfigureCameraInput() throws {
        guard let previousInput = videoInput else {
            throw LivePoseCaptureError.inputCreationFailed
        }

        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        session.removeInput(previousInput)
        do {
            let nextInput = try makeCameraInput(for: cameraPosition)
            guard session.canAddInput(nextInput) else {
                throw LivePoseCaptureError.inputCreationFailed
            }
            session.addInput(nextInput)
            videoInput = nextInput
            configureVideoConnection(session.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }.first?.connection(with: .video))
        } catch {
            if session.canAddInput(previousInput) {
                session.addInput(previousInput)
                videoInput = previousInput
                configureVideoConnection(session.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }.first?.connection(with: .video))
            }
            throw error
        }
    }

    private func makeCameraInput(for position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard let camera = cameraDevice(for: position) else {
            throw LivePoseCaptureError.cameraUnavailable
        }

        do {
            return try AVCaptureDeviceInput(device: camera)
        } catch {
            throw LivePoseCaptureError.inputCreationFailed
        }
    }

    private func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
    }

    private func configureVideoConnection(_ connection: AVCaptureConnection?) {
        guard let connection else {
            return
        }
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = false
        }
    }

    private func maybeLogAnalysisStats(timestamp: Double) {
        guard timestamp - lastAnalysisStatsTimestamp >= 1.5 else {
            return
        }
        lastAnalysisStatsTimestamp = timestamp
        let stats = LiveCaptureAnalysisStats(
            provider: providerKind,
            rawFrames: rawAnalysisPoseFrameCount,
            acceptedFrames: acceptedAnalysisPoseFrameCount,
            droppedFrames: droppedAnalysisPoseFrameCount
        )
        LiveServeDiagnostics.logCaptureAnalysisStats(stats)
        emitAnalysisStats(stats)
        rawAnalysisPoseFrameCount = 0
        acceptedAnalysisPoseFrameCount = 0
        droppedAnalysisPoseFrameCount = 0
    }
}

extension LivePoseCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        process(sampleBuffer: sampleBuffer)
    }
}
