import Foundation

func sideFrameMetrics(frame: PoseFrame, handedness: Handedness) -> FrameMetrics? {
    guard
        let leftShoulder = frame.point(.leftShoulder),
        let rightShoulder = frame.point(.rightShoulder),
        let leftHip = frame.point(.leftHip),
        let rightHip = frame.point(.rightHip),
        let leftKnee = frame.point(.leftKnee),
        let rightKnee = frame.point(.rightKnee),
        let leftAnkle = frame.point(.leftAnkle),
        let rightAnkle = frame.point(.rightAnkle),
        let nose = frame.point(.nose)
    else {
        return nil
    }

    let tossSide = handedness.opposite
    guard
        let hitShoulder = frame.point(handedness == .right ? .rightShoulder : .leftShoulder),
        let hitElbow = frame.point(handedness == .right ? .rightElbow : .leftElbow),
        let hitWrist = frame.point(handedness == .right ? .rightWrist : .leftWrist),
        let tossShoulder = frame.point(tossSide == .right ? .rightShoulder : .leftShoulder),
        let tossElbow = frame.point(tossSide == .right ? .rightElbow : .leftElbow),
        let tossWrist = frame.point(tossSide == .right ? .rightWrist : .leftWrist)
    else {
        return nil
    }

    let bodyScale = max(distance(leftShoulder, rightShoulder), distance(leftHip, rightHip), 1e-6)
    let shoulderCenter = midpoint(leftShoulder, rightShoulder)
    let hipCenter = midpoint(leftHip, rightHip)

    let tossArmAngle = angleDegrees(tossShoulder, tossElbow, tossWrist)
    let hitArmAngle = angleDegrees(hitShoulder, hitElbow, hitWrist)
    let leftKneeAngle = angleDegrees(leftHip, leftKnee, leftAnkle)
    let rightKneeAngle = angleDegrees(rightHip, rightKnee, rightAnkle)
    let meanKneeAngle = (leftKneeAngle + rightKneeAngle) / 2.0
    let stanceWidthRatio = distance(leftAnkle, rightAnkle) / bodyScale
    let shoulderTilt = horizontalTiltDegrees(leftShoulder, rightShoulder)
    let trunkTilt = tiltFromVertical(hipCenter, shoulderCenter)
    let tossWristLiftRatio = (shoulderCenter.y - tossWrist.y) / bodyScale
    let tossShoulderLiftRatio = (hitShoulder.y - tossShoulder.y) / bodyScale

    let tossArmScore = targetScore(tossArmAngle, target: 175.0, tolerance: 35.0)
    let tossWristScore = clamp((tossWristLiftRatio - 0.2) / 1.1)
    let hitArmScore = targetScore(hitArmAngle, target: 95.0, tolerance: 50.0)
    let kneeScore = targetScore(meanKneeAngle, target: 115.0, tolerance: 45.0)
    let shoulderScore = clamp((tossShoulderLiftRatio + 0.05) / 0.4)
    let trunkScore = targetScore(trunkTilt, target: 12.0, tolerance: 18.0)

    let trophyScore = (
        (0.24 * tossArmScore) +
        (0.20 * tossWristScore) +
        (0.20 * hitArmScore) +
        (0.16 * kneeScore) +
        (0.12 * shoulderScore) +
        (0.08 * trunkScore)
    )

    _ = nose

    return FrameMetrics(
        frameIndex: frame.index,
        timestampSeconds: frame.timestampSeconds,
        handedness: handedness,
        trophyScore: trophyScore,
        tossArmAngle: tossArmAngle,
        tossWristLiftRatio: tossWristLiftRatio,
        tossShoulderLiftRatio: tossShoulderLiftRatio,
        hitArmAngle: hitArmAngle,
        meanKneeAngle: meanKneeAngle,
        stanceWidthRatio: stanceWidthRatio,
        shoulderTiltDegrees: shoulderTilt,
        trunkTiltDegrees: trunkTilt
    )
}
