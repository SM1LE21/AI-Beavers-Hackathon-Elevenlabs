import AVFoundation
import CoreImage
import CoreVideo
import ImageIO

public struct LiveServeDebugClip: Identifiable {
    public let id = UUID()
    public let serveNumber: Int
    public let provider: LivePoseProviderKind
    public let clipStartTimeSeconds: Double
    public let clipEndTimeSeconds: Double
    public let impactTimeSeconds: Double
    public let trophyTimeSeconds: Double
    public let confidence: Double
    public let url: URL

    public init(
        serveNumber: Int,
        provider: LivePoseProviderKind,
        clipStartTimeSeconds: Double,
        clipEndTimeSeconds: Double,
        impactTimeSeconds: Double,
        trophyTimeSeconds: Double,
        confidence: Double,
        url: URL
    ) {
        self.serveNumber = serveNumber
        self.provider = provider
        self.clipStartTimeSeconds = clipStartTimeSeconds
        self.clipEndTimeSeconds = clipEndTimeSeconds
        self.impactTimeSeconds = impactTimeSeconds
        self.trophyTimeSeconds = trophyTimeSeconds
        self.confidence = confidence
        self.url = url
    }

    public var clipDurationSeconds: Double {
        max(clipEndTimeSeconds - clipStartTimeSeconds, 0.0)
    }

    public func clipOffsetSeconds(forSessionTime sessionTimeSeconds: Double) -> Double {
        let unclampedOffset = sessionTimeSeconds - clipStartTimeSeconds
        return max(0.0, min(unclampedOffset, clipDurationSeconds))
    }
}

final class LiveServeDebugClipRecorder {
    var onClipReady: ((LiveServeDebugClip) -> Void)?

    private struct BufferedFrame {
        let timestampSeconds: Double
        let pixelBuffer: CVPixelBuffer
    }

    private let sampleFPS = 12.0
    private let bufferWindowSeconds = 14.0
    private let clipPaddingBeforeSeconds = 0.5
    private let clipPaddingAfterSeconds = 0.75
    private let outputSize = CGSize(width: 240.0, height: 320.0)
    private let queue = DispatchQueue(label: "app.aibeavers.serve.debug-clip", qos: .utility)
    private let ciContext = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private var bufferedFrames: [BufferedFrame] = []
    private var lastBufferedTimestamp = -Double.greatestFiniteMagnitude

    func reset() {
        queue.async {
            self.bufferedFrames.removeAll()
            self.lastBufferedTimestamp = -Double.greatestFiniteMagnitude
        }
    }

    func ingest(pixelBuffer: CVPixelBuffer, timestampSeconds: Double) {
        queue.async {
            guard timestampSeconds.isFinite else {
                return
            }
            guard timestampSeconds >= self.lastBufferedTimestamp + (1.0 / self.sampleFPS) else {
                return
            }
            guard let resizedBuffer = self.makeDebugPixelBuffer(from: pixelBuffer) else {
                return
            }

            self.lastBufferedTimestamp = timestampSeconds
            self.bufferedFrames.append(
                BufferedFrame(
                    timestampSeconds: timestampSeconds,
                    pixelBuffer: resizedBuffer
                )
            )
            self.trimBuffer(endingAt: timestampSeconds)
        }
    }

    func exportClip(
        for event: ServeEvent,
        serveNumber: Int,
        provider: LivePoseProviderKind
    ) {
        queue.async {
            let clipStart = max(0.0, event.startTimeSeconds - self.clipPaddingBeforeSeconds)
            let clipEnd = event.endTimeSeconds + self.clipPaddingAfterSeconds
            let clipFrames = self.bufferedFrames.filter { frame in
                frame.timestampSeconds >= clipStart && frame.timestampSeconds <= clipEnd
            }

            guard clipFrames.count >= 6 else {
                return
            }

            let fileName = String(
                format: "live-serve-%@-%02d-%06d.mov",
                provider.rawValue,
                serveNumber,
                Int(round(event.impactTimeSeconds * 100))
            )
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: outputURL)

            do {
                try self.writeClip(frames: clipFrames, to: outputURL)
                let clip = LiveServeDebugClip(
                    serveNumber: serveNumber,
                    provider: provider,
                    clipStartTimeSeconds: clipStart,
                    clipEndTimeSeconds: clipEnd,
                    impactTimeSeconds: event.impactTimeSeconds,
                    trophyTimeSeconds: event.trophyTimeSeconds,
                    confidence: event.confidence,
                    url: outputURL
                )
                DispatchQueue.main.async {
                    self.onClipReady?(clip)
                }
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
    }

    private func trimBuffer(endingAt latestTimestamp: Double) {
        bufferedFrames.removeAll { frame in
            latestTimestamp - frame.timestampSeconds > bufferWindowSeconds
        }
    }

    private func makeDebugPixelBuffer(from sourceBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        var destinationBuffer: CVPixelBuffer?
        let creationStatus = CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &destinationBuffer
        )

        guard creationStatus == kCVReturnSuccess, let destinationBuffer else {
            return nil
        }

        let orientedImage = CIImage(cvPixelBuffer: sourceBuffer)
            .oriented(forExifOrientation: Int32(CGImagePropertyOrientation.right.rawValue))
        let fittedImage = fittedImageForDebugClip(orientedImage)

        ciContext.render(
            fittedImage,
            to: destinationBuffer,
            bounds: CGRect(origin: .zero, size: outputSize),
            colorSpace: colorSpace
        )
        return destinationBuffer
    }

    private func fittedImageForDebugClip(_ image: CIImage) -> CIImage {
        let bounds = image.extent.integral
        guard bounds.width > 0, bounds.height > 0 else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: outputSize))
        }

        let scale = min(outputSize.width / bounds.width, outputSize.height / bounds.height)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let centeredImage = scaledImage.transformed(
            by: CGAffineTransform(
                translationX: ((outputSize.width - scaledImage.extent.width) / 2.0) - scaledImage.extent.minX,
                y: ((outputSize.height - scaledImage.extent.height) / 2.0) - scaledImage.extent.minY
            )
        )
        let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: outputSize))
        return centeredImage.composited(over: background)
    }

    private func writeClip(frames: [BufferedFrame], to outputURL: URL) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "LiveServeDebugClipRecorder", code: 1)
        }

        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "LiveServeDebugClipRecorder", code: 2)
        }

        writer.startSession(atSourceTime: .zero)
        let originTimestamp = frames.first?.timestampSeconds ?? 0.0

        for frame in frames {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }

            let presentationTime = CMTime(
                seconds: max(0.0, frame.timestampSeconds - originTimestamp),
                preferredTimescale: 600
            )

            guard adaptor.append(frame.pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? NSError(domain: "LiveServeDebugClipRecorder", code: 3)
            }
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "LiveServeDebugClipRecorder", code: 4)
        }
    }
}
