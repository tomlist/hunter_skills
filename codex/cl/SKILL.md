---
name: cl
description: Copy the CODEX.md from this skill's directory into the current working directory. Use when the user wants to set up or merge a CODEX.md project guidance file.
---

Copy `CODEX.md` from this skill's own directory to the current working directory.

1. Locate this skill's base directory (the directory containing this SKILL.md).
2. If `./CODEX.md` does NOT exist in the current working directory:
   - Copy `CODEX.md` from the skill's base directory to `./CODEX.md`.
3. If `./CODEX.md` already exists:
   - Read the skill's `CODEX.md` and append its content to the end of the existing `./CODEX.md`.
   - Add a blank line separator before appending if the existing file doesn't already end with one.
4. Report what was done (created new file, or appended to existing file).

