import AVFoundation
import Foundation

private struct SessionReplayClipRequest {
    let serveNumber: Int
    let provider: LivePoseProviderKind
    let impactTimeSeconds: Double
    let trophyTimeSeconds: Double
    let confidence: Double
    let clipStartSeconds: Double
    let clipEndSeconds: Double
}

final class SessionReplayRecorder {
    var onClipReady: ((LiveServeDebugClip) -> Void)?
    var onSourceVideoReady: ((URL) -> Void)?

    private let queue = DispatchQueue(label: "app.aibeavers.serve.session-replay", qos: .utility)
    private let clipPaddingBeforeSeconds = 0.6
    private let clipPaddingAfterSeconds = 0.9

    private var generation = 0
    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var recordingOutputURL: URL?
    private var finalizedSourceURL: URL?
    private var sessionStarted = false
    private var queuedRequests: [SessionReplayClipRequest] = []
    private var exportedServeNumbers: Set<Int> = []
    private var temporaryClipURLs: [URL] = []

    func beginSession() {
        queue.async {
            self.generation += 1
            self.resetStateLocked(removeFiles: true)
            self.recordingOutputURL = self.makeSessionOutputURL()
        }
    }

    func reset() {
        queue.async {
            self.generation += 1
            self.resetStateLocked(removeFiles: true)
        }
    }

    func ingest(sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard CMSampleBufferDataIsReady(sampleBuffer) else {
                return
            }

            do {
                try self.ensureWriterLocked(for: sampleBuffer)
            } catch {
                self.resetRecordingLocked(removeOutputFile: true)
                return
            }

            guard let assetWriter = self.assetWriter,
                  let writerInput = self.writerInput
            else {
                return
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !self.sessionStarted {
                guard assetWriter.startWriting() else {
                    self.resetRecordingLocked(removeOutputFile: true)
                    return
                }
                assetWriter.startSession(atSourceTime: presentationTime)
                self.sessionStarted = true
            }

            guard writerInput.isReadyForMoreMediaData else {
                return
            }

            guard writerInput.append(sampleBuffer) else {
                self.resetRecordingLocked(removeOutputFile: true)
                return
            }
        }
    }

    func finishSession() {
        queue.async {
            guard let assetWriter = self.assetWriter,
                  let writerInput = self.writerInput,
                  let recordingOutputURL = self.recordingOutputURL
            else {
                self.processQueuedExportsLocked()
                return
            }

            let currentGeneration = self.generation
            self.assetWriter = nil
            self.writerInput = nil
            self.recordingOutputURL = nil
            self.sessionStarted = false

            writerInput.markAsFinished()
            assetWriter.finishWriting {
                self.queue.async {
                    guard currentGeneration == self.generation else {
                        try? FileManager.default.removeItem(at: recordingOutputURL)
                        return
                    }

                    guard assetWriter.status == .completed else {
                        try? FileManager.default.removeItem(at: recordingOutputURL)
                        self.finalizedSourceURL = nil
                        return
                    }

                    self.finalizedSourceURL = recordingOutputURL
                    DispatchQueue.main.async {
                        self.onSourceVideoReady?(recordingOutputURL)
                    }
                    self.processQueuedExportsLocked()
                }
            }
        }
    }

    func enqueueClipExport(
        for event: ServeEvent,
        serveNumber: Int,
        provider: LivePoseProviderKind
    ) {
        queue.async {
            self.queuedRequests.removeAll { request in
                request.serveNumber == serveNumber
            }
            self.queuedRequests.append(
                SessionReplayClipRequest(
                    serveNumber: serveNumber,
                    provider: provider,
                    impactTimeSeconds: event.impactTimeSeconds,
                    trophyTimeSeconds: event.trophyTimeSeconds,
                    confidence: event.confidence,
                    clipStartSeconds: max(0.0, event.startTimeSeconds - self.clipPaddingBeforeSeconds),
                    clipEndSeconds: event.endTimeSeconds + self.clipPaddingAfterSeconds
                )
            )
            self.processQueuedExportsLocked()
        }
    }

    private func ensureWriterLocked(for sampleBuffer: CMSampleBuffer) throws {
        guard assetWriter == nil else {
            return
        }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw NSError(domain: "SessionReplayRecorder", code: 1)
        }

