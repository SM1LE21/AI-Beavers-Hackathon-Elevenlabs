## Current focus
- 2026-06-06 — AI Beavers Hackathon, 8h build. Core loop: detect a serve → detect one error → speak feedback via ElevenLabs. Swift, on device, ElevenLabs is the only network hop.

## Recent changes
- 2026-06-06 — Repo initialized with standard agent conventions (AGENTS.md, CLAUDE.md, .gitignore, README.md, CHANGELOG.md, .vault/).

## Blockers
- (none)

## Next steps
- Stand up the camera capture + serve-detection scaffold (Vision/CoreML, on device).
- Pick the single error class to detect — most reliably detectable, not most impressive.
- Wire detected fault → cue text → ElevenLabs TTS → audio out.
- ADR 0001: on-device detection stack (Vision/CoreML) and the chosen error class.

## Runtime / deployment
- iOS, on physical device (camera + perf). ElevenLabs API key in `.env` (gitignored), never hardcoded.
