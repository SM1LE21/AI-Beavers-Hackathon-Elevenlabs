import Foundation

public struct ServeSessionOrderedIngestResult {
    public let result: LiveServeIngestResult
    public let frameTimestampSeconds: Double

    public init(result: LiveServeIngestResult, frameTimestampSeconds: Double) {
        self.result = result
        self.frameTimestampSeconds = frameTimestampSeconds
    }
}

public actor ServeSessionAnalysisWorker {
    private let processor = ServeSessionProcessor()
    private var activeSessionID = 0
    private var nextSequenceNumber = 0
    private var pendingFramesBySequence: [Int: PoseFrame] = [:]

    public init() {}

    public func startSession(
        id: Int,
        providerKind: LivePoseProviderKind,
        detectionMode: ServeSessionDetectionMode
    ) {
        activeSessionID = id
        nextSequenceNumber = 0
        pendingFramesBySequence.removeAll()
        processor.configure(
            providerKind: providerKind,
            detectionMode: detectionMode
        )
        processor.reset()
    }

    public func resetSession(
        id: Int,
        providerKind: LivePoseProviderKind,
        detectionMode: ServeSessionDetectionMode
    ) {
        activeSessionID = id
        nextSequenceNumber = 0
        pendingFramesBySequence.removeAll()
        processor.configure(
            providerKind: providerKind,
            detectionMode: detectionMode
        )
        processor.reset()
    }

    public func ingest(
        frame: PoseFrame,
        sessionID: Int,
        sequenceNumber: Int
    ) -> [ServeSessionOrderedIngestResult] {
        guard sessionID == activeSessionID else {
            return []
        }

        pendingFramesBySequence[sequenceNumber] = frame
        return processPendingFrames()
    }

    public func drainPendingServes(
        sessionID: Int,
        finalTimestamp: Double
    ) -> [LiveServeIngestResult] {
        guard sessionID == activeSessionID else {
            return []
        }
        return processPendingFrames().map(\.result) + processor.drainPending(finalTimestamp: finalTimestamp)
    }

    private func processPendingFrames() -> [ServeSessionOrderedIngestResult] {
        var results: [ServeSessionOrderedIngestResult] = []

        while let frame = pendingFramesBySequence.removeValue(forKey: nextSequenceNumber) {
            if let result = processor.ingest(frame: frame) {
                results.append(
                    ServeSessionOrderedIngestResult(
                        result: result,
                        frameTimestampSeconds: frame.timestampSeconds
                    )
                )
            }
            nextSequenceNumber += 1
        }

        return results
    }
}
