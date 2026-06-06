import AVFoundation
import Foundation
import ImageIO
import UIKit

public struct LiveOverlayPalette {
    public let skeletonColor: UIColor
    public let jointsColor: UIColor

    public init(skeletonColor: UIColor, jointsColor: UIColor) {
        self.skeletonColor = skeletonColor
        self.jointsColor = jointsColor
    }
}

public enum LiveOverlayProjection {
    case manualPortrait
    case captureDevicePoint
}

struct LivePoseProviderOutput {
    let rawPoseFrame: PoseFrame?
    let overlayFrame: LiveOverlayFrame?
}

public enum LivePoseProviderKind: String, CaseIterable, Identifiable {
    case mlKit

    public var id: String {
        rawValue
    }

    public var displayName: String {
        "ML Kit Pose"
    }

    public var shortLabel: String {
        "ML Kit"
    }

    public var overlayPalette: LiveOverlayPalette {
        LiveOverlayPalette(
            skeletonColor: UIColor(red: 1.00, green: 0.60, blue: 0.12, alpha: 1.0),
            jointsColor: UIColor(red: 1.00, green: 0.22, blue: 0.52, alpha: 1.0)
        )
    }

    public var overlayProjection: LiveOverlayProjection {
        .captureDevicePoint
    }
}

protocol LivePoseProvider: AnyObject {
    var kind: LivePoseProviderKind { get }
    var issueMessage: String? { get }

    func process(
        sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation,
        frameIndex: Int,
        timestampSeconds: Double
    ) -> LivePoseProviderOutput?

    func stop()
}

enum LivePoseProviderFactory {
    static func make(kind: LivePoseProviderKind) -> LivePoseProvider {
        MLKitLivePoseProvider()
    }
}

struct RawPoseLandmark {
    let x: Double
    let y: Double
    let confidence: Double
    let z: Double?
}

func normalizedBufferPoint(
    fromOrientedNormalizedPoint point: CGPoint,
    orientation: CGImagePropertyOrientation
) -> CGPoint {
    switch orientation {
    case .up:
        return point
    case .upMirrored:
        return CGPoint(x: 1.0 - point.x, y: point.y)
    case .down:
        return CGPoint(x: 1.0 - point.x, y: 1.0 - point.y)
    case .downMirrored:
        return CGPoint(x: point.x, y: 1.0 - point.y)
    case .left:
        return CGPoint(x: point.y, y: 1.0 - point.x)
    case .leftMirrored:
        return CGPoint(x: 1.0 - point.y, y: 1.0 - point.x)
    case .right:
        return CGPoint(x: 1.0 - point.y, y: point.x)
    case .rightMirrored:
        return CGPoint(x: point.y, y: point.x)
    @unknown default:
        return point
    }
}

func makePoseFrame(
    index: Int,
    timestampSeconds: Double,
    rawLandmarks: [LandmarkName: RawPoseLandmark]
) -> PoseFrame? {
    guard !rawLandmarks.isEmpty else {
        return nil
    }

    let landmarks = rawLandmarks.mapValues { rawLandmark in
        PoseLandmark(
            x: clamp(rawLandmark.x),
            y: clamp(rawLandmark.y),
            visibility: clamp(rawLandmark.confidence),
            z: rawLandmark.z
        )
    }

    return PoseFrame(
        index: index,
        timestampSeconds: timestampSeconds,
        landmarks: landmarks
    )
}

func bodyOnlyOverlayFrame(from rawFrame: PoseFrame?) -> LiveOverlayFrame? {
    guard let rawFrame else {
        return nil
    }

    return makeLiveOverlayFrame(bodyFrame: rawFrame)
}

