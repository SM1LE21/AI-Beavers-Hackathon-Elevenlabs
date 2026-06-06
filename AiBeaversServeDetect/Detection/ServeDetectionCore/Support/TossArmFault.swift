import CoreGraphics
import Foundation

// Defaults; calibrate θ_min + flexion_rel on real straight-vs-bent toss clips.
private enum TossArmTuning {
    static let lookbackSeconds = 2.0
    static let minVisibility = 0.5
    static let foreshortenMinRatio = 0.7      // drop frames whose arm projects < 70% of this serve's typical span
    static let smoothingWindow = 3            // median-of-3 keeps a 2-3 frame bend at ~10 FPS
    static let enterBendDegrees = 160.0
    static let exitBendDegrees = 165.0
    static let minBendDurationSeconds = 0.15
    static let minBendSamples = 2
    static let minFlexionRelDegrees = 20.0
    static let riseToleranceRatio = 0.02
    static let minValidSamples = 3
    static let trustedSampleCount = 5.0
    static let minReportConfidence = 0.35
}

struct TossArmFault {
    let bendDetected: Bool
    let minElbowAngle: Double
    let maxFlexionDegrees: Double      // 180 - minElbowAngle
    let flexionRelToStart: Double      // theta_start - theta_min over the lift
    let bendDurationSeconds: Double
    let measurementConfidence: Double  // 0..1; low => occluded / foreshortened / too few samples
}

private struct TossArmSample {
    let t: Double
    let theta: Double
    let lift: Double
    let armSpanRatio: Double
    let confidence: Double
}

// Detects a toss-arm fault where the arm starts straight then bends during the upward lift to trophy.
func detectTossArmFault(
    in sequence: PoseSequence,
    trophyTimeSeconds: Double,
    handedness: Handedness
) -> TossArmFault {
    let unreliable = TossArmFault(
        bendDetected: false,
        minElbowAngle: 180.0,
        maxFlexionDegrees: 0.0,
        flexionRelToStart: 0.0,
        bendDurationSeconds: 0.0,
        measurementConfidence: 0.0
    )

    let windowStart = trophyTimeSeconds - TossArmTuning.lookbackSeconds
    var consideredCount = 0
    var samples: [TossArmSample] = []
    for frame in sequence.frames {
        let t = frame.timestampSeconds
        guard t >= windowStart, t <= trophyTimeSeconds + 1e-6 else {
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

    let smoothTheta = medianFilter(framed.map { $0.theta }, window: TossArmTuning.smoothingWindow)
    let smoothLift = medianFilter(framed.map { $0.lift }, window: TossArmTuning.smoothingWindow)

    // Isolate the final continuous lift: walk back from trophy while the wrist was still rising.
    let startIndex = liftStartIndex(smoothLift: smoothLift)
    let riseTheta = Array(smoothTheta[startIndex...])
    let riseLift = Array(smoothLift[startIndex...])
    let riseTimes = framed[startIndex...].map { $0.t }
    let riseConf = framed[startIndex...].map { $0.confidence }
    guard riseTheta.count >= TossArmTuning.minValidSamples, let thetaMin = riseTheta.min() else {
        return unreliable
    }

    let thetaStart = median(Array(riseTheta.prefix(min(3, riseTheta.count)))) ?? riseTheta[0]
    let flexionRel = thetaStart - thetaMin
    let flexionAbs = 180.0 - thetaMin

    let bendRun = longestBendRun(
        theta: riseTheta,
        times: riseTimes,
        enter: TossArmTuning.enterBendDegrees,
        exit: TossArmTuning.exitBendDegrees
    )

    // Gate: the arm must bend WHILE rising (θ falls as wrist lift grows); a flat slope means "not on the way up".
    let onTheWayUp = (regressionSlope(x: riseLift, y: riseTheta) ?? 0.0) < 0.0

    let coverage = clamp(Double(framed.count) / Double(max(consideredCount, 1)))
    let meanConf = riseConf.reduce(0.0, +) / Double(riseConf.count)
    let sampleFactor = clamp(Double(riseTheta.count) / TossArmTuning.trustedSampleCount)
    let measurementConfidence = clamp(coverage * meanConf * sampleFactor)

    let bendDetected = bendRun.duration >= TossArmTuning.minBendDurationSeconds
        && bendRun.samples >= TossArmTuning.minBendSamples
        && flexionRel >= TossArmTuning.minFlexionRelDegrees
        && onTheWayUp

    return TossArmFault(
        bendDetected: bendDetected,
        minElbowAngle: thetaMin,
        maxFlexionDegrees: flexionAbs,
        flexionRelToStart: flexionRel,
        bendDurationSeconds: bendRun.duration,
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
        severity: clamp((fault.flexionRelToStart - 10.0) / 45.0),
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

private func liftStartIndex(smoothLift: [Double]) -> Int {
    guard smoothLift.count > 1 else {
        return 0
    }
    var i = smoothLift.count - 1
    while i > 0, smoothLift[i - 1] <= smoothLift[i] + TossArmTuning.riseToleranceRatio {
        i -= 1
    }
    return i
}

private func longestBendRun(
    theta: [Double],
    times: [Double],
    enter: Double,
    exit: Double
) -> (duration: Double, samples: Int) {
    var best = (duration: 0.0, samples: 0)
    var startTime: Double?
    var startIndex = 0
    var inBend = false

    for i in theta.indices {
        if !inBend {
            if theta[i] < enter {
                inBend = true
                startTime = times[i]
                startIndex = i
            }
        } else if theta[i] > exit {
            if let start = startTime, times[i - 1] - start > best.duration {
                best = (times[i - 1] - start, i - startIndex)
            }
            inBend = false
            startTime = nil
        }
    }
    if inBend, let start = startTime, (times.last ?? start) - start > best.duration {
        best = ((times.last ?? start) - start, theta.count - startIndex)
    }
    return best
}

private func regressionSlope(x: [Double], y: [Double]) -> Double? {
    let n = Double(x.count)
    guard n > 1 else {
        return nil
    }
    let meanX = x.reduce(0.0, +) / n
    let meanY = y.reduce(0.0, +) / n
    var numerator = 0.0
    var denominator = 0.0
    for i in x.indices {
        let dx = x[i] - meanX
        numerator += dx * (y[i] - meanY)
        denominator += dx * dx
    }
    guard denominator > 1e-9 else {
        return nil
    }
    return numerator / denominator
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
