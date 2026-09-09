---
name: stm32mp135_build_flash
description: >
  Build and flash STM32MP135 (Cortex-A7) bare-metal projects.
  Handles STM32CubeIDE makefile builds on Windows and Linux,
  STM32 V2.0 header generation (.stm32), and UART/USB flashing via
  STM32_Programmer_CLI (Windows only).
  Use when asked to build, flash, or clone build/flash scripts into
  an STM32MP135 project directory.
---

## 1. Default behavior

When invoked **without arguments**, build and flash the project in the current working directory using `do.ps1`:

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/do.ps1" -ProjectRoot "<cwd>" -Clean -MonitorTimeout 30
```

The user may override this with these keywords:
- `build` or `编译` → build only, no flash
- `flash` or `烧写` → build + flash (same as default)
- `clone` → copy scripts into the current project's `scripts/` directory then stop
- `-Clean`, `-Config Release`, etc. → passed through to the script

## 2. Script layout

```
{skill_dir}/
├── SKILL.md
└── scripts/
    ├── build.ps1                  # Find tools → make → .stm32
    ├── flash.py                   # Flash via STM32_Programmer_CLI (settings from config.yaml)
    ├── reset.py                   # Reset target: debugprobe GPIO or serial RTS (from config.yaml)
    ├── do.ps1                     # One-shot pipeline: build → reset → flash → monitor
    ├── config.yaml                # Device settings: flash interface, monitor serial, reset method
    ├── gpio_control.py            # Remote GPIO control via debugprobe (reset)
    ├── monitor.py                 # UART monitor with log capture (settings from config.yaml)
    └── imageheader/
        └── Python3/
            └── Stm32ImageAddHeader.py   # ST-provided, do not modify
```

All scripts accept `-ProjectRoot <path>` (PowerShell) or run from the project directory (Python) to override the project location. When omitted, they fall back to `$PSScriptRoot/..` (the directory above where the script lives).

## 3. Configuration file (config.yaml)

`flash.py`, `monitor.py` and `reset.py` read all device settings from `config.yaml` — they do not take ports/baud/DTR as command-line parameters. Config lookup order:

1. `--config <path>` (explicit)
2. `./config.yaml` (project root — where a cloned project's settings live)
3. `<script-dir>/config.yaml` (skill default)

The shipped `config.yaml` contains a comment above every key explaining how to configure it. Schema (same content, comments stripped):

```yaml
# ---- 烧写 (flash.py) ----
flash:
  interface: serial      # "serial" = 串口烧写 | "usb" = USB 烧写
  serial:                # 仅 interface: serial 时生效
    port: COM18          # 烧写串口号
    baud: 921600         # 烧写波特率 (ROM 引导默认 921600)
    dtr: true            # 给 CLI 传 dtr=high (GK 板 true, SIP 板 false)
    rts: true            # 给 CLI 传 rts=high (与 dtr 同规则)
  usb:                   # 仅 interface: usb 时生效
    port: USB1           # STM32_Programmer_CLI 的 USB 端口名
  partition_id: "0x01"   # 烧写目标分区 ID
  start_after_flash: true  # 烧完是否自动启动 (CLI 发 -g)

# ---- 监控 (monitor.py) ----
monitor:
  port: COM18            # 监控串口号
  baud: 115200           # 监控波特率 (须与固件打印波特率一致)
  dtr: true              # 打开串口是否断言 DTR (GK 板 true, SIP 板 false)
  rts: true              # 是否断言 RTS
  timeout: 30            # 监控时长(秒), 0 = 无限
  log_dir: logs          # 日志目录 (相对当前目录)

