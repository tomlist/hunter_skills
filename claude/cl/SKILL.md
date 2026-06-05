---
name: cl
description: Copy the CLAUDE.md from this skill's directory into the current working directory.
---

Copy `CLAUDE.md` from this skill's own directory to the current working directory.

1. Locate this skill's base directory (the directory containing this SKILL.md).
2. If `./CLAUDE.md` does NOT exist in the current working directory:
   - Copy `CLAUDE.md` from the skill's base directory to `./CLAUDE.md`.
3. If `./CLAUDE.md` already exists:
   - Read the skill's `CLAUDE.md` and append its content to the end of the existing `./CLAUDE.md`.
   - Add a blank line separator before appending if the existing file doesn't already end with one.
4. Report what was done (created new file, or appended to existing file).
