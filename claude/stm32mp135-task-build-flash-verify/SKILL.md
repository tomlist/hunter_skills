---
name: stm32mp135-task-build-flash-verify
description: Build, flash, and verify the STM32MP135 DDR utility project by executing task.yaml items, generating the .stm32 image, flashing over UART, and monitoring serial output for the benchmark completion marker. Use when working in an STM32MP135 DDR utility repository with task.yaml items mentioning build/编译, flash/烧写/下载, or UART verification.
---

Work from the repository root. Follow these steps:

## 1. Read task state

Read the repo-root `task.yaml` and select only items where `completed` is `false`. Execute them in list order. Mark `completed: true` only after every required action for that task succeeds. Leave failed tasks as `false` and report the exact blocker.

## 2. Interpret task text

- `编译` or `build` → run the build flow
- `烧写`, `flash`, or `下载` → build first, then flash
- Code change required → inspect the repository, implement the change, then build; flash only if the task requires it
- Serial verification mentioned → keep the monitor open until the benchmark finishes or timeout expires
- Do not assume a COM port unless the task text or the user provides one

## 3. Build the image

Run the bundled build script with the Bash tool:

```
pwsh -ExecutionPolicy Bypass -File "C:\Users\tomli\.claude\skills\stm32mp135-task-build-flash-verify\scripts\build-stm32-image.ps1" -RepoRoot "<cwd>" -ProjectDir STM32MP135C-DK_DDR_UTILITIES_A7 -Clean -GenStm32
```

Expected artifact: `<ProjectDir>\build\STM32MP135C-DK_DDR_UTILITIES_A7.stm32`

Use `-DryRun` first when validating a new repository layout. Override `-ProjectDir` or `-BuildScript` for non-default layouts.

## 4. Flash and monitor

Run the bundled flash script with the Bash tool (requires `pyserial` — install with `pip install pyserial` if missing):

```
python "C:\Users\tomli\.claude\skills\stm32mp135-task-build-flash-verify\scripts\flash-stm32-uart.py" COM4 --repo-root "<cwd>" --project-dir STM32MP135C-DK_DDR_UTILITIES_A7
```

Replace `COM4` with the requested port.

The script:
1. Copies the generated image to repo-root `test.stm32`
2. Resets the MPU over RTS on the selected UART
3. Invokes `STM32_Programmer_CLI` over UART
4. Starts the target after flash
5. Opens a UART monitor and saves output under repo-root `logs\`
6. Waits up to 600 seconds for the benchmark end marker `<<<DDR_BENCHMARK_DONE>>>`

Common overrides:
- `--no-monitor` — skip UART monitoring
- `--monitor-seconds 900` — extend the timeout
- `--image-src path\to\custom.stm32` — use an explicit image

## 5. Verify results

- Check command exit codes
- Confirm the `.stm32` artifact exists when the task requires image generation
- Check the newest file in `logs\` when serial verification is required
- `<<<DDR_BENCHMARK_DONE>>>` in the log means the benchmark completed successfully

## 6. Update task.yaml

After a task succeeds, write `completed: true` back to `task.yaml`. Do not reorder or modify other task descriptions.

## Notes

- `STM32_Programmer_CLI.exe` must be on PATH (installed via STM32CubeProgrammer)
- Default flash baud rate: `921600`; default monitor baud rate: `115200`
- If `STM32_Programmer_CLI` is missing, report it and stop — do not guess an install path
- Report missing COM ports, build failures, flash failures, and monitor timeouts with the failing command and relevant artifact/log path
