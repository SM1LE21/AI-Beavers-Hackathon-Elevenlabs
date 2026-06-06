import CoreGraphics
import Foundation

final class OverlayPoseTracker {
    private let maxHoldSeconds = 0.12
    private let maxTorsoJumpScale = 0.75
    private let carryForwardSeconds = 0.08
    private let smoothingAlpha = 0.7

    private var lastStableFrame: LiveOverlayFrame?

    func reset() {
        lastStableFrame = nil
    }

    func stabilize(frame: LiveOverlayFrame?, timestampSeconds: Double) -> LiveOverlayFrame? {
        guard let frame else {
            return heldFrame(at: timestampSeconds)
        }

        guard let incomingTorso = torsoState(for: frame.bodyFrame) else {
            return heldFrame(at: timestampSeconds)
        }

        guard let lastStableFrame, let stableTorso = torsoState(for: lastStableFrame.bodyFrame) else {
            let seededFrame = retimestamped(frame: frame, timestampSeconds: timestampSeconds)
            self.lastStableFrame = seededFrame
            return seededFrame
        }

        let torsoJump = distance(incomingTorso.center, stableTorso.center)
        if torsoJump > max(stableTorso.scale * maxTorsoJumpScale, 0.08) {
            return heldFrame(at: timestampSeconds)
        }

        let canCarryForward = (timestampSeconds - lastStableFrame.timestampSeconds) <= carryForwardSeconds
        let stabilizedBodyFrame = PoseFrame(
            index: frame.bodyFrame.index,
            timestampSeconds: timestampSeconds,
            landmarks: stabilizedBodyLandmarks(
                current: frame.bodyFrame,
                previous: lastStableFrame.bodyFrame,
                canCarryForward: canCarryForward
            )
        )

        let stabilizedFrame = LiveOverlayFrame(
            timestampSeconds: timestampSeconds,
            bodyFrame: stabilizedBodyFrame,
            bodyWorldLandmarks: stabilizedWorldLandmarks(
                current: frame.bodyWorldLandmarks,
                previous: lastStableFrame.bodyWorldLandmarks,
                keys: LandmarkName.allCases,
                canCarryForward: canCarryForward
            ),
            hands: stabilizedHands(
                current: frame.hands,
                previous: lastStableFrame.hands,
                canCarryForward: canCarryForward
            ),
            face: stabilizedFace(
                current: frame.face,
                previous: lastStableFrame.face,
                canCarryForward: canCarryForward
            )
        )

        self.lastStableFrame = stabilizedFrame
        return stabilizedFrame
    }

    private func stabilizedBodyLandmarks(
        current: PoseFrame,
        previous: PoseFrame,
        canCarryForward: Bool
    ) -> [LandmarkName: PoseLandmark] {
        var landmarks: [LandmarkName: PoseLandmark] = [:]

        for landmarkName in LandmarkName.allCases {
            let currentLandmark = current.landmarks[landmarkName]
            let previousLandmark = previous.landmarks[landmarkName]

            switch (currentLandmark, previousLandmark) {
            case let (.some(currentLandmark), .some(previousLandmark)):
                landmarks[landmarkName] = blend(previous: previousLandmark, current: currentLandmark)
            case let (.some(currentLandmark), .none):
                landmarks[landmarkName] = currentLandmark
            case let (.none, .some(previousLandmark)) where canCarryForward:
                landmarks[landmarkName] = previousLandmark
            default:
                break
            }
        }

        return landmarks
    }

    private func stabilizedWorldLandmarks<Key: Hashable>(
        current: [Key: WorldLandmark],
        previous: [Key: WorldLandmark],
        keys: [Key],
        canCarryForward: Bool
    ) -> [Key: WorldLandmark] {
        var landmarks: [Key: WorldLandmark] = [:]

        for key in keys {
            let currentLandmark = current[key]
            let previousLandmark = previous[key]

            switch (currentLandmark, previousLandmark) {
            case let (.some(currentLandmark), .some(previousLandmark)):
                landmarks[key] = blend(previous: previousLandmark, current: currentLandmark)
            case let (.some(currentLandmark), .none):
                landmarks[key] = currentLandmark
            case let (.none, .some(previousLandmark)) where canCarryForward:
                landmarks[key] = previousLandmark
            default:
                break
            }
        }

        return landmarks
    }

