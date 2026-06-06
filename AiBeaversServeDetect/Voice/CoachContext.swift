import Foundation

// Minimal, hardcoded player profile plus live session signals handed to the coaching LLM.
// Edit `CoachProfile.demo` for the demo athlete. Keep it right-handed: the detector
// currently hard-codes the toss arm to the left (assumes a right-handed server).
enum CoachLevel: String {
    case beginner
    case intermediate
    case advanced
}

struct CoachProfile {
    let name: String
    let handedness: Handedness
    let level: CoachLevel

    static let demo = CoachProfile(name: "Alex", handedness: .right, level: .intermediate)
}

struct CoachContext {
    let profile: CoachProfile
    let serveNumber: Int   // 1-based index of this serve in the session
    let faultsSoFar: Int   // toss-arm faults this session, including this serve
    let cleanStreak: Int   // consecutive clean serves ending at this one (0 on a fault)
}
