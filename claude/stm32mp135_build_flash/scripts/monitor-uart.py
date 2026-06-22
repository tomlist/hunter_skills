#!/usr/bin/env python3
"""
Serial output monitor for STM32MP135 firmware verification.

Opens a serial port, captures all output to a timestamped log file,
and waits for a configurable done marker or timeout.
"""

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime
from pathlib import Path


DEFAULT_DONE_MARKER = "<<<DONE>>>"
DEFAULT_TIMEOUT = 600
DEFAULT_BAUD = 115200


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Monitor serial output from an STM32MP135 target."
    )
    parser.add_argument(
        "port",
        help="COM port to monitor, e.g. COM4",
    )
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Root directory for the logs/ output directory (default: cwd)",
    )
    parser.add_argument(
        "--done-marker",
        default=DEFAULT_DONE_MARKER,
        help=f"String that signals completion (default: {DEFAULT_DONE_MARKER})",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT,
        help=f"Seconds to wait before giving up (default: {DEFAULT_TIMEOUT})",
    )
    parser.add_argument(
        "--baud",
        type=int,
        default=DEFAULT_BAUD,
        help=f"Serial baud rate (default: {DEFAULT_BAUD})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print resolved configuration and exit without opening serial port",
    )
    return parser.parse_args()


def check_dependencies() -> None:
    """Check that pyserial is available."""
    try:
        import serial  # noqa: F401
    except ImportError:
        print("pyserial not found. Run: pip install pyserial")
        sys.exit(1)


def main() -> int:
    # Platform guard
    if sys.platform != "win32":
        print("monitor-uart.py is only supported on Windows")
        return 1

    check_dependencies()
    import serial

    args = parse_args()
    args.port = args.port.upper()

    repo_root = Path(args.repo_root).resolve()
    log_dir = repo_root / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = log_dir / f"{timestamp}_{args.port}.log"

    print(f"Port         : {args.port}")
    print(f"Baud         : {args.baud}")
    print(f"Done marker  : {args.done_marker}")
    print(f"Timeout      : {args.timeout}s")
    print(f"Log file     : {log_path}")

    if args.dry_run:
        return 0

    deadline = time.monotonic() + args.timeout
    marker_found = False
    marker_window = ""

    try:
        with log_path.open("w", encoding="utf-8", newline="") as log_file:
            with serial.Serial() as uart:
                uart.port = args.port
                uart.baudrate = args.baud
                uart.timeout = 0.2
                uart.rtscts = False
                uart.dsrdtr = False
                uart.open()

                print(f"Monitoring {args.port}... (Ctrl+C to stop)")
                print("-" * 60)

                while time.monotonic() < deadline:
                    chunk = uart.read(4096)
                    if chunk:
                        text = chunk.decode("utf-8", errors="replace")
                        print(text, end="", flush=True)
                        log_file.write(text)
                        log_file.flush()
                        marker_window = (marker_window + text)[-max(len(args.done_marker) * 2, 256):]
                        if args.done_marker in marker_window:
                            marker_found = True
                            print(f"\nDone marker '{args.done_marker}' detected.")
                            break

    except KeyboardInterrupt:
        print("\nMonitor interrupted by user.")
        return 130
    except serial.SerialException as exc:
        print(f"Error: failed to read UART output from {args.port}: {exc}")
        return 1

    if marker_found:
        print(f"Output saved to {log_path}")
        return 0
    else:
        print(f"Timeout reached after {args.timeout:.0f}s. Done marker not found.")
        print(f"Partial output saved to {log_path}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
