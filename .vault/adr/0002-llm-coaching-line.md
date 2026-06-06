# 0002 — LLM-generated coaching line before TTS

Date: 2026-06-06
Status: Accepted

## Context
The voice path spoke one of two fixed lines per serve (toss-arm fault vs clean),
each backed by a bundled MP3 fallback. We want the spoken line to feel personal
and session-aware without touching the detector or the robust TTS fallback chain.

## Decision
Insert a fast LLM step between error detection and ElevenLabs:

```
detect serve -> fault/clean verdict
  -> build CoachContext (hardcoded demo profile + live session signals)
  -> GeminiCoachingProvider.coachingLine(context, fault)   [<=1.2s timeout]
  -> VoiceFeedback.speak(text:, fallback:)                  [ElevenLabs -> bundled MP3]
```

- **Provider:** Google Gemini `gemini-2.5-flash-lite`, thinking disabled, key in the
  gitignored `Secrets.swift`, behind a `CoachingProvider` protocol so `MockCoachingProvider`
  and a future Anthropic provider are one-line swaps.
- **LLM input is the verdict only** (fault/clean) plus minimal context: a hardcoded
  `CoachProfile.demo` (name, handedness, level) and live session signals (serve number,
  faults so far, clean streak). No joints, no metrics.
- **Output is exactly one short spoken sentence, <=10 words.** Enforced three ways: in the
  master prompt, by a low `maxOutputTokens`, and a parser guard (keep the first sentence;
  if it is still > 12 words, return nil and use the canned line).
- **Fallback is layered and never silent:** Gemini miss (empty key / timeout / error /
  over-long) -> canned `VoiceLine.text` -> ElevenLabs -> bundled MP3. An empty
  `geminiAPIKey` makes the feature a no-op (exactly today's behavior).

## Consequences
- Visible serve feedback (count, banner, haptic) is unchanged and instant; only the
  spoken line waits on the LLM, capped at ~1.2 s.
- The demo profile must stay right-handed while the detector hard-codes the toss arm to
  the left / assumes a right-handed server (changelog 2026-06-06 18:11).
- No test target (per AGENTS.md, agents do not run builds here); verification is via
  `MockCoachingProvider` + console logs + on-device serves. TDD intentionally not used.
- Rollback: the feature lives on branch `feat/llm-coaching-line` as micro-commits and is
  inert without a key; reverting the ViewModel wiring commit restores the previous voice
  path exactly.
