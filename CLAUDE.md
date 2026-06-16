# Screen OCR Claude Instructions

Follow `AGENTS.md` as the primary repository contract. The rules below are the
branching defaults Claude Code must preserve.

## Branching And PR Flow

- Start feature work from the latest `origin/develop`.
- If `origin/develop` is missing, create or synchronize it from `origin/main`
  before starting feature branches.
- Create work branches from `origin/develop`, using scoped names such as
  `codex/<short-description>`.
- Open implementation PRs against `origin/develop`.
- Do not open feature PRs directly to `origin/main`.

## Release Flow

- Keep `main` release-only.
- Release by opening a PR from `develop` to `main`.
- Put the intended `VERSION` change in the `develop -> main` release PR.
- After the release PR merges, verify the GitHub Actions release workflow and
  the produced GitHub Release artifacts before claiming release completion.
