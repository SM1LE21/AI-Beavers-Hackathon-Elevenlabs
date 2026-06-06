import CoreGraphics
import Foundation

public enum Handedness: String, Codable, CaseIterable {
    case left
    case right

    public var opposite: Handedness {
        self == .right ? .left : .right
    }

    public var displayTitle: String {
        rawValue.capitalized
    }
}

public enum LandmarkName: String, CaseIterable, Codable {
    case nose
    case leftEyeInner = "left_eye_inner"
    case leftEye = "left_eye"
    case leftEyeOuter = "left_eye_outer"
    case rightEyeInner = "right_eye_inner"
    case rightEye = "right_eye"
    case rightEyeOuter = "right_eye_outer"
    case leftEar = "left_ear"
    case rightEar = "right_ear"
    case mouthLeft = "mouth_left"
    case mouthRight = "mouth_right"
    case leftShoulder = "left_shoulder"
    case rightShoulder = "right_shoulder"
    case leftElbow = "left_elbow"
    case rightElbow = "right_elbow"
    case leftWrist = "left_wrist"
    case rightWrist = "right_wrist"
    case leftPinky = "left_pinky"
    case rightPinky = "right_pinky"
    case leftIndex = "left_index"
    case rightIndex = "right_index"
    case leftThumb = "left_thumb"
    case rightThumb = "right_thumb"
    case leftHip = "left_hip"
    case rightHip = "right_hip"
    case leftKnee = "left_knee"
    case rightKnee = "right_knee"
    case leftAnkle = "left_ankle"
    case rightAnkle = "right_ankle"
    case leftHeel = "left_heel"
    case rightHeel = "right_heel"
    case leftFootIndex = "left_foot_index"
    case rightFootIndex = "right_foot_index"

    public static let analysisCases: [LandmarkName] = [
        .nose,
        .leftShoulder,
        .rightShoulder,
        .leftElbow,
        .rightElbow,
        .leftWrist,
        .rightWrist,
        .leftHip,
        .rightHip,
        .leftKnee,
        .rightKnee,
        .leftAnkle,
        .rightAnkle,
    ]
}

public struct PoseLandmark: Codable {
    public let x: Double
    public let y: Double
    public let visibility: Double
    public let z: Double?

    public init(x: Double, y: Double, visibility: Double, z: Double?) {
        self.x = x
        self.y = y
        self.visibility = visibility
        self.z = z
    }

    public var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct WorldLandmark {
    public let x: Double
    public let y: Double
    public let z: Double
    public let visibility: Double?
    public let presence: Double?

    public init(x: Double, y: Double, z: Double, visibility: Double?, presence: Double?) {
        self.x = x
        self.y = y
        self.z = z
        self.visibility = visibility
        self.presence = presence
    }
}

public struct PoseFrame {
    public let index: Int
    public let timestampSeconds: Double
    public let landmarks: [LandmarkName: PoseLandmark]

    public init(index: Int, timestampSeconds: Double, landmarks: [LandmarkName: PoseLandmark]) {
        self.index = index
        self.timestampSeconds = timestampSeconds
        self.landmarks = landmarks
    }

    public func point(_ name: LandmarkName) -> CGPoint? {
        guard let landmark = landmarks[name], landmark.visibility > 0 else {
            return nil
        }
        return landmark.point
    }
}

public struct PoseSequence {
    public let fps: Double
    public let frames: [PoseFrame]
    public let source: String

    public init(fps: Double, frames: [PoseFrame], source: String) {
        self.fps = fps
        self.frames = frames
        self.source = source
    }
}
