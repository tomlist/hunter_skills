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
| `stm32mp135-task-build-flash-verify` | PS + Python | Build/flash/verify STM32MP135 DDR |
| `utf8-convert` | PowerShell | Convert files to UTF-8 encoding |
| `vscode-cpp-tag` | Python | Generate VS Code C++ IntelliSense configs |

## Syncing skills

To add or update a skill, copy it to `claude/` from `~/.claude/skills/`. Skills edited in this repo should be copied back to `~/.claude/skills/` to take effect in Claude Code.
