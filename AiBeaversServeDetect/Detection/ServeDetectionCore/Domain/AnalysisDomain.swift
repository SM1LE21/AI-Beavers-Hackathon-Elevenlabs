import Foundation

public struct FrameMetrics {
    public let frameIndex: Int
    public let timestampSeconds: Double
    public let handedness: Handedness
    public let trophyScore: Double
    public let tossArmAngle: Double
    public let tossWristLiftRatio: Double
    public let tossShoulderLiftRatio: Double
    public let hitArmAngle: Double
    public let meanKneeAngle: Double
    public let stanceWidthRatio: Double
    public let shoulderTiltDegrees: Double
    public let trunkTiltDegrees: Double

    public init(
        frameIndex: Int,
        timestampSeconds: Double,
        handedness: Handedness,
        trophyScore: Double,
        tossArmAngle: Double,
        tossWristLiftRatio: Double,
        tossShoulderLiftRatio: Double,
        hitArmAngle: Double,
        meanKneeAngle: Double,
        stanceWidthRatio: Double,
        shoulderTiltDegrees: Double,
        trunkTiltDegrees: Double
    ) {
        self.frameIndex = frameIndex
        self.timestampSeconds = timestampSeconds
        self.handedness = handedness
        self.trophyScore = trophyScore
        self.tossArmAngle = tossArmAngle
        self.tossWristLiftRatio = tossWristLiftRatio
        self.tossShoulderLiftRatio = tossShoulderLiftRatio
        self.hitArmAngle = hitArmAngle
        self.meanKneeAngle = meanKneeAngle
        self.stanceWidthRatio = stanceWidthRatio
        self.shoulderTiltDegrees = shoulderTiltDegrees
        self.trunkTiltDegrees = trunkTiltDegrees
    }
}

public struct FeedbackItem: Identifiable {
    public let id = UUID()
    public let category: String
    public let severity: Double
    public let message: String

    public init(category: String, severity: Double, message: String) {
        self.category = category
        self.severity = severity
        self.message = message
    }
}

public struct ServeEvent: Identifiable {
    public let id = UUID()
    public let serveIndex: Int
    public let startTimeSeconds: Double
    public let endTimeSeconds: Double
    public let trophyTimeSeconds: Double
    public let impactTimeSeconds: Double
    public let confidence: Double
    public let handedness: Handedness
    public let feedback: [FeedbackItem]

    public init(
        serveIndex: Int,
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        trophyTimeSeconds: Double,
        impactTimeSeconds: Double,
        confidence: Double,
        handedness: Handedness,
        feedback: [FeedbackItem]
    ) {
        self.serveIndex = serveIndex
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.trophyTimeSeconds = trophyTimeSeconds
        self.impactTimeSeconds = impactTimeSeconds
        self.confidence = confidence
        self.handedness = handedness
        self.feedback = feedback
    }

    public var handednessLabel: String {
        handedness.rawValue.capitalized
    }
}

public struct AnalysisReport {
    public let videoName: String
    public let durationSeconds: Double
    public let processingSeconds: Double
    public let sampleFPS: Double
    public let sampledFrameCount: Int
    public let serveEvents: [ServeEvent]

    public init(
        videoName: String,
        durationSeconds: Double,
        processingSeconds: Double,
        sampleFPS: Double,
        sampledFrameCount: Int,
        serveEvents: [ServeEvent]
    ) {
        self.videoName = videoName
        self.durationSeconds = durationSeconds
        self.processingSeconds = processingSeconds
        self.sampleFPS = sampleFPS
        self.sampledFrameCount = sampledFrameCount
        self.serveEvents = serveEvents
    }

    public var durationLabel: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var processingLabel: String {
        if processingSeconds < 60.0 {
            return String(format: "%.2fs", processingSeconds)
        }
        let minutes = Int(processingSeconds) / 60
        let seconds = processingSeconds - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }
}