        if recordingOutputURL == nil {
            recordingOutputURL = makeSessionOutputURL()
        }
        guard let recordingOutputURL else {
            throw NSError(domain: "SessionReplayRecorder", code: 2)
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let writer = try AVAssetWriter(outputURL: recordingOutputURL, fileType: .mov)
        let compressionSettings: [String: Any] = [
            AVVideoAverageBitRateKey: max(Int(dimensions.width * dimensions.height * 10), 6_000_000),
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height),
                AVVideoCompressionPropertiesKey: compressionSettings,
            ],
            sourceFormatHint: formatDescription
        )
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw NSError(domain: "SessionReplayRecorder", code: 3)
        }

        writer.add(input)
        assetWriter = writer
        writerInput = input
    }

    private func processQueuedExportsLocked() {
        guard let finalizedSourceURL else {
            return
        }

        let requests = queuedRequests
            .sorted { $0.serveNumber < $1.serveNumber }
            .filter { !exportedServeNumbers.contains($0.serveNumber) }

        guard !requests.isEmpty else {
            return
        }

        let currentGeneration = generation
        for request in requests {
            do {
                let clip = try exportClip(
                    for: request,
                    from: finalizedSourceURL,
                    generation: currentGeneration
                )
                guard currentGeneration == generation else {
                    try? FileManager.default.removeItem(at: clip.url)
                    return
                }
                exportedServeNumbers.insert(request.serveNumber)
                temporaryClipURLs.append(clip.url)
                DispatchQueue.main.async {
                    self.onClipReady?(clip)
                }
            } catch {
                continue
            }
        }
    }

    private func exportClip(
        for request: SessionReplayClipRequest,
        from sourceURL: URL,
        generation: Int
    ) throws -> LiveServeDebugClip {
        let asset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
            throw NSError(domain: "SessionReplayRecorder", code: 4)
        }

        let assetDurationSeconds = CMTimeGetSeconds(asset.duration)
        let boundedClipEnd = min(assetDurationSeconds, request.clipEndSeconds)
        guard boundedClipEnd > request.clipStartSeconds else {
            throw NSError(domain: "SessionReplayRecorder", code: 5)
        }

        let timeRange = CMTimeRange(
            start: CMTime(seconds: request.clipStartSeconds, preferredTimescale: 600),
            end: CMTime(seconds: boundedClipEnd, preferredTimescale: 600)
        )

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "SessionReplayRecorder", code: 6)
        }

        try compositionVideoTrack.insertTimeRange(
            timeRange,
            of: sourceVideoTrack,
            at: .zero
        )

        if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           )
        {
            try? compositionAudioTrack.insertTimeRange(
                timeRange,
                of: sourceAudioTrack,
                at: .zero
            )
        }

        let sourceSize = sourceVideoTrack.naturalSize
        let needsPortraitRotation = sourceSize.width > sourceSize.height
        let renderSize = needsPortraitRotation
            ? CGSize(width: sourceSize.height, height: sourceSize.width)
            : sourceSize
        let baseTransform = sourceVideoTrack.preferredTransform
        let portraitTransform = needsPortraitRotation
            ? CGAffineTransform(translationX: sourceSize.height, y: 0).rotated(by: .pi / 2)
            : .identity

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: max(Int32(round(sourceVideoTrack.nominalFrameRate)), 30)
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: timeRange.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(baseTransform.concatenating(portraitTransform), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let outputURL = makeClipOutputURL(
            provider: request.provider,
            serveNumber: request.serveNumber,
            impactTimeSeconds: request.impactTimeSeconds,
            generation: generation
        )
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw NSError(domain: "SessionReplayRecorder", code: 7)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = false

        let semaphore = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        guard exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw exportSession.error ?? NSError(domain: "SessionReplayRecorder", code: 8)
        }

        return LiveServeDebugClip(
            serveNumber: request.serveNumber,
            provider: request.provider,
            clipStartTimeSeconds: request.clipStartSeconds,
            clipEndTimeSeconds: boundedClipEnd,
            impactTimeSeconds: request.impactTimeSeconds,
            trophyTimeSeconds: request.trophyTimeSeconds,
            confidence: request.confidence,
            url: outputURL
        )
    }

    private func resetStateLocked(removeFiles: Bool) {
        resetRecordingLocked(removeOutputFile: removeFiles)
        queuedRequests.removeAll()
        exportedServeNumbers.removeAll()

        if removeFiles {
            if let finalizedSourceURL {
                try? FileManager.default.removeItem(at: finalizedSourceURL)
            }
            for clipURL in temporaryClipURLs {
                try? FileManager.default.removeItem(at: clipURL)
            }
        }

        finalizedSourceURL = nil
        temporaryClipURLs.removeAll()
    }

    private func resetRecordingLocked(removeOutputFile: Bool) {
        assetWriter = nil
        writerInput = nil
        sessionStarted = false
        if removeOutputFile, let recordingOutputURL {
            try? FileManager.default.removeItem(at: recordingOutputURL)
        }
        recordingOutputURL = nil
    }

    private func makeSessionOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("session-source-\(UUID().uuidString).mov")
    }

    private func makeClipOutputURL(
        provider: LivePoseProviderKind,
        serveNumber: Int,
        impactTimeSeconds: Double,
        generation: Int
    ) -> URL {
        let fileName = String(
            format: "session-serve-%@-%02d-%06d-%03d.mov",
            provider.rawValue,
            serveNumber,
            Int(round(impactTimeSeconds * 100)),
            generation
        )
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}