func makeLiveOverlayFrame(
    timestampSeconds: Double? = nil,
    bodyFrame: PoseFrame,
    bodyWorldLandmarks: [LandmarkName: WorldLandmark] = [:],
    hands: [HandSide: HandOverlayFrame] = [:],
    face: FaceOverlayFrame? = nil
) -> LiveOverlayFrame {
    let resolvedTimestamp = timestampSeconds ?? bodyFrame.timestampSeconds
    let resolvedBodyFrame: PoseFrame
    if bodyFrame.timestampSeconds == resolvedTimestamp {
        resolvedBodyFrame = bodyFrame
    } else {
        resolvedBodyFrame = PoseFrame(
            index: bodyFrame.index,
            timestampSeconds: resolvedTimestamp,
            landmarks: bodyFrame.landmarks
        )
    }

    return LiveOverlayFrame(
        timestampSeconds: resolvedTimestamp,
        bodyFrame: resolvedBodyFrame,
        bodyWorldLandmarks: bodyWorldLandmarks,
        hands: hands,
        face: face
    )
}

func overlayPoseFrame(
    from rawOverlayFrame: LiveOverlayFrame?,
    minimumConfidence: Double,
    minimumLandmarkCount: Int
) -> LiveOverlayFrame? {
    guard let rawOverlayFrame else {
        return nil
    }

    let filteredLandmarks = rawOverlayFrame.bodyFrame.landmarks.filter { _, landmark in
        landmark.visibility >= minimumConfidence
    }
    guard filteredLandmarks.count >= minimumLandmarkCount else {
        return nil
    }

    let filteredWorldLandmarks = rawOverlayFrame.bodyWorldLandmarks.filter { key, _ in
        filteredLandmarks[key] != nil
    }
    var filteredHands: [HandSide: HandOverlayFrame] = [:]
    for (handSide, handFrame) in rawOverlayFrame.hands {
        guard handFrame.confidence >= minimumConfidence else {
            continue
        }

        let landmarks = handFrame.landmarks.filter { _, landmark in
            landmark.visibility >= minimumConfidence
        }
        guard landmarks.count >= 5 else {
            continue
        }

        let worldLandmarks = handFrame.worldLandmarks.filter { key, _ in
            landmarks[key] != nil
        }

        filteredHands[handSide] = HandOverlayFrame(
            landmarks: landmarks,
            worldLandmarks: worldLandmarks,
            confidence: handFrame.confidence
        )
    }

    let filteredBodyFrame = PoseFrame(
        index: rawOverlayFrame.bodyFrame.index,
        timestampSeconds: rawOverlayFrame.timestampSeconds,
        landmarks: filteredLandmarks
    )

    return LiveOverlayFrame(
        timestampSeconds: rawOverlayFrame.timestampSeconds,
        bodyFrame: filteredBodyFrame,
        bodyWorldLandmarks: filteredWorldLandmarks,
        hands: filteredHands,
        face: rawOverlayFrame.face
    )
}

func analysisPoseFrame(
    from rawFrame: PoseFrame?,
    minimumConfidence: Double
) -> PoseFrame? {
    guard let rawFrame else {
        return nil
    }

    var landmarks: [LandmarkName: PoseLandmark] = [:]
    for landmarkName in LandmarkName.analysisCases {
        guard
            let landmark = rawFrame.landmarks[landmarkName],
            landmark.visibility >= minimumConfidence
        else {
            return nil
        }
        landmarks[landmarkName] = landmark
    }

    return PoseFrame(
        index: rawFrame.index,
        timestampSeconds: rawFrame.timestampSeconds,
        landmarks: landmarks
    )
}

func orientedImageSize(
    for sampleBuffer: CMSampleBuffer,
    orientation: CGImagePropertyOrientation
) -> CGSize {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        return .zero
    }

    let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
    let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
    if orientation.isQuarterTurn {
        return CGSize(width: height, height: width)
    }
    return CGSize(width: width, height: height)
}

private func clamp(_ value: Double) -> Double {
    min(max(value, 0.0), 1.0)
}

extension CGImagePropertyOrientation {
    var isQuarterTurn: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }

    var uiImageOrientation: UIImage.Orientation {
        switch self {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}
