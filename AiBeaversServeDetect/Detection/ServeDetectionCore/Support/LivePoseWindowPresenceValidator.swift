import CoreGraphics
import Foundation

private struct LiveBodyPresenceSnapshot {
    let bodyHeight: Double
    let torsoHeight: Double
    let shoulderWidth: Double
    let hipWidth: Double
    let legHeight: Double
}

private enum LiveBodyAxis: CaseIterable {
    case x
    case y

    func component(of point: CGPoint) -> Double {
        switch self {
        case .x:
            return point.x
        case .y:
            return point.y
        }
    }
}

struct LivePoseWindowPresenceReport {
    let accepted: Bool
    let validFrameRatio: Double
    let medianBodyHeight: Double
    let medianTorsoHeight: Double
    let medianShoulderWidth: Double
    let medianHipWidth: Double
    let medianLegHeight: Double
    let rejectionReason: String
}

struct LivePoseWindowPresenceThresholds {
    let minimumValidFrameRatio: Double
    let minimumMedianBodyHeight: Double
    let minimumMedianTorsoHeight: Double
    let minimumMedianShoulderWidth: Double
    let minimumMedianLegHeight: Double

    static let `default` = LivePoseWindowPresenceThresholds(
        minimumValidFrameRatio: 0.48,
        minimumMedianBodyHeight: 0.16,
        minimumMedianTorsoHeight: 0.055,
        minimumMedianShoulderWidth: 0.035,
        minimumMedianLegHeight: 0.09
    )
}

enum LivePoseWindowPresenceValidator {
    static func accepts(
        _ sequence: PoseSequence,
        thresholds: LivePoseWindowPresenceThresholds = .default
    ) -> Bool {
        report(for: sequence, thresholds: thresholds).accepted
    }

    static func report(
        for sequence: PoseSequence,
        thresholds: LivePoseWindowPresenceThresholds = .default
    ) -> LivePoseWindowPresenceReport {
        guard !sequence.frames.isEmpty else {
            return LivePoseWindowPresenceReport(
                accepted: false,
                validFrameRatio: 0.0,
                medianBodyHeight: 0.0,
                medianTorsoHeight: 0.0,
                medianShoulderWidth: 0.0,
                medianHipWidth: 0.0,
                medianLegHeight: 0.0,
                rejectionReason: "empty_sequence"
            )
        }

        let snapshots = sequence.frames.compactMap(snapshot(for:))
        let validFrameRatio = Double(snapshots.count) / Double(sequence.frames.count)
        let medianBodyHeight = median(of: snapshots.map(\.bodyHeight))
        let medianTorsoHeight = median(of: snapshots.map(\.torsoHeight))
        let medianShoulderWidth = median(of: snapshots.map(\.shoulderWidth))
        let medianHipWidth = median(of: snapshots.map(\.hipWidth))
        let medianLegHeight = median(of: snapshots.map(\.legHeight))

        if validFrameRatio < thresholds.minimumValidFrameRatio {
            return LivePoseWindowPresenceReport(
                accepted: false,
                validFrameRatio: validFrameRatio,
                medianBodyHeight: medianBodyHeight,
                medianTorsoHeight: medianTorsoHeight,
                medianShoulderWidth: medianShoulderWidth,
                medianHipWidth: medianHipWidth,
                medianLegHeight: medianLegHeight,
                rejectionReason: "low_valid_ratio"
            )
        }

        if medianBodyHeight < thresholds.minimumMedianBodyHeight {
            return LivePoseWindowPresenceReport(
                accepted: false,
                validFrameRatio: validFrameRatio,
                medianBodyHeight: medianBodyHeight,
                medianTorsoHeight: medianTorsoHeight,
                medianShoulderWidth: medianShoulderWidth,
                medianHipWidth: medianHipWidth,
                medianLegHeight: medianLegHeight,
                rejectionReason: "small_body"
            )
        }

        if medianTorsoHeight < thresholds.minimumMedianTorsoHeight {
            return LivePoseWindowPresenceReport(
                accepted: false,
                validFrameRatio: validFrameRatio,
                medianBodyHeight: medianBodyHeight,
                medianTorsoHeight: medianTorsoHeight,
                medianShoulderWidth: medianShoulderWidth,
                medianHipWidth: medianHipWidth,
                medianLegHeight: medianLegHeight,
                rejectionReason: "small_torso"
            )
        }

        if medianShoulderWidth < thresholds.minimumMedianShoulderWidth {
            return LivePoseWindowPresenceReport(
                accepted: false,
                validFrameRatio: validFrameRatio,
                medianBodyHeight: medianBodyHeight,
                medianTorsoHeight: medianTorsoHeight,
                medianShoulderWidth: medianShoulderWidth,
                medianHipWidth: medianHipWidth,
                medianLegHeight: medianLegHeight,
                rejectionReason: "narrow_shoulders"
            )
        }

        if medianLegHeight < thresholds.minimumMedianLegHeight {
            return LivePoseWindowPresenceReport(
                accepted: false,
                validFrameRatio: validFrameRatio,
                medianBodyHeight: medianBodyHeight,
                medianTorsoHeight: medianTorsoHeight,
                medianShoulderWidth: medianShoulderWidth,
                medianHipWidth: medianHipWidth,
                medianLegHeight: medianLegHeight,
                rejectionReason: "short_legs"
            )
        }

        if medianHipWidth < (thresholds.minimumMedianShoulderWidth * 0.45) {
            return LivePoseWindowPresenceReport(
                accepted: false,
                validFrameRatio: validFrameRatio,
                medianBodyHeight: medianBodyHeight,
                medianTorsoHeight: medianTorsoHeight,
                medianShoulderWidth: medianShoulderWidth,
                medianHipWidth: medianHipWidth,
                medianLegHeight: medianLegHeight,
                rejectionReason: "narrow_hips"
            )
        }

        return LivePoseWindowPresenceReport(
            accepted: true,
            validFrameRatio: validFrameRatio,
            medianBodyHeight: medianBodyHeight,
            medianTorsoHeight: medianTorsoHeight,
            medianShoulderWidth: medianShoulderWidth,
            medianHipWidth: medianHipWidth,
            medianLegHeight: medianLegHeight,
            rejectionReason: ""
        )
    }

