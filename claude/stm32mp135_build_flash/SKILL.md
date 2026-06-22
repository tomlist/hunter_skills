---
name: stm32mp135_build_flash
description: >
  Build, flash, and verify STM32MP135 (Cortex-A7) bare-metal projects.
  Handles STM32CubeIDE makefile builds on Windows and Linux,
  STM32 V2.0 header generation (.stm32), UART/USB flashing via
  STM32_Programmer_CLI (Windows only), and serial output monitoring.
  Use when asked to build, flash, or clone build/flash scripts into
  an STM32MP135 project directory.
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
{skill_dir}/
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

Each script has exactly one responsibility and a defined exit point.
No script knows what comes before or after it in a workflow.

## 4. Build the image

### Step 4a — Locate toolchain

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>\scripts\find-toolchain.ps1"
```

This outputs `ARM_GCC_DIR`, `ARM_GCC_EXE`, and `MAKE_EXE`. Use `-DryRun` to check without error.

### Step 4b — Build .elf

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>\scripts\build-elf.ps1" -RepoRoot "<cwd>" -Clean
```

The build script:
- Auto-discovers the build directory: checks `Application/Debug/makefile`, `Application/Release/makefile`, `Debug/makefile`, `Release/makefile`
- Respects `-Config` (Debug/Release, default: Debug)
- Auto-discovers toolchain via `find-toolchain.ps1 -AsObject` if not provided
- Reconstructs `objects.list` from `subdir.mk` files before building
- Streams make output directly to console
- Use `-DryRun` first with a new project layout

### Step 4c — Generate .stm32 header

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>\scripts\gen-stm32-header.ps1" -ElfPath "<path-to-elf>"
```

This wraps `imageheader/postbuild.ps1`, which:
1. Extracts the entry point from the ELF via `arm-none-eabi-readelf`
2. Converts ELF → binary via `arm-none-eabi-objcopy`
3. Invokes `Stm32ImageAddHeader.py` to add the STM32 V2.0 header
4. Produces a `.stm32` file alongside the `.elf`

Can be re-run independently without rebuilding.

## 5. Flash and monitor

### Step 5a — Flash the target (Windows only)

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>\scripts\flash-target.ps1" -ImagePath "<path-to-stm32>" [-Port <USB1|COMx>]
```

The flash script:
1. Copies the image to `<repo-root>\test.stm32`
2. For UART mode: resets the MPU via RTS (200ms assertion)
3. Invokes `STM32_Programmer_CLI` to flash and start the target
4. Exits immediately after the CLI completes — does not open a serial port

Parameters:
- `-ImagePath <path>` — full path to the .stm32 file (required)
- `-Port <USB1|COMx>` — flash port (default: USB1)
- `-RepoRoot <path>` — root for test.stm32 staging (default: cwd)
- `-Baud <rate>` — UART baud rate (default: 921600)
- `-NoStart` — flash only, do not start target
- `-DryRun` — print CLI command and exit

### Step 5b — Monitor serial output (Windows only)

```
python "<skill_dir>\scripts\monitor-uart.py" <COM port> --repo-root "<cwd>" [--done-marker "<text>"] [--timeout <sec>]
```

The monitor script:
1. Opens the serial port and captures output to a timestamped log under `logs\`
2. Writes each received line to both stdout and the log file in real time
3. Waits for the done marker string; exits cleanly when found
4. Exits on timeout (exit code 1)
5. Completely independent of flashing — can be started before or after flash

Parameters:
- `port` — COM port (positional, required), e.g. COM4
- `--repo-root <path>` — root for `logs\` directory (default: cwd)
- `--done-marker <str>` — completion string (default: `<<<DONE>>>`)
- `--timeout <sec>` — seconds to wait (default: 600)
- `--baud <rate>` — serial baud rate (default: 115200)

## 6. Platform rules

- Build scripts (`find-toolchain`, `build-elf`, `gen-stm32-header`, `postbuild`) run on both Windows and Linux.
- Flash and monitor scripts run on **Windows only**. If the platform is Linux, report that flashing is not supported and stop.
- Detect platform with `$IsWindows` (PowerShell) or `sys.platform` (Python).

## 7. Verify results

- Check command exit codes
- Confirm the `.stm32` artifact exists when the task requires image generation
- Check the newest file in `logs\` when serial verification is required
- The done marker in the log means the benchmark completed successfully
- Exit code 0 from `monitor-uart.py` = done marker found; exit code 1 = timeout

## 8. Update task.yaml

After a task succeeds, mark it completed in `task.yaml`. Do not reorder or modify other task descriptions.

## 9. Clone mode

Clone mode copies the skill scripts into the project directory and generates
orchestration wrappers (`do.ps1` / `do.sh`) so engineers can build and flash
with a single command. Use when the user asks to "clone", "copy build/flash
scripts", or "set up standalone scripts".

### What is created

```
<project-root>/
├── do.ps1                     # Windows: build + flash + monitor
├── do.sh                      # Linux: build only (.stm32 output)
└── scripts/
    ├── find-toolchain.ps1
    ├── build-elf.ps1
    ├── gen-stm32-header.ps1
    ├── flash-target.ps1       # Windows only
    ├── monitor-uart.py        # Windows only
    └── imageheader/
        ├── postbuild.ps1
        └── Python3/
            └── Stm32ImageAddHeader.py
