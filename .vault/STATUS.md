## Current focus
- 2026-06-06 — AI Beavers Hackathon, 8h build. First milestone: open app → start detecting → detect/count tennis serves on device.

## Recent changes
- 2026-06-06 — Bundled voice fallback: pre-generated the 3 fixed coaching lines with ElevenLabs into `Resources/Voice/*.mp3`; `VoiceFeedback.speak(VoiceLine)` plays the bundled MP3 when the live call errors or no key is set. Voice now works offline / without a key.
- 2026-06-06 — Per-serve ElevenLabs voice feedback: `Voice/VoiceFeedback.swift` speaks one line per detected serve (fault vs clean), keyed off the `toss_arm` feedback item. Key in gitignored `Secrets.swift`.
- 2026-06-06 — Chose the demo serve error (bent tossing arm) and added a trajectory-based detector: new `Support/TossArmFault.swift` + verdict merged onto every emitted serve in `ServeSessionProcessor`. ADR 0001 records the decision. Not yet shown in UI.
- 2026-06-06 — Full-screen via UILaunchScreen (no more letterbox bars); restored title + count pill; added a serve-detected banner and success haptic.
- 2026-06-06 — Decluttered the detection HUD: camera-forward layout with a floating count pill, light material chips, slim status line and Start/Stop button. Palette and skeleton overlay unchanged.
- 2026-06-06 — Minimal native Swift app scaffolded with local serve-detection source, Google ML Kit pose runtime, live camera preview, skeleton overlay, and start/stop serve counting UI. No private Founta pods.
- 2026-06-06 — Repo initialized with standard agent conventions (AGENTS.md, CLAUDE.md, .gitignore, README.md, CHANGELOG.md, .vault/).

## Blockers
- (none)

## Known issues
- 2026-06-06 — Pre-existing (not introduced by the toss-arm work, surfaced by review): on the trophy-recovery path `ServeSessionProcessor` calls `forgetEmittedServe(primaryServe)` on `.hold`/`.reject` with the recovered event's new UUID, so the originally-registered cluster (`nextServe`) is never removed and can suppress a genuine re-detection of that serve for up to ~12 s (emission-tracker retention). Fix: also forget `nextServe`, or match by cluster identity. Left unfixed to keep the toss-arm change surgical.

## Next steps
- Run `xcodegen generate` to add `TossArmFault.swift` to the target, then build (SourceKit shows false "cannot find type" errors until the project is regenerated).
- Human device validation: run a real serve, confirm overlay tracking + count, and confirm a bent toss arm produces the `toss_arm` feedback item.
- Verify the reworked toss-arm detector on device: do a deliberately bent toss + a clean toss, read the `toss_arm_fault` log line (straightest/minAfter/dip) for each, and calibrate `straightReference` (150°) and `minDip` (25°) in `TossArmFault.swift` from those numbers.
- Voice now plays the bundled `Resources/Voice/*.mp3` even without a key; `xcodegen generate` must run to bundle those resources. Paste an ElevenLabs key into `Secrets.swift` for the live voice; optionally surface the fault text in the UI too.

## Runtime / deployment
- iOS, on physical device (camera + ML Kit perf). Current milestone has no network dependency. Future ElevenLabs API key belongs in `.env` (gitignored), never hardcoded.
