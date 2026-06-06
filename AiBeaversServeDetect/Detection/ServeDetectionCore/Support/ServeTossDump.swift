import Foundation

// Single-line JSON dump of the toss-window joints + the rule verdict, for offline LLM comparison.
// Coordinates are ML-Kit normalized image space (origin top-left, y increases downward).
private enum ServeTossDumpTuning {
    static let preTrophySeconds = 2.0
    static let postTrophySeconds = 1.0
}

private let serveTossDumpJoints: [LandmarkName] = [
    .nose, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
    .leftWrist, .rightWrist, .leftHip, .rightHip,
]

private struct ServeTossDumpPayload: Encodable {
    struct Window: Encodable { let start: Double; let end: Double }
    struct RuleVerdict: Encodable {
        let bendDetected: Bool
        let straightestAngle: Double
        let minAngleAfterStraight: Double
        let dipDegrees: Double
        let confidence: Double
    }
    struct Frame: Encodable { let t: Double; let joints: [String: [Double]] }

    let serveIndex: Int
    let handedness: String
    let tossSide: String
    let trophyTime: Double
    let impactTime: Double
    let window: Window
    let ruleVerdict: RuleVerdict
    let frames: [Frame]
}

// Builds the compact single-line JSON for one serve; nil only if encoding fails.
func serveTossDumpJSON(_ event: ServeEvent, in sequence: PoseSequence, fault: TossArmFault) -> String? {
    let windowStart = event.trophyTimeSeconds - ServeTossDumpTuning.preTrophySeconds
    let windowEnd = event.trophyTimeSeconds + ServeTossDumpTuning.postTrophySeconds

    var frames: [ServeTossDumpPayload.Frame] = []
    for frame in sequence.frames {
        let t = frame.timestampSeconds
        guard t >= windowStart, t <= windowEnd else { continue }
        var joints: [String: [Double]] = [:]
        for name in serveTossDumpJoints {
            guard let landmark = frame.landmarks[name] else { continue }
            joints[name.rawValue] = [round4(landmark.x), round4(landmark.y), round4(landmark.visibility)]
        }
        guard !joints.isEmpty else { continue }
        frames.append(.init(t: round3(t), joints: joints))
    }

    let payload = ServeTossDumpPayload(
        serveIndex: event.serveIndex,
        handedness: event.handedness.rawValue,
        tossSide: event.handedness.opposite.rawValue,
        trophyTime: round3(event.trophyTimeSeconds),
        impactTime: round3(event.impactTimeSeconds),
        window: .init(start: round3(windowStart), end: round3(windowEnd)),
        ruleVerdict: .init(
            bendDetected: fault.bendDetected,
            straightestAngle: round1(fault.straightestAngle),
            minAngleAfterStraight: round1(fault.minAngleAfterStraight),
            dipDegrees: round1(fault.dipDegrees),
            confidence: round2(fault.measurementConfidence)
        ),
        frames: frames
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(payload), let json = String(data: data, encoding: .utf8) else {
        return nil
    }
    return json
}

private func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
private func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
private func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
private func round4(_ value: Double) -> Double { (value * 10000).rounded() / 10000 }
