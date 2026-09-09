#!/usr/bin/env python3
"""Reset the target board. The reset method comes from config.yaml:

  - "gpio":     external script — Raspberry Pi Debug Probe, two-step
                low → delay → high via gpio_control.py. MUST be two steps:
                a single open-drain "reset" pulse does not reach nRESET
                on some boards (GK_V10_MP13X verified).
  - "uart_rts": toggle the serial RTS line (release → assert → release)
                to hardware-reset the board, for targets where RTS is
                wired to nRESET. DTR is left untouched (SIP board: must
                stay low).

Config lookup order:
  1. --config <path>
  2. ./config.yaml          (project root, when running from the project)
  3. <script-dir>/config.yaml

Example config.yaml (see config.yaml in the scripts dir for full comments):
  reset:
    method: gpio               # "gpio" | "uart_rts"
    gpio:
      pin: 6                   # debugprobe GPIO pin driving nRESET
      assert_ms: 200           # low pulse duration
    uart_rts:
      port: COM18              # serial port to toggle RTS on
      baud: 115200             # any baud works for a reset pulse
      dtr: false               # keep DTR untouched (false on SIP board)
      active: true             # True = RTS asserted = reset held
      assert_ms: 100           # RTS asserted duration
      settle_ms: 300           # wait after release
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
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


def load_reset_config(path: Path) -> dict:
    if not path.is_file():
        sys.exit(f"Error: config file not found: {path}")
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        sys.exit(f"Error: invalid YAML in {path}: {e}")
    cfg = data.get("reset")
    if not isinstance(cfg, dict):
        sys.exit(f"Error: missing 'reset' section in {path}")
    method = str(cfg.get("method", "gpio")).lower()
    if method not in ("gpio", "uart_rts"):
        sys.exit(f"Error: reset.method must be 'gpio' or 'uart_rts', got: {cfg.get('method')}")
    cfg["method"] = method
    return cfg


def reset_via_gpio(cfg: dict, dry_run: bool) -> None:
    gpio = cfg.get("gpio") or {}
    pin = int(gpio.get("pin", 6))
    assert_ms = int(gpio.get("assert_ms", 200))
    gpio_script = script_dir() / "gpio_control.py"

    print(f"Reset via GPIO{pin} (external script): low ({assert_ms}ms) -> high")
    if dry_run:
        return

    subprocess.run(
        [sys.executable, str(gpio_script), str(pin), "low"], check=True,
        capture_output=False,
    )
    time.sleep(assert_ms / 1000.0)
    subprocess.run(
        [sys.executable, str(gpio_script), str(pin), "high"], check=True,
        capture_output=False,
    )


def reset_via_uart_rts(cfg: dict, dry_run: bool) -> None:
    urts = cfg.get("uart_rts") or {}
    port = str(urts.get("port", "COM1")).upper()
    baud = int(urts.get("baud", 115200))
    dtr = bool(urts.get("dtr", False))       # SIP board: must stay False
    active = bool(urts.get("active", True))  # True = RTS asserted = reset
    assert_ms = int(urts.get("assert_ms", 100))
    settle_ms = int(urts.get("settle_ms", 300))
    release = not active

    print(f"Reset via UART RTS: {port} @ {baud} baud "
          f"(dtr={dtr}, rts active={active}, assert {assert_ms}ms, settle {settle_ms}ms)")
    if dry_run:
        return

    try:
        uart = serial.Serial()
        uart.port = port
        uart.baudrate = baud
        uart.timeout = 1
        uart.rtscts = False
        uart.dsrdtr = False
        uart.dtr = dtr
        uart.rts = release
        uart.open()
        # Re-assert after open — some drivers reset the lines on open.
        uart.dtr = dtr
        uart.rts = release
        time.sleep(0.05)
        uart.rts = active                    # assert reset
        time.sleep(assert_ms / 1000.0)
        uart.rts = release                   # release reset
        time.sleep(settle_ms / 1000.0)
        uart.close()
    except serial.SerialException as e:
        sys.exit(f"Error: failed to reset via RTS on {port}: {e}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Reset the target board. Method comes from config.yaml.",
    )
    parser.add_argument("--config", help="Path to config.yaml (default: ./config.yaml, then script dir)")
    parser.add_argument("--dry-run", action="store_true", help="Print what would happen and exit")
    args = parser.parse_args()

    cfg_path = find_config(args.config)
    cfg = load_reset_config(cfg_path)

    print(f"Config : {cfg_path}")
    if cfg["method"] == "gpio":
        reset_via_gpio(cfg, args.dry_run)
    else:
        reset_via_uart_rts(cfg, args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
