import Foundation

// The master prompt plus the per-serve user message. This is the main iteration surface
// for the spoken coaching line — keep the <=10-word rule prominent.
enum CoachingPrompt {
    static let master = """
    You are a concise, encouraging tennis serve coach speaking out loud during a live \
    practice session. You are told the player's name, dominant hand, level, and how the \
    current serve went. Reply with exactly ONE short spoken sentence of at most 10 words, \
    warm and natural, to be read aloud immediately. No markdown, emoji, lists, or quotation \
    marks. Use the player's name occasionally, not every time. On a fault, give one specific, \
    actionable cue; when clean, give genuine, varied encouragement. Vary your wording across serves.
    """

    static func userMessage(_ context: CoachContext, fault: Bool) -> String {
        let p = context.profile
        let tossArm = p.handedness.opposite == .left ? "left" : "right"
        let serve = fault
            ? "BENT TOSSING ARM — the \(tossArm) (tossing) arm bent at the elbow during the toss"
            : "CLEAN — the tossing arm stayed straight through the toss"
        return """
        Player: \(p.name) (\(p.handedness.rawValue)-handed, \(p.level.rawValue)). \
        Serve #\(context.serveNumber). Faults so far: \(context.faultsSoFar). \
        Clean streak: \(context.cleanStreak). This serve: \(serve).
        """
    }
}
