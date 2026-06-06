import Foundation

struct LiveServeProviderTuning {
    let decisionLagSeconds: Double
    let analysisMinimumConfidence: Double
    let emissionThresholds: LiveServeEmissionThresholds
    let presenceThresholds: LivePoseWindowPresenceThresholds
    let validationThresholds: LiveServeEventValidationThresholds
}

extension LiveServeProviderTuning {
    static func `for`(_ providerKind: LivePoseProviderKind) -> LiveServeProviderTuning {
        switch providerKind {
        case .mlKit:
            return LiveServeProviderTuning(
                decisionLagSeconds: 4.0,
                analysisMinimumConfidence: 0.15,
                emissionThresholds: LiveServeEmissionThresholds(
                    clusterImpactGapSeconds: 0.9,
                    clusterTrophyGapSeconds: 0.75,
                    clusterCoreOverlapSeconds: 0.3,
                    maximumImpactBacktrackSeconds: 0.3,
                    settleSeconds: 1.0
                ),
                presenceThresholds: LivePoseWindowPresenceThresholds(
                    minimumValidFrameRatio: 0.42,
                    minimumMedianBodyHeight: 0.145,
                    minimumMedianTorsoHeight: 0.048,
                    minimumMedianShoulderWidth: 0.032,
                    minimumMedianLegHeight: 0.08
                ),
                validationThresholds: LiveServeEventValidationThresholds(
                    minimumTrophyPeakScore: 0.21,
                    minimumTrophySupportFrames: 1,
                    minimumTossWristLiftRatio: 0.2,
                    minimumTossArmAngle: 120.0,
                    minimumImpactShoulderMargin: 0.12,
                    minimumImpactWristLiftRatio: 0.18,
                    minimumImpactDelaySeconds: 0.12,
                    maximumImpactDelaySeconds: 2.8,
                    minimumSatisfiedSignals: 3
                )
            )
        }
    }
}
