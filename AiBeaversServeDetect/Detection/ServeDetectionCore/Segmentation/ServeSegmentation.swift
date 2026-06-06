import CoreGraphics
import Foundation

private struct ImpactCandidate {
    let frameIndex: Int
    let handedness: Handedness
    let confidence: Double
    let wristLiftRatio: Double
    let shoulderMarginRatio: Double
    let noseMarginRatio: Double
    let elbowAngle: Double
    let prominence: Double
}

private struct RecoveredCandidate {
    let impact: ImpactCandidate
    let trophyMetrics: FrameMetrics
    let heuristicConfidence: Double
}

private func localPeak(_ values: [Double], index: Int, radius: Int) -> Bool {
    let value = values[index]
    let start = max(0, index - radius)
    let end = min(values.count, index + radius + 1)
    for neighbor in start ..< end where neighbor != index {
        if values[neighbor] > value {
            return false
        }
    }
    return true
}

private func peakProminence(_ values: [Double], index: Int, radius: Int) -> Double {
    let value = values[index]
    let left = Array(values[max(0, index - radius) ..< index])
    let right = Array(values[(index + 1) ..< min(values.count, index + radius + 1)])
    let baseline = (left + right).max() ?? value
    return value - baseline
}

private func bodyReference(frame: PoseFrame) -> (CGPoint, Double)? {
    guard
        let leftShoulder = frame.point(.leftShoulder),
        let rightShoulder = frame.point(.rightShoulder),
        let leftHip = frame.point(.leftHip),
        let rightHip = frame.point(.rightHip)
    else {
        return nil
    }

    let shoulderCenter = midpoint(leftShoulder, rightShoulder)
    let bodyScale = max(distance(leftShoulder, rightShoulder), distance(leftHip, rightHip), 1e-6)
    return (shoulderCenter, bodyScale)
}

private func impactGeometry(frame: PoseFrame, handedness: Handedness) -> [String: Double]? {
    guard
        let (shoulderCenter, bodyScale) = bodyReference(frame: frame),
        let hitShoulder = frame.point(handedness == .right ? .rightShoulder : .leftShoulder),
        let hitElbow = frame.point(handedness == .right ? .rightElbow : .leftElbow),
        let hitWrist = frame.point(handedness == .right ? .rightWrist : .leftWrist),
        let nose = frame.point(.nose)
    else {
        return nil
    }

    return [
        "wristLiftRatio": (shoulderCenter.y - hitWrist.y) / bodyScale,
        "shoulderMarginRatio": (hitShoulder.y - hitWrist.y) / bodyScale,
        "noseMarginRatio": (nose.y - hitWrist.y) / bodyScale,
        "elbowAngle": angleDegrees(hitShoulder, hitElbow, hitWrist),
    ]
}

private func dedupeCandidates(
    _ candidates: [ImpactCandidate],
    fps: Double,
    gapSeconds: Double,
    preferLater: Bool = false
) -> [ImpactCandidate] {
    guard !candidates.isEmpty else {
        return []
    }
    let minGap = max(1, Int(round(fps * gapSeconds)))
    var deduped: [ImpactCandidate] = []

    for candidate in candidates.sorted(by: { $0.frameIndex < $1.frameIndex }) {
        if let last = deduped.last, candidate.frameIndex - last.frameIndex < minGap {
            if preferLater && candidate.frameIndex >= last.frameIndex {
                deduped[deduped.count - 1] = candidate
            } else if !preferLater && candidate.confidence > last.confidence {
                deduped[deduped.count - 1] = candidate
            }
            continue
        }
        deduped.append(candidate)
    }

    return deduped
}

private func detectImpactCandidates(sequence: PoseSequence) -> [ImpactCandidate] {
    let fps = max(sequence.fps, 1.0)
    let peakRadius = max(1, Int(round(fps * 0.18)))
    let sides: [Handedness] = [.right, .left]
    var sideValues: [Handedness: [Double]] = [:]
    var sideGeometry: [Handedness: [[String: Double]?]] = [:]

    for side in sides {
        sideValues[side] = []
        sideGeometry[side] = []
    }

    for frame in sequence.frames {
        for side in sides {
            let geometry = impactGeometry(frame: frame, handedness: side)
            sideGeometry[side, default: []].append(geometry)
            sideValues[side, default: []].append(geometry?["wristLiftRatio"] ?? -1.0)
        }
    }

    var candidates: [ImpactCandidate] = []

    for side in sides {
        let values = sideValues[side] ?? []
        let geometries = sideGeometry[side] ?? []

        for index in geometries.indices {
            guard let geometry = geometries[index] else {
                continue
            }

            let wristLiftRatio = geometry["wristLiftRatio"] ?? -1.0
            let shoulderMarginRatio = geometry["shoulderMarginRatio"] ?? -1.0
            let noseMarginRatio = geometry["noseMarginRatio"] ?? -1.0
            let elbowAngle = geometry["elbowAngle"] ?? 0.0

            guard localPeak(values, index: index, radius: peakRadius) else {
                continue
            }

            let prominence = peakProminence(values, index: index, radius: peakRadius)
            if prominence < 0.04 || shoulderMarginRatio < 0.18 || elbowAngle < 145.0 {
                continue
            }

            let confidence =
                (0.34 * clamp((shoulderMarginRatio - 0.18) / 0.55)) +
                (0.24 * clamp((noseMarginRatio + 0.05) / 0.35)) +
                (0.24 * clamp((elbowAngle - 145.0) / 30.0)) +
                (0.18 * clamp((prominence - 0.04) / 0.28))

            candidates.append(
                ImpactCandidate(
                    frameIndex: index,
                    handedness: side,
                    confidence: confidence,
                    wristLiftRatio: wristLiftRatio,
                    shoulderMarginRatio: shoulderMarginRatio,
                    noseMarginRatio: noseMarginRatio,
                    elbowAngle: elbowAngle,
                    prominence: prominence
                )
            )
        }
    }

    let firstPass = dedupeCandidates(candidates, fps: fps, gapSeconds: 0.6, preferLater: true)
    return dedupeCandidates(firstPass, fps: fps, gapSeconds: 2.2)
}

