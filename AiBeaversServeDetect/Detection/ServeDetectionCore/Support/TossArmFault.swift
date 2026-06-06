import CoreGraphics
import Foundation

// Defaults; calibrate straightReference + minDip on real straight-vs-bent toss clips (read the logged dip per serve).
private enum TossArmTuning {
    static let preTrophySeconds = 2.0
    static let postTrophySeconds = 1.0          // trophy anchors on the straight instant; the bend develops just after
    static let minVisibility = 0.5
    static let foreshortenMinRatio = 0.7        // drop frames whose arm projects < 70% of this serve's typical span
    static let smoothingWindow = 3              // median-of-3 keeps a 2-3 frame bend at ~10 FPS
    static let nearTopLiftFraction = 0.75       // judge the elbow only near the toss apex (excludes the arm-down descent)
    static let minApexLiftRatio = 0.3           // wrist must clear the shoulders for a real toss top
    static let straightReferenceDegrees = 150.0 // the arm must reach ~straight before a bend counts as "straight -> bent"
    static let minDipDegrees = 25.0             // straightest-near-top minus the most-bent angle that follows it
    static let minValidSamples = 3
    static let minNearTopSamples = 3
    static let trustedSampleCount = 5.0
    static let minReportConfidence = 0.35
}

struct TossArmFault {
    let bendDetected: Bool
    let straightestAngle: Double      // peak elbow extension reached near the top of the toss
    let minAngleAfterStraight: Double // most-bent elbow angle after that peak, still near the top
    let dipDegrees: Double            // straightestAngle - minAngleAfterStraight
    let measurementConfidence: Double // 0..1; low => occluded / foreshortened / too few samples
}

private struct TossArmSample {
    let t: Double
    let theta: Double
    let lift: Double
    let armSpanRatio: Double
    let confidence: Double
}

// Detects a toss arm that reaches near-straight then bends near the top of the toss (a dip in elbow angle as it rises).
func detectTossArmFault(
    in sequence: PoseSequence,
    trophyTimeSeconds: Double,
    handedness: Handedness
) -> TossArmFault {
    let unreliable = TossArmFault(
        bendDetected: false,
        straightestAngle: 180.0,
        minAngleAfterStraight: 180.0,
        dipDegrees: 0.0,
        measurementConfidence: 0.0
    )

    let windowStart = trophyTimeSeconds - TossArmTuning.preTrophySeconds
    let windowEnd = trophyTimeSeconds + TossArmTuning.postTrophySeconds
    var consideredCount = 0
    var samples: [TossArmSample] = []
    for frame in sequence.frames {
        let t = frame.timestampSeconds
        guard t >= windowStart, t <= windowEnd else {
            continue
        }
        consideredCount += 1
        if let sample = tossArmSample(frame: frame, handedness: handedness) {
            samples.append(sample)
        }
    }
    guard samples.count >= TossArmTuning.minValidSamples else {
        return unreliable
    }
    samples.sort { $0.t < $1.t }

    // Foreshortening guard: drop frames where the arm projects far shorter than this serve's typical span.
    guard let typicalArmSpan = median(samples.map { $0.armSpanRatio }) else {
        return unreliable
    }
    let framed = samples.filter { $0.armSpanRatio >= TossArmTuning.foreshortenMinRatio * typicalArmSpan }
    guard framed.count >= TossArmTuning.minValidSamples else {
        return unreliable
    }

    let theta = medianFilter(framed.map { $0.theta }, window: TossArmTuning.smoothingWindow)
    let lift = medianFilter(framed.map { $0.lift }, window: TossArmTuning.smoothingWindow)

    // Restrict to the top of the toss (highest wrist) so the natural post-toss arm-down bend is excluded.
    guard let apexLift = lift.max(), apexLift >= TossArmTuning.minApexLiftRatio else {
        return unreliable
    }
    let liftThreshold = TossArmTuning.nearTopLiftFraction * apexLift
    let nearTop = framed.indices.filter { lift[$0] >= liftThreshold }
    guard nearTop.count >= TossArmTuning.minNearTopSamples else {
        return unreliable
    }

    // Straightest elbow near the top, then the most-bent angle that follows it in time (straight -> bend).
    let straightPosition = nearTop.indices.max(by: { theta[nearTop[$0]] < theta[nearTop[$1]] }) ?? nearTop.startIndex
    let straightestAngle = theta[nearTop[straightPosition]]
    let minAfterStraight = nearTop[straightPosition...].map { theta[$0] }.min() ?? straightestAngle
    let dip = straightestAngle - minAfterStraight

    let nearTopConfidence = nearTop.map { framed[$0].confidence }
    let coverage = clamp(Double(framed.count) / Double(max(consideredCount, 1)))
    let meanConf = nearTopConfidence.reduce(0.0, +) / Double(nearTopConfidence.count)
    let sampleFactor = clamp(Double(nearTop.count) / TossArmTuning.trustedSampleCount)
    let measurementConfidence = clamp(coverage * meanConf * sampleFactor)

    let bendDetected = straightestAngle >= TossArmTuning.straightReferenceDegrees
        && dip >= TossArmTuning.minDipDegrees

    return TossArmFault(
        bendDetected: bendDetected,
        straightestAngle: straightestAngle,
        minAngleAfterStraight: minAfterStraight,
        dipDegrees: dip,
        measurementConfidence: measurementConfidence
    )
}

