---
name: stm32cubeide-flash
description: Flash prebuilt STM32CubeIDE firmware to an STM32 target using OpenOCD over CMSIS-DAP/SWD. Requires the project to be built first. Usage: /stm32cubeide-flash [release] [firmware=<path>]
---

Flash an already-built STM32CubeIDE firmware binary to the target board using OpenOCD. Follow these steps:

## 1. Parse arguments

The user may pass arguments after `/stm32cubeide-flash`. Recognised keywords (case-insensitive):
- `release` or `-release` → pass `-Configuration Release` to the script
- `debug` or `-debug` → pass `-Configuration Debug` to the script (default)
- `firmware=<path>` or `-firmware <path>` → pass `-FirmwarePath <path>` to the script

## 2. Verify the project

Check that the current working directory looks like an STM32CubeIDE project by looking for at least one of:
- A `.project` file
- A `.ioc` file
- A `Debug/makefile` or `Release/makefile`

If none of these exist, tell the user this does not appear to be an STM32CubeIDE project and stop.

## 3. Run the flash script

The bundled script is at:
```
C:\Users\tomli\.claude\skills\stm32cubeide-flash\scripts\flash-stm32cubeide-project.ps1
```

Run it with the Bash tool using `pwsh`:

```
pwsh -ExecutionPolicy Bypass -File "C:\Users\tomli\.claude\skills\stm32cubeide-flash\scripts\flash-stm32cubeide-project.ps1" -ProjectRoot "<cwd>" [flags]
```

Where `[flags]` is any combination of:
- `-Configuration Release` or `-Configuration Debug` if the user specified one
- `-FirmwarePath "<path>"` if the user passed an explicit firmware path

Use the current working directory as `-ProjectRoot`.

## 4. Report results

Show the key summary lines from the output:
- Configuration, OpenOCD path, Firmware path and size
- Whether the flash succeeded or failed

If the flash failed, highlight the error so the user can diagnose the connection or config issue.

## Notes

- The script auto-discovers OpenOCD from `D:\tools\xpack-openocd-0.12.0-7\bin\openocd.exe` or PATH.
- Default interface: `interface/cmsis-dap.cfg` (CMSIS-DAP over SWD).
- Default target: `target/stm32f1x.cfg` (STM32F1 family). For other MCU families, the user must pass `-TargetConfig` via the script directly.
- Default flash address: `0x08000000`.
- The firmware `.bin` must exist before flashing — run `/stm32cubeide-build` first if it is missing.
- If no `Debug/makefile` or `Release/makefile` exists, the user must regenerate project files from STM32CubeIDE.
