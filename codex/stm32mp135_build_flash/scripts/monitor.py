#!/usr/bin/env python3
"""Serial monitor — read UART output, print to console, save to log file.

Connection settings (port, baud, DTR, RTS) come from a YAML config file —
never from command-line device parameters. Config lookup order:

  1. --config <path>
  2. ./config.yaml          (project root, when running from the project)
  3. <script-dir>/config.yaml

Example config.yaml (see config.yaml in the scripts dir for full comments):
  monitor:
    port: COM18            # COM port to monitor
    baud: 115200           # baud rate
    dtr: true              # assert DTR (required on GK board; keep false on SIP board)
    rts: true              # assert RTS
    timeout: 30            # seconds, 0 = forever
    log_dir: logs          # log directory relative to cwd
"""

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import serial
except ImportError:
    sys.exit("Error: pyserial not installed. Run: pip install pyserial")

try:
    import yaml
except ImportError:
    sys.exit("Error: PyYAML not installed. Run: pip install pyyaml")

CONFIG_NAME = "config.yaml"


def script_dir() -> Path:
    return Path(__file__).resolve().parent


def find_config(explicit: str | None) -> Path:
    """Locate the config file: explicit path → cwd → script directory."""
    if explicit:
        return Path(explicit)
    cwd_cfg = Path.cwd() / CONFIG_NAME
    if cwd_cfg.is_file():
        return cwd_cfg
    return script_dir() / CONFIG_NAME


def load_monitor_config(path: Path) -> dict:
    if not path.is_file():
        sys.exit(f"Error: config file not found: {path}")
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        sys.exit(f"Error: invalid YAML in {path}: {e}")
    cfg = data.get("monitor")
    if not isinstance(cfg, dict):
        sys.exit(f"Error: missing 'monitor' section in {path}")
    if not cfg.get("port"):
        sys.exit(f"Error: monitor.port is required in {path}")
    return cfg


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Monitor STM32 UART output. Connection settings come from config.yaml.",
    )
    parser.add_argument("--config", help="Path to config.yaml (default: ./config.yaml, then script dir)")
    parser.add_argument("-t", "--timeout", type=float, default=None,
                        help="Monitor timeout in seconds, 0=forever (default: from config)")
    parser.add_argument("-o", "--logdir", default=None,
                        help="Log directory (default: from config)")
    args = parser.parse_args()

    cfg_path = find_config(args.config)
    cfg = load_monitor_config(cfg_path)

    port = str(cfg["port"]).upper()
    baud = int(cfg.get("baud", 115200))
    dtr = bool(cfg.get("dtr", True))
    rts = bool(cfg.get("rts", True))
    timeout = args.timeout if args.timeout is not None else float(cfg.get("timeout", 30))
    log_dir = Path(args.logdir) if args.logdir else Path(cfg.get("log_dir", "logs"))
    log_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = log_dir / f"uart_{timestamp}.log"

    deadline = None if timeout <= 0 else (time.monotonic() + timeout)

    print(f"Config : {cfg_path}")
    print(f"Monitor: {port} @ {baud} baud (dtr={dtr}, rts={rts})")
    if deadline:
        print(f"Timeout: {timeout:g}s")
    print(f"Log    : {log_path}")
    print("---")

    try:
        uart = serial.Serial()
        uart.port = port
        uart.baudrate = baud
        uart.timeout = 0.5
        uart.dtr = dtr
        uart.rts = rts
        uart.open()
        # Some drivers reset DTR/RTS on open; re-assert to honor config.
        uart.dtr = dtr
        uart.rts = rts

        with log_path.open("w", encoding="utf-8", newline="") as log_file:
            while deadline is None or time.monotonic() < deadline:
                chunk = uart.read(4096)
                if chunk:
                    text = chunk.decode("utf-8", errors="replace")
                    print(text, end="", flush=True)
                    log_file.write(text)
                    log_file.flush()

        uart.close()
    except serial.SerialException as e:
        sys.exit(f"Error: {e}")
    except KeyboardInterrupt:
        print("\nInterrupted.")
        uart.close()

    print("\nDone.")


if __name__ == "__main__":
    main()
