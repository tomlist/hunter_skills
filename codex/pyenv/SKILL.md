---
name: pyenv
description: Initialize and manage a Python virtual environment for the current working directory. Use this skill whenever the user needs to run Python code, install Python packages, or use pip/uv — even if they don't explicitly mention virtual environments. Prefers uv (fast Python package manager) when available, falls back to standard venv+pip. Trigger on: python, pip, uv, .py files, running scripts, installing packages, Jupyter, or any mention of Python tooling.
---

# pyenv — Python Virtual Environment Manager

Ensure every working directory has its own isolated Python virtual environment. Never install packages or run Python code against the system Python.

## Tool preference

**uv > standard venv+pip**. uv is a fast Rust-based Python package manager. Always check for it first and use it when available. Fall back to standard tooling only when uv is absent.

To check: `uv --version`.

## Quick reference

### With uv (preferred)

```bash
uv venv                          # create .venv (near-instant)
uv venv .venv                    # explicit path
uv pip install <pkg>             # install into .venv, auto-detected
uv pip install -r requirements.txt
uv pip freeze > requirements.txt
.venv/bin/python script.py       # run scripts (Linux/macOS)
.venv/Scripts/python script.py   # run scripts (Windows)
```

### Without uv (fallback)

```bash
python3 -m venv .venv            # Linux/macOS
python -m venv .venv             # Windows
.venv/bin/pip install <pkg>      # Linux/macOS
.venv/Scripts/pip install <pkg>  # Windows
```

## OS paths

| | Linux / macOS | Windows |
|---|---|---|
| venv python | `.venv/bin/python` | `.venv/Scripts/python` |
| venv pip | `.venv/bin/pip` | `.venv/Scripts/pip` |
| activate | `source .venv/bin/activate` | `.venv/Scripts/activate` |
| create (no uv) | `python3 -m venv .venv` | `python -m venv .venv` |

On Windows, forward slashes work fine: `.venv/Scripts/python`.

## Setup (first time in a directory)

When Python is needed and `.venv/` does not exist yet:

1. Check for uv: `uv --version`

2. Create the virtual environment:
   - **uv available**: `uv venv` (or `uv venv .venv`)
   - **No uv**: use the OS-appropriate create command from the table above

3. Ensure `.venv/` is in `.gitignore`:
   - Linux/macOS: `grep -q '^\.venv' .gitignore 2>/dev/null || echo '.venv/' >> .gitignore`
   - Windows PowerShell: `if (!(Select-String -Path .gitignore -Pattern '^\.venv' -Quiet)) { Add-Content .gitignore '.venv/' }`

## Installing packages

1. Make sure `.venv/` exists (create if needed, per Setup above)
2. Install:
   - **uv available**: `uv pip install <package>`
   - **No uv**: `.venv/bin/pip install <package>` (Linux/macOS) or `.venv/Scripts/pip install <package>` (Windows)

## Running Python

Always use the venv interpreter — never the system Python:

```bash
.venv/bin/python script.py          # Linux/macOS
.venv/Scripts/python script.py      # Windows
```

## Saving dependencies

- **With uv**: `uv pip freeze > requirements.txt`
- **Without uv**:
  - Linux/macOS: `.venv/bin/pip freeze > requirements.txt`
  - Windows: `.venv/Scripts/pip freeze > requirements.txt`

## Prefer inline paths

Use the explicit venv path (`.venv/bin/python`, `.venv/bin/pip`) in shell commands — unambiguous and survives shell restarts. Only suggest activation if the user needs an interactive shell.

## Pre-existing venvs

If `.venv/` already exists, just use it. Do not recreate unless the user explicitly asks to start fresh.

## .gitignore

Always ensure `.venv/` is in `.gitignore`. If `.gitignore` doesn't exist, create it with `.venv/` as the first line.

## Installing uv itself (if missing and user wants it)

- Linux/macOS: `curl -LsSf https://astral.sh/uv/install.sh | sh`
- Windows: `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`
- Or via pipx: `pipx install uv`

Only install uv if the user asks — don't do it automatically.

