# Screen OCR Agent Contract

This repository builds a macOS menu bar utility for screenshot OCR.

The product contract is:
- `Cmd+Shift+2` starts a region capture flow that feels close to macOS `Cmd+Shift+4`; if the default cannot be registered, the app falls back to `Cmd+Shift+0`.
- The selected screen region is captured as an image and made available to the app pipeline.
- PaddleOCR reads the captured image locally.
- The clipboard ends with recognized text when OCR succeeds.
- If OCR fails, the app must preserve useful user state: keep the captured image available when possible, write a diagnostic event, and expose the failure from the menu bar status.

## Autonomy

Work autonomously. Do not ask for permission for safe, reversible local actions such as reading files, writing docs, adding tests, implementing scoped code, running local commands, or launching local verification.

Ask only for destructive operations, credential-gated actions, external production changes, paid services, notarization account use, or decisions where two product outcomes would materially diverge.

## Required Workflow

Every substantial change follows this sequence:

1. Inspect current state.
2. Update or confirm the relevant artifact in `docs/`.
3. Write or update a behavior test before implementation when code behavior changes.
4. Implement the smallest aligned slice.
5. Run the narrowest meaningful verification first, then broader checks when available.
6. Update `docs/validation-report.md` with evidence.
7. Run `scripts/agent_gate.sh`.
8. Update `docs/feedback-loop.md` when the work revealed a process gap, repeated failure, or better rule.

Do not claim completion without fresh evidence.

## Phase Gates

The project advances through these gates:

- Explore: external facts and repo facts are documented in `docs/research.md`.
- Filter: included and rejected information is captured in `docs/decisions.md`.
- Specify: product behavior, permissions, data flow, and non-goals are captured in `docs/spec.md`.
- Test Plan: BDD/TDD scenarios, fixtures, and quantitative metrics are captured in `docs/test-plan.md`.
- Implement: code is written only for a documented vertical slice.
- Verify: tests, static checks, runtime smoke checks, and quantitative results are captured in `docs/validation-report.md`.

If a gate is incomplete, make concrete progress on that gate before moving forward.

## Parallel Work

Use parallel subagents when tasks are independent and materially improve throughput.

Good parallel lanes:
- Researcher: PaddleOCR docs, Apple APIs, packaging, permissions, or benchmark methodology.
- Explorer: repo-local mapping after code exists.
- Executor: disjoint implementation slices with non-overlapping write scopes.
- Verifier: independent evidence review after a slice has runnable checks.

Do not delegate the immediate blocking task when the main agent can resolve it faster locally. Always integrate and verify subagent results before treating them as project truth.

## Technical Defaults

These are starting defaults, not permanent decisions:

- macOS host: Swift/AppKit menu bar app.
- Hotkey: global `Cmd+Shift+2` by default with `Cmd+Shift+0` fallback, implemented through a native global shortcut path validated by a spike.
- Capture: region capture using a native macOS API or a minimal helper path, with permission handling documented before production polish.
- OCR: local PaddleOCR only, called through a Python sidecar/venv until a better minimal integration is proven.
- OCR profile: Korean-first mixed Korean/English, CPU-only by default.
- Clipboard: write recognized text on OCR success; preserve or expose captured image on failure.

Any change to these defaults must be recorded in `docs/decisions.md`.

## Test And Metrics Contract

Behavior tests must describe user-visible outcomes, not implementation details.

Required metric families:
- Capture latency: hotkey to image availability.
- OCR latency: cold and warm image-to-text time.
- OCR quality: character error rate and exact text recall on controlled fixtures.
- Reliability: pass rate over repeated captures.
- Resource cost: install size, model cache size, peak memory, and CPU profile when measurable.

Initial gates may use synthetic fixtures. Real screen crops must be added before claiming the utility is product-ready.

## Debugging Contract

Prefer reproducible evidence over guesswork.

For failures, capture:
- input image path or fixture id,
- OCR command/config,
- stdout/stderr or structured error,
- clipboard outcome,
- permission state,
- elapsed time,
- expected vs actual text.

Debug-only artifacts must live under ignored runtime/output directories once code exists. Do not scatter temporary files in source directories.

## Self-Feedback And Growth

This repository must improve its own operating system.

After each meaningful cycle, append a short entry to `docs/feedback-loop.md`:
- Observation: what slowed or endangered correctness.
- Evidence: command, file, or incident that proves it.
- Adjustment: the smallest rule, script, test, or doc change that prevents recurrence.
- Status: proposed, adopted, or rejected.

Patch this `AGENTS.md` only when a feedback entry proves that a durable repository rule changed. Patch scripts when a check can be automated.

## Completion Rule

Before marking the goal complete, audit every user requirement against direct evidence:

- `Cmd+Shift+2` capture flow works on macOS, with `Cmd+Shift+0` fallback when the default is unavailable.
- PaddleOCR reads captured image text locally.
- Clipboard contains OCR text after success.
- Menu bar app behavior is implemented.
- Research, filtered decisions, tech stack, BDD/TDD plan, quantitative fixtures, debugging strategy, roadmap, and feedback loop are documented.
- Relevant tests and smoke checks pass.
- Known gaps are either eliminated or explicitly outside the accepted scope.

Missing or indirect evidence means the goal is not complete.
