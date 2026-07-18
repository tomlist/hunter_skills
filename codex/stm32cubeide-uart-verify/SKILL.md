---
name: stm32cubeide-uart-verify
description: Verify STM32CubeIDE-generated embedded projects by reading UART output from a flashed target and checking whether runtime behavior matches the expected serial log. Use when Codex needs to confirm that a recent code change really works on hardware after an explicit build step and an explicit flash step, especially for periodic UART prints such as hello messages, temperature reports, counters, or sys_tick-based output.
---

Verify that a flashed STM32 target is producing the expected UART output.

## 1. Parse arguments

User passes a regex pattern and optional flags:
- Pattern (required): regex to match against serial output
- `port=<COMx>`: COM port; auto-detect if omitted
- `baud=<rate>`: default 115200
- `increasing`: verify monotonically increasing counter across matches
- `dtr`: assert DTR when opening port
- `timeout=<seconds>`: default 10
- `min=<count>`: minimum matches required, default 2

If no pattern: ask user what output to expect.

## 2. List ports if needed

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/list-serial-ports.ps1"
```

Auto-detect prefers STLink, ST-LINK, Virtual COM, CH340, CP210, CMSIS-DAP ports.

## 3. Run verification

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/verify-stm32-uart-output.ps1" -Pattern '<pattern>' [flags]
```

## 4. Report

Show: COM port used, captured lines, match count, monotonic check result. If failed, show captured output.

## Notes

- Build and flash first (stm32cubeide-build then stm32cubeide-flash).
- Default baud: 115200. Use `dtr` if board needs DTR asserted.
- Use `increasing` for sys_tick-style counters.

## Pattern examples

- `hello world \d+`
- `uart test!!! \d+`
- `adc_dma \d+ temp -?\d+\.\dC \d+`
