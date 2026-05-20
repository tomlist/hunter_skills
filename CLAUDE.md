# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains custom Claude Code skills (slash commands). Each skill is a directory under `claude/` containing the skill's source and configuration.

## Adding a skill

Skills follow the Claude Code custom slash command format. A skill directory typically includes an `instructions.md` defining how Claude should respond when the skill is invoked.

## Repository conventions

- Skill directories live under `claude/` (e.g., `claude/my-skill/`)
- The skill name matches the directory name
- The user for this repo is `hunter`

## No build/test/lint steps

There are currently no build, test, or lint steps in this repository.