```

### Clone steps

1. Copy `{skill_dir}/scripts/` → `<cwd>/scripts/`
2. Copy `{skill_dir}/do.ps1` → `<cwd>/do.ps1`
3. Copy `{skill_dir}/do.sh` → `<cwd>/do.sh`
4. Run `pwsh do.ps1 -DryRun` to verify the project is discoverable.
   If it fails, report the error and stop.

### do.ps1 (Windows) — primary entry point

Auto-discovers the build directory, builds, generates the STM32 header, flashes,
and optionally monitors serial output.

```
pwsh do.ps1 [-Port USB1|COMx] [-Config Debug|Release] [-Clean] [-NoStart] [-NoMonitor] [-DryRun]
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Port` | USB1 | Flash port: USB1 or COMx |
| `-Config` | Debug | Build configuration |
| `-Clean` | (switch) | Clean rebuild before make |
| `-NoStart` | (switch) | Flash but do not start target |
| `-NoMonitor` | (switch) | Skip UART monitor after flash |
| `-MonitorOnly` | (switch) | Skip build+flash, only open UART monitor |
| `-Baud` | 921600 | UART flash baud rate |
| `-MonitorBaud` | 115200 | UART monitor baud rate |
| `-DoneMarker` | `<<<DONE>>>` | Monitor completion marker |
| `-Timeout` | 600 | Monitor timeout in seconds |
| `-DryRun` | (switch) | Print actions without executing |

### do.sh (Linux) — build only

Builds the project and generates the `.stm32` image. Flashing is not supported
on Linux (use do.ps1 on Windows).

```
bash do.sh [-Config Debug|Release] [-Clean] [-DryRun]
```

### Usage reminder to show the engineer

```powershell
# --- Windows (PowerShell) ---

# Build + flash via USB (most common)
pwsh do.ps1

# Build + flash via UART + monitor
pwsh do.ps1 -Port COM4

# Flash without monitor
pwsh do.ps1 -NoMonitor

# Clean rebuild
pwsh do.ps1 -Clean

# Only monitor (skip build+flash)
pwsh do.ps1 -Port COM4 -MonitorOnly -DoneMarker "<<<BENCHMARK_DONE>>>"

# Dry-run to check what will happen
pwsh do.ps1 -DryRun
```

```bash
# --- Linux ---
bash do.sh
bash do.sh -Clean
bash do.sh -DryRun
```

### Advanced: individual scripts

Engineers can run each script directly when they need fine-grained control:

```powershell
pwsh scripts\find-toolchain.ps1
pwsh scripts\build-elf.ps1 -Clean
pwsh scripts\gen-stm32-header.ps1 -ElfPath Application\Debug\myproject.elf
pwsh scripts\flash-target.ps1 -ImagePath Application\Debug\myproject.stm32
python scripts\monitor-uart.py COM4 --done-marker "<<<DONE>>>"
```

## 10. Error handling rules

- If `STM32_Programmer_CLI.exe` is not on PATH: report it, stop, do not guess an install path.
- If no makefile is found under `Debug/` or `Release/`: report that the project must be built from STM32CubeIDE first to generate the makefile.
- If `pyserial` is missing: tell the user to run `pip install pyserial`.
- If `arm-none-eabi-gcc` is not found: report install STM32CubeCLT or STM32CubeIDE.
- Never silently skip a step. Each script must exit non-zero on failure.

## 11. Cross-cutting design rules

1. **No script calls another script except these allowed dependencies:**
   - `build-elf.ps1` may call `find-toolchain.ps1 -AsObject`
   - `gen-stm32-header.ps1` may call `imageheader/postbuild.ps1`
   - All other scripts are fully self-contained.

2. **Every script has a `-DryRun` parameter** (or `--dry-run` for Python) that prints what it would do and exits 0 without side effects.

3. **Every script exits non-zero on failure** with a human-readable message. No silent failures.

4. **No script writes to disk except its designated output:**
   - `find-toolchain.ps1` → nothing
   - `build-elf.ps1` → objects.list (intermediate), .elf (via make)
   - `gen-stm32-header.ps1` / `postbuild.ps1` → .stm32
   - `flash-target.ps1` → test.stm32 (staged copy)
   - `monitor-uart.py` → logs\*.log

5. **Platform guards are in place:**
   - `flash-target.ps1`: exit 1 if not Windows
   - `monitor-uart.py`: exit 1 if not Windows
   - Others work on both Windows and Linux PowerShell (`pwsh`)