    private static func snapshot(for frame: PoseFrame) -> LiveBodyPresenceSnapshot? {
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

        let shoulderCenter = midpoint(leftShoulder, rightShoulder)
        let hipCenter = midpoint(leftHip, rightHip)
        let kneeCenter = midpoint(leftKnee, rightKnee)
        let ankleCenter = midpoint(leftAnkle, rightAnkle)
        let shoulderWidth = distance(leftShoulder, rightShoulder)
        let hipWidth = distance(leftHip, rightHip)

        let candidates = LiveBodyAxis.allCases.compactMap { axis -> LiveBodyPresenceSnapshot? in
            let shoulderValue = axis.component(of: shoulderCenter)
            let hipValue = axis.component(of: hipCenter)
            let kneeValue = axis.component(of: kneeCenter)
            let ankleValue = axis.component(of: ankleCenter)
            let noseValue = axis.component(of: nose)
            let direction = ankleValue >= shoulderValue ? 1.0 : -1.0

            let projectedShoulder = shoulderValue * direction
            let projectedHip = hipValue * direction
            let projectedKnee = kneeValue * direction
            let projectedAnkle = ankleValue * direction
            let projectedNose = noseValue * direction

            let torsoHeight = projectedHip - projectedShoulder
            let upperLegHeight = projectedKnee - projectedHip
            let lowerLegHeight = projectedAnkle - projectedKnee
            let legHeight = projectedAnkle - projectedHip
            let bodyHeight = projectedAnkle - projectedShoulder

            guard
                projectedShoulder < projectedHip,
                projectedHip < projectedKnee,
                projectedKnee <= projectedAnkle + 0.04,
                projectedNose <= projectedShoulder + 0.14
            else {
                return nil
            }

            guard
                shoulderWidth >= 0.03,
                hipWidth >= 0.02,
                torsoHeight >= 0.05,
                upperLegHeight >= 0.03,
                lowerLegHeight >= 0.02,
                legHeight >= 0.10,
                bodyHeight >= 0.18
            else {
                return nil
            }

            return LiveBodyPresenceSnapshot(
                bodyHeight: bodyHeight,
                torsoHeight: torsoHeight,
                shoulderWidth: shoulderWidth,
                hipWidth: hipWidth,
                legHeight: legHeight
            )
        }

        return candidates.max { lhs, rhs in
            lhs.bodyHeight < rhs.bodyHeight
        }
    }

    private static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0.0
        }

        let sortedValues = values.sorted()
        let midpointIndex = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[midpointIndex - 1] + sortedValues[midpointIndex]) / 2.0
        }
        return sortedValues[midpointIndex]
    }
}
