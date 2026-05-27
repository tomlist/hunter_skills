---
name: stm32mp135-task-build-flash-verify
description: Build, flash, and verify STM32MP135 firmware projects. Handles STM32CubeIDE build (auto-discovers Application/ subdirectory), STM32 header generation (.stm32), UART flashing via STM32_Programmer_CLI, and serial output monitoring. Use when working with STM32MP135 bare-metal/Cortex-A7 projects.
---

Work from the repository root. Follow these steps:

## 1. Read task state

Read the repo-root `task.yaml` and select only items where `completed` is `false` (or `status` is `pending`). Execute them in list order. Mark the task done only after every required action succeeds.

## 2. Interpret task text

- `编译` or `build` → run the build flow
- `烧写`, `flash`, or `下载` → build first, then flash
- Code change required → inspect the repository, implement the change, then build; flash only if the task requires it
- Serial verification mentioned → keep the monitor open until the benchmark finishes or timeout expires
- Do not assume a COM port unless the task text or the user provides one

## 3. Build the image

Run the bundled build script with the Bash tool:

```
pwsh -ExecutionPolicy Bypass -File "C:\Users\tomli\.claude\skills\stm32mp135-task-build-flash-verify\scripts\build-stm32-image.ps1" -RepoRoot "<cwd>" -Clean -GenStm32
```

The build script:
- Auto-discovers the build directory: checks `<project>/Debug/makefile` and `<project>/Application/Debug/makefile` (and Release variants)
- Auto-discovers the ARM toolchain from `C:\ST\STM32CubeCLT_*` or `C:\ST\STM32CubeIDE_*`
- Auto-discovers `make.exe` from GnuWin32 or PATH
- Reconstructs `objects.list` from subdir.mk files before building
- If `-GenStm32`, runs `Scripts/imageheader/postbuild.ps1` to add the STM32 V2.0 header

Key parameters:
- `-RepoRoot <path>` — the repository/project root (default: current directory)
- `-ProjectDir <name>` — subdirectory containing the project (default: "." for repo root)
- `-Clean` — remove generated outputs before building
- `-GenStm32` — generate .stm32 image with STM32 header after linking
- `-Configuration Release` — build Release instead of Debug
- `-DryRun` — print resolved paths and exit without building

Use `-DryRun` first when working with a new project layout.

## 4. Flash and monitor

Run the bundled flash script (requires `pyserial` — install with `pip install pyserial` if missing):

```
python "C:\Users\tomli\.claude\skills\stm32mp135-task-build-flash-verify\scripts\flash-stm32-uart.py" COM4 --repo-root "<cwd>" --project-dir . --image-name "Application\Debug\sram_test_Application.stm32"
```

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
- `--image-src path\to\custom.stm32` — use an explicit image path
- `--image-name <path>` — relative path from project dir to the .stm32 file
- `--project-dir .` — when the project is at the repo root
- `--done-marker <text>` — custom completion marker

## 5. Verify results

- Check command exit codes
- Confirm the `.stm32` artifact exists when the task requires image generation
- Check the newest file in `logs\` when serial verification is required
- The done marker in the log means the benchmark completed successfully

## 6. Update task.yaml

After a task succeeds, mark it completed in `task.yaml`. Do not reorder or modify other task descriptions.

## Notes

- `STM32_Programmer_CLI.exe` must be on PATH (installed via STM32CubeProgrammer)
- Default flash baud rate: `921600`; default monitor baud rate: `115200`
- If `STM32_Programmer_CLI` is missing, report it and stop — do not guess an install path
- If no `Debug/makefile` or `Release/makefile` exists, the project must be generated from STM32CubeIDE first (use `stm32cubeidec.exe` headless import+build)
- The flash script can flash any `.stm32` image; it is not tied to a specific project structure
