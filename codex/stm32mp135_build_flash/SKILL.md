---
name: stm32mp135_build_flash
description: Build, flash, and verify the STM32MP135 DDR utility repository, including executing repo-root task.yaml items with completed=false, implementing code changes before build, generating the .stm32 image, monitoring UART output, saving logs, and marking only successful tasks completed. Use when Codex works in this repository on requests mentioning task.yaml, 编译/build, 烧写/flash/下载, COM ports, UART verification, benchmark logs, or STM32MP135 DDR utility automation.
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

## 3. Script layout

```
<skill_dir>/
├── SKILL.md
└── scripts/
    ├── find-toolchain.ps1        # Locate ARM GCC + make (Windows + Linux)
    ├── build-elf.ps1             # Run make, fix objects.list → .elf
    ├── gen-stm32-header.ps1      # Wrap postbuild → .stm32
    ├── flash-target.ps1          # Reset + STM32_Programmer_CLI (Windows only)
    ├── monitor-uart.py           # Serial monitor + log saver (Windows only)
    └── imageheader/
        ├── postbuild.ps1         # ELF→binary→STM32 header (called by gen-stm32-header)
        └── Python3/
            └── Stm32ImageAddHeader.py   # ST-provided, do not modify
```

`<skill_dir>` is the directory containing this SKILL.md.

## 4. Build the image

### Step 4a — Locate toolchain

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/find-toolchain.ps1"
```

Outputs `ARM_GCC_DIR`, `ARM_GCC_EXE`, `MAKE_EXE`. Use `-DryRun` to check without error.

### Step 4b — Build .elf

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/build-elf.ps1" -RepoRoot "<cwd>" -Clean
```

- Auto-discovers build directory: `Application/Debug/makefile`, `Application/Release/makefile`, `Debug/makefile`, `Release/makefile`
- Respects `-Config` (Debug/Release, default: Debug)
- Reconstructs `objects.list` from `subdir.mk` files before building
- Use `-DryRun` first with a new project layout

### Step 4c — Generate .stm32 header

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/gen-stm32-header.ps1" -ElfPath "<path-to-elf>"
```

This wraps `imageheader/postbuild.ps1`, which extracts entry point, converts ELF→binary, adds STM32 V2.0 header, and produces `.stm32`.

## 5. Flash and monitor

### Step 5a — Flash the target (Windows only)

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/flash-target.ps1" -ImagePath "<path-to-stm32>" [-Port <USB1|COMx>]
```

Parameters: `-ImagePath` (required), `-Port` (default: USB1), `-RepoRoot` (default: cwd), `-Baud` (default: 921600), `-NoStart`, `-DryRun`.

### Step 5b — Monitor serial output (Windows only)

```
python "<skill_dir>/scripts/monitor-uart.py" <COM port> --repo-root "<cwd>" [--done-marker "<text>"] [--timeout <sec>]
```

Parameters: `port` (required), `--repo-root`, `--done-marker` (default: `<<<DONE>>>`), `--timeout` (default: 600), `--baud` (default: 115200).

Opens serial port, captures to timestamped log under `logs/`, writes to stdout and log in real time, waits for done marker, exits on timeout.

## 6. Platform rules

- Build scripts run on both Windows and Linux.
- Flash and monitor run on Windows only.
- Detect platform with `$IsWindows` (PowerShell) or `sys.platform` (Python).

## 7. Verify results

- Check command exit codes
- Confirm `.stm32` artifact exists
- Check newest file in `logs/` for serial verification
- Done marker in log = benchmark completed

## 8. Update task.yaml

After a task succeeds, mark it completed. Do not reorder or modify other tasks.

## 9. Clone mode

Copy skill scripts into the project directory:

```
<project-root>/scripts/
    ├── find-toolchain.ps1
    ├── build-elf.ps1
    ├── gen-stm32-header.ps1
    ├── flash-target.ps1
    ├── monitor-uart.py
    └── imageheader/
        ├── postbuild.ps1
        └── Python3/
            └── Stm32ImageAddHeader.py
```

Verify with `pwsh scripts/find-toolchain.ps1 -DryRun`.

## 10. Error handling

- If `STM32_Programmer_CLI.exe` not on PATH: report and stop.
- If no makefile: project must be built from STM32CubeIDE first.
- If `pyserial` missing: `pip install pyserial`.
- If `arm-none-eabi-gcc` not found: install STM32CubeCLT or STM32CubeIDE.
- Never silently skip a step.

## 11. Cross-cutting design rules

1. Script dependencies: only `build-elf.ps1` → `find-toolchain.ps1 -AsObject` and `gen-stm32-header.ps1` → `imageheader/postbuild.ps1`.
2. Every script has `-DryRun`/`--dry-run`.
3. Every script exits non-zero on failure.
4. No script writes to disk except its designated output.
5. Platform guards: flash/monitor exit 1 if not Windows.
