---
name: stm32cubeide-build
description: Build STM32CubeIDE-generated embedded projects from a local workspace by driving the generated GNU Make files with a Windows-safe shell setup and automatic ARM toolchain discovery. Use when Codex needs to compile, rebuild, or verify an STM32CubeIDE project that contains files such as .project, .ioc, and generated Debug/ or Release/ makefiles.
---

Build an STM32CubeIDE-generated project in the current working directory. Follow these steps:

## 1. Parse arguments

The user may pass `rebuild`/`clean` (pass `-Clean`), `release` (use Release config), or `debug` (default, Debug config). Also `clone` to copy the build script to cwd.

## 2. Handle clone

If clone requested: `Copy-Item -Path "<skill_dir>/scripts/build-stm32cubeide-project.ps1" -Destination "<cwd>/build-stm32cubeide-project.ps1"` and stop.

## 3. Verify the project

Check for `.project`, `.ioc`, `Debug/makefile`, or `Release/makefile`. If none: tell user and stop.

## 4. Run the build script

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/build-stm32cubeide-project.ps1" -ProjectRoot "<cwd>" [flags]
```

Where `[flags]` is `-Clean`, `-Configuration Release`/`-Configuration Debug`.

`<skill_dir>` is the directory containing this SKILL.md.

## 5. Report results

Show: Configuration, Make, Toolchain, Artifact path/size, any errors/warnings, build success/failure.

## Notes

- Script auto-discovers ARM toolchain from `C:\ST\STM32CubeCLT_*` or `C:\ST\STM32CubeIDE_*`.
- Forces `SHELL=cmd.exe` for Windows make.
- If no makefile exists: regenerate from STM32CubeIDE first.
- If `make` is missing: install GnuWin32 `make.exe`.
- Build only — use stm32cubeide-flash for flashing.