# ---- 复位 (reset.py) ----
reset:
  method: gpio           # "gpio" = 外部脚本复位 | "uart_rts" = 串口 RTS 复位
  gpio:                  # 仅 method: gpio 时生效
    pin: 6               # debugprobe 接 nRESET 的 GPIO 编号
    assert_ms: 200       # 低电平脉宽 (ms)
  uart_rts:              # 仅 method: uart_rts 时生效
    port: COM18          # 产生 RTS 脉冲的串口
    baud: 115200         # 任意波特率均可
    dtr: false           # 打开端口时 DTR 电平 (SIP 板必须 false)
    active: true         # true = RTS 断言为复位电平
    assert_ms: 100       # RTS 断言(复位保持)时长 (ms)
    settle_ms: 300       # 释放后等待时长 (ms)
```

Reset method selection:
- `"gpio"` — reset via the **external script** (`reset.py` calls `gpio_control.py <pin> low` → delay → `<pin> high`, the two-step sequence that reaches nRESET on the GK board).
- `"uart_rts"` — reset by toggling the **serial RTS** line (release → assert → release, the sequence proven in `flash_core.py`), for boards where RTS is wired to nRESET.

Board-specific settings (verified on hardware):
- **GK_V10_MP13X board (COM18)**: monitor must assert DTR (`dtr: true`), flash uses `dtr=high`, reset via debugprobe GPIO6 (`method: "gpio"`).
- **SIP board (COM6)**: DTR must stay **low** — set `dtr: false` in `flash.serial`, `monitor`, and `reset.uart_rts` (if used), otherwise the UART is completely silent after flashing. Reset still via GPIO6 `method: "gpio"`.

## 4. Build the image

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/build.ps1" -ProjectRoot "<cwd>" [-Clean] [-Config Debug|Release] [-DryRun]
```

The build script does everything in one pass:
- Auto-discovers ARM GCC and make (searches STM32CubeCLT, STM32CubeIDE, PATH)
- Auto-discovers the build directory: checks `Application/Debug/makefile`, `Application/Release/makefile`, `Debug/makefile`, `Release/makefile`
- Reconstructs `objects.list` from `subdir.mk` files
- Runs make
- Generates `.stm32` with STM32 V2.0 header (elf → objcopy → Stm32ImageAddHeader.py)

Parameters:
- `-ProjectRoot <path>` — project root directory (required when running from skill dir; omit when running cloned copy inside the project)
- `-Clean` — clean before building
- `-Config` — Debug (default) or Release
- `-DryRun` — print what would happen and exit

## 5. Reset target

```
python <skill_dir>/scripts/reset.py [--config <path>] [--dry-run]
```

`reset.py` reads the reset method from `config.yaml` and performs the reset:

- **`method: "gpio"`** (default) — external script: `gpio_control.py <pin> low` → delay → `<pin> high` via Raspberry Pi Debug Probe. Requires Debug Probe with custom GPIO-control firmware, `pyusb` (and `libusb-package` on Windows).
  **Must be two steps: `low` → delay → `high`.** A single `reset` command (open-drain pulse) does not reach the target nRESET on some boards and leaves the UART silent.
- **`method: "uart_rts"`** — serial RTS toggle: open the port (DTR left at the configured level, `false` on the SIP board), release RTS → assert RTS (`assert_ms`) → release RTS → settle (`settle_ms`). Same sequence proven in `flash_core.py`. Requires Python + pyserial; no debug probe needed.

## 6. Flash the target (Windows only)

```
python <skill_dir>/scripts/flash.py --image <path-to-stm32> [--config <path>] [--no-start] [--dry-run]
```

The flash script:
1. Reads flash settings (interface, port, baud, DTR, RTS) from `config.yaml`
2. Copies the image to `<cwd>/test.stm32` (absolute path, so the CLI finds it)
3. Invokes `STM32_Programmer_CLI` to flash and (by default) start the target

Parameters:
- `--image <path>` — path to the .stm32 file, relative paths resolve from cwd (required)
- `--config <path>` — config file override (default: `./config.yaml`, then skill default)
- `--no-start` — flash only, do not start target
- `--dry-run` — print the command and exit

## 7. Monitor UART output

```
python <skill_dir>/scripts/monitor.py [--config <path>] [-t <timeout>] [-o <logdir>]
```

