---
name: stm32cubeide-flash
description: Flash prebuilt STM32CubeIDE-generated embedded firmware from a local workspace by programming an existing .bin artifact with OpenOCD. Use when Codex needs to burn a previously compiled STM32CubeIDE project that contains .project, .ioc, and generated Debug/ or Release/ makefiles, especially when the flashing flow should follow a local do.ps1 style workflow without rebuilding first.
---

Flash an already-built STM32CubeIDE firmware binary to the target board using OpenOCD.

## 1. Parse arguments

User may specify: `clone` (copy script to cwd), `release` (Release config), `debug` (Debug, default), `firmware=<path>` (explicit firmware path).

## 2. Handle clone

If clone: `Copy-Item -Path "<skill_dir>/scripts/flash-stm32cubeide-project.ps1" -Destination "<cwd>/flash-stm32cubeide-project.ps1"` and stop.

## 3. Verify the project

Check for `.project`, `.ioc`, `Debug/makefile`, or `Release/makefile`. If none: tell user and stop.

## 4. Run the flash script

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/flash-stm32cubeide-project.ps1" -ProjectRoot "<cwd>" [flags]
```

Where `[flags]` is `-Configuration Release`/`-Configuration Debug` and/or `-FirmwarePath "<path>"`.

## 5. Report results

Show: Configuration, OpenOCD path, Firmware path/size, flash success/failure.

## Notes

- Auto-discovers OpenOCD from `D:\tools\xpack-openocd-0.12.0-7\bin\openocd.exe` or PATH.
- Default: CMSIS-DAP over SWD, STM32F1 target, flash at 0x08000000.
- For other MCU families, pass `-TargetConfig` directly.
- Must build first (use stm32cubeide-build) if .bin is missing.