private func recoverCandidate(sequence: PoseSequence, candidate: ImpactCandidate) -> RecoveredCandidate? {
    let fps = max(sequence.fps, 1.0)
    let preWindow = max(2, Int(round(fps * 2.0)))
    let windowStart = max(0, candidate.frameIndex - preWindow)
    let windowEnd = max(windowStart + 1, candidate.frameIndex)

    var preImpactMetrics: [FrameMetrics] = []
    for frame in sequence.frames[windowStart ..< windowEnd] {
        if let metrics = sideFrameMetrics(frame: frame, handedness: candidate.handedness) {
            preImpactMetrics.append(metrics)
        }
    }

    guard let trophyMetrics = preImpactMetrics.max(by: { $0.trophyScore < $1.trophyScore }) else {
        return nil
    }
    guard trophyMetrics.frameIndex < candidate.frameIndex else {
        return nil
    }

    return RecoveredCandidate(
        impact: candidate,
        trophyMetrics: trophyMetrics,
        heuristicConfidence: min(candidate.confidence, max(trophyMetrics.trophyScore, 0.3))
    )
}

public enum ServeSegmentation {
    public static func detect(in sequence: PoseSequence) -> [ServeEvent] {
        let fps = max(sequence.fps, 1.0)
        let impactCandidates = detectImpactCandidates(sequence: sequence)
        guard !impactCandidates.isEmpty else {
            return []
        }

        let recoveredCandidates = impactCandidates.compactMap { recoverCandidate(sequence: sequence, candidate: $0) }
        guard !recoveredCandidates.isEmpty else {
            return []
        }

        var events: [ServeEvent] = []
        for recovered in recoveredCandidates {
            let trophyMetrics = recovered.trophyMetrics
            guard trophyMetrics.trophyScore >= 0.2 else {
                continue
            }
            guard recovered.heuristicConfidence >= 0.2 else {
                continue
            }

            let impactFrame = sequence.frames[recovered.impact.frameIndex]
            let startTime = max(0.0, trophyMetrics.timestampSeconds - 2.0)
            let endTime = impactFrame.timestampSeconds + 1.5

            events.append(
                ServeEvent(
                    serveIndex: events.count + 1,
                    startTimeSeconds: startTime,
                    endTimeSeconds: endTime,
                    trophyTimeSeconds: trophyMetrics.timestampSeconds,
                    impactTimeSeconds: impactFrame.timestampSeconds,
                    confidence: recovered.heuristicConfidence,
                    handedness: recovered.impact.handedness,
                    feedback: generateFeedback(metrics: trophyMetrics)
                )
            )
        }

        return dedupeOverlappingEvents(events, minGapSeconds: 1.0, fps: fps)
    }

    private static func dedupeOverlappingEvents(_ events: [ServeEvent], minGapSeconds: Double, fps: Double) -> [ServeEvent] {
        guard !events.isEmpty else {
            return []
        }

        let minGap = max(0.5, minGapSeconds - (1.0 / fps))
        var deduped: [ServeEvent] = []

        for event in events.sorted(by: { $0.impactTimeSeconds < $1.impactTimeSeconds }) {
            if let last = deduped.last, event.impactTimeSeconds - last.impactTimeSeconds < minGap {
                if event.confidence > last.confidence {
                    deduped[deduped.count - 1] = event
                }
                continue
            }
            deduped.append(event)
        }

        return deduped.enumerated().map { index, event in
            ServeEvent(
                serveIndex: index + 1,
                startTimeSeconds: event.startTimeSeconds,
                endTimeSeconds: event.endTimeSeconds,
                trophyTimeSeconds: event.trophyTimeSeconds,
                impactTimeSeconds: event.impactTimeSeconds,
                confidence: event.confidence,
                handedness: event.handedness,
                feedback: event.feedback
            )
        }
    }
}