    private func stabilizedHands(
        current: [HandSide: HandOverlayFrame],
        previous: [HandSide: HandOverlayFrame],
        canCarryForward: Bool
    ) -> [HandSide: HandOverlayFrame] {
        var hands: [HandSide: HandOverlayFrame] = [:]

        for handSide in HandSide.allCases {
            let currentHand = current[handSide]
            let previousHand = previous[handSide]

            switch (currentHand, previousHand) {
            case let (.some(currentHand), .some(previousHand)):
                let landmarks = stabilizedHandLandmarks(
                    current: currentHand.landmarks,
                    previous: previousHand.landmarks,
                    canCarryForward: canCarryForward
                )
                let worldLandmarks = stabilizedWorldLandmarks(
                    current: currentHand.worldLandmarks,
                    previous: previousHand.worldLandmarks,
                    keys: HandLandmarkName.allCases,
                    canCarryForward: canCarryForward
                )
                hands[handSide] = HandOverlayFrame(
                    landmarks: landmarks,
                    worldLandmarks: worldLandmarks,
                    confidence: max(currentHand.confidence, previousHand.confidence)
                )
            case let (.some(currentHand), .none):
                hands[handSide] = currentHand
            case let (.none, .some(previousHand)) where canCarryForward:
                hands[handSide] = previousHand
            default:
                break
            }
        }

        return hands
    }

    private func stabilizedHandLandmarks(
        current: [HandLandmarkName: PoseLandmark],
        previous: [HandLandmarkName: PoseLandmark],
        canCarryForward: Bool
    ) -> [HandLandmarkName: PoseLandmark] {
        var landmarks: [HandLandmarkName: PoseLandmark] = [:]

        for landmarkName in HandLandmarkName.allCases {
            let currentLandmark = current[landmarkName]
            let previousLandmark = previous[landmarkName]

            switch (currentLandmark, previousLandmark) {
            case let (.some(currentLandmark), .some(previousLandmark)):
                landmarks[landmarkName] = blend(previous: previousLandmark, current: currentLandmark)
            case let (.some(currentLandmark), .none):
                landmarks[landmarkName] = currentLandmark
            case let (.none, .some(previousLandmark)) where canCarryForward:
                landmarks[landmarkName] = previousLandmark
            default:
                break
            }
        }

        return landmarks
    }

    private func stabilizedFace(
        current: FaceOverlayFrame?,
        previous: FaceOverlayFrame?,
        canCarryForward: Bool
    ) -> FaceOverlayFrame? {
        switch (current, previous) {
        case let (.some(current), .some(previous)):
            return FaceOverlayFrame(
                landmarkCount: current.landmarkCount,
                anchor: blend(previous: previous.anchor, current: current.anchor),
                gazeTarget: blend(previous: previous.gazeTarget, current: current.gazeTarget),
                gazeVector: blend(previous: previous.gazeVector, current: current.gazeVector),
                yawDegrees: blend(previous: previous.yawDegrees, current: current.yawDegrees),
                pitchDegrees: blend(previous: previous.pitchDegrees, current: current.pitchDegrees),
                rollDegrees: blend(previous: previous.rollDegrees, current: current.rollDegrees)
            )
        case let (.some(current), .none):
            return current
        case let (.none, .some(previous)) where canCarryForward:
            return previous
        default:
            return nil
        }
    }

