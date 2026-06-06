# AI Beavers Serve Detect

Minimal native iOS app for the first hackathon milestone: open the app, start
detecting, and count tennis serves on device.

The detection stack is mono-repo local Swift source copied from the current
serve-detection path. The only pod dependency is Google ML Kit pose detection;
there are no private app pods, auth flows, uploads, review UI, or branding
assets.

## Run Locally

```bash
cp Secrets.swift.example AiBeaversServeDetect/Voice/Secrets.swift  # then paste your ElevenLabs key
xcodegen generate
pod install
open AiBeaversServeDetect.xcworkspace
```

`Secrets.swift` is gitignored. Set `elevenLabsAPIKey` to hear per-serve voice
feedback; leaving it empty disables voice but keeps detection working.

Then run the `AiBeaversServeDetect` scheme on a physical iPhone. Camera and pose
runtime validation on simulator is not meaningful.

## Conventions

This repo follows the standard agent conventions. See [`AGENTS.md`](AGENTS.md) for durable rules and [`.vault/`](.vault/) for the persistent agent knowledge base.
