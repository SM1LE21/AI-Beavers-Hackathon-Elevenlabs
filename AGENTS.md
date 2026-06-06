# Agent Guide

## Purpose
- Keep changes clean, and reviewable. ( You will be reviewed by other Agents )
- Do not add system architecture explainers unless requested.
- Keep this file for durable conventions and learnings only.

## Working Principles

These apply to every task, before any of the conventions below.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

## Conventions

Full conventions live in this file. `CLAUDE.md` points Claude Code agents back here.

## Knowledge base

The canonical knowledge base for this repo lives in `.vault/` at the repo root.

- `.vault/STATUS.md` — current state, in-flight work, blockers, next steps
- `.vault/QUESTIONS.md` — open escalations needing human / product input
- `.vault/adr/` — architecture decision records

Any durable knowledge — decisions, open questions, project state, deployment facts — belongs in `.vault/`, not in scattered ad-hoc Markdown files.

The vault is agent-maintained: humans can read or review it, but agents keep it current. Read it at the start of any non-trivial session; update it as a byproduct of meaningful work.

## Commit Convention

```
<type>(<scope>): <short description>

Types: feat | fix | refactor | chore | docs
Scope: optional, e.g. session, feedback, ui, db
```

Examples:
- `feat(session): add phase transition logging`
- `fix(feedback): handle empty transcript gracefully`
- `chore: update Config API endpoint`

**Micro-commit every change that is worth a commit. No exceptions. No batching.** Under-committing is treated as a defect, not a stylistic choice. One commit per coherent change — e.g. implement a feature, commit it as that feature. If `git status` shows 3+ unrelated modified files, you are already in violation — stage and commit each separately.

**No AI attribution.** Never add a `Co-Authored-By: Claude ...` trailer, a "Generated with Claude Code" line, or any other AI/agent attribution to commit messages. Commit only under the configured human git identity.

## Git Identity

Commit under whatever git identity is already configured globally (e.g. via `~/.gitconfig`). Whatever `git config user.name` and `git config user.email` return is the right answer.

- **Never** run `git config user.name` or `git config user.email` (per-repo or global).
- **Never** create your own identity (`<app-name> agent`, `Claude`, etc.).
- **Never** volunteer the configured identity to the human, compare it to any other address, or suggest switching accounts. Whose account it is is not your concern.
- If the global identity is unset in a fresh repo, stop and ask the human to set it. Do not "fix" it yourself.

## Changelog

After each significant change, append an entry to `CHANGELOG.md`:

```
## YYYY-MM-DD HH:MM — <Title>
- bullet (1–4 max)
```

Edit `CHANGELOG.md` freely as part of the work that produced the change. Default
to internal-only entries and do not invent release-facing copy.

Before editing `RELEASE_NOTES.md`, ask the human whether the change belongs in
the next app release notes.
- If yes, capture the release-note wording/category the human wants tracked.
- If no, leave `RELEASE_NOTES.md` alone — keep the changelog entry internal-only.

Commit the changelog alongside or right after the work.

## Code Rules

- **Max ~300 lines per file** — split consciously if growing beyond this
- **One responsibility per file** — no god classes
- **Comments only on major functions** — keep them one-line max
- **No dead code** — remove rather than comment out
- **Lean over clever** — prefer readable over terse

## Validation
- Do not run Xcode builds, simulator launches, or app-level test/verification commands unless the human explicitly asks for them.
- Assume the human developer owns build checks, runtime checks, and visual QA for this project.
- Default to making code and documentation changes only, then hand off for human validation.

## Learnings - Here Agents should add lines for other agents to remember
- Add only durable learnings that change future implementation choices.
- Do not use this file for temporary notes, architecture narration, or long explanations.
- Segmentation/ML Kit `handedness` is unreliable for this single-camera setup (it flips between serves and often picks the hitting arm). The toss arm is the LEFT arm; key toss-arm logic on `.left`, not `handedness.opposite`.
- The real "bent toss arm" fault is a chronically bent arm (~110°), not a straight→bent dip. Detect it by absolute elbow extension near the toss apex (flag if it never reaches ~160°), not by a relative dip.
- ML Kit `inFrameLikelihood` (→ `visibility`) for the raised toss arm reads ~0.3–0.5; gate toss-arm frames at `>0`/0.1, not 0.5, or the analyzer is starved.