    private func heldFrame(at timestampSeconds: Double) -> LiveOverlayFrame? {
        guard let lastStableFrame else {
            return nil
        }
        guard timestampSeconds - lastStableFrame.timestampSeconds <= maxHoldSeconds else {
            self.lastStableFrame = nil
            return nil
        }

        return retimestamped(frame: lastStableFrame, timestampSeconds: timestampSeconds)
    }

    private func retimestamped(frame: LiveOverlayFrame, timestampSeconds: Double) -> LiveOverlayFrame {
        let bodyFrame = PoseFrame(
            index: frame.bodyFrame.index,
            timestampSeconds: timestampSeconds,
            landmarks: frame.bodyFrame.landmarks
        )

        return LiveOverlayFrame(
            timestampSeconds: timestampSeconds,
            bodyFrame: bodyFrame,
            bodyWorldLandmarks: frame.bodyWorldLandmarks,
            hands: frame.hands,
            face: frame.face
        )
    }

    private func blend(previous: PoseLandmark, current: PoseLandmark) -> PoseLandmark {
        PoseLandmark(
            x: blend(previous: previous.x, current: current.x),
            y: blend(previous: previous.y, current: current.y),
            visibility: max(previous.visibility, current.visibility),
            z: blendOptional(previous: previous.z, current: current.z)
        )
    }

    private func blend(previous: WorldLandmark, current: WorldLandmark) -> WorldLandmark {
        WorldLandmark(
            x: blend(previous: previous.x, current: current.x),
            y: blend(previous: previous.y, current: current.y),
            z: blend(previous: previous.z, current: current.z),
            visibility: blendOptional(previous: previous.visibility, current: current.visibility),
            presence: blendOptional(previous: previous.presence, current: current.presence)
        )
    }

    private func blend(previous: GazeVector, current: GazeVector) -> GazeVector {
        GazeVector(
            x: blend(previous: previous.x, current: current.x),
            y: blend(previous: previous.y, current: current.y),
            z: blend(previous: previous.z, current: current.z)
        )
    }

    private func blend(previous: Double, current: Double) -> Double {
        let alpha = smoothingAlpha
        return (previous * (1.0 - alpha)) + (current * alpha)
    }

    private func blendOptional(previous: Double?, current: Double?) -> Double? {
        switch (previous, current) {
        case let (.some(previous), .some(current)):
            return blend(previous: previous, current: current)
        case let (.some(previous), .none):
            return previous
        case let (.none, .some(current)):
            return current
        default:
            return nil
        }
    }

    private func torsoState(for frame: PoseFrame) -> (center: CGPoint, scale: Double)? {
        let torsoPoints = [
            frame.point(.leftShoulder),
            frame.point(.rightShoulder),
            frame.point(.leftHip),
            frame.point(.rightHip),
        ].compactMap { $0 }

        guard torsoPoints.count >= 3 else {
            return nil
        }

        let center = torsoPoints.reduce(CGPoint.zero) { partialResult, point in
            CGPoint(
                x: partialResult.x + point.x,
                y: partialResult.y + point.y
            )
        }
        let averagedCenter = CGPoint(
            x: center.x / CGFloat(torsoPoints.count),
            y: center.y / CGFloat(torsoPoints.count)
        )
        let shoulderScale = shoulderDistance(for: frame)
        let hipScale = hipDistance(for: frame)
        let scale = max(shoulderScale, hipScale, 1e-6)
        guard scale > 0 else {
            return nil
        }

        return (averagedCenter, scale)
    }

    private func shoulderDistance(for frame: PoseFrame) -> Double {
        guard
            let leftShoulder = frame.point(.leftShoulder),
            let rightShoulder = frame.point(.rightShoulder)
        else {
            return 0.0
        }

        return distance(leftShoulder, rightShoulder)
    }

    private func hipDistance(for frame: PoseFrame) -> Double {
        guard
            let leftHip = frame.point(.leftHip),
            let rightHip = frame.point(.rightHip)
        else {
            return 0.0
        }

        return distance(leftHip, rightHip)
    }
}