// Returns the serve with a toss-arm coaching item merged in when a confident bend-during-toss fault is found.
func serveEventApplyingTossArmFault(_ event: ServeEvent, in sequence: PoseSequence) -> ServeEvent {
    let fault = detectTossArmFault(
        in: sequence,
        trophyTimeSeconds: event.trophyTimeSeconds,
        handedness: event.handedness
    )
    LiveServeDiagnostics.logTossArmFault(
        trophyTimeSeconds: event.trophyTimeSeconds,
        handedness: event.handedness,
        fault: fault
    )
    if let dump = serveTossDumpJSON(event, in: sequence, fault: fault) {
        LiveServeDiagnostics.logServeTossDump(dump)
    }
    guard let item = tossArmFaultFeedback(fault) else {
        return event
    }
    var feedback = event.feedback.filter { $0.category != "summary" }
    feedback.append(item)
    return ServeEvent(
        serveIndex: event.serveIndex,
        startTimeSeconds: event.startTimeSeconds,
        endTimeSeconds: event.endTimeSeconds,
        trophyTimeSeconds: event.trophyTimeSeconds,
        impactTimeSeconds: event.impactTimeSeconds,
        confidence: event.confidence,
        handedness: event.handedness,
        feedback: feedback
    )
}

// Builds the coaching item for a detected toss-arm bend; nil when no confident fault.
func tossArmFaultFeedback(_ fault: TossArmFault) -> FeedbackItem? {
    guard fault.bendDetected, fault.measurementConfidence >= TossArmTuning.minReportConfidence else {
        return nil
    }
    return FeedbackItem(
        category: "toss_arm",
        severity: clamp((fault.dipDegrees - 15.0) / 45.0),
        message: "Keep your tossing arm straight all the way up."
    )
}

private func tossArmSample(frame: PoseFrame, handedness: Handedness) -> TossArmSample? {
    let tossSide = handedness.opposite
    let shoulderName: LandmarkName = tossSide == .right ? .rightShoulder : .leftShoulder
    let elbowName: LandmarkName = tossSide == .right ? .rightElbow : .leftElbow
    let wristName: LandmarkName = tossSide == .right ? .rightWrist : .leftWrist

    guard
        let shoulder = frame.landmarks[shoulderName],
        let elbow = frame.landmarks[elbowName],
        let wrist = frame.landmarks[wristName],
        let leftShoulder = frame.landmarks[.leftShoulder], leftShoulder.visibility > 0,
        let rightShoulder = frame.landmarks[.rightShoulder], rightShoulder.visibility > 0
    else {
        return nil
    }

    let confidence = min(shoulder.visibility, elbow.visibility, wrist.visibility)
    guard confidence >= TossArmTuning.minVisibility else {
        return nil
    }

    var hipWidth = 0.0
    if let leftHip = frame.landmarks[.leftHip], leftHip.visibility > 0,
       let rightHip = frame.landmarks[.rightHip], rightHip.visibility > 0 {
        hipWidth = distance(leftHip.point, rightHip.point)
    }
    let bodyScale = max(distance(leftShoulder.point, rightShoulder.point), hipWidth, 1e-6)
    let shoulderCenter = midpoint(leftShoulder.point, rightShoulder.point)

    let s = shoulder.point
    let e = elbow.point
    let w = wrist.point
    return TossArmSample(
        t: frame.timestampSeconds,
        theta: angleDegrees(s, e, w),
        lift: (shoulderCenter.y - w.y) / bodyScale,
        armSpanRatio: (distance(s, e) + distance(e, w)) / bodyScale,
        confidence: confidence
    )
}

private func medianFilter(_ values: [Double], window: Int) -> [Double] {
    guard window > 1, values.count > 2 else {
        return values
    }
    let half = window / 2
    return values.indices.map { i in
        let lower = max(0, i - half)
        let upper = min(values.count - 1, i + half)
        return median(Array(values[lower ... upper])) ?? values[i]
    }
}

private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else {
        return nil
    }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2.0 : sorted[mid]
}