Reads port, baud, DTR and RTS from `config.yaml`, captures target UART output, prints to console and saves to `<logdir>/uart_<timestamp>.log`.

Parameters:
- `--config <path>` — config file override (default: `./config.yaml`, then skill default)
- `-t`, `--timeout` — seconds to monitor, 0 = forever (default: from config)
- `-o`, `--logdir` — log directory (default: from config)

## 8. Full pipeline: `do.ps1`

`do.ps1` runs the complete build → reset → flash → monitor cycle in one command:

```
pwsh -ExecutionPolicy Bypass -File "<skill_dir>/scripts/do.ps1" -ProjectRoot "<cwd>" [-Clean] [-Config Debug|Release] [-MonitorTimeout <sec>] [-NoMonitor] [-ConfigPath <path>]
```

Parameters:
- `-ProjectRoot <path>` — project root directory (required when running from skill dir)
- `-Clean` — clean rebuild
- `-Config` — Debug (default) or Release
- `-MonitorTimeout` — seconds to monitor (default: 30)
- `-NoMonitor` — skip UART monitor after flash
- `-ConfigPath` — config file override (default: `./config.yaml`, then skill default)

All device settings (flash port/baud/DTR, monitor port/baud/DTR, reset method/pin) come from `config.yaml` — do not pass `-Port`, `-Baud`, `-ResetPin`, or `-ResetDurationMs`.

The script auto-discovers the `.stm32` artifact name from the makefile, so it works with any STM32CubeIDE project.

If any step fails, the script stops immediately.

## 9. Platform rules

- `build.ps1` runs on both Windows and Linux.
- `flash.py` runs on **Windows only** (requires `STM32_Programmer_CLI.exe`). If the platform is Linux, report that flashing is not supported and stop.
- `gpio_control.py`, `reset.py` and `monitor.py` are cross-platform. `reset.py`/`monitor.py` require Python + pyserial; the `gpio` reset method additionally requires pyusb + debug probe.

## 10. Verify results

- Check command exit codes
- Confirm the `.stm32` artifact exists alongside the `.elf` when the task requires image generation

## 11. Clone mode

Clone mode copies the scripts into `<project-root>/scripts/` so engineers can run them without the skill.

### What to copy

```
<project-root>/
└── scripts/
    ├── build.ps1
    ├── flash.py
    ├── reset.py                ← Reset: debugprobe GPIO or serial RTS
    ├── do.ps1                  ← One-shot pipeline (build→reset→flash→monitor)
    ├── config.yaml             ← Device settings — EDIT THIS per board
    ├── gpio_control.py
    ├── monitor.py
    └── imageheader/
        └── Python3/
            └── Stm32ImageAddHeader.py
```

### Verification

Run `pwsh scripts/build.ps1 -DryRun` from the project root. If it fails, report the error and stop.

### Usage (cloned)

```powershell
# From the project root in PowerShell, no -ProjectRoot needed.
# First edit scripts/config.yaml (or copy it to the project root) to match the board.

# One-shot pipeline (most common)
./scripts/do.ps1 -Clean -MonitorTimeout 30

# Build only
./scripts/build.ps1 -Clean

# Flash via UART (settings from config.yaml)
python scripts/flash.py --image Application/Debug/<project>.stm32

# Flash via USB (set "interface": "usb" in config.yaml)

# Monitor UART output (settings from config.yaml)
python scripts/monitor.py

# Build + flash only, no monitor
./scripts/do.ps1 -Clean -NoMonitor
```

## 12. Error handling

- If `STM32_Programmer_CLI.exe` is not on PATH: report it, stop, do not guess an install path.
- If no makefile is found under `Debug/` or `Release/`: report that the project must be built from STM32CubeIDE first to generate the makefile.
- If `arm-none-eabi-gcc` is not found: report install STM32CubeCLT or STM32CubeIDE.
- If `config.yaml` is missing or invalid: report the exact path and YAML error, stop.
- Never silently skip a step. Each script exits non-zero on failure.
