---
name: stm32cubeide-build
description: Build STM32CubeIDE-generated embedded projects without opening the IDE. Handles ARM toolchain discovery, Windows make quirks, and objects.list generation. Usage: /stm32cubeide-build [rebuild] [release]
---

Build an STM32CubeIDE-generated project in the current working directory. Follow these steps:

## 1. Parse arguments

The user may pass arguments after `/stm32cubeide-build`. Recognised keywords (case-insensitive):
- `rebuild` or `-rebuild` or `clean` → pass `-Clean` to the script (remove generated outputs before building)
- `release` or `-release` → pass `-Configuration Release` to the script
- `debug` or `-debug` → pass `-Configuration Debug` to the script (default)

## 2. Verify the project

Check that the current working directory looks like an STM32CubeIDE project by looking for at least one of:
- A `.project` file
- A `.ioc` file
- A `Debug/makefile` or `Release/makefile`

If none of these exist, tell the user this does not appear to be an STM32CubeIDE project and stop.

## 3. Run the build script

The bundled script is at:
```
C:\Users\tomli\.claude\skills\stm32cubeide-build\scripts\build-stm32cubeide-project.ps1
```

Run it with the Bash tool using `pwsh`:

```
pwsh -ExecutionPolicy Bypass -File "C:\Users\tomli\.claude\skills\stm32cubeide-build\scripts\build-stm32cubeide-project.ps1" -ProjectRoot "<cwd>" [flags]
```

Where `[flags]` is any combination of:
- `-Clean` if the user asked for a clean/rebuild
- `-Configuration Release` or `-Configuration Debug` if the user specified one

Use the current working directory as `-ProjectRoot`.

## 4. Report results

Show the key summary lines from the output:
- Configuration, Make, Toolchain, Artifact path and size
- Any error or warning lines from the compiler
- Whether the build succeeded or failed

If the build failed, highlight the error lines so the user can fix them quickly.

## Notes

- The script auto-discovers the ARM toolchain from `C:\ST\STM32CubeCLT_*` or `C:\ST\STM32CubeIDE_*`.
- It forces `SHELL=cmd.exe` so Windows make does not fall into MSYS sh.exe.
- If no `Debug/makefile` or `Release/makefile` exists, the user must regenerate project files from STM32CubeIDE first.
- If `make` is missing, the user should install GnuWin32 `make.exe`.
- This skill only builds — it does not flash hardware. Use `/stm32cubeide-flash` for flashing.
