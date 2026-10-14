#!/usr/bin/env python3
"""Flash an STM32MP135 .stm32 image via STM32_Programmer_CLI (Windows only).

All connection settings (interface, port, baud, DTR, RTS) come from a YAML
config file — never from command-line device parameters. Config lookup order:

  1. --config <path>
  2. ./config.yaml          (project root, when running from the project)
  3. <script-dir>/config.yaml

Example config.yaml (see config.yaml in the scripts dir for full comments):
  flash:
    interface: serial      # "serial" | "usb"
    serial:
      port: COM18          # UART port for flashing
      baud: 921600         # programmer baud rate
      dtr: true            # pass dtr=high to the CLI
      rts: true            # pass rts=high to the CLI
    usb:
      port: USB1           # STM32_Programmer_CLI USB port
    partition_id: "0x01"
    start_after_flash: true
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("Error: PyYAML not installed. Run: pip install pyyaml")

CONFIG_NAME = "config.yaml"
DEFAULT_PARTITION_ID = "0x01"


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


def load_flash_config(path: Path) -> dict:
    if not path.is_file():
        sys.exit(f"Error: config file not found: {path}")
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        sys.exit(f"Error: invalid YAML in {path}: {e}")
    cfg = data.get("flash")
    if not isinstance(cfg, dict):
        sys.exit(f"Error: missing 'flash' section in {path}")
    interface = str(cfg.get("interface", "serial")).lower()
    if interface not in ("usb", "serial"):
        sys.exit(f"Error: flash.interface must be 'usb' or 'serial', got: {cfg.get('interface')}")
    cfg["interface"] = interface
    return cfg


def build_connection_string(cfg: dict) -> str:
    """Build the STM32_Programmer_CLI connection string from config."""
    if cfg["interface"] == "usb":
        usb = cfg.get("usb") or {}
        return f"port={usb.get('port', 'USB1')}"

    serial = cfg.get("serial") or {}
    conn = f"port={serial.get('port', 'COM1')} br={serial.get('baud', 921600)}"
    if serial.get("dtr"):
        conn += " dtr=high"
    if serial.get("rts"):
        conn += " rts=high"
    return conn


def resolve_programmer_cli() -> str:
    for candidate in ("STM32_Programmer_CLI.exe", "STM32_Programmer_CLI"):
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
    sys.exit("Error: STM32_Programmer_CLI.exe not found on PATH.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Flash an STM32MP135 .stm32 image. Connection settings come from config.yaml.",
        epilog="Example:\n"
               "  python scripts/flash.py --image Application/Debug/my_project.stm32\n"
               "  python scripts/flash.py --image build/fw.stm32 --no-start --dry-run",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--image", required=True, help="Path to the .stm32 image (relative to cwd)")
    parser.add_argument("--config", help="Path to config.yaml (default: ./config.yaml, then script dir)")
    parser.add_argument("--no-start", action="store_true", help="Flash only, do not start the target")
    parser.add_argument("--dry-run", action="store_true", help="Print the command and exit")
    args = parser.parse_args()

    cfg_path = find_config(args.config)
    cfg = load_flash_config(cfg_path)

    image = Path(args.image)
    if not image.is_file():
        sys.exit(f"Error: image file not found: {image.resolve()}")
    staging = Path.cwd() / "test.stm32"

    conn = build_connection_string(cfg)
    partition_id = str(cfg.get("partition_id", DEFAULT_PARTITION_ID))

    command = [
        resolve_programmer_cli() if not args.dry_run else "STM32_Programmer_CLI.exe",
        "-c", conn,
        "-d", str(staging), partition_id,
    ]
    if cfg.get("start_after_flash", True) and not args.no_start:
        command += ["-g", partition_id]

    print(f"Config     : {cfg_path}")
    print(f"Interface  : {cfg['interface']}")
    print(f"Connection : {conn}")
    print(f"Image      : {image.resolve()}")
    print(f"Staging    : {staging}")
    print(f"Command    : {' '.join(command)}")

    if args.dry_run:
        return 0

    shutil.copyfile(image, staging)
    print("Flashing...")
    try:
        completed = subprocess.run(command, check=False)
    except OSError as e:
        sys.exit(f"Error: failed to start STM32_Programmer_CLI: {e}")
    if completed.returncode != 0:
        sys.exit(f"Error: flash failed (exit {completed.returncode})")

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
