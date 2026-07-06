from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import serial


DEFAULT_DONE_MARKER = "<<<DDR_BENCHMARK_DONE>>>"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Flash an STM32 image (default: USB1; specify COM port for UART) and optionally monitor serial output.",
    )
    parser.add_argument(
        "com_port",
        nargs="?",
        default=None,
        help="Target UART port for flashing (e.g. COM4). If omitted, flash over USB1.",
    )
    parser.add_argument("--repo-root", default=".", help="Repository root used to resolve relative paths")
    parser.add_argument(
        "--project-dir",
        default=".",
        help="Project directory under the repo root (default: repo root itself)",
    )
    parser.add_argument(
        "--image-name",
        default="",
        help="Image file name relative to project-dir (default: auto-detect)",
    )
    parser.add_argument(
        "--image-src",
        default="",
        help="Optional explicit image path; overrides --project-dir/--image-name",
    )
    parser.add_argument(
        "--image-dst",
        default="test.stm32",
        help="Destination image path passed to STM32_Programmer_CLI",
    )
    parser.add_argument("--partition-id", default="0x01", help="Partition ID used for download and go")
    parser.add_argument(
        "--programmer-cli",
        default="",
        help="Optional explicit STM32_Programmer_CLI executable path",
    )
    parser.add_argument("--programmer-baudrate", type=int, default=921600)
    parser.add_argument("--reset-baudrate", type=int, default=115200)
    parser.add_argument("--monitor-baudrate", type=int, default=115200)
    parser.add_argument("--monitor-seconds", type=float, default=600.0)
    parser.add_argument("--monitor-idle-seconds", type=float, default=0.0)
    parser.add_argument("--monitor-start-delay-seconds", type=float, default=0.5)
    parser.add_argument("--flash-start-delay-seconds", type=float, default=1.0)
    parser.add_argument(
        "--log-dir",
        default="logs",
        help="Directory for captured UART logs relative to repo root unless absolute",
    )
    parser.add_argument(
        "--done-marker",
        default=DEFAULT_DONE_MARKER,
        help="Benchmark completion marker read from UART",
    )
    parser.add_argument(
        "--reset-active-level",
        choices=("high", "low"),
        default="high",
        help="Logical reset level asserted on RTS",
    )
    parser.add_argument("--reset-assert-seconds", type=float, default=0.1)
    parser.add_argument("--reset-settle-seconds", type=float, default=0.2)
    parser.add_argument("--pre-reset-release-seconds", type=float, default=0.05)
    parser.add_argument("--no-start", action="store_true", help="Do not issue the go command after flashing")
    parser.add_argument("--no-monitor", action="store_true", help="Do not open UART monitor after flashing")
    parser.add_argument(
        "--monitor-port",
        default=None,
        help="UART port for monitoring only (useful in USB flash mode, e.g. --monitor-port COM4)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print resolved actions without copying files, touching UART, or invoking the programmer",
    )
    return parser.parse_args()


def resolve_path(base: Path, raw: str) -> Path:
    path = Path(raw)
    if path.is_absolute():
        return path
    return (base / path).resolve()


def resolve_programmer_cli(explicit_path: str) -> str:
    if explicit_path:
        path = Path(explicit_path)
        if path.is_file():
            return str(path.resolve())
        raise SystemExit(f"Error: programmer CLI not found: {path}")

    for candidate in ("STM32_Programmer_CLI.exe", "STM32_Programmer_CLI"):
        resolved = shutil.which(candidate)
        if resolved:
            return resolved

    raise SystemExit(
        "Error: STM32_Programmer_CLI.exe not found. Install STM32CubeProgrammer and add it to PATH."
    )


def open_serial_port(
    com_port: str,
    baudrate: int,
    timeout: float,
    *,
    rts: bool,
    dtr: bool,
) -> serial.Serial:
    uart = serial.Serial()
    uart.port = com_port
    uart.baudrate = baudrate
    uart.timeout = timeout
    uart.rtscts = False
    uart.dsrdtr = False
    uart.rts = rts
    uart.dtr = dtr
    uart.open()
    uart.rts = rts
    uart.dtr = dtr
    return uart


def reset_mpu_via_rts(com_port: str, args: argparse.Namespace, active_level: bool) -> None:
    release_level = not active_level

    try:
        with open_serial_port(
            com_port=com_port,
            baudrate=args.reset_baudrate,
            timeout=1,
            rts=release_level,
            dtr=release_level,
        ) as uart:
            uart.rts = release_level
            time.sleep(args.pre_reset_release_seconds)
            uart.rts = active_level
            time.sleep(args.reset_assert_seconds)
            uart.rts = release_level
            time.sleep(args.reset_settle_seconds)
    except serial.SerialException as exc:
        raise SystemExit(f"Error: failed to open {com_port} for RTS reset: {exc}") from exc


def build_cli_args(args: argparse.Namespace, image_dst: Path, is_usb: bool) -> list[str]:
    if is_usb:
        cli_args = ["-c", "port=USB1"]
    else:
        cli_args = ["-c", f"port={args.com_port}", f"br={args.programmer_baudrate}"]

    cli_args.extend(["-d", str(image_dst), args.partition_id])

    if not args.no_start:
        if is_usb:
            cli_args.extend(["-g", args.partition_id])
        else:
            cli_args.extend(["-g", args.partition_id])

    return cli_args


