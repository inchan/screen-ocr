# Autonomous System

This document explains how agents should keep the project moving without waiting for repeated human direction.

## Target Result

Build and verify a macOS menu bar screen OCR utility that captures a selected screen region with `Cmd+Shift+2` by default, falls back to `Cmd+Shift+0` when needed, runs local PaddleOCR, and writes recognized text to the clipboard.

## Operating Loop

1. Read `AGENTS.md`.
2. Inspect current files and latest validation report.
3. Choose the current gate from `docs/roadmap.md`.
4. If external facts can change or affect implementation, research with official sources and record findings in `docs/research.md`.
5. Convert findings into accepted or rejected decisions in `docs/decisions.md`.
6. Add one behavior-level test for the next vertical slice.
7. Implement the minimum code for that test.
8. Verify with targeted commands and record evidence.
9. Run `scripts/agent_gate.sh`.
10. Keep executable entry points listed in `docs/script-inventory.md`.
11. Add feedback if the loop exposed a process gap.

## Stop Conditions

Stop only when:
- the current user request is verified complete,
- the active gate has no safe next action,
- a destructive or credential-gated action is required,
- or a material product decision cannot be derived from existing requirements.

## Feedback-To-Rule Pipeline

Use this escalation ladder:

1. One-off issue: record it in `docs/feedback-loop.md`.
2. Repeated issue: add or update a check in `scripts/agent_gate.sh`.
3. Durable project rule: update `AGENTS.md`.
4. Product decision: update `docs/decisions.md`.

Every rule change needs evidence. Do not add process because it feels tidy.

## Parallelization Policy

Parallelize only independent work:
- PaddleOCR official-doc research can run beside Apple API research.
- Test fixture design can run beside app architecture review.
- Verification can run beside docs cleanup after implementation has a stable target.

Keep implementation write scopes disjoint when delegating. The leader owns integration and final verification.
