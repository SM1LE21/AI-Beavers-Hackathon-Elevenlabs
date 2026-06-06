## Current focus
- 2026-06-06 — AI Beavers Hackathon, 8h build. First milestone: open app → start detecting → detect/count tennis serves on device.

## Recent changes
- 2026-06-06 — Full-screen via UILaunchScreen (no more letterbox bars); restored title + count pill; added a serve-detected banner and success haptic.
- 2026-06-06 — Decluttered the detection HUD: camera-forward layout with a floating count pill, light material chips, slim status line and Start/Stop button. Palette and skeleton overlay unchanged.
- 2026-06-06 — Minimal native Swift app scaffolded with local serve-detection source, Google ML Kit pose runtime, live camera preview, skeleton overlay, and start/stop serve counting UI. No private Founta pods.
- 2026-06-06 — Repo initialized with standard agent conventions (AGENTS.md, CLAUDE.md, .gitignore, README.md, CHANGELOG.md, .vault/).

## Blockers
- (none)

## Next steps
- Human device validation: run a real serve, confirm the overlay tracks the body, and confirm the serve count increments a few seconds after impact.
- Pick the single error class to detect — most reliably detectable, not most impressive.
- Wire detected fault → cue text → ElevenLabs TTS → audio out.
- ADR 0001: on-device detection stack and the chosen error class.

## Runtime / deployment
- iOS, on physical device (camera + ML Kit perf). Current milestone has no network dependency. Future ElevenLabs API key belongs in `.env` (gitignored), never hardcoded.
