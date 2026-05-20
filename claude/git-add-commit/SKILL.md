---
name: git-add-commit
description: Use when the user says "git add" or asks to add/stage changes and commit them. This skill stages relevant modified code and creates a Git commit using Uno Conventional Commits, while never pushing to a remote.
---

# Git Add Commit

## Scope

Use this skill when the user inputs `git add` or asks to stage modified code and commit it.

Allowed Git operations:

- `git status`
- `git diff`
- `git add`
- `git commit`
- `git show`

Forbidden Git operations:

- Never run `git push`.
- Never run `git reset`, `git checkout --`, `git restore`, `git clean`, `git rm`, `git mv`, `git stash`, rebase, merge, or amend unless the user explicitly requests that separate operation.
- Never rewrite history unless explicitly requested.

## Workflow

1. Inspect `git status --short`.
2. Review the relevant diffs before staging.
   - For tracked modified files, use `git diff`.
   - For untracked files, `git diff` will not show content. Inspect the file names and, when reasonable, inspect file contents before staging.
3. Before staging, check for obvious secrets, credentials, private keys, tokens, `.env` files, generated artifacts, large binaries, logs, local config files, IDE caches, and build outputs. Do not stage them unless the user explicitly confirms.
4. Stage only files that belong to the user's requested change.
5. Do not stage unrelated dirty worktree changes or untracked files unless they are clearly part of the requested change.
6. Run `git diff --cached --stat` and, when useful, `git diff --cached` to confirm exactly what will be committed.
7. If there are no staged or relevant changes, do not create an empty commit unless the user explicitly asks for one.
8. Commit with a message that follows Uno Conventional Commits.

If the requested change is ambiguous, make a pragmatic selection from the current task context. Ask only if staging the wrong file would be risky.

## Language

All output and status messages must be in Chinese or English. Never output Korean.

## Commit Message Format

Follow Uno Conventional Commits:

```text
<type>([optional scope]): <description>

[optional body]

[optional footer(s)]
```

Use these common types:

- `fix`: bug fix.
- `feat`: new functionality.
- `docs`: documentation change.
- `test`: unit tests or test coverage.
- `perf`: performance improvement without functional behavior changes.
- `chore`: catch-all for maintenance and supporting commits.

Rules:

- Prefer concise English commit messages.
- Use lowercase type names.
- Use an optional scope when it adds useful context, for example `fix(ddr): ...`.
- Use `!` after type or scope only for breaking changes, for example `fix(api)!: ...`.
- For breaking changes, include a commit body line beginning with `BREAKING CHANGE:`.
- Do not use vague messages like `update`, `changes`, or `fix bug`.
- Every commit message must end with a `Co-Authored-By` trailer. Use the actual agent name and model from the current session (check the system prompt for the model name — e.g. "Claude Opus 4.7", "Claude Sonnet 4.6", "DeepSeek v4 Pro"). Do not hardcode a specific model. Format: `Co-Authored-By: <Agent Name> <Model> <noreply@anthropic.com>`

Reference: https://platform.uno/docs/articles/uno-development/git-conventional-commits.html
