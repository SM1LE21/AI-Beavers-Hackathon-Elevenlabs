import AVFoundation
import Foundation
import os

#if canImport(MLKitPoseDetection) && canImport(MLKitVision)
import MLKitPoseDetection
import MLKitVision

final class MLKitLivePoseProvider: LivePoseProvider {
    static let log = Logger(subsystem: "AiBeaversServeDetect", category: "PoseDiagnostic")

    let kind: LivePoseProviderKind = .mlKit
    let issueMessage: String? = nil

    private let detector: PoseDetector

    init() {
        let options = PoseDetectorOptions()
        options.detectorMode = .stream
        detector = PoseDetector.poseDetector(options: options)
    }

    func process(
        sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation,
        frameIndex: Int,
        timestampSeconds: Double
    ) -> LivePoseProviderOutput? {
        let inPB = CMSampleBufferGetImageBuffer(sampleBuffer)
        let inW = inPB.map { CVPixelBufferGetWidth($0) } ?? -1
        let inH = inPB.map { CVPixelBufferGetHeight($0) } ?? -1
        Self.log.debug("MLKit.process: frame=\(frameIndex) t=\(timestampSeconds, format: .fixed(precision: 3)) buf=\(inW)x\(inH) orient=\(String(describing: orientation))")

        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = orientation.uiImageOrientation

        do {
            let poses = try detector.results(in: visionImage)
            guard let pose = poses.first else {
                Self.log.debug("MLKit.process: frame=\(frameIndex) no poses returned")
                return nil
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                Self.log.error("MLKit.process: frame=\(frameIndex) buffer missing post-detect")
                return nil
            }

            let imageWidth = Double(CVPixelBufferGetWidth(pixelBuffer))
            let imageHeight = Double(CVPixelBufferGetHeight(pixelBuffer))
            guard imageWidth > 0, imageHeight > 0 else {
                Self.log.error("MLKit.process: frame=\(frameIndex) zero dimensions w=\(imageWidth) h=\(imageHeight)")
                return nil
            }

            let mapping: [LandmarkName: PoseLandmarkType] = [
                .nose: .nose,
                .leftShoulder: .leftShoulder,
                .rightShoulder: .rightShoulder,
                .leftElbow: .leftElbow,
                .rightElbow: .rightElbow,
                .leftWrist: .leftWrist,
                .rightWrist: .rightWrist,
                .leftHip: .leftHip,
                .rightHip: .rightHip,
                .leftKnee: .leftKnee,
                .rightKnee: .rightKnee,
                .leftAnkle: .leftAnkle,
                .rightAnkle: .rightAnkle,
            ]

            var rawLandmarks: [LandmarkName: RawPoseLandmark] = [:]
            for (landmarkName, poseLandmarkType) in mapping {
                let landmark = pose.landmark(ofType: poseLandmarkType)
                let confidence = Double(landmark.inFrameLikelihood)
                guard confidence > 0 else {
                    continue
                }

                let normalizedImagePoint = CGPoint(
                    x: Double(landmark.position.x) / imageWidth,
                    y: Double(landmark.position.y) / imageHeight
                )
                let normalizedPoint = mlKitCaptureDevicePoint(
                    fromOrientedNormalizedPoint: normalizedImagePoint,
                    orientation: orientation
                )

                rawLandmarks[landmarkName] = RawPoseLandmark(
                    x: Double(normalizedPoint.x),
                    y: Double(normalizedPoint.y),
                    confidence: confidence,
                    z: nil
                )
            }

            let rawPoseFrame = makePoseFrame(
                index: frameIndex,
                timestampSeconds: timestampSeconds,
                rawLandmarks: rawLandmarks
            )
            #if DEBUG
            if let nose = rawLandmarks[.nose] {
                Self.log.debug("MLKit.process: frame=\(frameIndex) landmarks=\(rawLandmarks.count) nose normalized=(\(nose.x, format: .fixed(precision: 3)),\(nose.y, format: .fixed(precision: 3))) vis=\(nose.confidence, format: .fixed(precision: 2))")
            } else {
                Self.log.debug("MLKit.process: frame=\(frameIndex) landmarks=\(rawLandmarks.count) (no nose)")
            }
            #endif
            return LivePoseProviderOutput(
                rawPoseFrame: rawPoseFrame,
                overlayFrame: bodyOnlyOverlayFrame(from: rawPoseFrame)
            )
        } catch {
            Self.log.error("MLKit.process: frame=\(frameIndex) detector threw: \(error.localizedDescription)")
            return nil
        }
    }

    func stop() {}
}

private func mlKitCaptureDevicePoint(
    fromOrientedNormalizedPoint point: CGPoint,
    orientation: CGImagePropertyOrientation
) -> CGPoint {
    switch orientation {
    case .left:
        return CGPoint(x: 1.0 - point.y, y: point.x)
    case .leftMirrored:
        return CGPoint(x: point.y, y: point.x)
    case .right:
        return CGPoint(x: point.y, y: 1.0 - point.x)
    case .rightMirrored:
        return CGPoint(x: 1.0 - point.y, y: 1.0 - point.x)
    default:
        return normalizedBufferPoint(
            fromOrientedNormalizedPoint: point,
            orientation: orientation
        )
    }
}
#else
final class MLKitLivePoseProvider: LivePoseProvider {
    let kind: LivePoseProviderKind = .mlKit
    let issueMessage: String? = "ML Kit pods are not installed yet. Run `pod install` and open `AiBeaversServeDetect.xcworkspace`."

    func process(
        sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation,
        frameIndex: Int,
        timestampSeconds: Double
    ) -> LivePoseProviderOutput? {
        nil
    }

    func stop() {}
}
#endif
