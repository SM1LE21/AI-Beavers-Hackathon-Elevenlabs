# 0001 — First serve-error class: bent tossing arm

Date: 2026-06-06
Status: Accepted

## Context
The demo needs one serve error to detect and coach. The open question
(QUESTIONS.md) was which single error — the choice drives the whole detection
lane. The on-device stack is already fixed: Google ML Kit 2D pose, ~10 FPS
analysis, no depth (`PoseLandmark.z` is nil on the live path).

## Decision
Detect a **bent tossing arm during the toss**: the non-dominant arm starts
straight then flexes at the elbow as it rises to the trophy position. We
measure a *dip in elbow angle over the lift trajectory*, not the angle at a
single frame.

Chosen over candidates (low toss, foot fault, no knee bend, late trunk) because
it is the most reliably detectable with 2D pose: the toss arm is large, usually
unoccluded at the top of the swing, and the fault is a clear monotonic signal
(elbow angle falling while the wrist rises). It also has direct coaching value.

## How
Trajectory analyzer (`Support/TossArmFault.swift`) over the lift window
[bottom-of-lift … trophy], reusing `angleDegrees` and the toss-side landmarks:
- Prefer `flexion_rel` (player's own start angle − min angle) over absolute
  angle to cancel constant 2D-projection bias.
- Foreshortening guard via per-serve median arm span (drops frames where the
  limb points at the camera); negative slope of θ-vs-lift gates out an
  already-bent (non-rising) arm; median-of-3 smoothing + sustained-run +
  confidence weighting reject noise.
Surfaced as a `FeedbackItem(category: "toss_arm")` merged onto every emitted
serve at the `ServeSessionProcessor.analyze` chokepoints.

## Consequences
- 2D projection means we bias toward false negatives (miss depth-direction
  bends) rather than false positives — the safer choice for a demo.
- Thresholds (CONF_MIN, foreshorten ratio, 160/165° hysteresis, 0.15 s, 20°
  flexion_rel) are defaults and must be calibrated on real straight-vs-bent
  toss clips.
- The pre-existing single-frame trophy `toss_arm` check is kept; it catches a
  bent/short trophy snapshot, complementary to this dynamic detector.
- The verdict reaches `ServeEvent.feedback` but the current minimal UI does not
  render the feedback list, so it is not yet shown on screen (next: display /
  ElevenLabs TTS).
