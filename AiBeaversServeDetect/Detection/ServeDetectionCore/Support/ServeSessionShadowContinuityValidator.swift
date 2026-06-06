import Foundation

struct ServeSessionShadowContinuityThresholds {
    let leadInSeconds: Double
    let followThroughSeconds: Double
    let minimumWindowFrameCount: Int
    let minimumCoverageRatio: Double
    let maximumGapSeconds: Double
    let maximumTorsoJumpRatio: Double
    let maximumScaleChangeRatio: Double

    static let `default` = ServeSessionShadowContinuityThresholds(
        leadInSeconds: 0.35,
        followThroughSeconds: 0.15,
        minimumWindowFrameCount: 5,
        minimumCoverageRatio: 0.55,
        maximumGapSeconds: 0.35,
        maximumTorsoJumpRatio: 1.0,
        maximumScaleChangeRatio: 0.55
    )
}

public struct ServeSessionShadowContinuityReport {
    public let accepted: Bool
    public let frameCount: Int
    public let coverageRatio: Double
    public let maximumGapSeconds: Double
    public let maximumTorsoJumpRatio: Double
    public let maximumScaleChangeRatio: Double
    public let rejectionReasons: [String]

    public init(
        accepted: Bool,
        frameCount: Int,
        coverageRatio: Double,
        maximumGapSeconds: Double,
        maximumTorsoJumpRatio: Double,
        maximumScaleChangeRatio: Double,
        rejectionReasons: [String]
    ) {
        self.accepted = accepted
        self.frameCount = frameCount
        self.coverageRatio = coverageRatio
        self.maximumGapSeconds = maximumGapSeconds
        self.maximumTorsoJumpRatio = maximumTorsoJumpRatio
        self.maximumScaleChangeRatio = maximumScaleChangeRatio
        self.rejectionReasons = rejectionReasons
    }
}

enum ServeSessionShadowContinuityValidator {
    static func report(
        for event: ServeEvent,
        in sequence: PoseSequence,
        thresholds: ServeSessionShadowContinuityThresholds = .default
    ) -> ServeSessionShadowContinuityReport {
        let windowStart = max(0.0, event.trophyTimeSeconds - thresholds.leadInSeconds)
        let windowEnd = event.impactTimeSeconds + thresholds.followThroughSeconds
        let bodyStates = serveSessionShadowBodyStates(
            in: sequence,
            startTime: windowStart,
            endTime: windowEnd
        )

        guard !bodyStates.isEmpty else {
            return ServeSessionShadowContinuityReport(
                accepted: false,
                frameCount: 0,
                coverageRatio: 0.0,
                maximumGapSeconds: .greatestFiniteMagnitude,
                maximumTorsoJumpRatio: .greatestFiniteMagnitude,
                maximumScaleChangeRatio: .greatestFiniteMagnitude,
                rejectionReasons: ["missing_candidate_window"]
            )
        }

        let expectedFrameCount = max(
            thresholds.minimumWindowFrameCount,
            Int(round((windowEnd - windowStart) * sequence.fps)) + 1
        )
        let coverageRatio = Double(bodyStates.count) / Double(max(expectedFrameCount, 1))
        var maximumGapSeconds = 0.0
        var maximumTorsoJump = 0.0
        var maximumScaleChange = 0.0

        for index in 1 ..< bodyStates.count {
            let previous = bodyStates[index - 1]
            let current = bodyStates[index]
            maximumGapSeconds = max(maximumGapSeconds, current.timestampSeconds - previous.timestampSeconds)
            maximumTorsoJump = max(
                maximumTorsoJump,
                serveSessionShadowTorsoJumpRatio(from: previous, to: current)
            )
            maximumScaleChange = max(
                maximumScaleChange,
                serveSessionShadowBodyScaleChangeRatio(from: previous, to: current)
            )
        }

        var rejectionReasons: [String] = []
        if bodyStates.count < thresholds.minimumWindowFrameCount {
            rejectionReasons.append("candidate_frame_count")
        }
        if coverageRatio < thresholds.minimumCoverageRatio {
            rejectionReasons.append("candidate_coverage")
        }
        if maximumGapSeconds > thresholds.maximumGapSeconds {
            rejectionReasons.append("candidate_gap")
        }
        if maximumTorsoJump > thresholds.maximumTorsoJumpRatio {
            rejectionReasons.append("candidate_torso_jump")
        }
        if maximumScaleChange > thresholds.maximumScaleChangeRatio {
            rejectionReasons.append("candidate_scale_jump")
        }

        return ServeSessionShadowContinuityReport(
            accepted: rejectionReasons.isEmpty,
            frameCount: bodyStates.count,
            coverageRatio: coverageRatio,
            maximumGapSeconds: maximumGapSeconds,
            maximumTorsoJumpRatio: maximumTorsoJump,
            maximumScaleChangeRatio: maximumScaleChange,
            rejectionReasons: rejectionReasons
        )
    }
}
