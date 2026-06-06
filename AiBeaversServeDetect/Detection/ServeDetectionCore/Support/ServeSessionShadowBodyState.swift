import CoreGraphics
import Foundation

struct ServeSessionShadowBodyState {
    let timestampSeconds: Double
    let torsoCenter: CGPoint
    let bodyScale: Double
    let leftWristLiftRatio: Double
    let rightWristLiftRatio: Double

    var maximumWristLiftRatio: Double {
        max(leftWristLiftRatio, rightWristLiftRatio)
    }
}

func serveSessionShadowBodyState(for frame: PoseFrame) -> ServeSessionShadowBodyState? {
    guard
        let leftShoulder = frame.point(.leftShoulder),
        let rightShoulder = frame.point(.rightShoulder),
        let leftHip = frame.point(.leftHip),
        let rightHip = frame.point(.rightHip),
        let leftWrist = frame.point(.leftWrist),
        let rightWrist = frame.point(.rightWrist)
    else {
        return nil
    }

    let torsoCenter = CGPoint(
        x: (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4.0,
        y: (leftShoulder.y + rightShoulder.y + leftHip.y + rightHip.y) / 4.0
    )
    let shoulderCenter = midpoint(leftShoulder, rightShoulder)
    let bodyScale = max(distance(leftShoulder, rightShoulder), distance(leftHip, rightHip), 1e-6)

    return ServeSessionShadowBodyState(
        timestampSeconds: frame.timestampSeconds,
        torsoCenter: torsoCenter,
        bodyScale: bodyScale,
        leftWristLiftRatio: (shoulderCenter.y - leftWrist.y) / bodyScale,
        rightWristLiftRatio: (shoulderCenter.y - rightWrist.y) / bodyScale
    )
}

func serveSessionShadowBodyStates(
    in sequence: PoseSequence,
    startTime: Double = -.greatestFiniteMagnitude,
    endTime: Double = .greatestFiniteMagnitude
) -> [ServeSessionShadowBodyState] {
    sequence.frames.compactMap { frame in
        guard frame.timestampSeconds >= startTime, frame.timestampSeconds <= endTime else {
            return nil
        }
        return serveSessionShadowBodyState(for: frame)
    }
}

func averagedServeSessionShadowBodyState(
    _ states: [ServeSessionShadowBodyState]
) -> ServeSessionShadowBodyState? {
    guard let lastTimestamp = states.last?.timestampSeconds, !states.isEmpty else {
        return nil
    }

    let count = Double(states.count)
    let center = states.reduce(CGPoint.zero) { partialResult, state in
        CGPoint(
            x: partialResult.x + state.torsoCenter.x,
            y: partialResult.y + state.torsoCenter.y
        )
    }

    return ServeSessionShadowBodyState(
        timestampSeconds: lastTimestamp,
        torsoCenter: CGPoint(
            x: center.x / count,
            y: center.y / count
        ),
        bodyScale: states.map(\.bodyScale).reduce(0.0, +) / count,
        leftWristLiftRatio: states.map(\.leftWristLiftRatio).reduce(0.0, +) / count,
        rightWristLiftRatio: states.map(\.rightWristLiftRatio).reduce(0.0, +) / count
    )
}

func serveSessionShadowTorsoJumpRatio(
    from previous: ServeSessionShadowBodyState,
    to current: ServeSessionShadowBodyState
) -> Double {
    distance(previous.torsoCenter, current.torsoCenter) / max(previous.bodyScale, current.bodyScale, 1e-6)
}

func serveSessionShadowBodyScaleChangeRatio(
    from previous: ServeSessionShadowBodyState,
    to current: ServeSessionShadowBodyState
) -> Double {
    abs(current.bodyScale - previous.bodyScale) / max(previous.bodyScale, current.bodyScale, 1e-6)
}
