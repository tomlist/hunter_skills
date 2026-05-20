---
name: stm32cubeide-uart-verify
description: Verify STM32 firmware behavior by reading UART output from a flashed target and matching it against expected patterns. Usage: /stm32cubeide-uart-verify <pattern> [port=COM5] [baud=115200] [increasing] [dtr]
---

Verify that a flashed STM32 target is producing the expected UART output. Follow these steps:

## 1. Parse arguments

The user passes a regex pattern and optional flags after `/stm32cubeide-uart-verify`. Recognised arguments:
- First bare argument (or `pattern=<regex>`) → the regex pattern to match against serial output (required)
- `port=<COMx>` or `-port <COMx>` → pass `-PortName <COMx>` to the script; otherwise auto-detect
- `baud=<rate>` or `-baud <rate>` → pass `-BaudRate <rate>`; default is `115200`
- `increasing` or `-increasing` → pass `-RequireIncreasingLastInteger` (verify monotonically increasing counter)
- `dtr` or `-dtr` → pass `-EnableDtr` (assert DTR when opening the port)
- `timeout=<seconds>` or `-timeout <seconds>` → pass `-TimeoutSeconds <seconds>`; default is `10`
- `min=<count>` or `-min <count>` → pass `-MinMatches <count>`; default is `2`

If no pattern is given and the user hasn't described the expected output, ask what the expected UART output looks like before proceeding.

## 2. List ports if needed

If the user does not know which COM port to use, run the port lister first:

```
pwsh -ExecutionPolicy Bypass -File "C:\Users\tomli\.claude\skills\stm32cubeide-uart-verify\scripts\list-serial-ports.ps1"
```

Show the output and ask the user which port to use, or proceed with auto-detect if there is only one.

## 3. Run the verification script

```
pwsh -ExecutionPolicy Bypass -File "C:\Users\tomli\.claude\skills\stm32cubeide-uart-verify\scripts\verify-stm32-uart-output.ps1" -Pattern '<pattern>' [flags]
```

Use the Bash tool to run this. Build the flags from the parsed arguments above.

## 4. Report results

Show:
- Which COM port was used
- Lines captured from the serial port
- Whether the minimum match count was reached
- Whether the monotonic integer check passed (if enabled)

If verification failed, show the captured output so the user can diagnose the issue.

## Notes

- Build and flash must be done before calling this skill. Use `/stm32cubeide-build` then `/stm32cubeide-flash`.
- Default baud rate is `115200`.
- Auto-detect prefers ports matching `STLink`, `ST-LINK`, `Virtual COM`, `CH340`, `CP210`, or `CMSIS-DAP`.
- If multiple ports exist and none match the preference list, the script will error — pass `port=COMx` explicitly.
- Use `increasing` to validate `sys_tick`-style counters that should strictly increase across matched lines.
- Use `dtr` if the board only starts streaming after DTR is asserted (common with some USB-UART bridges).

## Pattern examples

- `hello wold \d+`
- `uart test!!! \d+`
- `adc_dma \d+ temp -?\d+\.\dC \d+`
