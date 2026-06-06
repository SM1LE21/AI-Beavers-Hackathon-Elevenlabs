# Changelog

Newest entry on top. One entry per session. Each entry maps to one or more micro-commits in git log.

Format: `## YYYY-MM-DD HH:MM — <Title>`
1–4 bullets. Soft max: 2. A title alone is often enough.
Bullets are concrete and compact — no narration.

---

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
