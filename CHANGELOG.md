# Changelog

Newest entry on top. One entry per session. Each entry maps to one or more micro-commits in git log.

Format: `## YYYY-MM-DD HH:MM — <Title>`
1–4 bullets. Soft max: 2. A title alone is often enough.
Bullets are concrete and compact — no narration.

---

## 2026-06-06 16:06 — Fix toss-arm bend detection (never fired)
- Reworked `TossArmFault` to flag a dip near the toss apex (arm reaches ~straight ≥150° then bends ≥25°), restricted to the top of the toss so the natural arm-down descent is excluded. The old start-relative flexion + trophy-capped window made the fault unreachable, so every serve got positive feedback.
- Logs `toss_arm_fault` (straightest/min-after/dip/confidence) per serve for on-device threshold calibration.

## 2026-06-06 15:50 — Test voice button
- Added a "Test voice" button under Start/Stop that fires one ElevenLabs line on demand, to verify the TTS chain without landing a serve.
- Added full-path VoiceFeedback console logging (request, HTTP status + bytes, playback started + volume) to diagnose silent runs.

## 2026-06-06 15:35 — Per-serve ElevenLabs voice feedback
- Each detected serve triggers exactly one ElevenLabs TTS call: a fault line when the bent-toss-arm verdict fired, encouragement otherwise.
- API key lives in gitignored `Secrets.swift` (template `Secrets.swift.example`); empty key disables voice but keeps detection.
- Fault decision keys on the trajectory detector's verdict message, not any `toss_arm` item (avoids the pre-existing trophy heuristic).

## 2026-06-06 15:05 — Bent tossing-arm error detection
- Added a trajectory-based toss-arm fault detector (`TossArmFault.swift`): flags an elbow-angle dip during the upward lift, with 2D-projection guards (flexion_rel, foreshortening, negative-slope gate).
- Merged the verdict into every emitted serve's feedback in `ServeSessionProcessor`; chose this error class in ADR 0001 and resolved the open question.

## 2026-06-06 13:05 — Gate pose processing to active session
- MLKit pose inference and skeleton render now run only while detecting; the idle camera preview no longer processes frames.

## 2026-06-06 12:55 — Full screen, HUD restore, serve feedback
- Added UILaunchScreen so the app uses the whole screen (removes the top/bottom black letterbox bars).
- Restored the "Serve Detect" title and count pill (always visible).
- Added a serve-detected banner and success haptic when the count increments.

## 2026-06-06 12:40 — Strip preview HUD chrome
- Removed the title and always-on status line; count pill now shows only while detecting, so the preview is just camera + Start button.
- Forced full-height layout so the Start button pins to the bottom instead of floating mid-screen.

## 2026-06-06 12:10 — Declutter detection HUD
- Rebuilt ContentView into a camera-forward HUD: floating count pill, light material chips, one slim status line, slim Start/Stop button.
- Dropped the heavy full-screen gradient and verbose per-serve detail card; palette and pose skeleton overlay unchanged.

## 2026-06-06 11:30 — Minimal serve detection app
- Added a native SwiftUI iOS app scaffold with XcodeGen, CocoaPods, Google ML Kit pose detection, local serve-detection source, live camera preview, skeleton overlay, and start/stop serve counting UI.
- Kept setup aligned with the reference app and copied only the live serve-detection path needed for the first milestone.

## 2026-06-06 10:52 — Agent conventions floor
- Overlaid standard conventions onto existing repo: AGENTS.md (canonical), CLAUDE.md pointer, .gitignore, README, `.vault/` per Project Vault Standard.
- Commit convention customized: one commit per coherent change; no AI co-author/attribution trailers.
