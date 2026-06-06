import Foundation

struct ServeSessionShadowResetStateThresholds {
    let minimumElapsedSeconds: Double
    let recentWindowSeconds: Double
    let minimumNeutralFrames: Int
    let maximumNeutralTrophyScore: Double
    let maximumRaisedWristLiftRatio: Double

    static let `default` = ServeSessionShadowResetStateThresholds(
        minimumElapsedSeconds: 0.75,
        recentWindowSeconds: 1.0,
        minimumNeutralFrames: 3,
        maximumNeutralTrophyScore: 0.16,
        maximumRaisedWristLiftRatio: 0.16
    )
}

struct ServeSessionShadowResetStateReport {
    let satisfied: Bool
    let sampledFrameCount: Int
    let neutralFrameCount: Int
    let maxRecentTrophyScore: Double
    let maxRecentWristLiftRatio: Double
    let rejectionReason: String
}

enum ServeSessionShadowResetStateValidator {
    static func report(
        after serve: ServeEvent,
        in sequence: PoseSequence,
        thresholds: ServeSessionShadowResetStateThresholds = .default
    ) -> ServeSessionShadowResetStateReport {
        guard let latestTimestamp = sequence.frames.last?.timestampSeconds else {
            return ServeSessionShadowResetStateReport(
                satisfied: false,
                sampledFrameCount: 0,
                neutralFrameCount: 0,
                maxRecentTrophyScore: 0.0,
                maxRecentWristLiftRatio: 0.0,
                rejectionReason: "empty_sequence"
            )
        }

        let minimumResetTimestamp = serve.impactTimeSeconds + thresholds.minimumElapsedSeconds
        guard latestTimestamp >= minimumResetTimestamp else {
            return ServeSessionShadowResetStateReport(
                satisfied: false,
                sampledFrameCount: 0,
                neutralFrameCount: 0,
                maxRecentTrophyScore: 0.0,
                maxRecentWristLiftRatio: 0.0,
                rejectionReason: "reset_too_soon"
            )
        }

        let windowStart = max(minimumResetTimestamp, latestTimestamp - thresholds.recentWindowSeconds)
        let recentFrames = sequence.frames.filter { frame in
            frame.timestampSeconds >= windowStart
        }
        guard !recentFrames.isEmpty else {
            return ServeSessionShadowResetStateReport(
                satisfied: false,
                sampledFrameCount: 0,
                neutralFrameCount: 0,
                maxRecentTrophyScore: 0.0,
                maxRecentWristLiftRatio: 0.0,
                rejectionReason: "missing_reset_window"
            )
        }

        var neutralFrameCount = 0
        var maxRecentTrophyScore = 0.0
        var maxRecentWristLiftRatio = 0.0

        for frame in recentFrames {
            guard let bodyState = serveSessionShadowBodyState(for: frame) else {
                continue
            }

            let leftScore = sideFrameMetrics(frame: frame, handedness: .left)?.trophyScore ?? 0.0
            let rightScore = sideFrameMetrics(frame: frame, handedness: .right)?.trophyScore ?? 0.0
            let maxTrophyScore = max(leftScore, rightScore)
            let maxWristLiftRatio = bodyState.maximumWristLiftRatio

            maxRecentTrophyScore = max(maxRecentTrophyScore, maxTrophyScore)
            maxRecentWristLiftRatio = max(maxRecentWristLiftRatio, maxWristLiftRatio)

            if maxTrophyScore <= thresholds.maximumNeutralTrophyScore
                && maxWristLiftRatio <= thresholds.maximumRaisedWristLiftRatio
            {
                neutralFrameCount += 1
            }
        }

        let satisfied = neutralFrameCount >= thresholds.minimumNeutralFrames
        return ServeSessionShadowResetStateReport(
            satisfied: satisfied,
            sampledFrameCount: recentFrames.count,
            neutralFrameCount: neutralFrameCount,
            maxRecentTrophyScore: maxRecentTrophyScore,
            maxRecentWristLiftRatio: maxRecentWristLiftRatio,
            rejectionReason: satisfied ? "" : "awaiting_reset_state"
        )
    }
}
