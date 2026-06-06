public enum HandSide: String, CaseIterable, Identifiable {
    case left
    case right

    public var id: String {
        rawValue
    }
}

public enum HandLandmarkName: Int, CaseIterable {
    case wrist
    case thumbCMC
    case thumbMCP
    case thumbIP
    case thumbTIP
    case indexFingerMCP
    case indexFingerPIP
    case indexFingerDIP
    case indexFingerTIP
    case middleFingerMCP
    case middleFingerPIP
    case middleFingerDIP
    case middleFingerTIP
    case ringFingerMCP
    case ringFingerPIP
    case ringFingerDIP
    case ringFingerTIP
    case pinkyMCP
    case pinkyPIP
    case pinkyDIP
    case pinkyTIP
}

public struct HandOverlayFrame {
    public let landmarks: [HandLandmarkName: PoseLandmark]
    public let worldLandmarks: [HandLandmarkName: WorldLandmark]
    public let confidence: Double

    public init(
        landmarks: [HandLandmarkName: PoseLandmark],
        worldLandmarks: [HandLandmarkName: WorldLandmark],
        confidence: Double
    ) {
        self.landmarks = landmarks
        self.worldLandmarks = worldLandmarks
        self.confidence = confidence
    }
}

public struct GazeVector {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct FaceOverlayFrame {
    public let landmarkCount: Int
    public let anchor: PoseLandmark
    public let gazeTarget: PoseLandmark
    public let gazeVector: GazeVector
    public let yawDegrees: Double
    public let pitchDegrees: Double
    public let rollDegrees: Double

    public init(
        landmarkCount: Int,
        anchor: PoseLandmark,
        gazeTarget: PoseLandmark,
        gazeVector: GazeVector,
        yawDegrees: Double,
        pitchDegrees: Double,
        rollDegrees: Double
    ) {
        self.landmarkCount = landmarkCount
        self.anchor = anchor
        self.gazeTarget = gazeTarget
        self.gazeVector = gazeVector
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
        self.rollDegrees = rollDegrees
    }
}

public struct LiveOverlayFrame {
    public let timestampSeconds: Double
    public let bodyFrame: PoseFrame
    public let bodyWorldLandmarks: [LandmarkName: WorldLandmark]
    public let hands: [HandSide: HandOverlayFrame]
    public let face: FaceOverlayFrame?

    public init(
        timestampSeconds: Double,
        bodyFrame: PoseFrame,
        bodyWorldLandmarks: [LandmarkName: WorldLandmark],
        hands: [HandSide: HandOverlayFrame],
        face: FaceOverlayFrame?
    ) {
        self.timestampSeconds = timestampSeconds
        self.bodyFrame = bodyFrame
        self.bodyWorldLandmarks = bodyWorldLandmarks
        self.hands = hands
        self.face = face
    }
}