def monitor_uart_output(
    com_port: str,
    monitor_baudrate: int,
    monitor_seconds: float,
    monitor_idle_seconds: float,
    monitor_start_delay_seconds: float,
    done_marker: str,
    log_dir: Path,
    active_level: bool,
) -> int:
    deadline = None if monitor_seconds <= 0 else (time.monotonic() + monitor_seconds)
    last_data_at = time.monotonic()
    received_any_data = False
    marker_found = False
    marker_window = ""
    release_level = not active_level
    log_path = log_dir / f"flash_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

    log_dir.mkdir(parents=True, exist_ok=True)

    print(f"Opening UART monitor: {com_port} @ {monitor_baudrate}")
    print(f"Log file: {log_path}")

    time.sleep(monitor_start_delay_seconds)

    try:
        with log_path.open("w", encoding="utf-8", newline="") as log_file:
            with open_serial_port(
                com_port=com_port,
                baudrate=monitor_baudrate,
                timeout=0.2,
                rts=release_level,
                dtr=release_level,
            ) as uart:
                while deadline is None or time.monotonic() < deadline:
                    chunk = uart.read(4096)
                    if chunk:
                        text = chunk.decode("utf-8", errors="replace")
                        print(text, end="", flush=True)
                        log_file.write(text)
                        log_file.flush()
                        received_any_data = True
                        last_data_at = time.monotonic()
                        marker_window = (marker_window + text)[-max(len(done_marker) * 2, 256):]
                        if done_marker in marker_window:
                            marker_found = True
                            print("\nDetected benchmark end marker.")
                            break
                        continue

                    if (
                        monitor_idle_seconds > 0
                        and received_any_data
                        and (time.monotonic() - last_data_at) >= monitor_idle_seconds
                    ):
                        break
    except KeyboardInterrupt:
        print("\nUART monitor interrupted by user.")
        return 130
    except serial.SerialException as exc:
        raise SystemExit(f"Error: failed to read UART output from {com_port}: {exc}") from exc

    if received_any_data:
        print()
    else:
        print("No UART output captured.")

    if deadline is not None and not marker_found:
        print(f"Monitor timeout reached after {monitor_seconds:.0f} seconds.")
        return 2

    return 0


def main() -> int:
    args = parse_args()

    is_usb = args.com_port is None

    if is_usb:
        mode_label = "USB1"
    else:
        args.com_port = args.com_port.upper()
        mode_label = args.com_port

    # Determine monitor port: explicit --monitor-port, or UART com_port, or none
    monitor_port = args.monitor_port
    if monitor_port is None and not is_usb:
        monitor_port = args.com_port
    do_monitor = (not args.no_monitor) and monitor_port is not None

    repo_root = Path(args.repo_root).resolve()
    project_dir = resolve_path(repo_root, args.project_dir)

    if args.image_src:
        image_src = resolve_path(repo_root, args.image_src)
    elif args.image_name:
        image_src = resolve_path(project_dir, args.image_name)
    else:
        raise SystemExit("Error: specify --image-src or --image-name to locate the .stm32 file.")
    image_dst = resolve_path(repo_root, args.image_dst)
    log_dir = resolve_path(repo_root, args.log_dir)
    active_level = args.reset_active_level == "high"

    print(f"Flash mode : {mode_label} {'(USB)' if is_usb else '(UART)'}")
    print(f"Repo root  : {repo_root}")
    print(f"Project dir: {project_dir}")
    print(f"Image src  : {image_src}")
    print(f"Image dst  : {image_dst}")
    print(f"Log dir    : {log_dir}")
    print(f"Monitor    : {'off' if not do_monitor else f'{monitor_port} @ {args.monitor_baudrate}'}")
    print(f"Done marker: {args.done_marker}")

    programmer_cli = resolve_programmer_cli(args.programmer_cli) if not args.dry_run else (
        args.programmer_cli or "STM32_Programmer_CLI.exe"
    )
    cli_args = [programmer_cli, *build_cli_args(args, image_dst, is_usb)]
    print("Programmer command:", subprocess.list2cmdline(cli_args))

    if args.dry_run:
        return 0

    if not image_src.is_file():
        raise SystemExit(f"Error: image file not found: {image_src}")

    image_dst.parent.mkdir(parents=True, exist_ok=True)
    if image_src.resolve() != image_dst.resolve():
        shutil.copyfile(image_src, image_dst)

    # RTS reset only for UART mode
    if not is_usb:
        print(f"Resetting MPU via RTS: {args.com_port}")
        reset_mpu_via_rts(args.com_port, args, active_level)
        time.sleep(args.flash_start_delay_seconds)
    else:
        print("USB mode: skipping RTS reset (connect via USB DFU)")

    print(f"Start flashing: {mode_label}")
    try:
        completed = subprocess.run(cli_args, cwd=repo_root, check=False)
    except OSError as exc:
        raise SystemExit(f"Error: failed to start STM32_Programmer_CLI: {exc}") from exc

    if completed.returncode != 0:
        return completed.returncode

    if not args.no_start:
        print(f"Flash completed, start request sent to partition {args.partition_id}.")

    if not do_monitor:
        return 0

    return monitor_uart_output(
        com_port=monitor_port,
        monitor_baudrate=args.monitor_baudrate,
        monitor_seconds=args.monitor_seconds,
        monitor_idle_seconds=args.monitor_idle_seconds,
        monitor_start_delay_seconds=args.monitor_start_delay_seconds,
        done_marker=args.done_marker,
        log_dir=log_dir,
        active_level=active_level,
    )


if __name__ == "__main__":
    sys.exit(main())
