# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains custom Claude Code skills (slash commands). Each skill lives under `claude/<name>/` and is defined by a `SKILL.md` file. Some skills include helper scripts in a `scripts/` subdirectory.

## Task tracking

`task.yaml` drives work via the `go` skill. Run `/go` to execute pending tasks in order. Tasks are updated with a `summary` on completion and a new empty placeholder is appended at the end.

## Skills inventory

| Skill | Scripts | Description |
|-------|---------|-------------|
| `git-add-commit` | — | Stage and commit with Uno Conventional Commits |
| `go` | — | Execute pending tasks from `task.yaml` |
| `keil` | — | Build and flash Keil MDK projects |
| `pdf` | Python (8 scripts) | Full PDF manipulation suite |
| `pdf-reading` | — | Read and extract content from PDFs |
| `pyenv` | — | Python virtual environment management |
| `stm32cubeide-build` | PowerShell | Build STM32CubeIDE projects |
| `stm32cubeide-flash` | PowerShell | Flash firmware via OpenOCD |
| `stm32cubeide-uart-verify` | PowerShell | Verify UART output against patterns |
| `stm32mp135_build_flash` | PS + Python | Build, flash, verify STM32MP135 bare-metal firmware |
| `utf8-convert` | PowerShell | Convert files to UTF-8 encoding |
| `vscode-cpp-tag` | Python | Generate VS Code C++ IntelliSense configs |

## Syncing skills

To add or update a skill, copy it to `claude/` from `~/.claude/skills/`. Skills edited in this repo should be copied back to `~/.claude/skills/` to take effect in Claude Code.

## Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

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

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
