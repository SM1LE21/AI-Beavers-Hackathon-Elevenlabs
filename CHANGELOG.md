# Changelog

Newest entry on top. One entry per session. Each entry maps to one or more micro-commits in git log.

Format: `## YYYY-MM-DD HH:MM — <Title>`
1–4 bullets. Soft max: 2. A title alone is often enough.
Bullets are concrete and compact — no narration.

---

## 2026-06-06 12:10 — Declutter detection HUD
- Rebuilt ContentView into a camera-forward HUD: floating count pill, light material chips, one slim status line, slim Start/Stop button.
- Dropped the heavy full-screen gradient and verbose per-serve detail card; palette and pose skeleton overlay unchanged.

## 2026-06-06 11:30 — Minimal serve detection app
- Added a native SwiftUI iOS app scaffold with XcodeGen, CocoaPods, Google ML Kit pose detection, local serve-detection source, live camera preview, skeleton overlay, and start/stop serve counting UI.
- Kept setup aligned with the reference app and copied only the live serve-detection path needed for the first milestone.

## 2026-06-06 10:52 — Agent conventions floor
- Overlaid standard conventions onto existing repo: AGENTS.md (canonical), CLAUDE.md pointer, .gitignore, README, `.vault/` per Project Vault Standard.
- Commit convention customized: one commit per coherent change; no AI co-author/attribution trailers.
